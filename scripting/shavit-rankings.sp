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
// Rank 1 per map/style/track gets ((points per tier * tier) * 1.5) + ((amount of records * (tier / 10.0) * 0.25)) + (rank 1 time in seconds / 15.0) points.
// Records below rank 1 get points% relative to their time in comparison to rank 1 and a final multiplier of 0.85% to promote rank 1 hunting.
//
// Bonus track gets a 0.25* final mutliplier for points and is treated as tier 1.
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

#undef REQUIRE_PLUGIN
#include <shavit>

#pragma newdecls required
#pragma semicolon 1

// uncomment when done
// #define DEBUG

char gS_MySQLPrefix[32];
Database gH_SQL = null;	

bool gB_Shavit = false;
bool gB_Stats = false;
bool gB_Late = false;

int gI_Tier = 1; // No floating numbers for tiers, sorry.

char gS_Map[160];
char gS_DisplayMap[128];

int gI_ValidMaps = 0;
ArrayList gA_ValidMaps = null;
StringMap gA_MapTiers = null;

ConVar gCV_PointsPerTier = null;
float gF_PointsPerTier = 50.0;

int gI_Rank[MAXPLAYERS+1];
float gF_Points[MAXPLAYERS+1];

int gI_RankedPlayers = 0;
char gS_Top100_SteamID[100][32];
char gS_Top100_Names[100][MAX_NAME_LENGTH];
char gS_Top100_Points[100][16]; // char[] because of formatting!

// Timer settings.
char gS_ChatStrings[CHATSETTINGS_SIZE][128];
any gA_StyleSettings[STYLE_LIMIT][STYLESETTINGS_SIZE];
int gI_Styles = 0;

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
	CreateNative("Shavit_GetPoints", Native_GetPoints);
	CreateNative("Shavit_GetRank", Native_GetRank);
	CreateNative("Shavit_GetRankedPlayers", Native_GetRankedPlayers);

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
	RegConsoleCmd("sm_tier", Command_Tier, "Prints the map's tier to chat.");
	RegConsoleCmd("sm_maptier", Command_Tier, "Prints the map's tier to chat. (sm_tier alias)");

	RegConsoleCmd("sm_rank", Command_Rank, "Show your or someone else's rank. Usage: sm_rank [name]");
	RegConsoleCmd("sm_top", Command_Top, "Show the top 100 players."); // The rewrite of rankings will not have the ability to show over 100 entries. Dynamic fetching can be exploited and overload the database.

	RegAdminCmd("sm_settier", Command_SetTier, ADMFLAG_RCON, "Change the map's tier. Usage: sm_settier <tier>");
	RegAdminCmd("sm_setmaptier", Command_SetTier, ADMFLAG_RCON, "Prints the map's tier to chat. Usage: sm_setmaptier <tier> (sm_settier alias)");

	RegAdminCmd("sm_recalcmap", Command_RecalcMap, ADMFLAG_RCON, "Recalculate the current map's records' points.");

	gCV_PointsPerTier = CreateConVar("shavit_rankings_pointspertier", "50.0", "Base points to use for per-tier scaling.\nRead the design idea to see how it works: https://github.com/shavitush/bhoptimer/issues/465", 0, true, 1.0);
	gCV_PointsPerTier.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-rankings.phrases");

	// tier cache
	gA_ValidMaps = new ArrayList(128);
	gA_MapTiers = new StringMap();
	
	if(gB_Shavit)
	{
		Shavit_GetDB(gH_SQL);
		SQL_SetPrefix();
		SetSQLInfo();
	}

	if(gB_Late)
	{
		Shavit_OnChatConfigLoaded();
	}
}

public void Shavit_OnChatConfigLoaded()
{
	for(int i = 0; i < CHATSETTINGS_SIZE; i++)
	{
		Shavit_GetChatStrings(i, gS_ChatStrings[i], 128);
	}
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		gI_Styles = Shavit_GetStyleCount();
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		Shavit_GetStyleSettings(i, gA_StyleSettings[i]);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit"))
	{
		gB_Shavit = true;
		
		Shavit_GetDB(gH_SQL);
		SQL_SetPrefix();
		SetSQLInfo();
	}

	else if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit"))
	{
		gB_Shavit = false;
		gH_SQL = null;
	}

	else if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = false;
	}
}

