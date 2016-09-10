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

#undef REQUIRE_PLUGIN
#include <shavit>
#include <adminmenu>

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

// #define DEBUG

bool gB_Late = false;
bool gB_Rankings = false;
bool gB_Stats = false;

// forwards
Handle gH_OnWorldRecord = null;
Handle gH_OnFinish_Post = null;
Handle gH_OnWRDeleted = null;

// database handle
Database gH_SQL = null;
bool gB_MySQL = false;

// cache
BhopStyle gBS_LastWR[MAXPLAYERS+1];
char gS_ClientMap[MAXPLAYERS+1][192];

char gS_Map[192]; // blame workshop paths being so fucking long

// current wr stats
float gF_WRTime[STYLE_LIMIT];
int gI_WRRecordID[STYLE_LIMIT];
char gS_WRName[STYLE_LIMIT][MAX_NAME_LENGTH];
int gI_RecordAmount[STYLE_LIMIT];
ArrayList gA_LeaderBoard[STYLE_LIMIT];

// more caching
float gF_PlayerRecord[MAXPLAYERS+1][STYLE_LIMIT];

// admin menu
Handle gH_AdminMenu = null;

// table prefix
char gS_MySQLPrefix[32];

// cvars
ConVar gCV_RecordsLimit = null;
ConVar gCV_RecentLimit = null;

// cached cvars
int gI_RecordsLimit = 50;
int gI_RecentLimit = 50;

// colors to minimize printtochat on finish
char gS_Color_Time[16];
char gS_Color_Rank[16];
char gS_Color_Sync[16];
char gS_Color_Better[16];
char gS_Color_Worse[16];

