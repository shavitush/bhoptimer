/*
 * shavit's Timer - Core
 * by: shavit, rtldg, KiD Fearless, GAMMA CASE, Technoblazed, carnifex, ofirgall, Nairda, Extan, rumour, olivia, Nickelony, sh4hrazad, BoomShotKapow, strafe
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
 *
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
#include <sdkhooks>
#include <sdktools>
#include <geoip>
#include <clientprefs>
#include <convar_class>
#include <dhooks>

#define DEBUG 0

#include <shavit/core>

#undef REQUIRE_PLUGIN
#include <shavit/hud>
#include <shavit/rankings>
#include <shavit/replay-playback>
#include <shavit/wr>
#include <shavit/zones>
#include <eventqueuefix>

#include <shavit/chat-colors>
#include <shavit/anti-sv_cheats.sp>
#include <shavit/steamid-stocks>
#include <shavit/style-settings.sp>
#include <shavit/sql-create-tables-and-migrations.sp>
#include <shavit/physicsuntouch>

#include <adminmenu>

#pragma newdecls required
#pragma semicolon 1

// game type (CS:S/CS:GO/TF2)
EngineVersion gEV_Type = Engine_Unknown;
bool gB_Protobuf = false;

// hook stuff
DynamicHook gH_AcceptInput; // used for hooking player_speedmod's AcceptInput
DynamicHook gH_TeleportDhook = null;
Address gI_TF2PreventBunnyJumpingAddr = Address_Null;

// database handle
Database gH_SQL = null;
int gI_Driver = Driver_unknown;

// forwards
Handle gH_Forwards_Start = null;
Handle gH_Forwards_StartPre = null;
Handle gH_Forwards_Stop = null;
Handle gH_Forwards_StopPre = null;
Handle gH_Forwards_FinishPre = null;
Handle gH_Forwards_Finish = null;
Handle gH_Forwards_OnRestartPre = null;
Handle gH_Forwards_OnRestart = null;
Handle gH_Forwards_OnEndPre = null;
Handle gH_Forwards_OnEnd = null;
Handle gH_Forwards_OnPause = null;
Handle gH_Forwards_OnResume = null;
Handle gH_Forwards_OnStyleCommandPre = null;
Handle gH_Forwards_OnStyleChanged = null;
Handle gH_Forwards_OnTrackChanged = null;
Handle gH_Forwards_OnChatConfigLoaded = null;
Handle gH_Forwards_OnUserCmdPre = null;
Handle gH_Forwards_OnTimeIncrement = null;
Handle gH_Forwards_OnTimeIncrementPost = null;
Handle gH_Forwards_OnTimescaleChanged = null;
Handle gH_Forwards_OnTimeOffsetCalculated = null;
Handle gH_Forwards_OnProcessMovement = null;
Handle gH_Forwards_OnProcessMovementPost = null;

// player timer variables
timer_snapshot_t gA_Timers[MAXPLAYERS+1];
bool gB_Auto[MAXPLAYERS+1];
// 0 is in air, 1 or greater is on ground, -1 means client was on ground with zero...ish... velocity
int gI_FirstTouchedGroundForStartTimer[MAXPLAYERS+1];
int gI_LastTickcount[MAXPLAYERS+1];

// these are here until the compiler bug is fixed
float gF_PauseOrigin[MAXPLAYERS+1][3];
float gF_PauseAngles[MAXPLAYERS+1][3];
float gF_PauseVelocity[MAXPLAYERS+1][3];

// potentially temporary more effective hijack angles
int gI_HijackFrames[MAXPLAYERS+1];
float gF_HijackedAngles[MAXPLAYERS+1][2];

// used for offsets
float gF_SmallestDist[MAXPLAYERS + 1];
float gF_Origin[MAXPLAYERS + 1][2][3];
float gF_Fraction[MAXPLAYERS + 1];

// cookies
Handle gH_StyleCookie = null;
Handle gH_AutoBhopCookie = null;
Cookie gH_IHateMain = null;

// late load
bool gB_Late = false;
bool gB_Linux = false;

// modules
bool gB_Eventqueuefix = false;
bool gB_Zones = false;
bool gB_ReplayPlayback = false;
bool gB_Rankings = false;
bool gB_HUD = false;
bool gB_AdminMenu = false;

TopMenu gH_AdminMenu = null;
TopMenuObject gH_TimerCommands = INVALID_TOPMENUOBJECT;

// cvars
Convar gCV_Restart = null;
Convar gCV_Pause = null;
Convar gCV_PauseMovement = null;
Convar gCV_BlockPreJump = null;
Convar gCV_NoZAxisSpeed = null;
Convar gCV_VelocityTeleport = null;
Convar gCV_DefaultStyle = null;
Convar gCV_NoChatSound = null;
Convar gCV_SimplerLadders = null;
Convar gCV_UseOffsets = null;
Convar gCV_TimeInMessages;
Convar gCV_DebugOffsets = null;
Convar gCV_SaveIps = null;
Convar gCV_HijackTeleportAngles = null;
// cached cvars
int gI_DefaultStyle = 0;
bool gB_StyleCookies = true;

// table prefix
char gS_MySQLPrefix[32];

// server side
ConVar sv_accelerate = null;
ConVar sv_airaccelerate = null;
ConVar sv_autobunnyhopping = null;
ConVar sv_enablebunnyhopping = null;
ConVar sv_friction = null;

// chat settings
chatstrings_t gS_ChatStrings;

// misc cache
int gI_ClientProcessingMovement = 0;
bool gB_StopChatSound = false;
bool gB_HookedJump = false;
char gS_LogPath[PLATFORM_MAX_PATH];
char gS_DeleteMap[MAXPLAYERS+1][PLATFORM_MAX_PATH];
int gI_WipePlayerID[MAXPLAYERS+1];
char gS_Verification[MAXPLAYERS+1][8];
bool gB_CookiesRetrieved[MAXPLAYERS+1];
float gF_ZoneAiraccelerate[MAXPLAYERS+1];
float gF_ZoneSpeedLimit[MAXPLAYERS+1];
float gF_ZoneStartSpeedLimit[MAXPLAYERS+1];
int gI_LastPrintedSteamID[MAXPLAYERS+1];

// kz support
bool gB_KZMap[TRACKS_SIZE];


#include <shavit/bhopstats-timerified.sp> // down here to get includes from replay-playback & to inherit gB_ReplayPlayback


public Plugin myinfo =
{
	name = "[shavit] Core",
	author = "shavit, rtldg, KiD Fearless, GAMMA CASE, Technoblazed, carnifex, ofirgall, Nairda, Extan, rumour, olivia, Nickelony, sh4hrazad, BoomShotKapow, strafe",
	description = "The core for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR >= 11
#else
	MarkNativeAsOptional("Int64ToString");
	MarkNativeAsOptional("StringToInt64");
#endif

	new Convar("shavit_core_log_sql", "0", "Whether to log SQL queries from the timer.", 0, true, 0.0, true, 1.0);

	Bhopstats_CreateNatives();
	Shavit_Style_Settings_Natives();

	CreateNative("Shavit_CanPause", Native_CanPause);
	CreateNative("Shavit_ChangeClientStyle", Native_ChangeClientStyle);
	CreateNative("Shavit_FinishMap", Native_FinishMap);
	CreateNative("Shavit_GetBhopStyle", Native_GetBhopStyle);
	CreateNative("Shavit_GetChatStrings", Native_GetChatStrings);
	CreateNative("Shavit_GetChatStringsStruct", Native_GetChatStringsStruct);
	CreateNative("Shavit_GetClientJumps", Native_GetClientJumps);
	CreateNative("Shavit_GetClientTime", Native_GetClientTime);
	CreateNative("Shavit_GetClientTrack", Native_GetClientTrack);
	CreateNative("Shavit_GetDatabase", Native_GetDatabase);
	CreateNative("Shavit_GetPerfectJumps", Native_GetPerfectJumps);
	CreateNative("Shavit_GetStrafeCount", Native_GetStrafeCount);
	CreateNative("Shavit_GetSync", Native_GetSync);
	CreateNative("Shavit_GetZoneOffset", Native_GetZoneOffset);
	CreateNative("Shavit_GetDistanceOffset", Native_GetDistanceOffset);
	CreateNative("Shavit_GetTimerStatus", Native_GetTimerStatus);
	CreateNative("Shavit_IsKZMap", Native_IsKZMap);
	CreateNative("Shavit_IsPaused", Native_IsPaused);
	CreateNative("Shavit_IsPracticeMode", Native_IsPracticeMode);
	CreateNative("Shavit_LoadSnapshot", Native_LoadSnapshot);
	CreateNative("Shavit_LogMessage", Native_LogMessage);
	CreateNative("Shavit_MarkKZMap", Native_MarkKZMap);
	CreateNative("Shavit_PauseTimer", Native_PauseTimer);
	CreateNative("Shavit_PrintToChat", Native_PrintToChat);
	CreateNative("Shavit_PrintToChatAll", Native_PrintToChatAll);
	CreateNative("Shavit_RestartTimer", Native_RestartTimer);
	CreateNative("Shavit_ResumeTimer", Native_ResumeTimer);
	CreateNative("Shavit_SaveSnapshot", Native_SaveSnapshot);
	CreateNative("Shavit_SetPracticeMode", Native_SetPracticeMode);
	CreateNative("Shavit_StartTimer", Native_StartTimer);
	CreateNative("Shavit_StopChatSound", Native_StopChatSound);
	CreateNative("Shavit_StopTimer", Native_StopTimer);
	CreateNative("Shavit_GetClientTimescale", Native_GetClientTimescale);
	CreateNative("Shavit_SetClientTimescale", Native_SetClientTimescale);
	CreateNative("Shavit_GetAvgVelocity", Native_GetAvgVelocity);
	CreateNative("Shavit_GetMaxVelocity", Native_GetMaxVelocity);
	CreateNative("Shavit_SetAvgVelocity", Native_SetAvgVelocity);
	CreateNative("Shavit_SetMaxVelocity", Native_SetMaxVelocity);
	CreateNative("Shavit_ShouldProcessFrame", Native_ShouldProcessFrame);
	CreateNative("Shavit_GotoEnd", Native_GotoEnd);
	CreateNative("Shavit_UpdateLaggedMovement", Native_UpdateLaggedMovement);
	CreateNative("Shavit_PrintSteamIDOnce", Native_PrintSteamIDOnce);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// forwards
	gH_Forwards_Start = CreateGlobalForward("Shavit_OnStart", ET_Ignore, Param_Cell, Param_Cell);
	gH_Forwards_StartPre = CreateGlobalForward("Shavit_OnStartPre", ET_Event, Param_Cell, Param_Cell, Param_CellByRef);
	gH_Forwards_Stop = CreateGlobalForward("Shavit_OnStop", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_StopPre = CreateGlobalForward("Shavit_OnStopPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_FinishPre = CreateGlobalForward("Shavit_OnFinishPre", ET_Hook, Param_Cell, Param_Array);
	gH_Forwards_Finish = CreateGlobalForward("Shavit_OnFinish", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnRestartPre = CreateGlobalForward("Shavit_OnRestartPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnRestart = CreateGlobalForward("Shavit_OnRestart", ET_Ignore, Param_Cell, Param_Cell);
	gH_Forwards_OnEndPre = CreateGlobalForward("Shavit_OnEndPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnEnd = CreateGlobalForward("Shavit_OnEnd", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnPause = CreateGlobalForward("Shavit_OnPause", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnResume = CreateGlobalForward("Shavit_OnResume", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnStyleCommandPre = CreateGlobalForward("Shavit_OnStyleCommandPre", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnStyleChanged = CreateGlobalForward("Shavit_OnStyleChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnTrackChanged = CreateGlobalForward("Shavit_OnTrackChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnChatConfigLoaded = CreateGlobalForward("Shavit_OnChatConfigLoaded", ET_Event);
	gH_Forwards_OnUserCmdPre = CreateGlobalForward("Shavit_OnUserCmdPre", ET_Event, Param_Cell, Param_CellByRef, Param_CellByRef, Param_Array, Param_Array, Param_Cell, Param_Cell, Param_Cell, Param_Array, Param_Array);
	gH_Forwards_OnTimeIncrement = CreateGlobalForward("Shavit_OnTimeIncrement", ET_Event, Param_Cell, Param_Array, Param_CellByRef, Param_Array);
	gH_Forwards_OnTimeIncrementPost = CreateGlobalForward("Shavit_OnTimeIncrementPost", ET_Event, Param_Cell, Param_Cell, Param_Array);
	gH_Forwards_OnTimescaleChanged = CreateGlobalForward("Shavit_OnTimescaleChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnTimeOffsetCalculated = CreateGlobalForward("Shavit_OnTimeOffsetCalculated", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnProcessMovement = CreateGlobalForward("Shavit_OnProcessMovement", ET_Event, Param_Cell);
	gH_Forwards_OnProcessMovementPost = CreateGlobalForward("Shavit_OnProcessMovementPost", ET_Event, Param_Cell);

	Bhopstats_CreateForwards();
	Shavit_Style_Settings_Forwards();

	LoadTranslations("shavit-core.phrases");
	LoadTranslations("shavit-common.phrases");

	// game types
	gEV_Type = GetEngineVersion();
	gB_Protobuf = (GetUserMessageType() == UM_Protobuf);

	sv_autobunnyhopping = FindConVar("sv_autobunnyhopping");
	if (sv_autobunnyhopping)
	{
		sv_autobunnyhopping.BoolValue = false;
		sv_autobunnyhopping.AddChangeHook(OnConVarChanged);
	}

	if (gEV_Type != Engine_CSGO && gEV_Type != Engine_CSS && gEV_Type != Engine_TF2)
	{
		SetFailState("This plugin was meant to be used in CS:S, CS:GO and TF2 *only*.");
	}

	LoadDHooks();

	// hooks
	gB_HookedJump = HookEventEx("player_jump", Player_Jump);
	HookEvent("player_death", Player_Death);
	HookEvent("player_team", Player_Death);
	HookEvent("player_spawn", Player_Death);

	// commands START
	// style
	RegConsoleCmd("sm_style", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_styles", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_diff", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_difficulty", Command_Style, "Choose your bhop style.");
	gH_StyleCookie = RegClientCookie("shavit_style", "Style cookie", CookieAccess_Protected);

	// timer start
	RegConsoleCmd("sm_start", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_r", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_restart", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_m", Command_StartTimer, "Start your timer on the main track.");
	RegConsoleCmd("sm_main", Command_StartTimer, "Start your timer on the main track.");
	RegConsoleCmd("sm_ihate!main", Command_IHateMain, "If you really hate !main :(((");
	gH_IHateMain = new Cookie("shavit_mainhater", "If you really hate !main :(((", CookieAccess_Protected);

	RegConsoleCmd("sm_b", Command_StartTimer, "Start your timer on the bonus track.");
	RegConsoleCmd("sm_bonus", Command_StartTimer, "Start your timer on the bonus track.");

	for (int i = Track_Bonus; i <= Track_Bonus_Last; i++)
	{
		char cmd[10], helptext[50];
		FormatEx(cmd, sizeof(cmd), "sm_b%d", i);
		FormatEx(helptext, sizeof(helptext), "Start your timer on the bonus %d track.", i);
		RegConsoleCmd(cmd, Command_StartTimer, helptext);
	}

	// teleport to end
	RegConsoleCmd("sm_end", Command_TeleportEnd, "Teleport to endzone.");

	RegConsoleCmd("sm_bend", Command_TeleportEnd, "Teleport to endzone of the bonus track.");
	RegConsoleCmd("sm_bonusend", Command_TeleportEnd, "Teleport to endzone of the bonus track.");

	// timer stop
	RegConsoleCmd("sm_stop", Command_StopTimer, "Stop your timer.");

	// timer pause / resume
	RegConsoleCmd("sm_pause", Command_TogglePause, "Toggle pause.");
	RegConsoleCmd("sm_unpause", Command_TogglePause, "Toggle pause.");
	RegConsoleCmd("sm_resume", Command_TogglePause, "Toggle pause");

	// autobhop toggle
	RegConsoleCmd("sm_auto", Command_AutoBhop, "Toggle autobhop.");
	RegConsoleCmd("sm_autobhop", Command_AutoBhop, "Toggle autobhop.");
	gH_AutoBhopCookie = RegClientCookie("shavit_autobhop", "Autobhop cookie", CookieAccess_Protected);

	// Timescale commandssssssssss
	RegConsoleCmd("sm_timescale", Command_Timescale, "Sets your timescale on TAS styles.");
	RegConsoleCmd("sm_ts", Command_Timescale, "Sets your timescale on TAS styles.");
	RegConsoleCmd("sm_timescaleplus", Command_TimescalePlus, "Adds the value to your current timescale.");
	RegConsoleCmd("sm_tsplus", Command_TimescalePlus, "Adds the value to your current timescale.");
	RegConsoleCmd("sm_timescaleminus", Command_TimescaleMinus, "Subtracts the value from your current timescale.");
	RegConsoleCmd("sm_tsminus", Command_TimescaleMinus, "Subtracts the value from your current timescale.");

	#if DEBUG
	RegConsoleCmd("sm_finishtest", Command_FinishTest);
	RegConsoleCmd("sm_fling", Command_Fling);
	#endif

	// admin
	RegAdminCmd("sm_deletemap", Command_DeleteMap, ADMFLAG_ROOT, "Deletes all map data. Usage: sm_deletemap <map>");
	RegAdminCmd("sm_wipeplayer", Command_WipePlayer, ADMFLAG_BAN, "Wipes all bhoptimer data for specified player. Usage: sm_wipeplayer <steamid3>");
	RegAdminCmd("sm_wipetrack", Command_WipeTrack, ADMFLAG_ROOT, "Deletes all runs on a track.");
	RegAdminCmd("sm_migration", Command_Migration, ADMFLAG_ROOT, "Force a database migration to run. Usage: sm_migration <migration id> or \"all\" to run all migrations.");
	// commands END

	// logs
	BuildPath(Path_SM, gS_LogPath, PLATFORM_MAX_PATH, "logs/shavit.log");

	CreateConVar("shavit_version", SHAVIT_VERSION, "Plugin version.", (FCVAR_NOTIFY | FCVAR_DONTRECORD));

	gCV_Restart = new Convar("shavit_core_restart", "1", "Allow commands that restart the timer?", 0, true, 0.0, true, 1.0);
	gCV_Pause = new Convar("shavit_core_pause", "1", "Allow pausing?", 0, true, 0.0, true, 1.0);
	gCV_PauseMovement = new Convar("shavit_core_pause_movement", "0", "Allow movement/noclip while paused?\n0 - Disabled, no movement while paused.\n1 - Allow movement/noclip while paused, must stand still to pause.\n2 - Allow movement/noclip while paused, can pause while moving. (Not recommended)\n3 - Disallow movement/noclip while paused, can pause while moving. (Not recommended)", 0, true, 0.0, true, 3.0);
	gCV_BlockPreJump = new Convar("shavit_core_blockprejump", "0", "Prevents jumping in the start zone.", 0, true, 0.0, true, 1.0);
	gCV_NoZAxisSpeed = new Convar("shavit_core_nozaxisspeed", "1", "Don't start timer if vertical speed exists (btimes style).", 0, true, 0.0, true, 1.0);
	gCV_VelocityTeleport = new Convar("shavit_core_velocityteleport", "0", "Teleport the client when changing its velocity? (for special styles)", 0, true, 0.0, true, 1.0);
	gCV_DefaultStyle = new Convar("shavit_core_defaultstyle", "0", "Default style ID.\nAdd the '!' prefix to disable style cookies - i.e. \"!3\" to *force* scroll to be the default style.", 0, true, 0.0);
	gCV_NoChatSound = new Convar("shavit_core_nochatsound", "0", "Disables click sound for chat messages.", 0, true, 0.0, true, 1.0);
	gCV_SimplerLadders = new Convar("shavit_core_simplerladders", "1", "Allows using all keys on limited styles (such as sideways) after touching ladders\nTouching the ground enables the restriction again.", 0, true, 0.0, true, 1.0);
	gCV_UseOffsets = new Convar("shavit_core_useoffsets", "1", "Calculates more accurate times by subtracting/adding tick offsets from the time the server uses to register that a player has left or entered a trigger", 0, true, 0.0, true, 1.0);
	gCV_TimeInMessages = new Convar("shavit_core_timeinmessages", "0", "Whether to prefix SayText2 messages with the time.", 0, true, 0.0, true, 1.0);
	gCV_DebugOffsets = new Convar("shavit_core_debugoffsets", "0", "Print offset upon leaving or entering a zone?", 0, true, 0.0, true, 1.0);
	gCV_SaveIps = new Convar("shavit_core_save_ips", "1", "Whether to save player IPs in the 'users' database table. IPs are used to show player location on the !profile menu.\nTurning this off will not wipe existing IPs from the 'users' table.", 0, true, 0.0, true, 1.0);
	gCV_HijackTeleportAngles = new Convar("shavit_core_hijack_teleport_angles", "0", "Whether to hijack player angles on teleport so their latency doesn't fuck up their shit.", 0, true, 0.0, true, 1.0);
	gCV_DefaultStyle.AddChangeHook(OnConVarChanged);

	Anti_sv_cheats_cvars();

	Convar.AutoExecConfig();

	sv_accelerate = FindConVar("sv_accelerate");
	sv_airaccelerate = FindConVar("sv_airaccelerate");
	sv_airaccelerate.Flags &= ~(FCVAR_NOTIFY | FCVAR_REPLICATED);

	sv_enablebunnyhopping = FindConVar("sv_enablebunnyhopping");

	if(sv_enablebunnyhopping != null)
	{
		sv_enablebunnyhopping.Flags &= ~(FCVAR_NOTIFY | FCVAR_REPLICATED);
	}

	sv_friction = FindConVar("sv_friction");

	gB_Eventqueuefix = LibraryExists("eventqueuefix");
	gB_Zones = LibraryExists("shavit-zones");
	gB_ReplayPlayback = LibraryExists("shavit-replay-playback");
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_HUD = LibraryExists("shavit-hud");
	gB_AdminMenu = LibraryExists("adminmenu");

	// database connections
	SQL_DBConnect();

	// late
	if(gB_Late)
	{
		if (gB_AdminMenu && (gH_AdminMenu = GetAdminTopMenu()) != null)
		{
			OnAdminMenuCreated(gH_AdminMenu);
			OnAdminMenuReady(gH_AdminMenu);
		}

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnPluginEnd()
{
	if (sv_enablebunnyhopping != null)
		sv_enablebunnyhopping.Flags |= (FCVAR_REPLICATED | FCVAR_NOTIFY);
	sv_airaccelerate.Flags |= (FCVAR_REPLICATED | FCVAR_NOTIFY);
}

public void OnAdminMenuCreated(Handle topmenu)
{
	gH_AdminMenu = TopMenu.FromHandle(topmenu);

	if ((gH_TimerCommands = gH_AdminMenu.FindCategory("Timer Commands")) == INVALID_TOPMENUOBJECT)
	{
		gH_TimerCommands = gH_AdminMenu.AddCategory("Timer Commands", CategoryHandler, "shavit_admin", ADMFLAG_RCON);
	}
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
	gH_AdminMenu = TopMenu.FromHandle(topmenu);
}

void LoadDHooks()
{
	GameData gamedataConf = LoadGameConfigFile("shavit.games");

	if(gamedataConf == null)
	{
		SetFailState("Failed to load shavit gamedata");
	}

	StartPrepSDKCall(SDKCall_Static);
	if(!PrepSDKCall_SetFromConf(gamedataConf, SDKConf_Signature, "CreateInterface_Server"))
	{
		SetFailState("Failed to get CreateInterface");
	}
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	Handle CreateInterface = EndPrepSDKCall();

	if(CreateInterface == null)
	{
		SetFailState("Unable to prepare SDKCall for CreateInterface");
	}

	char interfaceName[64];

	// ProcessMovement
	if(!GameConfGetKeyValue(gamedataConf, "IGameMovement", interfaceName, sizeof(interfaceName)))
	{
		SetFailState("Failed to get IGameMovement interface name");
	}

	Address IGameMovement = SDKCall(CreateInterface, interfaceName, 0);

	if(!IGameMovement)
	{
		SetFailState("Failed to get IGameMovement pointer");
	}

	int offset = GameConfGetOffset(gamedataConf, "ProcessMovement");
	if(offset == -1)
	{
		SetFailState("Failed to get ProcessMovement offset");
	}

	Handle processMovement = DHookCreate(offset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore, DHook_ProcessMovementPre);
	DHookAddParam(processMovement, HookParamType_CBaseEntity);
	DHookAddParam(processMovement, HookParamType_ObjectPtr);
	DHookRaw(processMovement, false, IGameMovement);

	Handle processMovementPost = DHookCreate(offset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore, DHook_ProcessMovementPost);
	DHookAddParam(processMovementPost, HookParamType_CBaseEntity);
	DHookAddParam(processMovementPost, HookParamType_ObjectPtr);
	DHookRaw(processMovementPost, true, IGameMovement);

	gB_Linux = GameConfGetOffset(gamedataConf, "OS") == 2;

	if (gEV_Type == Engine_TF2 && gB_Linux)
	{
		Handle PreventBunnyJumping = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_Ignore);

		if (!DHookSetFromConf(PreventBunnyJumping, gamedataConf, SDKConf_Signature, "CTFGameMovement::PreventBunnyJumping"))
		{
			SetFailState("Failed to set CTFGameMovement::PreventBunnyJumping signature");
		}

		if (!DHookEnableDetour(PreventBunnyJumping, false, DHook_PreventBunnyJumpingPre))
		{
			SetFailState("Failed to find CTFGameMovement::PreventBunnyJumping signature");
		}
	}
	else if (gEV_Type == Engine_TF2 && !gB_Linux)
	{
		gI_TF2PreventBunnyJumpingAddr = gamedataConf.GetMemSig("CTFGameMovement::PreventBunnyJumping");

		if (gI_TF2PreventBunnyJumpingAddr == Address_Null)
		{
			SetFailState("Failed to find CTFGameMovement::PreventBunnyJumping signature");
		}
		else
		{
			// Write the original JNZ byte but with updateMemAccess=true so we don't repeatedly page-protect it later.
			StoreToAddress(gI_TF2PreventBunnyJumpingAddr, 0x75, NumberType_Int8, true);
		}
	}

	LoadPhysicsUntouch(gamedataConf);

	delete CreateInterface;
	delete gamedataConf;

	gamedataConf = LoadGameConfigFile("sdktools.games");

	offset = GameConfGetOffset(gamedataConf, "AcceptInput");
	gH_AcceptInput = new DynamicHook(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity);
	gH_AcceptInput.AddParam(HookParamType_CharPtr);
	gH_AcceptInput.AddParam(HookParamType_CBaseEntity);
	gH_AcceptInput.AddParam(HookParamType_CBaseEntity);
	gH_AcceptInput.AddParam(HookParamType_Object, 20, DHookPass_ByVal|DHookPass_ODTOR|DHookPass_OCTOR|DHookPass_OASSIGNOP); //variant_t is a union of 12 (float[3]) plus two int type params 12 + 8 = 20
	gH_AcceptInput.AddParam(HookParamType_Int);

	offset = GameConfGetOffset(gamedataConf, "Teleport");
	if (offset == -1)
	{
		SetFailState("Couldn't get the offset for \"Teleport\"!");
	}

	gH_TeleportDhook = new DynamicHook(offset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity);

	gH_TeleportDhook.AddParam(HookParamType_VectorPtr);
	gH_TeleportDhook.AddParam(HookParamType_VectorPtr);
	gH_TeleportDhook.AddParam(HookParamType_VectorPtr);
	if (gEV_Type == Engine_CSGO)
	{
		gH_TeleportDhook.AddParam(HookParamType_Bool);
	}

	delete gamedataConf;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == sv_autobunnyhopping)
	{
		if (convar.BoolValue)
			convar.BoolValue = false;
		return;
	}

	gB_StyleCookies = (newValue[0] != '!');
	gI_DefaultStyle = StringToInt(newValue[1]);
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}
	else if(StrEqual(name, "shavit-replay-playback"))
	{
		gB_ReplayPlayback = true;
	}
	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}
	else if(StrEqual(name, "shavit-hud"))
	{
		gB_HUD = true;
	}
	else if(StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = true;
	}
	else if (StrEqual(name, "adminmenu"))
	{
		gB_AdminMenu = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}
	else if(StrEqual(name, "shavit-replay-playback"))
	{
		gB_ReplayPlayback = false;
	}
	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}
	else if(StrEqual(name, "shavit-hud"))
	{
		gB_HUD = false;
	}
	else if(StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = false;
	}
	else if (StrEqual(name, "adminmenu"))
	{
		gB_AdminMenu = false;
		gH_AdminMenu = null;
		gH_TimerCommands = INVALID_TOPMENUOBJECT;
	}
}

public void OnMapStart()
{
	// styles
	if(!LoadStyles())
	{
		SetFailState("Could not load the styles configuration file. Make sure it exists (addons/sourcemod/configs/shavit-styles.cfg) and follows the proper syntax!");
	}

	// messages
	if(!LoadMessages())
	{
		SetFailState("Could not load the chat messages configuration file. Make sure it exists (addons/sourcemod/configs/shavit-messages.cfg) and follows the proper syntax!");
	}
}

public void OnConfigsExecuted()
{
	Anti_sv_cheats_OnConfigsExecuted();
}

public void OnMapEnd()
{
	bool empty[TRACKS_SIZE];
	gB_KZMap = empty;
}

public Action Command_StartTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	if(!gCV_Restart.BoolValue)
	{
		if(args != -1)
		{
			Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings.sVariable, sCommand, gS_ChatStrings.sText);
		}

		return Plugin_Handled;
	}

	int track = Track_Main;

	if(StrContains(sCommand, "sm_b", false) == 0)
	{
		// Pull out bonus number for commands like sm_b1 and sm_b2.
		if ('1' <= sCommand[4] <= ('0' + Track_Bonus_Last))
		{
			track = sCommand[4] - '0';
		}
		else if (args < 1)
		{
			track = Shavit_GetClientTrack(client);
		}
		else
		{
			char arg[6];
			GetCmdArg(1, arg, sizeof(arg));
			track = StringToInt(arg);
		}

		if (track < Track_Bonus || track > Track_Bonus_Last)
		{
			track = Track_Bonus;
		}
	}
	else if(StrContains(sCommand, "sm_r", false) == 0 || StrContains(sCommand, "sm_s", false) == 0)
	{
		track = (DoIHateMain(client)) ? Track_Main : gA_Timers[client].iTimerTrack;
	}

	if (!gB_Zones || !(Shavit_ZoneExists(Zone_Start, track) || gB_KZMap[track]))
	{
		char sTrack[32];
		GetTrackName(client, track, sTrack, 32);

		Shavit_PrintToChat(client, "%T", "StartZoneUndefined", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTrack, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	Shavit_RestartTimer(client, track, false);

	return Plugin_Handled;
}

bool DoIHateMain(int client)
{
	char data[2];
	gH_IHateMain.Get(client, data, sizeof(data));
	return (data[0] == '1');
}

public Action Command_IHateMain(int client, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	bool bIHateMain = DoIHateMain(client);
	gH_IHateMain.Set(client, (bIHateMain) ? "0" : "1");
	Shavit_PrintToChat(client, (bIHateMain) ? ":)" : ":(");

	return Plugin_Handled;
}

public Action Command_TeleportEnd(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	int track = Track_Main;

	if(StrContains(sCommand, "sm_b", false) == 0)
	{
		if (args < 1)
		{
			track = Shavit_GetClientTrack(client);
		}
		else
		{
			char arg[6];
			GetCmdArg(1, arg, sizeof(arg));
			track = StringToInt(arg);
		}

		if (track < Track_Bonus || track > Track_Bonus_Last)
		{
			track = Track_Bonus;
		}
	}

	if (!gB_Zones || !(Shavit_ZoneExists(Zone_End, track) || gB_KZMap[track]))
	{
		Shavit_PrintToChat(client, "%T", "EndZoneUndefined", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return Plugin_Handled;
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnEndPre);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_Finish(result);

	if (result > Plugin_Continue)
	{
		return Plugin_Handled;
	}

	if (!Shavit_StopTimer(client, false))
	{
		return Plugin_Handled;
	}

	Call_StartForward(gH_Forwards_OnEnd);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_Finish();

	return Plugin_Handled;
}

public Action Command_StopTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Shavit_StopTimer(client, false);

	return Plugin_Handled;
}

public Action Command_TogglePause(int client, int args)
{
	if(!(1 <= client <= MaxClients) || !IsClientInGame(client))
	{
		return Plugin_Handled;
	}

	int iFlags = Shavit_CanPause(client);

	if((iFlags & CPR_NoTimer) > 0)
	{
		return Plugin_Handled;
	}

	if((iFlags & CPR_InStartZone) > 0)
	{
		Shavit_PrintToChat(client, "%T", "PauseStartZone", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if((iFlags & CPR_InEndZone) > 0)
	{
		Shavit_PrintToChat(client, "%T", "PauseEndZone", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if((iFlags & CPR_ByConVar) > 0)
	{
		char sCommand[16];
		GetCmdArg(0, sCommand, 16);

		Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings.sVariable, sCommand, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if (gA_Timers[client].bClientPaused)
	{
		TeleportEntity(client, gF_PauseOrigin[client], gF_PauseAngles[client], gF_PauseVelocity[client]);
		ResumeTimer(client);

		Shavit_PrintToChat(client, "%T", "MessageUnpause", client, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
	else
	{
		if (gCV_PauseMovement.IntValue == 0 || gCV_PauseMovement.IntValue == 1)
		{
			if ((iFlags & CPR_NotOnGround))
			{
				Shavit_PrintToChat(client, "%T", "PauseNotOnGround", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}

			if ((iFlags & CPR_Moving))
			{
				Shavit_PrintToChat(client, "%T", "PauseMoving", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}

			if ((iFlags & CPR_Duck))
			{
				Shavit_PrintToChat(client, "%T", "PauseDuck", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

				return Plugin_Handled;
			}
		}

		GetClientAbsOrigin(client, gF_PauseOrigin[client]);
		GetClientEyeAngles(client, gF_PauseAngles[client]);
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", gF_PauseVelocity[client]);

		PauseTimer(client);

		Shavit_PrintToChat(client, "%T", "MessagePause", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

public Action Command_Timescale(int client, int args)
{
	if (!IsValidClient(client, true))
	{
		return Plugin_Handled;
	}

	if (GetStyleSettingFloat(gA_Timers[client].bsStyle, "tas_timescale") != -1.0)
	{
		Shavit_PrintToChat(client, "%T", "NoEditingTimescale", client);
		return Plugin_Handled;
	}

	if (args < 1)
	{
		Shavit_PrintToChat(client, "!timescale <number>");
		return Plugin_Handled;
	}

	char sArg[16];
	GetCmdArg(1, sArg, 16);
	float ts = StringToFloat(sArg);

	if (ts >= 0.01 && ts <= 1.0)
	{
		Shavit_SetClientTimescale(client, ts);
	}

	return Plugin_Handled;
}

public Action Command_TimescalePlus(int client, int args)
{
	if (!IsValidClient(client, true))
	{
		return Plugin_Handled;
	}

	if (GetStyleSettingFloat(gA_Timers[client].bsStyle, "tas_timescale") != -1.0)
	{
		Shavit_PrintToChat(client, "%T", "NoEditingTimescale", client);
		return Plugin_Handled;
	}

	float ts = 0.1;

	if (args > 0)
	{
		char sArg[16];
		GetCmdArg(1, sArg, 16);
		ts = StringToFloat(sArg);
	}

	if (ts >= 0.01)
	{
		ts += gA_Timers[client].fTimescale;

		if (ts > 1.0)
		{
			ts = 1.0;
		}

		Shavit_SetClientTimescale(client, ts);
	}

	return Plugin_Handled;
}

public Action Command_TimescaleMinus(int client, int args)
{
	if (!IsValidClient(client, true))
	{
		return Plugin_Handled;
	}

	if (GetStyleSettingFloat(gA_Timers[client].bsStyle, "tas_timescale") != -1.0)
	{
		Shavit_PrintToChat(client, "%T", "NoEditingTimescale", client);
		return Plugin_Handled;
	}

	float ts = 0.1;

	if (args > 0)
	{
		char sArg[16];
		GetCmdArg(1, sArg, 16);
		ts = StringToFloat(sArg);
	}

	if (ts >= 0.01)
	{
		float newts = ts;

		// very hacky I know but I hate formatting timescales and seeing 0.39999 because float subtraction is stupid
		for (int i = 0; i < 99; i++)
		{
			float x = newts + ts;

			if (x >= gA_Timers[client].fTimescale)
			{
				break;
			}

			newts = x;
		}

		if (newts < ts)
		{
			newts = ts;
		}

		if (newts < 0.01)
		{
			newts = 0.01;
		}

		Shavit_SetClientTimescale(client, newts);
	}

	return Plugin_Handled;
}

#if DEBUG
public Action Command_FinishTest(int client, int args)
{
	Shavit_FinishMap(client, gA_Timers[client].iTimerTrack);

	return Plugin_Handled;
}

public Action Command_Fling(int client, int args)
{
	float up[3];
	up[2] = 1000.0;
	SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", up);

	return Plugin_Handled;
}
#endif

public Action Command_DeleteMap(int client, int args)
{
	if(args == 0)
	{
		ReplyToCommand(client, "Usage: sm_deletemap <map>\nOnce a map is chosen, \"sm_deletemap confirm\" to run the deletion.");

		return Plugin_Handled;
	}

	char sArgs[PLATFORM_MAX_PATH];
	GetCmdArgString(sArgs, sizeof(sArgs));
	LowercaseString(sArgs);

	if(StrEqual(sArgs, "confirm") && strlen(gS_DeleteMap[client]) > 0)
	{
		Shavit_WR_DeleteMap(gS_DeleteMap[client]);
		ReplyToCommand(client, "Deleted all records for %s.", gS_DeleteMap[client]);

		if(gB_Zones)
		{
			Shavit_Zones_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all zones for %s.", gS_DeleteMap[client]);
		}

		if (gB_ReplayPlayback)
		{
			Shavit_Replay_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all replay data for %s.", gS_DeleteMap[client]);
		}

		if(gB_Rankings)
		{
			Shavit_Rankings_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all rankings for %s.", gS_DeleteMap[client]);
		}

		Shavit_LogMessage("%L - deleted all map data for `%s`", client, gS_DeleteMap[client]);
		ReplyToCommand(client, "Finished deleting data for %s.", gS_DeleteMap[client]);
		gS_DeleteMap[client] = "";
	}
	else
	{
		gS_DeleteMap[client] = sArgs;
		ReplyToCommand(client, "Map to delete is now %s.\nRun \"sm_deletemap confirm\" to delete all data regarding the map %s.", gS_DeleteMap[client], gS_DeleteMap[client]);
	}

	return Plugin_Handled;
}

public Action Command_Migration(int client, int args)
{
	if(args == 0)
	{
		ReplyToCommand(client, "Usage: sm_migration <migration id or \"all\" to run all migrationsd>.");

		return Plugin_Handled;
	}

	char sArg[16];
	GetCmdArg(1, sArg, 16);

	bool bApplyMigration[MIGRATIONS_END];

	if(StrEqual(sArg, "all"))
	{
		for(int i = 0; i < MIGRATIONS_END; i++)
		{
			bApplyMigration[i] = true;
		}
	}
	else
	{
		int iMigration = StringToInt(sArg);

		if(0 <= iMigration < MIGRATIONS_END)
		{
			bApplyMigration[iMigration] = true;
		}
	}

	for(int i = 0; i < MIGRATIONS_END; i++)
	{
		if(bApplyMigration[i])
		{
			ReplyToCommand(client, "Applying database migration %d", i);
			ApplyMigration(i);
		}
	}

	return Plugin_Handled;
}

public Action Command_WipePlayer(int client, int args)
{
	if(args == 0)
	{
		ReplyToCommand(client, "Usage: sm_wipeplayer <steamid3>\nAfter entering a SteamID, you will be prompted with a verification captcha.");

		return Plugin_Handled;
	}

	char sArgString[32];
	GetCmdArgString(sArgString, 32);

	if(strlen(gS_Verification[client]) == 0 || !StrEqual(sArgString, gS_Verification[client]))
	{
		gI_WipePlayerID[client] = SteamIDToAccountID(sArgString);

		if(gI_WipePlayerID[client] == 0)
		{
			Shavit_PrintToChat(client, "Entered SteamID (%s) is invalid. The range for valid SteamIDs is [U:1:1] to [U:1:4294967295].", sArgString);

			return Plugin_Handled;
		}

		char sAlphabet[] = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#";
		strcopy(gS_Verification[client], 8, "");

		for(int i = 0; i < 5; i++)
		{
			gS_Verification[client][i] = sAlphabet[GetRandomInt(0, sizeof(sAlphabet) - 1)];
		}

		Shavit_PrintToChat(client, "Preparing to delete all user data for SteamID %s[U:1:%u]%s. To confirm, enter %s!wipeplayer %s",
			gS_ChatStrings.sVariable, gI_WipePlayerID[client], gS_ChatStrings.sText, gS_ChatStrings.sVariable2, gS_Verification[client]);
	}
	else
	{
		Shavit_PrintToChat(client, "Deleting data for SteamID %s[U:1:%u]%s...",
			gS_ChatStrings.sVariable, gI_WipePlayerID[client], gS_ChatStrings.sText);

		Shavit_LogMessage("%L - wiped [U:1:%u]'s player data", client, gI_WipePlayerID[client]);
		DeleteUserData(client, gI_WipePlayerID[client]);

		strcopy(gS_Verification[client], 8, "");
		gI_WipePlayerID[client] = -1;
	}

	return Plugin_Handled;
}

public Action Command_WipeTrack(int client, int args)
{

	return Plugin_Handled;
}

public void Trans_DeleteRestOfUserSuccess(Database db, DataPack hPack, int numQueries, DBResultSet[] results, any[] queryData)
{
	hPack.Reset();
	int client = hPack.ReadCell();
	int iSteamID = hPack.ReadCell();
	delete hPack;

	Shavit_ReloadLeaderboards();

	Shavit_LogMessage("%L - wiped user data for [U:1:%u].", client, iSteamID);
	Shavit_PrintToChat(client, "Finished wiping timer data for user %s[U:1:%u]%s.", gS_ChatStrings.sVariable, iSteamID, gS_ChatStrings.sText);
}

public void Trans_DeleteRestOfUserFailed(Database db, DataPack hPack, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	hPack.Reset();
	hPack.ReadCell();
	int iSteamID = hPack.ReadCell();
	delete hPack;
	LogError("Timer error! Failed to wipe user data (wipe | delete user data/times, id [U:1:%u]). Reason: %s", iSteamID, error);
}

void DeleteRestOfUser(int iSteamID, DataPack hPack)
{
	Transaction trans = new Transaction();
	char sQuery[256];

	FormatEx(sQuery, 256, "DELETE FROM %splayertimes WHERE auth = %d;", gS_MySQLPrefix, iSteamID);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, 256, "DELETE FROM %susers WHERE auth = %d;", gS_MySQLPrefix, iSteamID);
	AddQueryLog(trans, sQuery);

	gH_SQL.Execute(trans, Trans_DeleteRestOfUserSuccess, Trans_DeleteRestOfUserFailed, hPack);
}

void DeleteUserData(int client, const int iSteamID)
{
	DataPack hPack = new DataPack();
	hPack.WriteCell(client);
	hPack.WriteCell(iSteamID);
	char sQuery[512];

	FormatEx(sQuery, sizeof(sQuery),
		"SELECT id, style, track, map FROM %swrs WHERE auth = %d;",
		gS_MySQLPrefix, iSteamID);

	QueryLog(gH_SQL, SQL_DeleteUserData_GetRecords_Callback, sQuery, hPack, DBPrio_High);
}

public void SQL_DeleteUserData_GetRecords_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	hPack.Reset();
	hPack.ReadCell(); /*int client = */
	int iSteamID = hPack.ReadCell();

	if(results == null)
	{
		LogError("Timer error! Failed to wipe user data (wipe | get player records). Reason: %s", error);
		delete hPack;
		return;
	}

	char map[PLATFORM_MAX_PATH];

	while(results.FetchRow())
	{
		int id = results.FetchInt(0);
		int style = results.FetchInt(1);
		int track = results.FetchInt(2);
		results.FetchString(3, map, sizeof(map));

		Shavit_DeleteWR(style, track, map, iSteamID, id, false, false);
	}

	DeleteRestOfUser(iSteamID, hPack);
}

