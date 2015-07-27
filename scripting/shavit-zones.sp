/*
 * shavit's Timer - Map Zones
 * by: shavit
 *
 * This file is part of Shavit's Timer.
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
#pragma dynamic 131072 // let's make stuff faster
#pragma newdecls required // yay for SM 1.7 :D

Database gH_SQL = null;

char gS_Map[128];

char gS_ZoneNames[MAX_ZONES][] =
{
	"Start Zone",
	"End Zone",
	"Glitch Zone (Respawn Player)",
	"Glitch Zone (Stop Timer)",
	"Slay Player",
	"Freestyle Zone" // ignores style physics when at this zone. e.g. WASD when SWing
};

MapZones gMZ_Type[MAXPLAYERS+1];

// 0 - nothing
// 1 - needs to press E to setup first coord
// 2 - needs to press E to setup second coord
// 3 - confirm
int gI_MapStep[MAXPLAYERS+1];

// I suck
float gV_Point1[MAXPLAYERS+1][3];
float gV_Point2[MAXPLAYERS+1][3];

bool gB_Button[MAXPLAYERS+1];

float gV_MapZones[MAX_ZONES][2][3];

int gI_BeamSprite = -1;

int gI_Colors[MAX_ZONES][4];

// admin menu
Handle gH_AdminMenu = INVALID_HANDLE;

bool gB_Late;

// cvars
ConVar gCV_ZoneStyle = null;
bool gB_ZoneStyle = false;

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

	// registers library, check "LibraryExists(const String:name[])" in order to use with other plugins
	RegPluginLibrary("shavit-zones");
	
	gB_Late = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	// database shit
	Shavit_GetDB(gH_SQL);
	SQL_DBConnect();
}

public void OnPluginStart()
{
	// menu
	RegAdminCmd("sm_zones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu");
	RegAdminCmd("sm_mapzones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu");
	
	RegAdminCmd("sm_deletezone", Command_DeleteZone, ADMFLAG_RCON, "Delete a mapzone");
	RegAdminCmd("sm_deleteallzones", Command_DeleteAllZones, ADMFLAG_RCON, "Delete all mapzones");
	
	// colors
	SetupColors();
	
	// draw
	// start drawing timer here
	CreateTimer(0.10, Timer_DrawEverything, INVALID_HANDLE, TIMER_REPEAT);
	
	if(gB_Late)
	{
		OnAdminMenuReady(null);
	}
	
	// cvars and stuff
	gCV_ZoneStyle = CreateConVar("shavit_zones_style", "0", "Style for mapzone drawing.\n0 - 3D box\n1 - 2D box");
	HookConVarChange(gCV_ZoneStyle, OnConVarChanged);
	
	AutoExecConfig();
	gB_ZoneStyle = GetConVarBool(gCV_ZoneStyle);
}

public void OnConVarChanged(ConVar cvar, const char[] sOld, const char[] sNew)
{
	// using an if() statement just incase I'll add more cvars.
	if(cvar == gCV_ZoneStyle)
	{
		gB_ZoneStyle = view_as<bool>StringToInt(sNew);
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
		}
	}
}

public void CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayTitle)
	{
		FormatEx(buffer, maxlength, "Timer Commands:");
	}

	else if (action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "Timer Commands");
	}
}

public void AdminMenu_Zones(Handle topmenu,  TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "Add map zone");
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
		FormatEx(buffer, maxlength, "Delete map zone");
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
		FormatEx(buffer, maxlength, "Delete ALL map zones");
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
	
	return view_as<int>(InsideZone(client, gV_MapZones[type][0], gV_MapZones[type][1]));
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
}

public void OnMapStart()
{
	GetCurrentMap(gS_Map, 128);
	
	UnloadZones(0);
	
	gI_BeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
	
	RefreshZones();
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
	}
	
	else
	{
		for(int i = 0; i < 3; i++)
		{
			gV_MapZones[zone][0][i] = 0.0;
			gV_MapZones[zone][1][i] = 0.0;
		}
	}
}

public void RefreshZones()
{
	char sQuery[256];
	FormatEx(sQuery, 256, "SELECT type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z FROM mapzones WHERE map = '%s';", gS_Map);
	
	SQL_TQuery(gH_SQL, SQL_RefreshZones_Callback, sQuery, DBPrio_High);
}

public void SQL_RefreshZones_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (zone refresh) SQL query failed. Reason: %s", error);

		return;
	}
	
	while(SQL_FetchRow(hndl))
	{
		MapZones type = view_as<MapZones>SQL_FetchInt(hndl, 0);
		
		if(type == Zone_Freestyle)
		{
			/*
			* handle correctly
			*/
		}
		
		else
		{
			gV_MapZones[type][0][0] = SQL_FetchFloat(hndl, 1);
			gV_MapZones[type][0][1] = SQL_FetchFloat(hndl, 2);
			gV_MapZones[type][0][2] = SQL_FetchFloat(hndl, 3);
			gV_MapZones[type][1][0] = SQL_FetchFloat(hndl, 4);
			gV_MapZones[type][1][1] = SQL_FetchFloat(hndl, 5);
			gV_MapZones[type][1][2] = SQL_FetchFloat(hndl, 6);
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

	Handle menu = CreateMenu(Select_Type_MenuHandler);
	SetMenuTitle(menu, "Select a zone type:");

	AddMenuItem(menu, "0", "Start Zone");
	AddMenuItem(menu, "1", "End Zone");
	AddMenuItem(menu, "2", "Glitch Zone (Respawn Player)");
	AddMenuItem(menu, "3", "Glitch Zone (Stop Timer)");

	SetMenuExitButton(menu, true);

	DisplayMenu(menu, client, 20);

	return Plugin_Handled;
}

