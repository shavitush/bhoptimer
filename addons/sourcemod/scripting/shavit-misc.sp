/*
 * shavit's Timer - Miscellaneous
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
#include <clientprefs>
#include <convar_class>
#include <dhooks>

#undef REQUIRE_EXTENSIONS
#include <SteamWorks>
#include <cstrike>
#include <tf2>
#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <eventqueuefix>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 524288

#define CP_ANGLES				(1 << 0)
#define CP_VELOCITY				(1 << 1)

#define CP_DEFAULT				(CP_ANGLES|CP_VELOCITY)

#define DEBUG 0

#define EFL_CHECK_UNTOUCH (1<<24)

enum struct persistent_data_t
{
	int iSteamID;
	int iDisconnectTime;
	int iTimesTeleported;
	ArrayList aCheckpoints;
	int iCurrentCheckpoint;
	cp_cache_t cpcache;
}

typedef StopTimerCallback = function void (int data);

// game specific
EngineVersion gEV_Type = Engine_Unknown;

char gS_RadioCommands[][] = { "coverme", "takepoint", "holdpos", "regroup", "followme", "takingfire", "go", "fallback", "sticktog",
	"getinpos", "stormfront", "report", "roger", "enemyspot", "needbackup", "sectorclear", "inposition", "reportingin",
	"getout", "negative", "enemydown", "compliment", "thanks", "cheer", "go_a", "go_b", "sorry", "needrop", "playerradio", "playerchatwheel", "player_ping", "chatwheel_ping" };

bool gB_Hide[MAXPLAYERS+1];
bool gB_Late = false;
int gI_GroundEntity[MAXPLAYERS+1];
int gI_LastShot[MAXPLAYERS+1];
ArrayList gA_Advertisements = null;
int gI_AdvertisementsCycle = 0;
char gS_Map[PLATFORM_MAX_PATH];
char gS_PreviousMap[PLATFORM_MAX_PATH];
int gI_Style[MAXPLAYERS+1];
Function gH_AfterWarningMenu[MAXPLAYERS+1];
bool gB_ClosedKZCP[MAXPLAYERS+1];
int gI_LastWeaponTick[MAXPLAYERS+1];
int gI_LastNoclipTick[MAXPLAYERS+1];

ArrayList gA_Checkpoints[MAXPLAYERS+1];
int gI_CurrentCheckpoint[MAXPLAYERS+1];
int gI_TimesTeleported[MAXPLAYERS+1];
bool gB_InCheckpointMenu[MAXPLAYERS+1];

int gI_CheckpointsSettings[MAXPLAYERS+1];

// save states
bool gB_SaveStates[MAXPLAYERS+1]; // whether we have data for when player rejoins from spec
ArrayList gA_PersistentData = null;

// cookies
Handle gH_HideCookie = null;
Handle gH_CheckpointsCookie = null;
Cookie gH_BlockAdvertsCookie = null;

// cvars
Convar gCV_GodMode = null;
Convar gCV_PreSpeed = null;
Convar gCV_HideTeamChanges = null;
Convar gCV_RespawnOnTeam = null;
Convar gCV_RespawnOnRestart = null;
Convar gCV_StartOnSpawn = null;
Convar gCV_PrestrafeLimit = null;
Convar gCV_HideRadar = null;
Convar gCV_TeleportCommands = null;
Convar gCV_NoWeaponDrops = null;
Convar gCV_NoBlock = null;
Convar gCV_NoBlood = null;
Convar gCV_AutoRespawn = null;
Convar gCV_CreateSpawnPoints = null;
Convar gCV_DisableRadio = null;
Convar gCV_Scoreboard = null;
Convar gCV_WeaponCommands = null;
Convar gCV_WeaponsSpawnGood = null;
Convar gCV_PlayerOpacity = null;
Convar gCV_StaticPrestrafe = null;
Convar gCV_NoclipMe = null;
Convar gCV_AdvertisementInterval = null;
Convar gCV_Checkpoints = null;
Convar gCV_RemoveRagdolls = null;
Convar gCV_ClanTag = null;
Convar gCV_DropAll = null;
Convar gCV_ResetTargetname = null;
Convar gCV_ResetTargetnameMain = null;
Convar gCV_ResetTargetnameBonus = null;
Convar gCV_RestoreStates = null;
Convar gCV_JointeamHook = null;
Convar gCV_SpectatorList = null;
Convar gCV_MaxCP = null;
Convar gCV_MaxCP_Segmented = null;
Convar gCV_HideChatCommands = null;
Convar gCV_PersistData = null;
Convar gCV_StopTimerWarning = null;
Convar gCV_WRMessages = null;
Convar gCV_BhopSounds = null;
Convar gCV_RestrictNoclip = null;
Convar gCV_BotFootsteps = null;
Convar gCV_SpecScoreboardOrder = null;
ConVar gCV_ExperimentalSegmentedEyeAngleFix = null;
ConVar gCV_PauseMovement = null;

// external cvars
ConVar sv_cheats = null;
ConVar sv_disable_immunity_alpha = null;
ConVar mp_humanteam = null;
ConVar hostname = null;
ConVar hostport = null;
ConVar sv_disable_radar = null;

// forwards
Handle gH_Forwards_OnClanTagChangePre = null;
Handle gH_Forwards_OnClanTagChangePost = null;
Handle gH_Forwards_OnSave = null;
Handle gH_Forwards_OnTeleport = null;
Handle gH_Forwards_OnDelete = null;
Handle gH_Forwards_OnCheckpointMenuMade = null;
Handle gH_Forwards_OnCheckpointMenuSelect = null;

// dhooks
Handle gH_GetPlayerMaxSpeed = null;
DynamicHook gH_UpdateStepSound = null;
DynamicHook gH_IsSpawnPointValid = null;
DynamicDetour gH_CalcPlayerScore = null;
Handle gH_PhysicsCheckForEntityUntouch;

// modules
bool gB_Eventqueuefix = false;
bool gB_Rankings = false;
bool gB_Replay = false;
bool gB_Zones = false;
bool gB_Chat = false;

// timer settings
stylestrings_t gS_StyleStrings[STYLE_LIMIT];

// chat settings
chatstrings_t gS_ChatStrings;

public Plugin myinfo =
{
	name = "[shavit] Miscellaneous",
	author = "shavit",
	description = "Miscellaneous features for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetCheckpoint", Native_GetCheckpoint);
	CreateNative("Shavit_SetCheckpoint", Native_SetCheckpoint);
	CreateNative("Shavit_ClearCheckpoints", Native_ClearCheckpoints);
	CreateNative("Shavit_TeleportToCheckpoint", Native_TeleportToCheckpoint);
	CreateNative("Shavit_GetTotalCheckpoints", Native_GetTotalCheckpoints);
	CreateNative("Shavit_OpenCheckpointMenu", Native_OpenCheckpointMenu);
	CreateNative("Shavit_SaveCheckpoint", Native_SaveCheckpoint);
	CreateNative("Shavit_GetCurrentCheckpoint", Native_GetCurrentCheckpoint);
	CreateNative("Shavit_SetCurrentCheckpoint", Native_SetCurrentCheckpoint);
	CreateNative("Shavit_GetTimesTeleported", Native_GetTimesTeleported);

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// forwards
	gH_Forwards_OnClanTagChangePre = CreateGlobalForward("Shavit_OnClanTagChangePre", ET_Event, Param_Cell, Param_String, Param_Cell);
	gH_Forwards_OnClanTagChangePost = CreateGlobalForward("Shavit_OnClanTagChangePost", ET_Event, Param_Cell, Param_String, Param_Cell);
	gH_Forwards_OnSave = CreateGlobalForward("Shavit_OnSave", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnTeleport = CreateGlobalForward("Shavit_OnTeleport", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnCheckpointMenuMade = CreateGlobalForward("Shavit_OnCheckpointMenuMade", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnCheckpointMenuSelect = CreateGlobalForward("Shavit_OnCheckpointMenuSelect", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnDelete = CreateGlobalForward("Shavit_OnDelete", ET_Event, Param_Cell, Param_Cell);

	// cache
	gEV_Type = GetEngineVersion();

	sv_cheats = FindConVar("sv_cheats");
	sv_disable_immunity_alpha = FindConVar("sv_disable_immunity_alpha");

	// spectator list
	RegConsoleCmd("sm_specs", Command_Specs, "Show a list of spectators.");
	RegConsoleCmd("sm_spectators", Command_Specs, "Show a list of spectators.");

	// spec
	RegConsoleCmd("sm_spec", Command_Spec, "Moves you to the spectators' team. Usage: sm_spec [target]");
	RegConsoleCmd("sm_spectate", Command_Spec, "Moves you to the spectators' team. Usage: sm_spectate [target]");

	// hide
	RegConsoleCmd("sm_hide", Command_Hide, "Toggle players' hiding.");
	RegConsoleCmd("sm_unhide", Command_Hide, "Toggle players' hiding.");
	gH_HideCookie = RegClientCookie("shavit_hide", "Hide settings", CookieAccess_Protected);

	// tpto
	RegConsoleCmd("sm_tpto", Command_Teleport, "Teleport to another player. Usage: sm_tpto [target]");
	RegConsoleCmd("sm_goto", Command_Teleport, "Teleport to another player. Usage: sm_goto [target]");

	// weapons
	RegConsoleCmd("sm_usp", Command_Weapon, "Spawn a USP.");
	RegConsoleCmd("sm_glock", Command_Weapon, "Spawn a Glock.");
	RegConsoleCmd("sm_knife", Command_Weapon, "Spawn a knife.");

	// checkpoints
	RegConsoleCmd("sm_cpmenu", Command_Checkpoints, "Opens the checkpoints menu.");
	RegConsoleCmd("sm_cp", Command_Checkpoints, "Opens the checkpoints menu. Alias for sm_cpmenu.");
	RegConsoleCmd("sm_checkpoint", Command_Checkpoints, "Opens the checkpoints menu. Alias for sm_cpmenu.");
	RegConsoleCmd("sm_checkpoints", Command_Checkpoints, "Opens the checkpoints menu. Alias for sm_cpmenu.");
	RegConsoleCmd("sm_save", Command_Save, "Saves checkpoint.");
	RegConsoleCmd("sm_tele", Command_Tele, "Teleports to checkpoint. Usage: sm_tele [number]");
	gH_CheckpointsCookie = RegClientCookie("shavit_checkpoints", "Checkpoints settings", CookieAccess_Protected);
	gA_PersistentData = new ArrayList(sizeof(persistent_data_t));

	// noclip
	RegConsoleCmd("sm_prac", Command_Noclip, "Toggles noclip. (sm_nc alias)");
	RegConsoleCmd("sm_practice", Command_Noclip, "Toggles noclip. (sm_nc alias)");
	RegConsoleCmd("sm_nc", Command_Noclip, "Toggles noclip.");
	RegConsoleCmd("sm_noclipme", Command_Noclip, "Toggles noclip. (sm_nc alias)");
	AddCommandListener(CommandListener_Noclip, "+noclip");
	AddCommandListener(CommandListener_Noclip, "-noclip");
	// Hijack sourcemod's sm_noclip from funcommands to work when no args are specified.
	AddCommandListener(CommandListener_funcommands_Noclip, "sm_noclip");
	AddCommandListener(CommandListener_Real_Noclip, "noclip");

	// hook teamjoins
	AddCommandListener(Command_Jointeam, "jointeam");
	AddCommandListener(Command_Spectate, "spectate");

	// gCV_SpecScoreboardOrder stuff
	AddCommandListener(Command_SpecNextPrev, "spec_next");
	AddCommandListener(Command_SpecNextPrev, "spec_prev");

	// hook radio commands instead of a global listener
	for(int i = 0; i < sizeof(gS_RadioCommands); i++)
	{
		AddCommandListener(Command_Radio, gS_RadioCommands[i]);
	}

	// hooks
	HookEvent("player_spawn", Player_Spawn);
	HookEvent("player_team", Player_Notifications, EventHookMode_Pre);
	HookEvent("player_death", Player_Notifications, EventHookMode_Pre);
	HookEventEx("weapon_fire", Weapon_Fire);
	HookEventEx("weapon_fire_on_empty", Weapon_Fire);
	HookEventEx("weapon_reload", Weapon_Fire);
	AddCommandListener(Command_Drop, "drop");
	AddTempEntHook("EffectDispatch", EffectDispatch);
	AddTempEntHook("World Decal", WorldDecal);
	AddTempEntHook((gEV_Type != Engine_TF2)? "Shotgun Shot":"Fire Bullets", Shotgun_Shot);
	AddNormalSoundHook(NormalSound);

	// phrases
	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-misc.phrases");

	// advertisements
	gA_Advertisements = new ArrayList(300);
	hostname = FindConVar("hostname");
	hostport = FindConVar("hostport");
	RegConsoleCmd("sm_toggleadverts", Command_ToggleAdverts, "Toggles visibility of advertisements");
	gH_BlockAdvertsCookie = new Cookie("shavit-blockadverts", "whether to block shavit-misc advertisements", CookieAccess_Private);

	// cvars and stuff
	gCV_GodMode = new Convar("shavit_misc_godmode", "3", "Enable godmode for players?\n0 - Disabled\n1 - Only prevent fall/world damage.\n2 - Only prevent damage from other players.\n3 - Full godmode.", 0, true, 0.0, true, 3.0);
	gCV_PreSpeed = new Convar("shavit_misc_prespeed", "2", "Stop prespeeding in the start zone?\n0 - Disabled, fully allow prespeeding.\n1 - Limit relatively to prestrafelimit.\n2 - Block bunnyhopping in startzone.\n3 - Limit to prestrafelimit and block bunnyhopping.\n4 - Limit to prestrafelimit but allow prespeeding. Combine with shavit_core_nozaxisspeed 1 for SourceCode timer's behavior.\n5 - Limit horizontal speed to prestrafe but allow prespeeding.", 0, true, 0.0, true, 5.0);
	gCV_HideTeamChanges = new Convar("shavit_misc_hideteamchanges", "1", "Hide team changes in chat?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnTeam = new Convar("shavit_misc_respawnonteam", "1", "Respawn whenever a player joins a team?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnRestart = new Convar("shavit_misc_respawnonrestart", "1", "Respawn a dead player if they use the timer restart command?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_StartOnSpawn = new Convar("shavit_misc_startonspawn", "1", "Restart the timer for a player after they spawn?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_PrestrafeLimit = new Convar("shavit_misc_prestrafelimit", "30", "Prestrafe limitation in startzone.\nThe value used internally is style run speed + this.\ni.e. run speed of 250 can prestrafe up to 278 (+28) with regular settings.", 0, true, 0.0, false);
	gCV_HideRadar = new Convar("shavit_misc_hideradar", "1", "Should the plugin hide the in-game radar?", 0, true, 0.0, true, 1.0);
	gCV_TeleportCommands = new Convar("shavit_misc_tpcmds", "1", "Enable teleport-related commands? (sm_goto/sm_tpto)\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoWeaponDrops = new Convar("shavit_misc_noweapondrops", "1", "Remove every dropped weapon.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoBlock = new Convar("shavit_misc_noblock", "1", "Disable player collision?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoBlood = new Convar("shavit_misc_noblood", "1", "Hide blood decals and particles?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_AutoRespawn = new Convar("shavit_misc_autorespawn", "1.5", "Seconds to wait before respawning player?\n0 - Disabled", 0, true, 0.0, true, 10.0);
	gCV_CreateSpawnPoints = new Convar("shavit_misc_createspawnpoints", "6", "Amount of spawn points to add for each team.\n0 - Disabled", 0, true, 0.0, true, 32.0);
	gCV_DisableRadio = new Convar("shavit_misc_disableradio", "1", "Block radio commands.\n0 - Disabled (radio commands work)\n1 - Enabled (radio commands are blocked)", 0, true, 0.0, true, 1.0);
	gCV_Scoreboard = new Convar("shavit_misc_scoreboard", "1", "Manipulate scoreboard so score is -{time} and deaths are {rank})?\nDeaths part requires shavit-rankings.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_WeaponCommands = new Convar("shavit_misc_weaponcommands", "2", "Enable sm_usp, sm_glock and sm_knife?\n0 - Disabled\n1 - Enabled\n2 - Also give infinite reserved ammo.\n3 - Also give infinite clip ammo.", 0, true, 0.0, true, 3.0);
	gCV_WeaponsSpawnGood = new Convar("shavit_misc_weaponsspawngood", "3", "Bitflag for making glocks spawn on burst-fire and USPs spawn with a silencer on.\n0 - Disabled\n1 - Spawn USPs with a silencer.\n2 - Spawn glocks on burst-fire mode.\n3 - Spawn both USPs and glocks GOOD.", 0, true, 0.0, true, 3.0);
	gCV_PlayerOpacity = new Convar("shavit_misc_playeropacity", "69", "Player opacity (alpha) to set on spawn.\n-1 - Disabled\nValue can go up to 255. 0 for invisibility.", 0, true, -1.0, true, 255.0);
	gCV_StaticPrestrafe = new Convar("shavit_misc_staticprestrafe", "1", "Force prestrafe for every pistol.\n250 is the default value and some styles will have 260.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoclipMe = new Convar("shavit_misc_noclipme", "1", "Allow +noclip, sm_p and all the noclip commands?\n0 - Disabled\n1 - Enabled\n2 - requires 'admin_noclipme' override or ADMFLAG_CHEATS flag.", 0, true, 0.0, true, 2.0);
	gCV_AdvertisementInterval = new Convar("shavit_misc_advertisementinterval", "600.0", "Interval between each chat advertisement.\nConfiguration file for those is configs/shavit-advertisements.cfg.\nSet to 0.0 to disable.\nRequires server restart for changes to take effect.", 0, true, 0.0);
	gCV_Checkpoints = new Convar("shavit_misc_checkpoints", "1", "Allow players to save and teleport to checkpoints.", 0, true, 0.0, true, 1.0);
	gCV_RemoveRagdolls = new Convar("shavit_misc_removeragdolls", "1", "Remove ragdolls after death?\n0 - Disabled\n1 - Only remove replay bot ragdolls.\n2 - Remove all ragdolls.", 0, true, 0.0, true, 2.0);
	gCV_ClanTag = new Convar("shavit_misc_clantag", "{tr}{styletag} :: {time}", "Custom clantag for players.\n0 - Disabled\n{styletag} - style tag.\n{style} - style name.\n{time} - formatted time.\n{tr} - first letter of track.\n{rank} - player rank.\n{cr} - player's chatrank from shavit-chat, trimmed, with no colors", 0);
	gCV_DropAll = new Convar("shavit_misc_dropall", "1", "Allow all weapons to be dropped?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_ResetTargetname = new Convar("shavit_misc_resettargetname", "1", "Reset the player's targetname and eventqueue upon timer start?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_ResetTargetnameMain = new Convar("shavit_misc_resettargetname_main", "", "What targetname to use when resetting the player. You don't need to touch this");
	gCV_ResetTargetnameBonus = new Convar("shavit_misc_resettargetname_bonus", "", "What targetname to use when resetting the player (on bonus tracks). You don't need to touch this");
	gCV_RestoreStates = new Convar("shavit_misc_restorestates", "1", "Save the players' timer/position etc.. when they die/change teams,\nand load the data when they spawn?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_JointeamHook = new Convar("shavit_misc_jointeamhook", "1", "Hook `jointeam`?\n0 - Disabled\n1 - Enabled, players can instantly change teams.", 0, true, 0.0, true, 1.0);
	gCV_SpectatorList = new Convar("shavit_misc_speclist", "1", "Who to show in !specs?\n0 - everyone\n1 - all admins (admin_speclisthide override to bypass)\n2 - players you can target", 0, true, 0.0, true, 2.0);
	gCV_MaxCP = new Convar("shavit_misc_maxcp", "1000", "Maximum amount of checkpoints.\nNote: Very high values will result in high memory usage!", 0, true, 1.0, true, 10000.0);
	gCV_MaxCP_Segmented = new Convar("shavit_misc_maxcp_seg", "10", "Maximum amount of segmented checkpoints. Make this less or equal to shavit_misc_maxcp.\nNote: Very high values will result in HUGE memory usage! Segmented checkpoints contain frame data!", 0, true, 1.0, true, 50.0);
	gCV_HideChatCommands = new Convar("shavit_misc_hidechatcmds", "1", "Hide commands from chat?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_PersistData = new Convar("shavit_misc_persistdata", "600", "How long to persist timer data for disconnected users in seconds?\n-1 - Until map change\n0 - Disabled");
	gCV_StopTimerWarning = new Convar("shavit_misc_stoptimerwarning", "180", "Time in seconds to display a warning before stopping the timer with noclip or !stop.\n0 - Disabled");
	gCV_WRMessages = new Convar("shavit_misc_wrmessages", "3", "How many \"NEW <style> WR!!!\" messages to print?\n0 - Disabled", 0,  true, 0.0, true, 100.0);
	gCV_BhopSounds = new Convar("shavit_misc_bhopsounds", "1", "Should bhop (landing and jumping) sounds be muted?\n0 - Disabled\n1 - Blocked while !hide is enabled\n2 - Always blocked", 0,  true, 0.0, true, 2.0);
	gCV_RestrictNoclip = new Convar("shavit_misc_restrictnoclip", "0", "Should noclip be be restricted\n0 - Disabled\n1 - No vertical velocity while in noclip in start zone\n2 - No noclip in start zone", 0, true, 0.0, true, 2.0);
	gCV_BotFootsteps = new Convar("shavit_misc_botfootsteps", "1", "Enable footstep sounds for replay bots. Only works if shavit_misc_bhopsounds is less than 2.", 0, true, 0.0, true, 1.0);
	gCV_ExperimentalSegmentedEyeAngleFix = new Convar("shavit_misc_experimental_segmented_eyeangle_fix", "1", "When teleporting to a segmented checkpoint, the player's old eye-angles persist in replay-frames for as many ticks they're behind the server in latency. This applies the teleport-position angles to the replay-frame for that many ticks.", 0, true, 0.0, true, 1.0);
	gCV_SpecScoreboardOrder = new Convar("shavit_misc_spec_scoreboard_order", "1", "Use scoreboard ordering for players when changing target when spectating.", 0, true, 0.0, true, 1.0);

	gCV_HideRadar.AddChangeHook(OnConVarChanged);
	Convar.AutoExecConfig();

	mp_humanteam = FindConVar((gEV_Type == Engine_TF2) ? "mp_humans_must_join_team" : "mp_humanteam");
	sv_disable_radar = FindConVar("sv_disable_radar");

	// crons
	CreateTimer(10.0, Timer_Cron, 0, TIMER_REPEAT);
	CreateTimer(0.5, Timer_PersistKZCP, 0, TIMER_REPEAT);

	LoadDHooks();

	if(gEV_Type != Engine_TF2)
	{
		CreateTimer(1.0, Timer_Scoreboard, 0, TIMER_REPEAT);
	}

	// modules
	gB_Eventqueuefix = LibraryExists("eventqueuefix");
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_Replay = LibraryExists("shavit-replay");
	gB_Zones = LibraryExists("shavit-zones");
	gB_Chat = LibraryExists("shavit-chat");
}

public void OnAllPluginsLoaded()
{
	gCV_PauseMovement = FindConVar("shavit_core_pause_movement");
}

void LoadDHooks()
{
	Handle hGameData = LoadGameConfigFile("shavit.games");

	if (hGameData == null)
	{
		SetFailState("Failed to load shavit gamedata");
	}

	int iOffset;

	if (gEV_Type == Engine_TF2)
	{
		if (!(gH_CalcPlayerScore = DHookCreateDetour(Address_Null, CallConv_CDECL, ReturnType_Int, ThisPointer_Ignore)))
		{
			SetFailState("Failed to create detour for CTFGameRules::CalcPlayerScore");
		}

		if (DHookSetFromConf(gH_CalcPlayerScore, hGameData, SDKConf_Signature, "CTFGameRules::CalcPlayerScore"))
		{
			gH_CalcPlayerScore.AddParam(HookParamType_Int);
			gH_CalcPlayerScore.AddParam(HookParamType_CBaseEntity);
			gH_CalcPlayerScore.Enable(Hook_Pre, Detour_CalcPlayerScore);
		}
		else
		{
			LogError("Couldn't get the address for \"CTFGameRules::CalcPlayerScore\" - make sure your gamedata is updated!");
		}
	}
	else
	{
		if ((iOffset = GameConfGetOffset(hGameData, "CCSPlayer::GetPlayerMaxSpeed")) == -1)
		{
			SetFailState("Couldn't get the offset for \"CCSPlayer::GetPlayerMaxSpeed\" - make sure your gamedata is updated!");
		}

		gH_GetPlayerMaxSpeed = DHookCreate(iOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, CCSPlayer__GetPlayerMaxSpeed);
	}

	if ((iOffset = GameConfGetOffset(hGameData, "CBasePlayer::UpdateStepSound")) != -1)
	{
		gH_UpdateStepSound = new DynamicHook(iOffset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity);
		gH_UpdateStepSound.AddParam(HookParamType_ObjectPtr);
		gH_UpdateStepSound.AddParam(HookParamType_VectorPtr);
		gH_UpdateStepSound.AddParam(HookParamType_VectorPtr);
	}
	else
	{
		LogError("Couldn't get the offset for \"CBasePlayer::UpdateStepSound\" - make sure your gamedata is updated!");
	}

	if ((iOffset = GameConfGetOffset(hGameData, "CGameRules::IsSpawnPointValid")) != -1)
	{
		gH_IsSpawnPointValid = new DynamicHook(iOffset, HookType_GameRules, ReturnType_Bool, ThisPointer_Ignore);
		gH_IsSpawnPointValid.AddParam(HookParamType_CBaseEntity);
		gH_IsSpawnPointValid.AddParam(HookParamType_CBaseEntity);
	}
	else
	{
		SetFailState("Couldn't get the offset for \"CGameRules::IsSpawnPointValid\" - make sure your gamedata is updated!");
	}

	StartPrepSDKCall(SDKCall_Entity);
	if(!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "PhysicsCheckForEntityUntouch"))
	{
		SetFailState("Failed to get PhysicsCheckForEntityUntouch");
	}
	gH_PhysicsCheckForEntityUntouch = EndPrepSDKCall();

	delete hGameData;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (sv_disable_radar != null)
	{
		sv_disable_radar.BoolValue = gCV_HideRadar.BoolValue;
	}
}

public MRESReturn Hook_IsSpawnPointValid(Handle hReturn, Handle hParams)
{
	if (gCV_NoBlock.BoolValue)
	{
		DHookSetReturn(hReturn, true);
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

MRESReturn Detour_CalcPlayerScore(DHookReturn hReturn, DHookParam hParams)
{
	if (!gCV_Scoreboard.BoolValue)
	{
		return MRES_Ignored;
	}

	int client = hParams.Get(2);
	float fPB = Shavit_GetClientPB(client, 0, Track_Main);
	int iScore = (fPB != 0.0 && fPB < 2000)? -RoundToFloor(fPB):-2000;

	hReturn.Value = iScore;
	return MRES_Supercede;
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	char sSetting[8];
	GetClientCookie(client, gH_HideCookie, sSetting, 8);

	if(strlen(sSetting) == 0)
	{
		SetClientCookie(client, gH_HideCookie, "0");
		gB_Hide[client] = false;
	}

	else
	{
		gB_Hide[client] = view_as<bool>(StringToInt(sSetting));
	}

	GetClientCookie(client, gH_CheckpointsCookie, sSetting, 8);

	if(strlen(sSetting) == 0)
	{
		IntToString(CP_DEFAULT, sSetting, 8);
		SetClientCookie(client, gH_CheckpointsCookie, sSetting);
		gI_CheckpointsSettings[client] = CP_DEFAULT;
	}

	else
	{
		gI_CheckpointsSettings[client] = StringToInt(sSetting);
	}

	gI_Style[client] = Shavit_GetBhopStyle(client);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleStringsStruct(i, gS_StyleStrings[i]);
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);

	if(!LoadAdvertisementsConfig())
	{
		SetFailState("Cannot open \"configs/shavit-advertisements.cfg\". Make sure this file exists and that the server has read permissions to it.");
	}
}

void DeletePersistentDataFromClient(int client)
{
	persistent_data_t aData;
	int iIndex = FindPersistentData(client, aData);

	if (iIndex != -1)
	{
		DeletePersistentData(iIndex, aData);
	}

	gB_SaveStates[client] = false;
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	gI_Style[client] = newstyle;

	if (gB_SaveStates[client] && manual)
	{
		DeletePersistentDataFromClient(client);
	}

	if(StrContains(gS_StyleStrings[newstyle].sSpecialString, "segments") != -1)
	{
		// Gammacase somehow had this callback fire before OnClientPutInServer.
		// OnClientPutInServer will still fire but we need a valid arraylist in the mean time.
		if(gA_Checkpoints[client] == null)
		{
			gA_Checkpoints[client] = new ArrayList(sizeof(cp_cache_t));	
		}

		OpenCheckpointsMenu(client);
		Shavit_PrintToChat(client, "%T", "MiscSegmentedCommand", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
}

void LoadMapFixes()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-mapfixes.cfg");

	KeyValues kv = new KeyValues("shavit-mapfixes");
	
	if (kv.ImportFromFile(sPath) && kv.JumpToKey(gS_Map) && kv.GotoFirstSubKey(false))
	{
		do {
			char key[128];
			char value[128];
			kv.GetSectionName(key, sizeof(key));
			kv.GetString(NULL_STRING, value, sizeof(value));

			PrintToServer(">>>> mapfixes: %s \"%s\"", key, value);

			ConVar cvar = FindConVar(key);

			if (cvar)
			{
				cvar.SetString(value, true, true);
			}
		} while (kv.GotoNextKey(false));
	}

	delete kv;
}

void CreateSpawnPoint(int iTeam, float fOrigin[3], float fAngles[3])
{
	int iSpawnPoint = CreateEntityByName((gEV_Type == Engine_TF2)? "info_player_teamspawn":((iTeam == 2)? "info_player_terrorist":"info_player_counterterrorist"));

	if (DispatchSpawn(iSpawnPoint))
	{
		if (gEV_Type == Engine_TF2)
		{
			SetEntProp(iSpawnPoint, Prop_Send, "m_iTeamNum", iTeam);
		}

		TeleportEntity(iSpawnPoint, fOrigin, fAngles, NULL_VECTOR);
	}
}

public void OnMapStart()
{
	gH_IsSpawnPointValid.HookGamerules(Hook_Post, Hook_IsSpawnPointValid);

	GetLowercaseMapName(gS_Map);

	if (gB_Late)
	{
		gB_Late = false;
		Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount());
		Shavit_OnChatConfigLoaded();
		OnAutoConfigsBuffered();

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);

				if(AreClientCookiesCached(i))
				{
					OnClientCookiesCached(i);
					Shavit_OnStyleChanged(i, 0, Shavit_GetBhopStyle(i), Shavit_GetClientTrack(i), false);
				}
			}
		}
	}

	if (!StrEqual(gS_Map, gS_PreviousMap, false))
	{
		int iLength = gA_PersistentData.Length;

		for(int i = iLength - 1; i >= 0; i--)
		{
			persistent_data_t aData;
			gA_PersistentData.GetArray(i, aData);
			DeletePersistentData(i, aData);
		}
	}
}

public void OnAutoConfigsBuffered()
{
	LoadMapFixes();
}

public void OnConfigsExecuted()
{
	if(sv_disable_immunity_alpha != null)
	{
		sv_disable_immunity_alpha.BoolValue = true;
	}

	if (sv_disable_radar != null && gCV_HideRadar.BoolValue)
	{
		sv_disable_radar.BoolValue = true;
	}

	if(gCV_CreateSpawnPoints.IntValue > 0)
	{
		int info_player_terrorist        = FindEntityByClassname(-1, "info_player_terrorist");
		int info_player_counterterrorist = FindEntityByClassname(-1, "info_player_counterterrorist");
		int info_player_teamspawn        = FindEntityByClassname(-1, "info_player_teamspawn");
		int info_player_start            = FindEntityByClassname(-1, "info_player_start");

		int iEntity =
			((info_player_terrorist != -1)        ? info_player_terrorist :
			((info_player_counterterrorist != -1) ? info_player_counterterrorist :
			((info_player_teamspawn != -1)        ? info_player_teamspawn :
			((info_player_start != -1)            ? info_player_start : -1))));

		if (iEntity != -1)
		{
			float fOrigin[3], fAngles[3];
			GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
			GetEntPropVector(iEntity, Prop_Data, "m_angAbsRotation", fAngles);

			if (gEV_Type == Engine_TF2)
			{
				int iSearch = -1;
				bool haveRed = false;
				bool haveBlu = false;

				while ((iSearch = FindEntityByClassname(iSearch, "info_player_teamspawn")) != -1)
				{
					int team = GetEntProp(iSearch, Prop_Send, "m_iTeamNum");
					haveRed = haveRed || team == 2;
					haveBlu = haveBlu || team == 3;
				}

				if (!haveRed)
				{
					CreateSpawnPoint(2, fOrigin, fAngles);
				}

				if (!haveBlu)
				{
					CreateSpawnPoint(3, fOrigin, fAngles);
				}
			}
			else
			{
				if (info_player_terrorist == -1)
				{
					CreateSpawnPoint(2, fOrigin, fAngles);
				}

				if (info_player_counterterrorist == -1)
				{
					CreateSpawnPoint(3, fOrigin, fAngles);
				}
			}
		}
	}

	if(gCV_AdvertisementInterval.FloatValue > 0.0)
	{
		CreateTimer(gCV_AdvertisementInterval.FloatValue, Timer_Advertisement, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void OnMapEnd()
{
	gS_PreviousMap = gS_Map;
}

bool LoadAdvertisementsConfig()
{
	gA_Advertisements.Clear();

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-advertisements.cfg");

	KeyValues kv = new KeyValues("shavit-advertisements");
	
	if(!kv.ImportFromFile(sPath) || !kv.GotoFirstSubKey(false))
	{
		delete kv;

		return false;
	}

	do
	{
		char sTempMessage[300];
		kv.GetString(NULL_STRING, sTempMessage, 300, "<EMPTY ADVERTISEMENT>");

		ReplaceString(sTempMessage, 300, "{text}", gS_ChatStrings.sText);
		ReplaceString(sTempMessage, 300, "{warning}", gS_ChatStrings.sWarning);
		ReplaceString(sTempMessage, 300, "{variable}", gS_ChatStrings.sVariable);
		ReplaceString(sTempMessage, 300, "{variable2}", gS_ChatStrings.sVariable2);
		ReplaceString(sTempMessage, 300, "{style}", gS_ChatStrings.sStyle);

		gA_Advertisements.PushString(sTempMessage);
	}

	while(kv.GotoNextKey(false));

	delete kv;

	return true;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}

	else if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = true;
	}

	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}

	else if(StrEqual(name, "shavit-chat"))
	{
		gB_Chat = true;
	}

	else if(StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}

	else if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = false;
	}

	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}

	else if(StrEqual(name, "shavit-chat"))
	{
		gB_Chat = false;
	}

	else if(StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = false;
	}
}

int GetHumanTeam()
{
	char sTeam[8];
	mp_humanteam.GetString(sTeam, 8);

	if(StrEqual(sTeam, "t", false) || StrEqual(sTeam, "red", false))
	{
		return 2;
	}

	else if(StrEqual(sTeam, "ct", false) || StrContains(sTeam, "blu", false) != -1)
	{
		return 3;
	}

	return 0;
}

public Action Command_Spectate(int client, const char[] command, int args)
{
	if(!IsValidClient(client) || !gCV_JointeamHook.BoolValue)
	{
		return Plugin_Continue;
	}

	CleanSwitchTeam(client, 1);
	return Plugin_Handled;
}

public int ScoreboardSort(int index1, int index2, Handle array, Handle hndl)
{
	int a = GetArrayCell(array, index1);
	int b = GetArrayCell(array, index2);

	int a_team = GetClientTeam(a);
	int b_team = GetClientTeam(b);

	if (a_team != b_team)
	{
		return a_team > b_team ? -1 : 1;
	}

	int a_score;
	int b_score;

	if (gEV_Type == Engine_CSGO)
	{
		a_score = CS_GetClientContributionScore(a);
		b_score = CS_GetClientContributionScore(b);
	}
	else
	{
		a_score = GetEntProp(a, Prop_Data, "m_iFrags");
		b_score = GetEntProp(b, Prop_Data, "m_iFrags");
	}

	if (a_score != b_score)
	{
		return a_score > b_score ? -1 : 1;
	}

	int a_deaths = GetEntProp(a, Prop_Data, "m_iDeaths");
	int b_deaths = GetEntProp(b, Prop_Data, "m_iDeaths");

	if (a_deaths != b_deaths)
	{
		return a_deaths < b_deaths ? -1 : 1;
	}

	return a < b ? -1 : 1;
}

public Action Command_SpecNextPrev(int client, const char[] command, int args)
{
	if (!IsValidClient(client) || !gCV_SpecScoreboardOrder.BoolValue)
	{
		return Plugin_Continue;
	}

	int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

	if (iObserverMode <= 3 /* OBS_MODE_FIXED */)
	{
		return Plugin_Continue;
	}

	ArrayList players = new ArrayList(1);

	// add valid alive players
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i != client && IsValidClient(i) && IsPlayerAlive(i) && GetClientTeam(i) > 1)
		{
			players.Push(i);
		}
	}

	if (players.Length < 2)
	{
		return Plugin_Continue;
	}

	players.SortCustom(ScoreboardSort);

	int current_target = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

	if (!IsValidClient(current_target))
	{
		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", players.Get(0));
		return Plugin_Handled;
	}

	int pos = players.FindValue(current_target);

	if (pos == -1)
	{
		pos = 0;
	}

	pos += (StrEqual(command, "spec_next", true)) ? 1 : -1;

	if (pos < 0)
	{
		pos = players.Length - 1;
	}

	if (pos >= players.Length)
	{
		pos = 0;
	}

	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", players.Get(pos));

	return Plugin_Handled;
}

