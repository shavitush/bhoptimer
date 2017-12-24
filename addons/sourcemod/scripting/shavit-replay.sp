/*
 * shavit's Timer - Replay Bot
 * by: shavit
 *
 * This file is part of shavit's Timer.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
*/

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <shavit>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#include <tf2>

#define REPLAY_FORMAT_V2 "{SHAVITREPLAYFORMAT}{V2}"
#define REPLAY_FORMAT_FINAL "{SHAVITREPLAYFORMAT}{FINAL}"
#define REPLAY_FORMAT_SUBVERSION 0x01 // for compatibility, if i ever update this code again
#define CELLS_PER_FRAME 6 // origin[3], angles[2], buttons

// #define DEBUG

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

enum
{
	iCentralClient,
	iCentralStyle,
	iCentralReplayStatus,
	iCentralTrack,
	CENTRALBOTCACHE_SIZE
};

enum
{
	sReplayClanTag,
	sReplayNameStyle,
	sReplayCentralName,
	sReplayCentralStyle,
	sReplayCentralStyleTag,
	sReplayUnloaded,
	REPLAYSTRINGS_SIZE
};

// game type
EngineVersion gEV_Type = Engine_Unknown;

// cache
int gI_ReplayTick[STYLE_LIMIT];
int gI_ReplayBotClient[STYLE_LIMIT];
ArrayList gA_Frames[STYLE_LIMIT][TRACKS_SIZE];
float gF_StartTick[STYLE_LIMIT];
ReplayStatus gRS_ReplayStatus[STYLE_LIMIT];
any gA_FrameCache[STYLE_LIMIT][TRACKS_SIZE][3]; // int frame_count, float time, bool new_format
char gS_ReplayNames[STYLE_LIMIT][TRACKS_SIZE][MAX_NAME_LENGTH];
bool gB_ForciblyStopped = false;

bool gB_Button[MAXPLAYERS+1];
int gI_PlayerFrames[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];
bool gB_Record[MAXPLAYERS+1];
int gI_Track[MAXPLAYERS+1];

bool gB_Late = false;
int gI_DefaultTeamSlots = 0;

// server specific
float gF_Tickrate = 0.0;
char gS_Map[192];
int gI_ExpectedBots = 0;
ConVar bot_quota = null;
any gA_CentralCache[CENTRALBOTCACHE_SIZE];

// how do i call this
bool gB_HideNameChange = false;
bool gB_DontCallTimer = false;

// plugin cvars
ConVar gCV_Enabled = null;
ConVar gCV_ReplayDelay = null;
ConVar gCV_TimeLimit = null;
ConVar gCV_DefaultTeam = null;
ConVar gCV_CentralBot = null;

// cached cvars
bool gB_Enabled = true;
float gF_ReplayDelay = 5.0;
float gF_TimeLimit = 5400.0;
int gI_DefaultTeam = 3;
bool gB_CentralBot = true;

// timer settings
int gI_Styles = 0;
char gS_StyleStrings[STYLE_LIMIT][STYLESTRINGS_SIZE][128];
any gA_StyleSettings[STYLE_LIMIT][STYLESETTINGS_SIZE];

// chat settings
char gS_ChatStrings[CHATSETTINGS_SIZE][128];

// replay settings
char gS_ReplayStrings[REPLAYSTRINGS_SIZE][MAX_NAME_LENGTH];

// database related things
Database gH_SQL = null;
char gS_MySQLPrefix[32];

public Plugin myinfo =
{
	name = "[shavit] Replay Bot",
	author = "shavit",
	description = "A replay bot for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetReplayBotCurrentFrame", Native_GetReplayBotIndex);
	CreateNative("Shavit_GetReplayBotFirstFrame", Native_GetReplayBotFirstFrame);
	CreateNative("Shavit_GetReplayBotIndex", Native_GetReplayBotIndex);
	CreateNative("Shavit_GetReplayBotStyle", Native_GetReplayBotStyle);
	CreateNative("Shavit_GetReplayBotTrack", Native_GetReplayBotTrack);
	CreateNative("Shavit_GetReplayData", Native_GetReplayData);
	CreateNative("Shavit_GetReplayFrameCount", Native_GetReplayFrameCount);
	CreateNative("Shavit_GetReplayLength", Native_GetReplayLength);
	CreateNative("Shavit_GetReplayName", Native_GetReplayName);
	CreateNative("Shavit_GetReplayTime", Native_GetReplayTime);
	CreateNative("Shavit_IsReplayDataLoaded", Native_IsReplayDataLoaded);
	CreateNative("Shavit_ReloadReplay", Native_ReloadReplay);
	CreateNative("Shavit_ReloadReplays", Native_ReloadReplays);
	CreateNative("Shavit_SetReplayData", Native_SetReplayData);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-replay");

	gB_Late = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	if(!LibraryExists("shavit-wr"))
	{
		SetFailState("shavit-wr is required for the plugin to work.");
	}

	if(gH_SQL == null)
	{
		Shavit_OnDatabaseLoaded();
	}
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-replay.phrases");

	// game specific
	gEV_Type = GetEngineVersion();
	gF_Tickrate = (1.0 / GetTickInterval());

	// late load
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && !IsFakeClient(i))
		{
			OnClientPutInServer(i);
		}
	}

	// plugin convars
	gCV_Enabled = CreateConVar("shavit_replay_enabled", "1", "Enable replay bot functionality?", 0, true, 0.0, true, 1.0);
	gCV_ReplayDelay = CreateConVar("shavit_replay_delay", "5.0", "Time to wait before restarting the replay after it finishes playing.", 0, true, 0.0, true, 10.0);
	gCV_TimeLimit = CreateConVar("shavit_replay_timelimit", "5400.0", "Maximum amount of time (in seconds) to allow saving to disk.\nDefault is 5400.0 (1:30 hours)\n0 - Disabled");
	gCV_DefaultTeam = CreateConVar("shavit_replay_defaultteam", "3", "Default team to make the bots join, if possible.\n2 - Terrorists/RED\n3 - Counter Terrorists/BLU", 0, true, 2.0, true, 3.0);
	gCV_CentralBot = CreateConVar("shavit_replay_centralbot", "1", "Have one central bot instead of one bot per replay.\nTriggered with !replay.\nRestart the map for changes to take effect.\nThe disabled setting is not supported - use at your own risk.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);

	gCV_Enabled.AddChangeHook(OnConVarChanged);
	gCV_ReplayDelay.AddChangeHook(OnConVarChanged);
	gCV_TimeLimit.AddChangeHook(OnConVarChanged);
	gCV_DefaultTeam.AddChangeHook(OnConVarChanged);
	gCV_CentralBot.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	// hooks
	HookEvent("player_spawn", Player_Event, EventHookMode_Pre);
	HookEvent("player_death", Player_Event, EventHookMode_Pre);
	HookEvent("player_connect", BotEvents, EventHookMode_Pre);
	HookEvent("player_disconnect", BotEvents, EventHookMode_Pre);
	HookEventEx("player_connect_client", BotEvents, EventHookMode_Pre);
	HookEvent("round_start", Round_Start);

	// name change suppression
	HookUserMessage(GetUserMessageId("SayText2"), Hook_SayText2, true);

	// commands
	RegAdminCmd("sm_deletereplay", Command_DeleteReplay, ADMFLAG_RCON, "Open replay deletion menu.");
	RegConsoleCmd("sm_replay", Command_Replay, "Opens the central bot menu. For admins: 'sm_replay stop' to stop the playback.");

	// database
	SQL_SetPrefix();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gB_Enabled = gCV_Enabled.BoolValue;
	gF_ReplayDelay = gCV_ReplayDelay.FloatValue;
	gF_TimeLimit = gCV_TimeLimit.FloatValue;
	gI_DefaultTeam = gCV_DefaultTeam.IntValue;
	gB_CentralBot = gCV_CentralBot.BoolValue;

	if(convar == gCV_CentralBot)
	{
		OnMapStart();
	}
}