public Action CheckForSQLInfo(Handle Timer)
{
	return SetSQLInfo();
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
		SQL_DBConnect();

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

void SQL_DBConnect()
{
	if(gH_SQL != null)
	{
		// 160 because of mysql limitations
		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "CREATE TABLE IF NOT EXISTS `%smaptiers` (`map` VARCHAR(160), `tier` INT NOT NULL DEFAULT 1, PRIMARY KEY (`map`));", gS_MySQLPrefix);

		gH_SQL.Query(SQL_CreateTable_Callback, sQuery, 0, DBPrio_High);
	}
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings) error! Map tiers table creation failed. Reason: %s", error);

		return;
	}

	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			OnClientConnected(i);
		}
	}
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gF_PointsPerTier = gCV_PointsPerTier.FloatValue;
}

public void OnClientConnected(int client)
{
	gI_Rank[client] = 0;
	gF_Points[client] = 0.0;
}

public void OnClientPostAdminCheck(int client)
{
	if(!IsFakeClient(client))
	{
		UpdatePlayerRank(client);
	}
}

public void OnMapStart()
{
	UpdateRankedPlayers();

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
	}

	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_DisplayMap, 128);

	// Default tier.
	// I won't repeat the same mistake blacky has done with tier 3 being default..
	gI_Tier = 1;

	if(gH_SQL != null)
	{
		char[] sDriver = new char[8];
		gH_SQL.Driver.GetIdentifier(sDriver, 8);
		
		if(!StrEqual(sDriver, "mysql", false))
		{
			SetFailState("Rankings will only support MySQL for the moment. Sorry.");
		}

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "SELECT tier FROM %smaptiers WHERE map = '%s';", gS_MySQLPrefix, gS_Map);
		gH_SQL.Query(SQL_GetMapTier_Callback, sQuery, 0, DBPrio_High);
	}
}

public void SQL_GetMapTier_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, get map tier) error! Reason: %s", error);

		return;
	}

	if(results.RowCount > 0 && results.FetchRow())
	{
		gI_Tier = results.FetchInt(0);

		RecalculateAll(gS_Map, gI_Tier);
		UpdateAllPoints();

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "SELECT map, tier FROM %smaptiers;", gS_MySQLPrefix, gS_Map);
		gH_SQL.Query(SQL_FillTierCache_Callback, sQuery, 0, DBPrio_Low);
	}

	else
	{
		char[] sQuery = new char[256];
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
		char[] sMap = new char[160];
		results.FetchString(0, sMap, 160);

		char[] sDisplayMap = new char[128];
		GetMapDisplayName(sMap, sDisplayMap, 128);

		gA_MapTiers.SetValue(sDisplayMap, results.FetchInt(1));
		gA_ValidMaps.PushString(sDisplayMap);
	}

	gI_ValidMaps = gA_ValidMaps.Length;
	SortADTArray(gA_ValidMaps, Sort_Ascending, Sort_String);
}

void GuessBestMapName(const char[] input, char[] output, int size)
{
	if(gA_ValidMaps.FindString(input) != -1)
	{
		strcopy(output, size, input);

		return;
	}

	char[] sCache = new char[128];

	for(int i = 0; i < gI_ValidMaps; i++)
	{
		gA_ValidMaps.GetString(i, sCache, 128);

		if(StrContains(sCache, input) != -1)
		{
			strcopy(output, size, sCache);

			return;
		}
	}
}

public void OnMapEnd()
{
	RecalculateAll(gS_Map, gI_Tier);
}