public Action Command_Jointeam(int client, const char[] command, int args)
{
	if(!IsValidClient(client) || !gCV_JointeamHook.BoolValue)
	{
		return Plugin_Continue;
	}

	if(!gB_SaveStates[client])
	{
		PersistData(client, false);
	}

	char arg1[8];
	GetCmdArg(1, arg1, 8);

	int iTeam = StringToInt(arg1);
	int iHumanTeam = GetHumanTeam();

	if (iHumanTeam != 0)
	{
		iTeam = iHumanTeam;
	}

	if (iTeam < 1 || iTeam > 3)
	{
		iTeam = GetRandomInt(2, 3);
	}

	CleanSwitchTeam(client, iTeam);

	if(gCV_RespawnOnTeam.BoolValue && iTeam != 1)
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_RespawnPlayer(client);
		}
		else
		{
			RemoveAllWeapons(client); // so weapons are removed and we don't hit the edict limit
			CS_RespawnPlayer(client);
		}

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void CleanSwitchTeam(int client, int team)
{
	if (gEV_Type == Engine_CSGO && GetClientTeam(client) == team)
	{
		// Close the team menu when selecting your own team...
		Event event = CreateEvent("player_team");
		event.SetInt("userid", GetClientUserId(client));
		event.SetInt("team", team);
		event.SetBool("silent", true);
		event.FireToClient(client);
		event.Cancel();
	}

	if(gEV_Type == Engine_TF2)
	{
		TF2_ChangeClientTeam(client, view_as<TFTeam>(team));
	}
	else if(team != 1)
	{
		CS_SwitchTeam(client, team);
	}
	else
	{
		ChangeClientTeam(client, team);
	}
}

