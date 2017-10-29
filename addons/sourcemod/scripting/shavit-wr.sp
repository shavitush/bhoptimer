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

#pragma newdecls required
#pragma semicolon 1

// #define DEBUG

bool gB_Late = false;
bool gB_Rankings = false;
bool gB_Stats = false;

// forwards
Handle gH_OnWorldRecord = null;
Handle gH_OnFinish_Post = null;
Handle gH_OnWRDeleted = null;
Handle gH_OnWorstRecord = null;

// database handle
Database gH_SQL = null;
bool gB_MySQL = false;

// cache
int gBS_LastWR[MAXPLAYERS+1];
char gS_ClientMap[MAXPLAYERS+1][128];
int gI_LastTrack[MAXPLAYERS+1];
char gS_Map[160]; // blame workshop paths being so fucking long
ArrayList gA_ValidMaps = null;
int gI_ValidMaps = 1;

// current wr stats
float gF_WRTime[STYLE_LIMIT][TRACKS_SIZE];
int gI_WRRecordID[STYLE_LIMIT][TRACKS_SIZE];
char gS_WRName[STYLE_LIMIT][TRACKS_SIZE][MAX_NAME_LENGTH];
int gI_RecordAmount[STYLE_LIMIT][TRACKS_SIZE];
ArrayList gA_LeaderBoard[STYLE_LIMIT][TRACKS_SIZE];
float gF_PlayerRecord[MAXPLAYERS+1][STYLE_LIMIT][TRACKS_SIZE];

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

// timer settings
int gI_Styles = 0;
char gS_StyleStrings[STYLE_LIMIT][STYLESTRINGS_SIZE][128];
any gA_StyleSettings[STYLE_LIMIT][STYLESETTINGS_SIZE];

// chat settings
char gS_ChatStrings[CHATSETTINGS_SIZE][128];

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
	CreateNative("Shavit_GetPlayerPB", Native_GetPlayerPB);
	CreateNative("Shavit_GetRankForTime", Native_GetRankForTime);
	CreateNative("Shavit_GetRecordAmount", Native_GetRecordAmount);
	CreateNative("Shavit_GetWRName", Native_GetWRName);
	CreateNative("Shavit_GetWRRecordID", Native_GetWRRecordID);
	CreateNative("Shavit_GetWRTime", Native_GetWRTime);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-wr");

	gB_Late = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	if(gH_SQL == null)
	{
		Shavit_OnDatabaseLoaded();
	}
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-wr.phrases");

	// debug because I was making this all by myself and no one wanted to help me *sniff*
	#if defined DEBUG
	RegConsoleCmd("sm_junk", Command_Junk);
	#endif

	// forwards
	gH_OnWorldRecord = CreateGlobalForward("Shavit_OnWorldRecord", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnFinish_Post = CreateGlobalForward("Shavit_OnFinish_Post", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnWRDeleted = CreateGlobalForward("Shavit_OnWRDeleted", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_OnWorstRecord = CreateGlobalForward("Shavit_OnWorstRecord", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	// player commands
	RegConsoleCmd("sm_wr", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_wr [map]");
	RegConsoleCmd("sm_worldrecord", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_worldrecord [map]");

	RegConsoleCmd("sm_bwr", Command_WorldRecord_Bonus, "View the leaderboard of a map. Usage: sm_bwr [map]");
	RegConsoleCmd("sm_bworldrecord", Command_WorldRecord_Bonus, "View the leaderboard of a map. Usage: sm_bworldrecord [map]");
	RegConsoleCmd("sm_bonusworldrecord", Command_WorldRecord_Bonus, "View the leaderboard of a map. Usage: sm_bonusworldrecord [map]");

	RegConsoleCmd("sm_recent", Command_RecentRecords, "View the recent #1 times set.");
	RegConsoleCmd("sm_recentrecords", Command_RecentRecords, "View the recent #1 times set.");
	RegConsoleCmd("sm_rr", Command_RecentRecords, "View the recent #1 times set.");

	// delete records
	RegAdminCmd("sm_delete", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface.");
	RegAdminCmd("sm_deleterecord", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface.");
	RegAdminCmd("sm_deleterecords", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface.");
	RegAdminCmd("sm_deleteall", Command_DeleteAll, ADMFLAG_RCON, "Deletes all the records for this map.");
	RegAdminCmd("sm_deletestylerecords", Command_DeleteStyleRecords, ADMFLAG_RCON, "Deletes all the records for a style.");

	// cvars
	gCV_RecordsLimit = CreateConVar("shavit_wr_recordlimit", "50", "Limit of records shown in the WR menu.\nAdvised to not set above 1,000 because scrolling through so many pages is useless.\n(And can also cause the command to take long time to run)", 0, true, 1.0);
	gCV_RecentLimit = CreateConVar("shavit_wr_recentlimit", "50", "Limit of records shown in the RR menu.", 0, true, 1.0);

	gCV_RecordsLimit.AddChangeHook(OnConVarChanged);
	gCV_RecentLimit.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	// admin menu
	OnAdminMenuReady(null);

	// modules
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_Stats = LibraryExists("shavit-stats");

	// cache
	gA_ValidMaps = new ArrayList(192);

	for(int i = 0; i < STYLE_LIMIT; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gA_LeaderBoard[i][j] = new ArrayList();
			gI_RecordAmount[i][j] = 0;
		}
	}

	SQL_SetPrefix();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gI_RecordsLimit = gCV_RecordsLimit.BoolValue;
	gI_RecentLimit = gCV_RecentLimit.BoolValue;
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
			AddToTopMenu(gH_AdminMenu, "sm_deletestylerecords", TopMenuObject_Item, AdminMenu_DeleteStyleRecords, tmoTimer, "sm_deletestylerecords", ADMFLAG_RCON);
		}
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

public void AdminMenu_DeleteStyleRecords(Handle topmenu,  TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%t", "DeleteStyleRecords");
	}

	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteStyleRecords(param, 0);
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

	else if(StrEqual(name, "adminmenu"))
	{
		gH_AdminMenu = null;
	}
}

public void OnMapStart()
{
	if(gH_SQL == null)
	{
		return;
	}

	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);

	if(gH_SQL != null)
	{
		UpdateWRCache();

		char[] sLowerCase = new char[160];
		strcopy(sLowerCase, 160, gS_Map);

		for(int i = 0; i < strlen(sLowerCase); i++)
		{
			if(!IsCharUpper(sLowerCase[i]))
			{
				sLowerCase[i] = CharToLower(sLowerCase[i]);
			}
		}

		gA_ValidMaps.Clear();
		gA_ValidMaps.PushString(sLowerCase);
		gI_ValidMaps = 1;

		char sQuery[128];
		FormatEx(sQuery, 128, "SELECT map FROM %smapzones GROUP BY map;", gS_MySQLPrefix);
		gH_SQL.Query(SQL_UpdateMaps_Callback, sQuery, 0, DBPrio_Low);
	}

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
		Shavit_OnChatConfigLoaded();
	}
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
		char[] sMap = new char[192];
		results.FetchString(0, sMap, 192);

		char[] sLowerCase = new char[128];
		strcopy(sLowerCase, 128, sMap);

		for(int i = 0; i < strlen(sLowerCase); i++)
		{
			if(!IsCharUpper(sLowerCase[i]))
			{
				sLowerCase[i] = CharToLower(sLowerCase[i]);
			}
		}

		if(gA_ValidMaps.FindString(sLowerCase) == -1)
		{
			gA_ValidMaps.PushString(sLowerCase);
			gI_ValidMaps++;
		}
	}

	SortADTArray(gA_ValidMaps, Sort_Ascending, Sort_String);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleSettings(i, gA_StyleSettings[i]);
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i][sStyleName], 128);
		Shavit_GetStyleStrings(i, sShortName, gS_StyleStrings[i][sShortName], 128);
	}

	// arrays
	for(int i = 0; i < styles; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gA_LeaderBoard[i][j].Clear();
		}
	}

	for(int i = styles; i < STYLE_LIMIT; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			delete gA_LeaderBoard[i][j];
		}
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

