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
#include <shavit>

#undef REQUIRE_PLUGIN
#include <basecomm>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

// cache
float gF_LastMessage[MAXPLAYERS+1];

// modules
bool gB_BaseComm = false;

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
    MarkNativeAsOptional("BaseComm_IsClientGagged");
}

public void OnPluginStart()
{
    for(int i = 1; i <= MaxClients; i++)
    {
        OnClientPutInServer(i); // late loading
    }
}

public void OnClientPutInServer(int client)
{
    gF_LastMessage[client] = GetEngineTime();
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if(gB_BaseComm && BaseComm_IsClientGagged(client))
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
            strcopy(sTeam, 32, "*SPEC*");
        }
    }

    else
    {
        switch(iTeam)
        {
            case CS_TEAM_SPECTATOR:
            {
                strcopy(sTeam, 32, "(Spectator)");
            }

            case CS_TEAM_T:
            {
                strcopy(sTeam, 32, "(Terrorist)");
            }

            case CS_TEAM_CT:
            {
                strcopy(sTeam, 32, "(Counter-Terrorist)");
            }
        }
    }

    FormatEx(buffer, maxlen, " \x03%s%s %N :\x01  %s", Shavit_GetRank(client), (bAlive || iTeam == CS_TEAM_SPECTATOR)? "":"*DEAD*", sTeam, client, sMessage);
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
