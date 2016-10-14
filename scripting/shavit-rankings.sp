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
#include <shavit>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

// #define DEBUG

// forwards
Handle gH_Forwards_OnRankUpdated = null;

// cache
char gS_Map[256];
int gI_RankedPlayers = 0;

char gS_CachedMap[MAXPLAYERS+1][192];
float gF_MapTier = 1.0;
bool gB_ChatMessage[MAXPLAYERS+1];

float gF_PlayerPoints[MAXPLAYERS+1];
int gI_PlayerRank[MAXPLAYERS+1];

bool gB_CheckRankedPlayers = false;

bool gB_Late = false;

// convars
ConVar gCV_TopAmount = null;
ConVar gCV_TiersDB = null;
ConVar gCV_PointsPerTier = null;
ConVar gCV_PlayersToCalculate = null;

// cached cvars
int gI_TopAmount = 100;
bool gB_TiersDB = false;
float gF_PointsPerTier = 25.0;
int gI_PlayersToCalculate = -1;

// database handles
Database gH_SQL = null;
Database gH_Tiers = null;
bool gB_MySQL = false;
bool gB_TiersTable = false;

// table prefix
char gS_MySQLPrefix[32];

// modules
bool gB_Stats = false;

// timer settings
int gI_Styles = 0;
any gA_StyleSettings[STYLE_LIMIT][STYLESETTINGS_SIZE];

// chat settings
char gS_ChatStrings[CHATSETTINGS_SIZE][128];

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
	// forwards
	gH_Forwards_OnRankUpdated = CreateGlobalForward("Shavit_OnRankUpdated", ET_Event, Param_Cell);

	// player commands
	RegConsoleCmd("sm_points", Command_Points, "Prints the points you will get for a time on the default style.");
	RegConsoleCmd("sm_rank", Command_Rank, "Shows your current rank.");
	RegConsoleCmd("sm_prank", Command_Rank, "Shows your current rank. (sm_rank alias)");
	RegConsoleCmd("sm_top", Command_Top, "Shows the top players menu.");
	RegConsoleCmd("sm_ptop", Command_Top, "Shows the top players menu. (sm_top alias)");
	RegConsoleCmd("sm_tier", Command_Tier, "Prints the map's tier to chat.");
	RegConsoleCmd("sm_maptier", Command_Tier, "Prints the map's tier to chat. (sm_tier alias)");

	// admin commands
	RegAdminCmd("sm_settier", Command_SetTier, ADMFLAG_ROOT, "Set map tier. Has no effect except for sm_tier output or message upon connection.");
	RegAdminCmd("sm_setmaptier", Command_SetTier, ADMFLAG_ROOT, "Set map tier. Has no effect except for sm_tier output or message upon connection. (sm_settier alias)");

	// translations
	LoadTranslations("common.phrases");

	// cvars
	gCV_TopAmount = CreateConVar("shavit_rankings_topamount", "100", "Amount of people to show within the sm_top menu.", 0, true, 1.0, false);
	gCV_TiersDB = CreateConVar("shavit_rankings_tiersdb", "0", "If set to 1, use the `shavit` database to store map tiers.\nOtherwise, use a local SQLite database for them.", 0, true, 0.0, true, 1.0);
	gCV_PointsPerTier = CreateConVar("shavit_rankings_pointspertier", "25", "Points for default style's WR per map tier.\nFor example: if you set this value to 50 and you get a #1 Normal record, you will receive 50 points and players below you will receive less.\nIf a map has no tier set, it will reward as if it's tier 1.", 0, true, 1.0);
	gCV_PlayersToCalculate = CreateConVar("shavit_rankings_playerstocalculate", "-1", "(MySQL only!) Amount of players to have their points re-calculated per new map.\nSet to -1 if you want it to use the value of \"shavit_rankings_topamount\".", 0, true, -1.0, true, 250.0);

	gCV_TopAmount.AddChangeHook(OnConVarChanged);
	gCV_TiersDB.AddChangeHook(OnConVarChanged);
	gCV_PointsPerTier.AddChangeHook(OnConVarChanged);
	gCV_PlayersToCalculate.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	// database connections
	Shavit_GetDB(gH_SQL);
	SQL_SetPrefix();
	SetSQLInfo();

	// modules
	gB_Stats = LibraryExists("shavit-stats");
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gI_TopAmount = gCV_TopAmount.IntValue;
	gB_TiersDB = gCV_TiersDB.BoolValue;
	gF_PointsPerTier = gCV_PointsPerTier.FloatValue;
	gI_PlayersToCalculate = gCV_PlayersToCalculate.IntValue;
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

