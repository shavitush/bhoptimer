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

#define USES_STYLE_MULTIPLIERS
#include <shavit>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

//#define DEBUG

// cache
char gS_Map[256];
float gF_IdealTime = 0.0;
float gF_Points = -1.0;

// database handle
Database gH_SQL = null;

// table prefix
char gS_MySQLPrefix[32];

public Plugin myinfo =
{
	name = "[shavit] Rankings",
	author = "shavit",
	description = "Rankings system for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
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
    // database connections
    Shavit_GetDB(gH_SQL);
    SQL_SetPrefix();
    SetSQLInfo();

    // player commands
    RegConsoleCmd("sm_points", Command_Points, "Prints the points and ideal time for the map.");
    // sm_rank

    // admin commands
    RegAdminCmd("sm_setpoints", Command_SetPoints, ADMFLAG_ROOT, "Set points for a defined ideal time. sm_setpoints <time in seconds> <points>");

    #if defined DEBUG
    // debug
    RegServerCmd("sm_calc", Command_Calc);
    #endif
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
    gF_IdealTime = 0.0;
    gF_Points = -1.0;

    GetCurrentMap(gS_Map, 256);
    UpdatePointsCache(gS_Map);
}

public Action Command_Points(int client, int args)
{
    if(!IsValidClient(client))
    {
        return Plugin_Handled;
    }

    if(gF_Points == -1.0)
    {
        Shavit_PrintToChat(client, "Points are not defined for this map.");

        return Plugin_Handled;
    }

    char[] sDisplayMap = new char[strlen(gS_Map)];
    GetMapDisplayName(gS_Map, sDisplayMap, strlen(gS_Map));

    char[] sTime = new char[32];
    FormatSeconds(gF_IdealTime, sTime, 32, false);

    Shavit_PrintToChat(client, "\x04%s\x01: \x03%.01f\x01 points for \x05%s\x01.", sDisplayMap, gF_Points, sTime);

    return Plugin_Handled;
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
    float fPoints = gF_Points = StringToFloat(sArg2);

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

    gH_SQL.Query(SQL_SetPoints_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_SetPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! Failed to insert map data to the table. Reason: %s", error);

		return;
	}
}

public void UpdatePointsCache(const char[] map)
{
    char[] sQuery = new char[512]; // fuck workshop maps
    FormatEx(sQuery, 512, "SELECT time, points FROM %smappoints WHERE map = '%s';", gS_MySQLPrefix, map);

    gH_SQL.Query(SQL_UpdateCache_Callback, sQuery, 0, DBPrio_High);
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
        gF_Points = results.FetchFloat(1);
    }
}

// a ***very simple*** 'aglorithm' that calculates points for a given time while taking into account the following: bhop style, ideal time and map points for the ideal time
public float CalculatePoints(float time, BhopStyle style, float idealtime, float mappoints)
{
    if(gF_IdealTime < 0.0 || gF_Points < 0.0)
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

public void SQL_DBConnect()
{
	if(SQL_CheckConfig("shavit"))
	{
		if(gH_SQL != null)
		{
            char[] sQuery = new char[256];
            FormatEx(sQuery, 256, "CREATE TABLE IF NOT EXISTS `%smappoints` (`map` VARCHAR(192), `time` FLOAT, `points` FLOAT, PRIMARY KEY (`map`));", gS_MySQLPrefix);
            gH_SQL.Query(SQL_CreateTable_Callback, sQuery);

            FormatEx(sQuery, 256, "CREATE TABLE IF NOT EXISTS `%splayerpoints` (`recordid` INT NOT NULL, `points` FLOAT, PRIMARY KEY (`recordid`));", gS_MySQLPrefix);
            gH_SQL.Query(SQL_CreateTable_Callback, sQuery);
		}
	}

	else
	{
		SetFailState("Timer (rankings module) startup failed. Reason: %s", "\"shavit\" is not a specified entry in databases.cfg.");
	}
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! Table creation failed. Reason: %s", error);

		return;
	}
}
