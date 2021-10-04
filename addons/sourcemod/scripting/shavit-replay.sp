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
#include <profiler>
#include <dhooks>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <adminmenu>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#include <tf2>
#include <tf2_stocks>
#include <closestpos>

//#include <TickRateControl>
forward void TickRate_OnTickRateChanged(float fOld, float fNew);

// History of REPLAY_FORMAT_SUBVERSION:
// 0x01: standard origin[3], angles[2], and buttons
// 0x02: flags added movetype added
// 0x03: integrity stuff: style, track, and map added to header. preframe count added (unimplemented until later though)
// 0x04: steamid/accountid written as a 32-bit int instead of a string
// 0x05: postframes & fTickrate added
// 0x06: mousexy and vel added
// 0x07: fixed iFrameCount because postframes were included in the value when they shouldn't be
// 0x08: added zone-offsets to header

#define REPLAY_FORMAT_V2 "{SHAVITREPLAYFORMAT}{V2}"
#define REPLAY_FORMAT_FINAL "{SHAVITREPLAYFORMAT}{FINAL}"
#define REPLAY_FORMAT_SUBVERSION 0x08
#define REPLAY_FORMAT_CURRENT_USED_CELLS 8
#define FRAMES_PER_WRITE 100 // amounts of frames to write per read/write call
#define MAX_LOOPING_BOT_CONFIGS 24
#define HACKY_CLIENT_IDX_PROP "m_iTeamNum" // I store the client owner idx in this for Replay_Prop. My brain is too powerful.

#define DEBUG 0

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 2621440

enum struct replaystrings_t
{
	char sClanTag[MAX_NAME_LENGTH];
	char sNameStyle[MAX_NAME_LENGTH];
	char sCentralName[MAX_NAME_LENGTH];
	char sUnloaded[MAX_NAME_LENGTH];
}

enum struct loopingbot_config_t
{
	bool bEnabled;
	bool bSpawned;
	int iTrackMask; // only 9 bits needed for tracks
	int aStyleMask[8]; // all 256 bits needed for enabled styles
	char sName[MAX_NAME_LENGTH];
}

enum struct replay_header_t
{
	char sReplayFormat[40];
	int iReplayVersion;
	char sMap[PLATFORM_MAX_PATH];
	int iStyle;
	int iTrack;
	int iPreFrames;
	int iFrameCount;
	float fTime;
	int iSteamID;
	int iPostFrames;
	float fTickrate;
	float fZoneOffset[2];
}

enum struct bot_info_t
{
	int iEnt;
	int iStyle; // Shavit_GetReplayBotStyle
	int iStatus; // Shavit_GetReplayStatus
	int iType; // Shavit_GetReplayBotType
	int iTrack; // Shavit_GetReplayBotTrack
	int iStarterSerial; // Shavit_GetReplayStarter
	int iTick; // Shavit_GetReplayBotCurrentFrame
	int iLoopingConfig;
	Handle hTimer;
	float fFirstFrameTime; // Shavit_GetReplayBotFirstFrameTime
	bool bCustomFrames;
	bool bIgnoreLimit;
	bool b2x;
	float fDelay;
	frame_cache_t aCache;
}

enum struct finished_run_info
{
	int iSteamID;
	int style;
	float time;
	int jumps;
	int strafes;
	float sync;
	int track;
	float oldtime;
	float perfs;
	float avgvel;
	float maxvel;
	int timestamp;
	float fZoneOffset[2];
}

enum
{
	iBotShooting_Attack1 = (1 << 0),
	iBotShooting_Attack2 = (1 << 1)
}

enum
{
	CSS_ANIM_FIRE_GUN_PRIMARY,
	CSS_ANIM_FIRE_GUN_SECONDARY,
	CSS_ANIM_THROW_GRENADE,
	CSS_ANIM_JUMP
}

enum
{
	TF2_ANIM_JUMP = 6
}

enum
{
	CSGO_ANIM_FIRE_GUN_PRIMARY,
	CSGO_ANIM_FIRE_GUN_PRIMARY_OPT,
	CSGO_ANIM_FIRE_GUN_PRIMARY__SPECIAL,
	CSGO_ANIM_FIRE_GUN_PRIMARY_OPT_SPECIAL,
	CSGO_ANIM_FIRE_GUN_SECONDARY,
	CSGO_ANIM_FIRE_GUN_SECONDARY_SPECIAL,
	CSGO_ANIM_GRENADE_PULL_PIN,
	CSGO_ANIM_THROW_GRENADE,
	CSGO_ANIM_JUMP
}

// custom cvar settings
char gS_ForcedCvars[][][] =
{
	{ "bot_quota", "0" },
	{ "bot_stop", "1" },
	{ "bot_quota_mode", "normal" },
	{ "tf_bot_quota_mode", "normal" },
	{ "mp_limitteams", "0" },
	{ "bot_chatter", "off" },
	{ "bot_flipout", "1" },
	{ "bot_zombie", "1" },
	{ "mp_autoteambalance", "0" },
	{ "bot_controllable", "0" }
};

// game type
EngineVersion gEV_Type = Engine_Unknown;
bool gB_Linux;

// cache
char gS_ReplayFolder[PLATFORM_MAX_PATH];

frame_cache_t gA_FrameCache[STYLE_LIMIT][TRACKS_SIZE];

// stuff related to postframes
finished_run_info gA_FinishedRunInfo[MAXPLAYERS+1];
bool gB_GrabbingPostFrames[MAXPLAYERS+1];
Handle gH_PostFramesTimer[MAXPLAYERS+1];
int gI_PlayerFinishFrame[MAXPLAYERS+1];

bool gB_Button[MAXPLAYERS+1];
// we use gI_PlayerFrames instead of grabbing gA_PlayerFrames.Length because the ArrayList is resized to handle 2s worth of extra frames to reduce how often we have to resize it
int gI_PlayerFrames[MAXPLAYERS+1];
int gI_PlayerPrerunFrames[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];
int gI_MenuTrack[MAXPLAYERS+1];
int gI_MenuStyle[MAXPLAYERS+1];
int gI_MenuType[MAXPLAYERS+1];
bool gB_InReplayMenu[MAXPLAYERS+1];
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
char gS_Map[PLATFORM_MAX_PATH];

// replay bot stuff
int gI_CentralBot = -1;
loopingbot_config_t gA_LoopingBotConfig[MAX_LOOPING_BOT_CONFIGS];
int gI_DynamicBots = 0;
// Replay_Prop: index with starter/watcher
// Replay_ANYTHINGELSE: index with fakeclient index
bot_info_t gA_BotInfo[MAXPLAYERS+1];

// hooks and sdkcall stuff
Handle gH_BotAddCommand = INVALID_HANDLE;
Handle gH_DoAnimationEvent = INVALID_HANDLE ;
DynamicDetour gH_MaintainBotQuota = null;
DynamicDetour gH_TeamFull = null;
int gI_WEAPONTYPE_UNKNOWN = 123123123;
int gI_LatestClient = -1;
int gI_LastReplayFlags[MAXPLAYERS + 1];
float gF_EyeOffset;
float gF_EyeOffsetDuck;

// how do i call this
bool gB_HideNameChange = false;
int gI_HijackFrames[MAXPLAYERS+1];
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
Convar gCV_PlaybackPostRunTime = null;
Convar gCV_PreRunAlways = null;
Convar gCV_DynamicTimeSearch = null;
Convar gCV_DynamicTimeCheap = null;
Convar gCV_DynamicTimeTick = null;
Convar gCV_EnableDynamicTimeDifference = null;
ConVar sv_duplicate_playernames_ok = null;
ConVar bot_join_after_player = null;
ConVar mp_randomspawn = null;

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
Database2 gH_SQL = null;
char gS_MySQLPrefix[32];

