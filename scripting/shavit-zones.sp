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
#include <cstrike>
#include <dynamic>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <adminmenu>

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

#define PLACEHOLDER 32767

EngineVersion gEV_Type = Engine_Unknown;

Database gH_SQL = null;
bool gB_MySQL = false;

char gS_Map[128];

char gS_ZoneNames[MAX_ZONES][] =
{
	"Start Zone", // starts timer
	"End Zone", // stops timer
	"Glitch Zone (Respawn Player)", // respawns the player
	"Glitch Zone (Stop Timer)", // stops the player's timer
	"Slay Player", // slays (kills) players which come to this zone
	"Freestyle Zone", // ignores style physics when at this zone. e.g. WASD when SWing
	"No Speed Limit", // ignores velocity limit in that zone
	"Teleport Zone" // teleports to a defined point
};

enum
{
	sBeamSprite,
	sHaloSprite,
	ZONESPRITES_SIZE
}

enum
{
	bVisible,
	iRed,
	iGreen,
	iBlue,
	iAlpha,
	ZONESETTINGS_SIZE
}

any gA_ZoneSettings[MAX_ZONES*8][ZONESETTINGS_SIZE];

MapZones gMZ_Type[MAXPLAYERS+1];

// 0 - nothing
// 1 - wait for E tap to setup first coord
// 2 - wait for E tap to setup second coord
// 3 - confirm
int gI_MapStep[MAXPLAYERS+1];

float gF_Modifier[MAXPLAYERS+1];
int gI_GridSnap[MAXPLAYERS+1];

// I suck
float gV_Point1[MAXPLAYERS+1][3];
float gV_Point2[MAXPLAYERS+1][3];
float gV_Teleport[MAXPLAYERS+1][3];

bool gB_Button[MAXPLAYERS+1];

float gV_MapZones[MAX_ZONES][2][3];
float gV_FreestyleZones[MULTIPLEZONES_LIMIT][2][3];
MapZones gMZ_FreestyleTypes[MAXPLAYERS+1];
float gV_TeleportZoneDestination[MULTIPLEZONES_LIMIT][3];

// Sorry for adding too many variables: zone rotations
float gV_MapZonesFixes[MAX_ZONES][2][2];
float gV_FreeStyleZonesFixes[MULTIPLEZONES_LIMIT][2][2];

// ofir's pull request
float gF_ConstSin[MAX_ZONES];
float gF_MinusConstSin[MAX_ZONES];
float gF_ConstCos[MAX_ZONES];
float gF_MinusConstCos[MAX_ZONES];

float gF_FreeStyleConstSin[MULTIPLEZONES_LIMIT];
float gF_FreeStyleMinusConstSin[MULTIPLEZONES_LIMIT];
float gF_FreeStyleConstCos[MULTIPLEZONES_LIMIT];
float gF_FreeStyleMinusConstCos[MULTIPLEZONES_LIMIT];

float gF_CustomSpawn[3];

float gF_RotateAngle[MAXPLAYERS+1];
float gV_Fix1[MAXPLAYERS+1][2];
float gV_Fix2[MAXPLAYERS+1][2];

// beamsprite, used to draw the zone
char gS_Sprites[ZONESPRITES_SIZE][PLATFORM_MAX_PATH];
int gI_BeamSprite = -1;
int gI_HaloSprite = -1;

// admin menu
Handle gH_AdminMenu = INVALID_HANDLE;

// late load?
bool gB_Late;

// cvars
ConVar gCV_ZoneStyle = null;
ConVar gCV_Interval = null;
ConVar gCV_TeleportToStart = null;
ConVar gCV_UseCustomSprite = null;

// cached cvars
int gI_ZoneStyle = 0;
float gF_Interval = 1.0;
bool gB_TeleportToStart = true;
bool gB_UseCustomSprite = true;

// table prefix
char gS_MySQLPrefix[32];

// chat settings
char gS_ChatStrings[CHATSETTINGS_SIZE][128];

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
	// game specific
	gEV_Type = GetEngineVersion();

	// menu
	RegAdminCmd("sm_zones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu");
	RegAdminCmd("sm_mapzones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu");

	RegAdminCmd("sm_deletezone", Command_DeleteZone, ADMFLAG_RCON, "Delete a mapzone");
	RegAdminCmd("sm_deleteallzones", Command_DeleteAllZones, ADMFLAG_RCON, "Delete all mapzones");

	RegAdminCmd("sm_modifier", Command_Modifier, ADMFLAG_RCON, "Changes the axis modifier for the zone editor. Usage: sm_modifier <number>");
	
	RegAdminCmd("sm_addspawn", Command_AddSpawn,  ADMFLAG_RCON, "Adds a custom spawn location");
	RegAdminCmd("sm_delspawn", Command_DelSpawn,  ADMFLAG_RCON, "Deletes a custom spawn location");

	// cvars and stuff
	gCV_ZoneStyle = CreateConVar("shavit_zones_style", "0", "Style for mapzone drawing.\n0 - 3D box\n1 - 2D box", 0, true, 0.0, true, 1.0);
	gCV_Interval = CreateConVar("shavit_zones_interval", "1.0", "Interval between each time a mapzone is being drawn to the players.", 0, true, 0.5, true, 5.0);
	gCV_TeleportToStart = CreateConVar("shavit_zones_teleporttostart", "1", "Teleport players to the start zone on timer restart?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_UseCustomSprite = CreateConVar("shavit_zones_usecustomsprite", "1", "Use custom sprite for zone drawing?\nSee `configs/shavit-zones.cfg`.\nRestart server after change.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);

	gCV_ZoneStyle.AddChangeHook(OnConVarChanged);
	gCV_Interval.AddChangeHook(OnConVarChanged);
	gCV_TeleportToStart.AddChangeHook(OnConVarChanged);
	gCV_UseCustomSprite.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	Shavit_GetDB(gH_SQL);
	SQL_SetPrefix();
	SetSQLInfo();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gI_ZoneStyle = gCV_ZoneStyle.IntValue;
	gF_Interval = gCV_Interval.FloatValue;
	gB_TeleportToStart = gCV_TeleportToStart.BoolValue;
	gB_UseCustomSprite = gCV_UseCustomSprite.BoolValue;
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
		}
	}
}

public void CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayTitle)
	{
		strcopy(buffer, maxlength, "Timer Commands:");
	}

	else if(action == TopMenuAction_DisplayOption)
	{
		strcopy(buffer, maxlength, "Timer Commands");
	}
}

public void AdminMenu_Zones(Handle topmenu,  TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		strcopy(buffer, maxlength, "Add map zone");
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
		strcopy(buffer, maxlength, "Delete map zone");
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
		strcopy(buffer, maxlength, "Delete ALL map zones");
	}

	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteAllZones(param, 0);
	}
}