public Action Command_AutoBhop(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gB_Auto[client] = !gB_Auto[client];

	if (gB_Auto[client])
	{
		Shavit_PrintToChat(client, "%T", "AutobhopEnabled", client, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);
	}
	else
	{
		Shavit_PrintToChat(client, "%T", "AutobhopDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	char sAutoBhop[4];
	IntToString(view_as<int>(gB_Auto[client]), sAutoBhop, 4);
	SetClientCookie(client, gH_AutoBhopCookie, sAutoBhop);

	UpdateStyleSettings(client);

	return Plugin_Handled;
}

public Action Command_Style(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	// allow !style <number>
	if (args > 0)
	{
		char sArgs[16];
		GetCmdArg(1, sArgs, sizeof(sArgs));
		int style = StringToInt(sArgs);

		if (style < 0 || style >= Shavit_GetStyleCount())
		{
			return Plugin_Handled;
		}

		if (GetStyleSettingBool(style, "inaccessible"))
		{
			return Plugin_Handled;
		}

		ChangeClientStyle(client, style, true);
		return Plugin_Handled;
	}

	Menu menu = new Menu(StyleMenu_Handler);
	menu.SetTitle("%T", "StyleMenuTitle", client);

	int iStyleCount = Shavit_GetStyleCount();
	int iOrderedStyles[STYLE_LIMIT];
	Shavit_GetOrderedStyles(iOrderedStyles, iStyleCount);

	for(int i = 0; i < iStyleCount; i++)
	{
		int iStyle = iOrderedStyles[i];

		// this logic will prevent the style from showing in !style menu if it's specifically inaccessible
		// or just completely disabled
		if((GetStyleSettingBool(iStyle, "inaccessible") && GetStyleSettingInt(iStyle, "enabled") == 1) ||
		GetStyleSettingInt(iStyle, "enabled") == -1)
		{
			continue;
		}

		char sInfo[8];
		IntToString(iStyle, sInfo, 8);

		char sDisplay[64];

		if(GetStyleSettingBool(iStyle, "unranked"))
		{
			char sName[64];
			GetStyleSetting(iStyle, "name", sName, sizeof(sName));
			FormatEx(sDisplay, 64, "%T %s", "StyleUnranked", client, sName);
		}
		else
		{
			float time = Shavit_GetWorldRecord(iStyle, gA_Timers[client].iTimerTrack);

			if(time > 0.0)
			{
				char sTime[32];
				FormatSeconds(time, sTime, 32, false);

				char sWR[8];
				strcopy(sWR, 8, "WR");

				if (gA_Timers[client].iTimerTrack >= Track_Bonus)
				{
					strcopy(sWR, 8, "BWR");
				}

				char sName[64];
				GetStyleSetting(iStyle, "name", sName, sizeof(sName));

				float pb = Shavit_GetClientPB(client, iStyle, gA_Timers[client].iTimerTrack);

				if(pb > 0.0)
				{
					char sPb[32];
					FormatSeconds(pb, sPb, 32, false);
					FormatEx(sDisplay, 64, "%s - %s: %s - PB: %s", sName, sWR, sTime, sPb);
				}
				else
				{
					FormatEx(sDisplay, 64, "%s - %s: %s", sName, sWR, sTime);
				}
			}
			else
			{
				GetStyleSetting(iStyle, "name", sDisplay, sizeof(sDisplay));
			}
		}

		menu.AddItem(sInfo, sDisplay, (gA_Timers[client].bsStyle == iStyle || !Shavit_HasStyleAccess(client, iStyle))? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	}

	// should NEVER happen
	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "Nothing");
	}
	else if(menu.ItemCount <= ((gEV_Type == Engine_CSS)? 9:8))
	{
		menu.Pagination = MENU_NO_PAGINATION;
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int StyleMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);

		int style = StringToInt(info);

		if(style == -1)
		{
			return 0;
		}

		ChangeClientStyle(param1, style, true);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void CallOnTrackChanged(int client, int oldtrack, int newtrack)
{
	gA_Timers[client].iTimerTrack = newtrack;

	Call_StartForward(gH_Forwards_OnTrackChanged);
	Call_PushCell(client);
	Call_PushCell(oldtrack);
	Call_PushCell(newtrack);
	Call_Finish();

	if (oldtrack == Track_Main && oldtrack != newtrack && !DoIHateMain(client))
	{
		Shavit_StopChatSound();
		Shavit_PrintToChat(client, "%T", "TrackChangeFromMain", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
}

public any Native_PrintSteamIDOnce(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int steamid = GetNativeCell(2);

	if (gI_LastPrintedSteamID[client] != steamid && GetSteamAccountID(client) != steamid)
	{
		gI_LastPrintedSteamID[client] = steamid;

		char targetname[32+1], steam2[40], steam64[40];

		GetNativeString(3, targetname, sizeof(targetname));
		AccountIDToSteamID2(steamid, steam2, sizeof(steam2));
		AccountIDToSteamID64(steamid, steam64, sizeof(steam64));

		Shavit_PrintToChat(client, "%s: %s%s %s[U:1:%u]%s %s", targetname, gS_ChatStrings.sVariable, steam2, gS_ChatStrings.sText, steamid, gS_ChatStrings.sVariable, steam64);
	}

	return 1;
}

public any Native_UpdateLaggedMovement(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	bool user_timescale = GetNativeCell(2) != 0;
	UpdateLaggedMovement(client, user_timescale);
	return 1;
}

void UpdateLaggedMovement(int client, bool user_timescale)
{
	float style_laggedmovement =
		  GetStyleSettingFloat(gA_Timers[client].bsStyle, "timescale")
		* GetStyleSettingFloat(gA_Timers[client].bsStyle, "speed");

	float laggedmovement =
		  (user_timescale ? gA_Timers[client].fTimescale : 1.0)
		* style_laggedmovement;

	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", laggedmovement * gA_Timers[client].fplayer_speedmod);

	if (gB_Eventqueuefix)
	{
		SetEventsTimescale(client, style_laggedmovement);
	}
}

void CallOnStyleChanged(int client, int oldstyle, int newstyle, bool manual, bool noforward=false)
{
	gA_Timers[client].bsStyle = newstyle;

	if (!noforward)
	{
		Call_StartForward(gH_Forwards_OnStyleChanged);
		Call_PushCell(client);
		Call_PushCell(oldstyle);
		Call_PushCell(newstyle);
		Call_PushCell(gA_Timers[client].iTimerTrack);
		Call_PushCell(manual);
		Call_Finish();
	}

	float style_ts = GetStyleSettingFloat(newstyle, "tas_timescale");

	if (style_ts >= 0.0)
	{
		float newts = (style_ts > 0.0) ? style_ts : 1.0; // 🦎🦎🦎
		Shavit_SetClientTimescale(client, newts);
	}

	UpdateLaggedMovement(client, true);

	UpdateStyleSettings(client);

	SetEntityGravity(client, GetStyleSettingFloat(newstyle, "gravity"));
}

void CallOnTimescaleChanged(int client, float oldtimescale, float newtimescale)
{
	gA_Timers[client].fTimescale = newtimescale;
	Call_StartForward(gH_Forwards_OnTimescaleChanged);
	Call_PushCell(client);
	Call_PushCell(oldtimescale);
	Call_PushCell(newtimescale);
	Call_Finish();
}

void ChangeClientStyle(int client, int style, bool manual)
{
	if(!IsValidClient(client))
	{
		return;
	}

	if(!Shavit_HasStyleAccess(client, style))
	{
		if(manual)
		{
			Shavit_PrintToChat(client, "%T", "StyleNoAccess", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		}

		return;
	}

	if(manual)
	{
		Action result = Plugin_Continue;
		Call_StartForward(gH_Forwards_OnStyleCommandPre);
		Call_PushCell(client);
		Call_PushCell(gA_Timers[client].bsStyle);
		Call_PushCell(style);
		Call_PushCell(gA_Timers[client].iTimerTrack);
		Call_Finish(result);

		if (result > Plugin_Continue)
		{
			return;
		}

		if(!Shavit_StopTimer(client, false))
		{
			return;
		}

		char sName[64];
		GetStyleSetting(style, "name", sName, sizeof(sName));

		Shavit_PrintToChat(client, "%T", "StyleSelection", client, gS_ChatStrings.sStyle, sName, gS_ChatStrings.sText);
	}

	if(GetStyleSettingBool(style, "unranked"))
	{
		Shavit_PrintToChat(client, "%T", "UnrankedWarning", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	int aa_old = RoundToZero(GetStyleSettingFloat(gA_Timers[client].bsStyle, "airaccelerate"));
	int aa_new = RoundToZero(GetStyleSettingFloat(style, "airaccelerate"));

	if(aa_old != aa_new)
	{
		Shavit_PrintToChat(client, "%T", "NewAiraccelerate", client, aa_old, gS_ChatStrings.sVariable, aa_new, gS_ChatStrings.sText);
	}

	CallOnStyleChanged(client, gA_Timers[client].bsStyle, style, manual);

	if (gB_Zones && (Shavit_ZoneExists(Zone_Start, gA_Timers[client].iTimerTrack) || gB_KZMap[gA_Timers[client].iTimerTrack]))
	{
		Shavit_RestartTimer(client, gA_Timers[client].iTimerTrack);
	}

	char sStyle[4];
	IntToString(style, sStyle, 4);

	if(gB_StyleCookies)
	{
		SetClientCookie(client, gH_StyleCookie, sStyle);
	}
}

public void Player_Jump(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	DoJump(client);
}

void DoJump(int client)
{
	if (gA_Timers[client].bTimerEnabled && !gA_Timers[client].bClientPaused)
	{
		gA_Timers[client].iJumps++;
		gA_Timers[client].bJumped = true;
	}

	// TF2 doesn't use stamina
	if (gEV_Type != Engine_TF2 && (GetStyleSettingBool(gA_Timers[client].bsStyle, "easybhop")) || (gB_Zones && Shavit_InsideZone(client, Zone_Easybhop, gA_Timers[client].iTimerTrack)))
	{
		SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
	}

	RequestFrame(VelocityChanges, GetClientSerial(client));
}

void VelocityChanges(int data)
{
	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	int style = gA_Timers[client].bsStyle;

#if 0
	if(GetStyleSettingBool(style, "force_timescale"))
	{
		UpdateLaggedMovement(client, true);
	}
#endif

	float fAbsVelocity[3], fAbsOrig[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);
	fAbsOrig = fAbsVelocity;

	float fSpeed = (SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0)));

	if(fSpeed != 0.0)
	{
		float fVelocityMultiplier = GetStyleSettingFloat(style, "velocity");
		float fVelocityBonus = GetStyleSettingFloat(style, "bonus_velocity");
		float fMin = GetStyleSettingFloat(style, "min_velocity");

		if(fVelocityMultiplier != 0.0)
		{
			fAbsVelocity[0] *= fVelocityMultiplier;
			fAbsVelocity[1] *= fVelocityMultiplier;
		}

		if(fVelocityBonus != 0.0)
		{
			float x = fSpeed / (fSpeed + fVelocityBonus);
			fAbsVelocity[0] /= x;
			fAbsVelocity[1] /= x;
		}

		if(fMin != 0.0 && fSpeed < fMin)
		{
			float x = (fSpeed / fMin);
			fAbsVelocity[0] /= x;
			fAbsVelocity[1] /= x;
		}
	}

	float fJumpMultiplier = GetStyleSettingFloat(style, "jump_multiplier");
	float fJumpBonus = GetStyleSettingFloat(style, "jump_bonus");

	if(fJumpMultiplier != 0.0)
	{
		fAbsVelocity[2] *= fJumpMultiplier;
	}

	if(fJumpBonus != 0.0)
	{
		fAbsVelocity[2] += fJumpBonus;
	}

	float fSpeedLimit = GetStyleSettingFloat(gA_Timers[client].bsStyle, "velocity_limit");

	if (fSpeedLimit > 0.0)
	{
		if (gB_Zones && Shavit_InsideZone(client, Zone_CustomSpeedLimit, -1))
		{
			fSpeedLimit = gF_ZoneSpeedLimit[client];
		}

		float fSpeed_New = (SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0)));

		if (fSpeedLimit != 0.0 && fSpeed_New > 0.0)
		{
			float fScale = fSpeedLimit / fSpeed_New;

			if (fScale < 1.0)
			{
				fAbsVelocity[0] *= fScale;
				fAbsVelocity[1] *= fScale;
			}
		}
	}

	if (fAbsOrig[0] == fAbsVelocity[0] && fAbsOrig[1] == fAbsVelocity[1] && fAbsOrig[2] == fAbsVelocity[2])
		return;

	if(!gCV_VelocityTeleport.BoolValue)
	{
		SetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);
	}
	else
	{
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fAbsVelocity);
	}
}

public void Player_Death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	ResumeTimer(client);
	StopTimer(client);
}

