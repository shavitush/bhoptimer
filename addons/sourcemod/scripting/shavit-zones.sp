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
#include <sdktools>
#include <sdkhooks>
#include <convar_class>
#include <dhooks>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <adminmenu>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#include <tf2>

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

#define DEBUG 0

EngineVersion gEV_Type = Engine_Unknown;

Database2 gH_SQL = null;
bool gB_Connected = false;
bool gB_MySQL = false;
bool gB_InsertedPrebuiltZones = false;
bool gB_PrecachedStuff = false;

char gS_Map[PLATFORM_MAX_PATH];

char gS_ZoneNames[][] =
{
	"Start Zone", // starts timer
	"End Zone", // stops timer
	"Glitch Zone (Respawn Player)", // respawns the player
	"Glitch Zone (Stop Timer)", // stops the player's timer
	"Slay Player", // slays (kills) players which come to this zone
	"Freestyle Zone", // ignores style physics when at this zone. e.g. WASD when SWing
	"Custom Speed Limit", // overwrites velocity limit in the zone
	"Teleport Zone", // teleports to a defined point
	"SPAWN POINT", // << unused
	"Easybhop Zone", // forces easybhop whether if the player is in non-easy styles or if the server has different settings
	"Slide Zone", // allows players to slide, in order to fix parts like the 5th stage of bhop_arcane
	"Custom Airaccelerate", // custom sv_airaccelerate inside this,
	"Stage Zone" // shows time when entering zone
};

enum struct zone_cache_t
{
	bool bZoneInitialized;
	bool bPrebuilt; // comes from mod_zone_* entities
	int iZoneType;
	int iZoneTrack; // 0 - main, 1 - bonus etc
	int iEntityID;
	int iDatabaseID;
	int iZoneFlags;
	int iZoneData;
}

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

enum
{
	ZF_ForceRender = (1 << 0)
};

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

float gF_Modifier[MAXPLAYERS+1];
int gI_GridSnap[MAXPLAYERS+1];
bool gB_SnapToWall[MAXPLAYERS+1];
bool gB_CursorTracing[MAXPLAYERS+1];

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
Convar gCV_UseCustomSprite = null;
Convar gCV_Height = null;
Convar gCV_Offset = null;
Convar gCV_EnforceTracks = null;
Convar gCV_BoxOffset = null;
Convar gCV_PrebuiltVisualOffset = null;

// handles
Handle gH_DrawEverything = null;

// table prefix
char gS_MySQLPrefix[32];

// chat settings
chatstrings_t gS_ChatStrings;

// forwards
Handle gH_Forwards_EnterZone = null;
Handle gH_Forwards_LeaveZone = null;
Handle gH_Forwards_StageMessage = null;

// kz support
float gF_ClimbButtonCache[MAXPLAYERS+1][TRACKS_SIZE][2][3]; // 0 - location, 1 - angles
int gI_KZButtons[TRACKS_SIZE][2]; // 0 - start, 1 - end

