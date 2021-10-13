/*
 * shavit's Timer - Player Stats
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
#include <geoip>
#include <convar_class>
#include <dhooks>

#undef REQUIRE_PLUGIN
#include <shavit>

#undef REQUIRE_EXTENSIONS
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

// macros
#define MAPSDONE 0
#define MAPSLEFT 1

// modules
bool gB_Rankings = false;

// database handle
Database2 gH_SQL = null;
char gS_MySQLPrefix[32];

// cache
bool gB_CanOpenMenu[MAXPLAYERS+1];
int gI_MapType[MAXPLAYERS+1];
int gI_Style[MAXPLAYERS+1];
int gI_MenuPos[MAXPLAYERS+1];
int gI_Track[MAXPLAYERS+1];
int gI_TargetSteamID[MAXPLAYERS+1];
char gS_TargetName[MAXPLAYERS+1][MAX_NAME_LENGTH];

// playtime things
float gF_PlaytimeStart[MAXPLAYERS+1];
float gF_PlaytimeStyleStart[MAXPLAYERS+1];
int gI_CurrentStyle[MAXPLAYERS+1];
float gF_PlaytimeStyleSum[MAXPLAYERS+1][STYLE_LIMIT];
bool gB_HavePlaytimeOnStyle[MAXPLAYERS+1][STYLE_LIMIT];
bool gB_QueriedPlaytime[MAXPLAYERS+1];

bool gB_Late = false;
EngineVersion gEV_Type = Engine_Unknown;

// timer settings
int gI_Styles = 0;
stylestrings_t gS_StyleStrings[STYLE_LIMIT];

// chat settings
chatstrings_t gS_ChatStrings;

Convar gCV_SavePlaytime = null;

public Plugin myinfo =
{
	name = "[shavit] Player Stats",
	author = "shavit",
	description = "Player stats for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// natives
	CreateNative("Shavit_OpenStatsMenu", Native_OpenStatsMenu);

	RegPluginLibrary("shavit-stats");

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

	// player commands
	RegConsoleCmd("sm_p", Command_Profile, "Show the player's profile. Usage: sm_p [target]");
	RegConsoleCmd("sm_profile", Command_Profile, "Show the player's profile. Usage: sm_profile [target]");
	RegConsoleCmd("sm_stats", Command_Profile, "Show the player's profile. Usage: sm_stats [target]");
	RegConsoleCmd("sm_mapsdone", Command_MapsDoneLeft, "Show maps that the player has finished. Usage: sm_mapsdone [target]");
	RegConsoleCmd("sm_mapsleft", Command_MapsDoneLeft, "Show maps that the player has not finished yet. Usage: sm_mapsleft [target]");
	RegConsoleCmd("sm_playtime", Command_Playtime, "Show the top playtime list.");

	// translations
	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-stats.phrases");

	gCV_SavePlaytime = new Convar("shavit_stats_saveplaytime", "1", "Whether to save a player's playtime (total & per-style).", 0, true, 0.0, true, 1.0);
	Convar.AutoExecConfig();

	gB_Rankings = LibraryExists("shavit-rankings");

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount());
		Shavit_OnChatConfigLoaded();
		Shavit_OnDatabaseLoaded();

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientConnected(i) && IsClientInGame(i))
			{
				OnClientPutInServer(i);
			}
		}
	}

	CreateTimer(2.5 * 60.0, Timer_SavePlaytime, 0, TIMER_REPEAT);
}

public void Shavit_OnDatabaseLoaded()
{
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = GetTimerDatabaseHandle2(false);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%sstyleplaytime` (`auth` INT NOT NULL, `style` INT NOT NULL, `playtime` FLOAT NOT NULL, PRIMARY KEY (`auth`, `style`));",
		gS_MySQLPrefix);
	gH_SQL.Query(SQL_CreateStylePlaytimeTable_Callback, sQuery, 0, DBPrio_Normal);
}

public void SQL_CreateStylePlaytimeTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError("Timer (styleplaytime table creation) SQL query failed. Reason: %s", error);
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && !IsFakeClient(i) && IsClientAuthorized(i))
		{
			OnClientAuthorized(i, "");
		}
	}
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleStringsStruct(i, gS_StyleStrings[i]);
	}

	gI_Styles = styles;
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void OnClientConnected(int client)
{
	gF_PlaytimeStart[client] = 0.0;
	gF_PlaytimeStyleStart[client] = 0.0;
	any empty[STYLE_LIMIT];
	gF_PlaytimeStyleSum[client] = empty;
	gB_HavePlaytimeOnStyle[client] = empty;
	gB_QueriedPlaytime[client] = false;
}

public void OnClientPutInServer(int client)
{
	gB_CanOpenMenu[client] = true;

	float now = GetEngineTime();
	gF_PlaytimeStart[client] = now;
	gF_PlaytimeStyleStart[client] = now;
}

public void OnClientAuthorized(int client)
{
	if (IsFakeClient(client))
	{
		return;
	}

	QueryPlaytime(client);
}

void QueryPlaytime(int client)
{
	if (gH_SQL == null)
	{
		return;
	}

	int iSteamID = GetSteamAccountID(client);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery),
		"SELECT style, playtime FROM %sstyleplaytime WHERE auth = %d;",
		gS_MySQLPrefix, iSteamID);
	gH_SQL.Query(SQL_QueryStylePlaytime_Callback, sQuery, GetClientSerial(client), DBPrio_Normal);
}

public void SQL_QueryStylePlaytime_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError("Timer (style playtime) SQL query failed. Reason: %s", error);
		return;
	}

	int client = GetClientFromSerial(data);

	if (client < 1)
	{
		return;
	}

	while (results.FetchRow())
	{
		int style = results.FetchInt(0);
		//float playtime = results.FetchFloat(1);
		gB_HavePlaytimeOnStyle[client][style] = true;
	}

	gB_QueriedPlaytime[client] = true;
}

public void OnClientDisconnect(int client)
{
	if (gH_SQL == null || IsFakeClient(client) || !IsClientAuthorized(client) || !gCV_SavePlaytime.BoolValue)
	{
		return;
	}

	Transaction2 trans = null;
	SavePlaytime(client, GetEngineTime(), trans);

	if (trans != null)
	{
		gH_SQL.Execute(trans, Trans_SavePlaytime_Success, Trans_SavePlaytime_Failure);
	}
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	if (IsFakeClient(client))
	{
		return;
	}

	gI_CurrentStyle[client] = newstyle;

	if (!IsClientConnected(client) || !IsClientInGame(client))
	{
		return;
	}

	float now = GetEngineTime();

	if (gF_PlaytimeStyleStart[client] == 0.0)
	{
		gF_PlaytimeStyleStart[client] = now;
		return;
	}

	if (oldstyle == newstyle)
	{
		return;
	}

	gF_PlaytimeStyleSum[client][oldstyle] += (now - gF_PlaytimeStyleStart[client]);
	gF_PlaytimeStyleStart[client] = now;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}
}

void SavePlaytime222(int client, float now, Transaction2 &trans, int style, int iSteamID)
{
	char sQuery[512];

	if (style == -1) // regular playtime
	{
		if (gF_PlaytimeStart[client] <= 0.0)
		{
			return;
		}

		float diff = now - gF_PlaytimeStart[client];
		gF_PlaytimeStart[client] = now;

		if (diff <= 0.0)
		{
			return;
		}

		FormatEx(sQuery, sizeof(sQuery),
			"UPDATE `%susers` SET playtime = playtime + %f WHERE auth = %d;",
			gS_MySQLPrefix, diff, iSteamID);
	}
	else
	{
		float diff = gF_PlaytimeStyleSum[client][style];

		if (gI_CurrentStyle[client] == style)
		{
			diff += now - gF_PlaytimeStyleStart[client];
			gF_PlaytimeStyleStart[client] = now;
		}

		gF_PlaytimeStyleSum[client][style] = 0.0;

		if (diff <= 0.0)
		{
			return;
		}

		if (gB_HavePlaytimeOnStyle[client][style])
		{
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE `%sstyleplaytime` SET playtime = playtime + %f WHERE auth = %d AND style = %d;",
				gS_MySQLPrefix, diff, iSteamID, style);
		}
		else
		{
			gB_HavePlaytimeOnStyle[client][style] = true;
			FormatEx(sQuery, sizeof(sQuery),
				"INSERT INTO `%sstyleplaytime` (`auth`, `style`, `playtime`) VALUES (%d, %d, %f);",
				gS_MySQLPrefix, iSteamID, style, diff);
		}
	}

	if (trans == null)
	{
		trans = view_as<Transaction2>(new Transaction());
	}

	trans.AddQuery(sQuery);
}

public void Trans_SavePlaytime_Success(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
}

public void Trans_SavePlaytime_Failure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (stats save playtime) SQL query %d/%d failed. Reason: %s", failIndex, numQueries, error);
}

void SavePlaytime(int client, float now, Transaction2 &trans)
{
	int iSteamID = GetSteamAccountID(client);

	if (iSteamID == 0)
	{
		// how HOW HOW
		return;
	}

	if (!gB_QueriedPlaytime[client])
	{
		return;
	}

	for (int i = -1 /* yes */; i < gI_Styles; i++)
	{
		SavePlaytime222(client, now, trans, i, iSteamID);
	}
}