public int Native_GetReplayBotFirstFrame(Handle handler, int numParams)
{
	SetNativeCellRef(2, gF_StartTick[GetNativeCell(1)]);
}

public int Native_GetReplayBotCurrentFrame(Handle handler, int numParams)
{
	return gI_ReplayTick[GetNativeCell(1)];
}

public int Native_GetReplayBotIndex(Handle handler, int numParams)
{
	return gI_ReplayBotClient[GetNativeCell(1)];
}

public int Native_IsReplayDataLoaded(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);

	if(gB_CentralBot)
	{
		return (gA_CentralCache[iCentralClient] != -1 && gA_CentralCache[iCentralClient] != Replay_Idle && view_as<int>(gA_FrameCache[style][track][0]) > 0);
	}

	return view_as<int>(ReplayEnabled(style) && gA_FrameCache[style][Track_Main][0] > 0);
}

public int Native_ReloadReplay(Handle handler, int numParams)
{
	int style = GetNativeCell(1);

	gI_ReplayTick[style] = -1;
	gF_StartTick[style] = -65535.0;
	gRS_ReplayStatus[style] = Replay_Idle;

	int track = GetNativeCell(2);
	bool restart = view_as<bool>(GetNativeCell(3));

	char[] path = new char[PLATFORM_MAX_PATH];
	GetNativeString(4, path, PLATFORM_MAX_PATH);

	delete gA_Frames[style][track];
	gA_Frames[style][track] = new ArrayList(CELLS_PER_FRAME);
	gA_FrameCache[style][track][0] = 0;
	gA_FrameCache[style][track][1] = 0.0;
	gA_FrameCache[style][track][2] = false;
	strcopy(gS_ReplayNames[style][track], MAX_NAME_LENGTH, "invalid");

	bool loaded = false;

	if(strlen(path) > 0)
	{
		loaded = LoadReplay(style, track, path);
	}

	else
	{
		loaded = DefaultLoadReplay(style, track);
	}

	if(gB_CentralBot)
	{
		if(gA_CentralCache[iCentralStyle] == style && gA_CentralCache[iCentralTrack] == track)
		{
			StopCentralReplay(0);
		}
	}

	else
	{
		if(gI_ReplayBotClient[style] == 0)
		{
			ServerCommand((gEV_Type != Engine_TF2)? "bot_add":"tf_bot_add");
			gI_ExpectedBots++;
		}

		if(loaded && restart)
		{
			gI_ReplayTick[style] = 0;
			gRS_ReplayStatus[style] = Replay_Start;
			CreateTimer((gF_ReplayDelay / 2.0), Timer_StartReplay, style, TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	return loaded;
}

public int Native_ReloadReplays(Handle handler, int numParams)
{
	bool restart = view_as<bool>(GetNativeCell(1));
	int loaded = 0;

	for(int i = 0; i < gI_Styles; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		for(int j = 0; j < ((gB_CentralBot)? TRACKS_SIZE:1); j++)
		{
			if(Shavit_ReloadReplay(i, j, restart))
			{
				loaded++;
			}
		}
	}

	return loaded;
}

public int Native_SetReplayData(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	ArrayList frames = view_as<ArrayList>(CloneHandle(GetNativeCell(2), handler));
	gA_PlayerFrames[client] = frames.Clone();
	delete frames;

	gI_PlayerFrames[client] = gA_PlayerFrames[client].Length;
}

public int Native_GetReplayData(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	ArrayList frames = null;

	if(gA_PlayerFrames[client] != null)
	{
		ArrayList temp = gA_PlayerFrames[client].Clone();
		frames = view_as<ArrayList>(CloneHandle(temp, handler));
		delete temp;
	}

	return view_as<int>(frames);
}

public int Native_GetReplayFrameCount(Handle handler, int numParams)
{
	return view_as<int>(gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)][0]);
}

public int Native_GetReplayLength(Handle handler, int numParams)
{
	return view_as<int>(GetReplayLength(GetNativeCell(1), GetNativeCell(2)));
}

public int Native_GetReplayName(Handle handler, int numParams)
{
	return SetNativeString(3, gS_ReplayNames[GetNativeCell(1)][GetNativeCell(2)], GetNativeCell(4));
}

public int Native_GetReplayTime(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);

	if(gB_CentralBot)
	{
		if(gA_CentralCache[iCentralReplayStatus] == Replay_End)
		{
			return view_as<int>(GetReplayLength(style, track));
		}
	}

	else if(gRS_ReplayStatus[style] == Replay_End)
	{
		return view_as<int>(GetReplayLength(Track_Main, track));
	}

	return view_as<int>(float(gI_ReplayTick[style]) / gF_Tickrate);
}

public int Native_GetReplayBotStyle(Handle handler, int numParams)
{
	return (gB_CentralBot && gA_CentralCache[iCentralReplayStatus] == Replay_Idle)? -1:GetReplayStyle(GetNativeCell(1));
}

public int Native_GetReplayBotTrack(Handle handler, int numParams)
{
	return GetReplayTrack(GetNativeCell(1));
}

public void Shavit_OnDatabaseLoaded()
{
	gH_SQL = Shavit_GetDatabase();
	SetSQLInfo();
}

public Action CheckForSQLInfo(Handle Timer)
{
	return SetSQLInfo();
}