public void OnClientAuthorized(int client, const char[] auth)
{
	gB_ChatMessage[client] = false;
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	gF_PlayerPoints[client] = -1.0;
	gI_PlayerRank[client] = -1;

	if(!gB_ChatMessage[client])
	{
		CreateTimer(5.0, Timer_PrintTier, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);

		gB_ChatMessage[client] = true;
	}

	if(gH_SQL != null && gH_Tiers != null)
	{
		UpdatePlayerRank(client);
	}
}

void UpdatePointsToDatabase(int client)
{
	char[] sAuthID3 = new char[32];

	if(GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
	{
		char[] sQuery = new char[128];
		FormatEx(sQuery, 128, "SELECT points FROM %susers WHERE auth = '%s' LIMIT 1;", gS_MySQLPrefix, sAuthID3);

		gH_SQL.Query(SQL_GetUserPoints_Callback, sQuery, GetClientSerial(client), DBPrio_Low);
	}
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

		UpdatePlayerPoints(client);
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

	if(client == 0 || gF_MapTier == -1.0)
	{
		return Plugin_Stop;
	}

	char[] sDisplayMap = new char[strlen(gS_Map) + 1];
	GetMapDisplayName(gS_Map, sDisplayMap, strlen(gS_Map) + 1);

	Shavit_PrintToChat(client, "%s%s%s is rated %stier %.01f%s.", gS_ChatStrings[sMessageVariable2], sDisplayMap, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable2], gF_MapTier, gS_ChatStrings[sMessageText]);

	return Plugin_Stop;
}

public void OnMapStart()
{
	gF_MapTier = -1.0;
	gB_CheckRankedPlayers = false;

	GetCurrentMap(gS_Map, 256);

	if(gH_Tiers != null && gB_TiersTable)
	{
		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "SELECT tier FROM %smaptiers WHERE map = '%s';", gS_MySQLPrefix, gS_Map);

		gH_Tiers.Query(SQL_SetTierCache_Callback, sQuery, 0, DBPrio_High);
	}

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
		Shavit_OnChatConfigLoaded();
	}
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
		gF_MapTier = results.FetchFloat(0);
	}

	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "SELECT auth FROM %susers ORDER BY points DESC LIMIT %d;", gS_MySQLPrefix, (gI_PlayersToCalculate == -1)? gI_TopAmount:gI_PlayersToCalculate);

	gH_SQL.Query(SQL_RecalculatePoints_Callback, sQuery);
}

public void SQL_RecalculatePoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error on RecalculatePoints. Reason: %s", error);

		return;
	}

	while(results.FetchRow())
	{
		char[] sAuthID = new char[32];
		results.FetchString(0, sAuthID, 32);

		int iSerial = 0;
		char[] sTempAuthID = new char[32];

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i) && GetClientAuthId(i, AuthId_Steam3, sTempAuthID, 32) && StrEqual(sTempAuthID, sAuthID))
			{
				iSerial = GetClientSerial(i);

				break;
			}
		}

		WeighPoints(sAuthID, iSerial);
	}
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleSettings(view_as<BhopStyle>(i), gA_StyleSettings[i]);
	}

	gI_Styles = styles;
}

public void Shavit_OnChatConfigLoaded()
{
	for(int i = 0; i < CHATSETTINGS_SIZE; i++)
	{
		Shavit_GetChatStrings(i, gS_ChatStrings[i], 128);
	}
}

public Action Command_Points(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char[] sDisplayMap = new char[strlen(gS_Map) + 1];
	GetMapDisplayName(gS_Map, sDisplayMap, strlen(gS_Map) + 1);

	float fWRTime = 0.0;
	Shavit_GetWRTime(view_as<BhopStyle>(0), fWRTime);

	if(fWRTime < 0.0)
	{
		Shavit_PrintToChat(client, "%s%s%s: Unknown points, no records on map.", gS_ChatStrings[sMessageVariable], sDisplayMap, gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	float fTier = gF_MapTier;

	if(fTier == -1.0)
	{
		fTier = 1.0;
	}

	char[] sTime = new char[32];
	FormatSeconds(fWRTime, sTime, 32, false);

	Shavit_PrintToChat(client, "%s%s%s: Around %s%.01f%s points for a time of %s%s%s.", gS_ChatStrings[sMessageVariable], sDisplayMap, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable2], (fTier * gF_PointsPerTier), gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], sTime, gS_ChatStrings[sMessageText]);

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

	if(gI_PlayerRank[target] <= 0)
	{
		Shavit_PrintToChat(client, "%s%N%s is %sunranked%s.", gS_ChatStrings[sMessageVariable2], target, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

		return Plugin_Handled;
	}

	Shavit_PrintToChat(client, "%s%N%s is ranked %s%d%s out of %s%d%s with %s%.02f points%s.", gS_ChatStrings[sMessageVariable2], target, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], gI_PlayerRank[target], gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], gI_RankedPlayers, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], gF_PlayerPoints[target], gS_ChatStrings[sMessageText]);

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