bool gB_ClosestPos;
ClosestPos gH_ClosestPos[TRACKS_SIZE][STYLE_LIMIT];

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
	CreateNative("Shavit_GetReplayBotFirstFrameTime", Native_GetReplayBotFirstFrameTime);
	CreateNative("Shavit_GetReplayBotIndex", Native_GetReplayBotIndex);
	CreateNative("Shavit_GetReplayBotStyle", Native_GetReplayBotStyle);
	CreateNative("Shavit_GetReplayBotTrack", Native_GetReplayBotTrack);
	CreateNative("Shavit_GetReplayBotType", Native_GetReplayBotType);
	CreateNative("Shavit_GetReplayStarter", Native_GetReplayStarter);
	CreateNative("Shavit_GetReplayButtons", Native_GetReplayButtons);
	CreateNative("Shavit_GetReplayData", Native_GetReplayData);
	CreateNative("Shavit_GetReplayFrames", Native_GetReplayFrames);
	CreateNative("Shavit_GetReplayFrameCount", Native_GetReplayFrameCount);
	CreateNative("Shavit_GetReplayPreFrames", Native_GetReplayPreFrames);
	CreateNative("Shavit_GetReplayPostFrames", Native_GetReplayPostFrames);
	CreateNative("Shavit_GetReplayCacheFrameCount", Native_GetReplayCacheFrameCount);
	CreateNative("Shavit_GetReplayCachePreFrames", Native_GetReplayCachePreFrames);
	CreateNative("Shavit_GetReplayCachePostFrames", Native_GetReplayCachePostFrames);
	CreateNative("Shavit_GetReplayLength", Native_GetReplayLength);
	CreateNative("Shavit_GetReplayCacheLength", Native_GetReplayCacheLength);
	CreateNative("Shavit_GetReplayName", Native_GetReplayName);
	CreateNative("Shavit_GetReplayCacheName", Native_GetReplayCacheName);
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
	CreateNative("Shavit_GetPlayerPreFrames", Native_GetPlayerPreFrames);
	CreateNative("Shavit_SetPlayerPreFrames", Native_SetPlayerPreFrames);
	CreateNative("Shavit_GetClosestReplayTime", Native_GetClosestReplayTime);
	CreateNative("Shavit_GetClosestReplayStyle", Native_GetClosestReplayStyle);
	CreateNative("Shavit_SetClosestReplayStyle", Native_SetClosestReplayStyle);
	CreateNative("Shavit_GetClosestReplayVelocityDifference", Native_GetClosestReplayVelocityDifference);
	CreateNative("Shavit_StartReplayFromFrameCache", Native_StartReplayFromFrameCache);
	CreateNative("Shavit_StartReplayFromFile", Native_StartReplayFromFile);
	CreateNative("Shavit_GetLoopingBotByName", Native_GetLoopingBotByName);
	CreateNative("Shavit_SetReplayCacheName", Native_SetReplayCacheName);

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

	if (LibraryExists("closestpos"))
	{
		gB_ClosestPos = true;
	}
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-replay.phrases");

	// forwards
	gH_OnReplayStart = CreateGlobalForward("Shavit_OnReplayStart", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_OnReplayEnd = CreateGlobalForward("Shavit_OnReplayEnd", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_OnReplaysLoaded = CreateGlobalForward("Shavit_OnReplaysLoaded", ET_Event);
	gH_ShouldSaveReplayCopy = CreateGlobalForward("Shavit_ShouldSaveReplayCopy", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnReplaySaved = CreateGlobalForward("Shavit_OnReplaySaved", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_String);
	
	// game specific
	gEV_Type = GetEngineVersion();
	gF_Tickrate = (1.0 / GetTickInterval());

	switch (gEV_Type)
	{
		case Engine_TF2:
		{
			gF_EyeOffset = 75.0; // maybe should be a gamedata thing...
			gF_EyeOffsetDuck = 45.0;
		}
		case Engine_CSGO:
		{
			gF_EyeOffset = 64.0;
			gF_EyeOffsetDuck = 46.0;
		}
		case Engine_CSS:
		{
			gF_EyeOffset = 64.0;
			gF_EyeOffsetDuck = 47.0;
		}
	}

	ConVar bot_stop = FindConVar("bot_stop");

	if (bot_stop != null)
	{
		bot_stop.Flags &= ~FCVAR_CHEAT;
	}

	bot_join_after_player = FindConVar(gEV_Type == Engine_TF2 ? "tf_bot_join_after_player" : "bot_join_after_player");

	mp_randomspawn = FindConVar("mp_randomspawn");

	sv_duplicate_playernames_ok = FindConVar("sv_duplicate_playernames_ok");

	if (sv_duplicate_playernames_ok != null)
	{
		sv_duplicate_playernames_ok.Flags &= ~FCVAR_REPLICATED;
	}

	for(int i = 0; i < sizeof(gS_ForcedCvars); i++)
	{
		ConVar hCvar = FindConVar(gS_ForcedCvars[i][0]);

		if(hCvar != null)
		{
			hCvar.SetString(gS_ForcedCvars[i][1]);
			hCvar.AddChangeHook(OnForcedConVarChanged);
		}
	}

	// plugin convars
	gCV_Enabled = new Convar("shavit_replay_enabled", "1", "Enable replay bot functionality?", 0, true, 0.0, true, 1.0);
	gCV_ReplayDelay = new Convar("shavit_replay_delay", "2.5", "Time to wait before restarting the replay after it finishes playing.", 0, true, 0.0, true, 10.0);
	gCV_TimeLimit = new Convar("shavit_replay_timelimit", "7200.0", "Maximum amount of time (in seconds) to allow saving to disk.\nDefault is 7200 (2 hours)\n0 - Disabled");
	gCV_DefaultTeam = new Convar("shavit_replay_defaultteam", "3", "Default team to make the bots join, if possible.\n2 - Terrorists/RED\n3 - Counter Terrorists/BLU", 0, true, 2.0, true, 3.0);
	gCV_CentralBot = new Convar("shavit_replay_centralbot", "1", "Have one central bot instead of one bot per replay.\nTriggered with !replay.\nRestart the map for changes to take effect.\nThe disabled setting is not supported - use at your own risk.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_DynamicBotLimit = new Convar("shavit_replay_dynamicbotlimit", "3", "How many extra bots next to the central bot can be spawned with !replay.\n0 - no dynamically spawning bots.", 0, true, 0.0, true, float(MaxClients-2));
	gCV_AllowPropBots = new Convar("shavit_replay_allowpropbots", "1", "Should players be able to view replays through a prop instead of a bot?", 0, true, 0.0, true, 1.0);
	gCV_BotShooting = new Convar("shavit_replay_botshooting", "3", "Attacking buttons to allow for bots.\n0 - none\n1 - +attack\n2 - +attack2\n3 - both", 0, true, 0.0, true, 3.0);
	gCV_BotPlusUse = new Convar("shavit_replay_botplususe", "1", "Allow bots to use +use?", 0, true, 0.0, true, 1.0);
	gCV_BotWeapon = new Convar("shavit_replay_botweapon", "", "Choose which weapon the bot will hold.\nLeave empty to use the default.\nSet to \"none\" to have none.\nExample: weapon_usp");
	gCV_PlaybackCanStop = new Convar("shavit_replay_pbcanstop", "1", "Allow players to stop playback if they requested it?", 0, true, 0.0, true, 1.0);
	gCV_PlaybackCooldown = new Convar("shavit_replay_pbcooldown", "3.5", "Cooldown in seconds to apply for players between each playback they request/stop.\nDoes not apply to RCON admins.", 0, true, 0.0);
	gCV_PlaybackPreRunTime = new Convar("shavit_replay_preruntime", "1.5", "Time (in seconds) to record before a player leaves start zone.", 0, true, 0.0, true, 2.0);
	gCV_PlaybackPostRunTime = new Convar("shavit_replay_postruntime", "1.5", "Time (in seconds) to record after a player enters the end zone.", 0, true, 0.0, true, 2.0);
	gCV_PreRunAlways = new Convar("shavit_replay_prerun_always", "1", "Record prerun frames outside the start zone?", 0, true, 0.0, true, 1.0);
	gCV_DynamicTimeCheap = new Convar("shavit_replay_timedifference_cheap", "0.0", "0 - Disabled\n1 - only clip the search ahead to shavit_replay_timedifference_search\n2 - only clip the search behind to players current frame\n3 - clip the search to +/- shavit_replay_timedifference_search seconds to the players current frame", 0, true, 0.0, true, 3.0);
	gCV_DynamicTimeSearch = new Convar("shavit_replay_timedifference_search", "0.0", "Time in seconds to search the players current frame for dynamic time differences\n0 - Full Scan\nNote: Higher values will result in worse performance", 0, true, 0.0);
	gCV_EnableDynamicTimeDifference = new Convar("shavit_replay_timedifference", "0", "Enabled dynamic time/velocity differences for the hud", 0, true, 0.0, true, 1.0);

	char tenth[6];
	IntToString(RoundToFloor(1.0 / GetTickInterval() / 10), tenth, sizeof(tenth));
	gCV_DynamicTimeTick = new Convar("shavit_replay_timedifference_tick", tenth, "How often (in ticks) should the time difference update.\nYou should probably keep this around 0.1s worth of ticks.\nThe maximum value is your tickrate.", 0, true, 1.0, true, (1.0 / GetTickInterval()));

	Convar.AutoExecConfig();

	gCV_CentralBot.AddChangeHook(OnConVarChanged);
	gCV_DynamicBotLimit.AddChangeHook(OnConVarChanged);
	gCV_AllowPropBots.AddChangeHook(OnConVarChanged);

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
	gH_SQL = GetTimerDatabaseHandle2();

	LoadDHooks();

	CreateAllNavFiles();

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount());
		Shavit_OnChatConfigLoaded();
	}
	
	for(int i = 1; i <= MaxClients; i++)
	{
		ClearBotInfo(gA_BotInfo[i]);

		if (gB_Late && IsValidClient(i) && !IsFakeClient(i))
		{
			OnClientPutInServer(i);
		}
	}
}

void LoadDHooks()
{
	GameData gamedata = new GameData("shavit.games");

	if (gamedata == null)
	{
		SetFailState("Failed to load shavit gamedata");
	}

	gB_Linux = (gamedata.GetOffset("OS") == 2);

	if (gEV_Type == Engine_TF2)
	{
		StartPrepSDKCall(SDKCall_Static);

		if (!PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "NextBotCreatePlayerBot<CTFBot>"))
		{
			SetFailState("Failed to get NextBotCreatePlayerBot<CTFBot>");
		}

		PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);       // const char *name
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);   // bool bReportFakeClient
		PrepSDKCall_SetReturnInfo(SDKType_CBasePlayer, SDKPass_Pointer); // CTFBot*

		if (!(gH_BotAddCommand = EndPrepSDKCall()))
		{
			SetFailState("Unable to prepare SDKCall for NextBotCreatePlayerBot<CTFBot>");
		}
	}
	else
	{
		StartPrepSDKCall(gB_Linux ? SDKCall_Raw : SDKCall_Static);

		if (!PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CCSBotManager::BotAddCommand"))
		{
			SetFailState("Failed to get CCSBotManager::BotAddCommand");
		}

		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);  // int team
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);  // bool isFromConsole
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);  // const char *profileName
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);  // CSWeaponType weaponType
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);  // BotDifficultyType difficulty
		PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain); // bool

		if (!(gH_BotAddCommand = EndPrepSDKCall()))
		{
			SetFailState("Unable to prepare SDKCall for CCSBotManager::BotAddCommand");
		}

		if ((gI_WEAPONTYPE_UNKNOWN = gamedata.GetOffset("WEAPONTYPE_UNKNOWN")) == -1)
		{
			SetFailState("Failed to get WEAPONTYPE_UNKNOWN");
		}
	}

	if (!(gH_MaintainBotQuota = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_Address)))
	{
		SetFailState("Failed to create detour for BotManager::MaintainBotQuota");
	}

	if (!DHookSetFromConf(gH_MaintainBotQuota, gamedata, SDKConf_Signature, "BotManager::MaintainBotQuota"))
	{
		SetFailState("Failed to get address for BotManager::MaintainBotQuota");
	}

	gH_MaintainBotQuota.Enable(Hook_Pre, Detour_MaintainBotQuota);

	if (gEV_Type == Engine_CSS)
	{
		if (!(gH_TeamFull = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Bool, ThisPointer_Address)))
		{
			SetFailState("Failed to create detour for CCSGameRules::TeamFull");
		}

		gH_TeamFull.AddParam(HookParamType_Int); // Team ID

		if (!gH_TeamFull.SetFromConf(gamedata, SDKConf_Signature, "CCSGameRules::TeamFull"))
		{
			SetFailState("Failed to get address for CCSGameRules::TeamFull");
		}
	}

	StartPrepSDKCall(gB_Linux ? SDKCall_Static : SDKCall_Player);

	if (PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "Player::DoAnimationEvent"))
	{
		if(gB_Linux)
		{
			PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_ByRef);
		}
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_ByValue);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_ByValue);
	}

	gH_DoAnimationEvent = EndPrepSDKCall();

	delete gamedata;
}

// Stops bot_quota from doing anything.
public MRESReturn Detour_MaintainBotQuota(int pThis)
{
	return MRES_Supercede;
}

public MRESReturn Detour_TeamFull(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	hReturn.Value = false;
	return MRES_Supercede;
}

public void OnPluginEnd()
{
	KickAllReplays();
}

void KickAllReplays()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (gA_BotInfo[i].iEnt > 0)
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
	else if (strcmp(name, "closestpos") == 0)
	{
		gB_ClosestPos = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "adminmenu") == 0)
	{
		gH_AdminMenu = null;
		gH_TimerCommands = INVALID_TOPMENUOBJECT;
	}
	else if (strcmp(name, "closestpos") == 0)
	{
		gB_ClosestPos = false;
	}
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	OnMapStart();
}

