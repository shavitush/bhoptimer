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
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <shavit>

#define REPLAY_FORMAT_V2 "{SHAVITREPLAYFORMAT}{V2}"

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

enum
{
	iCentralClient,
	iCentralStyle,
	iCentralReplayStatus,
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
ArrayList gA_Frames[STYLE_LIMIT] = {null, ...};
float gF_StartTick[STYLE_LIMIT];
ReplayStatus gRS_ReplayStatus[STYLE_LIMIT];
int gI_FrameCount[STYLE_LIMIT];

bool gB_Button[MAXPLAYERS+1];
int gI_PlayerFrames[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];
bool gB_Record[MAXPLAYERS+1];

bool gB_Late = false;
int gI_DefaultTeamSlots = 0;

// server specific
float gF_Tickrate = 0.0;
char gS_Map[256];
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
	CreateNative("Shavit_GetReplayBotFirstFrame", Native_GetReplayBotFirstFrame);
	CreateNative("Shavit_GetReplayBotIndex", Native_GetReplayBotIndex);
	CreateNative("Shavit_GetReplayBotCurrentFrame", Native_GetReplayBotIndex);
	CreateNative("Shavit_IsReplayDataLoaded", Native_IsReplayDataLoaded);
	CreateNative("Shavit_GetReplayBotStyle", Native_GetReplayBotStyle);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-replay");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
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
	gCV_DefaultTeam = CreateConVar("shavit_replay_defaultteam", "3", "Default team to make the bots join, if possible.\n2 - Terrorists\n3 - Counter Terrorists", 0, true, 2.0, true, 3.0);
	gCV_CentralBot = CreateConVar("shavit_replay_centralbot", "1", "Have one central bot instead of one bot per replay.\nTriggered with !replay.\nRestart the map for changes to take effect.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);

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

	if(gB_CentralBot)
	{
		return (gA_CentralCache[iCentralClient] != -1 && gA_CentralCache[iCentralClient] != Replay_Idle && gA_CentralCache[iCentralStyle] == style);
	}

	return view_as<int>(ReplayEnabled(style) && gI_FrameCount[style] > 0);
}

public int Native_GetReplayBotStyle(Handle handler, int numParams)
{
	return (gB_CentralBot && gA_CentralCache[iCentralReplayStatus] == Replay_Idle)? -1:GetReplayStyle(GetNativeCell(1));
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

	// clear player cache if time is worse than wr
	// might cause issues if WR time is removed and someone else gets a new WR
	float[] fWRTimes = new float[gI_Styles];

	for(int i = 0; i < gI_Styles; i++)
	{
		Shavit_GetWRTime(i, fWRTimes[i]);

		if(!gB_CentralBot && gI_ReplayBotClient[i] != 0)
		{
			UpdateReplayInfo(gI_ReplayBotClient[i], i, fWRTimes[i]);
		}
	}

	if(gB_CentralBot && gA_CentralCache[iCentralClient] != -1)
	{
		if(gA_CentralCache[iCentralStyle] != -1)
		{
			UpdateReplayInfo(gA_CentralCache[iCentralClient], gA_CentralCache[iCentralStyle], -1.0);
		}

		else
		{
			UpdateReplayInfo(gA_CentralCache[iCentralClient], 0, 0.0);
		}
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(gI_PlayerFrames[i] == 0 || !IsValidClient(i, true) || IsFakeClient(i))
		{
			continue;
		}

		int style = Shavit_GetBhopStyle(i);

		if(!ReplayEnabled(style) || (fWRTimes[style] > 0.0 && Shavit_GetClientTime(i) > fWRTimes[style]))
		{
			ClearFrames(i);
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

	GetCurrentMap(gS_Map, 256);
	GetMapDisplayName(gS_Map, gS_Map, 256);

	if(!gB_Enabled)
	{
		return;
	}

	bot_quota = FindConVar("bot_quota");
	bot_quota.Flags &= ~FCVAR_NOTIFY;

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

	FindConVar("bot_stop").BoolValue = true;
	FindConVar("bot_quota_mode").SetString("normal");
	FindConVar("mp_autoteambalance").BoolValue = false;
	FindConVar("mp_limitteams").IntValue = 0;
	FindConVar("bot_join_after_player").BoolValue = false;
	FindConVar("bot_chatter").SetString("off");

	ServerCommand("bot_kick");

	gI_ExpectedBots = 0;

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot");

	if(!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		gA_Frames[i] = new ArrayList(6);

		gI_ReplayTick[i] = 0;
		gI_FrameCount[i] = 0;
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

		bool loaded = LoadReplay(i);

		if(!gB_CentralBot)
		{
			ServerCommand("bot_add");
			gI_ExpectedBots++;

			if(!loaded)
			{
				gI_ReplayTick[i] = -1;
			}

			else
			{
				gRS_ReplayStatus[i] = Replay_Start;
				CreateTimer((gF_ReplayDelay / 2.0), StartReplay, i, TIMER_FLAG_NO_MAPCHANGE);
			}
		}
	}

	if(gB_CentralBot)
	{
		gI_ExpectedBots = 1;
		ServerCommand("bot_add");
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

bool LoadReplay(int style)
{
	if(!ReplayEnabled(style))
	{
		return false;
	}

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(FileExists(sPath))
	{
		File fFile = OpenFile(sPath, "rb");

		char[] sHeader = new char[64];

		if(!fFile.ReadLine(sHeader, 64))
		{
			return false;
		}

		TrimString(sHeader);
		char[][] sExplodedHeader = new char[2][64];
		ExplodeString(sHeader, ":", sExplodedHeader, 2, 64);

		if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_V2)) // new replay format, fast!
		{
			int iReplaySize = StringToInt(sExplodedHeader[0]);
			gA_Frames[style].Resize(iReplaySize);

			any[] aReplayData = new any[6];

			for(int i = 0; i < iReplaySize; i++)
			{
				if(fFile.Read(aReplayData, 6, 4) >= 0)
				{
					gA_Frames[style].Set(i, view_as<float>(aReplayData[0]), 0);
					gA_Frames[style].Set(i, view_as<float>(aReplayData[1]), 1);
					gA_Frames[style].Set(i, view_as<float>(aReplayData[2]), 2);
					gA_Frames[style].Set(i, view_as<float>(aReplayData[3]), 3);
					gA_Frames[style].Set(i, view_as<float>(aReplayData[4]), 4);
					gA_Frames[style].Set(i, view_as<int>(aReplayData[5]), 5);
				}
			}
		}

		else // old, outdated and slow - only used for old replays
		{
			char[] sLine = new char[320];
			char[][] sExplodedLine = new char[6][64];

			for(int i = 0; !fFile.EndOfFile(); i++)
			{
				fFile.ReadLine(sLine, 320);
				int iStrings = ExplodeString(sLine, "|", sExplodedLine, 6, 64);

				gA_Frames[style].Resize(i + 1);
				gA_Frames[style].Set(i, StringToFloat(sExplodedLine[0]), 0);
				gA_Frames[style].Set(i, StringToFloat(sExplodedLine[1]), 1);
				gA_Frames[style].Set(i, StringToFloat(sExplodedLine[2]), 2);
				gA_Frames[style].Set(i, StringToFloat(sExplodedLine[3]), 3);
				gA_Frames[style].Set(i, StringToFloat(sExplodedLine[4]), 4);
				gA_Frames[style].Set(i, (iStrings == 6)? StringToInt(sExplodedLine[5]):0, 5);
			}
		}

		gI_FrameCount[style] = gA_Frames[style].Length;

		delete fFile;

		return true;
	}

	return false;
}

bool SaveReplay(int style)
{
	if(!ReplayEnabled(style))
	{
		return false;
	}

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(FileExists(sPath))
	{
		DeleteFile(sPath);
	}

	int iSize = gA_Frames[style].Length;

	File fFile = OpenFile(sPath, "wb");
	fFile.WriteLine("%d:%s", iSize, REPLAY_FORMAT_V2);

	int iTickrate = RoundToZero(gF_Tickrate);
	int iArraySize = (iTickrate * 6);
	any[] aReplayData = new any[iArraySize];
	any[] aFrameData = new any[6];

	int iQueuedFrames = 0;

	for(int i = 0; i < iSize; iQueuedFrames = (++i % iTickrate))
	{
		gA_Frames[style].GetArray(i, aFrameData, 6);

		for(int x = 0; x < 6; x++)
		{
			aReplayData[((iQueuedFrames * 6) + x)] = aFrameData[x];
		}

		if(i == (iSize - 1) || (iQueuedFrames + 1) == iTickrate)
		{
			fFile.Write(aReplayData, (iQueuedFrames * 6), 4);
		}
	}

	delete fFile;

	gI_FrameCount[style] = iSize;

	return true;
}

bool DeleteReplay(int style)
{
	if(!ReplayEnabled(style))
	{
		return false;
	}

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(!FileExists(sPath) || !DeleteFile(sPath))
	{
		return false;
	}

	if(gB_CentralBot && gA_CentralCache[iCentralStyle] == style)
	{
		StopCentralReplay(0);
	}

	gA_Frames[style].Clear();
	gI_FrameCount[style] = 0;
	gI_ReplayTick[style] = -1;

	if(gI_ReplayBotClient[style] != 0)
	{
		UpdateReplayInfo(gI_ReplayBotClient[style], style, 0.0);
	}

	return true;
}

public void OnClientPutInServer(int client)
{
	if(IsClientSourceTV(client))
	{
		return;
	}

	if(!IsFakeClient(client))
	{
		gA_PlayerFrames[client] = new ArrayList(6);
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

					UpdateReplayInfo(client, i, -1.0);

					break;
				}
			}
		}

		else if(gA_CentralCache[iCentralClient] == -1)
		{
			UpdateReplayInfo(client, 0, 0.0);
			gA_CentralCache[iCentralClient] = client;
		}
	}
}

