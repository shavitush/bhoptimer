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
// points[0] * 0.975^0 + points[1] * 0.975^1 + points[2] * 0.975^2 + ... + points[n] * 0.975^(n-1)
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

#undef REQUIRE_PLUGIN
#include <shavit>

#undef REQUIRE_EXTENSIONS
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

// uncomment when done
// #define DEBUG

enum struct ranking_t
{
	int iRank;
	float fPoints;
}

char gS_MySQLPrefix[32];
Database gH_SQL = null;	

bool gB_Stats = false;
bool gB_Late = false;
bool gB_TierQueried = false;

int gI_Tier = 1; // No floating numbers for tiers, sorry.

char gS_Map[160];
EngineVersion gEV_Type = Engine_Unknown;

ArrayList gA_ValidMaps = null;
StringMap gA_MapTiers = null;

Convar gCV_PointsPerTier = null;
Convar gCV_WeightingMultiplier = null;
Convar gCV_LastLoginRecalculate = null;
Convar gCV_MVPRankOnes = null;
Convar gCV_MVPRankOnes_Main = null;

ranking_t gA_Rankings[MAXPLAYERS+1];

int gI_RankedPlayers = 0;
Menu gH_Top100Menu = null;

Handle gH_Forwards_OnTierAssigned = null;
Handle gH_Forwards_OnRankAssigned = null;

// Timer settings.
chatstrings_t gS_ChatStrings;
int gI_Styles = 0;

int gI_WRAmount[MAXPLAYERS+1][2][STYLE_LIMIT];
int gI_WRAmountAll[MAXPLAYERS+1];
int gI_WRAmountCvar[MAXPLAYERS+1];
int gI_WRHolders[2][STYLE_LIMIT];
int gI_WRHoldersAll;
int gI_WRHoldersCvar;
int gI_WRHolderRank[MAXPLAYERS+1][2][STYLE_LIMIT];
int gI_WRHolderRankAll[MAXPLAYERS+1];
int gI_WRHolderRankCvar[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "[shavit] Rankings",
	author = "shavit",
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

	RegPluginLibrary("shavit-rankings");

	gB_Late = late;

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
	gEV_Type = GetEngineVersion();

	gH_Forwards_OnTierAssigned = CreateGlobalForward("Shavit_OnTierAssigned", ET_Event, Param_String, Param_Cell);
	gH_Forwards_OnRankAssigned = CreateGlobalForward("Shavit_OnRankAssigned", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	RegConsoleCmd("sm_tier", Command_Tier, "Prints the map's tier to chat.");
	RegConsoleCmd("sm_maptier", Command_Tier, "Prints the map's tier to chat. (sm_tier alias)");

	RegConsoleCmd("sm_rank", Command_Rank, "Show your or someone else's rank. Usage: sm_rank [name]");
	RegConsoleCmd("sm_top", Command_Top, "Show the top 100 players.");

	RegAdminCmd("sm_settier", Command_SetTier, ADMFLAG_RCON, "Change the map's tier. Usage: sm_settier <tier>");
	RegAdminCmd("sm_setmaptier", Command_SetTier, ADMFLAG_RCON, "Change the map's tier. Usage: sm_setmaptier <tier> (sm_settier alias)");

	RegAdminCmd("sm_recalcmap", Command_RecalcMap, ADMFLAG_RCON, "Recalculate the current map's records' points.");

	RegAdminCmd("sm_recalcall", Command_RecalcAll, ADMFLAG_ROOT, "Recalculate the points for every map on the server. Run this after you change the ranking multiplier for a style or after you install the plugin.");

	gCV_PointsPerTier = new Convar("shavit_rankings_pointspertier", "50.0", "Base points to use for per-tier scaling.\nRead the design idea to see how it works: https://github.com/shavitush/bhoptimer/issues/465", 0, true, 1.0);
	gCV_WeightingMultiplier = new Convar("shavit_rankings_weighting", "0.975", "Weighing multiplier. 1.0 to disable weighting.\nFormula: p[1] * this^0 + p[2] * this^1 + p[3] * this^2 + ... + p[n] * this^(n-1)\nRestart server to apply.", 0, true, 0.01, true, 1.0);
	gCV_LastLoginRecalculate = new Convar("shavit_rankings_llrecalc", "10080", "Maximum amount of time (in minutes) since last login to recalculate points for a player.\nsm_recalcall does not respect this setting.\n0 - disabled, don't filter anyone", 0, true, 0.0);
	gCV_MVPRankOnes = new Convar("shavit_rankings_mvprankones", "2", "Set the players' amount of MVPs to the amount of #1 times they have.\n0 - Disabled\n1 - Enabled, for all styles.\n2 - Enabled, for default style only.\n(CS:S/CS:GO only)", 0, true, 0.0, true, 2.0);
	gCV_MVPRankOnes_Main = new Convar("shavit_rankings_mvprankones_maintrack", "1", "If set to 0, all tracks will be counted for the MVP stars.\nOtherwise, only the main track will be checked.\n\nRequires \"shavit_stats_mvprankones\" set to 1 or above.\n(CS:S/CS:GO only)", 0, true, 0.0, true, 1.0);

	Convar.AutoExecConfig();

	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-rankings.phrases");

	// hooks
	HookEvent("player_spawn", Player_Event);
	HookEvent("player_team", Player_Event);

	// tier cache
	gA_ValidMaps = new ArrayList(128);
	gA_MapTiers = new StringMap();

	if(gB_Late)
	{
		Shavit_OnChatConfigLoaded();
	}

	SQL_DBConnect();
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStrings(sMessagePrefix, gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix));
	Shavit_GetChatStrings(sMessageText, gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	Shavit_GetChatStrings(sMessageWarning, gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning));
	Shavit_GetChatStrings(sMessageVariable, gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
	Shavit_GetChatStrings(sMessageVariable2, gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2));
	Shavit_GetChatStrings(sMessageStyle, gS_ChatStrings.sStyle, sizeof(chatstrings_t::sStyle));
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		gI_Styles = Shavit_GetStyleCount();
	}
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