public void OnForcedConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char sName[32];
	convar.GetName(sName, 32);

	for(int i = 0; i < sizeof(gS_ForcedCvars); i++)
	{
		if(StrEqual(sName, gS_ForcedCvars[i][0]))
		{
			if(!StrEqual(newValue, gS_ForcedCvars[i][1]))
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

void FinishReplay(bot_info_t info)
{
	Call_StartForward(gH_OnReplayEnd);
	Call_PushCell(info.iEnt);
	Call_PushCell(info.iType);
	Call_PushCell(true); // actually_finished
	Call_Finish();

	int starter = GetClientFromSerial(info.iStarterSerial);

	if (info.iType == Replay_Dynamic || info.iType == Replay_Prop)
	{
		KickReplay(info);
	}
	else if (info.iType == Replay_Looping)
	{
		int nexttrack = info.iTrack;
		int nextstyle = info.iStyle;
		bool hasFrames = FindNextLoop(nexttrack, nextstyle, info.iLoopingConfig);

		if (hasFrames)
		{
			ClearBotInfo(info);
			StartReplay(info, nexttrack, nextstyle, 0, gCV_ReplayDelay.FloatValue);
		}
		else
		{
			KickReplay(info);
		}
	}
	else if (info.iType == Replay_Central)
	{
		if (info.aCache.aFrames != null)
		{
			TeleportToFrame(info, 0);
		}

		ClearBotInfo(info);
	}

	if (starter > 0)
	{
		gF_LastInteraction[starter] = GetEngineTime();
		gA_BotInfo[starter].iEnt = -1;

		if (gB_InReplayMenu[starter])
		{
			OpenReplayMenu(starter); // Refresh menu so Spawn Replay option shows up again...
		}
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

		CancelReplay(gA_BotInfo[i], false);

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
	ClearFrameCache(gA_FrameCache[style][track]);
	delete gH_ClosestPos[track][style];

	bool loaded = false;

	if (reload)
	{
		if(strlen(path) > 0)
		{
			loaded = LoadReplay(gA_FrameCache[style][track], style, track, path, gS_Map);
		}
		else
		{
			loaded = DefaultLoadReplay(gA_FrameCache[style][track], style, track);
		}
	}

	StopOrRestartBots(style, track, restart);

	return loaded;
}

public int Native_DeleteReplay(Handle handler, int numParams)
{
	char sMap[PLATFORM_MAX_PATH];
	GetNativeString(1, sMap, sizeof(sMap));

	int iStyle = GetNativeCell(2);
	int iTrack = GetNativeCell(3);
	int iSteamID = GetNativeCell(4);

	return DeleteReplay(iStyle, iTrack, iSteamID, sMap);
}

public int Native_GetReplayBotFirstFrameTime(Handle handler, int numParams)
{
	return view_as<int>(gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].fFirstFrameTime);
}

public int Native_GetReplayBotCurrentFrame(Handle handler, int numParams)
{
	return gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].iTick;
}

public int Native_GetReplayBotIndex(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = -1;

	if (numParams > 1)
	{
		track = GetNativeCell(2);
	}

	if (track == -1 && style == -1 && gI_CentralBot > 0)
	{
		return gI_CentralBot;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (gA_BotInfo[i].iEnt > 0 && gA_BotInfo[i].iType != Replay_Prop)
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

void StartReplay(bot_info_t info, int track, int style, int starter, float delay)
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
	info.fDelay = delay;
	info.hTimer = CreateTimer((delay / 2.0), Timer_StartReplay, info.iEnt, TIMER_FLAG_NO_MAPCHANGE);

	if (!info.bCustomFrames)
	{
		info.aCache = gA_FrameCache[style][track];
		info.aCache.aFrames = view_as<ArrayList>(CloneHandle(info.aCache.aFrames));
	}

	TeleportToFrame(info, 0);
	UpdateReplayClient(info.iEnt);

	if (starter > 0 && GetClientTeam(starter) != 1)
	{
		ChangeClientTeam(starter, 1);
	}

	if (starter > 0 && info.iType != Replay_Prop)
	{
		gA_BotInfo[starter].iEnt = info.iEnt;
		// Timer is used because the bot's name is missing and profile pic random if using RequestFrame...
		// I really have no idea. Even delaying by 5 frames wasn't enough. Broken game.
		// Maybe would need to be delayed by the player's latency but whatever...
		// It seems to use early steamids for pfps since I've noticed BAILPAN and EricS 's avatars...
		CreateTimer(0.2, Timer_SpectateMyBot, GetClientSerial(info.iEnt), TIMER_FLAG_NO_MAPCHANGE);
	}

	Call_StartForward(gH_OnReplayStart);
	Call_PushCell(info.iEnt);
	Call_PushCell(info.iType);
	Call_PushCell(false); // delay_elapsed
	Call_Finish();
}

public int Native_IsReplayEntity(Handle handler, int numParams)
{
	int ent = GetNativeCell(1);
	return (gA_BotInfo[GetBotInfoIndex(ent)].iEnt == ent);
}

void SetupIfCustomFrames(bot_info_t info, frame_cache_t cache)
{
	info.bCustomFrames = false;

	if (cache.aFrames != null)
	{
		info.bCustomFrames = true;
		cache.aFrames = view_as<ArrayList>(CloneHandle(cache.aFrames));
		info.aCache = cache;
	}
}

int CreateReplayEntity(int track, int style, float delay, int client, int bot, int type, bool ignorelimit, frame_cache_t cache, int loopingConfig)
{
	if (client > 0 && gA_BotInfo[client].iEnt > 0)
	{
		return 0;
	}

	if (delay == -1.0)
	{
		delay = gCV_ReplayDelay.FloatValue;
	}

	if (bot == -1)
	{
		if (type == Replay_Prop)
		{
			if (!IsValidClient(client))
			{
				return 0;
			}

			bot = CreateReplayProp(client);

			if (!IsValidEntity(bot))
			{
				return 0;
			}

			SetupIfCustomFrames(gA_BotInfo[client], cache);
			StartReplay(gA_BotInfo[client], gI_MenuTrack[client], gI_MenuStyle[client], client, delay);
		}
		else
		{
			if (type == Replay_Dynamic)
			{
				if (!ignorelimit && gI_DynamicBots >= gCV_DynamicBotLimit.IntValue)
				{
					return 0;
				}
			}

			bot_info_t info;
			info.iType = type;
			info.iStyle = style;
			info.iTrack = track;
			info.iStarterSerial = (client > 0) ? GetClientSerial(client) : 0;
			info.bIgnoreLimit = ignorelimit;
			info.iLoopingConfig = loopingConfig;
			info.fDelay = delay;
			SetupIfCustomFrames(info, cache);
			bot = CreateReplayBot(info);

			if (bot != 0)
			{
				if (client > 0)
				{
					gA_BotInfo[client].iEnt = bot;
				}

				if (type == Replay_Dynamic && !ignorelimit)
				{
					++gI_DynamicBots;
				}
			}
		}
	}
	else
	{
		int index = GetBotInfoIndex(bot);

		if (index < 1)
		{
			return 0;
		}

		type = gA_BotInfo[index].iType;

		if (type != Replay_Central && type != Replay_Dynamic && type != Replay_Prop)
		{
			return 0;
		}

		CancelReplay(gA_BotInfo[index], false);
		SetupIfCustomFrames(gA_BotInfo[index], cache);
		StartReplay(gA_BotInfo[index], track, style, client, delay);
	}

	return bot;
}

public int Native_StartReplay(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	float delay = GetNativeCell(3);
	int client = GetNativeCell(4);
	int bot = GetNativeCell(5);
	int type = GetNativeCell(6);
	bool ignorelimit = view_as<bool>(GetNativeCell(7));

	frame_cache_t cache; // null cache
	return CreateReplayEntity(track, style, delay, client, bot, type, ignorelimit, cache, 0);
}

public int Native_StartReplayFromFrameCache(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	float delay = GetNativeCell(3);
	int client = GetNativeCell(4);
	int bot = GetNativeCell(5);
	int type = GetNativeCell(6);
	bool ignorelimit = view_as<bool>(GetNativeCell(7));

	if(GetNativeCell(9) != sizeof(frame_cache_t))
	{
		return ThrowNativeError(200, "frame_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(9), sizeof(frame_cache_t));
	}

	frame_cache_t cache;
	GetNativeArray(8, cache, sizeof(cache));

	return CreateReplayEntity(track, style, delay, client, bot, type, ignorelimit, cache, 0);
}

public int Native_StartReplayFromFile(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	float delay = GetNativeCell(3);
	int client = GetNativeCell(4);
	int bot = GetNativeCell(5);
	int type = GetNativeCell(6);
	bool ignorelimit = view_as<bool>(GetNativeCell(7));

	char path[PLATFORM_MAX_PATH];
	GetNativeString(8, path, sizeof(path));

	frame_cache_t cache; // null cache

	if (!LoadReplay(cache, style, track, path, gS_Map))
	{
		return 0;
	}

	return CreateReplayEntity(track, style, delay, client, bot, type, ignorelimit, cache, 0);
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
	ArrayList data = view_as<ArrayList>(GetNativeCell(2));
	bool cheapCloneHandle = view_as<bool>(GetNativeCell(3));

	if (gB_GrabbingPostFrames[client])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client]);
	}

	if (cheapCloneHandle)
	{
		data = view_as<ArrayList>(CloneHandle(data));
	}
	else
	{
		data = data.Clone();
	}

	delete gA_PlayerFrames[client];
	gA_PlayerFrames[client] = data;
	gI_PlayerFrames[client] = data.Length;
}

public int Native_GetReplayData(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool cheapCloneHandle = view_as<bool>(GetNativeCell(2));
	Handle cloned = null;

	if(gA_PlayerFrames[client] != null)
	{
		ArrayList frames = cheapCloneHandle ? gA_PlayerFrames[client] : gA_PlayerFrames[client].Clone();
		frames.Resize(gI_PlayerFrames[client]);
		cloned = CloneHandle(frames, plugin); // set the calling plugin as the handle owner

		if (!cheapCloneHandle)
		{
			// Only hit for .Clone()'d handles. .Clone() != CloneHandle()
			CloseHandle(frames);
		}
	}

	return view_as<int>(cloned);
}

public int Native_GetReplayFrames(Handle plugin, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	bool cheapCloneHandle = (numParams > 2) && view_as<bool>(GetNativeCell(3));
	Handle cloned = null;

	if(gA_FrameCache[style][track].aFrames != null)
	{
		ArrayList frames = cheapCloneHandle ? gA_FrameCache[style][track].aFrames : gA_FrameCache[style][track].aFrames.Clone();
		cloned = CloneHandle(frames, plugin); // set the calling plugin as the handle owner

		if (!cheapCloneHandle)
		{
			// Only hit for .Clone()'d handles. .Clone() != CloneHandle()
			CloseHandle(frames);
		}
	}

	return view_as<int>(cloned);
}

public int Native_GetReplayFrameCount(Handle handler, int numParams)
{
	return gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].iFrameCount;
}

public int Native_GetReplayPreFrames(Handle plugin, int numParams)
{
	return gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].iPreFrames;
}

public int Native_GetReplayPostFrames(Handle plugin, int numParams)
{
	return gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].iPostFrames;
}

public int Native_GetReplayCacheFrameCount(Handle handler, int numParams)
{
	int bot = GetNativeCell(1);
	int index = GetBotInfoIndex(bot);
	return gA_BotInfo[index].aCache.iFrameCount;
}

public int Native_GetReplayCachePreFrames(Handle plugin, int numParams)
{
	return gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].aCache.iPreFrames;
}

public int Native_GetReplayCachePostFrames(Handle plugin, int numParams)
{
	return gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].aCache.iPostFrames;
}

public int Native_GetClientFrameCount(Handle handler, int numParams)
{
	return gI_PlayerFrames[GetNativeCell(1)];
}

public int Native_GetReplayLength(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	return view_as<int>(GetReplayLength(style, track, gA_FrameCache[style][track]));
}

public int Native_GetReplayCacheLength(Handle handler, int numParams)
{
	int bot = GetNativeCell(1);
	int index = GetBotInfoIndex(bot);
	return view_as<int>(GetReplayLength(gA_BotInfo[index].iStyle,  gA_BotInfo[index].iTrack, gA_BotInfo[index].aCache));
}

public int Native_GetReplayName(Handle handler, int numParams)
{
	return SetNativeString(3, gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].sReplayName, GetNativeCell(4));
}

public int Native_GetReplayCacheName(Handle plugin, int numParams)
{
	return SetNativeString(2, gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].aCache.sReplayName, GetNativeCell(3));
}

public int Native_GetReplayStatus(Handle handler, int numParams)
{
	return gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].iStatus;
}

public any Native_GetReplayTime(Handle handler, int numParams)
{
	int index = GetBotInfoIndex(GetNativeCell(1));

	if (gA_BotInfo[index].iTick > (gA_BotInfo[index].aCache.iFrameCount + gA_BotInfo[index].aCache.iPreFrames))
	{
		return gA_BotInfo[index].aCache.fTime;
	}

	return float(gA_BotInfo[index].iTick - gA_BotInfo[index].aCache.iPreFrames) / gF_Tickrate * Shavit_GetStyleSettingFloat(gA_BotInfo[index].iStyle, "timescale");
}

public int Native_HijackAngles(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	gF_HijackedAngles[client][0] = view_as<float>(GetNativeCell(2));
	gF_HijackedAngles[client][1] = view_as<float>(GetNativeCell(3));
	gI_HijackFrames[client] = GetNativeCell(4);
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
	return gA_BotInfo[GetBotInfoIndex(GetNativeCell(1))].iType;
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
	gA_BotInfo[bot].aCache.aFrames.GetArray(gA_BotInfo[bot].iTick ? gA_BotInfo[bot].iTick-1 : 0, aFrame, 6);
	float prevAngle = aFrame.ang[1];
	gA_BotInfo[bot].aCache.aFrames.GetArray(gA_BotInfo[bot].iTick, aFrame, 6);

	SetNativeCellRef(2, GetAngleDiff(aFrame.ang[1], prevAngle));
	return aFrame.buttons;
}

