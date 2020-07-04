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

#undef REQUIRE_EXTENSIONS
#include <dhooks>
#include <SteamWorks>
#include <cstrike>
#include <tf2>
#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#include <shavit>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 524288

#define CP_ANGLES				(1 << 0)
#define CP_VELOCITY				(1 << 1)

#define CP_DEFAULT				(CP_ANGLES|CP_VELOCITY)


enum struct player_cpcache_t
{
	int iCheckpoints;
	int iCurrentCheckpoint;
}

enum struct persistent_data_t
{
	int iSteamID;
	float fDisconnectTime;
	float fPosition[3];
	float fAngles[3];
	MoveType iMoveType;
	float fGravity;
	float fSpeed;
	timer_snapshot_t aSnapshot;
	int iTargetname;
	int iClassname;
	ArrayList aFrames;
	int iPreFrames;
	int iTimerPreFrames;
	bool bPractice;
}

typedef StopTimerCallback = function void (int data);

// game specific
EngineVersion gEV_Type = Engine_Unknown;
int gI_Ammo = -1;

char gS_RadioCommands[][] = { "coverme", "takepoint", "holdpos", "regroup", "followme", "takingfire", "go", "fallback", "sticktog",
	"getinpos", "stormfront", "report", "roger", "enemyspot", "needbackup", "sectorclear", "inposition", "reportingin",
	"getout", "negative", "enemydown", "compliment", "thanks", "cheer", "go_a", "go_b", "sorry", "needrop" };

bool gB_Hide[MAXPLAYERS+1];
bool gB_Late = false;
int gI_GroundEntity[MAXPLAYERS+1];
int gI_LastShot[MAXPLAYERS+1];
ArrayList gA_Advertisements = null;
int gI_AdvertisementsCycle = 0;
char gS_CurrentMap[192];
int gI_Style[MAXPLAYERS+1];
Function gH_AfterWarningMenu[MAXPLAYERS+1];
bool gB_ClosedKZCP[MAXPLAYERS+1];

player_cpcache_t gA_CheckpointsCache[MAXPLAYERS+1];
int gI_CheckpointsSettings[MAXPLAYERS+1];
StringMap gSM_Checkpoints = null;
ArrayList gA_Targetnames = null;
ArrayList gA_Classnames = null;

// save states
bool gB_SaveStatesSegmented[MAXPLAYERS+1];
float gF_SaveStateData[MAXPLAYERS+1][3][3];
timer_snapshot_t gA_SaveStates[MAXPLAYERS+1];
bool gB_SaveStates[MAXPLAYERS+1];
char gS_SaveStateTargetname[MAXPLAYERS+1][32];
ArrayList gA_SaveFrames[MAXPLAYERS+1];
ArrayList gA_PersistentData = null;
int gI_SavePreFrames[MAXPLAYERS+1];
int gI_TimerFrames[MAXPLAYERS+1];

// cookies
Handle gH_HideCookie = null;
Handle gH_CheckpointsCookie = null;

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
Convar gCV_PlayerOpacity = null;
Convar gCV_StaticPrestrafe = null;
Convar gCV_NoclipMe = null;
Convar gCV_AdvertisementInterval = null;
Convar gCV_Checkpoints = null;
Convar gCV_RemoveRagdolls = null;
Convar gCV_ClanTag = null;
Convar gCV_DropAll = null;
Convar gCV_ResetTargetname = null;
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

// external cvars
ConVar sv_disable_immunity_alpha = null;
ConVar mp_humanteam = null;
ConVar hostname = null;
ConVar hostport = null;

// forwards
Handle gH_Forwards_OnClanTagChangePre = null;
Handle gH_Forwards_OnClanTagChangePost = null;
Handle gH_Forwards_OnSave = null;
Handle gH_Forwards_OnTeleport = null;
Handle gH_Forwards_OnCheckpointMenuMade = null;
Handle gH_Forwards_OnCheckpointMenuSelect = null;

// dhooks
Handle gH_GetPlayerMaxSpeed = null;

// modules
bool gB_Rankings = false;
bool gB_Replay = false;
bool gB_Zones = false;

