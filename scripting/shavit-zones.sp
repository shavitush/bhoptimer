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
#include <shavit>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

#define PLACEHOLDER 32767

ServerGame gSG_Type = Game_Unknown;

Database gH_SQL = null;

char gS_Map[128];

char gS_ZoneNames[MAX_ZONES][] =
{
	"Start Zone", // starts timer
	"End Zone", // stops timer
	"Glitch Zone (Respawn Player)", // respawns the player
	"Glitch Zone (Stop Timer)", // stops the player's timer
	"Slay Player", // slays (kills) players which come to this zone
	"Freestyle Zone", // ignores style physics when at this zone. e.g. WASD when SWing
	"No Speed Limit" // ignores velocity limit in that zone
};

MapZones gMZ_Type[MAXPLAYERS+1];

// 0 - nothing
// 1 - needs to press E to setup first coord
// 2 - needs to press E to setup second coord
// 3 - confirm
int gI_MapStep[MAXPLAYERS+1];

float gF_Modifier[MAXPLAYERS+1];

// I suck
float gV_Point1[MAXPLAYERS+1][3];
float gV_Point2[MAXPLAYERS+1][3];

bool gB_Button[MAXPLAYERS+1];

float gV_MapZones[MAX_ZONES][2][3];
float gV_FreestyleZones[MULTIPLEZONES_LIMIT][2][3];

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

float gF_RotateAngle[MAXPLAYERS+1];
float gV_Fix1[MAXPLAYERS+1][2];
float gV_Fix2[MAXPLAYERS+1][2];

// beamsprite, used to draw the zone
int gI_BeamSprite = -1;
int gI_HaloSprite = -1;

// zone colors
int gI_Colors[MAX_ZONES][4];

// admin menu
Handle gH_AdminMenu = INVALID_HANDLE;

// late load?
bool gB_Late;

// cvars
ConVar gCV_ZoneStyle = null;
ConVar gCV_Interval = null;
ConVar gCV_TeleportToStart = null;

// table prefix
char gS_MySQLPrefix[32];

public Plugin myinfo =
{
	name = "[shavit] Map Zones",
	author = "shavit", // reminder: add ~big big big~ HUGE thanks to blacky < done
	description = "Map zones for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "http://forums.alliedmods.net/member.php?u=163134"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// zone natives
	CreateNative("Shavit_ZoneExists", Native_ZoneExists);
	CreateNative("Shavit_InsideZone", Native_InsideZone);

	MarkNativeAsOptional("Shavit_ZoneExists");
	// MarkNativeAsOptional("Shavit_InsideZone"); // called in shavit-core

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-zones");

	gB_Late = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	Shavit_GetDB(gH_SQL);

	if(gB_Late)
	{
		OnAdminMenuReady(null);
	}
}

public void OnPluginStart()
{
	RegAdminCmd("sm_modifier", Command_Modifier, ADMFLAG_RCON, "Changes the axis modifier for the zone editor. Usage: sm_modifier <number>");

	// menu
	RegAdminCmd("sm_zones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu");
	RegAdminCmd("sm_mapzones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu");

	RegAdminCmd("sm_deletezone", Command_DeleteZone, ADMFLAG_RCON, "Delete a mapzone");
	RegAdminCmd("sm_deleteallzones", Command_DeleteAllZones, ADMFLAG_RCON, "Delete all mapzones");

	// colors
	SetupColors();

	// cvars and stuff
	gCV_ZoneStyle = CreateConVar("shavit_zones_style", "0", "Style for mapzone drawing.\n0 - 3D box\n1 - 2D box", 0, true, 0.0, true, 1.0);
	gCV_Interval = CreateConVar("shavit_zones_interval", "1.0", "Interval between each time a mapzone is being drawn to the players.", 0, true, 0.5, true, 5.0);
	gCV_TeleportToStart = CreateConVar("shavit_zones_teleporttostart", "1", "Teleport players to the start zone on timer restart?\n0 - Disabled\n1 - Enabled", 0, true, 0.5, true, 5.0);

	AutoExecConfig();

	// draw
	// start drawing mapzones here
	CreateTimer(gCV_Interval.FloatValue, Timer_DrawEverything, INVALID_HANDLE, TIMER_REPEAT);
}