void FormatStyle(const char[] source, int style, bool central, float time, char[] dest, int size)
{
	float fWRTime = 0.0;
	Shavit_GetWRTime(style, fWRTime);

	char[] sTime = new char[16];
	FormatSeconds((time == -1.0)? fWRTime:time, sTime, 16);

	char[] sName = new char[MAX_NAME_LENGTH];
	Shavit_GetWRName(style, sName, MAX_NAME_LENGTH);
	
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

	strcopy(dest, size, temp);
}

void UpdateReplayInfo(int client, int style, float time)
{
	if(!gB_Enabled || !IsValidClient(client) || !IsFakeClient(client))
	{
		return;
	}

	SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);

	bool central = (gA_CentralCache[iCentralClient] == client);
	bool idle = (central && gA_CentralCache[iCentralReplayStatus] == Replay_Idle);

	char[] sTag = new char[MAX_NAME_LENGTH];
	FormatStyle(gS_ReplayStrings[sReplayClanTag], style, central, time, sTag, MAX_NAME_LENGTH);
	CS_SetClientClanTag(client, sTag);

	char[] sName = new char[MAX_NAME_LENGTH];
	
	if(central || gI_FrameCount[style] > 0)
	{
		FormatStyle(gS_ReplayStrings[(idle)? sReplayCentralName:sReplayNameStyle], style, central, time, sName, MAX_NAME_LENGTH);
	}

	else
	{
		FormatStyle(gS_ReplayStrings[sReplayUnloaded], style, central, time, sName, MAX_NAME_LENGTH);
	}

	gB_HideNameChange = true;
	SetClientName(client, sName);

	int iScore = (gI_FrameCount[style] > 0 || client == gA_CentralCache[iCentralClient])? 2000:-2000;

	if(gEV_Type == Engine_CSGO)
	{
		CS_SetClientContributionScore(client, iScore);
	}

	else
	{
		SetEntProp(client, Prop_Data, "m_iFrags", iScore);
	}

	SetEntProp(client, Prop_Data, "m_iDeaths", 0);

	gB_DontCallTimer = true;

	if(!gB_CentralBot && gI_FrameCount[style] == 0)
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
			CS_RespawnPlayer(client);
		}

		if(GetPlayerWeaponSlot(client, CS_SLOT_KNIFE) == -1)
		{
			GivePlayerItem(client, "weapon_knife");
		}
	}

	if(gI_DefaultTeamSlots >= gI_Styles && GetClientTeam(client) != gI_DefaultTeam)
	{
		CS_SwitchTeam(client, gI_DefaultTeam);
	}
}

