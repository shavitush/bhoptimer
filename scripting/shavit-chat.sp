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

#include <sourcemod>
#include <cstrike>
#include <dynamic>

#define USES_CHAT_COLORS
#include <shavit>

#undef REQUIRE_PLUGIN
#include <basecomm>
#include <rtler>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

// cache
float gF_LastMessage[MAXPLAYERS+1];

char gS_Cached_Prefix[MAXPLAYERS+1][32];
char gS_Cached_Name[MAXPLAYERS+1][MAX_NAME_LENGTH*2];
char gS_Cached_Message[MAXPLAYERS+1][255];

StringMap gSM_Custom_Prefix = null;
StringMap gSM_Custom_Name = null;
StringMap gSM_Custom_Message = null;

int gI_TotalChatRanks = 0;
Dynamic gD_ChatRanks[64]; // limited to 64 chat ranks right now, i really don't think there's a need for more.

// modules
bool gB_BaseComm = false;
bool gB_RTLer = false;

// game-related
ServerGame gSG_Type = Game_Unknown;

public Plugin myinfo =
{
	name = "[shavit] Chat",
	author = "shavit",
	description = "Chat handler for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// natives
	CreateNative("Shavit_FormatChat", Native_FormatChat);
	MarkNativeAsOptional("Shavit_FormatChat");

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-chat");

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
    if(!LibraryExists("shavit-rankings"))
    {
        SetFailState("shavit-rankings is required for the plugin to work.");
    }

    // placed here and not in OnPluginStart() as `chat` is coming before `core` if sorted alphabetically
    gSG_Type = Shavit_GetGameType();

    // modules
    gB_BaseComm = LibraryExists("basecomm");
    gB_RTLer = LibraryExists("rtler");
}

public void OnPluginStart()
{
	RegAdminCmd("sm_reloadchat", Command_ReloadChat, ADMFLAG_ROOT, "Reload chat config.");

	RegConsoleCmd("sm_chatranks", Command_ChatRanks, "Shows a list of all the possible chat ranks.");
	RegConsoleCmd("sm_ranks", Command_ChatRanks, "Shows a list of all the possible chat ranks. Alias for sm_chatranks.");
}

public void OnMapStart()
{
    LoadConfig();
}

public void OnClientPutInServer(int client)
{
	gF_LastMessage[client] = GetEngineTime();
}

public void OnClientAuthorized(int client, const char[] auth)
{
	LoadChatCache(client);
}

