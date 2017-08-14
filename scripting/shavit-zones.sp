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
#include <cstrike>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <adminmenu>

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

EngineVersion gEV_Type = Engine_Unknown;

Database gH_SQL = null;
bool gB_MySQL = false;
bool gB_DBReady = false;

char gS_Map[160];

char gS_ZoneNames[][] =
{
	"Start Zone", // starts timer
	"End Zone", // stops timer
	"Glitch Zone (Respawn Player)", // respawns the player
	"Glitch Zone (Stop Timer)", // stops the player's timer
	"Slay Player", // slays (kills) players which come to this zone
	"Freestyle Zone", // ignores style physics when at this zone. e.g. WASD when SWing
	"No Speed Limit", // ignores velocity limit in that zone
	"Teleport Zone", // teleports to a defined point
	"SPAWN POINT", // << unused
	"Easybhop Zone" // forces easybhop whether if the player is in non-easy styles or if the server has different settings
};

enum
{
	bVisible,
	iRed,
	iGreen,
	iBlue,
	iAlpha,
	fWidth,
	ZONESETTINGS_SIZE
}

int gI_ZoneType[MAXPLAYERS+1];

// 0 - nothing
// 1 - wait for E tap to setup first coord
// 2 - wait for E tap to setup second coord
// 3 - confirm
int gI_MapStep[MAXPLAYERS+1];

float gF_Modifier[MAXPLAYERS+1];
int gI_GridSnap[MAXPLAYERS+1];
bool gB_SnapToWall[MAXPLAYERS+1];
bool gB_CursorTracing[MAXPLAYERS+1];

// Cache.
float gV_Point1[MAXPLAYERS+1][3];
float gV_Point2[MAXPLAYERS+1][3];
float gV_Teleport[MAXPLAYERS+1][3];
float gV_OldPosition[MAXPLAYERS+1][3];
float gV_WallSnap[MAXPLAYERS+1][3];
bool gB_Button[MAXPLAYERS+1];
bool gB_InsideZone[MAXPLAYERS+1][ZONETYPES_SIZE][TRACKS_SIZE];
bool gB_InsideZoneID[MAXPLAYERS+1][MAX_ZONES];
float gF_CustomSpawn[3];
int gI_ZoneTrack[MAXPLAYERS+1];
int gI_ZoneDatabaseID[MAXPLAYERS+1];

// Zone cache.
any gA_ZoneSettings[ZONETYPES_SIZE][ZONESETTINGS_SIZE];
any gA_ZoneCache[MAX_ZONES][ZONECACHE_SIZE]; // Vectors will not be inside this array.
int gI_MapZones = 0;
float gV_MapZones[MAX_ZONES][2][3];
float gV_MapZones_Visual[MAX_ZONES][8][3];
float gV_Destinations[MAX_ZONES][3];
float gV_ZoneCenter[MAX_ZONES][3];
int gI_EntityZone[4096];
bool gB_ZonesCreated = false;

char gS_BeamSprite[PLATFORM_MAX_PATH];
int gI_BeamSprite = -1;
int gI_HaloSprite = -1;

// admin menu
Handle gH_AdminMenu = INVALID_HANDLE;

// cache
bool gB_Late = false;
bool gB_Shavit = false;

// cvars
ConVar gCV_FlatZones = null;
ConVar gCV_Interval = null;
ConVar gCV_TeleportToStart = null;
ConVar gCV_TeleportToEnd = null;
ConVar gCV_UseCustomSprite = null;
ConVar gCV_Height = null;
ConVar gCV_Offset = null;

// cached cvars
bool gB_FlatZones = false;
float gF_Interval = 1.0;
bool gB_TeleportToStart = true;
bool gB_TeleportToEnd = true;
bool gB_UseCustomSprite = true;
float gF_Height = 128.0;
float gF_Offset = 0.5;

// handles
Handle gH_DrawEverything = null;

// table prefix
char gS_MySQLPrefix[32];

// chat settings
char gS_ChatStrings[CHATSETTINGS_SIZE][128];