public Action Command_Radio(int client, const char[] command, int args)
{
	if(gCV_DisableRadio.BoolValue)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public MRESReturn CCSPlayer__GetPlayerMaxSpeed(int pThis, DHookReturn hReturn)
{
	if(!gCV_StaticPrestrafe.BoolValue || !IsValidClient(pThis, true))
	{
		return MRES_Ignored;
	}

	hReturn.Value = Shavit_GetStyleSettingFloat(gI_Style[pThis], "runspeed");

	return MRES_Override;
}

// Remove flags from replay bots that cause CBasePlayer::UpdateStepSound to return without playing a footstep.
public MRESReturn Hook_UpdateStepSound_Pre(int pThis, DHookParam hParams)
{
	if (GetEntityMoveType(pThis) == MOVETYPE_NOCLIP)
	{
		SetEntityMoveType(pThis, MOVETYPE_WALK);
	}

	SetEntityFlags(pThis, GetEntityFlags(pThis) & ~FL_ATCONTROLS);

	return MRES_Ignored;
}

// Readd flags to replay bots now that CBasePlayer::UpdateStepSound is done.
public MRESReturn Hook_UpdateStepSound_Post(int pThis, DHookParam hParams)
{
	if (GetEntityMoveType(pThis) == MOVETYPE_WALK)
	{
		SetEntityMoveType(pThis, MOVETYPE_NOCLIP);
	}

	SetEntityFlags(pThis, GetEntityFlags(pThis) | FL_ATCONTROLS);

	return MRES_Ignored;
}

public Action Timer_Cron(Handle timer)
{
	if(gCV_HideRadar.BoolValue && gEV_Type == Engine_CSS)
	{
		float salt = GetURandomFloat();

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				RemoveRadar(i, salt);
			}
		}
	}

	if (gCV_NoWeaponDrops.BoolValue)
	{
		int ent = -1;

		while ((ent = FindEntityByClassname(ent, "weapon_*")) != -1)
		{
			if (GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity") == -1)
			{
				AcceptEntityInput(ent, "Kill");
			}
		}
	}

	if (gCV_PersistData.IntValue < 0)
	{
		return Plugin_Continue;
	}

	int iTime = GetTime();
	int iLength = gA_PersistentData.Length;

	for(int i = iLength - 1; i >= 0; i--)
	{
		persistent_data_t aData;
		gA_PersistentData.GetArray(i, aData);

		if(aData.iDisconnectTime && (iTime - aData.iDisconnectTime >= gCV_PersistData.IntValue))
		{
			DeletePersistentData(i, aData);
		}
	}

	return Plugin_Continue;
}