// set start
bool gB_HasSetStart[MAXPLAYERS+1][TRACKS_SIZE];
bool gB_StartAnglesOnly[MAXPLAYERS+1][TRACKS_SIZE];
float gF_StartPos[MAXPLAYERS+1][TRACKS_SIZE][3];
float gF_StartAng[MAXPLAYERS+1][TRACKS_SIZE][3];

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
	RegAdminCmd("sm_zones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu.");
	RegAdminCmd("sm_mapzones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu. Alias of sm_zones.");

	RegAdminCmd("sm_deletezone", Command_DeleteZone, ADMFLAG_RCON, "Delete a mapzone");
	RegAdminCmd("sm_deleteallzones", Command_DeleteAllZones, ADMFLAG_RCON, "Delete all mapzones");

	RegAdminCmd("sm_modifier", Command_Modifier, ADMFLAG_RCON, "Changes the axis modifier for the zone editor. Usage: sm_modifier <number>");

	RegAdminCmd("sm_addspawn", Command_AddSpawn, ADMFLAG_RCON, "Adds a custom spawn location");
	RegAdminCmd("sm_delspawn", Command_DelSpawn, ADMFLAG_RCON, "Deletes a custom spawn location");

	RegAdminCmd("sm_zoneedit", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone.");
	RegAdminCmd("sm_editzone", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone. Alias of sm_zoneedit.");
	RegAdminCmd("sm_modifyzone", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone. Alias of sm_zoneedit.");
	
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
	gCV_UseCustomSprite = new Convar("shavit_zones_usecustomsprite", "1", "Use custom sprite for zone drawing?\nSee `configs/shavit-zones.cfg`.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_Height = new Convar("shavit_zones_height", "128.0", "Height to use for the start zone.", 0, true, 0.0, false);
	gCV_Offset = new Convar("shavit_zones_offset", "1.0", "When calculating a zone's *VISUAL* box, by how many units, should we scale it to the center?\n0.0 - no downscaling. Values above 0 will scale it inward and negative numbers will scale it outwards.\nAdjust this value if the zones clip into walls.");
	gCV_EnforceTracks = new Convar("shavit_zones_enforcetracks", "1", "Enforce zone tracks upon entry?\n0 - allow every zone except for start/end to affect users on every zone.\n1 - require the user's track to match the zone's track.", 0, true, 0.0, true, 1.0);
	gCV_BoxOffset = new Convar("shavit_zones_box_offset", "16", "Offset zone trigger boxes by this many unit\n0 - matches players bounding box\n16 - matches players center");
	gCV_PrebuiltVisualOffset = new Convar("shavit_zones_prebuilt_visual_offset", "0", "YOU DONT NEED TO TOUCH THIS USUALLY.\nUsed to fix the VISUAL beam offset for prebuilt zones on a map.\nExample maps you'd want to use 16 on: bhop_tranquility and bhop_amaranthglow");

	gCV_Interval.AddChangeHook(OnConVarChanged);
	gCV_UseCustomSprite.AddChangeHook(OnConVarChanged);
	gCV_Offset.AddChangeHook(OnConVarChanged);
	gCV_PrebuiltVisualOffset.AddChangeHook(OnConVarChanged);

	Convar.AutoExecConfig();

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

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			OnClientConnected(i);
		}
	}

	if (gB_Late)
	{
		Shavit_OnChatConfigLoaded();
		Shavit_OnDatabaseLoaded();
	}
}

public void OnPluginEnd()
{
	UnloadZones(0);
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
	if(convar == gCV_Interval)
	{
		delete gH_DrawEverything;
		gH_DrawEverything = CreateTimer(gCV_Interval.FloatValue, Timer_DrawEverything, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
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

		gH_AdminMenu.AddItem("sm_zones", AdminMenu_Zones, gH_TimerCommands, "sm_zones", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_deletezone", AdminMenu_DeleteZone, gH_TimerCommands, "sm_deletezone", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_deleteallzones", AdminMenu_DeleteAllZones, gH_TimerCommands, "sm_deleteallzones", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_zoneedit", AdminMenu_ZoneEdit, gH_TimerCommands, "sm_zoneedit", ADMFLAG_RCON);
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
	gH_SQL.Query(SQL_DeleteMap_Callback, sQuery, StrEqual(gS_Map, sMap, false), DBPrio_High);
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
}

public int Native_DeleteSetStart(Handle handler, int numParams)
{
	DeleteSetStart(GetNativeCell(1), GetNativeCell(2));
}

public int Native_GetClientLastStage(Handle plugin, int numParams)
{
	return gI_LastStage[GetNativeCell(1)];
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
	kv.JumpToKey("Start"); // A stupid and hacky way to achieve what I want. It works though.

	int i = 0;
	int track;

	do
	{
		// retroactively don't respect custom spawn settings
		char sSection[32];
		kv.GetSectionName(sSection, 32);

		if(StrContains(sSection, "SPAWN POINT", false) != -1)
		{
			continue;
		}

		if((i % ZONETYPES_SIZE) == Zone_CustomSpawn)
		{
			i++;
		}

		track = (i / ZONETYPES_SIZE);

		if(track >= TRACKS_SIZE)
		{
			break;
		}

		int index = (i % ZONETYPES_SIZE);

		gA_ZoneSettings[index][track].bVisible = view_as<bool>(kv.GetNum("visible", 1));
		gA_ZoneSettings[index][track].iRed = kv.GetNum("red", 255);
		gA_ZoneSettings[index][track].iGreen = kv.GetNum("green", 255);
		gA_ZoneSettings[index][track].iBlue = kv.GetNum("blue", 255);
		gA_ZoneSettings[index][track].iAlpha = kv.GetNum("alpha", 255);
		gA_ZoneSettings[index][track].fWidth = kv.GetFloat("width", 2.0);
		gA_ZoneSettings[index][track].bFlatZone = view_as<bool>(kv.GetNum("flat", false));
		gA_ZoneSettings[index][track].bUseVanillaSprite = view_as<bool>(kv.GetNum("vanilla_sprite", false));
		gA_ZoneSettings[index][track].bNoHalo = view_as<bool>(kv.GetNum("no_halo", false));
		kv.GetString("beam", gA_ZoneSettings[index][track].sBeam, sizeof(zone_settings_t::sBeam), "");

		i++;
	}

	while(kv.GotoNextKey(false));

	delete kv;

	// copy bonus#1 settings to the rest of the bonuses
	for (++track; track < TRACKS_SIZE; track++)
	{
		for (int type = 0; type < ZONETYPES_SIZE; type++)
		{
			gA_ZoneSettings[type][track] = gA_ZoneSettings[type][Track_Bonus];
		}
	}

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
	if(gH_DrawEverything == null)
	{
		gH_DrawEverything = CreateTimer(gCV_Interval.FloatValue, Timer_DrawEverything, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
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
	delete gH_DrawEverything;
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

public void Frame_HookButton(any data)
{
	int entity = EntRefToEntIndex(data);

	if(entity == INVALID_ENT_REFERENCE)
	{
		return;
	}

	char sName[32];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, 32);

	if(StrContains(sName, "climb_") == -1)
	{
		return;
	}

	int zone = -1;
	int track = Track_Main;

	if(StrContains(sName, "startbutton") != -1)
	{
		zone = Zone_Start;
	}

	else if(StrContains(sName, "endbutton") != -1)
	{
		zone = Zone_End;
	}

	if(StrContains(sName, "bonus") != -1)
	{
		track = Track_Bonus;
	}

	if(zone != -1)
	{
		gI_KZButtons[track][zone] = entity;
		Shavit_MarkKZMap();

		SDKHook(entity, SDKHook_UsePost, UsePost);
	}
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

	// Please follow this naming scheme for this zones https://github.com/PMArkive/fly#trigger_multiple
	// mod_zone_start
	// mod_zone_end
	// mod_zone_checkpoint_X
	// mod_zone_bonus_X_start
	// mod_zone_bonus_X_end
	// mod_zone_bonus_X_checkpoint_X

	if(StrContains(sName, "mod_zone_") == -1)
	{
		return;
	}

	// Normalize some zone names that bhop_somp_island and bhop_overthinker use
	if (StrEqual(sName, "mod_zone_start_bonus") || StrEqual(sName, "mod_zone_bonus_start"))
	{
		sName = "mod_zone_bonus_1_start";
	}
	else if (StrEqual(sName, "mod_zone_end_bonus") || StrEqual(sName, "mod_zone_bonus_end"))
	{
		sName = "mod_zone_bonus_1_end";
	}

	int zone = -1;
	int zonedata = 0;
	int track = Track_Main;

	if(StrContains(sName, "start") != -1)
	{
		zone = Zone_Start;
	}
	else if(StrContains(sName, "end") != -1)
	{
		zone = Zone_End;
	}

	if(StrContains(sName, "bonus") != -1 || StrContains(sName, "checkpoint") != -1)
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
				return;
			}
		}

		if (StrContains(sName, "checkpoint") != -1)
		{
			zone = Zone_Stage;
			zonedata = StringToInt(sections[iCheckpointIndex]);

			if (zonedata <= 0 || zonedata > MAX_STAGES)
			{
				LogError("invalid stage number in prebuilt map zone (%s) on %s", sName, gS_Map);
				return;
			}
		}
	}

	if(zone != -1)
	{
		// TODO: Remove?
		if (zone == Zone_Start || zone == Zone_End)
		{
			gI_KZButtons[track][zone] = entity;
			Shavit_MarkKZMap();
		}

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

	gH_SQL.Query(SQL_RefreshZones_Callback, sQuery, 0, DBPrio_High);
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
				hTransaction.AddQuery(sQuery);
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
}

public void OnClientAuthorized(int client)
{
	if (gB_Connected && !IsFakeClient(client))
	{
		GetStartPosition(client);
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

	gH_SQL.Query(SQL_GetStartPosition_Callback, query, GetClientSerial(client));
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

	if(!InsideZone(client, Zone_Start, track))
	{
		Shavit_PrintToChat(client, "%T", "SetStartNotInStartZone", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);
		
		return Plugin_Handled;
	}
	
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
	
	gH_SQL.Query(SQL_InsertStartPosition_Callback, query);
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

	gH_SQL.Query(SQL_DeleteSetStart_Callback, query);
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

		gH_SQL.Query(SQL_DeleteCustom_Spawn_Callback, sQuery, GetClientSerial(param1));
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

		for(int i = 0; i < sizeof(gS_ZoneNames); i++)
		{
			if(i == Zone_CustomSpawn)
			{
				continue;
			}

			IntToString(i, sInfo, 8);
			submenu.AddItem(sInfo, gS_ZoneNames[i]);
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

Action OpenEditMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ZoneEdit);
	menu.SetTitle("%T\n ", "ZoneEditTitle", client);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "ZoneEditRefresh", client);
	menu.AddItem("-2", sDisplay);

	for(int i = 0; i < gI_MapZones; i++)
	{
		if(!gA_ZoneCache[i].bZoneInitialized)
		{
			continue;
		}

		char sInfo[8];
		IntToString(i, sInfo, 8);

		char sPrebuilt[16];
		sPrebuilt = gA_ZoneCache[i].bPrebuilt ? " (prebuilt)" : "";

		char sTrack[32];
		GetTrackName(client, gA_ZoneCache[i].iZoneTrack, sTrack, 32);

		if(gA_ZoneCache[i].iZoneType == Zone_CustomSpeedLimit || gA_ZoneCache[i].iZoneType == Zone_Stage || gA_ZoneCache[i].iZoneType == Zone_Airaccelerate)
		{
			FormatEx(sDisplay, 64, "#%d - %s %d (%s)%s", (i + 1), gS_ZoneNames[gA_ZoneCache[i].iZoneType], gA_ZoneCache[i].iZoneData, sTrack, sPrebuilt);
		}
		else
		{
			FormatEx(sDisplay, 64, "#%d - %s (%s)%s", (i + 1), gS_ZoneNames[gA_ZoneCache[i].iZoneType], sTrack, sPrebuilt);
		}

		if(gB_InsideZoneID[client][i])
		{
			Format(sDisplay, 64, "%s %T", sDisplay, "ZoneInside", client);
		}

		menu.AddItem(sInfo, sDisplay, gA_ZoneCache[i].bPrebuilt ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	if(menu.ItemCount == 0)
	{
		FormatEx(sDisplay, 64, "%T", "ZonesMenuNoneFound", client);
		menu.AddItem("-1", sDisplay);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);

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
				OpenEditMenu(param1);
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

public Action Command_DeleteZone(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	return OpenDeleteMenu(client);
}

Action OpenDeleteMenu(int client)
{
	Menu menu = new Menu(MenuHandler_DeleteZone);
	menu.SetTitle("%T\n ", "ZoneMenuDeleteTitle", client);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "ZoneEditRefresh", client);
	menu.AddItem("-2", sDisplay);

	for(int i = 0; i < gI_MapZones; i++)
	{
		if (gA_ZoneCache[i].bZoneInitialized)
		{
			char sPrebuilt[16];
			sPrebuilt = gA_ZoneCache[i].bPrebuilt ? " (prebuilt)" : "";

			char sTrack[32];
			GetTrackName(client, gA_ZoneCache[i].iZoneTrack, sTrack, 32);

			if(gA_ZoneCache[i].iZoneType == Zone_CustomSpeedLimit || gA_ZoneCache[i].iZoneType == Zone_Stage || gA_ZoneCache[i].iZoneType == Zone_Airaccelerate)
			{
				FormatEx(sDisplay, 64, "#%d - %s %d (%s)%s", (i + 1), gS_ZoneNames[gA_ZoneCache[i].iZoneType], gA_ZoneCache[i].iZoneData, sTrack, sPrebuilt);
			}
			else
			{
				FormatEx(sDisplay, 64, "#%d - %s (%s)%s", (i + 1), gS_ZoneNames[gA_ZoneCache[i].iZoneType], sTrack, sPrebuilt);
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

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "ZonesMenuNoneFound", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);

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
				OpenDeleteMenu(param1);
			}

			case -1:
			{
				Shavit_PrintToChat(param1, "%T", "ZonesMenuNoneFound", param1);
			}

			default:
			{
				Shavit_LogMessage("%L - deleted %s (id %d) from map `%s`.", param1, gS_ZoneNames[gA_ZoneCache[id].iZoneType], gA_ZoneCache[id].iDatabaseID, gS_Map);

				char sQuery[256];
				FormatEx(sQuery, 256, "DELETE FROM %smapzones WHERE %s = %d;", gS_MySQLPrefix, (gB_MySQL)? "id":"rowid", gA_ZoneCache[id].iDatabaseID);

				DataPack hDatapack = new DataPack();
				hDatapack.WriteCell(GetClientSerial(param1));
				hDatapack.WriteCell(gA_ZoneCache[id].iZoneType);

				gH_SQL.Query(SQL_DeleteZone_Callback, sQuery, hDatapack);
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

	Shavit_PrintToChat(client, "%T", "ZoneDeleteSuccessful", client, gS_ChatStrings.sVariable, gS_ZoneNames[type], gS_ChatStrings.sText);
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
			return;
		}

		Shavit_LogMessage("%L - deleted all zones from map `%s`.", param1, gS_Map);

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "DELETE FROM %smapzones WHERE map = '%s';", gS_MySQLPrefix, gS_Map);

		gH_SQL.Query(SQL_DeleteAllZones_Callback, sQuery, GetClientSerial(param1));
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}
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
		gI_ZoneData[client] = StringToInt(sArgs);
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
	char sTrack[64];
	GetTrackName(LANG_SERVER, gI_ZoneTrack[client], sTrack, sizeof(sTrack));

	if(iType == Zone_CustomSpawn)
	{
		Shavit_LogMessage("%L - added custom spawn {%.2f, %.2f, %.2f} to map `%s`.", client, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gS_Map);

		FormatEx(sQuery, sizeof(sQuery), 
			"INSERT INTO %smapzones (map, type, destination_x, destination_y, destination_z, track) VALUES ('%s', %d, '%.03f', '%.03f', '%.03f', %d);",
			gS_MySQLPrefix, gS_Map, Zone_CustomSpawn, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gI_ZoneTrack[client]);
	}

	else if(bInsert) // insert
	{
		Shavit_LogMessage("%L - added %s %s to map `%s`.", client, sTrack, gS_ZoneNames[iType], gS_Map);

		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO %smapzones (map, type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, destination_x, destination_y, destination_z, track, flags, data) VALUES ('%s', %d, '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', %d, %d, %d);",
			gS_MySQLPrefix, gS_Map, iType, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gV_Teleport[client][0], gV_Teleport[client][1], gV_Teleport[client][2], gI_ZoneTrack[client], gI_ZoneFlags[client], gI_ZoneData[client]);
	}

	else // update
	{
		Shavit_LogMessage("%L - updated %s %s in map `%s`.", client, sTrack, gS_ZoneNames[iType], gS_Map);

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

	gH_SQL.Query(SQL_InsertZone_Callback, sQuery, GetClientSerial(client));
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

public Action Timer_DrawEverything(Handle Timer)
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
						gA_ZoneSettings[type][track].iHalo);
				++iDrawn;
			}

			if(++iDrawn % iMaxZonesPerFrame == 0)
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

		DrawZone(points, GetZoneColors(type, track, 125), 0.1, gA_ZoneSettings[type][track].fWidth, false, origin, gI_BeamSpriteIgnoreZ, gA_ZoneSettings[type][track].iHalo);

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

void DrawZone(float points[8][3], int color[4], float life, float width, bool flat, float center[3], int beam, int halo)
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

	int clients[MAXPLAYERS+1];
	int count = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			float eyes[3];
			GetClientEyePosition(i, eyes);

			if(GetVectorDistance(eyes, center) <= 2048.0 ||
				(TR_TraceRayFilter(eyes, center, MASK_PLAYERSOLID, RayType_EndPoint, TraceFilter_World) && !TR_DidHit()))
			{
				clients[count++] = i;
			}
		}
	}

	for(int i = 0; i < ((flat)? 4:12); i++)
	{
		TE_SetupBeamPoints(points[pairs[i][0]], points[pairs[i][1]], beam, halo, 0, 0, life, width, width, 0, 0.0, color, 0);
		TE_Send(clients, count, 0.0);
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

	Transaction2 hTransaction = new Transaction2();

	char sQuery[1024];
	FormatEx(sQuery, 1024,
		"CREATE TABLE IF NOT EXISTS `%smapzones` (`id` INT AUTO_INCREMENT, `map` VARCHAR(128), `type` INT, `corner1_x` FLOAT, `corner1_y` FLOAT, `corner1_z` FLOAT, `corner2_x` FLOAT, `corner2_y` FLOAT, `corner2_z` FLOAT, `destination_x` FLOAT NOT NULL DEFAULT 0, `destination_y` FLOAT NOT NULL DEFAULT 0, `destination_z` FLOAT NOT NULL DEFAULT 0, `track` INT NOT NULL DEFAULT 0, `flags` INT NOT NULL DEFAULT 0, `data` INT NOT NULL DEFAULT 0, `prebuilt` BOOL, PRIMARY KEY (`id`))%s;",
		gS_MySQLPrefix, (gB_MySQL)? " ENGINE=INNODB":"");

	hTransaction.AddQuery(sQuery);

	FormatEx(sQuery, 1024,
		"CREATE TABLE IF NOT EXISTS `%sstartpositions` (`auth` INTEGER NOT NULL, `track` INTEGER NOT NULL, `map` VARCHAR(128) NOT NULL, `pos_x` FLOAT, `pos_y` FLOAT, `pos_z` FLOAT, `ang_x` FLOAT, `ang_y` FLOAT, `ang_z` FLOAT, `angles_only` BOOL, PRIMARY KEY (`auth`, `track`, `map`))%s;",
		gS_MySQLPrefix, (gB_MySQL)? " ENGINE=INNODB":"");

	hTransaction.AddQuery(sQuery);

	gH_SQL.Execute(hTransaction, Trans_CreateTable_Success, Trans_CreateTable_Failed);
}

public void Trans_CreateTable_Success(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	gB_Connected = true;
	OnMapStart();
}

public void Trans_CreateTable_Failed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (zones module) error! Map zones' table creation failed %d/%d. Reason: %s", failIndex, numQueries, error);
}

public void Shavit_OnRestart(int client, int track)
{
	gI_LastStage[client] = 0;

	if(gCV_TeleportToStart.BoolValue)
	{
		int iIndex = -1;

		// custom spawns
		if(!EmptyVector(gF_CustomSpawn[track]))
		{
			TeleportEntity(client, gF_CustomSpawn[track], NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}

		// standard zoning
		else if((iIndex = GetZoneIndex(Zone_Start, track)) != -1)
		{
			float fCenter[3], fCustomStart[3];
			fCenter[0] = gV_ZoneCenter[iIndex][0];
			fCenter[1] = gV_ZoneCenter[iIndex][1];
			fCenter[2] = gV_MapZones[iIndex][0][2] + 1.0; // no stuck in floor please

			bool bCustomStart = false;

			if(gB_HasSetStart[client][track] && !gB_StartAnglesOnly[client][track])
			{
				float bmin[3], bmax[3];
				FillBoxMinMax(gV_MapZones[iIndex][0], gV_MapZones[iIndex][1], bmin, bmax);
				bmin[2] -= 0.01; // help fix some slight float accuracy loss for things like bhop_pisjapahnetribkoj

				fCustomStart = gF_StartPos[client][track];
				fCustomStart[2] += 1.0;

				bCustomStart = PointInBox(fCustomStart, bmin, bmax);
			}

			TeleportEntity(client, bCustomStart ? fCustomStart : fCenter, gB_HasSetStart[client][track] ? gF_StartAng[client][track] : NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}

		// kz buttons
		else if(Shavit_IsKZMap() && !EmptyVector(gF_ClimbButtonCache[client][track][0]) && !EmptyVector(gF_ClimbButtonCache[client][track][1]))
		{
			TeleportEntity(client, gF_ClimbButtonCache[client][track][0], gF_ClimbButtonCache[client][track][1], view_as<float>({0.0, 0.0, 0.0}));

			return;
		}

		// Just let TouchPost/TouchPost_Trigger handle it so setstarts outside of a start zone don't start.
		if (!gB_HasSetStart[client][track] || gB_StartAnglesOnly[client][track])
		{
			Shavit_StartTimer(client, track);
		}
	}
}

public void Shavit_OnEnd(int client, int track)
{
	if(gCV_TeleportToEnd.BoolValue)
	{
		int iIndex = -1;

		if((iIndex = GetZoneIndex(Zone_End, track)) != -1)
		{
			float fCenter[3];
			fCenter[0] = gV_ZoneCenter[iIndex][0];
			fCenter[1] = gV_ZoneCenter[iIndex][1];
			fCenter[2] = gV_MapZones[iIndex][0][2] + 1.0; // no stuck in floor please

			TeleportEntity(client, fCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}
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
	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		gI_KZButtons[i][0] = -1;
		gI_KZButtons[i][1] = -1;
	}

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
		min[0] = -distance_x + gCV_BoxOffset.FloatValue;
		min[1] = -distance_y + gCV_BoxOffset.FloatValue;
		min[2] = -distance_z + height;
		SetEntPropVector(entity, Prop_Send, "m_vecMins", min);

		float max[3];
		max[0] = distance_x - gCV_BoxOffset.FloatValue;
		max[1] = distance_y - gCV_BoxOffset.FloatValue;
		max[2] = distance_z - height;
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
			char special[sizeof(stylestrings_t::sSpecialString)];
			Shavit_GetStyleStrings(Shavit_GetBhopStyle(other), sSpecialString, special, sizeof(special));

			if (status == Timer_Running && Shavit_GetClientTrack(other) == gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack && (num > gI_LastStage[other] || StrContains(special, "segments") != -1 || StrContains(special, "TAS") != -1 || Shavit_IsPracticeMode(other)))
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
			if(GetEntPropEnt(other, Prop_Send, "m_hGroundEntity") == -1)
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

void GetButtonInfo(int entity, int &zone, int &track)
{
	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		for(int j = 0; j < 2; j++)
		{
			if(gI_KZButtons[i][j] == entity)
			{
				zone = j;
				track = i;

				return;
			}
		}
	}
}

public void UsePost(int entity, int activator, int caller, UseType type, float value)
{
	if(activator < 1 || activator > MaxClients || IsFakeClient(activator) || GetEntPropEnt(activator, Prop_Send, "m_hGroundEntity") == -1)
	{
		return;
	}

	int zone = -1;
	int track = Track_Main;

	GetButtonInfo(entity, zone, track);

	if(zone == Zone_Start)
	{
		GetClientAbsOrigin(activator, gF_ClimbButtonCache[activator][track][0]);
		GetClientEyeAngles(activator, gF_ClimbButtonCache[activator][track][1]);

		Shavit_StartTimer(activator, track);
	}

	if(zone == Zone_End && !Shavit_IsPaused(activator) && Shavit_GetTimerStatus(activator) == Timer_Running && Shavit_GetClientTrack(activator) == track)
	{
		Shavit_FinishMap(activator, track);
	}
}