public int Native_ZoneExists(Handle handler, int numParams)
{
	MapZones type = GetNativeCell(1);

	return view_as<int>(!EmptyZone(gV_MapZones[type][0]) && !EmptyZone(gV_MapZones[type][1]));
}

public int Native_InsideZone(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	MapZones type = GetNativeCell(2);

	if(type >= Zone_Freestyle && type != Zone_Teleport)
	{
		for(int i = 0; i < MULTIPLEZONES_LIMIT; i++)
		{
			if((i == 0 && InsideZone(client, -PLACEHOLDER)) || InsideZone(client, -i))
			{
				return true;
			}
		}
	}

	return view_as<int>(InsideZone(client, view_as<int>(type)));
}

public int Native_IsClientCreatingZone(Handle handler, int numParams)
{
	return (gI_MapStep[GetNativeCell(1)] != 0);
}

bool LoadZonesConfig()
{
	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-zones.cfg");

	Dynamic dZones = Dynamic();

	if(!dZones.ReadKeyValues(sPath))
	{
		dZones.Dispose();

		return false;
	}

	Dynamic dSprites = dZones.GetDynamicByIndex((gEV_Type == Engine_CSS)? 0:1);
	dSprites.GetString("beam", gS_Sprites[sBeamSprite], PLATFORM_MAX_PATH);
	dSprites.GetString("halo", gS_Sprites[sHaloSprite], PLATFORM_MAX_PATH);

	char[] sDownloads = new char[PLATFORM_MAX_PATH * 8];
	dSprites.GetString("downloads", sDownloads, PLATFORM_MAX_PATH * 8);

	char[][] sDownloadsExploded = new char[PLATFORM_MAX_PATH][PLATFORM_MAX_PATH]; // we don't need more than 8 sprites ever
	int iDownloads = ExplodeString(sDownloads, ";", sDownloadsExploded, PLATFORM_MAX_PATH, PLATFORM_MAX_PATH, false);

	for(int i = 0; i < iDownloads; i++)
	{
		if(strlen(sDownloadsExploded[i]) > 0)
		{
			TrimString(sDownloadsExploded[i]);
			AddFileToDownloadsTable(sDownloadsExploded[i]);
		}
	}

	Dynamic dColors = dZones.GetDynamicByIndex(2);
	int iCount = dColors.MemberCount;

	for(int i = 0; i < iCount; i++)
	{
		Dynamic dZoneSettings = dColors.GetDynamicByIndex(i);
		gA_ZoneSettings[i][bVisible] = dZoneSettings.GetBool("visible", true);
		gA_ZoneSettings[i][iRed] = dZoneSettings.GetInt("red", 255);
		gA_ZoneSettings[i][iGreen] = dZoneSettings.GetInt("green", 255);
		gA_ZoneSettings[i][iBlue] = dZoneSettings.GetInt("blue", 255);
		gA_ZoneSettings[i][iAlpha] = dZoneSettings.GetInt("alpha", 255);
	}

	dZones.Dispose(true);

	return true;
}