public int Native_GetDatabase(Handle handler, int numParams)
{
	if (numParams > 0)
		SetNativeCellRef(1, gI_Driver);
	return gH_SQL ? view_as<int>(CloneHandle(gH_SQL, handler)) : 0;
}

public int Native_GetClientTime(Handle handler, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].fCurrentTime);
}

public int Native_GetClientTrack(Handle handler, int numParams)
{
	return gA_Timers[GetNativeCell(1)].iTimerTrack;
}

public int Native_GetClientJumps(Handle handler, int numParams)
{
	return gA_Timers[GetNativeCell(1)].iJumps;
}

public int Native_GetBhopStyle(Handle handler, int numParams)
{
	return gA_Timers[GetNativeCell(1)].bsStyle;
}

public int Native_GetTimerStatus(Handle handler, int numParams)
{
	return view_as<int>(GetTimerStatus(GetNativeCell(1)));
}

public int Native_IsKZMap(Handle handler, int numParams)
{
	if (numParams < 1)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Missing track parameter.");
	}

	return gB_KZMap[GetNativeCell(1)];
}

public int Native_StartTimer(Handle handler, int numParams)
{
	StartTimer(GetNativeCell(1), GetNativeCell(2), numParams >= 3 ? GetNativeCell(3) : false);
	return 0;
}