public Action Timer_PersistKZCP(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!gB_ClosedKZCP[i] &&
			Shavit_GetStyleSettingInt(gI_Style[i], "kzcheckpoints")
			&& GetClientMenu(i) == MenuSource_None &&
			IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i))
		{
			OpenKZCPMenu(i);
		}
		// reopen repeatedly in case someone has bad internet and the menu disappears
		else if (gB_InCheckpointMenu[i])
		{
			OpenNormalCPMenu(i);
		}
	}

	return Plugin_Continue;
}

public Action Timer_Scoreboard(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i))
		{
			continue;
		}

		if(gCV_Scoreboard.BoolValue)
		{
			UpdateScoreboard(i);
		}

		UpdateClanTag(i);
	}

	return Plugin_Continue;
}

public Action Timer_Advertisement(Handle timer)
{
	char sHostname[128];
	hostname.GetString(sHostname, 128);

	char sTimeLeft[32];
	int iTimeLeft = 0;
	GetMapTimeLeft(iTimeLeft);
	FormatSeconds(float(iTimeLeft), sTimeLeft, 32, false, true);

	char sTimeLeftRaw[8];
	IntToString(iTimeLeft, sTimeLeftRaw, 8);

	char sIPAddress[64];

	if(GetFeatureStatus(FeatureType_Native, "SteamWorks_GetPublicIP") == FeatureStatus_Available)
	{
		int iAddress[4];
		SteamWorks_GetPublicIP(iAddress);

		FormatEx(sIPAddress, 64, "%d.%d.%d.%d:%d", iAddress[0], iAddress[1], iAddress[2], iAddress[3], hostport.IntValue);
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			if(AreClientCookiesCached(i))
			{
				char sCookie[2];
				gH_BlockAdvertsCookie.Get(i, sCookie, sizeof(sCookie));

				if (sCookie[0] == '1')
				{
					continue;
				}
			}

			char sTempMessage[300];
			gA_Advertisements.GetString(gI_AdvertisementsCycle, sTempMessage, 300);

			char sName[MAX_NAME_LENGTH];
			GetClientName(i, sName, MAX_NAME_LENGTH);
			ReplaceString(sTempMessage, 300, "{name}", sName);
			ReplaceString(sTempMessage, 300, "{timeleft}", sTimeLeft);
			ReplaceString(sTempMessage, 300, "{timeleftraw}", sTimeLeftRaw);
			ReplaceString(sTempMessage, 300, "{hostname}", sHostname);
			ReplaceString(sTempMessage, 300, "{serverip}", sIPAddress);
			ReplaceString(sTempMessage, 300, "{map}", gS_Map);

			Shavit_PrintToChat(i, "%s", sTempMessage);
		}
	}

	if(++gI_AdvertisementsCycle >= gA_Advertisements.Length)
	{
		gI_AdvertisementsCycle = 0;
	}

	return Plugin_Continue;
}

void UpdateScoreboard(int client)
{
	// this doesn't work on tf2 probably because of CTFGameRules::CalcPlayerScore
	if(gEV_Type == Engine_TF2)
	{
		return;
	}

	float fPB = Shavit_GetClientPB(client, 0, Track_Main);

	int iScore = (fPB != 0.0 && fPB < 2000)? -RoundToFloor(fPB):-2000;

	if(gEV_Type == Engine_CSGO)
	{
		CS_SetClientContributionScore(client, iScore);
	}
	else
	{
		SetEntProp(client, Prop_Data, "m_iFrags", iScore);
	}

	if(gB_Rankings)
	{
		SetEntProp(client, Prop_Data, "m_iDeaths", Shavit_GetRank(client));
	}
}

void UpdateClanTag(int client)
{
	// no clan tags in tf2
	char sCustomTag[32];
	gCV_ClanTag.GetString(sCustomTag, 32);

	if(gEV_Type == Engine_TF2 || StrEqual(sCustomTag, "0"))
	{
		return;
	}

	char sTime[16];

	float fTime = Shavit_GetClientTime(client);

	if(Shavit_GetTimerStatus(client) == Timer_Stopped || fTime < 1.0)
	{
		strcopy(sTime, 16, "N/A");
	}
	else
	{
		FormatSeconds(fTime, sTime, sizeof(sTime), false, true);
	}

	int track = Shavit_GetClientTrack(client);
	char sTrack[4];

	if(track != Track_Main)
	{
		sTrack[0] = 'B';
		if (track > Track_Bonus)
		{
			sTrack[1] = '0' + track;
		}
	}

	char sRank[8];

	if(gB_Rankings)
	{
		IntToString(Shavit_GetRank(client), sRank, 8);
	}

	ReplaceString(sCustomTag, 32, "{style}", gS_StyleStrings[gI_Style[client]].sStyleName);
	ReplaceString(sCustomTag, 32, "{styletag}", gS_StyleStrings[gI_Style[client]].sClanTag);
	ReplaceString(sCustomTag, 32, "{time}", sTime);
	ReplaceString(sCustomTag, 32, "{tr}", sTrack);
	ReplaceString(sCustomTag, 32, "{rank}", sRank);

	if(gB_Chat)
	{
		char sChatrank[32];
		Shavit_GetPlainChatrank(client, sChatrank, sizeof(sChatrank), false);
		ReplaceString(sCustomTag, 32, "{cr}", sChatrank);
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnClanTagChangePre);
	Call_PushCell(client);
	Call_PushStringEx(sCustomTag, 32, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(32);
	Call_Finish(result);
	
	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}

	CS_SetClientClanTag(client, sCustomTag);

	Call_StartForward(gH_Forwards_OnClanTagChangePost);
	Call_PushCell(client);
	Call_PushStringEx(sCustomTag, 32, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(32);
	Call_Finish();
}

void RemoveRagdoll(int client)
{
	int iEntity = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");

	if(iEntity != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(iEntity, "Kill");
	}
}

public void Shavit_OnPause(int client, int track)
{
	if (gB_Eventqueuefix)
	{
		SetClientEventsPaused(client, true);
	}

	if (!gB_SaveStates[client])
	{
		PersistData(client, false);
	}
}

public void Shavit_OnResume(int client, int track)
{
	if (gB_Eventqueuefix)
	{
		SetClientEventsPaused(client, false);
	}

	if (gB_SaveStates[client])
	{
		// events&outputs won't work properly unless we do this next frame...
		RequestFrame(LoadPersistentData, GetClientSerial(client));
	}
}

public void Shavit_OnStop(int client, int track)
{
	if (gB_Eventqueuefix)
	{
		SetClientEventsPaused(client, false);
	}

	if (gB_SaveStates[client])
	{
		DeletePersistentDataFromClient(client);
	}
}

// This is used instead of `TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed)`.
// Why: TeleportEntity somehow triggers the zone EndTouch which fucks with `Shavit_InsideZone`.
void DumbSetVelocity(int client, float fSpeed[3])
{
	// Someone please let me know if any of these are unnecessary.
	SetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", NULL_VECTOR);
	SetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);
	SetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed); // m_vecBaseVelocity+m_vecVelocity
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style)
{
	bool bNoclip = (GetEntityMoveType(client) == MOVETYPE_NOCLIP);
	bool bInStart = Shavit_InsideZone(client, Zone_Start, track);

	// i will not be adding a setting to toggle this off
	if(bNoclip)
	{
		if(status == Timer_Running)
		{
			Shavit_StopTimer(client);
		}
		if(bInStart && gCV_RestrictNoclip.BoolValue)
		{
			if(gCV_RestrictNoclip.IntValue == 1)
			{
				float fSpeed[3];
				GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);
				fSpeed[2] = 0.0;
				DumbSetVelocity(client, fSpeed);
			}
			else if(gCV_RestrictNoclip.IntValue == 2)
			{
				SetEntityMoveType(client, MOVETYPE_ISOMETRIC);
			}
		}
	}

	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");

	// prespeed
	if(!bNoclip && Shavit_GetStyleSettingInt(gI_Style[client], "prespeed") == 0 && bInStart)
	{
		int iPrevGroundEntity = (gI_GroundEntity[client] != -1) ? EntRefToEntIndex(gI_GroundEntity[client]) : -1;
		if((gCV_PreSpeed.IntValue == 2 || gCV_PreSpeed.IntValue == 3) && iPrevGroundEntity == -1 && iGroundEntity != -1 && (buttons & IN_JUMP) > 0)
		{
			DumbSetVelocity(client, view_as<float>({0.0, 0.0, 0.0}));
		}
		else if(gCV_PreSpeed.IntValue == 1 || gCV_PreSpeed.IntValue >= 3)
		{
			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);

			float fLimit = (Shavit_GetStyleSettingFloat(gI_Style[client], "runspeed") + gCV_PrestrafeLimit.FloatValue);

			// if trying to jump, add a very low limit to stop prespeeding in an elegant way
			// otherwise, make sure nothing weird is happening (such as sliding at ridiculous speeds, at zone enter)
			if(gCV_PreSpeed.IntValue < 4 && fSpeed[2] > 0.0)
			{
				fLimit /= 3.0;
			}

			float fSpeedXY = (SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)));
			float fScale = (fLimit / fSpeedXY);

			if(fScale < 1.0)
			{
				if(gCV_PreSpeed.IntValue == 5)
				{
					float zSpeed = fSpeed[2];
					fSpeed[2] = 0.0;
					
					ScaleVector(fSpeed, fScale);
					fSpeed[2] = zSpeed;
				}
				else
				{
					ScaleVector(fSpeed, fScale);
				}
			}

			DumbSetVelocity(client, fSpeed);
		}
	}

	gI_GroundEntity[client] = (iGroundEntity != -1) ? EntIndexToEntRef(iGroundEntity) : -1;

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_SetTransmit, OnSetTransmit);
	SDKHook(client, SDKHook_WeaponDrop, OnWeaponDrop);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	gI_LastWeaponTick[client] = 0;
	gI_LastNoclipTick[client] = 0;

	if(IsFakeClient(client))
	{
		if (gCV_BotFootsteps.BoolValue && gH_UpdateStepSound != null)
		{
			gH_UpdateStepSound.HookEntity(Hook_Pre,  client, Hook_UpdateStepSound_Pre);
			gH_UpdateStepSound.HookEntity(Hook_Post, client, Hook_UpdateStepSound_Post);
		}
		return;
	}

	if(gEV_Type == Engine_TF2)
	{
		SDKHook(client, SDKHook_PreThinkPost, TF2_OnPreThink);
	}
	else
	{
		if(gH_GetPlayerMaxSpeed != null)
		{
			DHookEntity(gH_GetPlayerMaxSpeed, true, client);
		}
	}

	if(!AreClientCookiesCached(client))
	{
		gI_Style[client] = Shavit_GetBhopStyle(client);
		gB_Hide[client] = false;
		gI_CheckpointsSettings[client] = CP_DEFAULT;
	}

	if(gA_Checkpoints[client] == null)
	{
		gA_Checkpoints[client] = new ArrayList(sizeof(cp_cache_t));	
	}
	else 
	{
		ResetCheckpoints(client);
	}

	gB_SaveStates[client] = false;
	gB_ClosedKZCP[client] = false;
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

public void OnClientDisconnect(int client)
{
	if(gCV_NoWeaponDrops.BoolValue)
	{
		if (IsClientInGame(client))
		{
			RemoveAllWeapons(client);
		}
	}

	if(IsFakeClient(client))
	{
		return;
	}

	PersistData(client, true);

	// if data wasn't persisted, then we have checkpoints to reset...
	ResetCheckpoints(client);
	delete gA_Checkpoints[client];
}

int FindPersistentData(int client, persistent_data_t aData)
{
	int iSteamID;

	if((iSteamID = GetSteamAccountID(client)) != 0)
	{
		int index = gA_PersistentData.FindValue(iSteamID, 0);

		if (index != -1)
		{
			gA_PersistentData.GetArray(index, aData);
			return index;
		}
	}

	return -1;
}

void PersistData(int client, bool disconnected)
{
	if(!IsClientInGame(client) ||
		(!IsPlayerAlive(client) && !disconnected) ||
		(!IsPlayerAlive(client) && disconnected && !gB_SaveStates[client]) ||
		GetSteamAccountID(client) == 0 ||
		//Shavit_GetTimerStatus(client) == Timer_Stopped ||
		(!gCV_RestoreStates.BoolValue && !disconnected) ||
		(gCV_PersistData.IntValue == 0 && disconnected))
	{
		return;
	}

	persistent_data_t aData;
	int iIndex = FindPersistentData(client, aData);

	aData.iSteamID = GetSteamAccountID(client);
	aData.iTimesTeleported = gI_TimesTeleported[client];

	if (disconnected)
	{
		aData.iDisconnectTime = GetTime();
		aData.iCurrentCheckpoint = gI_CurrentCheckpoint[client];
		aData.aCheckpoints = gA_Checkpoints[client];
		gA_Checkpoints[client] = null;

		if (gB_Replay && aData.cpcache.aFrames == null)
		{
			aData.cpcache.aFrames = Shavit_GetReplayData(client, true);
			aData.cpcache.iPreFrames = Shavit_GetPlayerPreFrames(client);
		}
	}
	else
	{
		aData.iDisconnectTime = 0;
	}

	if (!gB_SaveStates[client])
	{
		SaveCheckpointCache(client, aData.cpcache, false);
	}

	gB_SaveStates[client] = true;

	if (iIndex == -1)
	{
		gA_PersistentData.PushArray(aData);
	}
	else
	{
		gA_PersistentData.SetArray(iIndex, aData);
	}
}

void DeletePersistentData(int index, persistent_data_t data)
{
	gA_PersistentData.Erase(index);
	DeleteCheckpointCache(data.cpcache);
	DeleteCheckpointCacheList(data.aCheckpoints);
	delete data.aCheckpoints;
}

