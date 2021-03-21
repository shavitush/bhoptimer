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
#include <convar_class>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <adminmenu>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#include <tf2>
#include <tf2_stocks>

//#include <TickRateControl>
forward void TickRate_OnTickRateChanged(float fOld, float fNew);

#define REPLAY_FORMAT_V2 "{SHAVITREPLAYFORMAT}{V2}"
#define REPLAY_FORMAT_FINAL "{SHAVITREPLAYFORMAT}{FINAL}"
#define REPLAY_FORMAT_SUBVERSION 0x04
#define FRAMES_PER_WRITE 100 // amounts of frames to write per read/write call
#define MAX_LOOPING_BOT_CONFIGS 24
#define HACKY_CLIENT_IDX_PROP "m_iTeamNum" // I store the client owner idx in this for Replay_Prop. My brain is too powerful.

// #define DEBUG

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 2621440

enum struct replaystrings_t
{
	char sClanTag[MAX_NAME_LENGTH];
	char sNameStyle[MAX_NAME_LENGTH];
	char sCentralName[MAX_NAME_LENGTH];
	char sCentralStyle[MAX_NAME_LENGTH];
	char sCentralStyleTag[MAX_NAME_LENGTH];
	char sUnloaded[MAX_NAME_LENGTH];
}

enum struct loopingbot_config_t
{
	bool bEnabled;
	int iTrackMask; // only 9 bits needed for tracks
	int aStyleMask[8]; // all 256 bits needed for enabled styles
	//bool bActive.... or something TODO;
	char sName[MAX_NAME_LENGTH];
}

enum struct bot_info_t
{
	int iEnt;
	int iStyle; // Shavit_GetReplayBotStyle
	ReplayStatus iStatus; // Shavit_GetReplayStatus
	ReplayBotType iType; // Shavit_GetReplayBotType
	int iTrack; // Shavit_GetReplayBotTrack
	int iStarterSerial; // Shavit_GetReplayStarter
	int iTick; // Shavit_GetReplayBotCurrentFrame
	int iLoopingConfig;
	Handle hTimer;
	float fStartTick; // Shavit_GetReplayBotFirstFrame
	bool bCustomFrames;
	framecache_t aCache;
}

enum
{
	iBotShooting_Attack1 = (1 << 0),
	iBotShooting_Attack2 = (1 << 1)
}

// custom cvar settings
char gS_ForcedCvars[][][] =
{
	{ "bot_quota", "{expected_bots}" },
	{ "tf_bot_quota", "{expected_bots}" },
	{ "bot_stop", "1" },
	{ "bot_quota_mode", "normal" },
	{ "tf_bot_quota_mode", "normal" },
	{ "mp_limitteams", "0" },
	{ "bot_join_after_player", "0" },
	{ "tf_bot_join_after_player", "0" },
	{ "bot_chatter", "off" },
	{ "bot_flipout", "1" },
	{ "bot_zombie", "1" },
	{ "mp_autoteambalance", "0" },
	{ "bot_controllable", "0" }
};

// game type
EngineVersion gEV_Type = Engine_Unknown;

// cache
char gS_ReplayFolder[PLATFORM_MAX_PATH];

framecache_t gA_FrameCache[STYLE_LIMIT][TRACKS_SIZE];

bool gB_Button[MAXPLAYERS+1];
int gI_PlayerFrames[MAXPLAYERS+1];
int gI_PlayerPrerunFrames[MAXPLAYERS+1];
int gI_PlayerTimerStartFrames[MAXPLAYERS+1];
bool gB_ClearFrame[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];
int gI_MenuTrack[MAXPLAYERS+1];
int gI_MenuStyle[MAXPLAYERS+1];
ReplayBotType gI_MenuType[MAXPLAYERS+1];
float gF_LastInteraction[MAXPLAYERS+1];
float gF_NextFrameTime[MAXPLAYERS+1];

float gF_TimeDifference[MAXPLAYERS+1];
int   gI_TimeDifferenceStyle[MAXPLAYERS+1];
float gF_VelocityDifference2D[MAXPLAYERS+1];
float gF_VelocityDifference3D[MAXPLAYERS+1];

bool gB_Late = false;

// forwards
Handle gH_OnReplayStart = null;
Handle gH_OnReplayEnd = null;
Handle gH_OnReplaysLoaded = null;
Handle gH_ShouldSaveReplayCopy = null;
Handle gH_OnReplaySaved = null;

// server specific
float gF_Tickrate = 0.0;
char gS_Map[160];
int gI_ExpectedBots = 0;

// replay bot stuff
int gI_CentralBot = -1;
loopingbot_config_t gA_LoopingBotConfig[MAX_LOOPING_BOT_CONFIGS];
ArrayList gA_BotEvents = null; // shitty fifo pipe
int gI_DynamicBots = 0;
// Replay_Prop: index with starter/watcher
// Replay_ANYTHINGELSE: index with fakeclient index
bot_info_t gA_BotInfo[MAXPLAYERS+1]; 

// how do i call this
bool gB_HideNameChange = false;
//bool gB_DontCallTimer = false;
bool gB_HijackFrame[MAXPLAYERS+1];
float gF_HijackedAngles[MAXPLAYERS+1][2];

// plugin cvars
Convar gCV_Enabled = null;
Convar gCV_ReplayDelay = null;
Convar gCV_TimeLimit = null;
Convar gCV_DefaultTeam = null;
Convar gCV_CentralBot = null;
Convar gCV_DynamicBotLimit = null;
Convar gCV_AllowPropBots = null;
Convar gCV_BotShooting = null;
Convar gCV_BotPlusUse = null;
Convar gCV_BotWeapon = null;
Convar gCV_PlaybackCanStop = null;
Convar gCV_PlaybackCooldown = null;
Convar gCV_PlaybackPreRunTime = null;
Convar gCV_ClearPreRun = null;
Convar gCV_DynamicTimeSearch = null;
Convar gCV_DynamicTimeCheap = null;
Convar gCV_DynamicTimeTick = null;
ConVar gCV_EnableDynamicTimeDifference = null;
ConVar gCV_BotQuota = null;