public void OnPrefixChange(ConVar cvar, const char[] oldValue, const char[] newValue)
{
	strcopy(gS_MySQLPrefix, 32, newValue);
}

public Action CheckForSQLInfo(Handle Timer)
{
	return SetSQLInfo();
}

public Action SetSQLInfo()
{
	float fTime = 0.0;

	if(gH_SQL == null)
	{
		Shavit_GetDB(gH_SQL);

		fTime = 0.5;
	}

	else
	{
		ConVar cvMySQLPrefix = FindConVar("shavit_core_sqlprefix");

		if(cvMySQLPrefix != null)
		{
			cvMySQLPrefix.GetString(gS_MySQLPrefix, 32);
			cvMySQLPrefix.AddChangeHook(OnPrefixChange);

			SQL_DBConnect();

			return Plugin_Stop;
		}

		fTime = 1.0;
	}

	CreateTimer(fTime, CheckForSQLInfo);

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

	if(type == Zone_Freestyle || type == Zone_NoVelLimit)
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

public void SetupColors()
{
	// start - cyan
	gI_Colors[Zone_Start] = {67, 210, 230, 255};

	// end - purple
	gI_Colors[Zone_End] = {165, 19, 194, 255};

	// glitches - invisible but orange for placement
	gI_Colors[Zone_Respawn] = {255, 200, 0, 255};
	gI_Colors[Zone_Stop] = {255, 200, 0, 255};
	gI_Colors[Zone_Slay] = {255, 200, 0, 255};

	// freestyle zones - blue
	gI_Colors[Zone_Freestyle] = {25, 25, 255, 195};

	// no speed limit - transparent hot pink
	gI_Colors[Zone_NoVelLimit] = {247, 3, 255, 50};
}

public void OnConfigsExecuted()
{
    SetSQLInfo();
}

public void OnMapStart()
{
	GetCurrentMap(gS_Map, 128);

	UnloadZones(0);

	if(gH_SQL != null)
	{
		RefreshZones();
	}

	gSG_Type = Shavit_GetGameType();

	if(gSG_Type == Game_CSS)
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

// 0 - all zones
public void UnloadZones(int zone)
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
			}
		}

		return;
	}

	if(zone != view_as<int>(Zone_Freestyle) || zone != view_as<int>(Zone_NoVelLimit))
	{
		for(int i = 0; i < 3; i++)
		{
			gV_MapZones[zone][0][i] = 0.0;
			gV_MapZones[zone][1][i] = 0.0;
		}
	}

	else
	{
		for(int i = 0; i < MULTIPLEZONES_LIMIT; i++)
		{
			for(int j = 0; j < 3; j++)
			{
				gV_FreestyleZones[i][0][j] = 0.0;
				gV_FreestyleZones[i][1][j] = 0.0;
			}
		}
	}
}

public void RefreshZones()
{
	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "SELECT type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, rot_ang, fix1_x, fix1_y, fix2_x, fix2_y FROM %smapzones WHERE map = '%s';", gS_MySQLPrefix, gS_Map);

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

		if(type == Zone_Freestyle || type == Zone_NoVelLimit)
		{
			gV_FreestyleZones[iFreestyleRow][0][0] = results.FetchFloat(1);
			gV_FreestyleZones[iFreestyleRow][0][1] = results.FetchFloat(2);
			gV_FreestyleZones[iFreestyleRow][0][2] = results.FetchFloat(3);
			gV_FreestyleZones[iFreestyleRow][1][0] = results.FetchFloat(4);
			gV_FreestyleZones[iFreestyleRow][1][1] = results.FetchFloat(5);
			gV_FreestyleZones[iFreestyleRow][1][2] = results.FetchFloat(6);

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
		ReplyToCommand(client, "%s Usage: sm_modifier <decimal number>", PREFIX);

		return Plugin_Handled;
	}

	char[] sArg1 = new char[16];
	GetCmdArg(1, sArg1, 16);

	if(StringToFloat(sArg1) <= 0.0)
	{
		ReplyToCommand(client, "%s Modifier must be higher than 0.", PREFIX, gF_Modifier[client]);
		return Plugin_Handled;
	}

	gF_Modifier[client] = StringToFloat(sArg1);

	ReplyToCommand(client, "%s Modifier set to \x03%.01f\x01.", PREFIX, gF_Modifier[client]);

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
		ReplyToCommand(client, "%s You can't setup mapzones when you're dead.", PREFIX);

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
		if(i == view_as<int>(Zone_Freestyle) || i == view_as<int>(Zone_NoVelLimit))
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

	if(!client)
	{
		return;
	}

	Shavit_PrintToChat(client, "Deleted \"%s\" sucessfully.", gS_ZoneNames[type]);
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

	if(!client)
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