public void OnClientDisconnect(int client)
{
	if(!IsFakeClient(client))
	{
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

public void Shavit_OnFinish(int client, int style, float time)
{
	float fWRTime = 0.0;
	Shavit_GetWRTime(style, fWRTime);

	if(!gB_Enabled || !ReplayEnabled(style) || (fWRTime > 0.0 && time > fWRTime))
	{
		ClearFrames(client);
	}

	gB_Record[client] = false;
}

public void Shavit_OnWorldRecord(int client, int style, float time)
{
	if(gI_PlayerFrames[client] == 0)
	{
		return;
	}

	if(!gB_Enabled || (gF_TimeLimit > 0.0 && time > gF_TimeLimit))
	{
		ClearFrames(client);

		return;
	}

	gA_Frames[style] = gA_PlayerFrames[client].Clone();
	ClearFrames(client);

	SaveReplay(style);

	if(ReplayEnabled(style) && !gB_CentralBot && gI_ReplayBotClient[style] != 0)
	{
		if(gB_CentralBot && gA_CentralCache[iCentralStyle] == style)
		{
			StopCentralReplay(0);
		}

		else if(gI_ReplayBotClient[style] != 0)
		{
			UpdateReplayInfo(gI_ReplayBotClient[style], style, time);
			CS_RespawnPlayer(gI_ReplayBotClient[style]);

			gRS_ReplayStatus[style] = Replay_Running;
			gI_ReplayTick[style] = 0;

			float vecPosition[3];
			vecPosition[0] = gA_Frames[style].Get(0, 0);
			vecPosition[1] = gA_Frames[style].Get(0, 1);
			vecPosition[2] = gA_Frames[style].Get(0, 2);

			TeleportEntity(gI_ReplayBotClient[style], vecPosition, NULL_VECTOR, NULL_VECTOR);
		}
	}
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

	int iReplayBotStyle = GetReplayStyle(client);

	if(iReplayBotStyle != -1 && ReplayEnabled(iReplayBotStyle))
	{
		buttons = 0;

		if(gA_Frames[iReplayBotStyle] == null || gI_FrameCount[iReplayBotStyle] <= 0) // if no replay is loaded
		{
			return Plugin_Changed;
		}

		if(gI_ReplayTick[iReplayBotStyle] != -1 && gI_FrameCount[iReplayBotStyle] >= 1)
		{
			float vecPosition[3];
			float vecAngles[3];

			if(gRS_ReplayStatus[iReplayBotStyle] != Replay_Running)
			{
				int iFrame = (gRS_ReplayStatus[iReplayBotStyle] == Replay_Start)? 0:(gI_FrameCount[iReplayBotStyle] - 1);

				vecPosition[0] = gA_Frames[iReplayBotStyle].Get(iFrame, 0);
				vecPosition[1] = gA_Frames[iReplayBotStyle].Get(iFrame, 1);
				vecPosition[2] = gA_Frames[iReplayBotStyle].Get(iFrame, 2);

				vecAngles[0] = gA_Frames[iReplayBotStyle].Get(iFrame, 3);
				vecAngles[1] = gA_Frames[iReplayBotStyle].Get(iFrame, 4);

				TeleportEntity(client, vecPosition, vecAngles, view_as<float>({0.0, 0.0, 0.0}));

				return Plugin_Changed;
			}

			if(++gI_ReplayTick[iReplayBotStyle] >= gI_FrameCount[iReplayBotStyle])
			{
				gI_ReplayTick[iReplayBotStyle] = 0;
				gRS_ReplayStatus[iReplayBotStyle] = gA_CentralCache[iCentralReplayStatus] = Replay_End;

				CreateTimer((gF_ReplayDelay / 2.0), EndReplay, iReplayBotStyle, TIMER_FLAG_NO_MAPCHANGE);

				SetEntityMoveType(client, MOVETYPE_NONE);

				return Plugin_Changed;
			}

			if(gI_ReplayTick[iReplayBotStyle] == 1)
			{
				gF_StartTick[iReplayBotStyle] = GetEngineTime();
			}

			SetEntityMoveType(client, ((GetEntityFlags(client) & FL_ONGROUND) > 0)? MOVETYPE_WALK:MOVETYPE_NOCLIP);

			vecPosition[0] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 0);
			vecPosition[1] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 1);
			vecPosition[2] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 2);

			vecAngles[0] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 3);
			vecAngles[1] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 4);

			buttons = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 5);

			float vecVelocity[3];
			MakeVectorFromPoints(vecCurrentPosition, vecPosition, vecVelocity);
			ScaleVector(vecVelocity, gF_Tickrate);

			float fDistance = GetVectorDistance(vecCurrentPosition, vecPosition);

			if((gI_ReplayTick[iReplayBotStyle] % RoundToFloor(gF_Tickrate * 1.5)) == 0 && GetVectorLength(vecVelocity) < 2.0 * fDistance)
			{
				TeleportEntity(client, vecPosition, vecAngles, vecVelocity);
			}

			else
			{
				TeleportEntity(client, NULL_VECTOR, vecAngles, vecVelocity);
			}

			return Plugin_Changed;
		}
	}

	else
	{
		if(gB_Record[client] && ReplayEnabled(Shavit_GetBhopStyle(client)) && Shavit_GetTimerStatus(client) == Timer_Running)
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
	}

	return Plugin_Continue;
}