Action SetSQLInfo()
{
	if(gH_SQL == null)
	{
		gH_SQL = Shavit_GetDatabase();

		CreateTimer(0.5, CheckForSQLInfo);
	}

	else
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void SQL_SetPrefix()
{
	char[] sFile = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-prefix.txt");

	File fFile = OpenFile(sFile, "r");

	if(fFile == null)
	{
		SetFailState("Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}
	
	char[] sLine = new char[PLATFORM_MAX_PATH*2];

	while(fFile.ReadLine(sLine, PLATFORM_MAX_PATH*2))
	{
		TrimString(sLine);
		strcopy(gS_MySQLPrefix, 32, sLine);

		break;
	}

	delete fFile;
}

public Action Cron(Handle Timer)
{
	if(!gB_Enabled)
	{
		bot_quota.IntValue = 0;

		return Plugin_Continue;
	}

	// make sure there are enough bots
	else if(bot_quota != null && bot_quota.IntValue != gI_ExpectedBots)
	{
		bot_quota.IntValue = gI_ExpectedBots;
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		for(int j = 0; j < ((gB_CentralBot)? TRACKS_SIZE:1); j++)
		{
			if(!gB_CentralBot && gI_ReplayBotClient[i] != 0)
			{
				UpdateReplayInfo(gI_ReplayBotClient[i], i, GetReplayLength(i, j), j);
			}
		}
	}

	if(gB_CentralBot && gA_CentralCache[iCentralClient] != -1)
	{
		if(gA_CentralCache[iCentralStyle] != -1)
		{
			UpdateReplayInfo(gA_CentralCache[iCentralClient], gA_CentralCache[iCentralStyle], -1.0, gA_CentralCache[iCentralTrack]);
		}

		else
		{
			UpdateReplayInfo(gA_CentralCache[iCentralClient], 0, 0.0, 0);
		}
	}

	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// trigger_once | trigger_multiple.. etc
	// func_door | func_door_rotating
	if(StrContains(classname, "trigger_") != -1 || StrContains(classname, "_door") != -1)
	{
		SDKHook(entity, SDKHook_StartTouch, HookTriggers);
		SDKHook(entity, SDKHook_EndTouch, HookTriggers);
		SDKHook(entity, SDKHook_Touch, HookTriggers);
	}
}

public Action HookTriggers(int entity, int other)
{
	if(other >= 1 && other <= MaxClients && IsFakeClient(other))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

bool LoadStyling()
{
	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-replay.cfg");

	KeyValues kv = new KeyValues("shavit-replay");
	
	if(!kv.ImportFromFile(sPath))
	{
		delete kv;

		return false;
	}

	kv.GetString("clantag", gS_ReplayStrings[sReplayClanTag], MAX_NAME_LENGTH, "<EMPTY CLANTAG>");
	kv.GetString("namestyle", gS_ReplayStrings[sReplayNameStyle], MAX_NAME_LENGTH, "<EMPTY NAMESTYLE>");
	kv.GetString("centralname", gS_ReplayStrings[sReplayCentralName], MAX_NAME_LENGTH, "<EMPTY CENTRALNAME>");
	kv.GetString("centralstyle", gS_ReplayStrings[sReplayCentralStyle], MAX_NAME_LENGTH, "<EMPTY CENTRALSTYLE>");
	kv.GetString("centralstyletag", gS_ReplayStrings[sReplayCentralStyleTag], MAX_NAME_LENGTH, "<EMPTY CENTRALSTYLETAG>");
	kv.GetString("unloaded", gS_ReplayStrings[sReplayUnloaded], MAX_NAME_LENGTH, "<EMPTY UNLOADED>");

	delete kv;

	return true;
}

public void OnMapStart()
{
	if(!LoadStyling())
	{
		SetFailState("Could not load the replay bots' configuration file. Make sure it exists (addons/sourcemod/configs/shavit-replay.cfg) and follows the proper syntax!");
	}

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
		Shavit_OnChatConfigLoaded();
	}

	gA_CentralCache[iCentralClient] = -1;
	gA_CentralCache[iCentralStyle] = -1;
	gA_CentralCache[iCentralReplayStatus] = Replay_Idle;
	gA_CentralCache[iCentralTrack] = Track_Main;

	gB_ForciblyStopped = false;

	GetCurrentMap(gS_Map, 192);
	GetMapDisplayName(gS_Map, gS_Map, 192);

	if(!gB_Enabled)
	{
		return;
	}

	bot_quota = FindConVar((gEV_Type != Engine_TF2)? "bot_quota":"tf_bot_quota");

	if(bot_quota != null)
	{
		bot_quota.Flags &= ~FCVAR_NOTIFY;
	}

	char[] sTempMap = new char[PLATFORM_MAX_PATH];
	FormatEx(sTempMap, PLATFORM_MAX_PATH, "maps/%s.nav", gS_Map);

	if(!FileExists(sTempMap))
	{
		if(!FileExists("maps/base.nav"))
		{
			SetFailState("Plugin startup FAILED: \"maps/base.nav\" does not exist.");
		}

		File_Copy("maps/base.nav", sTempMap);

		ForceChangeLevel(gS_Map, ".nav file generate");

		return;
	}

	ConVar bot_controllable = FindConVar("bot_controllable");

	if(bot_controllable != null)
	{
		bot_controllable.BoolValue = false;
		delete bot_controllable;
	}

	ConVar bot_stop = FindConVar("bot_stop");

	if(bot_stop != null)
	{
		bot_stop.BoolValue = true;
		delete bot_stop;
	}

	ConVar bot_quota_mode = FindConVar((gEV_Type != Engine_TF2)? "bot_quota_mode":"tf_bot_quota_mode");

	if(bot_quota_mode != null)
	{
		bot_quota_mode.SetString("normal");
		delete bot_quota_mode;
	}

	ConVar mp_limitteams = FindConVar("mp_limitteams");

	if(mp_limitteams != null)
	{
		mp_limitteams.IntValue = 0;
		delete mp_limitteams;
	}

	ConVar bot_join_after_player = FindConVar((gEV_Type != Engine_TF2)? "bot_join_after_player":"tf_bot_join_after_player");

	if(bot_join_after_player != null)
	{
		bot_join_after_player.BoolValue = false;
		delete bot_join_after_player;
	}

	ConVar bot_chatter = FindConVar("bot_chatter");

	if(bot_chatter != null)
	{
		bot_chatter.SetString("off");
		delete bot_chatter;
	}

	ConVar bot_zombie = FindConVar("bot_zombie");

	if(bot_zombie != null)
	{
		bot_zombie.BoolValue = true;
		delete bot_zombie;
	}

	ConVar mp_autoteambalance = FindConVar("mp_autoteambalance");
	mp_autoteambalance.BoolValue = false;
	delete mp_autoteambalance;

	ServerCommand((gEV_Type != Engine_TF2)? "bot_kick":"tf_bot_kick all");

	gI_ExpectedBots = 0;

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot");

	if(!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		gI_ReplayTick[i] = -1;
		gF_StartTick[i] = -65535.0;
		gRS_ReplayStatus[i] = Replay_Idle;

		if(!ReplayEnabled(i))
		{
			continue;
		}

		BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d", i);

		if(!DirExists(sPath))
		{
			CreateDirectory(sPath, 511);
		}

		bool loaded = false;

		for(int j = 0; j < ((gB_CentralBot)? TRACKS_SIZE:1); j++)
		{
			delete gA_Frames[i][j];
			gA_Frames[i][j] = new ArrayList(CELLS_PER_FRAME);
			gA_FrameCache[i][j][0] = 0;
			gA_FrameCache[i][j][1] = 0.0;
			gA_FrameCache[i][j][2] = false;
			strcopy(gS_ReplayNames[i][j], MAX_NAME_LENGTH, "invalid");

			loaded = DefaultLoadReplay(i, j);
		}

		if(!gB_CentralBot)
		{
			ServerCommand((gEV_Type != Engine_TF2)? "bot_add":"tf_bot_add");
			gI_ExpectedBots++;

			if(loaded)
			{
				gI_ReplayTick[i] = 0;
				gRS_ReplayStatus[i] = Replay_Start;
				CreateTimer((gF_ReplayDelay / 2.0), Timer_StartReplay, i, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}

	if(gB_CentralBot)
	{
		gI_ExpectedBots = 1;
		ServerCommand((gEV_Type != Engine_TF2)? "bot_add":"tf_bot_add");
	}

	CreateTimer(3.0, Cron, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleSettings(i, gA_StyleSettings[i]);
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i][sStyleName], 128);
		Shavit_GetStyleStrings(i, sShortName, gS_StyleStrings[i][sShortName], 128);
	}

	gI_Styles = styles;
}

public void Shavit_OnChatConfigLoaded()
{
	for(int i = 0; i < CHATSETTINGS_SIZE; i++)
	{
		Shavit_GetChatStrings(i, gS_ChatStrings[i], 128);
	}
}

bool DefaultLoadReplay(int style, int track)
{
	char[] sTrack = new char[4];
	FormatEx(sTrack, 4, "_%d", track);

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s%s.replay", style, gS_Map, (track > 0)? sTrack:"");

	return LoadReplay(style, track, sPath);
}

bool LoadReplay(int style, int track, const char[] path)
{
	if(FileExists(path))
	{
		File fFile = OpenFile(path, "rb");

		char[] sHeader = new char[64];

		if(!fFile.ReadLine(sHeader, 64))
		{
			return false;
		}

		TrimString(sHeader);
		char[][] sExplodedHeader = new char[2][64];
		ExplodeString(sHeader, ":", sExplodedHeader, 2, 64);

		if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_FINAL)) // hopefully, the last of them
		{
			// uncomment if ever needed
			// int iSubVersion = StringToInt(sExplodedHeader[0]);

			int iTemp = 0;
			fFile.ReadInt32(iTemp);
			gA_FrameCache[style][track][0] = iTemp;

			if(gA_Frames[style][track] == null)
			{
				gA_Frames[style][track] = new ArrayList(CELLS_PER_FRAME);
			}

			gA_Frames[style][track].Resize(iTemp);

			fFile.ReadInt32(iTemp);
			gA_FrameCache[style][track][1] = iTemp;

			char[] sAuthID = new char[32];
			fFile.ReadString(sAuthID, 32);

			if(gH_SQL != null)
			{
				char[] sQuery = new char[192];
				FormatEx(sQuery, 192, "SELECT name FROM %susers WHERE auth = '%s';", gS_MySQLPrefix, sAuthID);

				DataPack pack = new DataPack();
				pack.WriteCell(style);
				pack.WriteCell(track);

				gH_SQL.Query(SQL_GetUserName_Callback, sQuery, pack, DBPrio_High);
			}

			any[] aReplayData = new any[CELLS_PER_FRAME];

			for(int i = 0; i < gA_FrameCache[style][track][0]; i++)
			{
				if(fFile.Read(aReplayData, CELLS_PER_FRAME, 4) >= 0)
				{
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[0]), 0);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[1]), 1);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[2]), 2);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[3]), 3);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[4]), 4);
					gA_Frames[style][track].Set(i, view_as<int>(aReplayData[5]), 5);
				}
			}

			gA_FrameCache[style][track][2] = true; // not wr-based
		}

		else if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_V2))
		{
			int iReplaySize = gA_FrameCache[style][track][0] = StringToInt(sExplodedHeader[0]);
			gA_Frames[style][track].Resize(iReplaySize);

			gA_FrameCache[style][track][1] = 0.0; // N/A at this version

			any[] aReplayData = new any[6];

			for(int i = 0; i < iReplaySize; i++)
			{
				if(fFile.Read(aReplayData, 6, 4) >= 0)
				{
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[0]), 0);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[1]), 1);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[2]), 2);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[3]), 3);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[4]), 4);
					gA_Frames[style][track].Set(i, view_as<int>(aReplayData[5]), 5);
				}
			}

			gA_FrameCache[style][track][2] = false;
			strcopy(gS_ReplayNames[style][track], MAX_NAME_LENGTH, "invalid");
		}

		else // old, outdated and slow - only used for ancient replays
		{
			char[] sLine = new char[320];
			char[][] sExplodedLine = new char[6][64];

			for(int i = 0; !fFile.EndOfFile(); i++)
			{
				fFile.ReadLine(sLine, 320);
				int iStrings = ExplodeString(sLine, "|", sExplodedLine, 6, 64);

				gA_Frames[style][track].Resize(i + 1);
				gA_Frames[style][track].Set(i, StringToFloat(sExplodedLine[0]), 0);
				gA_Frames[style][track].Set(i, StringToFloat(sExplodedLine[1]), 1);
				gA_Frames[style][track].Set(i, StringToFloat(sExplodedLine[2]), 2);
				gA_Frames[style][track].Set(i, StringToFloat(sExplodedLine[3]), 3);
				gA_Frames[style][track].Set(i, StringToFloat(sExplodedLine[4]), 4);
				gA_Frames[style][track].Set(i, (iStrings == 6)? StringToInt(sExplodedLine[5]):0, 5);
			}

			gA_FrameCache[style][track][0] = gA_Frames[style][track].Length;
			gA_FrameCache[style][track][1] = 0.0; // N/A at this version
			gA_FrameCache[style][track][2] = false; // wr-based
			strcopy(gS_ReplayNames[style][track], MAX_NAME_LENGTH, "invalid");
		}

		delete fFile;

		return true;
	}

	return false;
}