// timer settings
int gI_Styles = 0;
char gS_StyleStrings[STYLE_LIMIT][STYLESTRINGS_SIZE][128];
any gA_StyleSettings[STYLE_LIMIT][STYLESETTINGS_SIZE];

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
	CreateNative("Shavit_GetWRTime", Native_GetWRTime);
	CreateNative("Shavit_GetWRRecordID", Native_GetWRRecordID);
	CreateNative("Shavit_GetWRName", Native_GetWRName);
	CreateNative("Shavit_GetPlayerPB", Native_GetPlayerPB);
	CreateNative("Shavit_GetRankForTime", Native_GetRankForTime);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-wr");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// debug because I was making this all by myself and no one wanted to help me *sniff*
	#if defined DEBUG
	RegConsoleCmd("sm_junk", Command_Junk);
	#endif

	// forwards
	gH_OnWorldRecord = CreateGlobalForward("Shavit_OnWorldRecord", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnFinish_Post = CreateGlobalForward("Shavit_OnFinish_Post", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnWRDeleted = CreateGlobalForward("Shavit_OnWRDeleted", ET_Event, Param_Cell, Param_Cell);

	// player commands
	RegConsoleCmd("sm_wr", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_wr [map]");
	RegConsoleCmd("sm_worldrecord", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_worldrecord [map]");
	RegConsoleCmd("sm_recent", Command_RecentRecords, "View the recent #1 times set.");
	RegConsoleCmd("sm_recentrecords", Command_RecentRecords, "View the recent #1 times set.");
	RegConsoleCmd("sm_rr", Command_RecentRecords, "View the recent #1 times set.");

	// delete records
	RegAdminCmd("sm_delete", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface");
	RegAdminCmd("sm_deleterecord", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface");
	RegAdminCmd("sm_deleterecords", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface");
	RegAdminCmd("sm_deleteall", Command_DeleteAll, ADMFLAG_RCON, "Deletes all the records");

	// cvars
	gCV_RecordsLimit = CreateConVar("shavit_wr_recordlimit", "50", "Limit of records shown in the WR menu.\nAdvised to not set above 1,000 because scrolling through so many pages is useless.\n(And can also cause the command to take long time to run)", 0, true, 1.0);
	gCV_RecentLimit = CreateConVar("shavit_wr_recentlimit", "50", "Limit of records shown in the RR menu.", 0, true, 1.0);

	gCV_RecordsLimit.AddChangeHook(OnConVarChanged);
	gCV_RecentLimit.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	// arrays
	for(int i = 0; i < gI_Styles; i++)
	{
		gA_LeaderBoard[i] = new ArrayList();
	}

	// admin menu
	OnAdminMenuReady(null);

	// colors
	EngineVersion evType = GetEngineVersion();

	strcopy(gS_Color_Time, 16, (evType == Engine_CSS)? "\x07D490CF":"\x07");
	strcopy(gS_Color_Rank, 16, (evType == Engine_CSS)? "\x077585E0":"\x05");
	strcopy(gS_Color_Sync, 16, (evType == Engine_CSS)? "\x07B590D4":"\x06");
	strcopy(gS_Color_Better, 16, (evType == Engine_CSS)? "\x07AD3BA6":"\x0C");
	strcopy(gS_Color_Worse, 16, (evType == Engine_CSS)? "\x07CCCCCC":"\x08");

	// modules
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_Stats = LibraryExists("shavit-stats");

	// mysql
	Shavit_GetDB(gH_SQL);
	SQL_SetPrefix();
	SetSQLInfo();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gI_RecordsLimit = gCV_RecordsLimit.BoolValue;
	gI_RecentLimit = gCV_RecentLimit.BoolValue;
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

public void OnAdminMenuReady(Handle topmenu)
{
	if(LibraryExists("adminmenu") && ((gH_AdminMenu = GetAdminTopMenu()) != null))
	{
		TopMenuObject tmoTimer = FindTopMenuCategory(gH_AdminMenu, "Timer Commands");

		if(tmoTimer != INVALID_TOPMENUOBJECT)
		{
			AddToTopMenu(gH_AdminMenu, "sm_deleteall", TopMenuObject_Item, AdminMenu_DeleteAll, tmoTimer, "sm_deleteall", ADMFLAG_RCON);
			AddToTopMenu(gH_AdminMenu, "sm_delete", TopMenuObject_Item, AdminMenu_Delete, tmoTimer, "sm_delete", ADMFLAG_RCON);
		}
	}
}

public void AdminMenu_Delete(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		strcopy(buffer, maxlength, "Delete a single record");
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
		strcopy(buffer, maxlength, "Delete ALL map records");
	}

	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteAll(param, 0);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit"))
	{
		Shavit_GetDB(gH_SQL);
	}

	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
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
		gH_SQL = null;
	}

	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}

	else if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = false;
	}

	else if(StrEqual(name, "adminmenu"))
	{
		gH_AdminMenu = null;
	}
}

public void OnMapStart()
{
	GetCurrentMap(gS_Map, 128);

	if(gH_SQL != null)
	{
		UpdateWRCache();
	}

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
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
		Shavit_GetStyleStrings(view_as<BhopStyle>(i), sStyleName, gS_StyleStrings[i][sStyleName], 128);
		Shavit_GetStyleStrings(view_as<BhopStyle>(i), sShortName, gS_StyleStrings[i][sShortName], 128);
	}

	gI_Styles = styles;
}

public void OnClientPutInServer(int client)
{
	for(int i = 0; i < gI_Styles; i++)
	{
		gF_PlayerRecord[client][i] = 0.0;
	}

	if(!IsClientConnected(client) || IsFakeClient(client) || gH_SQL == null)
	{
		return;
	}

	UpdateClientCache(client);
}

public void UpdateClientCache(int client)
{
	char sAuthID[32];
	GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

	char sQuery[256];
	FormatEx(sQuery, 256, "SELECT time, style FROM %splayertimes WHERE map = '%s' AND auth = '%s';", gS_MySQLPrefix, gS_Map, sAuthID);
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

	while(results.FetchRow())
	{
		int style = results.FetchInt(1);

		if(style >= gI_Styles || style < 0)
		{
			continue;
		}

		gF_PlayerRecord[client][style] = results.FetchFloat(0);
	}
}

public void UpdateWRCache()
{
	char sQuery[512];
	// thanks Ollie Jones from stackoverflow! http://stackoverflow.com/a/36239523/5335680
	// was a bit confused with this one :s
	FormatEx(sQuery, 512, "SELECT p.style, p.id, s.time, u.name FROM %splayertimes p JOIN(SELECT style, MIN(time) time FROM %splayertimes WHERE map = '%s' GROUP BY style) s ON p.style = s.style AND p.time = s.time JOIN %susers u ON p.auth = u.auth;", gS_MySQLPrefix, gS_MySQLPrefix, gS_Map, gS_MySQLPrefix);

	gH_SQL.Query(SQL_UpdateWRCache_Callback, sQuery, 0, DBPrio_Low);
}

public void SQL_UpdateWRCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR cache update) SQL query failed. Reason: %s", error);

		return;
	}

	// resultset structure
	// FIELD 0: style
	// FIELD 1: id
	// FIELD 2: time - sorted
	// FIELD 3: name

	// reset cache
	for(int i = 0; i < gI_Styles; i++)
	{
		if(gA_StyleSettings[i][bUnranked])
		{
			continue;
		}

		strcopy(gS_WRName[i], MAX_NAME_LENGTH, "invalid");
		gF_WRTime[i] = 0.0;
		gI_RecordAmount[i] = 0;
	}

	// setup cache again, dynamically and not hardcoded
	while(results.FetchRow())
	{
		int style = results.FetchInt(0);

		if(style >= gI_Styles || style < 0)
		{
			continue;
		}

		gI_WRRecordID[style] = results.FetchInt(1);
		gF_WRTime[style] = results.FetchFloat(2);
		results.FetchString(3, gS_WRName[style], MAX_NAME_LENGTH);
	}

	UpdateLeaderboards();
}