public int Native_Replay_DeleteMap(Handle handler, int numParams)
{
	char sMap[PLATFORM_MAX_PATH];
	GetNativeString(1, sMap, sizeof(sMap));
	LowercaseString(sMap);

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

public int Native_GetPlayerPreFrames(Handle handler, int numParams)
{
	return gI_PlayerPrerunFrames[GetNativeCell(1)];
}

public int Native_SetPlayerPreFrames(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int preframes = GetNativeCell(2);

	gI_PlayerPrerunFrames[client] = preframes;
}

public int Native_GetClosestReplayTime(Handle plugin, int numParams)
{
	if (!gCV_EnableDynamicTimeDifference.BoolValue)
	{
		return view_as<int>(-1.0);
	}

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

public int Native_GetLoopingBotByName(Handle plugin, int numParams)
{
	char name[PLATFORM_MAX_PATH];
	GetNativeString(1, name, sizeof(name));

	int configid = -1;

	for (int i = 0; i < MAX_LOOPING_BOT_CONFIGS; i++)
	{
		if (StrEqual(gA_LoopingBotConfig[i].sName, name))
		{
			configid = i;
			break;
		}
	}

	if (configid == -1)
	{
		return -1;
	}

	for (int i = 1; i <= MAXPLAYERS; i++)
	{
		if (gA_BotInfo[i].iType == Replay_Looping && gA_BotInfo[i].iLoopingConfig == configid)
		{
			return i;
		}
	}

	return 0;
}

public int Native_SetReplayCacheName(Handle plugin, int numParams)
{
	char name[MAX_NAME_LENGTH];
	GetNativeString(2, name, sizeof(name));

	int index = GetBotInfoIndex(GetNativeCell(1));
	gA_BotInfo[index].aCache.sReplayName = name;

	return 0;
}

public Action Timer_Cron(Handle Timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (gA_BotInfo[i].iEnt != i)
		{
			continue;
		}

		UpdateReplayClient(gA_BotInfo[i].iEnt);
	}

	if (!bot_join_after_player.BoolValue || GetClientCount() >= 1)
	{
		AddReplayBots();
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

void CreateAllNavFiles()
{
	StringMap mapList = new StringMap();
	DirectoryListing dir = OpenDirectory("maps", true);

	if (dir == null)
	{
		return;
	}

	char fileName[PLATFORM_MAX_PATH];
	FileType type;

	// Loop through maps folder.
	// If .bsp, mark as need .nav
	// If .nav, mark as have .nav
	while (dir.GetNext(fileName, sizeof(fileName), type))
	{
		if (type != FileType_File)
		{
			continue;
		}

		int length = strlen(fileName);

		if (length < 5 || fileName[length-4] != '.') // a.bsp
		{
			continue;
		}

		if (fileName[length-3] == 'b' && fileName[length-2] == 's' && fileName[length-1] == 'p')
		{
			fileName[length-4] = 0;
			mapList.SetValue(fileName, false, false); // note: false for 'replace'
		}
		else if (fileName[length-3] == 'n' && fileName[length-2] == 'a' && fileName[length-1] == 'v')
		{
			fileName[length-4] = 0;
			mapList.SetValue(fileName, true, true); // note: true for 'replace'
		}
	}

	delete dir;

	// StringMap shenanigans are used so we don't call FileExists() 2000 times
	StringMapSnapshot snapshot = mapList.Snapshot();

	for (int i = 0; i < snapshot.Length; i++)
	{
		snapshot.GetKey(i, fileName, sizeof(fileName));

		bool hasNAV = false;
		mapList.GetValue(fileName, hasNAV);

		if (!hasNAV)
		{
			WriteNavMesh(fileName, true);
		}
	}

	delete snapshot;
	delete mapList;
}

public void OnMapStart()
{
	if(!LoadStyling())
	{
		SetFailState("Could not load the replay bots' configuration file. Make sure it exists (addons/sourcemod/configs/shavit-replay.cfg) and follows the proper syntax!");
	}

	GetCurrentMap(gS_Map, sizeof(gS_Map));
	bool bWorkshopWritten = WriteNavMesh(gS_Map); // write "maps/workshop/123123123/bhop_map.nav"
	GetMapDisplayName(gS_Map, gS_Map, sizeof(gS_Map));
	bool bDisplayWritten = WriteNavMesh(gS_Map); // write "maps/bhop_map.nav"
	LowercaseString(gS_Map);

	// Likely won't run unless this is a workshop map since CreateAllNavFiles() is ran in OnPluginStart()
	if (bWorkshopWritten || bDisplayWritten)
	{
		SetCommandFlags("nav_load", GetCommandFlags("nav_load") & ~FCVAR_CHEAT);
		ServerCommand("nav_load");
	}

	KickAllReplays();

	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	PrecacheModel((gEV_Type == Engine_TF2)? "models/error.mdl":"models/props/cs_office/vending_machine.mdl");

	if (!DirExists(gS_ReplayFolder) && !CreateDirectory(gS_ReplayFolder, 511))
	{
		SetFailState("Failed to create replay folder (%s). Make sure you have file permissions", gS_ReplayFolder);
	}

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/copy", gS_ReplayFolder);

	if (!DirExists(sPath) && !CreateDirectory(sPath, 511))
	{
		SetFailState("Failed to create replay copy folder (%s). Make sure you have file permissions", sPath);
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d", gS_ReplayFolder, i);

		if (!DirExists(sPath) && !CreateDirectory(sPath, 511))
		{
			SetFailState("Failed to create replay style folder (%s). Make sure you have file permissions", sPath);
		}

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			ClearFrameCache(gA_FrameCache[i][j]);
			delete gH_ClosestPos[j][i];
			DefaultLoadReplay(gA_FrameCache[i][j], i, j);
		}

		Call_StartForward(gH_OnReplaysLoaded);
		Call_Finish();
	}

	// Test to see if replay file creation even works...
	FormatEx(sPath, sizeof(sPath), "%s/0/faketestfile_69.replay", gS_ReplayFolder);
	File fTest = OpenFile(sPath, "wb+");
	CloseHandle(fTest);

	if (fTest == null)
	{
		SetFailState("Failed to write to replay folder (%s). Make sure you have file permissions.", gS_ReplayFolder);
	}

	if (gH_TeamFull != null)
	{
		gH_TeamFull.Enable(Hook_Post, Detour_TeamFull);
	}

	CreateTimer(3.0, Timer_Cron, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEnd()
{
	if (gH_TeamFull != null)
	{
		gH_TeamFull.Disable(Hook_Post, Detour_TeamFull);
	}	
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleStringsStruct(i, gS_StyleStrings[i]);
	}

	gI_Styles = styles;
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	gI_TimeDifferenceStyle[client] = newstyle;
}

int InternalCreateReplayBot()
{
	gI_LatestClient = -1;

	if (gEV_Type == Engine_TF2)
	{
		int bot = SDKCall(
			gH_BotAddCommand,
			"replaybot", // name
			true // bReportFakeClient
		);

		if (IsValidClient(bot))
		{
			TF2_ChangeClientTeam(bot, TFTeam_Red);
			TF2_SetPlayerClass(bot, TFClass_Sniper);
			SetFakeClientConVar(bot, "name", "replaybot");
		}
	}
	else
	{
		// Do all this mp_randomspawn stuff on CSGO since it's easier than updating the signature for CCSGameRules::TeamFull.
		int mp_randomspawn_orig;
		
		if (mp_randomspawn != null)
		{
			mp_randomspawn_orig = mp_randomspawn.IntValue;
			mp_randomspawn.IntValue = gCV_DefaultTeam.IntValue;
		}

		if (gB_Linux)
		{
			/*int ret =*/ SDKCall(
				gH_BotAddCommand,
				0x10000,                   // thisptr           // unused (sourcemod needs > 0xFFFF though)
				gCV_DefaultTeam.IntValue,  // team
				false,                     // isFromConsole
				0,                         // profileName       // unused
				gI_WEAPONTYPE_UNKNOWN,     // CSWeaponType      // WEAPONTYPE_UNKNOWN
				0                          // BotDifficultyType // unused
			);
		}
		else
		{
			/*int ret =*/ SDKCall(
				gH_BotAddCommand,
				gCV_DefaultTeam.IntValue,  // team
				false,                     // isFromConsole
				0,                         // profileName       // unused
				gI_WEAPONTYPE_UNKNOWN,     // CSWeaponType      // WEAPONTYPE_UNKNOWN
				0                          // BotDifficultyType // unused
			);
		}

		if (mp_randomspawn != null)
		{
			mp_randomspawn.IntValue = mp_randomspawn_orig;
		}

		//bool success = (0xFF & ret) != 0;
	}

	return gI_LatestClient;
}

int CreateReplayBot(bot_info_t info)
{
	int bot = InternalCreateReplayBot();

	if (bot <= 0)
	{
		ClearBotInfo(info);
		return -1;
	}

	gA_BotInfo[bot] = info;
	gA_BotInfo[bot].iEnt = bot;

	if (info.iType == Replay_Central)
	{
		gI_CentralBot = bot;
		ClearBotInfo(gA_BotInfo[bot]);
	}
	else
	{
		StartReplay(gA_BotInfo[bot], gA_BotInfo[bot].iTrack, gA_BotInfo[bot].iStyle, GetClientFromSerial(info.iStarterSerial), info.fDelay);
	}

	gA_BotInfo[GetClientFromSerial(info.iStarterSerial)].iEnt = bot;

	if (info.iType == Replay_Looping)
	{
		gA_LoopingBotConfig[info.iLoopingConfig].bSpawned = true;
	}

	return bot;
}

void AddReplayBots()
{
	if (!gCV_Enabled.BoolValue)
	{
		return;
	}

	frame_cache_t cache; // NULL cache

	// Load central bot if enabled...
	if (gCV_CentralBot.BoolValue && gI_CentralBot <= 0)
	{
		int bot = CreateReplayEntity(0, 0, -1.0, 0, -1, Replay_Central, false, cache, 0);

		if (bot == 0)
		{
			LogError("Failed to create central replay bot (client count %d)", GetClientCount());
			return;
		}

		UpdateReplayClient(bot);
	}

	// Load all bots from looping config...
	for (int i = 0; i < MAX_LOOPING_BOT_CONFIGS; i++)
	{
		if (!gA_LoopingBotConfig[i].bEnabled || gA_LoopingBotConfig[i].bSpawned)
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

		int bot = CreateReplayEntity(track, style, -1.0, 0, -1, Replay_Looping, false, cache, i);

		if (bot == 0)
		{
			LogError("Failed to create looping bot %d (client count %d)", i, GetClientCount());
			return;
		}
	}
}

void GetReplayFilePath(int style, int track, const char[] mapname, char sPath[PLATFORM_MAX_PATH])
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, style, mapname, (track > 0)? sTrack:"");
}

bool DefaultLoadReplay(frame_cache_t cache, int style, int track)
{
	char sPath[PLATFORM_MAX_PATH];
	GetReplayFilePath(style, track, gS_Map, sPath);

	if (!LoadReplay(cache, style, track, sPath, gS_Map))
	{
		return false;
	}

	if (gB_ClosestPos)
	{
#if DEBUG
		Profiler p = new Profiler();
		p.Start();
#endif
		delete gH_ClosestPos[track][style];
		gH_ClosestPos[track][style] = new ClosestPos(cache.aFrames);
#if DEBUG
		p.Stop();
		PrintToServer(">>> ClosestPos / DefaultLoadReplay(style=%d, track=%d) = %f", style, track, p.Time);
		delete p;
#endif
	}

	return true;
}

bool LoadReplay(frame_cache_t cache, int style, int track, const char[] path, const char[] mapname)
{
	bool success = false;
	replay_header_t header;
	File fFile = ReadReplayHeader(path, header, style, track);

	if (fFile != null)
	{
		if (header.iReplayVersion > REPLAY_FORMAT_SUBVERSION)
		{
			// not going to try and read it
		}
		else if (header.iReplayVersion < 0x03 || (StrEqual(header.sMap, mapname, false) && header.iStyle == style && header.iTrack == track))
		{
			success = ReadReplayFrames(fFile, header, cache);
		}

		delete fFile;
	}

	return success;
}

bool ReadReplayFrames(File file, replay_header_t header, frame_cache_t cache)
{
	int total_cells = 6;
	int used_cells = 6;
	bool is_btimes = false;

	if (header.iReplayVersion > 0x01)
	{
		total_cells = 8;
		used_cells = 8;
	}

	// We have differing total_cells & used_cells because we want to save memory during playback since the latest two cells added (vel & mousexy) aren't needed and are only useful for replay file anticheat usage stuff....
	if (header.iReplayVersion >= 0x06)
	{
		total_cells = 10;
		used_cells = 8;
	}

	any aReplayData[sizeof(frame_t)];

	delete cache.aFrames;
	int iTotalSize = header.iFrameCount + header.iPreFrames + header.iPostFrames;
	cache.aFrames = new ArrayList(used_cells, iTotalSize);

	if (!header.sReplayFormat[0]) // old replay format. no header.
	{
		char sLine[320];
		char sExplodedLine[6][64];

		if(!file.Seek(0, SEEK_SET))
		{
			return false;
		}

		while (!file.EndOfFile())
		{
			file.ReadLine(sLine, 320);
			int iStrings = ExplodeString(sLine, "|", sExplodedLine, 6, 64);

			aReplayData[0] = StringToFloat(sExplodedLine[0]);
			aReplayData[1] = StringToFloat(sExplodedLine[1]);
			aReplayData[2] = StringToFloat(sExplodedLine[2]);
			aReplayData[3] = StringToFloat(sExplodedLine[3]);
			aReplayData[4] = StringToFloat(sExplodedLine[4]);
			aReplayData[5] = (iStrings == 6) ? StringToInt(sExplodedLine[5]) : 0;

			cache.aFrames.PushArray(aReplayData, 6);
		}

		cache.iFrameCount = cache.aFrames.Length;
	}
	else // assumes the file position will be at the start of the frames
	{
		is_btimes = StrEqual(header.sReplayFormat, "btimes");

		for (int i = 0; i < iTotalSize; i++)
		{
			if(file.Read(aReplayData, total_cells, 4) >= 0)
			{
				cache.aFrames.SetArray(i, aReplayData, used_cells);

				if (is_btimes && (aReplayData[5] & IN_BULLRUSH))
				{
					if (!header.iPreFrames)
					{
						header.iPreFrames = i;
						header.iFrameCount -= i;
					}
					else if (!header.iPostFrames)
					{
						header.iPostFrames = header.iFrameCount + header.iPreFrames - i;
						header.iFrameCount -= header.iPostFrames;
					}
				}
			}
		}

		if (StrEqual(header.sReplayFormat, REPLAY_FORMAT_FINAL))
		{
			char sQuery[192];
			FormatEx(sQuery, 192, "SELECT name FROM %susers WHERE auth = %d;", gS_MySQLPrefix, header.iSteamID);

			DataPack hPack = new DataPack();
			hPack.WriteCell(header.iStyle);
			hPack.WriteCell(header.iTrack);

			gH_SQL.Query(SQL_GetUserName_Callback, sQuery, hPack, DBPrio_High);
		}
	}

	cache.iFrameCount = header.iFrameCount;
	cache.fTime = header.fTime;
	cache.iReplayVersion = header.iReplayVersion;
	cache.bNewFormat = StrEqual(header.sReplayFormat, REPLAY_FORMAT_FINAL) || is_btimes;
	cache.sReplayName = "unknown";
	cache.iPreFrames = header.iPreFrames;
	cache.iPostFrames = header.iPostFrames;
	cache.fTickrate = header.fTickrate;

	return true;
}

File ReadReplayHeader(const char[] path, replay_header_t header, int style, int track)
{
	replay_header_t empty_header;
	header = empty_header;

	if (!FileExists(path))
	{
		return null;
	}

	File file = OpenFile(path, "rb");

	if (file == null)
	{
		return null;
	}

	char sHeader[64];

	if(!file.ReadLine(sHeader, 64))
	{
		delete file;
		return null;
	}

	TrimString(sHeader);
	char sExplodedHeader[2][64];
	ExplodeString(sHeader, ":", sExplodedHeader, 2, 64);

	strcopy(header.sReplayFormat, sizeof(header.sReplayFormat), sExplodedHeader[1]);

	if(StrEqual(header.sReplayFormat, REPLAY_FORMAT_FINAL)) // hopefully, the last of them
	{
		int version = StringToInt(sExplodedHeader[0]);

		header.iReplayVersion = version;

		// replay file integrity and PreFrames
		if(version >= 0x03)
		{
			file.ReadString(header.sMap, PLATFORM_MAX_PATH);
			file.ReadUint8(header.iStyle);
			file.ReadUint8(header.iTrack);
			
			file.ReadInt32(header.iPreFrames);

			// In case the replay was from when there could still be negative preframes
			if(header.iPreFrames < 0)
			{
				header.iPreFrames = 0;
			}
		}

		file.ReadInt32(header.iFrameCount);
		file.ReadInt32(view_as<int>(header.fTime));

		if (header.iReplayVersion < 0x07)
		{
			header.iFrameCount -= header.iPreFrames;
		}

		if(version >= 0x04)
		{
			file.ReadInt32(header.iSteamID);
		}
		else
		{
			char sAuthID[32];
			file.ReadString(sAuthID, 32);
			ReplaceString(sAuthID, 32, "[U:1:", "");
			ReplaceString(sAuthID, 32, "]", "");
			header.iSteamID = StringToInt(sAuthID);
		}

		if (version >= 0x05)
		{
			file.ReadInt32(header.iPostFrames);
			file.ReadInt32(view_as<int>(header.fTickrate));

			if (header.iReplayVersion < 0x07)
			{
				header.iFrameCount -= header.iPostFrames;
			}
		}

		if (version >= 0x08)
		{
			file.ReadInt32(view_as<int>(header.fZoneOffset[0]));
			file.ReadInt32(view_as<int>(header.fZoneOffset[1]));
		}
	}
	else if(StrEqual(header.sReplayFormat, REPLAY_FORMAT_V2))
	{
		header.iFrameCount = StringToInt(sExplodedHeader[0]);
	}
	else // old, outdated and slow - only used for ancient replays
	{
		// check for btimes replays
		file.Seek(0, SEEK_SET);
		any stuff[2];
		file.Read(stuff, 2, 4);

		int btimes_player_id = stuff[0];
		float run_time = stuff[1];

		if (btimes_player_id >= 0 && run_time > 0.0 && run_time < (10.0 * 60.0 * 60.0))
		{
			header.sReplayFormat = "btimes";
			header.fTime = run_time;

			file.Seek(0, SEEK_END);
			header.iFrameCount = (file.Position / 4 - 2) / 6;
			file.Seek(2*4, SEEK_SET);
		}
	}

	if (header.iReplayVersion < 0x03)
	{
		header.iStyle = style;
		header.iTrack = track;
	}

	if (header.iReplayVersion < 0x05)
	{
		header.fTickrate = gF_Tickrate;
	}

	return file;
}

void WriteReplayHeader(File fFile, int style, int track, float time, int steamid, int preframes, int postframes, float fZoneOffset[2], int iSize)
{
	fFile.WriteLine("%d:" ... REPLAY_FORMAT_FINAL, REPLAY_FORMAT_SUBVERSION);

	fFile.WriteString(gS_Map, true);
	fFile.WriteInt8(style);
	fFile.WriteInt8(track);
	fFile.WriteInt32(preframes);

	fFile.WriteInt32(iSize - preframes - postframes);
	fFile.WriteInt32(view_as<int>(time));
	fFile.WriteInt32(steamid);

	fFile.WriteInt32(postframes);
	fFile.WriteInt32(view_as<int>(gF_Tickrate));

	fFile.WriteInt32(view_as<int>(fZoneOffset[0]));
	fFile.WriteInt32(view_as<int>(fZoneOffset[1]));
}

void SaveReplay(int style, int track, float time, int steamid, char[] name, int preframes, ArrayList playerrecording, int iSize, int postframes, int timestamp, float fZoneOffset[2], bool saveCopy, bool saveReplay, char[] sPath, int sPathLen)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	File fWR = null;
	File fCopy = null;

	if (saveReplay)
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

	if (saveReplay)
	{
		WriteReplayHeader(fWR, style, track, time, steamid, preframes, postframes, fZoneOffset, iSize);
	}

	if (saveCopy)
	{
		WriteReplayHeader(fCopy, style, track, time, steamid, preframes, postframes, fZoneOffset, iSize);
	}

	any aFrameData[sizeof(frame_t)];
	any aWriteData[sizeof(frame_t) * FRAMES_PER_WRITE];
	int iFramesWritten = 0;

	for(int i = 0; i < iSize; i++)
	{
		playerrecording.GetArray(i, aFrameData, sizeof(frame_t));

		for(int j = 0; j < sizeof(frame_t); j++)
		{
			aWriteData[(sizeof(frame_t) * iFramesWritten) + j] = aFrameData[j];
		}

		if(++iFramesWritten == FRAMES_PER_WRITE || i == iSize - 1)
		{
			if (saveReplay)
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

	if (!saveReplay)
	{
		return;
	}

	delete gA_FrameCache[style][track].aFrames;
	gA_FrameCache[style][track].aFrames = view_as<ArrayList>(CloneHandle(playerrecording));
	gA_FrameCache[style][track].aFrames.Resize(iSize);
	gA_FrameCache[style][track].iFrameCount = iSize - preframes - postframes;
	gA_FrameCache[style][track].fTime = time;
	gA_FrameCache[style][track].iReplayVersion = REPLAY_FORMAT_SUBVERSION;
	gA_FrameCache[style][track].bNewFormat = true;
	strcopy(gA_FrameCache[style][track].sReplayName, MAX_NAME_LENGTH, name);
	gA_FrameCache[style][track].iPreFrames = preframes;
	gA_FrameCache[style][track].iPostFrames = postframes;
	gA_FrameCache[style][track].fTickrate = gF_Tickrate;
}

bool DeleteReplay(int style, int track, int accountid, const char[] mapname)
{
	char sPath[PLATFORM_MAX_PATH];
	GetReplayFilePath(style, track, mapname, sPath);

	if(!FileExists(sPath))
	{
		return false;
	}

	if(accountid != 0)
	{
		replay_header_t header;
		File file = ReadReplayHeader(sPath, header, style, track);

		if (file == null)
		{
			return false;
		}

		delete file;

		if (accountid != header.iSteamID)
		{
			return false;
		}
	}
	
	if(!DeleteFile(sPath))
	{
		return false;
	}

	if(StrEqual(mapname, gS_Map, false))
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
	if (gA_BotInfo[client].iEnt > 1 && gA_BotInfo[client].iType == Replay_Prop && !IsPlayerAlive(client))
	{
		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", gA_BotInfo[client].iEnt);
		SetClientViewEntity(client, gA_BotInfo[client].iEnt);
	}
}

public void OnClientPutInServer(int client)
{
	gI_LatestClient = client;
	gI_HijackFrames[client] = 0;

	if(IsClientSourceTV(client))
	{
		return;
	}

	if(!IsFakeClient(client))
	{
		gF_LastInteraction[client] = GetEngineTime() - gCV_PlaybackCooldown.FloatValue;
		gA_BotInfo[client].iEnt = -1;
		ClearBotInfo(gA_BotInfo[client]);
		ClearFrames(client);

		SDKHook(client, SDKHook_PostThink, ForceObserveProp);
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

void FormatStyle(const char[] source, int style, bool central, int track, char dest[MAX_NAME_LENGTH], bool idle, frame_cache_t aCache, int type)
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
		ReplaceString(temp, sizeof(temp), "{style}", "");
		ReplaceString(temp, sizeof(temp), "{styletag}", "");
	}
	else
	{
		FormatSeconds(GetReplayLength(style, track, aCache), sTime, 16);
		GetReplayName(style, track, sName, sizeof(sName));
		ReplaceString(temp, sizeof(temp), "{style}", gS_StyleStrings[style].sStyleName);
		ReplaceString(temp, sizeof(temp), "{styletag}", gS_StyleStrings[style].sClanTag);
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
	int type = gA_BotInfo[client].iType;
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

	int sv_duplicate_playernames_ok_original;
	if (sv_duplicate_playernames_ok != null)
	{
		sv_duplicate_playernames_ok_original = sv_duplicate_playernames_ok.IntValue;
		sv_duplicate_playernames_ok.IntValue = 1;
	}

	gB_HideNameChange = true;
	SetClientName(client, sName);

	if (sv_duplicate_playernames_ok != null)
	{
		sv_duplicate_playernames_ok.IntValue = sv_duplicate_playernames_ok_original;
	}

	int iScore = (iFrameCount > 0 || client == gI_CentralBot)? 1337:-1337;

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

public Action Timer_SpectateMyBot(Handle timer, any data)
{
	SpectateMyBot(data);
	return Plugin_Stop;
}

void SpectateMyBot(int serial)
{
	int bot = GetClientFromSerial(serial);

	if (bot == 0)
	{
		return;
	}

	int starter = GetClientFromSerial(gA_BotInfo[bot].iStarterSerial);

	if (starter == 0)
	{
		return;
	}

	SetEntPropEnt(starter, Prop_Send, "m_hObserverTarget", bot);
}

void RemoveAllWeapons(int client)
{
	int weapon = -1, max = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i = 0; i < max; i++)
	{
		if ((weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i)) == -1)
			continue;

		if (RemovePlayerItem(client, weapon))
		{
			AcceptEntityInput(weapon, "Kill");
		}
	}
}

void Frame_UpdateReplayClient(int serial)
{
	int client = GetClientFromSerial(serial);

	if (client > 0)
	{
		UpdateReplayClient(client);
	}
}

void UpdateReplayClient(int client)
{
	// Only run on fakeclients
	if(!gCV_Enabled.BoolValue || !IsValidClient(client) || !IsFakeClient(client))
	{
		return;
	}

	gF_Tickrate = (1.0 / GetTickInterval());

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

				bool same_thing = false;

				// special case for csgo stuff because the usp classname becomes weapon_hpk2000
				if (gEV_Type == Engine_CSGO)
				{
					if (StrEqual(sWeapon, "weapon_usp_silencer"))
					{
						same_thing = (61 == GetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex"));
					}
					else if (StrEqual(sWeapon, "weapon_hpk2000"))
					{
						same_thing = (32 == GetEntProp(iWeapon, Prop_Send, "m_iItemDefinitionIndex"));
					}
				}

				if (!same_thing && !StrEqual(sWeapon, sClassname))
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
		if (gA_BotInfo[client].iEnt > 0)
		{
			int index = GetBotInfoIndex(gA_BotInfo[client].iEnt);

			if (gA_BotInfo[index].iType == Replay_Central)
			{
				CancelReplay(gA_BotInfo[index]);
			}
			else
			{
				KickReplay(gA_BotInfo[index]);
			}
		}

		if (gB_GrabbingPostFrames[client])
		{
			FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client]);
		}

		return;
	}

	if (gA_BotInfo[client].iEnt == client)
	{
		CancelReplay(gA_BotInfo[client], false);

		gA_BotInfo[client].iEnt = -1;

		if (gA_BotInfo[client].iType == Replay_Looping)
		{
			gA_LoopingBotConfig[gA_BotInfo[client].iLoopingConfig].bSpawned = false;
		}
	}

	if (gI_CentralBot == client)
	{
		gI_CentralBot = -1;
	}
}