void SQL_DBConnect()
{
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = GetTimerDatabaseHandle();

	if(!IsMySQLDatabase(gH_SQL))
	{
		SetFailState("MySQL is the only supported database engine for shavit-rankings.");
	}

	char sQuery[256];
	FormatEx(sQuery, 256, "CREATE TABLE IF NOT EXISTS `%smaptiers` (`map` VARCHAR(128), `tier` INT NOT NULL DEFAULT 1, PRIMARY KEY (`map`)) ENGINE=INNODB;", gS_MySQLPrefix);

	gH_SQL.Query(SQL_CreateTable_Callback, sQuery, 0);
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings) error! Map tiers table creation failed. Reason: %s", error);

		return;
	}

	#if defined DEBUG
	PrintToServer("DEBUG: 0 (SQL_CreateTable_Callback)");
	#endif

	if(gI_Styles == 0)
	{
		Shavit_OnStyleConfigLoaded(-1);
	}

	SQL_LockDatabase(gH_SQL);
	SQL_FastQuery(gH_SQL, "DELIMITER ;;");
	SQL_FastQuery(gH_SQL, "DROP PROCEDURE IF EXISTS UpdateAllPoints;;"); // old (and very slow) deprecated method
	SQL_FastQuery(gH_SQL, "DROP FUNCTION IF EXISTS GetWeightedPoints;;"); // this is here, just in case we ever choose to modify or optimize the calculation
	SQL_FastQuery(gH_SQL, "DROP FUNCTION IF EXISTS GetRecordPoints;;");

	bool bSuccess = true;

	RunLongFastQuery(bSuccess, "CREATE GetWeightedPoints",
		"CREATE FUNCTION GetWeightedPoints(steamid INT) " ...
		"RETURNS FLOAT " ...
		"READS SQL DATA " ...
		"BEGIN " ...
		"DECLARE p FLOAT; " ...
		"DECLARE total FLOAT DEFAULT 0.0; " ...
		"DECLARE mult FLOAT DEFAULT 1.0; " ...
		"DECLARE done INT DEFAULT 0; " ...
		"DECLARE cur CURSOR FOR SELECT points FROM %splayertimes WHERE auth = steamid AND points > 0.0 ORDER BY points DESC; " ...
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
		"END;;", gS_MySQLPrefix, gCV_WeightingMultiplier.FloatValue);

	RunLongFastQuery(bSuccess, "CREATE GetRecordPoints",
		"CREATE FUNCTION GetRecordPoints(rstyle INT, rtrack INT, rtime FLOAT, rmap VARCHAR(128), pointspertier FLOAT, stylemultiplier FLOAT, pwr FLOAT) " ...
		"RETURNS FLOAT " ...
		"READS SQL DATA " ...
		"BEGIN " ...
		"DECLARE ppoints FLOAT DEFAULT 0.0; " ...
		"DECLARE ptier INT DEFAULT 1; " ...
		"SELECT tier FROM %smaptiers WHERE map = rmap INTO ptier; " ...
		"IF rtrack > 0 THEN SET ptier = 1; END IF; " ...
		"SET ppoints = ((pointspertier * ptier) * 1.5) + (pwr / 15.0); " ...
		"IF rtime > pwr THEN SET ppoints = ppoints * (pwr / rtime); END IF; " ...
		"SET ppoints = ppoints * stylemultiplier; " ...
		"IF rtrack > 0 THEN SET ppoints = ppoints * 0.25; END IF; " ...
		"RETURN ppoints; " ...
		"END;;", gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix);

	SQL_FastQuery(gH_SQL, "DELIMITER ;");
	SQL_UnlockDatabase(gH_SQL);

	if(!bSuccess)
	{
		return;
	}

	OnMapStart();

	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			OnClientConnected(i);
		}
	}
}