public void OnClientPutInServer(int client)
{
	for(int i = 0; i < gI_Styles; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gF_PlayerRecord[client][i][j] = 0.0;
		}
	}

	if(!IsClientConnected(client) || IsFakeClient(client) || gH_SQL == null)
	{
		return;
	}

	UpdateClientCache(client);
}

void UpdateClientCache(int client)
{
	char sAuthID[32];
	GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

	char sQuery[256];
	FormatEx(sQuery, 256, "SELECT time, style, track FROM %splayertimes WHERE map = '%s' AND auth = '%s';", gS_MySQLPrefix, gS_Map, sAuthID);
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
		int track = results.FetchInt(2);

		if(style >= gI_Styles || style < 0 || track >= TRACKS_SIZE)
		{
			continue;
		}

		gF_PlayerRecord[client][style][track] = results.FetchFloat(0);
	}
}

void UpdateWRCache()
{
	char sQuery[512];
	// thanks Ollie Jones from stackoverflow! http://stackoverflow.com/a/36239523/5335680
	// was a bit confused with this one :s

	if(gB_MySQL)
	{
		FormatEx(sQuery, 512, "SELECT p.style, p.id, TRUNCATE(LEAST(s.time, p.time), 3), u.name, p.track FROM %splayertimes p JOIN(SELECT style, MIN(time) time, map, track FROM %splayertimes WHERE map = '%s' GROUP BY style, track ORDER BY date ASC) s ON p.style = s.style AND p.time = s.time AND p.map = s.map JOIN %susers u ON p.auth = u.auth GROUP BY p.style, p.track ORDER BY date ASC;", gS_MySQLPrefix, gS_MySQLPrefix, gS_Map, gS_MySQLPrefix);
	}

	// sorry, LEAST() isn't available for SQLITE!
	else
	{
		FormatEx(sQuery, 512, "SELECT p.style, p.id, s.time, u.name, p.track FROM %splayertimes p JOIN(SELECT style, MIN(time) time, map, track FROM %splayertimes WHERE map = '%s' GROUP BY style, track) s ON p.style = s.style AND p.time = s.time AND p.map = s.map AND s.track = p.track JOIN %susers u ON p.auth = u.auth GROUP BY p.style, p.track;", gS_MySQLPrefix, gS_MySQLPrefix, gS_Map, gS_MySQLPrefix);
	}

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
	// FIELD 4: track

	// reset cache
	for(int i = 0; i < gI_Styles; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			strcopy(gS_WRName[i][j], MAX_NAME_LENGTH, "invalid");
			gF_WRTime[i][j] = 0.0;
			gI_RecordAmount[i][j] = 0;
		}
	}

	// setup cache again, dynamically and not hardcoded
	while(results.FetchRow())
	{
		int style = results.FetchInt(0);

		if(style >= gI_Styles || style < 0 || gA_StyleSettings[style][bUnranked])
		{
			continue;
		}

		int track = results.FetchInt(4);

		gI_WRRecordID[style][track] = results.FetchInt(1);
		gF_WRTime[style][track] = results.FetchFloat(2);
		results.FetchString(3, gS_WRName[style][track], MAX_NAME_LENGTH);
		ReplaceString(gS_WRName[style][track], MAX_NAME_LENGTH, "#", "?");
	}

	UpdateLeaderboards();
}

