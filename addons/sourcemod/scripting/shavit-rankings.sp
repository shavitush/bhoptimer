/*
 * shavit's Timer - Rankings
 * by: shavit, rtldg
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
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

// Design idea:
// Rank 1 per map/style/track gets ((points per tier * tier) * 1.5) + (rank 1 time in seconds / 15.0) points.
// Records below rank 1 get points% relative to their time in comparison to rank 1.
//
// Bonus track gets a 0.25* final multiplier for points and is treated as tier 1.
//
// Points for all styles are combined to promote competitive and fair gameplay.
// A player that gets good times at all styles should be ranked high.
//
// Total player points are weighted in the following way: (descending sort of points)
// points[0] * 0.975^0 + points[1] * 0.975^1 + points[2] * 0.975^2 + ... + points[n] * 0.975^n
//
// The ranking leaderboard will be calculated upon: map start.
// Points are calculated per-player upon: connection/map.
// Points are calculated per-map upon: map start, map end, tier changes.
// Rankings leaderboard is re-calculated once per map change.
// A command will be supplied to recalculate all of the above.
//
// Heavily inspired by pp (performance points) from osu!, written by Tom94. https://github.com/ppy/osu-performance

#include <sourcemod>
#include <convar_class>
#include <dhooks>

#include <shavit/core>
#include <shavit/rankings>
#include <shavit/wr>

#undef REQUIRE_PLUGIN

#undef REQUIRE_EXTENSIONS
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

// #define DEBUG

enum struct ranking_t
{
	int iRank;
	float fPoints;
	int iWRAmountAll;
	int iWRAmountCvar;
	int iWRHolderRankAll;
	int iWRHolderRankCvar;
	int iWRAmount[STYLE_LIMIT*2];
	int iWRHolderRank[STYLE_LIMIT*2];
}

char gS_MySQLPrefix[32];
Database gH_SQL = null;
bool gB_SQLWindowFunctions = false;
bool gB_SqliteHatesPOW = false;
int gI_Driver = Driver_unknown;

bool gB_Stats = false;
bool gB_Late = false;
bool gB_TierQueried = false;
bool gB_MapStarted = false;

int gI_Tier = 1; // No floating numbers for tiers, sorry.

char gS_Map[PLATFORM_MAX_PATH];
EngineVersion gEV_Type = Engine_Unknown;

ArrayList gA_ValidMaps = null;
StringMap gA_MapTiers = null;

Convar gCV_PointsPerTier = null;
Convar gCV_WeightingMultiplier = null;
Convar gCV_WeightingLimit = null;
Convar gCV_LastLoginRecalculate = null;
Convar gCV_MVPRankOnes_Slow = null;
Convar gCV_MVPRankOnes = null;
Convar gCV_MVPRankOnes_Main = null;
Convar gCV_DefaultTier = null;

ranking_t gA_Rankings[MAXPLAYERS+1];

int gI_RankedPlayers = 0;
Menu gH_Top100Menu = null;

Handle gH_Forwards_OnTierAssigned = null;
Handle gH_Forwards_OnRankAssigned = null;

// Timer settings.
chatstrings_t gS_ChatStrings;
int gI_Styles = 0;

bool gB_WorldRecordsCached = false;
bool gB_WRHolderTablesMade = false;
bool gB_WRHoldersRefreshed = false;
bool gB_WRHoldersRefreshedTimer = false;
int gI_WRHolders[2][STYLE_LIMIT];
int gI_WRHoldersAll;
int gI_WRHoldersCvar;

public Plugin myinfo =
{
	name = "[shavit] Rankings",
	author = "shavit, rtldg",
	description = "A fair and competitive ranking system for shavit's bhoptimer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetMapTier", Native_GetMapTier);
	CreateNative("Shavit_GetMapTiers", Native_GetMapTiers);
	CreateNative("Shavit_GetPoints", Native_GetPoints);
	CreateNative("Shavit_GetRank", Native_GetRank);
	CreateNative("Shavit_GetRankedPlayers", Native_GetRankedPlayers);
	CreateNative("Shavit_Rankings_DeleteMap", Native_Rankings_DeleteMap);
	CreateNative("Shavit_GetWRCount", Native_GetWRCount);
	CreateNative("Shavit_GetWRHolders", Native_GetWRHolders);
	CreateNative("Shavit_GetWRHolderRank", Native_GetWRHolderRank);
	CreateNative("Shavit_GuessPointsForTime", Native_GuessPointsForTime);

	RegPluginLibrary("shavit-rankings");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	gEV_Type = GetEngineVersion();

	gH_Forwards_OnTierAssigned = CreateGlobalForward("Shavit_OnTierAssigned", ET_Event, Param_String, Param_Cell);
	gH_Forwards_OnRankAssigned = CreateGlobalForward("Shavit_OnRankAssigned", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	RegConsoleCmd("sm_tier", Command_Tier, "Prints the map's tier to chat.");
	RegConsoleCmd("sm_maptier", Command_Tier, "Prints the map's tier to chat. (sm_tier alias)");

	RegConsoleCmd("sm_rank", Command_Rank, "Show your or someone else's rank. Usage: sm_rank [name]");
	RegConsoleCmd("sm_top", Command_Top, "Show the top 100 players.");

	RegAdminCmd("sm_settier", Command_SetTier, ADMFLAG_RCON, "Change the map's tier. Usage: sm_settier <tier> [map]");
	RegAdminCmd("sm_setmaptier", Command_SetTier, ADMFLAG_RCON, "Change the map's tier. Usage: sm_setmaptier <tier> [map] (sm_settier alias)");

	RegAdminCmd("sm_recalcmap", Command_RecalcMap, ADMFLAG_RCON, "Recalculate the current map's records' points.");

	RegAdminCmd("sm_recalcall", Command_RecalcAll, ADMFLAG_ROOT, "Recalculate the points for every map on the server. Run this after you change the ranking multiplier for a style or after you install the plugin.");

	gCV_PointsPerTier = new Convar("shavit_rankings_pointspertier", "50.0", "Base points to use for per-tier scaling.\nRead the design idea to see how it works: https://github.com/shavitush/bhoptimer/issues/465", 0, true, 1.0);
	gCV_WeightingMultiplier = new Convar("shavit_rankings_weighting", "0.975", "Weighting multiplier. 1.0 to disable weighting.\nFormula: p[0] * this^0 + p[1] * this^1 + p[2] * this^2 + ... + p[n] * this^n\nRestart server to apply.", 0, true, 0.01, true, 1.0);
	gCV_WeightingLimit = new Convar("shavit_rankings_weighting_limit", "0", "Limit the number of times retrieved for calculating a player's weighted points to this number.\n0 = no limit\nFor reference, a weighting of 0.975 to the power of 300 is 0.00050278777 and results in pretty much nil points for any further weighted times.\nUnused when shavit_rankings_weighting is 1.0.\nYou probably won't need to change this unless you have hundreds of thousands of player times in your database.", 0, true, 0.0, false);
	gCV_LastLoginRecalculate = new Convar("shavit_rankings_llrecalc", "0", "Maximum amount of time (in minutes) since last login to recalculate points for a player.\nsm_recalcall does not respect this setting.\n0 - disabled, don't filter anyone", 0, true, 0.0);
	gCV_MVPRankOnes_Slow = new Convar("shavit_rankings_mvprankones_slow", "1", "Uses a slower but more featureful MVP counting system.\nEnables the WR Holder ranks & counts for every style & track.\nYou probably won't need to change this unless you have hundreds of thousands of player times in your database.", 0, true, 0.0, true, 1.0);
	gCV_MVPRankOnes = new Convar("shavit_rankings_mvprankones", "2", "Set the players' amount of MVPs to the amount of #1 times they have.\n0 - Disabled\n1 - Enabled, for all styles.\n2 - Enabled, for default style only.\n(CS:S/CS:GO only)", 0, true, 0.0, true, 2.0);
	gCV_MVPRankOnes_Main = new Convar("shavit_rankings_mvprankones_maintrack", "1", "If set to 0, all tracks will be counted for the MVP stars.\nOtherwise, only the main track will be checked.\n\nRequires \"shavit_stats_mvprankones\" set to 1 or above.\n(CS:S/CS:GO only)", 0, true, 0.0, true, 1.0);
	gCV_DefaultTier = new Convar("shavit_rankings_default_tier", "1", "Sets the default tier for new maps added.", 0, true, 0.0, true, 10.0);

	Convar.AutoExecConfig();

	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-rankings.phrases");

	// tier cache
	gA_ValidMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	gA_MapTiers = new StringMap();

	if(gB_Late)
	{
		Shavit_OnChatConfigLoaded();
		Shavit_OnDatabaseLoaded();
	}

	if (gEV_Type != Engine_TF2)
	{
		CreateTimer(1.0, Timer_MVPs, 0, TIMER_REPEAT);
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	gI_Styles = styles;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = false;
	}
}

public void Shavit_OnDatabaseLoaded()
{
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = Shavit_GetDatabase(gI_Driver);

	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientAuthorized(i))
		{
			OnClientAuthorized(i, "");
		}
	}

	DbStuffPostMapStart();

	QueryLog(gH_SQL, SQL_Version_Callback,
		gI_Driver == Driver_sqlite
		? "WITH p AS (SELECT COUNT(*) FROM pragma_function_list WHERE name = 'pow') SELECT sqlite_version(), * FROM p;"
		: "SELECT VERSION();");
}

void CreateGetWeightedPointsFunction()
{
	if (gCV_WeightingMultiplier.FloatValue == 1.0)
	{
		return;
	}

	char sQuery[2048];
	Transaction trans = new Transaction();

	AddQueryLog(trans, "DROP PROCEDURE IF EXISTS UpdateAllPoints;;"); // old (and very slow) deprecated method
	AddQueryLog(trans, "DROP FUNCTION IF EXISTS GetWeightedPoints;;"); // this is here, just in case we ever choose to modify or optimize the calculation
	AddQueryLog(trans, "DROP FUNCTION IF EXISTS GetRecordPoints;;");

	char sWeightingLimit[30];

	if (gCV_WeightingLimit.IntValue > 0)
	{
		FormatEx(sWeightingLimit, sizeof(sWeightingLimit), "LIMIT %d", gCV_WeightingLimit.IntValue);
	}

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE FUNCTION GetWeightedPoints(steamid INT) " ...
		"RETURNS FLOAT " ...
		"READS SQL DATA " ...
		"BEGIN " ...
		"DECLARE p FLOAT; " ...
		"DECLARE total FLOAT DEFAULT 0.0; " ...
		"DECLARE mult FLOAT DEFAULT 1.0; " ...
		"DECLARE done INT DEFAULT 0; " ...
		"DECLARE cur CURSOR FOR SELECT points FROM %splayertimes WHERE auth = steamid AND points > 0.0 ORDER BY points DESC %s; " ...
		"DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1; " ...
		"OPEN cur; " ...
		"iter: LOOP " ...
			"FETCH cur INTO p; " ...
			"IF done THEN " ...
				"LEAVE iter; " ...
			"END IF; " ...
			"SET total = total + (p * mult); " ...
			"SET mult = mult * %f; " ...
		"END LOOP; " ...
		"CLOSE cur; " ...
		"RETURN total; " ...
		"END;;", gS_MySQLPrefix, sWeightingLimit, gCV_WeightingMultiplier.FloatValue);


	AddQueryLog(trans, sQuery);

	gH_SQL.Execute(trans, Trans_RankingsSetupSuccess, Trans_RankingsSetupError, 0, DBPrio_High);
}

public void Trans_RankingsSetupError(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Your Mysql/Mariadb didn't let us create the GetWeightedPoints function. Either update your DB version so it doesn't need GetWeightedPoints (to 8.0 or 10.2), fix your DB permissions, OR set `shavit_rankings_weighting` to `1.0`.");
	LogError("Timer (rankings) error %d/%d. Reason: %s", failIndex, numQueries, error);
	SetFailState("Read the error log");
}

public void Trans_RankingsSetupSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	DbStuffPostMapStart();
}

public void OnClientConnected(int client)
{
	ranking_t empty_ranking;
	gA_Rankings[client] = empty_ranking;
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (gH_SQL && !IsFakeClient(client))
	{
		if (gB_WRHolderTablesMade)
		{
			UpdateWRs(client);
		}

		UpdatePlayerRank(client, true);
	}
}

public void OnMapStart()
{
	GetLowercaseMapName(gS_Map);
	Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount()); // just in case :)
	gB_MapStarted = true;
	DbStuffPostMapStart();
}

void DbStuffPostMapStart()
{
	if (gH_SQL == null || !gB_MapStarted)
	{
		return;
	}

	if (gB_WRHolderTablesMade && !gB_WRHoldersRefreshed)
	{
		RefreshWRHolders();
	}

	// do NOT keep running this more than once per map, as UpdateAllPoints() is called after this eventually and locks up the database while it is running
	if (gB_TierQueried)
	{
		return;
	}

	if (gB_SqliteHatesPOW && gCV_WeightingMultiplier.FloatValue < 1.0)
	{
		LogError("Rankings Weighting multiplier set but sqlite extension isn't supported. Try using db.sqlite.ext from Sourcemod 1.12 or higher.");
	}

	if (gH_Top100Menu == null)
	{
		UpdateTop100();
	}

	// Default tier.
	// I won't repeat the same mistake blacky has done with tier 3 being default..
	gI_Tier = gCV_DefaultTier.IntValue;

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "SELECT map, tier FROM %smaptiers ORDER BY map ASC;", gS_MySQLPrefix);
	QueryLog(gH_SQL, SQL_FillTierCache_Callback, sQuery, 0, DBPrio_High);

	gB_TierQueried = true;
}

public void SQL_FillTierCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, fill tier cache) error! Reason: %s", error);

		return;
	}

	gA_ValidMaps.Clear();
	gA_MapTiers.Clear();

	while(results.FetchRow())
	{
		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(0, sMap, sizeof(sMap));
		LowercaseString(sMap);

		int tier = results.FetchInt(1);

		gA_MapTiers.SetValue(sMap, tier);
		gA_ValidMaps.PushString(sMap);

		Call_StartForward(gH_Forwards_OnTierAssigned);
		Call_PushString(sMap);
		Call_PushCell(tier);
		Call_Finish();
	}

	if (!gA_MapTiers.GetValue(gS_Map, gI_Tier))
	{
		Call_StartForward(gH_Forwards_OnTierAssigned);
		Call_PushString(gS_Map);
		Call_PushCell(gI_Tier);
		Call_Finish();

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "REPLACE INTO %smaptiers (map, tier) VALUES ('%s', %d);", gS_MySQLPrefix, gS_Map, gI_Tier);
		QueryLog(gH_SQL, SQL_SetMapTier_Callback, sQuery, 0, DBPrio_High);
	}
}

public void OnMapEnd()
{
	gB_TierQueried = false;
	gB_MapStarted = false;
	gB_WRHoldersRefreshed = false;
	gB_WRHoldersRefreshedTimer = false;
	gB_WorldRecordsCached = false;
}

public void Shavit_OnWRDeleted(int style, int id, int track, int accountid, const char[] mapname)
{
	if (!StrEqual(gS_Map, mapname))
	{
		return;
	}

	char sQuery[1024];
	// bUseCurrentMap=true because shavit-wr should maybe have updated the wr even through the updatewrcache query hasn't run yet
	FormatRecalculate(true, track, style, sQuery, sizeof(sQuery));
	QueryLog(gH_SQL, SQL_Recalculate_Callback, sQuery, (style << 8) | track, DBPrio_High);

	UpdateAllPoints(true);
}

public void Shavit_OnWorldRecordsCached()
{
	gB_WorldRecordsCached = true;
}

public Action Timer_MVPs(Handle timer)
{
	if (gCV_MVPRankOnes.IntValue == 0)
	{
		return Plugin_Continue;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			CS_SetMVPCount(i, Shavit_GetWRCount(i, -1, -1, true));
		}
	}

	return Plugin_Continue;
}

void UpdateWRs(int client)
{
	int iSteamID = GetSteamAccountID(client);

	if(iSteamID == 0)
	{
		return;
	}

	char sQuery[512];

	if (gCV_MVPRankOnes_Slow.BoolValue)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"     SELECT *, 0 as track, 0 as type FROM %swrhrankmain  WHERE auth = %d \
			UNION SELECT *, 1 as track, 0 as type FROM %swrhrankbonus WHERE auth = %d \
			UNION SELECT *, -1,         1 as type FROM %swrhrankall   WHERE auth = %d \
			UNION SELECT *, -1,         2 as type FROM %swrhrankcvar  WHERE auth = %d;",
			gS_MySQLPrefix, iSteamID, gS_MySQLPrefix, iSteamID, gS_MySQLPrefix, iSteamID, gS_MySQLPrefix, iSteamID);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"SELECT 0 as wrrank, -1 as style, auth, COUNT(*), -1 as track, 2 as type FROM %swrs WHERE auth = %d %s %s;",
			gS_MySQLPrefix,
			iSteamID,
			(gCV_MVPRankOnes.IntValue == 2)  ? "AND style = 0" : "",
			(gCV_MVPRankOnes_Main.BoolValue) ? "AND track = 0" : ""
		);
	}

	QueryLog(gH_SQL, SQL_GetWRs_Callback, sQuery, GetClientSerial(client));
}

public void SQL_GetWRs_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("SQL_GetWRs_Callback failed. Reason: %s", error);
		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	while (results.FetchRow())
	{
		int wrrank  = results.FetchInt(0);
		int style   = results.FetchInt(1);
		//int auth    = results.FetchInt(2);
		int wrcount = results.FetchInt(3);
		int track   = results.FetchInt(4);
		int type    = results.FetchInt(5);

		if (type == 0)
		{
			int index = STYLE_LIMIT*track + style;
			gA_Rankings[client].iWRAmount[index] = wrcount;
			gA_Rankings[client].iWRHolderRank[index] = wrrank;
		}
		else if (type == 1)
		{
			gA_Rankings[client].iWRAmountAll = wrcount;
			gA_Rankings[client].iWRHolderRankAll = wrcount;
		}
		else if (type == 2)
		{
			gA_Rankings[client].iWRAmountCvar = wrcount;
			gA_Rankings[client].iWRHolderRankCvar = wrrank;
		}
	}
}

public Action Command_Tier(int client, int args)
{
	int tier = gI_Tier;

	char sMap[PLATFORM_MAX_PATH];

	if(args == 0)
	{
		sMap = gS_Map;
	}
	else
	{
		GetCmdArgString(sMap, sizeof(sMap));
		LowercaseString(sMap);

		if(!GuessBestMapName(gA_ValidMaps, sMap, sMap) || !gA_MapTiers.GetValue(sMap, tier))
		{
			Shavit_PrintToChat(client, "%t", "Map was not found", sMap);
			return Plugin_Handled;
		}
	}

	Shavit_PrintToChat(client, "%T", "CurrentTier", client, gS_ChatStrings.sVariable, sMap, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, tier, gS_ChatStrings.sText);

	return Plugin_Handled;
}

public Action Command_Rank(int client, int args)
{
	int target = client;

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		target = FindTarget(client, sArgs, true, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}

	if(gA_Rankings[target].fPoints == 0.0)
	{
		Shavit_PrintToChat(client, "%T", "Unranked", client, gS_ChatStrings.sVariable2, target, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	Shavit_PrintToChat(client, "%T", "Rank", client, gS_ChatStrings.sVariable2, target, gS_ChatStrings.sText,
		gS_ChatStrings.sVariable, (gA_Rankings[target].iRank > gI_RankedPlayers)? gI_RankedPlayers:gA_Rankings[target].iRank, gS_ChatStrings.sText,
		gI_RankedPlayers,
		gS_ChatStrings.sVariable, gA_Rankings[target].fPoints, gS_ChatStrings.sText);

	return Plugin_Handled;
}

public Action Command_Top(int client, int args)
{
	if(gH_Top100Menu != null)
	{
		gH_Top100Menu.SetTitle("%T (%d)\n ", "Top100", client, gI_RankedPlayers);
		gH_Top100Menu.Display(client, MENU_TIME_FOREVER);
	}

	return Plugin_Handled;
}

public int MenuHandler_Top(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, 32);

		if(gB_Stats && !StrEqual(sInfo, "-1"))
		{
			FakeClientCommand(param1, "sm_profile [U:1:%s]", sInfo);
		}
	}

	return 0;
}

public Action Command_SetTier(int client, int args)
{
	char sArg[8];
	GetCmdArg(1, sArg, 8);

	int tier = StringToInt(sArg);

	int maxtier = GetMaxTier();

	if(args == 0 || tier < 1 || tier > maxtier)
	{
		ReplyToCommand(client, "%T", "ArgumentsMissing", client, "sm_settier <tier> (1-%d) [map]", maxtier);

		return Plugin_Handled;
	}

	char map[PLATFORM_MAX_PATH];

	if (args < 2)
	{
		gI_Tier = tier;
		map = gS_Map;
	}
	else
	{
		GetCmdArg(2, map, sizeof(map));
		TrimString(map);
		LowercaseString(map);

		if (!map[0])
		{
			Shavit_PrintToChat(client, "Invalid map name");
			return Plugin_Handled;
		}
	}

	gA_MapTiers.SetValue(map, tier);

	Call_StartForward(gH_Forwards_OnTierAssigned);
	Call_PushString(map);
	Call_PushCell(tier);
	Call_Finish();

	Shavit_PrintToChat(client, "%T", "SetTier", client, gS_ChatStrings.sVariable2, tier, gS_ChatStrings.sText);
	Shavit_LogMessage("%L - set tier of `%s` to %d", client, gS_Map, tier);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "REPLACE INTO %smaptiers (map, tier) VALUES ('%s', %d);", gS_MySQLPrefix, map, tier);

	DataPack data = new DataPack();
	data.WriteCell(client ? GetClientSerial(client) : 0);
	data.WriteString(map);

	QueryLog(gH_SQL, SQL_SetMapTier_Callback, sQuery, data);

	return Plugin_Handled;
}

public void SQL_SetMapTier_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if(results == null)
	{
		LogError("Timer (rankings, set map tier) error! Reason: %s", error);

		return;
	}

	if (data == null)
	{
		return;
	}

	int serial;
	char map[PLATFORM_MAX_PATH];

	data.Reset();
	serial = data.ReadCell();
	data.ReadString(map, sizeof(map));

	if (StrEqual(map, gS_Map))
	{
		ReallyRecalculateCurrentMap();
	}
	else
	{
		RecalculateSpecificMap(map, serial);
	}

	delete data;
}

public Action Command_RecalcMap(int client, int args)
{
	ReallyRecalculateCurrentMap();

	ReplyToCommand(client, "Recalc started.");

	return Plugin_Handled;
}

// You can use Sourcepawn_GetRecordPoints() as a reference for how the queries calculate points.
void FormatRecalculate(bool bUseCurrentMap, int track, int style, char[] sQuery, int sQueryLen, const char[] map = "")
{
	float fMultiplier = Shavit_GetStyleSettingFloat(style, "rankingmultiplier");

	if (track > 0)
	{
		fMultiplier *= 0.25;
	}

	if (Shavit_GetStyleSettingBool(style, "unranked") || fMultiplier == 0.0)
	{
		FormatEx(sQuery, sQueryLen,
			"UPDATE %splayertimes SET points = 0 WHERE style = %d AND track %c 0 %s%s%s;",
			gS_MySQLPrefix,
			style,
			(track > 0) ? '>' : '=',
			(bUseCurrentMap) ? "AND map = '" : "",
			(bUseCurrentMap) ? gS_Map : "",
			(bUseCurrentMap) ? "'" : ""
		);

		return;
	}

	if (bUseCurrentMap)
	{
		float fTier = (track > 0) ? 1.0 : float(gI_Tier);

		// a faster, joinless query is used for main due to it having 70% of playertimes.
		if (track == Track_Main && gB_WorldRecordsCached)
		{
			float fWR = Shavit_GetWorldRecord(style, track);

			FormatEx(sQuery, sQueryLen,
				"UPDATE %splayertimes " ...
				"SET points = %f * (%f / time) " ...
				"WHERE style = %d AND track = 0 AND map = '%s';",
				gS_MySQLPrefix,
				(((gCV_PointsPerTier.FloatValue * fTier) * 1.5) + (fWR / 15.0)) * fMultiplier,
				fWR,
				style,
				gS_Map
			);
		}
		else if (gI_Driver == Driver_sqlite)
		{
			FormatEx(sQuery, sQueryLen,
			    "UPDATE %splayertimes AS PT\n"
			... "SET\n"
			... " points =\n"
			... "   (%f + (WR.time / 15.0))\n"
			... " * (WR.time / PT.time)\n"
			... " * %f\n"
			... "FROM %swrs WR\n"
			... "WHERE PT.track %c 0 AND PT.style = %d AND PT.map = '%s'\n"
			... "  AND PT.track = WR.track AND PT.style = WR.style AND PT.map = WR.map;",
				gS_MySQLPrefix,
				((gCV_PointsPerTier.FloatValue * fTier) * 1.5),
				fMultiplier,
				gS_MySQLPrefix,
				(track > 0) ? '>' : '=',
				style,
				gS_Map
			);
		}
		else
		{
			FormatEx(sQuery, sQueryLen,
				"UPDATE %splayertimes AS PT " ...
				"INNER JOIN %swrs WR ON " ...
				"   PT.track = WR.track AND PT.style = WR.style AND PT.map = WR.map " ...
				"SET " ...
				" PT.points = "...
				"   (%f + (WR.time / 15.0)) " ...
				" * (WR.time / PT.time) " ...
				" * %f " ...
				"WHERE PT.track %c 0 AND PT.style = %d AND PT.map = '%s';",
				gS_MySQLPrefix, gS_MySQLPrefix,
				((gCV_PointsPerTier.FloatValue * fTier) * 1.5),
				fMultiplier,
				(track > 0) ? '>' : '=',
				style,
				gS_Map
			);
		}
	}
	else if (gI_Driver == Driver_sqlite)
	{
		char mapfilter[50+PLATFORM_MAX_PATH];
		if (map[0]) FormatEx(mapfilter, sizeof(mapfilter), "AND PT.map = '%s'", map);

		FormatEx(sQuery, sQueryLen,
		   "UPDATE %splayertimes AS PT\n"
		... "SET points =\n"
		... "   (((%f * %s) * 1.5) + (WR.time / 15.0))\n"
		... " * (WR.time / PT.time)\n"
		... " * %f\n"
		... "FROM %swrs AS WR\n"
		... "JOIN %smaptiers AS MT ON\n"
		... "  PT.map = MT.map\n"
		... "WHERE PT.track %c 0 AND PT.track = WR.track AND PT.style = %d AND PT.style = WR.style %s AND PT.map = WR.map;",
			gS_MySQLPrefix,
			gCV_PointsPerTier.FloatValue,
			(track > 0) ? "1" : "MT.tier",
			fMultiplier,
			gS_MySQLPrefix,
			gS_MySQLPrefix,
			(track > 0) ? '>' : '=',
			style,
			mapfilter
		);
	}
	else
	{
		char mapfilter[50+PLATFORM_MAX_PATH];
		if (map[0]) FormatEx(mapfilter, sizeof(mapfilter), "AND PT.map = '%s'", map);

		FormatEx(sQuery, sQueryLen,
			"UPDATE %splayertimes AS PT " ...
			"INNER JOIN %swrs AS WR ON " ...
			"  PT.track %c 0 AND PT.track = WR.track AND PT.style = %d AND PT.style = WR.style %s AND PT.map = WR.map " ...
			"INNER JOIN %smaptiers AS MT ON " ...
			"  PT.map = MT.map " ...
			"SET " ...
			" PT.points = "...
			"   (((%f * %s) * 1.5) + (WR.time / 15.0)) " ...
			" * (WR.time / PT.time) " ...
			" * %f;",
			gS_MySQLPrefix,
			gS_MySQLPrefix,
			(track > 0) ? '>' : '=',
			style,
			mapfilter,
			gS_MySQLPrefix,
			gCV_PointsPerTier.FloatValue,
			(track > 0) ? "1" : "MT.tier",
			fMultiplier
		);
	}
}

public Action Command_RecalcAll(int client, int args)
{
	ReplyToCommand(client, "- Started recalculating points for all maps. Check console for output.");

	Transaction trans = new Transaction();
	char sQuery[1024];

	FormatEx(sQuery, sizeof(sQuery), "UPDATE %splayertimes SET points = 0;", gS_MySQLPrefix);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %susers SET points = 0;", gS_MySQLPrefix);
	AddQueryLog(trans, sQuery);

	for(int i = 0; i < gI_Styles; i++)
	{
		if (!Shavit_GetStyleSettingBool(i, "unranked") && Shavit_GetStyleSettingFloat(i, "rankingmultiplier") != 0.0)
		{
			FormatRecalculate(false, Track_Main, i, sQuery, sizeof(sQuery));
			AddQueryLog(trans, sQuery);
			FormatRecalculate(false, Track_Bonus, i, sQuery, sizeof(sQuery));
			AddQueryLog(trans, sQuery);
		}
	}

	gH_SQL.Execute(trans, Trans_OnRecalcSuccess, Trans_OnRecalcFail, (client == 0)? 0:GetClientSerial(client));

	return Plugin_Handled;
}

public void Trans_OnRecalcSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	int client = (data == 0)? 0:GetClientFromSerial(data);

	if(client != 0)
	{
		SetCmdReplySource(SM_REPLY_TO_CONSOLE);
	}

	ReplyToCommand(client, "- Finished recalculating all points. Recalculating user points, top 100 and user cache.");

	UpdateAllPoints(true);
}

public void Trans_OnRecalcFail(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (rankings) error! Recalculation failed. Reason: %s", error);
}

void RecalculateSpecificMap(const char[] map, int serial)
{
	Transaction trans = new Transaction();
	char sQuery[1024];

	// Only maintrack times because bonus times aren't tiered.
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %splayertimes SET points = 0 WHERE map = '%s' AND track = 0;", gS_MySQLPrefix, map);
	AddQueryLog(trans, sQuery);

	for(int i = 0; i < gI_Styles; i++)
	{
		if (!Shavit_GetStyleSettingBool(i, "unranked") && Shavit_GetStyleSettingFloat(i, "rankingmultiplier") != 0.0)
		{
			FormatRecalculate(false, Track_Main, i, sQuery, sizeof(sQuery), map);
			AddQueryLog(trans, sQuery);
		}
	}

	gH_SQL.Execute(trans, Trans_OnRecalcSuccess, Trans_OnRecalcFail, serial);
}

void ReallyRecalculateCurrentMap()
{
	#if defined DEBUG
	LogError("DEBUG: 5xxx (ReallyRecalculateCurrentMap)");
	#endif

	Transaction trans = new Transaction();
	char sQuery[1024];

	FormatEx(sQuery, sizeof(sQuery), "UPDATE %splayertimes SET points = 0 WHERE map = '%s';", gS_MySQLPrefix, gS_Map);
	AddQueryLog(trans, sQuery);

	for (int i = 0; i < gI_Styles; i++)
	{
		if (!Shavit_GetStyleSettingBool(i, "unranked") && Shavit_GetStyleSettingFloat(i, "rankingmultiplier") != 0.0)
		{
			FormatRecalculate(true, Track_Main, i, sQuery, sizeof(sQuery));
			AddQueryLog(trans, sQuery);
			FormatRecalculate(true, Track_Bonus, i, sQuery, sizeof(sQuery));
			AddQueryLog(trans, sQuery);
		}
	}

	gH_SQL.Execute(trans, Trans_OnReallyRecalcSuccess, Trans_OnReallyRecalcFail, 0);
}

public void Trans_OnReallyRecalcSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	UpdateAllPoints(true, gS_Map);
}

public void Trans_OnReallyRecalcFail(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (rankings) error! ReallyRecalculateCurrentMap failed. Reason: %s", error);
}

public void Shavit_OnFinish_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int track)
{
	if (Shavit_GetStyleSettingBool(style, "unranked") || Shavit_GetStyleSettingFloat(style, "rankingmultiplier") == 0.0)
	{
		return;
	}

	if (rank != 1)
	{
		UpdatePointsForSinglePlayer(client);
		return;
	}

	#if defined DEBUG
	PrintToServer("Recalculating points. (%s, %d, %d)", map, track, style);
	#endif

	char sQuery[1024];
	FormatRecalculate(true, track, style, sQuery, sizeof(sQuery));

	QueryLog(gH_SQL, SQL_Recalculate_Callback, sQuery, (style << 8) | track, DBPrio_High);
	UpdateAllPoints(true, gS_Map, track);
}

public void SQL_Recalculate_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	int track = data & 0xFF;
	int style = data >> 8;

	if(results == null)
	{
		LogError("Timer (rankings, recalculate map points, %s, style=%d) error! Reason: %s", (track == Track_Main) ? "main" : "bonus", style, error);

		return;
	}

	#if defined DEBUG
	PrintToServer("Recalculated (%s, style=%d).", (track == Track_Main) ? "main_" : "bonus", style);
	#endif
}

void UpdatePointsForSinglePlayer(int client)
{
	int auth = GetSteamAccountID(client);

	char sQuery[1024];

	if (gCV_WeightingMultiplier.FloatValue == 1.0 || gB_SqliteHatesPOW)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"UPDATE %susers SET points = (SELECT SUM(points) FROM %splayertimes WHERE auth = %d) WHERE auth = %d;",
			gS_MySQLPrefix, gS_MySQLPrefix, auth, auth);
	}
	else if (gB_SQLWindowFunctions)
	{
		char sLimit[30];
		if (gCV_WeightingLimit.IntValue > 0)
			FormatEx(sLimit, sizeof(sLimit), "LIMIT %d", gCV_WeightingLimit.IntValue);

		FormatEx(sQuery, sizeof(sQuery),
		    "UPDATE %susers SET points = (\n"
		... "  SELECT SUM(points2) FROM (\n"
		... "    SELECT (points * POW(%f, ROW_NUMBER() OVER (ORDER BY points DESC) - 1)) as points2\n"
		... "    FROM %splayertimes\n"
		... "    WHERE auth = %d AND points > 0\n"
		... "    ORDER BY points DESC %s\n"
		... "  ) as t\n"
		... ") WHERE auth = %d;",
			gS_MySQLPrefix,
			gCV_WeightingMultiplier.FloatValue,
			gS_MySQLPrefix,
			auth,
			sLimit,
			auth
		);
	}
	else // We should only be here if mysql :)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"UPDATE %susers SET points = GetWeightedPoints(auth) WHERE auth = %d;",
			gS_MySQLPrefix, auth);
	}

	QueryLog(gH_SQL, SQL_UpdateAllPoints_Callback, sQuery, GetClientSerial(client));
}

void UpdateAllPoints(bool recalcall=false, char[] map="", int track=-1)
{
	#if defined DEBUG
	LogError("DEBUG: 6 (UpdateAllPoints)");
	#endif

	char sQuery[1024];
	char sLastLogin[69], sLimit[30], sMapWhere[512], sTrackWhere[64];

	if (track != -1)
		FormatEx(sTrackWhere, sizeof(sTrackWhere), "track = %d", track);
	if (map[0])
		FormatEx(sMapWhere, sizeof(sMapWhere), "map = '%s'", map);

	if (!recalcall && gCV_LastLoginRecalculate.IntValue > 0)
	{
		FormatEx(sLastLogin, sizeof(sLastLogin), "lastlogin > %d", (GetTime() - gCV_LastLoginRecalculate.IntValue * 60));
	}

	if (gCV_WeightingLimit.IntValue > 0)
		FormatEx(sLimit, sizeof(sLimit), "LIMIT %d", gCV_WeightingLimit.IntValue);

	if (gCV_WeightingMultiplier.FloatValue == 1.0 || gB_SqliteHatesPOW)
	{
		if (gI_Driver == Driver_sqlite)
		{
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %susers AS U SET points = P.total FROM (SELECT auth, SUM(points) AS total FROM %splayertimes GROUP BY auth) P WHERE U.auth = P.auth %s %s;",
				gS_MySQLPrefix, gS_MySQLPrefix,
				(sLastLogin[0] != 0) ? "AND " : "", sLastLogin);
		}
		else
		{
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %susers AS U INNER JOIN (SELECT auth, SUM(points) AS total FROM %splayertimes GROUP BY auth) P ON U.auth = P.auth SET U.points = P.total %s %s;",
				gS_MySQLPrefix, gS_MySQLPrefix,
				(sLastLogin[0] != 0) ? "WHERE" : "", sLastLogin);
		}
	}
	else if (gB_SQLWindowFunctions && gI_Driver == Driver_mysql)
	{
		if (sLastLogin[0])
			Format(sLastLogin, sizeof(sLastLogin), "u2.%s", sLastLogin);

		// fuck you mysql
		FormatEx(sQuery, sizeof(sQuery),
		    "UPDATE %susers AS u, (\n"
		... "  SELECT auth, SUM(t.points2) as pp FROM (\n"
		... "    SELECT p.auth, (p.points * POW(%f, ROW_NUMBER() OVER (PARTITION BY p.auth ORDER BY p.points DESC) - 1)) as points2\n"
		... "    FROM %splayertimes AS p\n"
		... "    JOIN %susers AS u2\n"
		... "     ON u2.auth = p.auth %s %s\n"
		... "    WHERE p.points > 0 AND p.auth IN (SELECT DISTINCT auth FROM %splayertimes %s %s %s %s)\n"
		... "    ORDER BY p.points DESC %s\n"
		... "  ) AS t\n"
		... "  GROUP by auth\n"
		... ") AS a\n"
		... "SET u.points = a.pp\n"
		... "WHERE u.auth = a.auth;",
			gS_MySQLPrefix,
			gCV_WeightingMultiplier.FloatValue,
			gS_MySQLPrefix,
			gS_MySQLPrefix,
			sLastLogin[0] ? "AND" : "", sLastLogin,
			gS_MySQLPrefix,
			(sMapWhere[0] || sTrackWhere[0]) ? "WHERE" : "",
			sMapWhere,
			(sMapWhere[0] && sTrackWhere[0]) ? "AND" : "",
			sTrackWhere,
			sLimit); // TODO: Remove/move sLimit?
	}
	else if (gB_SQLWindowFunctions)
	{
		FormatEx(sQuery, sizeof(sQuery),
		    "UPDATE %susers AS u\n"
		... "SET points = (\n"
		... "  SELECT SUM(points2) FROM (\n"
		... "    SELECT (points * POW(%f, ROW_NUMBER() OVER (ORDER BY points DESC) - 1)) AS points2\n"
		... "    FROM %splayertimes\n"
		... "    WHERE auth = u.auth AND points > 0\n"
		... "    ORDER BY points DESC %s\n"
		... "  ) AS t\n"
		... ") WHERE %s %s auth IN\n"
		... "  (SELECT DISTINCT auth FROM %splayertimes %s %s %s %s);",
			gS_MySQLPrefix,
			gCV_WeightingMultiplier.FloatValue,
			gS_MySQLPrefix,
			sLimit, // TODO: Remove/move sLimit?
			sLastLogin, sLastLogin[0] ? "AND" : "",
			gS_MySQLPrefix,
			(sMapWhere[0] || sTrackWhere[0]) ? "WHERE" : "",
			sMapWhere,
			(sMapWhere[0] && sTrackWhere[0]) ? "AND" : "",
			sTrackWhere);
	}
	else // !gB_SQLWindowFunctions && gI_Driver == Driver_mysql
	{
		FormatEx(sQuery, sizeof(sQuery),
			"UPDATE %susers SET points = GetWeightedPoints(auth) WHERE %s %s auth IN (SELECT DISTINCT auth FROM %splayertimes %s %s %s %s);",
			gS_MySQLPrefix,
			sLastLogin, (sLastLogin[0] != 0) ? "AND" : "",
			gS_MySQLPrefix,
			(sMapWhere[0] || sTrackWhere[0]) ? "WHERE" : "",
			sMapWhere,
			(sMapWhere[0] && sTrackWhere[0]) ? "AND" : "",
			sTrackWhere);
	}

	QueryLog(gH_SQL, SQL_UpdateAllPoints_Callback, sQuery);
}

public void SQL_UpdateAllPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update all points) error! Reason: %s", error);

		return;
	}

	UpdateTop100();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsClientAuthorized(i))
		{
			UpdatePlayerRank(i, false);
		}
	}
}

void UpdatePlayerRank(int client, bool first)
{
	int iSteamID = 0;

	if((iSteamID = GetSteamAccountID(client)) != 0)
	{
		// if there's any issue with this query,
		// add "ORDER BY points DESC " before "LIMIT 1"
		char sQuery[512];
		FormatEx(sQuery, 512, "SELECT u2.points, COUNT(*) FROM %susers u1 JOIN (SELECT points FROM %susers WHERE auth = %d) u2 WHERE u1.points >= u2.points;",
			gS_MySQLPrefix, gS_MySQLPrefix, iSteamID);

		DataPack hPack = new DataPack();
		hPack.WriteCell(GetClientSerial(client));
		hPack.WriteCell(first);

		QueryLog(gH_SQL, SQL_UpdatePlayerRank_Callback, sQuery, hPack, DBPrio_Low);
	}
}

public void SQL_UpdatePlayerRank_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack hPack = view_as<DataPack>(data);
	hPack.Reset();

	int iSerial = hPack.ReadCell();
	bool bFirst = view_as<bool>(hPack.ReadCell());
	delete hPack;

	if(results == null)
	{
		LogError("Timer (rankings, update player rank) error! Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(iSerial);

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		gA_Rankings[client].fPoints = results.FetchFloat(0);
		gA_Rankings[client].iRank = (gA_Rankings[client].fPoints > 0.0)? results.FetchInt(1):0;

		Call_StartForward(gH_Forwards_OnRankAssigned);
		Call_PushCell(client);
		Call_PushCell(gA_Rankings[client].iRank);
		Call_PushCell(gA_Rankings[client].fPoints);
		Call_PushCell(bFirst);
		Call_Finish();
	}
}

void UpdateTop100()
{
	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery),
		"SELECT * FROM (SELECT COUNT(*) as c, 0 as auth, '' as name, '' as p FROM %susers WHERE points > 0) a \
		UNION ALL \
		SELECT * FROM (SELECT -1 as c, auth, name, FORMAT(points, 2) FROM %susers WHERE points > 0 ORDER BY points DESC LIMIT 100) b;",
		gS_MySQLPrefix, gS_MySQLPrefix);

	QueryLog(gH_SQL, SQL_UpdateTop100_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_UpdateTop100_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update top 100) error! Reason: %s", error);

		return;
	}

	if (!results.FetchRow())
	{
		LogError("Timer (rankings, update top 100 b) error! Reason: failed to fetch first row");
		return;
	}

	gI_RankedPlayers = results.FetchInt(0);

	delete gH_Top100Menu;
	gH_Top100Menu = new Menu(MenuHandler_Top);

	int row = 0;

	while(results.FetchRow())
	{
		char sSteamID[32];
		results.FetchString(1, sSteamID, 32);

		char sName[32+1];
		results.FetchString(2, sName, sizeof(sName));

		char sPoints[16];
		results.FetchString(3, sPoints, 16);

		char sDisplay[96];
		FormatEx(sDisplay, 96, "#%d - %s (%s)", (++row), sName, sPoints);
		gH_Top100Menu.AddItem(sSteamID, sDisplay);
	}

	if(gH_Top100Menu.ItemCount == 0)
	{
		char sDisplay[64];
		FormatEx(sDisplay, 64, "%t", "NoRankedPlayers");
		gH_Top100Menu.AddItem("-1", sDisplay);
	}

	gH_Top100Menu.ExitButton = true;
}

bool DoWeHaveWindowFunctions(const char[] sVersion)
{
	char buf[100][2];
	ExplodeString(sVersion, ".", buf, 2, 100);
	int iMajor = StringToInt(buf[0]);
	int iMinor = StringToInt(buf[1]);

	if (gI_Driver == Driver_sqlite)
	{
		// 2018~
		return iMajor > 3 || (iMajor == 3 && iMinor >= 25); // 2018~
	}
	else if (gI_Driver == Driver_pgsql)
	{
		// 2009~
		return iMajor > 8 || (iMajor == 8 && iMinor >= 4);
	}
	else if (gI_Driver == Driver_mysql)
	{
		if (StrContains(sVersion, "MariaDB") != -1)
		{
			 // 2016~
			return iMajor > 10 || (iMajor == 10 && iMinor >= 2);
		}
		else // mysql then...
		{
			// 2018~
			return iMajor > 8 || (iMajor == 8 && iMinor >= 0);
		}
	}

	return false;
}

public void SQL_Version_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null || !results.FetchRow())
	{
		LogError("Timer (rankings) error! Failed to retrieve VERSION(). Reason: %s", error);
	}
	else
	{
		char sVersion[100];
		results.FetchString(0, sVersion, sizeof(sVersion));
		gB_SQLWindowFunctions = DoWeHaveWindowFunctions(sVersion);

		if (gI_Driver == Driver_sqlite)
		{
			gB_SqliteHatesPOW = results.FetchInt(1) == 0;
		}
	}

	if (!gB_SQLWindowFunctions)
	{
		if (gI_Driver == Driver_sqlite)
		{
			SetFailState("sqlite version not supported. Try using db.sqlite.ext from Sourcemod 1.12 or higher.");
		}
		else if (gI_Driver == Driver_pgsql)
		{
			LogError("Okay, really? Your postgres version is from 2014 or earlier... come on, brother...");
			SetFailState("Update postgresql");
		}
		else // mysql
		{
			// Mysql 5.7 is a cancer upon society. EOS is Oct 2023!! Unbelievable.
			// Please update your servers already, nfoservers.
			CreateGetWeightedPointsFunction();
		}
	}

	char sWRHolderRankTrackQueryYuck[] =
		"%s %s%s AS \
			SELECT \
			0 as wrrank, \
			style, auth, COUNT(auth) as wrcount \
			FROM %swrs WHERE track %c 0 GROUP BY style, auth;";

	char sWRHolderRankTrackQueryRANK[] =
		"%s %s%s AS \
			SELECT \
				RANK() OVER(PARTITION BY style ORDER BY COUNT(auth) DESC, auth ASC) \
			as wrrank, \
			style, auth, COUNT(auth) as wrcount \
			FROM %swrs WHERE track %c 0 GROUP BY style, auth;";

	char sWRHolderRankOtherQueryYuck[] =
		"%s %s%s AS \
			SELECT \
			0 as wrrank, \
			-1 as style, auth, COUNT(*) \
			FROM %swrs %s %s %s %s GROUP BY auth;";

	char sWRHolderRankOtherQueryRANK[] =
		"%s %s%s AS \
			SELECT \
				RANK() OVER(ORDER BY COUNT(auth) DESC, auth ASC) \
			as wrrank, \
			-1 as style, auth, COUNT(*) as wrcount \
			FROM %swrs %s %s %s %s GROUP BY auth;";

	char sQuery[800];
	Transaction trans = new Transaction();

	if (gI_Driver == Driver_sqlite)
	{
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankmain;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankbonus;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankall;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankcvar;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
	}

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankTrackQueryYuck : sWRHolderRankTrackQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankmain", gS_MySQLPrefix, '=');
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankTrackQueryYuck : sWRHolderRankTrackQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankbonus", gS_MySQLPrefix, '>');
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankOtherQueryYuck : sWRHolderRankOtherQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankall", gS_MySQLPrefix, "", "", "", "");
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankOtherQueryYuck : sWRHolderRankOtherQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankcvar", gS_MySQLPrefix,
		(gCV_MVPRankOnes.IntValue == 2 || gCV_MVPRankOnes_Main.BoolValue) ? "WHERE" : "",
		(gCV_MVPRankOnes.IntValue == 2)  ? "style = 0" : "",
		(gCV_MVPRankOnes.IntValue == 2 && gCV_MVPRankOnes_Main.BoolValue) ? "AND" : "",
		(gCV_MVPRankOnes_Main.BoolValue) ? "track = 0" : "");
	AddQueryLog(trans, sQuery);

	gH_SQL.Execute(trans, Trans_WRHolderRankTablesSuccess, Trans_WRHolderRankTablesError, 0, DBPrio_High);
}

public void Trans_WRHolderRankTablesSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	gB_WRHolderTablesMade = true;

	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientAuthorized(i))
		{
			UpdateWRs(i);
		}
	}

	RefreshWRHolders();
}

void RefreshWRHolders()
{
	if (gB_WRHoldersRefreshedTimer)
	{
		return;
	}

	gB_WRHoldersRefreshedTimer = true;
	CreateTimer(10.0, Timer_RefreshWRHolders, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RefreshWRHolders(Handle timer, any data)
{
	RefreshWRHoldersActually();
	return Plugin_Stop;
}

void RefreshWRHoldersActually()
{
	char sQuery[1024];

	if (gCV_MVPRankOnes_Slow.BoolValue)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"     SELECT 0 as type, 0 as track, style, COUNT(DISTINCT auth) FROM %swrhrankmain GROUP BY style \
			UNION SELECT 0 as type, 1 as track, style, COUNT(DISTINCT auth) FROM %swrhrankbonus GROUP BY style \
			UNION SELECT 1 as type, -1 as track, -1 as style, COUNT(DISTINCT auth) FROM %swrhrankall \
			UNION SELECT 2 as type, -1 as track, -1 as style, COUNT(DISTINCT auth) FROM %swrhrankcvar;",
			gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"SELECT 2 as type, -1 as track, -1 as style, COUNT(DISTINCT auth) FROM %swrs %s %s %s %s;",
			gS_MySQLPrefix,
			(gCV_MVPRankOnes.IntValue == 2 || gCV_MVPRankOnes_Main.BoolValue) ? "WHERE" : "",
			(gCV_MVPRankOnes.IntValue == 2)  ? "style = 0" : "",
			(gCV_MVPRankOnes.IntValue == 2 && gCV_MVPRankOnes_Main.BoolValue) ? "AND" : "",
			(gCV_MVPRankOnes_Main.BoolValue) ? "track = 0" : ""
		);
	}

	QueryLog(gH_SQL, SQL_GetWRHolders_Callback, sQuery);

	gB_WRHoldersRefreshed = true;
}

public void Trans_WRHolderRankTablesError(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (WR Holder Rank table creation %d/%d) SQL query failed. Reason: %s", failIndex, numQueries, error);
}

public void SQL_GetWRHolders_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (get WR Holder amount) SQL query failed. Reason: %s", error);

		return;
	}

	while (results.FetchRow())
	{
		int type  = results.FetchInt(0);
		int track = results.FetchInt(1);
		int style = results.FetchInt(2);
		int total = results.FetchInt(3);

		if (type == 0)
		{
			gI_WRHolders[track][style] = total;
		}
		else if (type == 1)
		{
			gI_WRHoldersAll = total;
		}
		else if (type == 2)
		{
			gI_WRHoldersCvar = total;
		}
	}
}

public int Native_GetWRCount(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);
	int style = GetNativeCell(3);
	bool usecvars = view_as<bool>(GetNativeCell(4));

	if (usecvars)
	{
		return gA_Rankings[client].iWRAmountCvar;
	}
	else if (track == -1 && style == -1)
	{
		return gA_Rankings[client].iWRAmountAll;
	}

	if (track > Track_Bonus)
	{
		track = Track_Bonus;
	}

	return gA_Rankings[client].iWRAmount[STYLE_LIMIT*track + style];
}

public int Native_GetWRHolders(Handle handler, int numParams)
{
	int track = GetNativeCell(1);
	int style = GetNativeCell(2);
	bool usecvars = view_as<bool>(GetNativeCell(3));

	if (usecvars)
	{
		return gI_WRHoldersCvar;
	}
	else if (track == -1 && style == -1)
	{
		return gI_WRHoldersAll;
	}

	if (track > Track_Bonus)
	{
		track = Track_Bonus;
	}

	return gI_WRHolders[track][style];
}

public int Native_GetWRHolderRank(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);
	int style = GetNativeCell(3);
	bool usecvars = view_as<bool>(GetNativeCell(4));

	if (usecvars)
	{
		return gA_Rankings[client].iWRHolderRankCvar;
	}
	else if (track == -1 && style == -1)
	{
		return gA_Rankings[client].iWRHolderRankAll;
	}

	if (track > Track_Bonus)
	{
		track = Track_Bonus;
	}

	return gA_Rankings[client].iWRHolderRank[STYLE_LIMIT*track + style];
}

public int Native_GetMapTier(Handle handler, int numParams)
{
	int tier = 0;
	char sMap[PLATFORM_MAX_PATH];
	GetNativeString(1, sMap, sizeof(sMap));

	if (!sMap[0])
	{
		return gI_Tier;
	}

	gA_MapTiers.GetValue(sMap, tier);
	return tier;
}

public int Native_GetMapTiers(Handle handler, int numParams)
{
	return view_as<int>(CloneHandle(gA_MapTiers, handler));
}

public int Native_GetPoints(Handle handler, int numParams)
{
	return view_as<int>(gA_Rankings[GetNativeCell(1)].fPoints);
}

public int Native_GetRank(Handle handler, int numParams)
{
	return gA_Rankings[GetNativeCell(1)].iRank;
}

public int Native_GetRankedPlayers(Handle handler, int numParams)
{
	return gI_RankedPlayers;
}

public int Native_Rankings_DeleteMap(Handle handler, int numParams)
{
	char sMap[PLATFORM_MAX_PATH];
	GetNativeString(1, sMap, sizeof(sMap));
	LowercaseString(sMap);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM %smaptiers WHERE map = '%s';", gS_MySQLPrefix, sMap);
	QueryLog(gH_SQL, SQL_DeleteMap_Callback, sQuery, StrEqual(gS_Map, sMap, false), DBPrio_High);
	return 1;
}

public int Native_GuessPointsForTime(Handle plugin, int numParams)
{
	int rtrack = GetNativeCell(1);
	int rstyle = GetNativeCell(2);
	int tier = GetNativeCell(3);
	float rtime = view_as<float>(GetNativeCell(4));
	float pwr = view_as<float>(GetNativeCell(5));

	float ppoints = Sourcepawn_GetRecordPoints(
		rtrack,
		rtime,
		gCV_PointsPerTier.FloatValue,
		Shavit_GetStyleSettingFloat(rstyle, "rankingmultiplier"),
		pwr,
		float(tier == -1 ? gI_Tier : tier)
	);

	return view_as<int>(ppoints);
}

float Sourcepawn_GetRecordPoints(int rtrack, float rtime, float pointspertier, float stylemultiplier, float pwr, float ptier)
{
	float ppoints = 0.0;

	if (rtrack > 0)
	{
		ptier = 1.0;
	}

	ppoints  = ((pointspertier * ptier) * 1.5) + (pwr / 15.0);
	ppoints *= (pwr / rtime);
	ppoints *= stylemultiplier;

	if (rtrack > 0)
	{
		ppoints *= 0.25;
	}

	return ppoints;
}

public void SQL_DeleteMap_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings deletemap) SQL query failed. Reason: %s", error);

		return;
	}

	if(view_as<bool>(data))
	{
		gI_Tier = gCV_DefaultTier.IntValue;

		UpdateAllPoints(true);
	}
}

int GetMaxTier()
{
	float val = 10.0;
	gCV_DefaultTier.GetBounds(ConVarBound_Upper, val);
	return RoundToFloor(val);
}