// timer settings
int gI_Styles = 0;
stylestrings_t gS_StyleStrings[STYLE_LIMIT];

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
	CreateNative("Shavit_DeleteReplay", Native_DeleteReplay);
	CreateNative("Shavit_GetReplayBotCurrentFrame", Native_GetReplayBotCurrentFrame);
	CreateNative("Shavit_GetClientFrameCount", Native_GetClientFrameCount);
	CreateNative("Shavit_GetReplayBotFirstFrame", Native_GetReplayBotFirstFrame);
	CreateNative("Shavit_GetReplayBotIndex", Native_GetReplayBotIndex);
	CreateNative("Shavit_GetReplayBotStyle", Native_GetReplayBotStyle);
	CreateNative("Shavit_GetReplayBotTrack", Native_GetReplayBotTrack);
	CreateNative("Shavit_GetReplayBotType", Native_GetReplayBotType);
	CreateNative("Shavit_GetReplayStarter", Native_GetReplayStarter);
	CreateNative("Shavit_GetReplayButtons", Native_GetReplayButtons);
	CreateNative("Shavit_GetReplayData", Native_GetReplayData);
	CreateNative("Shavit_GetReplayFrames", Native_GetReplayFrames);
	CreateNative("Shavit_GetReplayFrameCount", Native_GetReplayFrameCount);
	CreateNative("Shavit_GetReplayLength", Native_GetReplayLength);
	CreateNative("Shavit_GetReplayName", Native_GetReplayName);
	CreateNative("Shavit_GetReplayStatus", Native_GetReplayStatus);
	CreateNative("Shavit_GetReplayTime", Native_GetReplayTime);
	CreateNative("Shavit_HijackAngles", Native_HijackAngles);
	CreateNative("Shavit_IsReplayDataLoaded", Native_IsReplayDataLoaded);
	CreateNative("Shavit_IsReplayEntity", Native_IsReplayEntity);
	CreateNative("Shavit_StartReplay", Native_StartReplay);
	CreateNative("Shavit_ReloadReplay", Native_ReloadReplay);
	CreateNative("Shavit_ReloadReplays", Native_ReloadReplays);
	CreateNative("Shavit_Replay_DeleteMap", Native_Replay_DeleteMap);
	CreateNative("Shavit_SetReplayData", Native_SetReplayData);
	CreateNative("Shavit_GetPlayerPreFrame", Native_GetPreFrame);
	CreateNative("Shavit_SetPlayerPreFrame", Native_SetPreFrame);
	CreateNative("Shavit_SetPlayerTimerFrame", Native_SetTimerFrame);
	CreateNative("Shavit_GetPlayerTimerFrame", Native_GetTimerFrame);
	CreateNative("Shavit_GetClosestReplayTime", Native_GetClosestReplayTime);
	CreateNative("Shavit_GetClosestReplayStyle", Native_GetClosestReplayStyle);
	CreateNative("Shavit_SetClosestReplayStyle", Native_SetClosestReplayStyle);
	CreateNative("Shavit_GetClosestReplayVelocityDifference", Native_GetClosestReplayVelocityDifference);
	//CreateNative("Shavit_StartReplayFromFrameCache", Native_StartReplayFromFrameCache);
	//CreateNative("Shavit_StartReplayFromFile", Native_StartReplayFromFile);

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

	// admin menu
	if(LibraryExists("adminmenu") && ((gH_AdminMenu = GetAdminTopMenu()) != null))
	{
		OnAdminMenuReady(gH_AdminMenu);
	}

	// I don't like doing this
	gCV_EnableDynamicTimeDifference = FindConVar("shavit_hud_timedifference");
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-replay.phrases");

	// forwards
	gH_OnReplayStart = CreateGlobalForward("Shavit_OnReplayStart", ET_Event, Param_Cell, Param_Cell);
	gH_OnReplayEnd = CreateGlobalForward("Shavit_OnReplayEnd", ET_Event, Param_Cell, Param_Cell);
	gH_OnReplaysLoaded = CreateGlobalForward("Shavit_OnReplaysLoaded", ET_Event);
	gH_ShouldSaveReplayCopy = CreateGlobalForward("Shavit_ShouldSaveReplayCopy", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnReplaySaved = CreateGlobalForward("Shavit_OnReplaySaved", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_String);

	// game specific
	gEV_Type = GetEngineVersion();
	gF_Tickrate = (1.0 / GetTickInterval());

	gCV_BotQuota = FindConVar((gEV_Type != Engine_TF2)? "bot_quota":"tf_bot_quota");
	gCV_BotQuota.Flags &= ~FCVAR_NOTIFY;
	FindConVar("bot_stop").Flags &= ~FCVAR_CHEAT;
	gA_BotEvents = new ArrayList(sizeof(bot_info_t));

	for(int i = 0; i < sizeof(gS_ForcedCvars); i++)
	{
		ConVar hCvar = FindConVar(gS_ForcedCvars[i][0]);

		if(hCvar != null)
		{
			if(StrEqual(gS_ForcedCvars[i][1], "{expected_bots}"))
			{
				UpdateBotQuota(0);
			}
			else
			{
				hCvar.SetString(gS_ForcedCvars[i][1]);
			}

			hCvar.AddChangeHook(OnForcedConVarChanged);
		}
	}

	// late load
	for(int i = 1; i <= MaxClients; i++)
	{
		ClearBotInfo(gA_BotInfo[i]);

		if(IsValidClient(i) && !IsFakeClient(i))
		{
			OnClientPutInServer(i);
		}
	}

	// plugin convars
	gCV_Enabled = new Convar("shavit_replay_enabled", "1", "Enable replay bot functionality?", 0, true, 0.0, true, 1.0);
	gCV_ReplayDelay = new Convar("shavit_replay_delay", "5.0", "Time to wait before restarting the replay after it finishes playing.", 0, true, 0.0, true, 10.0);
	gCV_TimeLimit = new Convar("shavit_replay_timelimit", "7200.0", "Maximum amount of time (in seconds) to allow saving to disk.\nDefault is 7200 (2 hours)\n0 - Disabled");
	gCV_DefaultTeam = new Convar("shavit_replay_defaultteam", "3", "Default team to make the bots join, if possible.\n2 - Terrorists/RED\n3 - Counter Terrorists/BLU", 0, true, 2.0, true, 3.0);
	gCV_CentralBot = new Convar("shavit_replay_centralbot", "1", "Have one central bot instead of one bot per replay.\nTriggered with !replay.\nRestart the map for changes to take effect.\nThe disabled setting is not supported - use at your own risk.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_DynamicBotLimit = new Convar("shavit_replay_dynamicbotlimit", "3", "How many extra bots next to the central bot can be spawned with !replay.\n0 - no dynamically spawning bots.", 0, true, 0.0, true, float(MaxClients-2));
	gCV_AllowPropBots = new Convar("shavit_replay_allowpropbots", "1", "Should players be able to view replays through a prop instead of a bot?", 0, true, 0.0, true, 1.0);
	gCV_BotShooting = new Convar("shavit_replay_botshooting", "3", "Attacking buttons to allow for bots.\n0 - none\n1 - +attack\n2 - +attack2\n3 - both", 0, true, 0.0, true, 3.0);
	gCV_BotPlusUse = new Convar("shavit_replay_botplususe", "1", "Allow bots to use +use?", 0, true, 0.0, true, 1.0);
	gCV_BotWeapon = new Convar("shavit_replay_botweapon", "", "Choose which weapon the bot will hold.\nLeave empty to use the default.\nSet to \"none\" to have none.\nExample: weapon_usp");
	gCV_PlaybackCanStop = new Convar("shavit_replay_pbcanstop", "1", "Allow players to stop playback if they requested it?", 0, true, 0.0, true, 1.0);
	gCV_PlaybackCooldown = new Convar("shavit_replay_pbcooldown", "10.0", "Cooldown in seconds to apply for players between each playback they request/stop.\nDoes not apply to RCON admins.", 0, true, 0.0);
	gCV_PlaybackPreRunTime = new Convar("shavit_replay_preruntime", "1.0", "Time (in seconds) to record before a player leaves start zone. (The value should NOT be too high)", 0, true, 0.0);
	gCV_ClearPreRun = new Convar("shavit_replay_prerun_always", "1", "Record prerun frames outside the start zone?", 0, true, 0.0, true, 1.0);
	gCV_DynamicTimeCheap = new Convar("shavit_replay_timedifference_cheap", "0.0", "0 - Disabled\n1 - only clip the search ahead to shavit_replay_timedifference_search\n2 - only clip the search behind to players current frame\n3 - clip the search to +/- shavit_replay_timedifference_search seconds to the players current frame", 0, true, 0.0, true, 3.0);
	gCV_DynamicTimeSearch = new Convar("shavit_replay_timedifference_search", "0.0", "Time in seconds to search the players current frame for dynamic time differences\n0 - Full Scan\nNote: Higher values will result in worse performance", 0, true, 0.0);

	char tenth[6];
	IntToString(RoundToFloor(1.0 / GetTickInterval() / 10), tenth, sizeof(tenth));
	gCV_DynamicTimeTick = new Convar("shavit_replay_timedifference_tick", tenth, "How often (in ticks) should the time difference update.\nYou should probably keep this around 0.1s worth of ticks.\nThe maximum value is your tickrate.", 0, true, 1.0, true, (1.0 / GetTickInterval()));

	gCV_CentralBot.AddChangeHook(OnConVarChanged);
	gCV_DynamicBotLimit.AddChangeHook(OnConVarChanged);
	gCV_AllowPropBots.AddChangeHook(OnConVarChanged);

	Convar.AutoExecConfig();

	// hooks
	HookEvent("player_spawn", Player_Event, EventHookMode_Pre);
	HookEvent("player_death", Player_Event, EventHookMode_Pre);
	HookEvent("player_connect", BotEvents, EventHookMode_Pre);
	HookEvent("player_disconnect", BotEvents, EventHookMode_Pre);
	HookEventEx("player_connect_client", BotEvents, EventHookMode_Pre);
	// The spam from this one is really bad.: "\"%s<%i><%s><%s>\" changed name to \"%s\"\n"
	HookEvent("player_changename", BotEventsStopLogSpam, EventHookMode_Pre);
	// "\"%s<%i><%s><%s>\" joined team \"%s\"\n"
	HookEvent("player_team", BotEventsStopLogSpam, EventHookMode_Pre);
	// "\"%s<%i><%s><>\" entered the game\n"
	HookEvent("player_activate", BotEventsStopLogSpam, EventHookMode_Pre);

	// name change suppression
	HookUserMessage(GetUserMessageId("SayText2"), Hook_SayText2, true);

	// commands
	RegAdminCmd("sm_deletereplay", Command_DeleteReplay, ADMFLAG_RCON, "Open replay deletion menu.");
	RegConsoleCmd("sm_replay", Command_Replay, "Opens the central bot menu. For admins: 'sm_replay stop' to stop the playback.");

	// database
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = GetTimerDatabaseHandle();
}

public void OnPluginEnd()
{
	KickAllReplays();
}

void KickAllReplays()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidEntity(gA_BotInfo[i].iEnt))
		{
			KickReplay(gA_BotInfo[i]);
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "adminmenu") == 0)
	{
		if ((gH_AdminMenu = GetAdminTopMenu()) != null)
		{
			OnAdminMenuReady(gH_AdminMenu);
		}
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "adminmenu") == 0)
	{
		gH_AdminMenu = null;
		gH_TimerCommands = INVALID_TOPMENUOBJECT;
	}
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	OnMapStart();
}

void UpdateBotQuota(int quota)
{
	gCV_BotQuota.IntValue = gI_ExpectedBots = quota;
}

public void OnForcedConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char sName[32];
	convar.GetName(sName, 32);

	for(int i = 0; i < sizeof(gS_ForcedCvars); i++)
	{
		if(StrEqual(sName, gS_ForcedCvars[i][0]))
		{
			if(StrEqual(gS_ForcedCvars[i][1], "{expected_bots}"))
			{
				convar.IntValue = gI_ExpectedBots;
			}
			else if(!StrEqual(newValue, gS_ForcedCvars[i][1]))
			{
				convar.SetString(gS_ForcedCvars[i][1]);
			}

			break;
		}
	}
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

void FinishReplay(bot_info_t info, int stopper = -1)
{
	if (info.iType == Replay_Dynamic || info.iType == Replay_Prop)
	{
		KickReplay(info, stopper);
	}
	else if (info.iType == Replay_Looping)
	{
		int nexttrack = info.iTrack;
		int nextstyle = info.iStyle;
		bool hasFrames = FindNextLoop(nexttrack, nextstyle, info.iLoopingConfig);

		if (hasFrames)
		{
			StartReplay(info, nexttrack, nextstyle, stopper, gCV_ReplayDelay.FloatValue);
		}
		else
		{
			KickReplay(info, stopper);
		}
	}
	else if (info.iType == Replay_Central)
	{
		if (info.aCache.aFrames != null)
		{
			TeleportToStart(info);
		}

		ClearBotInfo(info);
	}
}

void StopOrRestartBots(int style, int track, bool restart)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (gA_BotInfo[i].iEnt <= 0 || gA_BotInfo[i].iTrack != track || gA_BotInfo[i].iStyle != style || gA_BotInfo[i].bCustomFrames)
		{
			continue;
		}

		CancelReplay(gA_BotInfo[i], 0, false);

		if (restart)
		{
			StartReplay(gA_BotInfo[i], track, style, GetClientFromSerial(gA_BotInfo[i].iStarterSerial), gCV_ReplayDelay.FloatValue);
		}
		else
		{
			FinishReplay(gA_BotInfo[i]);
		}
	}
}

bool UnloadReplay(int style, int track, bool reload, bool restart, const char[] path = "")
{
	delete gA_FrameCache[style][track].aFrames;
	gA_FrameCache[style][track].iFrameCount = 0;
	gA_FrameCache[style][track].fTime = 0.0;
	gA_FrameCache[style][track].bNewFormat = true;
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, "invalid");
	gA_FrameCache[style][track].iPreFrames = 0;

	bool loaded = false;

	if (reload)
	{
		if(strlen(path) > 0)
		{
			loaded = LoadReplay(style, track, path);
		}
		else
		{
			loaded = DefaultLoadReplay(style, track);
		}
	}

	StopOrRestartBots(style, track, restart);

	return loaded;
}

public int Native_DeleteReplay(Handle handler, int numParams)
{
	char sMap[160];
	GetNativeString(1, sMap, 160);

	int iStyle = GetNativeCell(2);
	int iTrack = GetNativeCell(3);
	int iSteamID = GetNativeCell(4);

	return DeleteReplay(iStyle, iTrack, iSteamID, sMap);
}

public int Native_GetReplayBotFirstFrame(Handle handler, int numParams)
{
	return view_as<int>(gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].fStartTick);
}

public int Native_GetReplayBotCurrentFrame(Handle handler, int numParams)
{
	return gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].iTick;
}

public int Native_GetReplayBotIndex(Handle handler, int numParams)
{
	int track = GetNativeCell(1);
	int style = GetNativeCell(2);

	if ((track == -1 || style == -1) && gI_CentralBot > 0)
	{
		return gI_CentralBot;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (gA_BotInfo[i].iEnt >= 1)
		{
			if ((track == -1 || gA_BotInfo[i].iTrack == track) && (style == -1 || gA_BotInfo[i].iStyle == style))
			{
				return gA_BotInfo[i].iEnt;
			}
		}
	}

	return -1;
}