public Action EndReplay(Handle Timer, any data)
{
	gI_ReplayTick[data] = 0;

	if(gI_ReplayBotClient[data] != gA_CentralCache[iCentralClient])
	{
		gRS_ReplayStatus[data] = Replay_Start;

		CreateTimer((gF_ReplayDelay / 2.0), StartReplay, data, TIMER_FLAG_NO_MAPCHANGE);
	}

	else
	{
		gRS_ReplayStatus[data] = gA_CentralCache[iCentralReplayStatus] = Replay_Idle;
		gI_ReplayBotClient[data] = 0;
	}

	return Plugin_Stop;
}

public Action StartReplay(Handle Timer, any data)
{
	if(gRS_ReplayStatus[data] == Replay_Running)
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

	else
	{
		ClearFrames(client);
	}
}

public Action DelayedUpdate(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return Plugin_Stop;
	}

	UpdateReplayInfo(client, GetReplayStyle(client), -1.0);

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
				UpdateReplayInfo(client, style, -1.0);
			}
		}
	}
}

public void Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	gI_DefaultTeamSlots = 0;

	int iEntity = -1;

	while((iEntity = FindEntityByClassname(iEntity, (gI_DefaultTeam == 2)? "info_player_terrorist":"info_player_counterterrorist")) != INVALID_ENT_REFERENCE)
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
	}

	else
	{
		BfRead bfmsg = msg;
		bfmsg.ReadByte();
		bfmsg.ReadByte();
		bfmsg.ReadString(sMessage, 24, false);
	}

	if(StrEqual(sMessage, "#Cstrike_Name_Change"))
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

