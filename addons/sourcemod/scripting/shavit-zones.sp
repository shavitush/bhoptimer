/*
 * shavit's Timer - Map Zones
 * by: shavit, GAMMA CASE, rtldg, KiD Fearless, Kryptanyte, carnifex, rumour, BoomShotKapow, Nuko, Technoblazed, Kxnrl, Extan, sh4hrazad, olivia
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
#include <clientprefs>
#include <sdktools>
#include <sdkhooks>
#include <convar_class>
#include <dhooks>
#include <profiler>

#include <shavit/core>
#include <shavit/zones>
#include <shavit/physicsuntouch>

#undef REQUIRE_PLUGIN
#include <adminmenu>
#include <shavit/replay-recorder>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#include <tf2>
#include <eventqueuefix>

#pragma semicolon 1
#pragma newdecls required

#define DEBUG 0

#define FSOLID_NOT_SOLID 4
#define FSOLID_TRIGGER 8
#define EF_NODRAW 32
#define SOLID_BBOX 2

EngineVersion gEV_Type = Engine_Unknown;

Database gH_SQL = null;
int gI_Driver = Driver_unknown;

bool gB_YouCanLoadZonesNow = false;

char gS_Map[PLATFORM_MAX_PATH];

enum struct zone_settings_t
{
	bool bVisible;
	int iRed;
	int iGreen;
	int iBlue;
	int iAlpha;
	float fWidth;
	bool bFlatZone;
	bool bUseVanillaSprite;
	bool bNoHalo;
	int iBeam;
	int iHalo;
	int iSpeed;
	char sBeam[PLATFORM_MAX_PATH];
}

// 0 - nothing
// 1 - wait for E tap to setup first coord
// 2 - wait for E tap to setup second coord
// 3 - confirm
int gI_MapStep[MAXPLAYERS+1];
Handle gH_StupidTimer[MAXPLAYERS+1];
int gI_CurrentTraceEntity = 0;
zone_cache_t gA_EditCache[MAXPLAYERS+1];
int gI_HookListPos[MAXPLAYERS+1];
int gI_ZoneID[MAXPLAYERS+1];
bool gB_WaitingForChatInput[MAXPLAYERS+1];
float gV_WallSnap[MAXPLAYERS+1][3];
bool gB_Button[MAXPLAYERS+1];

float gF_Modifier[MAXPLAYERS+1];
int gI_AdjustAxis[MAXPLAYERS+1];
int gI_GridSnap[MAXPLAYERS+1];
bool gB_SnapToWall[MAXPLAYERS+1];
bool gB_CursorTracing[MAXPLAYERS+1];
bool gB_IgnoreTriggers[MAXPLAYERS+1];

int gI_LatestTeleportTick[MAXPLAYERS+1];

// player zone status
int gI_InsideZone[MAXPLAYERS+1][TRACKS_SIZE]; // bit flag
bool gB_InsideZoneID[MAXPLAYERS+1][MAX_ZONES];

// zone cache
zone_settings_t gA_ZoneSettings[ZONETYPES_SIZE][TRACKS_SIZE];
zone_cache_t gA_ZoneCache[MAX_ZONES]; // Vectors will not be inside this array.
int gI_MapZones = 0;
float gV_MapZones_Visual[MAX_ZONES][8][3];
float gV_ZoneCenter[MAX_ZONES][3];
int gI_HighestStage[TRACKS_SIZE];
float gF_CustomSpawn[TRACKS_SIZE][3];
int gI_EntityZone[2048] = {-1, ...};
int gI_LastStage[MAXPLAYERS+1];

char gS_BeamSprite[PLATFORM_MAX_PATH];
char gS_BeamSpriteIgnoreZ[PLATFORM_MAX_PATH];
int gI_BeamSpriteIgnoreZ;

// admin menu
TopMenu gH_AdminMenu = null;
TopMenuObject gH_TimerCommands = INVALID_TOPMENUOBJECT;

// misc cache
bool gB_Late = false;
ConVar sv_gravity = null;

// cvars
Convar gCV_SQLZones = null;
Convar gCV_PrebuiltZones = null;
Convar gCV_ClimbButtons = null;
Convar gCV_Interval = null;
Convar gCV_TeleportToStart = null;
Convar gCV_TeleportToEnd = null;
Convar gCV_AllowDrawAllZones = null;
Convar gCV_UseCustomSprite = null;
Convar gCV_Height = null;
Convar gCV_Offset = null;
Convar gCV_EnforceTracks = null;
Convar gCV_BoxOffset = null;
Convar gCV_ExtraSpawnHeight = null;
Convar gCV_PrebuiltVisualOffset = null;
Convar gCV_EnableStageRestart = null;

Convar gCV_ForceTargetnameReset = null;
Convar gCV_ResetTargetnameMain = null;
Convar gCV_ResetTargetnameBonus = null;
Convar gCV_ResetClassnameMain = null;
Convar gCV_ResetClassnameBonus = null;

// handles
Handle gH_DrawVisible = null;
Handle gH_DrawAllZones = null;

bool gB_DrawAllZones[MAXPLAYERS+1];
Cookie gH_DrawAllZonesCookie = null;

// table prefix
char gS_MySQLPrefix[32];

// chat settings
chatstrings_t gS_ChatStrings;

// forwards
Handle gH_Forwards_EnterZone = null;
Handle gH_Forwards_LeaveZone = null;
Handle gH_Forwards_LoadZonesHere = null;
Handle gH_Forwards_StageMessage = null;

// sdkcalls
Handle gH_PhysicsRemoveTouchedList = null;
Handle gH_PassesTriggerFilters = null;
Handle gH_CommitSuicide = null; // sourcemod always finds a way to amaze me

// dhooks
DynamicHook gH_TeleportDhook = null;

// kz support
float gF_ClimbButtonCache[MAXPLAYERS+1][TRACKS_SIZE][2][3]; // 0 - location, 1 - angles

// set start
bool gB_HasSetStart[MAXPLAYERS+1][TRACKS_SIZE];
bool gB_StartAnglesOnly[MAXPLAYERS+1][TRACKS_SIZE];
float gF_StartPos[MAXPLAYERS+1][TRACKS_SIZE][3];
float gF_StartAng[MAXPLAYERS+1][TRACKS_SIZE][3];

// modules
bool gB_Eventqueuefix = false;
bool gB_ReplayRecorder = false;
bool gB_AdminMenu = false;

#define CZONE_VER 'c'
// custom zone stuff
Cookie gH_CustomZoneCookie = null;
Cookie gH_CustomZoneCookie2 = null; // fuck
int gI_ZoneDisplayType[MAXPLAYERS+1][ZONETYPES_SIZE][TRACKS_SIZE];
int gI_ZoneColor[MAXPLAYERS+1][ZONETYPES_SIZE][TRACKS_SIZE];
int gI_ZoneWidth[MAXPLAYERS+1][ZONETYPES_SIZE][TRACKS_SIZE];

int gI_LastMenuPos[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "[shavit] Map Zones",
	author = "shavit, GAMMA CASE, rtldg, KiD Fearless, Kryptanyte, carnifex, rumour, BoomShotKapow, Nuko, Technoblazed, Kxnrl, Extan, sh4hrazad, olivia",
	description = "Map zones for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// zone natives
	CreateNative("Shavit_GetZoneData", Native_GetZoneData);
	CreateNative("Shavit_GetZoneFlags", Native_GetZoneFlags);
	CreateNative("Shavit_GetHighestStage", Native_GetHighestStage);
	CreateNative("Shavit_InsideZone", Native_InsideZone);
	CreateNative("Shavit_InsideZoneGetID", Native_InsideZoneGetID);
	CreateNative("Shavit_IsClientCreatingZone", Native_IsClientCreatingZone);
	CreateNative("Shavit_ZoneExists", Native_ZoneExists);
	CreateNative("Shavit_Zones_DeleteMap", Native_Zones_DeleteMap);
	CreateNative("Shavit_SetStart", Native_SetStart);
	CreateNative("Shavit_DeleteSetStart", Native_DeleteSetStart);
	CreateNative("Shavit_GetClientLastStage", Native_GetClientLastStage);
	CreateNative("Shavit_GetZoneTrack", Native_GetZoneTrack);
	CreateNative("Shavit_GetZoneType", Native_GetZoneType);
	CreateNative("Shavit_GetZoneID", Native_GetZoneID);
	CreateNative("Shavit_ReloadZones", Native_ReloadZones);
	CreateNative("Shavit_UnloadZones", Native_UnloadZones);
	CreateNative("Shavit_GetZoneCount", Native_GetZoneCount);
	CreateNative("Shavit_GetZone", Native_GetZone);
	CreateNative("Shavit_AddZone", Native_AddZone);
	CreateNative("Shavit_RemoveZone", Native_RemoveZone);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-zones");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-zones.phrases");

	// game specific
	gEV_Type = GetEngineVersion();

	// menu
	RegAdminCmd("sm_addzone", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu.");
	RegAdminCmd("sm_zones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu.");
	RegAdminCmd("sm_mapzones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu. Alias of sm_zones.");

	RegAdminCmd("sm_delzone", Command_DeleteZone, ADMFLAG_RCON, "Delete a mapzone");
	RegAdminCmd("sm_deletezone", Command_DeleteZone, ADMFLAG_RCON, "Delete a mapzone");
	RegAdminCmd("sm_deleteallzones", Command_DeleteAllZones, ADMFLAG_RCON, "Delete all mapzones");

	RegAdminCmd("sm_modifier", Command_Modifier, ADMFLAG_RCON, "Changes the axis modifier for the zone editor. Usage: sm_modifier <number>");

	RegAdminCmd("sm_addspawn", Command_AddSpawn, ADMFLAG_RCON, "Adds a custom spawn location");
	RegAdminCmd("sm_delspawn", Command_DelSpawn, ADMFLAG_RCON, "Deletes a custom spawn location");

	RegAdminCmd("sm_zoneedit", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone.");
	RegAdminCmd("sm_editzone", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone. Alias of sm_zoneedit.");
	RegAdminCmd("sm_modifyzone", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone. Alias of sm_zoneedit.");
	RegAdminCmd("sm_hookzone", Command_HookZone, ADMFLAG_RCON, "Hook an existing trigger, teleporter, or button.");

	RegAdminCmd("sm_tptozone", Command_TpToZone, ADMFLAG_RCON, "Teleport to a zone");

	RegAdminCmd("sm_reloadzonesettings", Command_ReloadZoneSettings, ADMFLAG_ROOT, "Reloads the zone settings.");

	RegConsoleCmd("sm_beamer", Command_Beamer, "Draw cool beams");

	RegConsoleCmd("sm_stages", Command_Stages, "Opens the stage menu. Usage: sm_stages [stage #]");
	RegConsoleCmd("sm_stage", Command_Stages, "Opens the stage menu. Usage: sm_stage [stage #]");
	RegConsoleCmd("sm_s", Command_Stages, "Opens the stage menu. Usage: sm_s [stage #]");

	RegConsoleCmd("sm_rs", Command_StageRestart, "Teleports the player to the current stage. Only works on surf maps.");
	RegConsoleCmd("sm_stagerestart", Command_StageRestart, "Teleports the player to the current stage. Only works on surf maps.");
	RegConsoleCmd("sm_restartstage", Command_StageRestart, "Teleports the player to the current stage. Only works on surf maps.");

	RegConsoleCmd("sm_set", Command_SetStart, "Set current position as spawn location in start zone.");
	RegConsoleCmd("sm_setstart", Command_SetStart, "Set current position as spawn location in start zone.");
	RegConsoleCmd("sm_ss", Command_SetStart, "Set current position as spawn location in start zone.");
	RegConsoleCmd("sm_sp", Command_SetStart, "Set current position as spawn location in start zone.");
	RegConsoleCmd("sm_startpoint", Command_SetStart, "Set current position as spawn location in start zone.");

	RegConsoleCmd("sm_deletestart", Command_DeleteSetStart, "Deletes the custom set start position.");
	RegConsoleCmd("sm_deletesetstart", Command_DeleteSetStart, "Deletes the custom set start position.");
	RegConsoleCmd("sm_delss", Command_DeleteSetStart, "Deletes the custom set start position.");
	RegConsoleCmd("sm_delsp", Command_DeleteSetStart, "Deletes the custom set start position.");

	RegConsoleCmd("sm_drawallzones", Command_DrawAllZones, "Toggles drawing all zones.");
	RegConsoleCmd("sm_drawzones", Command_DrawAllZones, "Toggles drawing all zones.");
	gH_DrawAllZonesCookie = new Cookie("shavit_drawallzones", "Draw all zones cookie", CookieAccess_Protected);

	RegConsoleCmd("sm_czone", Command_CustomZones, "Customize start and end zone for each track");
	RegConsoleCmd("sm_czones", Command_CustomZones, "Customize start and end zone for each track");
	RegConsoleCmd("sm_customzones", Command_CustomZones, "Customize start and end zone for each track");

	gH_CustomZoneCookie = new Cookie("shavit_customzones", "Cookie for storing custom zone stuff", CookieAccess_Private);
	gH_CustomZoneCookie2 = new Cookie("shavit_customzones2", "Cooke (AGAIN) for storing custom zone stuff", CookieAccess_Private);

	for (int i = 0; i <= 9; i++)
	{
		char cmd[30];
		FormatEx(cmd, sizeof(cmd), "sm_s%d%cGo to stage %d", i, 0, i); // 😈
		RegConsoleCmd(cmd, Command_Stages, cmd[6]);
	}

	// events
	if(gEV_Type == Engine_TF2)
	{
		HookEvent("teamplay_round_start", Round_Start);
	}
	else
	{
		HookEvent("round_start", Round_Start);
	}

	HookEvent("player_spawn", Player_Spawn);

	// forwards
	gH_Forwards_EnterZone = CreateGlobalForward("Shavit_OnEnterZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_LeaveZone = CreateGlobalForward("Shavit_OnLeaveZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_LoadZonesHere = CreateGlobalForward("Shavit_LoadZonesHere", ET_Event);
	gH_Forwards_StageMessage = CreateGlobalForward("Shavit_OnStageMessage", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);

	// cvars and stuff
	gCV_SQLZones = new Convar("shavit_zones_usesql", "1", "Whether to automatically load zones from the database or not.\n0 - Load nothing. (You'll need a plugin to add zones with `Shavit_AddZone()`)\n1 - Load zones from database.", 0, true, 0.0, true, 1.0);
	gCV_PrebuiltZones = new Convar("shavit_zones_useprebuilt", "1", "Whether to automatically hook mod_zone_* zone entities.", 0, true, 0.0, true, 1.0);
	gCV_ClimbButtons = new Convar("shavit_zones_usebuttons", "1", "Whether to automatically hook climb_* buttons.", 0, true, 0.0, true, 1.0);
	gCV_Interval = new Convar("shavit_zones_interval", "1.0", "Interval between each time a mapzone is being drawn to the players.", 0, true, 0.25, true, 5.0);
	gCV_TeleportToStart = new Convar("shavit_zones_teleporttostart", "1", "Teleport players to the start zone on timer restart?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_TeleportToEnd = new Convar("shavit_zones_teleporttoend", "1", "Teleport players to the end zone on sm_end?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_AllowDrawAllZones = new Convar("shavit_zones_allowdrawallzones", "1", "Allow players to use !drawallzones to see all zones regardless of zone visibility settings.\n0 - nobody can use !drawallzones\n1 - admins (sm_zones access) can use !drawallzones\n2 - anyone can use !drawallzones", 0, true, 0.0, true, 2.0);
	gCV_UseCustomSprite = new Convar("shavit_zones_usecustomsprite", "1", "Use custom sprite for zone drawing?\nSee `configs/shavit-zones.cfg`.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_Height = new Convar("shavit_zones_height", "128.0", "Height to use for the start zone.", 0, true, 0.0, false);
	gCV_Offset = new Convar("shavit_zones_offset", "1.0", "When calculating a zone's *VISUAL* box, by how many units, should we scale it to the center?\n0.0 - no downscaling. Values above 0 will scale it inward and negative numbers will scale it outwards.\nAdjust this value if the zones clip into walls.");
	gCV_EnforceTracks = new Convar("shavit_zones_enforcetracks", "1", "Enforce zone tracks upon entry?\n0 - allow every zone except for start/end to affect users on every zone.\n1 - require the user's track to match the zone's track.", 0, true, 0.0, true, 1.0);
	gCV_BoxOffset = new Convar("shavit_zones_box_offset", "1", "Offset zone trigger boxes to the center of a player's bounding box or the edges.\n0 - triggers when edges of the bounding boxes touch.\n1 - triggers when the center of a player is in a zone.", 0, true, 0.0, true, 1.0);
	gCV_ExtraSpawnHeight = new Convar("shavit_zones_extra_spawn_height", "0.0", "YOU DONT NEED TO TOUCH THIS USUALLY. FIX YOUR ACTUAL ZONES.\nUsed to fix some shit prebuilt zones that are in the ground like bhop_strafecontrol");
	gCV_PrebuiltVisualOffset = new Convar("shavit_zones_prebuilt_visual_offset", "0", "YOU DONT NEED TO TOUCH THIS USUALLY.\nUsed to fix the VISUAL beam offset for prebuilt zones on a map.\nExample maps you'd want to use 16 on: bhop_tranquility and bhop_amaranthglow");
	gCV_EnableStageRestart = new Convar("shavit_zones_enable_stage_restart", "1", "Whether clients can use !stagerestart/!restartstage/!rs to restart to the current stage zone. Currently only available for `surf_` maps.", 0, true, 0.0, true, 1.0);

	gCV_ForceTargetnameReset = new Convar("shavit_zones_forcetargetnamereset", "0", "Reset the player's targetname upon timer start?\nRecommended to leave disabled. Enable via per-map configs when necessary.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_ResetTargetnameMain = new Convar("shavit_zones_resettargetname_main", "", "What targetname to use when resetting the player.\nWould be applied once player teleports to the start zone or on every start if shavit_zones_forcetargetnamereset cvar is set to 1.\nYou don't need to touch this");
	gCV_ResetTargetnameBonus = new Convar("shavit_zones_resettargetname_bonus", "", "What targetname to use when resetting the player (on bonus tracks).\nWould be applied once player teleports to the start zone or on every start if shavit_zones_forcetargetnamereset cvar is set to 1.\nYou don't need to touch this");
	gCV_ResetClassnameMain = new Convar("shavit_zones_resetclassname_main", "", "What classname to use when resetting the player.\nWould be applied once player teleports to the start zone or on every start if shavit_zones_forcetargetnamereset cvar is set to 1.\nYou don't need to touch this");
	gCV_ResetClassnameBonus = new Convar("shavit_zones_resetclassname_bonus", "", "What classname to use when resetting the player (on bonus tracks).\nWould be applied once player teleports to the start zone or on every start if shavit_zones_forcetargetnamereset cvar is set to 1.\nYou don't need to touch this");

	gCV_SQLZones.AddChangeHook(OnConVarChanged);
	gCV_PrebuiltZones.AddChangeHook(OnConVarChanged);
	gCV_ClimbButtons.AddChangeHook(OnConVarChanged);
	gCV_Interval.AddChangeHook(OnConVarChanged);
	gCV_UseCustomSprite.AddChangeHook(OnConVarChanged);
	gCV_Offset.AddChangeHook(OnConVarChanged);
	gCV_PrebuiltVisualOffset.AddChangeHook(OnConVarChanged);
	gCV_BoxOffset.AddChangeHook(OnConVarChanged);

	Convar.AutoExecConfig();

	LoadDHooks();

	// misc cvars
	sv_gravity = FindConVar("sv_gravity");

	for(int i = 0; i < ZONETYPES_SIZE; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gA_ZoneSettings[i][j].bVisible = true;
			gA_ZoneSettings[i][j].iRed = 255;
			gA_ZoneSettings[i][j].iGreen = 255;
			gA_ZoneSettings[i][j].iBlue = 255;
			gA_ZoneSettings[i][j].iAlpha = 255;
			gA_ZoneSettings[i][j].fWidth = 2.0;
			gA_ZoneSettings[i][j].bFlatZone = false;
		}
	}

	gB_ReplayRecorder = LibraryExists("shavit-replay-recorder");
	gB_Eventqueuefix = LibraryExists("eventqueuefix");
	gB_AdminMenu = LibraryExists("adminmenu");

	if (gB_Late)
	{
		GetLowercaseMapName(gS_Map); // erm...
		Shavit_OnChatConfigLoaded();
		Shavit_OnDatabaseLoaded();

		if (gB_AdminMenu && (gH_AdminMenu = GetAdminTopMenu()) != null)
		{
			OnAdminMenuReady(gH_AdminMenu);
		}

		for(int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i))
			{
				OnClientConnected(i);
				OnClientPutInServer(i);

				if (AreClientCookiesCached(i))
				{
					OnClientCookiesCached(i);
				}
			}
		}

		for (int entity = MaxClients+1, last = GetMaxEntities(); entity <= last; ++entity)
		{
			if (IsValidEntity(entity))
			{
				char classname[64];
				GetEntityClassname(entity, classname, sizeof(classname));
				OnEntityCreated(entity, classname);
			}
		}
	}
}

void KillShavitZoneEnts(const char[] classname)
{
	char targetname[64];
	int ent = -1;

	while ((ent = FindEntityByClassname(ent, classname)) != -1)
	{
		GetEntPropString(ent, Prop_Data, "m_iName", targetname, sizeof(targetname));

		if (StrContains(targetname, "shavit_zones_") == 0)
		{
			AcceptEntityInput(ent, "Kill");
		}
	}
}

public void OnPluginEnd()
{
	KillShavitZoneEnts("trigger_multiple");
	KillShavitZoneEnts("player_speedmod");
}

void LoadDHooks()
{
	Handle hGameData = LoadGameConfigFile("shavit.games");

	if (hGameData == null)
	{
		SetFailState("Failed to load shavit gamedata");
	}

	LoadPhysicsUntouch(hGameData);

	if (gEV_Type == Engine_CSGO)
	{
		StartPrepSDKCall(SDKCall_Entity);
	}
	else
	{
		StartPrepSDKCall(SDKCall_Static);
	}

	if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "PhysicsRemoveTouchedList"))
	{
		SetFailState("Failed to find \"PhysicsRemoveTouchedList\" signature!");
	}

	if (gEV_Type != Engine_CSGO)
	{
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	}

	gH_PhysicsRemoveTouchedList = EndPrepSDKCall();

	if (!gH_PhysicsRemoveTouchedList)
	{
		SetFailState("Failed to create sdkcall to \"PhysicsRemoveTouchedList\"!");
	}

	StartPrepSDKCall(SDKCall_Entity);

	if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CBaseTrigger::PassesTriggerFilters"))
	{
		SetFailState("Failed to find \"CBaseTrigger::PassesTriggerFilters\" offset!");
	}

	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);

	if (!(gH_PassesTriggerFilters = EndPrepSDKCall()))
	{
		SetFailState("Failed to create sdkcall to \"CBaseTrigger::PassesTriggerFilters\"!");
	}

	delete hGameData;

	hGameData = LoadGameConfigFile("sdktools.games");
	if (hGameData == null)
	{
		SetFailState("Failed to load sdktools gamedata");
	}

	int iOffset = GameConfGetOffset(hGameData, "Teleport");
	if (iOffset == -1)
	{
		SetFailState("Couldn't get the offset for \"Teleport\"!");
	}

	gH_TeleportDhook = new DynamicHook(iOffset, HookType_Entity, ReturnType_Void, ThisPointer_CBaseEntity);

	gH_TeleportDhook.AddParam(HookParamType_VectorPtr);
	gH_TeleportDhook.AddParam(HookParamType_VectorPtr);
	gH_TeleportDhook.AddParam(HookParamType_VectorPtr);
	if (GetEngineVersion() == Engine_CSGO)
	{
		gH_TeleportDhook.AddParam(HookParamType_Bool);
	}

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CommitSuicide");
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_ByValue); // explode
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_ByValue); // force
	if (!(gH_CommitSuicide = EndPrepSDKCall()))
	{
		SetFailState("Failed to create sdkcall to \"CommitSuicide\"");
	}

	delete hGameData;
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "adminmenu") == 0)
	{
		gB_AdminMenu = true;
	}
	else if (StrEqual(name, "shavit-replay-recorder"))
	{
		gB_ReplayRecorder = true;
	}
	else if (StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "adminmenu") == 0)
	{
		gB_AdminMenu = false;
		gH_AdminMenu = null;
		gH_TimerCommands = INVALID_TOPMENUOBJECT;
	}
	else if (StrEqual(name, "shavit-replay-recorder"))
	{
		gB_ReplayRecorder = false;
	}
	else if (StrEqual(name, "eventqueuefix"))
	{
		gB_Eventqueuefix = false;
	}
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(convar == gCV_Interval)
	{
		delete gH_DrawVisible;
		delete gH_DrawAllZones;
		gH_DrawVisible = CreateTimer(gCV_Interval.FloatValue, Timer_DrawZones, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		gH_DrawAllZones = CreateTimer(gCV_Interval.FloatValue, Timer_DrawZones, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	else if (convar == gCV_Offset || convar == gCV_PrebuiltVisualOffset)
	{
		for (int i = 0; i < gI_MapZones; i++)
		{
			if ((convar == gCV_Offset && gA_ZoneCache[i].iForm == ZoneForm_Box)
			||  (convar == gCV_PrebuiltVisualOffset && gA_ZoneCache[i].iForm == ZoneForm_trigger_multiple))
			{
				gV_MapZones_Visual[i][0] = gA_ZoneCache[i].fCorner1;
				gV_MapZones_Visual[i][7] = gA_ZoneCache[i].fCorner2;

				CreateZonePoints(gV_MapZones_Visual[i], convar == gCV_PrebuiltVisualOffset);
			}
		}
	}
	else if(convar == gCV_UseCustomSprite && !StrEqual(oldValue, newValue))
	{
		LoadZoneSettings();
	}
	else if (convar == gCV_BoxOffset)
	{
		for (int i = 0; i < gI_MapZones; i++)
		{
			if (gA_ZoneCache[i].iForm == ZoneForm_Box && gA_ZoneCache[i].iEntity > 0)
			{
				SetZoneMinsMaxs(i);
			}
		}
	}
	else if (convar == gCV_SQLZones)
	{
		for (int i = gI_MapZones; i > 0; i--)
		{
			if (StrEqual(gA_ZoneCache[i-1].sSource, "sql"))
				Shavit_RemoveZone(i-1);
		}

		if (convar.BoolValue) RefreshZones();
	}
	else if (convar == gCV_PrebuiltZones)
	{
		for (int i = gI_MapZones; i > 0; i--)
		{
			if (StrEqual(gA_ZoneCache[i-1].sSource, "autozone"))
				Shavit_RemoveZone(i-1);
		}

		if (convar.BoolValue) add_prebuilts_to_cache("trigger_multiple", false);
	}
	else if (convar == gCV_ClimbButtons)
	{
		for (int i = gI_MapZones; i > 0; i--)
		{
			if (StrEqual(gA_ZoneCache[i-1].sSource, "autobutton"))
				Shavit_RemoveZone(i-1);
		}

		if (convar.BoolValue) add_prebuilts_to_cache("func_button", true);
		if (convar.BoolValue) add_prebuilts_to_cache("func_rot_button", true);
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	gH_AdminMenu = TopMenu.FromHandle(topmenu);

	if ((gH_TimerCommands = gH_AdminMenu.FindCategory("Timer Commands")) != INVALID_TOPMENUOBJECT)
	{
		gH_AdminMenu.AddItem("sm_zones", AdminMenu_Zones, gH_TimerCommands, "sm_zones", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_deletezone", AdminMenu_DeleteZone, gH_TimerCommands, "sm_deletezone", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_deleteallzones", AdminMenu_DeleteAllZones, gH_TimerCommands, "sm_deleteallzones", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_zoneedit", AdminMenu_ZoneEdit, gH_TimerCommands, "sm_zoneedit", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_tptozone", AdminMenu_TpToZone, gH_TimerCommands, "sm_tptozone", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_hookzone", AdminMenu_HookZone, gH_TimerCommands, "sm_hookzone", ADMFLAG_RCON);
	}
}

public void AdminMenu_Zones(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "AddMapZone", param);
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Command_Zones(param, 0);
	}
}

public void AdminMenu_DeleteZone(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "DeleteMapZone", param);
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteZone(param, 0);
	}
}

public void AdminMenu_DeleteAllZones(Handle topmenu,  TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "DeleteAllMapZone", param);
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteAllZones(param, 0);
	}
}

public void AdminMenu_ZoneEdit(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "ZoneEdit", param);
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Reset(param);
		OpenEditMenu(param);
	}
}

public void AdminMenu_TpToZone(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "TpToZone", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		OpenTpToZoneMenu(param);
	}
}

public void AdminMenu_HookZone(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if (action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "HookZone", param);
	}
	else if (action == TopMenuAction_SelectOption)
	{
		OpenHookMenu_Form(param);
	}
}

public int Native_ZoneExists(Handle handler, int numParams)
{
	return (GetZoneIndex(GetNativeCell(1), GetNativeCell(2)) != -1);
}

public int Native_GetZoneData(Handle handler, int numParams)
{
	return gA_ZoneCache[GetNativeCell(1)].iData;
}

public int Native_GetZoneFlags(Handle handler, int numParams)
{
	return gA_ZoneCache[GetNativeCell(1)].iFlags;
}

public int Native_InsideZone(Handle handler, int numParams)
{
	return InsideZone(GetNativeCell(1), GetNativeCell(2), (numParams > 2) ? GetNativeCell(3) : -1);
}

public int Native_InsideZoneGetID(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int iType = GetNativeCell(2);
	int iTrack = GetNativeCell(3);

	if (iTrack >= 0 && !(gI_InsideZone[client][iTrack] & (1 << iType)))
	{
		return false;
	}

	for (int i = 0; i < gI_MapZones; i++)
	{
		if(gB_InsideZoneID[client][i] &&
			gA_ZoneCache[i].iType == iType &&
			(gA_ZoneCache[i].iTrack == iTrack || iTrack == -1))
		{
			SetNativeCellRef(4, i);

			return true;
		}
	}

	return false;
}

public int Native_GetHighestStage(Handle handler, int numParas)
{
	return gI_HighestStage[GetNativeCell(1)];
}

public int Native_Zones_DeleteMap(Handle handler, int numParams)
{
	char sMap[PLATFORM_MAX_PATH];
	GetNativeString(1, sMap, sizeof(sMap));
	LowercaseString(sMap);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM %smapzones WHERE map = '%s';", gS_MySQLPrefix, sMap);
	QueryLog(gH_SQL, SQL_DeleteMap_Callback, sQuery, StrEqual(gS_Map, sMap, false), DBPrio_High);
	return 1;
}

public void SQL_DeleteMap_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zones deletemap) SQL query failed. Reason: %s", error);

		return;
	}

	if(view_as<bool>(data))
	{
		//DBConnectedSoDoStuff();
	}
}

bool InsideZone(int client, int type, int track)
{
	if(track != -1)
	{
		return (gI_InsideZone[client][track] & (1 << type)) != 0;
	}
	else
	{
		int res = 0;

		for(int i = 0; i < TRACKS_SIZE; i++)
		{
			res |= gI_InsideZone[client][i];
		}

		return (res & (1 << type)) != 0;
	}
}

public int Native_IsClientCreatingZone(Handle handler, int numParams)
{
	return (gI_MapStep[GetNativeCell(1)] != 0);
}

public int Native_SetStart(Handle handler, int numParams)
{
	SetStart(GetNativeCell(1), GetNativeCell(2), view_as<bool>(GetNativeCell(3)));
	return 1;
}

public int Native_DeleteSetStart(Handle handler, int numParams)
{
	DeleteSetStart(GetNativeCell(1), GetNativeCell(2));
	return 1;
}

public int Native_GetClientLastStage(Handle plugin, int numParams)
{
	return gI_LastStage[GetNativeCell(1)];
}

public any Native_GetZoneTrack(Handle plugin, int numParams)
{
	int zoneid = GetNativeCell(1);
	return gA_ZoneCache[zoneid].iTrack;
}

public any Native_GetZoneType(Handle plugin, int numParams)
{
	int zoneid = GetNativeCell(1);
	return gA_ZoneCache[zoneid].iType;
}

public any Native_GetZoneID(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	return gI_EntityZone[entity];
}

public any Native_ReloadZones(Handle plugin, int numParams)
{
	LoadZonesHere();
	return 0;
}

public any Native_UnloadZones(Handle plugin, int numParams)
{
	UnloadZones();
	return 0;
}

public any Native_GetZoneCount(Handle plugin, int numParams)
{
	return gI_MapZones;
}

public any Native_GetZone(Handle plugin, int numParams)
{
	if (GetNativeCell(3) != sizeof(zone_cache_t))
	{
		return ThrowNativeError(200, "zone_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins", GetNativeCell(3), sizeof(zone_cache_t));
	}

	SetNativeArray(2, gA_ZoneCache[GetNativeCell(1)], sizeof(zone_cache_t));
	return 0;
}

public any Native_AddZone(Handle plugin, int numParams)
{
	if (gI_MapZones >= MAX_ZONES)
	{
		return -1;
	}

	if (GetNativeCell(2) != sizeof(zone_cache_t))
	{
		return ThrowNativeError(200, "zone_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins", GetNativeCell(2), sizeof(zone_cache_t));
	}

	zone_cache_t cache;
	GetNativeArray(1, cache, sizeof(cache));
	cache.iEntity = -1;

	if (cache.iForm != ZoneForm_Box && (cache.iFlags & ZF_Origin))
	{
		// previously origins were "%X %X %X" instead of "%.9f %.9f %.9f"...
		// so we just convert this right now...
		//      "C56D0000 455D0000 C3600000"
		//   to "-3792.000000000 3536.000000000 -224.000000000"
		if (-1 == StrContains(cache.sTarget, "."))
		{
			Format(cache.sTarget, sizeof(cache.sTarget),
				"%.9f %.9f %.9f",
				StringToInt(cache.sTarget, 16),
				StringToInt(cache.sTarget[9], 16),
				StringToInt(cache.sTarget[18], 16)
			);
		}
	}

	BoxPointsToMinsMaxs(cache.fCorner1, cache.fCorner2, cache.fCorner1, cache.fCorner2);

	gA_ZoneCache[gI_MapZones] = cache;

	gV_MapZones_Visual[gI_MapZones][0] = cache.fCorner1;
	gV_MapZones_Visual[gI_MapZones][7] = cache.fCorner2;

	CreateZonePoints(gV_MapZones_Visual[gI_MapZones], cache.iForm == ZoneForm_trigger_multiple);

	AddVectors(cache.fCorner1, cache.fCorner2, gV_ZoneCenter[gI_MapZones]);
	ScaleVector(gV_ZoneCenter[gI_MapZones], 0.5);

	if (cache.iType == Zone_Stage)
	{
		if (cache.iData > gI_HighestStage[cache.iTrack])
		{
			gI_HighestStage[cache.iTrack] = cache.iData;
		}
	}

	return gI_MapZones++;
}

public any Native_RemoveZone(Handle plugin, int numParams)
{
	int index = GetNativeCell(1);

	if (gI_MapZones <= 0 || index >= gI_MapZones)
	{
		return 0;
	}

	zone_cache_t cache; cache = gA_ZoneCache[index];

	int ent = gA_ZoneCache[index].iEntity;
	ClearZoneEntity(index, true);

	if (ent > MaxClients && gA_ZoneCache[index].iForm == ZoneForm_Box) // created by shavit-zones
	{
		AcceptEntityInput(ent, "Kill");
	}

	int top = --gI_MapZones;

	if (index < top)
	{
		gI_EntityZone[gA_ZoneCache[top].iEntity] = index;
		gA_ZoneCache[index] = gA_ZoneCache[top];
		gV_ZoneCenter[index] = gV_ZoneCenter[top];

		for (int i = 0; i < sizeof(gV_MapZones_Visual[]); i++)
		{
			gV_MapZones_Visual[index][i] = gV_MapZones_Visual[top][i];
		}

		for (int i = 1; i <= MaxClients; i++)
		{
			gB_InsideZoneID[i][index] = gB_InsideZoneID[i][top];
		}
	}
	else
	{
		bool empty_InsideZoneID[MAX_ZONES];

		for (int i = 1; i <= MaxClients; i++)
		{
			gB_InsideZoneID[i] = empty_InsideZoneID;
		}
	}

	RecalcInsideZoneAll();

	if (cache.iType == Zone_Stage && cache.iData == gI_HighestStage[cache.iTrack])
		RecalcHighestStage();

	// call EndTouchPost(zoneent, player) manually here?

	return 0;
}

bool JumpToZoneType(KeyValues kv, int type, int track)
{
	static const char config_keys[ZONETYPES_SIZE][2][50] = {
		{"Start", ""},
		{"End", ""},
		{"Glitch_Respawn", "Glitch Respawn"},
		{"Glitch_Stop", "Glitch Stop"},
		{"Glitch_Slay", "Glitch Slay"},
		{"Freestyle", ""},
		{"Custom Speed Limit", "Nolimit"},
		{"Teleport", ""},
		{"SPAWN POINT", ""},
		{"Easybhop", ""},
		{"Slide", ""},
		{"Airaccelerate", ""},
		{"Stage", ""},
		{"No Timer Gravity", ""},
		{"Gravity", ""},
		{"Speedmod", ""},
		{"No Jump", ""},
		{"Autobhop", ""},
	};

	char key[4][50];

	if (track == Track_Main)
	{
		key[0] = config_keys[type][0];
		key[1] = config_keys[type][1];
	}
	else
	{
		FormatEx(key[0], sizeof(key[]), "Bonus %d %s", track, config_keys[type][0]);
		if (track == Track_Bonus)
			FormatEx(key[1], sizeof(key[]), "Bonus %s", config_keys[type][0]);

		if (config_keys[type][0][0])
		{
			FormatEx(key[2], sizeof(key[]), "Bonus %d %s", track, config_keys[type][1]);
			if (track == Track_Bonus)
				FormatEx(key[3], sizeof(key[]), "Bonus %s", config_keys[type][1]);
		}
	}

	for (int i = 0; i < 4; i++)
	{
		if (key[i][0] && kv.JumpToKey(key[i]))
		{
			return true;
		}
	}

	return false;
}

bool LoadZonesConfig()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-zones.cfg");

	KeyValues kv = new KeyValues("shavit-zones");

	if(!kv.ImportFromFile(sPath))
	{
		delete kv;

		return false;
	}

	kv.JumpToKey("Sprites");
	kv.GetString("beam", gS_BeamSprite, PLATFORM_MAX_PATH);
	kv.GetString("beam_ignorez", gS_BeamSpriteIgnoreZ, PLATFORM_MAX_PATH, gS_BeamSprite);

	char sDownloads[PLATFORM_MAX_PATH * 8];
	kv.GetString("downloads", sDownloads, (PLATFORM_MAX_PATH * 8));

	char sDownloadsExploded[PLATFORM_MAX_PATH][PLATFORM_MAX_PATH];
	int iDownloads = ExplodeString(sDownloads, ";", sDownloadsExploded, PLATFORM_MAX_PATH, PLATFORM_MAX_PATH, false);

	for(int i = 0; i < iDownloads; i++)
	{
		if(strlen(sDownloadsExploded[i]) > 0)
		{
			TrimString(sDownloadsExploded[i]);
			AddFileToDownloadsTable(sDownloadsExploded[i]);
		}
	}

	kv.GoBack();
	kv.JumpToKey("Colors");

	for (int type = 0; type < ZONETYPES_SIZE; type++)
	{
		if (type == Zone_CustomSpawn)
		{
			continue;
		}

		for (int track = 0; track < TRACKS_SIZE; track++)
		{
			if (JumpToZoneType(kv, type, track))
			{
				gA_ZoneSettings[type][track].bVisible = view_as<bool>(kv.GetNum("visible", 1));
				gA_ZoneSettings[type][track].iRed = kv.GetNum("red", 255);
				gA_ZoneSettings[type][track].iGreen = kv.GetNum("green", 255);
				gA_ZoneSettings[type][track].iBlue = kv.GetNum("blue", 255);
				gA_ZoneSettings[type][track].iAlpha = kv.GetNum("alpha", 255);
				gA_ZoneSettings[type][track].fWidth = kv.GetFloat("width", 2.0);
				gA_ZoneSettings[type][track].bFlatZone = view_as<bool>(kv.GetNum("flat", false));
				gA_ZoneSettings[type][track].bUseVanillaSprite = view_as<bool>(kv.GetNum("vanilla_sprite", false));
				gA_ZoneSettings[type][track].bNoHalo = view_as<bool>(kv.GetNum("no_halo", false));
				gA_ZoneSettings[type][track].iSpeed = kv.GetNum("speed", 0);
				kv.GetString("beam", gA_ZoneSettings[type][track].sBeam, sizeof(zone_settings_t::sBeam), "");
				kv.GoBack();
			}
			else if (track > Track_Bonus)
			{
				// Copy bonus 1 settings to any other bonuses that are missing this zone...
				gA_ZoneSettings[type][track] = gA_ZoneSettings[type][Track_Bonus];
			}
		}
	}

	delete kv;

	return true;
}

void LoadZoneSettings()
{
	if(!LoadZonesConfig())
	{
		SetFailState("Cannot open \"configs/shavit-zones.cfg\". Make sure this file exists and that the server has read permissions to it.");
	}

	int defaultBeam;
	int defaultHalo;
	int customBeam;

	if(IsSource2013(gEV_Type))
	{
		defaultBeam = PrecacheModel("sprites/laser.vmt", true);
		defaultHalo = PrecacheModel("sprites/halo01.vmt", true);
	}
	else
	{
		defaultBeam = PrecacheModel("sprites/laserbeam.vmt", true);
		defaultHalo = PrecacheModel("sprites/glow01.vmt", true);
	}

	if(gCV_UseCustomSprite.BoolValue)
	{
		customBeam = PrecacheModel(gS_BeamSprite, true);
	}
	else
	{
		customBeam = defaultBeam;
	}

	gI_BeamSpriteIgnoreZ = PrecacheModel(gS_BeamSpriteIgnoreZ, true);

	for (int i = 0; i < ZONETYPES_SIZE; i++)
	{
		for (int j = 0; j < TRACKS_SIZE; j++)
		{

			if (gA_ZoneSettings[i][j].bUseVanillaSprite)
			{
				gA_ZoneSettings[i][j].iBeam = defaultBeam;
			}
			else
			{
				gA_ZoneSettings[i][j].iBeam = (gA_ZoneSettings[i][j].sBeam[0] != 0)
					? PrecacheModel(gA_ZoneSettings[i][j].sBeam, true)
					: customBeam;
			}

			gA_ZoneSettings[i][j].iHalo = (gA_ZoneSettings[i][j].bNoHalo) ? 0 : defaultHalo;
		}
	}
}

public void OnMapStart()
{
	GetLowercaseMapName(gS_Map);
	LoadZoneSettings();
	//UnloadZones();

	if (gEV_Type == Engine_TF2)
	{
		PrecacheModel("models/error.mdl");
	}
	else
	{
		PrecacheModel("models/props/cs_office/vending_machine.mdl");
	}
}

public void OnConfigsExecuted()
{
	if (gH_DrawAllZones == null)
	{
		gH_DrawVisible = CreateTimer(gCV_Interval.FloatValue, Timer_DrawZones, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		gH_DrawAllZones = CreateTimer(gCV_Interval.FloatValue, Timer_DrawZones, 1, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}

	RequestFrame(LoadZonesHere);
}

void LoadZonesHere()
{
	gB_YouCanLoadZonesNow = true;
	UnloadZones();
	Call_StartForward(gH_Forwards_LoadZonesHere);
	Call_Finish();
}

public void Shavit_LoadZonesHere()
{
	if (gCV_SQLZones.BoolValue && gH_SQL)
	{
		RefreshZones();
	}

	if (gCV_PrebuiltZones.BoolValue)
	{
		add_prebuilts_to_cache("trigger_multiple", false);
	}

	if (gCV_ClimbButtons.BoolValue)
	{
		add_prebuilts_to_cache("func_button", true);
		add_prebuilts_to_cache("func_rot_button", true);
	}
}

void add_prebuilts_to_cache(const char[] classname, bool button)
{
	char targetname[64];

	int ent = -1;
	while (-1 != (ent = FindEntityByClassname(ent, classname)))
	{
		GetEntPropString(ent, Prop_Data, "m_iName", targetname, sizeof(targetname));

		zone_cache_t cache;

		if (!Shavit_ParseZoneTargetname(targetname, button, cache.iType, cache.iTrack, cache.iData, gS_Map))
		{
			continue;
		}

		int hammerid = GetEntProp(ent, Prop_Data, "m_iHammerID");

		if (hammerid && IntToString(hammerid, cache.sTarget, sizeof(cache.sTarget)))
		{
			cache.iFlags |= ZF_Hammerid;
		}
		else
		{
			cache.sTarget = targetname;
		}

		PrintToServer(">>>> shavit-zones: Hooking '%s' '%s' (%d)", classname, targetname, hammerid);

		cache.iDatabaseID = -1;
		cache.iForm = button ? ZoneForm_func_button : ZoneForm_trigger_multiple;
		cache.sSource = button ? "autobutton" : "autozone";

		if (button)
		{
			Shavit_MarkKZMap(cache.iTrack);
		}
		else
		{
			float origin[3];
			GetEntPropVector(ent, Prop_Send, "m_vecOrigin", origin);
			GetEntPropVector(ent, Prop_Send, "m_vecMins", cache.fCorner1);
			GetEntPropVector(ent, Prop_Send, "m_vecMaxs", cache.fCorner2);

			//origin[2] -= (maxs[2] - 2.0); // so you don't get stuck in the ground
			origin[2] += 1.0; // so you don't get stuck in the ground
			AddVectors(origin, cache.fCorner1, cache.fCorner1);
			AddVectors(origin, cache.fCorner2, cache.fCorner2);
		}

		Shavit_AddZone(cache);
	}
}

public void OnGameFrame()
{
	bool search_trigger_multiple;
	bool search_trigger_teleport;
	bool search_func_button;

	for (int i = 0; i < gI_MapZones; i++)
	{
		if (gA_ZoneCache[i].iEntity > 0)
		{
			continue;
		}

		switch (gA_ZoneCache[i].iForm)
		{
			case ZoneForm_Box:
			{
				if (!CreateZoneTrigger(i))
				{
					return; // uhhhhhhhh
				}
			}
			case ZoneForm_trigger_multiple:
			{
				if (gA_ZoneCache[i].sTarget[0])
					search_trigger_multiple = true;
			}
			case ZoneForm_trigger_teleport:
			{
				if (gA_ZoneCache[i].sTarget[0])
					search_trigger_teleport = true;
			}
			case ZoneForm_func_button:
			{
				if (gA_ZoneCache[i].sTarget[0])
					search_func_button = true;
			}
		}
	}

	if (search_trigger_multiple)
	{
		FindEntitiesToHook("trigger_multiple", ZoneForm_trigger_multiple);
	}

	if (search_trigger_teleport)
	{
		FindEntitiesToHook("trigger_teleport", ZoneForm_trigger_teleport);
	}

	if (search_func_button)
	{
		FindEntitiesToHook("func_button", ZoneForm_func_button);
		FindEntitiesToHook("func_rot_button", ZoneForm_func_button);
	}
}

void EntOriginString(int ent, char[] sOrigin, bool short)
{
	float fOrigin[3];
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", fOrigin);
	FormatEx(sOrigin, 64, short ? "%.0f %.0f %.0f" : "%.9f %.9f %.9f", EXPAND_VECTOR(fOrigin));
}

void FindEntitiesToHook(const char[] classname, int form)
{
	char targetname[64];
	int ent = -1;

	while ((ent = FindEntityByClassname(ent, classname)) != -1)
	{
		if (gI_EntityZone[ent] > MaxClients)
		{
			continue;
		}

		GetEntPropString(ent, Prop_Data, form == ZoneForm_trigger_teleport ? "m_target" : "m_iName", targetname, sizeof(targetname));

		if (form == ZoneForm_trigger_multiple && StrContains(targetname, "shavit_zones_") == 0)
		{
			continue;
		}

		char hammerid[12];
		IntToString(GetEntProp(ent, Prop_Data, "m_iHammerID"), hammerid, sizeof(hammerid)); // xd string comparisons

		char sOrigin[64];
		EntOriginString(ent, sOrigin, false);

		for (int i = 0; i < gI_MapZones; i++)
		{
			if (gA_ZoneCache[i].iEntity > 0 || gA_ZoneCache[i].iForm != form
			||  !StrEqual(gA_ZoneCache[i].sTarget, (gA_ZoneCache[i].iFlags & ZF_Hammerid) ? hammerid :
			        ((gA_ZoneCache[i].iFlags & ZF_Origin) ? sOrigin : targetname))
			)
			{
				continue;
			}

			if (form == ZoneForm_func_button)
			{
				HookButton(i, ent);
			}
			else
			{
				HookZoneTrigger(i, ent);
			}
		}
	}
}

public void OnMapEnd()
{
	gB_YouCanLoadZonesNow = false;
	delete gH_DrawVisible;
	delete gH_DrawAllZones;
	UnloadZones();
}

public void OnClientPutInServer(int client)
{
	gI_LatestTeleportTick[client] = 0;

	if (!IsFakeClient(client) && gH_TeleportDhook != null)
	{
		gH_TeleportDhook.HookEntity(Hook_Pre, client, DHooks_OnTeleport);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// trigger_once | trigger_multiple.. etc
	if (StrContains(classname, "trigger_") != -1 || StrContains(classname, "player_speedmod") != -1)
	{
		SDKHook(entity, SDKHook_StartTouch, Hook_IgnoreTriggersWhileZoning);
		SDKHook(entity, SDKHook_EndTouch, Hook_IgnoreTriggersWhileZoning);
		SDKHook(entity, SDKHook_Touch, Hook_IgnoreTriggersWhileZoning);
	}
}

Action Hook_IgnoreTriggersWhileZoning(int entity, int other)
{
	if (1 <= other <= MaxClients && gI_MapStep[other] > 0 && gB_IgnoreTriggers[other])
	{
		if (Shavit_GetTimerStatus(other) != Timer_Running)
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public void OnEntityDestroyed(int entity)
{
	if (entity > MaxClients && entity < 2048 && gI_EntityZone[entity] > -1)
	{
		ClearZoneEntity(gI_EntityZone[entity], false);
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

void ClearZoneEntity(int index, bool unhook)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		gB_InsideZoneID[i][index] = false;
	}

	int entity = gA_ZoneCache[index].iEntity;

	gA_ZoneCache[index].iEntity = -1;

	if (entity > MaxClients)
	{
		gI_EntityZone[entity] = -1;

		if (unhook && IsValidEntity(entity))
		{
			UnhookZone(gA_ZoneCache[index]);
		}
	}
}

void UnhookZone(zone_cache_t cache)
{
	int entity = cache.iEntity;

	if (cache.iForm == ZoneForm_func_button)
	{
		SDKUnhook(entity, SDKHook_UsePost, UsePost_HookedButton);
	}
	else if (cache.iForm == ZoneForm_Box)
	{
		SDKUnhook(entity, SDKHook_StartTouchPost, StartTouchPost);
		SDKUnhook(entity, SDKHook_EndTouchPost, EndTouchPost);
		SDKUnhook(entity, SDKHook_TouchPost, TouchPost);

		if (cache.iType == Zone_Speedmod)
		{
			SDKUnhook(entity, SDKHook_StartTouch, SameTrack_StartTouch_er);
		}
	}
}

bool CreateZoneTrigger(int zone)
{
	bool speedmod = (gA_ZoneCache[zone].iType == Zone_Speedmod);
	char classname[32]; classname = speedmod ? "player_speedmod" : "trigger_multiple";
	int entity = CreateEntityByName(classname);

	if (entity == -1)
	{
		LogError("\"%s\" creation failed, map %s.", classname, gS_Map);
		return false;
	}

	if (!speedmod)
	{
		DispatchKeyValue(entity, "wait", "0"); // useless??? set to 0.0001 or something? ::Spawn() m_flWait 0 turns into 0.2 which then isn't even used anyway because eventqueuefix sets nextthinktick now???
		DispatchKeyValue(entity, "spawnflags", "4097"); // 1|4096 = allow clients|disallow bots
	}

	if (!DispatchSpawn(entity))
	{
		AcceptEntityInput(entity, "Kill");
		LogError("\"%s\" spawning failed, map %s.", classname, gS_Map);
		return false;
	}

	gA_ZoneCache[zone].iEntity = entity;

	ActivateEntity(entity);
	SetEntityModel(entity, (gEV_Type == Engine_TF2) ? "models/error.mdl" : "models/props/cs_office/vending_machine.mdl");
	SetEntProp(entity, Prop_Send, "m_fEffects", EF_NODRAW);
	SetEntProp(entity, Prop_Send, "m_nSolidType", SOLID_BBOX);

	if (speedmod)
	{
		SetEntProp(entity, Prop_Send, "m_usSolidFlags", FSOLID_TRIGGER|FSOLID_NOT_SOLID);
	}

	if (gA_ZoneCache[zone].iFlags & ZF_Solid)
	{
		SetEntProp(entity, Prop_Send, "m_usSolidFlags",
			GetEntProp(entity, Prop_Send, "m_usSolidFlags") & ~(FSOLID_TRIGGER|FSOLID_NOT_SOLID));

		EntityCollisionRulesChanged(entity);
	}

	TeleportEntity(entity, gV_ZoneCenter[zone], NULL_VECTOR, NULL_VECTOR);

	SetZoneMinsMaxs(zone);
	HookZoneTrigger(zone, entity);

	char sTargetname[64];
	FormatEx(sTargetname, sizeof(sTargetname), "shavit_zones_%d_%d", gA_ZoneCache[zone].iTrack, gA_ZoneCache[zone].iType);

	if (gA_ZoneCache[zone].iType == Zone_Stage)
	{
		Format(sTargetname, sizeof(sTargetname), "%s_stage%d", sTargetname, gA_ZoneCache[zone].iData);
	}

	DispatchKeyValue(entity, "targetname", sTargetname);

	return true;
}

void HookButton(int zone, int entity)
{
	Shavit_MarkKZMap(gA_ZoneCache[zone].iTrack);
	SDKHook(entity, SDKHook_UsePost, UsePost_HookedButton);

	gI_EntityZone[entity] = zone;
	gA_ZoneCache[zone].iEntity = entity;
}

void HookZoneTrigger(int zone, int entity)
{
	SDKHook(entity, SDKHook_StartTouchPost, StartTouchPost);
	SDKHook(entity, SDKHook_EndTouchPost, EndTouchPost);
	SDKHook(entity, SDKHook_TouchPost, TouchPost);

	if (gA_ZoneCache[zone].iType == Zone_Speedmod)
	{
		SDKHook(entity, SDKHook_StartTouch, SameTrack_StartTouch_er);
	}

	gI_EntityZone[entity] = zone;
	gA_ZoneCache[zone].iEntity = entity;
}

void UnloadZones()
{
	for (int i = 0; i < gI_MapZones; i++)
	{
		int ent = gA_ZoneCache[i].iEntity;
		ClearZoneEntity(i, true);

		if (ent && gA_ZoneCache[i].iForm == ZoneForm_Box) // created by shavit-zones
		{
			AcceptEntityInput(ent, "Kill");
		}

		zone_cache_t empty_cache;
		gA_ZoneCache[i] = empty_cache;
	}

	gI_MapZones = 0;

	int empty_tracks[TRACKS_SIZE];
	bool empty_InsideZoneID[MAX_ZONES];

	for (int i = 1; i <= MaxClients; i++)
	{
		gI_InsideZone[i] = empty_tracks;
		gB_InsideZoneID[i] = empty_InsideZoneID;
	}

	gI_HighestStage = empty_tracks;

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		gF_CustomSpawn[i] = ZERO_VECTOR;
	}
}

void RecalcInsideZoneAll()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		RecalcInsideZone(i);
	}
}

void RecalcInsideZone(int client)
{
	int empty_array[TRACKS_SIZE];
	gI_InsideZone[client] = empty_array;

	for (int i = 0; i < gI_MapZones; i++)
	{
		if (gB_InsideZoneID[client][i])
		{
			int track = gA_ZoneCache[i].iTrack;
			int type = gA_ZoneCache[i].iType;
			gI_InsideZone[client][track] |= (1 << type);
		}
	}
}

void RecalcHighestStage()
{
	int empty_tracks[TRACKS_SIZE];
	gI_HighestStage = empty_tracks;

	for (int i = 0; i < gI_MapZones; i++)
	{
		int type = gA_ZoneCache[i].iType;
		if (type != Zone_Stage) continue;

		int track = gA_ZoneCache[i].iTrack;
		int stagenum = gA_ZoneCache[i].iData;

		if (stagenum > gI_HighestStage[track])
			gI_HighestStage[track] = stagenum;
	}
}

void RefreshZones()
{
	char sQuery[512];
	FormatEx(sQuery, 512,
		"SELECT type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, destination_x, destination_y, destination_z, track, %s, flags, data, form, target FROM %smapzones WHERE map = '%s';",
		(gI_Driver != Driver_sqlite)? "id":"rowid", gS_MySQLPrefix, gS_Map);

	QueryLog(gH_SQL, SQL_RefreshZones_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_RefreshZones_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zone refresh) SQL query failed. Reason: %s", error);
		return;
	}

	while(results.FetchRow())
	{
		int type = results.FetchInt(0);
		int track = results.FetchInt(10);

		float destination[3];
		destination[0] = results.FetchFloat(7);
		destination[1] = results.FetchFloat(8);
		destination[2] = results.FetchFloat(9);

		if (type == Zone_CustomSpawn)
		{
			gF_CustomSpawn[track] = destination;
			continue;
		}

		zone_cache_t cache;
		cache.iEntity = -1;
		cache.iType = type;
		cache.fCorner1[0] = results.FetchFloat(1);
		cache.fCorner1[1] = results.FetchFloat(2);
		cache.fCorner1[2] = results.FetchFloat(3);
		cache.fCorner2[0] = results.FetchFloat(4);
		cache.fCorner2[1] = results.FetchFloat(5);
		cache.fCorner2[2] = results.FetchFloat(6);
		cache.fDestination = destination;
		cache.iTrack = track;
		cache.iDatabaseID = results.FetchInt(11);
		cache.iFlags = results.FetchInt(12);
		cache.iData = results.FetchInt(13);
		cache.iForm = results.FetchInt(14);
		results.FetchString(15, cache.sTarget, sizeof(cache.sTarget));
		cache.sSource = "sql";

		if (cache.iForm == ZoneForm_Box)
		{
			//
		}
		else if (cache.iForm == ZoneForm_trigger_multiple)
		{
			if (!cache.sTarget[0])
			{
				// ~~Migrate previous `prebuilt`-column-having zones~~ nevermind... TODO
				continue;
			}
		}

		Shavit_AddZone(cache);
	}

#if 0
	if (!gB_InsertedPrebuiltZones)
	{
		gB_InsertedPrebuiltZones = true;

		char sQuery[1024];
		Transaction trans;

		for (int i = 0; i < gI_MapZones; i++)
		{
			if (gA_ZoneCache[i].bPrebuilt)
			{
				if (trans == null)
				{
					trans = new Transaction();
				}

				InsertPrebuiltZone(i, false, sQuery, sizeof(sQuery));
				AddQueryLog(hTransaction, sQuery);
			}
		}

		if (trans != null)
		{
			gH_SQL.Execute(trans);
		}
	}
#endif
}

public void OnClientConnected(int client)
{
	int empty_InsideZone[TRACKS_SIZE];

	for (int i = 0; i < ZONETYPES_SIZE; i++)
	{
		gI_InsideZone[client] = empty_InsideZone;

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gI_ZoneDisplayType[client][i][j] = ZoneDisplay_Default;
			gI_ZoneColor[client][i][j] = ZoneColor_Default;
			gI_ZoneWidth[client][i][j] = ZoneWidth_Default;
		}
	}

	bool empty_InsideZoneID[MAX_ZONES];
	gB_InsideZoneID[client] = empty_InsideZoneID;

	for (int i = 0; i < TRACKS_SIZE; i++)
	{
		gF_ClimbButtonCache[client][i][0] = ZERO_VECTOR;
		gF_ClimbButtonCache[client][i][1] = ZERO_VECTOR;
	}

	bool empty_HasSetStart[TRACKS_SIZE];
	gB_HasSetStart[client] = empty_HasSetStart;

	Reset(client);

	gF_Modifier[client] = 16.0;
	gI_AdjustAxis[client] = 0;
	gI_GridSnap[client] = 16;
	gB_SnapToWall[client] = false;
	gB_CursorTracing[client] = true;
	gB_IgnoreTriggers[client] = true;
	gB_DrawAllZones[client] = false;
}

public void OnClientAuthorized(int client)
{
	if (gH_SQL && !IsFakeClient(client))
	{
		GetStartPosition(client);
	}
}

public void OnClientCookiesCached(int client)
{
	if (IsFakeClient(client))
	{
		return;
	}

	char setting[8];
	gH_DrawAllZonesCookie.Get(client, setting, sizeof(setting));
	gB_DrawAllZones[client] = view_as<bool>(StringToInt(setting));

	// we have to go through some pain because cookies can only fit into a char[100] buffer...
	char czone[200];
	gH_CustomZoneCookie.Get(client, czone, 100);
	gH_CustomZoneCookie2.Get(client, czone[99], 100);

	char ver = czone[0];

	if (ver == 'a' || ver == 'b') // "version number"
	{
		// a = [1 + 2*2*TRACKS_SIZE + 1]; // version + ((start + end) * 2 chars * tracks) + NUL terminator
		// b = [1 + ZONETYPES_SIZE*2*2 + 1] // version + (ZONETYPES_SIZE * 2 chars * (main+bonus)) + NUL terminator

		int p = 1;
		char c;

		while ((c = czone[p++]) != 0)
		{
			int track = c & 0xf;
#if CZONE_VER != 'a'
			if (track > Track_Bonus)
			{
				++p;
				continue;
			}
#endif
			int type = (c >> 4) & 1;
			gI_ZoneDisplayType[client][type][track] = (c >> 5) & 3;
			c = czone[p++];
			gI_ZoneColor[client][type][track] = c & 0xf;
			gI_ZoneWidth[client][type][track] = (c >> 4) & 7;
		}
	}
	else if (ver == 'c') // back to the original :pensive:
	{
		// c = [1 + ZONETYPES_SIZE*2*3 + 1] // version = (ZONETYPES_SIZE * (main+bonus) * 3 chars) + NUL terminator
		// char[109] as of right now....

		int p = 1;

		for (int type = Zone_Start; type < ZONETYPES_SIZE; type++)
		{
			for (int track = Track_Main; track <= Track_Bonus; track++)
			{
				gI_ZoneDisplayType[client][type][track] = czone[p++] - '0';
				gI_ZoneColor[client][type][track] = czone[p++] - '0';
				gI_ZoneWidth[client][type][track] = czone[p++] - '0';
			}
		}
	}
}

void GetStartPosition(int client)
{
	int steamID = GetSteamAccountID(client);

	if(steamID == 0 || client == 0)
	{
		return;
	}

	char query[512];

	FormatEx(query, 512,
		"SELECT track, pos_x, pos_y, pos_z, ang_x, ang_y, ang_z, angles_only FROM %sstartpositions WHERE auth = %d AND map = '%s'",
		gS_MySQLPrefix, steamID, gS_Map);

	QueryLog(gH_SQL, SQL_GetStartPosition_Callback, query, GetClientSerial(client));
}

public void SQL_GetStartPosition_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (get start position) SQL query failed. Reason: %s", error);
		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	while(results.FetchRow())
	{
		int track = results.FetchInt(0);

		gF_StartPos[client][track][0] = results.FetchFloat(1);
		gF_StartPos[client][track][1] = results.FetchFloat(2);
		gF_StartPos[client][track][2] = results.FetchFloat(3);

		gF_StartAng[client][track][0] = results.FetchFloat(4);
		gF_StartAng[client][track][1] = results.FetchFloat(5);
		gF_StartAng[client][track][2] = results.FetchFloat(6);

		gB_StartAnglesOnly[client][track] = results.FetchInt(7) > 0;
		gB_HasSetStart[client][track] = true;
	}
}

public Action Command_SetStart(int client, int args)
{
	if(!IsValidClient(client, true))
	{
		Shavit_PrintToChat(client, "%T", "SetStartCommandAlive", client, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	int track = Shavit_GetClientTrack(client);

	Shavit_PrintToChat(client, "%T", "SetStart", client, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);

	SetStart(client, track, GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") == -1);

	return Plugin_Handled;
}

void SetStart(int client, int track, bool anglesonly)
{
	gB_HasSetStart[client][track] = true;
	gB_StartAnglesOnly[client][track] = anglesonly;

	if (anglesonly)
	{
		gF_StartPos[client][track] = ZERO_VECTOR;
	}
	else
	{
		GetClientAbsOrigin(client, gF_StartPos[client][track]);
	}

	GetClientEyeAngles(client, gF_StartAng[client][track]);

	char query[1024];

	FormatEx(query, sizeof(query),
		"REPLACE INTO %sstartpositions (auth, track, map, pos_x, pos_y, pos_z, ang_x, ang_y, ang_z, angles_only) VALUES (%d, %d, '%s', %.03f, %.03f, %.03f, %.03f, %.03f, %.03f, %d);",
		gS_MySQLPrefix, GetSteamAccountID(client), track, gS_Map,
		gF_StartPos[client][track][0], gF_StartPos[client][track][1], gF_StartPos[client][track][2],
		gF_StartAng[client][track][0], gF_StartAng[client][track][1], gF_StartAng[client][track][2], anglesonly);

	QueryLog(gH_SQL, SQL_InsertStartPosition_Callback, query);
}

public void SQL_InsertStartPosition_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if(!db || !results || error[0])
	{
		LogError("Timer (zones) InsertStartPosition_Callback SQL query failed! (%s)", error);

		return;
	}
}

public Action Command_DeleteSetStart(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_DeleteSetStart);
	menu.SetTitle("%T\n ", "DeleteSetStartMenuTitle", client);

	for (int i = 0; i < TRACKS_SIZE; i++)
	{
		if (gB_HasSetStart[client][i])
		{
			char info[8], sTrack[32];
			IntToString(i, info, sizeof(info));
			GetTrackName(client, i, sTrack, sizeof(sTrack));
			menu.AddItem(info, sTrack);
		}
	}

	if (!menu.ItemCount)
	{
		delete menu;
		return Plugin_Handled;
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int MenuHandler_DeleteSetStart(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, sizeof(info));
		int track = StringToInt(info);
		Shavit_PrintToChat(param1, "%T", "DeleteSetStart", param1, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		DeleteSetStart(param1, track);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void DeleteSetStart(int client, int track)
{
	gB_HasSetStart[client][track] = false;
	gF_StartPos[client][track] = ZERO_VECTOR;
	gF_StartAng[client][track] = ZERO_VECTOR;

	char query[512];

	FormatEx(query, 512,
		"DELETE FROM %sstartpositions WHERE auth = %d AND track = %d AND map = '%s';",
		gS_MySQLPrefix, GetSteamAccountID(client), track, gS_Map);

	QueryLog(gH_SQL, SQL_DeleteSetStart_Callback, query);
}

public void SQL_DeleteSetStart_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if(!db || !results || error[0])
	{
		LogError("SQL_DeleteSetStart_Callback - Query failed! (%s)", error);

		return;
	}
}

public Action Command_Modifier(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(args == 0)
	{
		Shavit_PrintToChat(client, "%T", "ModifierCommandNoArgs", client);

		return Plugin_Handled;
	}

	char sArg1[16];
	GetCmdArg(1, sArg1, 16);

	float fArg1 = StringToFloat(sArg1);

	if(fArg1 <= 0.0)
	{
		Shavit_PrintToChat(client, "%T", "ModifierTooLow", client);

		return Plugin_Handled;
	}

	gF_Modifier[client] = fArg1;

	Shavit_PrintToChat(client, "%T %s%.01f%s.", "ModifierSet", client, gS_ChatStrings.sVariable, fArg1, gS_ChatStrings.sText);

	return Plugin_Handled;
}

bool CanDrawAllZones(int client)
{
	if (!gCV_AllowDrawAllZones.BoolValue)
	{
		return false;
	}

	return gCV_AllowDrawAllZones.IntValue == 2 || CheckCommandAccess(client, "sm_zones", ADMFLAG_RCON);
}

public Action Command_DrawAllZones(int client, int args)
{
	if (CanDrawAllZones(client))
	{
		gB_DrawAllZones[client] = !gB_DrawAllZones[client];
		gH_DrawAllZonesCookie.Set(client, gB_DrawAllZones[client] ? "1" : "0");
	}

	return Plugin_Handled;
}

public Action Command_AddSpawn(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

#if 0
	if (!gCV_SQLZones.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "ZonesNotSQL", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return Plugin_Handled;
	}
#endif

	return DisplayCustomSpawnMenu(client);
}

Action DisplayCustomSpawnMenu(int client)
{
	Menu menu = new Menu(MenuHandler_AddCustomSpawn);
	menu.SetTitle("%T\n ", "ZoneCustomSpawnMenuTitle", client);

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		char sTrack[32];
		GetTrackName(client, i, sTrack, 32);

		menu.AddItem(sInfo, sTrack);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_AddCustomSpawn(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!IsPlayerAlive(param1))
		{
			Shavit_PrintToChat(param1, "%T", "ZoneDead", param1);

			return 0;
		}

		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		int iTrack = StringToInt(sInfo);

		if(!EmptyVector(gF_CustomSpawn[iTrack]))
		{
			char sTrack[32];
			GetTrackName(param1, iTrack, sTrack, 32);

			Shavit_PrintToChat(param1, "%T", "ZoneCustomSpawnExists", param1, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);

			return 0;
		}

		zone_cache_t cache;
		cache.iType = Zone_CustomSpawn;
		cache.iTrack = iTrack;
		cache.iDatabaseID = -1;
		GetClientAbsOrigin(param1, cache.fDestination);
		gF_CustomSpawn[iTrack] = cache.fDestination;

		for (int i = 0; i < gI_MapZones; i++)
		{
			if (gA_ZoneCache[i].iType == Zone_CustomSpawn && gA_ZoneCache[i].iTrack == iTrack && StrEqual(gA_ZoneCache[i].sSource, "sql"))
			{
				cache.iDatabaseID = gA_ZoneCache[i].iDatabaseID;
				break;
			}
		}

		gA_EditCache[param1] = cache;

		InsertZone(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_DelSpawn(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	return DisplayCustomSpawnDeleteMenu(client);
}

Action DisplayCustomSpawnDeleteMenu(int client)
{
	Menu menu = new Menu(MenuHandler_DeleteCustomSpawn);
	menu.SetTitle("%T\n ", "ZoneCustomSpawnMenuDeleteTitle", client);

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		char sTrack[32];
		GetTrackName(client, i, sTrack, 32);

		menu.AddItem(sInfo, sTrack, (EmptyVector(gF_CustomSpawn[i]))? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_DeleteCustomSpawn(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		int iTrack = StringToInt(sInfo);

		if(EmptyVector(gF_CustomSpawn[iTrack]))
		{
			char sTrack[32];
			GetTrackName(param1, iTrack, sTrack, 32);

			Shavit_PrintToChat(param1, "%T", "ZoneCustomSpawnMissing", param1, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);

			return 0;
		}

		gF_CustomSpawn[iTrack] = ZERO_VECTOR;
		Shavit_LogMessage("%L - deleted custom spawn from map `%s`.", param1, gS_Map);

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery),
			"DELETE FROM %smapzones WHERE type = %d AND map = '%s' AND track = %d;",
			gS_MySQLPrefix, Zone_CustomSpawn, gS_Map, iTrack);

		QueryLog(gH_SQL, SQL_DeleteCustom_Spawn_Callback, sQuery, GetClientSerial(param1));
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void SQL_DeleteCustom_Spawn_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (custom spawn delete) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	Shavit_PrintToChat(client, "%T", "ZoneCustomSpawnDelete", client);
}

public Action Command_TpToZone(int client, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	return OpenTpToZoneMenu(client);
}

public Action Command_ZoneEdit(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

#if 0
	if (!gCV_SQLZones.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "ZonesNotSQL", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return Plugin_Handled;
	}
#endif

	Reset(client);

	return OpenEditMenu(client);
}

public Action Command_HookZone(int client, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}

#if 0
	if (!gCV_SQLZones.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "ZonesNotSQL", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return Plugin_Handled;
	}
#endif

	OpenHookMenu_Form(client);
	return Plugin_Handled;
}

public Action Command_ReloadZoneSettings(int client, int args)
{
	LoadZoneSettings();

	ReplyToCommand(client, "Reloaded zone settings.");

	return Plugin_Handled;
}

// Was originally used in beamer to replicate this gmod lua code:
/*
My code from tracegun.lua that I based this off of:
	local ang = tr.Normal:Angle() // calculate in SP with: ( traceRes.HitPos - traceRes.StartPos ):Normalize()
	ang:RotateAroundAxis(tr.HitNormal, 180)
	local dir = ang:Forward()*-1
	tr = util.TraceLine({start=tr.HitPos, endpos=tr.HitPos+(dir*100000), filter=players})
*/
stock void RotateAroundAxis(float v[3], const float in_k[3], float theta)
{
	// https://en.wikipedia.org/wiki/Rodrigues%27_rotation_formula#Statement
	// vrot = (v * cos(theta)) + ((k x v) * sin(theta)) + (k * (k . v) * (1 - cos(theta)))

	float k[3];
	k[0] = DegToRad(in_k[1]); k[1] = DegToRad(in_k[2]); k[2] = DegToRad(in_k[0]); // right-hand rule related ordering?
	NormalizeVector(k, k);

	theta = DegToRad(theta);
	float theta_cos = Cosine(theta);
	float theta_sin = Sine(theta);
	float one_minus_theta_cos = 1.0 - theta_cos;
	float kv_dot = GetVectorDotProduct(k, v);

	float kv_cross[3];
	GetVectorCrossProduct(k, v, kv_cross);

	for (int i = 0; i < 3; i++)
	{
		v[i] = (v[i] * theta_cos)
		     + (kv_cross[i] * theta_sin)
		     + (k[i] * kv_dot * one_minus_theta_cos);
	}
}