public int Native_IsReplayDataLoaded(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	return view_as<int>(ReplayEnabled(style) && gA_FrameCache[style][track].iFrameCount > 0);
}

void StartReplay(bot_info_t info, int track, int style, int starter, float delay, bool customFrames = false)
{
	if (starter > 0)
	{
		gF_LastInteraction[starter] = GetEngineTime();
	}

	//info.iEnt;
	info.iStyle = style;
	info.iStatus = Replay_Start;
	//info.iType
	info.iTrack = track;
	info.iStarterSerial = (starter > 0) ? GetClientSerial(starter) : 0;
	info.iTick = 0;
	//info.iLoopingConfig
	info.hTimer = CreateTimer((delay / 2.0), Timer_StartReplay, info.iEnt, TIMER_FLAG_NO_MAPCHANGE);
	info.bCustomFrames = customFrames;

	if (!customFrames)
	{
		info.aCache = gA_FrameCache[style][track];
		info.aCache.aFrames = view_as<ArrayList>(CloneHandle(info.aCache.aFrames));
	}

	TeleportToStart(info);
	UpdateReplayClient(info.iEnt);
}

public int Native_IsReplayEntity(Handle handler, int numParams)
{
	int ent = GetNativeCell(1);
	return (gA_BotInfo[GetBotInfoIndex(ent)].iEnt == ent);
}

public int Native_StartReplay(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	float delay = GetNativeCell(3);
	int client = GetNativeCell(4);
	int bot = GetNativeCell(5);
	ReplayBotType type = view_as<ReplayBotType>(GetNativeCell(6));
	bool ignorelimit = view_as<bool>(GetNativeCell(7));

	if(gA_FrameCache[style][track].iFrameCount == 0)
	{
		return 0;
	}

	if (bot == -1)
	{
		if (type == Replay_Prop && IsValidClient(client))
		{
			int ent = CreateReplayProp(client);

			if (!IsValidEntity(ent))
			{
				return 0;
			}

			StartReplay(gA_BotInfo[client], gI_MenuTrack[client], gI_MenuStyle[client], client, gCV_ReplayDelay.FloatValue);
		}
		else if (type == Replay_Dynamic)
		{
			if (!ignorelimit)
			{
				if (gCV_DynamicBotLimit.IntValue < 1 || gI_DynamicBots >= gCV_DynamicBotLimit.IntValue)
				{
					return 0;
				}

				++gI_DynamicBots;
			}

			bot_info_t info;
			info.iType = Replay_Dynamic;
			info.iStyle = style;
			info.iTrack = track;
			info.iStarterSerial = (client > 0) ? GetClientFromSerial(client) : 0;
			QueueAddReplayBot(info);
		}
	}
	else
	{
		int index = GetBotInfoIndex(bot);
		type = gA_BotInfo[index].iType;

		if (type != Replay_Central && type != Replay_Dynamic && type != Replay_Prop)
		{
			return 0;
		}

		if (gA_BotInfo[index].iStatus != Replay_Idle)
		{
			CancelReplay(gA_BotInfo[index], 0, false);
		}

		StartReplay(gA_BotInfo[index], track, style, client, delay);
	}

	return 1;
}

public int Native_ReloadReplay(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	bool restart = view_as<bool>(GetNativeCell(3));

	char path[PLATFORM_MAX_PATH];
	GetNativeString(4, path, PLATFORM_MAX_PATH);

	return UnloadReplay(style, track, true, restart, path);
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

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			if(UnloadReplay(i, j, true, restart, ""))
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
	gA_PlayerFrames[client] = view_as<ArrayList>(GetNativeCell(2)).Clone();
	gI_PlayerFrames[client] = gA_PlayerFrames[client].Length;
}

public int Native_GetReplayData(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	ArrayList frames = null;

	if(gA_PlayerFrames[client] != null)
	{
		frames = gA_PlayerFrames[client].Clone();
	}

	return view_as<int>(frames);
}

public int Native_GetReplayFrames(Handle handler, int numParams)
{
	int track = GetNativeCell(1);
	int style = GetNativeCell(2);
	ArrayList frames = null;

	if(gA_FrameCache[style][track].aFrames != null)
	{
		frames = gA_FrameCache[style][track].aFrames.Clone();
	}

	return view_as<int>(frames);
}

// TODO: Add a native that'd return the frame count of a replay bot... because custom frames...
public int Native_GetReplayFrameCount(Handle handler, int numParams)
{
	return gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].iFrameCount;
}

public int Native_GetClientFrameCount(Handle handler, int numParams)
{
	return gA_PlayerFrames[GetNativeCell(1)].Length;
}

// TODO: Add a native that'd return the replay length of a replay bot... because custom frames...
public int Native_GetReplayLength(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	return view_as<int>(GetReplayLength(style, track, gA_FrameCache[style][track]));
}

// TODO: Add a native that'd return the replay name of a replay bot... because custom frames...
public int Native_GetReplayName(Handle handler, int numParams)
{
	return SetNativeString(3, gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].sReplayName, GetNativeCell(4));
}

public int Native_GetReplayStatus(Handle handler, int numParams)
{
	return view_as<int>(gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].iStatus);
}

public any Native_GetReplayTime(Handle handler, int numParams)
{
	int index = GetBotInfoIndex(GetNativeCell(1));
	return float(gA_BotInfo[index].iTick - gA_BotInfo[index].aCache.iPreFrames) / gF_Tickrate * Shavit_GetStyleSettingFloat(gA_BotInfo[index].iStyle, "speed");
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
	return gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].iStyle;
}

public int Native_GetReplayBotTrack(Handle handler, int numParams)
{
	return gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].iTrack;
}

public int Native_GetReplayBotType(Handle handler, int numParams)
{
	return view_as<int>(gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].iType);
}

public int Native_GetReplayStarter(Handle handler, int numParams)
{
	int starter = gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].iStarterSerial;
	return (starter > 0) ? GetClientFromSerial(starter) : 0;
}

public int Native_GetReplayButtons(Handle handler, int numParams)
{
	int bot = GetBotInfoIndex(GetNativeCell(1));

	if (gA_BotInfo[bot].iStatus != Replay_Running)
	{
		return 0;
	}

	frame_t aFrame;
	gA_BotInfo[bot].aCache.aFrames.GetArray(gA_BotInfo[bot].iTick, aFrame, 6);
	return aFrame.buttons;
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

		for(int j = 0; j < TRACKS_SIZE; j++)
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

public int Native_GetPreFrame(Handle handler, int numParams)
{
	return gI_PlayerPrerunFrames[GetNativeCell(1)];
}

public int Native_GetTimerFrame(Handle handler, int numParams)
{
	return gI_PlayerTimerStartFrames[GetNativeCell(1)];
}

public int Native_SetPreFrame(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int preframes = GetNativeCell(2);

	gI_PlayerPrerunFrames[client] = preframes;
}

public int Native_SetTimerFrame(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int timerframes = GetNativeCell(2);

	gI_PlayerTimerStartFrames[client] = timerframes;
}

public int Native_GetClosestReplayTime(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return view_as<int>(gF_TimeDifference[client]);
}

public int Native_GetClosestReplayVelocityDifference(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (view_as<bool>(GetNativeCell(2)))
	{
		return view_as<int>(gF_VelocityDifference3D[client]);
	}
	else
	{
		return view_as<int>(gF_VelocityDifference2D[client]);
	}
}

public int Native_GetClosestReplayStyle(Handle plugin, int numParams)
{
	return gI_TimeDifferenceStyle[GetNativeCell(1)];
}

public int Native_SetClosestReplayStyle(Handle plugin, int numParams)
{
	gI_TimeDifferenceStyle[GetNativeCell(1)] = GetNativeCell(2);
}

public Action Cron(Handle Timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (gA_BotInfo[i].iEnt != i)
		{
			continue;
		}

		UpdateReplayClient(gA_BotInfo[i].iEnt);
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

	if(StrContains(sFolder, "{SM}") != -1)
	{
		ReplaceString(sFolder, PLATFORM_MAX_PATH, "{SM}/", "");
		BuildPath(Path_SM, sFolder, PLATFORM_MAX_PATH, "%s", sFolder);
	}
	
	strcopy(gS_ReplayFolder, PLATFORM_MAX_PATH, sFolder);

	if (kv.JumpToKey("Looping Bots"))
	{
		kv.GotoFirstSubKey(false);

		int index = 0;

		do
		{
			kv.GetSectionName(gA_LoopingBotConfig[index].sName, sizeof(loopingbot_config_t::sName));
			gA_LoopingBotConfig[index].bEnabled = view_as<bool>(kv.GetNum("enabled"));

			int pieces;
			char buf[PLATFORM_MAX_PATH];
			char sSplit[STYLE_LIMIT][4];

			kv.GetString("tracks", buf, sizeof(buf), "");
			pieces = ExplodeString(buf, ";", sSplit, STYLE_LIMIT, 4);

			for (int i = 0; i < pieces; i++)
			{
				gA_LoopingBotConfig[index].iTrackMask |= 1 << StringToInt(sSplit[i]);
			}

			kv.GetString("styles", buf, sizeof(buf), "");
			pieces = ExplodeString(buf, ";", sSplit, STYLE_LIMIT, 4);

			for (int i = 0; i < pieces; i++)
			{
				int style = StringToInt(sSplit[i]);
				gA_LoopingBotConfig[index].aStyleMask[style / 32] |= 1 << (style % 32);
			}

			bool atLeastOneStyle = false;
			for (int i = 0; i < 8; i++)
			{
				if (gA_LoopingBotConfig[index].aStyleMask[i] != 0)
				{
					atLeastOneStyle = true;
					break;
				}
			}

			if (!atLeastOneStyle || gA_LoopingBotConfig[index].iTrackMask == 0)
			{
				gA_LoopingBotConfig[index].bEnabled = false;
			}

			++index;
		} while (kv.GotoNextKey(false));
	}

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
		Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount());
		Shavit_OnChatConfigLoaded();
	}

	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);

	char sTempMap[PLATFORM_MAX_PATH];
	FormatEx(sTempMap, PLATFORM_MAX_PATH, "maps/%s.nav", gS_Map);

	if(!FileExists(sTempMap))
	{
		File file = OpenFile(sTempMap, "wb");

		if(file != null)
		{
			int defaultNavMesh[51] = {
				-17958194, 16, 1, 128600, 16777217, 1, 1, 0, -1007845376, 1112014848, 1107304447, -1035468800,
				1139638272, 1107304447, 1107304447, 1107304447, 0, 0, 0, 0, 4, -415236096, 2046820547, 2096962, 
				65858, 0, 49786, 536822394, 33636864, 0, 12745216, -12327104, 21102623, 3, -1008254976, 1139228672,
				1107304447, 1, 0, 0, 0, 4386816, 4386816, 4161536, 4161536, 4161536, 20938752, 16777216, 33554432, 0, 0
			};
			file.Write(defaultNavMesh, 51, 4);
			int zero[1] = {0};
			file.Write(zero, 1, 1); // defaultNavMesh is missing one byte...
			delete file;
		}

		ForceChangeLevel(gS_Map, ".nav file generate");

		return;
	}

	KickAllReplays();

	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	ServerCommand((gEV_Type != Engine_TF2)? "bot_kick":"tf_bot_kick all");
	UpdateBotQuota(0);

	if(!DirExists(gS_ReplayFolder))
	{
		CreateDirectory(gS_ReplayFolder, 511);
	}

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/copy", gS_ReplayFolder);

	if(!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d", gS_ReplayFolder, i);

		if(!DirExists(sPath))
		{
			CreateDirectory(sPath, 511);
		}

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			delete gA_FrameCache[i][j].aFrames;
			gA_FrameCache[i][j].iFrameCount = 0;
			gA_FrameCache[i][j].fTime = 0.0;
			gA_FrameCache[i][j].bNewFormat = true;
			strcopy(gA_FrameCache[i][j].sReplayName, MAX_NAME_LENGTH, "invalid");
			gA_FrameCache[i][j].iPreFrames = 0;

			DefaultLoadReplay(i, j);
		}

		Call_StartForward(gH_OnReplaysLoaded);
		Call_Finish();
	}

	AddReplayBots();

	CreateTimer(3.0, Cron, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	for(int i = 0; i < styles; i++)
	{
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

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	gI_TimeDifferenceStyle[client] = newstyle;
}

void QueueAddReplayBot(bot_info_t info)
{
	gA_BotEvents.PushArray(info);
	UpdateBotQuota(gI_ExpectedBots + 1);
}

void AddReplayBots()
{
	if (!gCV_Enabled.BoolValue)
	{
		return;
	}

	// Load central bot if enabled...
	if (gCV_CentralBot.BoolValue)
	{
		bot_info_t info;
		info.iType = Replay_Central;
		QueueAddReplayBot(info);
	}

	// Load all bots from looping config...
	for (int i = 0; i < MAX_LOOPING_BOT_CONFIGS; i++)
	{
		if (!gA_LoopingBotConfig[i].bEnabled)
		{
			continue;
		}

		int track = -1;
		int style = -1;
		bool hasFrames = FindNextLoop(track, style, i);

		if (!hasFrames)
		{
			continue;
		}

		bot_info_t info;
		info.iType = Replay_Looping;
		info.iLoopingConfig = i;
		info.iStyle = style;
		info.iTrack = track;
		QueueAddReplayBot(info);
	}
}

bool DefaultLoadReplay(int style, int track)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, style, gS_Map, (track > 0)? sTrack:"");

	return LoadReplay(style, track, sPath);
}