public int Native_GetWRTime(Handle handler, int numParams)
{
	SetNativeCellRef(2, gF_WRTime[GetNativeCell(1)]);
}

public int Native_GetWRRecordID(Handle handler, int numParams)
{
	SetNativeCellRef(2, gI_WRRecordID[GetNativeCell(1)]);
}

public int Native_GetWRName(Handle handler, int numParams)
{
	SetNativeString(2, gS_WRName[GetNativeCell(1)], GetNativeCell(3));
}

public int Native_GetPlayerPB(Handle handler, int numParams)
{
	SetNativeCellRef(3, gF_PlayerRecord[GetNativeCell(1)][GetNativeCell(2)]);
}

public int Native_GetRankForTime(Handle handler, int numParams)
{
	return GetRankForTime(GetNativeCell(1), GetNativeCell(2));
}

#if defined DEBUG
// debug
public Action Command_Junk(int client, int args)
{
	char[] sQuery = new char[256];

	char[] sAuth = new char[32];
	GetClientAuthId(client, AuthId_Steam3, sAuth, 32);
	FormatEx(sQuery, 256, "INSERT INTO %splayertimes (auth, map, time, jumps, date, style, strafes, sync) VALUES ('%s', '%s', %.03f, %d, %d, 0, %d, %.02f);", gS_MySQLPrefix, sAuth, gS_Map, GetRandomFloat(10.0, 20.0), GetRandomInt(5, 15), GetTime(), GetRandomInt(5, 15), GetRandomFloat(50.0, 99.99));

	SQL_LockDatabase(gH_SQL);
	SQL_FastQuery(gH_SQL, sQuery);
	SQL_UnlockDatabase(gH_SQL);

	return Plugin_Handled;
}
#endif

public Action Command_Delete(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_Delete);
	menu.SetTitle("Delete a record from:");

	for(int i = 0; i < gI_Styles; i++)
	{
		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		menu.AddItem(sInfo, gS_StyleStrings[i][sStyleName]);
	}

	menu.ExitButton = true;

	menu.Display(client, 20);

	return Plugin_Handled;
}

public Action Command_DeleteAll(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char[] sDisplayMap = new char[strlen(gS_Map) + 1];
	GetMapDisplayName(gS_Map, sDisplayMap, strlen(gS_Map) + 1);

	char[] sFormattedTitle = new char[192];
	FormatEx(sFormattedTitle, 192, "Delete ALL the records for \"%s\"?", sDisplayMap);

	Menu m = new Menu(MenuHandler_DeleteAll);
	m.SetTitle(sFormattedTitle);

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		m.AddItem("-1", "NO!");
	}

	m.AddItem("yes", "YES!!! DELETE ALL THE RECORDS!!! THIS ACTION CANNOT BE REVERTED!!!");

	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		m.AddItem("-1", "NO!");
	}

	m.ExitButton = true;

	m.Display(client, 20);

	return Plugin_Handled;
}

public int MenuHandler_DeleteAll(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		m.GetItem(param2, info, 16);

		if(StringToInt(info) == -1)
		{
			Shavit_PrintToChat(param1, "Aborted deletion.");

			return 0;
		}

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "DELETE FROM %splayertimes WHERE map = '%s';", gS_MySQLPrefix, gS_Map);

		gH_SQL.Query(DeleteAll_Callback, sQuery, GetClientSerial(param1), DBPrio_High);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public int MenuHandler_Delete(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		m.GetItem(param2, info, 16);

		OpenDelete(param1, view_as<BhopStyle>(StringToInt(info)));

		UpdateLeaderboards();
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public void OpenDelete(int client, BhopStyle style)
{
	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "SELECT p.id, u.name, p.time, p.jumps FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE map = '%s' AND style = '%d' ORDER BY time ASC LIMIT 1000;", gS_MySQLPrefix, gS_MySQLPrefix, gS_Map, style);

	DataPack datapack = new DataPack();
	datapack.WriteCell(GetClientSerial(client));
	datapack.WriteCell(style);

	gH_SQL.Query(SQL_OpenDelete_Callback, sQuery, datapack, DBPrio_High);
}