stock void ReflectAngles(float direction[3], const float normal[3])
{
	float fwd[3], reflected[3];

	GetAngleVectors(direction, fwd, NULL_VECTOR, NULL_VECTOR);

	float dot = GetVectorDotProduct(fwd, normal);

	for (int i = 0; i < 3; i++)
	{
		reflected[i] = fwd[i] - 2.0 * dot * normal[i];
	}

	NormalizeVector(reflected, reflected);
	GetVectorAngles(reflected, direction);
}

public Action Command_Beamer(int client, int args)
{
	static float rate_limit[MAXPLAYERS+1];
	float now = GetEngineTime();

	if (rate_limit[client] > now)
		return Plugin_Handled;

	rate_limit[client] = now + 0.2;

	float startpos[3], endpos[3], direction[3];
	GetClientEyePosition(client, startpos);
	startpos[2] -= 3.0;
	GetClientEyeAngles(client, direction);

	float delay = 0.0;

	for (int C = 20; C >= 0; --C)
	{
		TR_TraceRayFilter(startpos, direction, MASK_ALL, RayType_Infinite, TRFilter_NoPlayers, client);
		TR_GetEndPosition(endpos);

		TE_SetupBeamPoints(
			startpos,
			endpos,
			gI_BeamSpriteIgnoreZ,
			gA_ZoneSettings[Zone_Start][Track_Main].iHalo,
			0,    // StartFrame
			0,    // FrameRate
			10.0, // Life
			1.0,  // Width
			1.0,  // EndWidth
			0,    // FadeLength
			0.0,  // Amplitude
			{255, 255, 0, 192}, // Colour
			20    // Speed
		);

		TE_SendToClient(client, delay);
		delay += 0.11;

		if (!C) break;

		startpos = endpos;

		float hitnormal[3];
		TR_GetPlaneNormal(INVALID_HANDLE, hitnormal);

		ReflectAngles(direction, hitnormal);
	}

	return Plugin_Handled;
}

