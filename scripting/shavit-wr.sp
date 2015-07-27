/*
 * shavit's Timer - World Records
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
#include <shavit>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma semicolon 1
#pragma dynamic 131072 // let's make stuff faster
#pragma newdecls required // We're at 2015 :D

//#define DEBUG

bool gB_Late;

// forwards
Handle gH_OnWorldRecord = null;

// database handle
Handle gH_SQL = null;

BhopStyle gBS_LastWR[MAXPLAYERS+1];

char gS_Map[128]; // blame workshop paths to be so fkn long

// current wr stats
float gF_WRTime[MAX_STYLES];
char gS_WRName[MAX_STYLES][MAX_NAME_LENGTH];

float gF_PlayerRecord[MAXPLAYERS+1][MAX_STYLES];

// admin menu
Handle gH_AdminMenu = null;

public Plugin myinfo = 
{
	name = "[shavit] World Records",
	author = "shavit",
	description = "World records for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "http://forums.alliedmods.net/member.php?u=163134"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// get wr
	CreateNative("Shavit_GetWRTime", Native_GetWRTime);
	CreateNative("Shavit_GetWRName", Native_GetWRName);

	// get pb
	CreateNative("Shavit_GetPlayerPB", Native_GetPlayerPB);
	
	MarkNativeAsOptional("Shavit_GetWRTime");
	MarkNativeAsOptional("Shavit_GetWRName");
	MarkNativeAsOptional("Shavit_GetPlayerPB");

	// registers library, check "LibraryExists(const String:name[])" in order to use with other plugins
	RegPluginLibrary("shavit-wr");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// database connections
	Shavit_GetDB(gH_SQL);
	SQL_DBConnect();

	// debug because I was making this all by myself and no one wanted to help me *sniff*
	#if defined DEBUG
	RegConsoleCmd("sm_junk", Command_Junk);
	#endif

	// forwards
	gH_OnWorldRecord = CreateGlobalForward("Shavit_OnWorldRecord", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	// WR command
	RegConsoleCmd("sm_wr", Command_WR);
	RegConsoleCmd("sm_worldrecord", Command_WR);

	// WRSW command
	RegConsoleCmd("sm_wrsw", Command_WRSW);
	RegConsoleCmd("sm_worldrecordsw", Command_WRSW);

	// delete records
	RegAdminCmd("sm_delete", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface");
	RegAdminCmd("sm_deleterecord", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface");
	RegAdminCmd("sm_deleterecords", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface");
	RegAdminCmd("sm_deleteall", Command_DeleteAll, ADMFLAG_RCON, "Deletes all the records");

	OnAdminMenuReady(null);
}

public void OnAdminMenuReady(Handle topmenu)
{
	if(LibraryExists("adminmenu") && ((gH_AdminMenu = GetAdminTopMenu()) != null))
	{
		TopMenuObject tmoTimer = FindTopMenuCategory(gH_AdminMenu, "Timer Commands");
	
		if(tmoTimer != INVALID_TOPMENUOBJECT)
		{
			AddToTopMenu(gH_AdminMenu, "sm_deleteall", TopMenuObject_Item, AdminMenu_DeleteAll, tmoTimer, "sm_deleteall", ADMFLAG_RCON);
			AddToTopMenu(gH_AdminMenu, "sm_delete", TopMenuObject_Item, AdminMenu_Delete, tmoTimer, "sm_delete", ADMFLAG_RCON);
		}
	}
}

public void AdminMenu_Delete(Handle topmenu,  TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "Delete a single record");
	}

	else if(action == TopMenuAction_SelectOption)
	{
		Command_Delete(param, 0);
	}
}

public void AdminMenu_DeleteAll(Handle topmenu,  TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "Delete ALL map records");
	}

	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteAll(param, 0);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit"))
	{
		Shavit_GetDB(gH_SQL);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit"))
	{
		Shavit_GetDB(gH_SQL);
	}

	else if(StrEqual(name, "adminmenu"))
	{
		gH_AdminMenu = null;
	}
}

public void OnMapStart()
{
	GetCurrentMap(gS_Map, 128);

	if(gH_SQL != null)
	{
		UpdateWRCache();
	}
}

public void OnClientPutInServer(int client)
{
	for(int i = 0; i < MAX_STYLES; i++)
	{
		gF_PlayerRecord[client][i] = 0.0;
	}

	if(!IsClientConnected(client) || IsFakeClient(client) || gH_SQL == null)
	{
		return;
	}

	UpdateClientCache(client);
}

public void UpdateClientCache(int client)
{
	char sAuthID[32];
	GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

	char sQuery[256];
	FormatEx(sQuery, 256, "SELECT time, style FROM playertimes WHERE map = '%s' AND auth = '%s';", gS_Map, sAuthID);
	SQL_TQuery(gH_SQL, SQL_UpdateCache_Callback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void SQL_UpdateCache_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (PB cache update) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(!client)
	{
		return;
	}

	while(SQL_FetchRow(hndl))
	{
		gF_PlayerRecord[client][SQL_FetchInt(hndl, 1)] = SQL_FetchFloat(hndl, 0);
	}
}

public void UpdateWRCache()
{
	char sQuery[256];
	FormatEx(sQuery, 256, "SELECT u.name, p.time FROM playertimes p JOIN users u ON p.auth = u.auth WHERE map = '%s' AND style = '0' ORDER BY time ASC LIMIT 1;", gS_Map);
	SQL_TQuery(gH_SQL, SQL_UpdateWRCache_Forwards_Callback, sQuery, 0, DBPrio_High);

	// I FUCKING KNOW THERE'S A WAY TO DO THIS IN 1 QUERY BUT I SUCK AT SQL SO FORGIVE PLS ;-;
	FormatEx(sQuery, 256, "SELECT u.name, p.time FROM playertimes p JOIN users u ON p.auth = u.auth WHERE map = '%s' AND style = '1' ORDER BY time ASC LIMIT 1;", gS_Map);
	SQL_TQuery(gH_SQL, SQL_UpdateWRCache_Sideways_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_UpdateWRCache_Forwards_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (WR forwards cache update) SQL query failed. Reason: %s", error);

		return;
	}

	if(!SQL_FetchRow(hndl))
	{
		FormatEx(gS_WRName[0], MAX_NAME_LENGTH, "invalid");
		gF_WRTime[0] = 0.0;
	}

	else
	{
		SQL_FetchString(hndl, 0, gS_WRName[0], MAX_NAME_LENGTH);
		gF_WRTime[0] = SQL_FetchFloat(hndl, 1);
	}
}

public void SQL_UpdateWRCache_Sideways_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (WR sideways cache update) SQL query failed. Reason: %s", error);

		return;
	}

	if(!SQL_FetchRow(hndl))
	{
		FormatEx(gS_WRName[1], MAX_NAME_LENGTH, "invalid");
		gF_WRTime[1] = 0.0;
	}

	else
	{
		SQL_FetchString(hndl, 0, gS_WRName[1], MAX_NAME_LENGTH);
		gF_WRTime[1] = SQL_FetchFloat(hndl, 1);
	}
}

public int Native_GetWRTime(Handle handler, int numParams)
{
	BhopStyle style = GetNativeCell(1);
	SetNativeCellRef(2, gF_WRTime[style]);
}

public int Native_GetWRName(Handle handler, int numParams)
{
	BhopStyle style = GetNativeCell(1);
	int maxlength = GetNativeCell(3);

	SetNativeString(2, gS_WRName[style], maxlength);
}

public int Native_GetPlayerPB(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	BhopStyle style = GetNativeCell(2);

	SetNativeCellRef(3, gF_PlayerRecord[client][style]);
}

#if defined DEBUG
// debug
public Action Command_Junk(int client, int args)
{
	char sQuery[256];

	char sAuth[32];
	GetClientAuthId(client, AuthId_Steam3, sAuth, 32);
	FormatEx(sQuery, 256, "INSERT INTO playertimes (auth, map, time, jumps, date, style) VALUES ('%s', '%s', %.03f, %d, CURRENT_TIMESTAMP(), 0);", sAuth, gS_Map, GetRandomFloat(10.0, 20.0), GetRandomInt(5, 15));

	SQL_LockDatabase(gH_SQL);
	SQL_FastQuery(gH_SQL, sQuery);
	SQL_UnlockDatabase(gH_SQL);

	return Plugin_Handled;
}
#endif

public Action Command_Delete(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Handle menu = CreateMenu(MenuHandler_Delete);
	SetMenuTitle(menu, "Delete a record from:");

	AddMenuItem(menu, "forwards", "Forwards");
	AddMenuItem(menu, "sideways", "Sideways");

	SetMenuExitButton(menu, true);

	DisplayMenu(menu, client, 20);

	return Plugin_Handled;
}

public Action Command_DeleteAll(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Handle menu = CreateMenu(MenuHandler_DeleteAll);
	SetMenuTitle(menu, "Delete ALL the records for \"%s\"?", gS_Map);

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		AddMenuItem(menu, "-1", "NO!");
	}

	AddMenuItem(menu, "yes", "YES!!! DELETE ALL THE RECORDS!!! THIS ACTION CANNOT BE REVERTED!!!");
	
	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		AddMenuItem(menu, "-1", "NO!");
	}

	SetMenuExitButton(menu, true);

	DisplayMenu(menu, client, 20);

	return Plugin_Handled;
}

public int MenuHandler_DeleteAll(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		GetMenuItem(menu, param2, info, 16);

		if(StringToInt(info) == -1)
		{
			PrintToChat(param1, "%s Aborted deletion.", PREFIX);

			return;
		}
		
		char sQuery[256];
		FormatEx(sQuery, 256, "DELETE FROM playertimes WHERE map = '%s';", gS_Map);

		SQL_TQuery(gH_SQL, DeleteAll_Callback, sQuery, GetClientSerial(param1), DBPrio_High);
	}

	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public int MenuHandler_Delete(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		GetMenuItem(menu, param2, info, 16);

		if(StrEqual(info, "forwards"))
		{
			OpenDelete(param1, Style_Forwards);
		}

		else if(StrEqual(info, "sideways"))
		{
			OpenDelete(param1, Style_Sideways);
		}
	}

	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public void OpenDelete(int client, BhopStyle style)
{
	char sQuery[512];
	FormatEx(sQuery, 512, "SELECT p.id, u.name, p.time, p.jumps FROM playertimes p JOIN users u ON p.auth = u.auth WHERE map = '%s' AND style = '%d' ORDER BY time ASC LIMIT 1000;", gS_Map, style);

	Handle datapack = CreateDataPack();
	WritePackCell(datapack, GetClientSerial(client));
	WritePackCell(datapack, style);

	SQL_TQuery(gH_SQL, SQL_OpenDelete_Callback, sQuery, datapack, DBPrio_High);
}

public void SQL_OpenDelete_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	ResetPack(data);
	int client = GetClientFromSerial(ReadPackCell(data));
	BhopStyle style = ReadPackCell(data);
	CloseHandle(data);

	if(hndl == null)
	{
		LogError("Timer (WR OpenDelete) SQL query failed. Reason: %s", error);

		return;
	}

	if(!client)
	{
		return;
	}

	Handle menu = CreateMenu(OpenDelete_Handler);
	SetMenuTitle(menu, "Records for %s:\n(%s)", gS_Map, style == Style_Forwards? "Forwards":"Sideways");

	int iCount = 0;

	while(SQL_FetchRow(hndl))
	{
		iCount++;

		// 0 - record id, for statistic purposes.
		int id = SQL_FetchInt(hndl, 0);
		char sID[8];
		IntToString(id, sID, 8);

		// 1 - player name
		char sName[MAX_NAME_LENGTH];
		SQL_FetchString(hndl, 1, sName, MAX_NAME_LENGTH);

		// 2 - time
		float fTime = SQL_FetchFloat(hndl, 2);
		char sTime[16];
		FormatSeconds(fTime, sTime, 16);

		// 3 - jumps
		int iJumps = SQL_FetchInt(hndl, 3);

		char sDisplay[128];
		FormatEx(sDisplay, 128, "#%d - %s - %s (%d Jumps)", iCount, sName, sTime, iJumps);
		AddMenuItem(menu, sID, sDisplay);
	}

	if(!iCount)
	{
		AddMenuItem(menu, "-1", "No records found.");
	}

	SetMenuExitButton(menu, true);

	DisplayMenu(menu, client, 20);
}

public int OpenDelete_Handler(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		GetMenuItem(menu, param2, info, 16);
		
		if(StringToInt(info) == -1)
		{
			return;
		}

		Handle hMenu = CreateMenu(DeleteConfirm_Handler);
		SetMenuTitle(hMenu, "Are you sure?");

		for(int i = 1; i <= GetRandomInt(1, 4); i++)
		{
			AddMenuItem(hMenu, "-1", "NO!");
		}

		AddMenuItem(hMenu, info, "YES!!! DELETE THE RECORD!!!");
		
		for(int i = 1; i <= GetRandomInt(1, 3); i++)
		{
			AddMenuItem(hMenu, "-1", "NO!");
		}

		SetMenuExitButton(hMenu, true);

		DisplayMenu(hMenu, param1, 20);
	}

	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public int DeleteConfirm_Handler(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		GetMenuItem(menu, param2, info, 16);

		if(StringToInt(info) == -1)
		{
			PrintToChat(param1, "%s Aborted deletion.", PREFIX);

			return;
		}
		
		char sQuery[256];
		FormatEx(sQuery, 256, "DELETE FROM playertimes WHERE id = '%s';", info);

		SQL_TQuery(gH_SQL, DeleteConfirm_Callback, sQuery, GetClientSerial(param1), DBPrio_High);
	}

	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public void DeleteConfirm_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (WR DeleteConfirm) SQL query failed. Reason: %s", error);

		return;
	}
	
	UpdateWRCache();

	for(int i = 1; i <= MaxClients; i++)
	{
		OnClientPutInServer(i);
	}

	int client = GetClientFromSerial(data);

	if(!client)
	{
		return;
	}

	PrintToChat(client, "%s Deleted record.", PREFIX);
}

public void DeleteAll_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (WR DeleteAll) SQL query failed. Reason: %s", error);

		return;
	}
	
	UpdateWRCache();

	for(int i = 1; i <= MaxClients; i++)
	{
		OnClientPutInServer(i);
	}

	int client = GetClientFromSerial(data);

	if(!client)
	{
		return;
	}

	PrintToChat(client, "%s Deleted ALL records for \"%s\".", PREFIX, gS_Map);
}

public Action Command_WR(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sQuery[512];
	FormatEx(sQuery, 512, "SELECT p.id, u.name, p.time, p.jumps FROM playertimes p JOIN users u ON p.auth = u.auth WHERE map = '%s' AND style = '0' ORDER BY time ASC LIMIT 50;", gS_Map);

	SQL_TQuery(gH_SQL, SQL_WR_Callback, sQuery, GetClientSerial(client), DBPrio_High);

	gBS_LastWR[client] = Style_Forwards;

	return Plugin_Handled;
}

public Action Command_WRSW(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sQuery[512];
	FormatEx(sQuery, 512, "SELECT p.id, u.name, p.time, p.jumps FROM playertimes p JOIN users u ON p.auth = u.auth WHERE map = '%s' AND style = '1' ORDER BY time ASC LIMIT 100;", gS_Map);

	SQL_TQuery(gH_SQL, SQL_WR_Callback, sQuery, GetClientSerial(client), DBPrio_High);

	gBS_LastWR[client] = Style_Sideways;

	return Plugin_Handled;
}

public void SQL_WR_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (WR SELECT) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(!client)
	{
		return;
	}

	Handle menu = CreateMenu(WRMenu_Handler);
	SetMenuTitle(menu, "Records for %s:", gS_Map);

	int iCount = 0;

	while(SQL_FetchRow(hndl))
	{
		iCount++;

		// 0 - record id, for statistic purposes.
		int id = SQL_FetchInt(hndl, 0);
		char sID[8];
		IntToString(id, sID, 8);

		// 1 - player name
		char sName[MAX_NAME_LENGTH];
		SQL_FetchString(hndl, 1, sName, MAX_NAME_LENGTH);

		// 2 - time
		float fTime = SQL_FetchFloat(hndl, 2);
		char sTime[16];
		FormatSeconds(fTime, sTime, 16);

		// 3 - jumps
		int iJumps = SQL_FetchInt(hndl, 3);

		char sDisplay[128];
		FormatEx(sDisplay, 128, "#%d - %s - %s (%d Jumps)", iCount, sName, sTime, iJumps);
		AddMenuItem(menu, sID, sDisplay);
	}

	if(!iCount)
	{
		AddMenuItem(menu, "-1", "No records found.");
	}

	SetMenuExitButton(menu, true);

	DisplayMenu(menu, client, 20);
}

public int WRMenu_Handler(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		GetMenuItem(menu, param2, info, 16);
		int id = StringToInt(info);

		OpenSubMenu(param1, id);
	}

	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public void OpenSubMenu(int client, int id)
{
	char sQuery[512];
	FormatEx(sQuery, 512, "SELECT u.name, p.time, p.jumps, p.style, u.auth, p.date FROM playertimes p JOIN users u ON p.auth = u.auth WHERE p.id = '%d' LIMIT 1;", id);

	SQL_TQuery(gH_SQL, SQL_SubMenu_Callback, sQuery, GetClientSerial(client));
}

public void SQL_SubMenu_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (WR SUBMENU) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(!client)
	{
		return;
	}

	Handle menu = CreateMenu(SubMenu_Handler);

	char sName[MAX_NAME_LENGTH];
	char sAuthID[32];

	int iCount = 0;

	while(SQL_FetchRow(hndl))
	{
		iCount++;

		// 0 - name
		SQL_FetchString(hndl, 0, sName, MAX_NAME_LENGTH);

		// 1 - time
		float fTime = SQL_FetchFloat(hndl, 1);

		char sDisplay[128];
		FormatEx(sDisplay, 128, "Time: %.03f", fTime);
		AddMenuItem(menu, "-1", sDisplay);

		// 2 - jumps
		int iJumps = SQL_FetchInt(hndl, 2);
		FormatEx(sDisplay, 128, "Jumps: %d", iJumps);
		AddMenuItem(menu, "-1", sDisplay);

		// 3 - style
		int iStyle = SQL_FetchInt(hndl, 3);
		char sStyle[16];
		FormatEx(sStyle, 16, "%s", iStyle == view_as<int>Style_Forwards? "Forwards":"Sideways");
		FormatEx(sDisplay, 128, "Style: %s", sStyle);
		AddMenuItem(menu, "-1", sDisplay);

		// 4 - steamid3
		SQL_FetchString(hndl, 4, sAuthID, 32);

		// 5 - date
		char sDate[32];
		SQL_FetchString(hndl, 5, sDate, 32);
		FormatEx(sDisplay, 128, "Date: %s", sDate);
		AddMenuItem(menu, "-1", sDisplay);
	}

	SetMenuTitle(menu, "%s %s\n--- %s:", sName, sAuthID, gS_Map);

	SetMenuExitBackButton(menu, true);

	DisplayMenu(menu, client, 20);
}

public int SubMenu_Handler(Handle menu, MenuAction action, int param1, int param2)
{
	if((action == MenuAction_Cancel && (param2 == MenuCancel_ExitBack && param2 != MenuCancel_Exit)) || action == MenuAction_Select)
	{
		OpenWR(param1);
	}

	else if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
}

public void OpenWR(int client)
{
	if(!IsValidClient(client))
	{
		return;
	}

	if(gBS_LastWR[client] == Style_Forwards)
	{
		Command_WR(client, 0);
	}

	else
	{
		Command_WRSW(client, 0);
	}
}

public void SQL_DBConnect()
{
	if(SQL_CheckConfig("shavit"))
	{
		if(gH_SQL != null)
		{
			SQL_TQuery(gH_SQL, SQL_CreateTable_Callback, "CREATE TABLE IF NOT EXISTS `playertimes` (`id` INT NOT NULL AUTO_INCREMENT, `auth` VARCHAR(32), `map` VARCHAR(128), `time` FLOAT, `jumps` VARCHAR(32), `style` VARCHAR(32), `date` DATE, PRIMARY KEY (`id`));");
		}
	}

	else
	{
		SetFailState("Timer (WR module) startup failed. Reason: %s", "\"shavit\" is not a specified entry in databases.cfg.");
	}
}

public void SQL_CreateTable_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (WR module) error! Users' times table creation failed. Reason: %s", error);

		return;
	}
	
	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			OnClientPutInServer(i);
		}
		
		gB_Late = false;
	}
}

public any abs(any thing)
{
	if(thing < 0)
	{
		return thing * -1;
	}
	
	return thing;
}

public void Shavit_OnFinish(int client, int style, float time, int jumps)
{
	BhopStyle bsStyle = view_as<BhopStyle>style;
	
	char sTime[32];
	FormatSeconds(time, sTime, 32);

	// k people I made this forward so I'll use it to make cool text messages on WR (check timer-misc soon™)
	if(time < gF_WRTime[style] || gF_WRTime[style] == 0.0) // WR?
	{
		Call_StartForward(gH_OnWorldRecord);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_Finish();

		UpdateWRCache();
	}

	// 0 - no query
	// 1 - insert
	// 2 - update
	int overwrite;

	if(gF_PlayerRecord[client][style] == 0.0)
	{
		overwrite = 1;
	}

	else if(time < gF_PlayerRecord[client][style])
	{
		overwrite = 2;
	}
	
	float fDifference = (gF_PlayerRecord[client][style] - time) * -1.0;
	
	char sDifference[16];
	FormatSeconds(fDifference, sDifference, 16, true);
	
	if(overwrite > 0)
	{
		char sAuthID[32];
		GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

		char sQuery[256];

		if(overwrite == 1) // insert
		{
			PrintToChatAll("%s \x03%N\x01 finished (%s) on \x07%s\x01 with %d jumps.", PREFIX, client, bsStyle == Style_Forwards? "Forwards":"Sideways", sTime, jumps);
			
			FormatEx(sQuery, 256, "INSERT INTO playertimes (auth, map, time, jumps, date, style) VALUES ('%s', '%s', %.03f, %d, CURRENT_TIMESTAMP(), '%d');", sAuthID, gS_Map, time, jumps, style);
		}

		else // update
		{
			PrintToChatAll("%s \x03%N\x01 finished (%s) on \x07%s\x01 with %d jumps. \x0C(%s)", PREFIX, client, bsStyle == Style_Forwards? "Forwards":"Sideways", sTime, jumps, sDifference);
			
			FormatEx(sQuery, 256, "UPDATE playertimes SET time = '%.03f', jumps = '%d', date = CURRENT_TIMESTAMP() WHERE map = '%s' AND auth = '%s' AND style = '%d';", time, jumps, gS_Map, sAuthID, style);
		}

		SQL_TQuery(gH_SQL, SQL_OnFinish_Callback, sQuery, GetClientSerial(client));
	}

	else
	{
		if(!overwrite)
		{
			PrintToChat(client, "%s You have finished (%s) on \x07%s\x01 with %d jumps. \x08(+%s)", PREFIX, bsStyle == Style_Forwards? "Forwards":"Sideways", sTime, jumps, sDifference);
		}
		
		else
		{
			PrintToChat(client, "%s You have finished (%s) on \x07%s\x01 with %d jumps.", PREFIX, bsStyle == Style_Forwards? "Forwards":"Sideways", sTime, jumps);
		}
	}
}

public void SQL_OnFinish_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (WR OnFinish) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(!client)
	{
		return;
	}

	UpdateWRCache();
	UpdateClientCache(client);
}