public void SQL_OpenDelete_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	ResetPack(data);
	int client = GetClientFromSerial(ReadPackCell(data));
	BhopStyle style = ReadPackCell(data);
	delete view_as<DataPack>(data);

	if(results == null)
	{
		LogError("Timer (WR OpenDelete) SQL query failed. Reason: %s", error);

		return;
	}

	if(client == 0)
	{
		return;
	}

	char[] sDisplayMap = new char[strlen(gS_Map) + 1];
	GetMapDisplayName(gS_Map, sDisplayMap, strlen(gS_Map) + 1);

	char[] sFormattedTitle = new char[256];
	FormatEx(sFormattedTitle, 256, "Records for %s:\n(%s)", sDisplayMap, gS_StyleStrings[style][sStyleName]);

	Menu m = new Menu(OpenDelete_Handler);
	m.SetTitle(sFormattedTitle);

	int iCount = 0;

	while(results.FetchRow())
	{
		iCount++;

		// 0 - record id, for statistic purposes.
		int id = results.FetchInt(0);
		char[] sID = new char[8];
		IntToString(id, sID, 8);

		// 1 - player name
		char[] sName = new char[MAX_NAME_LENGTH];
		results.FetchString(1, sName, MAX_NAME_LENGTH);

		// 2 - time
		float fTime = results.FetchFloat(2);
		char[] sTime = new char[16];
		FormatSeconds(fTime, sTime, 16);

		// 3 - jumps
		int iJumps = results.FetchInt(3);

		char[] sDisplay = new char[128];
		FormatEx(sDisplay, 128, "#%d - %s - %s (%d jump%s)", iCount, sName, sTime, iJumps, (iJumps != 1)? "s":"");
		m.AddItem(sID, sDisplay);
	}

	if(iCount == 0)
	{
		m.AddItem("-1", "No records found.");
	}

	m.ExitButton = true;
	m.Display(client, 20);
}

public int OpenDelete_Handler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		m.GetItem(param2, info, 16);

		if(StringToInt(info) == -1)
		{
			return 0;
		}

		Menu m2 = new Menu(DeleteConfirm_Handler);
		m2.SetTitle("Are you sure?");

		for(int i = 1; i <= GetRandomInt(1, 4); i++)
		{
			m2.AddItem("-1", "NO!");
		}

		m2.AddItem(info, "YES!!! DELETE THE RECORD!!!");

		for(int i = 1; i <= GetRandomInt(1, 3); i++)
		{
			m2.AddItem("-1", "NO!");
		}

		m2.ExitButton = true;

		m2.Display(param1, 20);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public int DeleteConfirm_Handler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		m.GetItem(param2, info, 16);
		int iRecordID = StringToInt(info);

		if(iRecordID == -1)
		{
			Shavit_PrintToChat(param1, "Aborted deletion.");

			return 0;
		}

		for(int i = 0; i < gI_Styles; i++)
		{
			if(gA_StyleSettings[i][bUnranked] || gI_WRRecordID[i] != iRecordID)
			{
				continue;
			}

			Call_StartForward(gH_OnWRDeleted);
			Call_PushCell(i);
			Call_PushCell(iRecordID);
			Call_Finish();
		}

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "DELETE FROM %splayertimes WHERE id = %d;", gS_MySQLPrefix, iRecordID);

		gH_SQL.Query(DeleteConfirm_Callback, sQuery, GetClientSerial(param1), DBPrio_High);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public void DeleteConfirm_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR DeleteConfirm) SQL query failed. Reason: %s", error);

		return;
	}

	UpdateWRCache();

	for(int i = 1; i <= MaxClients; i++)
	{
		OnClientPutInServer(i);
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	Shavit_PrintToChat(client, "Deleted record.");
}

public void DeleteAll_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR DeleteAll) SQL query failed. Reason: %s", error);

		return;
	}

	UpdateWRCache();

	for(int i = 1; i <= MaxClients; i++)
	{
		OnClientPutInServer(i);
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		if(gA_StyleSettings[i][bUnranked])
		{
			continue;
		}

		Call_StartForward(gH_OnWRDeleted);
		Call_PushCell(i);
		Call_PushCell(-1);
		Call_Finish();
	}

	Shavit_PrintToChat(client, "Deleted ALL records for \"%s\".", gS_Map);
}

public Action Command_WorldRecord(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!args)
	{
		strcopy(gS_ClientMap[client], 192, gS_Map);
	}

	else
	{
		GetCmdArgString(gS_ClientMap[client], 192);
	}

	return ShowWRStyleMenu(client, gS_ClientMap[client]);
}

public Action ShowWRStyleMenu(int client, const char[] map)
{
	Menu menu = new Menu(MenuHandler_StyleChooser);
	menu.SetTitle("Choose a style:");

	for(int i = 0; i < gI_Styles; i++)
	{
		if(gA_StyleSettings[i][bUnranked])
		{
			continue;
		}

		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		menu.AddItem(sInfo, gS_StyleStrings[i][sStyleName]);
	}

	// should NEVER happen
	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "Nothing");
	}

	menu.ExitButton = true;

	menu.Display(client, 30);

	return Plugin_Handled;
}