public void Reset(int client)
{
	gF_Modifier[client] = 10.0;
	gI_MapStep[client] = 0;
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
	}
}

// neat idea for this part is by alongub, you have a cool way of thinking. :)
public void ShowPanel(int client, int step)
{
	gI_MapStep[client] = step;

	Panel pPanel = new Panel();

	char[] sPanelText = new char[128];
	FormatEx(sPanelText, 128, "Press USE (default \"E\") to set the %s corner in your current position.", step == 1? "FIRST":"SECOND");

	pPanel.DrawItem(sPanelText, ITEMDRAW_RAWLINE);
	pPanel.DrawItem("Abort zone creation");

	pPanel.Send(client, ZoneCreation_Handler, 540);

	delete pPanel;
}

public int ZoneCreation_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		Reset(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
	if(!IsValidClient(client, true))
	{
		return Plugin_Continue;
	}

	if(buttons & IN_USE)
	{
		if(!gB_Button[client] && gI_MapStep[client] > 0 && gI_MapStep[client] != 3)
		{
			float vOrigin[3];
			GetClientAbsOrigin(client, vOrigin);

			if(gI_MapStep[client] == 1)
			{
				gV_Point1[client] = vOrigin;

				// not gonna use gCV_Interval.FloatValue here as we need percision when setting up zones
				CreateTimer(0.1, Timer_Draw, client, TIMER_REPEAT);

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

	if(InsideZone(client, view_as<int>(Zone_Respawn)))
	{
		CS_RespawnPlayer(client);

		return Plugin_Continue;
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
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void CreateEditMenu(int client)
{
	Menu menu = new Menu(CreateZoneConfirm_Handler);
	menu.SetTitle("Confirm?");

	menu.AddItem("yes", "Yes");
	menu.AddItem("no", "No");
	menu.AddItem("adjust", "Adjust position");
	menu.AddItem("rotate", "Rotate zone");
	menu.AddItem("wl", "Modify width/length");

	menu.ExitButton = true;

	menu.Display(client, 20);
}

public void CreateAdjustMenu(int client, int page)
{
	Menu hMenu = new Menu(ZoneAdjuster_Handler);
	hMenu.SetTitle("Adjust the zone's position.\nUse \"sm_modifier <number>\" to set a new modifier.");

	hMenu.AddItem("done", "Done!");
	hMenu.AddItem("cancel", "Cancel");

	char[] sDisplay = new char[64];

	// sorry for this ugly code ;_;
	FormatEx(sDisplay, 64, "Point 1 | X axis +%.01f", gF_Modifier[client]);
	hMenu.AddItem("p1x_plus", sDisplay);
	FormatEx(sDisplay, 64, "Point 1 | X axis -%.01f", gF_Modifier[client]);
	hMenu.AddItem("p1x_minus", sDisplay);

	FormatEx(sDisplay, 64, "Point 1 | Y axis +%.01f", gF_Modifier[client]);
	hMenu.AddItem("p1y_plus", sDisplay);
	FormatEx(sDisplay, 64, "Point 1 | Y axis -%.01f", gF_Modifier[client]);
	hMenu.AddItem("p1y_minus", sDisplay);

	FormatEx(sDisplay, 64, "Point 1 | Z axis +%.01f", gF_Modifier[client]);
	hMenu.AddItem("p1z_plus", sDisplay);
	FormatEx(sDisplay, 64, "Point 1 | Z axis -%.01f", gF_Modifier[client]);
	hMenu.AddItem("p1z_minus", sDisplay);

	FormatEx(sDisplay, 64, "Point 2 | X axis +%.01f", gF_Modifier[client]);
	hMenu.AddItem("p2x_plus", sDisplay);
	FormatEx(sDisplay, 64, "Point 2 | X axis -%.01f", gF_Modifier[client]);
	hMenu.AddItem("p2x_minus", sDisplay);

	FormatEx(sDisplay, 64, "Point 2 | Y axis +%.01f", gF_Modifier[client]);
	hMenu.AddItem("p2y_plus", sDisplay);
	FormatEx(sDisplay, 64, "Point 2 | Y axis -%.01f", gF_Modifier[client]);
	hMenu.AddItem("p2y_minus", sDisplay);

	FormatEx(sDisplay, 64, "Point 2 | Z axis +%.01f", gF_Modifier[client]);
	hMenu.AddItem("p2z_plus", sDisplay);
	FormatEx(sDisplay, 64, "Point 2 | Z axis -%.01f", gF_Modifier[client]);
	hMenu.AddItem("p2z_minus", sDisplay);

	hMenu.ExitButton = false;

	hMenu.DisplayAt(client, page, 20);
}

public int ZoneAdjuster_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		if(StrEqual(info, "done"))
		{
			CreateEditMenu(param1);
		}

		else if(StrEqual(info, "cancel"))
		{
			Reset(param1);
		}

		else
		{
			// This is a damn big mess and I can't think of anything better to do this (I'm really tired now), any idea will be welcomed!
			// (except for using for example "0;plus" in the info string, I hate exploding strings)

			if(StrEqual(info, "p1x_plus"))
			{
				gV_Point1[param1][0] += gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03X\x01 axis \x0A(point 1) \x04increased\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "p1x_minus"))
			{
				gV_Point1[param1][0] -= gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03X\x01 axis \x0A(point 1) \x02reduced\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "p1y_plus"))
			{
				gV_Point1[param1][1] += gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Y\x01 axis \x0A(point 1) \x04increased\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "p1y_minus"))
			{
				gV_Point1[param1][1] -= gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Y\x01 axis \x0A(point 1) \x02reduced\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "p1z_plus"))
			{
				gV_Point1[param1][2] += gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Z\x01 axis \x0A(point 1) \x04increased\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "p1z_minus"))
			{
				gV_Point1[param1][2] -= gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Z\x01 axis \x0A(point 1) \x02reduced\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "p2x_plus"))
			{
				gV_Point2[param1][0] += gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03X\x01 axis \x0A(point 2) \x04increased\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "p2x_minus"))
			{
				gV_Point2[param1][0] -= gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03X\x01 axis \x0A(point 2) \x02reduced\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "p2y_plus"))
			{
				gV_Point2[param1][1] += gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Y\x01 axis \x0A(point 2) \x04increased\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "p2y_minus"))
			{
				gV_Point2[param1][1] -= gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Y\x01 axis \x0A(point 2) \x02reduced\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "p2z_plus"))
			{
				gV_Point2[param1][2] += gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Z\x01 axis \x0A(point 2) \x04increased\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "p2z_minus"))
			{
				gV_Point2[param1][2] -= gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Z\x01 axis \x0A(point 2) \x02reduced\x01 by \x03%.01f\x01.", gF_Modifier[param1]);
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

public void CreateRotateMenu(int client)
{
	Menu hMenu = new Menu(ZoneRotate_Handler);
	hMenu.SetTitle("Rotate the zone.\nUse \"sm_modifier <number>\" to set a new modifier.");

	hMenu.AddItem("done", "Done!");
	hMenu.AddItem("cancel", "Cancel");

	char[] sDisplay = new char[64];
	FormatEx(sDisplay, 64, "Rotate by +%.01f degrees", gF_Modifier[client]);
	hMenu.AddItem("plus", sDisplay);
	FormatEx(sDisplay, 64, "Rotate by -%.01f degrees", gF_Modifier[client]);
	hMenu.AddItem("minus", sDisplay);

	hMenu.Display(client, 40);
}

public int ZoneRotate_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		if(StrEqual(info, "done"))
		{
			CreateEditMenu(param1);
		}

		else if(StrEqual(info, "cancel"))
		{
			Reset(param1);
		}

		else
		{
			if(StrEqual(info, "plus"))
			{
				gF_RotateAngle[param1] += gF_Modifier[param1];

				Shavit_PrintToChat(param1, "Zone Rotated \x01 by \x03%.01f\x01 degrees.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "minus"))
			{
				gF_RotateAngle[param1] -= gF_Modifier[param1];

				Shavit_PrintToChat(param1, "Zone Rotated \x01 by \x03-%.01f\x01 degrees.", gF_Modifier[param1]);
			}

			CreateRotateMenu(param1);
		}
	}
}

public void CreateWidthLengthMenu(int client, int page)
{
	Menu hMenu = new Menu(ZoneEdge_Handler);
	hMenu.SetTitle("Rotate the zone.\nUse \"sm_modifier <number>\" to set a new modifier.");

	hMenu.AddItem("done", "Done!");
	hMenu.AddItem("cancel", "Cancel");

	char[] sDisplay = new char[64];
	FormatEx(sDisplay, 64, "Right edge | +%.01f", gF_Modifier[client]);
	hMenu.AddItem("plus_right", sDisplay);
	FormatEx(sDisplay, 64, "Right edge | -%.01f", gF_Modifier[client]);
	hMenu.AddItem("minus_right", sDisplay);

	FormatEx(sDisplay, 64, "Back edge | +%.01f", gF_Modifier[client]);
	hMenu.AddItem("plus_back", sDisplay);
	FormatEx(sDisplay, 64, "Back edge | -%.01f", gF_Modifier[client]);
	hMenu.AddItem("minus_back", sDisplay);

	FormatEx(sDisplay, 64, "Left edge | +%.01f", gF_Modifier[client]);
	hMenu.AddItem("plus_left", sDisplay);
	FormatEx(sDisplay, 64, "Left edge | -%.01f", gF_Modifier[client]);
	hMenu.AddItem("minus_left", sDisplay);

	FormatEx(sDisplay, 64, "Front edge | +%.01f", gF_Modifier[client]);
	hMenu.AddItem("plus_front", sDisplay);
	FormatEx(sDisplay, 64, "Front edge | -%.01f", gF_Modifier[client]);
	hMenu.AddItem("minus_front", sDisplay);


	DisplayMenuAtItem(hMenu, client, page, 40);
}

public int ZoneEdge_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		if(StrEqual(info, "done"))
		{
			CreateEditMenu(param1);
		}

		else if(StrEqual(info, "cancel"))
		{
			Reset(param1);
		}

		else
		{
			if(StrEqual(info, "plus_left"))
			{
				gV_Fix1[param1][0] += gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Left edge\x01 \x04increased\x01 by \x03%.01f degrees\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "minus_left"))
			{
				gV_Fix1[param1][0] -= gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Left edge\x01 \x02reduced\x01 by \x03%.01f degrees\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "plus_right"))
			{
				gV_Fix2[param1][0] += gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Right edge\x01 \x04increased\x01 by \x03%.01f degrees\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "minus_right"))
			{
				gV_Fix2[param1][0] -= gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Right edge\x01 \x02reduced\x01 by \x03%.01f degrees\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "plus_front"))
			{
				gV_Fix1[param1][1] += gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Front edge\x01 \x04increased\x01 by \x03%.01f degrees\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "minus_front"))
			{
				gV_Fix1[param1][1] -= gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Front edge\x01 \x02reduced\x01 by \x03%.01f degrees\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "plus_back"))
			{
				gV_Fix2[param1][1] += gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Back edge\x01 \x04increased\x01 by \x03%.01f degrees\x01.", gF_Modifier[param1]);
			}

			else if(StrEqual(info, "minus_back"))
			{
				gV_Fix2[param1][1] -= gF_Modifier[param1];

				Shavit_PrintToChat(param1, "\x03Back edge\x01 \x02reduced\x01 by \x03%.01f degrees\x01.", gF_Modifier[param1]);
			}

			CreateWidthLengthMenu(param1, GetMenuSelectionPosition());
		}
	}
}