// timer settings
stylestrings_t gS_StyleStrings[STYLE_LIMIT];
stylesettings_t gA_StyleSettings[STYLE_LIMIT];

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

	// cache
	gEV_Type = GetEngineVersion();

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
	gSM_Checkpoints = new StringMap();
	gA_Targetnames = new ArrayList(ByteCountToCells(64));
	gA_Classnames = new ArrayList(ByteCountToCells(64));
	gA_PersistentData = new ArrayList(sizeof(persistent_data_t));

	gI_Ammo = FindSendPropInfo("CCSPlayer", "m_iAmmo");

	// noclip
	RegConsoleCmd("sm_p", Command_Noclip, "Toggles noclip.");
	RegConsoleCmd("sm_prac", Command_Noclip, "Toggles noclip. (sm_p alias)");
	RegConsoleCmd("sm_practice", Command_Noclip, "Toggles noclip. (sm_p alias)");
	RegConsoleCmd("sm_nc", Command_Noclip, "Toggles noclip. (sm_p alias)");
	RegConsoleCmd("sm_noclipme", Command_Noclip, "Toggles noclip. (sm_p alias)");
	AddCommandListener(CommandListener_Noclip, "+noclip");
	AddCommandListener(CommandListener_Noclip, "-noclip");

	// hook teamjoins
	AddCommandListener(Command_Jointeam, "jointeam");

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

	// cvars and stuff
	gCV_GodMode = new Convar("shavit_misc_godmode", "3", "Enable godmode for players?\n0 - Disabled\n1 - Only prevent fall/world damage.\n2 - Only prevent damage from other players.\n3 - Full godmode.", 0, true, 0.0, true, 3.0);
	gCV_PreSpeed = new Convar("shavit_misc_prespeed", "1", "Stop prespeeding in the start zone?\n0 - Disabled, fully allow prespeeding.\n1 - Limit relatively to prestrafelimit.\n2 - Block bunnyhopping in startzone.\n3 - Limit to prestrafelimit and block bunnyhopping.\n4 - Limit to prestrafelimit but allow prespeeding. Combine with shavit_core_nozaxisspeed 1 for SourceCode timer's behavior.", 0, true, 0.0, true, 4.0);
	gCV_HideTeamChanges = new Convar("shavit_misc_hideteamchanges", "1", "Hide team changes in chat?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnTeam = new Convar("shavit_misc_respawnonteam", "1", "Respawn whenever a player joins a team?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnRestart = new Convar("shavit_misc_respawnonrestart", "1", "Respawn a dead player if they use the timer restart command?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_StartOnSpawn = new Convar("shavit_misc_startonspawn", "1", "Restart the timer for a player after they spawn?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_PrestrafeLimit = new Convar("shavit_misc_prestrafelimit", "30", "Prestrafe limitation in startzone.\nThe value used internally is style run speed + this.\ni.e. run speed of 250 can prestrafe up to 278 (+28) with regular settings.", 0, true, 0.0, false);
	gCV_HideRadar = new Convar("shavit_misc_hideradar", "1", "Should the plugin hide the in-game radar?", 0, true, 0.0, true, 1.0);
	gCV_TeleportCommands = new Convar("shavit_misc_tpcmds", "1", "Enable teleport-related commands? (sm_goto/sm_tpto)\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoWeaponDrops = new Convar("shavit_misc_noweapondrops", "1", "Remove every dropped weapon.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoBlock = new Convar("shavit_misc_noblock", "1", "Disable player collision?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoBlood = new Convar("shavit_misc_noblood", "0", "Hide blood decals and particles?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_AutoRespawn = new Convar("shavit_misc_autorespawn", "1.5", "Seconds to wait before respawning player?\n0 - Disabled", 0, true, 0.0, true, 10.0);
	gCV_CreateSpawnPoints = new Convar("shavit_misc_createspawnpoints", "6", "Amount of spawn points to add for each team.\n0 - Disabled", 0, true, 0.0, true, 32.0);
	gCV_DisableRadio = new Convar("shavit_misc_disableradio", "0", "Block radio commands.\n0 - Disabled (radio commands work)\n1 - Enabled (radio commands are blocked)", 0, true, 0.0, true, 1.0);
	gCV_Scoreboard = new Convar("shavit_misc_scoreboard", "1", "Manipulate scoreboard so score is -{time} and deaths are {rank})?\nDeaths part requires shavit-rankings.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_WeaponCommands = new Convar("shavit_misc_weaponcommands", "2", "Enable sm_usp, sm_glock and sm_knife?\n0 - Disabled\n1 - Enabled\n2 - Also give infinite reserved ammo.", 0, true, 0.0, true, 2.0);
	gCV_PlayerOpacity = new Convar("shavit_misc_playeropacity", "-1", "Player opacity (alpha) to set on spawn.\n-1 - Disabled\nValue can go up to 255. 0 for invisibility.", 0, true, -1.0, true, 255.0);
	gCV_StaticPrestrafe = new Convar("shavit_misc_staticprestrafe", "1", "Force prestrafe for every pistol.\n250 is the default value and some styles will have 260.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoclipMe = new Convar("shavit_misc_noclipme", "1", "Allow +noclip, sm_p and all the noclip commands?\n0 - Disabled\n1 - Enabled\n2 - requires 'admin_noclipme' override or ADMFLAG_CHEATS flag.", 0, true, 0.0, true, 2.0);
	gCV_AdvertisementInterval = new Convar("shavit_misc_advertisementinterval", "600.0", "Interval between each chat advertisement.\nConfiguration file for those is configs/shavit-advertisements.cfg.\nSet to 0.0 to disable.\nRequires server restart for changes to take effect.", 0, true, 0.0);
	gCV_Checkpoints = new Convar("shavit_misc_checkpoints", "1", "Allow players to save and teleport to checkpoints.", 0, true, 0.0, true, 1.0);
	gCV_RemoveRagdolls = new Convar("shavit_misc_removeragdolls", "1", "Remove ragdolls after death?\n0 - Disabled\n1 - Only remove replay bot ragdolls.\n2 - Remove all ragdolls.", 0, true, 0.0, true, 2.0);
	gCV_ClanTag = new Convar("shavit_misc_clantag", "{tr}{styletag} :: {time}", "Custom clantag for players.\n0 - Disabled\n{styletag} - style tag.\n{style} - style name.\n{time} - formatted time.\n{tr} - first letter of track.\n{rank} - player rank.", 0);
	gCV_DropAll = new Convar("shavit_misc_dropall", "1", "Allow all weapons to be dropped?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_ResetTargetname = new Convar("shavit_misc_resettargetname", "0", "Reset the player's targetname upon timer start?\nRecommended to leave disabled. Enable via per-map configs when necessary.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RestoreStates = new Convar("shavit_misc_restorestates", "0", "Save the players' timer/position etc.. when they die/change teams,\nand load the data when they spawn?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_JointeamHook = new Convar("shavit_misc_jointeamhook", "1", "Hook `jointeam`?\n0 - Disabled\n1 - Enabled, players can instantly change teams.", 0, true, 0.0, true, 1.0);
	gCV_SpectatorList = new Convar("shavit_misc_speclist", "1", "Who to show in !specs?\n0 - everyone\n1 - all admins (admin_speclisthide override to bypass)\n2 - players you can target", 0, true, 0.0, true, 2.0);
	gCV_MaxCP = new Convar("shavit_misc_maxcp", "1000", "Maximum amount of checkpoints.\nNote: Very high values will result in high memory usage!", 0, true, 1.0, true, 10000.0);
	gCV_MaxCP_Segmented = new Convar("shavit_misc_maxcp_seg", "10", "Maximum amount of segmented checkpoints. Make this less or equal to shavit_misc_maxcp.\nNote: Very high values will result in HUGE memory usage!", 0, true, 1.0, true, 50.0);
	gCV_HideChatCommands = new Convar("shavit_misc_hidechatcmds", "1", "Hide commands from chat?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_PersistData = new Convar("shavit_misc_persistdata", "300", "How long to persist timer data for disconnected users in seconds?\n-1 - Until map change\n0 - Disabled");
	gCV_StopTimerWarning = new Convar("shavit_misc_stoptimerwarning", "900", "Time in seconds to display a warning before stopping the timer with noclip or !stop.\n0 - Disabled");
	gCV_WRMessages = new Convar("shavit_misc_wrmessages", "3", "How many \"NEW <style> WR!!!\" messages to print?\n0 - Disabled", 0,  true, 0.0, true, 100.0);
	gCV_BhopSounds = new Convar("shavit_misc_bhopsounds", "0", "Should bhop (landing and jumping) sounds be muted?\n0 - Disabled\n1 - Blocked while !hide is enabled\n2 - Always blocked", 0,  true, 0.0, true, 3.0);
	gCV_RestrictNoclip = new Convar("shavit_misc_restrictnoclip", "1", "Should noclip be be restricted\n0 - Disabled\n1 - No vertical velocity while in noclip in start zone\n2 - No noclip in start zone", 0, true, 0.0, true, 2.0);

	Convar.AutoExecConfig();

	mp_humanteam = FindConVar("mp_humanteam");

	if(mp_humanteam == null)
	{
		mp_humanteam = FindConVar("mp_humans_must_join_team");
	}

	// crons
	CreateTimer(10.0, Timer_Cron, 0, TIMER_REPEAT);
	CreateTimer(0.5, Timer_PersistKZCP, 0, TIMER_REPEAT);

	if(gEV_Type != Engine_TF2)
	{
		CreateTimer(1.0, Timer_Scoreboard, 0, TIMER_REPEAT);

		if(LibraryExists("dhooks"))
		{
			Handle hGameData = LoadGameConfigFile("shavit.games");

			if(hGameData != null)
			{
				int iOffset = GameConfGetOffset(hGameData, "CCSPlayer::GetPlayerMaxSpeed");

				if(iOffset != -1)
				{
					gH_GetPlayerMaxSpeed = DHookCreate(iOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, CCSPlayer__GetPlayerMaxSpeed);
				}

				else
				{
					SetFailState("Couldn't get the offset for \"CCSPlayer::GetPlayerMaxSpeed\" - make sure your gamedata is updated!");
				}
			}

			delete hGameData;
		}
	}

	// late load
	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);

				if(AreClientCookiesCached(i))
				{
					OnClientCookiesCached(i);
				}
			}
		}
	}

	// modules
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_Replay = LibraryExists("shavit-replay");
	gB_Zones = LibraryExists("shavit-zones");
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
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleSettings(i, gA_StyleSettings[i]);
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i].sStyleName, sizeof(stylestrings_t::sStyleName));
		Shavit_GetStyleStrings(i, sClanTag, gS_StyleStrings[i].sClanTag, sizeof(stylestrings_t::sClanTag));
		Shavit_GetStyleStrings(i, sSpecialString, gS_StyleStrings[i].sSpecialString, sizeof(stylestrings_t::sSpecialString));
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStrings(sMessagePrefix, gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix));
	Shavit_GetChatStrings(sMessageText, gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	Shavit_GetChatStrings(sMessageWarning, gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning));
	Shavit_GetChatStrings(sMessageVariable, gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
	Shavit_GetChatStrings(sMessageVariable2, gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2));
	Shavit_GetChatStrings(sMessageStyle, gS_ChatStrings.sStyle, sizeof(chatstrings_t::sStyle));

	if(!LoadAdvertisementsConfig())
	{
		SetFailState("Cannot open \"configs/shavit-advertisements.cfg\". Make sure this file exists and that the server has read permissions to it.");
	}
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	gI_Style[client] = newstyle;

	if(StrContains(gS_StyleStrings[newstyle].sSpecialString, "segments") != -1)
	{
		OpenCheckpointsMenu(client);
		Shavit_PrintToChat(client, "%T", "MiscSegmentedCommand", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
}

public void OnConfigsExecuted()
{
	if(sv_disable_immunity_alpha != null)
	{
		sv_disable_immunity_alpha.BoolValue = true;
	}
}

public void OnMapStart()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		ResetCheckpoints(i);
	}

	int iLength = gA_PersistentData.Length;

	for(int i = iLength - 1; i >= 0; i--)
	{
		persistent_data_t aData;
		gA_PersistentData.GetArray(i, aData);

		delete aData.aFrames;
	}

	gSM_Checkpoints.Clear();
	gA_Targetnames.Clear();
	gA_Classnames.Clear();
	gA_PersistentData.Clear();

	GetCurrentMap(gS_CurrentMap, 192);
	GetMapDisplayName(gS_CurrentMap, gS_CurrentMap, 192);

	if(gCV_CreateSpawnPoints.IntValue > 0)
	{
		int iEntity = -1;

		if((iEntity = FindEntityByClassname(iEntity, "info_player_terrorist")) != -1 || // CS:S/CS:GO T
			(iEntity = FindEntityByClassname(iEntity, "info_player_counterterrorist")) != -1 || // CS:S/CS:GO CT
			(iEntity = FindEntityByClassname(iEntity, "info_player_teamspawn")) != -1 || // TF2 spawn point
			(iEntity = FindEntityByClassname(iEntity, "info_player_start")) != -1)
		{
			float fOrigin[3];
			GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);

			for(int i = 1; i <= gCV_CreateSpawnPoints.IntValue; i++)
			{
				for(int iTeam = 1; iTeam <= 2; iTeam++)
				{
					int iSpawnPoint = CreateEntityByName((gEV_Type == Engine_TF2)? "info_player_teamspawn":((iTeam == 1)? "info_player_terrorist":"info_player_counterterrorist"));

					if(DispatchSpawn(iSpawnPoint))
					{
						TeleportEntity(iSpawnPoint, fOrigin, view_as<float>({0.0, 0.0, 0.0}), NULL_VECTOR);
					}
				}
			}
		}
	}

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
		Shavit_OnChatConfigLoaded();
	}

	if(gCV_AdvertisementInterval.FloatValue > 0.0)
	{
		CreateTimer(gCV_AdvertisementInterval.FloatValue, Timer_Advertisement, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void OnMapEnd()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		ResetCheckpoints(i);
	}
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

public Action Command_Jointeam(int client, const char[] command, int args)
{
	if(!IsValidClient(client) || !gCV_JointeamHook.BoolValue)
	{
		return Plugin_Continue;
	}

	if(!gB_SaveStates[client])
	{
		SaveState(client);
	}

	char arg1[8];
	GetCmdArg(1, arg1, 8);

	int iTeam = StringToInt(arg1);
	int iHumanTeam = GetHumanTeam();

	if(iHumanTeam != 0 && iTeam != 0)
	{
		iTeam = iHumanTeam;
	}

	bool bRespawn = false;

	switch(iTeam)
	{
		case 2:
		{
			// if T spawns are available in the map
			if(gEV_Type == Engine_TF2 || FindEntityByClassname(-1, "info_player_terrorist") != -1)
			{
				bRespawn = true;
				CleanSwitchTeam(client, 2, true);
			}
		}

		case 3:
		{
			// if CT spawns are available in the map
			if(gEV_Type == Engine_TF2 || FindEntityByClassname(-1, "info_player_counterterrorist") != -1)
			{
				bRespawn = true;
				CleanSwitchTeam(client, 3, true);
			}
		}

		// if they chose to spectate, i'll force them to join the spectators
		case 1:
		{
			CleanSwitchTeam(client, 1, false);
		}

		default:
		{
			bRespawn = true;
			CleanSwitchTeam(client, GetRandomInt(2, 3), true);
		}
	}

	if(gCV_RespawnOnTeam.BoolValue && bRespawn)
	{
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

void CleanSwitchTeam(int client, int team, bool change = false)
{
	if(gEV_Type == Engine_TF2)
	{
		TF2_ChangeClientTeam(client, view_as<TFTeam>(team));
	}

	else if(change)
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

public MRESReturn CCSPlayer__GetPlayerMaxSpeed(int pThis, Handle hReturn)
{
	if(!gCV_StaticPrestrafe.BoolValue || !IsValidClient(pThis, true))
	{
		return MRES_Ignored;
	}

	DHookSetReturn(hReturn, view_as<float>(gA_StyleSettings[gI_Style[pThis]].fRunspeed));

	return MRES_Override;
}

public Action Timer_Cron(Handle Timer)
{
	int iLength = gA_PersistentData.Length;
	float fTime = GetEngineTime();

	for(int i = iLength - 1; i >= 0; i--)
	{
		persistent_data_t aData;
		gA_PersistentData.GetArray(i, aData);

		if(fTime - aData.fDisconnectTime >= gCV_PersistData.FloatValue)
		{
			DeletePersistentData(i, aData);
		}
	}

	return Plugin_Continue;
}

public Action Timer_PersistKZCP(Handle Timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!gB_ClosedKZCP[i] &&
			gA_StyleSettings[gI_Style[i]].bKZCheckpoints
			&& GetClientMenu(i) == MenuSource_None &&
			IsClientInGame(i) && IsPlayerAlive(i))
		{
			OpenKZCPMenu(i);
		}
	}

	return Plugin_Continue;
}

public Action Timer_Scoreboard(Handle Timer)
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

public Action Timer_Advertisement(Handle Timer)
{
	char sHostname[128];
	hostname.GetString(sHostname, 128);

	char sTimeLeft[32];
	int iTimeLeft = 0;
	GetMapTimeLeft(iTimeLeft);
	FormatSeconds(view_as<float>(iTimeLeft), sTimeLeft, 32, false);

	char sTimeLeftRaw[8];
	IntToString(iTimeLeft, sTimeLeftRaw, 8);

	char sIPAddress[64];
	strcopy(sIPAddress, 64, "");

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
			char sTempMessage[300];
			gA_Advertisements.GetString(gI_AdvertisementsCycle, sTempMessage, 300);

			char sName[MAX_NAME_LENGTH];
			GetClientName(i, sName, MAX_NAME_LENGTH);
			ReplaceString(sTempMessage, 300, "{name}", sName);
			ReplaceString(sTempMessage, 300, "{map}", gS_CurrentMap);
			ReplaceString(sTempMessage, 300, "{timeleft}", sTimeLeft);
			ReplaceString(sTempMessage, 300, "{timeleftraw}", sTimeLeftRaw);
			ReplaceString(sTempMessage, 300, "{hostname}", sHostname);
			ReplaceString(sTempMessage, 300, "{serverip}", sIPAddress);

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
	// this doesn't work on tf2 for some reason
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
	char sTag[32];
	gCV_ClanTag.GetString(sTag, 32);

	if(gEV_Type == Engine_TF2 || StrEqual(sTag, "0"))
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
		int time = RoundToFloor(fTime);

		if(time < 60)
		{
			IntToString(time, sTime, 16);
		}

		else
		{
			int minutes = (time / 60);
			int seconds = (time % 60);

			if(time < 3600)
			{
				FormatEx(sTime, 16, "%d:%s%d", minutes, (seconds < 10)? "0":"", seconds);
			}

			else
			{
				minutes %= 60;

				FormatEx(sTime, 16, "%d:%s%d:%s%d", (time / 3600), (minutes < 10)? "0":"", minutes, (seconds < 10)? "0":"", seconds);
			}
		}
	}

	int track = Shavit_GetClientTrack(client);
	char sTrack[3];

	if(track != Track_Main)
	{
		GetTrackName(client, track, sTrack, 3);
	}

	char sRank[8];

	if(gB_Rankings)
	{
		IntToString(Shavit_GetRank(client), sRank, 8);
	}

	char sCustomTag[32];
	strcopy(sCustomTag, 32, sTag);
	ReplaceString(sCustomTag, 32, "{style}", gS_StyleStrings[gI_Style[client]].sStyleName);
	ReplaceString(sCustomTag, 32, "{styletag}", gS_StyleStrings[gI_Style[client]].sClanTag);
	ReplaceString(sCustomTag, 32, "{time}", sTime);
	ReplaceString(sCustomTag, 32, "{tr}", sTrack);
	ReplaceString(sCustomTag, 32, "{rank}", sRank);

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnClanTagChangePre);
	Call_PushCell(client);
	Call_PushStringEx(sTag, 32, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
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

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style, stylesettings_t stylesettings)
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
				TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed);
			}
			else if(gCV_RestrictNoclip.IntValue == 2)
			{
				SetEntityMoveType(client, MOVETYPE_ISOMETRIC);
			}
		}
	}

	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");

	// prespeed
	if(!bNoclip && gA_StyleSettings[gI_Style[client]].iPrespeed == 0 && bInStart)
	{
		if((gCV_PreSpeed.IntValue == 2 || gCV_PreSpeed.IntValue == 3) && gI_GroundEntity[client] == -1 && iGroundEntity != -1 && (buttons & IN_JUMP) > 0)
		{
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
			Shavit_PrintToChat(client, "%T", "BHStartZoneDisallowed", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

			gI_GroundEntity[client] = iGroundEntity;

			return Plugin_Continue;
		}

		if(gCV_PreSpeed.IntValue == 1 || gCV_PreSpeed.IntValue >= 3)
		{
			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);

			float fLimit = (gA_StyleSettings[gI_Style[client]].fRunspeed + gCV_PrestrafeLimit.FloatValue);

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
				ScaleVector(fSpeed, fScale);
			}

			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed);
		}
	}

	gI_GroundEntity[client] = iGroundEntity;

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_SetTransmit, OnSetTransmit);
	SDKHook(client, SDKHook_WeaponDrop, OnWeaponDrop);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	if(gEV_Type == Engine_TF2)
	{
		SDKHook(client, SDKHook_PreThinkPost, OnPreThink);
	}

	if(IsFakeClient(client))
	{
		return;
	}

	if(!AreClientCookiesCached(client))
	{
		gI_Style[client] = Shavit_GetBhopStyle(client);
		gB_Hide[client] = false;
		gI_CheckpointsSettings[client] = CP_DEFAULT;
	}

	if(gH_GetPlayerMaxSpeed != null)
	{
		DHookEntity(gH_GetPlayerMaxSpeed, true, client);
	}

	ResetCheckpoints(client);

	gB_SaveStates[client] = false;
	delete gA_SaveFrames[client];

	gB_ClosedKZCP[client] = false;
}