public int MenuHandler_StyleChooser(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!IsValidClient(param1))
		{
			return 0;
		}

		char[] sInfo = new char[8];
		menu.GetItem(param2, sInfo, 8);

		int iStyle = StringToInt(sInfo);

		if(iStyle == -1)
		{
			Shavit_PrintToChat(param1, "FATAL ERROR: No styles are available. Contact the server owner immediately!");

			return 0;
		}

		gBS_LastWR[param1] = view_as<BhopStyle>(iStyle);

		StartWRMenu(param1, gS_ClientMap[param1], iStyle);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void StartWRMenu(int client, const char[] map, int style)
{
	DataPack dp = new DataPack();
	dp.WriteCell(GetClientSerial(client));
	dp.WriteString(map);

	int iLength = ((strlen(map) * 2) + 1);
	char[] sEscapedMap = new char[iLength];
	gH_SQL.Escape(map, sEscapedMap, iLength);

	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "SELECT p.id, u.name, p.time, p.jumps, p.auth FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE map = '%s' AND style = %d ORDER BY time ASC;", gS_MySQLPrefix, gS_MySQLPrefix, sEscapedMap, style);

	gH_SQL.Query(SQL_WR_Callback, sQuery, dp, DBPrio_High);

	return;
}

public void SQL_WR_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	ResetPack(data);

	int serial = ReadPackCell(data);

	char[] sMap = new char[192];
	ReadPackString(data, sMap, 192);

	delete view_as<DataPack>(data);

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

	char[] sAuth = new char[32];
	GetClientAuthId(client, AuthId_Steam3, sAuth, 32);

	Menu m = new Menu(WRMenu_Handler);

	int iCount = 0;
	int iMyRank = 0;

	while(results.FetchRow())
	{
		// add item to menu and don't overflow with too many entries
		if(++iCount <= gI_RecordsLimit)
		{
			// 0 - record id, for statistic purposes.
			int id = results.FetchInt(0);
			char[] sID = new char[8];
			IntToString(id, sID, 8);

			// 1 - player name
			char[] sName = new char[MAX_NAME_LENGTH];
			results.FetchString(1, sName, MAX_NAME_LENGTH);

			// 2 - time
			float fTime = results.FetchFloat(2);
			char[] sTime = new char[16];
			FormatSeconds(fTime, sTime, 16);

			// 3 - jumps
			int iJumps = results.FetchInt(3);

			char[] sDisplay = new char[128];
			FormatEx(sDisplay, 128, "#%d - %s - %s (%d jump%s)", iCount, sName, sTime, iJumps, (iJumps != 1)? "s":"");
			m.AddItem(sID, sDisplay);
		}

		// check if record exists in the map's top X
		char[] sQueryAuth = new char[32];
		results.FetchString(4, sQueryAuth, 32);

		if(StrEqual(sQueryAuth, sAuth))
		{
			iMyRank = iCount;
		}
	}

	char[] sDisplayMap = new char[strlen(sMap) + 1];
	GetMapDisplayName(sMap, sDisplayMap, strlen(sMap) + 1);

	char[] sFormattedTitle = new char[256];

	if(m.ItemCount == 0)
	{
		FormatEx(sFormattedTitle, 256, "Records for %s", sDisplayMap);
		m.SetTitle(sFormattedTitle);

		m.AddItem("-1", "No records found.");
	}

	else
	{
		int iRecords = results.RowCount;

		// [32] just in case there are 150k records on a map and you're ranked 100k or something
		char[] sRanks = new char[32];

		if(gF_PlayerRecord[client][gBS_LastWR[client]] == 0.0)
		{
			FormatEx(sRanks, 32, "(%d record%s)", iRecords, (iRecords != 1)? "s":"");
		}

		else
		{
			FormatEx(sRanks, 32, "(#%d/%d)", iMyRank, gI_RecordAmount[gBS_LastWR[client]]);
		}

		FormatEx(sFormattedTitle, 192, "Records for %s:\n%s", sDisplayMap, sRanks);
		m.SetTitle(sFormattedTitle);
	}

	m.ExitBackButton = true;
	m.Display(client, 20);
}

public int WRMenu_Handler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[16];
		m.GetItem(param2, sInfo, 16);
		int id = StringToInt(sInfo);

		if(id != -1)
		{
			OpenSubMenu(param1, id);
		}

		else
		{
			ShowWRStyleMenu(param1, gS_ClientMap[param1]);
		}
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowWRStyleMenu(param1, gS_ClientMap[param1]);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public Action Command_RecentRecords(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "SELECT p.id, p.map, u.name, MIN(p.time), p.jumps, p.style, p.points FROM %splayertimes p JOIN %susers u ON p.auth = u.auth GROUP BY p.map, p.style ORDER BY date DESC LIMIT %d;", gS_MySQLPrefix, gS_MySQLPrefix, gI_RecentLimit);

	gH_SQL.Query(SQL_RR_Callback, sQuery, GetClientSerial(client), DBPrio_High);

	return Plugin_Handled;
}

