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
#include <adminmenu>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#include <tf2>

#define REPLAY_FORMAT_V2 "{SHAVITREPLAYFORMAT}{V2}"
#define REPLAY_FORMAT_FINAL "{SHAVITREPLAYFORMAT}{FINAL}"
#define REPLAY_FORMAT_SUBVERSION 0x02
#define CELLS_PER_FRAME 8 // origin[3], angles[2], buttons, flags, movetype
#define FRAMES_PER_WRITE 100 // amounts of frames to write per read/write call

// #define DEBUG

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 262144

enum struct centralbot_cache_t
{
	int iClient;
	int iStyle;
	ReplayStatus iReplayStatus;
	int iTrack;
};

enum struct replaystrings_t
{
	char sClanTag[MAX_NAME_LENGTH];
	char sNameStyle[MAX_NAME_LENGTH];
	char sCentralName[MAX_NAME_LENGTH];
	char sCentralStyle[MAX_NAME_LENGTH];
	char sCentralStyleTag[MAX_NAME_LENGTH];
	char sUnloaded[MAX_NAME_LENGTH];
};

enum struct framecache_t
{
	int iFrameCount;
	float fTime;
	bool bNewFormat;
	int iReplayVersion;
	char sReplayName[MAX_NAME_LENGTH];
};

enum
{
	iBotShooting_Attack1 = (1 << 0),
	iBotShooting_Attack2 = (1 << 1)
}

// game type
EngineVersion gEV_Type = Engine_Unknown;

// cache
char gS_ReplayFolder[PLATFORM_MAX_PATH];

int gI_ReplayTick[STYLE_LIMIT];
int gI_ReplayBotClient[STYLE_LIMIT];
ArrayList gA_Frames[STYLE_LIMIT][TRACKS_SIZE];
float gF_StartTick[STYLE_LIMIT];
ReplayStatus gRS_ReplayStatus[STYLE_LIMIT];
framecache_t gA_FrameCache[STYLE_LIMIT][TRACKS_SIZE];
bool gB_ForciblyStopped = false;

bool gB_Button[MAXPLAYERS+1];
int gI_PlayerFrames[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];
int gI_Track[MAXPLAYERS+1];

bool gB_Late = false;

// forwards
Handle gH_OnReplayStart = null;
Handle gH_OnReplayEnd = null;

// server specific
float gF_Tickrate = 0.0;
char gS_Map[160];
int gI_ExpectedBots = 0;
ConVar bot_quota = null;
centralbot_cache_t gA_CentralCache;

// how do i call this
bool gB_HideNameChange = false;
bool gB_DontCallTimer = false;
bool gB_HijackFrame[MAXPLAYERS+1];
float gF_HijackedAngles[MAXPLAYERS+1][2];

// plugin cvars
ConVar gCV_Enabled = null;
ConVar gCV_ReplayDelay = null;
ConVar gCV_TimeLimit = null;
ConVar gCV_DefaultTeam = null;
ConVar gCV_CentralBot = null;
ConVar gCV_BotShooting = null;
ConVar gCV_BotPlusUse = null;
ConVar gCV_BotWeapon = null;

// timer settings
int gI_Styles = 0;
stylestrings_t gS_StyleStrings[STYLE_LIMIT];
stylesettings_t gA_StyleSettings[STYLE_LIMIT];

// chat settings
chatstrings_t gS_ChatStrings;

// replay settings
replaystrings_t gS_ReplayStrings;