public bool EmptyZone(float vZone[3])
{
	if(vZone[0] == 0.0 && vZone[1] == 0.0 && vZone[2] == 0.0)
	{
		return true;
	}

	return false;
}

public void InsertZone(int client)
{
	char[] sQuery = new char[512];

	MapZones type = gMZ_Type[client];

	if((EmptyZone(gV_MapZones[type][0]) && EmptyZone(gV_MapZones[type][1])) || type == Zone_Freestyle || type == Zone_NoVelLimit) // insert
	{
		FormatEx(sQuery, 512, "INSERT INTO %smapzones (map, type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, rot_ang, fix1_x, fix1_y, fix2_x, fix2_y) VALUES ('%s', '%d', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f');", gS_MySQLPrefix, gS_Map, type, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gF_RotateAngle[client], gV_Fix1[client][0], gV_Fix1[client][1], gV_Fix2[client][0], gV_Fix2[client][1]);
	}

	else // update
	{
		FormatEx(sQuery, 512, "UPDATE %smapzones SET corner1_x = '%.03f', corner1_y = '%.03f', corner1_z = '%.03f', corner2_x = '%.03f', corner2_y = '%.03f', corner2_z = '%.03f', rot_ang = '%.03f', fix1_x = '%.03f', fix1_y = '%.03f', fix2_x = '%.03f', fix2_y = '%.03f' WHERE map = '%s' AND type = '%d';", gS_MySQLPrefix, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gF_RotateAngle[client], gV_Fix1[client][0], gV_Fix1[client][1], gV_Fix2[client][0], gV_Fix2[client][1], gS_Map, type);
	}

	gH_SQL.Query(SQL_InsertZone_Callback, sQuery, type);

	Reset(client);
}

