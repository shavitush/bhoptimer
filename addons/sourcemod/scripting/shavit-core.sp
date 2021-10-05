/*
 * shavit's Timer - Core
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
#include <sdkhooks>
#include <sdktools>
#include <geoip>
#include <clientprefs>
#include <convar_class>
#include <dhooks>

#undef REQUIRE_PLUGIN
#define USES_CHAT_COLORS
#include <shavit>
#include <eventqueuefix>

#pragma newdecls required
#pragma semicolon 1

#define DEBUG 0

#define EFL_CHECK_UNTOUCH (1<<24)

// game type (CS:S/CS:GO/TF2)
EngineVersion gEV_Type = Engine_Unknown;
bool gB_Protobuf = false;

// hook stuff
DynamicHook gH_AcceptInput; // used for hooking player_speedmod's AcceptInput
Handle gH_PhysicsCheckForEntityUntouch;

// database handle
Database2 gH_SQL = null;
bool gB_MySQL = false;
int gI_MigrationsRequired;
int gI_MigrationsFinished;

// forwards
Handle gH_Forwards_Start = null;
Handle gH_Forwards_StartPre = null;
Handle gH_Forwards_Stop = null;
Handle gH_Forwards_StopPre = null;
Handle gH_Forwards_FinishPre = null;
Handle gH_Forwards_Finish = null;
Handle gH_Forwards_OnRestartPre = null;
Handle gH_Forwards_OnRestart = null;
Handle gH_Forwards_OnEnd = null;
Handle gH_Forwards_OnPause = null;
Handle gH_Forwards_OnResume = null;
Handle gH_Forwards_OnStyleChanged = null;
Handle gH_Forwards_OnTrackChanged = null;
Handle gH_Forwards_OnStyleConfigLoaded = null;
Handle gH_Forwards_OnDatabaseLoaded = null;
Handle gH_Forwards_OnChatConfigLoaded = null;
Handle gH_Forwards_OnUserCmdPre = null;
Handle gH_Forwards_OnTimerIncrement = null;
Handle gH_Forwards_OnTimerIncrementPost = null;
Handle gH_Forwards_OnTimescaleChanged = null;
Handle gH_Forwards_OnTimeOffsetCalculated = null;
Handle gH_Forwards_OnProcessMovement = null;
Handle gH_Forwards_OnProcessMovementPost = null;

StringMap gSM_StyleCommands = null;

// player timer variables
timer_snapshot_t gA_Timers[MAXPLAYERS+1];
bool gB_Auto[MAXPLAYERS+1];

// these are here until the compiler bug is fixed
float gF_PauseOrigin[MAXPLAYERS+1][3];
float gF_PauseAngles[MAXPLAYERS+1][3];
float gF_PauseVelocity[MAXPLAYERS+1][3];

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

// modules
bool gB_Eventqueuefix = false;
bool gB_Zones = false;
bool gB_WR = false;
bool gB_Replay = false;
bool gB_Rankings = false;
bool gB_HUD = false;

// cvars
Convar gCV_Restart = null;
Convar gCV_Pause = null;
Convar gCV_PauseMovement = null;
Convar gCV_AllowTimerWithoutZone = null;
Convar gCV_BlockPreJump = null;
Convar gCV_NoZAxisSpeed = null;
Convar gCV_VelocityTeleport = null;
Convar gCV_DefaultStyle = null;
Convar gCV_NoChatSound = null;
Convar gCV_SimplerLadders = null;
Convar gCV_UseOffsets = null;
Convar gCV_TimeInMessages;
Convar gCV_DebugOffsets = null;
Convar gCV_DisableSvCheats = null;
// cached cvars
int gI_DefaultStyle = 0;
bool gB_StyleCookies = true;

// table prefix
char gS_MySQLPrefix[32];

// server side
ConVar sv_airaccelerate = null;
ConVar sv_autobunnyhopping = null;
ConVar sv_enablebunnyhopping = null;

// timer settings
bool gB_Registered = false;
int gI_Styles = 0;
int gI_OrderedStyles[STYLE_LIMIT];
StringMap gSM_StyleKeys[STYLE_LIMIT];
int gI_CurrentParserIndex = 0;

// chat settings
chatstrings_t gS_ChatStrings;

// misc cache
bool gB_StopChatSound = false;
bool gB_HookedJump = false;
char gS_LogPath[PLATFORM_MAX_PATH];
char gS_DeleteMap[MAXPLAYERS+1][PLATFORM_MAX_PATH];
int gI_WipePlayerID[MAXPLAYERS+1];
char gS_Verification[MAXPLAYERS+1][8];
bool gB_CookiesRetrieved[MAXPLAYERS+1];
float gF_ZoneAiraccelerate[MAXPLAYERS+1];
float gF_ZoneSpeedLimit[MAXPLAYERS+1];

// flags
int gI_StyleFlag[STYLE_LIMIT];
char gS_StyleOverride[STYLE_LIMIT][32];

// kz support
bool gB_KZMap = false;

#if !DEBUG
ConVar sv_cheats = null;

char gS_CheatCommands[][] = {
	"ent_setpos",
	"setpos",
	"setpos_exact",
	"setpos_player",

	// can be used to kill other players
	"explode",
	"explodevector",
	"kill",
	"killvector",

	"give",
};
#endif

public Plugin myinfo =
{
	name = "[shavit] Core",
	author = "shavit",
	description = "The core for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
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
	CreateNative("Shavit_GetOrderedStyles", Native_GetOrderedStyles);
	CreateNative("Shavit_GetPerfectJumps", Native_GetPerfectJumps);
	CreateNative("Shavit_GetStrafeCount", Native_GetStrafeCount);
	CreateNative("Shavit_GetStyleCount", Native_GetStyleCount);
	CreateNative("Shavit_GetStyleSetting", Native_GetStyleSetting);
	CreateNative("Shavit_GetStyleSettingInt", Native_GetStyleSettingInt);
	CreateNative("Shavit_GetStyleSettingBool", Native_GetStyleSettingBool);
	CreateNative("Shavit_GetStyleSettingFloat", Native_GetStyleSettingFloat);
	CreateNative("Shavit_HasStyleSetting", Native_HasStyleSetting);
	CreateNative("Shavit_GetStyleStrings", Native_GetStyleStrings);
	CreateNative("Shavit_GetStyleStringsStruct", Native_GetStyleStringsStruct);
	CreateNative("Shavit_GetSync", Native_GetSync);
	CreateNative("Shavit_GetZoneOffset", Native_GetZoneOffset);
	CreateNative("Shavit_GetDistanceOffset", Native_GetDistanceOffset);
	CreateNative("Shavit_GetTimerStatus", Native_GetTimerStatus);
	CreateNative("Shavit_HasStyleAccess", Native_HasStyleAccess);
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
	CreateNative("Shavit_SetStyleSetting", Native_SetStyleSetting);
	CreateNative("Shavit_SetStyleSettingFloat", Native_SetStyleSettingFloat);
	CreateNative("Shavit_SetStyleSettingBool", Native_SetStyleSettingBool);
	CreateNative("Shavit_SetStyleSettingInt", Native_SetStyleSettingInt);
	CreateNative("Shavit_StartTimer", Native_StartTimer);
	CreateNative("Shavit_StopChatSound", Native_StopChatSound);
	CreateNative("Shavit_StopTimer", Native_StopTimer);
	CreateNative("Shavit_GetClientTimescale", Native_GetClientTimescale);
	CreateNative("Shavit_SetClientTimescale", Native_SetClientTimescale);
	CreateNative("Shavit_GetAvgVelocity", Native_GetAvgVelocity);
	CreateNative("Shavit_GetMaxVelocity", Native_GetMaxVelocity);
	CreateNative("Shavit_SetAvgVelocity", Native_SetAvgVelocity);
	CreateNative("Shavit_SetMaxVelocity", Native_SetMaxVelocity);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// forwards
	gH_Forwards_Start = CreateGlobalForward("Shavit_OnStart", ET_Ignore, Param_Cell, Param_Cell);
	gH_Forwards_StartPre = CreateGlobalForward("Shavit_OnStartPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_Stop = CreateGlobalForward("Shavit_OnStop", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_StopPre = CreateGlobalForward("Shavit_OnStopPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_FinishPre = CreateGlobalForward("Shavit_OnFinishPre", ET_Event, Param_Cell, Param_Array);
	gH_Forwards_Finish = CreateGlobalForward("Shavit_OnFinish", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnRestartPre = CreateGlobalForward("Shavit_OnRestartPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnRestart = CreateGlobalForward("Shavit_OnRestart", ET_Ignore, Param_Cell, Param_Cell);
	gH_Forwards_OnEnd = CreateGlobalForward("Shavit_OnEnd", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnPause = CreateGlobalForward("Shavit_OnPause", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnResume = CreateGlobalForward("Shavit_OnResume", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnStyleChanged = CreateGlobalForward("Shavit_OnStyleChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnTrackChanged = CreateGlobalForward("Shavit_OnTrackChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnStyleConfigLoaded = CreateGlobalForward("Shavit_OnStyleConfigLoaded", ET_Event, Param_Cell);
	gH_Forwards_OnDatabaseLoaded = CreateGlobalForward("Shavit_OnDatabaseLoaded", ET_Event);
	gH_Forwards_OnChatConfigLoaded = CreateGlobalForward("Shavit_OnChatConfigLoaded", ET_Event);
	gH_Forwards_OnUserCmdPre = CreateGlobalForward("Shavit_OnUserCmdPre", ET_Event, Param_Cell, Param_CellByRef, Param_CellByRef, Param_Array, Param_Array, Param_Cell, Param_Cell, Param_Cell, Param_Array, Param_Array);
	gH_Forwards_OnTimerIncrement = CreateGlobalForward("Shavit_OnTimeIncrement", ET_Event, Param_Cell, Param_Array, Param_CellByRef, Param_Array);
	gH_Forwards_OnTimerIncrementPost = CreateGlobalForward("Shavit_OnTimeIncrementPost", ET_Event, Param_Cell, Param_Cell, Param_Array);
	gH_Forwards_OnTimescaleChanged = CreateGlobalForward("Shavit_OnTimescaleChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnTimeOffsetCalculated = CreateGlobalForward("Shavit_OnTimeOffsetCalculated", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnProcessMovement = CreateGlobalForward("Shavit_OnProcessMovement", ET_Event, Param_Cell);
	gH_Forwards_OnProcessMovementPost = CreateGlobalForward("Shavit_OnProcessMovementPost", ET_Event, Param_Cell);
	LoadTranslations("shavit-core.phrases");
	LoadTranslations("shavit-common.phrases");

	// game types
	gEV_Type = GetEngineVersion();
	gB_Protobuf = (GetUserMessageType() == UM_Protobuf);

	if(gEV_Type == Engine_CSGO)
	{
		sv_autobunnyhopping = FindConVar("sv_autobunnyhopping");
		sv_autobunnyhopping.BoolValue = false;
	}

	else if(gEV_Type != Engine_CSS && gEV_Type != Engine_TF2)
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

	// style commands
	gSM_StyleCommands = new StringMap();

	#if DEBUG
	RegConsoleCmd("sm_finishtest", Command_FinishTest);
	RegConsoleCmd("sm_fling", Command_Fling);
	#endif

	// admin
	RegAdminCmd("sm_deletemap", Command_DeleteMap, ADMFLAG_ROOT, "Deletes all map data. Usage: sm_deletemap <map>");
	RegAdminCmd("sm_wipeplayer", Command_WipePlayer, ADMFLAG_BAN, "Wipes all bhoptimer data for specified player. Usage: sm_wipeplayer <steamid3>");
	RegAdminCmd("sm_migration", Command_Migration, ADMFLAG_ROOT, "Force a database migration to run. Usage: sm_migration <migration id> or \"all\" to run all migrations.");
	// commands END

	// logs
	BuildPath(Path_SM, gS_LogPath, PLATFORM_MAX_PATH, "logs/shavit.log");

	CreateConVar("shavit_version", SHAVIT_VERSION, "Plugin version.", (FCVAR_NOTIFY | FCVAR_DONTRECORD));

	gCV_Restart = new Convar("shavit_core_restart", "1", "Allow commands that restart the timer?", 0, true, 0.0, true, 1.0);
	gCV_Pause = new Convar("shavit_core_pause", "1", "Allow pausing?", 0, true, 0.0, true, 1.0);
	gCV_AllowTimerWithoutZone = new Convar("shavit_core_timernozone", "0", "Allow the timer to start if there's no start zone?", 0, true, 0.0, true, 1.0);
	gCV_PauseMovement = new Convar("shavit_core_pause_movement", "0", "Allow movement/noclip while paused?", 0, true, 0.0, true, 1.0);
	gCV_BlockPreJump = new Convar("shavit_core_blockprejump", "0", "Prevents jumping in the start zone.", 0, true, 0.0, true, 1.0);
	gCV_NoZAxisSpeed = new Convar("shavit_core_nozaxisspeed", "1", "Don't start timer if vertical speed exists (btimes style).", 0, true, 0.0, true, 1.0);
	gCV_VelocityTeleport = new Convar("shavit_core_velocityteleport", "0", "Teleport the client when changing its velocity? (for special styles)", 0, true, 0.0, true, 1.0);
	gCV_DefaultStyle = new Convar("shavit_core_defaultstyle", "0", "Default style ID.\nAdd the '!' prefix to disable style cookies - i.e. \"!3\" to *force* scroll to be the default style.", 0, true, 0.0);
	gCV_NoChatSound = new Convar("shavit_core_nochatsound", "0", "Disables click sound for chat messages.", 0, true, 0.0, true, 1.0);
	gCV_SimplerLadders = new Convar("shavit_core_simplerladders", "1", "Allows using all keys on limited styles (such as sideways) after touching ladders\nTouching the ground enables the restriction again.", 0, true, 0.0, true, 1.0);
	gCV_UseOffsets = new Convar("shavit_core_useoffsets", "1", "Calculates more accurate times by subtracting/adding tick offsets from the time the server uses to register that a player has left or entered a trigger", 0, true, 0.0, true, 1.0);
	gCV_TimeInMessages = new Convar("shavit_core_timeinmessages", "0", "Whether to prefix SayText2 messages with the time.", 0, true, 0.0, true, 1.0);
	gCV_DebugOffsets = new Convar("shavit_core_debugoffsets", "0", "Print offset upon leaving or entering a zone?", 0, true, 0.0, true, 1.0);
	gCV_DisableSvCheats = new Convar("shavit_core_disable_sv_cheats", "1", "Force sv_cheats to 0.", 0, true, 0.0, true, 1.0);
	gCV_DefaultStyle.AddChangeHook(OnConVarChanged);

	Convar.AutoExecConfig();

#if !DEBUG
	sv_cheats = FindConVar("sv_cheats");
	sv_cheats.AddChangeHook(sv_cheats_hook);

	for (int i = 0; i < sizeof(gS_CheatCommands); i++)
	{
		AddCommandListener(Command_Cheats, gS_CheatCommands[i]);
	}
#endif

	sv_airaccelerate = FindConVar("sv_airaccelerate");
	sv_airaccelerate.Flags &= ~(FCVAR_NOTIFY | FCVAR_REPLICATED);

	sv_enablebunnyhopping = FindConVar("sv_enablebunnyhopping");

	if(sv_enablebunnyhopping != null)
	{
		sv_enablebunnyhopping.Flags &= ~(FCVAR_NOTIFY | FCVAR_REPLICATED);
	}

	gB_Eventqueuefix = LibraryExists("eventqueuefix");
	gB_Zones = LibraryExists("shavit-zones");
	gB_WR = LibraryExists("shavit-wr");
	gB_Replay = LibraryExists("shavit-replay");
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_HUD = LibraryExists("shavit-hud");

	// database connections
	SQL_DBConnect();

	// late
	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

void LoadDHooks()
{
	Handle gamedataConf = LoadGameConfigFile("shavit.games");

	if(gamedataConf == null)
	{
		SetFailState("Failed to load shavit gamedata");
	}

	StartPrepSDKCall(SDKCall_Static);
	if(!PrepSDKCall_SetFromConf(gamedataConf, SDKConf_Signature, "CreateInterface"))
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

	Handle processMovement = DHookCreate(offset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore, DHook_ProcessMovement);
	DHookAddParam(processMovement, HookParamType_CBaseEntity);
	DHookAddParam(processMovement, HookParamType_ObjectPtr);
	DHookRaw(processMovement, false, IGameMovement);

	Handle processMovementPost = DHookCreate(offset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore, DHook_ProcessMovementPost);
	DHookAddParam(processMovementPost, HookParamType_CBaseEntity);
	DHookAddParam(processMovementPost, HookParamType_ObjectPtr);
	DHookRaw(processMovementPost, true, IGameMovement);

	StartPrepSDKCall(SDKCall_Entity);
	if(!PrepSDKCall_SetFromConf(gamedataConf, SDKConf_Signature, "PhysicsCheckForEntityUntouch"))
	{
		SetFailState("Failed to get PhysicsCheckForEntityUntouch");
	}
	gH_PhysicsCheckForEntityUntouch = EndPrepSDKCall();

	delete CreateInterface;
	delete gamedataConf;

	GameData AcceptInputGameData;

	if (gEV_Type == Engine_CSS)
	{
		AcceptInputGameData = new GameData("sdktools.games/game.cstrike");
	}
	else if (gEV_Type == Engine_TF2)
	{
		AcceptInputGameData = new GameData("sdktools.games/game.tf");
	}
	else if (gEV_Type == Engine_CSGO)
	{
		AcceptInputGameData = new GameData("sdktools.games/engine.csgo");
	}

	// Stolen from dhooks-test.sp
	offset = AcceptInputGameData.GetOffset("AcceptInput");
	delete AcceptInputGameData;
	gH_AcceptInput = new DynamicHook(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity);
	gH_AcceptInput.AddParam(HookParamType_CharPtr);
	gH_AcceptInput.AddParam(HookParamType_CBaseEntity);
	gH_AcceptInput.AddParam(HookParamType_CBaseEntity);
	gH_AcceptInput.AddParam(HookParamType_Object, 20, DHookPass_ByVal|DHookPass_ODTOR|DHookPass_OCTOR|DHookPass_OASSIGNOP); //variant_t is a union of 12 (float[3]) plus two int type params 12 + 8 = 20
	gH_AcceptInput.AddParam(HookParamType_Int);
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gB_StyleCookies = (newValue[0] != '!');
	gI_DefaultStyle = StringToInt(newValue[1]);
}

#if !DEBUG
public void sv_cheats_hook(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (gCV_DisableSvCheats.BoolValue)
	{
		sv_cheats.SetInt(0);
	}
}

public Action Command_Cheats(int client, const char[] command, int args)
{
	if (!sv_cheats.BoolValue || client == 0)
	{
		return Plugin_Continue;
	}

	if (StrContains(command, "kill") != -1 || StrContains(command, "explode") != -1)
	{
		bool bVector = StrContains(command, "vector") != -1;
		bool bKillOther = args > (bVector ? 3 : 0);

		if (!bKillOther)
		{
			return Plugin_Continue;
		}
	}

	if (!(GetUserFlagBits(client) & ADMFLAG_ROOT))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}
#endif

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}

	else if(StrEqual(name, "shavit-wr"))
	{
		gB_WR = true;
	}

	else if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = true;
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
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}

	else if(StrEqual(name, "shavit-wr"))
	{
		gB_WR = false;
	}

	else if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = false;
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
	if (gCV_DisableSvCheats.BoolValue)
	{
#if !DEBUG
		sv_cheats.SetInt(0);
#endif
	}
}

public void OnMapEnd()
{
	gB_KZMap = false;
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

		Action result = Plugin_Continue;
		Call_StartForward(gH_Forwards_OnRestartPre);
		Call_PushCell(client);
		Call_PushCell(track);
		Call_Finish(result);

		if (result > Plugin_Continue)
		{
			return Plugin_Handled;
		}
	}

	if(gCV_AllowTimerWithoutZone.BoolValue || (gB_Zones && (Shavit_ZoneExists(Zone_Start, track) || gB_KZMap)))
	{
		if(!Shavit_StopTimer(client, false))
		{
			return Plugin_Handled;
		}

		Call_StartForward(gH_Forwards_OnRestart);
		Call_PushCell(client);
		Call_PushCell(track);
		Call_Finish();

		if(gCV_AllowTimerWithoutZone.BoolValue || !gB_Zones)
		{
			StartTimer(client, track);
		}
	}
	else
	{
		char sTrack[32];
		GetTrackName(client, track, sTrack, 32);

		Shavit_PrintToChat(client, "%T", "StartZoneUndefined", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTrack, gS_ChatStrings.sText);
	}

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

	if(gB_Zones && (Shavit_ZoneExists(Zone_End, track) || gB_KZMap))
	{
		if(Shavit_StopTimer(client, false))
		{
			Call_StartForward(gH_Forwards_OnEnd);
			Call_PushCell(client);
			Call_PushCell(track);
			Call_Finish();
		}
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "EndZoneUndefined", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

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

		Shavit_PrintToChat(client, "%T", "MessageUnpause", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	else
	{
		if((iFlags & CPR_NotOnGround) > 0)
		{
			Shavit_PrintToChat(client, "%T", "PauseNotOnGround", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

			return Plugin_Handled;
		}

		if((iFlags & CPR_Moving) > 0)
		{
			Shavit_PrintToChat(client, "%T", "PauseMoving", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

			return Plugin_Handled;
		}

		if((iFlags & CPR_Duck) > 0)
		{
			Shavit_PrintToChat(client, "%T", "PauseDuck", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

			return Plugin_Handled;
		}

		GetClientAbsOrigin(client, gF_PauseOrigin[client]);
		GetClientEyeAngles(client, gF_PauseAngles[client]);
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", gF_PauseVelocity[client]);

		PauseTimer(client);

		Shavit_PrintToChat(client, "%T", "MessagePause", client, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
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
		if(gB_WR)
		{
			Shavit_WR_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all records for %s.", gS_DeleteMap[client]);
		}

		if(gB_Zones)
		{
			Shavit_Zones_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all zones for %s.", gS_DeleteMap[client]);
		}

		if(gB_Replay)
		{
			Shavit_Replay_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all replay data for %s.", gS_DeleteMap[client]);
		}

		if(gB_Rankings)
		{
			Shavit_Rankings_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all rankings for %s.", gS_DeleteMap[client]);
		}

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
		gI_WipePlayerID[client] = SteamIDToAuth(sArgString);

		if(gI_WipePlayerID[client] <= 0)
		{
			Shavit_PrintToChat(client, "Entered SteamID (%s) is invalid. The range for valid SteamIDs is [U:1:1] to [U:1:2147483647].", sArgString);

			return Plugin_Handled;
		}

		char sAlphabet[] = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#";
		strcopy(gS_Verification[client], 8, "");

		for(int i = 0; i < 5; i++)
		{
			gS_Verification[client][i] = sAlphabet[GetRandomInt(0, sizeof(sAlphabet) - 1)];
		}

		Shavit_PrintToChat(client, "Preparing to delete all user data for SteamID %s[U:1:%d]%s. To confirm, enter %s!wipeplayer %s",
			gS_ChatStrings.sVariable, gI_WipePlayerID[client], gS_ChatStrings.sText, gS_ChatStrings.sVariable2, gS_Verification[client]);
	}

	else
	{
		Shavit_PrintToChat(client, "Deleting data for SteamID %s[U:1:%d]%s...",
			gS_ChatStrings.sVariable, gI_WipePlayerID[client], gS_ChatStrings.sText);

		DeleteUserData(client, gI_WipePlayerID[client]);

		strcopy(gS_Verification[client], 8, "");
		gI_WipePlayerID[client] = -1;
	}

	return Plugin_Handled;
}

public void Trans_DeleteRestOfUserSuccess(Database db, DataPack hPack, int numQueries, DBResultSet[] results, any[] queryData)
{
	hPack.Reset();
	int client = hPack.ReadCell();
	int iSteamID = hPack.ReadCell();
	delete hPack;

	if(gB_WR)
	{
		Shavit_ReloadLeaderboards();
	}

	Shavit_LogMessage("%L - wiped user data for [U:1:%d].", client, iSteamID);
	Shavit_PrintToChat(client, "Finished wiping timer data for user %s[U:1:%d]%s.", gS_ChatStrings.sVariable, iSteamID, gS_ChatStrings.sText);
}

public void Trans_DeleteRestOfUserFailed(Database db, DataPack hPack, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	hPack.Reset();
	hPack.ReadCell();
	int iSteamID = hPack.ReadCell();
	delete hPack;
	LogError("Timer error! Failed to wipe user data (wipe | delete user data/times, id [U:1:%d]). Reason: %s", iSteamID, error);
}

void DeleteRestOfUser(int iSteamID, DataPack hPack)
{
	Transaction2 hTransaction = new Transaction2();
	char sQuery[256];

	FormatEx(sQuery, 256, "DELETE FROM %splayertimes WHERE auth = %d;", gS_MySQLPrefix, iSteamID);
	hTransaction.AddQuery(sQuery);
	FormatEx(sQuery, 256, "DELETE FROM %susers WHERE auth = %d;", gS_MySQLPrefix, iSteamID);
	hTransaction.AddQuery(sQuery);

	gH_SQL.Execute(hTransaction, Trans_DeleteRestOfUserSuccess, Trans_DeleteRestOfUserFailed, hPack);
}

void DeleteUserData(int client, const int iSteamID)
{
	DataPack hPack = new DataPack();
	hPack.WriteCell(client);
	hPack.WriteCell(iSteamID);
	char sQuery[512];

	if(gB_WR)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"SELECT id, style, track, map FROM %swrs WHERE auth = %d;",
			gS_MySQLPrefix, iSteamID);

		gH_SQL.Query(SQL_DeleteUserData_GetRecords_Callback, sQuery, hPack, DBPrio_High);
	}
	else
	{
		DeleteRestOfUser(iSteamID, hPack);
	}
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

	Menu menu = new Menu(StyleMenu_Handler);
	menu.SetTitle("%T", "StyleMenuTitle", client);

	for(int i = 0; i < gI_Styles; i++)
	{
		int iStyle = gI_OrderedStyles[i];

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
			gSM_StyleKeys[iStyle].GetString("name", sName, 64);
			FormatEx(sDisplay, 64, "%T %s", "StyleUnranked", client, sName);
		}

		else
		{
			float time = 0.0;

			if(gB_WR)
			{
				time = Shavit_GetWorldRecord(iStyle, gA_Timers[client].iTimerTrack);
			}

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
				gSM_StyleKeys[iStyle].GetString("name", sName, 64);
				FormatEx(sDisplay, 64, "%s - %s: %s", sName, sWR, sTime);
			}

			else
			{
				gSM_StyleKeys[iStyle].GetString("name", sDisplay, 64);
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
	Call_StartForward(gH_Forwards_OnTrackChanged);
	Call_PushCell(client);
	Call_PushCell(oldtrack);
	Call_PushCell(newtrack);
	Call_Finish();

	if (oldtrack == Track_Main && oldtrack != newtrack && !DoIHateMain(client))
	{
		Shavit_PrintToChat(client, "%T", "TrackChangeFromMain", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
}

void CallOnStyleChanged(int client, int oldstyle, int newstyle, bool manual, bool nofoward=false)
{
	if (!nofoward)
	{
		Call_StartForward(gH_Forwards_OnStyleChanged);
		Call_PushCell(client);
		Call_PushCell(oldstyle);
		Call_PushCell(newstyle);
		Call_PushCell(gA_Timers[client].iTimerTrack);
		Call_PushCell(manual);
		Call_Finish();
	}

	gA_Timers[client].bsStyle = newstyle;

	float fNewTimescale = GetStyleSettingFloat(newstyle, "timescale");

	if (gA_Timers[client].fTimescale != fNewTimescale && fNewTimescale > 0.0)
	{
		CallOnTimescaleChanged(client, gA_Timers[client].fTimescale, fNewTimescale);
		gA_Timers[client].fTimescale = fNewTimescale;
	}

	UpdateStyleSettings(client);

	float newLaggedMovement = fNewTimescale * GetStyleSettingFloat(newstyle, "speed");
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", newLaggedMovement); // might be problematic with the shavit-kz stuff TODO

	if (gB_Eventqueuefix)
	{
		SetEventsTimescale(client, newLaggedMovement);
	}

	SetEntityGravity(client, GetStyleSettingFloat(newstyle, "gravity"));
}

void CallOnTimescaleChanged(int client, float oldtimescale, float newtimescale)
{
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
		if(!Shavit_StopTimer(client, false))
		{
			return;
		}

		char sName[64];
		gSM_StyleKeys[style].GetString("name", sName, 64);

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

	if (gCV_AllowTimerWithoutZone.BoolValue || (gB_Zones && (Shavit_ZoneExists(Zone_Start, gA_Timers[client].iTimerTrack) || gB_KZMap)))
	{
		Shavit_StopTimer(client, true);
		Call_StartForward(gH_Forwards_OnRestart);
		Call_PushCell(client);
		Call_PushCell(gA_Timers[client].iTimerTrack);
		Call_Finish();
	}

	char sStyle[4];
	IntToString(style, sStyle, 4);

	SetClientCookie(client, gH_StyleCookie, sStyle);
}

// used as an alternative for games where player_jump isn't a thing, such as TF2
public void Bunnyhop_OnLeaveGround(int client, bool jumped, bool ladder)
{
	if(gB_HookedJump || !jumped || ladder)
	{
		return;
	}

	DoJump(client);
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
	if (gEV_Type != Engine_TF2 && (GetStyleSettingBool(gA_Timers[client].bsStyle, "easybhop")) || Shavit_InsideZone(client, Zone_Easybhop, gA_Timers[client].iTimerTrack))
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

	if(GetStyleSettingBool(style, "force_timescale"))
	{
		float mod = gA_Timers[client].fTimescale * GetStyleSettingFloat(gA_Timers[client].bsStyle, "speed");
		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", mod);

		if (gB_Eventqueuefix)
		{
			SetEventsTimescale(client, mod);
		}
	}

	float fAbsVelocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);

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

public int Native_GetOrderedStyles(Handle handler, int numParams)
{
	return SetNativeArray(1, gI_OrderedStyles, GetNativeCell(2));
}

public int Native_GetDatabase(Handle handler, int numParams)
{
	return view_as<int>(CloneHandle(gH_SQL, handler));
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
	return GetTimerStatus(GetNativeCell(1));
}

public int Native_HasStyleAccess(Handle handler, int numParams)
{
	int style = GetNativeCell(2);

	if(GetStyleSettingBool(style, "inaccessible") || GetStyleSettingInt(style, "enabled") <= 0)
	{
		return false;
	}

	return CheckCommandAccess(GetNativeCell(1), (strlen(gS_StyleOverride[style]) > 0)? gS_StyleOverride[style]:"<none>", gI_StyleFlag[style]);
}

public int Native_IsKZMap(Handle handler, int numParams)
{
	return view_as<bool>(gB_KZMap);
}

public int Native_StartTimer(Handle handler, int numParams)
{
	StartTimer(GetNativeCell(1), GetNativeCell(2));
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

	if (Shavit_InsideZone(client, Zone_Start, gA_Timers[client].iTimerTrack))
	{
		iFlags |= CPR_InStartZone;
	}

	if (Shavit_InsideZone(client, Zone_End, gA_Timers[client].iTimerTrack))
	{
		iFlags |= CPR_InEndZone;
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

public int Native_FinishMap(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int timestamp = GetTime();

	if(gCV_UseOffsets.BoolValue)
	{
		CalculateTickIntervalOffset(client, Zone_End);

		if(gCV_DebugOffsets.BoolValue)
		{
			char sOffsetMessage[100];
			char sOffsetDistance[8];
			FormatEx(sOffsetDistance, 8, "%.1f", gA_Timers[client].fDistanceOffset[Zone_End]);
			FormatEx(sOffsetMessage, sizeof(sOffsetMessage), "[END] %T %d", "DebugOffsets", client, gA_Timers[client].fZoneOffset[Zone_End], sOffsetDistance, gA_Timers[client].iZoneIncrement);
			Shavit_PrintToChat(client, "%s", sOffsetMessage);
		}
	}

	gA_Timers[client].fCurrentTime = (gA_Timers[client].fTimescaledTicks + gA_Timers[client].fZoneOffset[Zone_Start] + gA_Timers[client].fZoneOffset[Zone_End]) * GetTickInterval();

	timer_snapshot_t snapshot;
	BuildSnapshot(client, snapshot);

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_FinishPre);
	Call_PushCell(client);
	Call_PushArrayEx(snapshot, sizeof(timer_snapshot_t), SM_PARAM_COPYBACK);
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}

#if DEBUG
	float offset = (gA_Timers[client].fZoneOffset[Zone_Start] + gA_Timers[client].fZoneOffset[Zone_End]) * GetTickInterval();
	PrintToServer("0x%X %f -- ticks*interval -- offsettime=%f ticks=%.0f", snapshot.fCurrentTime, snapshot.fCurrentTime, offset, snapshot.fTimescaledTicks);
#endif

	Call_StartForward(gH_Forwards_Finish);
	Call_PushCell(client);

	int style = 0;
	int track = Track_Main;
	float perfs = 100.0;

	if(result == Plugin_Continue)
	{
		Call_PushCell(style = gA_Timers[client].bsStyle);
		Call_PushCell(gA_Timers[client].fCurrentTime);
		Call_PushCell(gA_Timers[client].iJumps);
		Call_PushCell(gA_Timers[client].iStrafes);
		//gross
		Call_PushCell((GetStyleSettingBool(gA_Timers[client].bsStyle, "sync"))? (gA_Timers[client].iGoodGains == 0)? 0.0:(gA_Timers[client].iGoodGains / float(gA_Timers[client].iTotalMeasures) * 100.0):-1.0);
		Call_PushCell(track = gA_Timers[client].iTimerTrack);
		perfs = (gA_Timers[client].iMeasuredJumps == 0)? 100.0:(gA_Timers[client].iPerfectJumps / float(gA_Timers[client].iMeasuredJumps) * 100.0);
	}
	else
	{
		Call_PushCell(style = snapshot.bsStyle);
		Call_PushCell(snapshot.fCurrentTime);
		Call_PushCell(snapshot.iJumps);
		Call_PushCell(snapshot.iStrafes);
		// gross
		Call_PushCell((GetStyleSettingBool(snapshot.bsStyle, "sync"))? (snapshot.iGoodGains == 0)? 0.0:(snapshot.iGoodGains / float(snapshot.iTotalMeasures) * 100.0):-1.0);
		Call_PushCell(track = snapshot.iTimerTrack);
		perfs = (snapshot.iMeasuredJumps == 0)? 100.0:(snapshot.iPerfectJumps / float(snapshot.iMeasuredJumps) * 100.0);
	}

	float oldtime = 0.0;

	if(gB_WR)
	{
		oldtime = Shavit_GetClientPB(client, style, track);
	}

	Call_PushCell(oldtime);
	Call_PushCell(perfs);

	if(result == Plugin_Continue)
	{
		Call_PushCell(gA_Timers[client].fAvgVelocity);
		Call_PushCell(gA_Timers[client].fMaxVelocity);
	}
	else
	{
		Call_PushCell(snapshot.fAvgVelocity);
		Call_PushCell(snapshot.fMaxVelocity);
	}

	Call_PushCell(timestamp);
	Call_Finish();

	StopTimer(client);
}

public int Native_PauseTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	GetClientAbsOrigin(client, gF_PauseOrigin[client]);
	GetClientEyeAngles(client, gF_PauseAngles[client]);
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", gF_PauseVelocity[client]);

	PauseTimer(client);
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
}

public int Native_StopChatSound(Handle handler, int numParams)
{
	gB_StopChatSound = true;
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
}

public int Native_PrintToChat(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	return SemiNative_PrintToChat(client, 2);
}

public int SemiNative_PrintToChat(int client, int formatParam)
{
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
	// strlen(sBuffer)>252 is when CSS stops printing the messages
	FormatEx(sBuffer, (gB_Protobuf ? sizeof(sBuffer) : 253), "%s%s%s %s%s", (gB_Protobuf ? " ":""), sTime, gS_ChatStrings.sPrefix, gS_ChatStrings.sText, sInput);

	if(client == 0)
	{
		PrintToServer("%s", sBuffer);

		return false;
	}

	if(!IsClientInGame(client))
	{
		gB_StopChatSound = false;

		return false;
	}

	Handle hSayText2 = StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);

	if(gB_Protobuf)
	{
		Protobuf pbmsg = UserMessageToProtobuf(hSayText2);
		pbmsg.SetInt("ent_idx", client);
		pbmsg.SetBool("chat", !(gB_StopChatSound || gCV_NoChatSound.BoolValue));
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
		bfmsg.WriteByte(!(gB_StopChatSound || gCV_NoChatSound.BoolValue));
		bfmsg.WriteString(sBuffer);
	}

	EndMessage();

	gB_StopChatSound = false;

	return true;
}

public int Native_RestartTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);

	Shavit_StopTimer(client, true);

	Call_StartForward(gH_Forwards_OnRestart);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_Finish();

	if(gCV_AllowTimerWithoutZone.BoolValue || !gB_Zones)
	{
		StartTimer(client, track);
	}
}

public int Native_GetPerfectJumps(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	return view_as<int>((gA_Timers[client].iMeasuredJumps == 0)? 100.0:(gA_Timers[client].iPerfectJumps / float(gA_Timers[client].iMeasuredJumps) * 100.0));
}

public int Native_GetStrafeCount(Handle handler, int numParams)
{
	return gA_Timers[GetNativeCell(1)].iStrafes;
}

public int Native_GetSync(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	return view_as<int>((GetStyleSettingBool(gA_Timers[client].bsStyle, "sync")? (gA_Timers[client].iGoodGains == 0)? 0.0:(gA_Timers[client].iGoodGains / float(gA_Timers[client].iTotalMeasures) * 100.0):-1.0));
}

public int Native_GetStyleCount(Handle handler, int numParams)
{
	return (gI_Styles > 0)? gI_Styles:-1;
}

public int Native_GetStyleStrings(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int type = GetNativeCell(2);
	int size = GetNativeCell(4);
	char sValue[128];

	switch(type)
	{
		case sStyleName:
		{
			gSM_StyleKeys[style].GetString("name", sValue, size);
		}
		case sShortName:
		{
			gSM_StyleKeys[style].GetString("shortname", sValue, size);
		}
		case sHTMLColor:
		{
			gSM_StyleKeys[style].GetString("htmlcolor", sValue, size);
		}
		case sChangeCommand:
		{
			gSM_StyleKeys[style].GetString("command", sValue, size);
		}
		case sClanTag:
		{
			gSM_StyleKeys[style].GetString("clantag", sValue, size);
		}
		case sSpecialString:
		{
			gSM_StyleKeys[style].GetString("specialstring", sValue, size);
		}
		case sStylePermission:
		{
			gSM_StyleKeys[style].GetString("permission", sValue, size);
		}
		default:
		{
			return -1;
		}
	}

	return SetNativeString(3, sValue, size);
}

public int Native_GetStyleStringsStruct(Handle plugin, int numParams)
{
	int style = GetNativeCell(1);

	if (GetNativeCell(3) != sizeof(stylestrings_t))
	{
		return ThrowNativeError(200, "stylestrings_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins", GetNativeCell(3), sizeof(stylestrings_t));
	}

	stylestrings_t strings;
	gSM_StyleKeys[style].GetString("name", strings.sStyleName, sizeof(strings.sStyleName));
	gSM_StyleKeys[style].GetString("shortname", strings.sShortName, sizeof(strings.sShortName));
	gSM_StyleKeys[style].GetString("htmlcolor", strings.sHTMLColor, sizeof(strings.sHTMLColor));
	gSM_StyleKeys[style].GetString("command", strings.sChangeCommand, sizeof(strings.sChangeCommand));
	gSM_StyleKeys[style].GetString("clantag", strings.sClanTag, sizeof(strings.sClanTag));
	gSM_StyleKeys[style].GetString("specialstring", strings.sSpecialString, sizeof(strings.sSpecialString));
	gSM_StyleKeys[style].GetString("permission", strings.sStylePermission, sizeof(strings.sStylePermission));

	return SetNativeArray(2, strings, sizeof(stylestrings_t));
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

	if(alert && practice && !gA_Timers[client].bPracticeMode && (!gB_HUD || (Shavit_GetHUDSettings(client) & HUD_NOPRACALERT) == 0))
	{
		Shavit_PrintToChat(client, "%T", "PracticeModeAlert", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	gA_Timers[client].bPracticeMode = practice;
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

	if (gA_Timers[client].iTimerTrack != snapshot.iTimerTrack)
	{
		CallOnTrackChanged(client, gA_Timers[client].iTimerTrack, snapshot.iTimerTrack);
	}

	gA_Timers[client].iTimerTrack = snapshot.iTimerTrack;

	if (gA_Timers[client].bsStyle != snapshot.bsStyle && Shavit_HasStyleAccess(client, snapshot.bsStyle))
	{
		CallOnStyleChanged(client, gA_Timers[client].bsStyle, snapshot.bsStyle, false);
	}

	gA_Timers[client] = snapshot;
	gA_Timers[client].bClientPaused = snapshot.bClientPaused && snapshot.bTimerEnabled;
	gA_Timers[client].fTimescale = (snapshot.fTimescale > 0.0) ? snapshot.fTimescale : 1.0;

	return 0;
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
}

public int Native_MarkKZMap(Handle handler, int numParams)
{
	gB_KZMap = true;
}

public int Native_GetClientTimescale(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	if (gA_Timers[client].fTimescale == GetStyleSettingFloat(gA_Timers[client].bsStyle, "timescale"))
	{
		return view_as<int>(-1.0);
	}

	return view_as<int>(gA_Timers[client].fTimescale);
}

public int Native_SetClientTimescale(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	float timescale = GetNativeCell(2);

	if (timescale != gA_Timers[client].fTimescale && timescale > 0.0)
	{
		CallOnTimescaleChanged(client, gA_Timers[client].fTimescale, timescale);
		gA_Timers[client].fTimescale = timescale;
	}
}

public int Native_GetStyleSetting(Handle handler, int numParams)
{
	int style = GetNativeCell(1);

	char sKey[256];
	GetNativeString(2, sKey, 256);

	int maxlength = GetNativeCell(4);
	
	char sValue[256];
	bool ret = gSM_StyleKeys[style].GetString(sKey, sValue, maxlength);

	SetNativeString(3, sValue, maxlength);
	return ret;
}

public int Native_GetStyleSettingInt(Handle handler, int numParams)
{
	int style = GetNativeCell(1);

	char sKey[256];
	GetNativeString(2, sKey, 256);

	return GetStyleSettingInt(style, sKey);
}

int GetStyleSettingInt(int style, char[] key)
{
	char sValue[16];
	gSM_StyleKeys[style].GetString(key, sValue, 16);
	return StringToInt(sValue);
}

public int Native_GetStyleSettingBool(Handle handler, int numParams)
{
	int style = GetNativeCell(1);

	char sKey[256];
	GetNativeString(2, sKey, 256);

	return GetStyleSettingBool(style, sKey);
}

bool GetStyleSettingBool(int style, char[] key)
{
	return GetStyleSettingInt(style, key) != 0;
}

public any Native_GetStyleSettingFloat(Handle handler, int numParams)
{
	int style = GetNativeCell(1);

	char sKey[256];
	GetNativeString(2, sKey, 256);

	return GetStyleSettingFloat(style, sKey);
}

float GetStyleSettingFloat(int style, char[] key)
{
	char sValue[16];
	gSM_StyleKeys[style].GetString(key, sValue, 16);
	return StringToFloat(sValue);
}

public any Native_HasStyleSetting(Handle handler, int numParams)
{
	// TODO: replace with sm 1.11 StringMap.ContainsKey
	int style = GetNativeCell(1);

	char sKey[256];
	GetNativeString(2, sKey, 256);

	return HasStyleSetting(style, sKey);
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
}

public any Native_SetMaxVelocity(Handle plugin, int numParams)
{
	gA_Timers[GetNativeCell(1)].fMaxVelocity = GetNativeCell(2);
}

bool HasStyleSetting(int style, char[] key)
{
	char sValue[1];
	return gSM_StyleKeys[style].GetString(key, sValue, 1);
}

public any Native_SetStyleSetting(Handle handler, int numParams)
{
	int style = GetNativeCell(1);

	char sKey[256];
	GetNativeString(2, sKey, 256);

	char sValue[256];
	GetNativeString(3, sValue, 256);

	bool replace = GetNativeCell(4);

	return gSM_StyleKeys[style].SetString(sKey, sValue, replace);
}

public any Native_SetStyleSettingFloat(Handle handler, int numParams)
{
	int style = GetNativeCell(1);

	char sKey[256];
	GetNativeString(2, sKey, 256);

	float fValue = GetNativeCell(3);

	char sValue[16];
	FloatToString(fValue, sValue, 16);

	bool replace = GetNativeCell(4);

	return gSM_StyleKeys[style].SetString(sKey, sValue, replace);
}

public any Native_SetStyleSettingBool(Handle handler, int numParams)
{
	int style = GetNativeCell(1);

	char sKey[256];
	GetNativeString(2, sKey, 256);

	bool value = GetNativeCell(3);

	bool replace = GetNativeCell(4);

	return gSM_StyleKeys[style].SetString(sKey, value ? "1" : "0", replace);
}

public any Native_SetStyleSettingInt(Handle handler, int numParams)
{
	int style = GetNativeCell(1);

	char sKey[256];
	GetNativeString(2, sKey, 256);

	int value = GetNativeCell(3);

	char sValue[16];
	IntToString(value, sValue, 16);

	bool replace = GetNativeCell(4);

	return gSM_StyleKeys[style].SetString(sKey, sValue, replace);
}

public Action Shavit_OnStartPre(int client, int track)
{
	if (GetTimerStatus(client) == view_as<int>(Timer_Paused) && gCV_PauseMovement.BoolValue)
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

int GetTimerStatus(int client)
{
	if (!gA_Timers[client].bTimerEnabled)
	{
		return view_as<int>(Timer_Stopped);
	}
	else if (gA_Timers[client].bClientPaused)
	{
		return view_as<int>(Timer_Paused);
	}

	return view_as<int>(Timer_Running);
}

void StartTimer(int client, int track)
{
	if(!IsValidClient(client, true) || GetClientTeam(client) < 2 || IsFakeClient(client) || !gB_CookiesRetrieved[client])
	{
		return;
	}

	float fSpeed[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);
	float curVel = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));

	if (!gCV_NoZAxisSpeed.BoolValue ||
		GetStyleSettingInt(gA_Timers[client].bsStyle, "prespeed") == 1 ||
		(fSpeed[2] == 0.0 && (GetStyleSettingInt(gA_Timers[client].bsStyle, "prespeed") == 2 || curVel <= 290.0)))
	{
		Action result = Plugin_Continue;
		Call_StartForward(gH_Forwards_StartPre);
		Call_PushCell(client);
		Call_PushCell(track);
		Call_Finish(result);

		if(result == Plugin_Continue)
		{
			Call_StartForward(gH_Forwards_Start);
			Call_PushCell(client);
			Call_PushCell(track);
			Call_Finish(result);

			if (gA_Timers[client].bClientPaused)
			{
				//SetEntityMoveType(client, MOVETYPE_WALK);
			}

			gA_Timers[client].iZoneIncrement = 0;
			gA_Timers[client].fTimescaledTicks = 0.0;
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
			gA_Timers[client].iSHSWCombination = -1;
			gA_Timers[client].fCurrentTime = 0.0;
			gA_Timers[client].bPracticeMode = false;
			gA_Timers[client].iMeasuredJumps = 0;
			gA_Timers[client].iPerfectJumps = 0;
			gA_Timers[client].bCanUseAllKeys = false;
			gA_Timers[client].fZoneOffset[Zone_Start] = 0.0;
			gA_Timers[client].fZoneOffset[Zone_End] = 0.0;
			gA_Timers[client].fDistanceOffset[Zone_Start] = 0.0;
			gA_Timers[client].fDistanceOffset[Zone_End] = 0.0;
			gA_Timers[client].fAvgVelocity = curVel;
			gA_Timers[client].fMaxVelocity = curVel;

			float mod = gA_Timers[client].fTimescale * GetStyleSettingFloat(gA_Timers[client].bsStyle, "speed");
			SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", mod);

			if (gB_Eventqueuefix)
			{
				SetEventsTimescale(client, mod);
			}

			SetEntityGravity(client, GetStyleSettingFloat(gA_Timers[client].bsStyle, "gravity"));
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

		if(0 <= newstyle < gI_Styles)
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

	if(!IsClientConnected(client) || IsFakeClient(client))
	{
		return;
	}

	gB_Auto[client] = true;
	gA_Timers[client].fStrafeWarning = 0.0;
	gA_Timers[client].bPracticeMode = false;
	gA_Timers[client].iSHSWCombination = -1;
	gA_Timers[client].iTimerTrack = 0;
	gA_Timers[client].bsStyle = 0;
	gA_Timers[client].fTimescale = 1.0;
	gA_Timers[client].fTimescaledTicks = 0.0;
	gA_Timers[client].iZoneIncrement = 0;
	gS_DeleteMap[client][0] = 0;

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

	int iSteamID = GetSteamAccountID(client);

	if(iSteamID == 0)
	{
		KickClient(client, "%T", "VerificationFailed", client);

		return;
	}

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);
	ReplaceString(sName, MAX_NAME_LENGTH, "#", "?"); // to avoid this: https://user-images.githubusercontent.com/3672466/28637962-0d324952-724c-11e7-8b27-15ff021f0a59.png

	int iLength = ((strlen(sName) * 2) + 1);
	char[] sEscapedName = new char[iLength];
	gH_SQL.Escape(sName, sEscapedName, iLength);

	char sIPAddress[64];
	GetClientIP(client, sIPAddress, 64);
	int iIPAddress = IPStringToAddress(sIPAddress);

	int iTime = GetTime();

	char sQuery[512];

	if(gB_MySQL)
	{
		FormatEx(sQuery, 512,
			"INSERT INTO %susers (auth, name, ip, lastlogin) VALUES (%d, '%s', %d, %d) ON DUPLICATE KEY UPDATE name = '%s', ip = %d, lastlogin = %d;",
			gS_MySQLPrefix, iSteamID, sEscapedName, iIPAddress, iTime, sEscapedName, iIPAddress, iTime);
	}

	else
	{
		FormatEx(sQuery, 512,
			"REPLACE INTO %susers (auth, name, ip, lastlogin) VALUES (%d, '%s', %d, %d);",
			gS_MySQLPrefix, iSteamID, sEscapedName, iIPAddress, iTime);
	}

	gH_SQL.Query(SQL_InsertUser_Callback, sQuery, GetClientSerial(client));
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

bool LoadStyles()
{
	for(int i = 0; i < STYLE_LIMIT; i++)
	{
		delete gSM_StyleKeys[i];
	}

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-styles.cfg");

	SMCParser parser = new SMCParser();
	parser.OnEnterSection = OnStyleEnterSection;
	parser.OnLeaveSection = OnStyleLeaveSection;
	parser.OnKeyValue = OnStyleKeyValue;
	parser.ParseFile(sPath);
	delete parser;

	for (int i = 0; i < gI_Styles; i++)
	{
		if (gSM_StyleKeys[i] == null)
		{
			SetFailState("Missing style index %d. Highest index is %d. Fix addons/sourcemod/configs/shavit-styles.cfg", i, gI_Styles-1);
		}
	}

	gB_Registered = true;

	SortCustom1D(gI_OrderedStyles, gI_Styles, SortAscending_StyleOrder);

	Call_StartForward(gH_Forwards_OnStyleConfigLoaded);
	Call_PushCell(gI_Styles);
	Call_Finish();

	return true;
}

public SMCResult OnStyleEnterSection(SMCParser smc, const char[] name, bool opt_quotes)
{
	// styles key
	if(!IsCharNumeric(name[0]))
	{
		return SMCParse_Continue;
	}

	gI_CurrentParserIndex = StringToInt(name);

	if (gSM_StyleKeys[gI_CurrentParserIndex] != null)
	{
		SetFailState("Style index %d (%s) already parsed. Stop using the same index for multiple styles. Fix addons/sourcemod/configs/shavit-styles.cfg", gI_CurrentParserIndex, name);
	}

	if (gI_CurrentParserIndex >= STYLE_LIMIT)
	{
		SetFailState("Style index %d (%s) too high (limit %d). Fix addons/sourcemod/configs/shavit-styles.cfg", gI_CurrentParserIndex, name, STYLE_LIMIT);
	}

	if(gI_Styles <= gI_CurrentParserIndex)
	{
		gI_Styles = gI_CurrentParserIndex + 1;
	}

	gSM_StyleKeys[gI_CurrentParserIndex] = new StringMap();

	gSM_StyleKeys[gI_CurrentParserIndex].SetString("name", "<MISSING STYLE NAME>");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("shortname", "<MISSING SHORT STYLE NAME>");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("htmlcolor", "<MISSING STYLE HTML COLOR>");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("command", "");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("clantag", "<MISSING STYLE CLAN TAG>");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("specialstring", "");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("permission", "");

	gSM_StyleKeys[gI_CurrentParserIndex].SetString("autobhop", "1");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("easybhop", "1");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("prespeed", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("velocity_limit", "0.0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("airaccelerate", "1000.0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("bunnyhopping", "1");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("runspeed", "260.00");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("gravity", "1.0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("speed", "1.0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("halftime", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("timescale", "1.0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("velocity", "1.0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("bonus_velocity", "0.0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("min_velocity", "0.0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("jump_multiplier", "0.0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("jump_bonus", "0.0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("block_w", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("block_a", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("block_s", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("block_d", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("block_use", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("force_hsw", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("block_pleft", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("block_pright", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("block_pstrafe", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("unranked", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("noreplay", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("sync", "1");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("strafe_count_w", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("strafe_count_a", "1");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("strafe_count_s", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("strafe_count_d", "1");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("rankingmultiplier", "1.00");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("special", "0");

	char sOrder[4];
	IntToString(gI_CurrentParserIndex, sOrder, 4);
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("ordering", sOrder);

	gSM_StyleKeys[gI_CurrentParserIndex].SetString("inaccessible", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("enabled", "1");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("kzcheckpoints", "0");
	gSM_StyleKeys[gI_CurrentParserIndex].SetString("force_groundkeys", "0");

	gI_OrderedStyles[gI_CurrentParserIndex] = gI_CurrentParserIndex;

	return SMCParse_Continue;
}

public SMCResult OnStyleLeaveSection(SMCParser smc)
{
	if (gI_CurrentParserIndex == -1)
	{
		// OnStyleLeaveSection can be called back to back.
		// And does for when hitting the last style!
		// So we set gI_CurrentParserIndex to -1 at the end of this function.
		return;
	}

	// if this style is disabled, we will force certain settings
	if(GetStyleSettingInt(gI_CurrentParserIndex, "enabled") <= 0)
	{
		gSM_StyleKeys[gI_CurrentParserIndex].SetString("noreplay", "1");
		gSM_StyleKeys[gI_CurrentParserIndex].SetString("rankingmultiplier", "0");
		gSM_StyleKeys[gI_CurrentParserIndex].SetString("inaccessible", "1");
	}

	if(GetStyleSettingBool(gI_CurrentParserIndex, "halftime"))
	{
		gSM_StyleKeys[gI_CurrentParserIndex].SetString("timescale", "0.5");
	}

	if (GetStyleSettingFloat(gI_CurrentParserIndex, "timescale") <= 0.0)
	{
		gSM_StyleKeys[gI_CurrentParserIndex].SetString("timescale", "1.0");
	}

	// Setting it here so that we can reference the timescale setting.
	if(!HasStyleSetting(gI_CurrentParserIndex, "force_timescale"))
	{
		if(GetStyleSettingFloat(gI_CurrentParserIndex, "timescale") == 1.0)
		{
			gSM_StyleKeys[gI_CurrentParserIndex].SetString("force_timescale", "0");
		}
		
		else
		{
			gSM_StyleKeys[gI_CurrentParserIndex].SetString("force_timescale", "1");
		}
	}

	char sStyleCommand[128];
	gSM_StyleKeys[gI_CurrentParserIndex].GetString("command", sStyleCommand, 128);
	char sName[64];
	gSM_StyleKeys[gI_CurrentParserIndex].GetString("name", sName, 64);

	if(!gB_Registered && strlen(sStyleCommand) > 0 && !GetStyleSettingBool(gI_CurrentParserIndex, "inaccessible"))
	{
		char sStyleCommands[32][32];
		int iCommands = ExplodeString(sStyleCommand, ";", sStyleCommands, 32, 32, false);

		char sDescription[128];
		FormatEx(sDescription, 128, "Change style to %s.", sName);

		for(int x = 0; x < iCommands; x++)
		{
			TrimString(sStyleCommands[x]);
			StripQuotes(sStyleCommands[x]);

			char sCommand[32];
			FormatEx(sCommand, 32, "sm_%s", sStyleCommands[x]);

			gSM_StyleCommands.SetValue(sCommand, gI_CurrentParserIndex);

			RegConsoleCmd(sCommand, Command_StyleChange, sDescription);
		}
	}

	char sPermission[64];
	gSM_StyleKeys[gI_CurrentParserIndex].GetString("permission", sPermission, 64);

	if(StrContains(sPermission, ";") != -1)
	{
		char sText[2][32];
		int iCount = ExplodeString(sPermission, ";", sText, 2, 32);

		AdminFlag flag = Admin_Reservation;

		if(FindFlagByChar(sText[0][0], flag))
		{
			gI_StyleFlag[gI_CurrentParserIndex] = FlagToBit(flag);
		}

		strcopy(gS_StyleOverride[gI_CurrentParserIndex], 32, (iCount >= 2)? sText[1]:"");
	}

	else if(strlen(sPermission) > 0)
	{
		AdminFlag flag = Admin_Reservation;

		if(FindFlagByChar(sPermission[0], flag))
		{
			gI_StyleFlag[gI_CurrentParserIndex] = FlagToBit(flag);
		}
	}

	gI_CurrentParserIndex = -1;
}

public SMCResult OnStyleKeyValue(SMCParser smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes)
{
	gSM_StyleKeys[gI_CurrentParserIndex].SetString(key, value);
}

public int SortAscending_StyleOrder(int index1, int index2, const int[] array, any hndl)
{
	int iOrder1 = GetStyleSettingInt(index1, "ordering");
	int iOrder2 = GetStyleSettingInt(index2, "ordering");

	if(iOrder1 < iOrder2)
	{
		return -1;
	}

	else if(iOrder1 == iOrder2)
	{
		return 0;
	}

	else
	{
		return 1;
	}
}

public Action Command_StyleChange(int client, int args)
{
	char sCommand[128];
	GetCmdArg(0, sCommand, 128);

	int style = 0;

	if(gSM_StyleCommands.GetValue(sCommand, style))
	{
		ChangeClientStyle(client, style, true);

		return Plugin_Handled;
	}

	return Plugin_Continue;
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
	gH_SQL = GetTimerDatabaseHandle2();
	gB_MySQL = IsMySQLDatabase(gH_SQL);

	// support unicode names
	if(!gH_SQL.SetCharset("utf8mb4"))
	{
		gH_SQL.SetCharset("utf8");
	}

	CreateUsersTable();
}

public void SQL_CreateMigrationsTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Migrations table creation failed. Reason: %s", error);

		return;
	}

	char sQuery[128];
	FormatEx(sQuery, 128, "SELECT code FROM %smigrations;", gS_MySQLPrefix);

	gH_SQL.Query(SQL_SelectMigrations_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_SelectMigrations_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Migrations selection failed. Reason: %s", error);

		return;
	}

	// this is ugly, i know. but it works and is more elegant than previous solutions so.. let it be =)
	bool bMigrationApplied[255] = { false, ... };

	while(results.FetchRow())
	{
		bMigrationApplied[results.FetchInt(0)] = true;
	}

	for(int i = 0; i < MIGRATIONS_END; i++)
	{
		if(!bMigrationApplied[i])
		{
			gI_MigrationsRequired++;
			PrintToServer("--- Applying database migration %d ---", i);
			ApplyMigration(i);
		}
	}

	if (!gI_MigrationsRequired)
	{
		Call_StartForward(gH_Forwards_OnDatabaseLoaded);
		Call_Finish();
	}
}

void ApplyMigration(int migration)
{
	switch(migration)
	{
		case Migration_RemoveWorkshopMaptiers, Migration_RemoveWorkshopMapzones, Migration_RemoveWorkshopPlayertimes: ApplyMigration_RemoveWorkshopPath(migration);
		case Migration_LastLoginIndex: ApplyMigration_LastLoginIndex();
		case Migration_RemoveCountry: ApplyMigration_RemoveCountry();
		case Migration_ConvertIPAddresses: ApplyMigration_ConvertIPAddresses();
		case Migration_ConvertSteamIDsUsers: ApplyMigration_ConvertSteamIDs();
		case Migration_ConvertSteamIDsPlayertimes, Migration_ConvertSteamIDsChat: return; // this is confusing, but the above case handles all of them
		case Migration_PlayertimesDateToInt: ApplyMigration_PlayertimesDateToInt();
		case Migration_AddZonesFlagsAndData: ApplyMigration_AddZonesFlagsAndData();
		case Migration_AddPlayertimesCompletions: ApplyMigration_AddPlayertimesCompletions();
		case Migration_AddCustomChatAccess: ApplyMigration_AddCustomChatAccess();
		case Migration_AddPlayertimesExactTimeInt: ApplyMigration_AddPlayertimesExactTimeInt();
		case Migration_FixOldCompletionCounts: ApplyMigration_FixOldCompletionCounts();
		case Migration_AddPrebuiltToMapZonesTable: ApplyMigration_AddPrebuiltToMapZonesTable();
		case Migration_AddPlaytime: ApplyMigration_AddPlaytime();
		case Migration_Lowercase_maptiers: ApplyMigration_LowercaseMaps("maptiers", migration);
		case Migration_Lowercase_mapzones: ApplyMigration_LowercaseMaps("mapzones", migration);
		case Migration_Lowercase_playertimes: ApplyMigration_LowercaseMaps("playertimes", migration);
		case Migration_Lowercase_stagetimeswr: ApplyMigration_LowercaseMaps("stagetimewrs", migration);
		case Migration_Lowercase_startpositions: ApplyMigration_LowercaseMaps("startpositions", migration);
	}
}

void ApplyMigration_LastLoginIndex()
{
	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%susers` ADD INDEX `lastlogin` (`lastlogin`);", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_LastLoginIndex, DBPrio_High);
}

void ApplyMigration_RemoveCountry()
{
	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%susers` DROP COLUMN `country`;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_RemoveCountry, DBPrio_High);
}

void ApplyMigration_PlayertimesDateToInt()
{
	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%splayertimes` CHANGE COLUMN `date` `date` INT;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_PlayertimesDateToInt, DBPrio_High);
}

void ApplyMigration_AddZonesFlagsAndData()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%smapzones` ADD COLUMN `flags` INT NULL AFTER `track`, ADD COLUMN `data` INT NULL AFTER `flags`;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddZonesFlagsAndData, DBPrio_High);
}

void ApplyMigration_AddPlayertimesCompletions()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%splayertimes` ADD COLUMN `completions` SMALLINT DEFAULT 1 AFTER `perfs`;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddPlayertimesCompletions, DBPrio_High);
}

void ApplyMigration_AddCustomChatAccess()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%schat` ADD COLUMN `ccaccess` INT NOT NULL DEFAULT 0 AFTER `ccmessage`;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddCustomChatAccess, DBPrio_High);
}

void ApplyMigration_AddPlayertimesExactTimeInt()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%splayertimes` ADD COLUMN `exact_time_int` INT NOT NULL DEFAULT 0 AFTER `completions`;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddPlayertimesExactTimeInt, DBPrio_High);
}

void ApplyMigration_FixOldCompletionCounts()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "UPDATE `%splayertimes` SET completions = completions - 1 WHERE completions > 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_FixOldCompletionCounts, DBPrio_High);
}

void ApplyMigration_AddPrebuiltToMapZonesTable()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%smapzones` ADD COLUMN `prebuilt` BOOL;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddPrebuiltToMapZonesTable, DBPrio_High);
}

// double up on this migration because some people may have used shavit-playtime which uses INT but I want FLOAT
void ApplyMigration_AddPlaytime()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%susers` MODIFY COLUMN `playtime` FLOAT NOT NULL DEFAULT 0;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_Migration_AddPlaytime2222222_Callback, sQuery, Migration_AddPlaytime, DBPrio_High);
}

public void SQL_Migration_AddPlaytime2222222_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%susers` ADD COLUMN `playtime` FLOAT NOT NULL DEFAULT 0 AFTER `points`;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddPlaytime, DBPrio_High);
}

void ApplyMigration_LowercaseMaps(const char[] table, int migration)
{
	char sQuery[192];
	FormatEx(sQuery, 192, "UPDATE `%s%s` SET map = LOWER(map);", gS_MySQLPrefix, table);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, migration, DBPrio_High);
}

public void SQL_TableMigrationSingleQuery_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	InsertMigration(data);

	// i hate hardcoding REEEEEEEE
	if(data == Migration_ConvertSteamIDsChat)
	{
		char sQuery[256];
		// deleting rows that cause data integrity issues
		FormatEx(sQuery, 256,
			"DELETE t1 FROM %splayertimes t1 LEFT JOIN %susers t2 ON t1.auth = t2.auth WHERE t2.auth IS NULL;",
			gS_MySQLPrefix, gS_MySQLPrefix);
		gH_SQL.Query(SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);

		FormatEx(sQuery, 256,
			"ALTER TABLE `%splayertimes` ADD CONSTRAINT `%spt_auth` FOREIGN KEY (`auth`) REFERENCES `%susers` (`auth`) ON UPDATE CASCADE ON DELETE CASCADE;",
			gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix);
		gH_SQL.Query(SQL_TableMigrationIndexing_Callback, sQuery);

		FormatEx(sQuery, 256,
			"DELETE t1 FROM %schat t1 LEFT JOIN %susers t2 ON t1.auth = t2.auth WHERE t2.auth IS NULL;",
			gS_MySQLPrefix, gS_MySQLPrefix);
		gH_SQL.Query(SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);

		FormatEx(sQuery, 256,
			"ALTER TABLE `%schat` ADD CONSTRAINT `%sch_auth` FOREIGN KEY (`auth`) REFERENCES `%susers` (`auth`) ON UPDATE CASCADE ON DELETE CASCADE;",
			gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix);
		gH_SQL.Query(SQL_TableMigrationIndexing_Callback, sQuery);
	}
}

void ApplyMigration_ConvertIPAddresses(bool index = true)
{
	char sQuery[128];

	if(index)
	{
		FormatEx(sQuery, 128, "ALTER TABLE `%susers` ADD INDEX `ip` (`ip`);", gS_MySQLPrefix);
		gH_SQL.Query(SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);
	}

	FormatEx(sQuery, 128, "SELECT DISTINCT ip FROM %susers WHERE ip LIKE '%%.%%';", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationIPAddresses_Callback, sQuery);
}

public void SQL_TableMigrationIPAddresses_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if(results == null || results.RowCount == 0)
	{
		InsertMigration(Migration_ConvertIPAddresses);

		return;
	}

	Transaction2 hTransaction = new Transaction2();
	int iQueries = 0;

	while(results.FetchRow())
	{
		char sIPAddress[32];
		results.FetchString(0, sIPAddress, 32);

		char sQuery[256];
		FormatEx(sQuery, 256, "UPDATE %susers SET ip = %d WHERE ip = '%s';", gS_MySQLPrefix, IPStringToAddress(sIPAddress), sIPAddress);

		hTransaction.AddQuery(sQuery);

		if(++iQueries >= 10000)
		{
			break;
		}
	}

	gH_SQL.Execute(hTransaction, Trans_IPAddressMigrationSuccess, Trans_IPAddressMigrationFailed, iQueries);
}

public void Trans_IPAddressMigrationSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	// too many queries, don't do all at once to avoid server crash due to too many queries in the transaction
	if(data >= 10000)
	{
		ApplyMigration_ConvertIPAddresses(false);

		return;
	}

	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%susers` DROP INDEX `ip`;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);

	FormatEx(sQuery, 128, "ALTER TABLE `%susers` CHANGE COLUMN `ip` `ip` INT;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_ConvertIPAddresses, DBPrio_High);
}

public void Trans_IPAddressMigrationFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (core) error! IP address migration failed. Reason: %s", error);
}

void ApplyMigration_ConvertSteamIDs()
{
	char sTables[][] =
	{
		"users",
		"playertimes",
		"chat"
	};

	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%splayertimes` DROP CONSTRAINT `%spt_auth`;", gS_MySQLPrefix, gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);

	FormatEx(sQuery, 128, "ALTER TABLE `%schat` DROP CONSTRAINT `%sch_auth`;", gS_MySQLPrefix, gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);

	for(int i = 0; i < sizeof(sTables); i++)
	{
		DataPack hPack = new DataPack();
		hPack.WriteCell(Migration_ConvertSteamIDsUsers + i);
		hPack.WriteString(sTables[i]);

		FormatEx(sQuery, 128, "UPDATE %s%s SET auth = REPLACE(REPLACE(auth, \"[U:1:\", \"\"), \"]\", \"\") WHERE auth LIKE '[%%';", sTables[i], gS_MySQLPrefix);
		gH_SQL.Query(SQL_TableMigrationSteamIDs_Callback, sQuery, hPack, DBPrio_High);
	}
}

public void SQL_TableMigrationIndexing_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	// nothing
}

public void SQL_TableMigrationSteamIDs_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int iMigration = data.ReadCell();
	char sTable[16];
	data.ReadString(sTable, 16);
	delete data;

	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%s%s` CHANGE COLUMN `auth` `auth` INT;", gS_MySQLPrefix, sTable);
	gH_SQL.Query(SQL_TableMigrationSingleQuery_Callback, sQuery, iMigration, DBPrio_High);
}

void ApplyMigration_RemoveWorkshopPath(int migration)
{
	char sTables[][] =
	{
		"maptiers",
		"mapzones",
		"playertimes"
	};

	DataPack hPack = new DataPack();
	hPack.WriteCell(migration);
	hPack.WriteString(sTables[migration]);

	char sQuery[192];
	FormatEx(sQuery, 192, "SELECT map FROM %s%s WHERE map LIKE 'workshop%%' GROUP BY map;", gS_MySQLPrefix, sTables[migration]);
	gH_SQL.Query(SQL_TableMigrationWorkshop_Callback, sQuery, hPack, DBPrio_High);
}

public void SQL_TableMigrationWorkshop_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int iMigration = data.ReadCell();
	char sTable[16];
	data.ReadString(sTable, 16);
	delete data;

	if(results == null || results.RowCount == 0)
	{
		// no error logging here because not everyone runs the rankings/wr modules
		InsertMigration(iMigration);

		return;
	}

	Transaction2 hTransaction = new Transaction2();

	while(results.FetchRow())
	{
		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(0, sMap, sizeof(sMap));

		char sDisplayMap[PLATFORM_MAX_PATH];
		GetMapDisplayName(sMap, sDisplayMap, sizeof(sDisplayMap));

		char sQuery[256];
		FormatEx(sQuery, 256, "UPDATE %s%s SET map = '%s' WHERE map = '%s';", gS_MySQLPrefix, sTable, sDisplayMap, sMap);

		hTransaction.AddQuery(sQuery);
	}

	gH_SQL.Execute(hTransaction, Trans_WorkshopMigration, INVALID_FUNCTION, iMigration);
}

public void Trans_WorkshopMigration(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	InsertMigration(data);
}

void InsertMigration(int migration)
{
	char sQuery[128];
	FormatEx(sQuery, 128, "INSERT INTO %smigrations (code) VALUES (%d);", gS_MySQLPrefix, migration);
	gH_SQL.Query(SQL_MigrationApplied_Callback, sQuery, migration);
}

public void SQL_MigrationApplied_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (++gI_MigrationsFinished >= gI_MigrationsRequired)
	{
		gI_MigrationsRequired = gI_MigrationsFinished = 0;
		Call_StartForward(gH_Forwards_OnDatabaseLoaded);
		Call_Finish();
	}
}

void CreateUsersTable()
{
	char sQuery[512];

	if(gB_MySQL)
	{
		FormatEx(sQuery, 512,
			"CREATE TABLE IF NOT EXISTS `%susers` (`auth` INT NOT NULL, `name` VARCHAR(32) COLLATE 'utf8mb4_general_ci', `ip` INT, `lastlogin` INT NOT NULL DEFAULT -1, `points` FLOAT NOT NULL DEFAULT 0, `playtime` FLOAT NOT NULL DEFAULT 0, PRIMARY KEY (`auth`), INDEX `points` (`points`), INDEX `lastlogin` (`lastlogin`)) ENGINE=INNODB;",
			gS_MySQLPrefix);
	}

	else
	{
		FormatEx(sQuery, 512,
			"CREATE TABLE IF NOT EXISTS `%susers` (`auth` INT NOT NULL PRIMARY KEY, `name` VARCHAR(32), `ip` INT, `lastlogin` INTEGER NOT NULL DEFAULT -1, `points` FLOAT NOT NULL DEFAULT 0, `playtime` FLOAT NOT NULL DEFAULT 0);",
			gS_MySQLPrefix);
	}

	gH_SQL.Query(SQL_CreateUsersTable_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_CreateUsersTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Users' data table creation failed. Reason: %s", error);

		return;
	}

	// migrations will only exist for mysql. sorry sqlite users
	if(gB_MySQL)
	{
		char sQuery[128];
		FormatEx(sQuery, 128, "CREATE TABLE IF NOT EXISTS `%smigrations` (`code` TINYINT NOT NULL, UNIQUE INDEX `code` (`code`));", gS_MySQLPrefix);

		gH_SQL.Query(SQL_CreateMigrationsTable_Callback, sQuery, 0, DBPrio_High);
	}
	else
	{
		Call_StartForward(gH_Forwards_OnDatabaseLoaded);
		Call_Finish();
	}
}

public void Shavit_OnEnterZone(int client, int type, int track, int id, int entity)
{
	if(type == Zone_Airaccelerate)
	{
		gF_ZoneAiraccelerate[client] = float(Shavit_GetZoneData(id));

		UpdateAiraccelerate(client, gF_ZoneAiraccelerate[client]);
	}

	else if(type == Zone_CustomSpeedLimit)
	{
		gF_ZoneSpeedLimit[client] = float(Shavit_GetZoneData(id));
	}
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity)
{
	if(type == Zone_Airaccelerate)
	{
		UpdateAiraccelerate(client, GetStyleSettingFloat(gA_Timers[client].bsStyle, "airaccelerate"));
	}
}

public void PreThinkPost(int client)
{
	if(IsPlayerAlive(client))
	{
		if(!gB_Zones || !Shavit_InsideZone(client, Zone_Airaccelerate, -1))
		{
			sv_airaccelerate.FloatValue = GetStyleSettingFloat(gA_Timers[client].bsStyle, "airaccelerate");
		}
		else
		{
			sv_airaccelerate.FloatValue = gF_ZoneAiraccelerate[client];
		}

		if(sv_enablebunnyhopping != null)
		{
			sv_enablebunnyhopping.BoolValue = GetStyleSettingBool(gA_Timers[client].bsStyle, "bunnyhopping");
		}

		MoveType mtMoveType = GetEntityMoveType(client);

		if (GetStyleSettingFloat(gA_Timers[client].bsStyle, "gravity") != 1.0 &&
			(mtMoveType == MOVETYPE_WALK || mtMoveType == MOVETYPE_ISOMETRIC) &&
			(gA_Timers[client].iLastMoveType == MOVETYPE_LADDER || GetEntityGravity(client) == 1.0))
		{
			SetEntityGravity(client, GetStyleSettingFloat(gA_Timers[client].bsStyle, "gravity"));
		}

		gA_Timers[client].iLastMoveType = mtMoveType;
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

		if(!gCV_NoZAxisSpeed.BoolValue)
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
			Shavit_PrintToChat(client, "%s", sOffsetMessage);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "player_speedmod"))
	{
		gH_AcceptInput.HookEntity(Hook_Pre, entity, DHook_AcceptInput_player_speedmod);
	}
}

// bool CBaseEntity::AcceptInput(char  const*, CBaseEntity*, CBaseEntity*, variant_t, int)
public MRESReturn DHook_AcceptInput_player_speedmod(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	char buf[128];
	hParams.GetString(1, buf, sizeof(buf));

	if (!StrEqual(buf, "ModifySpeed") || hParams.IsNull(2))
	{
		return MRES_Ignored;
	}

	int activator = hParams.Get(2);

	if (!IsValidClient(activator, true))
	{
		return MRES_Ignored;
	}

	hParams.GetObjectVarString(4, 0, ObjectValueType_String, buf, sizeof(buf));

	float speed = StringToFloat(buf);
	int style = gA_Timers[activator].bsStyle;

	speed *= gA_Timers[activator].fTimescale * GetStyleSettingFloat(style, "speed");
	SetEntPropFloat(activator, Prop_Data, "m_flLaggedMovementValue", speed);

	#if DEBUG
	int caller = hParams.Get(3);
	PrintToServer("ModifySpeed activator = %d(%N), caller = %d, old_speed = %s, new_speed = %f", activator, activator, caller, buf, speed);
	#endif

	hReturn.Value = true;
	return MRES_Supercede;
}

bool GetCheckUntouch(int client)
{
	int flags = GetEntProp(client, Prop_Data, "m_iEFlags");
	return (flags & EFL_CHECK_UNTOUCH) != 0;
}

public MRESReturn DHook_ProcessMovement(Handle hParams)
{
	int client = DHookGetParam(hParams, 1);

	// Causes client to do zone touching in movement instead of server frames.
	// From https://github.com/rumourA/End-Touch-Fix
	if(GetCheckUntouch(client))
	{
		SDKCall(gH_PhysicsCheckForEntityUntouch, client);
	}

	Call_StartForward(gH_Forwards_OnProcessMovement);
	Call_PushCell(client);
	Call_Finish();

	return MRES_Ignored;
}

public MRESReturn DHook_ProcessMovementPost(Handle hParams)
{
	int client = DHookGetParam(hParams, 1);

	Call_StartForward(gH_Forwards_OnProcessMovementPost);
	Call_PushCell(client);
	Call_Finish();

	if (gA_Timers[client].bClientPaused || !gA_Timers[client].bTimerEnabled)
	{
		return MRES_Ignored;
	}

	float interval = GetTickInterval();
	float time = interval * gA_Timers[client].fTimescale;
	float timeOrig = time;

	gA_Timers[client].iZoneIncrement++;

	timer_snapshot_t snapshot;
	BuildSnapshot(client, snapshot);

	Call_StartForward(gH_Forwards_OnTimerIncrement);
	Call_PushCell(client);
	Call_PushArray(snapshot, sizeof(timer_snapshot_t));
	Call_PushCellRef(time);
	Call_Finish();

	if (time == timeOrig)
	{
		gA_Timers[client].fTimescaledTicks += gA_Timers[client].fTimescale;
	}
	else
	{
		gA_Timers[client].fTimescaledTicks += time / interval;
	}

	gA_Timers[client].fCurrentTime = interval * gA_Timers[client].fTimescaledTicks;

	Call_StartForward(gH_Forwards_OnTimerIncrementPost);
	Call_PushCell(client);
	Call_PushCell(time);
	Call_Finish();

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

#if !DEBUG
	if (impulse && sv_cheats.BoolValue && !(GetUserFlagBits(client) & ADMFLAG_ROOT))
	{
		// Block cheat impulses
		switch (impulse)
		{
			case 76, 81, 82, 83, 102, 195, 196, 197, 202, 203:
			{
				impulse = 0;
			}
		}
	}
#endif

	int flags = GetEntityFlags(client);

	if (gA_Timers[client].bClientPaused && IsPlayerAlive(client) && !gCV_PauseMovement.BoolValue)
	{
		buttons = 0;
		vel = view_as<float>({0.0, 0.0, 0.0});

		SetEntityFlags(client, (flags | FL_ATCONTROLS));

		//SetEntityMoveType(client, MOVETYPE_NONE);

		return Plugin_Changed;
	}

	SetEntityFlags(client, (flags & ~FL_ATCONTROLS));

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
	bool bInStart = Shavit_InsideZone(client, Zone_Start, gA_Timers[client].iTimerTrack);

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

	int iPButtons = buttons;

	if (!gA_Timers[client].bClientPaused)
	{
		if (GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_w") && !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_w") &&
		(gA_Timers[client].iLastButtons & IN_FORWARD) == 0 && (buttons & IN_FORWARD) > 0)
		{
			gA_Timers[client].iStrafes++;
		}

		if (GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_a") && !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_a") && (gA_Timers[client].iLastButtons & IN_MOVELEFT) == 0 &&
			(buttons & IN_MOVELEFT) > 0 && (GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") > 0 || ((buttons & IN_FORWARD) == 0 && (buttons & IN_BACK) == 0)))
		{
			gA_Timers[client].iStrafes++;
		}

		if (GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_s") && !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_s") &&
			(gA_Timers[client].iLastButtons & IN_BACK) == 0 && (buttons & IN_BACK) > 0)
		{
			gA_Timers[client].iStrafes++;
		}

		if (GetStyleSettingBool(gA_Timers[client].bsStyle, "strafe_count_d") && !GetStyleSettingBool(gA_Timers[client].bsStyle, "block_d") && (gA_Timers[client].iLastButtons & IN_MOVERIGHT) == 0 &&
			(buttons & IN_MOVERIGHT) > 0 && (GetStyleSettingInt(gA_Timers[client].bsStyle, "force_hsw") > 0 || ((buttons & IN_FORWARD) == 0 && (buttons & IN_BACK) == 0)))
		{
			gA_Timers[client].iStrafes++;
		}
	}


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
	if(!gA_Timers[client].bCanUseAllKeys && mtMoveType != MOVETYPE_NOCLIP && mtMoveType != MOVETYPE_LADDER && !Shavit_InsideZone(client, Zone_Freestyle, -1))
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
					if(gA_Timers[client].iSHSWCombination == -1 && iCombination != -1)
					{
						Shavit_PrintToChat(client, "%T", (iCombination == 0)? "SHSWCombination0":"SHSWCombination1", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
						gA_Timers[client].iSHSWCombination = iCombination;
					}

					// W/A S/D
					if((gA_Timers[client].iSHSWCombination == 0 && iCombination != 0) ||
					// W/D S/A
						(gA_Timers[client].iSHSWCombination == 1 && iCombination != 1) ||
					// no valid combination & no valid input
						(gA_Timers[client].iSHSWCombination == -1 && iCombination == -1))
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

	// enable duck-jumping/bhop in tf2
	if (gEV_Type == Engine_TF2 && GetStyleSettingBool(gA_Timers[client].bsStyle, "bunnyhopping") && (buttons & IN_JUMP) > 0 && iGroundEntity != -1)
	{
		float fSpeed[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);

		fSpeed[2] = 289.0;
		SetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);
	}

	if (GetStyleSettingBool(gA_Timers[client].bsStyle, "autobhop") && gB_Auto[client] && (buttons & IN_JUMP) > 0 && mtMoveType == MOVETYPE_WALK && !bInWater)
	{
		int iOldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
		SetEntProp(client, Prop_Data, "m_nOldButtons", (iOldButtons & ~IN_JUMP));
	}

	// perf jump measuring
	bool bOnGround = (!bInWater && mtMoveType == MOVETYPE_WALK && iGroundEntity != -1);

	if(bOnGround && !gA_Timers[client].bOnGround)
	{
		gA_Timers[client].iLandingTick = tickcount;

		if (gEV_Type != Engine_TF2 && GetStyleSettingBool(gA_Timers[client].bsStyle, "easybhop"))
		{
			SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
		}
	}

	else if (!bOnGround && gA_Timers[client].bOnGround && gA_Timers[client].bJumped && !gA_Timers[client].bClientPaused)
	{
		int iDifference = (tickcount - gA_Timers[client].iLandingTick);

		if(iDifference < 10)
		{
			gA_Timers[client].iMeasuredJumps++;

			if(iDifference == 1)
			{
				gA_Timers[client].iPerfectJumps++;
			}
		}
	}

	if (bInStart && gCV_BlockPreJump.BoolValue && GetStyleSettingInt(gA_Timers[client].bsStyle, "prespeed") == 0 && (vel[2] > 0 || (buttons & IN_JUMP) > 0))
	{
		vel[2] = 0.0;
		buttons &= ~IN_JUMP;
	}

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
				ScaleVector(fSpeed, fScale);
				TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed); // maybe change this to SetEntPropVector some time?
			}
		}
	}

	float fAngle = GetAngleDiff(angles[1], gA_Timers[client].fLastAngle);

	if (!gA_Timers[client].bClientPaused && iGroundEntity == -1 && (GetEntityFlags(client) & FL_INWATER) == 0 && fAngle != 0.0)
	{
		float fAbsVelocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);

		if(SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0)) > 0.0)
		{
			float fTempAngle = angles[1];

			float fAngles[3];
			GetVectorAngles(fAbsVelocity, fAngles);

			if(fTempAngle < 0.0)
			{
				fTempAngle += 360.0;
			}

			TestAngles(client, (fTempAngle - fAngles[1]), fAngle, vel);
		}
	}

	if (GetTimerStatus(client) == view_as<int>(Timer_Running) && gA_Timers[client].fCurrentTime != 0.0)
	{
#if 0
		float frameCount = gB_Replay
			? float(Shavit_GetClientFrameCount(client) - Shavit_GetPlayerPreFrames(client)) + 1
			: (gA_Timers[client].fCurrentTime / GetTickInterval());
#else
		float frameCount = float(gA_Timers[client].iZoneIncrement);
#endif
		float fAbsVelocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);
		float curVel = SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0));
		float maxVel = gA_Timers[client].fMaxVelocity;
		gA_Timers[client].fMaxVelocity = (curVel > maxVel) ? curVel : maxVel;
		// STOLEN from Epic/Disrevoid. Thx :)
		gA_Timers[client].fAvgVelocity += (curVel - gA_Timers[client].fAvgVelocity) / frameCount;
	}

	gA_Timers[client].iLastButtons = iPButtons;
	gA_Timers[client].fLastAngle = angles[1];
	gA_Timers[client].bJumped = false;
	gA_Timers[client].bOnGround = bOnGround;

	return Plugin_Continue;
}

void TestAngles(int client, float dirangle, float yawdelta, float vel[3])
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
	else if((dirangle > 22.5 && dirangle < 67.5))
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
		sv_autobunnyhopping.ReplicateToClient(client, (GetStyleSettingBool(gA_Timers[client].bsStyle, "autobhop") && gB_Auto[client])? "1":"0");
	}

	if(sv_enablebunnyhopping != null)
	{
		sv_enablebunnyhopping.ReplicateToClient(client, (GetStyleSettingBool(gA_Timers[client].bsStyle, "bunnyhopping"))? "1":"0");
	}

	UpdateAiraccelerate(client, GetStyleSettingFloat(gA_Timers[client].bsStyle, "airaccelerate"));
}