public int Native_GetWRTime(Handle handler, int numParams)
{
	SetNativeCellRef(2, gF_WRTime[GetNativeCell(1)][GetNativeCell(3)]);
}

public int Native_GetWRRecordID(Handle handler, int numParams)
{
	SetNativeCellRef(2, gI_WRRecordID[GetNativeCell(1)][GetNativeCell(3)]);
}

public int Native_GetWRName(Handle handler, int numParams)
{
	SetNativeString(2, gS_WRName[GetNativeCell(1)][GetNativeCell(4)], GetNativeCell(3));
}

public int Native_GetPlayerPB(Handle handler, int numParams)
{
	SetNativeCellRef(3, gF_PlayerRecord[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(4)]);
}

public int Native_GetRankForTime(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(3);

	if(gA_LeaderBoard[style][track].Length == 0)
	{
		return 1;
	}

	return GetRankForTime(style, GetNativeCell(2), track);
}

public int Native_GetRecordAmount(Handle handler, int numParams)
{
	return gI_RecordAmount[GetNativeCell(1)][GetNativeCell(2)];
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

int GetTrackRecordCount(int track)
{
	int count = 0;

	for(int i = 0; i < gI_Styles; i++)
	{
		count += gI_RecordAmount[i][track];
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
		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		int records = GetTrackRecordCount(i);

		char[] sTrack = new char[64];
		GetTrackName(client, i, sTrack, 64);

		if(records > 0)
		{
			Format(sTrack, 64, "%s (%T: %d)", sTrack, "WRRecord", client, records);
		}

		menu.AddItem(sInfo, sTrack, (records > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);

	return Plugin_Handled;
}

public int MenuHandler_Delete_First(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);
		gI_LastTrack[param1] = StringToInt(info);

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

	for(int i = 0; i < gI_Styles; i++)
	{
		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		char[] sDisplay = new char[64];
		FormatEx(sDisplay, 64, "%s (%T: %d)", gS_StyleStrings[i][sStyleName], "WRRecord", client, gI_RecordAmount[i][gI_LastTrack[client]]);

		menu.AddItem(sInfo, gS_StyleStrings[i][sStyleName]);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);
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
		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		int records = GetTrackRecordCount(i);

		char[] sTrack = new char[64];
		GetTrackName(client, i, sTrack, 64);

		if(records > 0)
		{
			Format(sTrack, 64, "%s (%T: %d)", sTrack, "WRRecord", client, records);
		}

		menu.AddItem(sInfo, sTrack, (records > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);

	return Plugin_Handled;
}

public int MenuHandler_DeleteAll_First(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);
		gI_LastTrack[param1] = StringToInt(info);

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
	char[] sTrack = new char[32];
	GetTrackName(client, gI_LastTrack[client], sTrack, 32);

	Menu menu = new Menu(MenuHandler_DeleteAll);
	menu.SetTitle("%T\n ", "DeleteAllRecordsMenuTitle", client, gS_Map, sTrack);

	char[] sMenuItem = new char[64];

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
	menu.Display(client, 20);
}

public int MenuHandler_DeleteAll(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		if(StringToInt(info) == -1)
		{
			Shavit_PrintToChat(param1, "%T", "DeletionAborted", param1);

			return 0;
		}

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "DELETE FROM %splayertimes WHERE map = '%s' AND track = %d;", gS_MySQLPrefix, gS_Map, gI_LastTrack[param1]);

		gH_SQL.Query(DeleteAll_Callback, sQuery, GetClientSerial(param1), DBPrio_High);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_DeleteStyleRecords(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_DeleteStyleRecords);
	menu.SetTitle("%T\n ", "DeleteStyleRecordsRecordsMenuTitle", client, gS_Map);

	for(int i = 0; i < gI_Styles; i++)
	{
		if(gA_StyleSettings[i][bUnranked])
		{
			continue;
		}

		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		char[] sDisplay = new char[64];
		FormatEx(sDisplay, 64, "%s (%d %T)", gS_StyleStrings[i][sStyleName], gI_RecordAmount[i], "WRRecord", client);

		int iTotalAmount = 0;

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			iTotalAmount += gI_RecordAmount[i][j];
		}

		menu.AddItem(sInfo, sDisplay, (iTotalAmount > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	if(menu.ItemCount == 0)
	{
		char[] sNoRecords = new char[64];
		FormatEx(sNoRecords, 64, "%T", "WRMapNoRecords", client);
		menu.AddItem("-1", sNoRecords);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);

	return Plugin_Handled;
}

public int MenuHandler_DeleteStyleRecords(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		int style = StringToInt(info);
		int iTotalAmount = 0;

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			iTotalAmount += gI_RecordAmount[style][j];
		}

		if(iTotalAmount == 0)
		{
			return 0;
		}

		char[] sMenuItem = new char[128];

		Menu submenu = new Menu(MenuHandler_DeleteStyleRecords_Confirm);
		submenu.SetTitle("%T\n ", "DeleteConfirmStyle", param1, gS_StyleStrings[style][sStyleName]);

		for(int i = 1; i <= GetRandomInt(1, 4); i++)
		{
			FormatEx(sMenuItem, 128, "%T", "MenuResponseNo", param1);
			submenu.AddItem("-1", sMenuItem);
		}

		FormatEx(sMenuItem, 128, "%T", "MenuResponseYesStyle", param1, gS_StyleStrings[style][sStyleName]);

		IntToString(style, info, 16);
		submenu.AddItem(info, sMenuItem);

		for(int i = 1; i <= GetRandomInt(1, 3); i++)
		{
			FormatEx(sMenuItem, 128, "%T", "MenuResponseNo", param1);
			submenu.AddItem("-1", sMenuItem);
		}

		submenu.ExitButton = true;
		submenu.Display(param1, 20);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_DeleteStyleRecords_Confirm(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		int style = StringToInt(info);

		if(style == -1)
		{
			Shavit_PrintToChat(param1, "%T", "DeletionAborted", param1);

			return 0;
		}

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "DELETE FROM %splayertimes WHERE map = '%s' AND style = %d;", gS_MySQLPrefix, gS_Map, style);

		DataPack pack = new DataPack();
		pack.WriteCell(GetClientSerial(param1));
		pack.WriteCell(style);

		gH_SQL.Query(DeleteStyleRecords_Callback, sQuery, pack, DBPrio_High);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void DeleteStyleRecords_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	ResetPack(view_as<DataPack>(data));
	int serial = ReadPackCell(data);
	int style = ReadPackCell(data);
	delete view_as<DataPack>(data);

	if(results == null)
	{
		LogError("Timer (WR DeleteStyleRecords) SQL query failed. Reason: %s", error);

		return;
	}

	UpdateWRCache();

	for(int i = 1; i <= MaxClients; i++)
	{
		OnClientPutInServer(i);
	}

	int client = GetClientFromSerial(serial);

	if(client == 0)
	{
		return;
	}

	Shavit_PrintToChat(client, "%T", "DeletedRecordsStyle", client, gS_ChatStrings[sMessageStyle], gS_StyleStrings[style][sStyleName], gS_ChatStrings[sMessageText]);
}

public int MenuHandler_Delete(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		OpenDelete(param1, StringToInt(info));

		UpdateLeaderboards();
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenDelete(int client, int style)
{
	char[] sQuery = new char[512];

	FormatEx(sQuery, 512, "SELECT p.id, u.name, p.time, p.jumps FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE map = '%s' AND style = %d AND track = %d ORDER BY time ASC, date ASC LIMIT 1000;", gS_MySQLPrefix, gS_MySQLPrefix, gS_Map, style, gI_LastTrack[client]);
	DataPack datapack = new DataPack();
	datapack.WriteCell(GetClientSerial(client));
	datapack.WriteCell(style);

	gH_SQL.Query(SQL_OpenDelete_Callback, sQuery, datapack, DBPrio_High);
}

public void SQL_OpenDelete_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	ResetPack(data);
	int client = GetClientFromSerial(ReadPackCell(data));
	int style = ReadPackCell(data);
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

	Menu menu = new Menu(OpenDelete_Handler);
	menu.SetTitle("%t", "ListClientRecords", gS_Map, gS_StyleStrings[style][sStyleName]);

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
		ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");

		// 2 - time
		float time = results.FetchFloat(2);
		char[] sTime = new char[16];
		FormatSeconds(time, sTime, 16);

		// 3 - jumps
		int jumps = results.FetchInt(3);

		char[] sDisplay = new char[128];
		FormatEx(sDisplay, 128, "#%d - %s - %s (%d jump%s)", iCount, sName, sTime, jumps, (jumps != 1)? "s":"");
		menu.AddItem(sID, sDisplay);
	}

	if(iCount == 0)
	{
		char[] sNoRecords = new char[64];
		FormatEx(sNoRecords, 64, "%T", "WRMapNoRecords", client);
		menu.AddItem("-1", sNoRecords);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);
}

public int OpenDelete_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);

		int id = StringToInt(info);

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
	char[] sMenuItem = new char[64];

	Menu menu = new Menu(DeleteConfirm_Handler);
	menu.SetTitle("%T\n ", "DeleteConfirm", client);

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	FormatEx(sMenuItem, 64, "%T", "MenuResponseYesSingle", client);

	char[] info = new char[16];
	IntToString(id, info, 16);
	menu.AddItem(info, sMenuItem);

	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);
}