void LoadPersistentData(int serial)
{
	int client = GetClientFromSerial(serial);

	if(client == 0 ||
		GetSteamAccountID(client) == 0 ||
		GetClientTeam(client) < 2 ||
		!IsPlayerAlive(client))
	{
		return;
	}

	persistent_data_t aData;
	int iIndex = FindPersistentData(client, aData);

	if (iIndex == -1)
	{
		return;
	}

	LoadCheckpointCache(client, aData.cpcache, true);

	gI_TimesTeleported[client] = aData.iTimesTeleported;

	if (aData.aCheckpoints != null)
	{
		DeleteCheckpointCacheList(gA_Checkpoints[client]);
		delete gA_Checkpoints[client];
		gI_CurrentCheckpoint[client] = aData.iCurrentCheckpoint;
		gA_Checkpoints[client] = aData.aCheckpoints;
		aData.aCheckpoints = null;

		if (gA_Checkpoints[client].Length > 0)
		{
			OpenCheckpointsMenu(client);
		}
	}

	gB_SaveStates[client] = false;
	DeletePersistentData(iIndex, aData);
}

void DeleteCheckpointCache(cp_cache_t cache)
{
	delete cache.aFrames;
	delete cache.aEvents;
	delete cache.aOutputWaits;
}

void DeleteCheckpointCacheList(ArrayList cps)
{
	if (cps != null)
	{
		for(int i = 0; i < cps.Length; i++)
		{
			cp_cache_t cache;
			cps.GetArray(i, cache);
			DeleteCheckpointCache(cache);
		}
		
		cps.Clear();
	}
}

void ResetCheckpoints(int client)
{
	DeleteCheckpointCacheList(gA_Checkpoints[client]);
	gI_CurrentCheckpoint[client] = 0;
}

void ClearViewPunch(int victim)
{
	if (1 <= victim <= MaxClients)
	{
		if(gEV_Type == Engine_CSGO)
		{
			SetEntPropVector(victim, Prop_Send, "m_viewPunchAngle", NULL_VECTOR);
			SetEntPropVector(victim, Prop_Send, "m_aimPunchAngle", NULL_VECTOR);
			SetEntPropVector(victim, Prop_Send, "m_aimPunchAngleVel", NULL_VECTOR);
		}
		else
		{
			SetEntPropVector(victim, Prop_Send, "m_vecPunchAngle", NULL_VECTOR);
			SetEntPropVector(victim, Prop_Send, "m_vecPunchAngleVel", NULL_VECTOR);
		}
	}
}

public Action OnTakeDamage(int victim, int& attacker)
{
	bool bBlockDamage;

	switch(gCV_GodMode.IntValue)
	{
		case 0:
		{
			bBlockDamage = false;
		}
		case 1:
		{
			// 0 - world/fall damage
			if(attacker == 0)
			{
				bBlockDamage = true;
			}
		}
		case 2:
		{
			if(IsValidClient(attacker))
			{
				bBlockDamage = true;
			}
		}
		default:
		{
			bBlockDamage = true;
		}
	}

	if (gB_Hide[victim] || bBlockDamage || IsFakeClient(victim))
	{
		ClearViewPunch(victim);

		for (int i = 1; i <= MaxClients; i++)
		{
			if (i != victim && IsValidClient(i) && GetSpectatorTarget(i) == victim)
			{
				ClearViewPunch(i);
			}
		}
	}

	return bBlockDamage ? Plugin_Handled : Plugin_Continue;
}

public void OnWeaponDrop(int client, int entity)
{
	if(gCV_NoWeaponDrops.BoolValue && IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}
}