public Action Command_DeleteZone(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Handle menu = CreateMenu(DeleteZone_MenuHandler);
	SetMenuTitle(menu, "Delete a zone:\nPressing a zone will delete it. This action CANNOT BE REVERTED!");

	for (int i = 0; i < MAX_ZONES; i++)
	{
		if(!EmptyZone(gV_MapZones[i][0]) && !EmptyZone(gV_MapZones[i][1]))
		{
			char sInfo[8];
			IntToString(i, sInfo, 8);
			AddMenuItem(menu, sInfo, gS_ZoneNames[i]);
		}
	}
	
	if(!GetMenuItemCount(menu))
	{
		AddMenuItem(menu, "-1", "No zones found.");
	}

	SetMenuExitButton(menu, true);

	DisplayMenu(menu, client, 20);

	return Plugin_Handled;
}

public int DeleteZone_MenuHandler(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[8];
		GetMenuItem(menu, param2, info, 8);
		
		int iInfo = StringToInt(info);
		
		if(iInfo == -1)
		{
			return;
		}

		char sQuery[256];
		FormatEx(sQuery, 256, "DELETE FROM mapzones WHERE map = '%s' AND type = '%d';", gS_Map, iInfo);
		
		Handle hDatapack = CreateDataPack();
		WritePackCell(hDatapack, GetClientSerial(param1));
		WritePackCell(hDatapack, iInfo);
		
		SQL_TQuery(gH_SQL, SQL_DeleteZone_Callback, sQuery, hDatapack);
	}

	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public void SQL_DeleteZone_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);
	int client = GetClientFromSerial(ReadPackCell(data));
	int type = ReadPackCell(data);
	
	CloseHandle(data);
	
	if(hndl == null)
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
	
	PrintToChat(client, "%s Deleted \"%s\" sucessfully.", PREFIX, gS_ZoneNames[type]);
}

public Action Command_DeleteAllZones(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Handle menu = CreateMenu(DeleteAllZones_MenuHandler);
	SetMenuTitle(menu, "Delete ALL mapzones?\nPressing \"Yes\" will delete all the existing mapzones for this map.\nThis action CANNOT BE REVERTED!");

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		AddMenuItem(menu, "-1", "NO!");
	}

	AddMenuItem(menu, "yes", "YES!!! DELETE ALL THE MAPZONES!!!");
	
	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		AddMenuItem(menu, "-1", "NO!");
	}

	SetMenuExitButton(menu, true);

	DisplayMenu(menu, client, 20);

	return Plugin_Handled;
}

public int DeleteAllZones_MenuHandler(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[8];
		GetMenuItem(menu, param2, info, 8);
		
		int iInfo = StringToInt(info);
		
		if(iInfo == -1)
		{
			return;
		}

		char sQuery[256];
		FormatEx(sQuery, 256, "DELETE FROM mapzones WHERE map = '%s';", gS_Map);
		
		SQL_TQuery(gH_SQL, SQL_DeleteAllZones_Callback, sQuery, GetClientSerial(param1));
	}

	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public void SQL_DeleteAllZones_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
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
	
	PrintToChat(client, "%s Deleted all map zones sucessfully.", PREFIX);
}

