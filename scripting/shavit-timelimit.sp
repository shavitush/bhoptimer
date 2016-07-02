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
	gCV_TimeLimit = FindConVar("mp_timelimit");

	gCV_RoundTime = FindConVar("mp_roundtime");
	gCV_RoundTime.SetBounds(ConVarBound_Upper, false);

	gCV_RestartGame = FindConVar("mp_restartgame");

	gCV_DefaultLimit = CreateConVar("shavit_timelimit_default", "60.0", "Default timelimit to use in case there isn't an average.", 0, true, 10.0);
	gCV_MinimumTimes = CreateConVar("shavit_timelimit_minimumtimes", "5", "Minimum amount of times required to calculate an average.", 0, true, 5.0);
	gCV_PlayerAmount = CreateConVar("shavit_timelimit_playertime", "25", "Limited amount of times to grab from the database to calculate an average.\nSet to 0 to have it \"unlimited\".", 0);
	gCV_Style = CreateConVar("shavit_timelimit_style", "1", "If set to 1, calculate an average only from times that the first (default: forwards) style was used to set.", 0, true, 0.0, true, 1.0);

	AutoExecConfig();

	Shavit_GetDB(gH_SQL);
	SQL_SetPrefix();
	SetSQLInfo();
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

public void StartCalculating()
{
	if(gH_SQL != null)
	{
		char sMap[128];
		GetCurrentMap(sMap, 128);

		char sQuery[256];
		FormatEx(sQuery, 256, "SELECT time FROM %splayertimes WHERE map = '%s' %sLIMIT %d;", gS_MySQLPrefix, sMap, gCV_Style.BoolValue? "AND style = 0 ":"", gCV_PlayerAmount.IntValue);

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

	int iRows = results.RowCount;

	if(iRows >= gCV_MinimumTimes.IntValue)
	{
		float fTotal = 0.0;

		while(results.FetchRow())
		{
			fTotal += results.FetchFloat(0);

			#if defined DEBUG
			PrintToServer("total: %.02f", fTotal);
			#endif
		}

		float fAverage = (fTotal / 60 / iRows);

		#if defined DEBUG
		PrintToServer("fAverage 1: %.02f", fAverage);
		#endif

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

		#if defined DEBUG
		PrintToServer("fAverage 2: %.02f", fAverage);
		#endif

		fAverage += 5; // I give extra 5 minutes, so players can actually retry the map until they get a good time.

		#if defined DEBUG
		PrintToServer("fAverage 3: %.02f", fAverage);
		#endif

		if(fAverage < 20)
		{
			fAverage = 20.0;
		}

		else if(fAverage > 120)
		{
			fAverage = 120.0;
		}

		#if defined DEBUG
		PrintToServer("fAverage 4: %.02f", fAverage);
		#endif

		SetLimit(RoundToNearest(fAverage));
	}

	else
	{
		SetLimit(RoundToNearest(gCV_DefaultLimit.FloatValue));
	}
}

public void SetLimit(int time)
{
	gCV_TimeLimit.SetInt(time);
	gCV_RoundTime.SetInt(time);

	gCV_RestartGame.IntValue = 1;
}