public void OnClientDisconnect_Post(int client)
{
	// This runs after shavit-misc has cloned the handle
	delete gA_PlayerFrames[client];
}

public void OnEntityDestroyed(int entity)
{
	if (entity <= MaxClients)
	{
		return;
	}

	// Handle Replay_Props that mysteriously die.
	for (int i = 1; i <= MaxClients; i++)
	{
		if (gA_BotInfo[i].iEnt == entity)
		{
			KickReplay(gA_BotInfo[i]);
			return;
		}
	}
}

public Action Shavit_OnStart(int client)
{
	gI_HijackFrames[client] = 0;

	if (gB_GrabbingPostFrames[client])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client]);
	}

	int iMaxPreFrames = RoundToFloor(gCV_PlaybackPreRunTime.FloatValue * gF_Tickrate / Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(client), "speed"));
	bool bInStart = Shavit_InsideZone(client, Zone_Start, Shavit_GetClientTrack(client));

	if (bInStart)
	{
		int iFrameDifference = gI_PlayerFrames[client] - iMaxPreFrames;

		if (iFrameDifference > 0)
		{
			// For too many extra frames, we'll just shift the preframes to the start of the array.
			if (iFrameDifference > 100)
			{
				for (int i = iFrameDifference; i < gI_PlayerFrames[client]; i++)
				{
					gA_PlayerFrames[client].SwapAt(i, i-iFrameDifference);
				}

				gI_PlayerFrames[client] = iMaxPreFrames;
			}
			else // iFrameDifference isn't that bad, just loop through and erase.
			{
				while (iFrameDifference--)
				{
					gA_PlayerFrames[client].Erase(0);
					gI_PlayerFrames[client]--;
				}
			}
		}
	}
	else
	{
		if (!gCV_PreRunAlways.BoolValue)
		{
			ClearFrames(client);
		}
	}

	gI_PlayerPrerunFrames[client] = gI_PlayerFrames[client];

	return Plugin_Continue;
}

