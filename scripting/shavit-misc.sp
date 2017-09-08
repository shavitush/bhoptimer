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
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>

#undef REQUIRE_EXTENSIONS
#include <dhooks>
#include <SteamWorks>

#undef REQUIRE_PLUGIN
#include <shavit>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

#define CP_ANGLES				(1 << 0)
#define CP_VELOCITY				(1 << 1)

#define CP_DEFAULT				(CP_ANGLES|CP_VELOCITY)

#define CP_MAX					64 // this is the amount i'm willing to go for

// game specific
EngineVersion gEV_Type = Engine_Unknown;
int gI_Ammo = -1;

char gS_RadioCommands[][] = {"coverme", "takepoint", "holdpos", "regroup", "followme", "takingfire", "go", "fallback", "sticktog",
	"getinpos", "stormfront", "report", "roger", "enemyspot", "needbackup", "sectorclear", "inposition", "reportingin",
	"getout", "negative", "enemydown", "compliment", "thanks", "cheer"};

// enums
enum
{
	iCheckpoints,
	iCurrentCheckpoint,
	CHECKPOINTSCACHE_SIZE
};

enum
{
	iCPMoveType,
	fCPGravity,
	fCPSpeed,
	fCPStamina,
	bCPDucking,
	PCHECKPOINTSCACHE_SIZE
};

// cache
ConVar sv_disable_immunity_alpha = null;
ConVar sv_footsteps = null;
ConVar hostname = null;
ConVar hostport = null;

bool gB_Hide[MAXPLAYERS+1];
bool gB_Late = false;
int gI_GroundEntity[MAXPLAYERS+1];
int gI_LastShot[MAXPLAYERS+1];
ArrayList gA_Advertisements = null;
int gI_AdvertisementsCycle = 0;
char gS_CurrentMap[192];
int gBS_Style[MAXPLAYERS+1];

float gF_Checkpoints[MAXPLAYERS+1][CP_MAX][3][3]; // 3 - position, angles, velocity
int gI_CheckpointsSettings[MAXPLAYERS+1];
any gA_PlayerCheckPointsCache[MAXPLAYERS+1][CP_MAX][PCHECKPOINTSCACHE_SIZE];
any gA_CheckpointsSnapshots[MAXPLAYERS+1][CP_MAX][TIMERSNAPSHOT_SIZE];
any gA_CheckpointsCache[MAXPLAYERS+1][CHECKPOINTSCACHE_SIZE];
char gS_CheckpointsTargetname[MAXPLAYERS+1][CP_MAX][32];

// save states
float gF_SaveStateData[MAXPLAYERS+1][3][3];
any gA_SaveStates[MAXPLAYERS+1][TIMERSNAPSHOT_SIZE];
bool gB_SaveStates[MAXPLAYERS+1];
char gS_SaveStateTargetname[MAXPLAYERS+1][32];
ArrayList gA_SaveFrames[MAXPLAYERS+1];

// cookies
Handle gH_HideCookie = null;
Handle gH_CheckpointsCookie = null;

// cvars
ConVar gCV_GodMode = null;
ConVar gCV_PreSpeed = null;
ConVar gCV_HideTeamChanges = null;
ConVar gCV_RespawnOnTeam = null;
ConVar gCV_RespawnOnRestart = null;
ConVar gCV_StartOnSpawn = null;
ConVar gCV_PrespeedLimit = null;
ConVar gCV_HideRadar = null;
ConVar gCV_TeleportCommands = null;
ConVar gCV_NoWeaponDrops = null;
ConVar gCV_NoBlock = null;
ConVar gCV_NoBlood = null;
ConVar gCV_AutoRespawn = null;
ConVar gCV_CreateSpawnPoints = null;
ConVar gCV_DisableRadio = null;
ConVar gCV_Scoreboard = null;
ConVar gCV_WeaponCommands = null;
ConVar gCV_PlayerOpacity = null;
ConVar gCV_StaticPrestrafe = null;
ConVar gCV_NoclipMe = null;
ConVar gCV_AdvertisementInterval = null;
ConVar gCV_Checkpoints = null;
ConVar gCV_RemoveRagdolls = null;
ConVar gCV_ClanTag = null;
ConVar gCV_DropAll = null;
ConVar gCV_ResetTargetname = null;
ConVar gCV_RestoreStates = null;

// cached cvars
int gI_GodMode = 3;
int gI_PreSpeed = 3;
bool gB_HideTeamChanges = true;
bool gB_RespawnOnTeam = true;
bool gB_RespawnOnRestart = true;
bool gB_StartOnSpawn = true;
float gF_PrespeedLimit = 280.00;
bool gB_HideRadar = true;
bool gB_TeleportCommands = true;
bool gB_NoWeaponDrops = true;
bool gB_NoBlock = true;
bool gB_NoBlood = false;
float gF_AutoRespawn = 1.5;
int gI_CreateSpawnPoints = 32;
bool gB_DisableRadio = false;
bool gB_Scoreboard = true;
int gI_WeaponCommands = 2;
int gI_PlayerOpacity = -1;
bool gB_StaticPrestrafe = true;
int gI_NoclipMe = true;
float gF_AdvertisementInterval = 600.0;
bool gB_Checkpoints = true;
int gI_RemoveRagdolls = 1;
char gS_ClanTag[32] = "{styletag} :: {time}";
bool gB_ClanTag = true;
bool gB_DropAll = true;
bool gB_ResetTargetname = true;
bool gB_RestoreStates = false;

// dhooks
Handle gH_GetPlayerMaxSpeed = null;

// modules
bool gB_Rankings = false;
bool gB_Replay = false;

// timer settings
char gS_StyleStrings[STYLE_LIMIT][STYLESTRINGS_SIZE][128];
any gA_StyleSettings[STYLE_LIMIT][STYLESETTINGS_SIZE];

// chat settings
char gS_ChatStrings[CHATSETTINGS_SIZE][128];