// forwards
Handle gH_Forwards_EnterZone = null;
Handle gH_Forwards_LeaveZone = null;

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
	CreateNative("Shavit_ZoneExists", Native_ZoneExists);
	CreateNative("Shavit_InsideZone", Native_InsideZone);
	CreateNative("Shavit_IsClientCreatingZone", Native_IsClientCreatingZone);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-zones");

	gB_Late = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	if(gB_Late)
	{
		OnAdminMenuReady(null);
	}
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

	RegAdminCmd("sm_addspawn", Command_AddSpawn,  ADMFLAG_RCON, "Adds a custom spawn location");
	RegAdminCmd("sm_delspawn", Command_DelSpawn,  ADMFLAG_RCON, "Deletes a custom spawn location");

	RegAdminCmd("sm_zoneedit", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone.");
	RegAdminCmd("sm_editzone", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone. Alias of sm_zoneedit.");
	RegAdminCmd("sm_modifyzone", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone. Alias of sm_zoneedit.");
	
	RegAdminCmd("sm_reloadzonesettings", Command_ReloadZoneSettings, ADMFLAG_ROOT, "Reloads the zone settings.");

	// events
	HookEvent("player_spawn", Player_Spawn);
	HookEvent("round_start", Round_Start);

	// forwards
	gH_Forwards_EnterZone = CreateGlobalForward("Shavit_OnEnterZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_LeaveZone = CreateGlobalForward("Shavit_OnLeaveZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	// cvars and stuff
	gCV_FlatZones = CreateConVar("shavit_zones_flat", "0", "Should zones be drawn as flat instead of a 3D box?", 0, true, 0.0, true, 1.0);
	gCV_Interval = CreateConVar("shavit_zones_interval", "1.0", "Interval between each time a mapzone is being drawn to the players.", 0, true, 0.5, true, 5.0);
	gCV_TeleportToStart = CreateConVar("shavit_zones_teleporttostart", "1", "Teleport players to the start zone on timer restart?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_TeleportToEnd = CreateConVar("shavit_zones_teleporttoend", "1", "Teleport players to the end zone on sm_end?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_UseCustomSprite = CreateConVar("shavit_zones_usecustomsprite", "1", "Use custom sprite for zone drawing?\nSee `configs/shavit-zones.cfg`.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_Height = CreateConVar("shavit_zones_height", "128.0", "Height to use for the start zone.", 0, true, 0.0, false);
	gCV_Offset = CreateConVar("shavit_zones_offset", "0.5", "When calculating a zone's *VISUAL* box, by how many units, should we scale it to the center?\n0.0 - no downscaling. Values above 0 will scale it inward and negative numbers will scale it outwards.\nAdjust this value if the zones clip into walls.");

	gCV_FlatZones.AddChangeHook(OnConVarChanged);
	gCV_Interval.AddChangeHook(OnConVarChanged);
	gCV_TeleportToStart.AddChangeHook(OnConVarChanged);
	gCV_TeleportToEnd.AddChangeHook(OnConVarChanged);
	gCV_UseCustomSprite.AddChangeHook(OnConVarChanged);
	gCV_Height.AddChangeHook(OnConVarChanged);
	gCV_Offset.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	gB_Shavit = LibraryExists("shavit");

	if(gB_Shavit)
	{
		Shavit_GetDB(gH_SQL);
		SQL_SetPrefix();
		SetSQLInfo();
	}
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gB_FlatZones = gCV_FlatZones.BoolValue;
	gF_Interval = gCV_Interval.FloatValue;
	gB_TeleportToStart = gCV_TeleportToStart.BoolValue;
	gB_UseCustomSprite = gCV_UseCustomSprite.BoolValue;
	gB_TeleportToEnd = gCV_TeleportToEnd.BoolValue;
	gF_Height = gCV_Height.FloatValue;
	gF_Offset = gCV_Offset.FloatValue;

	if(convar == gCV_Interval)
	{
		delete gH_DrawEverything;
		gH_DrawEverything = CreateTimer(gF_Interval, Timer_DrawEverything, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}

	else if(convar == gCV_Offset && gI_MapZones > 0)
	{
		for(int i = 0; i < gI_MapZones; i++)
		{
			if(!gA_ZoneCache[i][bZoneInitialized])
			{
				continue;
			}

			gV_MapZones_Visual[i][0][0] = gV_MapZones[i][0][0];
			gV_MapZones_Visual[i][0][1] = gV_MapZones[i][0][1];
			gV_MapZones_Visual[i][0][2] = gV_MapZones[i][0][2];
			gV_MapZones_Visual[i][7][0] = gV_MapZones[i][1][0];
			gV_MapZones_Visual[i][7][1] = gV_MapZones[i][1][1];
			gV_MapZones_Visual[i][7][2] = gV_MapZones[i][1][2];

			CreateZonePoints(gV_MapZones_Visual[i], gF_Offset);
		}
	}

	else if(convar == gCV_UseCustomSprite && !StrEqual(oldValue, newValue))
	{
		LoadZoneSettings();
	}
}

public Action CheckForSQLInfo(Handle Timer)
{
	return SetSQLInfo();
}

Action SetSQLInfo()
{
	if(gH_SQL == null)
	{
		Shavit_GetDB(gH_SQL);

		CreateTimer(0.5, CheckForSQLInfo);
	}

	else
	{
		SQL_DBConnect();

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit"))
	{
		gB_Shavit = true;
		
		Shavit_GetDB(gH_SQL);
		SQL_SetPrefix();
		SetSQLInfo();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit"))
	{
		gB_Shavit = false;
		gH_SQL = null;
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	if(LibraryExists("adminmenu") && ((gH_AdminMenu = GetAdminTopMenu()) != null))
	{
		TopMenuObject tmoTimer = FindTopMenuCategory(gH_AdminMenu, "Timer Commands");

		if(tmoTimer != INVALID_TOPMENUOBJECT)
		{
			AddToTopMenu(gH_AdminMenu, "sm_zones", TopMenuObject_Item, AdminMenu_Zones, tmoTimer, "sm_zones", ADMFLAG_RCON);
			AddToTopMenu(gH_AdminMenu, "sm_deletezone", TopMenuObject_Item, AdminMenu_DeleteZone, tmoTimer, "sm_deletezone", ADMFLAG_RCON);
			AddToTopMenu(gH_AdminMenu, "sm_deleteallzones", TopMenuObject_Item, AdminMenu_DeleteAllZones, tmoTimer, "sm_deleteallzones", ADMFLAG_RCON);
			AddToTopMenu(gH_AdminMenu, "sm_zoneedit", TopMenuObject_Item, AdminMenu_ZoneEdit, tmoTimer, "sm_zoneedit", ADMFLAG_RCON);
		}
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

public void AdminMenu_Zones(Handle topmenu,  TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
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

public void AdminMenu_DeleteZone(Handle topmenu,  TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
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

public void AdminMenu_ZoneEdit(Handle topmenu,  TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
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

public int Native_InsideZone(Handle handler, int numParams)
{
	return InsideZone(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3));
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

bool LoadZonesConfig()
{
	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-zones.cfg");

	KeyValues kv = new KeyValues("shavit-zones");
	
	if(!kv.ImportFromFile(sPath))
	{
		delete kv;

		return false;
	}

	kv.JumpToKey("Sprites");
	kv.GetString("beam", gS_BeamSprite, PLATFORM_MAX_PATH);

	char[] sDownloads = new char[PLATFORM_MAX_PATH * 8];
	kv.GetString("downloads", sDownloads, (PLATFORM_MAX_PATH * 8));

	char[][] sDownloadsExploded = new char[PLATFORM_MAX_PATH][PLATFORM_MAX_PATH];
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

	do
	{
		gA_ZoneSettings[i][bVisible] = view_as<bool>(kv.GetNum("visible", 1));
		gA_ZoneSettings[i][iRed] = kv.GetNum("red", 255);
		gA_ZoneSettings[i][iGreen] = kv.GetNum("green", 255);
		gA_ZoneSettings[i][iBlue] = kv.GetNum("blue", 255);
		gA_ZoneSettings[i][iAlpha] = kv.GetNum("alpha", 255);
		gA_ZoneSettings[i][fWidth] = kv.GetFloat("width", 2.0);

		i++;
	}

	while(kv.GotoNextKey(false));

	delete kv;

	return true;
}

void LoadZoneSettings()
{
	if(!LoadZonesConfig())
	{
		SetFailState("Cannot open \"configs/shavit-zones.cfg\". Make sure this file exists and that the server has read permissions to it.");
	}

	if(gB_UseCustomSprite)
	{
		gI_BeamSprite = PrecacheModel(gS_BeamSprite, true);
		gI_HaloSprite = 0;
	}

	else
	{
		if(gEV_Type == Engine_CSS)
		{
			gI_BeamSprite = PrecacheModel("sprites/laser.vmt", true);
			gI_HaloSprite = PrecacheModel("sprites/halo01.vmt", true);
		}

		else
		{
			gI_BeamSprite = PrecacheModel("sprites/laserbeam.vmt", true);
			gI_HaloSprite = PrecacheModel("sprites/glow01.vmt", true);
		}
	}

}

public void OnMapStart()
{
	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);

	gI_MapZones = 0;
	UnloadZones(0);

	if(gH_SQL != null && gB_DBReady)
	{
		RefreshZones();
	}

	LoadZoneSettings();
	
	PrecacheModel("models/props/cs_office/vending_machine.mdl");

	// draw
	// start drawing mapzones here
	gH_DrawEverything = CreateTimer(gF_Interval, Timer_DrawEverything, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

	if(gB_Late)
	{
		Shavit_OnChatConfigLoaded();
	}
}

public void Shavit_OnChatConfigLoaded()
{
	for(int i = 0; i < CHATSETTINGS_SIZE; i++)
	{
		Shavit_GetChatStrings(i, gS_ChatStrings[i], 128);
	}
}

void ClearZone(int index)
{
	for(int i = 0; i < 3; i++)
	{
		gV_MapZones[index][0][i] = 0.0;
		gV_MapZones[index][1][i] = 0.0;
		gV_Destinations[index][i] = 0.0;
		gV_ZoneCenter[index][i] = 0.0;
	}

	gA_ZoneCache[index][bZoneInitialized] = false;
	gA_ZoneCache[index][iZoneType] = -1;
	gA_ZoneCache[index][iZoneTrack] = -1;
	gA_ZoneCache[index][iEntityID] = -1;
	gA_ZoneCache[index][iDatabaseID] = -1;
}

void UnhookEntity(int entity)
{
	SDKUnhook(entity, SDKHook_StartTouchPost, StartTouchPost);
	SDKUnhook(entity, SDKHook_EndTouchPost, EndTouchPost);
	SDKUnhook(entity, SDKHook_TouchPost, TouchPost);
}

void KillZoneEntity(int index)
{
	int entity = gA_ZoneCache[index][iEntityID];
	
	if(entity > MaxClients && IsValidEntity(entity))
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			for(int j = 0; j < TRACKS_SIZE; j++)
			{
				gB_InsideZone[i][gA_ZoneCache[index][iZoneType]][j] = false;
			}

			gB_InsideZoneID[i][index] = false;
		}

		UnhookEntity(entity);
		AcceptEntityInput(entity, "Kill");
	}
}

// 0 - all zones
void UnloadZones(int zone)
{
	if(zone == Zone_CustomSpawn)
	{
		ClearCustomSpawn();
	}

	else
	{
		for(int i = 0; i < MAX_ZONES; i++)
		{
			if(zone == 0 || gA_ZoneCache[i][iZoneType] == zone)
			{
				if(gA_ZoneCache[i][bZoneInitialized])
				{
					KillZoneEntity(i);
					ClearZone(i);
				}
			}
		}

		ClearCustomSpawn();

		if(zone == 0)
		{
			gB_ZonesCreated = false;

			int iMaxEntities = GetMaxEntities();

			char[] sClassname = new char[32];
			char[] sTargetname = new char[32];

			for(int i = (MaxClients + 1); i < iMaxEntities; i++)
			{
				if(!IsValidEntity(i) 
					|| !GetEntityClassname(i, sClassname, 32) || !StrEqual(sClassname, "trigger_multiple")
					|| GetEntPropString(i, Prop_Data, "m_iName", sTargetname, 32) == 0 || StrContains(sTargetname, "shavit_zones_") == -1)
				{
					continue;
				}

				AcceptEntityInput(i, "Kill");
			}
		}

		return;
	}
}

void RefreshZones()
{
	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "SELECT type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, destination_x, destination_y, destination_z, track, %s FROM %smapzones WHERE map = '%s';", (gB_MySQL)? "id":"rowid", gS_MySQLPrefix, gS_Map);

	if(gH_SQL != null)
	{
		gH_SQL.Query(SQL_RefreshZones_Callback, sQuery, DBPrio_High);
	}

	else
	{
		Shavit_GetDB(gH_SQL);
	}
}

public void SQL_RefreshZones_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zone refresh) SQL query failed. Reason: %s", error);

		return;
	}

	gB_DBReady = true;
	gI_MapZones = 0;

	while(results.FetchRow())
	{
		int type = results.FetchInt(0);

		if(type == Zone_CustomSpawn)
		{
			gF_CustomSpawn[0] = results.FetchFloat(7);
			gF_CustomSpawn[1] = results.FetchFloat(8);
			gF_CustomSpawn[2] = results.FetchFloat(9);
		}

		else
		{
			gV_MapZones[gI_MapZones][0][0] = gV_MapZones_Visual[gI_MapZones][0][0] = results.FetchFloat(1);
			gV_MapZones[gI_MapZones][0][1] = gV_MapZones_Visual[gI_MapZones][0][1] = results.FetchFloat(2);
			gV_MapZones[gI_MapZones][0][2] = gV_MapZones_Visual[gI_MapZones][0][2] = results.FetchFloat(3);
			gV_MapZones[gI_MapZones][1][0] = gV_MapZones_Visual[gI_MapZones][7][0] = results.FetchFloat(4);
			gV_MapZones[gI_MapZones][1][1] = gV_MapZones_Visual[gI_MapZones][7][1] = results.FetchFloat(5);
			gV_MapZones[gI_MapZones][1][2] = gV_MapZones_Visual[gI_MapZones][7][2] = results.FetchFloat(6);

			CreateZonePoints(gV_MapZones_Visual[gI_MapZones], gF_Offset);

			gV_ZoneCenter[gI_MapZones][0] = (gV_MapZones[gI_MapZones][0][0] + gV_MapZones[gI_MapZones][1][0]) / 2.0;
			gV_ZoneCenter[gI_MapZones][1] = (gV_MapZones[gI_MapZones][0][1] + gV_MapZones[gI_MapZones][1][1]) / 2.0;
			gV_ZoneCenter[gI_MapZones][2] = (gV_MapZones[gI_MapZones][0][2] + gV_MapZones[gI_MapZones][1][2]) / 2.0;

			if(type == Zone_Teleport)
			{
				gV_Destinations[gI_MapZones][0] = results.FetchFloat(7);
				gV_Destinations[gI_MapZones][1] = results.FetchFloat(8);
				gV_Destinations[gI_MapZones][2] = results.FetchFloat(9);
			}

			gA_ZoneCache[gI_MapZones][bZoneInitialized] = true;
			gA_ZoneCache[gI_MapZones][iZoneType] = type;
			gA_ZoneCache[gI_MapZones][iZoneTrack] = results.FetchInt(10);
			gA_ZoneCache[gI_MapZones][iDatabaseID] = results.FetchInt(11);
			gA_ZoneCache[gI_MapZones][iEntityID] = -1;

			gI_MapZones++;
		}
	}

	CreateZoneEntities();
}

public void OnClientPutInServer(int client)
{
	for(int i = 0; i < ZONETYPES_SIZE; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gB_InsideZone[client][i][j] = false;
		}
	}

	for(int i = 0; i < MAX_ZONES; i++)
	{
		gB_InsideZoneID[client][i] = false;
	}

	Reset(client);
}

public void OnClientDisconnect(int client)
{
	Reset(client);
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

	char[] sArg1 = new char[16];
	GetCmdArg(1, sArg1, 16);

	float fArg1 = StringToFloat(sArg1);

	if(fArg1 <= 0.0)
	{
		Shavit_PrintToChat(client, "%T", "ModifierTooLow", client);

		return Plugin_Handled;
	}

	gF_Modifier[client] = fArg1;

	Shavit_PrintToChat(client, "%T %s%.01f%s.", "ModifierSet", client, gS_ChatStrings[sMessageVariable], fArg1, gS_ChatStrings[sMessageText]);

	return Plugin_Handled;
}

//Krypt Custom Spawn Functions (https://github.com/Kryptanyte)
public Action Command_AddSpawn(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "ZoneDead", client);

		return Plugin_Handled;
	}

	if(!EmptyVector(gF_CustomSpawn))
	{
		Shavit_PrintToChat(client, "%T", "ZoneCustomSpawnExists", client);

		return Plugin_Handled;
	}

	gI_ZoneType[client] = Zone_CustomSpawn;

	GetClientAbsOrigin(client, gV_Point1[client]);
	InsertZone(client);

	return Plugin_Handled;
}

public Action Command_DelSpawn(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "DELETE FROM %smapzones WHERE type = '%d' AND map = '%s';", gS_MySQLPrefix, Zone_CustomSpawn, gS_Map);

	gH_SQL.Query(SQL_DeleteCustom_Spawn_Callback, sQuery, GetClientSerial(client));

	return Plugin_Handled;
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

	ClearCustomSpawn();

	Shavit_PrintToChat(client, "%T", "ZoneCustomSpawnDelete", client);
}

void ClearCustomSpawn()
{
	for(int i = 0; i < 3; i++)
	{
		gF_CustomSpawn[i] = 0.0;
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

public Action Command_Zones(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "%T", "ZonesCommand", client, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	Reset(client);

	Menu menu = new Menu(Select_Type_MenuHandler);
	menu.SetTitle("%T", "ZoneMenuTitle", client);

	for(int i = 0; i < sizeof(gS_ZoneNames); i++)
	{
		if(i == Zone_CustomSpawn)
		{
			continue;
		}

		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		menu.AddItem(sInfo, gS_ZoneNames[i]);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);

	return Plugin_Handled;
}

Action OpenEditMenu(int client)
{
	Menu menu = new Menu(ZoneEdit_MenuHandler);
	menu.SetTitle("%T\n ", "ZoneEditTitle", client);

	char[] sDisplay = new char[64];
	FormatEx(sDisplay, 64, "%T", "ZoneEditRefresh", client);
	menu.AddItem("-2", sDisplay);

	for(int i = 0; i < sizeof(gS_ZoneNames); i++)
	{
		if(!gA_ZoneCache[i][bZoneInitialized])
		{
			continue;
		}

		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		char[] sTrack = new char[32];
		GetTrackName(client, gA_ZoneCache[i][iZoneTrack], sTrack, 32);

		FormatEx(sDisplay, 64, "#%d - %s (%s)", (i + 1), gS_ZoneNames[gA_ZoneCache[i][iZoneType]], sTrack);

		if(gB_InsideZoneID[client][i])
		{
			Format(sDisplay, 64, "%s %T", sDisplay, "ZoneInside", client);
		}

		menu.AddItem(sInfo, sDisplay);
	}

	if(menu.ItemCount == 0)
	{
		FormatEx(sDisplay, 64, "%T", "ZonesMenuNoneFound", client);
		menu.AddItem("-1", sDisplay);
	}

	menu.ExitButton = true;
	menu.Display(client, 120);

	return Plugin_Handled;
}

public int ZoneEdit_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[8];
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
				gI_ZoneType[param1] = gA_ZoneCache[id][iZoneType];
				gI_ZoneTrack[param1] = gA_ZoneCache[id][iZoneTrack];
				gV_Teleport[param1] = gV_Destinations[id];
				gI_ZoneDatabaseID[param1] = gA_ZoneCache[id][iDatabaseID];

				// to stop the original zone from drawing
				gA_ZoneCache[id][bZoneInitialized] = false;

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
	Menu menu = new Menu(DeleteZone_MenuHandler);
	menu.SetTitle("%T\n ", "ZoneMenuDeleteTitle", client);

	char[] sDisplay = new char[64];
	FormatEx(sDisplay, 64, "%T", "ZoneEditRefresh", client);
	menu.AddItem("-2", sDisplay);

	for(int i = 0; i < gI_MapZones; i++)
	{
		if(gA_ZoneCache[i][bZoneInitialized])
		{
			char[] sTrack = new char[32];
			GetTrackName(client, gA_ZoneCache[i][iZoneTrack], sTrack, 32);

			FormatEx(sDisplay, 64, "#%d - %s (%s)", (i + 1), gS_ZoneNames[gA_ZoneCache[i][iZoneType]], sTrack);

			char[] sInfo = new char[8];
			IntToString(i, sInfo, 8);
			
			if(gB_InsideZoneID[client][i])
			{
				Format(sDisplay, 64, "%s %T", sDisplay, "ZoneInside", client);
			}

			menu.AddItem(sInfo, sDisplay);
		}
	}

	if(menu.ItemCount == 0)
	{
		char[] sMenuItem = new char[64];
		FormatEx(sMenuItem, 64, "%T", "ZonesMenuNoneFound", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);

	return Plugin_Handled;
}

public int DeleteZone_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[8];
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
				char[] sQuery = new char[256];
				FormatEx(sQuery, 256, "DELETE FROM %smapzones WHERE %s = %d;", gS_MySQLPrefix, (gB_MySQL)? "id":"rowid", gA_ZoneCache[id][iDatabaseID]);

				DataPack hDatapack = new DataPack();
				hDatapack.WriteCell(GetClientSerial(param1));
				hDatapack.WriteCell(gA_ZoneCache[id][iZoneType]);

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

public void SQL_DeleteZone_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	ResetPack(data);
	int client = GetClientFromSerial(ReadPackCell(data));
	int type = ReadPackCell(data);

	delete view_as<DataPack>(data);

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

	Shavit_PrintToChat(client, "%T", "ZoneDeleteSuccessful", client, gS_ChatStrings[sMessageVariable], gS_ZoneNames[type], gS_ChatStrings[sMessageText]);
}

public Action Command_DeleteAllZones(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(DeleteAllZones_MenuHandler);
	menu.SetTitle("%T", "ZoneMenuDeleteALLTitle", client);

	char[] sMenuItem = new char[64];

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

	menu.Display(client, 20);

	return Plugin_Handled;
}

public int DeleteAllZones_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[8];
		menu.GetItem(param2, info, 8);

		int iInfo = StringToInt(info);

		if(iInfo == -1)
		{
			return;
		}

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "DELETE FROM %smapzones WHERE map = '%s';", gS_MySQLPrefix, gS_Map);

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

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	Shavit_PrintToChat(client, "%T", "ZoneDeleteAllSuccessful", client);
}

public int Select_Type_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[8];
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
	gF_Modifier[client] = 10.0;
	gI_MapStep[client] = 0;
	gI_GridSnap[client] = 16;
	gB_SnapToWall[client] = false;
	gB_CursorTracing[client] = false;
	gI_ZoneDatabaseID[client] = -1;

	for(int i = 0; i < 3; i++)
	{
		gV_Point1[client][i] = 0.0;
		gV_Point2[client][i] = 0.0;
		gV_Teleport[client][i] = 0.0;
		gV_OldPosition[client][i] = 0.0;
		gV_WallSnap[client][i] = 0.0;
	}
}

void ShowPanel(int client, int step)
{
	gI_MapStep[client] = step;

	if(step == 1)
	{
		CreateTimer(0.1, Timer_Draw, GetClientSerial(client), TIMER_REPEAT);
	}

	Panel pPanel = new Panel();

	char[] sPanelText = new char[128];
	char[] sFirst = new char[64];
	char[] sSecond = new char[64];
	FormatEx(sFirst, 64, "%T", "ZoneFirst", client);
	FormatEx(sSecond, 64, "%T", "ZoneSecond", client);
	FormatEx(sPanelText, 128, "%T", "ZonePlaceText", client, (step == 1)? sFirst:sSecond);

	pPanel.DrawItem(sPanelText, ITEMDRAW_RAWLINE);
	char[] sPanelItem = new char[64];
	FormatEx(sPanelItem, 64, "%T", "AbortZoneCreation", client);
	pPanel.DrawItem(sPanelItem);

	char[] sDisplay = new char[64];
	FormatEx(sDisplay, 64, "%T", "GridSnap", client, gI_GridSnap[client]);
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

			case 4:
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

bool SnapToWall(float pos[3], int client, float final[3])
{
	if(AreVectorsEqual(pos, gV_OldPosition[client]))
	{
		final = gV_WallSnap[client];

		return true;
	}

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

		TR_TraceRayFilter(pos, end, MASK_SOLID, RayType_EndPoint, TraceFilter_NoClients, client);

		if(TR_DidHit())
		{
			TR_GetEndPosition(temp);
			prefinal[axis] = temp[axis];
			hit = true;
		}
	}

	if(hit && GetVectorDistance(prefinal, pos) <= gI_GridSnap[client])
	{
		final = prefinal;

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

	TR_TraceRayFilter(pos, angles, MASK_SHOT, RayType_Infinite, TraceFilter_NoClients, client);

	if(TR_DidHit())
	{
		float end[3];
		TR_GetEndPosition(end);

		float final[3];
		final = end;
		
		final[0] = float(RoundToNearest(end[0] / gI_GridSnap[client]) * gI_GridSnap[client]);
		final[1] = float(RoundToNearest(end[1] / gI_GridSnap[client]) * gI_GridSnap[client]);
		final[2] = float(RoundToNearest(end[2] / gI_GridSnap[client]) * gI_GridSnap[client]);

		return final;
	}

	return pos;
}

public bool TraceFilter_World(int entity, int contentsMask)
{
	return (entity == 0);
}

bool AreVectorsEqual(float vec1[3], float vec2[3])
{
	return (vec1[0] == vec2[0] && vec1[1] == vec2[1] && vec1[2] == vec2[2]);
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status)
{
	if(!IsPlayerAlive(client) || IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	if(gI_MapStep[client] > 0 && gI_MapStep[client] != 3)
	{
		if((buttons & IN_USE) > 0)
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
					origin[0] = float(RoundToNearest(vPlayerOrigin[0] / gI_GridSnap[client]) * gI_GridSnap[client]);
					origin[1] = float(RoundToNearest(vPlayerOrigin[1] / gI_GridSnap[client]) * gI_GridSnap[client]);
				}

				else
				{
					gV_WallSnap[client] = origin;
					gV_OldPosition[client] = vPlayerOrigin;
				}

				origin[2] = vPlayerOrigin[2];

				if(gI_MapStep[client] == 1)
				{
					gV_Point1[client] = origin;
					gV_Point1[client][2] += 1.0;

					ShowPanel(client, 2);
				}

				else if(gI_MapStep[client] == 2)
				{
					origin[2] += gF_Height;
					gV_Point2[client] = origin;

					gI_MapStep[client]++;

					CreateEditMenu(client);
				}
			}

			gB_Button[client] = true;
		}

		else
		{
			gB_Button[client] = false;
		}
	}

	return Plugin_Continue;
}

public int CreateZoneConfirm_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[8];
		menu.GetItem(param2, info, 8);

		if(StrEqual(info, "yes"))
		{
			InsertZone(param1);
			gI_MapStep[param1] = 0;
		}

		else if(StrEqual(info, "no"))
		{
			Reset(param1);
		}

		else if(StrEqual(info, "adjust"))
		{
			CreateAdjustMenu(param1, 0);
		}

		else if(StrEqual(info, "tpzone"))
		{
			UpdateTeleportZone(param1);
			CreateEditMenu(param1);
		}

		else if(StrEqual(info, "track"))
		{
			gI_ZoneTrack[param1] = CycleTracks(gI_ZoneTrack[param1]);
			CreateEditMenu(param1);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

int CycleTracks(int track)
{
	if(++track >= TRACKS_SIZE)
	{
		return 0;
	}

	return track;
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

void UpdateTeleportZone(int client)
{
	float vTeleport[3];
	GetClientAbsOrigin(client, vTeleport);
	vTeleport[2] += 2.0;

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

void CreateEditMenu(int client)
{
	char[] sTrack = new char[32];
	GetTrackName(client, gI_ZoneTrack[client], sTrack, 32);

	Menu menu = new Menu(CreateZoneConfirm_Handler, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	menu.SetTitle("%T\n%T\n ", "ZoneEditConfirm", client, "ZoneEditTrack", client, sTrack);

	char[] sMenuItem = new char[64];

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

	else
	{
		FormatEx(sMenuItem, 64, "%T", "ZoneSetYes", client);
		menu.AddItem("yes", sMenuItem);
	}

	FormatEx(sMenuItem, 64, "%T", "ZoneSetNo", client);
	menu.AddItem("no", sMenuItem);
	FormatEx(sMenuItem, 64, "%T", "ZoneSetAdjust", client);
	menu.AddItem("adjust", sMenuItem);
	FormatEx(sMenuItem, 64, "%T", "ZoneChangeTrack", client);
	menu.AddItem("track", sMenuItem);

	menu.ExitButton = true;
	menu.Display(client, 600);
}

void CreateAdjustMenu(int client, int page)
{
	Menu hMenu = new Menu(ZoneAdjuster_Handler);
	char[] sMenuItem = new char[64];
	hMenu.SetTitle("%T", "ZoneAdjustPosition", client);

	FormatEx(sMenuItem, 64, "%T", "ZoneAdjustDone", client);
	hMenu.AddItem("done", sMenuItem);
	FormatEx(sMenuItem, 64, "%T", "ZoneAdjustCancel", client);
	hMenu.AddItem("cancel", sMenuItem);

	char[] sAxis = new char[4];
	strcopy(sAxis, 4, "XYZ");

	char[] sDisplay = new char[32];
	char[] sInfo = new char[16];

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
		char[] sInfo = new char[16];
		menu.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "done"))
		{
			CreateEditMenu(param1);
		}

		else if(StrEqual(sInfo, "cancel"))
		{
			Reset(param1);
		}

		else
		{
			char[] sAxis = new char[4];
			strcopy(sAxis, 4, "XYZ");

			char[][] sExploded = new char[3][8];
			ExplodeString(sInfo, ";", sExploded, 3, 8);

			int iPoint = StringToInt(sExploded[0]);
			int iAxis = StringToInt(sExploded[1]);
			bool bIncrease = view_as<bool>(StringToInt(sExploded[2]) == 1);

			((iPoint == 1)? gV_Point1:gV_Point2)[param1][iAxis] += ((bIncrease)? gF_Modifier[param1]:-gF_Modifier[param1]);
			Shavit_PrintToChat(param1, "%T", (bIncrease)? "ZoneSizeIncrease":"ZoneSizeDecrease", param1, gS_ChatStrings[sMessageVariable2], sAxis[iAxis], gS_ChatStrings[sMessageText], iPoint, gS_ChatStrings[sMessageVariable], gF_Modifier[param1], gS_ChatStrings[sMessageText]);

			CreateAdjustMenu(param1, GetMenuSelectionPosition());
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void InsertZone(int client)
{
	int type = gI_ZoneType[client];
	int index = GetZoneIndex(type, gI_ZoneTrack[client]);
	bool insert = (gI_ZoneDatabaseID[client] == -1 && (index == -1 || type >= Zone_Respawn));

	char[] sQuery = new char[512];

	if(type == Zone_CustomSpawn)
	{
		FormatEx(sQuery, 512, "INSERT INTO %smapzones (map, type, destination_x, destination_y, destination_z) VALUES ('%s', '%d', '%.03f', '%.03f', '%.03f');", gS_MySQLPrefix, gS_Map, type, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2]);
	}

	else if(insert) // insert
	{
		if(type != Zone_Teleport)
		{
			FormatEx(sQuery, 512, "INSERT INTO %smapzones (map, type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, track) VALUES ('%s', '%d', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%d');", gS_MySQLPrefix, gS_Map, type, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gI_ZoneTrack[client]);
		}

		else
		{
			FormatEx(sQuery, 512, "INSERT INTO %smapzones (map, type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, destination_x, destination_y, destination_z) VALUES ('%s', '%d', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f');", gS_MySQLPrefix, gS_Map, type, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gV_Teleport[client][0], gV_Teleport[client][1], gV_Teleport[client][2]);
		}
	}

	else // update
	{
		if(gI_ZoneDatabaseID[client] == -1)
		{
			for(int i = 0; i < gI_MapZones; i++)
			{
				if(gA_ZoneCache[i][bZoneInitialized] && gA_ZoneCache[i][iZoneType] == type && gA_ZoneCache[i][iZoneTrack] == gI_ZoneTrack[client])
				{
					gI_ZoneDatabaseID[client] = gA_ZoneCache[i][iDatabaseID];
				}
			}
		}

		FormatEx(sQuery, 512, "UPDATE %smapzones SET corner1_x = '%.03f', corner1_y = '%.03f', corner1_z = '%.03f', corner2_x = '%.03f', corner2_y = '%.03f', corner2_z = '%.03f', track = %d WHERE %s = %d;", gS_MySQLPrefix, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gI_ZoneTrack[client], (gB_MySQL)? "id":"rowid", gI_ZoneDatabaseID[client]);
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

	for(int i = 0; i < gI_MapZones; i++)
	{
		if(gA_ZoneCache[i][bZoneInitialized] && gA_ZoneSettings[gA_ZoneCache[i][iZoneType]][bVisible])
		{
			DrawZone(gV_MapZones_Visual[i], GetZoneColors(gA_ZoneCache[i][iZoneType]), gF_Interval, gA_ZoneSettings[gA_ZoneCache[i][iZoneType]][fWidth], gB_FlatZones, gV_ZoneCenter[i]);
		}
	}

	return Plugin_Continue;
}

int[] GetZoneColors(int type, int customalpha = 0)
{
	int colors[4];
	colors[0] = gA_ZoneSettings[type][iRed];
	colors[1] = gA_ZoneSettings[type][iGreen];
	colors[2] = gA_ZoneSettings[type][iBlue];
	colors[3] = (customalpha > 0)? customalpha:gA_ZoneSettings[type][iAlpha];

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
		origin[0] = float(RoundToNearest(vPlayerOrigin[0] / gI_GridSnap[client]) * gI_GridSnap[client]);
		origin[1] = float(RoundToNearest(vPlayerOrigin[1] / gI_GridSnap[client]) * gI_GridSnap[client]);
	}

	else
	{
		gV_WallSnap[client] = origin;
		gV_OldPosition[client] = vPlayerOrigin;
	}

	if(gI_MapStep[client] == 1 || gV_Point2[client][0] == 0.0)
	{
		origin[2] = (vPlayerOrigin[2] + gF_Height);
	}

	else
	{
		origin = gV_Point2[client];
	}

	if(!EmptyVector(gV_Point1[client]) || !EmptyVector(gV_Point2[client]))
	{
		float points[8][3];
		points[0] = gV_Point1[client];
		points[7] = origin;
		CreateZonePoints(points, gF_Offset);

		// This is here to make the zone setup grid snapping be 1:1 to how it looks when done with the setup.
		origin = points[7];

		DrawZone(points, GetZoneColors(gI_ZoneType[client], 25), 0.1, gA_ZoneSettings[gI_ZoneType[client]][fWidth], false, origin);

		if(gI_ZoneType[client] == Zone_Teleport && !EmptyVector(gV_Teleport[client]))
		{
			TE_SetupEnergySplash(gV_Teleport[client], NULL_VECTOR, false);
			TE_SendToAll(0.0);
		}
	}

	if(gI_MapStep[client] != 3 && !EmptyVector(origin))
	{
		origin[2] -= gF_Height;

		TE_SetupBeamPoints(vPlayerOrigin, origin, gI_BeamSprite, gI_HaloSprite, 0, 0, 0.1, 1.0, 1.0, 0, 0.0, {255, 255, 255, 230}, 0);
		TE_SendToAll(0.0);
	}

	return Plugin_Continue;
}

void DrawZone(float points[8][3], int color[4], float life, float width, bool flat, float center[3])
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

	int[] clients = new int[MaxClients];
	int count = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			float eyes[3];
			GetClientEyePosition(i, eyes);

			if(GetVectorDistance(eyes, center) <= 1024.0 ||
				(TR_TraceRayFilter(eyes, center, CONTENTS_SOLID, RayType_EndPoint, TraceFilter_World) && !TR_DidHit()))
			{
				clients[count++] = i;
			}
		}
	}

	for(int i = 0; i < ((flat)? 4:12); i++)
	{
		TE_SetupBeamPoints(points[pairs[i][0]], points[pairs[i][1]], gI_BeamSprite, gI_HaloSprite, 0, 0, life, width, width, 0, 0.0, color, 0);
		TE_Send(clients, count, 0.0);
	}
}

// by blacky
// creates 3d box from 2 points
void CreateZonePoints(float point[8][3], float offset = 0.0)
{
	float center[2];
	center[0] = ((point[0][0] + point[7][0]) / 2);
	center[1] = ((point[0][1] + point[7][1]) / 2);

	for(int i = 0; i < 8; i++)
	{
		for(int j = 0; j < 3; j++)
		{
			if(i > 0 && i < 7)
			{
				point[i][j] = point[((i >> (2 - j)) & 1) * 7][j];
			}

			if(offset != 0.0 && j < 2)
			{
				if(point[i][j] < center[j])
				{
					point[i][j] += offset;
				}

				else
				{
					point[i][j] -= offset;
				}
			}
		}
	}
}

void SQL_SetPrefix()
{
	char[] sFile = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-prefix.txt");

	File fFile = OpenFile(sFile, "r");

	if(fFile == null)
	{
		SetFailState("Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}

	char[] sLine = new char[PLATFORM_MAX_PATH*2];

	while(fFile.ReadLine(sLine, PLATFORM_MAX_PATH*2))
	{
		TrimString(sLine);
		strcopy(gS_MySQLPrefix, 32, sLine);

		break;
	}

	delete fFile;
}

void SQL_DBConnect()
{
	if(gH_SQL != null)
	{
		char[] sDriver = new char[8];
		gH_SQL.Driver.GetIdentifier(sDriver, 8);
		gB_MySQL = StrEqual(sDriver, "mysql", false);

		char[] sQuery = new char[1024];
		FormatEx(sQuery, 1024, "CREATE TABLE IF NOT EXISTS `%smapzones` (`id` INT AUTO_INCREMENT, `map` VARCHAR(128), `type` INT, `corner1_x` FLOAT, `corner1_y` FLOAT, `corner1_z` FLOAT, `corner2_x` FLOAT, `corner2_y` FLOAT, `corner2_z` FLOAT, `destination_x` FLOAT NOT NULL DEFAULT 0, `destination_y` FLOAT NOT NULL DEFAULT 0, `destination_z` FLOAT NOT NULL DEFAULT 0, `track` INT NOT NULL DEFAULT 0, PRIMARY KEY (`id`));", gS_MySQLPrefix);

		gH_SQL.Query(SQL_CreateTable_Callback, sQuery);
	}
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zones module) error! Map zones' table creation failed. Reason: %s", error);

		return;
	}

	char[] sQuery = new char[64];
	FormatEx(sQuery, 64, "SELECT destination_x FROM %smapzones LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration1_Callback, sQuery);

	FormatEx(sQuery, 64, "SELECT track FROM %smapzones LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration2_Callback, sQuery);
}

public void SQL_TableMigration1_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		char[] sQuery = new char[256];

		if(gB_MySQL)
		{
			FormatEx(sQuery, 256, "ALTER TABLE `%smapzones` ADD (`destination_x` FLOAT NOT NULL DEFAULT 0, `destination_y` FLOAT NOT NULL DEFAULT 0, `destination_z` FLOAT NOT NULL DEFAULT 0);", gS_MySQLPrefix);
			gH_SQL.Query(SQL_AlterTable1_Callback, sQuery);
		}

		else
		{
			char[] sAxis = new char[4];
			strcopy(sAxis, 4, "xyz");

			for(int i = 0; i < 3; i++)
			{
				FormatEx(sQuery, 256, "ALTER TABLE `%smapzones` ADD COLUMN `destination_%c` FLOAT NOT NULL DEFAULT 0;", gS_MySQLPrefix, sAxis[i]);
				gH_SQL.Query(SQL_AlterTable1_Callback, sQuery);
			}
		}
	}
}


public void SQL_AlterTable1_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zones module) error! Map zones' table migration (1) failed. Reason: %s", error);

		return;
	}
}

