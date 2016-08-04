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
#include <cstrike>
#include <geoip>

#undef REQUIRE_PLUGIN
#define USES_STYLE_NAMES
#define USES_SHORT_STYLE_NAMES
#define USES_STYLE_PROPERTIES
#include <shavit>

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

// macros
#define MAPSDONE 0
#define MAPSLEFT 1

// modules
bool gB_Rankings = false;

// database handle
Database gH_SQL = null;

// table prefix
char gS_MySQLPrefix[32];

// cache
int gI_MapType[MAXPLAYERS+1];
int gI_Target[MAXPLAYERS+1];
BhopStyle gBS_Style[MAXPLAYERS+1];
int gI_WRAmount[MAXPLAYERS+1];
int gI_ClearCount[MAXPLAYERS+1];
int gI_TotalMaps = 0;

// cvars
ConVar gCV_MVPRankOnes = null;

public Plugin myinfo =
{
	name = "[shavit] Player Stats",
	author = "shavit",
	description = "Player stats for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public void OnAllPluginsLoaded()
{
	if(!LibraryExists("shavit-wr"))
	{
		SetFailState("shavit-wr is required for the plugin to work.");
	}

	gB_Rankings = LibraryExists("shavit-rankings");
}

public void OnPluginStart()
{
	// player commands
	RegConsoleCmd("sm_profile", Command_Profile, "Show the player's profile. Usage: sm_profile [target]");
	RegConsoleCmd("sm_stats", Command_Profile, "Show the player's profile. Usage: sm_profile [target]");

	// translations
	LoadTranslations("common.phrases");

	// hooks
	HookEvent("player_spawn", Player_Event);
	HookEvent("player_team", Player_Event);

	// cvars
	gCV_MVPRankOnes = CreateConVar("shavit_stats_mvprankones", "2", "Set the players' amount of MVPs to the amount of #1 times they have.\n0 - Disabled\n1 - Enabled, for all styles.\n2 - Enabled, for default style only.", 0, true, 0.0, true, 2.0);

	AutoExecConfig();

	// database connections
	Shavit_GetDB(gH_SQL);
	SQL_SetPrefix();
	SetSQLInfo();
}

public void OnMapStart()
{
	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "SELECT COUNT(*) FROM (SELECT id FROM %smapzones GROUP BY map) s;", gS_MySQLPrefix);

	gH_SQL.Query(SQL_GetTotalMaps_Callback, sQuery);
}

public void SQL_GetTotalMaps_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (get total maps) SQL query failed. You might be missing shavit-zones. Reason: %s", error);

		return;
	}

	if(results.FetchRow())
	{
		gI_TotalMaps = results.FetchInt(0);
	}
}

public void OnClientPutInServer(int client)
{
	gI_WRAmount[client] = 0;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}
}

public Action CheckForSQLInfo(Handle Timer)
{
	return SetSQLInfo();
}

public Action SetSQLInfo()
{
	if(gH_SQL == null)
	{
		Shavit_GetDB(gH_SQL);

		CreateTimer(0.5, CheckForSQLInfo);
	}

	else
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public void SQL_SetPrefix()
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
		char[] sLine = new char[PLATFORM_MAX_PATH*2];

		while(fFile.ReadLine(sLine, PLATFORM_MAX_PATH*2))
		{
			TrimString(sLine);
			strcopy(gS_MySQLPrefix, 32, sLine);

			break;
		}
	}

	delete fFile;
}

public void Player_Event(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	if(IsValidClient(client))
	{
		UpdateWRs(client);
	}
}

public void Shavit_OnFinish_Post(int client)
{
	UpdateWRs(client);
}

public void Shavit_OnWorldRecord(int client)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i, true))
		{
			UpdateWRs(i);
		}
	}
}

public void UpdateWRs(int client)
{
	if(gH_SQL == null)
	{
		return;
	}

	char[] sAuthID = new char[32];

	if(GetClientAuthId(client, AuthId_Steam3, sAuthID, 32))
	{
		char[] sQuery = new char[256];

		if(gCV_MVPRankOnes.IntValue == 2)
		{
			FormatEx(sQuery, 256, "SELECT COUNT(*) FROM (SELECT s.auth FROM (SELECT style, auth, MIN(time) FROM %splayertimes GROUP BY map, style) s WHERE style = 0) ss WHERE ss.auth = '%s' LIMIT 1;", gS_MySQLPrefix, sAuthID);

		}

		else
		{
			FormatEx(sQuery, 256, "SELECT COUNT(*) FROM (SELECT s.auth FROM (SELECT auth, MIN(time) FROM %splayertimes GROUP BY map, style) s) ss WHERE ss.auth = '%s' LIMIT 1;", gS_MySQLPrefix, sAuthID);
		}

		gH_SQL.Query(SQL_GetWRs_Callback, sQuery, GetClientSerial(client));

		FormatEx(sQuery, 256, "SELECT COUNT(*) FROM (SELECT id FROM %splayertimes WHERE auth = '%s' GROUP BY map) s LIMIT 1;", gS_MySQLPrefix, sAuthID);
		gH_SQL.Query(SQL_GetClears_Callback, sQuery, GetClientSerial(client));
	}
}