// admin menu
TopMenu gH_AdminMenu = null;
TopMenuObject gH_TimerCommands = INVALID_TOPMENUOBJECT;

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
	CreateNative("Shavit_GetReplayBotType", Native_GetReplayBotType);
	CreateNative("Shavit_GetReplayData", Native_GetReplayData);
	CreateNative("Shavit_GetReplayFrameCount", Native_GetReplayFrameCount);
	CreateNative("Shavit_GetReplayLength", Native_GetReplayLength);
	CreateNative("Shavit_GetReplayName", Native_GetReplayName);
	CreateNative("Shavit_GetReplayTime", Native_GetReplayTime);
	CreateNative("Shavit_HijackAngles", Native_HijackAngles);
	CreateNative("Shavit_IsReplayDataLoaded", Native_IsReplayDataLoaded);
	CreateNative("Shavit_ReloadReplay", Native_ReloadReplay);
	CreateNative("Shavit_ReloadReplays", Native_ReloadReplays);
	CreateNative("Shavit_Replay_DeleteMap", Native_Replay_DeleteMap);
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

	// forwards
	gH_OnReplayStart = CreateGlobalForward("Shavit_OnReplayStart", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnReplayEnd = CreateGlobalForward("Shavit_OnReplayEnd", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

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
	gCV_TimeLimit = CreateConVar("shavit_replay_timelimit", "7200.0", "Maximum amount of time (in seconds) to allow saving to disk.\nDefault is 7200 (2 hours)\n0 - Disabled");
	gCV_DefaultTeam = CreateConVar("shavit_replay_defaultteam", "3", "Default team to make the bots join, if possible.\n2 - Terrorists/RED\n3 - Counter Terrorists/BLU", 0, true, 2.0, true, 3.0);
	gCV_CentralBot = CreateConVar("shavit_replay_centralbot", "1", "Have one central bot instead of one bot per replay.\nTriggered with !replay.\nRestart the map for changes to take effect.\nThe disabled setting is not supported - use at your own risk.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_BotShooting = CreateConVar("shavit_replay_botshooting", "3", "Attacking buttons to allow for bots.\n0 - none\n1 - +attack\n2 - +attack2\n3 - both", 0, true, 0.0, true, 3.0);
	gCV_BotPlusUse = CreateConVar("shavit_replay_botplususe", "1", "Allow bots to use +use?", 0, true, 0.0, true, 1.0);
	gCV_BotWeapon = CreateConVar("shavit_replay_botweapon", "", "Choose which weapon the bot will hold.\nLeave empty to use the default.\nSet to \"none\" to have none.\nExample: weapon_usp");

	gCV_CentralBot.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	// admin menu
	if(LibraryExists("adminmenu") && ((gH_AdminMenu = GetAdminTopMenu()) != null))
	{
		OnAdminMenuReady(gH_AdminMenu);
	}

	// hooks
	HookEvent("player_spawn", Player_Event, EventHookMode_Pre);
	HookEvent("player_death", Player_Event, EventHookMode_Pre);
	HookEvent("player_connect", BotEvents, EventHookMode_Pre);
	HookEvent("player_disconnect", BotEvents, EventHookMode_Pre);
	HookEventEx("player_connect_client", BotEvents, EventHookMode_Pre);

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
	OnMapStart();
}

public void OnAdminMenuCreated(Handle topmenu)
{
	if(gH_AdminMenu == null || (topmenu == gH_AdminMenu && gH_TimerCommands != INVALID_TOPMENUOBJECT))
	{
		return;
	}

	gH_TimerCommands = gH_AdminMenu.AddCategory("Timer Commands", CategoryHandler, "shavit_admin", ADMFLAG_RCON);
}

public void CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayTitle)
	{
		FormatEx(buffer, maxlength, "%T:", "TimerCommands", param);
	}

	else if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "TimerCommands", param);
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	if((gH_AdminMenu = GetAdminTopMenu()) != null)
	{
		if(gH_TimerCommands == INVALID_TOPMENUOBJECT)
		{
			gH_TimerCommands = gH_AdminMenu.FindCategory("Timer Commands");

			if(gH_TimerCommands == INVALID_TOPMENUOBJECT)
			{
				OnAdminMenuCreated(topmenu);
			}
		}
		
		gH_AdminMenu.AddItem("sm_deletereplay", AdminMenu_DeleteReplay, gH_TimerCommands, "sm_deletereplay", ADMFLAG_RCON);
	}
}

public void AdminMenu_DeleteReplay(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%t", "DeleteReplayAdminMenu");
	}

	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteReplay(param, 0);
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
	if(gCV_CentralBot.BoolValue)
	{
		return gA_CentralCache.iClient;
	}

	return gI_ReplayBotClient[GetNativeCell(1)];
}

public int Native_IsReplayDataLoaded(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);

	if(gCV_CentralBot.BoolValue)
	{
		return view_as<int>(gA_CentralCache.iClient != -1 && gA_CentralCache.iReplayStatus != Replay_Idle && gA_FrameCache[style][track].iFrameCount > 0);
	}

	return view_as<int>(ReplayEnabled(style) && gA_FrameCache[style][Track_Main].iFrameCount > 0);
}

public int Native_ReloadReplay(Handle handler, int numParams)
{
	int style = GetNativeCell(1);

	gI_ReplayTick[style] = -1;
	gF_StartTick[style] = -65535.0;
	gRS_ReplayStatus[style] = Replay_Idle;

	int track = GetNativeCell(2);
	bool restart = view_as<bool>(GetNativeCell(3));

	char path[PLATFORM_MAX_PATH];
	GetNativeString(4, path, PLATFORM_MAX_PATH);

	delete gA_Frames[style][track];
	gA_Frames[style][track] = new ArrayList(CELLS_PER_FRAME);
	gA_FrameCache[style][track].iFrameCount = 0;
	gA_FrameCache[style][track].fTime = 0.0;
	gA_FrameCache[style][track].bNewFormat = false;
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, "invalid");

	bool loaded = false;

	if(strlen(path) > 0)
	{
		loaded = LoadReplay(style, track, path);
	}

	else
	{
		loaded = DefaultLoadReplay(style, track);
	}

	if(gCV_CentralBot.BoolValue)
	{
		if(gA_CentralCache.iStyle == style && gA_CentralCache.iTrack == track)
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
			CreateTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_StartReplay, style, TIMER_FLAG_NO_MAPCHANGE);
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

		for(int j = 0; j < ((gCV_CentralBot.BoolValue)? TRACKS_SIZE:1); j++)
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

	delete gA_PlayerFrames[client];

	ArrayList frames = view_as<ArrayList>(CloneHandle(GetNativeCell(2)));
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
	return gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].iFrameCount;
}

public int Native_GetReplayLength(Handle handler, int numParams)
{
	return view_as<int>(GetReplayLength(GetNativeCell(1), GetNativeCell(2)));
}

public int Native_GetReplayName(Handle handler, int numParams)
{
	return SetNativeString(3, gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].sReplayName, GetNativeCell(4));
}