public void OnClientDisconnect(int client)
{
	if(gCV_NoWeaponDrops.BoolValue)
	{
		int entity = -1;

		while((entity = FindEntityByClassname(entity, "weapon_*")) != -1)
		{
			if(GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
			{
				RequestFrame(RemoveWeapon, EntIndexToEntRef(entity));
			}
		}
	}

	if(IsFakeClient(client))
	{
		return;
	}

	ResetCheckpoints(client);

	gB_SaveStates[client] = false;
	delete gA_SaveFrames[client];

	PersistData(client);
}

void PersistData(int client)
{
	persistent_data_t aData;

	if(!IsClientInGame(client) ||
		!IsPlayerAlive(client) ||
		(aData.iSteamID = GetSteamAccountID((client))) == 0 ||
		Shavit_GetTimerStatus(client) == Timer_Stopped ||
		gCV_PersistData.IntValue == 0)
	{
		return;
	}

	if(gB_Replay)
	{
		aData.aFrames = Shavit_GetReplayData(client);
		aData.iPreFrames = Shavit_GetPlayerPreFrame(client);
		aData.iTimerPreFrames = Shavit_GetPlayerTimerFrame(client);
	}

	aData.fDisconnectTime = GetEngineTime();
	aData.iMoveType = GetEntityMoveType(client);
	aData.fGravity = GetEntityGravity(client);
	aData.fSpeed = GetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue");
	aData.bPractice = Shavit_IsPracticeMode(client);

	float fPosition[3];
	GetClientAbsOrigin(client, fPosition);
	CopyArray(fPosition, aData.fPosition, 3);

	float fAngles[3];
	GetClientEyeAngles(client, fAngles);
	CopyArray(fAngles, aData.fAngles, 3);

	timer_snapshot_t aSnapshot;
	Shavit_SaveSnapshot(client, aSnapshot);
	CopyArray(aSnapshot, aData.aSnapshot, sizeof(timer_snapshot_t));

	char sTargetname[64];
	GetEntPropString(client, Prop_Data, "m_iName", sTargetname, 64);

	aData.iTargetname = gA_Targetnames.FindString(sTargetname);

	if(aData.iTargetname == -1)
	{
		aData.iTargetname = gA_Targetnames.PushString(sTargetname);
	}

	char sClassname[64];
	GetEntityClassname(client, sClassname, 64);

	aData.iClassname = gA_Classnames.FindString(sClassname);

	if(aData.iClassname == -1)
	{
		aData.iClassname = gA_Classnames.PushString(sClassname);
	}

	gA_PersistentData.PushArray(aData);
}

void DeletePersistentData(int index, persistent_data_t data)
{
	delete data.aFrames;
	gA_PersistentData.Erase(index);
}

public Action Timer_LoadPersistentData(Handle Timer, any data)
{
	int iSteamID = 0;
	int client = GetClientFromSerial(data);

	if(client == 0 ||
		(iSteamID = GetSteamAccountID(client)) == 0 ||
		GetClientTeam(client) < 2 ||
		!IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}

	persistent_data_t aData;
	int iIndex = -1;
	int iLength = gA_PersistentData.Length;

	for(int i = 0; i < iLength; i++)
	{
		gA_PersistentData.GetArray(i, aData);

		if(iSteamID == aData.iSteamID)
		{
			iIndex = i;

			break;
		}
	}

	if(iIndex == -1)
	{
		return Plugin_Stop;
	}

	Shavit_StopTimer(client);

	float fPosition[3];
	CopyArray(aData.fPosition, fPosition, 3);

	float fAngles[3];
	CopyArray(aData.fAngles, fAngles, 3);

	SetEntityMoveType(client, aData.iMoveType);
	SetEntityGravity(client, aData.fGravity);
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", aData.fSpeed);

	timer_snapshot_t aSnapshot;
	CopyArray(aData.aSnapshot, aSnapshot, sizeof(timer_snapshot_t));
	Shavit_LoadSnapshot(client, aSnapshot);

	if(aData.iTargetname != -1)
	{
		char sTargetname[64];
		gA_Targetnames.GetString(aData.iTargetname, sTargetname, 64);

		SetEntPropString(client, Prop_Data, "m_iName", sTargetname);
	}

	if(aData.iClassname != -1)
	{
		char sClassname[64];
		gA_Classnames.GetString(aData.iClassname, sClassname, 64);

		SetEntPropString(client, Prop_Data, "m_iClassname", sClassname);
	}

	TeleportEntity(client, fPosition, fAngles, view_as<float>({ 0.0, 0.0, 0.0 }));

	if(gB_Replay && aData.aFrames != null)
	{
		Shavit_SetReplayData(client, aData.aFrames);
		Shavit_SetPlayerPreFrame(client, aData.iPreFrames);
		Shavit_SetPlayerTimerFrame(client, aData.iTimerPreFrames);
	}

	if(aData.bPractice)
	{
		Shavit_SetPracticeMode(client, true, false);
	}

	delete aData.aFrames;
	gA_PersistentData.Erase(iIndex);

	return Plugin_Stop;
}

void RemoveWeapon(any data)
{
	if(IsValidEntity(data))
	{
		AcceptEntityInput(data, "Kill");
	}
}

void ResetCheckpoints(int client)
{
	int serial = GetClientSerial(client);
	char key[32];

	for(int i = 0; i < gA_CheckpointsCache[client].iCheckpoints; i++)
	{
		FormatEx(key, 32, "%d_%d", serial, i);
		
		cp_cache_t cpcache;
		
		if(gSM_Checkpoints.GetArray(key, cpcache, sizeof(cp_cache_t)))
		{
			delete cpcache.aFrames; // free up replay frames if there are any
		}

		gSM_Checkpoints.Remove(key);
	}

	gA_CheckpointsCache[client].iCheckpoints = 0;
	gA_CheckpointsCache[client].iCurrentCheckpoint = 1;
}

public Action OnTakeDamage(int victim, int attacker)
{
	if(gB_Hide[victim])
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

	switch(gCV_GodMode.IntValue)
	{
		case 0:
		{
			return Plugin_Continue;
		}

		case 1:
		{
			// 0 - world/fall damage
			if(attacker == 0)
			{
				return Plugin_Handled;
			}
		}

		case 2:
		{
			if(IsValidClient(attacker, true))
			{
				return Plugin_Handled;
			}
		}

		// else
		default:
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
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

public void OnPreThink(int client)
{
	if(IsPlayerAlive(client))
	{
		// not the best method, but only one i found for tf2
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", gA_StyleSettings[gI_Style[client]].fRunspeed);
	}
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(IsChatTrigger() && gCV_HideChatCommands.BoolValue)
	{
		// hide commands
		return Plugin_Handled;
	}

	if(sArgs[0] == '!' || sArgs[0] == '/')
	{
		bool bUpper = false;

		for(int i = 0; i < strlen(sArgs); i++)
		{
			if(IsCharUpper(sArgs[i]))
			{
				bUpper = true;

				break;
			}
		}

		if(bUpper)
		{
			char sCopy[32];
			strcopy(sCopy, 32, sArgs[1]);

			FakeClientCommandEx(client, "sm_%s", sCopy);

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

	char sCookie[4];
	IntToString(view_as<int>(gB_Hide[client]), sCookie, 4);
	SetClientCookie(client, gH_HideCookie, sCookie);

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

	CleanSwitchTeam(client, 1, false);

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
		target = Shavit_GetReplayBotIndex(0);
	}

	if(IsValidClient(target, true))
	{
		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target);
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
		menu.Display(client, 60);
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

	if(Shavit_InsideZone(client, Zone_Start, -1) || Shavit_InsideZone(client, Zone_End, -1))
	{
		Shavit_PrintToChat(client, "%T", "TeleportInZone", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

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
		SetWeaponAmmo(client, iWeapon);
	}

	return Plugin_Handled;
}

void SetWeaponAmmo(int client, int weapon)
{
	int iAmmo = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	SetEntData(client, gI_Ammo + (iAmmo * 4), 255, 4, true);

	if(gEV_Type == Engine_CSGO)
	{
		SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", 255);
	}
}

public Action Command_Checkpoints(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints)
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

	int iMaxCPs = GetMaxCPs(client);
	bool bSegmenting = CanSegment(client);

	if(!gCV_Checkpoints.BoolValue && !bSegmenting)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	bool bOverflow = gA_CheckpointsCache[client].iCheckpoints >= iMaxCPs;
	int index = gA_CheckpointsCache[client].iCheckpoints + 1;

	if(!bSegmenting)
	{
		if(index > iMaxCPs)
		{
			index = iMaxCPs;
		}

		if(bOverflow)
		{
			Shavit_PrintToChat(client, "%T", "MiscCheckpointsOverflow", client, index, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

			return Plugin_Handled;
		}

		if(SaveCheckpoint(client, index))
		{
			gA_CheckpointsCache[client].iCurrentCheckpoint = ++gA_CheckpointsCache[client].iCheckpoints;
			Shavit_PrintToChat(client, "%T", "MiscCheckpointsSaved", client, gA_CheckpointsCache[client].iCurrentCheckpoint, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
		}
	}
	
	else if(SaveCheckpoint(client, index, bOverflow))
	{
		gA_CheckpointsCache[client].iCurrentCheckpoint = (bOverflow)? iMaxCPs:++gA_CheckpointsCache[client].iCheckpoints;
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsSaved", client, gA_CheckpointsCache[client].iCurrentCheckpoint, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
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

	int index = gA_CheckpointsCache[client].iCurrentCheckpoint;

	if(args > 0)
	{
		char arg[4];
		GetCmdArg(1, arg, 4);

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
	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints)
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
	FormatEx(sDisplay, 64, "%T", "MiscCheckpointSave", client, (gA_CheckpointsCache[client].iCheckpoints + 1));
	menu.AddItem("save", sDisplay, (gA_CheckpointsCache[client].iCheckpoints < gCV_MaxCP.IntValue)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	if(gA_CheckpointsCache[client].iCheckpoints > 0)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, gA_CheckpointsCache[client].iCurrentCheckpoint);
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
		if(CanSegment(param1) || !gA_StyleSettings[gI_Style[param1]].bKZCheckpoints)
		{
			return 0;
		}

		int iCurrent = gA_CheckpointsCache[param1].iCurrentCheckpoint;
		int iMaxCPs = GetMaxCPs(param1);

		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		if(StrEqual(sInfo, "save"))
		{
			if(gA_CheckpointsCache[param1].iCheckpoints < iMaxCPs &&
				SaveCheckpoint(param1, gA_CheckpointsCache[param1].iCheckpoints + 1))
			{
				gA_CheckpointsCache[param1].iCurrentCheckpoint = ++gA_CheckpointsCache[param1].iCheckpoints;
			}
		}

		else if(StrEqual(sInfo, "tele"))
		{
			TeleportToCheckpoint(param1, iCurrent, true);
		}

		else if(StrEqual(sInfo, "prev"))
		{
			if(iCurrent > 1)
			{
				gA_CheckpointsCache[param1].iCurrentCheckpoint--;
			}
		}

		else if(StrEqual(sInfo, "next"))
		{
			cp_cache_t cpcache;
			
			if(iCurrent++ < iMaxCPs && GetCheckpoint(param1, iCurrent, cpcache))
			{
				gA_CheckpointsCache[param1].iCurrentCheckpoint++;
			}
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

	Menu menu = new Menu(MenuHandler_Checkpoints, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);

	if(!bSegmented)
	{
		menu.SetTitle("%T\n%T\n ", "MiscCheckpointMenu", client, "MiscCheckpointWarning", client);
	}

	else
	{
		menu.SetTitle("%T\n ", "MiscCheckpointMenuSegmented", client);
	}

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "MiscCheckpointSave", client, (gA_CheckpointsCache[client].iCheckpoints + 1));
	menu.AddItem("save", sDisplay, (gA_CheckpointsCache[client].iCheckpoints < gCV_MaxCP.IntValue)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	if(gA_CheckpointsCache[client].iCheckpoints > 0)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, gA_CheckpointsCache[client].iCurrentCheckpoint);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DEFAULT);
	}

	else
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, 1);
		menu.AddItem("tele", sDisplay, ITEMDRAW_DISABLED);
	}

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointPrevious", client);
	menu.AddItem("prev", sDisplay);

	FormatEx(sDisplay, 64, "%T\n ", "MiscCheckpointNext", client);
	menu.AddItem("next", sDisplay);

	menu.AddItem("spacer", "", ITEMDRAW_NOTEXT);

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
		int iCurrent = gA_CheckpointsCache[param1].iCurrentCheckpoint;

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
			bool bSegmenting = CanSegment(param1);
			bool bOverflow = gA_CheckpointsCache[param1].iCheckpoints >= iMaxCPs;

			if(!bSegmenting)
			{
				// fight an exploit
				if(bOverflow)
				{
					return 0;
				}

				if(SaveCheckpoint(param1, gA_CheckpointsCache[param1].iCheckpoints + 1))
				{
					gA_CheckpointsCache[param1].iCurrentCheckpoint = ++gA_CheckpointsCache[param1].iCheckpoints;
				}
			}
			
			else
			{
				if(SaveCheckpoint(param1, gA_CheckpointsCache[param1].iCheckpoints + 1, bOverflow))
				{
					gA_CheckpointsCache[param1].iCurrentCheckpoint = (bOverflow)? iMaxCPs:++gA_CheckpointsCache[param1].iCheckpoints;
				}
			}
		}

		else if(StrEqual(sInfo, "tele"))
		{
			TeleportToCheckpoint(param1, iCurrent, true);
		}

		else if(StrEqual(sInfo, "prev"))
		{
			if(iCurrent > 1)
			{
				gA_CheckpointsCache[param1].iCurrentCheckpoint--;
			}
		}

		else if(StrEqual(sInfo, "next"))
		{
			cp_cache_t cpcache;
			
			if(iCurrent++ < iMaxCPs && GetCheckpoint(param1, iCurrent, cpcache))
			{
				gA_CheckpointsCache[param1].iCurrentCheckpoint++;
			}
		}

		else if(StrEqual(sInfo, "reset"))
		{
			ConfirmCheckpointsDeleteMenu(param1);

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
	hMenu.Display(client, 60);
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

bool SaveCheckpoint(int client, int index, bool overflow = false)
{
	// ???
	// nairda somehow triggered an error that requires this
	if(!IsValidClient(client))
	{
		return false;
	}

	int target = client;

	int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
	int iObserverTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	int iFlags = GetEntityFlags(client);

	if(IsClientObserver(client) && IsValidClient(iObserverTarget) && 3 <= iObserverMode <= 5)
	{
		target = iObserverTarget;
	}

	else if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAliveSpectate", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

	else if(Shavit_IsPaused(client) || Shavit_IsPaused(target))
	{
		Shavit_PrintToChat(client, "%T", "CommandNoPause", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints)
	{
		if((iFlags & FL_ONGROUND) == 0 || client != target)
		{
			Shavit_PrintToChat(client, "%T", "CommandSaveCPKZInvalid", client);

			return false;
		}

		else if(Shavit_InsideZone(client, Zone_Start, -1))
		{
			Shavit_PrintToChat(client, "%T", "CommandSaveCPKZZone", client);
			
			return false;
		}
	}

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

	char sKey[32];
	int iSerial = GetClientSerial(client);
	FormatEx(sKey, 32, "%d_%d", iSerial, index);

	cp_cache_t cpcacheprev;

	if(gSM_Checkpoints.GetArray(sKey, cpcacheprev, sizeof(cp_cache_t)))
	{
		delete cpcacheprev.aFrames;
		gSM_Checkpoints.Remove(sKey);
	}

	cp_cache_t cpcache;
	float temp[3];

	GetClientAbsOrigin(target, temp);
	CopyArray(temp, cpcache.fPosition, 3);

	GetClientEyeAngles(target, temp);
	CopyArray(temp, cpcache.fAngles, 3);

	GetEntPropVector(target, Prop_Data, "m_vecVelocity", temp);
	CopyArray(temp, cpcache.fVelocity, 3);

	GetEntPropVector(target, Prop_Data, "m_vecBaseVelocity", temp);
	CopyArray(temp, cpcache.fBaseVelocity, 3);

	char sTargetname[64];
	GetEntPropString(target, Prop_Data, "m_iName", sTargetname, 64);

	int iTargetname = gA_Targetnames.FindString(sTargetname);

	if(iTargetname == -1)
	{
		iTargetname = gA_Targetnames.PushString(sTargetname);
	}

	char sClassname[64];
	GetEntityClassname(target, sClassname, 64);

	int iClassname = gA_Classnames.FindString(sClassname);

	if(iClassname == -1)
	{
		iClassname = gA_Classnames.PushString(sClassname);
	}

	cpcache.iMoveType = GetEntityMoveType(target);
	cpcache.fGravity = GetEntityGravity(target);
	cpcache.fSpeed = GetEntPropFloat(target, Prop_Send, "m_flLaggedMovementValue");

	if(IsFakeClient(target))
	{
		iFlags |= FL_CLIENT;
		iFlags |= FL_AIMTARGET;
		iFlags &= ~FL_ATCONTROLS;
		iFlags &= ~FL_FAKECLIENT;

		cpcache.fStamina = 0.0;
		cpcache.iGroundEntity = -1;
		cpcache.iTargetname = -1;
		cpcache.iClassname = -1;
	}

	else
	{
		cpcache.fStamina = (gEV_Type != Engine_TF2)? GetEntPropFloat(target, Prop_Send, "m_flStamina"):0.0;
		cpcache.iGroundEntity = GetEntPropEnt(target, Prop_Data, "m_hGroundEntity");
		cpcache.iTargetname = iTargetname;
		cpcache.iClassname = iClassname;
	}

	cpcache.iFlags = iFlags;

	if(gEV_Type != Engine_TF2)
	{
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
		int style = Shavit_GetReplayBotStyle(target);
		int track = Shavit_GetReplayBotTrack(target);

		if(style < 0 || track < 0)
		{
			Shavit_PrintToChat(client, "%T", "CommandAliveSpectate", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
			
			return false;
		}

		snapshot.bTimerEnabled = true;
		snapshot.fCurrentTime = Shavit_GetReplayTime(style, track);
		snapshot.bClientPaused = false;
		snapshot.bsStyle = style;
		snapshot.iJumps = 0;
		snapshot.iStrafes = 0;
		snapshot.iTotalMeasures = 0;
		snapshot.iGoodGains = 0;
		snapshot.fServerTime = GetEngineTime();
		snapshot.iSHSWCombination = -1;
		snapshot.iTimerTrack = track;
	}

	else
	{
		Shavit_SaveSnapshot(target, snapshot);
	}

	CopyArray(snapshot, cpcache.aSnapshot, sizeof(timer_snapshot_t));

	if(CanSegment(target))
	{
		if(gB_Replay)
		{
			cpcache.aFrames = Shavit_GetReplayData(target);
			cpcache.iPreFrames = Shavit_GetPlayerPreFrame(target);
			cpcache.iTimerPreFrames = Shavit_GetPlayerTimerFrame(target);
		}

		cpcache.bSegmented = true;
	}

	else
	{
		cpcache.aFrames = null;
		cpcache.bSegmented = false;
	}

	cpcache.iSerial = GetClientSerial(target);
	cpcache.bPractice = Shavit_IsPracticeMode(target);

	if(overflow)
	{
		int iMaxCPs = GetMaxCPs(client);
		
		for(int i = 1; i <= iMaxCPs; i++)
		{
			cp_cache_t cpcacheold;
			FormatEx(sKey, 32, "%d_%d", iSerial, i);

			if(!gSM_Checkpoints.GetArray(sKey, cpcacheold, sizeof(cp_cache_t)))
			{
				continue; // ???
			}

			if(i == 1)
			{
				delete cpcacheold.aFrames;
				gSM_Checkpoints.Remove(sKey);

				continue;
			}

			gSM_Checkpoints.Remove(sKey);
			FormatEx(sKey, 32, "%d_%d", iSerial, (i - 1)); // set cp index to one less
			gSM_Checkpoints.SetArray(sKey, cpcacheold, sizeof(cp_cache_t));
		}

		SetCheckpoint(client, iMaxCPs, cpcache);
	}

	else
	{
		SetCheckpoint(client, index, cpcache);
	}

	return true;
}

void TeleportToCheckpoint(int client, int index, bool suppressMessage)
{
	if(index < 0 || index > gCV_MaxCP.IntValue || (!gCV_Checkpoints.BoolValue && !CanSegment(client)))
	{
		return;
	}

	cp_cache_t cpcache;
	
	if(!GetCheckpoint(client, index, cpcache) || index > gA_CheckpointsCache[client].iCheckpoints)
	{
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsEmpty", client, index, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return;
	}

	else if(Shavit_IsPaused(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandNoPause", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return;
	}

	timer_snapshot_t snapshot;
	CopyArray(cpcache.aSnapshot, snapshot, sizeof(timer_snapshot_t));

	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints != gA_StyleSettings[snapshot.bsStyle].bKZCheckpoints)
	{
		Shavit_PrintToChat(client, "%T", "CommandTeleCPInvalid", client);

		return;
	}

	float pos[3];
	CopyArray(cpcache.fPosition, pos, 3);

	if(IsNullVector(pos))
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

	if(Shavit_InsideZone(client, Zone_Start, -1))
	{
		Shavit_StopTimer(client);
	}

	MoveType mt = cpcache.iMoveType;

	if(mt == MOVETYPE_LADDER || mt == MOVETYPE_WALK)
	{
		SetEntityMoveType(client, mt);
	}

	SetEntityFlags(client, cpcache.iFlags);
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", cpcache.fSpeed);
	SetEntPropEnt(client, Prop_Data, "m_hGroundEntity", cpcache.iGroundEntity);

	if(gEV_Type != Engine_TF2)
	{
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

	float ang[3];
	CopyArray(cpcache.fAngles, ang, 3);

	// this is basically the same as normal checkpoints except much less data is used
	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints)
	{
		TeleportEntity(client, pos, ang, view_as<float>({ 0.0, 0.0, 0.0 }));

		return;
	}

	Shavit_LoadSnapshot(client, snapshot);
	Shavit_ResumeTimer(client);

	float vel[3];

	if((gI_CheckpointsSettings[client] & CP_VELOCITY) > 0 || cpcache.bSegmented)
	{
		float basevel[3];
		CopyArray(cpcache.fVelocity, vel, 3);
		CopyArray(cpcache.fBaseVelocity, basevel, 3);

		AddVectors(vel, basevel, vel);
	}

	else
	{
		vel = NULL_VECTOR;
	}

	if(cpcache.iTargetname != -1)
	{
		char sTargetname[64];
		gA_Targetnames.GetString(cpcache.iTargetname, sTargetname, 64);

		SetEntPropString(client, Prop_Data, "m_iName", sTargetname);
	}

	if(cpcache.iClassname != -1)
	{
		char sClassname[64];
		gA_Classnames.GetString(cpcache.iClassname, sClassname, 64);

		SetEntPropString(client, Prop_Data, "m_iClassname", sClassname);
	}

	TeleportEntity(client, pos,
		((gI_CheckpointsSettings[client] & CP_ANGLES) > 0 || cpcache.bSegmented)? ang:NULL_VECTOR,
		vel);

	if(cpcache.bPractice || !cpcache.bSegmented || GetClientSerial(client) != cpcache.iSerial)
	{
		Shavit_SetPracticeMode(client, true, true);
	}

	SetEntityGravity(client, cpcache.fGravity);

	if(cpcache.bSegmented && gB_Replay)
	{
		if(cpcache.aFrames == null)
		{
			LogError("SetReplayData for %L failed, recorded frames are null.", client);
		}

		else
		{
			Shavit_SetReplayData(client, cpcache.aFrames);
			Shavit_SetPlayerPreFrame(client, cpcache.iPreFrames);
			Shavit_SetPlayerTimerFrame(client, cpcache.iTimerPreFrames);
		}
	}
	
	if(!suppressMessage)
	{
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsTeleported", client, index, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
}

bool ShouldDisplayStopWarning(int client)
{
	return (gCV_StopTimerWarning.BoolValue && Shavit_GetTimerStatus(client) != Timer_Stopped && Shavit_GetClientTime(client) > gCV_StopTimerWarning.FloatValue);
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
	hMenu.Display(client, 30);
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

public Action Command_Specs(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client) && !IsClientObserver(client))
	{
		Shavit_PrintToChat(client, "%T", "SpectatorInvalid", client);

		return Plugin_Handled;
	}

	int iObserverTarget = client;

	if(IsClientObserver(client))
	{
		iObserverTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	}

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

public Action Shavit_OnStart(int client)
{
	if(gA_StyleSettings[gI_Style[client]].iPrespeed == 0 && GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		return Plugin_Stop;
	}

	if(gCV_ResetTargetname.BoolValue || Shavit_IsPracticeMode(client)) // practice mode can be abused to break map triggers
	{
		DispatchKeyValue(client, "targetname", "");
		SetEntPropString(client, Prop_Data, "m_iClassname", "player");
	}

	if(gA_StyleSettings[gI_Style[client]].bKZCheckpoints)
	{
		ResetCheckpoints(client);
	}

	return Plugin_Continue;
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
	if(!gB_ClosedKZCP[client] &&
		gA_StyleSettings[gI_Style[client]].bKZCheckpoints &&
		GetClientMenu(client, null) == MenuSource_None &&
		IsPlayerAlive(client) && GetClientTeam(client) >= 2)
	{
		OpenKZCPMenu(client);
	}
	
	if(!gCV_RespawnOnRestart.BoolValue)
	{
		return;
	}

	if(!IsPlayerAlive(client))
	{
		if(gEV_Type == Engine_TF2)
		{
			TF2_ChangeClientTeam(client, view_as<TFTeam>(3));
		}
		
		else
		{
			if(FindEntityByClassname(-1, "info_player_terrorist") != -1)
			{
				CS_SwitchTeam(client, 2);
			}

			else
			{
				CS_SwitchTeam(client, 3);
			}
		}

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
			RestartTimer(client, track);
		}
	}
}

public Action Respawn(Handle Timer, any data)
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

		if(gCV_HideRadar.BoolValue)
		{
			RequestFrame(RemoveRadar, serial);
		}

		if(gCV_StartOnSpawn.BoolValue)
		{
			RestartTimer(client, Track_Main);
		}

		if(gB_SaveStates[client])
		{
			if(gCV_RestoreStates.BoolValue)
			{
				RequestFrame(RestoreState, serial);
			}

			else
			{
				gB_SaveStates[client] = false;
			}
		}

		else
		{
			CreateTimer(0.10, Timer_LoadPersistentData, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}

		if(gCV_Scoreboard.BoolValue)
		{
			UpdateScoreboard(client);
		}

		UpdateClanTag(client);

		// refreshes kz cp menu if there is nothing open
		if(!gB_ClosedKZCP[client] &&
			gA_StyleSettings[gI_Style[client]].bKZCheckpoints &&
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

void RemoveRadar(any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0 || !IsPlayerAlive(client))
	{
		return;
	}

	if(gEV_Type == Engine_CSGO)
	{
		SetEntProp(client, Prop_Send, "m_iHideHUD", GetEntProp(client, Prop_Send, "m_iHideHUD") | (1 << 12)); // disables player radar
	}

	else if(gEV_Type == Engine_CSS)
	{
		SetEntPropFloat(client, Prop_Send, "m_flFlashDuration", 3600.0);
		SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", 0.5);
	}
}

void RestoreState(any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0 || !IsPlayerAlive(client))
	{
		return;
	}

	if(gA_SaveStates[client].bsStyle != Shavit_GetBhopStyle(client) ||
		gA_SaveStates[client].iTimerTrack != Shavit_GetClientTrack(client))
	{
		gB_SaveStates[client] = false;

		return;
	}

	LoadState(client);
}

public Action Player_Notifications(Event event, const char[] name, bool dontBroadcast)
{
	if(gCV_HideTeamChanges.BoolValue)
	{
		event.BroadcastDisabled = true;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsFakeClient(client))
	{
		if(!gB_SaveStates[client])
		{
			SaveState(client);
		}

		if(gCV_AutoRespawn.FloatValue > 0.0 && StrEqual(name, "player_death"))
		{
			CreateTimer(gCV_AutoRespawn.FloatValue, Respawn, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	switch(gCV_RemoveRagdolls.IntValue)
	{
		case 0:
		{
			return Plugin_Continue;
		}

		case 1:
		{
			if(IsFakeClient(client))
			{
				RemoveRagdoll(client);
			}
		}

		case 2:
		{
			RemoveRagdoll(client);
		}

		default:
		{
			return Plugin_Continue;
		}
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
		SetWeaponAmmo(client, GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"));
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

	int[] clients = new int[MaxClients];
	int count = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || i == client)
		{
			continue;
		}

		if(!gB_Hide[i] ||
			(IsClientObserver(i) && GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == client && 3 <= GetEntProp(i, Prop_Send, "m_iObserverMode") <= 5))
		{
			clients[count++] = i;
		}
	}

	if(numClients == count)
	{
		return Plugin_Continue;
	}

	TE_Start((gEV_Type != Engine_TF2)? "Shotgun Shot":"Fire Bullets");

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

public Action EffectDispatch(const char[] te_name, const Players[], int numClients, float delay)
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

public Action WorldDecal(const char[] te_name, const Players[], int numClients, float delay)
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
				if(IsValidClient(clients[i]) && gB_Hide[clients[i]])
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

public void Shavit_OnPause(int client, int track)
{
	if(!GetClientEyeAngles(client, gF_SaveStateData[client][1]))
	{
		gF_SaveStateData[client][1] = NULL_VECTOR;
	}
}

public void Shavit_OnResume(int client, int track)
{
	if(!IsNullVector(gF_SaveStateData[client][1]))
	{
		TeleportEntity(client, NULL_VECTOR, gF_SaveStateData[client][1], NULL_VECTOR);
	}
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

void LoadState(int client)
{
	TeleportEntity(client, gF_SaveStateData[client][0], gF_SaveStateData[client][1], gF_SaveStateData[client][2]);
	DispatchKeyValue(client, "targetname", gS_SaveStateTargetname[client]);

	Shavit_LoadSnapshot(client, gA_SaveStates[client]);
	Shavit_SetPracticeMode(client, gB_SaveStatesSegmented[client], false);

	if(gB_Replay && gA_SaveFrames[client] != null)
	{
		Shavit_SetReplayData(client, gA_SaveFrames[client]);
		Shavit_SetPlayerPreFrame(client, gI_SavePreFrames[client]);
		Shavit_SetPlayerTimerFrame(client, gI_TimerFrames[client]);
	}

	delete gA_SaveFrames[client];
	gB_SaveStates[client] = false;
}

void SaveState(int client)
{
	if(Shavit_GetTimerStatus(client) == Timer_Stopped)
	{
		return;
	}
	
	GetClientAbsOrigin(client, gF_SaveStateData[client][0]);
	GetClientEyeAngles(client, gF_SaveStateData[client][1]);
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", gF_SaveStateData[client][2]);
	GetEntPropString(client, Prop_Data, "m_iName", gS_SaveStateTargetname[client], 32);

	Shavit_SaveSnapshot(client, gA_SaveStates[client]);
	gB_SaveStatesSegmented[client] = Shavit_IsPracticeMode(client);

	if(gB_Replay)
	{
		delete gA_SaveFrames[client];
		gA_SaveFrames[client] = Shavit_GetReplayData(client);
		gI_SavePreFrames[client] = Shavit_GetPlayerPreFrame(client);
		gI_TimerFrames[client] = Shavit_GetPlayerTimerFrame(client);
	}

	gB_SaveStates[client] = true;
}

bool GetCheckpoint(int client, int index, cp_cache_t cpcache)
{
	char sKey[32];
	FormatEx(sKey, 32, "%d_%d", GetClientSerial(client), index);

	return gSM_Checkpoints.GetArray(sKey, cpcache, sizeof(cp_cache_t));
}

bool SetCheckpoint(int client, int index, cp_cache_t cpcache)
{
	char sKey[32];
	FormatEx(sKey, 32, "%d_%d", GetClientSerial(client), index);

	return gSM_Checkpoints.SetArray(sKey, cpcache, sizeof(cp_cache_t));
}

void CopyArray(const any[] from, any[] to, int size)
{
	for(int i = 0; i < size; i++)
	{
		to[i] = from[i];
	}
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
	if(GetCheckpoint(client, index, cpcache))
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
		position = gA_CheckpointsCache[client].iCurrentCheckpoint;
	}

	if(SetCheckpoint(client, position, cpcache))
	{
		gA_CheckpointsCache[client].iCurrentCheckpoint = ++gA_CheckpointsCache[client].iCheckpoints;
		return true;
	}
	
	return false;
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

public any Native_GetTotalCheckpoints(Handle plugin, int numParams)
{
	return gA_CheckpointsCache[GetNativeCell(1)].iCheckpoints;
}

public any Native_GetCurrentCheckpoint(Handle plugin, int numParams)
{
	return gA_CheckpointsCache[GetNativeCell(1)].iCurrentCheckpoint;
}

public any Native_SetCurrentCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int index = GetNativeCell(2);
	
	gA_CheckpointsCache[client].iCurrentCheckpoint = index;
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
	int iMaxCPs = GetMaxCPs(client);

	bool bSegmenting = CanSegment(client);
	bool bOverflow = gA_CheckpointsCache[client].iCheckpoints >= iMaxCPs;

	if(!bSegmenting)
	{
		// fight an exploit
		if(bOverflow)
		{
			return -1;
		}

		if(SaveCheckpoint(client, gA_CheckpointsCache[client].iCheckpoints + 1))
		{
			gA_CheckpointsCache[client].iCurrentCheckpoint = ++gA_CheckpointsCache[client].iCheckpoints;
		}
	}
	
	else
	{
		if(SaveCheckpoint(client, gA_CheckpointsCache[client].iCheckpoints + 1, bOverflow))
		{
			gA_CheckpointsCache[client].iCurrentCheckpoint = (bOverflow)? iMaxCPs:++gA_CheckpointsCache[client].iCheckpoints;
		}
	}

	return gA_CheckpointsCache[client].iCurrentCheckpoint;
}