bool SaveReplay(int style, int track, float time, char[] authid, char[] name)
{
	char[] sTrack = new char[4];
	FormatEx(sTrack, 4, "_%d", track);

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s%s.replay", style, gS_Map, (track > 0)? sTrack:"");

	if(FileExists(sPath))
	{
		DeleteFile(sPath);
	}

	File fFile = OpenFile(sPath, "wb");
	fFile.WriteLine("%d:" ... REPLAY_FORMAT_FINAL, REPLAY_FORMAT_SUBVERSION);

	int iSize = gA_Frames[style][track].Length;

	fFile.WriteInt32(iSize);
	fFile.WriteInt32(view_as<int>(time));
	fFile.WriteString(authid, true);

	// if REPLAY_FORMAT_SUBVERSION is over 0x01 i'll add variables here

	any[] aFrameData = new any[CELLS_PER_FRAME];

	for(int i = 0; i < iSize; i++)
	{
		gA_Frames[style][track].GetArray(i, aFrameData, CELLS_PER_FRAME);
		fFile.Write(aFrameData, CELLS_PER_FRAME, 4);
	}

	delete fFile;

	gA_FrameCache[style][track][0] = iSize;
	gA_FrameCache[style][track][1] = time;
	gA_FrameCache[style][track][2] = true;
	strcopy(gS_ReplayNames[style][track], MAX_NAME_LENGTH, name);

	return true;
}

bool DeleteReplay(int style, int track)
{
	char[] sTrack = new char[4];
	FormatEx(sTrack, 4, "_%d", track);

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s%s.replay", style, gS_Map, (track > 0)? sTrack:"");

	if(!FileExists(sPath) || !DeleteFile(sPath))
	{
		return false;
	}

	if(gB_CentralBot && gA_CentralCache[iCentralStyle] == style && gA_CentralCache[iCentralTrack] == track)
	{
		StopCentralReplay(0);
	}

	gA_Frames[style][track].Clear();
	gA_FrameCache[style][track][0] = 0;
	gA_FrameCache[style][track][1] = 0.0;
	gA_FrameCache[style][track][2] = false;
	strcopy(gS_ReplayNames[style][track], MAX_NAME_LENGTH, "invalid");
	gI_ReplayTick[style] = -1;

	if(gI_ReplayBotClient[style] != 0)
	{
		UpdateReplayInfo(gI_ReplayBotClient[style], style, 0.0, track);
	}

	return true;
}

public void SQL_GetUserName_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int style = data.ReadCell();
	int track = data.ReadCell();
	delete data;

	if(results == null)
	{
		LogError("Timer error! Get user name (replay) failed. Reason: %s", error);

		return;
	}

	if(results.FetchRow())
	{
		results.FetchString(0, gS_ReplayNames[style][track], MAX_NAME_LENGTH);
	}
}