public void Shavit_OnWRDeleted(int style)
{
	if(gI_FrameCount[style] > 0)
	{
		DeleteReplay(style);
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
		if(!ReplayEnabled(i) || gI_FrameCount[i] == 0)
		{
			continue;
		}

		char[] sInfo = new char[4];
		IntToString(i, sInfo, 4);

		float time = 0.0;
		Shavit_GetWRTime(i, time);

		char[] sDisplay = new char[64];

		if(time > 0.0)
		{
			char[] sTime = new char[32];
			FormatSeconds(time, sTime, 32, false);

			FormatEx(sDisplay, 64, "%s - WR: %s", gS_StyleStrings[i][sStyleName], sTime);
		}

		else
		{
			strcopy(sDisplay, 64, gS_StyleStrings[i][sStyleName]);
		}

		menu.AddItem(sInfo, sDisplay);
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
		char[] sInfo = new char[4];
		char[] sMenuItem = new char[64];
		menu.GetItem(param2, sInfo, 4);
		int style = StringToInt(sInfo);

		if(style == -1)
		{
			return 0;
		}

		Menu submenu = new Menu(DeleteConfirmation_Callback);
		submenu.SetTitle("%T", "ReplayDeletionConfirmation", param1, gS_StyleStrings[style][sStyleName]);

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

		if(DeleteReplay(style))
		{
			LogAction(param1, param1, "Deleted replay for %s on map %s.", gS_StyleStrings[style][sStyleName], gS_Map);

			Shavit_PrintToChat(param1, "%T", "ReplayDeleted", param1, gS_ChatStrings[sMessageStyle], gS_StyleStrings[style][sStyleName], gS_ChatStrings[sMessageText]);
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
	menu.SetTitle("%T\n ", "CentralReplayTitle", client);

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

		float time = 0.0;
		Shavit_GetWRTime(i, time);

		char[] sDisplay = new char[64];

		if(time > 0.0)
		{
			char[] sTime = new char[32];
			FormatSeconds(time, sTime, 32, false);

			FormatEx(sDisplay, 64, "%s - WR: %s", gS_StyleStrings[i][sStyleName], sTime);
		}

		else
		{
			strcopy(sDisplay, 64, gS_StyleStrings[i][sStyleName]);
		}

		menu.AddItem(sInfo, sDisplay, (gI_FrameCount[i] > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "ERROR");
	}

	else if(menu.ItemCount <= ((gEV_Type == Engine_CSS)? 9:8))
	{
		menu.Pagination = MENU_NO_PAGINATION;
	}

	menu.ExitButton = true;
	menu.Display(client, 20);

	return Plugin_Handled;
}

public int MenuHandler_Replay(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		if(StrEqual(info, "stop"))
		{
			StopCentralReplay(param1);
			OpenReplayMenu(param1);

			return 0;
		}

		int style = StringToInt(info);

		if(style == -1 || !ReplayEnabled(style) || gI_FrameCount[style] == 0 || gA_CentralCache[iCentralClient] <= 0)
		{
			return 0;
		}

		if(gA_CentralCache[iCentralReplayStatus] != Replay_Idle)
		{
			Shavit_PrintToChat(param1, "%T", "CentralReplayPlaying", param1);

			OpenReplayMenu(param1);
		}

		else
		{
			gI_ReplayTick[style] = 0;
			gA_CentralCache[iCentralStyle] = style;
			gI_ReplayBotClient[style] = gA_CentralCache[iCentralClient];
			gRS_ReplayStatus[style] = gA_CentralCache[iCentralReplayStatus] = Replay_Start;
			TeleportToStart(gA_CentralCache[iCentralClient], style);

			float time = 0.0;
			Shavit_GetWRTime(gA_CentralCache[iCentralStyle], time);

			UpdateReplayInfo(gA_CentralCache[iCentralClient], style, time);

			CreateTimer((gF_ReplayDelay / 2.0), StartReplay, style, TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void TeleportToStart(int client, int style)
{
	if(gI_FrameCount[style] == 0)
	{
		return;
	}

	float vecPosition[3];
	vecPosition[0] = gA_Frames[style].Get(0, 0);
	vecPosition[1] = gA_Frames[style].Get(0, 1);
	vecPosition[2] = gA_Frames[style].Get(0, 2);

	float vecAngles[3];
	vecAngles[0] = gA_Frames[style].Get(0, 3);
	vecAngles[1] = gA_Frames[style].Get(0, 4);

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
	TeleportToStart(gA_CentralCache[iCentralClient], style);
	gA_CentralCache[iCentralStyle] = 0;

	UpdateReplayInfo(client, 0, 0.0);
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