public void OnLibraryAdded(const char[] name)
{
    if(StrEqual(name, "basecomm"))
    {
        gB_BaseComm = true;
    }

    else if(StrEqual(name, "rtler"))
    {
        gB_RTLer = true;
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if(StrEqual(name, "basecomm"))
    {
        gB_BaseComm = false;
    }

    else if(StrEqual(name, "rtler"))
    {
        gB_RTLer = false;
    }
}

public void Shavit_OnRankUpdated(int client)
{
	LoadChatCache(client);
}

public void LoadChatCache(int client)
{
	// assign rank properties
	int iRank = Shavit_GetRank(client);

	if(iRank == -1)
	{
		return;
	}

	for(int i = 0; i < gI_TotalChatRanks; i++)
	{
		if(gD_ChatRanks[i].IsValid)
		{
			int iFrom = gD_ChatRanks[i].GetInt("rank_from");
			int iTo = gD_ChatRanks[i].GetInt("rank_to");

			if(iRank < iFrom || (iRank > iTo && iTo != -3))
			{
				continue;
			}

			gD_ChatRanks[i].GetString("prefix", gS_Cached_Prefix[client], 32);
			gD_ChatRanks[i].GetString("name", gS_Cached_Name[client], MAX_NAME_LENGTH*2);
			gD_ChatRanks[i].GetString("message", gS_Cached_Message[client], 255);
		}
	}

	char[] sAuthID = new char[32];

	if(GetClientAuthId(client, AuthId_Steam3, sAuthID, 32))
	{
		char[] sBuffer = new char[255];

		if(gSM_Custom_Prefix.GetString(sAuthID, sBuffer, 255))
		{
			strcopy(gS_Cached_Prefix[client], 32, sBuffer);
		}

		if(gSM_Custom_Name.GetString(sAuthID, sBuffer, 255))
		{
			strcopy(gS_Cached_Name[client], MAX_NAME_LENGTH*2, sBuffer);
		}

		if(gSM_Custom_Message.GetString(sAuthID, sBuffer, 255))
		{
			strcopy(gS_Cached_Message[client], 255, sBuffer);
		}
	}
}

public void LoadConfig()
{
	delete gSM_Custom_Prefix;
	delete gSM_Custom_Name;
	delete gSM_Custom_Message;

	gSM_Custom_Prefix = new StringMap();
	gSM_Custom_Name = new StringMap();
	gSM_Custom_Message = new StringMap();

	for(int i = 0; i < 64; i++)
	{
		if(gD_ChatRanks[i].IsValid)
		{
			gD_ChatRanks[i].Dispose();
		}
	}

	gI_TotalChatRanks = 0;

	KeyValues kvConfig = new KeyValues("Chat");

	char[] sFile = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-chat.cfg");

	if(!kvConfig.ImportFromFile(sFile))
	{
		SetFailState("File %s could not be found or accessed.", sFile);
	}

	if(kvConfig.GotoFirstSubKey())
	{
		char[] sBuffer = new char[255];

		do
		{
			kvConfig.GetSectionName(sBuffer, 255);

			char[] sPrefix = new char[32];
			kvConfig.GetString("prefix", sPrefix, 32);

			char[] sName = new char[MAX_NAME_LENGTH*2];
			kvConfig.GetString("name", sName, MAX_NAME_LENGTH*2);

			char[] sMessage = new char[255];
			kvConfig.GetString("message", sMessage, 255);

			// custom
			if(StrContains(sBuffer[0], "[U:") != -1)
			{
				if(strlen(sPrefix) > 0)
				{
					gSM_Custom_Prefix.SetString(sBuffer, sPrefix);
				}

				if(strlen(sName) > 0)
				{
					gSM_Custom_Name.SetString(sBuffer, sName);
				}

				if(strlen(sMessage) > 0)
				{
					gSM_Custom_Message.SetString(sBuffer, sMessage);
				}
			}

			// ranks
			else
			{
				int iFrom = kvConfig.GetNum("rank_from", -2);

				if(iFrom == -2)
				{
					LogError("Invalid \"rank_from\" value for \"%s\": %d or non-existant.", sBuffer, iFrom);

					continue;
				}

				char[] sTo = new char[16];
				kvConfig.GetString("rank_to", sTo, 16, "-2");
				int iTo = StrEqual(sTo, "infinity", false)? -3:StringToInt(sTo);

				if(iTo == -2)
				{
					LogError("Invalid \"rank_to\" value for \"%s\": %d or non-existant.", sBuffer, iTo);

					continue;
				}

				gD_ChatRanks[gI_TotalChatRanks] = Dynamic();
				gD_ChatRanks[gI_TotalChatRanks].SetInt("rank_from", iFrom);
				gD_ChatRanks[gI_TotalChatRanks].SetInt("rank_to", iTo);
				gD_ChatRanks[gI_TotalChatRanks].SetString("prefix", sPrefix, 32);
				gD_ChatRanks[gI_TotalChatRanks].SetString("name", (strlen(sName) > 0)? sName:"{name}", MAX_NAME_LENGTH*2);
				gD_ChatRanks[gI_TotalChatRanks].SetString("message", (strlen(sMessage) > 0)? sMessage:"{message}", 255);

				gI_TotalChatRanks++;
			}
		}

		while(kvConfig.GotoNextKey());
	}

	else
	{
		LogError("File %s might be empty?", sFile);
	}

	delete kvConfig;

	for(int i = 1; i <= MaxClients; i++)
    {
		if(IsValidClient(i)) // late loading
		{
			gF_LastMessage[i] = GetEngineTime();

			Shavit_OnRankUpdated(i);
		}
	}
}

public Action Command_ChatRanks(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	// dummies
	// char[] sExample = "Example."; // I tried using this variable, but it seemed to pick up "List of Chat ranks:" instead, I wonder why..
	int[] clients = new int[1];
	clients[0] = client;

	ChatMessage(client, clients, 1, "\x01List of chat ranks:");

	for(int i = gI_TotalChatRanks - 1; i >= 0; i--)
	{
		if(gD_ChatRanks[i].IsValid)
		{
			int iFrom = gD_ChatRanks[i].GetInt("rank_from");

			if(iFrom <= 0)
			{
				continue; // don't show unranked/due-lookup 'chat ranks'
			}

			int iTo = gD_ChatRanks[i].GetInt("rank_to");
			char[] sRankText = new char[16];

			if(iFrom == iTo)
			{
				FormatEx(sRankText, 16, "#%d", iFrom);
			}

			else
			{
				PrintToConsole(client, "%d", iTo);

				if(iTo == -3)
				{
					FormatEx(sRankText, 16, "#%d - ∞", iFrom, iTo);
				}

				else
				{
					FormatEx(sRankText, 16, "#%d - #%d", iFrom, iTo);
				}
			}

			char[] sPrefix = new char[32];
			gD_ChatRanks[i].GetString("prefix", sPrefix, 32);
			FormatVariables(client, sPrefix, 32, sPrefix, "Example.");

			char[] sName = new char[MAX_NAME_LENGTH*2];
			gD_ChatRanks[i].GetString("name", sName, MAX_NAME_LENGTH*2);
			FormatVariables(client, sName, MAX_NAME_LENGTH*2, sName, "Example.");

			char[] sMessage = new char[255];
			gD_ChatRanks[i].GetString("message", sMessage, 255);
			FormatVariables(client, sMessage, 255, sMessage, "Example.");

			char[] sBuffer = new char[300];
			FormatEx(sBuffer, 300, "%s\x04[%s]\x01 %s%s %s %s  %s", gSG_Type == Game_CSGO? " ":"", sRankText, strlen(sPrefix) == 0? "\x03":"", sPrefix, sName, gSG_Type == Game_CSGO? ":\x01":"\x01:", sMessage);

			ChatMessage(client, clients, 1, sBuffer);
		}
	}

	return Plugin_Handled;
}

public Action Command_ReloadChat(int client, int args)
{
    LoadConfig();

    ReplyToCommand(client, "Config reloaded.");

    return Plugin_Handled;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(!IsValidClient(client) || !IsClientAuthorized(client) || sArgs[0] == '!' || sArgs[0] == '/' || (gB_BaseComm && BaseComm_IsClientGagged(client)))
	{
		return Plugin_Continue;
	}

	if(GetEngineTime() - gF_LastMessage[client] < 0.70)
	{
		return Plugin_Handled;
	}

	bool bTeam = StrEqual(command, "say_team");

	if(bTeam || (CheckCommandAccess(client, "sm_say", ADMFLAG_CHAT) && sArgs[0] == '@'))
	{
		return Plugin_Handled;
	}

	char[] sMessage = new char[300];
	strcopy(sMessage, 300, sArgs);
	ReplaceString(sMessage[0], 1, "!", "");
	ReplaceString(sMessage[0], 1, "/", "");

	bool bCmd = false;
	Handle hCon = FindFirstConCommand(sMessage, 300, bCmd);

	if(hCon != null)
	{
		FindNextConCommand(hCon, sMessage, 300, bCmd);
		delete hCon;

		if(bCmd)
		{
			return Plugin_Handled;
		}
	}

	gF_LastMessage[client] = GetEngineTime();

	int iTeam = GetClientTeam(client);

	FormatChat(client, sArgs, IsPlayerAlive(client), iTeam, bTeam, sMessage, 300);

	int[] clients = new int[MaxClients];
	int count = 0;

	PrintToServer("%N: %s", client, sArgs);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			if(GetClientTeam(i) == iTeam || !bTeam)
			{
				clients[count++] = i;

				PrintToConsole(i, "%N: %s", client, sArgs);
			}
		}
	}

	ChatMessage(client, clients, count, sMessage);

	return Plugin_Handled;
}