public void SQL_InsertZone_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zone insert) SQL query failed. Reason: %s", error);

		return;
	}

	bool bFreestyle = (data == Zone_Freestyle || data == Zone_NoVelLimit);

	UnloadZones(bFreestyle? 0:data);
	RefreshZones();
}

public Action Timer_DrawEverything(Handle Timer, any data)
{
	for(int i = 0; i < MAX_ZONES; i++)
	{
		float vPoints[8][3];

		if(i == view_as<int>(Zone_Freestyle) || i == view_as<int>(Zone_NoVelLimit))
		{
			for(int j = 0; j < MULTIPLEZONES_LIMIT; j++)
			{
				if(EmptyZone(gV_FreestyleZones[j][0]) && EmptyZone(gV_FreestyleZones[j][1]))
				{
					continue;
				}

				vPoints[0] = gV_FreestyleZones[j][0];
				vPoints[7] = gV_FreestyleZones[j][1];

				if(gCV_ZoneStyle.BoolValue)
				{
					vPoints[7][2] = vPoints[0][2];
				}

				if(j == 0)
				{
					CreateZonePoints(vPoints, 0.0, gV_FreeStyleZonesFixes[j][0], gV_FreeStyleZonesFixes[j][1], -PLACEHOLDER, false);
				}

				else
				{
					CreateZonePoints(vPoints, 0.0, gV_FreeStyleZonesFixes[j][0], gV_FreeStyleZonesFixes[j][1], -j, false);
				}

				DrawZone(0, vPoints, gI_BeamSprite, 0, gI_Colors[i], gCV_Interval.FloatValue);
			}
		}

		else
		{
			// check shavit.inc, blacklisting glitch zones from being drawn
			if(i == view_as<int>(Zone_Respawn))
			{
				continue;
			}

			if(i == view_as<int>(Zone_Stop))
			{
				continue;
			}

			if(!EmptyZone(gV_MapZones[i][0]) && !EmptyZone(gV_MapZones[i][1]))
			{
				vPoints[0] = gV_MapZones[i][0];
				vPoints[7] = gV_MapZones[i][1];

				if(gCV_ZoneStyle.BoolValue)
				{
					vPoints[7][2] = vPoints[0][2];
				}

				CreateZonePoints(vPoints, 0.0, gV_MapZonesFixes[i][0], gV_MapZonesFixes[i][1], i, false);

				DrawZone(0, vPoints, gI_BeamSprite, gI_HaloSprite, gI_Colors[i], gCV_Interval.FloatValue);
			}
		}
	}
}