public int DeleteConfirm_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		menu.GetItem(param2, info, 16);
		int iRecordID = StringToInt(info);

		if(iRecordID == -1)
		{
			Shavit_PrintToChat(param1, "%T", "DeletionAborted", param1);

			return 0;
		}

		for(int i = 0; i < gI_Styles; i++)
		{
			if(gA_StyleSettings[i][bUnranked])
			{
				continue;
			}

			for(int j = 0; j < TRACKS_SIZE; j++)
			{
				if(gI_WRRecordID[i][j] != iRecordID)
				{
					continue;
				}

				Call_StartForward(gH_OnWRDeleted);
				Call_PushCell(i);
				Call_PushCell(iRecordID);
				Call_PushCell(j);
				Call_Finish();
			}
		}

		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "DELETE FROM %splayertimes WHERE id = %d;", gS_MySQLPrefix, iRecordID);

		gH_SQL.Query(DeleteConfirm_Callback, sQuery, GetClientSerial(param1), DBPrio_High);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
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

	Shavit_PrintToChat(client, "%T", "DeletedRecord", client);
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
		Call_PushCell(gI_LastTrack[client]);
		Call_Finish();
	}

	Shavit_PrintToChat(client, "%T", "DeletedRecordsMap", client, gS_ChatStrings[sMessageVariable], gS_Map, gS_ChatStrings[sMessageText]);
}

public Action Command_WorldRecord(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(args == 0)
	{
		strcopy(gS_ClientMap[client], 128, gS_Map);
	}

	else
	{
		GetCmdArgString(gS_ClientMap[client], 128);
		GuessBestMapName(gS_ClientMap[client], gS_ClientMap[client], 128);
	}

	return ShowWRStyleMenu(client, Track_Main);
}

public Action Command_WorldRecord_Bonus(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(args == 0)
	{
		strcopy(gS_ClientMap[client], 128, gS_Map);
	}

	else
	{
		GetCmdArgString(gS_ClientMap[client], 128);
		GuessBestMapName(gS_ClientMap[client], gS_ClientMap[client], 128);
	}

	return ShowWRStyleMenu(client, Track_Bonus);
}