bool LoadCurrentReplayFormat(File file, int version, int style, int track)
{
	if (version > REPLAY_FORMAT_SUBVERSION)
	{
		delete file;

		return false;
	}

	gA_FrameCache[style][track].iReplayVersion = version;

	// replay file integrity and PreFrames
	if(gA_FrameCache[style][track].iReplayVersion >= 0x03)
	{
		char sMap[160];
		file.ReadString(sMap, 160);

		int iStyle = 0;
		file.ReadUint8(iStyle);

		int iTrack = 0;
		file.ReadUint8(iTrack);

		if(!StrEqual(sMap, gS_Map, false) || iStyle != style || iTrack != track)
		{
			delete file;
			
			return false;
		}
		
		file.ReadInt32(gA_FrameCache[style][track].iPreFrames);

		// In case the replay was from when there could still be negative preframes
		if(gA_FrameCache[style][track].iPreFrames < 0)
		{
			gA_FrameCache[style][track].iPreFrames = 0;
		}
	}

	file.ReadInt32(gA_FrameCache[style][track].iFrameCount);

	int cells = 6;

	if (gA_FrameCache[style][track].iReplayVersion >= 0x04)
	{
		cells = 8;
	}

	gA_FrameCache[style][track].aFrames = new ArrayList(cells, gA_FrameCache[style][track].iFrameCount);

	file.ReadInt32(view_as<int>(gA_FrameCache[style][track].fTime));

	int iSteamID = 0;

	if(gA_FrameCache[style][track].iReplayVersion >= 0x04)
	{
		file.ReadInt32(iSteamID);
	}
	else
	{
		char sAuthID[32];
		file.ReadString(sAuthID, 32);
		ReplaceString(sAuthID, 32, "[U:1:", "");
		ReplaceString(sAuthID, 32, "]", "");
		iSteamID = StringToInt(sAuthID);
	}

	char sQuery[192];
	FormatEx(sQuery, 192, "SELECT name FROM %susers WHERE auth = %d;", gS_MySQLPrefix, iSteamID);

	DataPack hPack = new DataPack();
	hPack.WriteCell(style);
	hPack.WriteCell(track);

	gH_SQL.Query(SQL_GetUserName_Callback, sQuery, hPack, DBPrio_High);

	any[] aReplayData = new any[cells];

	for(int i = 0; i < gA_FrameCache[style][track].iFrameCount; i++)
	{
		if(file.Read(aReplayData, cells, 4) >= 0)
		{
			gA_FrameCache[style][track].aFrames.SetArray(i, aReplayData);
		}
	}

	gA_FrameCache[style][track].bNewFormat = true; // not wr-based

	delete file;

	return true;
}

bool LoadV2ReplayFormat(File file, int frames, int style, int track)
{
	int iReplaySize = gA_FrameCache[style][track].iFrameCount = frames;
	gA_FrameCache[style][track].aFrames = new ArrayList(6, iReplaySize);
	gA_FrameCache[style][track].fTime = 0.0; // N/A at this version

	any aReplayData[6];

	for(int i = 0; i < iReplaySize; i++)
	{
		if(file.Read(aReplayData, 6, 4) >= 0)
		{
			gA_FrameCache[style][track].aFrames.SetArray(i, aReplayData, 6);
		}
	}

	gA_FrameCache[style][track].bNewFormat = false;
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, "invalid");

	delete file;

	return true;
}

bool LoadOldReplayFormat(File file, int style, int track)
{
	char sLine[320];
	char sExplodedLine[6][64];

	if(!file.Seek(0, SEEK_SET))
	{
		delete file;

		return false;
	}

	gA_FrameCache[style][track].aFrames = new ArrayList(6);
	any data[6];

	for(int i = 0; !file.EndOfFile(); i++)
	{
		file.ReadLine(sLine, 320);
		int iStrings = ExplodeString(sLine, "|", sExplodedLine, 6, 64);

		data[0] = StringToFloat(sExplodedLine[0]);
		data[1] = StringToFloat(sExplodedLine[1]);
		data[2] = StringToFloat(sExplodedLine[2]);
		data[3] = StringToFloat(sExplodedLine[3]);
		data[4] = StringToFloat(sExplodedLine[4]);
		data[5] = (iStrings == 6) ? StringToInt(sExplodedLine[5]) : 0;

		gA_FrameCache[style][track].aFrames.SetArray(i, data, 6);
	}

	gA_FrameCache[style][track].iFrameCount = gA_FrameCache[style][track].aFrames.Length;
	gA_FrameCache[style][track].fTime = 0.0; // N/A at this version
	gA_FrameCache[style][track].bNewFormat = false; // wr-based
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, "invalid");

	delete file;

	return true;
}

bool LoadReplay(int style, int track, const char[] path)
{
	if(FileExists(path))
	{
		File fFile = OpenFile(path, "rb");

		char sHeader[64];

		if(!fFile.ReadLine(sHeader, 64))
		{
			delete fFile;

			return false;
		}

		TrimString(sHeader);
		char sExplodedHeader[2][64];
		ExplodeString(sHeader, ":", sExplodedHeader, 2, 64);

		if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_FINAL)) // hopefully, the last of them
		{
			return LoadCurrentReplayFormat(fFile, StringToInt(sExplodedHeader[0]), style, track);
		}
		else if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_V2))
		{
			return LoadV2ReplayFormat(fFile, StringToInt(sExplodedHeader[0]), style, track);
		}
		else // old, outdated and slow - only used for ancient replays
		{
			return LoadOldReplayFormat(fFile, style, track);
		}
	}

	return false;
}

void WriteReplayHeader(File fFile, int style, int track, float time, int steamid, int preframes, int timerstartframe, int iSize)
{
	fFile.WriteLine("%d:" ... REPLAY_FORMAT_FINAL, REPLAY_FORMAT_SUBVERSION);

	fFile.WriteString(gS_Map, true);
	fFile.WriteInt8(style);
	fFile.WriteInt8(track);
	fFile.WriteInt32(timerstartframe - preframes);

	fFile.WriteInt32(iSize - preframes);
	fFile.WriteInt32(view_as<int>(time));
	fFile.WriteInt32(steamid);
}

void SaveReplay(int style, int track, float time, int steamid, char[] name, int preframes, ArrayList playerrecording, int timerstartframe, int timestamp, bool saveCopy, bool saveWR, char[] sPath, int sPathLen)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	File fWR = null;
	File fCopy = null;

	if (saveWR)
	{
		FormatEx(sPath, sPathLen, "%s/%d/%s%s.replay", gS_ReplayFolder, style, gS_Map, (track > 0)? sTrack:"");
		DeleteFile(sPath);
		fWR = OpenFile(sPath, "wb");
	}

	if (saveCopy)
	{
		FormatEx(sPath, sPathLen, "%s/copy/%d_%d_%s.replay", gS_ReplayFolder, timestamp, steamid, gS_Map);
		DeleteFile(sPath);
		fCopy = OpenFile(sPath, "wb");
	}

	int iSize = playerrecording.Length;

	if (saveWR)
	{
		WriteReplayHeader(fWR, style, track, time, steamid, preframes, timerstartframe, iSize);

		delete gA_FrameCache[style][track].aFrames;
		gA_FrameCache[style][track].aFrames = new ArrayList(sizeof(frame_t), iSize-preframes);
	}

	if (saveCopy)
	{
		WriteReplayHeader(fCopy, style, track, time, steamid, preframes, timerstartframe, iSize);
	}

	any aFrameData[sizeof(frame_t)];
	any aWriteData[sizeof(frame_t) * FRAMES_PER_WRITE];
	int iFramesWritten = 0;

	for(int i = preframes; i < iSize; i++)
	{
		playerrecording.GetArray(i, aFrameData, sizeof(frame_t));
	
		if (saveWR)
		{
			gA_FrameCache[style][track].aFrames.SetArray(i-preframes, aFrameData);
		}

		for(int j = 0; j < sizeof(frame_t); j++)
		{
			aWriteData[(sizeof(frame_t) * iFramesWritten) + j] = aFrameData[j];
		}

		if(++iFramesWritten == FRAMES_PER_WRITE || i == iSize - 1)
		{
			if (saveWR)
			{
				fWR.Write(aWriteData, sizeof(frame_t) * iFramesWritten, 4);
			}

			if (saveCopy)
			{
				fCopy.Write(aWriteData, sizeof(frame_t) * iFramesWritten, 4);
			}

			iFramesWritten = 0;
		}
	}

	delete fWR;
	delete fCopy;

	if (!saveWR)
	{
		return;
	}

	gA_FrameCache[style][track].iFrameCount = iSize - preframes;
	gA_FrameCache[style][track].fTime = time;
	gA_FrameCache[style][track].bNewFormat = true;
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, name);
	gA_FrameCache[style][track].iPreFrames = timerstartframe - preframes;
}

