/*
 * shavit's Timer - Chat
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

// Note: For donator perks, give donators a custom flag and then override it to have "shavit_chat".

#include <sourcemod>
#include <chat-processor>
#include <clientprefs>

#undef REQUIRE_PLUGIN
#define USES_CHAT_COLORS
#include <shavit>
#include <rtler>

#undef REQUIRE_EXTENSIONS
#include <cstrike>

enum ChatRanksCache
{
	iCRRangeType, // 0 - flat, 1 - percent, 2 - point range
	Float:fCRFrom,
	Float:fCRTo,
	bool:bCRFree,
	String:sCRName[MAXLENGTH_NAME],
	String:sCRMessage[MAXLENGTH_MESSAGE],
	String:sCRDisplay[192],
	CRCACHE_SIZE
}

enum
{
	Rank_Flat,
	Rank_Percentage,
	Rank_Points
}

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

// database
Database gH_SQL = null;
char gS_MySQLPrefix[32];

// modules
bool gB_Rankings = false;
bool gB_RTLer = false;

// cvars
ConVar gCV_RankingsIntegration = null;
ConVar gCV_CustomChat = null;

// cached cvars
bool gB_RankingsIntegration = true;
int gI_CustomChat = 1;

// cache
EngineVersion gEV_Type = Engine_Unknown;

Handle gH_ChatCookie = null;

// -2: auto-assign - user will fallback to this if they're on an index that they don't have access to.
// -1: custom ccname/ccmsg
int gI_ChatSelection[MAXPLAYERS+1];
ArrayList gA_ChatRanks = null;

bool gB_NameEnabled[MAXPLAYERS+1];
char gS_CustomName[MAXPLAYERS+1][128];

bool gB_MessageEnabled[MAXPLAYERS+1];
char gS_CustomMessage[MAXPLAYERS+1][16];

public Plugin myinfo =
{
	name = "[shavit] Chat",
	author = "shavit",
	description = "Custom chat privileges (custom name/message colors), and rankings integration.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public void OnAllPluginsLoaded()
{
	gB_RTLer = LibraryExists("rtler");

	if(gH_SQL == null)
	{
		Shavit_OnDatabaseLoaded();
	}
}

public void OnPluginStart()
{
	gEV_Type = GetEngineVersion();

	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-chat.phrases");

	RegConsoleCmd("sm_cchelp", Command_CCHelp, "Provides help with setting a custom chat name/message color.");
	RegConsoleCmd("sm_ccname", Command_CCName, "Toggles/sets a custom chat name. Usage: sm_ccname <text> or sm_ccname \"off\" to disable.");
	RegConsoleCmd("sm_ccmsg", Command_CCMessage, "Toggles/sets a custom chat message color. Usage: sm_ccmsg <color> or sm_ccmsg \"off\" to disable.");
	RegConsoleCmd("sm_ccmessage", Command_CCMessage, "Toggles/sets a custom chat message color. Usage: sm_ccmessage <color> or sm_ccmessage \"off\" to disable.");
	RegConsoleCmd("sm_chatrank", Command_ChatRanks, "View a menu with the chat ranks available to you.");
	RegConsoleCmd("sm_chatranks", Command_ChatRanks, "View a menu with the chat ranks available to you.");

	RegAdminCmd("sm_cclist", Command_CCList, ADMFLAG_CHAT, "Print the custom chat setting of all online players.");
	RegAdminCmd("sm_reloadchatranks", Command_ReloadChatRanks, ADMFLAG_ROOT, "Reloads the chatranks config file.");

	gCV_RankingsIntegration = CreateConVar("shavit_chat_rankings", "1", "Integrate with rankings?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_CustomChat = CreateConVar("shavit_chat_customchat", "1", "Allow custom chat names or message colors?\n0 - Disabled\n1 - Enabled (requires chat flag/'shavit_chat' override)\n2 - Allow use by everyone", 0, true, 0.0, true, 2.0);

	gCV_RankingsIntegration.AddChangeHook(OnConVarChanged);
	gCV_CustomChat.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	gH_ChatCookie = RegClientCookie("shavit_chat_selection", "Chat settings", CookieAccess_Protected);
	gA_ChatRanks = new ArrayList(view_as<int>(CRCACHE_SIZE));

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			if(AreClientCookiesCached(i))
			{
				OnClientCookiesCached(i);
			}
		}
	}
	
	SQL_SetPrefix();
}

public void OnMapStart()
{
	if(!LoadChatConfig())
	{
		SetFailState("Could not load the chat configuration file. Make sure it exists (addons/sourcemod/configs/shavit-chat.cfg) and follows the proper syntax!");
	}
}

bool LoadChatConfig()
{
	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/shavit-chat.cfg");

	KeyValues kv = new KeyValues("shavit-chat");
	
	if(!kv.ImportFromFile(sPath) || !kv.GotoFirstSubKey())
	{
		delete kv;

		return false;
	}

	gA_ChatRanks.Clear();

	do
	{
		any[] aChatTitle = new any[CRCACHE_SIZE];
		char[] sRanks = new char[32];
		kv.GetString("ranks", sRanks, MAXLENGTH_NAME, "0");

		if(sRanks[0] == 'p')
		{	
			aChatTitle[iCRRangeType] = Rank_Points;
		}

		else
		{
			aChatTitle[iCRRangeType] = (StrContains(sRanks, "%%") == -1)? Rank_Flat:Rank_Percentage;
		}
		
		ReplaceString(sRanks, 32, "p", "");
		ReplaceString(sRanks, 32, "%%", "");

		if(StrContains(sRanks, "-") != -1)
		{
			char[][] sExplodedString = new char[2][16];
			ExplodeString(sRanks, "-", sExplodedString, 2, 64);
			aChatTitle[fCRFrom] = StringToFloat(sExplodedString[0]);
			aChatTitle[fCRTo] = StringToFloat(sExplodedString[1]);
		}

		else
		{
			float fRank = StringToFloat(sRanks);

			aChatTitle[fCRFrom] = fRank;
			aChatTitle[fCRTo] = (aChatTitle[iCRRangeType] != Rank_Points)? fRank:2147483648.0;
		}
		
		aChatTitle[bCRFree] = view_as<bool>(kv.GetNum("free", false));

		kv.GetString("name", aChatTitle[sCRName], MAXLENGTH_NAME, "{name}");
		kv.GetString("message", aChatTitle[sCRMessage], MAXLENGTH_MESSAGE, "");
		kv.GetString("display", aChatTitle[sCRDisplay], 192, "");

		if(strlen(aChatTitle[sCRDisplay]) > 0)
		{
			gA_ChatRanks.PushArray(aChatTitle);
		}
	}

	while(kv.GotoNextKey());

	delete kv;

	return true;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gB_RankingsIntegration = gCV_RankingsIntegration.BoolValue;
	gI_CustomChat = gCV_CustomChat.IntValue;
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

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "rtler"))
	{
		gB_RTLer = true;
	}

	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "rtler"))
	{
		gB_RTLer = false;
	}

	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}
}

public void OnClientCookiesCached(int client)
{
	char[] sChatSettings = new char[8];
	GetClientCookie(client, gH_ChatCookie, sChatSettings, 8);

	if(strlen(sChatSettings) == 0)
	{
		SetClientCookie(client, gH_ChatCookie, "-2");
		gI_ChatSelection[client] = -2;
	}

	else
	{
		gI_ChatSelection[client] = StringToInt(sChatSettings);
	}
}

public void OnClientPutInServer(int client)
{
	gB_NameEnabled[client] = false;
	strcopy(gS_CustomName[client], 128, "");

	gB_MessageEnabled[client] = false;
	strcopy(gS_CustomMessage[client], 128, "");
}

public void OnClientPostAdminCheck(int client)
{
	if(gH_SQL != null)
	{
		LoadFromDatabase(client);
	}
}

public Action Command_CCHelp(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "%t", "NoConsole");

		return Plugin_Handled;
	}

	Shavit_PrintToChat(client, "%T", "CheckConsole", client);

	PrintToConsole(client, "%T\n\n%T\n\n%T\n",
		"CCHelp_Intro", client,
		"CCHelp_Generic", client,
		"CCHelp_GenericVariables", client);

	if(IsSource2013(gEV_Type))
	{
		PrintToConsole(client, "%T\n\n%T",
			"CCHelp_CSS_1", client,
			"CCHelp_CSS_2", client);
	}

	else
	{
		PrintToConsole(client, "%T", "CCHelp_CSGO_1", client);
	}

	return Plugin_Handled;
}

public Action Command_CCName(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "%t", "NoConsole");

		return Plugin_Handled;
	}

	if(!(gI_CustomChat > 0 && (CheckCommandAccess(client, "shavit_chat", ADMFLAG_CHAT) || gI_CustomChat == 2)))
	{
		Shavit_PrintToChat(client, "%T", "NoCommandAccess", client);

		return Plugin_Handled;
	}

	char[] sArgs = new char[128];
	GetCmdArgString(sArgs, 128);

	if(args == 0 || strlen(sArgs) == 0)
	{
		Shavit_PrintToChat(client, "%T", "ArgumentsMissing", client, "sm_ccname <text>");
		Shavit_PrintToChat(client, "%T", "ChatCurrent", client, gS_CustomName[client]);

		return Plugin_Handled;
	}

	else if(StrEqual(sArgs, "off"))
	{
		Shavit_PrintToChat(client, "%T", "NameOff", client, sArgs);

		gB_NameEnabled[client] = false;

		SaveToDatabase(client);

		return Plugin_Handled;
	}

	Shavit_PrintToChat(client, "%T", "ChatUpdated", client);

	gB_NameEnabled[client] = true;
	strcopy(gS_CustomName[client], 128, sArgs);

	SaveToDatabase(client);

	return Plugin_Handled;
}

public Action Command_CCMessage(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "%t", "NoConsole");

		return Plugin_Handled;
	}

	if(!(gI_CustomChat > 0 && (CheckCommandAccess(client, "shavit_chat", ADMFLAG_CHAT) || gI_CustomChat == 2)))
	{
		Shavit_PrintToChat(client, "%T", "NoCommandAccess", client);

		return Plugin_Handled;
	}

	char[] sArgs = new char[32];
	GetCmdArgString(sArgs, 32);

	if(args == 0 || strlen(sArgs) == 0)
	{
		Shavit_PrintToChat(client, "%T", "ArgumentsMissing", client, "sm_ccmsg <text>");
		Shavit_PrintToChat(client, "%T", "ChatCurrent", client, gS_CustomMessage[client]);

		return Plugin_Handled;
	}

	else if(StrEqual(sArgs, "off"))
	{
		Shavit_PrintToChat(client, "%T", "MessageOff", client, sArgs);

		gB_MessageEnabled[client] = false;

		SaveToDatabase(client);

		return Plugin_Handled;
	}

	Shavit_PrintToChat(client, "%T", "ChatUpdated", client);

	gB_MessageEnabled[client] = true;
	strcopy(gS_CustomMessage[client], 16, sArgs);

	SaveToDatabase(client);

	return Plugin_Handled;
}

public Action Command_ChatRanks(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}

	return ShowChatRanksMenu(client, 0);
}

Action ShowChatRanksMenu(int client, int item)
{
	Menu menu = new Menu(MenuHandler_ChatRanks);
	menu.SetTitle("%T\n ", "SelectChatRank", client);

	char[] sDisplay = new char[128];
	FormatEx(sDisplay, 128, "%T\n ", "AutoAssign", client);
	menu.AddItem("-2", sDisplay, (gI_ChatSelection[client] == -2)? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

	if(gI_CustomChat > 0 && (CheckCommandAccess(client, "shavit_chat", ADMFLAG_CHAT) || gI_CustomChat == 2))
	{
		FormatEx(sDisplay, 128, "%T\n ", "CustomChat", client);
		menu.AddItem("-1", sDisplay, (gI_ChatSelection[client] == -1)? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	}

	int iLength = gA_ChatRanks.Length;

	for(int i = 0; i < iLength; i++)
	{
		if(!HasRankAccess(client, i))
		{
			continue;
		}

		any[] aCache = new any[CRCACHE_SIZE];
		gA_ChatRanks.GetArray(i, aCache, view_as<int>(CRCACHE_SIZE));

		strcopy(sDisplay, 192, aCache[sCRDisplay]);
		ReplaceString(sDisplay, 192, "<n>", "\n");
		StrCat(sDisplay, 192, "\n "); // to add spacing between each entry

		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		menu.AddItem(sInfo, sDisplay, (gI_ChatSelection[client] == i)? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	}

	menu.ExitButton = true;
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int MenuHandler_ChatRanks(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[8];
		menu.GetItem(param2, sInfo, 8);

		int iChoice = StringToInt(sInfo);

		gI_ChatSelection[param1] = iChoice;
		SetClientCookie(param1, gH_ChatCookie, sInfo);

		Shavit_PrintToChat(param1, "%T", "ChatUpdated", param1);
		ShowChatRanksMenu(param1, GetMenuSelectionPosition());
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}
}

bool HasRankAccess(int client, int rank)
{
	bool bAllowCustom = gI_CustomChat > 0 && (CheckCommandAccess(client, "shavit_chat", ADMFLAG_CHAT) || gI_CustomChat == 2);

	if(rank == -2 ||
		(rank == -1 && bAllowCustom))
	{
		return true;
	}

	else if(!(0 <= rank <= (gA_ChatRanks.Length - 1)))
	{
		return false;
	}

	static any aCache[view_as<int>(bCRFree)+1];
	gA_ChatRanks.GetArray(rank, aCache[0], sizeof(aCache)); // a hack to only retrieve up to what we want

	if(aCache[bCRFree])
	{
		return true;
	}

	if(!gB_Rankings || !gB_RankingsIntegration)
	{
		return false;
	}

	float fRank = (aCache[iCRRangeType] != Rank_Points)? float(Shavit_GetRank(client)):Shavit_GetPoints(client);

	if(aCache[iCRRangeType] == Rank_Flat || aCache[iCRRangeType] == Rank_Points)
	{
		if(aCache[fCRFrom] <= fRank <= aCache[fCRTo])
		{
			return true;
		}
	}

	else
	{
		int iRanked = Shavit_GetRankedPlayers();

		// just in case..
		if(iRanked == 0)
		{
			iRanked = 1;
		}

		float fPercentile = (fRank / iRanked) * 100.0;
		
		if(aCache[fCRFrom] <= fPercentile <= aCache[fCRTo])
		{
			PrintToServer("%.1f <= %.2f <= %.2f", aCache[fCRFrom], fPercentile, aCache[fCRTo]);

			return true;
		}
	}

	return false;
}

void GetPlayerChatSettings(int client, char[] name, char[] message)
{
	int iRank = gI_ChatSelection[client];
	
	if(!HasRankAccess(client, iRank))
	{
		iRank = -2;
	}

	int iLength = gA_ChatRanks.Length;

	// if we auto-assign, start looking for an available rank starting from index 0
	if(iRank == -2)
	{
		for(int i = 0; i < iLength; i++)
		{
			if(HasRankAccess(client, i))
			{
				iRank = i;

				break;
			}
		}
	}

	if(0 <= iRank <= (iLength - 1))
	{
		any[] aCache = new any[CRCACHE_SIZE];
		gA_ChatRanks.GetArray(iRank, aCache, view_as<int>(CRCACHE_SIZE));

		strcopy(name, MAXLENGTH_NAME, aCache[sCRName]);
		strcopy(message, MAXLENGTH_NAME, aCache[sCRMessage]);
	}
}

public Action Command_CCList(int client, int args)
{
	ReplyToCommand(client, "%T", "CheckConsole", client);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
		{
			continue;
		}

		if(gI_CustomChat > 0 && (CheckCommandAccess(i, "shavit_chat", ADMFLAG_CHAT) || gI_CustomChat == 2))
		{
			PrintToConsole(client, "%N (%d/#%d) (name: \"%s\"; message: \"%s\")", i, i, GetClientUserId(i), gS_CustomName[i], gS_CustomMessage[i]);
		}
	}

	return Plugin_Handled;
}

public Action Command_ReloadChatRanks(int client, int args)
{
	if(LoadChatConfig())
	{
		ReplyToCommand(client, "Reloaded chatranks config.");
	}

	return Plugin_Handled;
}

public Action CP_OnChatMessage(int &author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool &processcolors, bool &removecolors)
{
	if(author == 0)
	{
		return Plugin_Continue;
	}

	char[] sName = new char[MAXLENGTH_NAME];
	char[] sMessage = new char[MAXLENGTH_MESSAGE];

	if((gI_CustomChat > 0 && (CheckCommandAccess(author, "shavit_chat", ADMFLAG_CHAT) || gI_CustomChat == 2)) && gI_ChatSelection[author] == -1)
	{
		if(gB_NameEnabled[author])
		{
			strcopy(sName, MAXLENGTH_NAME, gS_CustomName[author]);
		}

		if(gB_MessageEnabled[author])
		{
			strcopy(sMessage, MAXLENGTH_MESSAGE, gS_CustomMessage[author]);
		}
	}

	else
	{
		GetPlayerChatSettings(author, sName, sMessage);
	}

	if(strlen(sName) > 0)
	{
		if(gEV_Type == Engine_CSGO)
		{
			FormatEx(name, MAXLENGTH_NAME, " %s", sName);
		}

		else
		{
			strcopy(name, MAXLENGTH_NAME, sName);
		}

		FormatChat(author, name, MAXLENGTH_NAME);
	}

	if(strlen(sMessage) > 0)
	{
		char[] sTemp = new char[MAXLENGTH_MESSAGE];

		// proper colors with rtler
		if(gB_RTLer && RTLify(sTemp, MAXLENGTH_MESSAGE, message) > 0)
		{
			TrimString(message);
			Format(message, MAXLENGTH_MESSAGE, "%s%s", message, sMessage);
		}

		else
		{
			Format(message, MAXLENGTH_MESSAGE, "%s%s", sMessage, message);
		}

		FormatChat(author, message, MAXLENGTH_NAME);
	}

	#if defined DEBUG
	PrintToServer("%N %s", author, flagstring);
	#endif

	removecolors = true;
	processcolors = false;

	return Plugin_Changed;
}

void FormatColors(char[] buffer, int size, bool colors, bool escape)
{
	if(colors)
	{
		for(int i = 0; i < sizeof(gS_GlobalColorNames); i++)
		{
			ReplaceString(buffer, size, gS_GlobalColorNames[i], gS_GlobalColors[i]);
		}

		if(gEV_Type == Engine_CSGO)
		{
			for(int i = 0; i < sizeof(gS_CSGOColorNames); i++)
			{
				ReplaceString(buffer, size, gS_CSGOColorNames[i], gS_CSGOColors[i]);
			}
		}

		ReplaceString(buffer, size, "^", "\x07");
		ReplaceString(buffer, size, "{RGB}", "\x07");
		ReplaceString(buffer, size, "&", "\x08");
		ReplaceString(buffer, size, "{RGBA}", "\x08");
	}

	if(escape)
	{
		ReplaceString(buffer, size, "%%", "");
	}
}

void FormatChat(int client, char[] buffer, int size)
{
	FormatColors(buffer, size, true, true);

	char[] temp = new char[8];

	do
	{
		if(IsSource2013(gEV_Type))
		{
			int color = ((RealRandomInt(0, 255) & 0xFF) << 16);
			color |= ((RealRandomInt(0, 255) & 0xFF) << 8);
			color |= (RealRandomInt(0, 255) & 0xFF);

			FormatEx(temp, 8, "\x07%06X", color);
		}

		else
		{
			strcopy(temp, 8, gS_CSGOColors[RealRandomInt(0, sizeof(gS_CSGOColors) - 1)]);
		}
	}

	while(ReplaceStringEx(buffer, size, "{rand}", temp) > 0);

	if(gEV_Type != Engine_TF2)
	{
		char[] sTag = new char[32];
		CS_GetClientClanTag(client, sTag, 32);
		ReplaceString(buffer, size, "{clan}", sTag);
	}

	if(gB_Rankings)
	{
		int iRank = Shavit_GetRank(client);
		char[] sRank = new char[16];
		IntToString(iRank, sRank, 16);
		ReplaceString(buffer, size, "{rank}", sRank);

		int iRanked = Shavit_GetRankedPlayers();

		if(iRanked == 0)
		{
			iRanked = 1;
		}

		float fPercentile = (float(iRank) / iRanked) * 100.0;
		FormatEx(sRank, 16, "%.01f", fPercentile);
		ReplaceString(buffer, size, "{rank1}", sRank);

		FormatEx(sRank, 16, "%.02f", fPercentile);
		ReplaceString(buffer, size, "{rank2}", sRank);

		FormatEx(sRank, 16, "%.03f", fPercentile);
		ReplaceString(buffer, size, "{rank3}", sRank);
	}

	char[] sName = new char[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);
	ReplaceString(buffer, size, "{name}", sName);
}

int RealRandomInt(int min, int max)
{
	int random = GetURandomInt();

	if(random == 0)
	{
		random++;
	}

	return (RoundToCeil(float(random) / (float(2147483647) / float(max - min + 1))) + min - 1);
}

void SQL_DBConnect()
{
	if(gH_SQL != null)
	{
		char[] sDriver = new char[8];
		gH_SQL.Driver.GetIdentifier(sDriver, 8);
		bool bMySQL = StrEqual(sDriver, "mysql", false);

		char[] sQuery = new char[512];
		FormatEx(sQuery, 512, "CREATE TABLE IF NOT EXISTS `%schat` (`auth` CHAR(32) NOT NULL, `name` INT NOT NULL DEFAULT 0, `ccname` CHAR(128), `message` INT NOT NULL DEFAULT 0, `ccmessage` CHAR(16), PRIMARY KEY (`auth`))%s;", gS_MySQLPrefix, (bMySQL)? " ENGINE=INNODB":"");
		
		gH_SQL.Query(SQL_CreateTable_Callback, sQuery, 0, DBPrio_High);
	}
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Chat table creation failed. Reason: %s", error);

		return;
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
		{
			continue;
		}

		if(gI_CustomChat > 0 && (CheckCommandAccess(i, "shavit_chat", ADMFLAG_CHAT) || gI_CustomChat == 2))
		{
			LoadFromDatabase(i);
		}
	}
}

void SaveToDatabase(int client)
{
	char[] sAuthID3 = new char[32];

	if(!GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
	{
		return;
	}

	int iLength = ((strlen(gS_CustomName[client]) * 2) + 1);
	char[] sEscapedName = new char[iLength];
	gH_SQL.Escape(gS_CustomName[client], sEscapedName, iLength);

	iLength = ((strlen(gS_CustomMessage[client]) * 2) + 1);
	char[] sEscapedMessage = new char[iLength];
	gH_SQL.Escape(gS_CustomMessage[client], sEscapedMessage, iLength);

	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "REPLACE INTO %schat (auth, name, ccname, message, ccmessage) VALUES ('%s', %d, '%s', %d, '%s');", gS_MySQLPrefix, sAuthID3, gB_NameEnabled[client], sEscapedName, gB_MessageEnabled[client], sEscapedMessage);

	gH_SQL.Query(SQL_UpdateUser_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_UpdateUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Failed to insert chat data. Reason: %s", error);

		return;
	}
}

void LoadFromDatabase(int client)
{
	char[] sAuthID3 = new char[32];

	if(!GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
	{
		return;
	}

	char sQuery[256];
	FormatEx(sQuery, 256, "SELECT name, ccname, message, ccmessage FROM %schat WHERE auth = '%s';", gS_MySQLPrefix, sAuthID3);

	gH_SQL.Query(SQL_GetChat_Callback, sQuery, GetClientSerial(client), DBPrio_Low);
}

public void SQL_GetChat_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (Chat cache update) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	while(results.FetchRow())
	{
		gB_NameEnabled[client] = view_as<bool>(results.FetchInt(0));
		results.FetchString(1, gS_CustomName[client], 128);

		gB_MessageEnabled[client] = view_as<bool>(results.FetchInt(2));
		results.FetchString(3, gS_CustomMessage[client], 16);
	}
}