void RunLongFastQuery(bool &success, const char[] func, const char[] query, any ...)
{
	char sQuery[2048];
	VFormat(sQuery, 2048, query, 4);

	if(!SQL_FastQuery(gH_SQL, sQuery))
	{
		char sError[255];
		SQL_GetError(gH_SQL, sError, 255);
		LogError("Timer (rankings, %s) error! Reason: %s", func, sError);

		success = false;
	}
}

public void OnClientConnected(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	gA_Rankings[client].iRank = 0;
	gA_Rankings[client].fPoints = 0.0;

	for (int i = 0; i < 2; i++)
	{
		for (int j = 0; j < gI_Styles; j++)
		{
			gI_WRAmount[client][i][j] = 0;
			gI_WRHolderRank[client][i][j] = 0;
		}
	}

	gI_WRAmountAll[client] = 0;
	gI_WRAmountCvar[client] = 0;
	gI_WRHolderRankAll[client] = 0;
	gI_WRHolderRankCvar[client] = 0;
}

public void OnClientPutInServer(int client)
{
	UpdateWRs(client);
}

public void OnClientPostAdminCheck(int client)
{
	if(!IsFakeClient(client))
	{
		UpdatePlayerRank(client, true);
	}
}

public void OnMapStart()
{
	// do NOT keep running this more than once per map, as UpdateAllPoints() is called after this eventually and locks up the database while it is running
	if(gB_TierQueried)
	{
		return;
	}

	#if defined DEBUG
	PrintToServer("DEBUG: 1 (OnMapStart)");
	#endif

	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);

	UpdateWRHolders();

	// Default tier.
	// I won't repeat the same mistake blacky has done with tier 3 being default..
	gI_Tier = 1;

	char sQuery[256];
	FormatEx(sQuery, 256, "SELECT tier FROM %smaptiers WHERE map = '%s';", gS_MySQLPrefix, gS_Map);
	gH_SQL.Query(SQL_GetMapTier_Callback, sQuery);

	gB_TierQueried = true;
}