public void OnClientPutInServer(int client)
{
	if(IsClientSourceTV(client))
	{
		return;
	}

	if(!IsFakeClient(client))
	{
		delete gA_PlayerFrames[client];
		gA_PlayerFrames[client] = new ArrayList(CELLS_PER_FRAME);
	}

	else
	{
		if(!gB_CentralBot)
		{
			for(int i = 0; i < gI_Styles; i++)
			{
				if(ReplayEnabled(i) && gI_ReplayBotClient[i] == 0)
				{
					gI_ReplayBotClient[i] = client;

					UpdateReplayInfo(client, i, -1.0, Track_Main);

					break;
				}
			}
		}

		else if(gA_CentralCache[iCentralClient] == -1)
		{
			UpdateReplayInfo(client, 0, 0.0, Track_Main);
			gA_CentralCache[iCentralClient] = client;
		}
	}
}

void FormatStyle(const char[] source, int style, bool central, float time, int track, char[] dest, int size)
{
	float fWRTime = GetReplayLength(style, track);

	char[] sTime = new char[16];
	FormatSeconds((time == -1.0)? fWRTime:time, sTime, 16);

	char[] sName = new char[MAX_NAME_LENGTH];
	GetReplayName(style, track, sName, MAX_NAME_LENGTH);
	
	char[] temp = new char[size];
	strcopy(temp, size, source);

	ReplaceString(temp, size, "{map}", gS_Map);

	if(central && gA_CentralCache[iCentralReplayStatus] == Replay_Idle)
	{
		ReplaceString(temp, size, "{style}", gS_ReplayStrings[sReplayCentralStyle]);
		ReplaceString(temp, size, "{styletag}", gS_ReplayStrings[sReplayCentralStyleTag]);
	}

	else
	{
		ReplaceString(temp, size, "{style}", gS_StyleStrings[style][sStyleName]);
		ReplaceString(temp, size, "{styletag}", gS_StyleStrings[style][sClanTag]);
	}
	
	ReplaceString(temp, size, "{time}", sTime);
	ReplaceString(temp, size, "{player}", sName);

	char[] sTrack = new char[32];
	GetTrackName(LANG_SERVER, track, sTrack, 32);
	ReplaceString(temp, size, "{track}", sTrack);

	strcopy(dest, size, temp);
}

void UpdateReplayInfo(int client, int style, float time, int track)
{
	if(!gB_Enabled || !IsValidClient(client) || !IsFakeClient(client))
	{
		return;
	}

	SetEntProp(client, Prop_Data, "m_CollisionGroup", 1);
	SetEntityMoveType(client, MOVETYPE_NOCLIP);

	bool central = (gA_CentralCache[iCentralClient] == client);
	bool idle = (central && gA_CentralCache[iCentralReplayStatus] == Replay_Idle);

	if(gEV_Type != Engine_TF2)
	{
		char[] sTag = new char[MAX_NAME_LENGTH];
		FormatStyle(gS_ReplayStrings[sReplayClanTag], style, central, time, track, sTag, MAX_NAME_LENGTH);
		CS_SetClientClanTag(client, sTag);
	}

	char[] sName = new char[MAX_NAME_LENGTH];
	int iFrameCount = view_as<int>(gA_FrameCache[style][track][0]);
	
	if(central || iFrameCount > 0)
	{
		FormatStyle(gS_ReplayStrings[(idle)? sReplayCentralName:sReplayNameStyle], style, central, time, track, sName, MAX_NAME_LENGTH);
	}

	else
	{
		FormatStyle(gS_ReplayStrings[sReplayUnloaded], style, central, time, track, sName, MAX_NAME_LENGTH);
	}

	gB_HideNameChange = true;
	SetClientName(client, sName);

	int iScore = (iFrameCount > 0 || client == gA_CentralCache[iCentralClient])? 2000:-2000;

	if(gEV_Type == Engine_CSGO)
	{
		CS_SetClientContributionScore(client, iScore);
	}

	else if(gEV_Type == Engine_CSS)
	{
		SetEntProp(client, Prop_Data, "m_iFrags", iScore);
	}

	SetEntProp(client, Prop_Data, "m_iDeaths", 0);

	gB_DontCallTimer = true;

	if(!gB_CentralBot && iFrameCount == 0)
	{
		if(IsPlayerAlive(client))
		{
			ForcePlayerSuicide(client);
		}
	}

	else
	{
		if(!IsPlayerAlive(client))
		{
			if(gEV_Type == Engine_TF2)
			{
				TF2_RespawnPlayer(client);
			}

			else
			{
				CS_RespawnPlayer(client);
			}
		}

		else
		{
			int iFlags = GetEntityFlags(client);

			if((iFlags & FL_ATCONTROLS) == 0)
			{
				SetEntityFlags(client, (iFlags|FL_ATCONTROLS));
			}
		}

		// Spectating is laggy if the player has no weapons
		if(gEV_Type != Engine_TF2 && GetPlayerWeaponSlot(client, CS_SLOT_KNIFE) == -1)
		{
			GivePlayerItem(client, "weapon_knife");
		}
	}

	if(gI_DefaultTeamSlots >= gI_Styles && GetClientTeam(client) != gI_DefaultTeam)
	{
		if(gEV_Type == Engine_TF2)
		{
			ChangeClientTeam(client, gI_DefaultTeam);
		}

		else
		{
			CS_SwitchTeam(client, gI_DefaultTeam);
		}
	}
}

public void OnClientDisconnect(int client)
{
	if(!IsFakeClient(client))
	{
		if(gA_PlayerFrames[client] != null)
		{
			delete gA_PlayerFrames[client];
		}

		return;
	}

	if(gA_CentralCache[iCentralClient] == client)
	{
		gA_CentralCache[iCentralClient] = -1;

		return;
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		if(client == gI_ReplayBotClient[i])
		{
			gI_ReplayBotClient[i] = 0;

			break;
		}
	}
}

public Action Shavit_OnStart(int client)
{
	ClearFrames(client);
	gB_Record[client] = true;

	return Plugin_Continue;
}

public void Shavit_OnStop(int client)
{
	ClearFrames(client);
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track)
{
	if(Shavit_IsPracticeMode(client))
	{
		return;
	}

	gB_Record[client] = false;

	float fWR = 0.0;
	Shavit_GetWRTime(style, fWR, track);

	if(!view_as<bool>(gA_FrameCache[style][track][2]))
	{
		if(view_as<int>(gA_FrameCache[style][track][0]) != 0 && gI_PlayerFrames[client] > gA_FrameCache[style][track][0])
		{
			return;
		}
	}

	else
	{
		float fReplayTime = view_as<float>(gA_FrameCache[style][track][1]);

		if(fReplayTime != 0.0 && time >= fReplayTime)
		{
			return;
		}
	}

	if(gI_PlayerFrames[client] == 0)
	{
		return;
	}

	if(!gB_Enabled || (gF_TimeLimit > 0.0 && time > gF_TimeLimit))
	{
		ClearFrames(client);

		return;
	}

	gA_Frames[style][track] = gA_PlayerFrames[client].Clone();

	char[] sAuthID = new char[32];
	GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

	char[] sName = new char[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);
	ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");

	SaveReplay(style, track, time, sAuthID, sName);

	if(ReplayEnabled(style))
	{
		if(gB_CentralBot && gA_CentralCache[iCentralStyle] == style && gA_CentralCache[iCentralTrack] == track)
		{
			StopCentralReplay(0);
		}

		else if(!gB_CentralBot && gI_ReplayBotClient[style] != 0)
		{
			UpdateReplayInfo(gI_ReplayBotClient[style], style, time, track);

			if(gEV_Type == Engine_TF2)
			{
				TF2_RespawnPlayer(gI_ReplayBotClient[style]);
			}

			else
			{
				CS_RespawnPlayer(gI_ReplayBotClient[style]);
			}

			gRS_ReplayStatus[style] = Replay_Running;
			gI_ReplayTick[style] = 0;

			float vecPosition[3];
			vecPosition[0] = gA_Frames[style][track].Get(0, 0);
			vecPosition[1] = gA_Frames[style][track].Get(0, 1);
			vecPosition[2] = gA_Frames[style][track].Get(0, 2);

			TeleportEntity(gI_ReplayBotClient[style], vecPosition, NULL_VECTOR, NULL_VECTOR);
		}
	}

	ClearFrames(client);
}