public Action Command_Tier(int client, int args)
{
	int tier = gI_Tier;

	char[] sMap = new char[128];
	strcopy(sMap, 128, gS_DisplayMap);

	if(args > 0)
	{
		GetCmdArgString(sMap, 128);
		GuessBestMapName(sMap, sMap, 128);
		
		if(!gA_MapTiers.GetValue(sMap, tier))
		{
			strcopy(sMap, 128, gS_DisplayMap);
		}
	}

	Shavit_PrintToChat(client, "%T", "CurrentTier", client, gS_ChatStrings[sMessageVariable], sMap, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable2], tier, gS_ChatStrings[sMessageText]);

	return Plugin_Handled;
}

public Action Command_Rank(int client, int args)
{
	int target = client;

	if(args > 0)
	{
		char[] sArgs = new char[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		target = FindTarget(client, sArgs, true, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}

	if(gI_Rank[target] == 0)
	{
		Shavit_PrintToChat(client, "%T", "Unranked", client, gS_ChatStrings[sMessageVariable2], target, gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	Shavit_PrintToChat(client, "%T", "Rank", client, gS_ChatStrings[sMessageVariable2], target, gS_ChatStrings[sMessageText],
		gS_ChatStrings[sMessageVariable], gI_Rank[target], gS_ChatStrings[sMessageText],
		gI_RankedPlayers,
		gS_ChatStrings[sMessageVariable], gF_Points[target], gS_ChatStrings[sMessageText]);

	return Plugin_Handled;
}

public Action Command_Top(int client, int args)
{
	Menu menu = new Menu(MenuHandler_Top);
	menu.SetTitle("%T (%d)\n ", "Top100", client, gI_RankedPlayers);

	if(gI_RankedPlayers == 0)
	{
		char[] sDisplay = new char[64];
		FormatEx(sDisplay, 64, "%T", "NoRankedPlayers", client);
		menu.AddItem("-1", sDisplay);
	}

	else
	{
		int ranked = gI_RankedPlayers;

		if(ranked > 100)
		{
			ranked = 100;
		}

		for(int i = 0; i < ranked; i++)
		{
			char[] sDisplay = new char[64];
			FormatEx(sDisplay, 64, "#%d - %s (%s)", (i + 1), gS_Top100_Names[i], gS_Top100_Points[i]);
			menu.AddItem(gS_Top100_SteamID[i], sDisplay);
		}
	}

	menu.ExitButton = true;
	menu.Display(client, 60);

	return Plugin_Handled;
}

public int MenuHandler_Top(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[32];
		menu.GetItem(param2, sInfo, 32);

		if(gB_Stats && !StrEqual(sInfo, "-1"))
		{
			Shavit_OpenStatsMenu(param1, sInfo);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_SetTier(int client, int args)
{
	char[] sArg = new char[8];
	GetCmdArg(1, sArg, 8);
	
	int tier = StringToInt(sArg);

	if(args == 0 || tier < 1 || tier > 10)
	{
		ReplyToCommand(client, "%T", "ArgumentsMissing", client, "sm_settier <tier> (1-10)");

		return Plugin_Handled;
	}

	gI_Tier = tier;

	Shavit_PrintToChat(client, "%T", "SetTier", client, gS_ChatStrings[sMessageVariable2], tier, gS_ChatStrings[sMessageText]);

	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "REPLACE INTO %smaptiers (map, tier) VALUES ('%s', %d);", gS_MySQLPrefix, gS_Map, tier);

	gH_SQL.Query(SQL_SetMapTier_Callback, sQuery, tier, DBPrio_Low);

	return Plugin_Handled;
}

public void SQL_SetMapTier_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, set map tier) error! Reason: %s", error);

		return;
	}

	RecalculateAll(gS_Map, data);
}

public Action Command_RecalcMap(int client, int args)
{
	RecalculateAll(gS_Map, gI_Tier);
	UpdateAllPoints();

	ReplyToCommand(client, "Done.");

	return Plugin_Handled;
}

void RecalculateAll(const char[] map, const int tier)
{
	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		for(int j = 0; j < gI_Styles; j++)
		{
			if(gA_StyleSettings[j][bUnranked])
			{
				continue;
			}

			RecalculateMap(map, i, j, tier);
		}
	}
}

public void Shavit_OnFinish_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int track)
{
	RecalculateMap(gS_Map, track, style, gI_Tier);
}