public void SQL_RR_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (RR SELECT) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	Menu m = new Menu(RRMenu_Handler);
	m.SetTitle("Recent %d record%s:", gI_RecentLimit, (gI_RecentLimit != 1)? "s":"");

	while(results.FetchRow())
	{
		char[] sMap = new char[192];
		results.FetchString(1, sMap, 192);

		char[] sDisplayMap = new char[64];
		GetMapDisplayName(sMap, sDisplayMap, 64);

		char[] sName = new char[MAX_NAME_LENGTH];
		results.FetchString(2, sName, MAX_NAME_LENGTH);

		char[] sTime = new char[16];
		float fTime = results.FetchFloat(3);
		FormatSeconds(fTime, sTime, 16);

		int iJumps = results.FetchInt(4);
		BhopStyle bsStyle = view_as<BhopStyle>(results.FetchInt(5));
		float fPoints = results.FetchFloat(6);

		char[] sDisplay = new char[192];

		if(gB_Rankings && fPoints > 0.0)
		{
			FormatEx(sDisplay, 192, "[%s] %s - %s @ %s (%.03f points)", gS_StyleStrings[bsStyle][sShortName], sDisplayMap, sName, sTime, fPoints);
		}

		else
		{
			FormatEx(sDisplay, 192, "[%s] %s - %s @ %s (%d jump%s)", gS_StyleStrings[bsStyle][sShortName], sDisplayMap, sName, sTime, iJumps, (iJumps != 1)? "s":"");
		}

		char[] sInfo = new char[192];
		FormatEx(sInfo, 192, "%d;%s", results.FetchInt(0), sMap);

		m.AddItem(sInfo, sDisplay);
	}

	if(m.ItemCount == 0)
	{
		m.AddItem("-1", "No records found.");
	}

	m.ExitButton = true;
	m.Display(client, 60);
}

public int RRMenu_Handler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[192];
		m.GetItem(param2, sInfo, 192);

		if(StringToInt(sInfo) != -1)
		{
			char[][] sExploded = new char[2][192];
			ExplodeString(sInfo, ";", sExploded, 2, 192, true);

			strcopy(gS_ClientMap[param1], 192, sExploded[1]);

			OpenSubMenu(param1, StringToInt(sExploded[0]));
		}

		else
		{
			ShowWRStyleMenu(param1, gS_ClientMap[param1]);
		}
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowWRStyleMenu(param1, gS_ClientMap[param1]);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public void OpenSubMenu(int client, int id)
{
	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "SELECT u.name, p.time, p.jumps, p.style, u.auth, p.date, p.map, p.strafes, p.sync, p.points FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE p.id = %d LIMIT 1;", gS_MySQLPrefix, gS_MySQLPrefix, id);

	gH_SQL.Query(SQL_SubMenu_Callback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void SQL_SubMenu_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR SUBMENU) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	Menu m = new Menu(SubMenu_Handler);

	char[] sFormattedTitle = new char[256];
	char[] sName = new char[MAX_NAME_LENGTH];
	char[] sAuthID = new char[32];
	char[] sDisplayMap = new char[192];

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
		FormatEx(sDisplay, 128, "Style: %s", gS_StyleStrings[bsStyle][sStyleName]);
		m.AddItem("-1", sDisplay);

		// 6 - map
		char[] sMap = new char[192];
		results.FetchString(6, sMap, 192);
		GetMapDisplayName(sMap, sDisplayMap, 192);

		float fPoints = results.FetchFloat(9);

		if(gB_Rankings && fPoints > 0.0)
		{
			FormatEx(sDisplay, 128, "Points: %.03f", fPoints);
			m.AddItem("-1", sDisplay);
		}

		// 4 - steamid3
		results.FetchString(4, sAuthID, 32);

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

		m.AddItem(sAuthID, "Player stats");
	}

	else
	{
		m.AddItem("-1", "Database error");
	}

	if(strlen(sName) > 0)
	{
		FormatEx(sFormattedTitle, 256, "%s %s\n--- %s:", sName, sAuthID, sDisplayMap);
	}

	else
	{
		strcopy(sFormattedTitle, 256, "ERROR");
	}

	m.SetTitle(sFormattedTitle);
	m.ExitBackButton = true;
	m.Display(client, 20);
}