public void Shavit_OnStop(int client)
{
	if (gB_GrabbingPostFrames[client])
	{
		FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client]);
	}

	ClearFrames(client);
}

public Action Timer_PostFrames(Handle timer, int client)
{
	gH_PostFramesTimer[client] = null;
	FinishGrabbingPostFrames(client, gA_FinishedRunInfo[client]);
	return Plugin_Stop;
}

void FinishGrabbingPostFrames(int client, finished_run_info info)
{
	gB_GrabbingPostFrames[client] = false;
	delete gH_PostFramesTimer[client];

	DoReplaySaverCallbacks(info.iSteamID, client, info.style, info.time, info.jumps, info.strafes, info.sync, info.track, info.oldtime, info.perfs, info.avgvel, info.maxvel, info.timestamp, info.fZoneOffset);
}

void DoReplaySaverCallbacks(int iSteamID, int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp, float fZoneOffset[2])
{
	bool isTooLong = (gCV_TimeLimit.FloatValue > 0.0 && time > gCV_TimeLimit.FloatValue);

	float length = GetReplayLength(style, track, gA_FrameCache[style][track]);
	bool isBestReplay = (length == 0.0 || time < length);

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
	Call_PushCell(isBestReplay);
	Call_Finish(action);

	bool makeCopy = (action != Plugin_Continue);
	bool makeReplay = (isBestReplay && !isTooLong);

	if (!makeCopy && !makeReplay)
	{
		return;
	}

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);
	ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");

	int postframes = gI_PlayerFrames[client] - gI_PlayerFinishFrame[client];

	char sPath[PLATFORM_MAX_PATH];
	SaveReplay(style, track, time, iSteamID, sName, gI_PlayerPrerunFrames[client], gA_PlayerFrames[client], gI_PlayerFrames[client], postframes, timestamp, fZoneOffset, makeCopy, makeReplay, sPath, sizeof(sPath));

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
	Call_PushCell(isBestReplay);
	Call_PushCell(makeCopy);
	Call_PushString(sPath);
	Call_Finish();

	if(makeReplay && ReplayEnabled(style))
	{
		StopOrRestartBots(style, track, false);

		if (gB_ClosestPos)
		{
#if DEBUG
			Profiler p = new Profiler();
			p.Start();
#endif
			delete gH_ClosestPos[track][style];
			gH_ClosestPos[track][style] = new ClosestPos(gA_FrameCache[style][track].aFrames);
#if DEBUG
			p.Stop();
			PrintToServer(">>> ClosestPos / DoReplaySaverCallbacks(style=%d, track=%d) = %f", style, track, p.Time);
			delete p;
#endif
		}
	}

	ClearFrames(client);
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
	if(Shavit_IsPracticeMode(client) || !gCV_Enabled.BoolValue || gI_PlayerFrames[client] == 0)
	{
		return;
	}

	gI_PlayerFinishFrame[client] = gI_PlayerFrames[client];

	float fZoneOffset[2];
	fZoneOffset[0] = Shavit_GetZoneOffset(client, 0);
	fZoneOffset[1] = Shavit_GetZoneOffset(client, 1);

	if (gCV_PlaybackPostRunTime.FloatValue > 0.0)
	{
		finished_run_info info;
		info.iSteamID = GetSteamAccountID(client);
		info.style = style;
		info.time = time;
		info.jumps = jumps;
		info.strafes = strafes;
		info.sync = sync;
		info.track = track;
		info.oldtime = oldtime;
		info.perfs = perfs;
		info.avgvel = avgvel;
		info.maxvel = maxvel;
		info.timestamp = timestamp;
		info.fZoneOffset = fZoneOffset;

		gA_FinishedRunInfo[client] = info;
		gB_GrabbingPostFrames[client] = true;
		delete gH_PostFramesTimer[client];
		gH_PostFramesTimer[client] = CreateTimer(gCV_PlaybackPostRunTime.FloatValue, Timer_PostFrames, client, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		DoReplaySaverCallbacks(GetSteamAccountID(client), client, style, time, jumps, strafes, sync, track, oldtime, perfs, avgvel, maxvel, timestamp, fZoneOffset);
	}
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

Action ReplayOnPlayerRunCmd(bot_info_t info, int &buttons, int &impulse, float vel[3])
{
	bool isClient = (1 <= info.iEnt <= MaxClients);

	buttons = 0;

	vel[0] = 0.0;
	vel[1] = 0.0;

	if(info.aCache.aFrames != null || info.aCache.iFrameCount > 0) // if no replay is loaded
	{
		if(info.iTick != -1 && info.aCache.iFrameCount >= 1)
		{
			if (info.iStatus == Replay_End)
			{
				return Plugin_Changed;
			}

			if (info.iStatus == Replay_Start)
			{
				bool bStart = (info.iStatus == Replay_Start);
				int iFrame = (bStart) ? 0 : (info.aCache.iFrameCount + info.aCache.iPostFrames + info.aCache.iPreFrames - 1);
				TeleportToFrame(info, iFrame);
				return Plugin_Changed;
			}

			info.iTick += info.b2x ? 2 : 1;

			int limit = (info.aCache.iFrameCount + info.aCache.iPreFrames + info.aCache.iPostFrames);

			if(info.iTick >= limit)
			{
				info.iTick = limit;
				info.iStatus = Replay_End;
				info.hTimer = CreateTimer((info.fDelay / 2.0), Timer_EndReplay, info.iEnt, TIMER_FLAG_NO_MAPCHANGE);

				Call_StartForward(gH_OnReplayEnd);
				Call_PushCell(info.iEnt);
				Call_PushCell(info.iType);
				Call_PushCell(false); // actually_finished
				Call_Finish();

				return Plugin_Changed;
			}

			if(info.iTick == 1)
			{
				info.fFirstFrameTime = GetEngineTime();
			}

			float vecPreviousPos[3];

			if (info.b2x)
			{
				frame_t aFramePrevious;
				int previousTick = (info.iTick > 0) ? (info.iTick-1) : 0;
				info.aCache.aFrames.GetArray(previousTick, aFramePrevious, (info.aCache.iReplayVersion >= 0x02) ? 8 : 6);
				vecPreviousPos = aFramePrevious.pos;
			}
			else
			{
				GetEntPropVector(info.iEnt, Prop_Send, "m_vecOrigin", vecPreviousPos);
			}

			frame_t aFrame;
			info.aCache.aFrames.GetArray(info.iTick, aFrame, (info.aCache.iReplayVersion >= 0x02) ? 8 : 6);
			buttons = aFrame.buttons;

			if (!isClient)
			{
				aFrame.pos[2] += (aFrame.buttons & IN_DUCK) ? gF_EyeOffsetDuck : gF_EyeOffset;
			}

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

					if((gI_LastReplayFlags[info.iEnt] & FL_ONGROUND) && !(iReplayFlags & FL_ONGROUND) && gH_DoAnimationEvent != INVALID_HANDLE)
					{
						int jumpAnim = (gEV_Type == Engine_CSS) ?
							CSS_ANIM_JUMP : ((gEV_Type == Engine_TF2) ? TF2_ANIM_JUMP : CSGO_ANIM_JUMP);
						
						if(gB_Linux)
						{
							SDKCall(gH_DoAnimationEvent, EntIndexToEntRef(info.iEnt), jumpAnim, 0);
						}
						else
						{
							SDKCall(gH_DoAnimationEvent, info.iEnt, jumpAnim, 0);
						}
					}
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
				gI_LastReplayFlags[info.iEnt] = aFrame.flags; 
				SetEntityMoveType(info.iEnt, mt);
			}

			float vecVelocity[3];
			MakeVectorFromPoints(vecPreviousPos, aFrame.pos, vecVelocity);
			ScaleVector(vecVelocity, gF_Tickrate);

			float ang[3];
			ang[0] = aFrame.ang[0];
			ang[1] = aFrame.ang[1];

			if(info.b2x || (info.iTick > 1 &&
				// replay is going above 50k speed, just teleport at this point
				(GetVectorLength(vecVelocity) > 50000.0 ||
				// bot is on ground.. if the distance between the previous position is much bigger (1.5x) than the expected according
				// to the bot's velocity, teleport to avoid sync issues
				(bWalk && GetVectorDistance(vecPreviousPos, aFrame.pos) > GetVectorLength(vecVelocity) / gF_Tickrate * 1.5))))
			{
				TeleportEntity(info.iEnt, aFrame.pos, ang, info.b2x ? vecVelocity : NULL_VECTOR);
			}
			else
			{
				TeleportEntity(info.iEnt, NULL_VECTOR, ang, vecVelocity);
			}
		}
	}

	return Plugin_Changed;
}