public Action Timer_SavePlaytime(Handle timer, any data)
{
	if (gH_SQL == null || !gCV_SavePlaytime.BoolValue)
	{
		return Plugin_Continue;
	}

	Transaction2 trans = null;
	float now = GetEngineTime();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsClientAuthorized(i))
		{
			continue;
		}

		if (gB_QueriedPlaytime[i])
		{
			SavePlaytime(i, now, trans);
		}
		else if ((now - gF_PlaytimeStart[i]) > 15.0)
		{
			QueryPlaytime(i);
		}
	}

	if (trans != null)
	{
		gH_SQL.Execute(trans, Trans_SavePlaytime_Success, Trans_SavePlaytime_Failure);
	}

	return Plugin_Continue;
}

public Action Command_Playtime(int client, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery),
		"(SELECT auth, name, playtime, -1 as ownrank FROM %susers WHERE playtime > 0 ORDER BY playtime DESC LIMIT 100) " ...
		"UNION " ...
		"(SELECT -1, '', u2.playtime, COUNT(*) as ownrank FROM %susers u1 JOIN (SELECT playtime FROM %susers WHERE auth = %d) u2 WHERE u1.playtime >= u2.playtime);",
		gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, GetSteamAccountID(client));
	gH_SQL.Query(SQL_TopPlaytime_Callback, sQuery, GetClientSerial(client), DBPrio_Normal);

	return Plugin_Handled;
}