// hide
public Action OnSetTransmit(int entity, int client)
{
	if(gB_Hide[client] && client != entity && (!IsClientObserver(client) || (GetEntProp(client, Prop_Send, "m_iObserverMode") != 6 &&
		GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") != entity)))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public void TF2_OnPreThink(int client)
{
	if(IsPlayerAlive(client))
	{
		float maxspeed;
		
		if (GetEntityFlags(client) & FL_ONGROUND)
		{
			maxspeed = Shavit_GetStyleSettingFloat(gI_Style[client], "runspeed");
		}
		else
		{
			// This is used to stop CTFGameMovement::PreventBunnyJumping from destroying
			// player velocity when doing uncrouch stuff. Kind of poopy.
			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);
			maxspeed = GetVectorLength(fSpeed);
		}

		// not the best method, but only one i found for tf2
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", maxspeed);
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	if(IsChatTrigger() && gCV_HideChatCommands.BoolValue)
	{
		// hide commands
		return Plugin_Handled;
	}

	if(sArgs[0] == '!' || sArgs[0] == '/')
	{
		bool bUpper = false;
		char buf[200];
		int size = strcopy(buf, sizeof(buf), sArgs[1]);

		for(int i = 0; i < size; i++)
		{
			if (buf[i] == ' ' || buf[i] == '\n' || buf[i] == '\t')
			{
				break;
			}

			if (IsCharUpper(buf[i]))
			{
				buf[i] = CharToLower(buf[i]);
				bUpper = true;
			}
		}

		if(bUpper)
		{
			FakeClientCommandEx(client, "sm_%s", buf);
			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
}

public Action Command_Hide(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gB_Hide[client] = !gB_Hide[client];
	SetClientCookie(client, gH_HideCookie, gB_Hide[client] ? "1" : "0");

	if(gB_Hide[client])
	{
		Shavit_PrintToChat(client, "%T", "HideEnabled", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
	else
	{
		Shavit_PrintToChat(client, "%T", "HideDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

public Action Command_Spec(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	CleanSwitchTeam(client, 1);

	int target = -1;

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		target = FindTarget(client, sArgs, false, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}
	else if(gB_Replay)
	{
		target = Shavit_GetReplayBotIndex(0, -1); // try to find normal bot

		if (target < 1)
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i, true) && IsFakeClient(i))
				{
					target = i;
					break;
				}
			}
		}
	}

	if(IsValidClient(target, true))
	{
		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target);
	}

	return Plugin_Handled;
}

public Action Command_ToggleAdverts(int client, int args)
{
	if (IsValidClient(client))
	{
		char sCookie[4];
		gH_BlockAdvertsCookie.Get(client, sCookie, sizeof(sCookie));
		gH_BlockAdvertsCookie.Set(client, (sCookie[0] == '1') ? "0" : "1");
		Shavit_PrintToChat(client, "%T", (sCookie[0] == '1') ? "AdvertisementsEnabled" : "AdvertisementsDisabled", client);
	}

	return Plugin_Handled;
}

public Action Command_Teleport(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gCV_TeleportCommands.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		int iTarget = FindTarget(client, sArgs, false, false);

		if(iTarget == -1)
		{
			return Plugin_Handled;
		}

		Teleport(client, GetClientSerial(iTarget));
	}

	else
	{
		Menu menu = new Menu(MenuHandler_Teleport);
		menu.SetTitle("%T", "TeleportMenuTitle", client);

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i, true) || i == client)
			{
				continue;
			}

			char serial[16];
			IntToString(GetClientSerial(i), serial, 16);

			char sName[MAX_NAME_LENGTH];
			GetClientName(i, sName, MAX_NAME_LENGTH);

			menu.AddItem(serial, sName);
		}

		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}

	return Plugin_Handled;
}

public int MenuHandler_Teleport(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(!Teleport(param1, StringToInt(sInfo)))
		{
			Command_Teleport(param1, 0);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

bool Teleport(int client, int targetserial)
{
	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "TeleportAlive", client);

		return false;
	}

	int iTarget = GetClientFromSerial(targetserial);

	if(iTarget == 0)
	{
		Shavit_PrintToChat(client, "%T", "TeleportInvalidTarget", client);

		return false;
	}

	float vecPosition[3];
	GetClientAbsOrigin(iTarget, vecPosition);

	Shavit_StopTimer(client);

	TeleportEntity(client, vecPosition, NULL_VECTOR, NULL_VECTOR);

	return true;
}

public Action Hook_GunTouch(int entity, int client)
{
	if (1 <= client <= MaxClients)
	{
		char classname[64];
		GetEntityClassname(entity, classname, sizeof(classname));

		if (StrEqual(classname, "weapon_glock"))
		{
			if (!IsValidClient(client) || !IsFakeClient(client))
			{
				SetEntProp(entity, Prop_Send, "m_bBurstMode", 1);
			}
		}
		else if (gEV_Type == Engine_CSS && StrEqual(classname, "weapon_usp"))
		{
			SetEntProp(entity, Prop_Send, "m_bSilencerOn", 1);
			SetEntProp(entity, Prop_Send, "m_weaponMode", 1);
			SetEntPropFloat(entity, Prop_Send, "m_flDoneSwitchingSilencer", GetGameTime() - 0.1);  
		}
	}

	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (((gCV_WeaponsSpawnGood.IntValue & 1) && gEV_Type == Engine_CSS && StrEqual(classname, "weapon_usp"))
	||  ((gCV_WeaponsSpawnGood.IntValue & 2) && StrEqual(classname, "weapon_glock")))
	{
		SDKHook(entity, SDKHook_Touch, Hook_GunTouch);
	}
}

public Action Command_Weapon(int client, int args)
{
	if(!IsValidClient(client) || gEV_Type == Engine_TF2)
	{
		return Plugin_Handled;
	}

	if(gCV_WeaponCommands.IntValue == 0)
	{
		Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "WeaponAlive", client, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if (GetGameTickCount() - gI_LastWeaponTick[client] < 10)
	{
		return Plugin_Handled;
	}

	gI_LastWeaponTick[client] = GetGameTickCount();

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	int iSlot = CS_SLOT_SECONDARY;
	char sWeapon[32];

	if(StrContains(sCommand, "usp", false) != -1)
	{
		strcopy(sWeapon, 32, (gEV_Type == Engine_CSS)? "weapon_usp":"weapon_usp_silencer");
	}
	else if(StrContains(sCommand, "glock", false) != -1)
	{
		strcopy(sWeapon, 32, "weapon_glock");
	}
	else
	{
		strcopy(sWeapon, 32, "weapon_knife");
		iSlot = CS_SLOT_KNIFE;
	}

	int iWeapon = GetPlayerWeaponSlot(client, iSlot);

	if(iWeapon != -1)
	{
		RemovePlayerItem(client, iWeapon);
		AcceptEntityInput(iWeapon, "Kill");
	}

	iWeapon = GivePlayerItem(client, sWeapon);
	FakeClientCommand(client, "use %s", sWeapon);

	if(iSlot != CS_SLOT_KNIFE)
	{
		SetWeaponAmmo(client, iWeapon, false);
	}

	return Plugin_Handled;
}

void SetWeaponAmmo(int client, int weapon, bool setClip1)
{
	int iAmmo = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	SetEntProp(client, Prop_Send, "m_iAmmo", 255, 4, iAmmo);

	if(gEV_Type == Engine_CSGO)
	{
		SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", 255);
	}

	if (gCV_WeaponCommands.IntValue >= 3 && setClip1)
	{
		int amount = GetEntProp(weapon, Prop_Send, "m_iClip1") + 1;

		if (HasEntProp(weapon, Prop_Send, "m_bBurstMode") && GetEntProp(weapon, Prop_Send, "m_bBurstMode"))
		{
			amount += 2;
		}

		SetEntProp(weapon, Prop_Data, "m_iClip1", amount);
	}
}

public Action Command_Checkpoints(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	if(Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints"))
	{
		gB_ClosedKZCP[client] = false;
	}

	return OpenCheckpointsMenu(client);
}

public Action Command_Save(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	bool bSegmenting = CanSegment(client);

	if(!gCV_Checkpoints.BoolValue && !bSegmenting)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(SaveCheckpoint(client))
	{ 
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsSaved", client, gI_CurrentCheckpoint[client], gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		if (gB_InCheckpointMenu[client])
		{
			OpenNormalCPMenu(client);
		}
	}

	return Plugin_Handled;
}

public Action Command_Tele(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	if(!gCV_Checkpoints.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	int index = gI_CurrentCheckpoint[client];

	if(args > 0)
	{
		char arg[8];
		GetCmdArg(1, arg, sizeof(arg));

		int parsed = StringToInt(arg);

		if(0 < parsed <= gCV_MaxCP.IntValue)
		{
			index = parsed;
		}
	}

	TeleportToCheckpoint(client, index, true);

	return Plugin_Handled;
}

public Action OpenCheckpointsMenu(int client)
{
	if(Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints"))
	{
		OpenKZCPMenu(client);
	}
	else
	{
		OpenNormalCPMenu(client);
	}

	return Plugin_Handled;
}

void OpenKZCPMenu(int client)
{
	// if we're segmenting, resort to the normal checkpoints instead
	if(CanSegment(client))
	{
		OpenNormalCPMenu(client);

		return;
	}
	Menu menu = new Menu(MenuHandler_KZCheckpoints, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	menu.SetTitle("%T\n", "MiscCheckpointMenu", client);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "MiscCheckpointSave", client, (gA_Checkpoints[client].Length + 1));
	menu.AddItem("save", sDisplay, (gA_Checkpoints[client].Length < gCV_MaxCP.IntValue)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	if(gA_Checkpoints[client].Length > 0)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, gI_CurrentCheckpoint[client]);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DEFAULT);
	}
	else
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, 1);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DISABLED);
	}

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointPrevious", client);
	menu.AddItem("prev", sDisplay);

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointNext", client);
	menu.AddItem("next", sDisplay);

	if((Shavit_CanPause(client) & CPR_ByConVar) == 0)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointPause", client);
		menu.AddItem("pause", sDisplay);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_KZCheckpoints(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(CanSegment(param1) || !Shavit_GetStyleSettingInt(gI_Style[param1], "kzcheckpoints"))
		{
			return 0;
		}

		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		if(StrEqual(sInfo, "save"))
		{
			if(gA_Checkpoints[param1].Length < gCV_MaxCP.IntValue)
			{
				SaveCheckpoint(param1);
			}
		}
		else if(StrEqual(sInfo, "tele"))
		{
			TeleportToCheckpoint(param1, gI_CurrentCheckpoint[param1], true);
		}
		else if(StrEqual(sInfo, "prev"))
		{
			if(gI_CurrentCheckpoint[param1] > 1)
			{
				gI_CurrentCheckpoint[param1]--;
			}
		}
		else if(StrEqual(sInfo, "next"))
		{
			if(gI_CurrentCheckpoint[param1] < gA_Checkpoints[param1].Length)
				gI_CurrentCheckpoint[param1]++;
		}
		else if(StrEqual(sInfo, "pause"))
		{
			if(Shavit_CanPause(param1) == 0)
			{
				if(Shavit_IsPaused(param1))
				{
					Shavit_ResumeTimer(param1, true);
				}
				else
				{
					Shavit_PauseTimer(param1);
				}
			}
		}

		OpenCheckpointsMenu(param1);
	}

	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_Exit)
		{
			gB_ClosedKZCP[param1] = true;
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenNormalCPMenu(int client)
{
	bool bSegmented = CanSegment(client);

	if(!gCV_Checkpoints.BoolValue && !bSegmented)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return;
	}

	Menu menu = new Menu(MenuHandler_Checkpoints, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem|MenuAction_Display);

	if(!bSegmented)
	{
		menu.SetTitle("%T\n%T\n ", "MiscCheckpointMenu", client, "MiscCheckpointWarning", client);
	}

	else
	{
		menu.SetTitle("%T\n ", "MiscCheckpointMenuSegmented", client);
	}

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "MiscCheckpointSave", client, (gA_Checkpoints[client].Length + 1));
	menu.AddItem("save", sDisplay, ITEMDRAW_DEFAULT);

	if(gA_Checkpoints[client].Length > 0)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, gI_CurrentCheckpoint[client]);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DEFAULT);
	}
	else
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, 1);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DISABLED);
	}

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointPrevious", client);
	menu.AddItem("prev", sDisplay, (gI_CurrentCheckpoint[client] > 1)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "%T\n ", "MiscCheckpointNext", client);
	menu.AddItem("next", sDisplay, (gI_CurrentCheckpoint[client] < gA_Checkpoints[client].Length)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	// apparently this is the fix
	// menu.AddItem("spacer", "", ITEMDRAW_RAWLINE);

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointDeleteCurrent", client);
	menu.AddItem("del", sDisplay, (gA_Checkpoints[client].Length > 0) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointReset", client);
	menu.AddItem("reset", sDisplay);
	if(!bSegmented)
	{
		char sInfo[16];
		IntToString(CP_ANGLES, sInfo, 16);
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointUseAngles", client);
		menu.AddItem(sInfo, sDisplay);

		IntToString(CP_VELOCITY, sInfo, 16);
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointUseVelocity", client);
		menu.AddItem(sInfo, sDisplay);
	}

	menu.Pagination = MENU_NO_PAGINATION;
	menu.ExitButton = true;

	Call_StartForward(gH_Forwards_OnCheckpointMenuMade);
	Call_PushCell(client);
	Call_PushCell(bSegmented);

	Action result = Plugin_Continue;
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Checkpoints(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		int iMaxCPs = GetMaxCPs(param1);
		int iCurrent = gI_CurrentCheckpoint[param1];

		Call_StartForward(gH_Forwards_OnCheckpointMenuSelect);
		Call_PushCell(param1);
		Call_PushCell(param2);
		Call_PushStringEx(sInfo, 16, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
		Call_PushCell(16); 
		Call_PushCell(iCurrent);
		Call_PushCell(iMaxCPs);

		Action result = Plugin_Continue;
		Call_Finish(result);

		if(result != Plugin_Continue)
		{
			return 0;
		}

		if(StrEqual(sInfo, "save"))
		{
			SaveCheckpoint(param1);
		}
		else if(StrEqual(sInfo, "tele"))
		{
			TeleportToCheckpoint(param1, iCurrent, true);
		}
		else if(StrEqual(sInfo, "prev"))
		{
			gI_CurrentCheckpoint[param1]--;
		}
		else if(StrEqual(sInfo, "next"))
		{
			gI_CurrentCheckpoint[param1]++;
		}
		else if(StrEqual(sInfo, "del"))
		{
			if(DeleteCheckpoint(param1, gI_CurrentCheckpoint[param1]))
			{
				if(gI_CurrentCheckpoint[param1] > gA_Checkpoints[param1].Length)
				{
					gI_CurrentCheckpoint[param1] = gA_Checkpoints[param1].Length;
				}
			}
		}
		else if(StrEqual(sInfo, "reset"))
		{
			ConfirmCheckpointsDeleteMenu(param1);
			gB_InCheckpointMenu[param1] = false;

			return 0;
		}
		else if(!StrEqual(sInfo, "spacer"))
		{
			char sCookie[8];
			gI_CheckpointsSettings[param1] ^= StringToInt(sInfo);
			IntToString(gI_CheckpointsSettings[param1], sCookie, 16);

			SetClientCookie(param1, gH_CheckpointsCookie, sCookie);
		}

		OpenCheckpointsMenu(param1);
	}
	else if(action == MenuAction_DisplayItem)
	{
		char sInfo[16];
		char sDisplay[64];
		int style = 0;
		menu.GetItem(param2, sInfo, 16, style, sDisplay, 64);

		if(StringToInt(sInfo) == 0)
		{
			return 0;
		}

		Format(sDisplay, 64, "[%s] %s", ((gI_CheckpointsSettings[param1] & StringToInt(sInfo)) > 0)? "x":" ", sDisplay);

		return RedrawMenuItem(sDisplay);
	}
	else if (action == MenuAction_Display)
	{
		gB_InCheckpointMenu[param1] = true;
	}
	else if (action == MenuAction_Cancel)
	{
		gB_InCheckpointMenu[param1] = false;
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void ConfirmCheckpointsDeleteMenu(int client)
{
	Menu hMenu = new Menu(MenuHandler_CheckpointsDelete);
	hMenu.SetTitle("%T\n ", "ClearCPWarning", client);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "ClearCPYes", client);
	hMenu.AddItem("yes", sDisplay);

	FormatEx(sDisplay, 64, "%T", "ClearCPNo", client);
	hMenu.AddItem("no", sDisplay);

	hMenu.ExitButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_CheckpointsDelete(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		if(StrEqual(sInfo, "yes"))
		{
			ResetCheckpoints(param1);
		}

		OpenCheckpointsMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

bool SaveCheckpoint(int client)
{
	// ???
	// nairda somehow triggered an error that requires this
	if(!IsValidClient(client))
	{
		return false;
	}

	int target = GetSpectatorTarget(client, client);

	if (target > MaxClients)
	{
		// TODO: Replay_Prop...
		return false;
	}

	if(target == client && !IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAliveSpectate", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

	if(Shavit_IsPaused(client) || Shavit_IsPaused(target))
	{
		Shavit_PrintToChat(client, "%T", "CommandNoPause", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

	if(Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints"))
	{
		if((GetEntityFlags(client) & FL_ONGROUND) == 0 || client != target)
		{
			Shavit_PrintToChat(client, "%T", "CommandSaveCPKZInvalid", client);

			return false;
		}

		if(Shavit_InsideZone(client, Zone_Start, -1))
		{
			Shavit_PrintToChat(client, "%T", "CommandSaveCPKZZone", client);
			
			return false;
		}
	}

	if (IsFakeClient(target))
	{
		int style = Shavit_GetReplayBotStyle(target);
		int track = Shavit_GetReplayBotTrack(target);

		if(style < 0 || track < 0)
		{
			Shavit_PrintToChat(client, "%T", "CommandAliveSpectate", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
			
			return false;
		}
	}

	int iMaxCPs = GetMaxCPs(client);
	bool overflow = (gA_Checkpoints[client].Length >= iMaxCPs);
	int index = (overflow ? iMaxCPs : gA_Checkpoints[client].Length+1);

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnSave);
	Call_PushCell(client);
	Call_PushCell(index);
	Call_PushCell(overflow);
	Call_Finish(result);
	
	if(result != Plugin_Continue)
	{
		return false;
	}

	cp_cache_t cpcache;
	SaveCheckpointCache(target, cpcache, true);
	gI_CurrentCheckpoint[client] = index;

	if(overflow)
	{
		DeleteCheckpoint(client, 1, true);

		if (gA_Checkpoints[client].Length >= iMaxCPs)
		{
			gA_Checkpoints[client].ShiftUp(iMaxCPs-1);
			gA_Checkpoints[client].SetArray(iMaxCPs-1, cpcache);
			return true;
		}
	}

	gA_Checkpoints[client].PushArray(cpcache);
	return true;
}

void SaveCheckpointCache(int target, cp_cache_t cpcache, bool actually_a_checkpoint)
{
	GetClientAbsOrigin(target, cpcache.fPosition);
	GetClientEyeAngles(target, cpcache.fAngles);
	GetEntPropVector(target, Prop_Data, "m_vecAbsVelocity", cpcache.fVelocity);
	GetEntPropVector(target, Prop_Data, "m_vecLadderNormal", cpcache.vecLadderNormal);

	cpcache.iMoveType = GetEntityMoveType(target);
	cpcache.fGravity = GetEntityGravity(target);
	cpcache.fSpeed = GetEntPropFloat(target, Prop_Send, "m_flLaggedMovementValue");

	if(IsFakeClient(target))
	{
		cpcache.iGroundEntity = -1;

		if (cpcache.iMoveType == MOVETYPE_NOCLIP)
		{
			cpcache.iMoveType = MOVETYPE_WALK;
		}
	}
	else
	{
		cpcache.iGroundEntity = GetEntPropEnt(target, Prop_Data, "m_hGroundEntity");

		if (cpcache.iGroundEntity != -1)
		{
			cpcache.iGroundEntity = EntIndexToEntRef(cpcache.iGroundEntity);
		}

		GetEntityClassname(target, cpcache.sClassname, 64);
		GetEntPropString(target, Prop_Data, "m_iName", cpcache.sTargetname, 64);
	}

	if (cpcache.iMoveType == MOVETYPE_NONE || (cpcache.iMoveType == MOVETYPE_NOCLIP && actually_a_checkpoint))
	{
		cpcache.iMoveType = MOVETYPE_WALK;
	}

	cpcache.iFlags = GetEntityFlags(target) & ~(FL_ATCONTROLS|FL_FAKECLIENT);

	if(gEV_Type != Engine_TF2)
	{
		cpcache.fStamina = GetEntPropFloat(target, Prop_Send, "m_flStamina");
		cpcache.bDucked = view_as<bool>(GetEntProp(target, Prop_Send, "m_bDucked"));
		cpcache.bDucking = view_as<bool>(GetEntProp(target, Prop_Send, "m_bDucking"));
	}

	if(gEV_Type == Engine_CSS)
	{
		cpcache.fDucktime = GetEntPropFloat(target, Prop_Send, "m_flDucktime");
	}
	else if(gEV_Type == Engine_CSGO)
	{
		cpcache.fDucktime = GetEntPropFloat(target, Prop_Send, "m_flDuckAmount");
		cpcache.fDuckSpeed = GetEntPropFloat(target, Prop_Send, "m_flDuckSpeed");
	}

	timer_snapshot_t snapshot;

	if(IsFakeClient(target))
	{
		// unfortunately replay bots don't have a snapshot, so we can generate a fake one
		snapshot.bTimerEnabled = true;
		snapshot.fCurrentTime = Shavit_GetReplayTime(target);
		snapshot.bClientPaused = false;
		snapshot.bsStyle = Shavit_GetReplayBotStyle(target);
		snapshot.iJumps = 0;
		snapshot.iStrafes = 0;
		snapshot.iTotalMeasures = 0;
		snapshot.iGoodGains = 0;
		snapshot.fServerTime = GetEngineTime();
		snapshot.iSHSWCombination = -1;
		snapshot.iTimerTrack = Shavit_GetReplayBotTrack(target);
		snapshot.fTimescale = Shavit_GetStyleSettingFloat(snapshot.bsStyle, "timescale");
		snapshot.fTimescaledTicks = (Shavit_GetReplayBotCurrentFrame(target) - Shavit_GetReplayCachePreFrames(target)) * snapshot.fTimescale;
		cpcache.fSpeed = snapshot.fTimescale * Shavit_GetStyleSettingFloat(snapshot.bsStyle, "speed");
		ScaleVector(cpcache.fVelocity, 1 / cpcache.fSpeed);
		cpcache.fGravity = Shavit_GetStyleSettingFloat(target, "gravity");
	}
	else
	{
		Shavit_SaveSnapshot(target, snapshot);
	}

	cpcache.aSnapshot = snapshot;
	cpcache.bSegmented = CanSegment(target);

	if (cpcache.bSegmented && gB_Replay && actually_a_checkpoint && cpcache.aFrames == null)
	{
		cpcache.aFrames = Shavit_GetReplayData(target, false);
		cpcache.iPreFrames = Shavit_GetPlayerPreFrames(target);
	}

	if (gB_Eventqueuefix && !IsFakeClient(target))
	{
		eventpack_t ep;

		if (GetClientEvents(target, ep))
		{
			cpcache.aEvents = ep.playerEvents;
			cpcache.aOutputWaits = ep.outputWaits;
		}
	}

	cpcache.iSteamID = GetSteamAccountID(target);
}

void TeleportToCheckpoint(int client, int index, bool suppressMessage)
{
	if(index < 1 || index > gCV_MaxCP.IntValue || (!gCV_Checkpoints.BoolValue && !CanSegment(client)))
	{
		return;
	}

	if(Shavit_IsPaused(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandNoPause", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return;
	}

	if(index > gA_Checkpoints[client].Length)
	{
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsEmpty", client, index, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return;
	}

	cp_cache_t cpcache;
	gA_Checkpoints[client].GetArray(index - 1, cpcache, sizeof(cp_cache_t));

	if(Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints") != Shavit_GetStyleSettingInt(cpcache.aSnapshot.bsStyle, "kzcheckpoints"))
	{
		Shavit_PrintToChat(client, "%T", "CommandTeleCPInvalid", client);

		return;
	}

	if(IsNullVector(cpcache.fPosition))
	{
		return;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAlive", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return;
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnTeleport);
	Call_PushCell(client);
	Call_PushCell(index);
	Call_Finish(result);
	
	if(result != Plugin_Continue)
	{
		return;
	}

	gI_TimesTeleported[client]++;

	if(Shavit_InsideZone(client, Zone_Start, -1))
	{
		Shavit_StopTimer(client);
	}

	LoadCheckpointCache(client, cpcache, false);
	Shavit_ResumeTimer(client);

	if(!suppressMessage)
	{
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsTeleported", client, index, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
}

bool GetCheckUntouch(int client)
{
	int flags = GetEntProp(client, Prop_Data, "m_iEFlags");
	return (flags & EFL_CHECK_UNTOUCH) != 0;
}

void LoadCheckpointCache(int client, cp_cache_t cpcache, bool isPersistentData)
{
	SetEntityMoveType(client, cpcache.iMoveType);
	SetEntityFlags(client, cpcache.iFlags);

	int ground = (cpcache.iGroundEntity != -1) ? EntRefToEntIndex(cpcache.iGroundEntity) : -1;
	SetEntPropEnt(client, Prop_Data, "m_hGroundEntity", ground);

	if(gEV_Type != Engine_TF2)
	{
		SetEntPropVector(client, Prop_Data, "m_vecLadderNormal", cpcache.vecLadderNormal);
		SetEntPropFloat(client, Prop_Send, "m_flStamina", cpcache.fStamina);
		SetEntProp(client, Prop_Send, "m_bDucked", cpcache.bDucked);
		SetEntProp(client, Prop_Send, "m_bDucking", cpcache.bDucking);
	}

	if(gEV_Type == Engine_CSS)
	{
		SetEntPropFloat(client, Prop_Send, "m_flDucktime", cpcache.fDucktime);
	}
	else if(gEV_Type == Engine_CSGO)
	{
		SetEntPropFloat(client, Prop_Send, "m_flDuckAmount", cpcache.fDucktime);
		SetEntPropFloat(client, Prop_Send, "m_flDuckSpeed", cpcache.fDuckSpeed);
	}

	// this is basically the same as normal checkpoints except much less data is used
	if(!isPersistentData && Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints"))
	{
		TeleportEntity(client, cpcache.fPosition, cpcache.fAngles, view_as<float>({ 0.0, 0.0, 0.0 }));

		return;
	}

	Shavit_LoadSnapshot(client, cpcache.aSnapshot);

	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", cpcache.fSpeed);
	SetEntPropString(client, Prop_Data, "m_iName", cpcache.sTargetname);
	SetEntPropString(client, Prop_Data, "m_iClassname", cpcache.sClassname);

	TeleportEntity(client, cpcache.fPosition,
		((gI_CheckpointsSettings[client] & CP_ANGLES)   > 0 || cpcache.bSegmented || isPersistentData) ? cpcache.fAngles   : NULL_VECTOR,
		((gI_CheckpointsSettings[client] & CP_VELOCITY) > 0 || cpcache.bSegmented || isPersistentData) ? cpcache.fVelocity : NULL_VECTOR);

	// Used to trigger all endtouch booster events which are then wiped via eventqueuefix :)
	if (GetCheckUntouch(client))
	{
		SDKCall(gH_PhysicsCheckForEntityUntouch, client);
	}

	if (cpcache.aSnapshot.bPracticeMode || !(cpcache.bSegmented || isPersistentData) || GetSteamAccountID(client) != cpcache.iSteamID)
	{
		Shavit_SetPracticeMode(client, true, true);
	}
	else
	{
		Shavit_SetPracticeMode(client, false, true);

		float latency = GetClientLatency(client, NetFlow_Both);

		if (gCV_ExperimentalSegmentedEyeAngleFix.BoolValue && latency > 0.0)
		{
			int ticks = RoundToCeil(latency / GetTickInterval()) + 1;
			//PrintToChat(client, "%f %f %d", latency, GetTickInterval(), ticks);
			Shavit_HijackAngles(client, cpcache.fAngles[0], cpcache.fAngles[1], ticks);
		}
	}

	SetEntityGravity(client, cpcache.fGravity);

	if(gB_Replay && cpcache.aFrames != null)
	{
		// if isPersistentData, then CloneHandle() is done instead of ArrayList.Clone()
		Shavit_SetReplayData(client, cpcache.aFrames, isPersistentData);
		Shavit_SetPlayerPreFrames(client, cpcache.iPreFrames);
	}

	if (gB_Eventqueuefix && cpcache.aEvents != null && cpcache.aOutputWaits != null)
	{
		eventpack_t ep;
		ep.playerEvents = cpcache.aEvents;
		ep.outputWaits = cpcache.aOutputWaits;
		SetClientEvents(client, ep);

		#if DEBUG
		PrintToConsole(client, "targetname='%s'", cpcache.sTargetname);

		for (int i = 0; i < cpcache.aEvents.Length; i++)
		{
			event_t e;
			cpcache.aEvents.GetArray(i, e);
			PrintToConsole(client, "%s %s %s %f %i %i %i", e.target, e.targetInput, e.variantValue, e.delay, e.activator, e.caller, e.outputID);
		}
		#endif
	}
}

bool DeleteCheckpoint(int client, int index, bool force=false)
{
	if (index < 1 || index > gA_Checkpoints[client].Length)
	{
		return false;
	}

	Action result = Plugin_Continue;

	if (!force)
	{
		Call_StartForward(gH_Forwards_OnDelete);
		Call_PushCell(client);
		Call_PushCell(index);
		Call_Finish(result);
	}

	if (result != Plugin_Continue)
	{
		return false;
	}

	cp_cache_t cpcache;
	gA_Checkpoints[client].GetArray(index-1, cpcache);
	gA_Checkpoints[client].Erase(index-1);
	DeleteCheckpointCache(cpcache);

	return true;
}

bool ShouldDisplayStopWarning(int client)
{
	return (gCV_StopTimerWarning.BoolValue && Shavit_GetTimerStatus(client) != Timer_Stopped && Shavit_GetClientTime(client) > gCV_StopTimerWarning.FloatValue && !CanSegment(client));
}

void DoNoclip(int client)
{
	Shavit_StopTimer(client);
	SetEntityMoveType(client, MOVETYPE_NOCLIP);
}

void DoStopTimer(int client)
{
	Shavit_StopTimer(client);
}

void OpenStopWarningMenu(int client, StopTimerCallback after)
{
	gH_AfterWarningMenu[client] = after;

	Menu hMenu = new Menu(MenuHandler_StopWarning);
	hMenu.SetTitle("%T\n ", "StopTimerWarning", client);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "StopTimerYes", client);
	hMenu.AddItem("yes", sDisplay);

	FormatEx(sDisplay, 64, "%T", "StopTimerNo", client);
	hMenu.AddItem("no", sDisplay);

	hMenu.ExitButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_StopWarning(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		if(StrEqual(sInfo, "yes"))
		{
			Call_StartFunction(null, gH_AfterWarningMenu[param1]);
			Call_PushCell(param1);
			Call_Finish();
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public bool Shavit_OnStopPre(int client, int track)
{
	if(ShouldDisplayStopWarning(client))
	{
		OpenStopWarningMenu(client, DoStopTimer);

		return false;
	}

	return true;
}

public Action Command_Noclip(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if (gI_LastNoclipTick[client] == GetGameTickCount())
	{
		return Plugin_Handled;
	}

	gI_LastNoclipTick[client] = GetGameTickCount();

	if(gCV_NoclipMe.IntValue == 0)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}
	else if(gCV_NoclipMe.IntValue == 2 && !CheckCommandAccess(client, "admin_noclipme", ADMFLAG_CHEATS))
	{
		Shavit_PrintToChat(client, "%T", "LackingAccess", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAlive", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(GetEntityMoveType(client) != MOVETYPE_NOCLIP)
	{
		if (gCV_PauseMovement.BoolValue && Shavit_IsPaused(client))
		{
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
			return Plugin_Handled;
		}

		if(!ShouldDisplayStopWarning(client))
		{
			Shavit_StopTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
		}
		else
		{
			OpenStopWarningMenu(client, DoNoclip);
		}
	}
	else
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}

	return Plugin_Handled;
}

public Action CommandListener_Noclip(int client, const char[] command, int args)
{
	if(!IsValidClient(client, true))
	{
		return Plugin_Handled;
	}

	if (gI_LastNoclipTick[client] == GetGameTickCount())
	{
		return Plugin_Handled;
	}

	gI_LastNoclipTick[client] = GetGameTickCount();

	if((gCV_NoclipMe.IntValue == 1 || (gCV_NoclipMe.IntValue == 2 && CheckCommandAccess(client, "noclipme", ADMFLAG_CHEATS))) && command[0] == '+')
	{
		if(!ShouldDisplayStopWarning(client))
		{
			Shavit_StopTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
		}

		else
		{
			OpenStopWarningMenu(client, DoNoclip);
		}
	}

	else if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}

	return Plugin_Handled;
}

public Action CommandListener_funcommands_Noclip(int client, const char[] command, int args)
{
	if (IsValidClient(client, true) && args < 1)
	{
		Command_Noclip(client, 0);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action CommandListener_Real_Noclip(int client, const char[] command, int args)
{
	if (sv_cheats.BoolValue)
	{
		if (gI_LastNoclipTick[client] == GetGameTickCount())
		{
			return Plugin_Stop;
		}

		gI_LastNoclipTick[client] = GetGameTickCount();
	}

	return Plugin_Continue;
}

public Action Command_Specs(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	int iObserverTarget = GetSpectatorTarget(client, client);

	if(args > 0)
	{
		char sTarget[MAX_TARGET_LENGTH];
		GetCmdArgString(sTarget, MAX_TARGET_LENGTH);

		int iNewTarget = FindTarget(client, sTarget, false, false);

		if(iNewTarget == -1)
		{
			return Plugin_Handled;
		}

		if(!IsPlayerAlive(iNewTarget))
		{
			Shavit_PrintToChat(client, "%T", "SpectateDead", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

			return Plugin_Handled;
		}

		iObserverTarget = iNewTarget;
	}

	int iCount = 0;
	bool bIsAdmin = CheckCommandAccess(client, "admin_speclisthide", ADMFLAG_KICK);
	char sSpecs[192];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetClientTeam(i) < 1)
		{
			continue;
		}

		if((gCV_SpectatorList.IntValue == 1 && !bIsAdmin && CheckCommandAccess(i, "admin_speclisthide", ADMFLAG_KICK)) ||
			(gCV_SpectatorList.IntValue == 2 && !CanUserTarget(client, i)))
		{
			continue;
		}

		if(GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == iObserverTarget)
		{
			iCount++;

			if(iCount == 1)
			{
				FormatEx(sSpecs, 192, "%s%N", gS_ChatStrings.sVariable2, i);
			}

			else
			{
				Format(sSpecs, 192, "%s%s, %s%N", sSpecs, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, i);
			}
		}
	}

	if(iCount > 0)
	{
		Shavit_PrintToChat(client, "%T", "SpectatorCount", client, gS_ChatStrings.sVariable2, iObserverTarget, gS_ChatStrings.sText, gS_ChatStrings.sVariable, iCount, gS_ChatStrings.sText, sSpecs);
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "SpectatorCountZero", client, gS_ChatStrings.sVariable2, iObserverTarget, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

void ClearClientEventsFrame(int serial)
{
	int client = GetClientFromSerial(serial);

	if (client > 0 && gB_Eventqueuefix)
	{
		ClearClientEvents(client);
	}
}

public Action Shavit_OnStart(int client)
{
	gI_TimesTeleported[client] = 0;

	if (gB_Eventqueuefix)
	{
		SetClientEventsPaused(client, false);
	}

	if(Shavit_GetStyleSettingInt(gI_Style[client], "prespeed") == 0 && GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		return Plugin_Stop;
	}

	if(gCV_ResetTargetname.BoolValue)
	{
		char targetname[64];

		if (Shavit_GetClientTrack(client) == Track_Main)
		{
			gCV_ResetTargetnameMain.GetString(targetname, sizeof(targetname));
		}
		else
		{
			gCV_ResetTargetnameBonus.GetString(targetname, sizeof(targetname));
		}

		DispatchKeyValue(client, "targetname", targetname);
		SetEntPropString(client, Prop_Data, "m_iClassname", "player");

		// Used to clear some (mainly basevelocity) events that can be used to boost out of the start zone.
		if(gB_Eventqueuefix)
		{
			ClearClientEvents(client); // maybe unneeded?
			// The RequestFrame is the on that's actually needed though...
			RequestFrame(ClearClientEventsFrame, GetClientSerial(client));
		}
	}

	if(Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints"))
	{
		ResetCheckpoints(client);
	}

	return Plugin_Continue;
}

public void Shavit_OnWorldRecord(int client, int style, float time, int jumps, int strafes, float sync, int track)
{
	char sUpperCase[64];
	strcopy(sUpperCase, 64, gS_StyleStrings[style].sStyleName);

	for(int i = 0; i < strlen(sUpperCase); i++)
	{
		if(!IsCharUpper(sUpperCase[i]))
		{
			sUpperCase[i] = CharToUpper(sUpperCase[i]);
		}
	}

	char sTrack[32];
	GetTrackName(LANG_SERVER, track, sTrack, 32);

	for(int i = 1; i <= gCV_WRMessages.IntValue; i++)
	{
		if(track == Track_Main)
		{
			Shavit_PrintToChatAll("%t", "WRNotice", gS_ChatStrings.sWarning, sUpperCase);
		}

		else
		{
			Shavit_PrintToChatAll("%s[%s]%s %t", gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText, "WRNotice", gS_ChatStrings.sWarning, sUpperCase);
		}
	}
}

public void Shavit_OnRestart(int client, int track)
{
	if(gEV_Type != Engine_TF2)
	{
		SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
	}

	if(!gB_ClosedKZCP[client] &&
		Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints") &&
		GetClientMenu(client, null) == MenuSource_None &&
		IsPlayerAlive(client) && GetClientTeam(client) >= 2)
	{
		OpenKZCPMenu(client);
	}
}

public Action Shavit_OnRestartPre(int client, int track)
{
	if(gCV_RespawnOnRestart.BoolValue && !IsPlayerAlive(client))
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_ChangeClientTeam(client, view_as<TFTeam>(GetRandomInt(2, 3)));
		}
		else
		{
			CS_SwitchTeam(client, GetRandomInt(2, 3));
		}

		if(gEV_Type == Engine_TF2)
		{
			TF2_RespawnPlayer(client);
		}
		else
		{
			CS_RespawnPlayer(client);
		}

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Respawn(Handle timer, any data)
{
	int client = GetClientFromSerial(data);

	if(IsValidClient(client) && !IsPlayerAlive(client) && GetClientTeam(client) >= 2)
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_RespawnPlayer(client);
		}

		else
		{
			CS_RespawnPlayer(client);
		}

		if(gCV_RespawnOnRestart.BoolValue)
		{
			RestartTimer(client, Track_Main);
		}
	}

	return Plugin_Handled;
}

void RestartTimer(int client, int track)
{
	if((gB_Zones && Shavit_ZoneExists(Zone_Start, track)) || Shavit_IsKZMap())
	{
		Shavit_RestartTimer(client, track);
	}
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsFakeClient(client))
	{
		int serial = GetClientSerial(client);

		if(gCV_HideRadar.BoolValue && gEV_Type == Engine_CSS)
		{
			RequestFrame(Frame_RemoveRadar, serial);
		}

		bool bCanStartOnSpawn = true;

		if(gB_SaveStates[client])
		{
			if(gCV_RestoreStates.BoolValue)
			{
				// events&outputs won't work properly unless we do this next frame...
				RequestFrame(LoadPersistentData, serial);
				bCanStartOnSpawn = false;
			}
		}
		else
		{
			persistent_data_t aData;
			int iIndex = FindPersistentData(client, aData);

			if (iIndex != -1)
			{
				gB_SaveStates[client] = true;
				// events&outputs won't work properly unless we do this next frame...
				RequestFrame(LoadPersistentData, serial);
				bCanStartOnSpawn = false;
			}
		}

		if(gCV_StartOnSpawn.BoolValue && bCanStartOnSpawn)
		{
			RestartTimer(client, Track_Main);
		}

		if(gCV_Scoreboard.BoolValue)
		{
			UpdateScoreboard(client);
		}

		UpdateClanTag(client);

		// refreshes kz cp menu if there is nothing open
		if(!gB_ClosedKZCP[client] &&
			Shavit_GetStyleSettingInt(gI_Style[client], "kzcheckpoints") &&
			GetClientMenu(client, null) == MenuSource_None &&
			IsPlayerAlive(client) && GetClientTeam(client) >= 2)
		{
			OpenKZCPMenu(client);
		}
	}

	if(gCV_NoBlock.BoolValue)
	{
		SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
	}

	if(gCV_PlayerOpacity.IntValue != -1)
	{
		SetEntityRenderMode(client, RENDER_TRANSCOLOR);
		SetEntityRenderColor(client, 255, 255, 255, gCV_PlayerOpacity.IntValue);
	}
}

void RemoveRadar(int client, float salt)
{
	if(client == 0 || !IsPlayerAlive(client))
	{
		return;
	}

	SetEntPropFloat(client, Prop_Send, "m_flFlashDuration", 20.0 + salt);
	SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", 0.5);
}

void Frame_RemoveRadar(any data)
{
	int client = GetClientFromSerial(data);
	RemoveRadar(client, GetURandomFloat());
}

public Action Player_Notifications(Event event, const char[] name, bool dontBroadcast)
{
	if(gCV_HideTeamChanges.BoolValue)
	{
		if (StrEqual(name, "player_team") && gEV_Type == Engine_CSGO)
		{
			event.SetBool("silent", true);
		}
		else
		{
			event.BroadcastDisabled = true;
		}
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsFakeClient(client))
	{
		if(!gB_SaveStates[client])
		{
			PersistData(client, false);
		}

		if(gCV_AutoRespawn.FloatValue > 0.0 && StrEqual(name, "player_death"))
		{
			CreateTimer(gCV_AutoRespawn.FloatValue, Respawn, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	if ((gCV_RemoveRagdolls.IntValue == 1 && IsFakeClient(client)) || gCV_RemoveRagdolls.IntValue == 2)
	{
		RemoveRagdoll(client);
	}

	return Plugin_Continue;
}

public void Weapon_Fire(Event event, const char[] name, bool dB)
{
	if(gCV_WeaponCommands.IntValue < 2)
	{
		return;
	}

	char sWeapon[16];
	event.GetString("weapon", sWeapon, 16);

	if(StrContains(sWeapon, "usp") != -1 || StrContains(sWeapon, "hpk") != -1 || StrContains(sWeapon, "glock") != -1)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		SetWeaponAmmo(client, GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"), true);
	}
}

public Action Shotgun_Shot(const char[] te_name, const int[] Players, int numClients, float delay)
{
	int client = (TE_ReadNum("m_iPlayer") + 1);

	if(!(1 <= client <= MaxClients) || !IsClientInGame(client))
	{
		return Plugin_Continue;
	}

	int ticks = GetGameTickCount();

	if(gI_LastShot[client] == ticks)
	{
		return Plugin_Continue;
	}

	gI_LastShot[client] = ticks;

	int clients[MAXPLAYERS+1];
	int count = 0;

	for(int i = 0; i < numClients; i++)
	{
		int x = Players[i];

		if (!IsClientInGame(x) || x == client)
		{
			continue;
		}

		if (!gB_Hide[x] || GetSpectatorTarget(x) == client)
		{
			clients[count++] = x;
		}
	}

	if(numClients == count)
	{
		return Plugin_Continue;
	}

	TE_Start(te_name);

	float temp[3];
	TE_ReadVector("m_vecOrigin", temp);
	TE_WriteVector("m_vecOrigin", temp);

	TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
	TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
	TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
	TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
	TE_WriteNum("m_iPlayer", (client - 1));

	if(gEV_Type == Engine_CSS)
	{
		TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
		TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
		TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
	}

	else if(gEV_Type == Engine_CSGO)
	{
		TE_WriteNum("m_weapon", TE_ReadNum("m_weapon"));
		TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
		TE_WriteFloat("m_flRecoilIndex", TE_ReadFloat("m_flRecoilIndex"));
		TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
		TE_WriteNum("m_nItemDefIndex", TE_ReadNum("m_nItemDefIndex"));
		TE_WriteNum("m_iSoundType", TE_ReadNum("m_iSoundType"));
	}

	else if(gEV_Type == Engine_TF2)
	{
		TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
		TE_WriteFloat("m_flSpread", TE_ReadFloat("m_flSpread"));
		TE_WriteNum("m_bCritical", TE_ReadNum("m_bCritical"));
	}
	
	TE_Send(clients, count, delay);

	return Plugin_Stop;
}

public Action EffectDispatch(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if(!gCV_NoBlood.BoolValue)
	{
		return Plugin_Continue;
	}

	int iEffectIndex = TE_ReadNum("m_iEffectName");
	int nHitBox = TE_ReadNum("m_nHitBox");

	char sEffectName[32];
	GetEffectName(iEffectIndex, sEffectName, 32);

	if(StrEqual(sEffectName, "csblood"))
	{
		return Plugin_Handled;
	}

	if(StrEqual(sEffectName, "ParticleEffect"))
	{
		char sParticleEffectName[32];
		GetParticleEffectName(nHitBox, sParticleEffectName, 32);

		if(StrEqual(sParticleEffectName, "impact_helmet_headshot") || StrEqual(sParticleEffectName, "impact_physics_dust"))
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action WorldDecal(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if(!gCV_NoBlood.BoolValue)
	{
		return Plugin_Continue;
	}

	float vecOrigin[3];
	TE_ReadVector("m_vecOrigin", vecOrigin);

	int nIndex = TE_ReadNum("m_nIndex");

	char sDecalName[32];
	GetDecalName(nIndex, sDecalName, 32);

	if(StrContains(sDecalName, "decals/blood") == 0 && StrContains(sDecalName, "_subrect") != -1)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action NormalSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (gEV_Type != Engine_CSGO && IsValidClient(entity) && IsFakeClient(entity) && StrContains(sample, "footsteps/") != -1)
	{
		numClients = 0;

		if (gCV_BhopSounds.IntValue < 2)
		{
			// The server removes recipients that are in the PVS because CS:S generates the footsteps clientside.
			// UpdateStepSound clientside bails because of MOVETYPE_NOCLIP though.
			// So fuck it, add all the clients xd.
			// Alternatively and preferably you'd patch out the RemoveRecipientsByPVS call in PlayStepSound.
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i) && (!gB_Hide[i] || GetSpectatorTarget(i) == entity))
				{
					clients[numClients++] = i;
				}
			}
		}

		return Plugin_Changed;
	}

	if(!gCV_BhopSounds.BoolValue)
	{
		return Plugin_Continue;
	}

	if(StrContains(sample, "physics/") != -1 || StrContains(sample, "weapons/") != -1 || StrContains(sample, "player/") != -1 || StrContains(sample, "items/") != -1)
	{
		if(gCV_BhopSounds.IntValue == 2)
		{
			numClients = 0;
		}
		else
		{
			for(int i = 0; i < numClients; ++i)
			{
				if(!IsValidClient(clients[i]) || (clients[i] != entity && gB_Hide[clients[i]] && GetSpectatorTarget(clients[i]) != entity))
				{
					for (int j = i; j < numClients-1; j++)
					{
						clients[j] = clients[j+1];
					}
					
					numClients--;
					i--;
				}
			}
		}

		return Plugin_Changed;
	}
   
	return Plugin_Continue;
}

int GetParticleEffectName(int index, char[] sEffectName, int maxlen)
{
	static int table = INVALID_STRING_TABLE;

	if(table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("ParticleEffectNames");
	}

	return ReadStringTable(table, index, sEffectName, maxlen);
}

int GetEffectName(int index, char[] sEffectName, int maxlen)
{
	static int table = INVALID_STRING_TABLE;

	if(table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("EffectDispatch");
	}

	return ReadStringTable(table, index, sEffectName, maxlen);
}

int GetDecalName(int index, char[] sDecalName, int maxlen)
{
	static int table = INVALID_STRING_TABLE;

	if(table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("decalprecache");
	}

	return ReadStringTable(table, index, sDecalName, maxlen);
}

public void Shavit_OnFinish(int client)
{
	if(!gCV_Scoreboard.BoolValue)
	{
		return;
	}

	UpdateScoreboard(client);
	UpdateClanTag(client);
}

public Action Command_Drop(int client, const char[] command, int argc)
{
	if(!gCV_DropAll.BoolValue || !IsValidClient(client) || gEV_Type == Engine_TF2)
	{
		return Plugin_Continue;
	}

	int iWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

	if(iWeapon != -1 && IsValidEntity(iWeapon) && GetEntPropEnt(iWeapon, Prop_Send, "m_hOwnerEntity") == client)
	{
		CS_DropWeapon(client, iWeapon, true);
	}

	return Plugin_Handled;
}

bool CanSegment(int client)
{
	return StrContains(gS_StyleStrings[gI_Style[client]].sSpecialString, "segments") != -1;
}

int GetMaxCPs(int client)
{
	return CanSegment(client)? gCV_MaxCP_Segmented.IntValue:gCV_MaxCP.IntValue;
}

public any Native_GetCheckpoint(Handle plugin, int numParams)
{
	if(GetNativeCell(4) != sizeof(cp_cache_t))
	{
		return ThrowNativeError(200, "cp_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(4), sizeof(cp_cache_t));
	}

	int client = GetNativeCell(1);
	int index = GetNativeCell(2);

	cp_cache_t cpcache;
	if(gA_Checkpoints[client].GetArray(index-1, cpcache, sizeof(cp_cache_t)))
	{
		SetNativeArray(3, cpcache, sizeof(cp_cache_t));
		return true;
	}

	return false;
}

public any Native_SetCheckpoint(Handle plugin, int numParams)
{
	if(GetNativeCell(4) != sizeof(cp_cache_t))
	{
		return ThrowNativeError(200, "cp_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(4), sizeof(cp_cache_t));
	}

	int client = GetNativeCell(1);
	int position = GetNativeCell(2);

	cp_cache_t cpcache;
	GetNativeArray(3, cpcache, sizeof(cp_cache_t));

	if(position == -1)
	{
		position = gI_CurrentCheckpoint[client];
	}

	DeleteCheckpoint(client, position, true);
	gA_Checkpoints[client].SetArray(position-1, cpcache);
	
	return true;
}

public any Native_ClearCheckpoints(Handle plugin, int numParams)
{
	ResetCheckpoints(GetNativeCell(1));
	return 0;
}

public any Native_TeleportToCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int position = GetNativeCell(2);
	bool suppress = GetNativeCell(3);

	TeleportToCheckpoint(client, position, suppress);
	return 0;
}

public any Native_GetTimesTeleported(Handle plugin, int numParams)
{
	return gI_TimesTeleported[GetNativeCell(1)];
}

public any Native_GetTotalCheckpoints(Handle plugin, int numParams)
{
	return gA_Checkpoints[GetNativeCell(1)].Length;
}

public any Native_GetCurrentCheckpoint(Handle plugin, int numParams)
{
	return gI_CurrentCheckpoint[GetNativeCell(1)];
}

public any Native_SetCurrentCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int index = GetNativeCell(2);
	
	gI_CurrentCheckpoint[client] = index;
	return 0;
}

public any Native_OpenCheckpointMenu(Handle plugin, int numParams)
{
	OpenNormalCPMenu(GetNativeCell(1));
	return 0;
}

public any Native_SaveCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if(!CanSegment(client) && gA_Checkpoints[client].Length >= GetMaxCPs(client))
	{
		return -1;
	}

	SaveCheckpoint(client);
	return gI_CurrentCheckpoint[client];
}