Action ShowWRStyleMenu(int client, int track)
{
	gI_LastTrack[client] = track;

	Menu menu = new Menu(MenuHandler_StyleChooser);
	menu.SetTitle("%T", "WRMenuTitle", client);

	for(int i = 0; i < gI_Styles; i++)
	{
		if(gA_StyleSettings[i][bUnranked])
		{
			continue;
		}

		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		char[] sDisplay = new char[64];

		if(StrEqual(gS_ClientMap[client], gS_Map) && gF_WRTime[i][track] > 0.0)
		{
			char[] sTime = new char[32];
			FormatSeconds(gF_WRTime[i][track], sTime, 32, false);

			FormatEx(sDisplay, 64, "%s - WR: %s", gS_StyleStrings[i][sStyleName], sTime);
		}

		else
		{
			strcopy(sDisplay, 64, gS_StyleStrings[i][sStyleName]);
		}

		menu.AddItem(sInfo, sDisplay, (gI_RecordAmount[i][track] > 0 || !StrEqual(gS_ClientMap[client], gS_Map))? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	// should NEVER happen
	if(menu.ItemCount == 0)
	{
		char[] sMenuItem = new char[64];
		FormatEx(sMenuItem, 64, "%T", "WRStyleNothing", client);
		menu.AddItem("-1", sMenuItem);
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
			Shavit_PrintToChat(param1, "%T", "NoStyles", param1, gS_ChatStrings[sMessageWarning], gS_ChatStrings[sMessageText]);

			return 0;
		}

		gBS_LastWR[param1] = iStyle;

		StartWRMenu(param1, gS_ClientMap[param1], iStyle, gI_LastTrack[param1]);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void StartWRMenu(int client, const char[] map, int style, int track)
{
	DataPack dp = new DataPack();
	dp.WriteCell(GetClientSerial(client));
	dp.WriteCell(track);
	dp.WriteString(map);

	int iLength = ((strlen(map) * 2) + 1);
	char[] sEscapedMap = new char[iLength];
	gH_SQL.Escape(map, sEscapedMap, iLength);

	char[] sQuery = new char[512];

	FormatEx(sQuery, 512, "SELECT p.id, u.name, p.time, p.jumps, p.auth FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE map = '%s' AND style = %d AND track = %d ORDER BY time ASC, date ASC;", gS_MySQLPrefix, gS_MySQLPrefix, sEscapedMap, style, track);
	gH_SQL.Query(SQL_WR_Callback, sQuery, dp, DBPrio_High);

	return;
}

public void SQL_WR_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	ResetPack(data);

	int serial = ReadPackCell(data);
	int track = ReadPackCell(data);

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

	Menu menu = new Menu(WRMenu_Handler);

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
			float time = results.FetchFloat(2);
			char[] sTime = new char[16];
			FormatSeconds(time, sTime, 16);

			// 3 - jumps
			int jumps = results.FetchInt(3);

			char[] sDisplay = new char[128];
			FormatEx(sDisplay, 128, "#%d - %s - %s (%d %T)", iCount, sName, sTime, jumps, "WRJumps", client);
			menu.AddItem(sID, sDisplay);
		}

		// check if record exists in the map's top X
		char[] sQueryAuth = new char[32];
		results.FetchString(4, sQueryAuth, 32);

		if(StrEqual(sQueryAuth, sAuth))
		{
			iMyRank = iCount;
		}
	}

	char[] sFormattedTitle = new char[256];

	if(menu.ItemCount == 0)
	{
		menu.SetTitle("%T", "WRMap", client, sMap);
		char[] sNoRecords = new char[64];
		FormatEx(sNoRecords, 64, "%T", "WRMapNoRecords", client);

		menu.AddItem("-1", sNoRecords);
	}

	else
	{
		int iRecords = results.RowCount;

		// [32] just in case there are 150k records on a map and you're ranked 100k or something
		char[] sRanks = new char[32];

		if(gF_PlayerRecord[client][gBS_LastWR[client]][track] == 0.0 || iMyRank == 0)
		{
			FormatEx(sRanks, 32, "(%d %T)", iRecords, "WRRecord", client);
		}

		else
		{
			FormatEx(sRanks, 32, "(#%d/%d)", iMyRank, gI_RecordAmount[gBS_LastWR[client]]);
		}

		char[] sTrack = new char[32];
		GetTrackName(client, track, sTrack, 32);

		FormatEx(sFormattedTitle, 192, "%T %s: [%s]\n%s", "WRRecordFor", client, sMap, sTrack, sRanks);
		menu.SetTitle(sFormattedTitle);
	}

	menu.ExitBackButton = true;
	menu.Display(client, 20);
}