public void OnMapStart()
{
	GetCurrentMap(gS_Map, 128);

	UnloadZones(0);

	if(gH_SQL != null)
	{
		RefreshZones();
	}

	if(!LoadZonesConfig())
	{
		SetFailState("Cannot open \"configs/shavit-zones.cfg\". Make sure this file exists and that the server has read permissions to it.");
	}

	if(gB_UseCustomSprite)
	{
		gI_BeamSprite = PrecacheModel(gS_Sprites[sBeamSprite], true);
		gI_HaloSprite = (StrEqual(gS_Sprites[sHaloSprite], "none"))? 0:PrecacheModel(gS_Sprites[sHaloSprite], true);
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

	// PrecacheModel("models/props/cs_office/vending_machine.mdl"); // placeholder model

	// draw
	// start drawing mapzones here
	CreateTimer(gF_Interval, Timer_DrawEverything, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

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

// 0 - all zones
void UnloadZones(int zone)
{
	if(!zone)
	{
		for(int i = 0; i < MAX_ZONES; i++)
		{
			for(int j = 0; j < 3; j++)
			{
				gV_MapZones[i][0][j] = 0.0;
				gV_MapZones[i][1][j] = 0.0;
			}
		}

		for(int i = 0; i < MULTIPLEZONES_LIMIT; i++)
		{
			for(int j = 0; j < 3; j++)
			{
				gV_FreestyleZones[i][0][j] = 0.0;
				gV_FreestyleZones[i][1][j] = 0.0;
				gMZ_FreestyleTypes[i] = view_as<MapZones>(-1);
			}
		}
		
		ClearCustomSpawn();
		
		return;
	}

	if(zone < view_as<int>(Zone_Freestyle))
	{
		for(int i = 0; i < 3; i++)
		{
			gV_MapZones[zone][0][i] = 0.0;
			gV_MapZones[zone][1][i] = 0.0;
		}
	}
	
	else if(zone == view_as<int>(Zone_CustomSpawn))
	{
		ClearCustomSpawn();
	}
	
	else
	{
		for(int i = 0; i < MULTIPLEZONES_LIMIT; i++)
		{
			for(int j = 0; j < 3; j++)
			{
				gV_FreestyleZones[i][0][j] = 0.0;
				gV_FreestyleZones[i][1][j] = 0.0;
				gMZ_FreestyleTypes[i] = view_as<MapZones>(-1);
			}
		}
	}
}

void RefreshZones()
{
	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "SELECT type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, rot_ang, fix1_x, fix1_y, fix2_x, fix2_y, destination_x, destination_y, destination_z FROM %smapzones WHERE map = '%s';", gS_MySQLPrefix, gS_Map);

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

	int iFreestyleRow = 0;

	while(results.FetchRow())
	{
		MapZones type = view_as<MapZones>(results.FetchInt(0));
		
		if(type == Zone_CustomSpawn)
		{
			gF_CustomSpawn[0] = results.FetchFloat(12);
			gF_CustomSpawn[1] = results.FetchFloat(13);
			gF_CustomSpawn[2] = results.FetchFloat(14);
		}
		
		else if(type >= Zone_Freestyle)
		{
			gV_FreestyleZones[iFreestyleRow][0][0] = results.FetchFloat(1);
			gV_FreestyleZones[iFreestyleRow][0][1] = results.FetchFloat(2);
			gV_FreestyleZones[iFreestyleRow][0][2] = results.FetchFloat(3);
			gV_FreestyleZones[iFreestyleRow][1][0] = results.FetchFloat(4);
			gV_FreestyleZones[iFreestyleRow][1][1] = results.FetchFloat(5);
			gV_FreestyleZones[iFreestyleRow][1][2] = results.FetchFloat(6);

			gMZ_FreestyleTypes[iFreestyleRow] = type;

			float ang = results.FetchFloat(7);

			float radian = DegToRad(ang);
			gF_FreeStyleConstSin[iFreestyleRow] = Sine(radian);
			gF_FreeStyleConstCos[iFreestyleRow] = Cosine(radian);

			radian = DegToRad(-ang);
			gF_FreeStyleMinusConstSin[iFreestyleRow] = Sine(radian);
			gF_FreeStyleMinusConstCos[iFreestyleRow] = Cosine(radian);

			gV_FreeStyleZonesFixes[iFreestyleRow][0][0] = results.FetchFloat(8);
			gV_FreeStyleZonesFixes[iFreestyleRow][0][1] = results.FetchFloat(9);
			gV_FreeStyleZonesFixes[iFreestyleRow][1][0] = results.FetchFloat(10);
			gV_FreeStyleZonesFixes[iFreestyleRow][1][1] = results.FetchFloat(11);

			if(type == Zone_Teleport)
			{
				gV_TeleportZoneDestination[iFreestyleRow][0] = results.FetchFloat(12);
				gV_TeleportZoneDestination[iFreestyleRow][1] = results.FetchFloat(13);
				gV_TeleportZoneDestination[iFreestyleRow][2] = results.FetchFloat(14);
			}

			iFreestyleRow++;
		}

		else
		{
			if(view_as<int>(type) >= MAX_ZONES || view_as<int>(type) < 0)
			{
				continue;
			}

			gV_MapZones[type][0][0] = results.FetchFloat(1);
			gV_MapZones[type][0][1] = results.FetchFloat(2);
			gV_MapZones[type][0][2] = results.FetchFloat(3);
			gV_MapZones[type][1][0] = results.FetchFloat(4);
			gV_MapZones[type][1][1] = results.FetchFloat(5);
			gV_MapZones[type][1][2] = results.FetchFloat(6);

			float ang = results.FetchFloat(7);

			float radian = DegToRad(ang);
			gF_ConstSin[type] = Sine(radian);
			gF_ConstCos[type] = Cosine(radian);

			radian = DegToRad(-ang);
			gF_MinusConstSin[type] = Sine(radian);
			gF_MinusConstCos[type] = Cosine(radian);

			gV_MapZonesFixes[type][0][0] = results.FetchFloat(8);
			gV_MapZonesFixes[type][0][1] = results.FetchFloat(9);
			gV_MapZonesFixes[type][1][0] = results.FetchFloat(10);
			gV_MapZonesFixes[type][1][1] = results.FetchFloat(11);
		}
	}
}

public void OnClientPutInServer(int client)
{
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

	if(!args)
	{
		Shavit_PrintToChat(client, "Usage: sm_modifier <decimal number>");

		return Plugin_Handled;
	}

	char[] sArg1 = new char[16];
	GetCmdArg(1, sArg1, 16);

	float fArg1 = StringToFloat(sArg1);

	if(fArg1 <= 0.0)
	{
		Shavit_PrintToChat(client, "Modifier must be higher than 0.");

		return Plugin_Handled;
	}

	gF_Modifier[client] = fArg1;

	Shavit_PrintToChat(client, "Modifier set to %s%.01f%s.", gS_ChatStrings[sMessageVariable], fArg1, gS_ChatStrings[sMessageText]);

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
		Shavit_PrintToChat(client, "You can't place zones when you're dead.");

		return Plugin_Handled;
	}

	if(!EmptyZone(gF_CustomSpawn))
	{
		Shavit_PrintToChat(client, "Custom Spawn already exists. Please delete it before placing a new one.");

		return Plugin_Handled;
	}

	gMZ_Type[client] = Zone_CustomSpawn;
	
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

	Shavit_PrintToChat(client, "Deleted Custom Spawn sucessfully.");
}

void ClearCustomSpawn()
{
	for(int i = 0; i < 3; i++)
	{
		gF_CustomSpawn[i] = 0.0;
	}
}

public Action Command_Zones(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		Shavit_PrintToChat(client, "You %scannot%s setup mapzones when you're dead.", gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	Reset(client);

	Menu menu = new Menu(Select_Type_MenuHandler);
	menu.SetTitle("Select a zone type:");

	for(int i = 0; i < sizeof(gS_ZoneNames); i++)
	{
		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		menu.AddItem(sInfo, gS_ZoneNames[i]);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);

	return Plugin_Handled;
}

public Action Command_DeleteZone(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(DeleteZone_MenuHandler);
	menu.SetTitle("Delete a zone:\nPressing a zone will delete it. This action CANNOT BE REVERTED!");

	for(int i = 0; i < MAX_ZONES; i++)
	{
		if(i >= view_as<int>(Zone_Freestyle))
		{
			if(!EmptyZone(gV_FreestyleZones[0][0]) && !EmptyZone(gV_FreestyleZones[0][1]))
			{
				char[] sInfo = new char[8];
				IntToString(i, sInfo, 8);
				menu.AddItem(sInfo, gS_ZoneNames[i]);
			}
		}

		if(!EmptyZone(gV_MapZones[i][0]) && !EmptyZone(gV_MapZones[i][1]))
		{
			char[] sInfo = new char[8];
			IntToString(i, sInfo, 8);
			menu.AddItem(sInfo, gS_ZoneNames[i]);
		}
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "No zones found.");
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

		int iInfo = StringToInt(info);

		if(iInfo == -1)
		{
			return 0;
		}

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "DELETE FROM %smapzones WHERE map = '%s' AND type = '%d';", gS_MySQLPrefix, gS_Map, iInfo);

		DataPack hDatapack = new DataPack();
		hDatapack.WriteCell(GetClientSerial(param1));
		hDatapack.WriteCell(iInfo);

		gH_SQL.Query(SQL_DeleteZone_Callback, sQuery, hDatapack);
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

	Shavit_PrintToChat(client, "Deleted %s%s%s sucessfully.", gS_ChatStrings[sMessageVariable], gS_ZoneNames[type], gS_ChatStrings[sMessageText]);
}

public Action Command_DeleteAllZones(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(DeleteAllZones_MenuHandler);
	menu.SetTitle("Delete ALL mapzones?\nPressing \"Yes\" will delete all the existing mapzones for this map.\nThis action CANNOT BE REVERTED!");

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		menu.AddItem("-1", "NO!");
	}

	menu.AddItem("yes", "YES!!! DELETE ALL THE MAPZONES!!!");

	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		menu.AddItem("-1", "NO!");
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

	Shavit_PrintToChat(client, "Deleted all map zones sucessfully.");
}

public int Select_Type_MenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[8];
		menu.GetItem(param2, info, 8);

		gMZ_Type[param1] = view_as<MapZones>(StringToInt(info));

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
	gF_Modifier[client] = 10.0;
	gI_MapStep[client] = 0;
	gI_GridSnap[client] = 16;
	gF_RotateAngle[client] = 0.0;

	for(int i = 0; i < 2; i++)
	{
		gV_Fix1[client][i] = 0.0;
		gV_Fix2[client][i] = 0.0;
	}

	for(int i = 0; i < 3; i++)
	{
		gV_Point1[client][i] = 0.0;
		gV_Point2[client][i] = 0.0;
		gV_Teleport[client][i] = 0.0;
	}
}