public int Native_StopTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	bool bBypass = (numParams < 2 || view_as<bool>(GetNativeCell(2)));

	if(!bBypass)
	{
		bool bResult = true;
		Call_StartForward(gH_Forwards_StopPre);
		Call_PushCell(client);
		Call_PushCell(gA_Timers[client].iTimerTrack);
		Call_Finish(bResult);

		if(!bResult)
		{
			return false;
		}
	}

	StopTimer(client);

	Call_StartForward(gH_Forwards_Stop);
	Call_PushCell(client);
	Call_PushCell(gA_Timers[client].iTimerTrack);
	Call_Finish();

	return true;
}

public int Native_CanPause(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int iFlags = 0;

	if(!gCV_Pause.BoolValue)
	{
		iFlags |= CPR_ByConVar;
	}

	if (!gA_Timers[client].bTimerEnabled)
	{
		iFlags |= CPR_NoTimer;
	}

	if (gB_Zones)
	{
		if (Shavit_InsideZone(client, Zone_Start, gA_Timers[client].iTimerTrack))
		{
			iFlags |= CPR_InStartZone;
		}

		if (Shavit_InsideZone(client, Zone_End, gA_Timers[client].iTimerTrack))
		{
			iFlags |= CPR_InEndZone;
		}
	}

	if(GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") == -1 && GetEntityMoveType(client) != MOVETYPE_LADDER)
	{
		iFlags |= CPR_NotOnGround;
	}

	float vel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
	if (vel[0] != 0.0 || vel[1] != 0.0 || vel[2] != 0.0)
	{
		iFlags |= CPR_Moving;
	}


	float CS_PLAYER_DUCK_SPEED_IDEAL = 8.0;
	bool bDucked, bDucking;
	float fDucktime, fDuckSpeed = CS_PLAYER_DUCK_SPEED_IDEAL;

	if(gEV_Type != Engine_TF2)
	{
		bDucked = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucked"));
		bDucking = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucking"));

		if(gEV_Type == Engine_CSS)
		{
			fDucktime = GetEntPropFloat(client, Prop_Send, "m_flDucktime");
		}
		else if(gEV_Type == Engine_CSGO)
		{
			fDucktime = GetEntPropFloat(client, Prop_Send, "m_flDuckAmount");
			fDuckSpeed = GetEntPropFloat(client, Prop_Send, "m_flDuckSpeed");
		}
	}

	if (bDucked || bDucking || fDucktime > 0.0 || fDuckSpeed < CS_PLAYER_DUCK_SPEED_IDEAL || GetClientButtons(client) & IN_DUCK)
	{
		iFlags |= CPR_Duck;
	}

	return iFlags;
}

public int Native_ChangeClientStyle(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int style = GetNativeCell(2);
	bool force = view_as<bool>(GetNativeCell(3));
	bool manual = view_as<bool>(GetNativeCell(4));
	bool noforward = view_as<bool>(GetNativeCell(5));

	if(force || Shavit_HasStyleAccess(client, style))
	{
		CallOnStyleChanged(client, gA_Timers[client].bsStyle, style, manual, noforward);

		return true;
	}

	return false;
}

void CalculateRunTime(timer_snapshot_t s, bool finished)
{
	if (finished)
	{
		// Round up fractional ticks... mostly
		if (s.iFractionalTicks > 100)
			s.iFractionalTicks = 10000;
	}

	float ticks = float(s.iFullTicks) + (s.iFractionalTicks / 10000.0);

	if (gCV_UseOffsets.BoolValue)
	{
		ticks += s.fZoneOffset[Zone_Start];

		if (finished)
		{
			ticks -= (1.0 - s.fZoneOffset[Zone_End]);
		}
	}

	s.fCurrentTime = ticks * GetTickInterval();
}

public int Native_FinishMap(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int timestamp = GetTime();

	if (!gA_Timers[client].iFullTicks)
	{
		return 0;
	}

	if(gCV_UseOffsets.BoolValue)
	{
		CalculateTickIntervalOffset(client, Zone_End);

		if(gCV_DebugOffsets.BoolValue)
		{
			char sOffsetMessage[100];
			char sOffsetDistance[8];
			FormatEx(sOffsetDistance, 8, "%.1f", gA_Timers[client].fDistanceOffset[Zone_End]);
			FormatEx(sOffsetMessage, sizeof(sOffsetMessage), "[END] %T %d", "DebugOffsets", client, gA_Timers[client].fZoneOffset[Zone_End], sOffsetDistance, gA_Timers[client].iZoneIncrement);
			PrintToConsole(client, "%s", sOffsetMessage);
			Shavit_StopChatSound();
			Shavit_PrintToChat(client, "%s", sOffsetMessage);
		}
	}

	CalculateRunTime(gA_Timers[client], true);

	float minimum_time = GetStyleSettingFloat(gA_Timers[client].bsStyle, gA_Timers[client].iTimerTrack == Track_Main ? "minimum_time" : "minimum_time_bonus");
	float current_time = gA_Timers[client].fCurrentTime;

	if (current_time <= 0.11 || current_time < minimum_time)
	{
		Shavit_PrintToChat(client, "%T", (current_time <= 0.11) ? "TimeUnderMinimumTime2" : "TimeUnderMinimumTime", client, (current_time <= 0.11) ? 0.11 : minimum_time, current_time,
		gA_Timers[client].iTimerTrack == Track_Main ? "minimum_time" : "minimum_time_bonus");
		Shavit_StopTimer(client);
		return 0;
	}

	timer_snapshot_t snapshot;
	BuildSnapshot(client, snapshot);

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_FinishPre);
	Call_PushCell(client);
	Call_PushArrayEx(snapshot, sizeof(timer_snapshot_t), SM_PARAM_COPYBACK);
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return 0;
	}