public int WRMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[16];
		menu.GetItem(param2, sInfo, 16);
		int id = StringToInt(sInfo);

		if(id != -1)
		{
			OpenSubMenu(param1, id);
		}

		else
		{
			ShowWRStyleMenu(param1, gI_LastTrack[param1]);
		}
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowWRStyleMenu(param1, gI_LastTrack[param1]);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
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
	FormatEx(sQuery, 512, "SELECT p.id, p.map, u.name, MIN(p.time), p.jumps, p.style, p.points, p.track FROM %splayertimes p JOIN %susers u ON p.auth = u.auth GROUP BY p.map, p.style, p.track ORDER BY date DESC LIMIT %d;", gS_MySQLPrefix, gS_MySQLPrefix, gI_RecentLimit);

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
	m.SetTitle("%T:", "RecentRecords", client, gI_RecentLimit);

	while(results.FetchRow())
	{
		char[] sMap = new char[192];
		results.FetchString(1, sMap, 192);
		
		char[] sName = new char[MAX_NAME_LENGTH];
		results.FetchString(2, sName, MAX_NAME_LENGTH);

		char[] sTime = new char[16];
		float time = results.FetchFloat(3);
		FormatSeconds(time, sTime, 16);

		int jumps = results.FetchInt(4);
		int style = results.FetchInt(5);
		float fPoints = results.FetchFloat(6);

		char[] sTrack = new char[32];
		GetTrackName(client, results.FetchInt(7), sTrack, 32);

		char[] sDisplay = new char[192];

		if(gB_Rankings && fPoints > 0.0)
		{
			FormatEx(sDisplay, 192, "[%s] [%s] %s - %s @ %s (%.03f %T)", gS_StyleStrings[style][sShortName], sTrack, sMap, sName, sTime, fPoints, "WRPoints", client);
		}

		else
		{
			FormatEx(sDisplay, 192, "[%s] [%s] %s - %s @ %s (%d %T)", gS_StyleStrings[style][sShortName], sTrack, sMap, sName, sTime, jumps, "WRJumps", client);
		}

		char[] sInfo = new char[192];
		FormatEx(sInfo, 192, "%d;%s", results.FetchInt(0), sMap);

		m.AddItem(sInfo, sDisplay);
	}

	if(m.ItemCount == 0)
	{
		char[] sMenuItem = new char[64];
		FormatEx(sMenuItem, 64, "%T", "WRMapNoRecords", client);
		m.AddItem("-1", sMenuItem);
	}

	m.ExitButton = true;
	m.Display(client, 60);
}

public int RRMenu_Handler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[128];
		m.GetItem(param2, sInfo, 128);

		if(StringToInt(sInfo) != -1)
		{
			char[][] sExploded = new char[2][128];
			ExplodeString(sInfo, ";", sExploded, 2, 128, true);

			strcopy(gS_ClientMap[param1], 128, sExploded[1]);

			OpenSubMenu(param1, StringToInt(sExploded[0]));
		}

		else
		{
			ShowWRStyleMenu(param1, gI_LastTrack[param1]);
		}
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowWRStyleMenu(param1, gI_LastTrack[param1]);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

void OpenSubMenu(int client, int id)
{
	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "SELECT u.name, p.time, p.jumps, p.style, u.auth, p.date, p.map, p.strafes, p.sync, p.points, p.track FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE p.id = %d LIMIT 1;", gS_MySQLPrefix, gS_MySQLPrefix, id);

	DataPack datapack = new DataPack();
	datapack.WriteCell(GetClientSerial(client));
	datapack.WriteCell(id);

	gH_SQL.Query(SQL_SubMenu_Callback, sQuery, datapack, DBPrio_High);
}

public void SQL_SubMenu_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR SUBMENU) SQL query failed. Reason: %s", error);

		return;
	}

	ResetPack(data);
	int client = GetClientFromSerial(ReadPackCell(data));
	int id = ReadPackCell(data);
	delete view_as<DataPack>(data);

	if(client == 0)
	{
		return;
	}

	Menu menu = new Menu(SubMenu_Handler);

	char[] sFormattedTitle = new char[256];
	char[] sName = new char[MAX_NAME_LENGTH];
	char[] sAuthID = new char[32];
	char[] sTrack = new char[32];
	char[] sMap = new char[192];

	if(results.FetchRow())
	{
		// 0 - name
		results.FetchString(0, sName, MAX_NAME_LENGTH);

		// 1 - time
		float time = results.FetchFloat(1);
		char[] sTime = new char[16];
		FormatSeconds(time, sTime, 16);

		char[] sDisplay = new char[128];
		FormatEx(sDisplay, 128, "%T: %s", "WRTime", client, sTime);
		menu.AddItem("-1", sDisplay);

		// 2 - jumps
		int jumps = results.FetchInt(2);
		FormatEx(sDisplay, 128, "%T: %d", "WRJumps", client, jumps);
		menu.AddItem("-1", sDisplay);

		// 3 - style
		int style = results.FetchInt(3);
		FormatEx(sDisplay, 128, "%T: %s", "WRStyle", client, gS_StyleStrings[style][sStyleName]);
		menu.AddItem("-1", sDisplay);

		// 6 - map
		results.FetchString(6, sMap, 192);
		
		float fPoints = results.FetchFloat(9);

		if(gB_Rankings && fPoints > 0.0)
		{
			FormatEx(sDisplay, 128, "%T: %.03f", "WRPointsCap", client, fPoints);
			menu.AddItem("-1", sDisplay);
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

		FormatEx(sDisplay, 128, "%T: %s", "WRDate", client, sDate);
		menu.AddItem("-1", sDisplay);

		int strafes = results.FetchInt(7);
		float sync = results.FetchFloat(8);

		if(jumps > 0 || strafes > 0)
		{
			FormatEx(sDisplay, 128, (sync != -1.0)? "%T: %d (%.02f%%)":"%T: %d", "WRStrafes", client, strafes, sync);
			menu.AddItem("-1", sDisplay);
		}

		char[] sMenuItem = new char[64];
		FormatEx(sMenuItem, 64, "%T", "WRPlayerStats", client);

		char[] sInfo = new char[32];
		FormatEx(sInfo, 32, "0;%s", sAuthID);

		if(gB_Stats)
		{
			menu.AddItem(sInfo, sMenuItem);
		}

		if(CheckCommandAccess(client, "sm_delete", ADMFLAG_RCON))
		{
			FormatEx(sMenuItem, 64, "%T", "WRDeleteRecord", client);
			FormatEx(sInfo, 32, "1;%d", id);
			menu.AddItem(sInfo, sMenuItem);
		}

		GetTrackName(client, results.FetchInt(10), sTrack, 32);
	}

	else
	{
		char[] sMenuItem = new char[64];
		FormatEx(sMenuItem, 64, "%T", "DatabaseError", client);
		menu.AddItem("-1", sMenuItem);
	}

	if(strlen(sName) > 0)
	{
		FormatEx(sFormattedTitle, 256, "%s %s\n--- %s: [%s]", sName, sAuthID, sMap, sTrack);
	}

	else
	{
		FormatEx(sFormattedTitle, 256, "%T", "Error", client);
	}

	menu.SetTitle(sFormattedTitle);
	menu.ExitBackButton = true;
	menu.Display(client, 20);
}

