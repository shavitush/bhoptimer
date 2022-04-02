/*
 * shavit's Timer - Map Zones
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
#include <clientprefs>
#include <sdktools>
#include <sdkhooks>
#include <convar_class>
#include <dhooks>

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

EngineVersion gEV_Type = Engine_Unknown;

Database2 gH_SQL = null;
bool gB_Connected = false;
bool gB_MySQL = false;
bool gB_InsertedPrebuiltZones = false;
bool gB_PrecachedStuff = false;

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
	char sBeam[PLATFORM_MAX_PATH];
}

// 0 - nothing
// 1 - wait for E tap to setup first coord
// 2 - wait for E tap to setup second coord
// 3 - confirm
int gI_MapStep[MAXPLAYERS+1];
int gI_ZoneFlags[MAXPLAYERS+1];
int gI_ZoneData[MAXPLAYERS+1];
int gI_ZoneTrack[MAXPLAYERS+1];
int gI_ZoneType[MAXPLAYERS+1];
int gI_ZoneDatabaseID[MAXPLAYERS+1];
int gI_ZoneID[MAXPLAYERS+1];
bool gB_WaitingForChatInput[MAXPLAYERS+1];
float gV_Point1[MAXPLAYERS+1][3];
float gV_Point2[MAXPLAYERS+1][3];
float gV_Teleport[MAXPLAYERS+1][3];
float gV_WallSnap[MAXPLAYERS+1][3];
bool gB_Button[MAXPLAYERS+1];
bool gB_HackyResetCheck[MAXPLAYERS+1];

float gF_Modifier[MAXPLAYERS+1];
int gI_GridSnap[MAXPLAYERS+1];
bool gB_SnapToWall[MAXPLAYERS+1];
bool gB_CursorTracing[MAXPLAYERS+1];

int gI_LatestTeleportTick[MAXPLAYERS+1];

// player zone status
bool gB_InsideZone[MAXPLAYERS+1][ZONETYPES_SIZE][TRACKS_SIZE];
bool gB_InsideZoneID[MAXPLAYERS+1][MAX_ZONES];

// zone cache
zone_settings_t gA_ZoneSettings[ZONETYPES_SIZE][TRACKS_SIZE];
zone_cache_t gA_ZoneCache[MAX_ZONES]; // Vectors will not be inside this array.
int gI_MapZones = 0;
float gV_MapZones[MAX_ZONES][2][3];
float gV_MapZones_Visual[MAX_ZONES][8][3];
float gV_Destinations[MAX_ZONES][3];
float gV_ZoneCenter[MAX_ZONES][3];
int gI_StageZoneID[TRACKS_SIZE][MAX_ZONES];
int gI_HighestStage[TRACKS_SIZE];
float gF_CustomSpawn[TRACKS_SIZE][3];
int gI_EntityZone[4096];
int gI_LastStage[MAXPLAYERS+1];

char gS_BeamSprite[PLATFORM_MAX_PATH];
char gS_BeamSpriteIgnoreZ[PLATFORM_MAX_PATH];
int gI_BeamSpriteIgnoreZ;

// admin menu
TopMenu gH_AdminMenu = null;
TopMenuObject gH_TimerCommands = INVALID_TOPMENUOBJECT;

// misc cache
bool gB_ZoneCreationQueued = false;
bool gB_Late = false;
ConVar sv_gravity = null;

// cvars
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
Handle gH_Forwards_StageMessage = null;

// sdkcalls
Handle gH_PhysicsRemoveTouchedList = null;

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

// custom zone stuff
Cookie gH_CustomZoneCookie = null;
int gI_ZoneDisplayType[MAXPLAYERS+1][ZONETYPES_SIZE][TRACKS_SIZE];
int gI_ZoneColor[MAXPLAYERS+1][ZONETYPES_SIZE][TRACKS_SIZE];
int gI_ZoneWidth[MAXPLAYERS+1][ZONETYPES_SIZE][TRACKS_SIZE];

int gI_LastMenuPos[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "[shavit] Map Zones",
	author = "shavit",
	description = "Map zones for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// zone natives
	CreateNative("Shavit_GetZoneData", Native_GetZoneData);
	CreateNative("Shavit_GetZoneFlags", Native_GetZoneFlags);
	CreateNative("Shavit_GetStageZone", Native_GetStageZone);
	CreateNative("Shavit_GetStageCount", Native_GetStageCount);
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

	RegAdminCmd("sm_tptozone", Command_TpToZone, ADMFLAG_RCON, "Teleport to a zone");

	RegAdminCmd("sm_reloadzonesettings", Command_ReloadZoneSettings, ADMFLAG_ROOT, "Reloads the zone settings.");

	RegConsoleCmd("sm_stages", Command_Stages, "Opens the stage menu. Usage: sm_stages [stage #]");
	RegConsoleCmd("sm_stage", Command_Stages, "Opens the stage menu. Usage: sm_stage [stage #]");
	RegConsoleCmd("sm_s", Command_Stages, "Opens the stage menu. Usage: sm_s [stage #]");

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

	for (int i = 0; i <= 9; i++)
	{
		char cmd[10], helptext[50];
		FormatEx(cmd, sizeof(cmd), "sm_s%d", i);
		FormatEx(helptext, sizeof(helptext), "Go to stage %d", i);
		RegConsoleCmd(cmd, Command_Stages, helptext);
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
	gH_Forwards_StageMessage = CreateGlobalForward("Shavit_OnStageMessage", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);

	// cvars and stuff
	gCV_Interval = new Convar("shavit_zones_interval", "1.0", "Interval between each time a mapzone is being drawn to the players.", 0, true, 0.25, true, 5.0);
	gCV_TeleportToStart = new Convar("shavit_zones_teleporttostart", "1", "Teleport players to the start zone on timer restart?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_TeleportToEnd = new Convar("shavit_zones_teleporttoend", "1", "Teleport players to the end zone on sm_end?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_AllowDrawAllZones = new Convar("shavit_zones_allowdrawallzones", "1", "Allow players to use !drawallzones to see all zones regardless of zone visibility settings.\n0 - nobody can use !drawallzones\n1 - admins (sm_zones access) can use !drawallzones\n2 - anyone can use !drawallzones", 0, true, 0.0, true, 2.0);
	gCV_UseCustomSprite = new Convar("shavit_zones_usecustomsprite", "1", "Use custom sprite for zone drawing?\nSee `configs/shavit-zones.cfg`.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_Height = new Convar("shavit_zones_height", "128.0", "Height to use for the start zone.", 0, true, 0.0, false);
	gCV_Offset = new Convar("shavit_zones_offset", "1.0", "When calculating a zone's *VISUAL* box, by how many units, should we scale it to the center?\n0.0 - no downscaling. Values above 0 will scale it inward and negative numbers will scale it outwards.\nAdjust this value if the zones clip into walls.");
	gCV_EnforceTracks = new Convar("shavit_zones_enforcetracks", "1", "Enforce zone tracks upon entry?\n0 - allow every zone except for start/end to affect users on every zone.\n1 - require the user's track to match the zone's track.", 0, true, 0.0, true, 1.0);
	gCV_BoxOffset = new Convar("shavit_zones_box_offset", "16", "Offset zone trigger boxes by this many unit\n0 - matches players bounding box\n16 - matches players center");
	gCV_ExtraSpawnHeight = new Convar("shavit_zones_extra_spawn_height", "0.0", "YOU DONT NEED TO TOUCH THIS USUALLY. FIX YOUR ACTUAL ZONES.\nUsed to fix some shit prebuilt zones that are in the ground like bhop_strafecontrol");
	gCV_PrebuiltVisualOffset = new Convar("shavit_zones_prebuilt_visual_offset", "0", "YOU DONT NEED TO TOUCH THIS USUALLY.\nUsed to fix the VISUAL beam offset for prebuilt zones on a map.\nExample maps you'd want to use 16 on: bhop_tranquility and bhop_amaranthglow");

	gCV_ForceTargetnameReset = new Convar("shavit_zones_forcetargetnamereset", "0", "Reset the player's targetname upon timer start?\nRecommended to leave disabled. Enable via per-map configs when necessary.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_ResetTargetnameMain = new Convar("shavit_zones_resettargetname_main", "", "What targetname to use when resetting the player.\nWould be applied once player teleports to the start zone or on every start if shavit_zones_forcetargetnamereset cvar is set to 1.\nYou don't need to touch this");
	gCV_ResetTargetnameBonus = new Convar("shavit_zones_resettargetname_bonus", "", "What targetname to use when resetting the player (on bonus tracks).\nWould be applied once player teleports to the start zone or on every start if shavit_zones_forcetargetnamereset cvar is set to 1.\nYou don't need to touch this");
	gCV_ResetClassnameMain = new Convar("shavit_zones_resetclassname_main", "", "What classname to use when resetting the player.\nWould be applied once player teleports to the start zone or on every start if shavit_zones_forcetargetnamereset cvar is set to 1.\nYou don't need to touch this");
	gCV_ResetClassnameBonus = new Convar("shavit_zones_resetclassname_bonus", "", "What classname to use when resetting the player (on bonus tracks).\nWould be applied once player teleports to the start zone or on every start if shavit_zones_forcetargetnamereset cvar is set to 1.\nYou don't need to touch this");

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

	for(int i = 0; i < sizeof(gI_EntityZone); i++)
	{
		gI_EntityZone[i] = -1;
	}

	gB_ReplayRecorder = LibraryExists("shavit-replay-recorder");
	gB_Eventqueuefix = LibraryExists("eventqueuefix");

	if (gB_Late)
	{
		Shavit_OnChatConfigLoaded();
		Shavit_OnDatabaseLoaded();

		for(int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i))
			{
				OnClientConnected(i);
				OnClientPutInServer(i);

				if (AreClientCookiesCached(i) && !IsFakeClient(i))
				{
					OnClientCookiesCached(i);
				}
			}
		}
	}
}

public void OnPluginEnd()
{
	UnloadZones(0);
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
	
	delete hGameData;
}

public void OnAllPluginsLoaded()
{
	// admin menu
	if(LibraryExists("adminmenu") && ((gH_AdminMenu = GetAdminTopMenu()) != null))
	{
		OnAdminMenuReady(gH_AdminMenu);
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
		gH_DrawVisible = CreateTimer(gCV_Interval.FloatValue, Timer_DrawVisible, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		gH_DrawAllZones = CreateTimer(gCV_Interval.FloatValue, Timer_DrawAllZones, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	else if ((convar == gCV_Offset || convar == gCV_PrebuiltVisualOffset) && gI_MapZones > 0)
	{
		for(int i = 0; i < gI_MapZones; i++)
		{
			if(!gA_ZoneCache[i].bZoneInitialized)
			{
				continue;
			}

			gV_MapZones_Visual[i][0][0] = gV_MapZones[i][0][0];
			gV_MapZones_Visual[i][0][1] = gV_MapZones[i][0][1];
			gV_MapZones_Visual[i][0][2] = gV_MapZones[i][0][2];
			gV_MapZones_Visual[i][7][0] = gV_MapZones[i][1][0];
			gV_MapZones_Visual[i][7][1] = gV_MapZones[i][1][1];
			gV_MapZones_Visual[i][7][2] = gV_MapZones[i][1][2];

			float offset = -(gA_ZoneCache[i].bPrebuilt ? gCV_PrebuiltVisualOffset.FloatValue : 0.0) + gCV_Offset.FloatValue;
			CreateZonePoints(gV_MapZones_Visual[i], offset);
		}
	}
	else if(convar == gCV_UseCustomSprite && !StrEqual(oldValue, newValue))
	{
		LoadZoneSettings();
	}
	else if (convar == gCV_BoxOffset)
	{
		CreateZoneEntities(false);
	}
}

public void OnAdminMenuCreated(Handle topmenu)
{
	if(gH_AdminMenu == null || (topmenu == gH_AdminMenu && gH_TimerCommands != INVALID_TOPMENUOBJECT))
	{
		return;
	}

	if ((gH_TimerCommands = gH_AdminMenu.FindCategory("Timer Commands")) != INVALID_TOPMENUOBJECT)
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

		gH_AdminMenu.AddItem("sm_zones", AdminMenu_Zones, gH_TimerCommands, "sm_zones", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_deletezone", AdminMenu_DeleteZone, gH_TimerCommands, "sm_deletezone", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_deleteallzones", AdminMenu_DeleteAllZones, gH_TimerCommands, "sm_deleteallzones", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_zoneedit", AdminMenu_ZoneEdit, gH_TimerCommands, "sm_zoneedit", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_tptozone", AdminMenu_TpToZone, gH_TimerCommands, "sm_tptozone", ADMFLAG_RCON);
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

public int Native_ZoneExists(Handle handler, int numParams)
{
	return (GetZoneIndex(GetNativeCell(1), GetNativeCell(2)) != -1);
}

public int Native_GetZoneData(Handle handler, int numParams)
{
	return gA_ZoneCache[GetNativeCell(1)].iZoneData;
}

public int Native_GetZoneFlags(Handle handler, int numParams)
{
	return gA_ZoneCache[GetNativeCell(1)].iZoneFlags;
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

	for(int i = 0; i < MAX_ZONES; i++)
	{
		if(gB_InsideZoneID[client][i] &&
			gA_ZoneCache[i].iZoneType == iType &&
			(gA_ZoneCache[i].iZoneTrack == iTrack || iTrack == -1))
		{
			SetNativeCellRef(4, i);

			return true;
		}
	}

	return false;
}

public int Native_GetStageZone(Handle handler, int numParams)
{
	int iStageNumber = GetNativeCell(1);
	int iTrack = GetNativeCell(2);
	return gI_StageZoneID[iTrack][iStageNumber];
}

public int Native_GetStageCount(Handle handler, int numParas)
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
	gH_SQL.Query2(SQL_DeleteMap_Callback, sQuery, StrEqual(gS_Map, sMap, false), DBPrio_High);
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
		OnMapStart();
	}
}

bool InsideZone(int client, int type, int track)
{
	if(track != -1)
	{
		return gB_InsideZone[client][type][track];
	}
	else
	{
		for(int i = 0; i < TRACKS_SIZE; i++)
		{
			if(gB_InsideZone[client][type][i])
			{
				return true;
			}
		}
	}

	return false;
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
	return gA_ZoneCache[zoneid].iZoneTrack;
}

public any Native_GetZoneType(Handle plugin, int numParams)
{
	int zoneid = GetNativeCell(1);
	return gA_ZoneCache[zoneid].iZoneType;
}

public any Native_GetZoneID(Handle plugin, int numParams)
{
	int entity = GetNativeCell(1);
	return gI_EntityZone[entity];
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
	if (!gB_PrecachedStuff)
	{
		GetLowercaseMapName(gS_Map);
		LoadZoneSettings();

		if (gEV_Type == Engine_TF2)
		{
			PrecacheModel("models/error.mdl");
		}
		else
		{
			PrecacheModel("models/props/cs_office/vending_machine.mdl");
		}

		gB_PrecachedStuff = true;
	}

	if(!gB_Connected)
	{
		return;
	}

	UnloadZones(0);
	RefreshZones();

	// start drawing mapzones here
	if(gH_DrawAllZones == null)
	{
		gH_DrawVisible = CreateTimer(gCV_Interval.FloatValue, Timer_DrawVisible, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		gH_DrawAllZones = CreateTimer(gCV_Interval.FloatValue, Timer_DrawAllZones, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && !IsFakeClient(i))
		{
			GetStartPosition(i);
		}
	}
}

public void OnMapEnd()
{
	gB_PrecachedStuff = false;
	gB_InsertedPrebuiltZones = false;
	delete gH_DrawVisible;
	delete gH_DrawAllZones;
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
	if(StrEqual(classname, "func_button", false))
	{
		RequestFrame(Frame_HookButton, EntIndexToEntRef(entity));
	}
	else if(StrEqual(classname, "trigger_multiple", false))
	{
		RequestFrame(Frame_HookTrigger, EntIndexToEntRef(entity));
	}
}

public void OnEntityDestroyed(int entity)
{
	if (entity > MaxClients && entity < 4096 && gI_EntityZone[entity] > -1)
	{
		KillZoneEntity(gI_EntityZone[entity], false);

		if (!gB_ZoneCreationQueued)
		{
			RequestFrame(CreateZoneEntities, true);
			gB_ZoneCreationQueued = true;
		}
	}
}

bool GetButtonInfo(int entity, int& zone, int& track)
{
	char sName[32];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, 32);

	if(StrContains(sName, "climb_") == -1)
	{
		return false;
	}

	if(StrContains(sName, "startbutton") != -1)
	{
		zone = Zone_Start;
	}
	else if(StrContains(sName, "endbutton") != -1)
	{
		zone = Zone_End;
	}
	else
	{
		return false;
	}

	int bonus = StrContains(sName, "bonus");

	if (bonus != -1)
	{
		track = Track_Bonus;

		if ('0' <= sName[bonus+5] <= '9')
		{
			track = StringToInt(sName[bonus+5]);

			if (track < Track_Bonus || track > Track_Bonus_Last)
			{
				LogError("invalid track in climb button (%s) on %s", sName, gS_Map);
				return false;
			}
		}
	}
	else
	{
		track = Track_Main;
	}

	return true;
}

public void Frame_HookButton(any data)
{
	int entity = EntRefToEntIndex(data);

	if(entity == INVALID_ENT_REFERENCE)
	{
		return;
	}

	int zone = -1;
	int track = Track_Main;

	if (!GetButtonInfo(entity, zone, track))
	{
		return;
	}

	Shavit_MarkKZMap(track);
	SDKHook(entity, SDKHook_UsePost, UsePost);
}

bool parse_mod_zone(char sName[32], int& zone, int& track, int& zonedata)
{
	// Please follow this naming scheme for this zones https://github.com/PMArkive/fly#trigger_multiple
	// mod_zone_start
	// mod_zone_end
	// mod_zone_checkpoint_X
	// mod_zone_bonus_X_start
	// mod_zone_bonus_X_end
	// mod_zone_bonus_X_checkpoint_X

	// Normalize some zone names that bhop_somp_island and bhop_overthinker use
	if (StrEqual(sName, "mod_zone_start_bonus") || StrEqual(sName, "mod_zone_bonus_start"))
	{
		sName = "mod_zone_bonus_1_start";
	}
	else if (StrEqual(sName, "mod_zone_end_bonus") || StrEqual(sName, "mod_zone_bonus_end"))
	{
		sName = "mod_zone_bonus_1_end";
	}

	if (StrContains(sName, "start") != -1)
	{
		zone = Zone_Start;
	}
	else if (StrContains(sName, "end") != -1)
	{
		zone = Zone_End;
	}

	if (StrContains(sName, "bonus") != -1 || StrContains(sName, "checkpoint") != -1)
	{
		char sections[8][12];
		ExplodeString(sName, "_", sections, 8, 12, false);

		int iCheckpointIndex = 3; // mod_zone_checkpoint_X

		if (StrContains(sName, "bonus") != -1)
		{
			iCheckpointIndex = 5; // mod_zone_bonus_X_checkpoint_X

			track = StringToInt(sections[3]); // 0 on failure to parse. 0 is less than Track_Bonus

			if (track < Track_Bonus || track > Track_Bonus_Last)
			{
				LogError("invalid track in prebuilt map zone (%s) on %s", sName, gS_Map);
				return false;
			}
		}

		if (StrContains(sName, "checkpoint") != -1)
		{
			zone = Zone_Stage;
			zonedata = StringToInt(sections[iCheckpointIndex]);

			if (zonedata <= 0 || zonedata > MAX_STAGES)
			{
				LogError("invalid stage number in prebuilt map zone (%s) on %s", sName, gS_Map);
				return false;
			}
		}
	}

	return true;
}

bool parse_climb_zone(char sName[32], int& zone, int& track, int& zonedata)
{
	// climb_startzone for the start of the main course.
	// climb_endzone for the end of the main course.
	// climb_bonusX_startzone for the start of a bonus course where X is the bonus number.
	// climb_bonusX_endzone for the end of a bonus course where X is the bonus number.

	if (StrContains(sName, "startzone") != -1)
	{
		zone = Zone_Start;
	}
	else if (StrContains(sName, "endzone") != -1)
	{
		zone = Zone_End;
	}

	int bonus = StrContains(sName, "bonus");

	if (bonus != -1)
	{
		track = Track_Bonus;

		if ('0' <= sName[bonus+5] <= '9')
		{
			track = StringToInt(sName[bonus+5]);

			if (track < Track_Bonus || track > Track_Bonus_Last)
			{
				LogError("invalid track in prebuilt map zone (%s) on %s", sName, gS_Map);
				return false;
			}
		}
	}

	return true;
}

public void Frame_HookTrigger(any data)
{
	int entity = EntRefToEntIndex(data);

	if (entity == INVALID_ENT_REFERENCE || gI_EntityZone[entity] > -1)
	{
		return;
	}

	char sName[32];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, 32);

	int zone = -1;
	int zonedata = 0;
	int track = Track_Main;

	if (StrContains(sName, "mod_zone_") == 0)
	{
		if (!parse_mod_zone(sName, zone, track, zonedata))
		{
			return;
		}
	}
	else if (StrContains(sName, "climb_") == 0)
	{
		if (!parse_climb_zone(sName, zone, track, zonedata))
		{
			return;
		}
	}
	else
	{
		return;
	}

	if(zone != -1)
	{
		int iZoneIndex = gI_MapZones;

		// Check for existing prebuilt zone in the cache and reuse slot.
		for (int i = 0; i < gI_MapZones; i++)
		{
			if (gA_ZoneCache[i].bPrebuilt && gA_ZoneCache[i].iZoneType == zone && gA_ZoneCache[i].iZoneTrack == track && gA_ZoneCache[i].iZoneData == zonedata)
			{
				iZoneIndex = i;
				break;
			}
		}

		gI_EntityZone[entity] = iZoneIndex;
		gA_ZoneCache[iZoneIndex].iEntityID = entity;

		SDKHook(entity, SDKHook_StartTouchPost, StartTouchPost);
		SDKHook(entity, SDKHook_EndTouchPost, EndTouchPost);
		SDKHook(entity, SDKHook_TouchPost, TouchPost);

		if (iZoneIndex != gI_MapZones)
		{
			return;
		}

		float maxs[3], mins[3], origin[3];
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
		GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);

		//origin[2] -= (maxs[2] - 2.0); // so you don't get stuck in the ground
		origin[2] += 1.0; // so you don't get stuck in the ground

		AddZoneToCache(
			zone,
			origin[0]+mins[0], origin[1]+mins[1], origin[2]+mins[2], // corner1_xyz
			origin[0]+maxs[0], origin[1]+maxs[1], origin[2]+maxs[2], // corner2_xyz
			0.0, 0.0, 0.0, // destination_xyz (Zone_Teleport/Zone_Stage)
			track,
			-1,       // iDatabaseID
			0,        // iZoneFlags
			zonedata,
			true      // bPrebuilt
		);
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

void ClearZone(int index)
{
	gV_MapZones[index][0] = NULL_VECTOR;
	gV_MapZones[index][1] = NULL_VECTOR;
	gV_Destinations[index] = NULL_VECTOR;
	gV_ZoneCenter[index] = NULL_VECTOR;

	gA_ZoneCache[index].bZoneInitialized = false;
	gA_ZoneCache[index].bPrebuilt = false;
	gA_ZoneCache[index].iZoneType = -1;
	gA_ZoneCache[index].iZoneTrack = -1;
	gA_ZoneCache[index].iEntityID = -1;
	gA_ZoneCache[index].iDatabaseID = -1;
	gA_ZoneCache[index].iZoneFlags = 0;
	gA_ZoneCache[index].iZoneData = 0;
}

void KillZoneEntity(int index, bool kill=true)
{
	int entity = gA_ZoneCache[index].iEntityID;

	if(entity > MaxClients)
	{
		gA_ZoneCache[index].iEntityID = -1;
		gI_EntityZone[entity] = -1;

		for(int i = 1; i <= MaxClients; i++)
		{
			for(int j = 0; j < TRACKS_SIZE; j++)
			{
				gB_InsideZone[i][gA_ZoneCache[index].iZoneType][j] = false;
			}

			gB_InsideZoneID[i][index] = false;
		}

		if (!IsValidEntity(entity))
		{
			return;
		}

		if (kill && !gA_ZoneCache[index].bPrebuilt)
		{
			AcceptEntityInput(entity, "Kill");
		}
	}
}

void KillAllZones()
{
	char sTargetname[32];
	int iEntity = -1;

	while ((iEntity = FindEntityByClassname(iEntity, "trigger_multiple")) != -1)
	{
		GetEntPropString(iEntity, Prop_Data, "m_iName", sTargetname, sizeof(sTargetname));

		bool shavit_created = (StrContains(sTargetname, "shavit_zones_") == 0);

		if (shavit_created
		|| (StrContains(sTargetname, "mod_zone_") == 0)
		|| (StrContains(sTargetname, "climb_") == 0)
		)
		{
			SDKUnhook(iEntity, SDKHook_StartTouchPost, StartTouchPost);
			SDKUnhook(iEntity, SDKHook_EndTouchPost, EndTouchPost);
			SDKUnhook(iEntity, SDKHook_TouchPost, TouchPost);

			if (shavit_created)
			{
				AcceptEntityInput(iEntity, "Kill");
			}
		}
	}
}

void UnloadZones2()
{
	KillAllZones();

	for (int i = 0; i < MAX_ZONES; i++)
	{
		ClearZone(i);
	}

	ClearCustomSpawn(-1);
}

// 0 - all zones
void UnloadZones(int zone)
{
	if (zone != Zone_CustomSpawn)
	{
		for(int i = 0; i < MAX_ZONES; i++)
		{
			if((zone == 0 || gA_ZoneCache[i].iZoneType == zone) && gA_ZoneCache[i].bZoneInitialized)
			{
				KillZoneEntity(i);
				ClearZone(i);
			}
		}
	}

	ClearCustomSpawn(-1);
}

void RefreshZones()
{
	gI_MapZones = 0;

	int empty_array[TRACKS_SIZE];
	gI_HighestStage = empty_array;

	ReloadPrebuiltZones();

	char sQuery[512];
	FormatEx(sQuery, 512,
		"SELECT type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, destination_x, destination_y, destination_z, track, %s, flags, data, prebuilt FROM %smapzones WHERE map = '%s';",
		(gB_MySQL)? "id":"rowid", gS_MySQLPrefix, gS_Map);

	gH_SQL.Query2(SQL_RefreshZones_Callback, sQuery, 0, DBPrio_High);
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
		if (results.FetchInt(14)) // prebuilt
		{
			// prebuilt zones already exist in db so we can mark them as already inserted
			gB_InsertedPrebuiltZones = true;
			continue;
		}

		int type = results.FetchInt(0);
		int track = results.FetchInt(10);

		if(type == Zone_CustomSpawn)
		{
			gF_CustomSpawn[track][0] = results.FetchFloat(7);
			gF_CustomSpawn[track][1] = results.FetchFloat(8);
			gF_CustomSpawn[track][2] = results.FetchFloat(9);
		}
		else
		{
			AddZoneToCache(
				type,
				results.FetchFloat(1), results.FetchFloat(2), results.FetchFloat(3), // corner1_xyz
				results.FetchFloat(4), results.FetchFloat(5), results.FetchFloat(6), // corner2_xyz
				results.FetchFloat(7), results.FetchFloat(8), results.FetchFloat(9), // destination_xyz (Zone_Teleport/Zone_Stage)
				track,
				results.FetchInt(11), // iDatabaseID
				results.FetchInt(12), // iZoneFlags
				results.FetchInt(13), // iZoneData
				false                 // bPrebuilt
			);
		}
	}

	if (!gB_InsertedPrebuiltZones)
	{
		gB_InsertedPrebuiltZones = true;

		char sQuery[1024];
		Transaction2 hTransaction;

		for (int i = 0; i < gI_MapZones; i++)
		{
			if (gA_ZoneCache[i].bPrebuilt)
			{
				if (hTransaction == null)
				{
					hTransaction = new Transaction2();
				}

				InsertPrebuiltZone(i, false, sQuery, sizeof(sQuery));
				hTransaction.AddQuery2(sQuery);
			}
		}

		if (hTransaction != null)
		{
			gH_SQL.Execute(hTransaction);
		}
	}

	CreateZoneEntities(false);
}

public void AddZoneToCache(int type, float corner1_x, float corner1_y, float corner1_z, float corner2_x, float corner2_y, float corner2_z, float destination_x, float destination_y, float destination_z, int track, int id, int flags, int data, bool prebuilt)
{
	gV_MapZones[gI_MapZones][0][0] = gV_MapZones_Visual[gI_MapZones][0][0] = corner1_x;
	gV_MapZones[gI_MapZones][0][1] = gV_MapZones_Visual[gI_MapZones][0][1] = corner1_y;
	gV_MapZones[gI_MapZones][0][2] = gV_MapZones_Visual[gI_MapZones][0][2] = corner1_z;
	gV_MapZones[gI_MapZones][1][0] = gV_MapZones_Visual[gI_MapZones][7][0] = corner2_x;
	gV_MapZones[gI_MapZones][1][1] = gV_MapZones_Visual[gI_MapZones][7][1] = corner2_y;
	gV_MapZones[gI_MapZones][1][2] = gV_MapZones_Visual[gI_MapZones][7][2] = corner2_z;

	float offset = -(prebuilt ? gCV_PrebuiltVisualOffset.FloatValue : 0.0) + gCV_Offset.FloatValue;
	CreateZonePoints(gV_MapZones_Visual[gI_MapZones], offset);

	gV_ZoneCenter[gI_MapZones][0] = (gV_MapZones[gI_MapZones][0][0] + gV_MapZones[gI_MapZones][1][0]) / 2.0;
	gV_ZoneCenter[gI_MapZones][1] = (gV_MapZones[gI_MapZones][0][1] + gV_MapZones[gI_MapZones][1][1]) / 2.0;
	gV_ZoneCenter[gI_MapZones][2] = (gV_MapZones[gI_MapZones][0][2] + gV_MapZones[gI_MapZones][1][2]) / 2.0;

	if(type == Zone_Teleport || type == Zone_Stage)
	{
		gV_Destinations[gI_MapZones][0] = destination_x;
		gV_Destinations[gI_MapZones][1] = destination_y;
		gV_Destinations[gI_MapZones][2] = destination_z;
	}

	if (type == Zone_Stage)
	{
		gI_StageZoneID[track][data] = id;

		if (data > gI_HighestStage[track])
		{
			gI_HighestStage[track] = data;
		}
	}

	gA_ZoneCache[gI_MapZones].bZoneInitialized = true;
	gA_ZoneCache[gI_MapZones].bPrebuilt = prebuilt;
	gA_ZoneCache[gI_MapZones].iZoneType = type;
	gA_ZoneCache[gI_MapZones].iZoneTrack = track;
	gA_ZoneCache[gI_MapZones].iDatabaseID = id;
	gA_ZoneCache[gI_MapZones].iZoneFlags = flags;
	gA_ZoneCache[gI_MapZones].iZoneData = data;

	if (!prebuilt)
	{
		gA_ZoneCache[gI_MapZones].iEntityID = -1;
	}

	gI_MapZones++;
}

public void OnClientConnected(int client)
{
	bool empty_InsideZone[TRACKS_SIZE];

	for (int i = 0; i < ZONETYPES_SIZE; i++)
	{
		gB_InsideZone[client][i] = empty_InsideZone;

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
		gF_ClimbButtonCache[client][i][0] = NULL_VECTOR;
		gF_ClimbButtonCache[client][i][1] = NULL_VECTOR;
	}

	bool empty_HasSetStart[TRACKS_SIZE];
	gB_HasSetStart[client] = empty_HasSetStart;

	Reset(client);

	gF_Modifier[client] = 16.0;
	gI_GridSnap[client] = 16;
	gB_SnapToWall[client] = false;
	gB_CursorTracing[client] = true;
	gB_DrawAllZones[client] = false;
}

public void OnClientAuthorized(int client)
{
	if (gB_Connected && !IsFakeClient(client))
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

	char czone[1 + 2*2*TRACKS_SIZE + 1]; // version + ((start + end) * 2 chars * tracks) + NUL terminator
	gH_CustomZoneCookie.Get(client, czone, sizeof(czone));

	if (czone[0] == 'a') // "version number"
	{
		int p = 1;
		char c;

		while ((c = czone[p++]) != 0)
		{
			int track = c & 0xf;
			int type = (c >> 4) & 1;
			gI_ZoneDisplayType[client][type][track] = (c >> 5) & 3;
			c = czone[p++];
			gI_ZoneColor[client][type][track] = c & 0xf;
			gI_ZoneWidth[client][type][track] = (c >> 4) & 7;
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

	gH_SQL.Query2(SQL_GetStartPosition_Callback, query, GetClientSerial(client));
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

#if 0
	if(!InsideZone(client, Zone_Start, track))
	{
		Shavit_PrintToChat(client, "%T", "SetStartNotInStartZone", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);

		return Plugin_Handled;
	}
#endif

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
		gF_StartPos[client][track] = NULL_VECTOR;
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

	gH_SQL.Query2(SQL_InsertStartPosition_Callback, query);
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

	Shavit_PrintToChat(client, "%T", "DeleteSetStart", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

	DeleteSetStart(client, Shavit_GetClientTrack(client));

	return Plugin_Handled;
}

void DeleteSetStart(int client, int track)
{
	gB_HasSetStart[client][track] = false;
	gF_StartPos[client][track] = view_as<float>({0.0, 0.0, 0.0});
	gF_StartAng[client][track] = view_as<float>({0.0, 0.0, 0.0});

	char query[512];

	FormatEx(query, 512,
		"DELETE FROM %sstartpositions WHERE auth = %d AND track = %d AND map = '%s';",
		gS_MySQLPrefix, GetSteamAccountID(client), track, gS_Map);

	gH_SQL.Query2(SQL_DeleteSetStart_Callback, query);
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

// Krypt Custom Spawn Functions (https://github.com/Kryptanyte)
public Action Command_AddSpawn(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

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
	menu.Display(client, 300);

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

		gI_ZoneType[param1] = Zone_CustomSpawn;
		gI_ZoneTrack[param1] = iTrack;
		GetClientAbsOrigin(param1, gV_Point1[param1]);

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
	menu.Display(client, 300);

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

		gI_ZoneTrack[param1] = iTrack;
		Shavit_LogMessage("%L - deleted custom spawn from map `%s`.", param1, gS_Map);

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery),
			"DELETE FROM %smapzones WHERE type = '%d' AND map = '%s' AND track = %d;",
			gS_MySQLPrefix, Zone_CustomSpawn, gS_Map, iTrack);

		gH_SQL.Query2(SQL_DeleteCustom_Spawn_Callback, sQuery, GetClientSerial(param1));
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

	ClearCustomSpawn(gI_ZoneTrack[client]);
	Shavit_PrintToChat(client, "%T", "ZoneCustomSpawnDelete", client);
}

void ClearCustomSpawn(int track)
{
	if(track != -1)
	{
		gF_CustomSpawn[track] = NULL_VECTOR;

		return;
	}

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		gF_CustomSpawn[i] = NULL_VECTOR;
	}
}

void ReloadPrebuiltZones()
{
	char sTargetname[32];
	int iEntity = INVALID_ENT_REFERENCE;

	while((iEntity = FindEntityByClassname(iEntity, "trigger_multiple")) != INVALID_ENT_REFERENCE)
	{
		GetEntPropString(iEntity, Prop_Data, "m_iName", sTargetname, 32);

		if(StrContains(sTargetname, "mod_zone_") != -1)
		{
			Frame_HookTrigger(EntIndexToEntRef(iEntity));
		}
	}

	iEntity = INVALID_ENT_REFERENCE;

	while ((iEntity = FindEntityByClassname(iEntity, "func_button")) != INVALID_ENT_REFERENCE)
	{
		GetEntPropString(iEntity, Prop_Data, "m_iName", sTargetname, sizeof(sTargetname));

		if (StrContains(sTargetname, "climb_") != -1)
		{
			Frame_HookButton(EntIndexToEntRef(iEntity));
		}
	}
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

	Reset(client);

	return OpenEditMenu(client);
}

public Action Command_ReloadZoneSettings(int client, int args)
{
	LoadZoneSettings();

	ReplyToCommand(client, "Reloaded zone settings.");

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
			if(gA_ZoneCache[i].bZoneInitialized && gA_ZoneCache[i].iZoneType == Zone_Stage && gA_ZoneCache[i].iZoneData == iStage)
			{
				Shavit_StopTimer(client);
				if(!EmptyVector(gV_Destinations[i]))
				{
					TeleportEntity(client, gV_Destinations[i], NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
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
			if(gA_ZoneCache[i].bZoneInitialized && gA_ZoneCache[i].iZoneType == Zone_Stage)
			{
				char sTrack[32];
				GetTrackName(client, gA_ZoneCache[i].iZoneTrack, sTrack, 32);

				FormatEx(sDisplay, 64, "#%d - %T (%s)", (i + 1), "ZoneSetStage", client, gA_ZoneCache[i].iZoneData, sTrack);

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

public int MenuHandler_SelectStage(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		int iIndex = StringToInt(sInfo);

		Shavit_StopTimer(param1);

		if(!EmptyVector(gV_Destinations[iIndex]))
		{
			TeleportEntity(param1, gV_Destinations[iIndex], NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
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
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "ZonesCommand", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

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

	menu.ExitButton = true;
	menu.Display(client, 300);

	return Plugin_Handled;
}

public int MenuHandler_SelectZoneTrack(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		gI_ZoneTrack[param1] = StringToInt(sInfo);

		char sTrack[16];
		GetTrackName(param1, gI_ZoneTrack[param1], sTrack, 16);

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
		submenu.Display(param1, 300);
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
	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "ZoneEditRefresh", client);
	menu.AddItem("-2", sDisplay);

	for (int i = 0; i < gI_MapZones; i++)
	{
		if (!gA_ZoneCache[i].bZoneInitialized)
		{
			continue;
		}

		if ((menu.ItemCount % newPageInterval) == 0)
		{
			FormatEx(sDisplay, 64, "%T", "ZoneEditRefresh", client);
			menu.AddItem("-2", sDisplay);
		}

		char sInfo[8];
		IntToString(i, sInfo, 8);

		char sPrebuilt[16];
		sPrebuilt = gA_ZoneCache[i].bPrebuilt ? " (prebuilt)" : "";

		char sTrack[32];
		GetTrackName(client, gA_ZoneCache[i].iZoneTrack, sTrack, 32);

		char sZoneName[32];
		GetZoneName(client, gA_ZoneCache[i].iZoneType, sZoneName, sizeof(sZoneName));

		if (gA_ZoneCache[i].iZoneType == Zone_CustomSpeedLimit || gA_ZoneCache[i].iZoneType == Zone_Stage || gA_ZoneCache[i].iZoneType == Zone_Airaccelerate)
		{
			FormatEx(sDisplay, 64, "#%d - %s %d (%s)%s", (i + 1), sZoneName, gA_ZoneCache[i].iZoneData, sTrack, sPrebuilt);
		}
		else
		{
			FormatEx(sDisplay, 64, "#%d - %s (%s)%s", (i + 1), sZoneName, sTrack, sPrebuilt);
		}

		if (gB_InsideZoneID[client][i])
		{
			Format(sDisplay, 64, "%s %T", sDisplay, "ZoneInside", client);
		}

		menu.AddItem(sInfo, sDisplay, ITEMDRAW_DEFAULT);
	}

	menu.ExitButton = true;
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
				fCenter[2] = gV_MapZones[id][0][2];

				TeleportEntity(param1, fCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
			}
		}

		OpenTpToZoneMenu(param1, GetMenuSelectionPosition());
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

Action OpenEditMenu(int client, int pos = 0)
{
	Menu menu = new Menu(MenuHandler_ZoneEdit);
	menu.SetTitle("%T\n ", "ZoneEditTitle", client);


	int newPageInterval = (gEV_Type == Engine_CSGO) ? 6 : 7;
	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "ZoneEditRefresh", client);
	menu.AddItem("-2", sDisplay);

	for(int i = 0; i < gI_MapZones; i++)
	{
		if(!gA_ZoneCache[i].bZoneInitialized)
		{
			continue;
		}

		if ((menu.ItemCount % newPageInterval) == 0)
		{
			FormatEx(sDisplay, 64, "%T", "ZoneEditRefresh", client);
			menu.AddItem("-2", sDisplay);
		}

		char sInfo[8];
		IntToString(i, sInfo, 8);

		char sPrebuilt[16];
		sPrebuilt = gA_ZoneCache[i].bPrebuilt ? " (prebuilt)" : "";

		char sTrack[32];
		GetTrackName(client, gA_ZoneCache[i].iZoneTrack, sTrack, 32);

		char sZoneName[32];
		GetZoneName(client, gA_ZoneCache[i].iZoneType, sZoneName, sizeof(sZoneName));

		if(gA_ZoneCache[i].iZoneType == Zone_CustomSpeedLimit || gA_ZoneCache[i].iZoneType == Zone_Stage || gA_ZoneCache[i].iZoneType == Zone_Airaccelerate)
		{
			FormatEx(sDisplay, 64, "#%d - %s %d (%s)%s", (i + 1), sZoneName, gA_ZoneCache[i].iZoneData, sTrack, sPrebuilt);
		}
		else
		{
			FormatEx(sDisplay, 64, "#%d - %s (%s)%s", (i + 1), sZoneName, sTrack, sPrebuilt);
		}

		if(gB_InsideZoneID[client][i])
		{
			Format(sDisplay, 64, "%s %T", sDisplay, "ZoneInside", client);
		}

		menu.AddItem(sInfo, sDisplay, gA_ZoneCache[i].bPrebuilt ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	menu.ExitButton = true;
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
				gV_Point1[param1] = gV_MapZones[id][0];
				gV_Point2[param1] = gV_MapZones[id][1];
				gI_ZoneType[param1] = gA_ZoneCache[id].iZoneType;
				gI_ZoneTrack[param1] = gA_ZoneCache[id].iZoneTrack;
				gV_Teleport[param1] = gV_Destinations[id];
				gI_ZoneDatabaseID[param1] = gA_ZoneCache[id].iDatabaseID;
				gI_ZoneFlags[param1] = gA_ZoneCache[id].iZoneFlags;
				gI_ZoneData[param1] = gA_ZoneCache[id].iZoneData;
				gI_ZoneID[param1] = id;

				// to stop the original zone from drawing
				gA_ZoneCache[id].bZoneInitialized = false;

				// draw the zone edit
				CreateTimer(0.1, Timer_Draw, GetClientSerial(param1), TIMER_REPEAT);

				CreateEditMenu(param1);
			}
		}
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
	for (int i = 0; i < TRACKS_SIZE; i++)
	{
		for (int j = 0; j <= Zone_End; j++)
		{
			if (gA_ZoneSettings[j][0].bVisible)
			{
				char info[8];
				FormatEx(info, sizeof(info), "%i;%i", i, j);
				char trackName[32], zoneName[32], display[64];
				GetTrackName(client, i, trackName, sizeof(trackName));
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
	char buf[1 + 2*2*TRACKS_SIZE + 1]; // version + ((start + end) * 2 chars * tracks) + NUL terminator
	int p = 0;

	for (int type = Zone_Start; type <= Zone_End; type++)
	{
		for (int track = Track_Main; track < TRACKS_SIZE; track++)
		{
			if (gI_ZoneDisplayType[client][type][track] || gI_ZoneColor[client][type][track] || gI_ZoneWidth[client][type][track])
			{
				if (!p) buf[p++] = 'a'; // "version number"
				// highest bit (0x80) set so we don't get a zero byte terminating the cookie early
				buf[p++] = 0x80 | (gI_ZoneDisplayType[client][type][track] << 5) | (type << 4) | track;
				buf[p++] = 0x80 | (gI_ZoneWidth[client][type][track] << 4) | gI_ZoneColor[client][type][track];
			}
		}
	}

	gH_CustomZoneCookie.Set(client, buf);
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
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	return OpenDeleteMenu(client);
}

Action OpenDeleteMenu(int client, int pos = 0)
{
	Menu menu = new Menu(MenuHandler_DeleteZone);
	menu.SetTitle("%T\n ", "ZoneMenuDeleteTitle", client);

	int newPageInterval = (gEV_Type == Engine_CSGO) ? 6 : 7;
	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "ZoneEditRefresh", client);
	menu.AddItem("-2", sDisplay);

	for(int i = 0; i < gI_MapZones; i++)
	{
		if (gA_ZoneCache[i].bZoneInitialized)
		{
			if ((menu.ItemCount % newPageInterval) == 0)
			{
				FormatEx(sDisplay, 64, "%T", "ZoneEditRefresh", client);
				menu.AddItem("-2", sDisplay);
			}

			char sPrebuilt[16];
			sPrebuilt = gA_ZoneCache[i].bPrebuilt ? " (prebuilt)" : "";

			char sTrack[32];
			GetTrackName(client, gA_ZoneCache[i].iZoneTrack, sTrack, 32);

			char sZoneName[32];
			GetZoneName(client, gA_ZoneCache[i].iZoneType, sZoneName, sizeof(sZoneName));

			if(gA_ZoneCache[i].iZoneType == Zone_CustomSpeedLimit || gA_ZoneCache[i].iZoneType == Zone_Stage || gA_ZoneCache[i].iZoneType == Zone_Airaccelerate)
			{
				FormatEx(sDisplay, 64, "#%d - %s %d (%s)%s", (i + 1), sZoneName, gA_ZoneCache[i].iZoneData, sTrack, sPrebuilt);
			}
			else
			{
				FormatEx(sDisplay, 64, "#%d - %s (%s)%s", (i + 1), sZoneName, sTrack, sPrebuilt);
			}

			char sInfo[8];
			IntToString(i, sInfo, 8);

			if(gB_InsideZoneID[client][i])
			{
				Format(sDisplay, 64, "%s %T", sDisplay, "ZoneInside", client);
			}

			menu.AddItem(sInfo, sDisplay, gA_ZoneCache[i].bPrebuilt ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
		}
	}

	menu.ExitButton = true;
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
				GetZoneName(LANG_SERVER, gA_ZoneCache[id].iZoneType, sZoneName, sizeof(sZoneName));

				Shavit_LogMessage("%L - deleted %s (id %d) from map `%s`.", param1, sZoneName, gA_ZoneCache[id].iDatabaseID, gS_Map);

				char sQuery[256];
				FormatEx(sQuery, 256, "DELETE FROM %smapzones WHERE %s = %d;", gS_MySQLPrefix, (gB_MySQL)? "id":"rowid", gA_ZoneCache[id].iDatabaseID);

				DataPack hDatapack = new DataPack();
				hDatapack.WriteCell(GetClientSerial(param1));
				hDatapack.WriteCell(gA_ZoneCache[id].iZoneType);

				gH_SQL.Query2(SQL_DeleteZone_Callback, sQuery, hDatapack);
			}
		}
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

	UnloadZones(type);
	RefreshZones();

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

	menu.ExitButton = true;
	menu.Display(client, 300);

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

		gH_SQL.Query2(SQL_DeleteAllZones_Callback, sQuery, GetClientSerial(param1));
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

	UnloadZones(0);
	RequestFrame(ReloadPrebuiltZones);

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

		gI_ZoneType[param1] = StringToInt(info);

		if (gI_ZoneType[param1] == Zone_Gravity)
		{
			gI_ZoneData[param1] = view_as<int>(1.0);
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
	gI_ZoneTrack[client] = Track_Main;
	gI_MapStep[client] = 0;
	gI_ZoneFlags[client] = 0;
	gI_ZoneData[client] = 0;
	gI_ZoneDatabaseID[client] = -1;
	gB_WaitingForChatInput[client] = false;
	gI_ZoneID[client] = -1;

	gV_Point1[client] = NULL_VECTOR;
	gV_Point2[client] = NULL_VECTOR;
	gV_Teleport[client] = NULL_VECTOR;
	gV_WallSnap[client] = NULL_VECTOR;
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

	pPanel.Send(client, ZoneCreation_Handler, 600);

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

void FillBoxMinMax(float point1[3], float point2[3], float boxmin[3], float boxmax[3])
{
	for (int i = 0; i < 3; i++)
	{
		boxmin[i] = (point1[i] < point2[i]) ? point1[i] : point2[i];
		boxmax[i] = (point1[i] < point2[i]) ? point2[i] : point1[i];
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
		FillBoxMinMax(point1, point2, amin, amax);
	}

	for (int i = 0; i < MAX_ZONES; i++)
	{
		if (!gA_ZoneCache[i].bZoneInitialized || (gA_ZoneCache[i].iZoneTrack == track && gA_ZoneCache[i].iZoneType == type) || (gA_ZoneCache[i].iZoneType != Zone_End && gA_ZoneCache[i].iZoneType != Zone_Start))
		{
			continue;
		}

		float bmin[3], bmax[3];
		FillBoxMinMax(gV_MapZones_Visual[i][0], gV_MapZones_Visual[i][7], bmin, bmax);

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

					if (!InStartOrEndZone(origin, NULL_VECTOR, gI_ZoneTrack[client], gI_ZoneType[client]))
					{
						gV_Point1[client] = origin;
						ShowPanel(client, 2);
					}
				}
				else if(gI_MapStep[client] == 2)
				{
					origin[2] += gCV_Height.FloatValue;

					if (origin[0] != gV_Point1[client][0] && origin[1] != gV_Point1[client][1] && !InStartOrEndZone(gV_Point1[client], origin, gI_ZoneTrack[client], gI_ZoneType[client]))
					{
						gV_Point2[client] = origin;
						gI_MapStep[client]++;

						CreateEditMenu(client);
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
	return (entity != view_as<int>(data) || (entity < 1 || entity > MaxClients));
}

public int CreateZoneConfirm_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		gB_HackyResetCheck[param1] = true;

		if(StrEqual(sInfo, "yes"))
		{
			if (gI_ZoneID[param1] != -1)
			{
				// reenable so it can be wiped in the subsequent InsertZones->SQL_Callback->UnloadZones
				gA_ZoneCache[gI_ZoneID[param1]].bZoneInitialized = true;
			}

			InsertZone(param1);
			gI_MapStep[param1] = 0;

			return 0;
		}
		else if(StrEqual(sInfo, "no"))
		{
			if (gI_ZoneID[param1] != -1)
			{
				gA_ZoneCache[gI_ZoneID[param1]].bZoneInitialized = true;
			}

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
			gI_ZoneData[param1] = 0;
			gB_WaitingForChatInput[param1] = true;

			Shavit_PrintToChat(param1, "%T", "ZoneEnterDataChat", param1);

			return 0;
		}
		else if(StrEqual(sInfo, "forcerender"))
		{
			gI_ZoneFlags[param1] ^= ZF_ForceRender;
		}

		CreateEditMenu(param1);
	}
	else if (action == MenuAction_Cancel)
	{
		if (!gB_HackyResetCheck[param1])
		{
			if (gI_ZoneID[param1] != -1)
			{
				gA_ZoneCache[gI_ZoneID[param1]].bZoneInitialized = true;
			}
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
		if (gI_ZoneType[client] == Zone_Gravity)
		{
			gI_ZoneData[client] = view_as<int>(StringToFloat(sArgs));
		}
		else
		{
			gI_ZoneData[client] = StringToInt(sArgs);
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

	if(gI_ZoneType[client] == Zone_Stage)
	{
		gV_Teleport[client] = vTeleport;

		Shavit_PrintToChat(client, "%T", "ZoneTeleportUpdated", client);
	}
	else
	{
		bool bInside = true;

		for(int i = 0; i < 3; i++)
		{
			if(gV_Point1[client][i] >= vTeleport[i] == gV_Point2[client][i] >= vTeleport[i])
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
			gV_Teleport[client] = vTeleport;

			Shavit_PrintToChat(client, "%T", "ZoneTeleportUpdated", client);
		}
	}
}

void CreateEditMenu(int client)
{
	char sTrack[32];
	GetTrackName(client, gI_ZoneTrack[client], sTrack, 32);

	gB_HackyResetCheck[client] = false;
	Menu menu = new Menu(CreateZoneConfirm_Handler);
	menu.SetTitle("%T\n%T\n ", "ZoneEditConfirm", client, "ZoneEditTrack", client, sTrack);

	char sMenuItem[64];

	if(gI_ZoneType[client] == Zone_Teleport)
	{
		if(EmptyVector(gV_Teleport[client]))
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
	else if(gI_ZoneType[client] == Zone_Stage)
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
	menu.AddItem("adjust", sMenuItem);

	FormatEx(sMenuItem, 64, "%T", "ZoneForceRender", client, ((gI_ZoneFlags[client] & ZF_ForceRender) > 0)? "＋":"－");
	menu.AddItem("forcerender", sMenuItem);

	if(gI_ZoneType[client] == Zone_Stage)
	{
		FormatEx(sMenuItem, 64, "%T", "ZoneSetStage", client, gI_ZoneData[client]);
		menu.AddItem("datafromchat", sMenuItem);
	}
	else if(gI_ZoneType[client] == Zone_Airaccelerate)
	{
		FormatEx(sMenuItem, 64, "%T", "ZoneSetAiraccelerate", client, gI_ZoneData[client]);
		menu.AddItem("datafromchat", sMenuItem);
	}
	else if(gI_ZoneType[client] == Zone_CustomSpeedLimit)
	{
		if(gI_ZoneData[client] == 0)
		{
			FormatEx(sMenuItem, 64, "%T", "ZoneSetSpeedLimitUnlimited", client, gI_ZoneData[client]);
		}
		else
		{
			FormatEx(sMenuItem, 64, "%T", "ZoneSetSpeedLimit", client, gI_ZoneData[client]);
		}

		menu.AddItem("datafromchat", sMenuItem);
	}
	else if (gI_ZoneType[client] == Zone_Gravity)
	{
		float g = view_as<float>(gI_ZoneData[client]);
		FormatEx(sMenuItem, sizeof(sMenuItem), "%T", "ZoneSetGravity", client, g);
		menu.AddItem("datafromchat", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 600);
}

void CreateAdjustMenu(int client, int page)
{
	Menu hMenu = new Menu(ZoneAdjuster_Handler);
	char sMenuItem[64];
	hMenu.SetTitle("%T", "ZoneAdjustPosition", client);

	FormatEx(sMenuItem, 64, "%T", "ZoneAdjustDone", client);
	hMenu.AddItem("done", sMenuItem);
	FormatEx(sMenuItem, 64, "%T", "ZoneAdjustCancel", client);
	hMenu.AddItem("cancel", sMenuItem);

	char sAxis[4];
	strcopy(sAxis, 4, "XYZ");

	char sDisplay[32];
	char sInfo[16];

	for(int iPoint = 1; iPoint <= 2; iPoint++)
	{
		for(int iAxis = 0; iAxis < 3; iAxis++)
		{
			for(int iState = 1; iState <= 2; iState++)
			{
				FormatEx(sDisplay, 32, "%T %c%.01f", "ZonePoint", client, iPoint, sAxis[iAxis], (iState == 1)? '+':'-', gF_Modifier[client]);
				FormatEx(sInfo, 16, "%d;%d;%d", iPoint, iAxis, iState);
				hMenu.AddItem(sInfo, sDisplay);
			}
		}
	}

	hMenu.ExitButton = false;
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
		else if(StrEqual(sInfo, "cancel"))
		{
			if (gI_ZoneID[param1] != -1)
			{
				// reenable original zone
				gA_ZoneCache[gI_ZoneID[param1]].bZoneInitialized = true;
			}

			Reset(param1);
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

			((iPoint == 1)? gV_Point1:gV_Point2)[param1][iAxis] += ((bIncrease)? gF_Modifier[param1]:-gF_Modifier[param1]);
			Shavit_PrintToChat(param1, "%T", (bIncrease)? "ZoneSizeIncrease":"ZoneSizeDecrease", param1, gS_ChatStrings.sVariable2, sAxis[iAxis], gS_ChatStrings.sText, iPoint, gS_ChatStrings.sVariable, gF_Modifier[param1], gS_ChatStrings.sText);

			CreateAdjustMenu(param1, GetMenuSelectionPosition());
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (gI_ZoneID[param1] != -1)
		{
			// reenable original zone
			gA_ZoneCache[gI_ZoneID[param1]].bZoneInitialized = true;
		}

		Reset(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void InsertPrebuiltZone(int zone, bool update, char[] sQuery, int sQueryLen)
{
	if (update)
	{
		FormatEx(sQuery, sQueryLen,
			"UPDATE %smapzones SET corner1_x = '%.03f', corner1_y = '%.03f', corner1_z = '%.03f', corner2_x = '%.03f', corner2_y = '%.03f', corner2_z = '%.03f', prebuilt = 1 WHERE map = '%s' AND type = %d AND track = %d;",
			gS_MySQLPrefix,
			gV_MapZones[zone][0][0], gV_MapZones[zone][0][1], gV_MapZones[zone][0][2],
			gV_MapZones[zone][1][0], gV_MapZones[zone][1][1], gV_MapZones[zone][1][2],
			gS_Map, gA_ZoneCache[zone].iZoneType, gA_ZoneCache[zone].iZoneTrack
		);
	}
	else
	{
		FormatEx(sQuery, sQueryLen,
			"INSERT INTO %smapzones (map, type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, track, data, prebuilt) VALUES ('%s', %d, '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', %d, %d, 1);",
			gS_MySQLPrefix, gS_Map, gA_ZoneCache[zone].iZoneType,
			gV_MapZones[zone][0][0], gV_MapZones[zone][0][1], gV_MapZones[zone][0][2],
			gV_MapZones[zone][1][0], gV_MapZones[zone][1][1], gV_MapZones[zone][1][2],
			gA_ZoneCache[zone].iZoneTrack, gA_ZoneCache[zone].iZoneData
		);
	}
}

void InsertZone(int client)
{
	int iType = gI_ZoneType[client];
	int iIndex = GetZoneIndex(iType, gI_ZoneTrack[client]);
	bool bInsert = (gI_ZoneDatabaseID[client] == -1 && (iIndex == -1 || iType >= Zone_Respawn));

	char sQuery[1024];
	char sTrack[64], sZoneName[32];
	GetTrackName(LANG_SERVER, gI_ZoneTrack[client], sTrack, sizeof(sTrack));
	GetZoneName(LANG_SERVER, iType, sZoneName, sizeof(sZoneName));

	if(iType == Zone_CustomSpawn)
	{
		Shavit_LogMessage("%L - added custom spawn {%.2f, %.2f, %.2f} to map `%s`.", client, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gS_Map);

		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO %smapzones (map, type, destination_x, destination_y, destination_z, track) VALUES ('%s', %d, '%.03f', '%.03f', '%.03f', %d);",
			gS_MySQLPrefix, gS_Map, Zone_CustomSpawn, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gI_ZoneTrack[client]);
	}
	else if(bInsert) // insert
	{
		Shavit_LogMessage("%L - added %s %s to map `%s`.", client, sTrack, sZoneName, gS_Map);

		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO %smapzones (map, type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, destination_x, destination_y, destination_z, track, flags, data) VALUES ('%s', %d, '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', %d, %d, %d);",
			gS_MySQLPrefix, gS_Map, iType, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gV_Teleport[client][0], gV_Teleport[client][1], gV_Teleport[client][2], gI_ZoneTrack[client], gI_ZoneFlags[client], gI_ZoneData[client]);
	}
	else // update
	{
		Shavit_LogMessage("%L - updated %s %s in map `%s`.", client, sTrack, sZoneName, gS_Map);

		if(gI_ZoneDatabaseID[client] == -1)
		{
			for(int i = 0; i < gI_MapZones; i++)
			{
				if(gA_ZoneCache[i].bZoneInitialized && gA_ZoneCache[i].iZoneType == iType && gA_ZoneCache[i].iZoneTrack == gI_ZoneTrack[client])
				{
					gI_ZoneDatabaseID[client] = gA_ZoneCache[i].iDatabaseID;
				}
			}
		}

		FormatEx(sQuery, sizeof(sQuery),
			"UPDATE %smapzones SET corner1_x = '%.03f', corner1_y = '%.03f', corner1_z = '%.03f', corner2_x = '%.03f', corner2_y = '%.03f', corner2_z = '%.03f', destination_x = '%.03f', destination_y = '%.03f', destination_z = '%.03f', track = %d, flags = %d, data = %d WHERE %s = %d;",
			gS_MySQLPrefix, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gV_Teleport[client][0], gV_Teleport[client][1], gV_Teleport[client][2], gI_ZoneTrack[client], gI_ZoneFlags[client], gI_ZoneData[client], (gB_MySQL)? "id":"rowid", gI_ZoneDatabaseID[client]);
	}

	gH_SQL.Query2(SQL_InsertZone_Callback, sQuery, GetClientSerial(client));
}

public void SQL_InsertZone_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zone insert) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	if(gI_ZoneType[client] == Zone_CustomSpawn)
	{
		Shavit_PrintToChat(client, "%T", "ZoneCustomSpawnSuccess", client);
	}

	UnloadZones(0);
	RefreshZones();
	Reset(client);
}

public Action Timer_DrawVisible(Handle Timer)
{
	if(gI_MapZones == 0)
	{
		return Plugin_Continue;
	}

	static int iCycle = 0;
	static int iMaxZonesPerFrame = 5;

	if(iCycle >= gI_MapZones)
	{
		iCycle = 0;
	}

	int iDrawn = 0;

	for(int i = iCycle; i < gI_MapZones; i++, iCycle++)
	{
		if(gA_ZoneCache[i].bZoneInitialized)
		{
			int type = gA_ZoneCache[i].iZoneType;
			int track = gA_ZoneCache[i].iZoneTrack;

			if(gA_ZoneSettings[type][track].bVisible || (gA_ZoneCache[i].iZoneFlags & ZF_ForceRender) > 0)
			{
				DrawZone(gV_MapZones_Visual[i],
						GetZoneColors(type, track),
						RoundToCeil(float(gI_MapZones) / iMaxZonesPerFrame + 2.0) * gCV_Interval.FloatValue,
						gA_ZoneSettings[type][track].fWidth,
						gA_ZoneSettings[type][track].bFlatZone,
						gV_ZoneCenter[i],
						gA_ZoneSettings[type][track].iBeam,
						gA_ZoneSettings[type][track].iHalo,
						track,
						type,
						false,
						0);

				if (++iDrawn % iMaxZonesPerFrame == 0)
				{
					return Plugin_Continue;
				}
			}
		}
	}

	iCycle = 0;

	return Plugin_Continue;
}

public Action Timer_DrawAllZones(Handle Timer)
{
	if (gI_MapZones == 0 || !gCV_AllowDrawAllZones.BoolValue)
	{
		return Plugin_Continue;
	}

	static int iCycle = 0;
	static int iMaxZonesPerFrame = 5;

	if (iCycle >= gI_MapZones)
	{
		iCycle = 0;
	}

	int iDrawn = 0;

	for (int i = iCycle; i < gI_MapZones; i++, iCycle++)
	{
		if (gA_ZoneCache[i].bZoneInitialized)
		{
			int type = gA_ZoneCache[i].iZoneType;
			int track = gA_ZoneCache[i].iZoneTrack;

			DrawZone(
				gV_MapZones_Visual[i],
				GetZoneColors(type, track),
				RoundToCeil(float(gI_MapZones) / iMaxZonesPerFrame + 2.0) * gCV_Interval.FloatValue,
				gA_ZoneSettings[type][track].fWidth,
				gA_ZoneSettings[type][track].bFlatZone,
				gV_ZoneCenter[i],
				gA_ZoneSettings[type][track].iBeam,
				gA_ZoneSettings[type][track].iHalo,
				track,
				type,
				true, // <==== this is the the important part,
				0
			);

			if (++iDrawn % iMaxZonesPerFrame == 0)
			{
				return Plugin_Continue;
			}
		}
	}

	iCycle = 0;

	return Plugin_Continue;
}

int[] GetZoneColors(int type, int track, int customalpha = 0)
{
	int colors[4];
	colors[0] = gA_ZoneSettings[type][track].iRed;
	colors[1] = gA_ZoneSettings[type][track].iGreen;
	colors[2] = gA_ZoneSettings[type][track].iBlue;
	colors[3] = (customalpha > 0)? customalpha:gA_ZoneSettings[type][track].iAlpha;

	return colors;
}

public Action Timer_Draw(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0 || gI_MapStep[client] == 0)
	{
		Reset(client);

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

	if(gI_MapStep[client] == 1 || gV_Point2[client][0] == 0.0)
	{
		origin[2] = (vPlayerOrigin[2] + gCV_Height.FloatValue);
	}
	else
	{
		origin = gV_Point2[client];
	}

	int type = gI_ZoneType[client];
	int track = gI_ZoneTrack[client];

	if(!EmptyVector(gV_Point1[client]) || !EmptyVector(gV_Point2[client]))
	{
		float points[8][3];
		points[0] = gV_Point1[client];
		points[7] = origin;
		CreateZonePoints(points, gCV_Offset.FloatValue);

		// This is here to make the zone setup grid snapping be 1:1 to how it looks when done with the setup.
		origin = points[7];

		DrawZone(points, GetZoneColors(type, track, 125), 0.1, gA_ZoneSettings[type][track].fWidth, false, origin, gI_BeamSpriteIgnoreZ, gA_ZoneSettings[type][track].iHalo, track, type);

		if(gI_ZoneType[client] == Zone_Teleport && !EmptyVector(gV_Teleport[client]))
		{
			TE_SetupEnergySplash(gV_Teleport[client], NULL_VECTOR, false);
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

void DrawZone(float points[8][3], int color[4], float life, float width, bool flat, float center[3], int beam, int halo, int track, int type, bool drawallzones=false, int single_client=0)
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

	for (int i = 0; i < count; i++)
	{
		int point_size = (gI_ZoneDisplayType[clients[i]][type][track] == ZoneDisplay_Flat ||
		                  gI_ZoneDisplayType[clients[i]][type][track] == ZoneDisplay_Default && flat) ? 4 : 12;

		int actual_color[4];
		actual_color = (gI_ZoneColor[clients[i]][type][track] == ZoneColor_Default) ? color : clrs[gI_ZoneColor[clients[i]][type][track] - 1];

		float actual_width = (gI_ZoneWidth[clients[i]][type][track] == ZoneWidth_Default) ? width : some_width[gI_ZoneWidth[clients[i]][type][track] - 1];

		for(int j = 0; j < point_size; j++)
		{
			TE_SetupBeamPoints(points[pairs[j][0]], points[pairs[j][1]], beam, halo, 0, 0, life, actual_width, actual_width, 0, 0.0, actual_color, 0);
			TE_SendToClient(clients[i], 0.0);
		}
	}
}

// original by blacky
// creates 3d box from 2 points
void CreateZonePoints(float point[8][3], float offset = 0.0)
{
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
	gH_SQL = view_as<Database2>(Shavit_GetDatabase());
	gB_MySQL = IsMySQLDatabase(gH_SQL);

	gB_Connected = true;

	if (!gB_Late)
	{
		OnMapStart();
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
			TeleportEntity(client, gF_CustomSpawn[track], NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}
		// standard zoning
		else if (iIndex != -1)
		{
			float fCenter[3];
			fCenter[0] = gV_ZoneCenter[iIndex][0];
			fCenter[1] = gV_ZoneCenter[iIndex][1];
			fCenter[2] = gV_MapZones[iIndex][0][2] + gCV_ExtraSpawnHeight.FloatValue;

			if (bCustomStart)
			{
				fCenter = gF_StartPos[client][track];
			}

			fCenter[2] += 1.0;

			TeleportEntity(client, fCenter, gB_HasSetStart[client][track] ? gF_StartAng[client][track] : NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
			// I would like to put MaybeDoPhysicsUntouch() here but then it doesn't retrigger the zone's starttouch until next frame so the hud can show the wrong thing if I spam !r since the player isn't "in-the-zone"... TODO maybe...

			if (gB_ReplayRecorder && gB_HasSetStart[client][track])
			{
				Shavit_HijackAngles(client, gF_StartAng[client][track][0], gF_StartAng[client][track][1], -1, true);
			}

			if (!gB_HasSetStart[client][track] || gB_StartAnglesOnly[client][track])
			{
				ResetClientTargetNameAndClassName(client, track);
				// normally StartTimer will happen on zone-touch BUT we have this here for zones that are in the air
				Shavit_StartTimer(client, track);
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
		DrawZone(
			gV_MapZones_Visual[iIndex],
			GetZoneColors(Zone_Start, track),
			gCV_Interval.FloatValue,
			gA_ZoneSettings[Zone_Start][track].fWidth,
			gA_ZoneSettings[Zone_Start][track].bFlatZone,
			gV_ZoneCenter[iIndex],
			gA_ZoneSettings[Zone_Start][track].iBeam,
			gA_ZoneSettings[Zone_Start][track].iHalo,
			track,
			Zone_Start,
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
			fCenter[2] = gV_MapZones[iIndex][0][2] + 1.0; // no stuck in floor please

			TeleportEntity(client, fCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}
	}

	if (iIndex != -1)
	{
		DrawZone(
			gV_MapZones_Visual[iIndex],
			GetZoneColors(Zone_End, track),
			gCV_Interval.FloatValue,
			gA_ZoneSettings[Zone_End][track].fWidth,
			gA_ZoneSettings[Zone_End][track].bFlatZone,
			gV_ZoneCenter[iIndex],
			gA_ZoneSettings[Zone_End][track].iBeam,
			gA_ZoneSettings[Zone_End][track].iHalo,
			track,
			Zone_End,
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
	if(gI_MapZones == 0)
	{
		return -1;
	}

	for(int i = start; i < gI_MapZones; i++)
	{
		if(gA_ZoneCache[i].bZoneInitialized && gA_ZoneCache[i].iZoneType == type && (gA_ZoneCache[i].iZoneTrack == track || track == -1))
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
	bool empty_InsideZone[TRACKS_SIZE];

	for (int i = 0; i <= MaxClients; i++)
	{
		for (int j = 0; j < ZONETYPES_SIZE; j++)
		{
			gB_InsideZone[i][j] = empty_InsideZone;
		}

		bool empty_InsideZoneID[MAX_ZONES];
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

public void CreateZoneEntities(bool only_create_dead_entities)
{
	for(int i = 0; i < gI_MapZones; i++)
	{
		if(gA_ZoneCache[i].bPrebuilt)
		{
			continue;
		}

		for(int j = 1; j <= MaxClients; j++)
		{
			for(int k = 0; k < TRACKS_SIZE; k++)
			{
				gB_InsideZone[j][gA_ZoneCache[i].iZoneType][k] = false;
			}

			gB_InsideZoneID[j][i] = false;
		}

		if(gA_ZoneCache[i].iEntityID != -1)
		{
			if (only_create_dead_entities)
			{
				continue;
			}

			KillZoneEntity(i);
		}

		if(!gA_ZoneCache[i].bZoneInitialized)
		{
			continue;
		}

		int entity = CreateEntityByName("trigger_multiple");

		if(entity == -1)
		{
			LogError("\"trigger_multiple\" creation failed, map %s.", gS_Map);

			continue;
		}

		DispatchKeyValue(entity, "wait", "0");
		DispatchKeyValue(entity, "spawnflags", "4097");

		if(!DispatchSpawn(entity))
		{
			LogError("\"trigger_multiple\" spawning failed, map %s.", gS_Map);

			continue;
		}

		ActivateEntity(entity);
		SetEntityModel(entity, (gEV_Type == Engine_TF2)? "models/error.mdl":"models/props/cs_office/vending_machine.mdl");
		SetEntProp(entity, Prop_Send, "m_fEffects", 32);

		TeleportEntity(entity, gV_ZoneCenter[i], NULL_VECTOR, NULL_VECTOR);

		float distance_x = Abs(gV_MapZones[i][0][0] - gV_MapZones[i][1][0]) / 2;
		float distance_y = Abs(gV_MapZones[i][0][1] - gV_MapZones[i][1][1]) / 2;
		float distance_z = Abs(gV_MapZones[i][0][2] - gV_MapZones[i][1][2]) / 2;

		float height = ((IsSource2013(gEV_Type))? 62.0:72.0) / 2;

		float min[3];
		min[0] = -distance_x;
		min[1] = -distance_y;
		min[2] = -distance_z + height;

		float max[3];
		max[0] = distance_x;
		max[1] = distance_y;
		max[2] = distance_z - height;

		float offset = gCV_BoxOffset.FloatValue;

		if (distance_x > offset)
		{
			min[0] += offset;
			max[0] -= offset;
		}

		if (distance_y > offset)
		{
			min[1] += offset;
			max[1] -= offset;
		}

		SetEntPropVector(entity, Prop_Send, "m_vecMins", min);
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", max);

		SetEntProp(entity, Prop_Send, "m_nSolidType", 2);

		SDKHook(entity, SDKHook_StartTouchPost, StartTouchPost);
		SDKHook(entity, SDKHook_EndTouchPost, EndTouchPost);
		SDKHook(entity, SDKHook_TouchPost, TouchPost);

		gI_EntityZone[entity] = i;
		gA_ZoneCache[i].iEntityID = entity;

		char sTargetname[32];
		FormatEx(sTargetname, 32, "shavit_zones_%d_%d", gA_ZoneCache[i].iZoneTrack, gA_ZoneCache[i].iZoneType);
		DispatchKeyValue(entity, "targetname", sTargetname);
	}

	gB_ZoneCreationQueued = false;
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

public void StartTouchPost(int entity, int other)
{
	if(other < 1 || other > MaxClients || gI_EntityZone[entity] == -1 || !gA_ZoneCache[gI_EntityZone[entity]].bZoneInitialized || IsFakeClient(other) ||
		(gCV_EnforceTracks.BoolValue && gA_ZoneCache[gI_EntityZone[entity]].iZoneType > Zone_End && gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack != Shavit_GetClientTrack(other)))
	{
		return;
	}

	TimerStatus status = Shavit_GetTimerStatus(other);

	switch(gA_ZoneCache[gI_EntityZone[entity]].iZoneType)
	{
		case Zone_Respawn:
		{
			CS_RespawnPlayer(other);
		}

		case Zone_Teleport:
		{
			TeleportEntity(other, gV_Destinations[gI_EntityZone[entity]], NULL_VECTOR, NULL_VECTOR);
		}

		case Zone_Slay:
		{
			Shavit_StopTimer(other);
			ForcePlayerSuicide(other);
			Shavit_PrintToChat(other, "%T", "ZoneSlayEnter", other, gS_ChatStrings.sWarning, gS_ChatStrings.sVariable2, gS_ChatStrings.sWarning);
		}

		case Zone_Stop:
		{
			if(status != Timer_Stopped)
			{
				Shavit_StopTimer(other);
				Shavit_PrintToChat(other, "%T", "ZoneStopEnter", other, gS_ChatStrings.sWarning, gS_ChatStrings.sVariable2, gS_ChatStrings.sWarning);
			}
		}

		case Zone_End:
		{
			if (status == Timer_Running && Shavit_GetClientTrack(other) == gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack)
			{
				Shavit_FinishMap(other, gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack);
			}
		}

		case Zone_Stage:
		{
			int num = gA_ZoneCache[gI_EntityZone[entity]].iZoneData;
			int iStyle = Shavit_GetBhopStyle(other);
			bool bTASSegments = Shavit_GetStyleSettingBool(iStyle, "tas") || Shavit_GetStyleSettingBool(iStyle, "segments");

			if (status == Timer_Running && Shavit_GetClientTrack(other) == gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack && (num > gI_LastStage[other] || bTASSegments || Shavit_IsPracticeMode(other)))
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
	}

	gB_InsideZone[other][gA_ZoneCache[gI_EntityZone[entity]].iZoneType][gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack] = true;
	gB_InsideZoneID[other][gI_EntityZone[entity]] = true;

	Call_StartForward(gH_Forwards_EnterZone);
	Call_PushCell(other);
	Call_PushCell(gA_ZoneCache[gI_EntityZone[entity]].iZoneType);
	Call_PushCell(gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack);
	Call_PushCell(gI_EntityZone[entity]);
	Call_PushCell(entity);
	Call_PushCell(gA_ZoneCache[gI_EntityZone[entity]].iZoneData);
	Call_Finish();
}

public void EndTouchPost(int entity, int other)
{
	if(other < 1 || other > MaxClients || gI_EntityZone[entity] == -1 || IsFakeClient(other))
	{
		return;
	}

	int entityzone = gI_EntityZone[entity];
	int type = gA_ZoneCache[entityzone].iZoneType;
	int track = gA_ZoneCache[entityzone].iZoneTrack;

	if (type < 0 || track < 0) // odd
	{
		return;
	}

	gB_InsideZone[other][type][track] = false;
	gB_InsideZoneID[other][entityzone] = false;

	Call_StartForward(gH_Forwards_LeaveZone);
	Call_PushCell(other);
	Call_PushCell(type);
	Call_PushCell(track);
	Call_PushCell(entityzone);
	Call_PushCell(entity);
	Call_PushCell(gA_ZoneCache[entityzone].iZoneData);
	Call_Finish();
}

public void TouchPost(int entity, int other)
{
	if(other < 1 || other > MaxClients || gI_EntityZone[entity] == -1 || IsFakeClient(other) ||
		(gCV_EnforceTracks.BoolValue && gA_ZoneCache[gI_EntityZone[entity]].iZoneType > Zone_End && gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack != Shavit_GetClientTrack(other)))
	{
		return;
	}

	// do precise stuff here, this will be called *A LOT*
	switch(gA_ZoneCache[gI_EntityZone[entity]].iZoneType)
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
						ResetClientTargetNameAndClassName(other, gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack);

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
			
			if (GetEntPropEnt(other, Prop_Send, "m_hGroundEntity") == -1 && !Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(other), "startinair"))
			{
				return;
			}

			// start timer instantly for main track, but require bonuses to have the current timer stopped
			// so you don't accidentally step on those while running
			if(Shavit_GetTimerStatus(other) == Timer_Stopped || Shavit_GetClientTrack(other) != Track_Main)
			{
				Shavit_StartTimer(other, gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack);
			}
			else if(gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack == Track_Main)
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
			TeleportEntity(other, gV_Destinations[gI_EntityZone[entity]], NULL_VECTOR, NULL_VECTOR);
		}

		case Zone_Slay:
		{
			Shavit_StopTimer(other);
			ForcePlayerSuicide(other);
			Shavit_PrintToChat(other, "%T", "ZoneSlayEnter", other, gS_ChatStrings.sWarning, gS_ChatStrings.sVariable2, gS_ChatStrings.sWarning);
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

public void UsePost(int entity, int activator, int caller, UseType type, float value)
{
	if (activator < 1 || activator > MaxClients || IsFakeClient(activator))
	{
		return;
	}

	int zone = -1;
	int track = Track_Main;

	if (!GetButtonInfo(entity, zone, track))
	{
		return;
	}

	if(zone == Zone_Start)
	{
		if (GetEntPropEnt(activator, Prop_Send, "m_hGroundEntity") == -1)
		{
			return;
		}

		GetClientAbsOrigin(activator, gF_ClimbButtonCache[activator][track][0]);
		GetClientEyeAngles(activator, gF_ClimbButtonCache[activator][track][1]);

		Shavit_StartTimer(activator, track);
	}
	else if (zone == Zone_End && !Shavit_IsPaused(activator) && Shavit_GetTimerStatus(activator) == Timer_Running && Shavit_GetClientTrack(activator) == track)
	{
		Shavit_FinishMap(activator, track);
	}
}