#if DEBUG
	PrintToServer("0x%X %f -- startoffset=%f endoffset=%f fullticks=%d fracticks=%d", snapshot.fCurrentTime, snapshot.fCurrentTime, snapshot.fZoneOffset[Zone_Start], snapshot.fZoneOffset[Zone_End], snapshot.iFullTicks, snapshot.iFractionalTicks);
#endif

	Call_StartForward(gH_Forwards_Finish);
	Call_PushCell(client);

	Call_PushCell(snapshot.bsStyle);
	Call_PushCell(snapshot.fCurrentTime);
	Call_PushCell(snapshot.iJumps);
	Call_PushCell(snapshot.iStrafes);
	Call_PushCell(CalcSync(snapshot));
	Call_PushCell(snapshot.iTimerTrack);
	Call_PushCell(Shavit_GetClientPB(client, snapshot.bsStyle, snapshot.iTimerTrack)); // oldtime
	Call_PushCell(CalcPerfs(snapshot));
	Call_PushCell(snapshot.fAvgVelocity);
	Call_PushCell(snapshot.fMaxVelocity);

	Call_PushCell(timestamp);
	Call_Finish();

	StopTimer(client);
	return 1;
}

public int Native_PauseTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	GetClientAbsOrigin(client, gF_PauseOrigin[client]);
	GetClientEyeAngles(client, gF_PauseAngles[client]);
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", gF_PauseVelocity[client]);

	PauseTimer(client);
	return 1;
}

public any Native_GetZoneOffset(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int zonetype = GetNativeCell(2);

	if(zonetype > 1 || zonetype < 0)
	{
		return ThrowNativeError(32, "ZoneType is out of bounds");
	}

	return gA_Timers[client].fZoneOffset[zonetype];
}

public any Native_GetDistanceOffset(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int zonetype = GetNativeCell(2);

	if(zonetype > 1 || zonetype < 0)
	{
		return ThrowNativeError(32, "ZoneType is out of bounds");
	}

	return gA_Timers[client].fDistanceOffset[zonetype];
}

public int Native_ResumeTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	ResumeTimer(client);

	if(numParams >= 2 && view_as<bool>(GetNativeCell(2))) // teleport?
	{
		TeleportEntity(client, gF_PauseOrigin[client], gF_PauseAngles[client], gF_PauseVelocity[client]);
	}

	return 1;
}

public int Native_StopChatSound(Handle handler, int numParams)
{
	gB_StopChatSound = true;
	return 1;
}

public int Native_PrintToChatAll(Handle plugin, int numParams)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			SetGlobalTransTarget(i);

			bool previousStopChatSound = gB_StopChatSound;
			SemiNative_PrintToChat(i, 1);
			gB_StopChatSound = previousStopChatSound;
		}
	}

	gB_StopChatSound = false;
	return 1;
}

public int Native_PrintToChat(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	return SemiNative_PrintToChat(client, 2);
}

public int SemiNative_PrintToChat(int client, int formatParam)
{
	bool stopChatSound = gB_StopChatSound;
	gB_StopChatSound = false;

	int iWritten;
	char sBuffer[256];
	char sInput[300];
	FormatNativeString(0, formatParam, formatParam+1, sizeof(sInput), iWritten, sInput);

	char sTime[50];

	if (gCV_TimeInMessages.BoolValue)
	{
		FormatTime(sTime, sizeof(sTime), gB_Protobuf ? "%H:%M:%S " : "\x01%H:%M:%S ");
	}

	// space before message needed show colors in cs:go
	// strlen(sBuffer)>252 is when the CSS server stops sending the messages
	// css user message size limit is 255. byte for client, byte for chatsound, 252 chars + 1 null terminator = 255
	FormatEx(sBuffer, (gB_Protobuf ? sizeof(sBuffer) : 253), "%s%s%s%s%s%s", (gB_Protobuf ? " ":""), sTime, gS_ChatStrings.sPrefix, (gS_ChatStrings.sPrefix[0] != 0 ? " " : ""), gS_ChatStrings.sText, sInput);

	if(client == 0)
	{
		PrintToServer("%s", sBuffer);
		return false;
	}

	if(!IsClientInGame(client))
	{
		return false;
	}

	Handle hSayText2 = StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);

	if(gB_Protobuf)
	{
		Protobuf pbmsg = UserMessageToProtobuf(hSayText2);
		pbmsg.SetInt("ent_idx", client);
		pbmsg.SetBool("chat", !(stopChatSound || gCV_NoChatSound.BoolValue));
		pbmsg.SetString("msg_name", sBuffer);

		// needed to not crash
		for(int i = 1; i <= 4; i++)
		{
			pbmsg.AddString("params", "");
		}
	}
	else
	{
		BfWrite bfmsg = UserMessageToBfWrite(hSayText2);
		bfmsg.WriteByte(client);
		bfmsg.WriteByte(!(stopChatSound || gCV_NoChatSound.BoolValue));
		bfmsg.WriteString(sBuffer);
	}

	EndMessage();
	return true;
}

public int Native_GotoEnd(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);

	Shavit_StopTimer(client, true);

	Call_StartForward(gH_Forwards_OnEnd);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_Finish();

	return 1;
}

public int Native_RestartTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);
	bool force = (numParams < 3) || GetNativeCell(3);

	if (!force)
	{
		Action result = Plugin_Continue;
		Call_StartForward(gH_Forwards_OnRestartPre);
		Call_PushCell(client);
		Call_PushCell(track);
		Call_Finish(result);

		if (result > Plugin_Continue)
		{
			return 0;
		}
	}

	if (gA_Timers[client].bTimerEnabled && !Shavit_StopTimer(client, force))
	{
		return 0;
	}

	if (gA_Timers[client].iTimerTrack != track)
	{
		CallOnTrackChanged(client, gA_Timers[client].iTimerTrack, track);
	}

	Call_StartForward(gH_Forwards_OnRestart);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_Finish();

	return 1;
}

float CalcPerfs(timer_snapshot_t s)
{
	return (s.iMeasuredJumps == 0) ? 0.0 : (s.iPerfectJumps / float(s.iMeasuredJumps) * 100.0);
}

public int Native_GetPerfectJumps(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	return view_as<int>(CalcPerfs(gA_Timers[client]));
}

public int Native_GetStrafeCount(Handle handler, int numParams)
{
	return gA_Timers[GetNativeCell(1)].iStrafes;
}

float CalcSync(timer_snapshot_t s)
{
	return GetStyleSettingBool(s.bsStyle, "sync") ? ((s.iGoodGains == 0) ? 0.0 : (s.iGoodGains / float(s.iTotalMeasures) * 100.0)):-1.0;
}

public int Native_GetSync(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	return view_as<int>(CalcSync(gA_Timers[client]));
}

public int Native_GetChatStrings(Handle handler, int numParams)
{
	int type = GetNativeCell(1);
	int size = GetNativeCell(3);

	switch(type)
	{
		case sMessagePrefix: return SetNativeString(2, gS_ChatStrings.sPrefix, size);
		case sMessageText: return SetNativeString(2, gS_ChatStrings.sText, size);
		case sMessageWarning: return SetNativeString(2, gS_ChatStrings.sWarning, size);
		case sMessageVariable: return SetNativeString(2, gS_ChatStrings.sVariable, size);
		case sMessageVariable2: return SetNativeString(2, gS_ChatStrings.sVariable2, size);
		case sMessageStyle: return SetNativeString(2, gS_ChatStrings.sStyle, size);
	}

	return -1;
}

public int Native_GetChatStringsStruct(Handle plugin, int numParams)
{
	if (GetNativeCell(2) != sizeof(chatstrings_t))
	{
		return ThrowNativeError(200, "chatstrings_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins", GetNativeCell(2), sizeof(chatstrings_t));
	}

	return SetNativeArray(1, gS_ChatStrings, sizeof(gS_ChatStrings));
}

public int Native_SetPracticeMode(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	bool practice = view_as<bool>(GetNativeCell(2));
	bool alert = view_as<bool>(GetNativeCell(3));

	if(alert && practice && !gA_Timers[client].bPracticeMode && (!gB_HUD || (Shavit_GetHUDSettings(client) & HUD_NOPRACALERT) == 0) && !Shavit_InsideZone(client, Zone_Start, -1))
	{
		Shavit_PrintToChat(client, "%T", "PracticeModeAlert", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	gA_Timers[client].bPracticeMode = practice;

	return 1;
}

public int Native_IsPaused(Handle handler, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].bClientPaused);
}

public int Native_IsPracticeMode(Handle handler, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].bPracticeMode);
}

public int Native_SaveSnapshot(Handle handler, int numParams)
{
	if(GetNativeCell(3) != sizeof(timer_snapshot_t))
	{
		return ThrowNativeError(200, "timer_snapshot_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(3), sizeof(timer_snapshot_t));
	}

	int client = GetNativeCell(1);

	timer_snapshot_t snapshot;
	BuildSnapshot(client, snapshot);
	return SetNativeArray(2, snapshot, sizeof(timer_snapshot_t));
}

public int Native_LoadSnapshot(Handle handler, int numParams)
{
	if(GetNativeCell(3) != sizeof(timer_snapshot_t))
	{
		return ThrowNativeError(200, "timer_snapshot_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(3), sizeof(timer_snapshot_t));
	}

	int client = GetNativeCell(1);

	timer_snapshot_t snapshot;
	GetNativeArray(2, snapshot, sizeof(timer_snapshot_t));
	snapshot.fTimescale = (snapshot.fTimescale > 0.0) ? snapshot.fTimescale : 1.0;

	bool force = GetNativeCell(4);

	if (!Shavit_HasStyleAccess(client, snapshot.bsStyle) && !force)
	{
		return 0;
	}

	if (gA_Timers[client].iTimerTrack != snapshot.iTimerTrack)
	{
		CallOnTrackChanged(client, gA_Timers[client].iTimerTrack, snapshot.iTimerTrack);
	}

	if (gA_Timers[client].bsStyle != snapshot.bsStyle)
	{
		CallOnStyleChanged(client, gA_Timers[client].bsStyle, snapshot.bsStyle, false);
	}

	float oldts = gA_Timers[client].fTimescale;

	gA_Timers[client] = snapshot;
	gA_Timers[client].bClientPaused = snapshot.bClientPaused && snapshot.bTimerEnabled;

	if (GetStyleSettingFloat(snapshot.bsStyle, "tas_timescale") < 0.0)
	{
		Shavit_SetClientTimescale(client, oldts);
	}

	return 1;
}

public int Native_LogMessage(Handle plugin, int numParams)
{
	char sPlugin[32];

	if(!GetPluginInfo(plugin, PlInfo_Name, sPlugin, 32))
	{
		GetPluginFilename(plugin, sPlugin, 32);
	}

	static int iWritten = 0;

	char sBuffer[300];
	FormatNativeString(0, 1, 2, 300, iWritten, sBuffer);

	LogToFileEx(gS_LogPath, "[%s] %s", sPlugin, sBuffer);
	return 1;
}

public int Native_MarkKZMap(Handle handler, int numParams)
{
	if (numParams < 1)
	{
		return ThrowNativeError(SP_ERROR_NATIVE, "Missing track parameter.");
	}

	gB_KZMap[GetNativeCell(1)] = true;
	return 0;
}

public int Native_GetClientTimescale(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	return view_as<int>(gA_Timers[client].fTimescale);
}

public int Native_SetClientTimescale(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	float timescale = GetNativeCell(2);

	timescale = float(RoundFloat((timescale * 10000.0)))/10000.0;

	if (timescale != gA_Timers[client].fTimescale && timescale > 0.0)
	{
		CallOnTimescaleChanged(client, gA_Timers[client].fTimescale, timescale);
		UpdateLaggedMovement(client, true);
	}

	return 1;
}

public any Native_GetAvgVelocity(Handle plugin, int numParams)
{
	return gA_Timers[GetNativeCell(1)].fAvgVelocity;
}

public any Native_GetMaxVelocity(Handle plugin, int numParams)
{
	return gA_Timers[GetNativeCell(1)].fMaxVelocity;
}

public any Native_SetAvgVelocity(Handle plugin, int numParams)
{
	gA_Timers[GetNativeCell(1)].fAvgVelocity = GetNativeCell(2);
	return 1;
}

public any Native_SetMaxVelocity(Handle plugin, int numParams)
{
	gA_Timers[GetNativeCell(1)].fMaxVelocity = GetNativeCell(2);
	return 1;
}

public any Native_ShouldProcessFrame(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return gA_Timers[client].fTimescale == 1.0
	    || gA_Timers[client].fNextFrameTime <= 0.0;
}

public Action Shavit_OnStartPre(int client, int track)
{
	if (GetTimerStatus(client) == Timer_Paused && gCV_PauseMovement.IntValue > 0)
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

TimerStatus GetTimerStatus(int client)
{
	if (!gA_Timers[client].bTimerEnabled)
	{
		return Timer_Stopped;
	}
	else if (gA_Timers[client].bClientPaused)
	{
		return Timer_Paused;
	}

	return Timer_Running;
}

float StyleMaxPrestrafe(int style)
{
	float runspeed = GetStyleSettingFloat(style, "runspeed");
	return MaxPrestrafe(runspeed, sv_accelerate.FloatValue, sv_friction.FloatValue, GetTickInterval());
}

bool CanStartTimer(int client, int track, bool skipGroundCheck)
{
	if(!IsValidClient(client, true) || GetClientTeam(client) < 2 || IsFakeClient(client) || !gB_CookiesRetrieved[client])
	{
		return false;
	}

	int style = gA_Timers[client].bsStyle;

	int prespeed = GetStyleSettingInt(style, "prespeed");
	if (prespeed == 1)
		return true;

	float fSpeed[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);

	int nozaxisspeed = GetStyleSettingInt(style, "nozaxisspeed");
	if (nozaxisspeed < 0) nozaxisspeed = gCV_NoZAxisSpeed.IntValue;

	if (nozaxisspeed && fSpeed[2] != 0.0)
		return false;

	if (prespeed == 2)
		return true;

	bool skipGroundTimer = false;
	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_StartPre);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_PushCellRef(skipGroundTimer);
	Call_Finish(result);

	if (result != Plugin_Continue)
		return false;

	// re-grab velocity in case shavit-misc capped it
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);
	float curVel = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));

	// This helps with zones that are floating in the air (commonly for bonuses).
	// Since you teleport into the air with 0-velocity...
	if (curVel <= 50.0)
		return true;

	float cfgMax = GetStyleSettingFloat(style, "maxprestrafe");
	float zoneMax = gF_ZoneStartSpeedLimit[client];
	float prestrafe;

	if (zoneMax > 0.0)
	{
		prestrafe = zoneMax;
	}
	else if (cfgMax > 0.0)
	{
		prestrafe = cfgMax;
	}
	else
	{
		prestrafe = StyleMaxPrestrafe(style);
	}

	if (curVel > prestrafe)
		return false;

	if (skipGroundCheck || GetStyleSettingBool(style, "startinair"))
		return true;