public int Native_GetReplayTime(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);

	if(style < 0 || track < 0)
	{
		return view_as<int>(0.0);
	}

	if(gCV_CentralBot.BoolValue)
	{
		if(gA_CentralCache.iReplayStatus == Replay_End)
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

public int Native_HijackAngles(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	gB_HijackFrame[client] = true;
	gF_HijackedAngles[client][0] = view_as<float>(GetNativeCell(2));
	gF_HijackedAngles[client][1] = view_as<float>(GetNativeCell(3));
}

public int Native_GetReplayBotStyle(Handle handler, int numParams)
{
	return (gCV_CentralBot.BoolValue && gA_CentralCache.iReplayStatus == Replay_Idle)? -1:GetReplayStyle(GetNativeCell(1));
}

public int Native_GetReplayBotTrack(Handle handler, int numParams)
{
	return GetReplayTrack(GetNativeCell(1));
}

public int Native_GetReplayBotType(Handle handler, int numParams)
{
	return view_as<int>((gCV_CentralBot.BoolValue)? Replay_Central:Replay_Legacy);
}

public int Native_Replay_DeleteMap(Handle handler, int numParams)
{
	char sMap[160];
	GetNativeString(1, sMap, 160);

	for(int i = 0; i < gI_Styles; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		for(int j = 0; j < ((gCV_CentralBot.BoolValue)? TRACKS_SIZE:1); j++)
		{
			char sTrack[4];
			FormatEx(sTrack, 4, "_%d", j);

			char sPath[PLATFORM_MAX_PATH];
			FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, i, sMap, (j > 0)? sTrack:"");

			if(FileExists(sPath))
			{
				DeleteFile(sPath);
			}
		}
	}

	if(StrEqual(gS_Map, sMap, false))
	{
		OnMapStart();
	}
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
	char sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-prefix.txt");

	File fFile = OpenFile(sFile, "r");

	if(fFile == null)
	{
		SetFailState("Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}
	
	char sLine[PLATFORM_MAX_PATH*2];

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
	if(!gCV_Enabled.BoolValue)
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
		for(int j = 0; j < ((gCV_CentralBot.BoolValue)? TRACKS_SIZE:1); j++)
		{
			if(!gCV_CentralBot.BoolValue && gI_ReplayBotClient[i] != 0)
			{
				UpdateReplayInfo(gI_ReplayBotClient[i], i, GetReplayLength(i, j), j);
			}
		}
	}

	if(gCV_CentralBot.BoolValue && gA_CentralCache.iClient != -1)
	{
		if(gA_CentralCache.iStyle != -1)
		{
			UpdateReplayInfo(gA_CentralCache.iClient, gA_CentralCache.iStyle, -1.0, gA_CentralCache.iTrack);
		}

		else
		{
			UpdateReplayInfo(gA_CentralCache.iClient, 0, 0.0, 0);
		}
	}

	return Plugin_Continue;
}

bool LoadStyling()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-replay.cfg");

	KeyValues kv = new KeyValues("shavit-replay");
	
	if(!kv.ImportFromFile(sPath))
	{
		delete kv;

		return false;
	}

	kv.GetString("clantag", gS_ReplayStrings.sClanTag, MAX_NAME_LENGTH, "<EMPTY CLANTAG>");
	kv.GetString("namestyle", gS_ReplayStrings.sNameStyle, MAX_NAME_LENGTH, "<EMPTY NAMESTYLE>");
	kv.GetString("centralname", gS_ReplayStrings.sCentralName, MAX_NAME_LENGTH, "<EMPTY CENTRALNAME>");
	kv.GetString("centralstyle", gS_ReplayStrings.sCentralStyle, MAX_NAME_LENGTH, "<EMPTY CENTRALSTYLE>");
	kv.GetString("centralstyletag", gS_ReplayStrings.sCentralStyleTag, MAX_NAME_LENGTH, "<EMPTY CENTRALSTYLETAG>");
	kv.GetString("unloaded", gS_ReplayStrings.sUnloaded, MAX_NAME_LENGTH, "<EMPTY UNLOADED>");

	char sFolder[PLATFORM_MAX_PATH];
	kv.GetString("replayfolder", sFolder, PLATFORM_MAX_PATH, "{SM}/data/replaybot");

	delete kv;

	if(StrContains(sFolder, "{SM}") != -1)
	{
		ReplaceString(sFolder, PLATFORM_MAX_PATH, "{SM}/", "");
		BuildPath(Path_SM, sFolder, PLATFORM_MAX_PATH, "%s", sFolder);
	}
	
	strcopy(gS_ReplayFolder, PLATFORM_MAX_PATH, sFolder);

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

	gA_CentralCache.iClient = -1;
	gA_CentralCache.iStyle = -1;
	gA_CentralCache.iReplayStatus = Replay_Idle;
	gA_CentralCache.iTrack = Track_Main;

	gB_ForciblyStopped = false;

	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);

	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	bot_quota = FindConVar((gEV_Type != Engine_TF2)? "bot_quota":"tf_bot_quota");

	if(bot_quota != null)
	{
		bot_quota.Flags &= ~FCVAR_NOTIFY;
	}

	char sTempMap[PLATFORM_MAX_PATH];
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

	if(!DirExists(gS_ReplayFolder))
	{
		CreateDirectory(gS_ReplayFolder, 511);
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

		char sPath[PLATFORM_MAX_PATH];
		FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d", gS_ReplayFolder, i);

		if(!DirExists(sPath))
		{
			CreateDirectory(sPath, 511);
		}

		bool loaded = false;

		for(int j = 0; j < ((gCV_CentralBot.BoolValue)? TRACKS_SIZE:1); j++)
		{
			delete gA_Frames[i][j];
			gA_Frames[i][j] = new ArrayList(CELLS_PER_FRAME);
			gA_FrameCache[i][j].iFrameCount = 0;
			gA_FrameCache[i][j].fTime = 0.0;
			gA_FrameCache[i][j].bNewFormat = false;
			strcopy(gA_FrameCache[i][j].sReplayName, MAX_NAME_LENGTH, "invalid");

			loaded = DefaultLoadReplay(i, j);
		}

		if(!gCV_CentralBot.BoolValue)
		{
			ServerCommand((gEV_Type != Engine_TF2)? "bot_add":"tf_bot_add");
			gI_ExpectedBots++;

			if(loaded)
			{
				gI_ReplayTick[i] = 0;
				gRS_ReplayStatus[i] = Replay_Start;
				CreateTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_StartReplay, i, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}

	if(gCV_CentralBot.BoolValue)
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
		Shavit_GetStyleStrings(i, sClanTag, gS_StyleStrings[i].sClanTag, sizeof(stylestrings_t::sClanTag));
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i].sStyleName, sizeof(stylestrings_t::sStyleName));
		Shavit_GetStyleStrings(i, sShortName, gS_StyleStrings[i].sShortName, sizeof(stylestrings_t::sShortName));
	}

	gI_Styles = styles;
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStrings(sMessagePrefix, gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix));
	Shavit_GetChatStrings(sMessageText, gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	Shavit_GetChatStrings(sMessageWarning, gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning));
	Shavit_GetChatStrings(sMessageVariable, gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
	Shavit_GetChatStrings(sMessageVariable2, gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2));
	Shavit_GetChatStrings(sMessageStyle, gS_ChatStrings.sStyle, sizeof(chatstrings_t::sStyle));
}