public void Shavit_OnPause(int client)
{
	gB_Record[client] = false;
}

public void Shavit_OnResume(int client)
{
	gB_Record[client] = true;
}

// OnPlayerRunCmd instead of Shavit_OnUserCmdPre because bots are also used here.
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
	if(!gB_Enabled)
	{
		return Plugin_Continue;
	}

	if(!IsPlayerAlive(client))
	{
		if((buttons & IN_USE) > 0)
		{
			if(!gB_Button[client] && GetSpectatorTarget(client) == gA_CentralCache[iCentralClient])
			{
				OpenReplayMenu(client);
			}

			gB_Button[client] = true;
		}

		else
		{
			gB_Button[client] = false;
		}

		return Plugin_Continue;
	}

	float vecCurrentPosition[3];
	GetClientAbsOrigin(client, vecCurrentPosition);

	int style = GetReplayStyle(client);
	int track = GetReplayTrack(client);

	if(style != -1 && ReplayEnabled(style))
	{
		buttons = 0;

		vel[0] = 0.0;
		vel[1] = 0.0;

		int iFrameCount = view_as<int>(gA_FrameCache[style][track][0]);

		if(gA_Frames[style][track] == null || iFrameCount <= 0) // if no replay is loaded
		{
			return Plugin_Changed;
		}

		if(gI_ReplayTick[style] != -1 && iFrameCount >= 1)
		{
			float vecPosition[3];
			float vecAngles[3];

			if(gRS_ReplayStatus[style] != Replay_Running)
			{
				bool bStart = (gRS_ReplayStatus[style] == Replay_Start);

				int iFrame = (bStart)? 0:(iFrameCount - 1);

				vecPosition[0] = gA_Frames[style][track].Get(iFrame, 0);
				vecPosition[1] = gA_Frames[style][track].Get(iFrame, 1);
				vecPosition[2] = gA_Frames[style][track].Get(iFrame, 2);

				vecAngles[0] = gA_Frames[style][track].Get(iFrame, 3);
				vecAngles[1] = gA_Frames[style][track].Get(iFrame, 4);
				
				if(bStart)
				{
					TeleportEntity(client, vecPosition, vecAngles, view_as<float>({0.0, 0.0, 0.0}));
				}

				else
				{
					float vecVelocity[3];
					MakeVectorFromPoints(vecCurrentPosition, vecPosition, vecVelocity);
					ScaleVector(vecVelocity, gF_Tickrate);
					TeleportEntity(client, NULL_VECTOR, vecAngles, vecVelocity);
				}

				return Plugin_Changed;
			}

			if(++gI_ReplayTick[style] >= iFrameCount)
			{
				gI_ReplayTick[style] = 0;
				gRS_ReplayStatus[style] = gA_CentralCache[iCentralReplayStatus] = Replay_End;

				CreateTimer((gF_ReplayDelay / 2.0), Timer_EndReplay, style, TIMER_FLAG_NO_MAPCHANGE);

				return Plugin_Changed;
			}

			if(gI_ReplayTick[style] == 1)
			{
				gF_StartTick[style] = GetEngineTime();
			}

			vecPosition[0] = gA_Frames[style][track].Get(gI_ReplayTick[style], 0);
			vecPosition[1] = gA_Frames[style][track].Get(gI_ReplayTick[style], 1);
			vecPosition[2] = gA_Frames[style][track].Get(gI_ReplayTick[style], 2);

			vecAngles[0] = gA_Frames[style][track].Get(gI_ReplayTick[style], 3);
			vecAngles[1] = gA_Frames[style][track].Get(gI_ReplayTick[style], 4);

			buttons = gA_Frames[style][track].Get(gI_ReplayTick[style], 5);

			float vecVelocity[3];
			MakeVectorFromPoints(vecCurrentPosition, vecPosition, vecVelocity);
			ScaleVector(vecVelocity, gF_Tickrate);

			if((gI_ReplayTick[style] % RoundToFloor(gF_Tickrate * 1.5)) == 0)
			{
				float vecLastPosition[3];
				vecLastPosition[0] = gA_Frames[style][track].Get(gI_ReplayTick[style] - 1, 0);
				vecLastPosition[1] = gA_Frames[style][track].Get(gI_ReplayTick[style] - 1, 1);
				vecLastPosition[2] = gA_Frames[style][track].Get(gI_ReplayTick[style] - 1, 2);

				#if defined DEBUG
				PrintToChatAll("vecVelocity: %.02f | dist %.02f", GetVectorLength(vecVelocity), GetVectorDistance(vecLastPosition, vecPosition) * gF_Tickrate);
				#endif

				if(GetVectorLength(vecVelocity) / (GetVectorDistance(vecLastPosition, vecPosition) * gF_Tickrate) > 2.0)
				{
					MakeVectorFromPoints(vecLastPosition, vecPosition, vecVelocity);
					ScaleVector(vecVelocity, gF_Tickrate);
					TeleportEntity(client, vecLastPosition, vecAngles, vecVelocity);

					return Plugin_Changed;
				}
			}

			TeleportEntity(client, NULL_VECTOR, vecAngles, vecVelocity);

			return Plugin_Changed;
		}
	}

	else if(gB_Record[client] && ReplayEnabled(Shavit_GetBhopStyle(client)) && Shavit_GetTimerStatus(client) == Timer_Running)
	{
		gA_PlayerFrames[client].Resize(gI_PlayerFrames[client] + 1);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[0], 0);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[1], 1);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[2], 2);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], angles[0], 3);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], angles[1], 4);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], buttons, 5);

		gI_PlayerFrames[client]++;
	}

	return Plugin_Continue;
}

public Action Timer_EndReplay(Handle Timer, any data)
{
	gB_ForciblyStopped = false;
	gI_ReplayTick[data] = 0;

	if(gI_ReplayBotClient[data] != gA_CentralCache[iCentralClient])
	{
		gRS_ReplayStatus[data] = Replay_Start;

		CreateTimer((gF_ReplayDelay / 2.0), Timer_StartReplay, data, TIMER_FLAG_NO_MAPCHANGE);
	}

	else
	{
		gRS_ReplayStatus[data] = gA_CentralCache[iCentralReplayStatus] = Replay_Idle;
		gI_ReplayBotClient[data] = 0;
	}

	return Plugin_Stop;
}

public Action Timer_StartReplay(Handle Timer, any data)
{
	if(gRS_ReplayStatus[data] == Replay_Running || (gB_CentralBot && gB_ForciblyStopped))
	{
		return Plugin_Stop;
	}

	gRS_ReplayStatus[data] = gA_CentralCache[iCentralReplayStatus] = Replay_Running;

	return Plugin_Stop;
}

bool ReplayEnabled(any style)
{
	return (!gA_StyleSettings[style][bUnranked] && !gA_StyleSettings[style][bNoReplay]);
}