public Plugin myinfo =
{
	name = "[shavit] Miscellaneous",
	author = "shavit",
	description = "Miscellaneous stuff for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// cache
	gEV_Type = GetEngineVersion();

	sv_disable_immunity_alpha = FindConVar("sv_disable_immunity_alpha");

	sv_footsteps = FindConVar("sv_footsteps");
	sv_footsteps.Flags &= ~(FCVAR_NOTIFY | FCVAR_REPLICATED);

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
	RegConsoleCmd("sm_save", Command_Save, "Saves checkpoint (default: 1). Usage: sm_save [number]");
	RegConsoleCmd("sm_tele", Command_Tele, "Teleports to checkpoint (default: 1). Usage: sm_tele [number]");
	gH_CheckpointsCookie = RegClientCookie("shavit_checkpoints", "Checkpoints settings", CookieAccess_Protected);

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
	HookEvent("weapon_fire", Weapon_Fire);
	AddCommandListener(Command_Drop, "drop");
	AddTempEntHook("Shotgun Shot", Shotgun_Shot);
	AddTempEntHook("EffectDispatch", EffectDispatch);
	AddTempEntHook("World Decal", WorldDecal);

	// phrases
	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-misc.phrases");

	// advertisements
	gA_Advertisements = new ArrayList(300);
	hostname = FindConVar("hostname");
	hostport = FindConVar("hostport");

	// cvars and stuff
	gCV_GodMode = CreateConVar("shavit_misc_godmode", "3", "Enable godmode for players?\n0 - Disabled\n1 - Only prevent fall/world damage.\n2 - Only prevent damage from other players.\n3 - Full godmode.", 0, true, 0.0, true, 3.0);
	gCV_PreSpeed = CreateConVar("shavit_misc_prespeed", "3", "Stop prespeeding in the start zone?\n0 - Disabled, fully allow prespeeding.\n1 - Limit to shavit_misc_prespeedlimit.\n2 - Block bunnyhopping in startzone.\n3 - Limit to shavit_misc_prespeedlimit and block bunnyhopping.", 0, true, 0.0, true, 3.0);
	gCV_HideTeamChanges = CreateConVar("shavit_misc_hideteamchanges", "1", "Hide team changes in chat?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnTeam = CreateConVar("shavit_misc_respawnonteam", "1", "Respawn whenever a player joins a team?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnRestart = CreateConVar("shavit_misc_respawnonrestart", "1", "Respawn a dead player if they use the timer restart command?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_StartOnSpawn = CreateConVar("shavit_misc_startonspawn", "1", "Restart the timer for a player after they spawn?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_PrespeedLimit = CreateConVar("shavit_misc_prespeedlimit", "280.00", "Prespeed limitation in startzone.", 0, true, 10.0, false);
	gCV_HideRadar = CreateConVar("shavit_misc_hideradar", "1", "Should the plugin hide the in-game radar?", 0, true, 0.0, true, 1.0);
	gCV_TeleportCommands = CreateConVar("shavit_misc_tpcmds", "1", "Enable teleport-related commands? (sm_goto/sm_tpto)\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoWeaponDrops = CreateConVar("shavit_misc_noweapondrops", "1", "Remove every dropped weapon.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoBlock = CreateConVar("shavit_misc_noblock", "1", "Disable player collision?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoBlood = CreateConVar("shavit_misc_noblood", "0", "Hide blood decals and particles?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_AutoRespawn = CreateConVar("shavit_misc_autorespawn", "1.5", "Seconds to wait before respawning player?\n0 - Disabled", 0, true, 0.0, true, 10.0);
	gCV_CreateSpawnPoints = CreateConVar("shavit_misc_createspawnpoints", "32", "Amount of spawn points to add for each team.\n0 - Disabled", 0, true, 0.0, true, 32.0);
	gCV_DisableRadio = CreateConVar("shavit_misc_disableradio", "0", "Block radio commands.\n0 - Disabled (radio commands work)\n1 - Enabled (radio commands are blocked)", 0, true, 0.0, true, 1.0);
	gCV_Scoreboard = CreateConVar("shavit_misc_scoreboard", "1", "Manipulate scoreboard so score is -{time} and deaths are {rank})?\nDeaths part requires shavit-rankings.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_WeaponCommands = CreateConVar("shavit_misc_weaponcommands", "2", "Enable sm_usp, sm_glock and sm_knife?\n0 - Disabled\n1 - Enabled\n2 - Also give infinite reserved ammo.", 0, true, 0.0, true, 2.0);
	gCV_PlayerOpacity = CreateConVar("shavit_misc_playeropacity", "-1", "Player opacity (alpha) to set on spawn.\n-1 - Disabled\nValue can go up to 255. 0 for invisibility.", 0, true, -1.0, true, 255.0);
	gCV_StaticPrestrafe = CreateConVar("shavit_misc_staticprestrafe", "1", "Force prestrafe for every pistol.\n250 is the default value and some styles will have 260.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_NoclipMe = CreateConVar("shavit_misc_noclipme", "1", "Allow +noclip, sm_p and all the noclip commands?\n0 - Disabled\n1 - Enabled\n2 - requires 'admin_noclipme' override or ADMFLAG_CHEATS flag.", 0, true, 0.0, true, 2.0);
	gCV_AdvertisementInterval = CreateConVar("shavit_misc_advertisementinterval", "600.0", "Interval between each chat advertisement.\nConfiguration file for those is configs/shavit-advertisements.cfg.\nSet to 0.0 to disable.\nRequires server restart for changes to take effect.", 0, true, 0.0);
	gCV_Checkpoints = CreateConVar("shavit_misc_checkpoints", "1", "Allow players to save and teleport to checkpoints.", 0, true, 0.0, true, 1.0);
	gCV_RemoveRagdolls = CreateConVar("shavit_misc_removeragdolls", "1", "Remove ragdolls after death?\n0 - Disabled\n1 - Only remove replay bot ragdolls.\n2 - Remove all ragdolls.", 0, true, 0.0, true, 2.0);
	gCV_ClanTag = CreateConVar("shavit_misc_clantag", "{styletag} :: {time}", "Custom clantag for players.\n0 - Disabled\n{styletag} - style settings from shavit-styles.cfg.\n{style} - style name.\n{time} - formatted time.", 0);
	gCV_DropAll = CreateConVar("shavit_misc_dropall", "1", "Allow all weapons to be dropped?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 2.0);
	gCV_ResetTargetname = CreateConVar("shavit_misc_resettargetname", "1", "Reset the player's targetname upon timer start?\nRecommended to leave enabled. Disable via per-map configs if it's problematic.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 2.0);
	gCV_RestoreStates = CreateConVar("shavit_misc_restorestates", "0", "Save the players' timer/position etc.. when they die/change teams,\nand load the data when they spawn?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 2.0);

	gCV_GodMode.AddChangeHook(OnConVarChanged);
	gCV_PreSpeed.AddChangeHook(OnConVarChanged);
	gCV_HideTeamChanges.AddChangeHook(OnConVarChanged);
	gCV_RespawnOnTeam.AddChangeHook(OnConVarChanged);
	gCV_RespawnOnRestart.AddChangeHook(OnConVarChanged);
	gCV_StartOnSpawn.AddChangeHook(OnConVarChanged);
	gCV_PrespeedLimit.AddChangeHook(OnConVarChanged);
	gCV_HideRadar.AddChangeHook(OnConVarChanged);
	gCV_TeleportCommands.AddChangeHook(OnConVarChanged);
	gCV_NoWeaponDrops.AddChangeHook(OnConVarChanged);
	gCV_NoBlock.AddChangeHook(OnConVarChanged);
	gCV_NoBlood.AddChangeHook(OnConVarChanged);
	gCV_AutoRespawn.AddChangeHook(OnConVarChanged);
	gCV_CreateSpawnPoints.AddChangeHook(OnConVarChanged);
	gCV_DisableRadio.AddChangeHook(OnConVarChanged);
	gCV_Scoreboard.AddChangeHook(OnConVarChanged);
	gCV_WeaponCommands.AddChangeHook(OnConVarChanged);
	gCV_PlayerOpacity.AddChangeHook(OnConVarChanged);
	gCV_StaticPrestrafe.AddChangeHook(OnConVarChanged);
	gCV_NoclipMe.AddChangeHook(OnConVarChanged);
	gCV_AdvertisementInterval.AddChangeHook(OnConVarChanged);
	gCV_Checkpoints.AddChangeHook(OnConVarChanged);
	gCV_RemoveRagdolls.AddChangeHook(OnConVarChanged);
	gCV_ClanTag.AddChangeHook(OnConVarChanged);
	gCV_DropAll.AddChangeHook(OnConVarChanged);
	gCV_ResetTargetname.AddChangeHook(OnConVarChanged);
	gCV_RestoreStates.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	// crons
	CreateTimer(1.0, Timer_Scoreboard, 0, TIMER_REPEAT);

	if(LibraryExists("dhooks"))
	{
		Handle hGameData = LoadGameConfigFile("shavit.games");

		if(hGameData != null)
		{
			int iOffset = GameConfGetOffset(hGameData, "GetPlayerMaxSpeed");

			if(iOffset != -1)
			{
				gH_GetPlayerMaxSpeed = DHookCreate(iOffset, HookType_Entity, ReturnType_Float, ThisPointer_CBaseEntity, DHook_GetMaxPlayerSpeed);
			}

			else
			{
				SetFailState("Couldn't get the offset for \"GetPlayerMaxSpeed\" - make sure your gamedata is updated!");
			}
		}

		delete hGameData;
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
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	char[] sSetting = new char[8];
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

	UpdateFootsteps(client);

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

	gBS_Style[client] = Shavit_GetBhopStyle(client);
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
		Shavit_GetStyleStrings(i, sClanTag, gS_StyleStrings[i][sClanTag], 128);
	}
}

public void Shavit_OnChatConfigLoaded()
{
	for(int i = 0; i < CHATSETTINGS_SIZE; i++)
	{
		Shavit_GetChatStrings(i, gS_ChatStrings[i], 128);
	}

	if(!LoadAdvertisementsConfig())
	{
		SetFailState("Cannot open \"configs/shavit-advertisements.cfg\". Make sure this file exists and that the server has read permissions to it.");
	}
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle)
{
	gBS_Style[client] = newstyle;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gI_GodMode = gCV_GodMode.IntValue;
	gI_PreSpeed = gCV_PreSpeed.IntValue;
	gB_HideTeamChanges = gCV_HideTeamChanges.BoolValue;
	gB_RespawnOnTeam = gCV_RespawnOnTeam.BoolValue;
	gB_RespawnOnRestart = gCV_RespawnOnRestart.BoolValue;
	gB_StartOnSpawn = gCV_StartOnSpawn.BoolValue;
	gF_PrespeedLimit = gCV_PrespeedLimit.FloatValue;
	gB_HideRadar = gCV_HideRadar.BoolValue;
	gB_TeleportCommands = gCV_TeleportCommands.BoolValue;
	gB_NoWeaponDrops = gCV_NoWeaponDrops.BoolValue;
	gB_NoBlock = gCV_NoBlock.BoolValue;
	gB_NoBlood = gCV_NoBlood.BoolValue;
	gF_AutoRespawn = gCV_AutoRespawn.FloatValue;
	gI_CreateSpawnPoints = gCV_CreateSpawnPoints.IntValue;
	gB_DisableRadio = gCV_DisableRadio.BoolValue;
	gB_Scoreboard = gCV_Scoreboard.BoolValue;
	gI_WeaponCommands = gCV_WeaponCommands.IntValue;
	gI_PlayerOpacity = gCV_PlayerOpacity.IntValue;
	gB_StaticPrestrafe = gCV_StaticPrestrafe.BoolValue;
	gI_NoclipMe = gCV_NoclipMe.IntValue;
	gF_AdvertisementInterval = gCV_AdvertisementInterval.FloatValue;
	gB_Checkpoints = gCV_Checkpoints.BoolValue;
	gI_RemoveRagdolls = gCV_RemoveRagdolls.IntValue;
	gCV_ClanTag.GetString(gS_ClanTag, 32);
	gB_DropAll = gCV_DropAll.BoolValue;
	gB_ResetTargetname = gCV_ResetTargetname.BoolValue;
	gB_RestoreStates = gCV_RestoreStates.BoolValue;

	gB_ClanTag = !StrEqual(gS_ClanTag, "0");
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
	GetCurrentMap(gS_CurrentMap, 192);
	GetMapDisplayName(gS_CurrentMap, gS_CurrentMap, 192);

	if(gI_CreateSpawnPoints > 0)
	{
		int iEntity = -1;
		float fOrigin[3];

		if((iEntity = FindEntityByClassname(iEntity, "info_player_terrorist")) != INVALID_ENT_REFERENCE)
		{
			GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
		}

		else if((iEntity = FindEntityByClassname(iEntity, "info_player_counterterrorist")) != INVALID_ENT_REFERENCE)
		{
			GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
		}

		if(iEntity != -1)
		{
			for(int i = 1; i <= gI_CreateSpawnPoints; i++)
			{
				for(int iTeam = 1; iTeam <= 2; iTeam++)
				{
					int iSpawnPoint = CreateEntityByName((iTeam == 1)? "info_player_terrorist":"info_player_counterterrorist");

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

	if(gF_AdvertisementInterval > 0.0)
	{
		CreateTimer(gF_AdvertisementInterval, Timer_Advertisement, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

bool LoadAdvertisementsConfig()
{
	gA_Advertisements.Clear();

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-advertisements.cfg");

	KeyValues kv = new KeyValues("shavit-advertisements");
	
	if(!kv.ImportFromFile(sPath) || !kv.GotoFirstSubKey(false))
	{
		delete kv;

		return false;
	}

	do
	{
		char[] sTempMessage = new char[300];
		kv.GetString(NULL_STRING, sTempMessage, 300, "<EMPTY ADVERTISEMENT>");

		ReplaceString(sTempMessage, 300, "{text}", gS_ChatStrings[sMessageText]);
		ReplaceString(sTempMessage, 300, "{warning}", gS_ChatStrings[sMessageWarning]);
		ReplaceString(sTempMessage, 300, "{variable}", gS_ChatStrings[sMessageVariable]);
		ReplaceString(sTempMessage, 300, "{variable2}", gS_ChatStrings[sMessageVariable2]);
		ReplaceString(sTempMessage, 300, "{style}", gS_ChatStrings[sMessageStyle]);

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
}

public Action Command_Jointeam(int client, const char[] command, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	if(!gB_SaveStates[client])
	{
		SaveState(client);
	}

	char[] arg1 = new char[8];
	GetCmdArg(1, arg1, 8);

	int iTeam = StringToInt(arg1);

	bool bRespawn = false;

	switch(iTeam)
	{
		case CS_TEAM_T:
		{
			// if T spawns are available in the map
			if(FindEntityByClassname(-1, "info_player_terrorist") != -1)
			{
				bRespawn = true;

				CS_SwitchTeam(client, CS_TEAM_T);
			}
		}

		case CS_TEAM_CT:
		{
			// if CT spawns are available in the map
			if(FindEntityByClassname(-1, "info_player_counterterrorist") != -1)
			{
				bRespawn = true;

				CS_SwitchTeam(client, CS_TEAM_CT);
			}
		}

		// if they chose to spectate, i'll force them to join the spectators
		case CS_TEAM_SPECTATOR:
		{
			ChangeClientTeam(client, CS_TEAM_SPECTATOR);
		}

		default:
		{
			bRespawn = true;

			CS_SwitchTeam(client, GetRandomInt(2, 3));
		}
	}

	if(gB_RespawnOnTeam && bRespawn)
	{
		CS_RespawnPlayer(client);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Command_Radio(int client, const char[] command, int args)
{
	if(gB_DisableRadio)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public MRESReturn DHook_GetMaxPlayerSpeed(int pThis, Handle hReturn)
{
	if(!gB_StaticPrestrafe && !IsValidClient(pThis, true))
	{
		return MRES_Ignored;
	}

	DHookSetReturn(hReturn, view_as<float>(gA_StyleSettings[gBS_Style[pThis]][fRunspeed]));

	return MRES_Override;
}

public Action Timer_Scoreboard(Handle Timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i))
		{
			continue;
		}

		if(gB_Scoreboard)
		{
			UpdateScoreboard(i);
		}

		if(gB_ClanTag)
		{
			UpdateClanTag(i);
		}
	}

	return Plugin_Continue;
}

public Action Timer_Advertisement(Handle Timer)
{
	char[] sHostname = new char[128];
	hostname.GetString(sHostname, 128);

	char[] sTimeLeft = new char[32];
	int iTimeLeft = 0;
	GetMapTimeLeft(iTimeLeft);
	FormatSeconds(view_as<float>(iTimeLeft), sTimeLeft, 32, false);

	char[] sTimeLeftRaw = new char[8];
	IntToString(iTimeLeft, sTimeLeftRaw, 8);

	char[] sIPAddress = new char[64];
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
			char[] sTempMessage = new char[300];
			gA_Advertisements.GetString(gI_AdvertisementsCycle, sTempMessage, 300);

			char[] sName = new char[MAX_NAME_LENGTH];
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
	float fPB = 0.0;
	Shavit_GetPlayerPB(client, 0, fPB, Track_Main);

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
	char[] sTime = new char[16];

	float fTime = Shavit_GetClientTime(client);

	if(Shavit_GetTimerStatus(client) == Timer_Stopped || fTime <= 0.0)
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

	char[] sCustomTag = new char[32];
	strcopy(sCustomTag, 32, gS_ClanTag);
	ReplaceString(sCustomTag, 32, "{style}", gS_StyleStrings[gBS_Style[client]][sStyleName]);
	ReplaceString(sCustomTag, 32, "{styletag}", gS_StyleStrings[gBS_Style[client]][sClanTag]);
	ReplaceString(sCustomTag, 32, "{time}", sTime);

	CS_SetClientClanTag(client, sCustomTag);
}

void RemoveRagdoll(int client)
{
	int iEntity = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");

	if(iEntity != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(iEntity, "Kill");
	}
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track)
{
	bool bNoclip = (GetEntityMoveType(client) == MOVETYPE_NOCLIP);

	if(bNoclip && status == Timer_Running)
	{
		Shavit_StopTimer(client);
	}

	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");

	// prespeed
	if(!gA_StyleSettings[gBS_Style[client]][bPrespeed] && Shavit_InsideZone(client, Zone_Start, track))
	{
		if((gI_PreSpeed == 2 || gI_PreSpeed == 3) && gI_GroundEntity[client] == -1 && iGroundEntity != -1 && (buttons & IN_JUMP) > 0)
		{
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
			Shavit_PrintToChat(client, "%T", "BHStartZoneDisallowed", client, gS_ChatStrings[sMessageVariable], gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

			gI_GroundEntity[client] = iGroundEntity;

			return Plugin_Continue;
		}

		if(gI_PreSpeed == 1 || gI_PreSpeed == 3)
		{
			float speed[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", speed);

			float speed_New = (SquareRoot(Pow(speed[0], 2.0) + Pow(speed[1], 2.0)));
			float fScale = (gF_PrespeedLimit / speed_New);

			if(bNoclip)
			{
				speed[2] = 0.0;
			}

			else if(fScale < 1.0)
			{
				ScaleVector(speed, fScale);
			}

			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, speed);
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

	if(IsFakeClient(client))
	{
		return;
	}

	if(!AreClientCookiesCached(client))
	{
		gBS_Style[client] = Shavit_GetBhopStyle(client);
		gB_Hide[client] = false;
		gI_CheckpointsSettings[client] = CP_DEFAULT;

		UpdateFootsteps(client);
	}

	if(gH_GetPlayerMaxSpeed != null)
	{
		DHookEntity(gH_GetPlayerMaxSpeed, true, client);
	}

	ResetCheckpoints(client);

	gB_SaveStates[client] = false;

	if(gA_SaveFrames[client] != null)
	{
		delete gA_SaveFrames[client];
		gA_SaveFrames[client] = null;
	}
}

void ResetCheckpoints(int client)
{
	for(int i = 0; i < sizeof(gF_Checkpoints[]); i++)
	{
		for(int j = 0; j < sizeof(gF_Checkpoints[][]); j++)
		{
			gF_Checkpoints[client][i][j] = NULL_VECTOR;
		}
	}

	for(int i = 0; i < CP_MAX; i++)
	{
		gA_CheckpointsSnapshots[client][i][bTimerEnabled] = false;
		gA_CheckpointsSnapshots[client][i][fStartTime] = 0.0;
		gA_CheckpointsSnapshots[client][i][fCurrentTime] = 0.0;
		gA_CheckpointsSnapshots[client][i][fPauseStartTime] = 0.0;
		gA_CheckpointsSnapshots[client][i][fPauseTotalTime] = 0.0;
		gA_CheckpointsSnapshots[client][i][bClientPaused] = false;
		gA_CheckpointsSnapshots[client][i][iJumps] = 0;
		gA_CheckpointsSnapshots[client][i][bsStyle] = 0;
		gA_CheckpointsSnapshots[client][i][iStrafes] = 0;
		gA_CheckpointsSnapshots[client][i][iTotalMeasures] = 0;
		gA_CheckpointsSnapshots[client][i][iGoodGains] = 0;
		gA_CheckpointsSnapshots[client][i][iSHSWCombination] = -1;

		gA_PlayerCheckPointsCache[client][i][iCPMoveType] = MOVETYPE_WALK;
		gA_PlayerCheckPointsCache[client][i][fCPGravity] = 1.0;
		gA_PlayerCheckPointsCache[client][i][fCPSpeed] = 1.0;
		gA_PlayerCheckPointsCache[client][i][fCPStamina] = 1.0;
		gA_PlayerCheckPointsCache[client][i][bCPDucking] = false;

		strcopy(gS_CheckpointsTargetname[client][i], 32, "");
	}

	gA_CheckpointsCache[client][iCheckpoints] = 0;
	gA_CheckpointsCache[client][iCurrentCheckpoint] = 1;
}

public Action OnTakeDamage(int victim, int attacker)
{
	switch(gI_GodMode)
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
	if(gB_NoWeaponDrops && IsValidEntity(entity))
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

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(IsChatTrigger())
	{
		// hide commands
		return Plugin_Handled;
	}

	else if(sArgs[0] == '!' || sArgs[0] == '/')
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
			char[] sCopy = new char[32];
			strcopy(sCopy, 32, sArgs[1]);

			FakeClientCommand(client, "sm_%s", sCopy);

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
	UpdateFootsteps(client);

	char[] sCookie = new char[4];
	IntToString(view_as<int>(gB_Hide[client]), sCookie, 4);
	SetClientCookie(client, gH_HideCookie, sCookie);

	if(gB_Hide[client])
	{
		Shavit_PrintToChat(client, "%T", "HideEnabled", client, gS_ChatStrings[sMessageVariable], gS_ChatStrings[sMessageText]);
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "HideDisabled", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);
	}

	return Plugin_Handled;
}

public Action Command_Spec(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	ChangeClientTeam(client, CS_TEAM_SPECTATOR);

	if(args > 0)
	{
		char[] sArgs = new char[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		int iTarget = FindTarget(client, sArgs, false, false);

		if(iTarget == -1)
		{
			return Plugin_Handled;
		}

		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", iTarget);
	}

	return Plugin_Handled;
}

public Action Command_Teleport(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gB_TeleportCommands)
	{
		Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	if(args > 0)
	{
		char[] sArgs = new char[MAX_TARGET_LENGTH];
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

			char[] serial = new char[16];
			IntToString(GetClientSerial(i), serial, 16);

			char[] sName = new char[MAX_NAME_LENGTH];
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
		char[] sInfo = new char[16];
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
		Shavit_PrintToChat(client, "%T", "TeleportInZone", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], gS_ChatStrings[sMessageText]);

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
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(gI_WeaponCommands == 0)
	{
		Shavit_PrintToChat(client, "%T", "CommandDisabled", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "WeaponAlive", client, gS_ChatStrings[sMessageVariable2], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	char[] sCommand = new char[16];
	GetCmdArg(0, sCommand, 16);

	int iSlot = CS_SLOT_SECONDARY;
	char[] sWeapon = new char[32];

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

	return OpenCheckpointsMenu(client, 0);
}

public Action Command_Save(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	if(!gB_Checkpoints)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}
	
	if(args > 0)
	{
		int index = 0;

		char[] arg = new char[4];
		GetCmdArg(1, arg, 4);

		int parsed = StringToInt(arg);

		if(parsed > 0 && parsed <= CP_MAX)
		{
			index = (parsed - 1);
		}

		SaveCheckpoint(client, index);

		Shavit_PrintToChat(client, "%T", "MiscCheckpointsSaved", client, (index + 1), gS_ChatStrings[sMessageVariable], gS_ChatStrings[sMessageText]);
	}

	else
	{
		if(gA_CheckpointsCache[client][iCheckpoints] < CP_MAX)
		{
			SaveCheckpoint(client, gA_CheckpointsCache[client][iCheckpoints]);
			gA_CheckpointsCache[client][iCurrentCheckpoint] = ++gA_CheckpointsCache[client][iCheckpoints];
		}

		else
		{
			SaveCheckpoint(client, (CP_MAX - 1));
			gA_CheckpointsCache[client][iCurrentCheckpoint] = CP_MAX;
		}

		Shavit_PrintToChat(client, "%T", "MiscCheckpointsSaved", client, gA_CheckpointsCache[client][iCurrentCheckpoint], gS_ChatStrings[sMessageVariable], gS_ChatStrings[sMessageText]);
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

	if(!gB_Checkpoints)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	int index = (gA_CheckpointsCache[client][iCurrentCheckpoint] - 1);

	if(args > 0)
	{
		char[] arg = new char[4];
		GetCmdArg(1, arg, 4);

		int parsed = StringToInt(arg);

		if(parsed > 0 && parsed <= CP_MAX)
		{
			index = (parsed - 1);
		}
	}

	if(IsNullVector(gF_Checkpoints[client][index][0]))
	{
		Shavit_PrintToChat(client, "%T", "MiscCheckpointsEmpty", client, (index + 1), gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	TeleportToCheckpoint(client, index);

	return Plugin_Handled;
}

public Action OpenCheckpointsMenu(int client, int item)
{
	if(!gB_Checkpoints)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAlive", client, gS_ChatStrings[sMessageVariable], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_Checkpoints, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	menu.SetTitle("%T\n%T\n ", "MiscCheckpointMenu", client, "MiscCheckpointWarning", client);

	char[] sDisplay = new char[64];
	FormatEx(sDisplay, 64, "%T", "MiscCheckpointSave", client, (gA_CheckpointsCache[client][iCheckpoints] + 1));
	menu.AddItem("save", sDisplay, (gA_CheckpointsCache[client][iCheckpoints] < CP_MAX)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);

	if(gA_CheckpointsCache[client][iCheckpoints] > 0)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointTeleport", client, gA_CheckpointsCache[client][iCurrentCheckpoint]);
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

	FormatEx(sDisplay, 64, "%T", "MiscCheckpointReset", client);
	menu.AddItem("reset", sDisplay);

	char[] sInfo = new char[16];
	IntToString(CP_ANGLES, sInfo, 16);
	FormatEx(sDisplay, 64, "%T", "MiscCheckpointUseAngles", client);
	menu.AddItem(sInfo, sDisplay);

	IntToString(CP_VELOCITY, sInfo, 16);
	FormatEx(sDisplay, 64, "%T", "MiscCheckpointUseVelocity", client);
	menu.AddItem(sInfo, sDisplay);

	menu.Pagination = MENU_NO_PAGINATION;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_Checkpoints(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		int current = gA_CheckpointsCache[param1][iCurrentCheckpoint];

		switch(param2)
		{
			case 0:
			{
				// fight an exploit
				if(gA_CheckpointsCache[param1][iCheckpoints] >= CP_MAX)
				{
					return 0;
				}

				SaveCheckpoint(param1, gA_CheckpointsCache[param1][iCheckpoints]);
				gA_CheckpointsCache[param1][iCurrentCheckpoint] = ++gA_CheckpointsCache[param1][iCheckpoints];
			}

			case 1:
			{
				TeleportToCheckpoint(param1, current - 1);
			}

			case 2:
			{
				if(current > 1)
				{
					gA_CheckpointsCache[param1][iCurrentCheckpoint]--;
				}
			}

			case 3:
			{
				if(current < CP_MAX && !IsNullVector(gF_Checkpoints[param1][current][0]))
				{
					gA_CheckpointsCache[param1][iCurrentCheckpoint]++;
				}
			}

			case 4:
			{
				ResetCheckpoints(param1);
			}

			default:
			{
				char[] sInfo = new char[8];
				menu.GetItem(param2, sInfo, 8);
				
				char[] sCookie = new char[8];
				gI_CheckpointsSettings[param1] ^= StringToInt(sInfo);
				IntToString(gI_CheckpointsSettings[param1], sCookie, 16);

				SetClientCookie(param1, gH_CheckpointsCookie, sCookie);
			}
		}

		OpenCheckpointsMenu(param1, GetMenuSelectionPosition());
	}

	else if(action == MenuAction_DisplayItem && param2 >= 5)
	{
		char[] sInfo = new char[16];
		char[] sDisplay = new char[64];
		int style = 0;
		menu.GetItem(param2, sInfo, 16, style, sDisplay, 64);

		Format(sDisplay, 64, "[%s] %s", ((gI_CheckpointsSettings[param1] & StringToInt(sInfo)) > 0)? "x":" ", sDisplay);

		return RedrawMenuItem(sDisplay);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void SaveCheckpoint(int client, int index)
{
	GetClientAbsOrigin(client, gF_Checkpoints[client][index][0]);
	GetClientEyeAngles(client, gF_Checkpoints[client][index][1]);
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", gF_Checkpoints[client][index][2]);
	GetEntPropString(client, Prop_Data, "m_iName", gS_CheckpointsTargetname[client][index], 32);

	gA_PlayerCheckPointsCache[client][index][iCPMoveType] = GetEntityMoveType(client);
	gA_PlayerCheckPointsCache[client][index][fCPGravity] = GetEntityGravity(client);
	gA_PlayerCheckPointsCache[client][index][fCPSpeed] = 1.0;
	gA_PlayerCheckPointsCache[client][index][fCPStamina] = GetEntPropFloat(client, Prop_Send, "m_flStamina");
	gA_PlayerCheckPointsCache[client][index][bCPDucking] = (GetClientButtons(client) & IN_DUCK) > 0;

	Shavit_SaveSnapshot(client, gA_CheckpointsSnapshots[client][index]);
}

void TeleportToCheckpoint(int client, int index)
{
	if(index < 0 || index >= CP_MAX || IsNullVector(gF_Checkpoints[client][index][0]))
	{
		return;
	}

	bool bDucking = (GetClientButtons(client) & IN_DUCK) > 0;

	if(gA_PlayerCheckPointsCache[client][index][bCPDucking] != bDucking)
	{
		Shavit_PrintToChat(client, "%T", (bDucking)? "MiscCheckpointsCrouchOff":"MiscCheckpointsCrouchOn", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return;
	}

	bool bInStart = Shavit_InsideZone(client, Zone_Start, -1);

	Shavit_SetPracticeMode(client, true, !bInStart);
	Shavit_LoadSnapshot(client, gA_CheckpointsSnapshots[client][index]);

	TeleportEntity(client, gF_Checkpoints[client][index][0],
		((gI_CheckpointsSettings[client] & CP_ANGLES) > 0)? gF_Checkpoints[client][index][1]:NULL_VECTOR,
		((gI_CheckpointsSettings[client] & CP_VELOCITY) > 0)? gF_Checkpoints[client][index][2]:NULL_VECTOR);

	SetEntityMoveType(client, view_as<MoveType>(gA_PlayerCheckPointsCache[client][index][iCPMoveType]));
	SetEntityGravity(client, view_as<float>(gA_PlayerCheckPointsCache[client][index][fCPGravity]));
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", view_as<float>(gA_PlayerCheckPointsCache[client][index][fCPSpeed]));
	SetEntPropFloat(client, Prop_Send, "m_flStamina", view_as<float>(gA_PlayerCheckPointsCache[client][index][fCPStamina]));
	DispatchKeyValue(client, "targetname", gS_CheckpointsTargetname[client][index]);

	if(bInStart)
	{
		Shavit_StopTimer(client);
	}
	
	Shavit_PrintToChat(client, "%T", "MiscCheckpointsTeleported", client, (index + 1), gS_ChatStrings[sMessageVariable], gS_ChatStrings[sMessageText]);
}

public Action Command_Noclip(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(gI_NoclipMe == 0)
	{
		Shavit_PrintToChat(client, "%T", "FeatureDisabled", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	else if(gI_NoclipMe == 2 && !CheckCommandAccess(client, "admin_noclipme", ADMFLAG_CHEATS))
	{
		Shavit_PrintToChat(client, "%T", "LackingAccess", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "CommandAlive", client, gS_ChatStrings[sMessageVariable], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	if(GetEntityMoveType(client) != MOVETYPE_NOCLIP)
	{
		if(Shavit_GetTimerStatus(client) != Timer_Stopped)
		{
			Shavit_StopTimer(client);
		}

		SetEntityMoveType(client, MOVETYPE_NOCLIP);
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

	if((gI_NoclipMe == 1 || (gI_NoclipMe == 2 && CheckCommandAccess(client, "noclipme", ADMFLAG_CHEATS))) && command[0] == '+')
	{
		if(Shavit_GetTimerStatus(client) != Timer_Stopped)
		{
			Shavit_StopTimer(client);
		}
		
		SetEntityMoveType(client, MOVETYPE_NOCLIP);
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

	int iSpecTarget = client;

	if(IsClientObserver(client))
	{
		iSpecTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	}

	if(args > 0)
	{
		char[] sTarget = new char[MAX_TARGET_LENGTH];
		GetCmdArgString(sTarget, MAX_TARGET_LENGTH);

		int iNewTarget = FindTarget(client, sTarget, false, false);

		if(iNewTarget == -1)
		{
			return Plugin_Handled;
		}

		if(!IsPlayerAlive(iNewTarget))
		{
			Shavit_PrintToChat(client, "%T", "SpectateDead", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

			return Plugin_Handled;
		}

		iSpecTarget = iNewTarget;
	}

	int iCount;
	char[] sSpecs = new char[192];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i))
		{
			continue;
		}

		if(GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == iSpecTarget)
		{
			iCount++;

			if(iCount == 1)
			{
				FormatEx(sSpecs, 192, "%s%N", gS_ChatStrings[sMessageVariable2], i);
			}

			else
			{
				Format(sSpecs, 192, "%s%s, %s%N", sSpecs, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable2], i);
			}
		}
	}

	if(iCount > 0)
	{
		Shavit_PrintToChat(client, "%T", "SpectatorCount", client, gS_ChatStrings[sMessageVariable2], iSpecTarget, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], iCount, gS_ChatStrings[sMessageText], sSpecs);
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "SpectatorCountZero", client, gS_ChatStrings[sMessageVariable2], iSpecTarget, gS_ChatStrings[sMessageText]);
	}

	return Plugin_Handled;
}

public Action Shavit_OnStart(int client)
{
	if(!gA_StyleSettings[gBS_Style[client]][bPrespeed] && GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		return Plugin_Stop;
	}

	if(gB_ResetTargetname)
	{
		DispatchKeyValue(client, "targetname", "");
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
	char[] sUpperCase = new char[64];
	strcopy(sUpperCase, 64, gS_StyleStrings[style][sStyleName]);

	for(int i = 0; i < strlen(sUpperCase); i++)
	{
		if(!IsCharUpper(sUpperCase[i]))
		{
			sUpperCase[i] = CharToUpper(sUpperCase[i]);
		}
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i))
		{
			continue;
		}

		char[] sTrack = new char[32];
		GetTrackName(i, track, sTrack, 32);

		for(int j = 1; j <= 3; j++)
		{
			if(track == Track_Main)
			{
				Shavit_PrintToChat(i, "%T", "WRNotice", i, gS_ChatStrings[sMessageWarning], sUpperCase);
			}

			else
			{
				Shavit_PrintToChat(i, "%s[%s]%s %T", gS_ChatStrings[sMessageVariable], sTrack, gS_ChatStrings[sMessageText], "WRNotice", i, gS_ChatStrings[sMessageWarning], sUpperCase);
			}
		}
	}
}

public void Shavit_OnRestart(int client)
{
	if(!gB_RespawnOnRestart)
	{
		return;
	}

	if(!IsPlayerAlive(client))
	{
		if(FindEntityByClassname(-1, "info_player_terrorist") != -1)
		{
			CS_SwitchTeam(client, CS_TEAM_T);
		}

		else
		{
			CS_SwitchTeam(client, CS_TEAM_CT);
		}

		CreateTimer(0.1, Respawn, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Respawn(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(IsValidClient(client) && !IsPlayerAlive(client) && GetClientTeam(client) >= CS_TEAM_T)
	{
		CS_RespawnPlayer(client);

		if(gB_RespawnOnRestart)
		{
			RestartTimer(client);
		}
	}

	return Plugin_Handled;
}

void RestartTimer(int client)
{
	if(Shavit_ZoneExists(Zone_Start, Track_Main))
	{
		Shavit_RestartTimer(client, Track_Main);
	}
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsFakeClient(client))
	{
		int serial = GetClientSerial(client);

		if(gB_HideRadar)
		{
			RequestFrame(RemoveRadar, serial);
		}

		if(gB_StartOnSpawn)
		{
			RestartTimer(client);
		}

		if(gB_SaveStates[client])
		{
			if(gB_RestoreStates)
			{
				RequestFrame(RestoreState, serial);
			}

			else
			{
				gB_SaveStates[client] = false;
			}
		}

		if(gB_Scoreboard)
		{
			UpdateScoreboard(client);
		}

		if(gB_ClanTag)
		{
			UpdateClanTag(client);
		}
	}

	if(gB_NoBlock)
	{
		SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
	}

	if(gI_PlayerOpacity != -1)
	{
		SetEntityRenderMode(client, RENDER_TRANSCOLOR);
		SetEntityRenderColor(client, 255, 255, 255, gI_PlayerOpacity);
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

	else
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

	LoadState(client);
}

public Action Player_Notifications(Event event, const char[] name, bool dontBroadcast)
{
	if(gB_HideTeamChanges)
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

		if(gF_AutoRespawn > 0.0 && StrEqual(name, "player_death"))
		{
			CreateTimer(gF_AutoRespawn, Respawn, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	switch(gI_RemoveRagdolls)
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
	if(gI_WeaponCommands < 2)
	{
		return;
	}

	char[] sWeapon = new char[16];
	event.GetString("weapon", sWeapon, 16);

	if(StrContains(sWeapon, "usp") != -1 || StrContains(sWeapon, "hpk") != -1 || StrEqual(sWeapon, "glock"))
	{
		int client = GetClientOfUserId(event.GetInt("userid"));

		SetWeaponAmmo(client, GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"));
	}
}

public Action Shotgun_Shot(const char[] te_name, const int[] Players, int numClients, float delay)
{
	int client = (TE_ReadNum("m_iPlayer") + 1);
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
		if(!IsValidClient(i) || i == client || gB_Hide[i])
		{
			continue;
		}

		if(IsClientObserver(i) && GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == client)
		{
			// recycling code from shavit-hud~
			int iObserverMode = GetEntProp(i, Prop_Send, "m_iObserverMode");

			if(iObserverMode >= 3 && iObserverMode <= 5)
			{
				clients[count++] = i;
			}
		}
	}

	if(numClients == count)
	{
		return Plugin_Continue;
	}

	float temp[3];
	TE_Start("Shotgun Shot");
	TE_ReadVector("m_vecOrigin", temp);
	TE_WriteVector("m_vecOrigin", temp);
	TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
	TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
	
	if(gEV_Type == Engine_CSS)
	{
		TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
	}

	else
	{
		TE_WriteNum("m_weapon", TE_ReadNum("m_weapon"));
	}
        
	TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
	TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
	TE_WriteNum("m_iPlayer", (client - 1));
	TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
	TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
	TE_Send(clients, count, delay);

	return Plugin_Stop;
}

public Action EffectDispatch(const char[] te_name, const Players[], int numClients, float delay)
{
	if(!gB_NoBlood)
	{
		return Plugin_Continue;
	}

	int iEffectIndex = TE_ReadNum("m_iEffectName");
	int nHitBox = TE_ReadNum("m_nHitBox");

	char[] sEffectName = new char[32];
	GetEffectName(iEffectIndex, sEffectName, 32);

	if(StrEqual(sEffectName, "csblood"))
	{
		return Plugin_Handled;
	}

	if(StrEqual(sEffectName, "ParticleEffect"))
	{
		char[] sParticleEffectName = new char[32];
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
	if(!gB_NoBlood)
	{
		return Plugin_Continue;
	}

	float vecOrigin[3];
	TE_ReadVector("m_vecOrigin", vecOrigin);

	int nIndex = TE_ReadNum("m_nIndex");

	char[] sDecalName = new char[32];
	GetDecalName(nIndex, sDecalName, 32);

	if(StrContains(sDecalName, "decals/blood") == 0 && StrContains(sDecalName, "_subrect") != -1)
	{
		return Plugin_Handled;
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
	if(!gB_Scoreboard)
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
	if(!gB_DropAll || !IsValidClient(client))
	{
		return Plugin_Continue;
	}

	int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

	if(weapon != -1 && IsValidEntity(weapon))
	{
		CS_DropWeapon(client, weapon, true);
	}

	return Plugin_Handled;
}

void LoadState(int client)
{
	TeleportEntity(client, gF_SaveStateData[client][0], gF_SaveStateData[client][1], gF_SaveStateData[client][2]);
	DispatchKeyValue(client, "targetname", gS_SaveStateTargetname[client]);

	Shavit_LoadSnapshot(client, gA_SaveStates[client]);

	if(gA_SaveFrames[client] != null)
	{
		if(gB_Replay)
		{
			Shavit_SetReplayData(client, gA_SaveFrames[client]);
		}

		delete gA_SaveFrames[client];
		gA_SaveFrames[client] = null;
	}

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

	if(gB_Replay)
	{
		gA_SaveFrames[client] = Shavit_GetReplayData(client);
	}

	gB_SaveStates[client] = true;
}

void UpdateFootsteps(int client)
{
	if(sv_footsteps != null)
	{
		char[] sFootsteps = new char[4];
		IntToString((gB_Hide[client])? 0:sv_footsteps.IntValue, sFootsteps, 4);
		sv_footsteps.ReplicateToClient(client, sFootsteps);
	}
}

bool IsNullVector(float vec[3])
{
	return (vec[0] == NULL_VECTOR[0] && vec[1] == NULL_VECTOR[1] && vec[2] == NULL_VECTOR[2]);
}