public void FormatChat(int client, const char[] sMessage, bool bAlive, int iTeam, bool bTeam, char[] buffer, int maxlen)
{
	char[] sTeam = new char[32];

	if(!bTeam)
	{
		if(iTeam == CS_TEAM_SPECTATOR)
		{
			strcopy(sTeam, 32, "*SPEC* ");
		}
	}

	else
	{
		switch(iTeam)
		{
			case CS_TEAM_SPECTATOR:
			{
				strcopy(sTeam, 32, "(Spectator) ");
			}

			case CS_TEAM_T:
			{
				strcopy(sTeam, 32, "(Terrorist) ");
			}

			case CS_TEAM_CT:
			{
				strcopy(sTeam, 32, "(Counter-Terrorist) ");
			}
		}
	}

	char[] sAuthID = new char[32];
	GetClientAuthId(client, AuthId_Steam3, sAuthID, 32);

	char[] sBuffer = new char[255];
	char[] sNewPrefix = new char[32];

	if(strlen(gS_Cached_Prefix[client]) > 0)
	{
		FormatVariables(client, sBuffer, 255, gS_Cached_Prefix[client], sMessage);
		int iLen = strlen(sBuffer);
		sBuffer[iLen] = (iLen > 0)? ' ':'\0';
		strcopy(sNewPrefix, 32, sBuffer);
	}

	char[] sNewName = new char[MAX_NAME_LENGTH*2];

	if(strlen(gS_Cached_Name[client]) > 0)
	{
		FormatVariables(client, sBuffer, 255, gS_Cached_Name[client], sMessage);
		strcopy(sNewName, MAX_NAME_LENGTH*2, sBuffer);
	}

	else
	{
		FormatEx(sNewName, MAX_NAME_LENGTH*2, "\x03%N", client);
	}

	char[] sFormattedText = new char[maxlen];
	strcopy(sFormattedText, maxlen, sMessage);

	// solve shitty exploits
	ReplaceString(sFormattedText, maxlen, "\n", "");
	ReplaceString(sFormattedText, maxlen, "\t", "");
	ReplaceString(sFormattedText, maxlen, "    ", " ");
	TrimString(sFormattedText);

	if(gB_RTLer)
	{
		RTLify(sFormattedText, maxlen, sFormattedText);
	}

	if(strlen(gS_Cached_Message[client]) > 0)
	{
		FormatVariables(client, sBuffer, 255, gS_Cached_Message[client], sFormattedText);
		strcopy(sFormattedText, 255, sBuffer);
	}

	FormatEx(buffer, maxlen, "\x01%s%s%s\x03%s%s %s  %s", gSG_Type == Game_CSGO? " ":"", (bAlive || iTeam == CS_TEAM_SPECTATOR)? "":"*DEAD* ", sTeam, sNewPrefix, sNewName, gSG_Type == Game_CSGO? ":\x01":"\x01:", sFormattedText);
}