public int SubMenu_Handler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[32];
		m.GetItem(param2, sInfo, 32);

		if(gB_Stats && StringToInt(sInfo) != -1)
		{
			char[][] sExploded = new char[2][32];
			ExplodeString(sInfo, ";", sExploded, 2, 32, true);

			int first = StringToInt(sExploded[0]);

			switch(first)
			{
				case 0:
				{
					Shavit_OpenStatsMenu(param1, sExploded[1]);
				}

				case 1:
				{
					OpenDeleteMenu(param1, StringToInt(sExploded[1]));
				}
			}
		}

		else
		{
			StartWRMenu(param1, gS_ClientMap[param1], gBS_LastWR[param1], Track_Main);
		}
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		StartWRMenu(param1, gS_ClientMap[param1], gBS_LastWR[param1], Track_Main);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public void Shavit_OnDatabaseLoaded()
{
	gH_SQL = Shavit_GetDatabase();
	SetSQLInfo();
}

public Action CheckForSQLInfo(Handle Timer)
{
	return SetSQLInfo();
}

Action SetSQLInfo()
{
	if(gH_SQL == null)
	{
		gH_SQL = Shavit_GetDatabase();

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
		char[] sDriver = new char[8];
		gH_SQL.Driver.GetIdentifier(sDriver, 8);
		gB_MySQL = StrEqual(sDriver, "mysql", false);

		char[] sQuery = new char[512];

		if(gB_MySQL)
		{
			FormatEx(sQuery, 512, "CREATE TABLE IF NOT EXISTS `%splayertimes` (`id` INT NOT NULL AUTO_INCREMENT, `auth` CHAR(32), `map` CHAR(128), `time` FLOAT, `jumps` INT, `style` INT, `date` CHAR(16), `strafes` INT, `sync` FLOAT, `points` FLOAT NOT NULL DEFAULT 0, `track` INT NOT NULL DEFAULT 0, PRIMARY KEY (`id`), INDEX `auth` (`auth`), INDEX `points` (`points`), INDEX `time` (`time`), FULLTEXT INDEX `map` (`map`));", gS_MySQLPrefix);
		}

		else
		{
			FormatEx(sQuery, 512, "CREATE TABLE IF NOT EXISTS `%splayertimes` (`id` INTEGER PRIMARY KEY, `auth` CHAR(32), `map` CHAR(128), `time` FLOAT, `jumps` INT, `style` INT, `date` CHAR(16), `strafes` INT, `sync` FLOAT, `points` FLOAT NOT NULL DEFAULT 0, `track` INT NOT NULL DEFAULT 0);", gS_MySQLPrefix);
		}

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
		FormatEx(sQuery, 64, "ALTER TABLE %splayertimes MODIFY date CHAR(16);", gS_MySQLPrefix);
		gH_SQL.Query(SQL_AlterTable2_Callback, sQuery);
	}

	FormatEx(sQuery, 64, "SELECT points FROM %splayertimes LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration3_Callback, sQuery);

	FormatEx(sQuery, 64, "SELECT track FROM %splayertimes LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration4_Callback, sQuery);
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
		FormatEx(sQuery, 256, "ALTER TABLE `%splayertimes` ADD %s;", gS_MySQLPrefix, (gB_MySQL)? "(`points` FLOAT NOT NULL DEFAULT 0)":"COLUMN `points` FLOAT NOT NULL DEFAULT 0");
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

public void SQL_TableMigration4_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		char[] sQuery = new char[256];
		FormatEx(sQuery, 256, "ALTER TABLE `%splayertimes` ADD %s;", gS_MySQLPrefix, (gB_MySQL)? "(`track` INT NOT NULL DEFAULT 0)":"COLUMN `track` INT NOT NULL DEFAULT 0");
		gH_SQL.Query(SQL_AlterTable4_Callback, sQuery);

		return;
	}

	OnMapStart();
}

public void SQL_AlterTable4_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR module) error! Times' table migration (4) failed. Reason: %s", error);

		return;
	}

	OnMapStart();
}