public void SQL_GetWRs_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (get WR amount) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0 || !results.FetchRow())
	{
		return;
	}

	int iWRs = results.FetchInt(0);

	if(gCV_MVPRankOnes.BoolValue)
	{
		CS_SetMVPCount(client, iWRs);
	}

	gI_WRAmount[client] = iWRs;
}

public void SQL_GetClears_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (get clear amount) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		gI_ClearCount[client] = results.FetchInt(0);
	}
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

	char[] sRankingString = new char[128];

	if(gB_Rankings)
	{
		FormatEx(sRankingString, 128, "\nRank: %d/%d\nPoints: %d", Shavit_GetRank(gI_Target[client]), Shavit_GetRankedPlayers(), RoundToFloor(Shavit_GetPoints(gI_Target[client])));
	}

	char[] sCountry = new char[64];
	GetClientIP(gI_Target[client], sCountry, 64);

	if(!GeoipCountry(sCountry, sCountry, 64))
	{
		strcopy(sCountry, 64, "Local Area Network");
	}

	char[] sClearString = new char[128];
	FormatEx(sClearString, 128, "Map completions: %d/%d", gI_ClearCount[gI_Target[client]], gI_TotalMaps);

	Menu m = new Menu(MenuHandler_ProfileHandler);
	m.SetTitle("%N's profile.\nCountry: %s\n%s\n%s #1 records: %d%s\nSteamID3: %s", gI_Target[client], sCountry, sClearString, (gCV_MVPRankOnes.IntValue == 2)? gS_BhopStyles[0]:"Total", gI_WRAmount[gI_Target[client]], sRankingString, sAuthID);

	for(int i = 0; i < sizeof(gS_BhopStyles); i++)
	{
		if(!(gI_StyleProperties[i] & STYLE_UNRANKED))
		{
			char[] sInfo = new char[4];
			IntToString(i, sInfo, 4);

			m.AddItem(sInfo, gS_BhopStyles[i]);
		}
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

public int MenuHandler_ProfileHandler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!IsValidClient(gI_Target[param1]))
		{
			return 0;
		}

		char[] sInfo = new char[32];
		m.GetItem(param2, sInfo, 32);

		gBS_Style[param1] = view_as<BhopStyle>(StringToInt(sInfo));

		Menu menu = new Menu(MenuHandler_TypeHandler);
		menu.SetTitle("[%s] Stats:", gS_ShortBhopStyles[gBS_Style[param1]]);

		menu.AddItem("0", "Maps done");
		menu.AddItem("1", "Maps left");

		menu.ExitBackButton = true;
		menu.Display(param1, 20);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public int MenuHandler_TypeHandler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!IsValidClient(gI_Target[param1]))
		{
			return 0;
		}

		char[] sInfo = new char[32];
		m.GetItem(param2, sInfo, 32);
		gI_MapType[param1] = StringToInt(sInfo);

		ShowMaps(param1);
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

	char[] sQuery = new char[512];

	if(gI_MapType[client] == MAPSDONE)
	{
		FormatEx(sQuery, 512, "SELECT a.map, a.time, a.jumps, a.id, COUNT(b.map) + 1 rank FROM %splayertimes a LEFT JOIN %splayertimes b ON a.time > b.time AND a.map = b.map AND a.style = b.style WHERE a.auth = '%s' AND a.style = %d GROUP BY a.map ORDER BY a.map;", gS_MySQLPrefix, gS_MySQLPrefix, sAuth, view_as<int>(gBS_Style[client]));
	}

	else
	{
		FormatEx(sQuery, 512, "SELECT DISTINCT m.map FROM %smapzones m LEFT JOIN %splayertimes r ON r.map = m.map AND r.auth = '%s' AND r.style = %d WHERE r.map IS NULL ORDER BY m.map;", gS_MySQLPrefix, gS_MySQLPrefix, sAuth, view_as<int>(gBS_Style[client]));
	}

	gH_SQL.Query(ShowMapsCallback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void ShowMapsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (ShowMaps SELECT) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(!IsValidClient(client) || !IsValidClient(gI_Target[client]))
	{
		return;
	}

	int rows = results.RowCount;

	char[] sTitle = new char[64];

	if(gI_MapType[client] == MAPSDONE)
	{
		FormatEx(sTitle, 64, "[%s] Maps done for %N: (%d)", gS_ShortBhopStyles[gBS_Style[client]], gI_Target[client], rows);
	}

	else
	{
		FormatEx(sTitle, 64, "[%s] Maps left for %N: (%d)", gS_ShortBhopStyles[gBS_Style[client]], gI_Target[client], rows);
	}

	Menu m = new Menu(MenuHandler_ShowMaps);
	m.SetTitle(sTitle);

	while(results.FetchRow())
	{
		char[] sMap = new char[192];
		results.FetchString(0, sMap, 192);
		GetMapDisplayName(sMap, sMap, 192);

		char[] sRecordID = new char[16];
		char[] sDisplay = new char[256];

		if(gI_MapType[client] == MAPSDONE)
		{
			float fTime = results.FetchFloat(1);
			int iJumps = results.FetchInt(2);
			int iRank = results.FetchInt(4);

			char[] sTime = new char[32];
			FormatSeconds(fTime, sTime, 32);

			bool bPoints = false;

			if(gB_Rankings)
			{
				float fPoints = 0.0;
				float fIdealTime = -1.0;
				Shavit_GetGivenMapValues(sMap, fPoints, fIdealTime);

				if(fPoints != -1.0 && fIdealTime != 0.0)
				{
					FormatEx(sDisplay, 192, "[#%d] %s - %s (%.03f points)", iRank, sMap, sTime, Shavit_CalculatePoints(fTime, gBS_Style[client], fIdealTime, fPoints));
					bPoints = true;
				}
			}

			if(!bPoints)
			{
				FormatEx(sDisplay, 192, "[#%d] %s - %s (%d jumps)", iRank, sMap, sTime, iJumps);
			}

			int iRecordID = results.FetchInt(3);
			IntToString(iRecordID, sRecordID, 16);
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
		FormatEx(sQuery, 512, "SELECT u.name, p.time, p.jumps, p.style, u.auth, p.date, p.map, p.strafes, p.sync FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE p.id = '%s' LIMIT 1;", gS_MySQLPrefix, gS_MySQLPrefix, sInfo);

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

public void SQL_SubMenu_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
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

	if(results.FetchRow())
	{
		// 0 - name
		results.FetchString(0, sName, MAX_NAME_LENGTH);

		// 1 - time
		float fTime = results.FetchFloat(1);
		char[] sTime = new char[16];
		FormatSeconds(fTime, sTime, 16);

		char[] sDisplay = new char[128];
		FormatEx(sDisplay, 128, "Time: %s", sTime);
		m.AddItem("-1", sDisplay);

		// 2 - jumps
		int iJumps = results.FetchInt(2);
		FormatEx(sDisplay, 128, "Jumps: %d", iJumps);
		m.AddItem("-1", sDisplay);

		// 3 - style
		BhopStyle bsStyle = view_as<BhopStyle>(results.FetchInt(3));
		FormatEx(sDisplay, 128, "Style: %s", gS_BhopStyles[bsStyle]);
		m.AddItem("-1", sDisplay);

		// 4 - steamid3
		results.FetchString(4, sAuthID, 32);

		// 6 - map
		results.FetchString(6, sMap, 256);

		if(gB_Rankings)
		{
			float fPoints = 0.0;
			float fIdealTime = -1.0;
			Shavit_GetGivenMapValues(sMap, fPoints, fIdealTime);

			if(fPoints != -1.0 && fIdealTime != 0.0)
			{
				FormatEx(sDisplay, 192, "Points: %.03f", Shavit_CalculatePoints(fTime, bsStyle, fIdealTime, fPoints));
				m.AddItem("-1", sDisplay);
			}
		}

		// 5 - date
		char[] sDate = new char[32];
		results.FetchString(5, sDate, 32);

		if(sDate[4] != '-')
		{
			FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", StringToInt(sDate));
		}

		FormatEx(sDisplay, 128, "Date: %s", sDate);
		m.AddItem("-1", sDisplay);

		int iStrafes = results.FetchInt(7);
		float fSync = results.FetchFloat(8);

		if(iJumps > 0 || iStrafes > 0)
		{
			FormatEx(sDisplay, 128, (fSync != -1.0)? "Strafes: %d (%.02f%%)":"Strafes: %d", iStrafes, fSync);
			m.AddItem("-1", sDisplay);
		}

		GetMapDisplayName(sMap, sMap, 256);
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