bool DeleteReplay(int style, int track, int accountid = 0, const char[] mapname = gS_Map)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, style, mapname, (track > 0)? sTrack:"");

	if(!FileExists(sPath))
	{
		return false;
	}

	if(accountid != 0)
	{
		File file = OpenFile(sPath, "wb");

		char szTemp[160];
		file.ReadString(szTemp, 160);

		int iTemp = 0;
		file.ReadUint8(iTemp);
		file.ReadUint8(iTemp);
		file.ReadInt32(iTemp);
		file.ReadInt32(iTemp);
		int iSteamID = 0;

		if(gA_FrameCache[style][track].iReplayVersion >= 0x04)
		{
			file.ReadInt32(iSteamID);
		}
		else
		{
			char sAuthID[32];
			file.ReadString(sAuthID, 32);
			ReplaceString(sAuthID, 32, "[U:1:", "");
			ReplaceString(sAuthID, 32, "]", "");
			iSteamID = StringToInt(sAuthID);
		}

		delete file;
		
		if(accountid == iSteamID && !DeleteFile(sPath))
		{
			return false;
		}
	}
	else 
	{
		if(!DeleteFile(sPath))
		{
			return false;
		}
	}

	if(StrEqual(mapname, gS_Map))
	{
		UnloadReplay(style, track, false, false);
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

void ForceObserveProp(int client)
{
	if (gA_BotInfo[client].iEnt > 1 && gA_BotInfo[client].iType == Replay_Prop)
	{
		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", gA_BotInfo[client].iEnt);
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
		gA_BotInfo[client].iEnt = -1;
		ClearBotInfo(gA_BotInfo[client]);
		ClearFrames(client);

		SDKHook(client, SDKHook_PostThink, ForceObserveProp);

		// The server kicks all the bots when it's hibernating... so let's add them back in...
		if (GetClientCount() <= 1)
		{
			AddReplayBots();
		}
	}
	else if (gA_BotEvents.Length > 0)
	{
		bot_info_t info;
		gA_BotEvents.GetArray(0, info);
		gA_BotEvents.Erase(0);

		gA_BotInfo[client] = info;
		gA_BotInfo[client].iEnt = client;

		if (info.iType == Replay_Central)
		{
			gI_CentralBot = client;
			ClearBotInfo(gA_BotInfo[client]);
		}
		else
		{
			StartReplay(gA_BotInfo[client], gA_BotInfo[client].iTrack, gA_BotInfo[client].iStyle, GetClientFromSerial(info.iStarterSerial), gCV_ReplayDelay.FloatValue);
		}

		// Used to make the bot fucking spawn.....
		RequestFrame(DelayedUpdateReplayClient, GetClientSerial(client));

		if (info.iType == Replay_Dynamic)
		{
			// TODO: Add link to bot in gA_BotInfo[starter].iEnt...
			// Dead bots can't be spectated... so let's use this to spectate them when they spawn...
			RequestFrame(SpectateMyDynamicBot, GetClientSerial(client));
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

void FormatStyle(const char[] source, int style, bool central, int track, char dest[MAX_NAME_LENGTH], bool idle, framecache_t aCache, ReplayBotType type)
{
	char sTime[16];
	char sName[MAX_NAME_LENGTH];

	char temp[128];
	strcopy(temp, sizeof(temp), source);

	ReplaceString(temp, sizeof(temp), "{map}", gS_Map);

	if(central && idle)
	{
		FormatSeconds(0.0, sTime, 16);
		sName = "you should never see this";
		ReplaceString(temp, sizeof(temp), "{style}", gS_ReplayStrings.sCentralStyle);
	}
	else
	{
		FormatSeconds(GetReplayLength(style, track, aCache), sTime, 16);
		GetReplayName(style, track, sName, sizeof(sName));
		ReplaceString(temp, sizeof(temp), "{style}", gS_StyleStrings[style].sStyleName);
	}

	char sType[32];
	if (type == Replay_Central)
	{
		FormatEx(sType, sizeof(sType), "%T", "Replay_Central", 0);
	}
	else if (type == Replay_Dynamic)
	{
		FormatEx(sType, sizeof(sType), "%T", "Replay_Dynamic", 0);
	}
	else if (type == Replay_Looping)
	{
		FormatEx(sType, sizeof(sType), "%T", "Replay_Looping", 0);
	}

	ReplaceString(temp, sizeof(temp), "{type}", sType);
	ReplaceString(temp, sizeof(temp), "{time}", sTime);
	ReplaceString(temp, sizeof(temp), "{player}", sName);

	char sTrack[32];
	GetTrackName(LANG_SERVER, track, sTrack, 32);
	ReplaceString(temp, sizeof(temp), "{track}", sTrack);

	strcopy(dest, MAX_NAME_LENGTH, temp);
}

void UpdateBotScoreboard(int client)
{
	int track = gA_BotInfo[client].iTrack;
	int style = gA_BotInfo[client].iStyle;
	ReplayBotType type = gA_BotInfo[client].iType;
	int iFrameCount = gA_BotInfo[client].aCache.iFrameCount;

	bool central = (gI_CentralBot == client);
	bool idle = (gA_BotInfo[client].iStatus == Replay_Idle);

	if(gEV_Type != Engine_TF2)
	{
		char sTag[MAX_NAME_LENGTH];
		FormatStyle(gS_ReplayStrings.sClanTag, style, central, track, sTag, idle, gA_BotInfo[client].aCache, type);
		CS_SetClientClanTag(client, sTag);
	}

	char sName[MAX_NAME_LENGTH];
	
	if(central || iFrameCount > 0)
	{
		FormatStyle(idle ? gS_ReplayStrings.sCentralName : gS_ReplayStrings.sNameStyle, style, central, track, sName, idle, gA_BotInfo[client].aCache, type);
	}
	else
	{
		FormatStyle(gS_ReplayStrings.sUnloaded, style, central, track, sName, idle, gA_BotInfo[client].aCache, type);
	}

	gB_HideNameChange = true;
	SetClientName(client, sName);

	int iScore = (iFrameCount > 0 || client == gI_CentralBot)? 2000:-2000;

	if(gEV_Type == Engine_CSGO)
	{
		CS_SetClientContributionScore(client, iScore);
	}
	else if(gEV_Type == Engine_CSS)
	{
		SetEntProp(client, Prop_Data, "m_iFrags", iScore);
	}

	SetEntProp(client, Prop_Data, "m_iDeaths", 0);
}

void SpectateMyDynamicBot(int serial)
{
	int bot = GetClientFromSerial(serial);

	if (bot == 0)
	{
		return;
	}

	if (!IsPlayerAlive(bot))
	{
		// Uhh.... recursion lmao....
		// The bot doesn't like to respawn immediately and it's really annoying
		RequestFrame(SpectateMyDynamicBot, GetClientSerial(bot));
		return;
	}

	int starter = GetClientFromSerial(gA_BotInfo[bot].iStarterSerial);

	if (starter == 0)
	{
		return;
	}

	SetEntPropEnt(starter, Prop_Send, "m_hObserverTarget", bot);
}

void DelayedUpdateReplayClient(int serial)
{
	UpdateReplayClient(GetClientFromSerial(serial));
}

void RemoveAllWeapons(int client)
{
	int weapon = -1, max = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i = 0; i < max; i++)
	{
		if ((weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i)) == -1)
			continue;

		CS_DropWeapon(client, weapon, false, true);
		AcceptEntityInput(weapon, "Kill");
	}
}

void UpdateReplayClient(int client)
{
	// Only run on fakeclients
	if(!gCV_Enabled.BoolValue || !IsValidClient(client) || !IsFakeClient(client))
	{
		return;
	}

	SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
	SetEntityMoveType(client, MOVETYPE_NOCLIP);

	UpdateBotScoreboard(client);

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
		
	int iFlags = GetEntityFlags(client);

	if((iFlags & FL_ATCONTROLS) == 0)
	{
		SetEntityFlags(client, (iFlags | FL_ATCONTROLS));
	}

	char sWeapon[32];
	gCV_BotWeapon.GetString(sWeapon, 32);

	if(gEV_Type != Engine_TF2 && strlen(sWeapon) > 0)
	{
		int iWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

		if(StrEqual(sWeapon, "none"))
		{
			RemoveAllWeapons(client);
		}
		else
		{
			char sClassname[32];

			if(iWeapon != -1 && IsValidEntity(iWeapon))
			{
				GetEntityClassname(iWeapon, sClassname, 32);

				if(!StrEqual(sWeapon, sClassname))
				{
					RemoveAllWeapons(client);
					GivePlayerItem(client, sWeapon);
				}
			}
			else
			{
				GivePlayerItem(client, sWeapon);
			}
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
		RequestFrame(ClearFrames, client);

		if (gA_BotInfo[client].iEnt >= 1) // Remove Replay_Prop's
		{
			KickReplay(gA_BotInfo[client]);
		}

		return;
	}

	if (gA_BotInfo[client].iEnt == client)
	{
		UpdateBotQuota(gI_ExpectedBots - 1);
		CancelReplay(gA_BotInfo[client], 0, false);

		gA_BotInfo[client].iEnt = -1;

		if (gI_CentralBot == client)
		{
			gI_CentralBot = -1;
		}
	}
}

public Action Shavit_OnStart(int client)
{
	int iMaxPreFrames = RoundToFloor(gCV_PlaybackPreRunTime.FloatValue * gF_Tickrate / Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(client), "speed"));

	gI_PlayerPrerunFrames[client] = gA_PlayerFrames[client].Length - iMaxPreFrames;
	if(gI_PlayerPrerunFrames[client] < 0)
	{
		gI_PlayerPrerunFrames[client] = 0;
	}
	gI_PlayerTimerStartFrames[client] = gA_PlayerFrames[client].Length;

	if(!gB_ClearFrame[client])
	{
		if(!gCV_ClearPreRun.BoolValue)
		{
			ClearFrames(client);
		}
		gB_ClearFrame[client] = true;
	}
	else
	{
		if(gA_PlayerFrames[client].Length >= iMaxPreFrames)
		{
			gA_PlayerFrames[client].Erase(0);
			gI_PlayerFrames[client]--;
		}
	}

	return Plugin_Continue;
}

public void Shavit_OnStop(int client)
{
	ClearFrames(client);
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity)
{
	if(type == Zone_Start)
	{
		gB_ClearFrame[client] = false;
	}
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
	if(Shavit_IsPracticeMode(client) || !gCV_Enabled.BoolValue || gI_PlayerFrames[client] == 0)
	{
		return;
	}

	bool isTooLong = (gCV_TimeLimit.FloatValue > 0.0 && time > gCV_TimeLimit.FloatValue);
	bool isWR = true;
	
	float length = GetReplayLength(style, track, gA_FrameCache[style][track]);

	if(gA_FrameCache[style][track].bNewFormat)
	{
		if(length > 0.0 && time > length)
		{
			isWR = false;
		}
	}
	else
	{
		float wrtime = Shavit_GetWorldRecord(style, track);

		if(wrtime != 0.0 && time > wrtime)
		{
			isWR = false;
		}
	}

	Action action = Plugin_Continue;
	Call_StartForward(gH_ShouldSaveReplayCopy);
	Call_PushCell(client);
	Call_PushCell(style);
	Call_PushCell(time);
	Call_PushCell(jumps);
	Call_PushCell(strafes);
	Call_PushCell(sync);
	Call_PushCell(track);
	Call_PushCell(oldtime);
	Call_PushCell(perfs);
	Call_PushCell(avgvel);
	Call_PushCell(maxvel);
	Call_PushCell(timestamp);
	Call_PushCell(isTooLong);
	Call_PushCell(isWR);
	Call_Finish(action);

	bool makeCopy = (action != Plugin_Continue);
	bool makeWR = (isWR && !isTooLong);

	if (!makeCopy && !makeWR)
	{
		return;
	}

	int iSteamID = GetSteamAccountID(client);

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);
	ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");

	char sPath[PLATFORM_MAX_PATH];
	SaveReplay(style, track, time, iSteamID, sName, gI_PlayerPrerunFrames[client], gA_PlayerFrames[client], gI_PlayerTimerStartFrames[client], timestamp, makeCopy, makeWR, sPath, sizeof(sPath));

	Call_StartForward(gH_OnReplaySaved);
	Call_PushCell(client);
	Call_PushCell(style);
	Call_PushCell(time);
	Call_PushCell(jumps);
	Call_PushCell(strafes);
	Call_PushCell(sync);
	Call_PushCell(track);
	Call_PushCell(oldtime);
	Call_PushCell(perfs);
	Call_PushCell(avgvel);
	Call_PushCell(maxvel);
	Call_PushCell(timestamp);
	Call_PushCell(isTooLong);
	Call_PushCell(isWR);
	Call_PushCell(makeCopy);
	Call_PushString(sPath);
	Call_Finish();

	if(makeWR && ReplayEnabled(style))
	{
		StopOrRestartBots(style, track, false);
	}

	ClearFrames(client);
}

void ApplyFlags(int &flags1, int flags2, int flag)
{
	if((flags2 & flag) != 0)
	{
		flags1 |= flag;
	}
	else
	{
		flags1 &= ~flag;
	}
}

public void Shavit_OnTimescaleChanged(int client, float oldtimescale, float newtimescale)
{
	gF_NextFrameTime[client] = 0.0;
}

Action ReplayRunCmd(bot_info_t info, int &buttons, int &impulse, float vel[3])
{
	float vecCurrentPosition[3];
	GetEntPropVector(info.iEnt, Prop_Send, "m_vecOrigin", vecCurrentPosition);

	bool isClient = (1 <= info.iEnt <= MaxClients);

	buttons = 0;

	vel[0] = 0.0;
	vel[1] = 0.0;

	if(info.aCache.aFrames != null || info.aCache.iFrameCount > 0) // if no replay is loaded
	{
		if(info.iTick != -1 && info.aCache.iFrameCount >= 1)
		{
			if(info.iStatus != Replay_Running)
			{
				bool bStart = (info.iStatus == Replay_Start);

				int iFrame = (bStart)? 0:(info.aCache.iFrameCount - 1);

				frame_t aFrame;
				info.aCache.aFrames.GetArray(iFrame, aFrame, 5);
					
				if(bStart)
				{
					float ang[3];
					ang[0] = aFrame.ang[0];
					ang[1] = aFrame.ang[1];
					TeleportEntity(info.iEnt, aFrame.pos, ang, view_as<float>({0.0, 0.0, 0.0}));
				}
				else
				{
					float vecVelocity[3];
					MakeVectorFromPoints(vecCurrentPosition, aFrame.pos, vecVelocity);
					ScaleVector(vecVelocity, gF_Tickrate);
					TeleportEntity(info.iEnt, NULL_VECTOR, NULL_VECTOR, vecVelocity);
				}

				return Plugin_Changed;
			}

			if(++info.iTick >= info.aCache.iFrameCount - 1)
			{
				info.iStatus = Replay_End;
				info.hTimer = CreateTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_EndReplay, info.iEnt, TIMER_FLAG_NO_MAPCHANGE);

				return Plugin_Changed;
			}

			if(info.iTick == 1)
			{
				info.fStartTick = GetEngineTime();
			}

			frame_t aFrame;
			info.aCache.aFrames.GetArray(info.iTick, aFrame, (info.aCache.iReplayVersion >= 0x02) ? 8 : 6);
			buttons = aFrame.buttons;

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

			bool bWalk = false;
			MoveType mt = MOVETYPE_NOCLIP;

			if(info.aCache.iReplayVersion >= 0x02)
			{
				int iReplayFlags = aFrame.flags;

				if (isClient)
				{
					int iEntityFlags = GetEntityFlags(info.iEnt);

					ApplyFlags(iEntityFlags, iReplayFlags, FL_ONGROUND);
					ApplyFlags(iEntityFlags, iReplayFlags, FL_PARTIALGROUND);
					ApplyFlags(iEntityFlags, iReplayFlags, FL_INWATER);
					ApplyFlags(iEntityFlags, iReplayFlags, FL_SWIM);

					SetEntityFlags(info.iEnt, iEntityFlags);
				}

				if(aFrame.mt == MOVETYPE_LADDER)
				{
					mt = aFrame.mt;
				}
				else if(aFrame.mt == MOVETYPE_WALK && (iReplayFlags & FL_ONGROUND) > 0)
				{
					bWalk = true;
				}
			}

			if (isClient)
			{
				SetEntityMoveType(info.iEnt, mt);
			}

			float vecVelocity[3];
			MakeVectorFromPoints(vecCurrentPosition, aFrame.pos, vecVelocity);
			ScaleVector(vecVelocity, gF_Tickrate);

			float ang[3];
			ang[0] = aFrame.ang[0];
			ang[1] = aFrame.ang[1];

			if(info.iTick > 1 &&
				// replay is going above 50k speed, just teleport at this point
				(GetVectorLength(vecVelocity) > 50000.0 ||
				// bot is on ground.. if the distance between the previous position is much bigger (1.5x) than the expected according
				// to the bot's velocity, teleport to avoid sync issues
				(bWalk && GetVectorDistance(vecCurrentPosition, aFrame.pos) > GetVectorLength(vecVelocity) / gF_Tickrate * 1.5)))
			{
				TeleportEntity(info.iEnt, aFrame.pos, ang, NULL_VECTOR);
			}
			else
			{
				TeleportEntity(info.iEnt, NULL_VECTOR, ang, vecVelocity);
			}
		}
	}

	return Plugin_Changed;
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
			if(!gB_Button[client] && GetSpectatorTarget(client) != -1)
			{
				OpenReplayTypeMenu(client);
			}

			gB_Button[client] = true;
		}
		else
		{
			gB_Button[client] = false;
		}

		return Plugin_Continue;
	}

	if (IsFakeClient(client))
	{
		if (gA_BotInfo[client].iEnt == client)
		{
			return ReplayRunCmd(gA_BotInfo[client], buttons, impulse, vel);
		}
	}
	else if(ReplayEnabled(Shavit_GetBhopStyle(client)) && Shavit_GetTimerStatus(client) == Timer_Running)
	{
		if((gI_PlayerFrames[client] / gF_Tickrate) > gCV_TimeLimit.FloatValue)
		{
			// in case of bad timing
			if(gB_HijackFrame[client])
			{
				gB_HijackFrame[client] = false;
			}

			return Plugin_Continue;
		}

		float fTimescale = Shavit_GetClientTimescale(client);

		if(fTimescale != 0.0)
		{
			if(gF_NextFrameTime[client] <= 0.0)
			{
				// TODO: better resizing than this. Probably pre-allocating two seconds worth.
				gA_PlayerFrames[client].Resize(gI_PlayerFrames[client] + 1);

				frame_t aFrame;
				GetClientAbsOrigin(client, aFrame.pos);

				if(!gB_HijackFrame[client])
				{
					float vecEyes[3];
					GetClientEyeAngles(client, vecEyes);
					aFrame.ang[0] = vecEyes[0];
					aFrame.ang[1] = vecEyes[1];
				}
				else
				{
					aFrame.ang[0] = gF_HijackedAngles[client][0];
					aFrame.ang[1] = gF_HijackedAngles[client][1];
					gB_HijackFrame[client] = false;
				}

				aFrame.buttons = buttons;
				aFrame.flags = GetEntityFlags(client);
				aFrame.mt = GetEntityMoveType(client);
				//GetEntPropVector(client, Prop_Data, "m_vecVelocity", aFrame.vel); // TODO: m_vecBaseVelocity? m_vecAbsVelocity?

				// TODO: Change to pusharray
				gA_PlayerFrames[client].SetArray(gI_PlayerFrames[client], aFrame, sizeof(frame_t));
				gI_PlayerFrames[client]++;

				if(fTimescale != -1.0)
				{
					gF_NextFrameTime[client] += (1.0 - fTimescale);
				}
			}
			else if(fTimescale != -1.0)
			{
				gF_NextFrameTime[client] -= fTimescale;
			}
		}
	}

	return Plugin_Continue;
}