Action ShowTopMenu(int client)
{
	char[] sQuery = new char[192];
	FormatEx(sQuery, 192, "SELECT name, %s points, auth FROM %susers WHERE points > 0.0 ORDER BY points DESC LIMIT %d;", gB_MySQL? "FORMAT(points, 2)":"points", gS_MySQLPrefix, gI_TopAmount);

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
	m.SetTitle("Top %d Players", gI_TopAmount);

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

			char[] sAuthID = new char[32];
			results.FetchString(2, sAuthID, 32);

			m.AddItem(sAuthID, sDisplay);
		}
	}

	m.ExitButton = true;

	m.Display(client, 20);
}

public int MenuHandler_TopMenu(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select && gB_Stats)
	{
		char[] sInfo = new char[32];
		m.GetItem(param2, sInfo, 32);

		if(StringToInt(sInfo) != -1)
		{
			Shavit_OpenStatsMenu(param1, sInfo);
		}
	}

	else if(action == MenuAction_End)
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

		if(gF_MapTier != -1)
		{
			Shavit_PrintToChat(client, "%s%s%s is rated %stier %.01f%s.", gS_ChatStrings[sMessageVariable], sDisplayMap, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable2], gF_MapTier, gS_ChatStrings[sMessageText]);
		}

		else
		{
			Shavit_PrintToChat(client, "%s%s%s is not rated.", gS_ChatStrings[sMessageVariable], sDisplayMap, gS_ChatStrings[sMessageText]);
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

		Shavit_PrintToChat(client, "%s%s%s is rated %stier %.01f%s.", gS_ChatStrings[sMessageVariable], sDisplayMap, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable2], results.FetchFloat(1), gS_ChatStrings[sMessageText]);
	}

	else
	{
		Shavit_PrintToChat(client, "Couldn't find map tier for %s%s%s.", gS_ChatStrings[sMessageVariable], gS_CachedMap[client], gS_ChatStrings[sMessageText]);
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

	float fTier = StringToFloat(sArg1);

	if(fTier < 0)
	{
		ReplyToCommand(client, "Invalid map tier (%.01f)!", fTier);

		return Plugin_Handled;
	}

	gF_MapTier = fTier;

	ReplyToCommand(client, "Map tier is now %.01f.", fTier);

	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "REPLACE INTO %smaptiers (map, tier) VALUES ('%s', %.1f);", gS_MySQLPrefix, gS_Map, fTier);
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

	UpdateRecordPoints();
}

void UpdateRecordPoints()
{
	if(gF_MapTier == -1.0)
	{
		return;
	}

	float fTier = gF_MapTier;

	if(fTier < 0.0)
	{
		fTier = -fTier;
	}

	float fDefaultWR = 0.0;
	Shavit_GetWRTime(view_as<BhopStyle>(0), fDefaultWR);

	char[] sQuery = new char[512];

	for(int i = 0; i < gI_Styles; i++)
	{
		if(gA_StyleSettings[i][bUnranked])
		{
			continue;
		}

		float fStyleWR = 0.0;
		Shavit_GetWRTime(view_as<BhopStyle>(i), fStyleWR);

		float fMeasureTime = 0.0;

		if(fDefaultWR <= 0.0)
		{
			if(fStyleWR <= 0.0)
			{
				continue;
			}

			else
			{
				fMeasureTime = fStyleWR;
			}
		}

		else
		{
			fMeasureTime = fDefaultWR;
		}

		FormatEx(sQuery, 512, "UPDATE %splayertimes SET points = ((%.02f / time) * %.02f) WHERE map = '%s' AND style = %d;", gS_MySQLPrefix, fMeasureTime, ((fTier * gF_PointsPerTier) * view_as<float>(gA_StyleSettings[i][fRankingMultiplier])), gS_Map, i);
		gH_SQL.Query(SQL_UpdateRecords_Callback, sQuery, 0, DBPrio_Low);
	}
}

public void SQL_UpdateRecords_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! Update record points failed. Reason: %s", error);

		return;
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			UpdatePlayerPoints(i);
		}
	}
}

void WeighPoints(const char[] auth, int serial)
{
	if(!gB_MySQL)
	{
		return;
	}

	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "UPDATE %susers SET points = (SELECT (points * (@f := 0.98 * @f) / 0.98) sumpoints FROM %splayertimes pt CROSS JOIN (SELECT @f := 1.0) params WHERE auth = '%s' AND points > 0.0 ORDER BY points DESC LIMIT 1) WHERE auth = '%s';", gS_MySQLPrefix, gS_MySQLPrefix, auth, auth);

	gH_SQL.Query(SQL_WeighPoints_Callback, sQuery, serial, DBPrio_Low);
}

public void SQL_WeighPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings module) error! Weighing of points failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client != 0)
	{
		UpdatePlayerPoints(client);
	}
}