public int SubMenu_Handler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[32];
		m.GetItem(param2, sInfo, 32);

		if(gB_Stats && StringToInt(sInfo) != -1)
		{
			Shavit_OpenStatsMenu(param1, sInfo);
		}

		else
		{
			StartWRMenu(param1, gS_ClientMap[param1], view_as<int>(gBS_LastWR[param1]));
		}
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		StartWRMenu(param1, gS_ClientMap[param1], view_as<int>(gBS_LastWR[param1]));
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
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

		char[] sQuery = new char[512];
		FormatEx(sQuery, 512, "CREATE TABLE IF NOT EXISTS `%splayertimes` (`id` %s, `auth` VARCHAR(32), `map` VARCHAR(192), `time` FLOAT, `jumps` INT, `style` INT, `date` VARCHAR(32), `strafes` INT, `sync` FLOAT, `points` FLOAT NOT NULL DEFAULT 0%s);", gS_MySQLPrefix, gB_MySQL? "INT NOT NULL AUTO_INCREMENT":"INTEGER PRIMARY KEY", gB_MySQL? ", PRIMARY KEY (`id`)":"");

		gH_SQL.Query(SQL_CreateTable_Callback, sQuery, 0, DBPrio_High);
	}
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR module) error! Users' times table creation failed. Reason: %s", error);

		return;
	}

	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			OnClientPutInServer(i);
		}

		gB_Late = false;
	}

	char[] sQuery = new char[64];
	FormatEx(sQuery, 64, "SELECT strafes FROM %splayertimes LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration1_Callback, sQuery);

	if(gB_MySQL) // this isn't possible in sqlite
	{
		FormatEx(sQuery, 64, "ALTER TABLE %splayertimes MODIFY date VARCHAR(32);", gS_MySQLPrefix);
		gH_SQL.Query(SQL_AlterTable2_Callback, sQuery);
	}

	FormatEx(sQuery, 64, "SELECT points FROM %splayertimes LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration3_Callback, sQuery);
}

public void SQL_TableMigration1_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		char[] sQuery = new char[256];

		if(gB_MySQL)
		{
			FormatEx(sQuery, 256, "ALTER TABLE `%splayertimes` ADD (`strafes` INT NOT NULL DEFAULT 0, `sync` FLOAT NOT NULL DEFAULT 0);", gS_MySQLPrefix);
			gH_SQL.Query(SQL_AlterTable1_Callback, sQuery);
		}

		else
		{
			FormatEx(sQuery, 256, "ALTER TABLE `%splayertimes` ADD COLUMN `strafes` INT NOT NULL DEFAULT 0;", gS_MySQLPrefix);
			gH_SQL.Query(SQL_AlterTable1_Callback, sQuery);

			FormatEx(sQuery, 256, "ALTER TABLE `%splayertimes` ADD COLUMN `sync` FLOAT NOT NULL DEFAULT 0;", gS_MySQLPrefix);
			gH_SQL.Query(SQL_AlterTable1_Callback, sQuery);
		}
	}
}

public void SQL_AlterTable1_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR module) error! Times' table migration (1) failed. Reason: %s", error);

		return;
	}
}

public void SQL_AlterTable2_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR module) error! Times' table migration (2) failed. Reason: %s", error);

		return;
	}
}

public void SQL_TableMigration3_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "ALTER TABLE `%splayertimes` ADD %s;", gS_MySQLPrefix, gB_MySQL? "(`points` FLOAT NOT NULL DEFAULT 0)":"COLUMN `points` FLOAT NOT NULL DEFAULT 0");
		gH_SQL.Query(SQL_AlterTable3_Callback, sQuery);
	}
}

public void SQL_AlterTable3_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR module) error! Times' table migration (3) failed. Reason: %s", error);

		return;
	}
}