public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track)
{
	char[] sTime = new char[32];
	FormatSeconds(time, sTime, 32);

	char[] sTrack = new char[32];
	GetTrackName(LANG_SERVER, track, sTrack, 32);

	// 0 - no query
	// 1 - insert
	// 2 - update
	int overwrite = 0;

	if(gA_StyleSettings[style][bUnranked] || Shavit_IsPracticeMode(client))
	{
		overwrite = 0; // ugly way of not writing to database
	}

	else if(gF_PlayerRecord[client][style][track] == 0.0)
	{
		overwrite = 1;
	}

	else if(time <= gF_PlayerRecord[client][style][track])
	{
		overwrite = 2;
	}

	if(overwrite > 0 && (time < gF_WRTime[style][track] || gF_WRTime[style][track] == 0.0)) // WR?
	{
		gF_WRTime[style][track] = time;

		Call_StartForward(gH_OnWorldRecord);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_PushCell(strafes);
		Call_PushCell(sync);
		Call_PushCell(track);
		Call_Finish();
	}

	int iRank = GetRankForTime(style, time, track);

	if(iRank >= gI_RecordAmount[style][track])
	{
		Call_StartForward(gH_OnWorstRecord);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_PushCell(strafes);
		Call_PushCell(sync);
		Call_PushCell(track);
		Call_Finish();
	}

	float fDifference = (gF_PlayerRecord[client][style][track] - time);

	if(fDifference < 0.0)
	{
		fDifference = -fDifference;
	}

	char[] sDifference = new char[16];
	FormatSeconds(fDifference, sDifference, 16, true);

	char[] sSync = new char[32]; // 32 because colors
	FormatEx(sSync, 32, (sync != -1.0)? " @ %s%.02f%%":"", gS_ChatStrings[sMessageVariable], sync);

	if(overwrite > 0)
	{
		char[] sAuthID = new char[32];
		GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

		char[] sQuery = new char[512];

		if(overwrite == 1) // insert
		{
			Shavit_PrintToChatAll("%s[%s]%s %T", gS_ChatStrings[sMessageVariable], sTrack, gS_ChatStrings[sMessageText], "FirstCompletion", LANG_SERVER, gS_ChatStrings[sMessageVariable2], client, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageStyle], gS_StyleStrings[style][sStyleName], gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable2], sTime, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], iRank, gS_ChatStrings[sMessageText], jumps, strafes, sSync, gS_ChatStrings[sMessageText]);

			if(gH_SQL == null)
			{
				return;
			}

			FormatEx(sQuery, 512, "INSERT INTO %splayertimes (auth, map, time, jumps, date, style, strafes, sync, points, track) VALUES ('%s', '%s', %.03f, %d, %d, %d, %d, %.2f, 0.0, %d);", gS_MySQLPrefix, sAuthID, gS_Map, time, jumps, GetTime(), style, strafes, sync, track);
		}

		else // update
		{
			Shavit_PrintToChatAll("%s[%s]%s %T", gS_ChatStrings[sMessageVariable], sTrack, gS_ChatStrings[sMessageText], "NotFirstCompletion", LANG_SERVER, gS_ChatStrings[sMessageVariable2], client, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageStyle], gS_StyleStrings[style][sStyleName], gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable2], sTime, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable], iRank, gS_ChatStrings[sMessageText], jumps, strafes, sSync, gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageWarning], sDifference);

			FormatEx(sQuery, 512, "UPDATE %splayertimes SET time = %.03f, jumps = %d, date = %d, strafes = %d, sync = %.02f, points = 0.0 WHERE map = '%s' AND auth = '%s' AND style = %d AND track = %d;", gS_MySQLPrefix, time, jumps, GetTime(), strafes, sync, gS_Map, sAuthID, style, track);
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
		Call_PushCell(track);
		Call_Finish();

		gF_PlayerRecord[client][style][track] = time;
	}

	else if(overwrite == 0 && !gA_StyleSettings[style][bUnranked])
	{
		Shavit_PrintToChat(client, "%s[%s]%s %T", gS_ChatStrings[sMessageVariable], sTrack, gS_ChatStrings[sMessageText], "WorseTime", client, gS_ChatStrings[sMessageStyle], gS_StyleStrings[style][sStyleName], gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable2], sTime, gS_ChatStrings[sMessageText], jumps, strafes, sSync, gS_ChatStrings[sMessageText], sDifference);
	}

	else
	{
		Shavit_PrintToChat(client, "%s[%s]%s] %T", gS_ChatStrings[sMessageVariable], sTrack, gS_ChatStrings[sMessageText], "UnrankedTime", client, gS_ChatStrings[sMessageStyle], gS_StyleStrings[style][sStyleName], gS_ChatStrings[sMessageText], gS_ChatStrings[sMessageVariable2], sTime, gS_ChatStrings[sMessageText], jumps, strafes, sSync, gS_ChatStrings[sMessageText]);
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

void UpdateLeaderboards()
{
	char[] sQuery = new char[192];
	FormatEx(sQuery, 192, "SELECT style, time, track FROM %splayertimes WHERE map = '%s' ORDER BY time ASC, date ASC;", gS_MySQLPrefix, gS_Map);
	gH_SQL.Query(SQL_UpdateLeaderboards_Callback, sQuery, 0);
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
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gI_RecordAmount[i][j] = 0;
			gA_LeaderBoard[i][j].Clear();
		}
	}

	while(results.FetchRow())
	{
		int style = results.FetchInt(0);
		int track = results.FetchInt(2);

		if(style >= gI_Styles || gA_StyleSettings[style][bUnranked] || track >= TRACKS_SIZE)
		{
			continue;
		}

		gA_LeaderBoard[style][track].Push(results.FetchFloat(1));
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		if(i >= gI_Styles || gA_StyleSettings[i][bUnranked])
		{
			continue;
		}

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			SortADTArray(gA_LeaderBoard[i][j], Sort_Ascending, Sort_Float);
			gI_RecordAmount[i][j] = gA_LeaderBoard[i][j].Length;
		}
	}
}

int GetRankForTime(int style, float time, int track)
{
	if(time < gF_WRTime[style][track] || gI_RecordAmount[style][track] <= 0)
	{
		return 1;
	}

	for(int i = 0; i < gI_RecordAmount[style][track]; i++)
	{
		if(time < gA_LeaderBoard[style][track].Get(i))
		{
			return ++i;
		}
	}

	return (gI_RecordAmount[style][track] + 1);
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

void GetTrackName(int client, int track, char[] output, int size)
{
	if(track < 0 || track >= TRACKS_SIZE)
	{
		FormatEx(output, size, "%T", "Track_Unknown", client);

		return;
	}

	static char sTrack[16];
	FormatEx(sTrack, 16, "Track_%d", track);
	FormatEx(output, size, "%T", sTrack, client);
}