public Action Command_Stages(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "StageCommandAlive", client, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	int iStage = -1;
	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	if ('0' <= sCommand[4] <= '9')
	{
		iStage = sCommand[4] - '0';
	}
	else if (args > 0)
	{
		char arg1[8];
		GetCmdArg(1, arg1, 8);
		iStage = StringToInt(arg1);
	}

	if (iStage > -1)
	{
		for(int i = 0; i < gI_MapZones; i++)
		{
			if (gA_ZoneCache[i].iType == Zone_Stage && gA_ZoneCache[i].iData == iStage)
			{
				Shavit_StopTimer(client);

				if (!EmptyVector(gA_ZoneCache[i].fDestination))
				{
					TeleportEntity(client, gA_ZoneCache[i].fDestination, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
				}
				else
				{
					TeleportEntity(client, gV_ZoneCenter[i], NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
				}
			}
		}
	}
	else
	{
		Menu menu = new Menu(MenuHandler_SelectStage);
		menu.SetTitle("%T", "ZoneMenuStage", client);

		char sDisplay[64];

		for(int i = 0; i < gI_MapZones; i++)
		{
			if (gA_ZoneCache[i].iType == Zone_Stage)
			{
				char sTrack[32];
				GetTrackName(client, gA_ZoneCache[i].iTrack, sTrack, 32);

				FormatEx(sDisplay, 64, "#%d - %T (%s)", (i + 1), "ZoneSetStage", client, gA_ZoneCache[i].iData, sTrack);

				char sInfo[8];
				IntToString(i, sInfo, 8);

				menu.AddItem(sInfo, sDisplay);
			}
		}

		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}

	return Plugin_Handled;
}

public Action Command_StageRestart(int client, int args)
{
	// This command should only work on surf maps for now
	// There are quite a few bhop maps that have checkpoint triggers and this command would ruin those maps
	// Ideally there would be a zone-based solution to this problem
	if(!IsValidClient(client) || strncmp(gS_Map, "surf_", 5))
	{
		return Plugin_Handled;
	}

	if (!gCV_EnableStageRestart.BoolValue)
	{
		Shavit_PrintToChat(client, "!stagerestart is disabled!"); // untranslated strings in 2024...
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "StageCommandAlive", client);
		return Plugin_Handled;
	}

	int last = gI_LastStage[client];
	int track = Shavit_GetClientTrack(client);

	// crude way to prevent cheesing
	if (InsideZone(client, Zone_Stage, track) || InsideZone(client, Zone_Start, -1))
	{
		return Plugin_Handled;
	}

	if (last <= 0 || Shavit_GetTimerStatus(client) == Timer_Stopped || InsideZone(client, Zone_End, track))
	{
		Shavit_RestartTimer(client, track);
	}
	else
	{
		for(int i = 0; i < gI_MapZones; i++)
		{
			if (gA_ZoneCache[i].iType == Zone_Stage && gA_ZoneCache[i].iData == last && gA_ZoneCache[i].iTrack == track)
			{
				if (!EmptyVector(gA_ZoneCache[i].fDestination))
				{
					TeleportEntity(client, gA_ZoneCache[i].fDestination, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
				}
				else
				{
					TeleportEntity(client, gV_ZoneCenter[i], NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
				}
			}
		}
	}

	return Plugin_Handled;
}


public int MenuHandler_SelectStage(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		int iIndex = StringToInt(sInfo);

		Shavit_StopTimer(param1);

		if (!EmptyVector(gA_ZoneCache[iIndex].fDestination))
		{
			TeleportEntity(param1, gA_ZoneCache[iIndex].fDestination, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}
		else
		{
			TeleportEntity(param1, gV_ZoneCenter[iIndex], NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Zones(int client, int args)
{
	if (!gH_SQL)
	{
		Shavit_PrintToChat(client, "Database not loaded. Check your error logs.");
		return Plugin_Handled;
	}

	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "ZonesCommand", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return Plugin_Handled;
	}

#if 0
	if (!gCV_SQLZones.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "ZonesNotSQL", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return Plugin_Handled;
	}
#endif

	Reset(client);

	Menu menu = new Menu(MenuHandler_SelectZoneTrack);
	menu.SetTitle("%T", "ZoneMenuTrack", client);

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		char sDisplay[16];
		GetTrackName(client, i, sDisplay, 16);

		menu.AddItem(sInfo, sDisplay);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_SelectZoneTrack(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		gA_EditCache[param1].iTrack = StringToInt(sInfo);

		char sTrack[16];
		GetTrackName(param1, gA_EditCache[param1].iTrack, sTrack, 16);

		Menu submenu = new Menu(MenuHandler_SelectZoneType);
		submenu.SetTitle("%T\n ", "ZoneMenuTitle", param1, sTrack);

		char sZoneName[32];

		for(int i = 0; i < ZONETYPES_SIZE; i++)
		{
			if(i == Zone_CustomSpawn)
			{
				continue;
			}

			GetZoneName(param1, i, sZoneName, sizeof(sZoneName));

			IntToString(i, sInfo, 8);
			submenu.AddItem(sInfo, sZoneName);
		}

		submenu.ExitButton = true;
		submenu.Display(param1, MENU_TIME_FOREVER);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		gH_AdminMenu.DisplayCategory(gH_TimerCommands, param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

Action OpenTpToZoneMenu(int client, int pagepos=0)
{
	Menu menu = new Menu(MenuHandler_TpToEdit);
	menu.SetTitle("%T\n ", "TpToZone", client);

	int newPageInterval = (gEV_Type == Engine_CSGO) ? 6 : 7;
	char sDisplay[128];
	FormatEx(sDisplay, sizeof(sDisplay), "%T", "ZoneEditRefresh", client);
	menu.AddItem("-2", sDisplay);

	for (int i = 0; i < gI_MapZones; i++)
	{
		if ((menu.ItemCount % newPageInterval) == 0)
		{
			FormatEx(sDisplay, sizeof(sDisplay), "%T", "ZoneEditRefresh", client);
			menu.AddItem("-2", sDisplay);
		}

		char sInfo[8];
		IntToString(i, sInfo, 8);

		char sTarget[64];

		switch (gA_ZoneCache[i].iForm)
		{
			case ZoneForm_func_button, ZoneForm_trigger_multiple, ZoneForm_trigger_teleport:
			{
				FormatEx(sTarget, sizeof(sTarget), " (%s)", gA_ZoneCache[i].sTarget);
			}
		}

		char sTrack[32];
		GetTrackName(client, gA_ZoneCache[i].iTrack, sTrack, 32);

		char sZoneName[32];
		GetZoneName(client, gA_ZoneCache[i].iType, sZoneName, sizeof(sZoneName));

		if (gA_ZoneCache[i].iType == Zone_CustomSpeedLimit || gA_ZoneCache[i].iType == Zone_Stage || gA_ZoneCache[i].iType == Zone_Airaccelerate)
		{
			FormatEx(sDisplay, sizeof(sDisplay), "#%d - %s %d (%s)%s", (i + 1), sZoneName, gA_ZoneCache[i].iData, sTrack, sTarget);
		}
		else if (gA_ZoneCache[i].iType == Zone_Gravity || gA_ZoneCache[i].iType == Zone_Speedmod)
		{
			FormatEx(sDisplay, 64, "#%d - %s %.2f (%s)", (i + 1), sZoneName, gA_ZoneCache[i].iData, sTrack);
		}
		else
		{
			FormatEx(sDisplay, sizeof(sDisplay), "#%d - %s (%s)%s", (i + 1), sZoneName, sTrack, sTarget);
		}

		if (gB_InsideZoneID[client][i])
		{
			Format(sDisplay, sizeof(sDisplay), "%s %T", sDisplay, "ZoneInside", client);
		}

		menu.AddItem(sInfo, sDisplay, ITEMDRAW_DEFAULT);
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, pagepos, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_TpToEdit(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, 8);

		int id = StringToInt(info);

		switch (id)
		{
			case -2:
			{
			}
			case -1:
			{
				Shavit_PrintToChat(param1, "%T", "ZonesMenuNoneFound", param1);
			}
			default:
			{
				Shavit_StopTimer(param1);

				float fCenter[3];
				fCenter[0] = gV_ZoneCenter[id][0];
				fCenter[1] = gV_ZoneCenter[id][1];
				fCenter[2] = gA_ZoneCache[id].fCorner1[2];

				TeleportEntity(param1, fCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
			}
		}

		OpenTpToZoneMenu(param1, GetMenuSelectionPosition());
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		gH_AdminMenu.DisplayCategory(gH_TimerCommands, param1);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_HookZone_Editor(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(param2, info, sizeof(info));

		if (StrEqual(info, "tpto"))
		{
			Shavit_StopTimer(param1);
			float center[3];
			center[0] = (gA_EditCache[param1].fCorner1[0] + gA_EditCache[param1].fCorner2[0]) * 0.5;
			center[1] = (gA_EditCache[param1].fCorner1[1] + gA_EditCache[param1].fCorner2[1]) * 0.5;
			center[2] = gA_EditCache[param1].fCorner1[2] + 1.0;
			TeleportEntity(param1, center, NULL_VECTOR, ZERO_VECTOR);
		}
		else if (StrEqual(info, "track"))
		{
			if ((gA_EditCache[param1].iTrack += 1) > Track_Bonus_Last)
				gA_EditCache[param1].iTrack = 0;
		}
		else if (StrEqual(info, "ztype"))
		{
			static int allowed_types[] = {
				// ZoneForm_Box (unused)
				0
				// ZoneForm_trigger_multiple
				, (1 << Zone_Start)
				| (1 << Zone_End)
				| (1 << Zone_Respawn)
				| (1 << Zone_Stop)
				| (1 << Zone_Slay)
				| (1 << Zone_Freestyle)
				| (1 << Zone_CustomSpeedLimit)
				| (1 << Zone_Teleport)
				| (1 << Zone_Easybhop)
				| (1 << Zone_Slide)
				| (1 << Zone_Airaccelerate)
				| (1 << Zone_Stage)
				| (1 << Zone_NoTimerGravity)
				| (1 << Zone_Gravity)
				| (1 << Zone_Speedmod)
				| (1 << Zone_NoJump)
				| (1 << Zone_Autobhop)
				// ZoneForm_trigger_teleport
				, (1 << Zone_End)
				| (1 << Zone_Respawn)
				| (1 << Zone_Stop)
				| (1 << Zone_Slay)
				| (1 << Zone_Freestyle)
				| (1 << Zone_CustomSpeedLimit)
				| (1 << Zone_Stage)
				| (1 << Zone_NoTimerGravity)
				// ZoneForm_func_button
				, (1 << Zone_Start)
				| (1 << Zone_End)
				| (1 << Zone_Stop)
				| (1 << Zone_Slay)
				| (1 << Zone_Stage)
			};

			int form = gA_EditCache[param1].iForm;

			for (int i = 0; i < 100; i++) // no infinite loops = good :)
			{
				if (++gA_EditCache[param1].iType >= ZONETYPES_SIZE)
					gA_EditCache[param1].iType = 0;
				if (allowed_types[form] & (1 << gA_EditCache[param1].iType))
					break;
			}
		}
		else if (StrEqual(info, "htype"))
		{
			if (gA_EditCache[param1].iFlags == -1)
				gA_EditCache[param1].iFlags = 0;
			else if (gA_EditCache[param1].iFlags & ZF_Origin)
				gA_EditCache[param1].iFlags &= ~ZF_Origin;
			else if (gA_EditCache[param1].iFlags & ZF_Hammerid)
				gA_EditCache[param1].iFlags ^= ZF_Hammerid|ZF_Origin;
			else
				gA_EditCache[param1].iFlags |= ZF_Hammerid;
		}
		else if (StrEqual(info, "hook"))
		{
			if (gA_EditCache[param1].iFlags & ZF_Hammerid)
				IntToString(GetEntProp(gA_EditCache[param1].iEntity, Prop_Data, "m_iHammerID"), gA_EditCache[param1].sTarget, sizeof(gA_EditCache[].sTarget));
			else if (gA_EditCache[param1].iFlags & ZF_Origin)
				EntOriginString(gA_EditCache[param1].iEntity, gA_EditCache[param1].sTarget, false);
			else
				GetEntPropString(gA_EditCache[param1].iEntity, Prop_Data, gA_EditCache[param1].iForm == ZoneForm_trigger_teleport ? "m_target" : "m_iName", gA_EditCache[param1].sTarget, sizeof(gA_EditCache[].sTarget));

			CreateEditMenu(param1, true);
			return 0;
		}

		OpenHookMenu_Editor(param1);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenHookMenu_List(param1, gA_EditCache[param1].iForm, gI_HookListPos[param1]);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenHookMenu_Editor(int client)
{
	int ent = gA_EditCache[client].iEntity;
	int form = gA_EditCache[client].iForm;
	int track = gA_EditCache[client].iTrack;
	int hooktype = gA_EditCache[client].iFlags;
	int zonetype = gA_EditCache[client].iType;

	char classname[32], targetname[64], hammerid[16], sOrigin[64];
	GetEntityClassname(ent, classname, sizeof(classname));
	GetEntPropString(ent, Prop_Data, form == ZoneForm_trigger_teleport ? "m_target" : "m_iName", targetname, sizeof(targetname));
	IntToString(GetEntProp(ent, Prop_Data, "m_iHammerID"), hammerid, sizeof(hammerid));
	EntOriginString(ent, sOrigin, true);

	Menu menu = new Menu(MenuHandler_HookZone_Editor);
	menu.SetTitle("%s\nhammerid = %s\n%s = '%s'\norigin = %s\n ", classname, hammerid, form == ZoneForm_trigger_teleport ? "target" : "targetname", targetname, sOrigin);

	char display[128], buf[32];

	FormatEx(display, sizeof(display), "%T\n ", "ZoneHook_Tpto", client);
	menu.AddItem("tpto", display);//, form == ZoneForm_trigger_teleport ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

	GetTrackName(client, track, buf, sizeof(buf), true);
	FormatEx(display, sizeof(display), "%T", "ZoneEditTrack", client, buf);
	menu.AddItem("track", display);
	GetZoneName(client, zonetype, buf, sizeof(buf));
	FormatEx(display, sizeof(display), "%T", "ZoneHook_Zonetype", client, buf);
	menu.AddItem("ztype", display);
	FormatEx(display, sizeof(display), "%T\n ", "ZoneHook_Hooktype", client,
		(hooktype == -1) ? "UNKNOWN" :
			(hooktype & ZF_Hammerid) ? "hammerid" :
				((hooktype & ZF_Origin) ? "origin" : (form == ZoneForm_trigger_teleport ? "target" : "targetname")),
		(hooktype == -1) ? "":
			(hooktype & ZF_Hammerid) ? hammerid :
				((hooktype & ZF_Origin) ? sOrigin : targetname)
	);
	menu.AddItem("htype", display);

	FormatEx(display, sizeof(display), "%T", "ZoneHook_Confirm", client);
	menu.AddItem(
		"hook", display,
		(zonetype != -1 && hooktype != -1 && track != -1) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED
	);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void HookZone_SetupEditor(int client, int ent)
{
	float origin[3];
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", origin);
	GetEntPropVector(ent, Prop_Send, "m_vecMins", gA_EditCache[client].fCorner1);
	GetEntPropVector(ent, Prop_Send, "m_vecMaxs", gA_EditCache[client].fCorner2);
	origin[2] += 1.0; // so you don't get stuck in the ground
	AddVectors(origin, gA_EditCache[client].fCorner1, gA_EditCache[client].fCorner1);
	AddVectors(origin, gA_EditCache[client].fCorner2, gA_EditCache[client].fCorner2);

	gI_MapStep[client] = 3;
	gA_EditCache[client].iEntity = ent;
	gA_EditCache[client].iType = -1;
	gA_EditCache[client].iTrack = -1;
	gA_EditCache[client].iFlags = -1;
	OpenHookMenu_Editor(client);

	//if (gA_EditCache[client].iForm == ZoneForm_trigger_multiple)
	gH_StupidTimer[client] = CreateTimer(0.1, Timer_Draw, GetClientSerial(client), TIMER_REPEAT);
}

public int MenuHandle_HookZone_List(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[20];
		menu.GetItem(param2, info, sizeof(info));
		int ent = EntRefToEntIndex(StringToInt(info));

		if (ent <= MaxClients)
		{
			Shavit_PrintToChat(param1, "Invalid entity index???");
			OpenHookMenu_List(param1, gA_EditCache[param1].iForm, 0);
			return 0;
		}

		gI_HookListPos[param1] = GetMenuSelectionPosition();
		HookZone_SetupEditor(param1, ent);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenHookMenu_Form(param1);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

enum struct ent_list_thing
{
	float dist;
	int ent;
}

void OpenHookMenu_List(int client, int form, int pos = 0)
{
	Reset(client);
	gA_EditCache[client].iForm = form;
	gA_EditCache[client].sSource = "sql";

	float player_origin[3];
	GetClientAbsOrigin(client, player_origin);

	char classname[32]; classname =
		 (form == ZoneForm_trigger_multiple) ? "trigger_multiple" :
		((form == ZoneForm_trigger_teleport) ? "trigger_teleport" : "func_button");

	char targetname[64], info[20], display[128];
	int ent = -1;

	ArrayList list = new ArrayList(sizeof(ent_list_thing));

	while ((ent = FindEntityByClassname(ent, classname)) != -1)
	{
		if (gI_EntityZone[ent] > -1) continue;

		float ent_origin[3];
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", ent_origin);

		ent_list_thing thing;
		thing.dist = GetVectorDistance(player_origin, ent_origin);
		thing.ent = ent;
		list.PushArray(thing);
	}

	// copy & paste for func_rot_button because it's shrimple and I can't think of how to do it cleanly otherwise right now
	if (form == ZoneForm_func_button)
	{
		while ((ent = FindEntityByClassname(ent, "func_rot_button")) != -1)
		{
			if (gI_EntityZone[ent] > -1) continue;

			float ent_origin[3];
			GetEntPropVector(ent, Prop_Send, "m_vecOrigin", ent_origin);

			ent_list_thing thing;
			thing.dist = GetVectorDistance(player_origin, ent_origin);
			thing.ent = ent;
			list.PushArray(thing);
		}
	}

	if (!list.Length)
	{
		Shavit_PrintToChat(client, "No unhooked entities found");
		delete list;
		OpenHookMenu_Form(client);
		return;
	}

	list.Sort(Sort_Ascending, Sort_Float);

	Menu menu = new Menu(MenuHandle_HookZone_List);
	menu.SetTitle("%T\n ", "HookZone2", client, classname);

	for (int i = 0; i < list.Length; i++)
	{
		ent_list_thing thing;
		list.GetArray(i, thing);

		GetEntPropString(thing.ent, Prop_Data, form == ZoneForm_trigger_teleport ? "m_target" : "m_iName", targetname, sizeof(targetname));

		if (form == ZoneForm_trigger_multiple && StrContains(targetname, "shavit_zones_") == 0)
		{
			continue;
		}

		FormatEx(display, sizeof(display), "%s | %d dist=%.1fm", targetname, GetEntProp(thing.ent, Prop_Data, "m_iHammerID"), thing.dist*0.01905);
		FormatEx(info, sizeof(info), "%d", EntIndexToEntRef(thing.ent));
		menu.AddItem(info, display);
	}

	delete list;

	if (!menu.ItemCount)
	{
		Shavit_PrintToChat(client, "No unhooked entities found");
		delete menu;
		OpenHookMenu_Form(client);
		return;
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, pos, MENU_TIME_FOREVER);
}


bool TeleportFilter(int entity)
{
	char classname[20];
	GetEntityClassname(entity, classname, sizeof(classname));

	if (StrEqual(classname, "trigger_teleport") || StrEqual(classname, "trigger_multiple") || StrEqual(classname, "func_button") || StrEqual(classname, "func_rot_button"))
	{
		//TR_ClipCurrentRayToEntity(MASK_ALL, entity);
		gI_CurrentTraceEntity = entity;
		return false;
	}

	return true;
}

public int MenuHandle_HookZone_Form(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[20];
		menu.GetItem(param2, info, sizeof(info));
		int form = StringToInt(info);

		if (form != -1)
		{
			OpenHookMenu_List(param1, form, 0);
			return 0;
		}

		// entity under crosshair

		float origin[3], endpos[3];
		GetClientEyePosition(param1, origin);
		GetClientEyeAngles(param1, endpos);
		GetAngleVectors(endpos, endpos, NULL_VECTOR, NULL_VECTOR);
		ScaleVector(endpos, 30000.0);
		AddVectors(origin, endpos, endpos);

		gI_CurrentTraceEntity = 0; // had some troubles in mpbhops_but_working with TR_EnumerateEntitiesHull. So I did this. And copied it to bhoptimer
		TR_EnumerateEntitiesHull(origin, endpos,
			view_as<float>({-8.0, -8.0, 0.0}), view_as<float>({8.0, 8.0, 0.0}),
			PARTITION_TRIGGER_EDICTS, TeleportFilter, 0);
		int ent = gI_CurrentTraceEntity;

		if (ent <= MaxClients || ent >= 2048)
		{
			Shavit_PrintToChat(param1, "Couldn't find entity under crosshair");
			OpenHookMenu_Form(param1);
			return 0;
		}

		char classname[32];
		GetEntityClassname(ent, classname, sizeof(classname));

		if (StrEqual(classname, "func_button") || StrEqual(classname, "func_rot_button"))
		{
			form = ZoneForm_func_button;
		}
		else if (StrEqual(classname, "trigger_multiple"))
		{
			form = ZoneForm_trigger_multiple;
		}
		else if (StrEqual(classname, "trigger_teleport"))
		{
			form = ZoneForm_trigger_teleport;
		}
		else
		{
			Shavit_PrintToChat(param1, "Entity class %s (%d) not supported", classname, ent);
			OpenHookMenu_Form(param1);
			return 0;
		}

		if (gI_EntityZone[ent] > -1)
		{
			Shavit_PrintToChat(param1, "Entity %s (%d) is already hooked", classname, ent);
			OpenHookMenu_Form(param1);
			return 0;
		}

		Reset(param1);
		gI_HookListPos[param1] = 0;
		gA_EditCache[param1].iForm = form;
		gA_EditCache[param1].sSource = "sql";
		HookZone_SetupEditor(param1, ent);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		gH_AdminMenu.DisplayCategory(gH_TimerCommands, param1);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenHookMenu_Form(int client)
{
	Reset(client);

	Menu menu = new Menu(MenuHandle_HookZone_Form);
	menu.SetTitle("%T\n ", "HookZone", client);

	char display[128];

	FormatEx(display, sizeof(display), "%T\n ", "ZoneHook_Crosshair", client);
	menu.AddItem("-1", display);
	// hardcoded ZoneForm_ values
	menu.AddItem("3", "func_button");
	menu.AddItem("1", "trigger_multiple");
	menu.AddItem("2", "trigger_teleport");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

Action OpenEditMenu(int client, int pos = 0)
{
	Menu menu = new Menu(MenuHandler_ZoneEdit);
	menu.SetTitle("%T\n ", "ZoneEditTitle", client);

	int newPageInterval = (gEV_Type == Engine_CSGO) ? 6 : 7;
	char sDisplay[128];
	FormatEx(sDisplay, sizeof(sDisplay), "%T", "ZoneEditRefresh", client);
	menu.AddItem("-2", sDisplay);

	for(int i = 0; i < gI_MapZones; i++)
	{
		if ((menu.ItemCount % newPageInterval) == 0)
		{
			FormatEx(sDisplay, sizeof(sDisplay), "%T", "ZoneEditRefresh", client);
			menu.AddItem("-2", sDisplay);
		}

		char sInfo[8];
		IntToString(i, sInfo, 8);

		char sTarget[64];

		switch (gA_ZoneCache[i].iForm)
		{
			case ZoneForm_func_button, ZoneForm_trigger_multiple, ZoneForm_trigger_teleport:
			{
				FormatEx(sTarget, sizeof(sTarget), " (%s)", gA_ZoneCache[i].sTarget);
			}
		}

		char sTrack[32];
		GetTrackName(client, gA_ZoneCache[i].iTrack, sTrack, 32);

		char sZoneName[32];
		GetZoneName(client, gA_ZoneCache[i].iType, sZoneName, sizeof(sZoneName));

		if (gA_ZoneCache[i].iType == Zone_CustomSpeedLimit || gA_ZoneCache[i].iType == Zone_Stage || gA_ZoneCache[i].iType == Zone_Airaccelerate)
		{
			FormatEx(sDisplay, sizeof(sDisplay), "#%d - %s %d (%s)%s", (i + 1), sZoneName, gA_ZoneCache[i].iData, sTrack, sTarget);
		}
		else if (gA_ZoneCache[i].iType == Zone_Gravity || gA_ZoneCache[i].iType == Zone_Speedmod)
		{
			FormatEx(sDisplay, 64, "#%d - %s %.2f (%s)", (i + 1), sZoneName, gA_ZoneCache[i].iData, sTrack);
		}
		else
		{
			FormatEx(sDisplay, sizeof(sDisplay), "#%d - %s (%s)%s", (i + 1), sZoneName, sTrack, sTarget);
		}

		if(gB_InsideZoneID[client][i])
		{
			Format(sDisplay, sizeof(sDisplay), "%s %T", sDisplay, "ZoneInside", client);
		}

		menu.AddItem(sInfo, sDisplay, ITEMDRAW_DEFAULT);
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, pos, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_ZoneEdit(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, 8);

		int id = StringToInt(info);

		switch(id)
		{
			case -2:
			{
				OpenEditMenu(param1, GetMenuSelectionPosition());
			}

			case -1:
			{
				Shavit_PrintToChat(param1, "%T", "ZonesMenuNoneFound", param1);
			}

			default:
			{
				// a hack to place the player in the last step of zone editing
				gI_MapStep[param1] = 3;
				gA_EditCache[param1] = gA_ZoneCache[id];
				gI_ZoneID[param1] = id;
				gI_LastMenuPos[param1] = GetMenuSelectionPosition();

				// draw the zone edit
				CreateTimer(0.1, Timer_Draw, GetClientSerial(param1), TIMER_REPEAT);

				CreateEditMenu(param1);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		gH_AdminMenu.DisplayCategory(gH_TimerCommands, param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_CustomZones(int client, int args)
{
	if (!client) return Plugin_Handled;

	OpenCustomZoneMenu(client);

	return Plugin_Handled;
}

void OpenCustomZoneMenu(int client, int pos=0)
{
	Menu menu = new Menu(MenuHandler_CustomZones);
	menu.SetTitle("%T", "CustomZone_MainMenuTitle", client);

	// Only start zone and end zone are customizable imo, why do you even want to customize the zones that arent often used/seen???
#if CZONE_VER != 'a'
	for (int i = 0; i <= Track_Bonus; i++)
	{
		for (int j = 0; j < ZONETYPES_SIZE; j++)
#else
	for (int i = 0; i < TRACKS_SIZE; i++)
	{
		for (int j = 0; j <= Zone_End; j++)
#endif
		{
			if (j != Zone_CustomSpawn)// && gA_ZoneSettings[j][i].bVisible)
			{
				char info[8];
				FormatEx(info, sizeof(info), "%i;%i", i, j);
				char trackName[32], zoneName[32], display[64];
				GetTrackName(client, i, trackName, sizeof(trackName), !(CZONE_VER == 'b'));
				GetZoneName(client, j, zoneName, sizeof(zoneName));

				FormatEx(display, sizeof(display), "%s - %s", trackName, zoneName);
				menu.AddItem(info, display);
			}
		}
	}

	menu.DisplayAt(client, pos, MENU_TIME_FOREVER);
}

public int MenuHandler_CustomZones(Menu menu, MenuAction action, int client, int position)
{
	if(action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(position, info, sizeof(info));

		char exploded[2][4];
		ExplodeString(info, ";", exploded, 2, 4);

		int track = StringToInt(exploded[0]);
		int zoneType = StringToInt(exploded[1]);

		gI_LastMenuPos[client] = GetMenuSelectionPosition();
		OpenSubCustomZoneMenu(client, track, zoneType);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenSubCustomZoneMenu(int client, int track, int zoneType)
{
	Menu menu = new Menu(MenuHandler_SubCustomZones);

	char trackName[32], zoneName[32];
	GetTrackName(client, track, trackName, sizeof(trackName));
	GetZoneName(client, zoneType, zoneName, sizeof(zoneName));

	menu.SetTitle("%T", "CustomZone_SubMenuTitle", client, trackName, zoneName);

	char info[16], display[64];

	static char displayName[ZoneDisplay_Size][] =
	{
		"CustomZone_Default",
		"CustomZone_DisplayType_Flat",
		"CustomZone_DisplayType_Box",
		"CustomZone_DisplayType_None",
	};

	static char colorName[ZoneColor_Size][] =
	{
		"CustomZone_Default",
		"CustomZone_Color_White",
		"CustomZone_Color_Red",
		"CustomZone_Color_Orange",
		"CustomZone_Color_Yellow",
		"CustomZone_Color_Green",
		"CustomZone_Color_Cyan",
		"CustomZone_Color_Blue",
		"CustomZone_Color_Purple",
		"CustomZone_Color_Pink"
	};

	static char widthName[ZoneWidth_Size][] =
	{
		"CustomZone_Default",
		"CustomZone_Width_UltraThin",
		"CustomZone_Width_Thin",
		"CustomZone_Width_Normal",
		"CustomZone_Width_Thick"
	};

	FormatEx(info, sizeof(info), "%i;%i;0", track, zoneType);
	FormatEx(display, sizeof(display), "%T: %T", "CustomZone_DisplayType", client, displayName[gI_ZoneDisplayType[client][zoneType][track]], client);
	menu.AddItem(info, display);

	FormatEx(info, sizeof(info), "%i;%i;1", track, zoneType);
	FormatEx(display, sizeof(display), "%T: %T", "CustomZone_Color", client, colorName[gI_ZoneColor[client][zoneType][track]], client);
	menu.AddItem(info, display);

	FormatEx(info, sizeof(info), "%i;%i;2", track, zoneType);
	FormatEx(display, sizeof(display), "%T: %T", "CustomZone_Width", client, widthName[gI_ZoneWidth[client][zoneType][track]], client);
	menu.AddItem(info, display);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void HandleCustomZoneCookie(int client)
{
	char buf[200];
	int p = 0;

#if CZONE_VER >= 'b'
	for (int type = Zone_Start; type < ZONETYPES_SIZE; type++)
	{
		for (int track = Track_Main; track <= Track_Bonus; track++)
#else
	for (int type = Zone_Start; type <= Zone_End; type++)
	{
		for (int track = Track_Main; track < TRACKS_SIZE; track++)
#endif
		{
#if CZONE_VER == 'c'
			if (!p) buf[p++] = CZONE_VER;
			buf[p++] = '0' + gI_ZoneDisplayType[client][type][track];
			buf[p++] = '0' + gI_ZoneColor[client][type][track];
			buf[p++] = '0' + gI_ZoneWidth[client][type][track];
#else
			if (gI_ZoneDisplayType[client][type][track] || gI_ZoneColor[client][type][track] || gI_ZoneWidth[client][type][track])
			{
				if (!p) buf[p++] = CZONE_VER;
				// highest bit (0x80) set so we don't get a zero byte terminating the cookie early
				buf[p++] = 0x80 | (gI_ZoneDisplayType[client][type][track] << 5) | (type << 4) | track;
				buf[p++] = 0x80 | (gI_ZoneWidth[client][type][track] << 4) | gI_ZoneColor[client][type][track];
			}
#endif
		}
	}

	Format(buf[100], 100, "%s", buf[99]); // shift that bitch over...
	buf[99] = 0;
	gH_CustomZoneCookie.Set(client, buf);
	gH_CustomZoneCookie2.Set(client, buf[100]);
}

public int MenuHandler_SubCustomZones(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, sizeof(info));

		char exploded[3][4];
		ExplodeString(info, ";", exploded, 3, 4);

		int track = StringToInt(exploded[0]);
		int zoneType = StringToInt(exploded[1]);
		int option = StringToInt(exploded[2]);

		if (option == 0) // Display type
		{
			gI_ZoneDisplayType[client][zoneType][track]++;

			if (gI_ZoneDisplayType[client][zoneType][track] >= ZoneDisplay_Size)
				gI_ZoneDisplayType[client][zoneType][track] = ZoneDisplay_Default;

			HandleCustomZoneCookie(client);
		}
		else if (option == 1) // Color
		{
			gI_ZoneColor[client][zoneType][track]++;

			if (gI_ZoneColor[client][zoneType][track] >= ZoneColor_Size)
				gI_ZoneColor[client][zoneType][track] = ZoneColor_Default;

			HandleCustomZoneCookie(client);
		}
		else if (option == 2) // Width
		{
			gI_ZoneWidth[client][zoneType][track]++;

			if (gI_ZoneWidth[client][zoneType][track] >= ZoneWidth_Size)
				gI_ZoneWidth[client][zoneType][track] = ZoneWidth_Default;

			HandleCustomZoneCookie(client);
		}

		OpenSubCustomZoneMenu(client, track, zoneType);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenCustomZoneMenu(client, gI_LastMenuPos[client]);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_DeleteZone(int client, int args)
{
	if (!gH_SQL)
	{
		Shavit_PrintToChat(client, "Database not loaded. Check your error logs.");
		return Plugin_Handled;
	}

	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

#if 0
	if (!gCV_SQLZones.BoolValue)
	{
		Shavit_PrintToChat(client, "%T", "ZonesNotSQL", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return Plugin_Handled;
	}
#endif

	return OpenDeleteMenu(client);
}

Action OpenDeleteMenu(int client, int pos = 0)
{
	Menu menu = new Menu(MenuHandler_DeleteZone);
	menu.SetTitle("%T\n ", "ZoneMenuDeleteTitle", client);

	int newPageInterval = (gEV_Type == Engine_CSGO) ? 6 : 7;
	char sDisplay[128];
	FormatEx(sDisplay, sizeof(sDisplay), "%T", "ZoneEditRefresh", client);
	menu.AddItem("-2", sDisplay);

	for(int i = 0; i < gI_MapZones; i++)
	{
		if (true)//(gA_ZoneCache[i].bInitialized)
		{
			if ((menu.ItemCount % newPageInterval) == 0)
			{
				FormatEx(sDisplay, sizeof(sDisplay), "%T", "ZoneEditRefresh", client);
				menu.AddItem("-2", sDisplay);
			}

			char sTarget[64];

			switch (gA_ZoneCache[i].iForm)
			{
				case ZoneForm_func_button, ZoneForm_trigger_multiple, ZoneForm_trigger_teleport:
				{
					FormatEx(sTarget, sizeof(sTarget), " (%s)", gA_ZoneCache[i].sTarget);
				}
			}

			char sTrack[32];
			GetTrackName(client, gA_ZoneCache[i].iTrack, sTrack, 32);

			char sZoneName[32];
			GetZoneName(client, gA_ZoneCache[i].iType, sZoneName, sizeof(sZoneName));

			if(gA_ZoneCache[i].iType == Zone_CustomSpeedLimit || gA_ZoneCache[i].iType == Zone_Stage || gA_ZoneCache[i].iType == Zone_Airaccelerate)
			{
				FormatEx(sDisplay, sizeof(sDisplay), "#%d - %s %d (%s)%s", (i + 1), sZoneName, gA_ZoneCache[i].iData, sTrack, sTarget);
			}
			else if (gA_ZoneCache[i].iType == Zone_Gravity || gA_ZoneCache[i].iType == Zone_Speedmod)
			{
				FormatEx(sDisplay, 64, "#%d - %s %.2f (%s)", (i + 1), sZoneName, gA_ZoneCache[i].iData, sTrack);
			}
			else
			{
				FormatEx(sDisplay, sizeof(sDisplay), "#%d - %s (%s)%s", (i + 1), sZoneName, sTrack, sTarget);
			}

			char sInfo[8];
			IntToString(i, sInfo, 8);

			if(gB_InsideZoneID[client][i])
			{
				Format(sDisplay, sizeof(sDisplay), "%s %T", sDisplay, "ZoneInside", client);
			}

			menu.AddItem(sInfo, sDisplay, ITEMDRAW_DEFAULT);
		}
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, pos, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_DeleteZone(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, 8);

		int id = StringToInt(info);

		switch(id)
		{
			case -2:
			{
				OpenDeleteMenu(param1, GetMenuSelectionPosition());
			}

			case -1:
			{
				Shavit_PrintToChat(param1, "%T", "ZonesMenuNoneFound", param1);
			}

			default:
			{
				char sZoneName[32];
				GetZoneName(LANG_SERVER, gA_ZoneCache[id].iType, sZoneName, sizeof(sZoneName));

				Shavit_LogMessage("%L - deleted %s (id %d) from map `%s`.", param1, sZoneName, gA_ZoneCache[id].iDatabaseID, gS_Map);

				char sQuery[256];
				FormatEx(sQuery, 256, "DELETE FROM %smapzones WHERE %s = %d;", gS_MySQLPrefix, (gI_Driver != Driver_sqlite) ? "id":"rowid", gA_ZoneCache[id].iDatabaseID);

				DataPack hDatapack = new DataPack();
				hDatapack.WriteCell(GetClientSerial(param1));
				hDatapack.WriteCell(gA_ZoneCache[id].iType);

				QueryLog(gH_SQL, SQL_DeleteZone_Callback, sQuery, hDatapack);

				Shavit_RemoveZone(id);
			}
		}
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		gH_AdminMenu.DisplayCategory(gH_TimerCommands, param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void SQL_DeleteZone_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int client = GetClientFromSerial(data.ReadCell());
	int type = data.ReadCell();

	delete data;

	if(results == null)
	{
		LogError("Timer (single zone delete) SQL query failed. Reason: %s", error);

		return;
	}

	if(client == 0)
	{
		return;
	}

	char sZoneName[32];
	GetZoneName(client, type, sZoneName, sizeof(sZoneName));

	Shavit_PrintToChat(client, "%T", "ZoneDeleteSuccessful", client, gS_ChatStrings.sVariable, sZoneName, gS_ChatStrings.sText);
}

public Action Command_DeleteAllZones(int client, int args)
{
	if (!gH_SQL)
	{
		Shavit_PrintToChat(client, "Database not loaded. Check your error logs.");
		return Plugin_Handled;
	}

	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_DeleteAllZones);
	menu.SetTitle("%T", "ZoneMenuDeleteALLTitle", client);

	char sMenuItem[64];

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "ZoneMenuNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	FormatEx(sMenuItem, 64, "%T", "ZoneMenuYes", client);
	menu.AddItem("yes", sMenuItem);

	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "ZoneMenuNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_DeleteAllZones(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, 8);

		int iInfo = StringToInt(info);

		if(iInfo == -1)
		{
			return 0;
		}

		Shavit_LogMessage("%L - deleted all zones from map `%s`.", param1, gS_Map);

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "DELETE FROM %smapzones WHERE map = '%s';", gS_MySQLPrefix, gS_Map);

		QueryLog(gH_SQL, SQL_DeleteAllZones_Callback, sQuery, GetClientSerial(param1));
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		gH_AdminMenu.DisplayCategory(gH_TimerCommands, param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void SQL_DeleteAllZones_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (single zone delete) SQL query failed. Reason: %s", error);

		return;
	}

	UnloadZones();

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	Shavit_PrintToChat(client, "%T", "ZoneDeleteAllSuccessful", client);
}

public int MenuHandler_SelectZoneType(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[8];
		menu.GetItem(param2, info, 8);

		gA_EditCache[param1].iType = StringToInt(info);

		if (gA_EditCache[param1].iType == Zone_Gravity || gA_EditCache[param1].iType == Zone_Speedmod)
		{
			gA_EditCache[param1].iData = view_as<int>(1.0);
		}

		ShowPanel(param1, 1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void Reset(int client)
{
	zone_cache_t cache;
	cache.iDatabaseID = -1;
	gA_EditCache[client] = cache;
	gI_MapStep[client] = 0;
	gI_HookListPos[client] = -1;
	delete gH_StupidTimer[client];
	gB_WaitingForChatInput[client] = false;
	gI_ZoneID[client] = -1;

	gV_WallSnap[client] = ZERO_VECTOR;
}

void ShowPanel(int client, int step)
{
	gI_MapStep[client] = step;

	if(step == 1)
	{
		CreateTimer(0.1, Timer_Draw, GetClientSerial(client), TIMER_REPEAT);
	}

	Panel pPanel = new Panel();

	char sPanelText[128];
	char sFirst[64];
	char sSecond[64];
	FormatEx(sFirst, 64, "%T", "ZoneFirst", client);
	FormatEx(sSecond, 64, "%T", "ZoneSecond", client);

	if(gEV_Type == Engine_TF2)
	{
		FormatEx(sPanelText, 128, "%T", "ZonePlaceTextTF2", client, (step == 1)? sFirst:sSecond);
	}
	else
	{
		FormatEx(sPanelText, 128, "%T", "ZonePlaceText", client, (step == 1)? sFirst:sSecond);
	}

	pPanel.DrawItem(sPanelText, ITEMDRAW_RAWLINE);
	char sPanelItem[64];
	FormatEx(sPanelItem, 64, "%T", "AbortZoneCreation", client);
	pPanel.DrawItem(sPanelItem);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "GridSnapPlus", client, gI_GridSnap[client]);
	pPanel.DrawItem(sDisplay);

	FormatEx(sDisplay, 64, "%T", "GridSnapMinus", client);
	pPanel.DrawItem(sDisplay);

	FormatEx(sDisplay, 64, "%T", "WallSnap", client, (gB_SnapToWall[client])? "ZoneSetYes":"ZoneSetNo", client);
	pPanel.DrawItem(sDisplay);

	FormatEx(sDisplay, 64, "%T", "CursorZone", client, (gB_CursorTracing[client])? "ZoneSetYes":"ZoneSetNo", client);
	pPanel.DrawItem(sDisplay);

	FormatEx(sDisplay, sizeof(sDisplay), "%T", "ZoningIgnoreTriggers", client, (gB_IgnoreTriggers[client])? "ZoneSetYes":"ZoneSetNo", client);
	pPanel.DrawItem(sDisplay);

	pPanel.Send(client, ZoneCreation_Handler, MENU_TIME_FOREVER);

	delete pPanel;
}

public int ZoneCreation_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		switch(param2)
		{
			case 1:
			{
				Reset(param1);

				return 0;
			}

			case 2:
			{
				gI_GridSnap[param1] *= 2;

				if(gI_GridSnap[param1] > 64)
				{
					gI_GridSnap[param1] = 1;
				}
			}

			case 3:
			{
				gI_GridSnap[param1] /= 2;

				if(gI_GridSnap[param1] < 1)
				{
					gI_GridSnap[param1] = 64;
				}
			}

			case 4:
			{
				gB_SnapToWall[param1] = !gB_SnapToWall[param1];

				if(gB_SnapToWall[param1])
				{
					gB_CursorTracing[param1] = false;

					if(gI_GridSnap[param1] < 32)
					{
						gI_GridSnap[param1] = 32;
					}
				}
			}

			case 5:
			{
				gB_CursorTracing[param1] = !gB_CursorTracing[param1];

				if(gB_CursorTracing[param1])
				{
					gB_SnapToWall[param1] = false;
				}
			}

			case 6:
			{
				gB_IgnoreTriggers[param1] = !gB_IgnoreTriggers[param1];
			}
		}

		ShowPanel(param1, gI_MapStep[param1]);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

float[] SnapToGrid(float pos[3], int grid, bool third)
{
	float origin[3];
	origin = pos;

	origin[0] = float(RoundToNearest(pos[0] / grid) * grid);
	origin[1] = float(RoundToNearest(pos[1] / grid) * grid);

	if(third)
	{
		origin[2] = float(RoundToNearest(pos[2] / grid) * grid);
	}

	return origin;
}

bool SnapToWall(float pos[3], int client, float final[3])
{
	bool hit = false;

	float end[3];
	float temp[3];

	float prefinal[3];
	prefinal = pos;

	for(int i = 0; i < 4; i++)
	{
		end = pos;

		int axis = (i / 2);
		end[axis] += (((i % 2) == 1)? -gI_GridSnap[client]:gI_GridSnap[client]);

		TR_TraceRayFilter(pos, end, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_NoClients, client);

		if(TR_DidHit())
		{
			TR_GetEndPosition(temp);
			prefinal[axis] = temp[axis];
			hit = true;
		}
	}

	if(hit && GetVectorDistance(prefinal, pos) <= gI_GridSnap[client])
	{
		final = SnapToGrid(prefinal, gI_GridSnap[client], false);

		return true;
	}

	return false;
}

public bool TraceFilter_NoClients(int entity, int contentsMask, any data)
{
	return (entity != data && !IsValidClient(data));
}

float[] GetAimPosition(int client)
{
	float pos[3];
	GetClientEyePosition(client, pos);

	float angles[3];
	GetClientEyeAngles(client, angles);

	TR_TraceRayFilter(pos, angles, MASK_PLAYERSOLID, RayType_Infinite, TraceFilter_NoClients, client);

	if(TR_DidHit())
	{
		float end[3];
		TR_GetEndPosition(end);

		return SnapToGrid(end, gI_GridSnap[client], true);
	}

	return pos;
}

public bool TraceFilter_World(int entity, int contentsMask)
{
	return (entity == 0);
}

// Sometimes our points aren't mins/maxs... sometimes old DB points... which is not good...
void BoxPointsToMinsMaxs(float point1[3], float point2[3], float boxmin[3], float boxmax[3])
{
	for (int i = 0; i < 3; i++)
	{
		float a = point1[i];
		float b = point2[i];

		if (a < b)
		{
			boxmin[i] = a;
			boxmax[i] = b;
		}
		else
		{
			boxmin[i] = b;
			boxmax[i] = a;
		}
	}
}

bool BoxesIntersect(float amin[3], float amax[3], float bmin[3], float bmax[3])
{
	return (amin[0] <= bmax[0] && amax[0] >= bmin[0]) &&
	       (amin[1] <= bmax[1] && amax[1] >= bmin[1]) &&
	       (amin[2] <= bmax[2] && amax[2] >= bmin[2]);
}

bool PointInBox(float point[3], float bmin[3], float bmax[3])
{
	return (bmin[0] <= point[0] <= bmax[0]) &&
	       (bmin[1] <= point[1] <= bmax[1]) &&
	       (bmin[2] <= point[2] <= bmax[2]);
}

bool InStartOrEndZone(float point1[3], float point2[3], int track, int type)
{
	if (type != Zone_Start && type != Zone_End)
	{
		return false;
	}

	float amin[3], amax[3];
	bool box = !IsNullVector(point2);

	if (box)
	{
		BoxPointsToMinsMaxs(point1, point2, amin, amax);
	}

	for (int i = 0; i < gI_MapZones; i++)
	{
		// we only care about start/end zones
		if (gA_ZoneCache[i].iType != Zone_End && gA_ZoneCache[i].iType != Zone_Start)
			continue;
		// we don't care about start/end zones from other tracks
		if (gA_ZoneCache[i].iTrack != track)
			continue;
		// placing multiple overlapping startzones, or multiple overlapping endzones, is fine
		if (gA_ZoneCache[i].iType == type)
			continue;

		float bmin[3], bmax[3];
		BoxPointsToMinsMaxs(gV_MapZones_Visual[i][0], gV_MapZones_Visual[i][7], bmin, bmax);

		if (box)
		{
			if (BoxesIntersect(amin, amax, bmin, bmax))
			{
				return true;
			}
		}
		else
		{
			if (PointInBox(point1, bmin, bmax))
			{
				return true;
			}
		}
	}

	return false;
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style)
{
	if(gI_MapStep[client] > 0 && gI_MapStep[client] != 3)
	{
		int button = (gEV_Type == Engine_TF2)? IN_ATTACK2:IN_USE;

		if((buttons & button) > 0)
		{
			if(!gB_Button[client])
			{
				float vPlayerOrigin[3];
				GetClientAbsOrigin(client, vPlayerOrigin);

				float origin[3];

				if(gB_CursorTracing[client])
				{
					origin = GetAimPosition(client);
				}
				else if(!(gB_SnapToWall[client] && SnapToWall(vPlayerOrigin, client, origin)))
				{
					origin = SnapToGrid(vPlayerOrigin, gI_GridSnap[client], false);
				}
				else
				{
					gV_WallSnap[client] = origin;
				}

				origin[2] = vPlayerOrigin[2];

				if(gI_MapStep[client] == 1)
				{
					origin[2] += 1.0;

					if (!InStartOrEndZone(origin, NULL_VECTOR, gA_EditCache[client].iTrack, gA_EditCache[client].iType))
					{
						gA_EditCache[client].fCorner1 = origin;
						ShowPanel(client, 2);
					}
				}
				else if(gI_MapStep[client] == 2)
				{
					origin[2] += gCV_Height.FloatValue;

					if (origin[0] != gA_EditCache[client].fCorner1[0] && origin[1] != gA_EditCache[client].fCorner1[1] && !InStartOrEndZone(gA_EditCache[client].fCorner1, origin, gA_EditCache[client].iTrack, gA_EditCache[client].iType))
					{
						gA_EditCache[client].fCorner2 = origin;
						gI_MapStep[client]++;

						CreateEditMenu(client, true);
					}
				}
			}
		}

		gB_Button[client] = (buttons & button) > 0;
	}

	if(InsideZone(client, Zone_Slide, (gCV_EnforceTracks.BoolValue)? track:-1) && GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") == -1)
	{
		// trace down, see if there's 8 distance or less to ground
		float fPosition[3];
		GetClientAbsOrigin(client, fPosition);
		TR_TraceRayFilter(fPosition, view_as<float>({90.0, 0.0, 0.0}), MASK_PLAYERSOLID, RayType_Infinite, TRFilter_NoPlayers, client);

		float fGroundPosition[3];

		if(TR_DidHit() && TR_GetEndPosition(fGroundPosition) && GetVectorDistance(fPosition, fGroundPosition) <= 8.0)
		{
			float fSpeed[3];
			GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fSpeed);

			fSpeed[2] = 8.0 * GetEntityGravity(client) * GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue") * (sv_gravity.FloatValue / 800);
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed);
		}
	}

	return Plugin_Continue;
}

public bool TRFilter_NoPlayers(int entity, int mask, any data)
{
	//return (entity != view_as<int>(data) || (entity < 1 || entity > MaxClients));
	return !(1 <= entity <= MaxClients);
}

public int CreateZoneConfirm_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "yes"))
		{
			if (gI_ZoneID[param1] != -1)
			{
				Shavit_RemoveZone(gI_ZoneID[param1]); // TODO: gI_ZoneID can be wiped mid menu or something...
			}

			InsertZone(param1);
			return 0;
		}
		else if(StrEqual(sInfo, "no"))
		{
			Reset(param1);
			return 0;
		}
		else if(StrEqual(sInfo, "adjust"))
		{
			CreateAdjustMenu(param1, 0);
			return 0;
		}
		else if(StrEqual(sInfo, "tpzone"))
		{
			UpdateTeleportZone(param1);
		}
		else if(StrEqual(sInfo, "datafromchat"))
		{
			gA_EditCache[param1].iData = 0;
			gB_WaitingForChatInput[param1] = true;
			Shavit_PrintToChat(param1, "%T", "ZoneEnterDataChat", param1);
			return 0;
		}
		else if(StrEqual(sInfo, "forcerender"))
		{
			gA_EditCache[param1].iFlags ^= ZF_ForceRender;
		}

		CreateEditMenu(param1);
	}
	else if (action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack)
		{
			if (gI_ZoneID[param1] == -1)
			{
				OpenHookMenu_Editor(param1);
			}
			else
			{
				OpenEditMenu(param1, gI_LastMenuPos[param1]);
			}
		}
		else
		{
			Reset(param1);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(gB_WaitingForChatInput[client] && gI_MapStep[client] == 3)
	{
		if (gA_EditCache[client].iType == Zone_Gravity || gA_EditCache[client].iType == Zone_Speedmod)
		{
			gA_EditCache[client].iData = view_as<int>(StringToFloat(sArgs));
		}
		else
		{
			gA_EditCache[client].iData = StringToInt(sArgs);
		}

		CreateEditMenu(client);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void UpdateTeleportZone(int client)
{
	float vTeleport[3];
	GetClientAbsOrigin(client, vTeleport);
	vTeleport[2] += 2.0;

	if (gA_EditCache[client].iType == Zone_Stage)
	{
		gA_EditCache[client].fDestination = vTeleport;

		Shavit_PrintToChat(client, "%T", "ZoneTeleportUpdated", client);
	}
	else
	{
		bool bInside = true;

		for(int i = 0; i < 3; i++)
		{
			if (gA_EditCache[client].fCorner1[i] >= vTeleport[i] == gA_EditCache[client].fCorner2[i] >= vTeleport[i])
			{
				bInside = false;
			}
		}

		if(bInside)
		{
			Shavit_PrintToChat(client, "%T", "ZoneTeleportInsideZone", client);
		}
		else
		{
			gA_EditCache[client].fDestination = vTeleport;

			Shavit_PrintToChat(client, "%T", "ZoneTeleportUpdated", client);
		}
	}
}

void CreateEditMenu(int client, bool autostage=false)
{
	bool hookmenu = gI_HookListPos[client] != -1;

	char sTrack[32], sType[32];
	GetTrackName(client, gA_EditCache[client].iTrack, sTrack, 32);
	GetZoneName(client, gA_EditCache[client].iType, sType, sizeof(sType));

	Menu menu = new Menu(CreateZoneConfirm_Handler);

	if (hookmenu)
	{
		menu.SetTitle("%T\n%T\n%T\n%T\n ",
			"ZoneEditConfirm", client,
			"ZoneEditTrack", client, sTrack,
			"ZoneHook_Zonetype", client, sType,
			"ZoneHook_Hooktype", client,
			(gA_EditCache[client].iFlags & ZF_Hammerid) ? "hammerid" :
				((gA_EditCache[client].iFlags & ZF_Origin) ? "origin" :
					(gA_EditCache[client].iForm == ZoneForm_trigger_teleport ? "target" : "targetname")),
			gA_EditCache[client].sTarget);
	}
	else
	{
		menu.SetTitle("%T\n%T\n%T\n ",
			"ZoneEditConfirm", client,
			"ZoneEditTrack", client, sTrack,
			"ZoneHook_Zonetype", client, sType);
	}

	char sMenuItem[64];

	if (gA_EditCache[client].iType == Zone_Teleport)
	{
		if (EmptyVector(gA_EditCache[client].fDestination))
		{
			FormatEx(sMenuItem, 64, "%T", "ZoneSetTP", client);
			menu.AddItem("-1", sMenuItem, ITEMDRAW_DISABLED);
		}
		else
		{
			FormatEx(sMenuItem, 64, "%T", "ZoneSetYes", client);
			menu.AddItem("yes", sMenuItem);
		}

		FormatEx(sMenuItem, 64, "%T", "ZoneSetTPZone", client);
		menu.AddItem("tpzone", sMenuItem);
	}
	else if (gA_EditCache[client].iType == Zone_Stage)
	{
		FormatEx(sMenuItem, 64, "%T", "ZoneSetYes", client);
		menu.AddItem("yes", sMenuItem);

		FormatEx(sMenuItem, 64, "%T", "ZoneSetTPZone", client);
		menu.AddItem("tpzone", sMenuItem);
	}
	else
	{
		FormatEx(sMenuItem, 64, "%T", "ZoneSetYes", client);
		menu.AddItem("yes", sMenuItem);
	}

	FormatEx(sMenuItem, 64, "%T", "ZoneSetNo", client);
	menu.AddItem("no", sMenuItem);

	FormatEx(sMenuItem, 64, "%T", "ZoneSetAdjust", client);
	menu.AddItem("adjust", sMenuItem,
		(hookmenu || gA_EditCache[client].iForm != ZoneForm_Box) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);

	FormatEx(sMenuItem, 64, "%T", "ZoneForceRender", client, ((gA_EditCache[client].iFlags & ZF_ForceRender) > 0)? "＋":"－");
	menu.AddItem("forcerender", sMenuItem);

	if (gA_EditCache[client].iType == Zone_Start)
	{
		if (gA_EditCache[client].iData == 0)
		{
			FormatEx(sMenuItem, 64, "%T", "ZoneSetSpeedLimitDefault", client, gA_EditCache[client].iData);
		}
		else
		{
			FormatEx(sMenuItem, 64, "%T", "ZoneSetSpeedLimit", client, gA_EditCache[client].iData);
		}

		menu.AddItem("datafromchat", sMenuItem);
	}
	else if (gA_EditCache[client].iType == Zone_Stage)
	{
		if (autostage)
		{
			gA_EditCache[client].iData = gI_HighestStage[gA_EditCache[client].iTrack] + 1;
		}

		FormatEx(sMenuItem, 64, "%T", "ZoneSetStage", client, gA_EditCache[client].iData);
		menu.AddItem("datafromchat", sMenuItem);
	}
	else if (gA_EditCache[client].iType == Zone_Airaccelerate)
	{
		FormatEx(sMenuItem, 64, "%T", "ZoneSetAiraccelerate", client, gA_EditCache[client].iData);
		menu.AddItem("datafromchat", sMenuItem);
	}
	else if (gA_EditCache[client].iType == Zone_CustomSpeedLimit)
	{
		if (gA_EditCache[client].iData == 0)
		{
			FormatEx(sMenuItem, 64, "%T", "ZoneSetSpeedLimitUnlimited", client, gA_EditCache[client].iData);
		}
		else
		{
			FormatEx(sMenuItem, 64, "%T", "ZoneSetSpeedLimit", client, gA_EditCache[client].iData);
		}

		menu.AddItem("datafromchat", sMenuItem);
	}
	else if (gA_EditCache[client].iType == Zone_Gravity)
	{
		float g = view_as<float>(gA_EditCache[client].iData);
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "ZoneSetGravity", client, g);
		menu.AddItem("datafromchat", sMenuItem);
	}
	else if (gA_EditCache[client].iType == Zone_Speedmod)
	{
		float speed = view_as<float>(gA_EditCache[client].iData);
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "ZoneSetSpeedmod", client, speed);
		menu.AddItem("datafromchat", sMenuItem);
	}

	if (hookmenu || gI_ZoneID[client] != -1)
		menu.ExitBackButton = true;
	else
		menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

void CreateAdjustMenu(int client, int page)
{
	Menu hMenu = new Menu(ZoneAdjuster_Handler);
	char sMenuItem[64];
	hMenu.SetTitle("%T\n ", "ZoneAdjustPosition", client);

	char sAxis[4];
	strcopy(sAxis, 4, "XYZ");

	char sDisplay[32];
	char sInfo[16];

	for(int iPoint = 1; iPoint <= 2; iPoint++)
	{
		for (int iState = 1; iState <= 2; iState++)
		{
			FormatEx(sDisplay, 32, "%T %c%.01f%s", "ZonePoint", client, iPoint, sAxis[gI_AdjustAxis[client]], (iState == 1)? '+':'-', gF_Modifier[client], (iState==2)?"\n ":"");
			FormatEx(sInfo, 16, "%d;%d;%d", iPoint, gI_AdjustAxis[client], iState);
			hMenu.AddItem(sInfo, sDisplay);
		}
	}

	FormatEx(sMenuItem, 64, "%T\n ", "ZoneAxis", client);
	hMenu.AddItem("axis", sMenuItem);

	FormatEx(sMenuItem, 64, "%T", "ZoneAdjustDone", client);
	hMenu.AddItem("done", sMenuItem);

	hMenu.ExitButton = true;
	hMenu.DisplayAt(client, page, MENU_TIME_FOREVER);
}

public int ZoneAdjuster_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "done"))
		{
			CreateEditMenu(param1);
		}
		else if (StrEqual(sInfo, "axis"))
		{
			gI_AdjustAxis[param1] = (gI_AdjustAxis[param1] + 1) % 3;
			CreateAdjustMenu(param1, GetMenuSelectionPosition());
		}
		else
		{
			char sAxis[4];
			strcopy(sAxis, 4, "XYZ");

			char sExploded[3][8];
			ExplodeString(sInfo, ";", sExploded, 3, 8);

			int iPoint = StringToInt(sExploded[0]);
			int iAxis = StringToInt(sExploded[1]);
			bool bIncrease = view_as<bool>(StringToInt(sExploded[2]) == 1);
			float mod = ((bIncrease)? gF_Modifier[param1]:-gF_Modifier[param1]);

			if (iPoint == 1)
				gA_EditCache[param1].fCorner1[iAxis] += mod;
			else
				gA_EditCache[param1].fCorner2[iAxis] += mod;

			Shavit_StopChatSound();
			Shavit_PrintToChat(param1, "%T", (bIncrease)? "ZoneSizeIncrease":"ZoneSizeDecrease", param1, gS_ChatStrings.sVariable2, sAxis[iAxis], gS_ChatStrings.sText, iPoint, gS_ChatStrings.sVariable, gF_Modifier[param1], gS_ChatStrings.sText);

			CreateAdjustMenu(param1, GetMenuSelectionPosition());
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (gI_ZoneID[param1] != -1)
		{
			// reenable original zone
			//gA_ZoneCache[gI_ZoneID[param1]].bInitialized = true;
		}

		Reset(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void InsertZone(int client)
{
	zone_cache_t c; c = gA_EditCache[client];
	c.iEntity = -1;
	c.sSource = "sql";

	char sQuery[1024];
	char sTrack[64], sZoneName[32];
	GetTrackName(LANG_SERVER, c.iTrack, sTrack, sizeof(sTrack));
	GetZoneName(LANG_SERVER, c.iType, sZoneName, sizeof(sZoneName));

	BoxPointsToMinsMaxs(c.fCorner1, c.fCorner2, c.fCorner1, c.fCorner2);

	Reset(client);

	if (!gCV_SQLZones.BoolValue)
	{
		c.sSource = "folder?";
		c.iDatabaseID = GetTime();
	}

	Shavit_AddZone(c);

	if (!gCV_SQLZones.BoolValue)
		return;

	if (c.iDatabaseID == -1) // insert
	{
		Shavit_LogMessage(
			"%L - added %s %s to map `%s`. \
			p1(%f, %f, %f), p2(%f, %f, %f), dest(%f, %f, %f), \
			flags=%d, data=%d, form=%d, target='%s'",
			client, sTrack, sZoneName, gS_Map,
			EXPAND_VECTOR(c.fCorner1),
			EXPAND_VECTOR(c.fCorner2),
			EXPAND_VECTOR(c.fDestination),
			c.iFlags, c.iData,
			c.iForm, c.sTarget
		);

		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO %smapzones (map, type, \
			corner1_x, corner1_y, corner1_z, \
			corner2_x, corner2_y, corner2_z, \
			destination_x, destination_y, destination_z, \
			track, flags, data, form, target) VALUES \
			('%s', %d,  \
			%f, %f, %f, \
			%f, %f, %f, \
			%f, %f, %f, \
			%d, %d, %d, \
			%d, '%s');",
			gS_MySQLPrefix,
			gS_Map, c.iType,
			EXPAND_VECTOR(c.fCorner1),
			EXPAND_VECTOR(c.fCorner2),
			EXPAND_VECTOR(c.fDestination),
			c.iTrack, c.iFlags, c.iData,
			c.iForm, c.sTarget
		);
	}
	else // update
	{
		Shavit_LogMessage(
			"%L - updated %s %s (%d) in map `%s`. \
			p1(%f, %f, %f), p2(%f, %f, %f), dest(%f, %f, %f), \
			flags=%d, data=%d, form=%d, target='%s'",
			client, sTrack, sZoneName, c.iDatabaseID, gS_Map,
			EXPAND_VECTOR(c.fCorner1),
			EXPAND_VECTOR(c.fCorner2),
			EXPAND_VECTOR(c.fDestination),
			c.iFlags, c.iData,
			c.iForm, c.sTarget
		);

		FormatEx(sQuery, sizeof(sQuery),
			"UPDATE %smapzones SET \
			  corner1_x = '%f', corner1_y = '%f', corner1_z = '%f' \
			, corner2_x = '%f', corner2_y = '%f', corner2_z = '%f' \
			, destination_x = '%f', destination_y = '%f', destination_z = '%f' \
			, flags = %d, data = %d \
			, form = %d, target = '%s' \
			WHERE %s = %d;",
			gS_MySQLPrefix,
			EXPAND_VECTOR(c.fCorner1),
			EXPAND_VECTOR(c.fCorner2),
			EXPAND_VECTOR(c.fDestination),
			c.iFlags, c.iData,
			c.iForm, c.sTarget,
			(gI_Driver != Driver_sqlite) ? "id" : "rowid", c.iDatabaseID
		);
	}

	DataPack pack = new DataPack();
	pack.WriteCellArray(c, sizeof(c));
	QueryLog(gH_SQL, SQL_InsertZone_Callback, sQuery, pack);
}

bool MyArrayEquals(any[] a, any[] b, int size)
{
	for (int i = 0; i < size; i++)
		if (a[i] != b[i])
			return false;
	return true;
}

public void SQL_InsertZone_Callback(Database db, DBResultSet results, const char[] error, DataPack pack)
{
	zone_cache_t cache;
	pack.Reset();
	pack.ReadCellArray(cache, sizeof(cache));
	delete pack;

	if (results == null)
	{
		LogError("Timer (zone insert) SQL query failed. Reason: %s", error);
		return;
	}

	for (int i = 0; i < gI_MapZones; i++)
	{
		cache.iEntity = gA_ZoneCache[i].iEntity;
		if (MyArrayEquals(gA_ZoneCache[i], cache, sizeof(zone_cache_t)))
		{
			gA_ZoneCache[i].iDatabaseID = results.InsertId;
			break;
		}
	}
}

public Action Timer_DrawZones(Handle Timer, any drawAll)
{
	if (gI_MapZones == 0)
	{
		return Plugin_Continue;
	}

	if (drawAll && !gCV_AllowDrawAllZones.BoolValue)
	{
		return Plugin_Continue;
	}

	static int iCycle[2];
	static int iMaxZonesPerFrame = 5;

	if (iCycle[drawAll] >= gI_MapZones)
	{
		iCycle[drawAll] = 0;
	}

	int iDrawn = 0;

	for (int i = iCycle[drawAll]; i < gI_MapZones; i++, iCycle[drawAll]++)
	{
		int form = gA_ZoneCache[i].iForm;
		int type = gA_ZoneCache[i].iType;
		int track = gA_ZoneCache[i].iTrack;

		if (drawAll || gA_ZoneSettings[type][track].bVisible || (gA_ZoneCache[i].iFlags & ZF_ForceRender) > 0)
		{
			if ((form == ZoneForm_trigger_teleport || form == ZoneForm_func_button) && !(drawAll || (gA_ZoneCache[i].iFlags & ZF_ForceRender) > 0))
			{
				continue;
			}

			int colors[4];
			GetZoneColors(colors, type, track);

			DrawZone(
				gV_MapZones_Visual[i],
				colors,
				RoundToCeil(float(gI_MapZones) / iMaxZonesPerFrame + 2.0) * gCV_Interval.FloatValue,
				gA_ZoneSettings[type][track].fWidth,
				gA_ZoneSettings[type][track].bFlatZone,
				gV_ZoneCenter[i],
				gA_ZoneSettings[type][track].iBeam,
				gA_ZoneSettings[type][track].iHalo,
				track,
				type,
				gA_ZoneSettings[type][track].iSpeed,
				!!drawAll,
				0
			);

			if (++iDrawn % iMaxZonesPerFrame == 0)
			{
				return Plugin_Continue;
			}
		}
	}

	iCycle[drawAll] = 0;

	return Plugin_Continue;
}

void GetZoneColors(int colors[4], int type, int track, int customalpha = 0)
{
	colors[0] = gA_ZoneSettings[type][track].iRed;
	colors[1] = gA_ZoneSettings[type][track].iGreen;
	colors[2] = gA_ZoneSettings[type][track].iBlue;
	colors[3] = (customalpha > 0)? customalpha:gA_ZoneSettings[type][track].iAlpha;
}

public Action Timer_Draw(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0 || gI_MapStep[client] == 0)
	{
		Reset(client);

		for (int i = 1; i < MAXPLAYERS+1; i++)
		{
			if (gH_StupidTimer[i] == Timer)
			{
				gH_StupidTimer[i] = null;
				break;
			}
		}

		return Plugin_Stop;
	}

	float vPlayerOrigin[3];
	GetClientAbsOrigin(client, vPlayerOrigin);

	float origin[3];

	if(gB_CursorTracing[client])
	{
		origin = GetAimPosition(client);
	}
	else if(!(gB_SnapToWall[client] && SnapToWall(vPlayerOrigin, client, origin)))
	{
		origin = SnapToGrid(vPlayerOrigin, gI_GridSnap[client], false);
	}
	else
	{
		gV_WallSnap[client] = origin;
	}

	if (gI_MapStep[client] == 1 || gA_EditCache[client].fCorner2[0] == 0.0)
	{
		origin[2] = (vPlayerOrigin[2] + gCV_Height.FloatValue);
	}
	else
	{
		origin = gA_EditCache[client].fCorner2;
	}

	int type = gA_EditCache[client].iType; type = type < 0 ? 0 : type;
	int track = gA_EditCache[client].iTrack; track = track < 0 ? 0 : track;

	if (!EmptyVector(gA_EditCache[client].fCorner1) || !EmptyVector(gA_EditCache[client].fCorner2))
	{
		float points[8][3];
		points[0] = gA_EditCache[client].fCorner1;
		points[7] = origin;
		CreateZonePoints(points, false);

		// This is here to make the zone setup grid snapping be 1:1 to how it looks when done with the setup.
		origin = points[7];

		int colors[4];
		GetZoneColors(colors, type, track, 125);
		DrawZone(points, colors, 0.1, gA_ZoneSettings[type][track].fWidth, false, origin, gI_BeamSpriteIgnoreZ, gA_ZoneSettings[type][track].iHalo, track, type, gA_ZoneSettings[type][track].iSpeed, false, 0, gI_AdjustAxis[client]);

		if (gA_EditCache[client].iType == Zone_Teleport && !EmptyVector(gA_EditCache[client].fDestination))
		{
			TE_SetupEnergySplash(gA_EditCache[client].fDestination, ZERO_VECTOR, false);
			TE_SendToAll(0.0);
		}
	}

	if(gI_MapStep[client] != 3 && !EmptyVector(origin))
	{
		origin[2] -= gCV_Height.FloatValue;

		TE_SetupBeamPoints(vPlayerOrigin, origin, gI_BeamSpriteIgnoreZ, gA_ZoneSettings[type][track].iHalo, 0, 0, 0.1, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
		TE_SendToAll(0.0);

		// visualize grid snap
		float snap1[3];
		float snap2[3];

		for(int i = 0; i < 3; i++)
		{
			snap1 = origin;
			snap1[i] -= gI_GridSnap[client];

			snap2 = origin;
			snap2[i] += gI_GridSnap[client];

			TE_SetupBeamPoints(snap1, snap2, gI_BeamSpriteIgnoreZ, gA_ZoneSettings[type][track].iHalo, 0, 0, 0.1, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
			TE_SendToAll(0.0);
		}
	}

	return Plugin_Continue;
}

void DrawZone(float points[8][3], int color[4], float life, float width, bool flat, float center[3], int beam, int halo, int track, int type, int speed, bool drawallzones, int single_client, int editaxis=-1)
{
	static int pairs[][] =
	{
		{ 0, 2 },
		{ 2, 6 },
		{ 6, 4 },
		{ 4, 0 },
		{ 0, 1 },
		{ 3, 1 },
		{ 3, 2 },
		{ 3, 7 },
		{ 5, 1 },
		{ 5, 4 },
		{ 6, 7 },
		{ 7, 5 }
	};

	static int clrs[][4] =
	{
		{ 255, 255, 255, 255 }, // White
		{ 255, 0, 0, 255 }, // Red
		{ 255, 128, 0, 255 }, // Orange
		{ 255, 255 ,0, 255 }, // Yellow
		{ 0, 255, 0, 255}, // Green
		{ 0, 255, 255, 255 }, // Cyan
		{ 0, 0, 255, 255 }, // Blue
		{ 128, 0, 128, 255 }, // Purple
		{ 255, 192, 203, 255 }, // Pink
	};

	static float some_width[4] =
	{
		0.1, 0.5, 2.0, 8.0
	};

#if CZONE_VER == 'b'
	track = (track >= Track_Bonus) ? Track_Bonus : Track_Main;
#endif

	int clients[MAXPLAYERS+1];
	int count = 0;

	if (single_client)
	{
		clients[count++] = single_client;
	}
	else
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i) && (!drawallzones || (gB_DrawAllZones[i] && CanDrawAllZones(i))))
			{
				float eyes[3];
				GetClientEyePosition(i, eyes);

				if(gI_ZoneDisplayType[i][type][track] != ZoneDisplay_None &&
					(GetVectorDistance(eyes, center) <= 2048.0 ||
					(TR_TraceRayFilter(eyes, center, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_World) && !TR_DidHit())))
				{
					clients[count++] = i;
				}
			}
		}
	}

	if (editaxis != -1)
	{
		// The is generated with https://gist.github.com/rtldg/94fa32b7abb064e0e99dfbf0c73c1cda
		// The beam pairs array at the top of this function isn't useful for the order we want
		// for drawing the editaxis beams so that gist was used to help figure out which
		// beam indices go where, and then to make a fun little magic string out of it...
		char magic[] = "\x01\x132\x02EWvF\x04\x15&77&2v\x15\x04\x10T\x13W\x02F7\x151u&\x04 d#g\x01E";

		for (int j = 0; j < 12; j++)
		{
			float actual_width = (j >= 8) ? 0.5 : 1.0;
			char x = magic[editaxis*12+j];
			TE_SetupBeamPoints(points[x >> 4], points[x & 7], beam, halo, 0, 0, life, actual_width, actual_width, 0, 0.0, clrs[((j >= 8) ? ZoneColor_White : ZoneColor_Green) - 1], speed);
			TE_Send(clients, count, 0.0);
		}

		return;
	}

	for (int i = 0; i < count; i++)
	{
		int point_size = (gI_ZoneDisplayType[clients[i]][type][track] == ZoneDisplay_Flat ||
		                  gI_ZoneDisplayType[clients[i]][type][track] == ZoneDisplay_Default && flat) ? 4 : 12;

		int actual_color[4];
		actual_color = (gI_ZoneColor[clients[i]][type][track] == ZoneColor_Default) ? color : clrs[gI_ZoneColor[clients[i]][type][track] - 1];

		float actual_width = (gI_ZoneWidth[clients[i]][type][track] == ZoneWidth_Default) ? width : some_width[gI_ZoneWidth[clients[i]][type][track] - 1];

		for(int j = 0; j < point_size; j++)
		{
			TE_SetupBeamPoints(points[pairs[j][0]], points[pairs[j][1]], beam, halo, 0, 0, life, actual_width, actual_width, 0, 0.0, actual_color, speed);
			TE_SendToClient(clients[i], 0.0);
		}
	}
}

// original by blacky
// creates 3d box from 2 points
void CreateZonePoints(float point[8][3], bool prebuilt)
{
	float offset = -(prebuilt ? gCV_PrebuiltVisualOffset.FloatValue : 0.0) + gCV_Offset.FloatValue;

	// calculate all zone edges
	for(int i = 1; i < 7; i++)
	{
		for(int j = 0; j < 3; j++)
		{
			point[i][j] = point[((i >> (2 - j)) & 1) * 7][j];
		}
	}

	// apply beam offset
	if(offset != 0.0)
	{
		float center[2];
		center[0] = ((point[0][0] + point[7][0]) / 2);
		center[1] = ((point[0][1] + point[7][1]) / 2);

		for(int i = 0; i < 8; i++)
		{
			for(int j = 0; j < 2; j++)
			{
				if(point[i][j] < center[j])
				{
					point[i][j] += offset;
				}
				else if(point[i][j] > center[j])
				{
					point[i][j] -= offset;
				}
			}
		}
	}
}

public void Shavit_OnDatabaseLoaded()
{
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = Shavit_GetDatabase(gI_Driver);

	if (gB_YouCanLoadZonesNow && gCV_SQLZones.BoolValue)
	{
		RefreshZones();
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i))
		{
			GetStartPosition(i);
		}
	}
}

void ResetClientTargetNameAndClassName(int client, int track)
{
	char targetname[64];
	char classname[64];

	if (track == Track_Main)
	{
		gCV_ResetTargetnameMain.GetString(targetname, sizeof(targetname));
		gCV_ResetClassnameMain.GetString(classname, sizeof(classname));
	}
	else
	{
		gCV_ResetTargetnameBonus.GetString(targetname, sizeof(targetname));
		gCV_ResetClassnameBonus.GetString(classname, sizeof(classname));
	}

	DispatchKeyValue(client, "targetname", targetname);

	if (!classname[0])
	{
		classname = "player";
	}

	SetEntPropString(client, Prop_Data, "m_iClassname", classname);
}

public Action Shavit_OnStart(int client, int track)
{
	if(gCV_ForceTargetnameReset.BoolValue)
	{
		ResetClientTargetNameAndClassName(client, track);
	}

	return Plugin_Continue;
}

public void Shavit_OnRestart(int client, int track)
{
	gI_LastStage[client] = 0;

	if (!IsPlayerAlive(client))
	{
		return;
	}

	int iIndex = GetZoneIndex(Zone_Start, track);

	if(gCV_TeleportToStart.BoolValue)
	{
		bool bCustomStart = gB_HasSetStart[client][track] && !gB_StartAnglesOnly[client][track];
		bool use_CustomStart_over_CustomSpawn = (iIndex != -1) && bCustomStart;

		// custom spawns
		if (!use_CustomStart_over_CustomSpawn && !EmptyVector(gF_CustomSpawn[track]))
		{
			float pos[3]; pos = gF_CustomSpawn[track]; pos[2] += 1.0;
			TeleportEntity(client, pos, NULL_VECTOR, ZERO_VECTOR);
		}
		// standard zoning
		else if (bCustomStart || iIndex != -1)
		{
			float fCenter[3];

			if (bCustomStart)
			{
				fCenter = gF_StartPos[client][track];
			}
			else
			{
				fCenter[0] = gV_ZoneCenter[iIndex][0];
				fCenter[1] = gV_ZoneCenter[iIndex][1];
				fCenter[2] = gA_ZoneCache[iIndex].fCorner1[2] + gCV_ExtraSpawnHeight.FloatValue;
			}

			fCenter[2] += 1.0;

			TeleportEntity(client, fCenter, gB_HasSetStart[client][track] ? gF_StartAng[client][track] : NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));

			if (gB_ReplayRecorder && gB_HasSetStart[client][track])
			{
				Shavit_HijackAngles(client, gF_StartAng[client][track][0], gF_StartAng[client][track][1], -1, true);
			}

			if (!gB_HasSetStart[client][track] || gB_StartAnglesOnly[client][track])
			{
				ResetClientTargetNameAndClassName(client, track);
				// normally StartTimer will happen on zone-touch BUT we have this here for zones that are in the air
				bool skipGroundCheck = true;
				Shavit_StartTimer(client, track, skipGroundCheck);
			}
		}
		// kz buttons
		else if (Shavit_IsKZMap(track))
		{
			if (EmptyVector(gF_ClimbButtonCache[client][track][0]) || EmptyVector(gF_ClimbButtonCache[client][track][1]))
			{
				return;
			}

			TeleportEntity(client, gF_ClimbButtonCache[client][track][0], gF_ClimbButtonCache[client][track][1], view_as<float>({0.0, 0.0, 0.0}));

			return;
		}
	}

	if (iIndex != -1)
	{
		int colors[4];
		GetZoneColors(colors, Zone_Start, track);

		DrawZone(
			gV_MapZones_Visual[iIndex],
			colors,
			gCV_Interval.FloatValue,
			gA_ZoneSettings[Zone_Start][track].fWidth,
			gA_ZoneSettings[Zone_Start][track].bFlatZone,
			gV_ZoneCenter[iIndex],
			gA_ZoneSettings[Zone_Start][track].iBeam,
			gA_ZoneSettings[Zone_Start][track].iHalo,
			track,
			Zone_Start,
			gA_ZoneSettings[Zone_Start][track].iSpeed,
			false,
			client
		);
	}
}

public void Shavit_OnEnd(int client, int track)
{
	int iIndex = GetZoneIndex(Zone_End, track);

	if(gCV_TeleportToEnd.BoolValue)
	{
		if(iIndex != -1)
		{
			float fCenter[3];
			fCenter[0] = gV_ZoneCenter[iIndex][0];
			fCenter[1] = gV_ZoneCenter[iIndex][1];
			fCenter[2] = gA_ZoneCache[iIndex].fCorner1[2] + 1.0; // no stuck in floor please

			TeleportEntity(client, fCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}
	}

	if (iIndex != -1)
	{
		int colors[4];
		GetZoneColors(colors, Zone_End, track);

		DrawZone(
			gV_MapZones_Visual[iIndex],
			colors,
			gCV_Interval.FloatValue,
			gA_ZoneSettings[Zone_End][track].fWidth,
			gA_ZoneSettings[Zone_End][track].bFlatZone,
			gV_ZoneCenter[iIndex],
			gA_ZoneSettings[Zone_End][track].iBeam,
			gA_ZoneSettings[Zone_End][track].iHalo,
			track,
			Zone_End,
			gA_ZoneSettings[Zone_End][track].iSpeed,
			false,
			client
		);
	}
}

bool EmptyVector(float vec[3])
{
	return (IsNullVector(vec) || (vec[0] == 0.0 && vec[1] == 0.0 && vec[2] == 0.0));
}

// returns -1 if there's no zone
int GetZoneIndex(int type, int track, int start = 0)
{
	for(int i = start; i < gI_MapZones; i++)
	{
		if (gA_ZoneCache[i].iForm == ZoneForm_func_button)
			continue;

		if (gA_ZoneCache[i].iType == type && (gA_ZoneCache[i].iTrack == track || track == -1))
		{
			return i;
		}
	}

	return -1;
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	Reset(GetClientOfUserId(event.GetInt("userid")));
}

public void Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	int empty_InsideZone[TRACKS_SIZE];
	bool empty_InsideZoneID[MAX_ZONES];

	for (int i = 1; i <= MaxClients; i++)
	{
		gI_InsideZone[i] = empty_InsideZone;
		gB_InsideZoneID[i] = empty_InsideZoneID;
	}
}

float Abs(float input)
{
	if(input < 0.0)
	{
		return -input;
	}

	return input;
}

void SetZoneMinsMaxs(int zone)
{
	float offsets[2]; // 0 = x/y width. 1 = z height.

	if (gCV_BoxOffset.FloatValue != 0.0)
	{
		if (gEV_Type == Engine_CSS)
		{
			offsets[0] = 32.0 / 2.0;
			offsets[1] = 62.0 / 2.0;
		}
		else if (gEV_Type == Engine_CSGO)
		{
			offsets[0] = 32.0 / 2.0;
			offsets[1] = 72.0 / 2.0;
		}
		else if (gEV_Type == Engine_TF2)
		{
			offsets[0] = 48.0 / 2.0;
			offsets[1] = 82.0 / 2.0;
		}
	}

	float mins[3], maxs[3];

	for (int i = 0; i < 3; i++)
	{
		float offset = offsets[i/2];
#if 1
		maxs[i] = Abs(gA_ZoneCache[zone].fCorner1[i] - gA_ZoneCache[zone].fCorner2[i]) / 2.0;
		if (maxs[i] > offset) maxs[i] -= offset;
#else // maybe this would be good?
		maxs[i] = Abs(gA_ZoneCache[zone].fCorner1[i] - gA_ZoneCache[zone].fCorner2[i]) / 2.0 - offset;
		if (maxs[i] < 1.0) maxs[i] = 1.0;
#endif
		mins[i] = -maxs[i];
	}

	SetEntPropVector(gA_ZoneCache[zone].iEntity, Prop_Send, "m_vecMins", mins);
	SetEntPropVector(gA_ZoneCache[zone].iEntity, Prop_Send, "m_vecMaxs", maxs);
}

public MRESReturn DHooks_OnTeleport(int pThis, DHookParam hParams)
{
	if (!IsValidEntity(pThis) || !IsClientInGame(pThis))
	{
		return MRES_Ignored;
	}

	if (!hParams.IsNull(1))
	{
		gI_LatestTeleportTick[pThis] = GetGameTickCount();
	}

	return MRES_Ignored;
}

void PhysicsRemoveTouchedList(int client)
{
	SDKCall(gH_PhysicsRemoveTouchedList, client);
}

void ACTUALLY_ForcePlayerSuicide(int client)
{
	SDKCall(gH_CommitSuicide, client, false, true);
}

public void StartTouchPost(int entity, int other)
{
	if (other < 1 || other > MaxClients || IsFakeClient(other))
		return;

	int zone = gI_EntityZone[entity];

	if (zone == -1)
		return;

	int type = gA_ZoneCache[zone].iType;
	int track = gA_ZoneCache[zone].iTrack;

	// todo: do this after the inside-zone is set?
	if (gCV_EnforceTracks.BoolValue && type > Zone_End && track != Shavit_GetClientTrack(other))
		return;

	if (gA_ZoneCache[zone].iForm == ZoneForm_trigger_multiple || gA_ZoneCache[zone].iForm == ZoneForm_trigger_teleport)
	{
		if (!SDKCall(gH_PassesTriggerFilters, entity, other))
		{
			return;
		}
	}

	TimerStatus status = Shavit_GetTimerStatus(other);

	switch (type)
	{
		case Zone_Respawn:
		{
			CS_RespawnPlayer(other);
		}

		case Zone_Teleport:
		{
			TeleportEntity(other, gA_ZoneCache[zone].fDestination, NULL_VECTOR, NULL_VECTOR);
		}

		case Zone_Slay:
		{
			if (status == Timer_Running)
			{
				Shavit_StopTimer(other);
				ACTUALLY_ForcePlayerSuicide(other);
				Shavit_PrintToChat(other, "%T", "ZoneSlayEnter", other, gS_ChatStrings.sWarning, gS_ChatStrings.sVariable2, gS_ChatStrings.sWarning);
			}
		}

		case Zone_Stop:
		{
			if(status == Timer_Running)
			{
				Shavit_StopTimer(other);
				Shavit_PrintToChat(other, "%T", "ZoneStopEnter", other, gS_ChatStrings.sWarning, gS_ChatStrings.sVariable2, gS_ChatStrings.sWarning);
			}
		}

		case Zone_End:
		{
			if (status == Timer_Running && Shavit_GetClientTrack(other) == track)
			{
				Shavit_FinishMap(other, track);
			}
		}

		case Zone_Stage:
		{
			int num = gA_ZoneCache[zone].iData;
			int iStyle = Shavit_GetBhopStyle(other);
			bool bTASSegments = Shavit_GetStyleSettingBool(iStyle, "tas") || Shavit_GetStyleSettingBool(iStyle, "segments");

			if (status == Timer_Running && Shavit_GetClientTrack(other) == track && (num > gI_LastStage[other] || bTASSegments || Shavit_IsPracticeMode(other)))
			{
				gI_LastStage[other] = num;
				char sTime[32];
				FormatSeconds(Shavit_GetClientTime(other), sTime, 32, true);

				char sMessage[255];
				FormatEx(sMessage, 255, "%T", "ZoneStageEnter", other, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, num, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText);

				Action aResult = Plugin_Continue;
				Call_StartForward(gH_Forwards_StageMessage);
				Call_PushCell(other);
				Call_PushCell(num);
				Call_PushStringEx(sMessage, 255, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
				Call_PushCell(255);
				Call_Finish(aResult);

				if(aResult < Plugin_Handled)
				{
					Shavit_PrintToChat(other, "%s", sMessage);
				}
			}
		}

		case Zone_Speedmod:
		{
			char s[16];
			FloatToString(view_as<float>(gA_ZoneCache[zone].iData), s, sizeof(s));
			SetVariantString(s);
			AcceptEntityInput(entity, "ModifySpeed", other, entity, 0);
		}
	}

	gI_InsideZone[other][track] |= (1 << type);
	gB_InsideZoneID[other][zone] = true;

	Call_StartForward(gH_Forwards_EnterZone);
	Call_PushCell(other);
	Call_PushCell(type);
	Call_PushCell(track);
	Call_PushCell(zone);
	Call_PushCell(entity);
	Call_PushCell(gA_ZoneCache[zone].iData);
	Call_Finish();
}

public Action SameTrack_StartTouch_er(int entity, int other)
{
	if (other < 1 || other > MaxClients || IsFakeClient(other))
		return Plugin_Stop;

	int zone = gI_EntityZone[entity];

	if (zone == -1 || gA_ZoneCache[zone].iTrack != Shavit_GetClientTrack(other))
		return Plugin_Stop;

	return Plugin_Continue;
}

public void EndTouchPost(int entity, int other)
{
	if (other < 1 || other > MaxClients || IsFakeClient(other))
		return;

	int entityzone = gI_EntityZone[entity];

	if (entityzone == -1)
		return;

	int type = gA_ZoneCache[entityzone].iType;
	int track = gA_ZoneCache[entityzone].iTrack;

	if (type < 0 || track < 0) // odd
	{
		return;
	}

	gB_InsideZoneID[other][entityzone] = false;
	RecalcInsideZone(other);

	if (type == Zone_Speedmod)
	{
		SetVariantString("1.0");
		AcceptEntityInput(entity, "ModifySpeed", other, entity, 0);
	}

	Call_StartForward(gH_Forwards_LeaveZone);
	Call_PushCell(other);
	Call_PushCell(type);
	Call_PushCell(track);
	Call_PushCell(entityzone);
	Call_PushCell(entity);
	Call_PushCell(gA_ZoneCache[entityzone].iData);
	Call_Finish();
}

public void TouchPost(int entity, int other)
{
	if (other < 1 || other > MaxClients || IsFakeClient(other))
		return;

	int zone = gI_EntityZone[entity];

	if (zone == -1)
		return;

	int type = gA_ZoneCache[zone].iType;
	int track = gA_ZoneCache[zone].iTrack;

	if (gCV_EnforceTracks.BoolValue && type > Zone_End && track != Shavit_GetClientTrack(other))
		return;

	if (gA_ZoneCache[zone].iForm == ZoneForm_trigger_multiple || gA_ZoneCache[zone].iForm == ZoneForm_trigger_teleport)
	{
		if (!SDKCall(gH_PassesTriggerFilters, entity, other))
		{
			return;
		}
	}

	// do precise stuff here, this will be called *A LOT*
	switch (type)
	{
		case Zone_Start:
		{
			if (gB_Eventqueuefix)
			{
				static int tick_served[MAXPLAYERS + 1];
				int curr_tick = GetGameTickCount();

				// GAMMACASE: This prevents further abuses related to external events being ran after you teleport from the trigger, with events setup, outside the start zone into the start zone.
				// This accounts for the io events that might be set inside the start zone trigger in OnStartTouch and wont reset them!
				// Logic behind this code is that all events in this chain are not instantly fired, so checking if there were teleport from the outside of a start zone in last couple of ticks
				// and doing PhysicsRemoveTouchedList() now to trigger all OnEndTouch that should happen at the same tick but later and removing them allows further events from OnStartTouch be separated
				// and be fired after which is the expected and desired effect.
				// This also kills all ongoing events that were active on the client prior to the teleportation to start and also resets targetname and classname
				// before the OnStartTouch from triggers in start zone are run, thus preventing the maps to be abusable if they don't have any reset triggers in place
				if (gI_LatestTeleportTick[other] <= curr_tick <= gI_LatestTeleportTick[other] + 4)
				{
					if (curr_tick != tick_served[other])
					{
						ResetClientTargetNameAndClassName(other, track);

						PhysicsRemoveTouchedList(other);
						ClearClientEvents(other);

						tick_served[other] = curr_tick;
					}

					return;
				}
				else if (curr_tick != tick_served[other])
				{
					tick_served[other] = 0;
				}
			}

#if 0
			if (GetEntPropEnt(other, Prop_Send, "m_hGroundEntity") == -1 && !Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(other), "startinair"))
			{
				return;
			}
#endif

			// start timer instantly for main track, but require bonuses to have the current timer stopped
			// so you don't accidentally step on those while running
			if (Shavit_GetTimerStatus(other) == Timer_Stopped || Shavit_GetClientTrack(other) != Track_Main)
			{
				Shavit_StartTimer(other, track);
			}
			else if (track == Track_Main)
			{
				Shavit_StartTimer(other, Track_Main);
			}
		}
		case Zone_Respawn:
		{
			CS_RespawnPlayer(other);
		}
		case Zone_Teleport:
		{
			TeleportEntity(other, gA_ZoneCache[zone].fDestination, NULL_VECTOR, NULL_VECTOR);
		}
		case Zone_Slay:
		{
			TimerStatus status = Shavit_GetTimerStatus(other);

			if (status != Timer_Stopped)
			{
				Shavit_StopTimer(other);
				ACTUALLY_ForcePlayerSuicide(other);
				Shavit_PrintToChat(other, "%T", "ZoneSlayEnter", other, gS_ChatStrings.sWarning, gS_ChatStrings.sVariable2, gS_ChatStrings.sWarning);
			}
		}
		case Zone_Stop:
		{
			if(Shavit_GetTimerStatus(other) != Timer_Stopped)
			{
				Shavit_StopTimer(other);
				Shavit_PrintToChat(other, "%T", "ZoneStopEnter", other, gS_ChatStrings.sWarning, gS_ChatStrings.sVariable2, gS_ChatStrings.sWarning);
			}
		}
	}
}

public void UsePost_HookedButton(int entity, int activator, int caller, UseType type, float value)
{
	if (activator < 1 || activator > MaxClients || IsFakeClient(activator))
	{
		return;
	}

	int zone = gI_EntityZone[entity];

	if (zone > -1)
	{
		ButtonLogic(activator, gA_ZoneCache[zone].iType, gA_ZoneCache[zone].iTrack);
	}
}

void ButtonLogic(int activator, int type, int track)
{
	if (type == Zone_Start)
	{
		if (GetEntPropEnt(activator, Prop_Send, "m_hGroundEntity") == -1)
		{
			return;
		}

		GetClientAbsOrigin(activator, gF_ClimbButtonCache[activator][track][0]);
		GetClientEyeAngles(activator, gF_ClimbButtonCache[activator][track][1]);

		Shavit_StartTimer(activator, track);
	}
	else if (type == Zone_End && !Shavit_IsPaused(activator) && Shavit_GetTimerStatus(activator) == Timer_Running && Shavit_GetClientTrack(activator) == track)
	{
		Shavit_FinishMap(activator, track);
	}
}
