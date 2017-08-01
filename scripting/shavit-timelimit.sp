/*
 * shavit's Timer - Dynamic Timelimits
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

// original idea from ckSurf.

#include <sourcemod>

#undef REQUIRE_PLUGIN
#include <shavit>

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

// #define DEBUG

// database handle
Database gH_SQL = null;

// base cvars
ConVar gCV_TimeLimit = null;
ConVar gCV_RoundTime = null;
ConVar gCV_RestartGame = null;

// cvars
ConVar gCV_DefaultLimit = null;
ConVar gCV_MinimumTimes = null;
ConVar gCV_PlayerAmount = null;
ConVar gCV_Style = null;

// cached cvars
float gF_DefaultLimit = 60.0;
int gI_MinimumTimes = 5;
int gI_PlayerAmount = 25;
bool gB_Style = true;

// table prefix
char gS_MySQLPrefix[32];

public Plugin myinfo =
{
	name = "[shavit] Dynamic Timelimits",
	author = "shavit",
	description = "Sets a dynamic value of mp_timelimit and mp_roundtime, based on average map times on the server.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
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
	gCV_RestartGame = FindConVar("mp_restartgame");
	gCV_TimeLimit = FindConVar("mp_timelimit");

	gCV_RoundTime = FindConVar("mp_roundtime");
	gCV_RoundTime.SetBounds(ConVarBound_Upper, false);

	gCV_DefaultLimit = CreateConVar("shavit_timelimit_default", "60.0", "Default timelimit to use in case there isn't an average.", 0, true, 10.0);
	gCV_MinimumTimes = CreateConVar("shavit_timelimit_minimumtimes", "5", "Minimum amount of times required to calculate an average.", 0, true, 5.0);
	gCV_PlayerAmount = CreateConVar("shavit_timelimit_playertime", "25", "Limited amount of times to grab from the database to calculate an average.\nSet to 0 to have it \"unlimited\".", 0);
	gCV_Style = CreateConVar("shavit_timelimit_style", "1", "If set to 1, calculate an average only from times that the first (default: forwards) style was used to set.", 0, true, 0.0, true, 1.0);

	gCV_DefaultLimit.AddChangeHook(OnConVarChanged);
	gCV_MinimumTimes.AddChangeHook(OnConVarChanged);
	gCV_PlayerAmount.AddChangeHook(OnConVarChanged);
	gCV_Style.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	Shavit_GetDB(gH_SQL);
	SQL_SetPrefix();
	SetSQLInfo();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gF_DefaultLimit = gCV_DefaultLimit.FloatValue;
	gI_MinimumTimes = gCV_MinimumTimes.IntValue;
	gI_PlayerAmount = gCV_PlayerAmount.IntValue;
	gB_Style = gCV_Style.BoolValue;
}

public Action CheckForSQLInfo(Handle Timer)
{
	return SetSQLInfo();
}

public void OnMapStart()
{
	StartCalculating();
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
		return Plugin_Stop;
	}

	return Plugin_Continue;
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

void StartCalculating()
{
	if(gH_SQL != null)
	{
		char sMap[256];
		GetCurrentMap(sMap, 256);

		char sQuery[512];
		FormatEx(sQuery, 512, "SELECT COUNT(*), SUM(t.time) FROM (SELECT r.time, r.style FROM %splayertimes r WHERE r.map = '%s' AND r.track = 0 %sORDER BY r.time LIMIT %d) t;", gS_MySQLPrefix, sMap, (gB_Style)? "AND style = 0 ":"", gI_PlayerAmount);

		#if defined DEBUG
		PrintToServer(sQuery);
		#endif

		gH_SQL.Query(SQL_GetMapTimes, sQuery, 0, DBPrio_High);
	}
}

public void SQL_GetMapTimes(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (TIMELIMIT time selection) SQL query failed. Reason: %s", error);

		return;
	}

	results.FetchRow();
	int iRows = results.FetchInt(0);

	if(iRows >= gI_MinimumTimes)
	{
		float fTimeSum = results.FetchFloat(1);
		float fAverage = (fTimeSum / 60 / iRows);

		if(fAverage <= 1)
		{
			fAverage *= 10;
		}

		else if(fAverage <= 2)
		{
			fAverage *= 9;
		}

		else if(fAverage <= 4)
		{
			fAverage *= 8;
		}

		else if(fAverage <= 8)
		{
			fAverage *= 7;
		}

		else if(fAverage <= 10)
		{
			fAverage *= 6;
		}

		fAverage += 5; // I give extra 5 minutes, so players can actually retry the map until they get a good time.

		if(fAverage < 20)
		{
			fAverage = 20.0;
		}

		else if(fAverage > 120)
		{
			fAverage = 120.0;
		}

		SetLimit(RoundToNearest(fAverage));
	}

	else
	{
		SetLimit(RoundToNearest(gF_DefaultLimit));
	}
}

void SetLimit(int time)
{
	gCV_TimeLimit.IntValue = time;
	gCV_RoundTime.IntValue = time;
	gCV_RestartGame.IntValue = 1;
}

public void Shavit_OnDatabaseLoaded(Database db)
{
	gH_SQL = db;
}