#if 0
	MoveType mtMoveType = GetEntityMoveType(client);
	bool bInWater = (GetEntProp(client, Prop_Send, "m_nWaterLevel") >= 2);
	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	// gA_Timers[client].bOnGround isn't updated/correct when zones->touchpost->starttimer happens... frustrating...
	bool bOnGround = (!bInWater && mtMoveType == MOVETYPE_WALK && iGroundEntity != -1);

	if (!bOnGround) return false;
#endif

	if (skipGroundTimer) return true;

	if (gI_FirstTouchedGroundForStartTimer[client] < 0)
	{
		// was on ground with zero...ish... velocity...
		return true;
	}
	else if (gI_FirstTouchedGroundForStartTimer[client] > 0)
	{
		int halfSecOfTicks = RoundFloat(0.5 / GetTickInterval());
		int onGroundTicks = gI_LastTickcount[client] - gI_FirstTouchedGroundForStartTimer[client];

		return onGroundTicks >= halfSecOfTicks;
	}

	return false;
}

void StartTimer(int client, int track, bool skipGroundCheck)
{
	if (CanStartTimer(client, track, skipGroundCheck))
	{
		if (true) // fucking shit
		{
			if (gA_Timers[client].bClientPaused)
			{
				//SetEntityMoveType(client, MOVETYPE_WALK);
			}

			gA_Timers[client].iZoneIncrement = 0;
			gA_Timers[client].iFullTicks = 0;
			gA_Timers[client].iFractionalTicks = 0;
			gA_Timers[client].bClientPaused = false;
			gA_Timers[client].iStrafes = 0;
			gA_Timers[client].iJumps = 0;
			gA_Timers[client].iTotalMeasures = 0;
			gA_Timers[client].iGoodGains = 0;

			if (gA_Timers[client].iTimerTrack != track)
			{
				CallOnTrackChanged(client, gA_Timers[client].iTimerTrack, track);
			}

			gA_Timers[client].iTimerTrack = track;
			gA_Timers[client].bTimerEnabled = true;
			gA_Timers[client].iKeyCombo = -1;
			gA_Timers[client].fCurrentTime = 0.0;
			gA_Timers[client].bPracticeMode = false;
			gA_Timers[client].iMeasuredJumps = 0;
			gA_Timers[client].iPerfectJumps = 0;
			gA_Timers[client].bCanUseAllKeys = false;
			gA_Timers[client].fZoneOffset[Zone_Start] = 0.0;
			gA_Timers[client].fZoneOffset[Zone_End] = 0.0;
			gA_Timers[client].fDistanceOffset[Zone_Start] = 0.0;
			gA_Timers[client].fDistanceOffset[Zone_End] = 0.0;

			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);
			float curVel = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));

			gA_Timers[client].fAvgVelocity = curVel;
			gA_Timers[client].fMaxVelocity = curVel;

			// TODO: Look into when this should be reset (since resetting it here disables timescale while in startzone).
			//gA_Timers[client].fNextFrameTime = 0.0;

			gA_Timers[client].fplayer_speedmod = 1.0;
			UpdateLaggedMovement(client, true);

			SetEntityGravity(client, GetStyleSettingFloat(gA_Timers[client].bsStyle, "gravity"));

			Call_StartForward(gH_Forwards_Start);
			Call_PushCell(client);
			Call_PushCell(track);
			Call_Finish();
		}
#if 0
		else if(result == Plugin_Handled || result == Plugin_Stop)
		{
			gA_Timers[client].bTimerEnabled = false;
		}
#endif
	}
}

void StopTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	if (gA_Timers[client].bClientPaused)
	{
		//SetEntityMoveType(client, MOVETYPE_WALK);
	}

	gA_Timers[client].bTimerEnabled = false;
	gA_Timers[client].iJumps = 0;
	gA_Timers[client].fCurrentTime = 0.0;
	gA_Timers[client].iFullTicks = 0;
	gA_Timers[client].iFractionalTicks = 0;
	gA_Timers[client].bClientPaused = false;
	gA_Timers[client].iStrafes = 0;
	gA_Timers[client].iTotalMeasures = 0;
	gA_Timers[client].iGoodGains = 0;
}

void PauseTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	Call_StartForward(gH_Forwards_OnPause);
	Call_PushCell(client);
	Call_PushCell(gA_Timers[client].iTimerTrack);
	Call_Finish();

	gA_Timers[client].bClientPaused = true;
}

void ResumeTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	Call_StartForward(gH_Forwards_OnResume);
	Call_PushCell(client);
	Call_PushCell(gA_Timers[client].iTimerTrack);
	Call_Finish();

	gA_Timers[client].bClientPaused = false;
	// setting is handled in usercmd
	//SetEntityMoveType(client, MOVETYPE_WALK);
}

public void OnClientDisconnect(int client)
{
	RequestFrame(StopTimer, client);
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client) || !IsClientInGame(client))
	{
		return;
	}

	char sCookie[4];

	if(gH_AutoBhopCookie != null)
	{
		GetClientCookie(client, gH_AutoBhopCookie, sCookie, 4);
	}

	gB_Auto[client] = (strlen(sCookie) > 0)? view_as<bool>(StringToInt(sCookie)):true;

	int style = gI_DefaultStyle;

	if(gB_StyleCookies && gH_StyleCookie != null)
	{
		GetClientCookie(client, gH_StyleCookie, sCookie, 4);
		int newstyle = StringToInt(sCookie);

		if (0 <= newstyle < Shavit_GetStyleCount())
		{
			style = newstyle;
		}
	}

	if(Shavit_HasStyleAccess(client, style))
	{
		CallOnStyleChanged(client, gA_Timers[client].bsStyle, style, false);
	}

	gB_CookiesRetrieved[client] = true;
}

public void OnClientPutInServer(int client)
{
	StopTimer(client);
	Bhopstats_OnClientPutInServer(client);

	if(!IsClientConnected(client) || IsFakeClient(client))
	{
		return;
	}

	gH_TeleportDhook.HookEntity(Hook_Post, client, DHooks_OnTeleport);

	gB_Auto[client] = true;
	gA_Timers[client].fStrafeWarning = 0.0;
	gA_Timers[client].bPracticeMode = false;
	gA_Timers[client].iKeyCombo = -1;
	gA_Timers[client].iTimerTrack = 0;
	gA_Timers[client].bsStyle = 0;
	gA_Timers[client].fTimescale = 1.0;
	gA_Timers[client].iFullTicks = 0;
	gA_Timers[client].iFractionalTicks = 0;
	gA_Timers[client].iZoneIncrement = 0;
	gA_Timers[client].fNextFrameTime = 0.0;
	gA_Timers[client].fplayer_speedmod = 1.0;
	gS_DeleteMap[client][0] = 0;
	gI_FirstTouchedGroundForStartTimer[client] = 0;
	gI_LastTickcount[client] = 0;
	gI_HijackFrames[client] = 0;
	gI_LastPrintedSteamID[client] = 0;

	gB_CookiesRetrieved[client] = false;

	if(AreClientCookiesCached(client))
	{
		OnClientCookiesCached(client);
	}

	// not adding style permission check here for obvious reasons
	else
	{
		CallOnStyleChanged(client, 0, gI_DefaultStyle, false);
	}

	SDKHook(client, SDKHook_PreThinkPost, PreThinkPost);
	SDKHook(client, SDKHook_PostThinkPost, PostThinkPost);
}

public void OnClientAuthorized(int client, const char[] auth)
{
	int iSteamID = GetSteamAccountID(client);

	if(iSteamID == 0)
	{
		return;
	}

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, sizeof(sName));
	ReplaceString(sName, MAX_NAME_LENGTH, "#", "?"); // to avoid this: https://user-images.githubusercontent.com/3672466/28637962-0d324952-724c-11e7-8b27-15ff021f0a59.png

	int iLength = ((strlen(sName) * 2) + 1);
	char[] sEscapedName = new char[iLength];
	gH_SQL.Escape(sName, sEscapedName, iLength);

	int iIPAddress = 0;

	if (gCV_SaveIps.BoolValue)
	{
		char sIPAddress[64];
		GetClientIP(client, sIPAddress, 64);
		iIPAddress = IPStringToAddress(sIPAddress);
	}

	int iTime = GetTime();

	char sQuery[512];

	if (gI_Driver == Driver_mysql)
	{
		FormatEx(sQuery, 512,
			"INSERT INTO %susers (auth, name, ip, lastlogin, firstlogin) VALUES (%d, '%s', %d, %d, %d) ON DUPLICATE KEY UPDATE name = '%s', ip = %d, lastlogin = %d;",
			gS_MySQLPrefix, iSteamID, sEscapedName, iIPAddress, iTime, iTime, sEscapedName, iIPAddress, iTime);
	}
	else // postgresql & sqlite
	{
		FormatEx(sQuery, 512,
			"INSERT INTO %susers (auth, name, ip, lastlogin, firstlogin) VALUES (%d, '%s', %d, %d, %d) ON CONFLICT(auth) DO UPDATE SET name = '%s', ip = %d, lastlogin = %d;",
			gS_MySQLPrefix, iSteamID, sEscapedName, iIPAddress, iTime, iTime, sEscapedName, iIPAddress, iTime);
	}

	QueryLog(gH_SQL, SQL_InsertUser_Callback, sQuery, GetClientSerial(client));
}

public void SQL_InsertUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		int client = GetClientFromSerial(data);

		if(client == 0)
		{
			LogError("Timer error! Failed to insert a disconnected player's data to the table. Reason: %s", error);
		}
		else
		{
			LogError("Timer error! Failed to insert \"%N\"'s data to the table. Reason: %s", client, error);
		}

		return;
	}
}

// alternatively, SnapEyeAngles &| SetLocalAngles should work...
// but we have easy gamedata for Teleport so whatever...
public MRESReturn DHooks_OnTeleport(int pThis, DHookParam hParams)
{
	if (gCV_HijackTeleportAngles.BoolValue && !hParams.IsNull(2) && IsPlayerAlive(pThis))
	{
		float latency = GetClientLatency(pThis, NetFlow_Both);

		if (latency > 0.0)
		{
			gI_HijackFrames[pThis] = RoundToCeil(latency / GetTickInterval()) + 1;

			float angles[3];
			hParams.GetVector(2, angles);
			gF_HijackedAngles[pThis][0] = angles[0];
			gF_HijackedAngles[pThis][1] = angles[1];
		}
	}

	return MRES_Ignored;
}

void ReplaceColors(char[] string, int size)
{
	for(int x = 0; x < sizeof(gS_GlobalColorNames); x++)
	{
		ReplaceString(string, size, gS_GlobalColorNames[x], gS_GlobalColors[x]);
	}

	for(int x = 0; x < sizeof(gS_CSGOColorNames); x++)
	{
		ReplaceString(string, size, gS_CSGOColorNames[x], gS_CSGOColors[x]);
	}

	ReplaceString(string, size, "{RGB}", "\x07");
	ReplaceString(string, size, "{RGBA}", "\x08");
}

bool LoadMessages()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-messages.cfg");

	KeyValues kv = new KeyValues("shavit-messages");

	if(!kv.ImportFromFile(sPath))
	{
		delete kv;

		return false;
	}

	kv.JumpToKey((IsSource2013(gEV_Type))? "CS:S":"CS:GO");

	kv.GetString("prefix", gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix), "\x075e70d0[Timer]");
	kv.GetString("text", gS_ChatStrings.sText, sizeof(chatstrings_t::sText), "\x07ffffff");
	kv.GetString("warning", gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning), "\x07af2a22");
	kv.GetString("variable", gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable), "\x077fd772");
	kv.GetString("variable2", gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2), "\x07276f5c");
	kv.GetString("style", gS_ChatStrings.sStyle, sizeof(chatstrings_t::sStyle), "\x07db88c2");

	delete kv;

	ReplaceColors(gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix));
	ReplaceColors(gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	ReplaceColors(gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning));
	ReplaceColors(gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
	ReplaceColors(gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2));
	ReplaceColors(gS_ChatStrings.sStyle, sizeof(chatstrings_t::sStyle));

	Call_StartForward(gH_Forwards_OnChatConfigLoaded);
	Call_Finish();

	return true;
}

void SQL_DBConnect()
{
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = GetTimerDatabaseHandle();
	gI_Driver = GetDatabaseDriver(gH_SQL);

	SQL_CreateTables(gH_SQL, gS_MySQLPrefix, gI_Driver);
}

public void Shavit_OnEnterZone(int client, int type, int track, int id, int entity, int data)
{
	if (type == Zone_Start && track == gA_Timers[client].iTimerTrack)
	{
		gF_ZoneStartSpeedLimit[client] = float(data);
	}
	else if (type == Zone_Airaccelerate && track == gA_Timers[client].iTimerTrack)
	{
		gF_ZoneAiraccelerate[client] = float(data);
	}
	else if (type == Zone_CustomSpeedLimit && track == gA_Timers[client].iTimerTrack)
	{
		gF_ZoneSpeedLimit[client] = float(data);
	}
	else if (type != Zone_Autobhop)
	{
		return;
	}

	UpdateStyleSettings(client);
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity)
{
	// TODO: Do we need to do something about clients switching tracks and not having style-related cvars set or anything like that?
	//       Probably so very niche that it doesn't matter.
	if (track != gA_Timers[client].iTimerTrack)
		return;
	if (type != Zone_Airaccelerate && type != Zone_CustomSpeedLimit && type != Zone_Autobhop && type != Zone_Start)
		return;

	UpdateStyleSettings(client);
}

public void PreThinkPost(int client)
{
	if(IsPlayerAlive(client))
	{
		if (!gB_Zones || !Shavit_InsideZone(client, Zone_Airaccelerate, gA_Timers[client].iTimerTrack))
		{
			sv_airaccelerate.FloatValue = GetStyleSettingFloat(gA_Timers[client].bsStyle, "airaccelerate");
		}
		else
		{
			sv_airaccelerate.FloatValue = gF_ZoneAiraccelerate[client];
		}

		if(sv_enablebunnyhopping != null)
		{
			if (gB_Zones && Shavit_InsideZone(client, Zone_CustomSpeedLimit, gA_Timers[client].iTimerTrack))
			{
				sv_enablebunnyhopping.BoolValue = true;
			}
			else
			{
				sv_enablebunnyhopping.BoolValue = GetStyleSettingBool(gA_Timers[client].bsStyle, "bunnyhopping");
			}
		}

		MoveType mtMoveType = GetEntityMoveType(client);
		MoveType mtLast = gA_Timers[client].iLastMoveType;
		gA_Timers[client].iLastMoveType = mtMoveType;

		if (mtMoveType == MOVETYPE_WALK || mtMoveType == MOVETYPE_ISOMETRIC)
		{
			float g = 0.0;
			float styleg = GetStyleSettingFloat(gA_Timers[client].bsStyle, "gravity");

			if (gB_Zones)
			{
				if (Shavit_InsideZone(client, Zone_NoTimerGravity, gA_Timers[client].iTimerTrack))
				{
					return;
				}

				int id;

				if (Shavit_InsideZoneGetID(client, Zone_Gravity, gA_Timers[client].iTimerTrack, id))
				{
					g = view_as<float>(Shavit_GetZoneData(id));
				}
			}

			float clientg = GetEntityGravity(client);

			if (g == 0.0 && styleg != 1.0 && ((mtLast == MOVETYPE_LADDER || clientg == 1.0 || clientg == 0.0)))
			{
				g = styleg;
			}

			if (g != 0.0)
			{
				SetEntityGravity(client, g);
			}
		}
	}
}