#if defined DEBUG
float CalculatePoints(float time, BhopStyle style, float tier)
{
	float fWRTime = 0.0;
	Shavit_GetWRTime(view_as<BhopStyle>(0), fWRTime);

	if(tier <= 0.0 || fWRTime <= 0.0)
	{
		return gF_PointsPerTier;
	}

	return (((fWRTime / time) * (tier * gF_PointsPerTier)) * view_as<float>(gA_StyleSettings[style][fRankingMultiplier]));
}
#endif

public void Shavit_OnFinish_Post(int client, BhopStyle style, float time, int jumps, int strafes, float sync, int rank)
{
	#if defined DEBUG
	Shavit_PrintToChat(client, "Points: %.02f", CalculatePoints(time, style, gF_IdealTime, gF_MapPoints));
	#endif

	UpdateRecordPoints();
}

void UpdatePlayerPoints(int client)
{
	if(!IsClientAuthorized(client))
	{
		return;
	}

	char[] sAuthID = new char[32];
	GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

	char[] sQuery = new char[256];
	FormatEx(sQuery, 256, "SELECT points FROM %splayertimes WHERE auth = '%s' AND points > 0.0 ORDER BY points DESC;", gS_MySQLPrefix, sAuthID);
	gH_SQL.Query(SQL_UpdatePoints_Callback, sQuery, GetClientSerial(client), DBPrio_Low);
}

// would completely deprecate this if we weren't SQLite compatible
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
		gF_PlayerPoints[client] = fPoints;

		char[] sAuthID3 = new char[32];

		if(GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
		{
			char[] sQuery = new char[256];
			FormatEx(sQuery, 256, "UPDATE %susers SET points = '%.02f' WHERE auth = '%s';", gS_MySQLPrefix, fPoints, sAuthID3);

			gH_SQL.Query(SQL_UpdatePointsTable_Callback, sQuery, 0, DBPrio_Low);
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

	int client = GetClientFromSerial(data);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			UpdatePlayerRank(client);
		}
	}
}

void UpdatePlayerRank(int client)
{
	if(!IsValidClient(client) || gH_SQL == null)
	{
		return;
	}

	char[] sAuthID3 = new char[32];

	if(GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
	{
		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "SELECT COUNT(*) rank, points FROM %susers WHERE points >= (SELECT points FROM %susers WHERE auth = '%s' LIMIT 1) ORDER BY points DESC LIMIT 1;", gS_MySQLPrefix, gS_MySQLPrefix, sAuthID3);

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

	if(results.FetchRow() && results.FetchFloat(1) > 0.0)
	{
		gI_PlayerRank[client] = results.FetchInt(0);

		UpdatePointsToDatabase(client);

		Call_StartForward(gH_Forwards_OnRankUpdated);
		Call_PushCell(client);
		Call_Finish();

		if(!gB_CheckRankedPlayers)
		{
			UpdateRankedPlayers();

			gB_CheckRankedPlayers = true;
		}
	}

	else
	{
		gI_PlayerRank[client] = 0;
	}
}

void UpdateRankedPlayers()
{
	char[] sQuery = new char[128];
	FormatEx(sQuery, 128, "SELECT COUNT(*) FROM %susers WHERE points > 0.0 LIMIT 1;", gS_MySQLPrefix);
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

	gB_CheckRankedPlayers = false;
}

public void Shavit_OnWRDeleted()
{
	UpdateRecordPoints();
}

public int Native_GetPoints(Handle handler, int numParams)
{
	return view_as<int>(gF_PlayerPoints[GetNativeCell(1)]);
}

public int Native_GetRank(Handle handler, int numParams)
{
	return gI_PlayerRank[GetNativeCell(1)];
}

public int Native_GetRankedPlayers(Handle handler, int numParams)
{
	return gI_RankedPlayers;
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

void SQL_DBConnect()
{
	if(gH_SQL != null)
	{
		char[] sError = new char[255];

		if(gB_TiersDB)
		{
			gH_Tiers = gH_SQL;
		}

		else
		{
			gH_Tiers = SQLite_UseDatabase("shavit-tiers", sError, 255);

			if(gH_Tiers == null)
			{
				LogError("Cannot start `shavit-tiers` SQLite table. %s", sError);

				return;
			}
		}

		char[] sDriver = new char[8];
		gH_SQL.Driver.GetIdentifier(sDriver, 8);
		gB_MySQL = StrEqual(sDriver, "mysql", false);

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "CREATE TABLE IF NOT EXISTS `%smaptiers` (`map` VARCHAR(192), `tier` FLOAT, PRIMARY KEY (`map`));", gS_MySQLPrefix);

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

	gB_TiersTable = true;

	OnMapStart();
}

public void Shavit_OnDatabaseLoaded(Database db)
{
	gH_SQL = db;
}