public void Shavit_OnFinish(int client, BhopStyle style, float time, int jumps, int strafes, float sync)
{
	char[] sTime = new char[32];
	FormatSeconds(time, sTime, 32);

	// 0 - no query
	// 1 - insert
	// 2 - update
	int overwrite = 0;

	if(gA_StyleSettings[style][bUnranked])
	{
		overwrite = 0; // ugly way of not writing to database
	}

	else if(gF_PlayerRecord[client][style] == 0.0)
	{
		overwrite = 1;
	}

	else if(time <= gF_PlayerRecord[client][style])
	{
		overwrite = 2;
	}

	if(overwrite > 0 && (time < gF_WRTime[style] || gF_WRTime[style] == 0.0)) // WR?
	{
		gF_WRTime[style] = time;

		Call_StartForward(gH_OnWorldRecord);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_PushCell(strafes);
		Call_PushCell(sync);
		Call_Finish();

		UpdateWRCache();
	}

	int iRank = GetRankForTime(style, time);

	float fDifference = (gF_PlayerRecord[client][style] - time);

	if(fDifference < 0.0)
	{
		fDifference = -fDifference;
	}

	char[] sDifference = new char[16];
	FormatSeconds(fDifference, sDifference, 16, true);

	char[] sSync = new char[32]; // 32 because colors
	FormatEx(sSync, 32, (sync != -1.0)? " @ %s%.02f%%":"", gS_Color_Sync, sync);

	if(overwrite > 0)
	{
		char[] sAuthID = new char[32];
		GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

		char[] sQuery = new char[512];

		if(overwrite == 1) // insert
		{
			Shavit_PrintToChatAll("\x03%N\x01 finished (%s) in %s%s\x01 (%s#%d\x01) with %d jump%s, %d strafe%s%s\x01.", client, gS_StyleStrings[style][sStyleName], gS_Color_Time, sTime, gS_Color_Rank, iRank, jumps, (jumps != 1)? "s":"", strafes, (strafes != 1)? "s":"", sSync);

			// prevent duplicate records in case there's a long enough lag for the mysql server between two map finishes
			// TODO: work on a solution that can function the same while not causing lost records
			if(gH_SQL == null)
			{
				return;
			}

			FormatEx(sQuery, 512, "INSERT INTO %splayertimes (auth, map, time, jumps, date, style, strafes, sync) VALUES ('%s', '%s', %.03f, %d, %d, %d, %d, %.2f);", gS_MySQLPrefix, sAuthID, gS_Map, time, jumps, GetTime(), style, strafes, sync);
		}

		else // update
		{
			Shavit_PrintToChatAll("\x03%N\x01 finished (%s) in %s%s\x01 (%s#%d\x01) with %d jump%s, %d strafe%s%s\x01. %s(-%s)", client, gS_StyleStrings[style][sStyleName], gS_Color_Time, sTime, gS_Color_Rank, iRank, jumps, (jumps != 1)? "s":"", strafes, (strafes != 1)? "s":"", sSync, gS_Color_Better, sDifference);

			FormatEx(sQuery, 512, "UPDATE %splayertimes SET time = %.03f, jumps = %d, date = %d, strafes = %d, sync = %.02f WHERE map = '%s' AND auth = '%s' AND style = '%d';", gS_MySQLPrefix, time, jumps, GetTime(), strafes, sync, gS_Map, sAuthID, style);
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
		Call_PushCell(overwrite);
		Call_Finish();

		gF_PlayerRecord[client][style] = time;
	}

	else if(overwrite == 0 && !gA_StyleSettings[style][bUnranked])
	{
		Shavit_PrintToChat(client, "You have finished (%s) in %s%s\x01 with %d jump%s, %d strafe%s%s\x01. %s(+%s)", gS_StyleStrings[style][sStyleName], gS_Color_Time, sTime, jumps, (jumps != 1)? "s":"", strafes, (strafes != 1)? "s":"", sSync, gS_Color_Worse, sDifference);
	}

	else
	{
		Shavit_PrintToChat(client, "You have finished (%s) in %s%s\x01 with %d jump%s, %d strafe%s%s\x01.", gS_StyleStrings[style][sStyleName], gS_Color_Time, sTime, jumps, (jumps != 1)? "s":"", strafes, (strafes != 1)? "s":"", sSync);
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

	UpdateWRCache();
	UpdateClientCache(client);
}

public void UpdateLeaderboards()
{
	char[] sQuery = new char[192];
	FormatEx(sQuery, 192, "SELECT style, time FROM %splayertimes WHERE map = '%s' ORDER BY time ASC;", gS_MySQLPrefix, gS_Map);

	gH_SQL.Query(SQL_UpdateLeaderboards_Callback, sQuery, 0, DBPrio_Low);
}

public void SQL_UpdateLeaderboards_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR UpdateLeaderboards) SQL query failed. Reason: %s", error);

		return;
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		gI_RecordAmount[i] = 0;
		gA_LeaderBoard[i].Clear();
	}

	while(results.FetchRow())
	{
		BhopStyle style = view_as<BhopStyle>(results.FetchInt(0));

		if(view_as<int>(style) >= gI_Styles || gA_StyleSettings[style][bUnranked])
		{
			continue;
		}

		gA_LeaderBoard[style].Push(results.FetchFloat(1));
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		if(view_as<int>(i) >= gI_Styles || gA_StyleSettings[i][bUnranked])
		{
			continue;
		}

		SortADTArray(gA_LeaderBoard[i], Sort_Ascending, Sort_Float);
		gI_RecordAmount[i] = gA_LeaderBoard[i].Length;
	}
}

public int GetRankForTime(BhopStyle style, float time)
{
	if(time < gF_WRTime[style])
	{
		return 1;
	}

	for(int i = 0; i < gI_RecordAmount[style]; i++)
	{
		if(time < gA_LeaderBoard[style].Get(i))
		{
			return ++i;
		}
	}

	return gI_RecordAmount[style] + 1;
}