public void SQL_TableMigration2_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		char[] sQuery = new char[256];

		if(gB_MySQL)
		{
			FormatEx(sQuery, 256, "ALTER TABLE `%smapzones` ADD (`track` INT NOT NULL DEFAULT 0);", gS_MySQLPrefix);
		}

		else
		{
			FormatEx(sQuery, 256, "ALTER TABLE `%smapzones` ADD COLUMN `track` INTEGER NOT NULL DEFAULT 0;", gS_MySQLPrefix);
		}

		gH_SQL.Query(SQL_AlterTable2_Callback, sQuery);
	}

	else
	{
		// we have a database, time to load zones
		RefreshZones();
	}
}


public void SQL_AlterTable2_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zones module) error! Map zones' table migration (2) failed. Reason: %s", error);

		return;
	}
}

public void Shavit_OnRestart(int client, int track)
{
	if(gB_TeleportToStart)
	{
		Shavit_StartTimer(client, track);

		if(!EmptyVector(gF_CustomSpawn))
		{
			TeleportEntity(client, gF_CustomSpawn, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}

		else
		{
			int index = GetZoneIndex(Zone_Start, track);

			if(index == -1)
			{
				return;
			}

			float center[3];
			center[0] = gV_ZoneCenter[index][0];
			center[1] = gV_ZoneCenter[index][1];
			center[2] = gV_MapZones[index][0][2];

			TeleportEntity(client, center, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}
	}
}

public void Shavit_OnEnd(int client, int track)
{
	if(gB_TeleportToEnd)
	{
		int index = GetZoneIndex(Zone_End, track);

		if(index == -1)
		{
			return;
		}

		float center[3];
		center[0] = gV_ZoneCenter[index][0];
		center[1] = gV_ZoneCenter[index][1];
		center[2] = gV_MapZones[index][0][2];

		TeleportEntity(client, center, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
	}
}

public void Shavit_OnDatabaseLoaded(Database db)
{
	gH_SQL = db;
}

bool EmptyVector(float vec[3])
{
	return (vec[0] == 0.0 && vec[1] == 0.0 && vec[2] == 0.0);
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
		if(gA_ZoneCache[i][bZoneInitialized] && gA_ZoneCache[i][iZoneType] == type && (gA_ZoneCache[i][iZoneTrack] == track || track == -1))
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
	gB_ZonesCreated = false;

	RequestFrame(Frame_CreateZoneEntities);
}

public void Frame_CreateZoneEntities(any data)
{
	CreateZoneEntities();
}

float Abs(float input)
{
	if(input < 0.0)
	{
		return -input;
	}

	return input;
}

public void CreateZoneEntities()
{
	if(gB_ZonesCreated)
	{
		return;
	}

	for(int i = 0; i < gI_MapZones; i++)
	{
		for(int j = 1; j <= MaxClients; j++)
		{
			for(int k = 0; k < TRACKS_SIZE; k++)
			{
				gB_InsideZone[j][gA_ZoneCache[i][iZoneType]][k] = false;
			}

			gB_InsideZoneID[j][i] = false;
		}

		if(gA_ZoneCache[i][iEntityID] != -1)
		{
			KillZoneEntity(i);

			gA_ZoneCache[i][iEntityID] = -1;
		}

		if(!gA_ZoneCache[i][bZoneInitialized])
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
		SetEntityModel(entity, "models/props/cs_office/vending_machine.mdl");
		SetEntProp(entity, Prop_Send, "m_fEffects", 32);

		TeleportEntity(entity, gV_ZoneCenter[i], NULL_VECTOR, NULL_VECTOR);

		float distance_x = Abs(gV_MapZones[i][0][0] - gV_MapZones[i][1][0]) / 2;
		float distance_y = Abs(gV_MapZones[i][0][1] - gV_MapZones[i][1][1]) / 2;
		float distance_z = Abs(gV_MapZones[i][0][2] - gV_MapZones[i][1][2]) / 2;

		float height = ((gEV_Type == Engine_CSS)? 62.0:72.0) / 2;

		float min[3];
		min[0] = -distance_x + 16.0;
		min[1] = -distance_y + 16.0;
		min[2] = -distance_z + height;
		SetEntPropVector(entity, Prop_Send, "m_vecMins", min);

		float max[3];
		max[0] = distance_x - 16.0;
		max[1] = distance_y - 16.0;
		max[2] = distance_z - height;
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", max);

		SetEntProp(entity, Prop_Send, "m_nSolidType", 2);

		SDKHook(entity, SDKHook_StartTouchPost, StartTouchPost);
		SDKHook(entity, SDKHook_EndTouchPost, EndTouchPost);
		SDKHook(entity, SDKHook_TouchPost, TouchPost);

		gI_EntityZone[entity] = i;
		gA_ZoneCache[i][iEntityID] = entity;

		char[] sTargetname = new char[32];
		FormatEx(sTargetname, 32, "shavit_zones_%d_%d", gA_ZoneCache[i][iZoneTrack], gA_ZoneCache[i][iZoneType]);
		DispatchKeyValue(entity, "targetname", sTargetname);

		gB_ZonesCreated = true;
	}
}

public void StartTouchPost(int entity, int other)
{
	if(other < 1 || other > MaxClients || gI_EntityZone[entity] == -1 || !gA_ZoneCache[gI_EntityZone[entity]][bZoneInitialized] || IsFakeClient(other))
	{
		return;
	}

	TimerStatus status = Shavit_GetTimerStatus(other);

	switch(gA_ZoneCache[gI_EntityZone[entity]][iZoneType])
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
		}

		case Zone_Stop:
		{
			if(status != Timer_Stopped)
			{
				Shavit_StopTimer(other);
			}
		}

		case Zone_End:
		{
			if(status != Timer_Stopped && Shavit_GetClientTrack(other) == gA_ZoneCache[gI_EntityZone[entity]][iZoneTrack])
			{
				Shavit_FinishMap(other, gA_ZoneCache[gI_EntityZone[entity]][iZoneTrack]);
			}
		}
	}

	gB_InsideZone[other][gA_ZoneCache[gI_EntityZone[entity]][iZoneType]][gA_ZoneCache[gI_EntityZone[entity]][iZoneTrack]] = true;
	gB_InsideZoneID[other][gI_EntityZone[entity]] = true;

	Call_StartForward(gH_Forwards_EnterZone);
	Call_PushCell(other);
	Call_PushCell(gA_ZoneCache[gI_EntityZone[entity]][iZoneType]);
	Call_PushCell(gA_ZoneCache[gI_EntityZone[entity]][iZoneTrack]);
	Call_PushCell(gI_EntityZone[entity]);
	Call_PushCell(entity);
	Call_Finish();
}

public void EndTouchPost(int entity, int other)
{
	if(other < 1 || other > MaxClients || gI_EntityZone[entity] == -1 || gI_EntityZone[entity] >= sizeof(gA_ZoneCache) || IsFakeClient(other))
	{
		return;
	}

	int entityzone = gI_EntityZone[entity];
	int type = gA_ZoneCache[entityzone][iZoneType];
	int track = gA_ZoneCache[entityzone][iZoneTrack];

	gB_InsideZone[other][type][track] = false;
	gB_InsideZoneID[other][entityzone] = false;

	Call_StartForward(gH_Forwards_LeaveZone);
	Call_PushCell(other);
	Call_PushCell(type);
	Call_PushCell(track);
	Call_PushCell(entityzone);
	Call_PushCell(entity);
	Call_Finish();
}

public void TouchPost(int entity, int other)
{
	if(other < 1 || other > MaxClients || gI_EntityZone[entity] == -1 || IsFakeClient(other))
	{
		return;
	}

	// do precise stuff here, this will be called *A LOT*
	switch(gA_ZoneCache[gI_EntityZone[entity]][iZoneType])
	{
		case Zone_Start:
		{
			// start timer instantly for main track, but require bonuses to have the current timer stopped
			// so you don't accidentally step on those while running
			if(Shavit_GetTimerStatus(other) == Timer_Stopped || Shavit_GetClientTrack(other) != Track_Main)
			{
				Shavit_StartTimer(other, gA_ZoneCache[gI_EntityZone[entity]][iZoneTrack]);
			}

			else if(gA_ZoneCache[gI_EntityZone[entity]][iZoneTrack] == Track_Main)
			{
				Shavit_StartTimer(other, Track_Main);
			}
		}
	}
}
