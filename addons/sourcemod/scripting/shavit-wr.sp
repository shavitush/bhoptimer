/*
 * shavit's Timer - World Records
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
#include <convar_class>
#include <dhooks>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <adminmenu>

#pragma newdecls required
#pragma semicolon 1

// #define DEBUG

enum struct wrcache_t
{
	int iLastStyle;
	int iLastTrack;
	int iPagePosition;
	bool bForceStyle;
	bool bPendingMenu;
	char sClientMap[PLATFORM_MAX_PATH];
	float fWRs[STYLE_LIMIT];
}

enum struct stagetimewrcp_t
{
	float fTime;
	int iAuth;
}

bool gB_Late = false;
bool gB_Rankings = false;
bool gB_Stats = false;

// forwards
Handle gH_OnWorldRecord = null;
Handle gH_OnFinish_Post = null;
Handle gH_OnWRDeleted = null;
Handle gH_OnWorstRecord = null;
Handle gH_OnFinishMessage = null;

// database handle
Database2 gH_SQL = null;
bool gB_Connected = false;
bool gB_MySQL = false;

// cache
wrcache_t gA_WRCache[MAXPLAYERS+1];
StringMap gSM_StyleCommands = null;

char gS_Map[PLATFORM_MAX_PATH];
ArrayList gA_ValidMaps = null;

// current wr stats
float gF_WRTime[STYLE_LIMIT][TRACKS_SIZE];
int gI_WRRecordID[STYLE_LIMIT][TRACKS_SIZE];
int gI_WRSteamID[STYLE_LIMIT][TRACKS_SIZE];
StringMap gSM_WRNames = null;
ArrayList gA_Leaderboard[STYLE_LIMIT][TRACKS_SIZE];
bool gB_LoadedCache[MAXPLAYERS+1];
float gF_PlayerRecord[MAXPLAYERS+1][STYLE_LIMIT][TRACKS_SIZE];
int gI_PlayerCompletion[MAXPLAYERS+1][STYLE_LIMIT][TRACKS_SIZE];

// admin menu
TopMenu gH_AdminMenu = null;
TopMenuObject gH_TimerCommands = INVALID_TOPMENUOBJECT;

// table prefix
char gS_MySQLPrefix[32];

// cvars
Convar gCV_RecordsLimit = null;
Convar gCV_RecentLimit = null;

// timer settings
int gI_Styles = 0;
stylestrings_t gS_StyleStrings[STYLE_LIMIT];

// chat settings
chatstrings_t gS_ChatStrings;

// stage times (wrs/pbs)
float gA_StageWR[STYLE_LIMIT][TRACKS_SIZE][MAX_STAGES]; // WR run's stage times
//stagetimewrcp_t gA_StageWRCP[STYLE_LIMIT][TRACKS_SIZE];
ArrayList gA_StagePB[MAXPLAYERS+1][STYLE_LIMIT][TRACKS_SIZE]; // player's best WRCP times or something
float gA_StageTimes[MAXPLAYERS+1][MAX_STAGES]; // player's current run stage times

public Plugin myinfo =
{
	name = "[shavit] World Records",
	author = "shavit",
	description = "World records for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// natives
	CreateNative("Shavit_GetClientPB", Native_GetClientPB);
	CreateNative("Shavit_SetClientPB", Native_SetClientPB);
	CreateNative("Shavit_GetClientCompletions", Native_GetClientCompletions);
	CreateNative("Shavit_GetRankForTime", Native_GetRankForTime);
	CreateNative("Shavit_GetRecordAmount", Native_GetRecordAmount);
	CreateNative("Shavit_GetTimeForRank", Native_GetTimeForRank);
	CreateNative("Shavit_GetWorldRecord", Native_GetWorldRecord);
	CreateNative("Shavit_GetWRName", Native_GetWRName);
	CreateNative("Shavit_GetWRRecordID", Native_GetWRRecordID);
	CreateNative("Shavit_ReloadLeaderboards", Native_ReloadLeaderboards);
	CreateNative("Shavit_WR_DeleteMap", Native_WR_DeleteMap);
	CreateNative("Shavit_DeleteWR", Native_DeleteWR);
	CreateNative("Shavit_GetStageWR", Native_GetStageWR);
	CreateNative("Shavit_GetStagePB", Native_GetStagePB);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-wr");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-wr.phrases");

	#if defined DEBUG
	RegConsoleCmd("sm_junk", Command_Junk);
	RegConsoleCmd("sm_printleaderboards", Command_PrintLeaderboards);
	#endif

	gSM_WRNames = new StringMap();
	gSM_StyleCommands = new StringMap();

	// forwards
	gH_OnWorldRecord = CreateGlobalForward("Shavit_OnWorldRecord", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnFinish_Post = CreateGlobalForward("Shavit_OnFinish_Post", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnWRDeleted = CreateGlobalForward("Shavit_OnWRDeleted", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_String);
	gH_OnWorstRecord = CreateGlobalForward("Shavit_OnWorstRecord", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnFinishMessage = CreateGlobalForward("Shavit_OnFinishMessage", ET_Event, Param_Cell, Param_CellByRef, Param_Array, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_String, Param_Cell);

	// player commands
	RegConsoleCmd("sm_wr", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_wr [map]");
	RegConsoleCmd("sm_worldrecord", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_worldrecord [map]");

	RegConsoleCmd("sm_bwr", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_bwr [map] [bonus number]");
	RegConsoleCmd("sm_bworldrecord", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_bworldrecord [map] [bonus number]");
	RegConsoleCmd("sm_bonusworldrecord", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_bonusworldrecord [map] [bonus number]");

	RegConsoleCmd("sm_recent", Command_RecentRecords, "View the recent #1 times set.");
	RegConsoleCmd("sm_recentrecords", Command_RecentRecords, "View the recent #1 times set.");
	RegConsoleCmd("sm_rr", Command_RecentRecords, "View the recent #1 times set.");

	// delete records
	RegAdminCmd("sm_delete", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface.");
	RegAdminCmd("sm_deleterecord", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface.");
	RegAdminCmd("sm_deleterecords", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface.");
	RegAdminCmd("sm_deleteall", Command_DeleteAll, ADMFLAG_RCON, "Deletes all the records for this map.");

	// cvars
	gCV_RecordsLimit = new Convar("shavit_wr_recordlimit", "50", "Limit of records shown in the WR menu.\nAdvised to not set above 1,000 because scrolling through so many pages is useless.\n(And can also cause the command to take long time to run)", 0, true, 1.0);
	gCV_RecentLimit = new Convar("shavit_wr_recentlimit", "50", "Limit of records shown in the RR menu.", 0, true, 1.0);

	Convar.AutoExecConfig();

	// modules
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_Stats = LibraryExists("shavit-stats");

	// cache
	gA_ValidMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount());
		Shavit_OnChatConfigLoaded();
		Shavit_OnDatabaseLoaded();
	}

	CreateTimer(2.5, Timer_Dominating, 0, TIMER_REPEAT);
}

public void OnAllPluginsLoaded()
{
	// admin menu
	if(LibraryExists("adminmenu") && ((gH_AdminMenu = GetAdminTopMenu()) != null))
	{
		OnAdminMenuReady(gH_AdminMenu);
	}
}

public void OnAdminMenuCreated(Handle topmenu)
{
	if(gH_AdminMenu == null || (topmenu == gH_AdminMenu && gH_TimerCommands != INVALID_TOPMENUOBJECT))
	{
		return;
	}

	gH_TimerCommands = gH_AdminMenu.AddCategory("Timer Commands", CategoryHandler, "shavit_admin", ADMFLAG_RCON);
}

public void CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayTitle)
	{
		FormatEx(buffer, maxlength, "%T:", "TimerCommands", param);
	}

	else if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "TimerCommands", param);
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	if((gH_AdminMenu = GetAdminTopMenu()) != null)
	{
		if(gH_TimerCommands == INVALID_TOPMENUOBJECT)
		{
			gH_TimerCommands = gH_AdminMenu.FindCategory("Timer Commands");

			if(gH_TimerCommands == INVALID_TOPMENUOBJECT)
			{
				OnAdminMenuCreated(topmenu);
			}
		}

		gH_AdminMenu.AddItem("sm_deleteall", AdminMenu_DeleteAll, gH_TimerCommands, "sm_deleteall", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_delete", AdminMenu_Delete, gH_TimerCommands, "sm_delete", ADMFLAG_RCON);
	}
}

public void AdminMenu_Delete(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%t", "DeleteSingleRecord");
	}

	else if(action == TopMenuAction_SelectOption)
	{
		Command_Delete(param, 0);
	}
}

public void AdminMenu_DeleteAll(Handle topmenu,  TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%t", "DeleteAllRecords");
	}

	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteAll(param, 0);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}

	else if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = true;
	}

	else if (StrEqual(name, "adminmenu"))
	{
		if ((gH_AdminMenu = GetAdminTopMenu()) != null)
		{
			OnAdminMenuReady(gH_AdminMenu);
		}
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}

	else if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = false;
	}

	else if (StrEqual(name, "adminmenu"))
	{
		gH_AdminMenu = null;
		gH_TimerCommands = INVALID_TOPMENUOBJECT;
	}
}

public Action Timer_Dominating(Handle timer)
{
	bool bHasWR[MAXPLAYERS+1];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			char sSteamID[20];
			IntToString(GetSteamAccountID(i), sSteamID, sizeof(sSteamID));
			bHasWR[i] = gSM_WRNames.GetString(sSteamID, sSteamID, sizeof(sSteamID));
		}
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
		{
			continue;
		}

		for (int x = 1; x <= MaxClients; x++)
		{
			SetEntProp(i, Prop_Send, "m_bPlayerDominatingMe", bHasWR[x], 1, x);
		}
	}
}

void ResetWRs()
{
	gSM_WRNames.Clear();

	any empty_cells[TRACKS_SIZE];

	for(int i = 0; i < gI_Styles; i++)
	{
		gF_WRTime[i] = empty_cells;
		gI_WRRecordID[i] = empty_cells;
		gI_WRSteamID[i] = empty_cells;
	}
}

void ResetLeaderboards()
{
	for(int i = 0; i < gI_Styles; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gA_Leaderboard[i][j].Clear();
		}
	}
}

public void OnMapStart()
{
	if(!gB_Connected)
	{
		return;
	}

	GetLowercaseMapName(gS_Map);

	UpdateWRCache();

	gA_ValidMaps.Clear();
	gA_ValidMaps.PushString(gS_Map);

	char sQuery[128];
	FormatEx(sQuery, 128, "SELECT map FROM %smapzones GROUP BY map;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_UpdateMaps_Callback, sQuery, 0, DBPrio_Low);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && IsClientAuthorized(i))
		{
			OnClientAuthorized(i, "");
		}
	}
}

public void OnMapEnd()
{
	ResetWRs();
}

public void SQL_UpdateMaps_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR maps cache update) SQL query failed. Reason: %s", error);

		return;
	}

	while(results.FetchRow())
	{
		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(0, sMap, sizeof(sMap));
		LowercaseString(sMap);

		if(gA_ValidMaps.FindString(sMap) == -1)
		{
			gA_ValidMaps.PushString(sMap);
		}
	}

	SortADTArray(gA_ValidMaps, Sort_Ascending, Sort_String);
}

void RegisterWRCommands(int style)
{
	char sStyleCommands[32][32];
	int iCommands = ExplodeString(gS_StyleStrings[style].sChangeCommand, ";", sStyleCommands, 32, 32, false);

	char sDescription[128];
	FormatEx(sDescription, 128, "View the leaderboard of a map on style %s.", gS_StyleStrings[style].sStyleName);

	for (int x = 0; x < iCommands; x++)
	{
		TrimString(sStyleCommands[x]);
		StripQuotes(sStyleCommands[x]);

		if (strlen(sStyleCommands[x]) < 1)
		{
			continue;
		}


		char sCommand[40];
		FormatEx(sCommand, sizeof(sCommand), "sm_wr%s", sStyleCommands[x]);
		gSM_StyleCommands.SetValue(sCommand, style);
		RegConsoleCmd(sCommand, Command_WorldRecord_Style, sDescription);

		FormatEx(sCommand, sizeof(sCommand), "sm_bwr%s", sStyleCommands[x]);
		gSM_StyleCommands.SetValue(sCommand, style);
		RegConsoleCmd(sCommand, Command_WorldRecord_Style, sDescription);
	}
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	for(int i = 0; i < STYLE_LIMIT; i++)
	{
		if (i < styles)
		{
			Shavit_GetStyleStringsStruct(i, gS_StyleStrings[i]);
			RegisterWRCommands(i);
		}

		for (int j = 0; j < TRACKS_SIZE; j++)
		{
			if (i < styles)
			{
				if (gA_Leaderboard[i][j] == null)
				{
					gA_Leaderboard[i][j] = new ArrayList();
				}

				gA_Leaderboard[i][j].Clear();
			}
			else
			{
				delete gA_Leaderboard[i][j];
			}
		}
	}

	gI_Styles = styles;
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void OnClientConnected(int client)
{
	wrcache_t empty_cache;
	gA_WRCache[client] = empty_cache;

	gB_LoadedCache[client] = false;

	any empty_cells[TRACKS_SIZE];

	for(int i = 0; i < gI_Styles; i++)
	{
		gF_PlayerRecord[client][i] = empty_cells;
		gI_PlayerCompletion[client][i] = empty_cells;
	}
}

public void OnClientAuthorized(int client)
{
	if (gB_Connected && !IsFakeClient(client))
	{
		UpdateClientCache(client);
	}
}

void UpdateClientCache(int client)
{
	int iSteamID = GetSteamAccountID(client);

	if(iSteamID == 0)
	{
		return;
	}

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "SELECT time, style, track, completions, exact_time_int FROM %splayertimes WHERE map = '%s' AND auth = %d;", gS_MySQLPrefix, gS_Map, iSteamID);
	gH_SQL.Query(SQL_UpdateCache_Callback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void SQL_UpdateCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (PB cache update) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	OnClientConnected(client);

	while(results.FetchRow())
	{
		int style = results.FetchInt(1);
		int track = results.FetchInt(2);

		if(style >= gI_Styles || style < 0 || track >= TRACKS_SIZE)
		{
			continue;
		}

		gF_PlayerRecord[client][style][track] = ExactTimeMaybe(results.FetchFloat(0), results.FetchInt(4));
		gI_PlayerCompletion[client][style][track] = results.FetchInt(3);

	}

	gB_LoadedCache[client] = true;
}

void UpdateWRCache(int client = -1)
{
	if (client == -1)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i))
			{
				UpdateClientCache(i);
			}
		}
	}
	else
	{
		UpdateClientCache(client);
	}

	char sQuery[512];

	FormatEx(sQuery, sizeof(sQuery),
		"SELECT p.id, p.auth, p.style, p.track, p.time, u.name, p.exact_time_int FROM %swrs p JOIN %susers u ON p.auth = u.auth WHERE p.map = '%s';",
		gS_MySQLPrefix, gS_MySQLPrefix, gS_Map);

	gH_SQL.Query(SQL_UpdateWRCache_Callback, sQuery, client);

	UpdateLeaderboards();

	if (client != -1)
	{
		return;
	}

	FormatEx(sQuery, sizeof(sQuery),
		"SELECT style, track, auth, stage, time FROM `%sstagetimeswr` WHERE map = '%s';",
		gS_MySQLPrefix, gS_Map);

	gH_SQL.Query(SQL_UpdateWRStageTimes_Callback, sQuery);
}

public void SQL_UpdateWRCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR cache update) SQL query failed. Reason: %s", error);

		return;
	}

	ResetWRs();

	// setup cache again, dynamically and not hardcoded
	while(results.FetchRow())
	{
		int iStyle = results.FetchInt(2);
		int iTrack = results.FetchInt(3);

		if(iStyle >= gI_Styles || iStyle < 0 || Shavit_GetStyleSettingInt(iStyle, "unranked"))
		{
			continue;
		}

		gI_WRRecordID[iStyle][iTrack] = results.FetchInt(0);
		gF_WRTime[iStyle][iTrack] = ExactTimeMaybe(results.FetchFloat(4), results.FetchInt(6));
		gI_WRSteamID[iStyle][iTrack] = results.FetchInt(1);

		char sSteamID[20];
		IntToString(gI_WRSteamID[iStyle][iTrack], sSteamID, sizeof(sSteamID));

		char sName[MAX_NAME_LENGTH];
		results.FetchString(5, sName, MAX_NAME_LENGTH);
		ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");
		gSM_WRNames.SetString(sSteamID, sName, false);
	}
}

public void SQL_UpdateWRStageTimes_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(!db || !results || error[0])
	{
		LogError("Timer (WR stage times cache) SQL query failed. Reason: %s", error);

		return;
	}

	float empty_times[MAX_STAGES];

	for(int i = 0; i < gI_Styles; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gA_StageWR[i][j] = empty_times;
		}
	}

	while(results.FetchRow())
	{
		int style = results.FetchInt(0);
		int track = results.FetchInt(1);
		int stage = results.FetchInt(3);

		gA_StageWR[style][track][stage] = results.FetchFloat(4);
	}
}

public int Native_GetWorldRecord(Handle handler, int numParams)
{
	return view_as<int>(gF_WRTime[GetNativeCell(1)][GetNativeCell(2)]);
}

public int Native_ReloadLeaderboards(Handle handler, int numParams)
{
	UpdateWRCache();
}

public int Native_GetWRRecordID(Handle handler, int numParams)
{
	SetNativeCellRef(2, gI_WRRecordID[GetNativeCell(1)][GetNativeCell(3)]);
}

public int Native_GetWRName(Handle handler, int numParams)
{
	int iSteamID = gI_WRSteamID[GetNativeCell(1)][GetNativeCell(4)];
	char sName[MAX_NAME_LENGTH];

	if (iSteamID != 0)
	{
		char sSteamID[20];
		IntToString(iSteamID, sSteamID, sizeof(sSteamID));

		if (gSM_WRNames.GetString(sSteamID, sName, sizeof(sName)))
		{
			SetNativeString(2, sName, GetNativeCell(3));
			return 0;
		}
	}

	SetNativeString(2, "invalid", GetNativeCell(3));
	return 0;
}

public int Native_GetClientPB(Handle handler, int numParams)
{
	return view_as<int>(gF_PlayerRecord[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)]);
}

public int Native_SetClientPB(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int style = GetNativeCell(2);
	int track = GetNativeCell(3);
	float time = GetNativeCell(4);

	gF_PlayerRecord[client][style][track] = time;
}

public int Native_GetPlayerPB(Handle handler, int numParams)
{
	SetNativeCellRef(3, gF_PlayerRecord[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(4)]);
}

public int Native_GetClientCompletions(Handle handler, int numParams)
{
	return gI_PlayerCompletion[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)];
}

public int Native_GetRankForTime(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(3);

	if(gA_Leaderboard[style][track] == null || gA_Leaderboard[style][track].Length == 0)
	{
		return 1;
	}

	return GetRankForTime(style, GetNativeCell(2), track);
}

public int Native_GetRecordAmount(Handle handler, int numParams)
{
	return GetRecordAmount(GetNativeCell(1), GetNativeCell(2));
}

public int Native_GetTimeForRank(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int rank = GetNativeCell(2);
	int track = GetNativeCell(3);

	#if defined DEBUG
	Shavit_PrintToChatAll("style %d | rank %d | track %d | amount %d", style, rank, track, GetRecordAmount(style, track));
	#endif

	if(rank > GetRecordAmount(style, track))
	{
		return view_as<int>(0.0);
	}

	return view_as<int>(gA_Leaderboard[style][track].Get(rank - 1));
}

public int Native_WR_DeleteMap(Handle handler, int numParams)
{
	char sMap[PLATFORM_MAX_PATH];
	GetNativeString(1, sMap, sizeof(sMap));
	LowercaseString(sMap);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM %splayertimes WHERE map = '%s';", gS_MySQLPrefix, sMap);
	gH_SQL.Query(SQL_DeleteMap_Callback, sQuery, StrEqual(gS_Map, sMap, false), DBPrio_High);
}

void DeleteWRFinal(int style, int track, const char[] map, int steamid, int recordid, bool update_cache)
{
	Call_StartForward(gH_OnWRDeleted);
	Call_PushCell(style);
	Call_PushCell(recordid);
	Call_PushCell(track);
	Call_PushCell(steamid);
	Call_PushString(map);
	Call_Finish();

	if (update_cache)
	{
		UpdateWRCache();
	}
}

public void DeleteWR_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	hPack.Reset();

	int style = hPack.ReadCell();
	int track = hPack.ReadCell();
	char map[PLATFORM_MAX_PATH];
	hPack.ReadString(map, sizeof(map));
	bool update_cache = view_as<bool>(hPack.ReadCell());
	int steamid = hPack.ReadCell();
	int recordid = hPack.ReadCell();

	delete hPack;

	if(results == null)
	{
		LogError("Timer (WR DeleteWR) SQL query failed. Reason: %s", error);
		return;
	}

	DeleteWRFinal(style, track, map, steamid, recordid, update_cache);
}

void DeleteWRInner(int recordid, int steamid, DataPack hPack)
{
	hPack.WriteCell(steamid);
	hPack.WriteCell(recordid);

	char sQuery[169];
	FormatEx(sQuery, sizeof(sQuery),
		"DELETE FROM %splayertimes WHERE id = %d;",
		gS_MySQLPrefix, recordid);
	gH_SQL.Query(DeleteWR_Callback, sQuery, hPack, DBPrio_High);
}

public void DeleteWRGetID_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	if(results == null || !results.FetchRow())
	{
		LogError("Timer (WR DeleteWRGetID) SQL query failed. Reason: %s", error);
		return;
	}

	DeleteWRInner(results.FetchInt(0), results.FetchInt(1), hPack);
}

void DeleteWR(int style, int track, const char[] map, int steamid, int recordid, bool delete_sql, bool update_cache)
{
	if (delete_sql)
	{
		DataPack hPack = new DataPack();
		hPack.WriteCell(style);
		hPack.WriteCell(track);
		hPack.WriteString(map);
		hPack.WriteCell(update_cache);

		char sQuery[512];

		if (recordid == -1) // missing WR recordid thing...
		{
			FormatEx(sQuery, sizeof(sQuery),
				"SELECT id, auth FROM %swrs WHERE map = '%s' AND style = %d AND track = %d;",
				gS_MySQLPrefix, map, style, track, gS_MySQLPrefix, map, style, track);
			gH_SQL.Query(DeleteWRGetID_Callback, sQuery, hPack, DBPrio_High);
		}
		else
		{
			DeleteWRInner(recordid, steamid, hPack);
		}
	}
	else
	{
		DeleteWRFinal(style, track, map, steamid, recordid, update_cache);
	}
}

public int Native_DeleteWR(Handle handle, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	char map[PLATFORM_MAX_PATH];
	GetNativeString(3, map, sizeof(map));
	LowercaseString(map);
	int steamid = GetNativeCell(4);
	int recordid = GetNativeCell(5);
	bool delete_sql = view_as<bool>(GetNativeCell(6));
	bool update_cache = view_as<bool>(GetNativeCell(7));

	DeleteWR(style, track, map, steamid, recordid, delete_sql, update_cache);
}

public int Native_GetStageWR(Handle plugin, int numParams)
{
	int track = GetNativeCell(1);
	int style = GetNativeCell(2);
	int stage = GetNativeCell(3);
	return view_as<int>(gA_StageWR[style][track][stage]);
}

public int Native_GetStagePB(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);
	int style = GetNativeCell(3);
	int stage = GetNativeCell(4);
	float pb;

	if (gA_StagePB[client][style][track] != null)
	{
		pb = gA_StagePB[client][style][track].Get(stage);
	}

	return view_as<int>(pb);
}

public void SQL_DeleteMap_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR deletemap) SQL query failed. Reason: %s", error);

		return;
	}

	if(view_as<bool>(data))
	{
		OnMapStart();
	}
}

#if defined DEBUG
// debug
public Action Command_Junk(int client, int args)
{
	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery),
		"INSERT INTO %splayertimes (auth, map, time, jumps, date, style, strafes, sync) VALUES (%d, '%s', %f, %d, %d, 0, %d, %.02f);",
		gS_MySQLPrefix, GetSteamAccountID(client), gS_Map, GetRandomFloat(10.0, 20.0), GetRandomInt(5, 15), GetTime(), GetRandomInt(5, 15), GetRandomFloat(50.0, 99.99));

	SQL_LockDatabase(gH_SQL);
	SQL_FastQuery(gH_SQL, sQuery);
	SQL_UnlockDatabase(gH_SQL);

	return Plugin_Handled;
}

public Action Command_PrintLeaderboards(int client, int args)
{
	char sArg[8];
	GetCmdArg(1, sArg, 8);

	int iStyle = StringToInt(sArg);
	int iRecords = GetRecordAmount(iStyle, Track_Main);

	ReplyToCommand(client, "Track: Main - Style: %d", iStyle);
	ReplyToCommand(client, "Current PB: %f", gF_PlayerRecord[client][iStyle][0]);
	ReplyToCommand(client, "Count: %d", iRecords);
	ReplyToCommand(client, "Rank: %d", Shavit_GetRankForTime(iStyle, gF_PlayerRecord[client][iStyle][0], iStyle));

	for(int i = 0; i < iRecords; i++)
	{
		ReplyToCommand(client, "#%d: %f", i, gA_Leaderboard[iStyle][0].Get(i));
	}

	return Plugin_Handled;
}
#endif

int GetTrackRecordCount(int track)
{
	int count = 0;

	for(int i = 0; i < gI_Styles; i++)
	{
		count += GetRecordAmount(i, track);
	}

	return count;
}

public Action Command_Delete(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_Delete_First);
	menu.SetTitle("%T\n ", "DeleteTrackSingle", client);

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		int records = GetTrackRecordCount(i);

		char sTrack[64];
		GetTrackName(client, i, sTrack, 64);

		if(records > 0)
		{
			Format(sTrack, 64, "%s (%T: %d)", sTrack, "WRRecord", client, records);
		}

		menu.AddItem(sInfo, sTrack, (records > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);

	return Plugin_Handled;
}

public int MenuHandler_Delete_First(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);
		gA_WRCache[param1].iLastTrack = StringToInt(info);

		DeleteSubmenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void DeleteSubmenu(int client)
{
	Menu menu = new Menu(MenuHandler_Delete);
	menu.SetTitle("%T\n ", "DeleteMenuTitle", client);

	int[] styles = new int[gI_Styles];
	Shavit_GetOrderedStyles(styles, gI_Styles);

	for(int i = 0; i < gI_Styles; i++)
	{
		int iStyle = styles[i];

		if(Shavit_GetStyleSettingInt(iStyle, "enabled") == -1)
		{
			continue;
		}

		char sInfo[8];
		IntToString(iStyle, sInfo, 8);

		char sDisplay[64];
		FormatEx(sDisplay, 64, "%s (%T: %d)", gS_StyleStrings[iStyle].sStyleName, "WRRecord", client, GetRecordAmount(iStyle, gA_WRCache[client].iLastTrack));

		menu.AddItem(sInfo, sDisplay, (GetRecordAmount(iStyle, gA_WRCache[client].iLastTrack) > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);
}

public Action Command_DeleteAll(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_DeleteAll_First);
	menu.SetTitle("%T\n ", "DeleteTrackAll", client);

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		int iRecords = GetTrackRecordCount(i);

		char sTrack[64];
		GetTrackName(client, i, sTrack, 64);

		if(iRecords > 0)
		{
			Format(sTrack, 64, "%s (%T: %d)", sTrack, "WRRecord", client, iRecords);
		}

		menu.AddItem(sInfo, sTrack, (iRecords > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);

	return Plugin_Handled;
}

public int MenuHandler_DeleteAll_First(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		int iTrack = gA_WRCache[param1].iLastTrack = StringToInt(sInfo);

		char sTrack[64];
		GetTrackName(param1, iTrack, sTrack, 64);

		Menu subMenu = new Menu(MenuHandler_DeleteAll_Second);
		subMenu.SetTitle("%T\n ", "DeleteTrackAllStyle", param1, sTrack);

		int[] styles = new int[gI_Styles];
		Shavit_GetOrderedStyles(styles, gI_Styles);

		for(int i = 0; i < gI_Styles; i++)
		{
			int iStyle = styles[i];

			if(Shavit_GetStyleSettingInt(iStyle, "enabled") == -1)
			{
				continue;
			}

			char sStyle[64];
			strcopy(sStyle, 64, gS_StyleStrings[iStyle].sStyleName);

			IntToString(iStyle, sInfo, 8);

			int iRecords = GetRecordAmount(iStyle, iTrack);

			if(iRecords > 0)
			{
				Format(sStyle, 64, "%s (%T: %d)", sStyle, "WRRecord", param1, iRecords);
			}

			subMenu.AddItem(sInfo, sStyle, (iRecords > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
		}

		subMenu.ExitButton = true;
		subMenu.Display(param1, 300);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_DeleteAll_Second(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		gA_WRCache[param1].iLastStyle = StringToInt(sInfo);

		DeleteAllSubmenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void DeleteAllSubmenu(int client)
{
	char sTrack[32];
	GetTrackName(client, gA_WRCache[client].iLastTrack, sTrack, 32);

	Menu menu = new Menu(MenuHandler_DeleteAll);
	menu.SetTitle("%T\n ", "DeleteAllRecordsMenuTitle", client, gS_Map, sTrack, gS_StyleStrings[gA_WRCache[client].iLastStyle].sStyleName);

	char sMenuItem[64];

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	FormatEx(sMenuItem, 64, "%T", "MenuResponseYes", client);
	menu.AddItem("yes", sMenuItem);

	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);
}

public int MenuHandler_DeleteAll(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);

		if(StringToInt(info) == -1)
		{
			Shavit_PrintToChat(param1, "%T", "DeletionAborted", param1);

			return 0;
		}

		char sTrack[32];
		GetTrackName(LANG_SERVER, gA_WRCache[param1].iLastTrack, sTrack, 32);

		Shavit_LogMessage("%L - deleted all %s track and %s style records from map `%s`.",
			param1, sTrack, gS_StyleStrings[gA_WRCache[param1].iLastStyle].sStyleName, gS_Map);

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "DELETE FROM %splayertimes WHERE map = '%s' AND style = %d AND track = %d;",
			gS_MySQLPrefix, gS_Map, gA_WRCache[param1].iLastStyle, gA_WRCache[param1].iLastTrack);

		DataPack hPack = new DataPack();
		hPack.WriteCell(GetClientSerial(param1));
		hPack.WriteCell(gA_WRCache[param1].iLastStyle);
		hPack.WriteCell(gA_WRCache[param1].iLastTrack);

		gH_SQL.Query(DeleteAll_Callback, sQuery, hPack, DBPrio_High);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_Delete(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);
		gA_WRCache[param1].iLastStyle = StringToInt(info);

		OpenDelete(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenDelete(int client)
{
	char sQuery[512];
	FormatEx(sQuery, 512, "SELECT p.id, u.name, p.time, p.jumps FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE map = '%s' AND style = %d AND track = %d ORDER BY time ASC, date ASC LIMIT 1000;",
		gS_MySQLPrefix, gS_MySQLPrefix, gS_Map, gA_WRCache[client].iLastStyle, gA_WRCache[client].iLastTrack);

	gH_SQL.Query(SQL_OpenDelete_Callback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void SQL_OpenDelete_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR OpenDelete) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	int iStyle = gA_WRCache[client].iLastStyle;

	Menu menu = new Menu(OpenDelete_Handler);
	menu.SetTitle("%t", "ListClientRecords", gS_Map, gS_StyleStrings[iStyle].sStyleName);

	int iCount = 0;

	while(results.FetchRow())
	{
		iCount++;

		// 0 - record id, for statistic purposes.
		int id = results.FetchInt(0);
		char sID[8];
		IntToString(id, sID, 8);

		// 1 - player name
		char sName[MAX_NAME_LENGTH];
		results.FetchString(1, sName, MAX_NAME_LENGTH);
		ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");

		// 2 - time
		float time = results.FetchFloat(2);
		char sTime[16];
		FormatSeconds(time, sTime, 16);

		// 3 - jumps
		int jumps = results.FetchInt(3);

		char sDisplay[128];
		FormatEx(sDisplay, 128, "#%d - %s - %s (%d jump%s)", iCount, sName, sTime, jumps, (jumps != 1)? "s":"");
		menu.AddItem(sID, sDisplay);
	}

	if(iCount == 0)
	{
		char sNoRecords[64];
		FormatEx(sNoRecords, 64, "%T", "WRMapNoRecords", client);
		menu.AddItem("-1", sNoRecords);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);
}

public int OpenDelete_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		int id = StringToInt(sInfo);

		if(id != -1)
		{
			OpenDeleteMenu(param1, id);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenDeleteMenu(int client, int id)
{
	char sMenuItem[64];

	Menu menu = new Menu(DeleteConfirm_Handler);
	menu.SetTitle("%T\n ", "DeleteConfirm", client);

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	FormatEx(sMenuItem, 64, "%T", "MenuResponseYesSingle", client);

	char sInfo[16];
	IntToString(id, sInfo, 16);
	menu.AddItem(sInfo, sMenuItem);

	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);
}

public int DeleteConfirm_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		int iRecordID = StringToInt(sInfo);

		if(iRecordID == -1)
		{
			Shavit_PrintToChat(param1, "%T", "DeletionAborted", param1);

			return 0;
		}

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery),
		"SELECT u.auth, u.name, p.map, p.time, p.sync, p.perfs, p.jumps, p.strafes, p.id, p.date, "...
		"(SELECT id FROM %splayertimes WHERE style = %d AND track = %d AND map = p.map ORDER BY time, date ASC LIMIT 1) "...
		"FROM %susers u LEFT JOIN %splayertimes p ON u.auth = p.auth WHERE p.id = %d;",
			gS_MySQLPrefix, gA_WRCache[param1].iLastStyle, gA_WRCache[param1].iLastTrack, gS_MySQLPrefix, gS_MySQLPrefix, iRecordID);

		gH_SQL.Query(GetRecordDetails_Callback, sQuery, GetClientSerial(param1), DBPrio_High);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void GetRecordDetails_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR GetRecordDetails) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		int iSteamID = results.FetchInt(0);

		char sName[MAX_NAME_LENGTH];
		results.FetchString(1, sName, MAX_NAME_LENGTH);

		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(2, sMap, sizeof(sMap));

		float fTime = results.FetchFloat(3);
		float fSync = results.FetchFloat(4);
		float fPerfectJumps = results.FetchFloat(5);

		int iJumps = results.FetchInt(6);
		int iStrafes = results.FetchInt(7);
		int iRecordID = results.FetchInt(8);
		int iTimestamp = results.FetchInt(9);
		int iWRRecordID = results.FetchInt(10);

		int iStyle = gA_WRCache[client].iLastStyle;
		int iTrack = gA_WRCache[client].iLastTrack;

		// that's a big datapack ya yeet
		DataPack hPack = new DataPack();
		hPack.WriteCell(GetClientSerial(client));
		hPack.WriteCell(iSteamID);
		hPack.WriteString(sName);
		hPack.WriteString(sMap);
		hPack.WriteCell(fTime);
		hPack.WriteCell(fSync);
		hPack.WriteCell(fPerfectJumps);
		hPack.WriteCell(iJumps);
		hPack.WriteCell(iStrafes);
		hPack.WriteCell(iRecordID);
		hPack.WriteCell(iTimestamp);
		hPack.WriteCell(iStyle);
		hPack.WriteCell(iTrack);

		bool bWRDeleted = iWRRecordID == iRecordID;
		hPack.WriteCell(bWRDeleted);

		char sQuery[256];
		FormatEx(sQuery, 256, "DELETE FROM %splayertimes WHERE id = %d;",
			gS_MySQLPrefix, iRecordID);

		gH_SQL.Query(DeleteConfirm_Callback, sQuery, hPack, DBPrio_High);
	}
}

public void DeleteConfirm_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	hPack.Reset();

	int iSerial = hPack.ReadCell();
	int iSteamID = hPack.ReadCell();

	char sName[MAX_NAME_LENGTH];
	hPack.ReadString(sName, MAX_NAME_LENGTH);

	char sMap[PLATFORM_MAX_PATH];
	hPack.ReadString(sMap, sizeof(sMap));

	float fTime = view_as<float>(hPack.ReadCell());
	float fSync = view_as<float>(hPack.ReadCell());
	float fPerfectJumps = view_as<float>(hPack.ReadCell());

	int iJumps = hPack.ReadCell();
	int iStrafes = hPack.ReadCell();
	int iRecordID = hPack.ReadCell();
	int iTimestamp = hPack.ReadCell();
	int iStyle = hPack.ReadCell();
	int iTrack = hPack.ReadCell();

	bool bWRDeleted = view_as<bool>(hPack.ReadCell());
	delete hPack;

	if(results == null)
	{
		LogError("Timer (WR DeleteConfirm) SQL query failed. Reason: %s", error);

		return;
	}

	if(bWRDeleted)
	{
		DeleteWR(iStyle, iTrack, sMap, iSteamID, iRecordID, false, true);
	}
	else
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && GetSteamAccountID(i) == iSteamID)
			{
				UpdateClientCache(i);
				break;
			}
		}
	}

	int client = GetClientFromSerial(iSerial);

	char sTrack[32];
	GetTrackName(LANG_SERVER, iTrack, sTrack, 32);

	char sDate[32];
	FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", iTimestamp);

	// above the client == 0 so log doesn't get lost if admin disconnects between deleting record and query execution
	Shavit_LogMessage("%L - deleted record. Runner: %s ([U:1:%d]) | Map: %s | Style: %s | Track: %s | Time: %.2f (%s) | Strafes: %d (%.1f%%) | Jumps: %d (%.1f%%) | Run date: %s | Record ID: %d",
		client, sName, iSteamID, sMap, gS_StyleStrings[iStyle].sStyleName, sTrack, fTime, (bWRDeleted)? "WR":"not WR", iStrafes, fSync, iJumps, fPerfectJumps, sDate, iRecordID);

	if(client == 0)
	{
		return;
	}

	Shavit_PrintToChat(client, "%T", "DeletedRecord", client);
}

public void DeleteAll_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	hPack.Reset();
	int client = GetClientFromSerial(hPack.ReadCell());
	int style = hPack.ReadCell();
	int track = hPack.ReadCell();
	delete hPack;

	if(results == null)
	{
		LogError("Timer (WR DeleteAll) SQL query failed. Reason: %s", error);

		return;
	}

	DeleteWR(style, track, gS_Map, 0, -1, false, true);

	Shavit_PrintToChat(client, "%T", "DeletedRecordsMap", client, gS_ChatStrings.sVariable, gS_Map, gS_ChatStrings.sText);
}

public Action Command_WorldRecord_Style(int client, int args)
{
	char sCommand[128];
	GetCmdArg(0, sCommand, sizeof(sCommand));

	int style = 0;

	if (gSM_StyleCommands.GetValue(sCommand, style))
	{
		gA_WRCache[client].bForceStyle = true;
		gA_WRCache[client].iLastStyle = style;
		Command_WorldRecord(client, args);
	}

	return Plugin_Handled;
}

public Action Command_WorldRecord(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	int track = Track_Main;
	bool havemap = false;

	if(StrContains(sCommand, "sm_b", false) == 0)
	{
		if (args >= 1)
		{
			char arg[6];
			GetCmdArg((args > 1) ? 2 : 1, arg, sizeof(arg));
			track = StringToInt(arg);

			// if the track doesn't fit in the bonus track range then assume it's a map name
			if (args > 1 || (track < Track_Bonus || track > Track_Bonus_Last))
			{
				havemap = true;
			}
		}

		if (track < Track_Bonus || track > Track_Bonus_Last)
		{
			track = Track_Bonus;
		}
	}
	else
	{
		havemap = (args >= 1);
	}

	if(!havemap)
	{
		gA_WRCache[client].sClientMap = gS_Map;
	}
	else
	{
		GetCmdArg(1, gA_WRCache[client].sClientMap, sizeof(wrcache_t::sClientMap));
		LowercaseString(gA_WRCache[client].sClientMap);

		if (!GuessBestMapName(gA_ValidMaps, gA_WRCache[client].sClientMap, gA_WRCache[client].sClientMap))
		{
			Shavit_PrintToChat(client, "%t", "Map was not found", gA_WRCache[client].sClientMap);
			return Plugin_Handled;
		}
	}

	gA_WRCache[client].iLastTrack = track;

	RetrieveWRMenu(client, track);
	return Plugin_Handled;
}

void RetrieveWRMenu(int client, int track)
{
	if (gA_WRCache[client].bPendingMenu)
	{
		return;
	}

	if (StrEqual(gA_WRCache[client].sClientMap, gS_Map))
	{
		for (int i = 0; i < gI_Styles; i++)
		{
			gA_WRCache[client].fWRs[i] = gF_WRTime[i][track];
		}

		if (gA_WRCache[client].bForceStyle)
		{
			StartWRMenu(client);
		}
		else
		{
			ShowWRStyleMenu(client);
		}
	}
	else
	{
		gA_WRCache[client].bPendingMenu = true;
		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery),
			"SELECT style, time FROM %swrs WHERE map = '%s' AND track = %d AND style < %d ORDER BY style;",
			gS_MySQLPrefix, gA_WRCache[client].sClientMap, track, gI_Styles);
		gH_SQL.Query(SQL_RetrieveWRMenu_Callback, sQuery, GetClientSerial(client));
	}
}

public void SQL_RetrieveWRMenu_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR RetrieveWRMenu) SQL query failed. Reason: %s", error);
		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	gA_WRCache[client].bPendingMenu = false;

	for (int i = 0; i < gI_Styles; i++)
	{
		gA_WRCache[client].fWRs[i] = 0.0;
	}

	while (results.FetchRow())
	{
		int style  = results.FetchInt(0);
		float time = results.FetchFloat(1);
		gA_WRCache[client].fWRs[style] = time;
	}

	if (gA_WRCache[client].bForceStyle)
	{
		StartWRMenu(client);
	}
	else
	{
		ShowWRStyleMenu(client);
	}
}

void ShowWRStyleMenu(int client, int first_item=0)
{
	Menu menu = new Menu(MenuHandler_StyleChooser);
	menu.SetTitle("%T", "WRMenuTitle", client);

	int[] styles = new int[gI_Styles];
	Shavit_GetOrderedStyles(styles, gI_Styles);

	for(int i = 0; i < gI_Styles; i++)
	{
		int iStyle = styles[i];

		if(Shavit_GetStyleSettingInt(iStyle, "unranked") || Shavit_GetStyleSettingInt(iStyle, "enabled") == -1)
		{
			continue;
		}

		char sInfo[8];
		IntToString(iStyle, sInfo, 8);

		char sDisplay[64];

		if (gA_WRCache[client].fWRs[iStyle] > 0.0)
		{
			char sTime[32];
			FormatSeconds(gA_WRCache[client].fWRs[iStyle], sTime, 32, false);

			FormatEx(sDisplay, 64, "%s - WR: %s", gS_StyleStrings[iStyle].sStyleName, sTime);
		}
		else
		{
			strcopy(sDisplay, 64, gS_StyleStrings[iStyle].sStyleName);
		}

		menu.AddItem(sInfo, sDisplay, (gA_WRCache[client].fWRs[iStyle] > 0.0) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	// should NEVER happen
	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "WRStyleNothing", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.DisplayAt(client, first_item, MENU_TIME_FOREVER);
}

public int MenuHandler_StyleChooser(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!IsValidClient(param1))
		{
			return 0;
		}

		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		int iStyle = StringToInt(sInfo);

		if(iStyle == -1)
		{
			Shavit_PrintToChat(param1, "%T", "NoStyles", param1, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

			return 0;
		}

		gA_WRCache[param1].iLastStyle = iStyle;
		gA_WRCache[param1].iPagePosition = GetMenuSelectionPosition();

		StartWRMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void StartWRMenu(int client)
{
	gA_WRCache[client].bForceStyle = false;

	DataPack dp = new DataPack();
	dp.WriteCell(GetClientSerial(client));
	dp.WriteCell(gA_WRCache[client].iLastTrack);
	dp.WriteString(gA_WRCache[client].sClientMap);

	int iLength = ((strlen(gA_WRCache[client].sClientMap) * 2) + 1);
	char[] sEscapedMap = new char[iLength];
	gH_SQL.Escape(gA_WRCache[client].sClientMap, sEscapedMap, iLength);

	char sQuery[512];
	FormatEx(sQuery, 512, "SELECT p.id, u.name, p.time, p.jumps, p.auth FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE map = '%s' AND style = %d AND track = %d ORDER BY time ASC, date ASC;", gS_MySQLPrefix, gS_MySQLPrefix, sEscapedMap, gA_WRCache[client].iLastStyle, gA_WRCache[client].iLastTrack);
	gH_SQL.Query(SQL_WR_Callback, sQuery, dp);
}

public void SQL_WR_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int serial = data.ReadCell();
	int track = data.ReadCell();

	char sMap[PLATFORM_MAX_PATH];
	data.ReadString(sMap, sizeof(sMap));

	delete data;

	if(results == null)
	{
		LogError("Timer (WR SELECT) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(serial);

	if(client == 0)
	{
		return;
	}

	int iSteamID = GetSteamAccountID(client);

	Menu hMenu = new Menu(WRMenu_Handler);

	int iCount = 0;
	int iMyRank = 0;

	while(results.FetchRow())
	{
		if(++iCount <= gCV_RecordsLimit.IntValue)
		{
			// 0 - record id, for statistic purposes.
			int id = results.FetchInt(0);
			char sID[8];
			IntToString(id, sID, 8);

			// 1 - player name
			char sName[MAX_NAME_LENGTH];
			results.FetchString(1, sName, MAX_NAME_LENGTH);

			// 2 - time
			float time = results.FetchFloat(2);
			char sTime[16];
			FormatSeconds(time, sTime, 16);

			// 3 - jumps
			int jumps = results.FetchInt(3);

			char sDisplay[128];
			FormatEx(sDisplay, 128, "#%d - %s - %s (%d %T)", iCount, sName, sTime, jumps, "WRJumps", client);
			hMenu.AddItem(sID, sDisplay);
		}

		// check if record exists in the map's top X
		int iQuerySteamID = results.FetchInt(4);

		if(iQuerySteamID == iSteamID)
		{
			iMyRank = iCount;
		}
	}

	char sFormattedTitle[256];

	if(hMenu.ItemCount == 0)
	{
		hMenu.SetTitle("%T", "WRMap", client, sMap);
		char sNoRecords[64];
		FormatEx(sNoRecords, 64, "%T", "WRMapNoRecords", client);

		hMenu.AddItem("-1", sNoRecords);
	}

	else
	{
		int iStyle = gA_WRCache[client].iLastStyle;
		int iRecords = results.RowCount;

		// [32] just in case there are 150k records on a map and you're ranked 100k or something
		char sRanks[32];

		if(gF_PlayerRecord[client][iStyle][track] == 0.0 || iMyRank == 0)
		{
			FormatEx(sRanks, 32, "(%d %T)", iRecords, "WRRecord", client);
		}

		else
		{
			FormatEx(sRanks, 32, "(#%d/%d)", iMyRank, iRecords);
		}

		char sTrack[32];
		GetTrackName(client, track, sTrack, 32);

		FormatEx(sFormattedTitle, 192, "%T %s: [%s]\n%s", "WRRecordFor", client, sMap, sTrack, sRanks);
		hMenu.SetTitle(sFormattedTitle);
	}

	hMenu.ExitBackButton = true;
	hMenu.Display(client, 300);
}

public int WRMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);
		int id = StringToInt(sInfo);

		if(id != -1)
		{
			OpenSubMenu(param1, id);
		}

		else
		{
			ShowWRStyleMenu(param1);
		}
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowWRStyleMenu(param1, gA_WRCache[param1].iPagePosition);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_RecentRecords(int client, int args)
{
	if(gA_WRCache[client].bPendingMenu || !IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sQuery[512];

	FormatEx(sQuery, sizeof(sQuery),
		"SELECT a.id, a.map, u.name, a.time, a.style, a.track FROM %swrs a JOIN %susers u on a.auth = u.auth ORDER BY a.date DESC LIMIT 100;",
		gS_MySQLPrefix, gS_MySQLPrefix);

	gH_SQL.Query(SQL_RR_Callback, sQuery, GetClientSerial(client), DBPrio_Low);

	gA_WRCache[client].bPendingMenu = true;

	return Plugin_Handled;
}

public void SQL_RR_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientFromSerial(data);

	gA_WRCache[client].bPendingMenu = false;

	if(results == null)
	{
		LogError("Timer (RR SELECT) SQL query failed. Reason: %s", error);

		return;
	}

	if(client == 0)
	{
		return;
	}

	Menu menu = new Menu(RRMenu_Handler);
	menu.SetTitle("%T:", "RecentRecords", client, gCV_RecentLimit.IntValue);

	while(results.FetchRow())
	{
		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(1, sMap, sizeof(sMap));

		char sName[MAX_NAME_LENGTH];
		results.FetchString(2, sName, sizeof(sName));
		TrimDisplayString(sName, sName, sizeof(sName), 9);

		char sTime[16];
		float fTime = results.FetchFloat(3);
		FormatSeconds(fTime, sTime, 16);

		int iStyle = results.FetchInt(4);
		if(iStyle >= gI_Styles || iStyle < 0 || Shavit_GetStyleSettingInt(iStyle, "unranked"))
		{
			continue;
		}

		char sTrack[32];
		GetTrackName(client, results.FetchInt(5), sTrack, 32);

		char sDisplay[192];
		FormatEx(sDisplay, 192, "[%s/%c] %s - %s @ %s", gS_StyleStrings[iStyle].sShortName, sTrack[0], sMap, sName, sTime);

		char sInfo[192];
		FormatEx(sInfo, 192, "%d;%s", results.FetchInt(0), sMap);

		menu.AddItem(sInfo, sDisplay);
	}

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "WRMapNoRecords", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);
}

public int RRMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[128];
		menu.GetItem(param2, sInfo, 128);

		if(StringToInt(sInfo) != -1)
		{
			char sExploded[2][128];
			ExplodeString(sInfo, ";", sExploded, 2, 128, true);

			strcopy(gA_WRCache[param1].sClientMap, 128, sExploded[1]);

			OpenSubMenu(param1, StringToInt(sExploded[0]));
		}

		else
		{
			RetrieveWRMenu(param1, gA_WRCache[param1].iLastTrack);
		}
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		RetrieveWRMenu(param1, gA_WRCache[param1].iLastTrack);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenSubMenu(int client, int id)
{
	char sQuery[512];
	FormatEx(sQuery, 512,
		"SELECT u.name, p.time, p.jumps, p.style, u.auth, p.date, p.map, p.strafes, p.sync, p.perfs, p.points, p.track, p.completions FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE p.id = %d LIMIT 1;",
		gS_MySQLPrefix, gS_MySQLPrefix, id);

	DataPack datapack = new DataPack();
	datapack.WriteCell(GetClientSerial(client));
	datapack.WriteCell(id);

	gH_SQL.Query(SQL_SubMenu_Callback, sQuery, datapack, DBPrio_High);
}

public void SQL_SubMenu_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int client = GetClientFromSerial(data.ReadCell());
	int id = data.ReadCell();
	delete data;

	if(results == null)
	{
		LogError("Timer (WR SUBMENU) SQL query failed. Reason: %s", error);

		return;
	}

	if(client == 0)
	{
		return;
	}

	Menu hMenu = new Menu(SubMenu_Handler);

	char sFormattedTitle[256];
	char sName[MAX_NAME_LENGTH];
	int iSteamID = 0;
	char sTrack[32];
	char sMap[PLATFORM_MAX_PATH];

	if(results.FetchRow())
	{
		results.FetchString(0, sName, MAX_NAME_LENGTH);

		float fTime = results.FetchFloat(1);
		char sTime[16];
		FormatSeconds(fTime, sTime, 16);

		char sDisplay[128];
		FormatEx(sDisplay, 128, "%T: %s", "WRTime", client, sTime);
		hMenu.AddItem("-1", sDisplay);

		int iStyle = results.FetchInt(3);
		int iJumps = results.FetchInt(2);
		float fPerfs = results.FetchFloat(9);

		if(Shavit_GetStyleSettingInt(iStyle, "autobhop"))
		{
			FormatEx(sDisplay, 128, "%T: %d", "WRJumps", client, iJumps);
		}

		else
		{
			FormatEx(sDisplay, 128, "%T: %d (%.2f%%)", "WRJumps", client, iJumps, fPerfs);
		}

		hMenu.AddItem("-1", sDisplay);

		FormatEx(sDisplay, 128, "%T: %d", "WRCompletions", client, results.FetchInt(12));
		hMenu.AddItem("-1", sDisplay);

		FormatEx(sDisplay, 128, "%T: %s", "WRStyle", client, gS_StyleStrings[iStyle].sStyleName);
		hMenu.AddItem("-1", sDisplay);

		results.FetchString(6, sMap, sizeof(sMap));

		float fPoints = results.FetchFloat(10);

		if(gB_Rankings && fPoints > 0.0)
		{
			FormatEx(sDisplay, 128, "%T: %.03f", "WRPointsCap", client, fPoints);
			hMenu.AddItem("-1", sDisplay);
		}

		iSteamID = results.FetchInt(4);

		char sDate[32];
		results.FetchString(5, sDate, 32);

		if(sDate[4] != '-')
		{
			FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", StringToInt(sDate));
		}

		FormatEx(sDisplay, 128, "%T: %s", "WRDate", client, sDate);
		hMenu.AddItem("-1", sDisplay);

		int strafes = results.FetchInt(7);
		float sync = results.FetchFloat(8);

		if(iJumps > 0 || strafes > 0)
		{
			FormatEx(sDisplay, 128, (sync != -1.0)? "%T: %d (%.02f%%)":"%T: %d", "WRStrafes", client, strafes, sync);
			hMenu.AddItem("-1", sDisplay);
		}

		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "WRPlayerStats", client);

		char sInfo[32];
		FormatEx(sInfo, 32, "0;%d", iSteamID);

		if(gB_Stats)
		{
			hMenu.AddItem(sInfo, sMenuItem);
		}

		if(CheckCommandAccess(client, "sm_delete", ADMFLAG_RCON))
		{
			FormatEx(sMenuItem, 64, "%T", "WRDeleteRecord", client);
			FormatEx(sInfo, 32, "1;%d", id);
			hMenu.AddItem(sInfo, sMenuItem);
		}

		GetTrackName(client, results.FetchInt(11), sTrack, 32);
	}

	else
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "DatabaseError", client);
		hMenu.AddItem("-1", sMenuItem);
	}

	if(strlen(sName) > 0)
	{
		FormatEx(sFormattedTitle, 256, "%s [U:1:%d]\n--- %s: [%s]", sName, iSteamID, sMap, sTrack);
	}

	else
	{
		FormatEx(sFormattedTitle, 256, "%T", "Error", client);
	}

	hMenu.SetTitle(sFormattedTitle);
	hMenu.ExitBackButton = true;
	hMenu.Display(client, 300);
}

public int SubMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, 32);

		if(gB_Stats && StringToInt(sInfo) != -1)
		{
			char sExploded[2][32];
			ExplodeString(sInfo, ";", sExploded, 2, 32, true);

			int first = StringToInt(sExploded[0]);

			switch(first)
			{
				case 0:
				{
					Shavit_OpenStatsMenu(param1, StringToInt(sExploded[1]));
				}

				case 1:
				{
					OpenDeleteMenu(param1, StringToInt(sExploded[1]));
				}
			}
		}

		else
		{
			StartWRMenu(param1);
		}
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		StartWRMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void Shavit_OnDatabaseLoaded()
{
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = view_as<Database2>(Shavit_GetDatabase());
	gB_MySQL = IsMySQLDatabase(gH_SQL);

	char sQuery[1024];
	Transaction2 hTransaction = new Transaction2();

	if(gB_MySQL)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%splayertimes` (`id` INT NOT NULL AUTO_INCREMENT, `auth` INT, `map` VARCHAR(128), `time` FLOAT, `jumps` INT, `style` TINYINT, `date` INT, `strafes` INT, `sync` FLOAT, `points` FLOAT NOT NULL DEFAULT 0, `track` TINYINT NOT NULL DEFAULT 0, `perfs` FLOAT DEFAULT 0, `completions` SMALLINT DEFAULT 1, `exact_time_int` INT DEFAULT 0, PRIMARY KEY (`id`), INDEX `map` (`map`, `style`, `track`, `time`), INDEX `auth` (`auth`, `date`, `points`), INDEX `time` (`time`), CONSTRAINT `%spt_auth` FOREIGN KEY (`auth`) REFERENCES `%susers` (`auth`) ON UPDATE CASCADE ON DELETE CASCADE) ENGINE=INNODB;",
			gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%splayertimes` (`id` INTEGER PRIMARY KEY, `auth` INT, `map` VARCHAR(128), `time` FLOAT, `jumps` INT, `style` TINYINT, `date` INT, `strafes` INT, `sync` FLOAT, `points` FLOAT NOT NULL DEFAULT 0, `track` TINYINT NOT NULL DEFAULT 0, `perfs` FLOAT DEFAULT 0, `completions` SMALLINT DEFAULT 1, `exact_time_int` INT DEFAULT 0, CONSTRAINT `%spt_auth` FOREIGN KEY (`auth`) REFERENCES `%susers` (`auth`) ON UPDATE CASCADE ON DELETE CASCADE);",
			gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix);
	}

	hTransaction.AddQuery(sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%sstagetimeswr` (`style` TINYINT NOT NULL, `track` TINYINT NOT NULL DEFAULT 0, `map` VARCHAR(128) NOT NULL, `stage` TINYINT NOT NULL, `auth` INT NOT NULL, `time` FLOAT NOT NULL, PRIMARY KEY (`style`, `track`, `map`, `stage`))%s;",
		gS_MySQLPrefix, (gB_MySQL)? " ENGINE=INNODB":"");
	hTransaction.AddQuery(sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%sstagetimespb` (`style` TINYINT NOT NULL, `track` TINYINT NOT NULL DEFAULT 0, `map` VARCHAR(128) NOT NULL, `stage` TINYINT NOT NULL, `auth` INT NOT NULL, `time` FLOAT NOT NULL, PRIMARY KEY (`style`, `track`, `auth`, `map`, `stage`))%s;",
		gS_MySQLPrefix, (gB_MySQL)? " ENGINE=INNODB":"");
	hTransaction.AddQuery(sQuery);

#if 1
	FormatEx(sQuery, sizeof(sQuery),
		"%s %swrs_min AS SELECT MIN(time) time, map, track, style FROM %splayertimes GROUP BY map, track, style;",
		gB_MySQL ? "CREATE OR REPLACE VIEW" : "CREATE VIEW IF NOT EXISTS",
		gS_MySQLPrefix, gS_MySQLPrefix);
	hTransaction.AddQuery(sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"%s %swrs AS SELECT a.* FROM %splayertimes a JOIN %swrs_min b ON a.time = b.time AND a.map = b.map AND a.track = b.track AND a.style = b.style;",
		gB_MySQL ? "CREATE OR REPLACE VIEW" : "CREATE VIEW IF NOT EXISTS",
		gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix);
	hTransaction.AddQuery(sQuery);
#else
	FormatEx(sQuery, sizeof(sQuery),
		"DROP VIEW IF EXISTS %swrs_min;",
		gS_MySQLPrefix);
	hTransaction.AddQuery(sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"%s %swrs AS SELECT MIN(time) time, MIN(id) id, MIN(auth) auth, MIN(exact_time_int) exact_time_int, MIN(date) date, map, track, style FROM %splayertimes GROUP BY map, track, style;",
		gB_MySQL ? "CREATE OR REPLACE VIEW" : "CREATE VIEW IF NOT EXISTS",
		gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix);
	hTransaction.AddQuery(sQuery);
#endif

	gH_SQL.Execute(hTransaction, Trans_CreateTable_Success, Trans_CreateTable_Error, 0, DBPrio_High);
}

public void Trans_CreateTable_Success(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	gB_Connected = true;

	OnMapStart();
}

public void Trans_CreateTable_Error(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (WR module) SQL query %d/%d failed. Reason: %s", failIndex, numQueries, error);
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
	// do not risk overwriting the player's data if their PB isn't loaded to cache yet
	if (!gB_LoadedCache[client])
	{
		return;
	}

#if 0
	time = view_as<float>(0x43611FB3); // 225.123825; // this value loses accuracy and becomes 0x43611FBE \ 225.123992 once it's returned from mysql
	PrintToServer("time = %f %X record = %f %X", time, time, gF_WRTime[style][track], gF_WRTime[style][track]);
#endif

	int iSteamID = GetSteamAccountID(client);

	char sTime[32];
	FormatSeconds(time, sTime, 32);

	char sTrack[32];
	GetTrackName(LANG_SERVER, track, sTrack, 32);

	// 0 - no query
	// 1 - insert
	// 2 - update
	bool bIncrementCompletions = true;
	int iOverwrite = 0;

	if(Shavit_GetStyleSettingInt(style, "unranked") || Shavit_IsPracticeMode(client))
	{
		iOverwrite = 0; // ugly way of not writing to database
		bIncrementCompletions = false;
	}

	else if(gF_PlayerRecord[client][style][track] == 0.0)
	{
		iOverwrite = 1;
	}

	else if(time < gF_PlayerRecord[client][style][track])
	{
		iOverwrite = 2;
	}

	bool bEveryone = (iOverwrite > 0);
	char sMessage[255];
	char sMessage2[255];

	if(iOverwrite > 0 && (time < gF_WRTime[style][track] || gF_WRTime[style][track] == 0.0)) // WR?
	{
		float fOldWR = gF_WRTime[style][track];
		gF_WRTime[style][track] = time;

		gI_WRSteamID[style][track] = iSteamID;

		Call_StartForward(gH_OnWorldRecord);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_PushCell(strafes);
		Call_PushCell(sync);
		Call_PushCell(track);
		Call_PushCell(fOldWR);
		Call_PushCell(oldtime);
		Call_PushCell(perfs);
		Call_PushCell(avgvel);
		Call_PushCell(maxvel);
		Call_PushCell(timestamp);
		Call_Finish();

		#if defined DEBUG
		Shavit_PrintToChat(client, "old: %.01f new: %.01f", fOldWR, time);
		#endif

		Transaction2 hTransaction = new Transaction2();
		char query[512];

		FormatEx(query, sizeof(query),
			"DELETE FROM `%sstagetimeswr` WHERE style = %d AND track = %d AND map = '%s';",
			gS_MySQLPrefix, style, track, gS_Map
		);

		hTransaction.AddQuery(query);

		for (int i = 0; i < MAX_STAGES; i++)
		{
			float fTime = gA_StageTimes[client][i];
			gA_StageWR[style][track][i] = fTime;

			if (fTime == 0.0)
			{
				continue;
			}

			FormatEx(query, sizeof(query),
				"INSERT INTO `%sstagetimeswr` (`style`, `track`, `map`, `auth`, `time`, `stage`) VALUES (%d, %d, '%s', %d, %f, %d);",
				gS_MySQLPrefix, style, track, gS_Map, iSteamID, fTime, i
			);

			hTransaction.AddQuery(query);
		}

		gH_SQL.Execute(hTransaction, Trans_ReplaceStageTimes_Success, Trans_ReplaceStageTimes_Error, 0, DBPrio_High);
	}

	int iRank = GetRankForTime(style, time, track);

	if(iRank >= GetRecordAmount(style, track))
	{
		Call_StartForward(gH_OnWorstRecord);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_PushCell(strafes);
		Call_PushCell(sync);
		Call_PushCell(track);
		Call_PushCell(oldtime);
		Call_PushCell(perfs);
		Call_PushCell(avgvel);
		Call_PushCell(maxvel);
		Call_PushCell(timestamp);
		Call_Finish();
	}

	float fDifference = (gF_PlayerRecord[client][style][track] - time);

	if(fDifference < 0.0)
	{
		fDifference = -fDifference;
	}

	char sDifference[16];
	FormatSeconds(fDifference, sDifference, 16, true);

	char sSync[32]; // 32 because colors
	FormatEx(sSync, 32, (sync != -1.0)? " @ %s%.02f%%":"", gS_ChatStrings.sVariable, sync);

	if(iOverwrite > 0)
	{
		char sQuery[1024];

		if(iOverwrite == 1) // insert
		{
			FormatEx(sMessage, 255, "%s[%s]%s %T",
				gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText, "FirstCompletion", LANG_SERVER, gS_ChatStrings.sVariable2, client, gS_ChatStrings.sText, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, gS_ChatStrings.sVariable, iRank, gS_ChatStrings.sText, jumps, strafes, sSync, gS_ChatStrings.sText);

			FormatEx(sQuery, sizeof(sQuery),
				"INSERT INTO %splayertimes (auth, map, time, jumps, date, style, strafes, sync, points, track, perfs, exact_time_int) VALUES (%d, '%s', %f, %d, %d, %d, %d, %.2f, 0.0, %d, %.2f, %d);",
				gS_MySQLPrefix, iSteamID, gS_Map, time, jumps, timestamp, style, strafes, sync, track, perfs, view_as<int>(time));
		}
		else // update
		{
			FormatEx(sMessage, 255, "%s[%s]%s %T",
				gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText, "NotFirstCompletion", LANG_SERVER, gS_ChatStrings.sVariable2, client, gS_ChatStrings.sText, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, gS_ChatStrings.sVariable, iRank, gS_ChatStrings.sText, jumps, strafes, sSync, gS_ChatStrings.sText, gS_ChatStrings.sWarning, sDifference);

			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %splayertimes SET time = %f, jumps = %d, date = %d, strafes = %d, sync = %.02f, points = 0.0, perfs = %.2f, exact_time_int = %d, completions = completions + 1 WHERE map = '%s' AND auth = %d AND style = %d AND track = %d;",
				gS_MySQLPrefix, time, jumps, timestamp, strafes, sync, perfs, view_as<int>(time), gS_Map, iSteamID, style, track);
		}

		gH_SQL.Query(SQL_OnFinish_Callback, sQuery, GetClientSerial(client), DBPrio_High);

		Call_StartForward(gH_OnFinish_Post);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_PushCell(strafes);
		Call_PushCell(sync);
		Call_PushCell(iRank);
		Call_PushCell(iOverwrite);
		Call_PushCell(track);
		Call_PushCell(oldtime);
		Call_PushCell(perfs);
		Call_PushCell(avgvel);
		Call_PushCell(maxvel);
		Call_PushCell(timestamp);
		Call_Finish();
	}

	if(bIncrementCompletions)
	{
		if (iOverwrite == 0)
		{
			char sQuery[512];
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %splayertimes SET completions = completions + 1 WHERE map = '%s' AND auth = %d AND style = %d AND track = %d;",
				gS_MySQLPrefix, gS_Map, iSteamID, style, track);

			gH_SQL.Query(SQL_OnIncrementCompletions_Callback, sQuery, 0, DBPrio_Low);
		}

		gI_PlayerCompletion[client][style][track]++;

		if(iOverwrite == 0 && !Shavit_GetStyleSettingInt(style, "unranked"))
		{
			FormatEx(sMessage, 255, "%s[%s]%s %T",
				gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText, "WorseTime", client, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, jumps, strafes, sSync, gS_ChatStrings.sText, sDifference);
		}
	}
	else
	{
		FormatEx(sMessage, 255, "%s[%s]%s %T",
			gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText, "UnrankedTime", client, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, jumps, strafes, sSync, gS_ChatStrings.sText);
	}

	timer_snapshot_t aSnapshot;
	Shavit_SaveSnapshot(client, aSnapshot);

	if (!Shavit_GetStyleSettingBool(style, "autobhop"))
	{
		FormatEx(sMessage2, sizeof(sMessage2), "%s[%s]%s %T", gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText, "CompletionExtraInfo", LANG_SERVER, gS_ChatStrings.sVariable, avgvel, gS_ChatStrings.sText, gS_ChatStrings.sVariable, maxvel, gS_ChatStrings.sText, gS_ChatStrings.sVariable, perfs, gS_ChatStrings.sText);
	}

	Action aResult = Plugin_Continue;
	Call_StartForward(gH_OnFinishMessage);
	Call_PushCell(client);
	Call_PushCellRef(bEveryone);
	Call_PushArrayEx(aSnapshot, sizeof(timer_snapshot_t), SM_PARAM_COPYBACK);
	Call_PushCell(iOverwrite);
	Call_PushCell(iRank);
	Call_PushStringEx(sMessage, 255, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(255);
	Call_PushStringEx(sMessage2, sizeof(sMessage2), SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(sizeof(sMessage2));
	Call_Finish(aResult);

	if(aResult < Plugin_Handled)
	{
		if(bEveryone)
		{
			Shavit_PrintToChatAll("%s", sMessage);
		}
		else
		{
			Shavit_PrintToChat(client, "%s", sMessage);

			for(int i = 1; i <= MaxClients; i++)
			{
				if(client != i && IsValidClient(i) && GetSpectatorTarget(i) == client)
				{
					Shavit_PrintToChat(i, "%s", sMessage);

					if (sMessage2[0] != 0)
					{
						Shavit_PrintToChat(i, "%s", sMessage2);
					}
				}
			}
		}

		if (sMessage2[0] != 0)
		{
			Shavit_PrintToChat(client, "%s", sMessage2);
		}
	}

	// update pb cache only after sending the message so we can grab the old one inside the Shavit_OnFinishMessage forward
	if(iOverwrite > 0)
	{
		gF_PlayerRecord[client][style][track] = time;
	}
}

public void SQL_OnIncrementCompletions_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR OnIncrementCompletions) SQL query failed. Reason: %s", error);

		return;
	}
}

public void SQL_OnFinish_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR OnFinish) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	UpdateWRCache(client);
}

public void Trans_ReplaceStageTimes_Success(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	return;
}

public void Trans_ReplaceStageTimes_Error(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (ReplaceStageTimes) SQL query failed %d/%d. Reason: %s", failIndex, numQueries, error);
}

void UpdateLeaderboards()
{
	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "SELECT style, track, time, exact_time_int FROM %splayertimes WHERE map = '%s' ORDER BY time ASC, date ASC;", gS_MySQLPrefix, gS_Map);
	gH_SQL.Query(SQL_UpdateLeaderboards_Callback, sQuery);
}

public void SQL_UpdateLeaderboards_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR UpdateLeaderboards) SQL query failed. Reason: %s", error);

		return;
	}

	ResetLeaderboards();

	while(results.FetchRow())
	{
		int style = results.FetchInt(0);
		int track = results.FetchInt(1);

		if(style >= gI_Styles || Shavit_GetStyleSettingInt(style, "unranked") || track >= TRACKS_SIZE)
		{
			continue;
		}

		gA_Leaderboard[style][track].Push(ExactTimeMaybe(results.FetchFloat(2), results.FetchInt(3)));
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		if (Shavit_GetStyleSettingInt(i, "unranked"))
		{
			continue;
		}

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			SortADTArray(gA_Leaderboard[i][j], Sort_Ascending, Sort_Float);
		}
	}
}

public Action Shavit_OnStageMessage(int client, int stageNumber, char[] message, int maxlen)
{
	int style = Shavit_GetBhopStyle(client);
	int track = Shavit_GetClientTrack(client);
	float stageTime = Shavit_GetClientTime(client);
	float stageTimeWR = gA_StageWR[style][track][stageNumber];

	gA_StageTimes[client][stageNumber] = stageTime;

	if (stageTimeWR == 0.0)
	{
		return Plugin_Continue;
	}

	float fDifference = (stageTime - stageTimeWR);

	char sStageTime[16];
	FormatSeconds(stageTime, sStageTime, 16);

	char sDifference[16];
	FormatSeconds(fDifference, sDifference, 16);

	if(fDifference >= 0.0)
	{
		Format(sDifference, sizeof(sDifference), "+%s", sDifference);
	}

	Shavit_PrintToChat(client, "%T", "WRStageTime", client, gS_ChatStrings.sText, gS_ChatStrings.sVariable, stageNumber, gS_ChatStrings.sText, gS_ChatStrings.sVariable, sStageTime, gS_ChatStrings.sText, (fDifference <= 0.0) ? gS_ChatStrings.sVariable : gS_ChatStrings.sWarning, sDifference, gS_ChatStrings.sText);

	return Plugin_Handled;
}

public Action Shavit_OnStart(int client, int track)
{
	float empty_times[MAX_STAGES];
	gA_StageTimes[client] = empty_times;

	return Plugin_Continue;
}

int GetRecordAmount(int style, int track)
{
	if(gA_Leaderboard[style][track] == null)
	{
		return 0;
	}

	return gA_Leaderboard[style][track].Length;
}

int GetRankForTime(int style, float time, int track)
{
	int iRecords = GetRecordAmount(style, track);

	if(time <= gF_WRTime[style][track] || iRecords <= 0)
	{
		return 1;
	}

	if(gA_Leaderboard[style][track] != null && gA_Leaderboard[style][track].Length > 0)
	{
		for(int i = 0; i < iRecords; i++)
		{
			if(time <= gA_Leaderboard[style][track].Get(i))
			{
				return ++i;
			}
		}
	}

	return (iRecords + 1);
}

float ExactTimeMaybe(float time, int exact_time)
{
	return (exact_time != 0) ? view_as<float>(exact_time) : time;
}