public int Select_Type_MenuHandler(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[8];
		GetMenuItem(menu, param2, info, 8);

		gMZ_Type[param1] = view_as<MapZones>StringToInt(info);

		ShowPanel(param1, 1);
	}

	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public void Reset(int client)
{
	gI_MapStep[client] = 0;
	
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
	
	Handle hPanel = CreatePanel();

	char sPanelText[128];
	FormatEx(sPanelText, 128, "Press USE (default \"E\") to set the %s corner in your current position.", step == 1? "FIRST":"SECOND");

	DrawPanelItem(hPanel, sPanelText, ITEMDRAW_RAWLINE);
	DrawPanelItem(hPanel, "Abort zone creation");

	SendPanelToClient(hPanel, client, ZoneCreation_Handler, 540);
	CloseHandle(hPanel);
}

public int ZoneCreation_Handler(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		Reset(param1);
	}
	
	else if (action == MenuAction_End)
	{
		CloseHandle(menu);
	}
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
				
				CreateTimer(0.1, Timer_Draw, client, TIMER_REPEAT);
				
				ShowPanel(client, 2);
			}
			
			else if(gI_MapStep[client] == 2)
			{
				//vOrigin[2] += 72; // was requested to make it higher
				vOrigin[2] += 144;
				gV_Point2[client] = vOrigin;
				
				gI_MapStep[client]++;
				
				Handle menu = CreateMenu(CreateZoneConfirm_Handler);
				SetMenuTitle(menu, "Confirm?");
			
				AddMenuItem(menu, "yes", "Yes");
				AddMenuItem(menu, "no", "No");
			
				SetMenuExitButton(menu, true);
			
				DisplayMenu(menu, client, 20);
			}
		}
		
		gB_Button[client] = true;
	}
	
	else
	{
		gB_Button[client] = false;
	}
	
	if(InsideZone(client, gV_MapZones[Zone_Respawn][0], gV_MapZones[Zone_Respawn][1]))
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
	
	if(InsideZone(client, gV_MapZones[Zone_Start][0], gV_MapZones[Zone_Start][1]))
	{
		Shavit_StartTimer(client);
		
		return Plugin_Continue;
	}
	
	if(bStarted)
	{
		if(InsideZone(client, gV_MapZones[Zone_Slay][0], gV_MapZones[Zone_Slay][1]))
		{
			Shavit_StopTimer(client);
			
			ForcePlayerSuicide(client);
		}
		
		if(InsideZone(client, gV_MapZones[Zone_Stop][0], gV_MapZones[Zone_Stop][1]))
		{
			Shavit_StopTimer(client);
		}
		
		if(InsideZone(client, gV_MapZones[Zone_End][0], gV_MapZones[Zone_End][1]))
		{
			Shavit_FinishMap(client);
		}
	}
	
	return Plugin_Continue;
}

public int CreateZoneConfirm_Handler(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[8];
		GetMenuItem(menu, param2, info, 8);

		if(StrEqual(info, "yes"))
		{
			InsertZone(param1);
			
			gI_MapStep[param1] = 0;
		}
	}

	else if(action == MenuAction_End)
	{
		Reset(param1);
		
		CloseHandle(menu);
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
	char sQuery[256];

	MapZones type = gMZ_Type[client];
	
	if(type == Zone_Freestyle)
	{
		FormatEx(sQuery, 256, "INSERT INTO mapzones (map, type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z) VALUES ('%s', '%d', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f');", gS_Map, type, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2]);
		
		/*
		* set gV_FreestyleZones[number] array here
		*/
	}
	
	else
	{
		 if(EmptyZone(gV_MapZones[type][0]) && EmptyZone(gV_MapZones[type][1])) // insert
		{
			FormatEx(sQuery, 256, "INSERT INTO mapzones (map, type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z) VALUES ('%s', '%d', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f');", gS_Map, type, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2]);
		}
		
		else // update
		{
			FormatEx(sQuery, 256, "UPDATE mapzones SET corner1_x = '%.03f', corner1_y = '%.03f', corner1_z = '%.03f', corner2_x = '%.03f', corner2_y = '%.03f', corner2_z = '%.03f' WHERE map = '%s' AND type = '%d';", gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gS_Map, type);
		}
		
		gV_MapZones[type][0] = gV_Point1[client];
		gV_MapZones[type][1] = gV_Point2[client];
	}
	
	SQL_TQuery(gH_SQL, SQL_InsertZone_Callback, sQuery, GetClientSerial(client));
	
	Reset(client);
}