public void SQL_GetMapTier_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, get map tier) error! Reason: %s", error);

		return;
	}

	#if defined DEBUG
	PrintToServer("DEBUG: 2 (SQL_GetMapTier_Callback)");
	#endif

	if(results.RowCount > 0 && results.FetchRow())
	{
		gI_Tier = results.FetchInt(0);

		#if defined DEBUG
		PrintToServer("DEBUG: 3 (tier: %d) (SQL_GetMapTier_Callback)", gI_Tier);
		#endif

		RecalculateAll(gS_Map);
		UpdateAllPoints();

		#if defined DEBUG
		PrintToServer("DEBUG: 4 (SQL_GetMapTier_Callback)");
		#endif

		char sQuery[256];
		FormatEx(sQuery, 256, "SELECT map, tier FROM %smaptiers;", gS_MySQLPrefix, gS_Map);
		gH_SQL.Query(SQL_FillTierCache_Callback, sQuery, 0, DBPrio_High);
	}

	else
	{
		char sQuery[256];
		FormatEx(sQuery, 256, "REPLACE INTO %smaptiers (map, tier) VALUES ('%s', %d);", gS_MySQLPrefix, gS_Map, gI_Tier);
		gH_SQL.Query(SQL_SetMapTier_Callback, sQuery, gI_Tier, DBPrio_High);
	}
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
		char sMap[160];
		results.FetchString(0, sMap, 160);

		int tier = results.FetchInt(1);

		gA_MapTiers.SetValue(sMap, tier);
		gA_ValidMaps.PushString(sMap);

		Call_StartForward(gH_Forwards_OnTierAssigned);
		Call_PushString(sMap);
		Call_PushCell(tier);
		Call_Finish();
	}

	SortADTArray(gA_ValidMaps, Sort_Ascending, Sort_String);
}

public void OnMapEnd()
{
	RecalculateAll(gS_Map);
	gB_TierQueried = false;
}

public void Player_Event(Event event, const char[] name, bool dontBroadcast)
{
	if(gCV_MVPRankOnes.IntValue == 0)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsValidClient(client) && !IsFakeClient(client) && gEV_Type != Engine_TF2)
	{
		CS_SetMVPCount(client, Shavit_GetWRCount(client, -1, -1, true));
	}
}

void UpdateWRs(int client)
{
	int iSteamID = GetSteamAccountID(client);

	if(iSteamID == 0)
	{
		return;
	}

	char sQuery[512];

	FormatEx(sQuery, sizeof(sQuery),
		"     SELECT *, 0 as track, 0 as type FROM wrhrankmain  WHERE auth = %d \
		UNION SELECT *, 1 as track, 0 as type FROM wrhrankbonus WHERE auth = %d \
		UNION SELECT *, -1,         1 as type FROM wrhrankall   WHERE auth = %d \
		UNION SELECT *, -1,         2 as type FROM wrhrankcvar  WHERE auth = %d;",
		iSteamID, iSteamID, iSteamID, iSteamID);
	gH_SQL.Query(SQL_GetWRs_Callback, sQuery, GetClientSerial(client));
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
			gI_WRAmount[client][track][style] = wrcount;
			gI_WRHolderRank[client][track][style] = wrrank;
		}
		else if (type == 1)
		{
			gI_WRAmountAll[client] = wrcount;
			gI_WRHolderRankAll[client] = wrrank;
		}
		else if (type == 2)
		{
			gI_WRAmountCvar[client] = wrcount;
			gI_WRHolderRankCvar[client] = wrrank;
		}
	}

	if(gCV_MVPRankOnes.IntValue > 0 && gEV_Type != Engine_TF2)
	{
		CS_SetMVPCount(client, Shavit_GetWRCount(client, -1, -1, true));
	}
}