public void Player_Event(Event event, const char[] name, bool dontBroadcast)
{
	if(!gB_Enabled)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsFakeClient(client))
	{
		event.BroadcastDisabled = true;

		if(!gB_DontCallTimer)
		{
			CreateTimer(0.10, DelayedUpdate, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}

		gB_DontCallTimer = false;
	}
}

public Action DelayedUpdate(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return Plugin_Stop;
	}

	UpdateReplayInfo(client, GetReplayStyle(client), -1.0, GetReplayTrack(client));

	return Plugin_Stop;
}

public void BotEvents(Event event, const char[] name, bool dontBroadcast)
{
	if(!gB_Enabled)
	{
		return;
	}

	if(event.GetBool("bot"))
	{
		event.BroadcastDisabled = true;

		int client = GetClientOfUserId(event.GetInt("userid"));

		if(IsValidClient(client))
		{
			int style = GetReplayStyle(client);

			if(style != -1)
			{
				UpdateReplayInfo(client, style, -1.0, GetReplayTrack(client));
			}
		}
	}
}

public void Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	gI_DefaultTeamSlots = 0;

	char[] sEntity = new char[32];

	if(gEV_Type == Engine_TF2)
	{
		strcopy(sEntity, 32, "info_player_teamspawn");
	}

	else
	{
		strcopy(sEntity, 32, (gI_DefaultTeam == 2)? "info_player_terrorist":"info_player_counterterrorist");
	}

	int iEntity = -1;

	while((iEntity = FindEntityByClassname(iEntity, sEntity)) != INVALID_ENT_REFERENCE)
	{
		gI_DefaultTeamSlots++;
	}
}