bool DefaultLoadReplay(int style, int track)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, style, gS_Map, (track > 0)? sTrack:"");

	return LoadReplay(style, track, sPath);
}

bool LoadReplay(int style, int track, const char[] path)
{
	if(FileExists(path))
	{
		File fFile = OpenFile(path, "rb");

		char sHeader[64];

		if(!fFile.ReadLine(sHeader, 64))
		{
			return false;
		}

		TrimString(sHeader);
		char sExplodedHeader[2][64];
		ExplodeString(sHeader, ":", sExplodedHeader, 2, 64);

		if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_FINAL)) // hopefully, the last of them
		{
			gA_FrameCache[style][track].iReplayVersion = StringToInt(sExplodedHeader[0]);

			int iTemp = 0;
			fFile.ReadInt32(iTemp);
			gA_FrameCache[style][track].iFrameCount = iTemp;

			if(gA_Frames[style][track] == null)
			{
				gA_Frames[style][track] = new ArrayList(CELLS_PER_FRAME);
			}

			gA_Frames[style][track].Resize(iTemp);

			fFile.ReadInt32(iTemp);
			gA_FrameCache[style][track].fTime = view_as<float>(iTemp);

			char sAuthID[32];
			fFile.ReadString(sAuthID, 32);

			if(gH_SQL != null)
			{
				char sQuery[192];
				FormatEx(sQuery, 192, "SELECT name FROM %susers WHERE auth = '%s';", gS_MySQLPrefix, sAuthID);

				DataPack pack = new DataPack();
				pack.WriteCell(style);
				pack.WriteCell(track);

				gH_SQL.Query(SQL_GetUserName_Callback, sQuery, pack, DBPrio_High);
			}

			int cells = CELLS_PER_FRAME;

			// backwards compatibility
			if(gA_FrameCache[style][track].iReplayVersion == 0x01)
			{
				cells = 6;
			}

			any[] aReplayData = new any[cells];

			for(int i = 0; i < gA_FrameCache[style][track].iFrameCount; i++)
			{
				if(fFile.Read(aReplayData, cells, 4) >= 0)
				{
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[0]), 0);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[1]), 1);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[2]), 2);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[3]), 3);
					gA_Frames[style][track].Set(i, view_as<float>(aReplayData[4]), 4);
					gA_Frames[style][track].Set(i, view_as<int>(aReplayData[5]), 5);

					if(gA_FrameCache[style][track].iReplayVersion >= 0x02)
					{
						gA_Frames[style][track].Set(i, view_as<int>(aReplayData[6]), 6);
						gA_Frames[style][track].Set(i, view_as<int>(aReplayData[7]), 7);
					}
				}
			}

			gA_FrameCache[style][track].bNewFormat = true; // not wr-based
		}

		else if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_V2))
		{
			int iReplaySize = gA_FrameCache[style][track].iFrameCount = StringToInt(sExplodedHeader[0]);
			gA_Frames[style][track].Resize(iReplaySize);

			gA_FrameCache[style][track].fTime = 0.0; // N/A at this version

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

			gA_FrameCache[style][track].bNewFormat = false;
			strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, "invalid");
		}

		else // old, outdated and slow - only used for ancient replays
		{
			char sLine[320];
			char sExplodedLine[6][64];

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

			gA_FrameCache[style][track].iFrameCount = gA_Frames[style][track].Length;
			gA_FrameCache[style][track].fTime = 0.0; // N/A at this version
			gA_FrameCache[style][track].bNewFormat = false; // wr-based
			strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, "invalid");
		}

		delete fFile;

		return true;
	}

	return false;
}

bool SaveReplay(int style, int track, float time, char[] authid, char[] name)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, style, gS_Map, (track > 0)? sTrack:"");

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

	any aFrameData[CELLS_PER_FRAME];
	any aWriteData[CELLS_PER_FRAME * FRAMES_PER_WRITE];
	int iFramesWritten = 0;

	for(int i = 0; i < iSize; i++)
	{
		gA_Frames[style][track].GetArray(i, aFrameData, CELLS_PER_FRAME);

		for(int j = 0; j < CELLS_PER_FRAME; j++)
		{
			aWriteData[(CELLS_PER_FRAME * iFramesWritten) + j] = aFrameData[j];
		}

		if(++iFramesWritten == FRAMES_PER_WRITE || i == iSize - 1)
		{
			fFile.Write(aWriteData, CELLS_PER_FRAME * iFramesWritten, 4);

			iFramesWritten = 0;
		}
	}

	delete fFile;

	gA_FrameCache[style][track].iFrameCount = iSize;
	gA_FrameCache[style][track].fTime = time;
	gA_FrameCache[style][track].bNewFormat = true;
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, name);

	return true;
}