public Action Command_Tier(int client, int args)
{
	int tier = gI_Tier;

	char sMap[128];

	if(args == 0)
	{
		strcopy(sMap, 128, gS_Map);
	}
	
	else
	{
		GetCmdArgString(sMap, 128);
		if(!GuessBestMapName(gA_ValidMaps, sMap, sMap, 128) || !gA_MapTiers.GetValue(sMap, tier))
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
			Shavit_OpenStatsMenu(param1, StringToInt(sInfo));
		}
	}

	return 0;
}

public Action Command_SetTier(int client, int args)
{
	char sArg[8];
	GetCmdArg(1, sArg, 8);
	
	int tier = StringToInt(sArg);

	if(args == 0 || tier < 1 || tier > 10)
	{
		ReplyToCommand(client, "%T", "ArgumentsMissing", client, "sm_settier <tier> (1-10)");

		return Plugin_Handled;
	}

	gI_Tier = tier;
	gA_MapTiers.SetValue(gS_Map, tier);

	Call_StartForward(gH_Forwards_OnTierAssigned);
	Call_PushString(gS_Map);
	Call_PushCell(tier);
	Call_Finish();

	Shavit_PrintToChat(client, "%T", "SetTier", client, gS_ChatStrings.sVariable2, tier, gS_ChatStrings.sText);

	char sQuery[256];
	FormatEx(sQuery, 256, "REPLACE INTO %smaptiers (map, tier) VALUES ('%s', %d);", gS_MySQLPrefix, gS_Map, tier);

	gH_SQL.Query(SQL_SetMapTier_Callback, sQuery);

	return Plugin_Handled;
}

public void SQL_SetMapTier_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, set map tier) error! Reason: %s", error);

		return;
	}

	RecalculateAll(gS_Map);
}

public Action Command_RecalcMap(int client, int args)
{
	RecalculateAll(gS_Map);
	UpdateAllPoints(true);

	ReplyToCommand(client, "Done.");

	return Plugin_Handled;
}

void FormatRecalculate(const char[] map, int track, int style, char[] sQuery, int sQueryLen)
{
	char sTrack[30];
	bool bHaveMap = strlen(map) != 0;

	if (track != -1)
	{
		FormatEx(sTrack, sizeof(sTrack), "track %c 0", (track > 0) ? '>' : '=');
	}

	float fMultiplier = Shavit_GetStyleSettingFloat(style, "rankingmultiplier");

	if (Shavit_GetStyleSettingBool(style, "unranked") || fMultiplier == 0.0)
	{
		FormatEx(sQuery, sQueryLen,
			"UPDATE %splayertimes SET points = 0 WHERE style = %d %s %s%s%c %s %s;",
			gS_MySQLPrefix, style,
			(bHaveMap || track != -1) ? "AND" : "",
			(bHaveMap) ? "map = '" : "",
			(bHaveMap) ? map : "",
			(bHaveMap) ? '\'' : ' ',
			(bHaveMap && track != -1) ? "AND" : "",
			sTrack
		);
	}
	else
	{
		FormatEx(sQuery, sQueryLen,
			"UPDATE %splayertimes AS PT, "...
			"( SELECT MIN(time) as time, map, track, style "...
			"  FROM %splayertimes "...
			"  WHERE style = %d %s %s%s%c %s %s"...
			"  GROUP BY map, track, style "...
			") as WR "...
			"SET PT.points = GetRecordPoints(PT.style, PT.track, PT.time, PT.map, %.1f, %.3f, WR.time) "...
			"WHERE PT.style = WR.style and PT.track = WR.track and PT.map = WR.map;",
			gS_MySQLPrefix, gS_MySQLPrefix, style,
			(bHaveMap || track != -1) ? "AND" : "",
			(bHaveMap) ? "map = '" : "",
			(bHaveMap) ? map : "",
			(bHaveMap) ? '\'' : ' ',
			(bHaveMap && track != -1) ? "AND" : "",
			sTrack,
			gCV_PointsPerTier.FloatValue, fMultiplier
		);
	}
}