void RecalculateMap(const char[] map, const int track, const int style, const int tier)
{
	char[] sQuery = new char[2048];
	FormatEx(sQuery, 2048, "UPDATE %splayertimes t LEFT JOIN " ...
		"(SELECT MIN(time) mintime, MAP, track, style FROM %splayertimes GROUP BY MAP, track, style) minjoin " ...
			"ON t.time = minjoin.mintime AND t.MAP = minjoin.MAP AND t.track = minjoin.track AND t.style = minjoin.style " ...
		"JOIN (SELECT ((%.01f * %d) * 1.5) points) best " ...
		"JOIN (SELECT (COUNT(*) * (%d / 10.0)) points, MAP, track, style FROM %splayertimes GROUP BY MAP, track, style) additive " ...
			"ON t.MAP = additive.MAP AND t.track = additive.track AND t.style = additive.style " ...
		"JOIN (SELECT MIN(time) lowest, (MIN(time) / 15.0) points, MAP, track, style FROM %splayertimes GROUP BY MAP, track, style) FINAL " ...
			"ON t.MAP = FINAL.MAP AND t.track = FINAL.track AND t.style = FINAL.style JOIN (SELECT (%.03f) style, (%.03f) track) multipliers " ...

		"SET t.points = (CASE " ...
			"WHEN minjoin.mintime IS NOT NULL THEN (((best.points + additive.points + FINAL.points) * multipliers.style) * multipliers.track) " ...
			"ELSE (((((best.points + additive.points + FINAL.points) * multipliers.style) * multipliers.track) * (FINAL.lowest / t.time)) * 0.85) " ...
		"END) " ...

		"WHERE t.MAP = '%s' " ...
			"AND t.track = %d " ...
			"AND t.style = %d;",
			gS_MySQLPrefix, gS_MySQLPrefix,
			gF_PointsPerTier, (track == Track_Main)? tier:1, (track == Track_Main)? tier:1,
			gS_MySQLPrefix, gS_MySQLPrefix,
			gA_StyleSettings[style][fRankingMultiplier], (track == Track_Main)? 1.0:0.25,
			map, track, style);

	gH_SQL.Query(SQL_Recalculate_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_Recalculate_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, recalculate map points) error! Reason: %s", error);

		return;
	}
}

void UpdatePlayerPoints(int client)
{
	char[] sAuthID = new char[32];

	if(GetClientAuthId(client, AuthId_Steam3, sAuthID, 32))
	{
		char[] sQuery = new char[512];
		FormatEx(sQuery, 512, "UPDATE %susers u JOIN (SELECT SUM(fPoints) total FROM(SELECT (points * (@f := 0.975 * @f) / 0.975) fPoints " ...
			"FROM %splayertimes t CROSS JOIN (SELECT @f := 1.0) params WHERE points > 0.0 AND auth = '%s' ORDER BY points DESC) f) temp " ...
			"SET u.points = temp.total WHERE auth = '%s';",
			gS_MySQLPrefix, gS_MySQLPrefix, sAuthID, sAuthID);

		gH_SQL.Query(SQL_UpdatePlayerPoints_Callback, sQuery, GetClientSerial(client), DBPrio_Low);
	}
}

public void SQL_UpdatePlayerPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update player points) error! Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client != 0)
	{
		UpdatePlayerRank(client);
	}

	UpdateRankedPlayers();
}