bool DeleteReplay(int style, int track)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, style, gS_Map, (track > 0)? sTrack:"");

	if(!FileExists(sPath) || !DeleteFile(sPath))
	{
		return false;
	}

	if(gCV_CentralBot.BoolValue && gA_CentralCache.iStyle == style && gA_CentralCache.iTrack == track)
	{
		StopCentralReplay(0);
	}

	gA_Frames[style][track].Clear();
	gA_FrameCache[style][track].iFrameCount = 0;
	gA_FrameCache[style][track].fTime = 0.0;
	gA_FrameCache[style][track].bNewFormat = false;
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, "invalid");
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
		results.FetchString(0, gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH);
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
		if(!gCV_CentralBot.BoolValue)
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

		else if(gA_CentralCache.iClient == -1)
		{
			UpdateReplayInfo(client, 0, 0.0, Track_Main);
			gA_CentralCache.iClient = client;
		}
	}
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
		SDKHook(entity, SDKHook_Use, HookTriggers);
	}
}

public Action HookTriggers(int entity, int other)
{
	if(gCV_Enabled.BoolValue && 1 <= other <= MaxClients && IsFakeClient(other))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void FormatStyle(const char[] source, int style, bool central, float time, int track, char[] dest, int size)
{
	float fWRTime = GetReplayLength(style, track);

	char sTime[16];
	FormatSeconds((time == -1.0)? fWRTime:time, sTime, 16);

	char sName[MAX_NAME_LENGTH];
	GetReplayName(style, track, sName, MAX_NAME_LENGTH);
	
	char[] temp = new char[size];
	strcopy(temp, size, source);

	ReplaceString(temp, size, "{map}", gS_Map);

	if(central && gA_CentralCache.iReplayStatus == Replay_Idle)
	{
		ReplaceString(temp, size, "{style}", gS_ReplayStrings.sCentralStyle);
		ReplaceString(temp, size, "{styletag}", gS_ReplayStrings.sCentralStyleTag);
	}

	else
	{
		ReplaceString(temp, size, "{style}", gS_StyleStrings[style].sStyleName);
		ReplaceString(temp, size, "{styletag}", gS_StyleStrings[style].sClanTag);
	}
	
	ReplaceString(temp, size, "{time}", sTime);
	ReplaceString(temp, size, "{player}", sName);

	char sTrack[32];
	GetTrackName(LANG_SERVER, track, sTrack, 32);
	ReplaceString(temp, size, "{track}", sTrack);

	strcopy(dest, size, temp);
}

void UpdateReplayInfo(int client, int style, float time, int track)
{
	if(!gCV_Enabled.BoolValue || !IsValidClient(client) || !IsFakeClient(client))
	{
		return;
	}

	SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
	SetEntityMoveType(client, MOVETYPE_NOCLIP);

	bool central = (gA_CentralCache.iClient == client);
	bool idle = (central && gA_CentralCache.iReplayStatus == Replay_Idle);

	if(gEV_Type != Engine_TF2)
	{
		char sTag[MAX_NAME_LENGTH];
		FormatStyle(gS_ReplayStrings.sClanTag, style, central, time, track, sTag, MAX_NAME_LENGTH);
		CS_SetClientClanTag(client, sTag);
	}

	char sName[MAX_NAME_LENGTH];
	int iFrameCount = gA_FrameCache[style][track].iFrameCount;
	
	if(central || iFrameCount > 0)
	{
		if(idle)
		{
			FormatStyle(gS_ReplayStrings.sCentralName, style, central, time, track, sName, MAX_NAME_LENGTH);
		}
		
		else
		{
			FormatStyle(gS_ReplayStrings.sNameStyle, style, central, time, track, sName, MAX_NAME_LENGTH);
		}
	}

	else
	{
		FormatStyle(gS_ReplayStrings.sUnloaded, style, central, time, track, sName, MAX_NAME_LENGTH);
	}

	gB_HideNameChange = true;
	SetClientName(client, sName);

	int iScore = (iFrameCount > 0 || client == gA_CentralCache.iClient)? 2000:-2000;

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

	if(!gCV_CentralBot.BoolValue && iFrameCount == 0)
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

		char sWeapon[32];
		gCV_BotWeapon.GetString(sWeapon, 32);

		if(gEV_Type != Engine_TF2 && strlen(sWeapon) > 0)
		{
			int iWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

			if(StrEqual(sWeapon, "none"))
			{
				if(iWeapon != -1 && IsValidEntity(iWeapon))
				{
					CS_DropWeapon(client, iWeapon, false);
					AcceptEntityInput(iWeapon, "Kill");
				}
			}

			else
			{
				char sClassname[32];

				if(iWeapon != -1 && IsValidEntity(iWeapon))
				{
					GetEntityClassname(iWeapon, sClassname, 32);

					if(!StrEqual(sWeapon, sClassname))
					{
						CS_DropWeapon(client, iWeapon, false);
						AcceptEntityInput(iWeapon, "Kill");
					}
				}

				else
				{
					GivePlayerItem(client, sWeapon);
				}
			}
		}
	}

	if(GetClientTeam(client) != gCV_DefaultTeam.IntValue)
	{
		if(gEV_Type == Engine_TF2)
		{
			ChangeClientTeam(client, gCV_DefaultTeam.IntValue);
		}

		else
		{
			CS_SwitchTeam(client, gCV_DefaultTeam.IntValue);
		}
	}
}