public Action Command_RecalcAll(int client, int args)
{
	ReplyToCommand(client, "- Started recalculating points for all maps. Check console for output.");

	Transaction trans = new Transaction();
	char sQuery[666];

	for(int i = 0; i < gI_Styles; i++)
	{
		FormatRecalculate("", -1, i, sQuery, sizeof(sQuery));
		trans.AddQuery(sQuery);
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
	UpdateTop100();

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsClientAuthorized(i))
		{
			UpdatePlayerRank(i, false);
		}
	}

	ReplyToCommand(client, "- Done.");
}

public void Trans_OnRecalcFail(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (rankings) error! Recalculation failed. Reason: %s", error);
}

void RecalculateAll(const char[] map)
{
	#if defined DEBUG
	LogError("DEBUG: 5 (RecalculateAll)");
	#endif

	char sQuery[666];

	for(int i = 0; i < gI_Styles; i++)
	{
		FormatRecalculate(map, -1, i, sQuery, sizeof(sQuery));
		gH_SQL.Query(SQL_Recalculate_Callback, sQuery, 0, DBPrio_High);
	}
}

public void Shavit_OnFinish_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int track)
{
	RecalculateMap(gS_Map, track, style);
}

void RecalculateMap(const char[] map, const int track, const int style)
{
	#if defined DEBUG
	PrintToServer("Recalculating points. (%s, %d, %d)", map, track, style);
	#endif

	char sQuery[666];
	FormatRecalculate(map, track, style, sQuery, sizeof(sQuery));

	gH_SQL.Query(SQL_Recalculate_Callback, sQuery, 0, DBPrio_High);

	#if defined DEBUG
	PrintToServer("Sent query.");
	#endif
}

public void SQL_Recalculate_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if(results == null)
	{
		LogError("Timer (rankings, recalculate map points) error! Reason: %s", error);

		return;
	}

	#if defined DEBUG
	PrintToServer("Recalculated.");
	#endif
}

void UpdateAllPoints(bool recalcall = false)
{
	#if defined DEBUG
	LogError("DEBUG: 6 (UpdateAllPoints)");
	#endif

	char sQuery[256];

	if(recalcall || gCV_LastLoginRecalculate.IntValue == 0)
	{
		FormatEx(sQuery, 256, "UPDATE %susers SET points = GetWeightedPoints(auth) WHERE auth IN (SELECT DISTINCT auth FROM %splayertimes);",
			gS_MySQLPrefix, gS_MySQLPrefix);
	}

	else
	{
		FormatEx(sQuery, 256, "UPDATE %susers SET points = GetWeightedPoints(auth) WHERE lastlogin > %d AND auth IN (SELECT DISTINCT auth FROM %splayertimes);",
			gS_MySQLPrefix, (GetTime() - gCV_LastLoginRecalculate.IntValue * 60), gS_MySQLPrefix);
	}
	
	gH_SQL.Query(SQL_UpdateAllPoints_Callback, sQuery);
}

public void SQL_UpdateAllPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update all points) error! Reason: %s", error);

		return;
	}

	UpdateRankedPlayers();
}

void UpdatePlayerRank(int client, bool first)
{
	gA_Rankings[client].iRank = 0;
	gA_Rankings[client].fPoints = 0.0;

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

		gH_SQL.Query(SQL_UpdatePlayerRank_Callback, sQuery, hPack, DBPrio_Low);
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

void UpdateRankedPlayers()
{
	char sQuery[512];
	FormatEx(sQuery, 512, "SELECT COUNT(*) count FROM %susers WHERE points > 0.0;",
		gS_MySQLPrefix);

	gH_SQL.Query(SQL_UpdateRankedPlayers_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_UpdateRankedPlayers_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update ranked players) error! Reason: %s", error);

		return;
	}

	if(results.FetchRow())
	{
		gI_RankedPlayers = results.FetchInt(0);

		UpdateTop100();
	}
}