public Action Timer_EndReplay(Handle Timer, any data)
{
	data = GetBotInfoIndex(data);
	gA_BotInfo[data].hTimer = null;

	Call_StartForward(gH_OnReplayEnd);
	Call_PushCell(gA_BotInfo[data].iEnt);
	Call_PushCell(gA_BotInfo[data].iType);
	Call_Finish();

	FinishReplay(gA_BotInfo[data]);

	return Plugin_Stop;
}

public Action Timer_StartReplay(Handle Timer, any data)
{
	data = GetBotInfoIndex(data);
	gA_BotInfo[data].hTimer = null;
	gA_BotInfo[data].iStatus = Replay_Running;

	Call_StartForward(gH_OnReplayStart);
	Call_PushCell(gA_BotInfo[data].iEnt);
	Call_PushCell(gA_BotInfo[data].iType);
	Call_Finish();

	return Plugin_Stop;
}

bool ReplayEnabled(any style)
{
	return !Shavit_GetStyleSettingBool(style, "unranked") && !Shavit_GetStyleSettingBool(style, "noreplay");
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
	}
	else
	{
		// Here to kill Replay_Prop s when the watcher/starter respawns.
		KickReplay(gA_BotInfo[client]);
	}
}

public Action BotEvents(Event event, const char[] name, bool dontBroadcast)
{
	if(!gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	if(event.GetBool("bot"))
	{
		event.BroadcastDisabled = true;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public Action BotEventsStopLogSpam(Event event, const char[] name, bool dontBroadcast)
{
	if(!gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	if(IsFakeClient(GetClientOfUserId(event.GetInt("userid"))))
	{
		event.BroadcastDisabled = true;
		return Plugin_Handled; // Block with Plugin_Handled...
	}

	return Plugin_Continue;
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
	delete gA_PlayerFrames[client];
	gA_PlayerFrames[client] = new ArrayList(sizeof(frame_t));
	gI_PlayerFrames[client] = 0;
	gF_NextFrameTime[client] = 0.0;
	gI_PlayerPrerunFrames[client] = 0;
	gI_PlayerTimerStartFrames[client] = 0;
}

public void Shavit_OnWRDeleted(int style, int id, int track, int accountid, const char[] mapname)
{
	DeleteReplay(style, track, accountid, mapname);
}

public Action Command_DeleteReplay(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(DeleteReplay_Callback);
	menu.SetTitle("%T", "DeleteReplayMenuTitle", client);

	int[] styles = new int[gI_Styles];
	Shavit_GetOrderedStyles(styles, gI_Styles);

	for(int i = 0; i < gI_Styles; i++)
	{
		int iStyle = styles[i];

		if(!ReplayEnabled(iStyle))
		{
			continue;
		}

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			if(gA_FrameCache[iStyle][j].iFrameCount == 0)
			{
				continue;
			}

			char sInfo[8];
			FormatEx(sInfo, 8, "%d;%d", iStyle, j);

			float time = GetReplayLength(iStyle, j, gA_FrameCache[iStyle][j]);

			char sTrack[32];
			GetTrackName(client, j, sTrack, 32);

			char sDisplay[64];

			if(time > 0.0)
			{
				char sTime[32];
				FormatSeconds(time, sTime, 32, false);

				FormatEx(sDisplay, 64, "%s (%s) - %s", gS_StyleStrings[iStyle].sStyleName, sTrack, sTime);
			}

			else
			{
				FormatEx(sDisplay, 64, "%s (%s)", gS_StyleStrings[iStyle].sStyleName, sTrack);
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
	menu.Display(client, 300);

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

		gI_MenuTrack[param1] = StringToInt(sExploded[1]);

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
		submenu.Display(param1, 300);
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

		if(DeleteReplay(style, gI_MenuTrack[param1]))
		{
			char sTrack[32];
			GetTrackName(param1, gI_MenuTrack[param1], sTrack, 32);

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

int CreateReplayProp(int client)
{
	if (gA_BotInfo[client].iEnt >= 1)
	{
		return -1;
	}

	int ent = CreateEntityByName("prop_physics_override");

	if (ent == -1)
	{
		return -1;
	}
	
	char models[][] = {
		"models/props_interiors/lightbulb02a.mdl",
		"models/props/cs_office/vending_machine.mdl",
		"models/props/cs_italy/bananna_bunch.mdl",
		"models/player/t_leet.mdl",
	};

	int modelidx = 1;

	PrecacheModel(models[modelidx]);
	SetEntityModel(ent, models[modelidx]);

	DispatchSpawn(ent);

	// Turn prop invisible
	SetEntityRenderMode(ent, RENDER_TRANSCOLOR);
	SetEntityRenderColor(ent, 255, 255, 255, 0);

	// To get the prop to transmit to the viewer....
	// TODO: Make it so it only transmits to viewers instead of using FL_EDICT_ALWAYS...
	int edict = EntRefToEntIndex(ent);
	SetEdictFlags(edict, GetEdictFlags(edict) | FL_EDICT_ALWAYS);

	// Make prop not collide (especially with the world)
	DispatchKeyValue(ent, "Solid", "0");

	SetEntProp(ent, Prop_Data, HACKY_CLIENT_IDX_PROP, client); // WHAT A FUCKING HACK

	gA_BotInfo[client].iEnt = ent;
	gA_BotInfo[client].iType = Replay_Prop;
	ClearBotInfo(gA_BotInfo[client]);

	return ent;
}

public Action Command_Replay(int client, int args)
{
	if (!IsValidClient(client) || !gCV_Enabled.BoolValue || !(gCV_CentralBot.BoolValue || gCV_AllowPropBots.BoolValue || gCV_DynamicBotLimit.IntValue > 0))
	{
		return Plugin_Handled;
	}

	if(GetClientTeam(client) > 1)
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_ChangeClientTeam(client, TFTeam_Spectator);
		}
		else
		{
			ChangeClientTeam(client, CS_TEAM_SPECTATOR);
		}
	}

	OpenReplayTypeMenu(client);
	return Plugin_Handled;
}

void OpenReplayTypeMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ReplayType);
	menu.SetTitle("%T\n ", "Menu_ReplayBotType", client);

	char sDisplay[64];
	char sInfo[8];

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "Menu_Replay_Central", client);
	IntToString(view_as<int>(Replay_Central), sInfo, sizeof(sInfo));
	menu.AddItem(sInfo, sDisplay, (gCV_CentralBot.BoolValue && IsValidClient(gI_CentralBot) && gA_BotInfo[gI_CentralBot].iStatus == Replay_Idle) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "Menu_Replay_Dynamic", client);
	IntToString(view_as<int>(Replay_Dynamic), sInfo, sizeof(sInfo));
	menu.AddItem(sInfo, sDisplay, (gCV_DynamicBotLimit.IntValue > 0 && gI_DynamicBots < gCV_DynamicBotLimit.IntValue) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "Menu_Replay_Prop", client);
	IntToString(view_as<int>(Replay_Prop), sInfo, sizeof(sInfo));
	menu.AddItem(sInfo, sDisplay, (gCV_AllowPropBots.BoolValue) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	bool canstop = false;
	int target = GetSpectatorTarget(client);

	if (target != -1)
	{
		int index = GetBotInfoIndex(target);

		if (gA_BotInfo[index].iStatus == Replay_Start || gA_BotInfo[index].iStatus == Replay_Running)
		{
			canstop = CanStopReplay(client, gA_BotInfo[index]);
		}
	}

	FormatEx(sDisplay, 64, "%T", "CentralReplayStop", client);
	menu.AddItem("stop", sDisplay, canstop ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	menu.ExitButton = true;
	menu.DisplayAt(client, 0, 300);
}

public int MenuHandler_ReplayType(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "stop"))
		{
			int target = GetSpectatorTarget(param1);

			if (target != -1)
			{
				int index = GetBotInfoIndex(target);

				if ((gA_BotInfo[index].iStatus == Replay_Start || gA_BotInfo[index].iStatus == Replay_Running) && CanStopReplay(param1, gA_BotInfo[index]))
				{
					FinishReplay(gA_BotInfo[index], param1);
				}
			}

			return 0;
		}

		ReplayBotType type = view_as<ReplayBotType>(StringToInt(sInfo));

		if (type != Replay_Central && type != Replay_Dynamic && type != Replay_Prop)
		{
			return 0;
		}

		if ((type == Replay_Central && (!gCV_CentralBot.BoolValue || !IsValidClient(gI_CentralBot) || gA_BotInfo[gI_CentralBot].iStatus != Replay_Idle))
		|| (type == Replay_Dynamic && (gCV_DynamicBotLimit.IntValue < 1 || gI_DynamicBots >= gCV_DynamicBotLimit.IntValue))
		|| (type == Replay_Prop && (!gCV_AllowPropBots.BoolValue)))
		{
			PrintToChat(param1, "fuck off"); // TODO
			return 0;
		}

		gI_MenuType[param1] = type;
		OpenReplayTrackMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenReplayTrackMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ReplayTrack);
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

	menu.ExitBackButton = true;
	menu.Display(client, 300);
}

public int MenuHandler_ReplayTrack(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		int track = StringToInt(sInfo);

		// avoid an exploit
		if(track >= 0 && track < TRACKS_SIZE)
		{
			gI_MenuTrack[param1] = track;
			OpenReplayStyleMenu(param1, track);
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenReplayTypeMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenReplayStyleMenu(int client, int track)
{
	char sTrack[32];
	GetTrackName(client, track, sTrack, 32);

	Menu menu = new Menu(MenuHandler_ReplayStyle);
	menu.SetTitle("%T (%s)\n ", "CentralReplayTitle", client, sTrack);

	int[] styles = new int[gI_Styles];
	Shavit_GetOrderedStyles(styles, gI_Styles);

	for(int i = 0; i < gI_Styles; i++)
	{
		int iStyle = styles[i];

		if(!ReplayEnabled(iStyle))
		{
			continue;
		}

		char sInfo[8];
		IntToString(iStyle, sInfo, 8);

		float time = GetReplayLength(iStyle, track, gA_FrameCache[iStyle][track]);

		char sDisplay[64];

		if(time > 0.0)
		{
			char sTime[32];
			FormatSeconds(time, sTime, 32, false);

			FormatEx(sDisplay, 64, "%s - %s", gS_StyleStrings[iStyle].sStyleName, sTime);
		}
		else
		{
			strcopy(sDisplay, 64, gS_StyleStrings[iStyle].sStyleName);
		}

		menu.AddItem(sInfo, sDisplay, (gA_FrameCache[iStyle][track].iFrameCount > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "ERROR");
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, 0, 300);
}

public int MenuHandler_ReplayStyle(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		int style = StringToInt(sInfo);

		if(style < 0 || style >= gI_Styles || !ReplayEnabled(style) || gA_FrameCache[style][gI_MenuTrack[param1]].iFrameCount == 0)
		{
			return 0;
		}

		gI_MenuStyle[param1] = style;
		ReplayBotType type = gI_MenuType[param1];

		FinishReplay(gA_BotInfo[param1]);

		if (type == Replay_Central)
		{
			if (IsValidClient(gI_CentralBot))
			{
				StartReplay(gA_BotInfo[gI_CentralBot], gI_MenuTrack[param1], gI_MenuStyle[param1], param1, gCV_ReplayDelay.FloatValue);
				SetEntPropEnt(param1, Prop_Send, "m_hObserverTarget", gI_CentralBot);
			}
			// TODO: error message if not valid
		}
		else if (type == Replay_Dynamic)
		{
			bot_info_t info;
			info.iType = Replay_Dynamic;
			info.iStyle = gI_MenuStyle[param1];
			info.iTrack = gI_MenuTrack[param1];
			info.iStarterSerial = GetClientSerial(param1);
			QueueAddReplayBot(info);
		}
		else if (type == Replay_Prop)
		{
			int ent = CreateReplayProp(param1);

			if (IsValidEntity(ent))
			{
				StartReplay(gA_BotInfo[param1], gI_MenuTrack[param1], gI_MenuStyle[param1], param1, gCV_ReplayDelay.FloatValue);
			}
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenReplayTrackMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

bool CanStopReplay(int client, bot_info_t info)
{
	return (CheckCommandAccess(client, "sm_deletereplay", ADMFLAG_RCON) ||
			(gCV_PlaybackCanStop.BoolValue &&
			GetClientSerial(client) == info.iStarterSerial &&
			GetEngineTime() - gF_LastInteraction[client] > gCV_PlaybackCooldown.FloatValue));
}

void TeleportToStart(bot_info_t info)
{
	frame_t frame;
	info.aCache.aFrames.GetArray(0, frame, 5);

	float vecAngles[3];
	vecAngles[0] = frame.ang[0];
	vecAngles[1] = frame.ang[1];

	TeleportEntity(info.iEnt, frame.pos, vecAngles, view_as<float>({0.0, 0.0, 0.0}));
}

int GetBotInfoIndex(int ent)
{
	// Replay_Prop's are not clients... so use a hack instead...
	return (1 <= ent <= MaxClients) ? ent : GetEntProp(ent, Prop_Data, HACKY_CLIENT_IDX_PROP);
}

void ClearBotInfo(bot_info_t info)
{
	//info.iEnt
	info.iStyle = -1;
	info.iStatus = Replay_Idle;
	//info.iType
	info.iTrack = -1;
	info.iStarterSerial = -1;
	info.iTick = -1;
	//info.iLoopingConfig
	delete info.hTimer;
	info.fStartTick = -1.0;
	info.bCustomFrames = false;

	info.aCache.iFrameCount = -1;
	info.aCache.fTime = -1.0;
	info.aCache.bNewFormat = false;
	info.aCache.iReplayVersion = -1;
	info.aCache.sReplayName = "";
	info.aCache.iPreFrames = -1;
	delete info.aCache.aFrames;
}

int GetNextBit(int start, int[] mask, int max)
{
	for (int i = start+1; i < max; i++)
	{
		if ((mask[i / 32] & (1 << (i % 32))) != 0)
		{
			return i;
		}
	}

	for (int i = 0; i < start; i++)
	{
		if ((mask[i / 32] & (1 << (i % 32))) != 0)
		{
			return i;
		}
	}

	return start;
}

// Need to find the next style/track in the loop that have frames.
bool FindNextLoop(int &track, int &style, int config)
{
	int originalTrack = track;
	int originalStyle = style;
	int aTrackMask[1];
	aTrackMask[0] = gA_LoopingBotConfig[config].iTrackMask;

	// This for loop is just so we don't infinite loop....
	for (int i = 0; i < (TRACKS_SIZE*gI_Styles); i++)
	{
		int nextstyle = GetNextBit(style, gA_LoopingBotConfig[config].aStyleMask, gI_Styles);

		if (nextstyle <= style || track == -1)
		{
			track = GetNextBit(track, aTrackMask, TRACKS_SIZE);
		}

		if (track == -1)
		{
			return false;
		}

		style = nextstyle;
		bool hasFrames = (gA_FrameCache[style][track].iFrameCount > 0);

		if (track == originalTrack && style == originalStyle)
		{
			return hasFrames;
		}

		if (hasFrames)
		{
			return true;
		}
	}

	return false;
}

void CancelReplay(bot_info_t info, int client, bool update = true)
{
	if(client > 0)
	{
		Shavit_PrintToChat(client, "%T", "CentralReplayStopped", client);
	}

	int starter = GetClientFromSerial(info.iStarterSerial);

	if(starter != 0)
	{
		gF_LastInteraction[starter] = GetEngineTime();
	}

	if (update)
	{
		TeleportToStart(info);
	}

	ClearBotInfo(info);

	if (update)
	{
		UpdateReplayClient(info.iEnt);
	}
}

void KickReplay(bot_info_t info, int stopper = -1)
{
	if (info.iEnt <= 0)
	{
		return;
	}

	int starter = GetClientFromSerial(info.iStarterSerial);

	CancelReplay(info, stopper, false);

	if (1 <= info.iEnt <= MaxClients)
	{
		UpdateBotQuota(gI_ExpectedBots - 1);
		KickClient(info.iEnt);
	}
	else // Replay_Prop
	{
		if (starter != 0)
		{
			// Unset target so we don't get hud errors in the single frame the prop is still alive...
			SetEntPropEnt(starter, Prop_Send, "m_hObserverTarget", 0);
		}

		AcceptEntityInput(info.iEnt, "Kill");
	}

	info.iEnt = -1;
	info.iType = view_as<ReplayBotType>(-1);
}

float GetReplayLength(int style, int track, framecache_t aCache)
{
	if(aCache.iFrameCount == 0)
	{
		return 0.0;
	}
	
	if(aCache.bNewFormat)
	{
		return aCache.fTime;
	}

	return Shavit_GetWorldRecord(style, track) * Shavit_GetStyleSettingFloat(style, "speed");
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

public void TickRate_OnTickRateChanged(float fOld, float fNew)
{
	gF_Tickrate = fNew;
}

public void OnGameFrame()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (gA_BotInfo[i].iEnt <= 0 || gA_BotInfo[i].iType != Replay_Prop)
		{
			continue;
		}

		int buttons, impulse;
		float vel[3];

		ReplayRunCmd(gA_BotInfo[i], buttons, impulse, vel);

		/*
		if (!IsPlayerAlive(i))
		{
			float pos[3];
			GetEntPropVector(gA_BotInfo[i].iEnt, Prop_Send, "m_vecOrigin", pos);
			pos[2] += 64.0;
			TeleportEntity(i, pos, NULL_VECTOR, NULL_VECTOR);
		}
		*/
	}

	if (!gCV_EnableDynamicTimeDifference || !gCV_EnableDynamicTimeDifference.BoolValue)
	{
		return;
	}

	int valid = 0;
	int modtick = GetGameTickCount() % gCV_DynamicTimeTick.IntValue;

	for (int client = 1; client <= MaxClients; client++)
	{
		// Using modtick & valid to spread out client updates across different ticks.
		if (IsValidClient(client, true) && !IsFakeClient(client) && Shavit_GetTimerStatus(client) == Timer_Running && (++valid % gCV_DynamicTimeTick.IntValue) == modtick)
		{
			gF_TimeDifference[client] = GetClosestReplayTime(client);
		}
	}
}

// also calculates gF_VelocityDifference2D & gF_VelocityDifference3D
float GetClosestReplayTime(int client)
{
	int style = gI_TimeDifferenceStyle[client];
	int track = Shavit_GetClientTrack(client);

	if (gA_FrameCache[style][track].aFrames == null)
	{
		return -1.0;
	}

	int iLength = gA_FrameCache[style][track].aFrames.Length;

	if (iLength < 1)
	{
		return -1.0;
	}

	int iPreframes = gA_FrameCache[style][track].iPreFrames;
	int iSearch = RoundToFloor(gCV_DynamicTimeSearch.FloatValue * (1.0 / GetTickInterval()));
	int iPlayerFrames = gA_PlayerFrames[client].Length - gI_PlayerPrerunFrames[client];

	int iStartFrame = iPlayerFrames - iSearch;
	int iEndFrame = iPlayerFrames + iSearch;
	
	if(iSearch == 0)
	{
		iStartFrame = 0;
		iEndFrame = iLength - 1;
	}
	else
	{
		// Check if the search behind flag is off
		if(iStartFrame < 0 || gCV_DynamicTimeCheap.IntValue & 2 == 0)
		{
			iStartFrame = 0;
		}
		
		// check if the search ahead flag is off
		if(iEndFrame >= iLength || gCV_DynamicTimeCheap.IntValue & 1 == 0)
		{
			iEndFrame = iLength - 1;
		}
	}

	float fReplayPos[3];
	int iClosestFrame;
	// Single.MaxValue
	float fMinDist = view_as<float>(0x7f7fffff);

	float fClientPos[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", fClientPos);

	for(int frame = iStartFrame; frame < iEndFrame; frame++)
	{
		gA_FrameCache[style][track].aFrames.GetArray(frame, fReplayPos, 3);

		float dist = GetVectorDistance(fClientPos, fReplayPos, true);
		if(dist < fMinDist)
		{
			fMinDist = dist;
			iClosestFrame = frame;
		}
	}

	// out of bounds
	if(iClosestFrame == 0 || iClosestFrame == iEndFrame)
	{
		return -1.0;
	}

	// inside start zone
	if(iClosestFrame < iPreframes)
	{
		gF_VelocityDifference2D[client] = 0.0;
		gF_VelocityDifference3D[client] = 0.0;
		return 0.0;
	}

	float frametime = GetReplayLength(style, track, gA_FrameCache[style][track]) / float(gA_FrameCache[style][track].iFrameCount - iPreframes);
	float timeDifference = (iClosestFrame - iPreframes) * frametime;

	// Hides the hud if we are using the cheap search method and too far behind to be accurate
	if(iSearch > 0 && gCV_DynamicTimeCheap.BoolValue)
	{
		float preframes = float(gI_PlayerTimerStartFrames[client] - gI_PlayerPrerunFrames[client]) / (1.0 / GetTickInterval());
		if(Shavit_GetClientTime(client) - timeDifference >= gCV_DynamicTimeSearch.FloatValue - preframes)
		{
			return -1.0;
		}
	}

	float clientVel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", clientVel); // TODO: m_vecBaseVelocity? m_vecAbsVelocity?

	float fReplayPrevPos[3], fReplayClosestPos[3];
	gA_FrameCache[style][track].aFrames.GetArray(iClosestFrame, fReplayClosestPos, 3);
	gA_FrameCache[style][track].aFrames.GetArray(iClosestFrame == 0 ? 0 : iClosestFrame-1, fReplayPrevPos, 3);

	float replayVel[3];
	MakeVectorFromPoints(fReplayClosestPos, fReplayPrevPos, replayVel);
	ScaleVector(replayVel, gF_Tickrate);

	gF_VelocityDifference2D[client] = (SquareRoot(Pow(clientVel[0], 2.0) + Pow(clientVel[1], 2.0))) - (SquareRoot(Pow(replayVel[0], 2.0) + Pow(replayVel[1], 2.0)));
	gF_VelocityDifference3D[client] = GetVectorLength(clientVel) - GetVectorLength(replayVel);

	return timeDifference;
}