// this takes a while, needs to be ran manually or on map start, in a transaction
void UpdateAllPoints()
{
	char[] sQuery = new char[128];
	FormatEx(sQuery, 128, "SELECT auth FROM %splayertimes WHERE points > 0.0 GROUP BY auth;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_UpdateAllPoints_Callback, sQuery, 0, DBPrio_Low);
}

public void SQL_UpdateAllPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update all points) error! Reason: %s", error);

		return;
	}

	StringMap auths = new StringMap();

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i))
		{
			continue;
		}

		char[] sAuthID = new char[32];

		if(GetClientAuthId(i, AuthId_Steam3, sAuthID, 32))
		{
			auths.SetValue(sAuthID, i);
		}
	}

	Transaction trans = new Transaction();

	#if defined DEBUG
	LogError("start: %f", GetEngineTime());
	#endif

	if(results.RowCount > 0)
	{
		while(results.FetchRow())
		{
			char[] sAuthID = new char[32];
			results.FetchString(0, sAuthID, 32);

			int client = 0;

			if(auths.GetValue(sAuthID, client))
			{
				UpdatePlayerPoints(client);

				continue;
			}

			char[] sQuery = new char[512];
			FormatEx(sQuery, 512, "UPDATE %susers u JOIN (SELECT SUM(fPoints) total FROM(SELECT (points * (@f := 0.975 * @f) / 0.975) fPoints " ...
				"FROM %splayertimes t CROSS JOIN (SELECT @f := 1.0) params WHERE t.points > 0.0 AND t.auth = '%s' ORDER BY points DESC) f) temp " ...
				"SET u.points = temp.total WHERE u.auth = '%s';",
				gS_MySQLPrefix, gS_MySQLPrefix, sAuthID, sAuthID);

			trans.AddQuery(sQuery);
		}
	}

	delete auths;

	#if defined DEBUG
	LogError("start: %f", GetEngineTime());
	#endif

	gH_SQL.Execute(trans, SQL_OnSuccess, SQL_OnFailure);
}

public void SQL_OnSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	UpdateRankedPlayers();

	#if defined DEBUG
	LogError("end (success): %f", GetEngineTime());
	#endif
}

public void SQL_OnFailure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Transaction query (%d): %s", failIndex, error);

	#if defined DEBUG
	LogError("end (fail): %f", GetEngineTime());
	#endif
}

void UpdatePlayerRank(int client)
{
	gI_Rank[client] = 0;
	gF_Points[client] = 0.0;

	char[] sAuthID = new char[32];

	if(GetClientAuthId(client, AuthId_Steam3, sAuthID, 32))
	{
		char[] sQuery = new char[512];
		FormatEx(sQuery, 512, "SELECT COUNT(*) rank, points FROM %susers WHERE points >= (SELECT points FROM %susers WHERE auth = '%s' LIMIT 1) ORDER BY points DESC LIMIT 1;",
			gS_MySQLPrefix, gS_MySQLPrefix, sAuthID);

		gH_SQL.Query(SQL_UpdatePlayerRank_Callback, sQuery, GetClientSerial(client), DBPrio_Low);
	}
}

public void SQL_UpdatePlayerRank_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update player rank) error! Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		gI_Rank[client] = results.FetchInt(0);
		gF_Points[client] = results.FetchFloat(1);
	}
}

void UpdateRankedPlayers()
{
	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "SELECT COUNT(*) count FROM %susers WHERE points > 0.0;", gS_MySQLPrefix);
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
	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "SELECT auth, name, CAST(points AS DECIMAL(18, 2)) points FROM %susers WHERE points > 0.0 ORDER BY points DESC LIMIT 100;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_UpdateTop100_Callback, sQuery, 0, DBPrio_Low);
}

public void SQL_UpdateTop100_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update top 100) error! Reason: %s", error);

		return;
	}

	int row = 0;

	while(results.FetchRow())
	{
		results.FetchString(0, gS_Top100_SteamID[row], 32);
		results.FetchString(1, gS_Top100_Names[row], MAX_NAME_LENGTH);
		results.FetchString(2, gS_Top100_Points[row++], 16);
	}
}

public int Native_GetPoints(Handle handler, int numParams)
{
	return view_as<int>(gF_Points[GetNativeCell(1)]);
}

public int Native_GetRank(Handle handler, int numParams)
{
	return gI_Rank[GetNativeCell(1)];
}

public int Native_GetRankedPlayers(Handle handler, int numParams)
{
	return gI_RankedPlayers;
}
