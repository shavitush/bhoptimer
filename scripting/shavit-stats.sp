/*
 * shavit's Timer - Player Stats
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

#define USES_STYLE_NAMES
#define USES_SHORT_STYLE_NAMES
#define USES_STYLE_PROPERTIES
#include <shavit>

#pragma semicolon 1
#pragma dynamic 131072 // let's make stuff faster
#pragma newdecls required // We're at 2015 :D

// macros
#define MAPSDONE 0
#define MAPSLEFT 1

// database handle
Database gH_SQL = null;

// table prefix
char gS_MySQLPrefix[32];

// cache
int gI_MapType[MAXPLAYERS+1];
int gI_Target[MAXPLAYERS+1];
BhopStyle gBS_Style[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "[shavit] Player Stats",
	author = "shavit",
	description = "Player stats for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "http://forums.alliedmods.net/member.php?u=163134"
}

public void OnAllPluginsLoaded()
{
	if(!LibraryExists("shavit-wr"))
	{
		SetFailState("shavit-wr is required for the plugin to work.");
	}

	// database related stuff
	Shavit_GetDB(gH_SQL);
	SetSQLInfo();
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_profile", Command_Profile, "Show the player's profile. Usage: sm_profile [target]");
	RegConsoleCmd("sm_stats", Command_Profile, "Show the player's profile. Usage: sm_profile [target]");

	LoadTranslations("common.phrases");
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

			return Plugin_Stop;
		}

		fTime = 1.0;
	}

	CreateTimer(fTime, CheckForSQLInfo);

	return Plugin_Continue;
}

public Action Command_Profile(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	int target = client;

	if(args > 0)
	{
		char[] sArgs = new char[64];
		GetCmdArgString(sArgs, 64);

		target = FindTarget(client, sArgs, true, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}

	gI_Target[client] = target;

	return ShowStyleMenu(client);
}

public Action ShowStyleMenu(int client)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsValidClient(gI_Target[client]))
	{
		Shavit_PrintToChat(client, "The target has disconnected.");

		return Plugin_Handled;
	}

	char[] sAuthID = new char[32];
	GetClientAuthId(gI_Target[client], AuthId_Steam3, sAuthID, 32);

	Menu m = new Menu(MenuHandler_Profile);
	m.SetTitle("%N's profile.\nSteamID3: %s", gI_Target[client], sAuthID);

	for(int i = 0; i < sizeof(gS_BhopStyles); i++)
	{
		if(gI_StyleProperties[i] & STYLE_UNRANKED)
		{
			continue;
		}
		
		char[] sInfo = new char[32];
		FormatEx(sInfo, 32, "mapsdone;%d", i);

		char[] sDisplay = new char[32];
		FormatEx(sDisplay, 32, "[%s] Maps done", gS_BhopStyles[i]);
		m.AddItem(sInfo, sDisplay);

		FormatEx(sInfo, 32, "mapsleft;%d", i);
		FormatEx(sDisplay, 32, "[%s] Maps left", gS_BhopStyles[i]);
		m.AddItem(sInfo, sDisplay);
	}

	// should NEVER happen
	if(m.ItemCount == 0)
	{
		m.AddItem("-1", "Nothing");
	}

	m.ExitButton = true;

	m.Display(client, 20);

	return Plugin_Handled;
}

public int MenuHandler_Profile(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!IsValidClient(gI_Target[param1]))
		{
			return 0;
		}

		char[] sInfo = new char[32];
		m.GetItem(param2, sInfo, 32);

		char[][] sSplit = new char[2][16];
		ExplodeString(sInfo, ";", sSplit, 2, 16);

		gI_MapType[param1] = StrEqual(sSplit[0], "mapsdone")? MAPSDONE:MAPSLEFT;
		gBS_Style[param1] = view_as<BhopStyle>(StringToInt(sSplit[1]));

		ShowMaps(param1);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public Action Timer_DBFailure(Handle timer, any data)
{
	int client = GetClientFromSerial(data);

	if(!client)
	{
		return Plugin_Stop;
	}

	ShowMaps(client);

	return Plugin_Stop;
}

public void ShowMaps(int client)
{
	if(!IsValidClient(gI_Target[client]))
	{
		return;
	}

	// database not found, display with a 3 seconds delay
	if(gH_SQL == null)
	{
		CreateTimer(3.0, Timer_DBFailure, GetClientSerial(client));

		return;
	}

	char[] sAuth = new char[32];
	GetClientAuthId(gI_Target[client], AuthId_Steam3, sAuth, 32);

	char[] sQuery = new char[256];

	if(gI_MapType[client] == MAPSDONE)
	{
		FormatEx(sQuery, 256, "SELECT map, time, jumps, id FROM %splayertimes WHERE auth = '%s' AND style = %d ORDER BY map;", gS_MySQLPrefix, sAuth, view_as<int>(gBS_Style[client]));
	}

	else
	{
		FormatEx(sQuery, 256, "SELECT DISTINCT m.map FROM %smapzones m LEFT JOIN %splayertimes r ON r.map = m.map AND r.auth = '%s' AND r.style = %d WHERE r.map IS NULL ORDER BY m.map;", gS_MySQLPrefix, gS_MySQLPrefix, sAuth, view_as<int>(gBS_Style[client]));
	}

	gH_SQL.Query(ShowMapsCallback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void ShowMapsCallback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (ShowMaps SELECT) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(!IsValidClient(client) || !IsValidClient(gI_Target[client]))
	{
		return;
	}

	int rows = SQL_GetRowCount(hndl);

	char[] sTitle = new char[64];

	if(gI_MapType[client] == MAPSDONE)
	{
		FormatEx(sTitle, 32, "[%s] Maps done for %N: (%d)", gS_ShortBhopStyles[gBS_Style[client]], gI_Target[client], rows);
	}

	else
	{
		FormatEx(sTitle, 32, "[%s] Maps left for %N: (%d)", gS_ShortBhopStyles[gBS_Style[client]], gI_Target[client], rows);
	}

	Menu m = new Menu(MenuHandler_ShowMaps);
	m.SetTitle(sTitle);

	while(SQL_FetchRow(hndl))
	{
		char[] sMap = new char[128];
		SQL_FetchString(hndl, 0, sMap, 128);

		char[] sRecordID = new char[16];

		char[] sDisplay = new char[192];

		if(gI_MapType[client] == MAPSDONE)
		{
			float time = SQL_FetchFloat(hndl, 1);
			int jumps = SQL_FetchInt(hndl, 2);

			char[] sTime = new char[32];
			FormatSeconds(time, sTime, 32);

			FormatEx(sDisplay, 192, "%s - %s (%d jumps)", sMap, sTime, jumps);

			int recordid = SQL_FetchInt(hndl, 3);
			IntToString(recordid, sRecordID, 16);
		}

		else
		{
			strcopy(sDisplay, 192, sMap);
			strcopy(sRecordID, 16, "nope");
		}

		m.AddItem(sRecordID, sDisplay);
	}

	if(m.ItemCount == 0)
	{
		m.AddItem("nope", "No results.");
	}

	m.ExitBackButton = true;

	m.Display(client, 60);
}

public int MenuHandler_ShowMaps(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[16];
		m.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "nope"))
		{
			ShowStyleMenu(param1);

			return 0;
		}

		char[] sQuery = new char[512];
		FormatEx(sQuery, 512, "SELECT u.name, p.time, p.jumps, p.style, u.auth, p.date, p.map FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE p.id = '%s' LIMIT 1;", gS_MySQLPrefix, gS_MySQLPrefix, sInfo);

		gH_SQL.Query(SQL_SubMenu_Callback, sQuery, GetClientSerial(param1));
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowStyleMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public void SQL_SubMenu_Callback(Handle owner, Handle hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		LogError("Timer (STATS SUBMENU) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(!client)
	{
		return;
	}

	Menu m = new Menu(SubMenu_Handler);

	char[] sName = new char[MAX_NAME_LENGTH];
	char[] sAuthID = new char[32];
	char[] sMap = new char[256];

	if(SQL_FetchRow(hndl))
	{
		// 0 - name
		SQL_FetchString(hndl, 0, sName, MAX_NAME_LENGTH);

		// 1 - time
		float fTime = SQL_FetchFloat(hndl, 1);
		char[] sTime = new char[16];
		FormatSeconds(fTime, sTime, 16);

		char[] sDisplay = new char[128];
		FormatEx(sDisplay, 128, "Time: %s", sTime);
		m.AddItem("-1", sDisplay);

		// 2 - jumps
		int iJumps = SQL_FetchInt(hndl, 2);
		FormatEx(sDisplay, 128, "Jumps: %d", iJumps);
		m.AddItem("-1", sDisplay);

		// 3 - style
		int iStyle = SQL_FetchInt(hndl, 3);
		FormatEx(sDisplay, 128, "Style: %s", gS_BhopStyles[iStyle]);
		m.AddItem("-1", sDisplay);

		// 4 - steamid3
		SQL_FetchString(hndl, 4, sAuthID, 32);

		// 5 - date
		char[] sDate = new char[32];
		SQL_FetchString(hndl, 5, sDate, 32);
		FormatEx(sDisplay, 128, "Date: %s", sDate);
		m.AddItem("-1", sDisplay);

		// 6 - map
		SQL_FetchString(hndl, 6, sMap, 256);
	}

	char[] sFormattedTitle = new char[256];
	FormatEx(sFormattedTitle, 256, "%s %s\n--- %s:", sName, sAuthID, sMap);

	m.SetTitle(sFormattedTitle);

	m.ExitBackButton = true;

	m.Display(client, 20);
}

public int SubMenu_Handler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowMaps(param1);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}
