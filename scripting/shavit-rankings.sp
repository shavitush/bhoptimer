/*
 * shavit's Timer - Rankings
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

#undef REQUIRE_PLUGIN
#define USES_STYLE_MULTIPLIERS
#include <shavit>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

// #define DEBUG

// forwards
Handle gH_Forwards_OnRankUpdated = null;

// cache
char gS_Map[256];
float gF_IdealTime = 0.0;
float gF_MapPoints = -1.0;
int gI_NeededRecordsAmount = 0;
int gI_CachedRecordsAmount = 0;
int gI_RankedPlayers = 0;

char gS_CachedMap[MAXPLAYERS+1][192];
int gI_MapTier = -1;

float gF_PlayerPoints[MAXPLAYERS+1];
int gI_PlayerRank[MAXPLAYERS+1];
bool gB_PointsToChat[MAXPLAYERS+1];

StringMap gSM_Points = null;
StringMap gSM_Time = null;

// convars
ConVar gCV_TopAmount = null;

// database handles
Database gH_SQL = null;
Database gH_Tiers = null;
bool gB_MySQL = false;

// table prefix
char gS_MySQLPrefix[32];

public Plugin myinfo =
{
	name = "[shavit] Rankings",
	author = "shavit",
	description = "Ranking system for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetPoints", Native_GetPoints);
	CreateNative("Shavit_GetRank", Native_GetRank);
	CreateNative("Shavit_GetMapValues", Native_GetMapValues);
	CreateNative("Shavit_GetGivenMapValues", Native_GetGivenMapValues);
	CreateNative("Shavit_GetRankedPlayers", Native_GetRankedPlayers);
	CreateNative("Shavit_CalculatePoints", Native_CalculatePoints);

	RegPluginLibrary("shavit-rankings");

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
    if(!LibraryExists("shavit-wr"))
    {
        SetFailState("shavit-wr is required for the plugin to work.");
    }
}

public void OnPluginStart()
{
	// cache
	gSM_Points = new StringMap();
	gSM_Time = new StringMap();

	// forwards
	gH_Forwards_OnRankUpdated = CreateGlobalForward("Shavit_OnRankUpdated", ET_Event, Param_Cell);

	// database connections
	Shavit_GetDB(gH_SQL);
	SQL_SetPrefix();
	SetSQLInfo();

	// player commands
	RegConsoleCmd("sm_points", Command_Points, "Prints the points and ideal time for the map.");
	RegConsoleCmd("sm_rank", Command_Rank, "Shows your current rank.");
	RegConsoleCmd("sm_prank", Command_Rank, "Shows your current rank. (sm_rank alias)");
	RegConsoleCmd("sm_top", Command_Top, "Shows the top players menu.");
	RegConsoleCmd("sm_ptop", Command_Top, "Shows the top players menu. (sm_top alias)");
	RegConsoleCmd("sm_tier", Command_Tier, "Prints the map's tier to chat.");
	RegConsoleCmd("sm_maptier", Command_Tier, "Prints the map's tier to chat. (sm_tier alias)");

	// admin commands
	RegAdminCmd("sm_setpoints", Command_SetPoints, ADMFLAG_ROOT, "Set points for a defined ideal time. sm_setpoints <time in seconds> <points>");
	RegAdminCmd("sm_setmappoints", Command_SetPoints, ADMFLAG_ROOT, "Set points for a defined ideal time. sm_setpoints <time in seconds> <points> (sm_setpoints alias)");
	RegAdminCmd("sm_settier", Command_SetTier, ADMFLAG_ROOT, "Set map tier. Has no effect except for sm_tier output or message upon connection.");
	RegAdminCmd("sm_setmaptier", Command_SetTier, ADMFLAG_ROOT, "Set map tier. Has no effect except for sm_tier output or message upon connection. (sm_settier alias)");

	// translations
	LoadTranslations("common.phrases");

	#if defined DEBUG
	// debug
	RegServerCmd("sm_calc", Command_Calc);
	#endif

	// cvars
	gCV_TopAmount = CreateConVar("shavit_rankings_topamount", "100", "Amount of people to show within the sm_top menu.", 0, true, 1.0, false);

	AutoExecConfig();
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client))
	{
	return;
		}

	gF_PlayerPoints[client] = -1.0;
	gI_PlayerRank[client] = -1;
	gB_PointsToChat[client] = false;

	char[] sAuthID3 = new char[32];

	if(GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
	{
		char[] sQuery = new char[128];
		FormatEx(sQuery, 128, "SELECT points FROM %suserpoints WHERE auth = '%s' LIMIT 1;", gS_MySQLPrefix, sAuthID3);

		gH_SQL.Query(SQL_GetUserPoints_Callback, sQuery, GetClientSerial(client), DBPrio_Low);
	}

	CreateTimer(5.0, Timer_PrintTier, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
}

public void SQL_GetUserPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error on GetUserPoints. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		gF_PlayerPoints[client] = results.FetchFloat(0);

		UpdatePlayerPoints(client, false);
	}

	else
	{
		char[] sAuthID3 = new char[32];

		if(GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
		{
			char[] sQuery = new char[128];
			FormatEx(sQuery, 128, "REPLACE INTO %suserpoints (auth, points) VALUES ('%s', 0.0);", gS_MySQLPrefix, sAuthID3);

			gH_SQL.Query(SQL_InsertUser_Callback, sQuery, 0, DBPrio_Low);
		}
	}

	UpdateRankedPlayers();
}

public void SQL_InsertUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results == null)
    {
        LogError("Timer error on InsertUser. Reason: %s", error);

        return;
    }
}

public Action Timer_PrintTier(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0 || gI_MapTier == -1)
	{
		return Plugin_Stop;
	}

	char[] sDisplayMap = new char[strlen(gS_Map) + 1];
	GetMapDisplayName(gS_Map, sDisplayMap, strlen(gS_Map) + 1);

	Shavit_PrintToChat(client, "\x04%s\x01 is rated \x05tier %d\x01.", sDisplayMap, gI_MapTier);

	return Plugin_Stop;
}

#if defined DEBUG
public Action Command_Calc(int args)
{
    if(args != 4)
    {
        PrintToServer("no");

        return Plugin_Handled;
    }

    char[] sArg1 = new char[32];
    GetCmdArg(1, sArg1, 32);
    float fTime = StringToFloat(sArg1);

    char[] sArg2 = new char[32];
    GetCmdArg(2, sArg2, 32);
    BhopStyle style = view_as<BhopStyle>(StringToInt(sArg2));

    char[] sArg3 = new char[32];
    GetCmdArg(3, sArg3, 32);
    float fIdealTime = StringToFloat(sArg3);

    char[] sArg4 = new char[32];
    GetCmdArg(4, sArg4, 32);
    float fMapPoints = StringToFloat(sArg4);

    PrintToServer("%.02f", CalculatePoints(fTime, style, fIdealTime, fMapPoints));

    return Plugin_Handled;
}
#endif

public void OnMapStart()
{
	gI_NeededRecordsAmount = 0;
	gI_CachedRecordsAmount = 0;

	gF_IdealTime = 0.0;
	gF_MapPoints = -1.0;

	GetCurrentMap(gS_Map, 256);
	UpdatePointsCache(gS_Map);

	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "SELECT tier FROM %smaptiers WHERE map = '%s';", gS_MySQLPrefix, gS_Map);

	gH_Tiers.Query(SQL_SetTierCache_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_SetTierCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! Set tier cache failed. Reason: %s", error);

		return;
	}

	if(results.FetchRow())
	{
		gI_MapTier = results.FetchInt(0);
	}
}

public Action Command_Points(int client, int args)
{
    if(!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    if(gF_MapPoints == -1.0)
    {
        Shavit_PrintToChat(client, "Points are not defined for this map.");

        return Plugin_Handled;
    }

    char[] sDisplayMap = new char[strlen(gS_Map) + 1];
    GetMapDisplayName(gS_Map, sDisplayMap, strlen(gS_Map) + 1);

    char[] sTime = new char[32];
    FormatSeconds(gF_IdealTime, sTime, 32, false);

    Shavit_PrintToChat(client, "\x04%s\x01: \x03%.01f\x01 points for \x05%s\x01.", sDisplayMap, gF_MapPoints, sTime);

    return Plugin_Handled;
}

public Action Command_Rank(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	int target = client;

	if(args > 0)
	{
		char[] sTarget = new char[MAX_TARGET_LENGTH];
		GetCmdArgString(sTarget, MAX_TARGET_LENGTH);

		target = FindTarget(client, sTarget, true, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}

	if(gI_PlayerRank[target] <= 0 || gF_PlayerPoints[target] <= 0.0)
	{
		Shavit_PrintToChat(client, "\x03%N\x01 is unranked.", target);

		return Plugin_Handled;
	}

	Shavit_PrintToChat(client, "\x03%N\x01 is ranked \x03%d\x01 out of \x03%d\x01 with \x05%.02f points\x01.", target, gI_PlayerRank[target], gI_RankedPlayers, gF_PlayerPoints[target]);

	return Plugin_Handled;
}

public Action Command_Top(int client, int args)
{
    if(!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    return ShowTopMenu(client);
}

public Action ShowTopMenu(int client)
{
    char[] sQuery = new char[192];
    FormatEx(sQuery, 192, "SELECT u.name, %s points FROM %susers u JOIN %suserpoints up ON up.auth = u.auth WHERE up.points > 0.0 ORDER BY up.points DESC LIMIT %d;", gB_MySQL? "FORMAT(up.points, 2)":"up.points", gS_MySQLPrefix, gS_MySQLPrefix, gCV_TopAmount.IntValue);

    gH_SQL.Query(SQL_ShowTopMenu_Callback, sQuery, GetClientSerial(client));

    return Plugin_Handled;
}

public void SQL_ShowTopMenu_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error on ShowTopMenu. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	Menu m = new Menu(MenuHandler_TopMenu);
	m.SetTitle("Top %d Players", gCV_TopAmount.IntValue);

	if(results.RowCount == 0)
	{
		m.AddItem("-1", "No results.");
	}

	else
	{
		int count = 0;

		while(results.FetchRow())
		{
			char[] sName = new char[MAX_NAME_LENGTH];
			results.FetchString(0, sName, MAX_NAME_LENGTH);

			int iRank = ++count;
			char[] sRank = new char[6];
			IntToString(iRank, sRank, 6); // info string for future purposes

			char[] sDisplay = new char[64];

			if(gB_MySQL)
			{
				char[] sPoints = new char[16];
				results.FetchString(1, sPoints, 16);

				FormatEx(sDisplay, 64, "#%d - %s (%s points)", iRank, sName, sPoints);
			}

			else
			{
				FormatEx(sDisplay, 64, "#%d - %s (%.02f points)", iRank, sName, results.FetchFloat(1));
			}

			m.AddItem(sRank, sDisplay);
		}
	}

	m.ExitButton = true;

	m.Display(client, 20);
}

public int MenuHandler_TopMenu(Menu m, MenuAction action, int param1, int param2)
{
    // *eventually* add some shavit-stats call here, to show the player's profile
    if(action == MenuAction_End)
    {
        delete m;
    }

    return 0;
}

public Action Command_Tier(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(args == 0)
	{
		char[] sDisplayMap = new char[strlen(gS_Map) + 1];
		GetMapDisplayName(gS_Map, sDisplayMap, strlen(gS_Map) + 1);

		if(gI_MapTier != -1)
		{
			Shavit_PrintToChat(client, "\x04%s\x01 is rated \x05tier %d\x01.", sDisplayMap, gI_MapTier);
		}

		else
		{
			Shavit_PrintToChat(client, "\x04%s\x01 is not rated.", sDisplayMap);
		}
	}

	else
	{
		GetCmdArg(1, gS_CachedMap[client], 192);

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "SELECT map, tier FROM %smaptiers WHERE map LIKE '%%%s%%';", gS_MySQLPrefix, gS_CachedMap[client]);

		gH_Tiers.Query(SQL_GetTier_Callback, sQuery, GetClientSerial(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public void SQL_GetTier_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! Get map tier failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		char[] sMap = new char[192];
		results.FetchString(0, sMap, 192);

		char[] sDisplayMap = new char[strlen(sMap) + 1];
		GetMapDisplayName(sMap, sDisplayMap, strlen(sMap) + 1);

		Shavit_PrintToChat(client, "\x04%s\x01 is rated \x05tier %d\x01.", sDisplayMap, gI_MapTier);
	}

	else
	{
		Shavit_PrintToChat(client, "Couldn't find map tier for \x04%s\x01.", gS_CachedMap[client]);
	}
}

public Action Command_SetTier(int client, int args)
{
	if(args != 1)
	{
		char[] sArg0 = new char[32];
		GetCmdArg(0, sArg0, 32);

		ReplyToCommand(client, "Usage: %s <tier>", sArg0);

		return Plugin_Handled;
	}

	char[] sArg1 = new char[8];
	GetCmdArg(1, sArg1, 8);

	int iTier = StringToInt(sArg1);

	if(iTier < 0)
	{
		ReplyToCommand(client, "Invalid map tier (%d)!", iTier);

		return Plugin_Handled;
	}

	gI_MapTier = iTier;

	ReplyToCommand(client, "Map tier is now %d.", iTier);

	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "REPLACE INTO %smaptiers (map, tier) VALUES ('%s', %d);", gS_MySQLPrefix, gS_Map, iTier);

	gH_Tiers.Query(SQL_SetTier_Callback, sQuery, GetClientSerial(client), DBPrio_High);

	return Plugin_Handled;
}

public void SQL_SetTier_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! Set map tier failed. Reason: %s", error);

		return;
	}
}

public Action Command_SetPoints(int client, int args)
{
    if(args != 2)
    {
        char[] sArg0 = new char[32];
        GetCmdArg(0, sArg0, 32);

        ReplyToCommand(client, "Usage: %s <time in seconds> <points>", sArg0);

        return Plugin_Handled;
    }

    char[] sArg1 = new char[32];
    GetCmdArg(1, sArg1, 32);
    float fTime = gF_IdealTime = StringToFloat(sArg1);
    FormatSeconds(fTime, sArg1, 32, false);

    char[] sArg2 = new char[32];
    GetCmdArg(2, sArg2, 32);
    float fPoints = gF_MapPoints = StringToFloat(sArg2);

    if(fTime < 0.0 || fPoints < 0.0)
    {
        ReplyToCommand(client, "Invalid arguments: {%.01f} {%.01f}", fTime, fPoints);

        return Plugin_Handled;
    }

    ReplyToCommand(client, "Set \x03%.01f\x01 points for \x05%s\x01.", fPoints, sArg1);

    SetMapPoints(fTime, fPoints);

    return Plugin_Handled;
}

public void SetMapPoints(float time, float points)
{
    char[] sQuery = new char[256];
    FormatEx(sQuery, 256, "REPLACE INTO %smappoints (map, time, points) VALUES ('%s', '%.01f', '%.01f');", gS_MySQLPrefix, gS_Map, time, points);

    gH_SQL.Query(SQL_SetPoints_Callback, sQuery, 0, DBPrio_Low);
}

public void SQL_SetPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results == null)
    {
        LogError("Timer (rankings module) error! Failed to insert map data to the table. Reason: %s", error);

        return;
    }

    char[] sQuery = new char[512];
    FormatEx(sQuery, 512, "SELECT pt.id, pt.time, pt.style, mp.time, mp.points FROM %splayertimes pt JOIN %smappoints mp ON pt.map = mp.map WHERE pt.map = '%s';", gS_MySQLPrefix, gS_MySQLPrefix, gS_Map);

    gH_SQL.Query(SQL_RetroactivePoints_Callback, sQuery, 0, DBPrio_Low);
}

public void SQL_RetroactivePoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results == null)
    {
        LogError("Timer (rankings module) error! RetroactivePoints failed. Reason: %s", error);

        return;
    }

    gI_NeededRecordsAmount = results.RowCount;

    while(results.FetchRow())
    {
        float fTime = results.FetchFloat(1);
        BhopStyle style = view_as<BhopStyle>(results.FetchInt(2));
        float fIdealTime = results.FetchFloat(3);
        float fMapPoints = results.FetchFloat(4);

        float fPoints = CalculatePoints(fTime, style, fIdealTime, fMapPoints);

        char[] sQuery = new char[256];
        FormatEx(sQuery, 256, "REPLACE INTO %splayerpoints (recordid, points) VALUES ('%d', '%f');", gS_MySQLPrefix, results.FetchInt(0), fPoints);

        gH_SQL.Query(SQL_RetroactivePoints_Callback2, sQuery, 0, DBPrio_Low);

        gI_CachedRecordsAmount++;
    }
}

public void SQL_RetroactivePoints_Callback2(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! RetroactivePoints2 failed. Reason: %s", error);

		return;
	}

	if(gI_CachedRecordsAmount == gI_NeededRecordsAmount)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
			}
		}

		gI_NeededRecordsAmount = 0;
		gI_CachedRecordsAmount = 0;
	}

	UpdateRankedPlayers();
}

public void UpdateStringMap()
{
	char[] sQuery = new char[64];
	FormatEx(sQuery, 64, "SELECT * FROM %smappoints;", gS_MySQLPrefix);

	gH_SQL.Query(SQL_UpdateStringMap_Callback, sQuery, 0, DBPrio_Low);
}

public void SQL_UpdateStringMap_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! Couldn't update stringmap. Reason: %s", error);

		return;
	}

	gSM_Time.Clear();
	gSM_Points.Clear();

	while(results.FetchRow())
	{
		char[] sMap = new char[192];
		results.FetchString(0, sMap, 192);

		float fTime = results.FetchFloat(1);
		gSM_Time.SetValue(sMap, fTime);

		float fPoints = results.FetchFloat(2);
		gSM_Points.SetValue(sMap, fPoints);
	}
}

public void UpdatePointsCache(const char[] map)
{
    char[] sQuery = new char[192];
    FormatEx(sQuery, 192, "SELECT time, points FROM %smappoints WHERE map = '%s' LIMIT 1;", gS_MySQLPrefix, map);

    gH_SQL.Query(SQL_UpdateCache_Callback, sQuery, 0, DBPrio_Low);
}

public void SQL_UpdateCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! Couldn't update points cache. Reason: %s", error);

		return;
	}

	if(results.FetchRow())
	{
		gF_IdealTime = results.FetchFloat(0);
		gF_MapPoints = results.FetchFloat(1);
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			OnClientPutInServer(i);
		}
	}

	UpdateStringMap();
}

// a ***very simple*** 'aglorithm' that calculates points for a given time while taking into account the following: bhop style, ideal time and map points for the ideal time
public float CalculatePoints(float time, BhopStyle style, float idealtime, float mappoints)
{
    if(gF_IdealTime < 0.0 || gF_MapPoints < 0.0)
    {
        return -1.0; // something's wrong! map points might be undefined.
    }

    float points = ((mappoints / (time/idealtime)) * gI_RankingMultipliers[style]);

    if(time <= idealtime)
    {
        points *= 1.25;
    }

    return points;
}

public void Shavit_OnFinish_Post(int client, BhopStyle style, float time)
{
	#if defined DEBUG
	Shavit_PrintToChat(client, "Points: %.02f", CalculatePoints(time, style, gF_IdealTime, gF_MapPoints));
	#endif

	if(gF_MapPoints <= 0.0 || gF_IdealTime <= 0.0)
	{
		return;
	}

	float fPoints = CalculatePoints(time, style, gF_IdealTime, gF_MapPoints);
	Shavit_PrintToChat(client, "This record was rated \x05%.02f points\x01.", fPoints);
	SavePoints(GetClientSerial(client), style, gS_Map, fPoints, "");
}

public void SavePoints(int serial, BhopStyle style, const char[] map, float points, const char[] authid)
{
    char[] sAuthID = new char[32];

    if(strlen(authid) == 0)
    {
        int client = GetClientFromSerial(serial);

        if(client == 0)
        {
            LogError("Couldn't find client from serial %d.", serial);

            return;
        }

        else
        {
            GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);
        }
    }

    else
    {
        strcopy(sAuthID, 32, authid);
    }

    DataPack dp = new DataPack();
    dp.WriteCell(serial);
    dp.WriteString(sAuthID);
    dp.WriteString(map);
    dp.WriteCell(style);
    dp.WriteCell(points);

    char[] sQuery = new char[256];
    FormatEx(sQuery, 256, "SELECT id FROM %splayertimes WHERE auth = '%s' AND map = '%s' AND style = %d LIMIT 1;", gS_MySQLPrefix, sAuthID, map, style);

    gH_SQL.Query(SQL_FindRecordID_Callback, sQuery, dp, DBPrio_Low);
}

public void SQL_FindRecordID_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	ResetPack(data);
	int serial = ReadPackCell(data);

	char[] sAuthID = new char[32];
	ReadPackString(data, sAuthID, 32);

	char[] sMap = new char[192];
	ReadPackString(data, sMap, 192);

	BhopStyle style = ReadPackCell(data);
	float fPoints = ReadPackCell(data);
	CloseHandle(data);

	if(results == null)
	{
		LogError("Timer (rankings module) error! FindRecordID query failed. Reason: %s", error);

		return;
	}

	if(results.FetchRow())
	{
		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "REPLACE INTO %splayerpoints (recordid, points) VALUES ('%d', '%f');", gS_MySQLPrefix, results.FetchInt(0), fPoints);

		gH_SQL.Query(SQL_InsertPoints_Callback, sQuery, serial, DBPrio_Low);
	}

	else // just loop endlessly until it's in the database. if hosted locally, it should be instantly available!
	{
		SavePoints(serial, style, sMap, fPoints, sAuthID);
	}
}

public void SQL_InsertPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! Insertion of %d (serial) points to table failed. Reason: %s", data, error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client != 0)
	{
		UpdatePlayerPoints(client, true);
	}

	UpdateRankedPlayers();
}

public void UpdatePlayerPoints(int client, bool chat)
{
    if(!IsClientAuthorized(client))
    {
        return;
    }

    gB_PointsToChat[client] = chat;

    char[] sAuthID = new char[32];
    GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

    char[] sQuery = new char[256];
    FormatEx(sQuery, 256, "SELECT points FROM %splayertimes pt JOIN %splayerpoints pp ON pt.id = pp.recordid WHERE pt.auth = '%s' AND pp.points != -1 ORDER BY pp.points DESC;", gS_MySQLPrefix, gS_MySQLPrefix, sAuthID);

    gH_SQL.Query(SQL_UpdatePoints_Callback, sQuery, GetClientSerial(client), DBPrio_Low);
}

public void SQL_UpdatePoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results == null)
    {
        LogError("Timer (rankings module) error! Update of %d (serial) points failed. Reason: %s", data, error);

        return;
    }

    float fPoints = 0.0;
    float fWeight = 1.0;

    while(results.FetchRow())
    {
        fPoints += (results.FetchFloat(0) * fWeight);
        fWeight *= 0.95;
    }

    int client = GetClientFromSerial(data);

    if(client != 0)
    {
        if(gB_PointsToChat[client])
        {
            Shavit_PrintToChat(client, "Total points: \x05%.02f\x01.", fPoints);

            gB_PointsToChat[client] = false;
        }

        gF_PlayerPoints[client] = fPoints;

        char[] sAuthID3 = new char[32];

        if(GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
        {
            char[] sQuery = new char[256];
            FormatEx(sQuery, 256, "UPDATE %suserpoints SET points = '%f' WHERE auth = '%s';", gS_MySQLPrefix, fPoints, sAuthID3);

            gH_SQL.Query(SQL_UpdatePointsTable_Callback, sQuery, 0, DBPrio_Low);

            UpdatePlayerRank(client);
        }
    }
}

public void SQL_UpdatePointsTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results == null)
    {
        LogError("Timer (rankings module) error! UpdatePointsTable failed. Reason: %s", error);

        return;
    }
}

public void UpdatePlayerRank(int client)
{
    char[] sAuthID3 = new char[32];

    if(GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
    {
        char[] sQuery = new char[256];
        FormatEx(sQuery, 256, "SELECT COUNT(*) rank FROM %suserpoints up LEFT JOIN %susers u ON up.auth = u.auth WHERE up.points >= (SELECT points FROM %suserpoints WHERE auth = '%s' LIMIT 1) ORDER BY up.points DESC LIMIT 1;", gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, sAuthID3);

        gH_SQL.Query(SQL_UpdatePlayerRank_Callback, sQuery, GetClientSerial(client), DBPrio_Low);
    }
}

public void SQL_UpdatePlayerRank_Callback(Database db, DBResultSet results, const char[] error, any data)
{
    if(results == null)
    {
        LogError("Timer (rankings module) error! UpdatePlayerRank failed. Reason: %s", error);

        return;
    }

    int client = GetClientFromSerial(data);

    if(client == 0)
    {
        return;
    }

    if(results.FetchRow())
    {
		gI_PlayerRank[client] = results.FetchInt(0);

		Call_StartForward(gH_Forwards_OnRankUpdated);
		Call_PushCell(client);
		Call_Finish();
    }
}

public void UpdateRankedPlayers()
{
	char[] sQuery = new char[128];
	FormatEx(sQuery, 128, "SELECT COUNT(*) FROM %suserpoints WHERE points > 0 LIMIT 1;", gS_MySQLPrefix);

	gH_SQL.Query(SQL_UpdateRankedPlayers_Callback, sQuery);
}

public void SQL_UpdateRankedPlayers_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! UpdateRankedPlayers failed. Reason: %s", error);

		return;
	}

	if(results.FetchRow())
	{
		gI_RankedPlayers = results.FetchInt(0);
	}

	UpdateStringMap();
}

public int Native_GetPoints(Handle handler, int numParams)
{
	return view_as<int>(gF_PlayerPoints[GetNativeCell(1)]);
}

public int Native_GetRank(Handle handler, int numParams)
{
	return gI_PlayerRank[GetNativeCell(1)];
}

public int Native_GetMapValues(Handle handler, int numParams)
{
    SetNativeCellRef(1, gF_MapPoints);
    SetNativeCellRef(2, gF_IdealTime);
}

public int Native_GetGivenMapValues(Handle handler, int numParams)
{
	char[] map = new char[192];
	GetNativeString(1, map, 192);

	float fPoints = -1.0;

	if(!gSM_Points.GetValue(map, fPoints))
	{
		fPoints = -1.0;
	}

	SetNativeCellRef(2, fPoints);

	float fTime = 0.0;

	if(!gSM_Time.GetValue(map, fTime))
	{
		fTime = 0.0;
	}

	SetNativeCellRef(3, fTime);
}

public int Native_GetRankedPlayers(Handle handler, int numParams)
{
    return gI_RankedPlayers;
}

public int Native_CalculatePoints(Handle handler, int numParams)
{
	return view_as<int>(CalculatePoints(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3), GetNativeCell(4)));
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
		SQL_DBConnect();

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

public void SQL_DBConnect()
{
	if(gH_SQL != null)
	{
		char[] sDriver = new char[8];
		gH_SQL.Driver.GetIdentifier(sDriver, 8);
		gB_MySQL = StrEqual(sDriver, "mysql", false);

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "CREATE TABLE IF NOT EXISTS `%smappoints` (`map` VARCHAR(192), `time` FLOAT, `points` FLOAT, PRIMARY KEY (`map`));", gS_MySQLPrefix);
		gH_SQL.Query(SQL_CreateTable_Callback, sQuery, 0, DBPrio_High);

		FormatEx(sQuery, 256, "CREATE TABLE IF NOT EXISTS `%splayerpoints` (`recordid` INT NOT NULL, `points` FLOAT, PRIMARY KEY (`recordid`));", gS_MySQLPrefix);
		gH_SQL.Query(SQL_CreateTable_Callback, sQuery, 0, DBPrio_High);

		FormatEx(sQuery, 256, "CREATE TABLE IF NOT EXISTS `%suserpoints` (`auth` VARCHAR(32), `points` FLOAT, PRIMARY KEY (`auth`));", gS_MySQLPrefix);
		gH_SQL.Query(SQL_CreateTable_Callback, sQuery, 0, DBPrio_High);

		char[] sError = new char[255];
		gH_Tiers = SQLite_UseDatabase("shavit-tiers", sError, 255);

		if(gH_Tiers == null)
		{
			LogError("Cannot start `shavit-tiers` SQLite table. %s", sError);

			return;
		}

		FormatEx(sQuery, 256, "CREATE TABLE IF NOT EXISTS `%smaptiers` (`map` VARCHAR(192), `tier` INT, PRIMARY KEY (`map`));", gS_MySQLPrefix);
		gH_Tiers.Query(SQL_CreateTable_Callback, sQuery, 0, DBPrio_High);
	}
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! Table creation failed. Reason: %s", error);

		return;
	}

	UpdatePointsCache(gS_Map);
}