public void PostThinkPost(int client)
{
	gF_Origin[client][1] = gF_Origin[client][0];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", gF_Origin[client][0]);

	if(gA_Timers[client].iZoneIncrement == 1 && gCV_UseOffsets.BoolValue)
	{
		float fVel[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", fVel);

		int nozaxisspeed = GetStyleSettingInt(gA_Timers[client].bsStyle, "nozaxisspeed");

		if (nozaxisspeed < 0)
		{
			nozaxisspeed = gCV_NoZAxisSpeed.BoolValue;
		}

		if (!nozaxisspeed)
		{
			if(fVel[2] == 0.0)
			{
				CalculateTickIntervalOffset(client, Zone_Start);
			}
		}
		else
		{
			CalculateTickIntervalOffset(client, Zone_Start);
		}

		if(gCV_DebugOffsets.BoolValue)
		{
			char sOffsetMessage[100];
			char sOffsetDistance[8];
			FormatEx(sOffsetDistance, 8, "%.1f", gA_Timers[client].fDistanceOffset[Zone_Start]);
			FormatEx(sOffsetMessage, sizeof(sOffsetMessage), "[START] %T", "DebugOffsets", client, gA_Timers[client].fZoneOffset[Zone_Start], sOffsetDistance);
			PrintToConsole(client, "%s", sOffsetMessage);
			Shavit_StopChatSound();
			Shavit_PrintToChat(client, "%s", sOffsetMessage);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "player_speedmod"))
	{
		gH_AcceptInput.HookEntity(Hook_Post, entity, DHook_AcceptInput_player_speedmod_Post);
	}
}

// bool CBaseEntity::AcceptInput(char  const*, CBaseEntity*, CBaseEntity*, variant_t, int)
public MRESReturn DHook_AcceptInput_player_speedmod_Post(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	char buf[128];
	hParams.GetString(1, buf, sizeof(buf));

	if (!StrEqual(buf, "ModifySpeed", false) || hParams.IsNull(2))
	{
		return MRES_Ignored;
	}

	int activator = hParams.Get(2);

	if (!IsValidClient(activator, true))
	{
		return MRES_Ignored;
	}

	float speed;

	int variant_type = hParams.GetObjectVar(4, 16, ObjectValueType_Int);

	if (variant_type == 2 /* FIELD_STRING */)
	{
		hParams.GetObjectVarString(4, 0, ObjectValueType_String, buf, sizeof(buf));
		speed = StringToFloat(buf);
	}
	else // should be FIELD_FLOAT but don't check who cares
	{
		speed = hParams.GetObjectVar(4, 0, ObjectValueType_Float);
	}

	gA_Timers[activator].fplayer_speedmod = speed;
	UpdateLaggedMovement(activator, true);

	#if DEBUG
	int caller = hParams.Get(3);
	PrintToServer("ModifySpeed activator = %d(%N), caller = %d, old_speed = %s, new_speed = %f", activator, activator, caller, buf, speed);
	#endif

	return MRES_Ignored;
}

public MRESReturn DHook_PreventBunnyJumpingPre()
{
	if (GetStyleSettingBool(gA_Timers[gI_ClientProcessingMovement].bsStyle, "bunnyhopping"))
		return MRES_Supercede;
	else
		return MRES_Ignored;
}

public MRESReturn DHook_ProcessMovementPre(Handle hParams)
{
	int client = DHookGetParam(hParams, 1);
	gI_ClientProcessingMovement = client;

	if (gI_TF2PreventBunnyJumpingAddr != Address_Null)
	{
		if (GetStyleSettingBool(gA_Timers[client].bsStyle, "bunnyhopping"))
			StoreToAddress(gI_TF2PreventBunnyJumpingAddr, 0xEB, NumberType_Int8, false); // jmp
		else
			StoreToAddress(gI_TF2PreventBunnyJumpingAddr, 0x75, NumberType_Int8, false); // jnz
	}

	// Causes client to do zone touching in movement instead of server frames.
	// From https://github.com/rumourA/End-Touch-Fix
	MaybeDoPhysicsUntouch(client);

	Call_StartForward(gH_Forwards_OnProcessMovement);
	Call_PushCell(client);
	Call_Finish();

	if (IsFakeClient(client) || !IsPlayerAlive(client))
	{
		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0); // otherwise you get slow spec noclip
		return MRES_Ignored;
	}

	MoveType mt = GetEntityMoveType(client);

	if (gA_Timers[client].fTimescale == 1.0 || mt == MOVETYPE_NOCLIP)
	{
		if (gB_Eventqueuefix)
		{
			SetClientEventsPaused(client, gA_Timers[client].bClientPaused);
		}

		return MRES_Ignored;
	}

	// i got this code from kid-tas by kid fearless
	if (gA_Timers[client].fNextFrameTime <= 0.0)
	{
		gA_Timers[client].fNextFrameTime += (1.0 - gA_Timers[client].fTimescale);

		if (mt != MOVETYPE_NONE)
		{
			gA_Timers[client].iLastMoveTypeTAS = mt;
		}

		UpdateLaggedMovement(client, false);
	}
	else
	{
		gA_Timers[client].fNextFrameTime -= gA_Timers[client].fTimescale;
		SetEntityMoveType(client, MOVETYPE_NONE);
	}

	if (gB_Eventqueuefix)
	{
		SetClientEventsPaused(client, (!Shavit_ShouldProcessFrame(client) || gA_Timers[client].bClientPaused));
	}

	return MRES_Ignored;
}

public MRESReturn DHook_ProcessMovementPost(Handle hParams)
{
	int client = DHookGetParam(hParams, 1);

	Call_StartForward(gH_Forwards_OnProcessMovementPost);
	Call_PushCell(client);
	Call_Finish();

	if (IsFakeClient(client) || !IsPlayerAlive(client))
	{
		return MRES_Ignored;
	}

	if (gA_Timers[client].fTimescale != 1.0 && GetEntityMoveType(client) != MOVETYPE_NOCLIP)
	{
		SetEntityMoveType(client, gA_Timers[client].iLastMoveTypeTAS);
		UpdateLaggedMovement(client, true);
	}

	if (gA_Timers[client].bClientPaused || !gA_Timers[client].bTimerEnabled)
	{
		return MRES_Ignored;
	}

	float interval = GetTickInterval();
	float ts = GetStyleSettingFloat(gA_Timers[client].bsStyle, "timescale") * gA_Timers[client].fTimescale;
	float time = interval * ts;

	gA_Timers[client].iZoneIncrement++;

	timer_snapshot_t snapshot;
	BuildSnapshot(client, snapshot);

	Call_StartForward(gH_Forwards_OnTimeIncrement);
	Call_PushCell(client);
	Call_PushArray(snapshot, sizeof(timer_snapshot_t));
	Call_PushCellRef(time);
	Call_Finish();

	gA_Timers[client].iFractionalTicks += RoundFloat(ts * 10000.0);
	int whole_tick = gA_Timers[client].iFractionalTicks / 10000;
	gA_Timers[client].iFractionalTicks -= whole_tick * 10000;
	gA_Timers[client].iFullTicks       += whole_tick;

	CalculateRunTime(gA_Timers[client], false);

	Call_StartForward(gH_Forwards_OnTimeIncrementPost);
	Call_PushCell(client);
	Call_PushCell(time);
	Call_Finish();

	MaybeDoPhysicsUntouch(client);

	return MRES_Ignored;
}

// reference: https://github.com/momentum-mod/game/blob/5e2d1995ca7c599907980ee5b5da04d7b5474c61/mp/src/game/server/momentum/mom_timer.cpp#L388
void CalculateTickIntervalOffset(int client, int zonetype)
{
	float localOrigin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", localOrigin);
	float maxs[3];
	float mins[3];
	float vel[3];
	GetEntPropVector(client, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(client, Prop_Send, "m_vecMaxs", maxs);
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);

	gF_SmallestDist[client] = 0.0;

	if (zonetype == Zone_Start)
	{
		TR_EnumerateEntitiesHull(localOrigin, gF_Origin[client][1], mins, maxs, PARTITION_TRIGGER_EDICTS, TREnumTrigger, client);
	}
	else
	{
		TR_EnumerateEntitiesHull(gF_Origin[client][0], localOrigin, mins, maxs, PARTITION_TRIGGER_EDICTS, TREnumTrigger, client);
	}

	float offset = gF_Fraction[client] * GetTickInterval();

	gA_Timers[client].fZoneOffset[zonetype] = gF_Fraction[client];
	gA_Timers[client].fDistanceOffset[zonetype] = gF_SmallestDist[client];

	Call_StartForward(gH_Forwards_OnTimeOffsetCalculated);
	Call_PushCell(client);
	Call_PushCell(zonetype);
	Call_PushCell(offset);
	Call_PushCell(gF_SmallestDist[client]);
	Call_Finish();

	gF_SmallestDist[client] = 0.0;
}

bool TREnumTrigger(int entity, int client) {

	if (entity <= MaxClients) {
		return true;
	}

	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));

	//the entity is a zone
	if(StrContains(classname, "trigger_multiple") > -1)
	{
		TR_ClipCurrentRayToEntity(MASK_ALL, entity);

		float start[3];
		TR_GetStartPosition(INVALID_HANDLE, start);

		float end[3];
		TR_GetEndPosition(end);

		float distance = GetVectorDistance(start, end);
		gF_SmallestDist[client] = distance;
		gF_Fraction[client] = TR_GetFraction();

		return false;
	}
	return true;
}