public Action Hook_SayText2(UserMsg msg_id, any msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if(!gB_HideNameChange || !gB_Enabled)
	{
		return Plugin_Continue;
	}

	char[] sMessage = new char[24];

	if(GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pbmsg = msg;
		pbmsg.ReadString("msg_name", sMessage, 24);
		delete pbmsg;
	}

	else
	{
		BfRead bfmsg = msg;
		bfmsg.ReadByte();
		bfmsg.ReadByte();
		bfmsg.ReadString(sMessage, 24, false);
		delete bfmsg;
	}

	if(StrEqual(sMessage, "#Cstrike_Name_Change") || StrEqual(sMessage, "#TF_Name_Change"))
	{
		gB_HideNameChange = false;

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void ClearFrames(int client)
{
	gA_PlayerFrames[client].Clear();
	gI_PlayerFrames[client] = 0;
}

public void Shavit_OnWRDeleted(int style, int id, int track)
{
	float time = 0.0;
	Shavit_GetWRTime(style, time, track);

	if(view_as<int>(gA_FrameCache[style][track][0]) > 0 && GetReplayLength(style, track) - gF_Tickrate <= time) // -0.1 to fix rounding issues
	{
		DeleteReplay(style, track);
	}
}

public Action Command_DeleteReplay(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(DeleteReplay_Callback);
	menu.SetTitle("%T", "DeleteReplayMenuTitle", client);

	for(int i = 0; i < gI_Styles; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			if(view_as<int>(gA_FrameCache[i][j][0]) == 0)
			{
				continue;
			}

			char[] sInfo = new char[8];
			FormatEx(sInfo, 8, "%d;%d", i, j);

			float time = GetReplayLength(i, j);

			char[] sTrack = new char[32];
			GetTrackName(client, j, sTrack, 32);

			char[] sDisplay = new char[64];

			if(time > 0.0)
			{
				char[] sTime = new char[32];
				FormatSeconds(time, sTime, 32, false);

				FormatEx(sDisplay, 64, "%s (%s) - %s", gS_StyleStrings[i][sStyleName], sTrack, sTime);
			}

			else
			{
				FormatEx(sDisplay, 64, "%s (%s)", gS_StyleStrings[i][sStyleName], sTrack);
			}

			menu.AddItem(sInfo, sDisplay);
		}
	}

	if(menu.ItemCount == 0)
	{
		char[] sMenuItem = new char[64];
		FormatEx(sMenuItem, 64, "%T", "ReplaysUnavailable", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);

	return Plugin_Handled;
}

public int DeleteReplay_Callback(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[8];
		menu.GetItem(param2, sInfo, 8);

		char[][] sExploded = new char[2][4];
		ExplodeString(sInfo, ";", sExploded, 2, 4);
		
		int style = StringToInt(sExploded[0]);

		if(style == -1)
		{
			return 0;
		}

		gI_Track[param1] = StringToInt(sExploded[1]);

		Menu submenu = new Menu(DeleteConfirmation_Callback);
		submenu.SetTitle("%T", "ReplayDeletionConfirmation", param1, gS_StyleStrings[style][sStyleName]);

		char[] sMenuItem = new char[64];

		for(int i = 1; i <= GetRandomInt(2, 4); i++)
		{
			FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", param1);
			submenu.AddItem("-1", sMenuItem);
		}

		FormatEx(sMenuItem, 64, "%T", "MenuResponseYes", param1);
		submenu.AddItem(sInfo, sMenuItem);

		for(int i = 1; i <= GetRandomInt(2, 4); i++)
		{
			FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", param1);
			submenu.AddItem("-1", sMenuItem);
		}

		submenu.ExitButton = true;
		submenu.Display(param1, 20);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int DeleteConfirmation_Callback(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[4];
		menu.GetItem(param2, sInfo, 4);
		int style = StringToInt(sInfo);

		if(DeleteReplay(style, gI_Track[param1]))
		{
			char[] sTrack = new char[32];
			GetTrackName(param1, gI_Track[param1], sTrack, 32);

			LogAction(param1, param1, "Deleted replay for %s on map %s. (Track: %s)", gS_StyleStrings[style][sStyleName], gS_Map, sTrack);

			Shavit_PrintToChat(param1, "%T (%s%s%s)", "ReplayDeleted", param1, gS_ChatStrings[sMessageStyle], gS_StyleStrings[style][sStyleName], gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], sTrack, gS_ChatStrings[sMessageText]);
		}

		else
		{
			Shavit_PrintToChat(param1, "%T", "ReplayDeleteFailure", param1, gS_ChatStrings[sMessageStyle], gS_StyleStrings[style][sStyleName], gS_ChatStrings[sMessageText]);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Replay(int client, int args)
{
	if(!IsValidClient(client) || !gB_CentralBot || gA_CentralCache[iCentralClient] == -1)
	{
		return Plugin_Handled;
	}

	if(GetClientTeam(client) != 1 || GetSpectatorTarget(client) != gA_CentralCache[iCentralClient])
	{
		Shavit_PrintToChat(client, "%T", "CentralReplaySpectator", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	if(CheckCommandAccess(client, "sm_deletereplay", ADMFLAG_RCON))
	{
		char[] arg = new char[8];
		GetCmdArg(1, arg, 8);

		if(StrEqual(arg, "stop"))
		{
			StopCentralReplay(client);

			return Plugin_Handled;
		}
	}

	return OpenReplayMenu(client);
}

Action OpenReplayMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Replay);
	menu.SetTitle("%T\n ", "CentralReplayTrack", client);

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		bool records = false;

		for(int j = 0; j < gI_Styles; j++)
		{
			if(view_as<int>(gA_FrameCache[j][i][0]) > 0)
			{
				records = true;

				continue;
			}
		}

		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		char[] sTrack = new char[32];
		GetTrackName(client, i, sTrack, 32);

		menu.AddItem(sInfo, sTrack, (records)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitButton = true;
	menu.Display(client, 60);

	return Plugin_Handled;
}

public int MenuHandler_Replay(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		// avoid an exploit
		if(param2 >= 0 && param2 < TRACKS_SIZE)
		{
			OpenReplaySubMenu(param1, param2);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenReplaySubMenu(int client, int track)
{
	gI_Track[client] = track;

	char[] sTrack = new char[32];
	GetTrackName(client, track, sTrack, 32);

	Menu menu = new Menu(MenuHandler_ReplaySubmenu);
	menu.SetTitle("%T (%s)\n ", "CentralReplayTitle", client, sTrack);

	if(CheckCommandAccess(client, "sm_deletereplay", ADMFLAG_RCON))
	{
		char[] sDisplay = new char[64];
		FormatEx(sDisplay, 64, "%T", "CentralReplayStop", client);

		menu.AddItem("stop", sDisplay, (gA_CentralCache[iCentralReplayStatus] != Replay_Idle)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		float time = GetReplayLength(i, track);

		char[] sDisplay = new char[64];

		if(time > 0.0)
		{
			char[] sTime = new char[32];
			FormatSeconds(time, sTime, 32, false);

			FormatEx(sDisplay, 64, "%s - %s", gS_StyleStrings[i][sStyleName], sTime);
		}

		else
		{
			strcopy(sDisplay, 64, gS_StyleStrings[i][sStyleName]);
		}

		menu.AddItem(sInfo, sDisplay, (view_as<int>(gA_FrameCache[i][track][0]) > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "ERROR");
	}

	else if(menu.ItemCount <= ((gEV_Type == Engine_CSS)? 8:7))
	{
		menu.Pagination = MENU_NO_PAGINATION;
	}

	menu.ExitBackButton = true;
	menu.Display(client, 60);
}

public int MenuHandler_ReplaySubmenu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		if(StrEqual(info, "stop"))
		{
			StopCentralReplay(param1);
			OpenReplaySubMenu(param1, gI_Track[param1]);

			return 0;
		}

		int style = StringToInt(info);

		if(style == -1 || !ReplayEnabled(style) || view_as<int>(gA_FrameCache[style][gI_Track[param1]][0]) == 0 || gA_CentralCache[iCentralClient] <= 0)
		{
			return 0;
		}

		if(gA_CentralCache[iCentralReplayStatus] != Replay_Idle)
		{
			Shavit_PrintToChat(param1, "%T", "CentralReplayPlaying", param1);

			OpenReplaySubMenu(param1, gI_Track[param1]);
		}

		else
		{
			gI_ReplayTick[style] = 0;
			gA_CentralCache[iCentralStyle] = style;
			gA_CentralCache[iCentralTrack] = gI_Track[param1];
			gI_ReplayBotClient[style] = gA_CentralCache[iCentralClient];
			gRS_ReplayStatus[style] = gA_CentralCache[iCentralReplayStatus] = Replay_Start;
			TeleportToStart(gA_CentralCache[iCentralClient], style, gI_Track[param1]);
			gB_ForciblyStopped = false;

			float time = GetReplayLength(gA_CentralCache[iCentralStyle], gI_Track[param1]);

			UpdateReplayInfo(gA_CentralCache[iCentralClient], style, time, gI_Track[param1]);

			CreateTimer((gF_ReplayDelay / 2.0), Timer_StartReplay, style, TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenReplayMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void TeleportToStart(int client, int style, int track)
{
	if(view_as<int>(gA_FrameCache[style][track][0]) == 0)
	{
		return;
	}

	float vecPosition[3];
	vecPosition[0] = gA_Frames[style][track].Get(0, 0);
	vecPosition[1] = gA_Frames[style][track].Get(0, 1);
	vecPosition[2] = gA_Frames[style][track].Get(0, 2);

	float vecAngles[3];
	vecAngles[0] = gA_Frames[style][track].Get(0, 3);
	vecAngles[1] = gA_Frames[style][track].Get(0, 4);

	TeleportEntity(client, vecPosition, vecAngles, view_as<float>({0.0, 0.0, 0.0}));
}

void StopCentralReplay(int client)
{
	if(client > 0)
	{
		Shavit_PrintToChat(client, "%T", "CentralReplayStopped", client);
	}

	int style = gA_CentralCache[iCentralStyle];

	gRS_ReplayStatus[style] = gA_CentralCache[iCentralReplayStatus] = Replay_Idle;
	gI_ReplayTick[style] = 0;
	gI_ReplayBotClient[style] = 0;
	gF_StartTick[style] = -65535.0;
	TeleportToStart(gA_CentralCache[iCentralClient], style, GetReplayTrack(gA_CentralCache[iCentralClient]));
	gA_CentralCache[iCentralStyle] = 0;
	gB_ForciblyStopped = true;

	UpdateReplayInfo(client, 0, 0.0, gA_CentralCache[iCentralTrack]);
}

int GetReplayStyle(int client)
{
	if(!IsFakeClient(client))
	{
		return -1;
	}

	if(gB_CentralBot)
	{
		if(gA_CentralCache[iCentralStyle] == -1)
		{
			return 0;
		}

		return gA_CentralCache[iCentralStyle];
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		if(gI_ReplayBotClient[i] == client)
		{
			return i;
		}
	}

	return -1;
}

int GetReplayTrack(int client)
{
	if(!IsFakeClient(client))
	{
		return -1;
	}

	return (gB_CentralBot)? gA_CentralCache[iCentralTrack]:Track_Main;
}

int GetSpectatorTarget(int client)
{
	int target = -1;

	if(IsClientObserver(client))
	{
		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		if(iObserverMode >= 3 && iObserverMode <= 5)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if(IsValidClient(iTarget, true))
			{
				target = iTarget;
			}
		}
	}

	return target;
}

void GetTrackName(int client, int track, char[] output, int size)
{
	if(track < 0 || track >= TRACKS_SIZE)
	{
		FormatEx(output, size, "%T", "Track_Unknown", client);

		return;
	}

	static char sTrack[16];
	FormatEx(sTrack, 16, "Track_%d", track);
	FormatEx(output, size, "%T", sTrack, client);
}

float GetReplayLength(int style, int track)
{
	if(view_as<bool>(gA_FrameCache[style][track][2]))
	{
		return view_as<float>(gA_FrameCache[style][track][1]);
	}

	float fWRTime = 0.0;
	Shavit_GetWRTime(style, fWRTime, track);

	return fWRTime;
}

void GetReplayName(int style, int track, char[] buffer, int length)
{
	if(view_as<bool>(gA_FrameCache[style][track][2]))
	{
		strcopy(buffer, length, gS_ReplayNames[style][track]);

		return;
	}

	Shavit_GetWRName(style, buffer, length, track);
}

/*
 * Copies file source to destination
 * Based on code of javalia:
 * http://forums.alliedmods.net/showthread.php?t=159895
 *
 * @param source		Input file
 * @param destination	Output file
 */
bool File_Copy(const char[] source, const char[] destination)
{
	File file_source = OpenFile(source, "rb");

	if(file_source == null)
	{
		return false;
	}

	File file_destination = OpenFile(destination, "wb");

	if(file_destination == null)
	{
		delete file_source;

		return false;
	}

	int[] buffer = new int[32];
	int cache = 0;

	while(!IsEndOfFile(file_source))
	{
		cache = ReadFile(file_source, buffer, 32, 1);

		file_destination.Write(buffer, cache, 1);
	}

	delete file_source;
	delete file_destination;

	return true;
}
