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
StringMap gSM_Custom_Prefix = null;
StringMap gSM_Custom_Name = null;
StringMap gSM_Custom_Message = null;

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
	for(int i = 1; i <= MaxClients; i++)
    {
		OnClientPutInServer(i); // late loading
	}

	RegAdminCmd("sm_reloadchat", Command_ReloadChat, ADMFLAG_ROOT, "Reload chat config.");
}

public void OnMapStart()
{
    LoadConfig();
}

public void OnClientPutInServer(int client)
{
    gF_LastMessage[client] = GetEngineTime();
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

public void LoadConfig()
{
	delete gSM_Custom_Prefix;
	delete gSM_Custom_Name;
	delete gSM_Custom_Message;

	gSM_Custom_Prefix = new StringMap();
	gSM_Custom_Name = new StringMap();
	gSM_Custom_Message = new StringMap();

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

			if(StrContains(sBuffer[0], "[U:") != -1)
			{
				char[] sProperty = new char[255];
				kvConfig.GetString("prefix", sProperty, 255);

				if(strlen(sProperty) > 0)
				{
					gSM_Custom_Prefix.SetString(sBuffer, sProperty);
				}

				kvConfig.GetString("name", sProperty, 255);

				if(strlen(sProperty) > 0)
				{
					gSM_Custom_Name.SetString(sBuffer, sProperty);
				}

				kvConfig.GetString("message", sProperty, 255);

				if(strlen(sProperty) > 0)
				{
					gSM_Custom_Message.SetString(sBuffer, sProperty);
				}
			}
		}

		while(kvConfig.GotoNextKey());
	}

	else
	{
		LogError("File %s might be empty?", sFile);
	}

	delete kvConfig;
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

	gF_LastMessage[client] = GetEngineTime();

	bool bTeam = StrEqual(command, "say_team");
	int iTeam = GetClientTeam(client);

	char[] sMessage = new char[300];
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

	if(gSM_Custom_Prefix.GetString(sAuthID, sBuffer, 255))
	{
		FormatVariables(client, sBuffer, 255, sMessage);
		strcopy(sNewPrefix, 32, sBuffer);
	}

	char[] sNewName = new char[MAX_NAME_LENGTH*2];

	if(gSM_Custom_Name.GetString(sAuthID, sBuffer, 255))
	{
		FormatVariables(client, sBuffer, 255, sMessage);
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
	TrimString(sFormattedText);

	if(gB_RTLer)
	{
		RTLify(sFormattedText, maxlen, sFormattedText);
	}

	if(gSM_Custom_Message.GetString(sAuthID, sBuffer, 255))
	{
		FormatVariables(client, sBuffer, 255, sFormattedText);
		strcopy(sFormattedText, 255, sBuffer);
	}

	// assign rank stuff if theres the need
	// int iRank = Shavit_GetRank(client);

	FormatEx(buffer, maxlen, "%s%s%s%s%s%s %s  %s", gSG_Type == Game_CSGO? " ":"", strlen(sNewPrefix) == 0? "\x03":"", (bAlive || iTeam == CS_TEAM_SPECTATOR)? "":"*DEAD* ", sTeam, sNewPrefix, sNewName, gSG_Type == Game_CSGO? ":\x01":"\x01:", sFormattedText);
}

public void FormatVariables(int client, char[] buffer, int maxlen, const char[] message)
{
	char[] sName = new char[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);
	ReplaceString(buffer, maxlen, "{name}", sName);

	char[] sClanTag = new char[32];
	CS_GetClientClanTag(client, sClanTag, 32);
	int iLen = strlen(sClanTag);
	sClanTag[iLen] = iLen > 0? ' ':'\0'; // add spacing after the clan tag if there is one
	ReplaceString(buffer, maxlen, "{clan}", sClanTag);

	ReplaceString(buffer, maxlen, "{message}", message);

	for(int i = 0; i < sizeof(gS_GlobalColorNames); i++)
	{
		ReplaceString(buffer, maxlen, gS_GlobalColorNames[i], gS_GlobalColors[i]);
	}

	if(gSG_Type == Game_CSS)
	{
		ReplaceString(buffer, maxlen, "{RGB}", "\x07");
		ReplaceString(buffer, maxlen, "{RGBA}", "\x08");
	}

	else
	{
		for(int i = 0; i < sizeof(gS_CSGOColorNames); i++)
		{
			ReplaceString(buffer, maxlen, gS_CSGOColorNames[i], gS_CSGOColors[i]);
		}
	}
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