public void SQL_InsertZone_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (zone insert) SQL query failed. Reason: %s", error);

		return;
	}
}

public Action Timer_DrawEverything(Handle Timer, any data)
{
	for(int i = 0; i < MAX_ZONES; i++)
	{
		// check shavit.inc, blacklisting glitch zones from being drawn
		if(i == view_as<int>Zone_Respawn || i == view_as<int>Zone_Stop)
		{
			continue;
		}
		
		//PrintToChatAll("%d", i);
		
		if(i == view_as<int>Zone_Freestyle)
		{
			/*
			* loop through freestyle zones and draw seperately
			*/
		}
		
		else
		{
			if(!EmptyZone(gV_MapZones[i][0]) && !EmptyZone(gV_MapZones[i][1]))
			{
				float vPoints[8][3];
				vPoints[0] = gV_MapZones[i][0];
				vPoints[7] = gV_MapZones[i][1];
				
				if(gB_ZoneStyle)
				{
					vPoints[7][2] = vPoints[0][2];
				}
				
				CreateZonePoints(vPoints);
				
				DrawZone(0, vPoints, gI_BeamSprite, 0, gI_Colors[i], 0.10);
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
		
		vOrigin[2] += 144;
	}
	
	else
	{
		vOrigin = gV_Point2[data];
	}
	
	float vPoints[8][3];
	vPoints[0] = gV_Point1[data];
	vPoints[7] = vOrigin;
	
	CreateZonePoints(vPoints);
	
	DrawZone(0, vPoints, gI_BeamSprite, 0, gI_Colors[gMZ_Type[data]], 0.1);
	
	return Plugin_Continue;
}

// by blacky https://forums.alliedmods.net/showthread.php?t=222822
// I just remade it for SM 1.7, that's it.
/*
* returns true if a player is inside the given zone
* returns false if they aren't in it
*/
public bool InsideZone(int client, float point1[3], float point2[3])
{
    float playerPos[3];
    
    GetEntPropVector(client, Prop_Send, "m_vecOrigin", playerPos);
    playerPos[2] += 5.0;
    
    for(int i = 0; i < 3; i++)
    {
        if(point1[i] >= playerPos[i] == point2[i] >= playerPos[i])
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

/*
* Generates all 8 points of a zone given just 2 of its points
*/
public void CreateZonePoints(float point[8][3])
{
	for(int i = 1; i < 7; i++)
	{
		for(int j = 0; j < 3; j++)
		{
			point[i][j] = point[((i >> (2-j)) & 1) * 7][j];
		}
	}
}
// thanks a lot for those stuff, I couldn't do it without you blacky!

public void SQL_DBConnect()
{
	if(SQL_CheckConfig("shavit"))
	{
		if(gH_SQL != null)
		{
			SQL_TQuery(gH_SQL, SQL_CreateTable_Callback, "CREATE TABLE IF NOT EXISTS `mapzones` (`id` INT AUTO_INCREMENT, `map` VARCHAR(128), `type` INT, `corner1_x` FLOAT, `corner1_y` FLOAT, `corner1_z` FLOAT, `corner2_x` FLOAT, `corner2_y` FLOAT, `corner2_z` FLOAT, PRIMARY KEY (`id`));");
		}
	}

	else
	{
		SetFailState("Timer (zones module) startup failed. Reason: %s", "\"shavit\" is not a specified entry in databases.cfg.");
	}
}

public void SQL_CreateTable_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (zones module) error! Map zones' table creation failed. Reason: %s", error);

		return;
	}
}

public void Shavit_OnRestart(int client)
{
	if(!EmptyZone(gV_MapZones[0][0]) && !EmptyZone(gV_MapZones[0][1]))
	{
		float vCenter[3];
		MakeVectorFromPoints(gV_MapZones[0][0], gV_MapZones[0][1], vCenter);
		
		vCenter[0] /= 2;
		vCenter[1] /= 2;
		vCenter[2] /= 2;
		
		vCenter[2] -= 20;
		
		AddVectors(gV_MapZones[0][0], vCenter, vCenter);
		
		TeleportEntity(client, vCenter, NULL_VECTOR, view_as<float>{0.0, 0.0, 0.0});
	}
}