// neat idea for this part is by alongub, you have a cool way of thinking. :)
void ShowPanel(int client, int step)
{
	gI_MapStep[client] = step;

	if(step == 1)
	{
		// not gonna use gF_Interval here as we need percision when setting up zones
		CreateTimer(0.1, Timer_Draw, GetClientSerial(client), TIMER_REPEAT);
	}

	Panel pPanel = new Panel();

	char[] sPanelText = new char[128];
	FormatEx(sPanelText, 128, "Press USE (default \"E\") to set the %s corner in your current position.", (step == 1)? "FIRST":"SECOND");

	pPanel.DrawItem(sPanelText, ITEMDRAW_RAWLINE);
	pPanel.DrawItem("Abort zone creation");

	char[] sDisplay = new char[16];
	FormatEx(sDisplay, 16, "Grid snap: x%d", gI_GridSnap[client]);
	pPanel.DrawItem(sDisplay);

	pPanel.Send(client, ZoneCreation_Handler, 600);

	delete pPanel;
}

public int ZoneCreation_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(param2 == 1)
		{
			Reset(param1);
		}

		else
		{
			gI_GridSnap[param1] *= 2;

			if(gI_GridSnap[param1] > 64)
			{
				gI_GridSnap[param1] = 1;
			}

			ShowPanel(param1, gI_MapStep[param1]);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action OnPlayerRunCmd(int client, int &buttons)
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
				float vOrigin[3];
				GetClientAbsOrigin(client, vOrigin);

				// grid snapping
				vOrigin[0] = float(RoundToNearest(vOrigin[0] / gI_GridSnap[client]) * gI_GridSnap[client]);
				vOrigin[1] = float(RoundToNearest(vOrigin[1] / gI_GridSnap[client]) * gI_GridSnap[client]);

				if(gI_MapStep[client] == 1)
				{
					gV_Point1[client] = vOrigin;

					ShowPanel(client, 2);
				}

				else if(gI_MapStep[client] == 2)
				{
					//vOrigin[2] += 72; // was requested to make it higher
					vOrigin[2] += 144;
					gV_Point2[client] = vOrigin;

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

	if(InsideZone(client, view_as<int>(Zone_Respawn)))
	{
		CS_RespawnPlayer(client);

		return Plugin_Continue;
	}

	for(int i = 0; i < MULTIPLEZONES_LIMIT; i++)
	{
		if(gMZ_FreestyleTypes[i] == Zone_Teleport && !EmptyZone(gV_TeleportZoneDestination[i]) && InsideTeleportZone(client, i))
		{
			TeleportEntity(client, gV_TeleportZoneDestination[i], NULL_VECTOR, NULL_VECTOR);
		}
	}

	// temp variables
	static float fTime;
	static int iJumps;
	static BhopStyle bsStyle;
	bool bStarted;
	Shavit_GetTimer(client, fTime, iJumps, bsStyle, bStarted);

	if(InsideZone(client, view_as<int>(Zone_Start)))
	{
		Shavit_ResumeTimer(client);
		Shavit_StartTimer(client);

		return Plugin_Continue;
	}

	if(InsideZone(client, view_as<int>(Zone_Slay)))
	{
		Shavit_StopTimer(client);

		ForcePlayerSuicide(client);
	}

	if(bStarted)
	{
		if(InsideZone(client, view_as<int>(Zone_Stop)))
		{
			Shavit_StopTimer(client);
		}

		if(InsideZone(client, view_as<int>(Zone_End)))
		{
			Shavit_FinishMap(client);
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

		else if(StrEqual(info, "rotate"))
		{
			CreateRotateMenu(param1);
		}

		else if(StrEqual(info, "wl"))
		{
			CreateWidthLengthMenu(param1, 0);
		}

		else if(StrEqual(info, "tpzone"))
		{
			GetClientAbsOrigin(param1, gV_Teleport[param1]);
			Shavit_PrintToChat(param1, "Teleport zone destination updated.");

			CreateEditMenu(param1);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void CreateEditMenu(int client)
{
	Menu menu = new Menu(CreateZoneConfirm_Handler, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	menu.SetTitle("Confirm?");

	if(gMZ_Type[client] == Zone_Teleport)
	{
		if(EmptyZone(gV_Teleport[client]))
		{
			menu.AddItem("-1", "Yes (choose teleport destination first)", ITEMDRAW_DISABLED);
		}

		else
		{
			menu.AddItem("yes", "Yes");
		}

		menu.AddItem("tpzone", "Update teleport destination");
	}

	else
	{
		menu.AddItem("yes", "Yes");
	}
	
	menu.AddItem("no", "No");
	menu.AddItem("adjust", "Adjust position");
	menu.AddItem("rotate", "Rotate zone");
	menu.AddItem("wl", "Modify width/length");

	menu.ExitButton = true;

	menu.Display(client, 600);
}

void CreateAdjustMenu(int client, int page)
{
	Menu hMenu = new Menu(ZoneAdjuster_Handler);
	hMenu.SetTitle("Adjust the zone's position.\nUse \"sm_modifier <number>\" to set a new modifier.");

	hMenu.AddItem("done", "Done!");
	hMenu.AddItem("cancel", "Cancel");

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
				FormatEx(sDisplay, 32, "Point %d | %c axis %c%.01f", iPoint, sAxis[iAxis], (iState == 1)? '+':'-', gF_Modifier[client]);
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

			if(bIncrease)
			{
				Shavit_PrintToChat(param1, "%s%c axis%s (point %d) increased by %s%.01f%s.", gS_ChatStrings[sMessageVariable2], sAxis[iAxis], gS_ChatStrings[sMessageText], iPoint, gS_ChatStrings[sMessageVariable], gF_Modifier[param1], gS_ChatStrings[sMessageText]);
			}

			else
			{
				Shavit_PrintToChat(param1, "%s%c axis%s (point %d) decreased by %s%.01f%s.", gS_ChatStrings[sMessageVariable2], sAxis[iAxis], gS_ChatStrings[sMessageText], iPoint, gS_ChatStrings[sMessageVariable], gF_Modifier[param1], gS_ChatStrings[sMessageText]);
			}

			CreateAdjustMenu(param1, GetMenuSelectionPosition());
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void CreateRotateMenu(int client)
{
	Menu hMenu = new Menu(ZoneRotate_Handler);
	hMenu.SetTitle("Rotate the zone.\nUse \"sm_modifier <number>\" to set a new modifier.");

	hMenu.AddItem("done", "Done!");
	hMenu.AddItem("cancel", "Cancel");

	char[] sDisplay = new char[64];
	FormatEx(sDisplay, 64, "Rotate by +%.01f degrees", gF_Modifier[client]);
	hMenu.AddItem("1", sDisplay);

	FormatEx(sDisplay, 64, "Rotate by -%.01f degrees", gF_Modifier[client]);
	hMenu.AddItem("2", sDisplay);

	hMenu.Display(client, 40);
}

public int ZoneRotate_Handler(Menu menu, MenuAction action, int param1, int param2)
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
			bool bIncrease = view_as<bool>(StringToInt(sInfo) == 1);
			gF_RotateAngle[param1] += (bIncrease? gF_Modifier[param1]:-gF_Modifier[param1]);

			Shavit_PrintToChat(param1, "Zone rotated by %s%.01f%s degrees.", gS_ChatStrings[sMessageVariable], ((bIncrease)? gF_Modifier[param1]:-gF_Modifier[param1]), gS_ChatStrings[sMessageText]);

			CreateRotateMenu(param1);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}
}

void CreateWidthLengthMenu(int client, int page)
{
	Menu hMenu = new Menu(ZoneEdge_Handler);
	hMenu.SetTitle("Rotate the zone.\nUse \"sm_modifier <number>\" to set a new modifier.");

	hMenu.AddItem("done", "Done!");
	hMenu.AddItem("cancel", "Cancel");

	char sEdges[][] =
	{
		"Right",
		"Back",
		"Left",
		"Front"
	};

	char[] sDisplay = new char[32];
	char[] sInfo = new char[8];

	for(int iEdge = 0; iEdge < 4; iEdge++)
	{
		for(int iState = 1; iState <= 2; iState++)
		{
			FormatEx(sDisplay, 32, "%s edge | %c%.01f", sEdges[iEdge], (iState == 1)? "+":"-", gF_Modifier[client]);
			FormatEx(sInfo, 8, "%d;%d", iEdge, iState);
			hMenu.AddItem(sInfo, sDisplay);
		}
	}

	hMenu.DisplayAt(client, page, MENU_TIME_FOREVER);
}

public int ZoneEdge_Handler(Menu menu, MenuAction action, int param1, int param2)
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
			char sEdges[][] =
			{
				"Right",
				"Back",
				"Left",
				"Front"
			};

			char[][] sExploded = new char[2][8];
			ExplodeString(sInfo, ";", sExploded, 2, 8);

			int iEdge = StringToInt(sExploded[0]);
			bool bIncrease = view_as<bool>(StringToInt(sExploded[1]) == 1);

			if(iEdge >= 2)
			{
				iEdge -= 2;

				gV_Fix1[param1][iEdge] += (bIncrease? gF_Modifier[param1]:-gF_Modifier[param1]);
			}

			else
			{
				gV_Fix2[param1][iEdge] += (bIncrease? gF_Modifier[param1]:-gF_Modifier[param1]);
			}

			Shavit_PrintToChat(param1, "%s edge %s%s%s by %s%.01f degrees%s.", sEdges[iEdge], gS_ChatStrings[sMessageVariable2], (bIncrease)? "increased":"decreased", gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], gF_Modifier[param1], gS_ChatStrings[sMessageText]);

			CreateWidthLengthMenu(param1, GetMenuSelectionPosition());
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}
}

bool EmptyZone(float vZone[3])
{
	if(vZone[0] == 0.0 && vZone[1] == 0.0 && vZone[2] == 0.0)
	{
		return true;
	}

	return false;
}

void InsertZone(int client)
{
	MapZones type = gMZ_Type[client];

	char[] sQuery = new char[512];
	
	if(type == Zone_CustomSpawn)
	{
		FormatEx(sQuery, 512, "INSERT INTO %smapzones (map, type, destination_x, destination_y, destination_z) VALUES ('%s', '%d', '%.03f', '%.03f', '%.03f');", gS_MySQLPrefix, gS_Map, type, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2]);
	}
	
	else if((EmptyZone(gV_MapZones[type][0]) && EmptyZone(gV_MapZones[type][1])) || type >= Zone_Freestyle) // insert
	{
		if(type != Zone_Teleport)
		{
			FormatEx(sQuery, 512, "INSERT INTO %smapzones (map, type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, rot_ang, fix1_x, fix1_y, fix2_x, fix2_y) VALUES ('%s', '%d', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f');", gS_MySQLPrefix, gS_Map, type, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gF_RotateAngle[client], gV_Fix1[client][0], gV_Fix1[client][1], gV_Fix2[client][0], gV_Fix2[client][1]);
		}
		
		else
		{
			FormatEx(sQuery, 512, "INSERT INTO %smapzones (map, type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, rot_ang, fix1_x, fix1_y, fix2_x, fix2_y, destination_x, destination_y, destination_z) VALUES ('%s', '%d', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f');", gS_MySQLPrefix, gS_Map, type, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gF_RotateAngle[client], gV_Fix1[client][0], gV_Fix1[client][1], gV_Fix2[client][0], gV_Fix2[client][1], gV_Teleport[client][0], gV_Teleport[client][1], gV_Teleport[client][2]);
		}
	}

	else // update
	{
		FormatEx(sQuery, 512, "UPDATE %smapzones SET corner1_x = '%.03f', corner1_y = '%.03f', corner1_z = '%.03f', corner2_x = '%.03f', corner2_y = '%.03f', corner2_z = '%.03f', rot_ang = '%.03f', fix1_x = '%.03f', fix1_y = '%.03f', fix2_x = '%.03f', fix2_y = '%.03f' WHERE map = '%s' AND type = '%d';", gS_MySQLPrefix, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gF_RotateAngle[client], gV_Fix1[client][0], gV_Fix1[client][1], gV_Fix2[client][0], gV_Fix2[client][1], gS_Map, type);
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
	
	if(gMZ_Type[client] == Zone_CustomSpawn)
	{
		Shavit_PrintToChat(client, "Successfully placed custom spawn!.");
	}
	
	UnloadZones((gMZ_Type[client] >= Zone_Freestyle && gMZ_Type[client] != Zone_CustomSpawn)? 0:view_as<int>(gMZ_Type[client]));
	RefreshZones();
	Reset(client);
}

public Action Timer_DrawEverything(Handle Timer, any data)
{
	for(int i = 0; i < MAX_ZONES; i++)
	{
		float vPoints[8][3];

		if(i >= view_as<int>(Zone_Freestyle))
		{
			for(int j = 0; j < MULTIPLEZONES_LIMIT; j++)
			{
				if(gMZ_FreestyleTypes[j] >= Zone_Freestyle && gA_ZoneSettings[gMZ_FreestyleTypes[j]][bVisible] && !EmptyZone(gV_FreestyleZones[j][0]) && !EmptyZone(gV_FreestyleZones[j][1]))
				{
					vPoints[0] = gV_FreestyleZones[j][0];
					vPoints[7] = gV_FreestyleZones[j][1];

					if(gEV_Type == Engine_CSS)
					{
						vPoints[0][2] += 2.0;
						vPoints[7][2] += 2.0;
					}

					if(gI_ZoneStyle == 1)
					{
						vPoints[7][2] = vPoints[0][2];
					}

					if(j == 0)
					{
						CreateZonePoints(vPoints, 0.0, gV_FreeStyleZonesFixes[j][0], gV_FreeStyleZonesFixes[j][1], -PLACEHOLDER, false, true);
					}

					else
					{
						CreateZonePoints(vPoints, 0.0, gV_FreeStyleZonesFixes[j][0], gV_FreeStyleZonesFixes[j][1], -j, false, true);
					}

					int iColors[4];
					iColors[0] = gA_ZoneSettings[gMZ_FreestyleTypes[j]][iRed];
					iColors[1] = gA_ZoneSettings[gMZ_FreestyleTypes[j]][iGreen];
					iColors[2] = gA_ZoneSettings[gMZ_FreestyleTypes[j]][iBlue];
					iColors[3] = gA_ZoneSettings[gMZ_FreestyleTypes[j]][iAlpha];

					DrawZone(vPoints, gI_BeamSprite, gI_HaloSprite, iColors, gF_Interval + 0.2);
				}
			}
		}

		else
		{
			if(!gA_ZoneSettings[i][bVisible] || (EmptyZone(gV_MapZones[i][0]) && EmptyZone(gV_MapZones[i][1])))
			{
				continue;
			}

			vPoints[0] = gV_MapZones[i][0];
			vPoints[7] = gV_MapZones[i][1];

			if(gEV_Type == Engine_CSS)
			{
				vPoints[0][2] += 2.0;
				vPoints[7][2] += 2.0;
			}

			if(gI_ZoneStyle == 1)
			{
				vPoints[7][2] = vPoints[0][2];
			}

			CreateZonePoints(vPoints, 0.0, gV_MapZonesFixes[i][0], gV_MapZonesFixes[i][1], i, false, true);

			int iColors[4];
			iColors[0] = gA_ZoneSettings[i][iRed];
			iColors[1] = gA_ZoneSettings[i][iGreen];
			iColors[2] = gA_ZoneSettings[i][iBlue];
			iColors[3] = gA_ZoneSettings[i][iAlpha];

			DrawZone(vPoints, gI_BeamSprite, gI_HaloSprite, iColors, gF_Interval + 0.2);
		}
	}
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

	float vOrigin[3];
	vOrigin[0] = float(RoundToNearest(vPlayerOrigin[0] / gI_GridSnap[client]) * gI_GridSnap[client]);
	vOrigin[1] = float(RoundToNearest(vPlayerOrigin[1] / gI_GridSnap[client]) * gI_GridSnap[client]);

	if(gI_MapStep[client] == 1 || (gV_Point2[client][0] == 0.0))
	{
		vOrigin[2] = (vPlayerOrigin[2] + 144.0);
	}

	else
	{
		vOrigin = gV_Point2[client];
	}

	if(!EmptyZone(gV_Point1[client]) || !EmptyZone(gV_Point2[client]))
	{
		float vPoints[8][3];
		vPoints[0] = gV_Point1[client];
		vPoints[7] = vOrigin;

		if(gEV_Type == Engine_CSS)
		{
			vPoints[0][2] += 2.0;
			vPoints[7][2] += 2.0;
		}

		CreateZonePoints(vPoints, gF_RotateAngle[client], gV_Fix1[client], gV_Fix2[client], PLACEHOLDER, false, true);

		int iColors[4];
		iColors[0] = gA_ZoneSettings[gMZ_Type[client]][iRed];
		iColors[1] = gA_ZoneSettings[gMZ_Type[client]][iGreen];
		iColors[2] = gA_ZoneSettings[gMZ_Type[client]][iBlue];
		iColors[3] = 255;

		DrawZone(vPoints, gI_BeamSprite, gI_HaloSprite, iColors, 0.1);

		if(gMZ_Type[client] == Zone_Teleport && !EmptyZone(gV_Teleport[client]))
		{
			TE_SetupEnergySplash(gV_Teleport[client], NULL_VECTOR, false);
			TE_SendToAll(0.0);
		}
	}

	if(gI_MapStep[client] != 3 && !EmptyZone(vOrigin))
	{
		vOrigin[2] -= 144.0;

		TE_SetupBeamPoints(vPlayerOrigin, vOrigin, gI_BeamSprite, gI_HaloSprite, 0, 0, 0.1, 3.5, 3.5, 0, 0.0, {230, 83, 124, 175}, 0);
		TE_SendToAll(0.0);
	}

	return Plugin_Continue;
}

bool UsedFixes(float[2][2] fixes)
{
	for(int a = 0; a < 2; a++)
	{
		for(int b = 0; b < 2; b++)
		{
			if(fixes[a][b] > 0.0)
			{
				return true;
			}
		}
	}

	return false;
}

// by blacky https://forums.alliedmods.net/showthread.php?t=222822
// Some of those functions are by ofir753. Thanks <3
// I just remade it for SM 1.7, that's it.
/*
*
* @param client - client to check
* @param zone - zone to check (-PLACEHOLDER for freestyle 0, -zone for freestyle)
*
* returns true if a player is inside the given zone
* returns false if they aren't in it
*/
bool InsideZone(int client, int zone)
{
	float playerPos[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", playerPos);

	playerPos[2] += 5.0;

	float vPoints[8][3];

	if(zone >= 0)
	{
		vPoints[0] = gV_MapZones[zone][0];
		vPoints[7] = gV_MapZones[zone][1];

		if(UsedFixes(gV_MapZonesFixes[zone]))
		{
			// Getting the original zone points with the fixes
			CreateZonePoints(vPoints, 0.0, gV_MapZonesFixes[zone][0], gV_MapZonesFixes[zone][1], zone, true, false);
		}

		if(gF_MinusConstSin[zone] != 0.0 || gF_MinusConstCos[zone] != 0.0)
		{
			// Rotating the player so the box and the player will be on the same axis
			PointConstRotate(gF_MinusConstSin[zone], gF_MinusConstCos[zone], vPoints[0], playerPos);
		}
	}

	else
	{
		// Explanation above
		if(zone == -PLACEHOLDER)
		{
			vPoints[0] = gV_FreestyleZones[0][0];
			vPoints[7] = gV_FreestyleZones[0][1];

			if(UsedFixes(gV_FreeStyleZonesFixes[0]))
			{
				CreateZonePoints(vPoints, 0.0, gV_FreeStyleZonesFixes[0][0], gV_FreeStyleZonesFixes[0][1], zone, true, false);
			}

			if(gF_FreeStyleMinusConstSin[0] != 0.0 || gF_FreeStyleMinusConstCos[0] != 0.0)
			{
				PointConstRotate(gF_FreeStyleMinusConstSin[0], gF_FreeStyleMinusConstCos[0], vPoints[0], playerPos);
			}
		}

		else
		{
			vPoints[0] = gV_FreestyleZones[-zone][0];
			vPoints[7] = gV_FreestyleZones[-zone][1];

			if(UsedFixes(gV_FreeStyleZonesFixes[-zone]))
			{
				CreateZonePoints(vPoints, 0.0, gV_FreeStyleZonesFixes[-zone][0], gV_FreeStyleZonesFixes[-zone][1], zone, true, false);
			}

			if(gF_FreeStyleMinusConstSin[-zone] != 0.0 || gF_FreeStyleMinusConstCos[-zone] != 0.0)
			{
				PointConstRotate(gF_FreeStyleMinusConstSin[-zone], gF_FreeStyleMinusConstCos[-zone], vPoints[0], playerPos);
			}
		}
	}

	// Checking if player is inside the box after rotation
	for(int i = 0; i < 3; i++)
	{
		if(vPoints[0][i] >= playerPos[i] == vPoints[7][i] >= playerPos[i])
		{
			return false;
		}
	}

	return true;
}

// like InsideZone but for teleport zones
bool InsideTeleportZone(int client, int zone)
{
	float fPlayerPos[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", fPlayerPos);

	fPlayerPos[2] += 5.0;

	float vPoints[8][3];
	vPoints[0] = gV_FreestyleZones[zone][0];
	vPoints[7] = gV_FreestyleZones[zone][1];

	if(UsedFixes(gV_FreeStyleZonesFixes[zone]))
	{
		CreateZonePoints(vPoints, 0.0, gV_FreeStyleZonesFixes[zone][0], gV_FreeStyleZonesFixes[zone][1], zone, true, false);
	}

	if(gF_FreeStyleMinusConstSin[zone] != 0.0 || gF_FreeStyleMinusConstCos[zone] != 0.0)
	{
		PointConstRotate(gF_FreeStyleMinusConstSin[zone], gF_FreeStyleMinusConstCos[zone], vPoints[0], fPlayerPos);
	}

	// Checking if player is inside the box after rotation
	for(int i = 0; i < 3; i++)
	{
		if(vPoints[0][i] >= fPlayerPos[i] == vPoints[7][i] >= fPlayerPos[i])
		{
			return false;
		}
	}

	return true;
}

/*
* Graphically draws a zone
*    if client == 0, it draws it for all players in the game
*   if client index is between 0 and MaxClients+1, it draws for the specified client
*/
void DrawZone(float array[8][3], int beamsprite, int halosprite, int color[4], float life)
{
	for(int i = 0, i2 = 3; i2 >= 0; i += i2--)
	{
		for(int j = 1; j <= 7; j += (j / 2) + 1)
		{
			if(j != 7 - i)
			{
				TE_SetupBeamPoints(array[i], array[j], beamsprite, halosprite, 0, 0, life, 5.0, 5.0, 0, 0.0, color, 0);
				TE_SendToAll(0.0);
			}
		}
	}
}

// Rotating point around 2d axis
void PointRotate(float angle, float axis[3], float point[3])
{
	/*
	a - rotation degree as radians
	x - old X
	x' - new X
	y - old Y
	y' - new Y

	Rotation Transformation formula:
	x' = x cos(a) - y sin(a)
	y' = y cos(a) + x sin(a)
	*/

	float transTmp[3];
	transTmp[0] = point[0];
	transTmp[1] = point[1];

	// Moving point for axis = (0, 0)
	transTmp[0] -= axis[0];
	transTmp[1] -= axis[1];

	float radian = DegToRad(angle);
	float rotTmp[3];

	// Rotating point (0, 0) as axis
	rotTmp[0] = transTmp[0] * Cosine(radian) - transTmp[1] * Sine(radian);
	rotTmp[1] = transTmp[1] * Cosine(radian) + transTmp[0] * Sine(radian);

	// Moving point back
	rotTmp[0] += axis[0];
	rotTmp[1] += axis[1];

	point[0] = rotTmp[0];
	point[1] = rotTmp[1];
}

// Rotating point around 2d axis with constant sin and cos
void PointConstRotate(float sin, float cos, float axis[3], float point[3])
{
	/*
	a - rotation degree as radians
	x - old X
	x' - new X
	y - old Y
	y' - new Y

	Rotation Transformation formula:
	x' = x cos(a) - y sin(a)
	y' = y cos(a) + x sin(a)
	*/

	float transTmp[3];
	transTmp[0] = point[0];
	transTmp[1] = point[1];

	// Moving point for axis = (0, 0)
	transTmp[0] -= axis[0];
	transTmp[1] -= axis[1];

	float rotTmp[3];
	// Rotating point (0, 0) as axis
	rotTmp[0] = transTmp[0] * cos - transTmp[1] * sin;
	rotTmp[1] = transTmp[1] * cos + transTmp[0] * sin;

	// Moving point back
	rotTmp[0] += axis[0];
	rotTmp[1] += axis[1];

	point[0] = rotTmp[0];
	point[1] = rotTmp[1];
}

// Translate 2D Point
void PointTranslate(float point[3], float t[2])
{
	point[0] += t[0];
	point[1] += t[1];
}

/*
* Generates 8 points of a zone given just 2 of its points
* angle - rotated angle for not constant zone (preview zone)
* fix1 - edge fixes
* fix2 - edge fixes
* zone - PLACEHOLDER for not constant zone, -PLACEHOLDER for index 0 freestyle zone, zone id (- for free style zone)
* norotate - don't rotate zone points
* all - calculate all 8 zone points
*/
void CreateZonePoints(float point[8][3], float angle, float fix1[2], float fix2[2], int zone, bool norotate, bool all)
{
	if(all)
	{
		for(int i = 1; i < 7; i++)
		{
			for(int j = 0; j < 3; j++)
			{
				point[i][j] = point[((i >> (2-j)) & 1) * 7][j];
			}
		}
	}

	if(fix1[0] != 0.0 || fix2[0] != 0.0 || fix1[1] != 0.0 || fix2[1] != 0.0)
	{
		TranslateZone(point, fix1, fix2);
	}

	if(zone == PLACEHOLDER)
	{
		for(int i = 1; i < 8; i++)
		{
			if(zone == PLACEHOLDER)
			{
				PointRotate(angle, point[0], point[i]);
			}
		}
	}

	else if(!norotate)
	{
		if(zone >= 0 && zone != -PLACEHOLDER)
		{
			RotateZone(point, gF_ConstSin[zone], gF_ConstCos[zone]);
		}

		else
		{
			if(zone == -PLACEHOLDER)
			{
				RotateZone(point, gF_FreeStyleConstSin[0], gF_FreeStyleConstCos[0]);
			}

			else
			{
				RotateZone(point, gF_FreeStyleConstSin[-zone], gF_FreeStyleConstCos[-zone]);
			}
		}
	}
}

// Translating Zone
void TranslateZone(float point[8][3], float fix1[2], float fix2[2])
{
	float fix[2];
	// X Translate
	fix[1] = 0.0;
	fix[0] = fix1[0];

	PointTranslate(point[0], fix);
	PointTranslate(point[1], fix);
	PointTranslate(point[2], fix);
	PointTranslate(point[3], fix);

	fix[0] = fix2[0];
	PointTranslate(point[4], fix);
	PointTranslate(point[5], fix);
	PointTranslate(point[6], fix);
	PointTranslate(point[7], fix);

	// Y Translate
	fix[0] = 0.0;
	fix[1] = fix1[1];

	PointTranslate(point[0], fix);
	PointTranslate(point[1], fix);
	PointTranslate(point[4], fix);
	PointTranslate(point[5], fix);

	fix[1] = fix2[1];

	PointTranslate(point[2], fix);
	PointTranslate(point[3], fix);
	PointTranslate(point[6], fix);
	PointTranslate(point[7], fix);
}

//Rotating Zone by constant sin and cos
void RotateZone(float point[8][3], float sin, float cos)
{
	for(int i = 1; i < 8; i++)
	{
		PointConstRotate(sin, cos, point[0], point[i]);
	}
}

// thanks a lot for those stuff, I couldn't do it without you blacky!
void SQL_SetPrefix()
{
	char[] sFile = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-prefix.txt");

	File fFile = OpenFile(sFile, "r");

	if(fFile == null)
	{
		SetFailState("Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}

	else
	{
		char[] sLine = new char[PLATFORM_MAX_PATH * 2];

		while(fFile.ReadLine(sLine, PLATFORM_MAX_PATH * 2))
		{
			TrimString(sLine);
			strcopy(gS_MySQLPrefix, 32, sLine);

			break;
		}
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
		FormatEx(sQuery, 1024, "CREATE TABLE IF NOT EXISTS `%smapzones` (`id` INT AUTO_INCREMENT, `map` VARCHAR(128), `type` INT, `corner1_x` FLOAT, `corner1_y` FLOAT, `corner1_z` FLOAT, `corner2_x` FLOAT, `corner2_y` FLOAT, `corner2_z` FLOAT, `rot_ang` FLOAT NOT NULL default 0, `fix1_x` FLOAT NOT NULL default 0, `fix1_y` FLOAT NOT NULL default 0, `fix2_x` FLOAT NOT NULL default 0, `fix2_y` FLOAT NOT NULL default 0, `destination_x` FLOAT NOT NULL default 0, `destination_y` FLOAT NOT NULL default 0, `destination_z` FLOAT NOT NULL default 0, PRIMARY KEY (`id`));", gS_MySQLPrefix);

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
	FormatEx(sQuery, 64, "SELECT rot_ang FROM %smapzones LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration1_Callback, sQuery);

	FormatEx(sQuery, 64, "SELECT destination_x FROM %smapzones LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration2_Callback, sQuery);
}

public void SQL_TableMigration1_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		char[] sQuery = new char[256];

		if(gB_MySQL)
		{
			FormatEx(sQuery, 256, "ALTER TABLE `%smapzones` ADD (`rot_ang` FLOAT NOT NULL default 0, `fix1_x` FLOAT NOT NULL default 0, `fix1_y` FLOAT NOT NULL default 0, `fix2_x` FLOAT NOT NULL default 0, `fix2_y` FLOAT NOT NULL default 0);", gS_MySQLPrefix);
			gH_SQL.Query(SQL_AlterTable1_Callback, sQuery);
		}

		else
		{
			FormatEx(sQuery, 256, "ALTER TABLE `%smapzones` ADD COLUMN `rot_ang` FLOAT NOT NULL default 0;", gS_MySQLPrefix);
			gH_SQL.Query(SQL_AlterTable1_Callback, sQuery);

			for(int i = 1; i <= 2; i++)
			{
				FormatEx(sQuery, 256, "ALTER TABLE `%smapzones` ADD COLUMN `fix%d_x` FLOAT NOT NULL default 0;", gS_MySQLPrefix, i);
				gH_SQL.Query(SQL_AlterTable1_Callback, sQuery);

				FormatEx(sQuery, 256, "ALTER TABLE `%smapzones` ADD COLUMN `fix%d_y` FLOAT NOT NULL default 0;", gS_MySQLPrefix, i);
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
		FormatEx(sQuery, 256, "ALTER TABLE `%smapzones` ADD (`destination_x` FLOAT NOT NULL default 0, `destination_y` FLOAT NOT NULL default 0, `destination_z` FLOAT NOT NULL default 0);", gS_MySQLPrefix);

		gH_SQL.Query(SQL_AlterTable2_Callback, sQuery);
	}
}

public void SQL_AlterTable2_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zones module) error! Map zones' table migration (2) failed. Reason: %s", error);

		return;
	}

	// we have a database, time to load zones
	RefreshZones();
}

public void Shavit_OnRestart(int client)
{
	if(gB_TeleportToStart && !IsFakeClient(client) && !EmptyZone(gV_MapZones[Zone_Start][0]) && !EmptyZone(gV_MapZones[Zone_Start][1]))
	{
		Shavit_StartTimer(client);

		if(!EmptyZone(gF_CustomSpawn))
		{
			TeleportEntity(client, gF_CustomSpawn, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}
		
		else
		{
			float vCenter[3];
			MakeVectorFromPoints(gV_MapZones[0][0], gV_MapZones[0][1], vCenter);
			vCenter[0] /= 2.0;
			vCenter[1] /= 2.0;

			AddVectors(gV_MapZones[0][0], vCenter, vCenter);
			vCenter[2] = gV_MapZones[0][0][2];

			TeleportEntity(client, vCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}
	}
}

public void Shavit_OnEnd(int client)
{
	if(gB_TeleportToStart && !IsFakeClient(client) && !EmptyZone(gV_MapZones[Zone_End][0]) && !EmptyZone(gV_MapZones[Zone_End][1]))
	{
		float vCenter[3];
		MakeVectorFromPoints(gV_MapZones[1][0], gV_MapZones[1][1], vCenter);
		vCenter[0] /= 2.0;
		vCenter[1] /= 2.0;

		AddVectors(gV_MapZones[1][0], vCenter, vCenter);
		vCenter[2] = gV_MapZones[1][0][2];

		TeleportEntity(client, vCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
	}
}

public void Shavit_OnDatabaseLoaded(Database db)
{
	gH_SQL = db;
}