void UpdateTop100()
{
	char sQuery[512];
	FormatEx(sQuery, 512, "SELECT auth, name, FORMAT(points, 2) FROM %susers WHERE points > 0.0 ORDER BY points DESC LIMIT 100;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_UpdateTop100_Callback, sQuery, 0, DBPrio_Low);
}

public void SQL_UpdateTop100_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update top 100) error! Reason: %s", error);

		return;
	}

	if(gH_Top100Menu != null)
	{
		delete gH_Top100Menu;
	}

	gH_Top100Menu = new Menu(MenuHandler_Top);

	int row = 0;

	while(results.FetchRow())
	{
		if(row > 100)
		{
			break;
		}

		char sSteamID[32];
		results.FetchString(0, sSteamID, 32);

		char sName[MAX_NAME_LENGTH];
		results.FetchString(1, sName, MAX_NAME_LENGTH);

		char sPoints[16];
		results.FetchString(2, sPoints, 16);

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

void UpdateWRHolders()
{
	// Compatible with MySQL 5.6, 5.7, 8.0
	char sWRHolderRankTrackQueryYuck[] =
		"CREATE TEMPORARY TABLE %s AS \
			SELECT ( \
				CASE style \
				WHEN @curGroup \
				THEN @curRow := @curRow + 1 \
				ELSE @curRow := 1 AND @curGroup := style END \
			) as wrrank, \
			style, auth, wrcount \
			FROM ( \
				SELECT style, auth, SUM(c) as wrcount FROM ( \
					SELECT style, auth, COUNT(auth) as c FROM %swrs WHERE track %c 0 GROUP BY style, auth \
				) a GROUP BY style, auth ORDER BY style ASC, wrcount DESC, auth ASC \
			) x, \
			(SELECT @curRow := 0, @curGroup := 0) r \
			ORDER BY style ASC, wrrank ASC, auth ASC;";
	
	// Compatible with MySQL 8.0 and SQLite // TODO: SELECT VERSION() and check...
	char sWRHolderRankTrackQueryRANK[] =
		"CREATE TEMPORARY TABLE %s AS \
			SELECT \
				RANK() OVER(PARTITION BY style ORDER BY wrcount DESC, auth ASC) \
			as wrrank, \
			style, auth, wrcount \
			FROM ( \
				SELECT style, auth, SUM(c) as wrcount FROM ( \
					SELECT style, auth, COUNT(auth) as c FROM %swrs WHERE track %c 0 GROUP BY style, auth \
				) a GROUP BY style, auth \
			) x;";

	// Compatible with MySQL 5.6, 5.7, 8.0
	char sWRHolderRankOtherQueryYuck[] =
		"CREATE TEMPORARY TABLE %s AS \
			SELECT ( \
				@curRow := @curRow + 1 \
			) as wrrank, \
			-1 as style, auth, wrcount \
			FROM ( \
				SELECT COUNT(*) as wrcount, auth FROM %swrs %s %s %s %s GROUP BY auth ORDER BY wrcount DESC, auth ASC \
			) x, \
			(SELECT @curRow := 0) r \
			ORDER BY style ASC, wrrank ASC, auth ASC;";

	// Compatible with MySQL 8.0 and SQLite // TODO: SELECT VERSION() and check...
	char sWRHolderRankOtherQueryRANK[] =
		"CREATE TEMPORARY TABLE %s AS \
			SELECT \
				RANK() OVER(ORDER BY wrcount DESC, auth ASC) \
			as wrrank, \
			-1 as style, auth, wrcount \
			FROM ( \
				SELECT COUNT(*) as wrcount, auth FROM %swrs %s %s %s %s GROUP BY auth \
			) x;";

	char sQuery[800];
	Transaction hTransaction = new Transaction();

	hTransaction.AddQuery("DROP TABLE IF EXISTS wrhrankmain;");
	FormatEx(sQuery, sizeof(sQuery),
		IsMySQLDatabase(gH_SQL) ? sWRHolderRankTrackQueryYuck : sWRHolderRankTrackQueryRANK,
		"wrhrankmain", gS_MySQLPrefix, '=');
	hTransaction.AddQuery(sQuery);

	hTransaction.AddQuery("DROP TABLE IF EXISTS wrhrankbonus;");
	FormatEx(sQuery, sizeof(sQuery),
		IsMySQLDatabase(gH_SQL) ? sWRHolderRankTrackQueryYuck : sWRHolderRankTrackQueryRANK,
		"wrhrankbonus", gS_MySQLPrefix, '>');
	hTransaction.AddQuery(sQuery);

	hTransaction.AddQuery("DROP TABLE IF EXISTS wrhrankall;");
	FormatEx(sQuery, sizeof(sQuery),
		IsMySQLDatabase(gH_SQL) ? sWRHolderRankOtherQueryYuck : sWRHolderRankOtherQueryRANK,
		"wrhrankall", gS_MySQLPrefix, "", "", "", "");
	hTransaction.AddQuery(sQuery);

	hTransaction.AddQuery("DROP TABLE IF EXISTS wrhrankcvar;");
	FormatEx(sQuery, sizeof(sQuery),
		IsMySQLDatabase(gH_SQL) ? sWRHolderRankOtherQueryYuck : sWRHolderRankOtherQueryRANK,
		"wrhrankcvar", gS_MySQLPrefix,
		(gCV_MVPRankOnes.IntValue == 2 || gCV_MVPRankOnes_Main.BoolValue) ? "WHERE" : "",
		(gCV_MVPRankOnes.IntValue == 2)  ? "style = 0" : "",
		(gCV_MVPRankOnes.IntValue == 2 && gCV_MVPRankOnes_Main.BoolValue) ? "AND" : "",
		(gCV_MVPRankOnes_Main.BoolValue) ? "track = 0" : "");
	hTransaction.AddQuery(sQuery);

	gH_SQL.Execute(hTransaction, Trans_WRHolderRankTablesSuccess, Trans_WRHolderRankTablesError, 0, DBPrio_High);
}

public void Trans_WRHolderRankTablesSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{	
	char sQuery[1024];
	FormatEx(sQuery, sizeof(sQuery),
		"     SELECT 0 as type, 0 as track, style, COUNT(DISTINCT auth) FROM wrhrankmain GROUP BY STYLE \
		UNION SELECT 0 as type, 1 as track, style, COUNT(DISTINCT auth) FROM wrhrankbonus GROUP BY STYLE \
		UNION SELECT 1 as type, -1 as track, -1 as style, COUNT(DISTINCT auth) FROM wrhrankall \
		UNION SELECT 2 as type, -1 as track, -1 as style, COUNT(DISTINCT auth) FROM wrhrankcvar;");
	gH_SQL.Query(SQL_GetWRHolders_Callback, sQuery);
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
		return gI_WRAmountCvar[client];
	}
	else if (track == -1 && style == -1)
	{
		return gI_WRAmountAll[client];
	}

	if (track > Track_Bonus)
	{
		track = Track_Bonus;
	}

	return gI_WRAmount[client][track][style];
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
		return gI_WRHolderRankCvar[client];
	}
	else if (track == -1 && style == -1)
	{
		return gI_WRHolderRankAll[client];
	}

	if (track > Track_Bonus)
	{
		track = Track_Bonus;
	}

	return gI_WRHolderRank[client][track][style];
}


public int Native_GetMapTier(Handle handler, int numParams)
{
	int tier = 0;

	char sMap[128];
	GetNativeString(1, sMap, 128);

	if(!gA_MapTiers.GetValue(sMap, tier))
	{
		return 0;
	}

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
	char sMap[160];
	GetNativeString(1, sMap, 160);

	char sQuery[256];
	FormatEx(sQuery, 256, "DELETE FROM %smaptiers WHERE map = '%s';", gS_MySQLPrefix, sMap);
	gH_SQL.Query(SQL_DeleteMap_Callback, sQuery, StrEqual(gS_Map, sMap, false), DBPrio_High);
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
		gI_Tier = 1;
		
		UpdateAllPoints(true);
		UpdateRankedPlayers();
	}
}