public void OnClientDisconnect(int client)
{
	if(IsClientSourceTV(client))
	{
		return;
	}

	if(!IsFakeClient(client))
	{
		if(gA_PlayerFrames[client] != null)
		{
			delete gA_PlayerFrames[client];
		}

		return;
	}

	if(gA_CentralCache.iClient == client)
	{
		gA_CentralCache.iClient = -1;

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

	if(!gCV_Enabled.BoolValue || (gCV_TimeLimit.FloatValue > 0.0 && time > gCV_TimeLimit.FloatValue))
	{
		ClearFrames(client);

		return;
	}

	float length = GetReplayLength(style, track);

	if(gA_FrameCache[style][track].bNewFormat)
	{
		if(length > 0.0 && time > length)
		{
			return;
		}
	}

	else
	{
		float wrtime = Shavit_GetWorldRecord(style, track);

		if(wrtime != 0.0 && time > wrtime)
		{
			return;
		}
	}

	if(gI_PlayerFrames[client] == 0)
	{
		return;
	}

	delete gA_Frames[style][track];
	gA_Frames[style][track] = gA_PlayerFrames[client].Clone();

	char sAuthID[32];
	GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);
	ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");

	SaveReplay(style, track, time, sAuthID, sName);

	if(ReplayEnabled(style))
	{
		if(gCV_CentralBot.BoolValue && gA_CentralCache.iStyle == style && gA_CentralCache.iTrack == track)
		{
			StopCentralReplay(0);
		}

		else if(!gCV_CentralBot.BoolValue && gI_ReplayBotClient[style] != 0)
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

void ApplyFlags(int &flags1, int flags2, int flag)
{
	if((flags2 & flag) > 0)
	{
		flags1 |= flag;
	}

	else
	{
		flags2 &= ~flag;
	}
}

// OnPlayerRunCmd instead of Shavit_OnUserCmdPre because bots are also used here.
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
	if(!gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	if(!IsPlayerAlive(client))
	{
		if((buttons & IN_USE) > 0)
		{
			if(!gB_Button[client] && GetSpectatorTarget(client) == gA_CentralCache.iClient)
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

		if(gA_Frames[style][track] == null || gA_FrameCache[style][track].iFrameCount <= 0) // if no replay is loaded
		{
			return Plugin_Changed;
		}

		if(gI_ReplayTick[style] != -1 && gA_FrameCache[style][track].iFrameCount >= 1)
		{
			float vecPosition[3];
			float vecAngles[3];

			if(gRS_ReplayStatus[style] != Replay_Running)
			{
				bool bStart = (gRS_ReplayStatus[style] == Replay_Start);

				int iFrame = (bStart)? 0:(gA_FrameCache[style][track].iFrameCount - 1);

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

			if(++gI_ReplayTick[style] >= gA_FrameCache[style][track].iFrameCount)
			{
				gI_ReplayTick[style] = 0;
				gRS_ReplayStatus[style] = gA_CentralCache.iReplayStatus = Replay_End;

				CreateTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_EndReplay, style, TIMER_FLAG_NO_MAPCHANGE);

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

			if((gCV_BotShooting.IntValue & iBotShooting_Attack1) == 0)
			{
				buttons &= ~IN_ATTACK;
			}

			if((gCV_BotShooting.IntValue & iBotShooting_Attack2) == 0)
			{
				buttons &= ~IN_ATTACK2;
			}

			if(!gCV_BotPlusUse.BoolValue)
			{
				buttons &= ~IN_USE;
			}

			MoveType mt = MOVETYPE_NOCLIP;

			if(gA_FrameCache[style][track].iReplayVersion >= 0x02)
			{
				int iReplayFlags = gA_Frames[style][track].Get(gI_ReplayTick[style], 6);
				int iEntityFlags = GetEntityFlags(client);

				ApplyFlags(iEntityFlags, iReplayFlags, FL_ONGROUND);
				ApplyFlags(iEntityFlags, iReplayFlags, FL_PARTIALGROUND);
				ApplyFlags(iEntityFlags, iReplayFlags, FL_INWATER);
				ApplyFlags(iEntityFlags, iReplayFlags, FL_SWIM);

				SetEntityFlags(client, iEntityFlags);
				
				MoveType movetype = gA_Frames[style][track].Get(gI_ReplayTick[style], 7);

				if(movetype == MOVETYPE_LADDER)
				{
					mt = MOVETYPE_LADDER;
				}
			}

			SetEntityMoveType(client, mt);

			float vecVelocity[3];
			MakeVectorFromPoints(vecCurrentPosition, vecPosition, vecVelocity);
			ScaleVector(vecVelocity, gF_Tickrate);

			if(gI_ReplayTick[style] > 1)
			{
				float vecLastPosition[3];
				vecLastPosition[0] = gA_Frames[style][track].Get(gI_ReplayTick[style] - 1, 0);
				vecLastPosition[1] = gA_Frames[style][track].Get(gI_ReplayTick[style] - 1, 1);
				vecLastPosition[2] = gA_Frames[style][track].Get(gI_ReplayTick[style] - 1, 2);

				// fix for replay not syncing
				if(GetVectorDistance(vecLastPosition, vecCurrentPosition) >= 100.0 && IsWallBetween(vecLastPosition, vecCurrentPosition, client))
				{
					TeleportEntity(client, vecPosition, NULL_VECTOR, NULL_VECTOR);
					
					return Plugin_Handled;
				}

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

	else if(ReplayEnabled(Shavit_GetBhopStyle(client)) && Shavit_GetTimerStatus(client) == Timer_Running)
	{
		if((gI_PlayerFrames[client] / gF_Tickrate) > gCV_TimeLimit.FloatValue)
		{
			Shavit_PrintToChat(client, "stopped recording: %d", gI_PlayerFrames[client]);
			// in case of bad timing
			if(gB_HijackFrame[client])
			{
				gB_HijackFrame[client] = false;
			}

			return Plugin_Continue;
		}

		gA_PlayerFrames[client].Resize(gI_PlayerFrames[client] + 1);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[0], 0);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[1], 1);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[2], 2);

		if(!gB_HijackFrame[client])
		{
			float vecEyes[3];
			GetClientEyeAngles(client, vecEyes);

			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecEyes[0], 3);
			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecEyes[1], 4);
		}

		else
		{
			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], gF_HijackedAngles[client][0], 3);
			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], gF_HijackedAngles[client][1], 4);

			gB_HijackFrame[client] = false;
		}

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], buttons, 5);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], GetEntityFlags(client), 6);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], GetEntityMoveType(client), 7);

		gI_PlayerFrames[client]++;
	}

	return Plugin_Continue;
}