void BuildSnapshot(int client, timer_snapshot_t snapshot)
{
	snapshot = gA_Timers[client];
	snapshot.fServerTime = GetEngineTime();
	snapshot.fTimescale = (gA_Timers[client].fTimescale > 0.0) ? gA_Timers[client].fTimescale : 1.0;
	//snapshot.iLandingTick = ?????; // TODO: Think about handling segmented scroll? /shrug
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	Remove_sv_cheat_Impluses(client, impulse);

	int flags = GetEntityFlags(client);

	if (gA_Timers[client].bClientPaused && IsPlayerAlive(client) && (gCV_PauseMovement.IntValue == 0 || gCV_PauseMovement.IntValue == 3))
	{
		buttons = 0;
		vel = view_as<float>({0.0, 0.0, 0.0});

		if (gCV_PauseMovement.IntValue == 3)
		{
			TeleportEntity(client, gF_PauseOrigin[client], gF_PauseAngles[client], view_as<float>({0.0, 0.0, 0.0}));
		}

		SetEntityFlags(client, (flags | FL_ATCONTROLS));

		//SetEntityMoveType(client, MOVETYPE_NONE);

		return Plugin_Changed;
	}

	SetEntityFlags(client, (flags & ~FL_ATCONTROLS));

	if (gI_HijackFrames[client])
	{
		--gI_HijackFrames[client];
		angles[0] = gF_HijackedAngles[client][0];
		angles[1] = gF_HijackedAngles[client][1];
	}

	// Wait till now to return so spectators can free-cam while paused...
	if(!IsPlayerAlive(client))
	{
		return Plugin_Changed;
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnUserCmdPre);
	Call_PushCell(client);
	Call_PushCellRef(buttons);
	Call_PushCellRef(impulse);
	Call_PushArrayEx(vel, 3, SM_PARAM_COPYBACK);
	Call_PushArrayEx(angles, 3, SM_PARAM_COPYBACK);
	Call_PushCell(GetTimerStatus(client));
	Call_PushCell(gA_Timers[client].iTimerTrack);
	Call_PushCell(gA_Timers[client].bsStyle);
	Call_PushArrayEx(mouse, 2, SM_PARAM_COPYBACK);
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return result;
	}

	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	bool bInStart = gB_Zones && Shavit_InsideZone(client, Zone_Start, gA_Timers[client].iTimerTrack);

	if (gA_Timers[client].bTimerEnabled && !gA_Timers[client].bClientPaused)
	{
		// +left/right block
		if(!gB_Zones || (!bInStart && ((GetStyleSettingInt(gA_Timers[client].bsStyle, "block_pleft") > 0 &&
			(buttons & IN_LEFT) > 0) || (GetStyleSettingInt(gA_Timers[client].bsStyle, "block_pright") > 0 && (buttons & IN_RIGHT) > 0))))
		{
			vel[0] = 0.0;
			vel[1] = 0.0;

			if(GetStyleSettingInt(gA_Timers[client].bsStyle, "block_pright") >= 2)
			{
				char sCheatDetected[64];
				FormatEx(sCheatDetected, 64, "%T", "LeftRightCheat", client);
				StopTimer_Cheat(client, sCheatDetected);
			}
		}

		// +strafe block
		if (GetStyleSettingInt(gA_Timers[client].bsStyle, "block_pstrafe") > 0 &&
			!GetStyleSettingBool(gA_Timers[client].bsStyle, "autostrafe") &&
			((vel[0] > 0.0 && (buttons & IN_FORWARD) == 0) || (vel[0] < 0.0 && (buttons & IN_BACK) == 0) ||
			(vel[1] > 0.0 && (buttons & IN_MOVERIGHT) == 0) || (vel[1] < 0.0 && (buttons & IN_MOVELEFT) == 0)))
		{
			if (gA_Timers[client].fStrafeWarning < gA_Timers[client].fCurrentTime)
			{
				if (GetStyleSettingInt(gA_Timers[client].bsStyle, "block_pstrafe") >= 2)
				{
					char sCheatDetected[64];
					FormatEx(sCheatDetected, 64, "%T", "Inconsistencies", client);
					StopTimer_Cheat(client, sCheatDetected);
				}

				vel[0] = 0.0;
				vel[1] = 0.0;

				return Plugin_Changed;
			}

			gA_Timers[client].fStrafeWarning = gA_Timers[client].fCurrentTime + 0.3;
		}
	}

	#if DEBUG
	static int cycle = 0;

	if(++cycle % 50 == 0)
	{
		Shavit_StopChatSound();
		Shavit_PrintToChat(client, "vel[0]: %.01f | vel[1]: %.01f", vel[0], vel[1]);
	}
	#endif

	MoveType mtMoveType = GetEntityMoveType(client);

	if(mtMoveType == MOVETYPE_LADDER && gCV_SimplerLadders.BoolValue)
	{
		gA_Timers[client].bCanUseAllKeys = true;
	}
	else if(iGroundEntity != -1)
	{
		gA_Timers[client].bCanUseAllKeys = false;
	}

	// key blocking
	if(!gA_Timers[client].bCanUseAllKeys && mtMoveType != MOVETYPE_NOCLIP && mtMoveType != MOVETYPE_LADDER && !(gB_Zones && Shavit_InsideZone(client, Zone_Freestyle, -1)))
	{
		// block E
		if (GetStyleSettingBool(gA_Timers[client].bsStyle, "block_use") && (buttons & IN_USE) > 0)
		{
			buttons &= ~IN_USE;
		}

		if (iGroundEntity == -1 || GetStyleSettingBool(gA_Timers[client].bsStyle, "force_groundkeys"))
		{
			if (GetStyleSettingBool(gA_Timers[client].bsStyle, "block_w") && ((buttons & IN_FORWARD) > 0 || vel[0] > 0.0))
			{
				vel[0] = 0.0;
				buttons &= ~IN_FORWARD;
			}

			if (GetStyleSettingBool(gA_Timers[client].bsStyle, "block_a") && ((buttons & IN_MOVELEFT) > 0 || vel[1] < 0.0))
			{
				vel[1] = 0.0;
				buttons &= ~IN_MOVELEFT;
			}

			if (GetStyleSettingBool(gA_Timers[client].bsStyle, "block_s") && ((buttons & IN_BACK) > 0 || vel[0] < 0.0))
			{
				vel[0] = 0.0;
				buttons &= ~IN_BACK;
			}

			if (GetStyleSettingBool(gA_Timers[client].bsStyle, "block_d") && ((buttons & IN_MOVERIGHT) > 0 || vel[1] > 0.0))
			{
				vel[1] = 0.0;
				buttons &= ~IN_MOVERIGHT;
			}

			if (GetStyleSettingBool(gA_Timers[client].bsStyle, "a_or_d_only"))
			{
				int iCombination = -1;
				bool bMoveLeft = ((buttons & IN_MOVELEFT) > 0 && vel[1] < 0.0);
				bool bMoveRight = ((buttons & IN_MOVERIGHT) > 0 && vel[1] > 0.0);

				if (bMoveLeft)
				{
					iCombination = 0;
				}
				else if (bMoveRight)
				{
					iCombination = 1;
				}

				if (iCombination != -1)
				{
					if (gA_Timers[client].iKeyCombo == -1)
					{
						gA_Timers[client].iKeyCombo = iCombination;
					}

					if (iCombination != gA_Timers[client].iKeyCombo)
					{
						vel[1] = 0.0;
						buttons &= ~(IN_MOVELEFT|IN_MOVERIGHT);
					}
				}
			}

			// HSW
			// Theory about blocking non-HSW strafes while playing HSW:
			// Block S and W without A or D.
			// Block A and D without S or W.
			if (GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") > 0)
			{
				bool bSHSW = (GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") == 2) && !bInStart; // don't decide on the first valid input until out of start zone!
				int iCombination = -1;

				bool bForward = ((buttons & IN_FORWARD) > 0 && vel[0] > 0.0);
				bool bMoveLeft = ((buttons & IN_MOVELEFT) > 0 && vel[1] < 0.0);
				bool bBack = ((buttons & IN_BACK) > 0 && vel[0] < 0.0);
				bool bMoveRight = ((buttons & IN_MOVERIGHT) > 0 && vel[1] > 0.0);

				if(bSHSW)
				{
					if((bForward && bMoveLeft) || (bBack && bMoveRight))
					{
						iCombination = 0;
					}
					else if((bForward && bMoveRight || bBack && bMoveLeft))
					{
						iCombination = 1;
					}

					// int gI_SHSW_FirstCombination[MAXPLAYERS+1]; // 0 - W/A S/D | 1 - W/D S/A
					if(gA_Timers[client].iKeyCombo == -1 && iCombination != -1)
					{
						Shavit_PrintToChat(client, "%T", (iCombination == 0)? "SHSWCombination0":"SHSWCombination1", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
						gA_Timers[client].iKeyCombo = iCombination;
					}

					// W/A S/D
					if((gA_Timers[client].iKeyCombo == 0 && iCombination != 0) ||
					// W/D S/A
						(gA_Timers[client].iKeyCombo == 1 && iCombination != 1) ||
					// no valid combination & no valid input
						(gA_Timers[client].iKeyCombo == -1 && iCombination == -1))
					{
						vel[0] = 0.0;
						vel[1] = 0.0;

						buttons &= ~IN_FORWARD;
						buttons &= ~IN_MOVELEFT;
						buttons &= ~IN_MOVERIGHT;
						buttons &= ~IN_BACK;
					}
				}
				else
				{
					if(bBack && (bMoveLeft || bMoveRight))
					{
						vel[0] = 0.0;

						buttons &= ~IN_FORWARD;
						buttons &= ~IN_BACK;
					}

					if(bForward && !(bMoveLeft || bMoveRight))
					{
						vel[0] = 0.0;

						buttons &= ~IN_FORWARD;
						buttons &= ~IN_BACK;
					}

					if((bMoveLeft || bMoveRight) && !bForward)
					{
						vel[1] = 0.0;

						buttons &= ~IN_MOVELEFT;
						buttons &= ~IN_MOVERIGHT;
					}
				}
			}
		}
	}

	bool bInWater = (GetEntProp(client, Prop_Send, "m_nWaterLevel") >= 2);
	int iOldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");

	if (   gB_Auto[client]
		&& (buttons & IN_JUMP) > 0
		&& mtMoveType == MOVETYPE_WALK
		&& !bInWater
		&& (   GetStyleSettingBool(gA_Timers[client].bsStyle, "autobhop")
			|| (gB_Zones && Shavit_InsideZone(client, Zone_Autobhop, gA_Timers[client].iTimerTrack))
		   )
	)
	{
		SetEntProp(client, Prop_Data, "m_nOldButtons", (iOldButtons &= ~IN_JUMP));
	}

	int blockprejump = GetStyleSettingInt(gA_Timers[client].bsStyle, "blockprejump");

	if (blockprejump < 0)
	{
		blockprejump = gCV_BlockPreJump.BoolValue;
	}

	if (bInStart && blockprejump && GetStyleSettingInt(gA_Timers[client].bsStyle, "prespeed") == 0 && (vel[2] > 0 || (buttons & IN_JUMP) > 0))
	{
		vel[2] = 0.0;
		buttons &= ~IN_JUMP;
	}

	if (gB_Zones && Shavit_InsideZone(client, Zone_NoJump, gA_Timers[client].iTimerTrack))
	{
		vel[2] = 0.0;
		buttons &= ~IN_JUMP;
	}

	// enable duck-jumping/bhop in tf2
	if (gEV_Type == Engine_TF2 && GetStyleSettingBool(gA_Timers[client].bsStyle, "bunnyhopping") && (buttons & IN_JUMP) > 0 && !(iOldButtons & IN_JUMP) && iGroundEntity != -1)
	{
		float fSpeed[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);

		fSpeed[2] = 289.0;
		SetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);

		DoJump(client);
	}

	// perf jump measuring
	bool bOnGround = (!bInWater && mtMoveType == MOVETYPE_WALK && iGroundEntity != -1);

	gI_LastTickcount[client] = tickcount;

	if (bOnGround)
	{
		if (gI_FirstTouchedGroundForStartTimer[client] == 0)
		{
			// just landed (or teleported to the ground or whatever)
			gI_FirstTouchedGroundForStartTimer[client] = tickcount;
		}

		if (gI_FirstTouchedGroundForStartTimer[client] > 0)
		{
			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);

			// zero...ish... velocity... (squared-ish (cubed?))
			if (GetVectorLength(fSpeed, true) <= 1000.0)
			{
				gI_FirstTouchedGroundForStartTimer[client] = -1;
			}
		}
	}
	else
	{
		gI_FirstTouchedGroundForStartTimer[client] = 0;
	}

	if(bOnGround && !gA_Timers[client].bOnGround)
	{
		gA_Timers[client].iLandingTick = tickcount;
		gI_FirstTouchedGroundForStartTimer[client] = tickcount;

		if (gEV_Type != Engine_TF2 && GetStyleSettingBool(gA_Timers[client].bsStyle, "easybhop"))
		{
			SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
		}
	}
	else if (!bOnGround && gA_Timers[client].bOnGround && gA_Timers[client].bJumped && !gA_Timers[client].bClientPaused)
	{
		int iDifference = (tickcount - gA_Timers[client].iLandingTick);

		if (iDifference < 10)
		{
			gA_Timers[client].iMeasuredJumps++;

			if (iDifference == 1)
			{
				gA_Timers[client].iPerfectJumps++;
			}
		}
	}

	// This can be bypassed by spamming +duck on CSS which causes `iGroundEntity` to be `-1` here...
	//   (e.g. an autobhop + velocity_limit style...)
	// m_hGroundEntity changes from 0 -> -1 same tick which causes problems and I'm not sure what the best way / place to handle that is...
	// There's not really many things using m_hGroundEntity that "matter" in this function
	// so I'm just going to move this `velocity_limit` logic somewhere else instead of trying to "fix" it.
	// Now happens in `VelocityChanges()` which comes from `player_jump->RequestFrame(VelocityChanges)`.
	//   (that is also the same thing btimes does)
#if 0
	// velocity limit
	if (iGroundEntity != -1 && GetStyleSettingFloat(gA_Timers[client].bsStyle, "velocity_limit") > 0.0)
	{
		float fSpeedLimit = GetStyleSettingFloat(gA_Timers[client].bsStyle, "velocity_limit");

		if(gB_Zones && Shavit_InsideZone(client, Zone_CustomSpeedLimit, -1))
		{
			fSpeedLimit = gF_ZoneSpeedLimit[client];
		}

		float fSpeed[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);

		float fSpeed_New = (SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)));

		if(fSpeedLimit != 0.0 && fSpeed_New > 0.0)
		{
			float fScale = fSpeedLimit / fSpeed_New;

			if(fScale < 1.0)
			{
				fSpeed[0] *= fScale;
				fSpeed[1] *= fScale;
				TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed); // maybe change this to SetEntPropVector some time?
			}
		}
	}
#endif

	gA_Timers[client].bJumped = false;
	gA_Timers[client].bOnGround = bOnGround;

	return Plugin_Continue;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (IsFakeClient(client))
	{
		return;
	}

	if (!IsPlayerAlive(client) || GetTimerStatus(client) != Timer_Running)
	{
		return;
	}

	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");

	if (iGroundEntity == -1
	&& GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_w")
	&& !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_w")
	&& (gA_Timers[client].fLastInputVel[0] <= 0.0) && (vel[0] > 0.0)
	&& GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") != 1
	)
	{
		gA_Timers[client].iStrafes++;
	}

	if (iGroundEntity == -1
	&& GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_s")
	&& !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_s")
	&& (gA_Timers[client].fLastInputVel[0] >= 0.0) && (vel[0] < 0.0)
	)
	{
		gA_Timers[client].iStrafes++;
	}

	if (iGroundEntity == -1
	&& GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_a")
	&& !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_a")
	&& (gA_Timers[client].fLastInputVel[1] >= 0.0) && (vel[1] < 0.0)
	&& (GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") > 0 || vel[0] == 0.0)
	)
	{
		gA_Timers[client].iStrafes++;
	}

	if (iGroundEntity == -1
	&& GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_d")
	&& !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_d")
	&& (gA_Timers[client].fLastInputVel[1] <= 0.0) && (vel[1] > 0.0)
	&& (GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") > 0 || vel[0] == 0.0)
	)
	{
		gA_Timers[client].iStrafes++;
	}

	float fAngle = GetAngleDiff(angles[1], gA_Timers[client].fLastAngle);

	float fAbsVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);
	float curVel = SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0));

	if (iGroundEntity == -1 && GetEntityMoveType(client) != MOVETYPE_LADDER && (GetEntityFlags(client) & FL_INWATER) == 0 && fAngle != 0.0 && curVel > 0.0)
	{
		float fTempAngle = angles[1];

		float fAngles[3];
		GetVectorAngles(fAbsVelocity, fAngles);

		if (fTempAngle < 0.0)
		{
			fTempAngle += 360.0;
		}

		TestAngles(client, (fTempAngle - fAngles[1]), fAngle, vel);
	}

	if (gA_Timers[client].fCurrentTime != 0.0)
	{
		float frameCount = float(gA_Timers[client].iZoneIncrement);
		float maxVel = gA_Timers[client].fMaxVelocity;
		gA_Timers[client].fMaxVelocity = (curVel > maxVel) ? curVel : maxVel;
		// STOLEN from Epic/Disrevoid. Thx :)
		gA_Timers[client].fAvgVelocity += (curVel - gA_Timers[client].fAvgVelocity) / frameCount;
	}

	gA_Timers[client].iLastButtons = buttons;
	gA_Timers[client].fLastAngle = angles[1];
	gA_Timers[client].fLastInputVel[0] = vel[0];
	gA_Timers[client].fLastInputVel[1] = vel[1];
}

void TestAngles(int client, float dirangle, float yawdelta, const float vel[3])
{
	if(dirangle < 0.0)
	{
		dirangle = -dirangle;
	}

	// normal
	if(dirangle < 22.5 || dirangle > 337.5)
	{
		gA_Timers[client].iTotalMeasures++;

		if((yawdelta > 0.0 && vel[1] <= -100.0) || (yawdelta < 0.0 && vel[1] >= 100.0))
		{
			gA_Timers[client].iGoodGains++;
		}
	}

	// hsw (thanks nairda!)
	else if((dirangle > 22.5 && dirangle < 67.5) || (dirangle > 292.5 && dirangle < 337.5))
	{
		gA_Timers[client].iTotalMeasures++;

		if((yawdelta != 0.0) && (vel[0] >= 100.0 || vel[1] >= 100.0) && (vel[0] >= -100.0 || vel[1] >= -100.0))
		{
			gA_Timers[client].iGoodGains++;
		}
	}

	// backwards hsw
	else if((dirangle > 112.5 && dirangle < 157.5) || (dirangle > 202.5 && dirangle < 247.5))
	{
		gA_Timers[client].iTotalMeasures++;

		if((yawdelta != 0.0) && (vel[0] >= 100.0 || vel[1] >= 100.0) && (vel[0] >= -100.0 || vel[1] >= -100.0))
		{
			gA_Timers[client].iGoodGains++;
		}
	}

	// sw
	else if((dirangle > 67.5 && dirangle < 112.5) || (dirangle > 247.5 && dirangle < 292.5))
	{
		gA_Timers[client].iTotalMeasures++;

		if(vel[0] <= -100.0 || vel[0] >= 100.0)
		{
			gA_Timers[client].iGoodGains++;
		}
	}

	// backwards
	else if(dirangle > 157.5 || dirangle < 202.5)
	{
		gA_Timers[client].iTotalMeasures++;

		if((yawdelta > 0.0 && vel[1] <= -100.0) || (yawdelta < 0.0 && vel[1] >= 100.0))
		{
			gA_Timers[client].iGoodGains++;
		}
	}
}

void StopTimer_Cheat(int client, const char[] message)
{
	Shavit_StopTimer(client);
	Shavit_PrintToChat(client, "%T", "CheatTimerStop", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, message);
}

void UpdateAiraccelerate(int client, float airaccelerate)
{
	char sAiraccelerate[8];
	FloatToString(airaccelerate, sAiraccelerate, 8);
	sv_airaccelerate.ReplicateToClient(client, sAiraccelerate);
}

void UpdateStyleSettings(int client)
{
	if(sv_autobunnyhopping != null)
	{
		sv_autobunnyhopping.ReplicateToClient(client,
			(
				gB_Auto[client]
				&&
				(
					GetStyleSettingBool(gA_Timers[client].bsStyle, "autobhop")
				    || (gB_Zones && Shavit_InsideZone(client, Zone_Autobhop, gA_Timers[client].iTimerTrack))
				)
			)
			? "1":"0"
		);
	}

	if(sv_enablebunnyhopping != null)
	{
		if (gB_Zones && Shavit_InsideZone(client, Zone_CustomSpeedLimit, gA_Timers[client].iTimerTrack))
		{
			sv_enablebunnyhopping.ReplicateToClient(client, "1");
		}
		else
		{
			sv_enablebunnyhopping.ReplicateToClient(client, (GetStyleSettingBool(gA_Timers[client].bsStyle, "bunnyhopping"))? "1":"0");
		}
	}

	if (gB_Zones && Shavit_InsideZone(client, Zone_Airaccelerate, gA_Timers[client].iTimerTrack))
	{
		UpdateAiraccelerate(client, gF_ZoneAiraccelerate[client]);
	}
	else
	{
		UpdateAiraccelerate(client, GetStyleSettingFloat(gA_Timers[client].bsStyle, "airaccelerate"));
	}
}
