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

#undef REQUIRE_PLUGIN
#define USES_CHAT_COLORS
#include <shavit>

// database
Database gH_SQL = null;
char gS_MySQLPrefix[32];

// cache
EngineVersion gEV_Type = Engine_Unknown;

bool gB_AllowCustom[MAXPLAYERS+1];

bool gB_NameEnabled[MAXPLAYERS+1];
char gS_CustomName[MAXPLAYERS+1][128];

bool gB_MessageEnabled[MAXPLAYERS+1];
char gS_CustomMessage[MAXPLAYERS+1][16];

public Plugin myinfo =
{
	name = "[shavit] Chat",
	author = "shavit",
	description = "Custom chat privileges (custom name and message colors).",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
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

	RegAdminCmd("sm_cclist", Command_CCList, ADMFLAG_CHAT, "Print the custom chat setting of all online players.");

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			OnClientPostAdminCheck(i);
		}
	}

	if(LibraryExists("shavit"))
	{
		Shavit_GetDB(gH_SQL);
		SQL_SetPrefix();
		SetSQLInfo();
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit"))
	{
		Shavit_GetDB(gH_SQL);
		SQL_SetPrefix();
		SetSQLInfo();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit"))
	{
		gH_SQL = null;
	}
}

public void Shavit_OnDatabaseLoaded(Database db)
{
	gH_SQL = db;
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

public void OnClientDisconnect(int client)
{
	gB_AllowCustom[client] = false;
}

public void OnClientPutInServer(int client)
{
	gB_AllowCustom[client] = false;

	gB_NameEnabled[client] = false;
	strcopy(gS_CustomName[client], 128, "");

	gB_MessageEnabled[client] = false;
	strcopy(gS_CustomMessage[client], 128, "");
}

public void OnClientPostAdminCheck(int client)
{
	gB_AllowCustom[client] = CheckCommandAccess(client, "shavit_chat", ADMFLAG_CHAT);

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

	PrintToConsole(client, "%T\n", "CCHelp_Intro", client);
	PrintToConsole(client, "%T", "CCHelp_Generic", client);
	PrintToConsole(client, "%T", "CCHelp_GenericVariables", client);

	if(gEV_Type == Engine_CSS)
	{
		PrintToConsole(client, "%T", "CCHelp_CSS_1", client);
		PrintToConsole(client, "%T", "CCHelp_CSS_2", client);
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

	if(!gB_AllowCustom[client])
	{
		Shavit_PrintToChat(client, "%T", "NoCommandAccess", client);

		return Plugin_Handled;
	}

	char[] sArgs = new char[128];
	GetCmdArgString(sArgs, 128);
	TrimString(sArgs);
	FormatColors(sArgs, 128, true, true);

	if(args == 0 || strlen(sArgs) == 0)
	{
		Shavit_PrintToChat(client, "%T", "ArgumentsMissing", client, "sm_ccname <text>");
		Shavit_PrintToChat(client, "%T", "ChatCurrent", client, sArgs);

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

	if(!gB_AllowCustom[client])
	{
		Shavit_PrintToChat(client, "%T", "NoCommandAccess", client);

		return Plugin_Handled;
	}

	char[] sArgs = new char[32];
	GetCmdArgString(sArgs, 32);
	TrimString(sArgs);
	FormatColors(sArgs, 32, true, true);

	if(args == 0 || strlen(sArgs) == 0)
	{
		Shavit_PrintToChat(client, "%T", "ArgumentsMissing", client, "sm_ccmsg <text>");
		Shavit_PrintToChat(client, "%T", "ChatCurrent", client, sArgs);

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

public Action Command_CCList(int client, int args)
{
	ReplyToCommand(client, "%T", "CheckConsole", client);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(gB_AllowCustom[i])
		{
			PrintToConsole(client, "%N (%d/%d) (name: \"%s\"; message: \"%s\")", i, i, GetClientUserId(i), gS_CustomName[i], gS_CustomMessage[i])
		}
	}

	return Plugin_Handled;
}

public Action CP_OnChatMessage(int &author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool &processcolors, bool &removecolors)
{
	if(!gB_AllowCustom[author])
	{
		return Plugin_Continue;
	}

	Action retvalue = Plugin_Continue;

	if(gB_NameEnabled[author] && strlen(gS_CustomName[author]) > 0)
	{
		char[] sName = new char[MAX_NAME_LENGTH];
		GetClientName(author, sName, MAX_NAME_LENGTH);
		ReplaceString(gS_CustomName[author], MAXLENGTH_NAME, "{name}", sName);

		strcopy(name, MAXLENGTH_NAME, gS_CustomName[author]);
		FormatRandom(name, MAXLENGTH_NAME);

		retvalue = Plugin_Changed;
	}

	if(gB_MessageEnabled[author] && strlen(gS_CustomMessage[author]) > 0)
	{
		Format(message, MAXLENGTH_MESSAGE, "%s%s", gS_CustomMessage[author], message);
		FormatRandom(message, MAXLENGTH_MESSAGE);

		retvalue = Plugin_Changed;
	}

	removecolors = true;
	processcolors = false;

	return retvalue;
}

void FormatColors(char[] buffer, int size, bool colors, bool escape)
{
	if(colors)
	{
		for(int i = 0; i < sizeof(gS_GlobalColorNames); i++)
		{
			ReplaceString(buffer, size, gS_GlobalColorNames[i], gS_GlobalColors[i]);
		}

		for(int i = 0; i < sizeof(gS_CSGOColorNames); i++)
		{
			ReplaceString(buffer, size, gS_CSGOColorNames[i], gS_CSGOColors[i]);
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

void FormatRandom(char[] buffer, int size)
{
	char[] temp = new char[8];

	do
	{
		int color = ((RealRandomInt(0, 255) & 0xFF) << 16);
		color |= ((RealRandomInt(0, 255) & 0xFF) << 8);
		color |= (RealRandomInt(0, 255) & 0xFF);

		FormatEx(temp, 16, "\x07%06X", color);
	}

	while(ReplaceStringEx(buffer, size, "{rand}", temp) > 0);
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
		char[] sQuery = new char[512];
		FormatEx(sQuery, 512, "CREATE TABLE IF NOT EXISTS `%schat` (`auth` VARCHAR(32) NOT NULL, `name` INT NOT NULL DEFAULT 0, `ccname` VARCHAR(128), `message` INT NOT NULL DEFAULT 0, `ccmessage` VARCHAR(16), PRIMARY KEY (`auth`));", gS_MySQLPrefix);
		
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
		if(gB_AllowCustom[i])
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