public bool Filter_Clients(int entity, int contentsMask, any data)
{
	return (1 <= entity <= MaxClients && entity != data);
}

bool IsWallBetween(float pos1[3], float pos2[3], int bot)
{
	TR_TraceRayFilter(pos1, pos2, MASK_SOLID, RayType_EndPoint, Filter_Clients, bot);
	
	return !TR_DidHit();
}

public Action Timer_EndReplay(Handle Timer, any data)
{
	if(gCV_CentralBot.BoolValue && gB_ForciblyStopped)
	{
		gB_ForciblyStopped = false;

		return Plugin_Stop;
	}

	gI_ReplayTick[data] = 0;

	Call_StartForward(gH_OnReplayEnd);
	Call_PushCell(gI_ReplayBotClient[data]);
	Call_Finish();

	if(gI_ReplayBotClient[data] != gA_CentralCache.iClient)
	{
		gRS_ReplayStatus[data] = Replay_Start;

		CreateTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_StartReplay, data, TIMER_FLAG_NO_MAPCHANGE);
	}

	else
	{
		gRS_ReplayStatus[data] = gA_CentralCache.iReplayStatus = Replay_Idle;
		gI_ReplayBotClient[data] = 0;
	}

	return Plugin_Stop;
}

public Action Timer_StartReplay(Handle Timer, any data)
{
	if(gRS_ReplayStatus[data] == Replay_Running || (gCV_CentralBot.BoolValue && gB_ForciblyStopped))
	{
		return Plugin_Stop;
	}

	Call_StartForward(gH_OnReplayStart);
	Call_PushCell(gI_ReplayBotClient[data]);
	Call_Finish();

	gRS_ReplayStatus[data] = gA_CentralCache.iReplayStatus = Replay_Running;

	return Plugin_Stop;
}

bool ReplayEnabled(any style)
{
	return (!gA_StyleSettings[style].bUnranked && !gA_StyleSettings[style].bNoReplay);
}