public Action Timer_Draw(Handle Timer, any data)
{
	if(!IsValidClient(data, true) || gI_MapStep[data] == 0)
	{
		Reset(data);

		return Plugin_Stop;
	}

	float vOrigin[3];

	if(gI_MapStep[data] == 1 || gV_Point2[data][0] == 0.0)
	{
		GetClientAbsOrigin(data, vOrigin);

		vOrigin[2] += 144.0;
	}

	else
	{
		vOrigin = gV_Point2[data];
	}

	float vPoints[8][3];
	vPoints[0] = gV_Point1[data];
	vPoints[7] = vOrigin;

	CreateZonePoints(vPoints, gF_RotateAngle[data], gV_Fix1[data], gV_Fix2[data], PLACEHOLDER, false);

	DrawZone(0, vPoints, gI_BeamSprite, 0, gI_Colors[gMZ_Type[data]], 0.1);

	return Plugin_Continue;
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
public bool InsideZone(int client, int zone)
{
	float playerPos[3];

	GetEntPropVector(client, Prop_Send, "m_vecOrigin", playerPos);
	playerPos[2] += 5.0;

	float vPoints[8][3];

	if(zone >= 0)
	{
		vPoints[0] = gV_MapZones[zone][0];
		vPoints[7] = gV_MapZones[zone][1];

		// Getting the original zone points with the fixes
		CreateZonePoints(vPoints, 0.0, gV_MapZonesFixes[zone][0], gV_MapZonesFixes[zone][1], zone, true);

		// Rotating the player so the box and the player will be on the same axis
		PointConstRotate(gF_MinusConstSin[zone], gF_MinusConstCos[zone], vPoints[0], playerPos);
	}
	else
	{
		// Explanation above
		if(zone == -PLACEHOLDER)
		{
			vPoints[0] = gV_FreestyleZones[0][0];
			vPoints[7] = gV_FreestyleZones[0][1];

			CreateZonePoints(vPoints, 0.0, gV_FreeStyleZonesFixes[0][0], gV_FreeStyleZonesFixes[0][1], zone, true);

			PointConstRotate(gF_FreeStyleMinusConstSin[0], gF_FreeStyleMinusConstCos[0], vPoints[0], playerPos);
		}

		else
		{
			vPoints[0] = gV_FreestyleZones[-zone][0];
			vPoints[7] = gV_FreestyleZones[-zone][1];

			CreateZonePoints(vPoints, 0.0, gV_FreeStyleZonesFixes[-zone][0], gV_FreeStyleZonesFixes[-zone][1], zone, true);

			PointConstRotate(gF_FreeStyleMinusConstSin[-zone], gF_FreeStyleMinusConstCos[-zone], vPoints[0], playerPos);
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

/*
* Graphically draws a zone
*    if client == 0, it draws it for all players in the game
*   if client index is between 0 and MaxClients+1, it draws for the specified client
*/
public void DrawZone(int client, float array[8][3], int beamsprite, int halosprite, int color[4], float life)
{
	for(int i = 0, i2 = 3; i2 >= 0; i += i2--)
	{
		for(int j = 1; j <= 7; j += (j / 2) + 1)
		{
			if(j != 7 - i)
			{
				TE_SetupBeamPoints(array[i], array[j], beamsprite, halosprite, 0, 0, life, 5.0, 5.0, 0, 0.0, color, 0);

				if(0 < client <= MaxClients)
				{
					TE_SendToClient(client, 0.0);
				}

				else
				{
					TE_SendToAll(0.0);
				}
			}
		}
	}
}

// Rotating point around 2d axis
public void PointRotate(float angle, float axis[3], float point[3])
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
public void PointConstRotate(float sin, float cos, float axis[3], float point[3])
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
public void PointTranslate(float point[3], float t[2])
{
	point[0] += t[0];
	point[1] += t[1];
}

/*
* Generates all 8 points of a zone given just 2 of its points
* angle - rotated angle for not constant zone (preview zone)
* fix1 - edge fixes
* fix2 - edge fixes
* zone - PLACEHOLDER for not constant zone, -PLACEHOLDER for index 0 freestyle zone, zone id (- for free style zone)
* norotate - dont rotae
*/
public void CreateZonePoints(float point[8][3], float angle, float fix1[2], float fix2[2], int zone, bool norotate)
{
	for(int i = 1; i < 7; i++)
	{
		for(int j = 0; j < 3; j++)
		{
			point[i][j] = point[((i >> (2-j)) & 1) * 7][j];
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
	else
	{
		if(zone >= 0 && zone != -PLACEHOLDER)
		{
			if(!norotate)
			{
				RotateZone(point, gF_ConstSin[zone], gF_ConstCos[zone]);
			}
		}

		else
		{
			if(zone == -PLACEHOLDER)
			{
				if(!norotate)
				{
					RotateZone(point, gF_FreeStyleConstSin[0], gF_FreeStyleConstCos[0]);
				}
			}

			else
			{
				if(!norotate)
				{
					RotateZone(point, gF_FreeStyleConstSin[-zone], gF_FreeStyleConstCos[-zone]);
				}
			}
		}
	}
}

// Translating Zone
public void TranslateZone(float point[8][3], float fix1[2], float fix2[2])
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
public void RotateZone(float point[8][3], float sin, float cos)
{
	for(int i = 1; i < 8; i++)
	{
		PointConstRotate(sin, cos, point[0], point[i]);
	}
}

// thanks a lot for those stuff, I couldn't do it without you blacky!

public void SQL_DBConnect()
{
	if(SQL_CheckConfig("shavit"))
	{
		if(gH_SQL != null)
		{
			char[] sQuery = new char[512];
			FormatEx(sQuery, 512, "CREATE TABLE IF NOT EXISTS `%smapzones` (`id` INT AUTO_INCREMENT, `map` VARCHAR(128), `type` INT, `corner1_x` FLOAT, `corner1_y` FLOAT, `corner1_z` FLOAT, `corner2_x` FLOAT, `corner2_y` FLOAT, `corner2_z` FLOAT, `rot_ang` FLOAT NOT NULL default 0, `fix1_x` FLOAT NOT NULL default 0, `fix1_y` FLOAT NOT NULL default 0, `fix2_x` FLOAT NOT NULL default 0, `fix2_y` FLOAT NOT NULL default 0, PRIMARY KEY (`id`));", gS_MySQLPrefix);

			gH_SQL.Query(SQL_CreateTable_Callback, sQuery);
		}
	}

	else
	{
		SetFailState("Timer (zones module) startup failed. Reason: %s", "\"shavit\" is not a specified entry in databases.cfg.");
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
	FormatEx(sQuery, 128, "SELECT rot_ang FROM %smapzones;", gS_MySQLPrefix);

	gH_SQL.Query(SQL_CheckRotation_Callback, sQuery);

	// we have a database, time to load zones
	RefreshZones();
}

public void SQL_CheckRotation_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	// rot_ang and the new stuff are missing. this is for people that update [shavit] from an older version
	if(results == null)
	{
		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "ALTER TABLE `%smapzones` ADD (`rot_ang` FLOAT NOT NULL default 0, `fix1_x` FLOAT NOT NULL default 0, `fix1_y` FLOAT NOT NULL default 0, `fix2_x` FLOAT NOT NULL default 0, `fix2_y` FLOAT NOT NULL default 0);", gS_MySQLPrefix);

		gH_SQL.Query(SQL_AlterTable_Callback, sQuery);
	}
}

public void SQL_AlterTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zones module) error! Map zones' table alteration failed. Reason: %s", error);

		return;
	}
}

public void Shavit_OnRestart(int client)
{
	if(gCV_TeleportToStart.BoolValue && !IsFakeClient(client) && !EmptyZone(gV_MapZones[0][0]) && !EmptyZone(gV_MapZones[0][1]))
	{
		float vCenter[3];
		MakeVectorFromPoints(gV_MapZones[0][0], gV_MapZones[0][1], vCenter);

		// calculate center
		vCenter[0] /= 2;
		vCenter[1] /= 2;
		// i could also use ScaleVector() by 0.5f I guess? dunno which is more resource intensive, so i'll do it manually.

		// old method of calculating Z axis
		// vCenter[2] /= 2;
		// vCenter[2] -= 20;

		// spawn at the same Z axis the start zone is at
		// this may break some spawns, where there's a displacement instead of a flat surface at the spawn point, for example; bhop_monster_jam ~ recompile with this commented and the old method uncommented if it's an issue!
		// vCenter[2] = gV_MapZones[0][0] + 84.0;
		// ^ didn't work

		AddVectors(gV_MapZones[0][0], vCenter, vCenter);

		vCenter[2] = gV_MapZones[0][0][2];

		TeleportEntity(client, vCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
	}
}

public void Shavit_OnEnd(int client)
{
	if(gCV_TeleportToStart.BoolValue && !IsFakeClient(client) && !EmptyZone(gV_MapZones[1][0]) && !EmptyZone(gV_MapZones[1][1]))
	{
		float vCenter[3];
		MakeVectorFromPoints(gV_MapZones[1][0], gV_MapZones[1][1], vCenter);

		// calculate center
		vCenter[0] /= 2;
		vCenter[1] /= 2;

		AddVectors(gV_MapZones[1][0], vCenter, vCenter);

		vCenter[2] = gV_MapZones[1][0][2];

		TeleportEntity(client, vCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
	}
}