public void SQL_TopPlaytime_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null || !results.RowCount)
	{
		LogError("Timer (!playtime) SQL query failed. Reason: %s", error);
		return;
	}

	int client = GetClientFromSerial(data);

	if (client < 1)
	{
		return;
	}

	Menu menu = new Menu(PlaytimeMenu_Handler);

	char sOwnPlaytime[16];
	int own_rank = 0;
	int rank = 1;

	while (results.FetchRow())
	{
		char sSteamID[20];
		results.FetchString(0, sSteamID, sizeof(sSteamID));

		char sName[PLATFORM_MAX_PATH];
		results.FetchString(1, sName, sizeof(sName));

		float fPlaytime = results.FetchFloat(2);
		char sPlaytime[16];
		FormatSeconds(fPlaytime, sPlaytime, sizeof(sPlaytime), false, true, true);

		int iOwnRank = results.FetchInt(3);

		if (iOwnRank != -1)
		{
			own_rank = iOwnRank;
			sOwnPlaytime = sPlaytime;
		}
		else
		{
			char sDisplay[128];
			FormatEx(sDisplay, sizeof(sDisplay), "#%d - %s - %s", rank++, sPlaytime, sName);
			menu.AddItem(sSteamID, sDisplay, ITEMDRAW_DEFAULT);
		}
	}

	menu.SetTitle("%T\n%T (#%d): %s", "Playtime", client, "YourPlaytime", client, own_rank, sOwnPlaytime);

	if (menu.ItemCount <= ((gEV_Type == Engine_CSS) ? 9 : 8))
	{
		menu.Pagination = MENU_NO_PAGINATION;
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int PlaytimeMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[20];
		menu.GetItem(param2, info, sizeof(info));
		FakeClientCommand(param1, "sm_profile [U:1:%s]", info);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_MapsDoneLeft(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}

	int target = client;
	int iSteamID = 0;

	if(args > 0)
	{
		char sArgs[64];
		GetCmdArgString(sArgs, 64);

		iSteamID = SteamIDToAuth(sArgs);

		if (iSteamID < 1)
		{
			target = FindTarget(client, sArgs, true, false);

			if (target == -1)
			{
				return Plugin_Handled;
			}
		}
		else
		{
			FormatEx(gS_TargetName[client], sizeof(gS_TargetName[]), "[U:1:%d]", iSteamID);
		}
	}

	if (iSteamID < 1)
	{
		GetClientName(target, gS_TargetName[client], sizeof(gS_TargetName[]));
		iSteamID = GetSteamAccountID(target);
	}

	gI_TargetSteamID[client] = iSteamID;

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	ReplaceString(gS_TargetName[client], MAX_NAME_LENGTH, "#", "?");

	Menu menu = new Menu(MenuHandler_MapsDoneLeft);

	if(StrEqual(sCommand, "sm_mapsdone"))
	{
		gI_MapType[client] = MAPSDONE;
		menu.SetTitle("%T\n ", "MapsDoneOnStyle", client, gS_TargetName[client]);
	}

	else
	{
		gI_MapType[client] = MAPSLEFT;
		menu.SetTitle("%T\n ", "MapsLeftOnStyle", client, gS_TargetName[client]);
	}

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
		menu.AddItem(sInfo, gS_StyleStrings[iStyle].sStyleName);
	}

	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_MapsDoneLeft(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		gI_Style[param1] = StringToInt(sInfo);

		Menu submenu = new Menu(MenuHandler_MapsDoneLeft_Track);
		submenu.SetTitle("%T\n ", "SelectTrack", param1);

		for(int i = 0; i < TRACKS_SIZE; i++)
		{
			IntToString(i, sInfo, 8);

			char sTrack[32];
			GetTrackName(param1, i, sTrack, 32);
			submenu.AddItem(sInfo, sTrack);
		}

		submenu.Display(param1, MENU_TIME_FOREVER);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_MapsDoneLeft_Track(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		gI_Track[param1] = StringToInt(sInfo);

		ShowMaps(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Profile(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}

	int target = client;
	int iSteamID = 0;

	if(args > 0)
	{
		char sArgs[64];
		GetCmdArgString(sArgs, 64);

		iSteamID = SteamIDToAuth(sArgs);

		if (iSteamID < 1)
		{
			target = FindTarget(client, sArgs, true, false);

			if (target == -1)
			{
				return Plugin_Handled;
			}
		}
	}

	gI_TargetSteamID[client] = (iSteamID > 0) ? iSteamID : GetSteamAccountID(target);

	return OpenStatsMenu(client, gI_TargetSteamID[client]);
}

Action OpenStatsMenu(int client, int steamid, int style = 0, int item = 0)
{
	gI_Style[client] = style;
	gI_MenuPos[client] = item;

	// no spam please
	if(!gB_CanOpenMenu[client])
	{
		return Plugin_Handled;
	}

	// big ass query, looking for optimizations TODO
	char sQuery[2048];

	if(gB_Rankings)
	{
		FormatEx(sQuery, 2048, "SELECT a.clears, b.maps, c.wrs, d.name, d.ip, d.lastlogin, f.clears, g.maps, h.wrs, d.points, e.rank, d.playtime, i.styleplaytime FROM " ...
				"(SELECT COUNT(*) clears FROM (SELECT map FROM %splayertimes WHERE auth = %d AND track = 0 AND style = %d GROUP BY map) s) a " ...
				"JOIN (SELECT COUNT(*) maps FROM (SELECT map FROM %smapzones WHERE track = 0 AND type = 0 GROUP BY map) s) b " ...
				"JOIN (SELECT COUNT(*) wrs FROM %swrs WHERE auth = %d AND track = 0 AND style = %d) c " ...
				"JOIN (SELECT name, ip, lastlogin, FORMAT(points, 2) points, playtime FROM %susers WHERE auth = %d) d " ...
				"JOIN (SELECT COUNT(*) as 'rank' FROM %susers as u1 JOIN (SELECT points FROM %susers WHERE auth = %d) u2 WHERE u1.points >= u2.points) e " ...
				"JOIN (SELECT COUNT(*) clears FROM (SELECT map FROM %splayertimes WHERE auth = %d AND track > 0 AND style = %d GROUP BY map) s) f " ...
				"JOIN (SELECT COUNT(*) maps FROM (SELECT map FROM %smapzones WHERE track > 0 AND type = 0 GROUP BY map) s) g " ...
				"JOIN (SELECT COUNT(*) wrs FROM %swrs WHERE auth = %d AND track > 0 AND style = %d) h " ...
				"JOIN (SELECT SUM(playtime) as styleplaytime FROM %sstyleplaytime WHERE auth = %d AND style = %d) i " ...
			"LIMIT 1;", gS_MySQLPrefix, steamid, style, gS_MySQLPrefix, gS_MySQLPrefix, steamid, style, gS_MySQLPrefix, steamid, gS_MySQLPrefix, gS_MySQLPrefix, steamid, gS_MySQLPrefix, steamid, style, gS_MySQLPrefix, gS_MySQLPrefix, steamid, style, gS_MySQLPrefix, steamid, style);
	}
	else
	{
		FormatEx(sQuery, 2048, "SELECT a.clears, b.maps, c.wrs, d.name, d.ip, d.lastlogin, e.clears, f.maps, g.wrs, d.playtime, i.styleplaytime FROM " ...
				"(SELECT COUNT(*) clears FROM (SELECT map FROM %splayertimes WHERE auth = %d AND track = 0 AND style = %d GROUP BY map) s) a " ...
				"JOIN (SELECT COUNT(*) maps FROM (SELECT map FROM %smapzones WHERE track = 0 AND type = 0 GROUP BY map) s) b " ...
				"JOIN (SELECT COUNT(*) wrs FROM %swrs WHERE auth = %d AND track = 0 AND style = %d) c " ...
				"JOIN (SELECT name, ip, lastlogin, playtime FROM %susers WHERE auth = %d) d " ...
				"JOIN (SELECT COUNT(*) clears FROM (SELECT map FROM %splayertimes WHERE auth = %d AND track > 0 AND style = %d GROUP BY map) s) e " ...
				"JOIN (SELECT COUNT(*) maps FROM (SELECT map FROM %smapzones WHERE track > 0 AND type = 0 GROUP BY map) s) f " ...
				"JOIN (SELECT COUNT(*) wrs FROM %swrs WHERE auth = %d AND track > 0 AND style = %d) g " ...
				"JOIN (SELECT SUM(playtime) as styleplaytime FROM %sstyleplaytime WHERE auth = %d AND style = %d) i " ...
			"LIMIT 1;", gS_MySQLPrefix, steamid, style, gS_MySQLPrefix, gS_MySQLPrefix, steamid, style, gS_MySQLPrefix, steamid, gS_MySQLPrefix, steamid, style, gS_MySQLPrefix, gS_MySQLPrefix, steamid, style, gS_MySQLPrefix, steamid, style);
	}

	gB_CanOpenMenu[client] = false;

	DataPack data = new DataPack();
	data.WriteCell(GetClientSerial(client));
	data.WriteCell(item);

	gH_SQL.Query(OpenStatsMenuCallback, sQuery, data, DBPrio_Low);

	return Plugin_Handled;
}

public void OpenStatsMenuCallback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int client = GetClientFromSerial(data.ReadCell());
	int item = data.ReadCell();

	gB_CanOpenMenu[client] = true;

	if(results == null)
	{
		LogError("Timer (statsmenu) SQL query failed. Reason: %s", error);

		return;
	}

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		// create variables
		int iClears = results.FetchInt(0);
		int iTotalMaps = results.FetchInt(1);
		int iWRs = results.FetchInt(2);
		results.FetchString(3, gS_TargetName[client], MAX_NAME_LENGTH);
		ReplaceString(gS_TargetName[client], MAX_NAME_LENGTH, "#", "?");

		int iIPAddress = results.FetchInt(4);
		char sIPAddress[32];
		IPAddressToString(iIPAddress, sIPAddress, 32);

		char sCountry[64];

		if(!GeoipCountry(sIPAddress, sCountry, 64))
		{
			strcopy(sCountry, 64, "Local Area Network");
		}

		int iLastLogin = results.FetchInt(5);
		char sLastLogin[32];
		FormatTime(sLastLogin, 32, "%Y-%m-%d %H:%M:%S", iLastLogin);
		Format(sLastLogin, 32, "%T: %s", "LastLogin", client, (iLastLogin != -1)? sLastLogin:"N/A");

		int iBonusClears = results.FetchInt(6);
		int iBonusTotalMaps = results.FetchInt(7);
		int iBonusWRs = results.FetchInt(8);

		char sPoints[16];
		char sRank[16];

		if(gB_Rankings)
		{
			results.FetchString(9, sPoints, 16);
			results.FetchString(10, sRank, 16);
		}

		float fPlaytime = results.FetchFloat(gB_Rankings ? 11 : 9);
		char sPlaytime[16];
		FormatSeconds(fPlaytime, sPlaytime, sizeof(sPlaytime), false, true, true);

		float fStylePlaytime = results.FetchFloat(gB_Rankings ? 12 : 10);
		char sStylePlaytime[16];
		FormatSeconds(fStylePlaytime, sStylePlaytime, sizeof(sStylePlaytime), false, true, true);

		char sRankingString[64];

		if(gB_Rankings)
		{
			if(StringToInt(sRank) > 0 && StringToInt(sPoints) > 0)
			{
				FormatEx(sRankingString, 64, "\n%T: #%s/%d\n%T: %s", "Rank", client, sRank, Shavit_GetRankedPlayers(), "Points", client, sPoints);
			}
			else
			{
				FormatEx(sRankingString, 64, "\n%T: %T", "Rank", client, "PointsUnranked", client);
			}
		}

		if(iClears > iTotalMaps)
		{
			iClears = iTotalMaps;
		}

		Menu menu = new Menu(MenuHandler_ProfileHandler);
		menu.SetTitle("%s's %T. [U:1:%d]\n%T: %s\n%s\n%s\n%T: %s\n",
			gS_TargetName[client], "Profile", client, gI_TargetSteamID[client], "Country", client, sCountry, sLastLogin,
			sRankingString, "Playtime", client, sPlaytime);

		int[] styles = new int[gI_Styles];
		Shavit_GetOrderedStyles(styles, gI_Styles);

		for(int i = 0; i < gI_Styles; i++)
		{
			int iStyle = styles[i];

			if(Shavit_GetStyleSettingInt(iStyle, "unranked") || Shavit_GetStyleSettingInt(iStyle, "enabled") <= 0)
			{
				continue;
			}

			char sInfo[4];
			IntToString(iStyle, sInfo, 4);

			char sStyleInfo[256];

			if (iStyle == gI_Style[client])
			{
				FormatEx(sStyleInfo, sizeof(sStyleInfo),
					"%s\n"...
					"    [Main] %T: %d/%d (%0.1f%%)\n"...
					"    [Main] %T: %d\n"...
					"    [Bonus] %T: %d/%d (%0.1f%%)\n"...
					"    [Bonus] %T: %d\n"...
					"    [%T] %s\n"...
					"",
					gS_StyleStrings[iStyle].sStyleName,
					"MapCompletions", client, iClears, iTotalMaps, ((float(iClears) / (iTotalMaps > 0 ? float(iTotalMaps) : 0.0)) * 100.0),
					"WorldRecords", client, iWRs,
					"MapCompletions", client, iBonusClears, iBonusTotalMaps, ((float(iBonusClears) / (iBonusTotalMaps > 0 ? float(iBonusTotalMaps) : 0.0)) * 100.0),
					"WorldRecords", client, iBonusWRs,
					"Playtime", client, sStylePlaytime
				);
			}
			else
			{
				FormatEx(sStyleInfo, sizeof(sStyleInfo), "%s\n", gS_StyleStrings[iStyle].sStyleName);
			}

			menu.AddItem(sInfo, sStyleInfo);
		}

		// should NEVER happen
		if(menu.ItemCount == 0)
		{
			char sMenuItem[64];
			FormatEx(sMenuItem, 64, "%T", "NoRecords", client);
			menu.AddItem("-1", sMenuItem);
		}

		menu.ExitButton = true;
		menu.DisplayAt(client, item, MENU_TIME_FOREVER);
	}

	else
	{
		Shavit_PrintToChat(client, "%T", "StatsMenuFailure", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}
}

public int MenuHandler_ProfileHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[32];

		menu.GetItem(param2, sInfo, 32);
		int iSelectedStyle = StringToInt(sInfo);
		gI_MenuPos[param1] = GetMenuSelectionPosition();

		// If we select the same style, then display these
		if(iSelectedStyle == gI_Style[param1])
		{
			Menu submenu = new Menu(MenuHandler_TypeHandler);
			submenu.SetTitle("%T", "MapsMenu", param1, gS_StyleStrings[gI_Style[param1]].sShortName);

			for(int j = 0; j < TRACKS_SIZE; j++)
			{
				char sTrack[32];
				GetTrackName(param1, j, sTrack, 32);

				char sMenuItem[64];
				FormatEx(sMenuItem, 64, "%T (%s)", "MapsDone", param1, sTrack);

				char sNewInfo[32];
				FormatEx(sNewInfo, 32, "%d;0", j);
				submenu.AddItem(sNewInfo, sMenuItem);

				FormatEx(sMenuItem, 64, "%T (%s)", "MapsLeft", param1, sTrack);
				FormatEx(sNewInfo, 32, "%d;1", j);
				submenu.AddItem(sNewInfo, sMenuItem);
			}

			submenu.ExitBackButton = true;
			submenu.Display(param1, MENU_TIME_FOREVER);
		}
		else // No? display stats menu but different style
		{
			OpenStatsMenu(param1, gI_TargetSteamID[param1], iSelectedStyle, gI_MenuPos[param1]);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_TypeHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, 32);

		char sExploded[2][4];
		ExplodeString(sInfo, ";", sExploded, 2, 4);

		gI_Track[param1] = StringToInt(sExploded[0]);
		gI_MapType[param1] = StringToInt(sExploded[1]);

		ShowMaps(param1);
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenStatsMenu(param1, gI_TargetSteamID[param1], gI_Style[param1], gI_MenuPos[param1]);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void ShowMaps(int client)
{
	if(!gB_CanOpenMenu[client])
	{
		return;
	}

	char sQuery[512];

	if(gI_MapType[client] == MAPSDONE)
	{
		FormatEx(sQuery, 512,
			"SELECT a.map, a.time, a.jumps, a.id, COUNT(b.map) + 1 as 'rank', a.points FROM %splayertimes a LEFT JOIN %splayertimes b ON a.time > b.time AND a.map = b.map AND a.style = b.style AND a.track = b.track WHERE a.auth = %d AND a.style = %d AND a.track = %d GROUP BY a.map, a.time, a.jumps, a.id, a.points ORDER BY a.%s;",
			gS_MySQLPrefix, gS_MySQLPrefix, gI_TargetSteamID[client], gI_Style[client], gI_Track[client], (gB_Rankings)? "points DESC":"map");
	}

	else
	{
		if(gB_Rankings)
		{
			FormatEx(sQuery, 512,
				"SELECT DISTINCT m.map, t.tier FROM %smapzones m LEFT JOIN %smaptiers t ON m.map = t.map WHERE m.type = 0 AND m.track = %d AND m.map NOT IN (SELECT DISTINCT map FROM %splayertimes WHERE auth = %d AND style = %d AND track = %d) ORDER BY m.map;",
				gS_MySQLPrefix, gS_MySQLPrefix, gI_Track[client], gS_MySQLPrefix, gI_TargetSteamID[client], gI_Style[client], gI_Track[client]);
		}

		else
		{
			FormatEx(sQuery, 512,
				"SELECT DISTINCT map FROM %smapzones WHERE type = 0 AND track = %d AND map NOT IN (SELECT DISTINCT map FROM %splayertimes WHERE auth = %d AND style = %d AND track = %d) ORDER BY map;",
				gS_MySQLPrefix, gI_Track[client], gS_MySQLPrefix, gI_TargetSteamID[client], gI_Style[client], gI_Track[client]);
		}
	}

	gB_CanOpenMenu[client] = false;
	
	gH_SQL.Query(ShowMapsCallback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void ShowMapsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (ShowMaps SELECT) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	gB_CanOpenMenu[client] = true;

	int rows = results.RowCount;

	char sTrack[32];
	GetTrackName(client, gI_Track[client], sTrack, 32);

	Menu menu = new Menu(MenuHandler_ShowMaps);

	if(gI_MapType[client] == MAPSDONE)
	{
		menu.SetTitle("%T (%s)", "MapsDoneFor", client, gS_StyleStrings[gI_Style[client]].sShortName, gS_TargetName[client], rows, sTrack);
	}

	else
	{
		menu.SetTitle("%T (%s)", "MapsLeftFor", client, gS_StyleStrings[gI_Style[client]].sShortName, gS_TargetName[client], rows, sTrack);
	}

	while(results.FetchRow())
	{
		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(0, sMap, sizeof(sMap));

		char sRecordID[PLATFORM_MAX_PATH];
		char sDisplay[PLATFORM_MAX_PATH];

		if(gI_MapType[client] == MAPSDONE)
		{
			float time = results.FetchFloat(1);
			int jumps = results.FetchInt(2);
			int rank = results.FetchInt(4);

			char sTime[32];
			FormatSeconds(time, sTime, 32);

			float points = results.FetchFloat(5);

			if(gB_Rankings && points > 0.0)
			{
				FormatEx(sDisplay, sizeof(sDisplay), "[#%d] %s - %s (%.03f %T)", rank, sMap, sTime, points, "MapsPoints", client);
			}
			else
			{
				FormatEx(sDisplay, sizeof(sDisplay), "[#%d] %s - %s (%d %T)", rank, sMap, sTime, jumps, "MapsJumps", client);
			}

			int iRecordID = results.FetchInt(3);
			IntToString(iRecordID, sRecordID, sizeof(sRecordID));
		}
		else
		{
			if(gB_Rankings)
			{
				int iTier = results.FetchInt(1);

				if(results.IsFieldNull(1) || iTier == 0)
				{
					iTier = 1;
				}

				FormatEx(sDisplay, sizeof(sDisplay), "%s (Tier %d)", sMap, iTier);
			}
			else
			{
				sDisplay = sMap;
			}

			sRecordID = sMap;
		}

		menu.AddItem(sRecordID, sDisplay);
	}

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "NoResults", client);
		menu.AddItem("nope", sMenuItem);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ShowMaps(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[PLATFORM_MAX_PATH];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		if(StrEqual(sInfo, "nope"))
		{
			OpenStatsMenu(param1, gI_TargetSteamID[param1], gI_Style[param1], gI_MenuPos[param1]);

			return 0;
		}

		else if(StringToInt(sInfo) == 0)
		{
			FakeClientCommand(param1, "sm_nominate %s", sInfo);

			return 0;
		}
		
		char sQuery[512];
		FormatEx(sQuery, 512, "SELECT u.name, p.time, p.jumps, p.style, u.auth, p.date, p.map, p.strafes, p.sync, p.points FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE p.id = '%s' LIMIT 1;", gS_MySQLPrefix, gS_MySQLPrefix, sInfo);

		gH_SQL.Query(SQL_SubMenu_Callback, sQuery, GetClientSerial(param1));
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenStatsMenu(param1, gI_TargetSteamID[param1], gI_Style[param1], gI_MenuPos[param1]);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void SQL_SubMenu_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (STATS SUBMENU) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	Menu hMenu = new Menu(SubMenu_Handler);

	char sName[MAX_NAME_LENGTH];
	int iSteamID = 0;
	char sMap[PLATFORM_MAX_PATH];

	if(results.FetchRow())
	{
		// 0 - name
		results.FetchString(0, sName, MAX_NAME_LENGTH);

		// 1 - time
		float time = results.FetchFloat(1);
		char sTime[16];
		FormatSeconds(time, sTime, 16);

		char sDisplay[128];
		FormatEx(sDisplay, 128, "%T: %s", "Time", client, sTime);
		hMenu.AddItem("-1", sDisplay);

		// 2 - jumps
		int jumps = results.FetchInt(2);
		FormatEx(sDisplay, 128, "%T: %d", "Jumps", client, jumps);
		hMenu.AddItem("-1", sDisplay);

		// 3 - style
		int style = results.FetchInt(3);
		FormatEx(sDisplay, 128, "%T: %s", "Style", client, gS_StyleStrings[style].sStyleName);
		hMenu.AddItem("-1", sDisplay);

		// 4 - steamid3
		iSteamID = results.FetchInt(4);

		// 6 - map
		results.FetchString(6, sMap, sizeof(sMap));

		float points = results.FetchFloat(9);

		if(gB_Rankings && points > 0.0)
		{
			FormatEx(sDisplay, 128, "%T: %.03f", "Points", client, points);
			hMenu.AddItem("-1", sDisplay);
		}

		// 5 - date
		char sDate[32];
		results.FetchString(5, sDate, 32);

		if(sDate[4] != '-')
		{
			FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", StringToInt(sDate));
		}

		FormatEx(sDisplay, 128, "%T: %s", "Date", client, sDate);
		hMenu.AddItem("-1", sDisplay);

		int strafes = results.FetchInt(7);
		float sync = results.FetchFloat(8);

		if(jumps > 0 || strafes > 0)
		{
			FormatEx(sDisplay, 128, (sync > 0.0)? "%T: %d (%.02f%%)":"%T: %d", "Strafes", client, strafes, sync, "Strafes", client, strafes);
			hMenu.AddItem("-1", sDisplay);
		}
	}

	char sFormattedTitle[256];
	FormatEx(sFormattedTitle, 256, "%s [U:1:%d]\n--- %s:", sName, iSteamID, sMap);

	hMenu.SetTitle(sFormattedTitle);
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int SubMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowMaps(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int Native_OpenStatsMenu(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	gI_TargetSteamID[client] = GetNativeCell(2);
	OpenStatsMenu(client, gI_TargetSteamID[client]);
}