public void Player_Event(Event event, const char[] name, bool dontBroadcast)
{
	if(!gCV_Enabled.BoolValue)
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
	if(!gCV_Enabled.BoolValue)
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

public Action Hook_SayText2(UserMsg msg_id, any msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if(!gB_HideNameChange || !gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	// caching usermessage type rather than call it every time
	static UserMessageType um = view_as<UserMessageType>(-1);

	if(um == view_as<UserMessageType>(-1))
	{
		um = GetUserMessageType();
	}

	char sMessage[24];

	if(um == UM_Protobuf)
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
		bfmsg.ReadString(sMessage, 24);
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
	float time = Shavit_GetWorldRecord(style, track);

	if(gA_FrameCache[style][track].iFrameCount > 0 && GetReplayLength(style, track) - gF_Tickrate <= time) // -0.1 to fix rounding issues
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
			if(gA_FrameCache[i][j].iFrameCount == 0)
			{
				continue;
			}

			char sInfo[8];
			FormatEx(sInfo, 8, "%d;%d", i, j);

			float time = GetReplayLength(i, j);

			char sTrack[32];
			GetTrackName(client, j, sTrack, 32);

			char sDisplay[64];

			if(time > 0.0)
			{
				char sTime[32];
				FormatSeconds(time, sTime, 32, false);

				FormatEx(sDisplay, 64, "%s (%s) - %s", gS_StyleStrings[i].sStyleName, sTrack, sTime);
			}

			else
			{
				FormatEx(sDisplay, 64, "%s (%s)", gS_StyleStrings[i].sStyleName, sTrack);
			}

			menu.AddItem(sInfo, sDisplay);
		}
	}

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
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
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		char sExploded[2][4];
		ExplodeString(sInfo, ";", sExploded, 2, 4);
		
		int style = StringToInt(sExploded[0]);

		if(style == -1)
		{
			return 0;
		}

		gI_Track[param1] = StringToInt(sExploded[1]);

		Menu submenu = new Menu(DeleteConfirmation_Callback);
		submenu.SetTitle("%T", "ReplayDeletionConfirmation", param1, gS_StyleStrings[style].sStyleName);

		char sMenuItem[64];

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
		char sInfo[4];
		menu.GetItem(param2, sInfo, 4);
		int style = StringToInt(sInfo);

		if(DeleteReplay(style, gI_Track[param1]))
		{
			char sTrack[32];
			GetTrackName(param1, gI_Track[param1], sTrack, 32);

			LogAction(param1, param1, "Deleted replay for %s on map %s. (Track: %s)", gS_StyleStrings[style].sStyleName, gS_Map, sTrack);

			Shavit_PrintToChat(param1, "%T (%s%s%s)", "ReplayDeleted", param1, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);
		}

		else
		{
			Shavit_PrintToChat(param1, "%T", "ReplayDeleteFailure", param1, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
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
	if(!IsValidClient(client) || !gCV_CentralBot.BoolValue || gA_CentralCache.iClient == -1)
	{
		return Plugin_Handled;
	}

	if(GetClientTeam(client) != 1 || GetSpectatorTarget(client) != gA_CentralCache.iClient)
	{
		Shavit_PrintToChat(client, "%T", "CentralReplaySpectator", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(CheckCommandAccess(client, "sm_deletereplay", ADMFLAG_RCON))
	{
		char arg[8];
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
			if(gA_FrameCache[j][i].iFrameCount > 0)
			{
				records = true;

				continue;
			}
		}

		char sInfo[8];
		IntToString(i, sInfo, 8);

		char sTrack[32];
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

	char sTrack[32];
	GetTrackName(client, track, sTrack, 32);

	Menu menu = new Menu(MenuHandler_ReplaySubmenu);
	menu.SetTitle("%T (%s)\n ", "CentralReplayTitle", client, sTrack);

	if(CheckCommandAccess(client, "sm_deletereplay", ADMFLAG_RCON))
	{
		char sDisplay[64];
		FormatEx(sDisplay, 64, "%T", "CentralReplayStop", client);

		menu.AddItem("stop", sDisplay, (gA_CentralCache.iReplayStatus != Replay_Idle)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		char sInfo[8];
		IntToString(i, sInfo, 8);

		float time = GetReplayLength(i, track);

		char sDisplay[64];

		if(time > 0.0)
		{
			char sTime[32];
			FormatSeconds(time, sTime, 32, false);

			FormatEx(sDisplay, 64, "%s - %s", gS_StyleStrings[i].sStyleName, sTime);
		}

		else
		{
			strcopy(sDisplay, 64, gS_StyleStrings[i].sStyleName);
		}

		menu.AddItem(sInfo, sDisplay, (gA_FrameCache[i][track].iFrameCount > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
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
		char info[16];
		menu.GetItem(param2, info, 16);

		if(StrEqual(info, "stop"))
		{
			StopCentralReplay(param1);
			OpenReplaySubMenu(param1, gI_Track[param1]);

			return 0;
		}

		int style = StringToInt(info);

		if(style == -1 || !ReplayEnabled(style) || gA_FrameCache[style][gI_Track[param1]].iFrameCount == 0 || gA_CentralCache.iClient <= 0)
		{
			return 0;
		}

		if(gA_CentralCache.iReplayStatus != Replay_Idle)
		{
			Shavit_PrintToChat(param1, "%T", "CentralReplayPlaying", param1);

			OpenReplaySubMenu(param1, gI_Track[param1]);
		}

		else
		{
			gI_ReplayTick[style] = 0;
			gA_CentralCache.iStyle = style;
			gA_CentralCache.iTrack = gI_Track[param1];
			gI_ReplayBotClient[style] = gA_CentralCache.iClient;
			gRS_ReplayStatus[style] = gA_CentralCache.iReplayStatus = Replay_Start;
			TeleportToStart(gA_CentralCache.iClient, style, gI_Track[param1]);
			gB_ForciblyStopped = false;

			float time = GetReplayLength(gA_CentralCache.iStyle, gI_Track[param1]);

			UpdateReplayInfo(gA_CentralCache.iClient, style, time, gI_Track[param1]);

			CreateTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_StartReplay, style, TIMER_FLAG_NO_MAPCHANGE);
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
	if(gA_FrameCache[style][track].iFrameCount == 0)
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

	int style = gA_CentralCache.iStyle;

	gRS_ReplayStatus[style] = gA_CentralCache.iReplayStatus = Replay_Idle;
	gI_ReplayTick[style] = 0;
	gI_ReplayBotClient[style] = 0;
	gF_StartTick[style] = -65535.0;
	TeleportToStart(gA_CentralCache.iClient, style, GetReplayTrack(gA_CentralCache.iClient));
	gA_CentralCache.iStyle = 0;
	gB_ForciblyStopped = true;

	UpdateReplayInfo(client, 0, 0.0, gA_CentralCache.iTrack);
}

int GetReplayStyle(int client)
{
	if(!IsFakeClient(client) || IsClientSourceTV(client))
	{
		return -1;
	}

	if(gCV_CentralBot.BoolValue)
	{
		if(gA_CentralCache.iStyle == -1)
		{
			return 0;
		}

		return gA_CentralCache.iStyle;
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
	if(!IsFakeClient(client) || IsClientSourceTV(client))
	{
		return -1;
	}

	return (gCV_CentralBot.BoolValue)? gA_CentralCache.iTrack:Track_Main;
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
	if(gA_FrameCache[style][track].bNewFormat)
	{
		return gA_FrameCache[style][track].fTime;
	}

	float fWRTime = Shavit_GetWorldRecord(style, track);

	return fWRTime;
}

void GetReplayName(int style, int track, char[] buffer, int length)
{
	if(gA_FrameCache[style][track].bNewFormat)
	{
		strcopy(buffer, length, gA_FrameCache[style][track].sReplayName);

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

	int buffer[32];
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