public void FormatVariables(int client, char[] buffer, int maxlen, const char[] formattingrules, const char[] message)
{
	char[] sTempFormattingRules = new char[maxlen];
	strcopy(sTempFormattingRules, maxlen, formattingrules);

	for(int i = 0; i < sizeof(gS_GlobalColorNames); i++)
	{
		ReplaceString(sTempFormattingRules, maxlen, gS_GlobalColorNames[i], gS_GlobalColors[i]);
	}

	if(gSG_Type == Game_CSS)
	{
		ReplaceString(sTempFormattingRules, maxlen, "{RGB}", "\x07");
		ReplaceString(sTempFormattingRules, maxlen, "{RGBA}", "\x08");
	}

	else
	{
		for(int i = 0; i < sizeof(gS_CSGOColorNames); i++)
		{
			ReplaceString(sTempFormattingRules, maxlen, gS_CSGOColorNames[i], gS_CSGOColors[i]);
		}
	}

	char[] sName = new char[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);
	ReplaceString(sTempFormattingRules, maxlen, "{name}", sName);

	char[] sClanTag = new char[32];
	CS_GetClientClanTag(client, sClanTag, 32);
	int iLen = strlen(sClanTag);
	sClanTag[iLen] = (iLen > 0)? ' ':'\0';
	ReplaceString(sTempFormattingRules, maxlen, "{clan}", sClanTag);

	ReplaceString(sTempFormattingRules, maxlen, "{message}", message);

	strcopy(buffer, maxlen, sTempFormattingRules);
}

public void ChatMessage(int from, int[] clients, int count, const char[] sMessage)
{
    Handle hSayText2 = StartMessage("SayText2", clients, count);

    if(hSayText2 != null)
    {
        if(gSG_Type == Game_CSGO)
        {
            PbSetInt(hSayText2, "ent_idx", from);
            PbSetBool(hSayText2, "chat", true);
            PbSetString(hSayText2, "msg_name", sMessage);

            for(int i = 1; i <= 4; i++)
            {
                PbAddString(hSayText2, "params", "");
            }
        }

        else
        {
            BfWriteByte(hSayText2, from);
            BfWriteByte(hSayText2, true);
            BfWriteString(hSayText2, sMessage);
        }

        EndMessage();
    }
}

public int Native_FormatChat(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	if(!IsValidClient(client))
	{
		ThrowNativeError(200, "Invalid client index %d", client);

		return -1;
	}

	char[] sMessage = new char[255];
	GetNativeString(2, sMessage, 255);

	char[] sBuffer = new char[300];
	FormatChat(client, sMessage, IsPlayerAlive(client), GetClientTeam(client), view_as<bool>(GetNativeCell(3)), sBuffer, 300);

	int maxlength = GetNativeCell(5);

	return SetNativeString(6, sBuffer, maxlength);
}