int LimitMoveVelFloat(float vel)
{
	int x = RoundToCeil(vel);
	return ((x < -666) ? -666 : ((x > 666) ? 666 : x)) & 0xFFFF;
}

// OnPlayerRunCmd instead of Shavit_OnUserCmdPre because bots are also used here.
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
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

	if (IsFakeClient(client))
	{
		if (gA_BotInfo[client].iEnt == client)
		{
			return ReplayOnPlayerRunCmd(gA_BotInfo[client], buttons, impulse, vel);
		}
	}
	else if (gB_GrabbingPostFrames[client] || (ReplayEnabled(Shavit_GetBhopStyle(client)) && Shavit_GetTimerStatus(client) == Timer_Running))
	{
		if((gI_PlayerFrames[client] / gF_Tickrate) > gCV_TimeLimit.FloatValue)
		{
			if (gI_HijackFrames[client])
			{
				gI_HijackFrames[client] = 0;
			}

			return Plugin_Continue;
		}

		float fTimescale = Shavit_GetClientTimescale(client);

		if(fTimescale != 0.0)
		{
			if(gF_NextFrameTime[client] <= 0.0)
			{
				if (gA_PlayerFrames[client].Length <= gI_PlayerFrames[client])
				{
					// Add about two seconds worth of frames so we don't have to resize so often
					gA_PlayerFrames[client].Resize(gI_PlayerFrames[client] + (RoundToCeil(gF_Tickrate) * 2));
					//PrintToChat(client, "resizing %d -> %d", gI_PlayerFrames[client], gA_PlayerFrames[client].Length);
				}

				frame_t aFrame;
				GetClientAbsOrigin(client, aFrame.pos);

				if (!gI_HijackFrames[client])
				{
					float vecEyes[3];
					GetClientEyeAngles(client, vecEyes);
					aFrame.ang[0] = vecEyes[0];
					aFrame.ang[1] = vecEyes[1];
				}
				else
				{
					aFrame.ang = gF_HijackedAngles[client];
					--gI_HijackFrames[client];
				}

				aFrame.buttons = buttons;
				aFrame.flags = GetEntityFlags(client);
				aFrame.mt = GetEntityMoveType(client);

				aFrame.mousexy = (mouse[0] & 0xFFFF) | ((mouse[1] & 0xFFFF) << 16);
				aFrame.vel = LimitMoveVelFloat(vel[0]) | (LimitMoveVelFloat(vel[1]) << 16);

				gA_PlayerFrames[client].SetArray(gI_PlayerFrames[client]++, aFrame, sizeof(frame_t));

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
	Call_PushCell(true); // delay_elapsed
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
	else if (gA_BotInfo[client].iEnt > 0)
	{
		// Here to kill Replay_Prop s when the watcher/starter respawns.
		int index = GetBotInfoIndex(gA_BotInfo[client].iEnt);

		if (gA_BotInfo[index].iType == Replay_Central)
		{
			//CancelReplay(gA_BotInfo[index]); // TODO: Is this worth doing? Might be a bit annoying until rewind/ff is added...
		}
		else
		{
			KickReplay(gA_BotInfo[index]);
		}
	}
}

public Action BotEvents(Event event, const char[] name, bool dontBroadcast)
{
	if(!gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if(event.GetBool("bot") || !client || IsFakeClient(client))
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
	}
	else
	{
		BfRead bfmsg = msg;
		bfmsg.ReadByte();
		bfmsg.ReadByte();
		bfmsg.ReadString(sMessage, 24);
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
	gI_PlayerFinishFrame[client] = 0;
}

void ClearFrameCache(frame_cache_t cache)
{
	delete cache.aFrames;
	cache.iFrameCount = 0;
	cache.fTime = 0.0;
	cache.bNewFormat = true;
	cache.iReplayVersion = 0;
	cache.sReplayName = "unknown";
	cache.iPreFrames = 0;
	cache.iPostFrames = 0;
	cache.fTickrate = 0.0;
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
	menu.Display(client, MENU_TIME_FOREVER);

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
		submenu.Display(param1, MENU_TIME_FOREVER);
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

		if(DeleteReplay(style, gI_MenuTrack[param1], 0, gS_Map))
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
	if (gA_BotInfo[client].iEnt > 0)
	{
		return -1;
	}

	int ent = CreateEntityByName("prop_physics_override");

	if (ent == -1)
	{
		return -1;
	}

	SetEntityModel(ent, (gEV_Type == Engine_TF2)? "models/error.mdl":"models/props/cs_office/vending_machine.mdl");

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

	// Storing the client index in the prop's m_iTeamNum.
	// Great way to get the starter without having array of MAXENTS
	SetEntProp(ent, Prop_Data, HACKY_CLIENT_IDX_PROP, client);

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

	OpenReplayMenu(client);
	return Plugin_Handled;
}

void OpenReplayMenu(int client, bool canControlReplayUiFix=false)
{
	Menu menu = new Menu(MenuHandler_Replay, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem|MenuAction_Display);
	menu.SetTitle("%T\n ", "Menu_Replay", client);

	char sDisplay[64];
	bool alreadyHaveBot = (gA_BotInfo[client].iEnt > 0);
	int index = GetControllableReplay(client);
	bool canControlReplay = canControlReplayUiFix || (index != -1);

	FormatEx(sDisplay, 64, "%T", "CentralReplayStop", client);
	menu.AddItem("stop", sDisplay, canControlReplay ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "%T", "Menu_SpawnReplay", client);
	menu.AddItem("spawn", sDisplay, !(alreadyHaveBot) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "+1s");
	menu.AddItem("+1", sDisplay, canControlReplay ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "-1s");
	menu.AddItem("-1", sDisplay, canControlReplay ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "+10s");
	menu.AddItem("+10", sDisplay, canControlReplay ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "-10s");
	menu.AddItem("-10", sDisplay, canControlReplay ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "%T", "Menu_Replay2X", client, (index != -1 && gA_BotInfo[index].b2x) ? "+" : "_");
	menu.AddItem("2x", sDisplay, canControlReplay ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "%T", "Menu_RefreshReplay", client);
	menu.AddItem("refresh", sDisplay, ITEMDRAW_DEFAULT);

	menu.Pagination = MENU_NO_PAGINATION;
	menu.ExitButton = true;
	menu.DisplayAt(client, 0, MENU_TIME_FOREVER);
}

public int MenuHandler_Replay(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if (StrEqual(sInfo, "stop"))
		{
			int index = GetControllableReplay(param1);

			if (index != -1)
			{
				Shavit_PrintToChat(param1, "%T", "CentralReplayStopped", param1);
				FinishReplay(gA_BotInfo[index]);
			}

			OpenReplayMenu(param1);
		}
		else if (StrEqual(sInfo, "spawn"))
		{
			OpenReplayTypeMenu(param1);
		}
		else if (StrEqual(sInfo, "2x"))
		{
			int index = GetControllableReplay(param1);

			if (index != -1)
			{
				gA_BotInfo[index].b2x = !gA_BotInfo[index].b2x;
			}

			OpenReplayMenu(param1);
		}
		else if (StrEqual(sInfo, "refresh"))
		{
			OpenReplayMenu(param1);
		}
		else if (sInfo[0] == '-' || sInfo[0] == '+')
		{
			int seconds = StringToInt(sInfo);

			int index = GetControllableReplay(param1);

			if (index != -1)
			{
				gA_BotInfo[index].iTick += RoundToFloor(seconds * gF_Tickrate);

				if (gA_BotInfo[index].iTick < 0)
				{
					gA_BotInfo[index].iTick = 0;
				}
				else
				{
					int limit = (gA_BotInfo[index].aCache.iFrameCount + gA_BotInfo[index].aCache.iPreFrames + gA_BotInfo[index].aCache.iPostFrames);

					if (gA_BotInfo[index].iTick > limit)
					{
						gA_BotInfo[index].iTick = limit;
					}
				}
			}

			OpenReplayMenu(param1);
		}
	}
	else if (action == MenuAction_Display)
	{
		gB_InReplayMenu[param1] = true;
	}
	else if (action == MenuAction_Cancel)
	{
		gB_InReplayMenu[param1] = false;
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenReplayTypeMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ReplayType);
	menu.SetTitle("%T\n ", "Menu_ReplayBotType", client);

	char sDisplay[64];
	char sInfo[8];
	bool alreadyHaveBot = (gA_BotInfo[client].iEnt > 0);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "Menu_Replay_Central", client);
	IntToString(Replay_Central, sInfo, sizeof(sInfo));
	menu.AddItem(sInfo, sDisplay, (gCV_CentralBot.BoolValue && IsValidClient(gI_CentralBot) && gA_BotInfo[gI_CentralBot].iStatus == Replay_Idle && !alreadyHaveBot) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "Menu_Replay_Dynamic", client);
	IntToString(Replay_Dynamic, sInfo, sizeof(sInfo));
	menu.AddItem(sInfo, sDisplay, (gI_DynamicBots < gCV_DynamicBotLimit.IntValue && !alreadyHaveBot) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "Menu_Replay_Prop", client);
	IntToString(Replay_Prop, sInfo, sizeof(sInfo));
	menu.AddItem(sInfo, sDisplay, (gCV_AllowPropBots.BoolValue && !alreadyHaveBot) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.DisplayAt(client, 0, MENU_TIME_FOREVER);
}

public int MenuHandler_ReplayType(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		int type = StringToInt(sInfo);

		if (type != Replay_Central && type != Replay_Dynamic && type != Replay_Prop)
		{
			return 0;
		}

		if ((type == Replay_Central && (!gCV_CentralBot.BoolValue || !IsValidClient(gI_CentralBot) || gA_BotInfo[gI_CentralBot].iStatus != Replay_Idle))
		|| (type == Replay_Dynamic && (gI_DynamicBots >= gCV_DynamicBotLimit.IntValue))
		|| (type == Replay_Prop && (!gCV_AllowPropBots.BoolValue))
		|| (gA_BotInfo[param1].iEnt > 0))
		{
			return 0;
		}

		gI_MenuType[param1] = type;
		OpenReplayTrackMenu(param1);
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
	menu.Display(client, MENU_TIME_FOREVER);
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

		if(style < 0 || style >= gI_Styles || !ReplayEnabled(style) || gA_FrameCache[style][gI_MenuTrack[param1]].iFrameCount == 0 || gA_BotInfo[param1].iEnt > 0 || (GetEngineTime() - gF_LastInteraction[param1] < gCV_PlaybackCooldown.FloatValue && !CheckCommandAccess(param1, "sm_deletereplay", ADMFLAG_RCON)))
		{
			return 0;
		}

		gI_MenuStyle[param1] = style;
		int type = gI_MenuType[param1];

		int bot = -1;

		if (type == Replay_Central)
		{
			if (!IsValidClient(gI_CentralBot))
			{
				return 0;
			}

			if (gA_BotInfo[gI_CentralBot].iStatus != Replay_Idle)
			{
				Shavit_PrintToChat(param1, "%T", "CentralReplayPlaying", param1);
				return 0;
			}

			bot = gI_CentralBot;
		}
		else if (type == Replay_Dynamic)
		{
			if (gI_DynamicBots >= gCV_DynamicBotLimit.IntValue)
			{
				Shavit_PrintToChat(param1, "%T", "TooManyDynamicBots", param1);
				return 0;
			}
		}
		else if (type == Replay_Prop)
		{
			if (!gCV_AllowPropBots.BoolValue)
			{
				return 0;
			}
		}

		frame_cache_t cache; // NULL cache
		bot = CreateReplayEntity(gI_MenuTrack[param1], gI_MenuStyle[param1], gCV_ReplayDelay.FloatValue, param1, bot, type, false, cache, 0);

		if (bot == 0)
		{
			Shavit_PrintToChat(param1, "%T", "FailedToCreateReplay", param1);
			return 0;
		}

		OpenReplayMenu(param1, true);
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

bool CanControlReplay(int client, bot_info_t info)
{
	return CheckCommandAccess(client, "sm_deletereplay", ADMFLAG_RCON)
		|| (gCV_PlaybackCanStop.BoolValue && GetClientSerial(client) == info.iStarterSerial)
	;
}

int GetControllableReplay(int client)
{
	int target = GetSpectatorTarget(client);

	if (target != -1)
	{
		int index = GetBotInfoIndex(target);

		if (gA_BotInfo[index].iStatus == Replay_Start || gA_BotInfo[index].iStatus == Replay_Running)
		{
			if (CanControlReplay(client, gA_BotInfo[index]))
			{
				return index;
			}
		}
	}

	return -1;
}

void TeleportToFrame(bot_info_t info, int iFrame)
{
	frame_t frame;
	info.aCache.aFrames.GetArray(iFrame, frame, 6);

	float vecAngles[3];
	vecAngles[0] = frame.ang[0];
	vecAngles[1] = frame.ang[1];

	if (info.iType == Replay_Prop)
	{
		frame.pos[2] += (frame.buttons & IN_DUCK) ? gF_EyeOffsetDuck : gF_EyeOffset;
	}

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
	info.fFirstFrameTime = -1.0;
	info.bCustomFrames = false;
	//info.bIgnoreLimit
	info.b2x = false;
	info.fDelay = 0.0;

	ClearFrameCache(info.aCache);
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

void CancelReplay(bot_info_t info, bool update = true)
{
	int starter = GetClientFromSerial(info.iStarterSerial);

	if(starter != 0)
	{
		gF_LastInteraction[starter] = GetEngineTime();
		gA_BotInfo[starter].iEnt = -1;
	}

	if (update)
	{
		TeleportToFrame(info, 0);
	}

	ClearBotInfo(info);

	if (update && 1 <= info.iEnt <= MaxClients)
	{
		RequestFrame(Frame_UpdateReplayClient, GetClientSerial(info.iEnt));
	}
}

void KickReplay(bot_info_t info)
{
	if (info.iEnt <= 0)
	{
		return;
	}

	if (info.iType == Replay_Dynamic && !info.bIgnoreLimit)
	{
		--gI_DynamicBots;
	}

	if (1 <= info.iEnt <= MaxClients)
	{
		KickClient(info.iEnt);

		if (info.iType == Replay_Looping)
		{
			gA_LoopingBotConfig[info.iLoopingConfig].bSpawned = false;
		}
	}
	else // Replay_Prop
	{
		int starter = GetClientFromSerial(info.iStarterSerial);

		if (starter != 0)
		{
			// Unset target so we don't get hud errors in the single frame the prop is still alive...
			SetEntPropEnt(starter, Prop_Send, "m_hObserverTarget", 0);
			SetClientViewEntity(starter, starter);
		}

		AcceptEntityInput(info.iEnt, "Kill");
	}

	CancelReplay(info, false);

	info.iEnt = -1;
	info.iType = -1;
}

float GetReplayLength(int style, int track, frame_cache_t aCache)
{
	if(aCache.iFrameCount <= 0)
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

		ReplayOnPlayerRunCmd(gA_BotInfo[i], buttons, impulse, vel);
	}

	if (!gCV_EnableDynamicTimeDifference.BoolValue)
	{
		return;
	}

	int valid = 0;
	int modtick = GetGameTickCount() % gCV_DynamicTimeTick.IntValue;

	for (int client = 1; client <= MaxClients; client++)
	{
		// Using modtick & valid to spread out client updates across different ticks.
		if (IsValidClient(client, true) && !IsFakeClient(client) && Shavit_GetTimerStatus(client) == Timer_Running && !Shavit_InsideZone(client, Zone_Start, Shavit_GetClientTrack(client)) && (++valid % gCV_DynamicTimeTick.IntValue) == modtick)
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

	int iPreFrames = gA_FrameCache[style][track].iPreFrames;
	int iPostFrames = gA_FrameCache[style][track].iPostFrames;
	int iSearch = RoundToFloor(gCV_DynamicTimeSearch.FloatValue * (1.0 / GetTickInterval()));
	int iPlayerFrames = gI_PlayerFrames[client] - gI_PlayerPrerunFrames[client];

	float fClientPos[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", fClientPos);

	int iClosestFrame;
	int iEndFrame;

#if DEBUG
	Profiler profiler = new Profiler();
	profiler.Start();
#endif

	if (gB_ClosestPos)
	{
		iClosestFrame = gH_ClosestPos[track][style].Find(fClientPos);
		iEndFrame = iLength - 1;
		iSearch = 0;
	}
	else
	{
		int iStartFrame = iPlayerFrames - iSearch;
		iEndFrame = iPlayerFrames + iSearch;
		
		if(iSearch == 0)
		{
			iStartFrame = 0;
			iEndFrame = iLength - 1 - iPostFrames;
		}
		else
		{
			// Check if the search behind flag is off
			if(iStartFrame < 0 || gCV_DynamicTimeCheap.IntValue & 2 == 0)
			{
				iStartFrame = 0;
			}
			
			// check if the search ahead flag is off
			if(gCV_DynamicTimeCheap.IntValue & 1 == 0)
			{
				iEndFrame = iLength - 1;
			}
		}

		if (iEndFrame >= iLength)
		{
			iEndFrame = iLength - 1;
		}

		float fReplayPos[3];
		// Single.MaxValue
		float fMinDist = view_as<float>(0x7f7fffff);

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
	}

#if DEBUG
	profiler.Stop();
	PrintToConsole(client, "iClosestFrame(%fs) = %d", client, profiler.Time, iClosestFrame);
	delete profiler;
#endif

	// out of bounds
	if(/*iClosestFrame == 0 ||*/ iClosestFrame == iEndFrame)
	{
		return -1.0;
	}

	// inside start zone
	if(iClosestFrame < iPreFrames)
	{
		gF_VelocityDifference2D[client] = 0.0;
		gF_VelocityDifference3D[client] = 0.0;
		return 0.0;
	}

	float frametime = GetReplayLength(style, track, gA_FrameCache[style][track]) / float(gA_FrameCache[style][track].iFrameCount);
	float timeDifference = (iClosestFrame - iPreFrames) * frametime;

	// Hides the hud if we are using the cheap search method and too far behind to be accurate
	if(iSearch > 0 && gCV_DynamicTimeCheap.BoolValue)
	{
		float preframes = float(gI_PlayerPrerunFrames[client]) / (1.0 / GetTickInterval());
		if(Shavit_GetClientTime(client) - timeDifference >= gCV_DynamicTimeSearch.FloatValue - preframes)
		{
			return -1.0;
		}
	}

	float clientVel[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", clientVel);

	float fReplayPrevPos[3], fReplayClosestPos[3];
	gA_FrameCache[style][track].aFrames.GetArray(iClosestFrame, fReplayClosestPos, 3);
	gA_FrameCache[style][track].aFrames.GetArray(iClosestFrame == 0 ? 0 : iClosestFrame-1, fReplayPrevPos, 3);

	float replayVel[3];
	MakeVectorFromPoints(fReplayClosestPos, fReplayPrevPos, replayVel);
	ScaleVector(replayVel, gF_Tickrate / Shavit_GetStyleSettingFloat(style, "speed") / Shavit_GetStyleSettingFloat(style, "timescale"));

	gF_VelocityDifference2D[client] = (SquareRoot(Pow(clientVel[0], 2.0) + Pow(clientVel[1], 2.0))) - (SquareRoot(Pow(replayVel[0], 2.0) + Pow(replayVel[1], 2.0)));
	gF_VelocityDifference3D[client] = GetVectorLength(clientVel) - GetVectorLength(replayVel);

	return timeDifference;
}

bool WriteNavMesh(const char[] map, bool skipExistsCheck = false)
{
	char sTempMap[PLATFORM_MAX_PATH];
	FormatEx(sTempMap, PLATFORM_MAX_PATH, "maps/%s.nav", map);

	if(skipExistsCheck || !FileExists(sTempMap))
	{
		File file = OpenFile(sTempMap, "wb");

		if(file != null)
		{
			static int defaultNavMesh[205] = {
				0xCE, 0xFA, 0xED, 0xFE, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x58, 0xF6, 0x01, 0x00, 
				0x01, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
				0x00, 0x80, 0xED, 0xC3, 0x00, 0x00, 0x48, 0x42, 0xFF, 0x1F, 0x00, 0x42, 0x00, 0x00, 0x48, 0xC2, 
				0x00, 0x80, 0xED, 0x43, 0xFF, 0x1F, 0x00, 0x42, 0xFF, 0x1F, 0x00, 0x42, 0xFF, 0x1F, 0x00, 0x42, 
				0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
				0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0xE7, 0xC3, 0x00, 0x00, 0x7A, 0x42, 0xFF, 0x1F, 0x00, 
				0x42, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7A, 0xC2, 0x00, 0x00, 0x7A, 0x42, 0xFF, 0x1F, 
				0x00, 0x42, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7A, 0xC2, 0x00, 0x40, 0xE7, 0x43, 0xFF, 
				0x1F, 0x00, 0x42, 0x01, 0x03, 0x00, 0x00, 0x00, 0x00, 0x40, 0xE7, 0xC3, 0x00, 0x40, 0xE7, 0x43, 
				0xFF, 0x1F, 0x00, 0x42, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
				0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x42, 0x00, 0x00, 0xF0, 0x42, 0x00, 0x00, 0x80, 0x3F, 0x00, 
				0x00, 0x80, 0x3F, 0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x80, 0x3F, 0x01, 0x00, 0x00, 0x00, 0x01, 
				0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
			};

			file.Write(defaultNavMesh, 205, 1);
			delete file;
		}

		return true;
	}

	return false;
}
