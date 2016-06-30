/*
 * shavit's Timer - Sounds
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

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <shavit>

#define SOUNDS_LIMIT 64 // we really don't need more than that

ServerGame gSG_Type = Game_Unknown;

ArrayList gA_FirstSounds = null;
ArrayList gA_PersonalSounds = null;
ArrayList gA_WorldSounds = null;
ArrayList gA_WorseSounds = null;

public Plugin myinfo =
{
	name = "[shavit] Sounds",
	author = "shavit",
	description = "Play custom sounds when timer-related events happen.",
	version = SHAVIT_VERSION,
	url = "http://forums.alliedmods.net/member.php?u=163134"
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
    gA_FirstSounds = new ArrayList(SOUNDS_LIMIT);
    gA_PersonalSounds = new ArrayList(SOUNDS_LIMIT);
    gA_WorldSounds = new ArrayList(SOUNDS_LIMIT);
    gA_WorseSounds = new ArrayList(SOUNDS_LIMIT);

    gSG_Type = Shavit_GetGameType();
}

public void OnMapStart()
{
    gA_FirstSounds.Clear();
    gA_PersonalSounds.Clear();
    gA_WorldSounds.Clear();

    char[] sFile = new char[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-sounds.cfg");

    File fFile = OpenFile(sFile, "r"); // readonly, unless i implement in-game editing

    if(fFile == null)
    {
        SetFailState("Cannot open \"configs/shavit-sounds.cfg\". Make sure this file exists and that the server has read permissions to it.");
    }

    else
    {
        char[] sLine = new char[PLATFORM_MAX_PATH * 2];
        char[] sDownloadString = new char[PLATFORM_MAX_PATH];

        while(fFile.ReadLine(sLine, PLATFORM_MAX_PATH * 2))
        {
            TrimString(sLine);

            if(sLine[0] != '\"')
            {
                continue;
            }

            ReplaceString(sLine, PLATFORM_MAX_PATH * 2, "\"", "");

            char sExploded[2][PLATFORM_MAX_PATH];
            ExplodeString(sLine, " ", sExploded, 2, PLATFORM_MAX_PATH);

            if(StrEqual(sExploded[0], "first"))
            {
                gA_FirstSounds.PushString(sExploded[1]);
            }

            else if(StrEqual(sExploded[0], "personal"))
            {
                gA_PersonalSounds.PushString(sExploded[1]);
            }

            else if(StrEqual(sExploded[0], "world"))
            {
                gA_WorldSounds.PushString(sExploded[1]);
            }

            else if(StrEqual(sExploded[0], "worse"))
            {
                gA_WorseSounds.PushString(sExploded[1]);
            }

            else
            {
                LogError("\"%s\" is an invalid record type!", sExploded[0]);

                continue;
            }

            // thanks TotallyMehis for this workaround
            // make sure to star his amazing StandUp plugin! https://github.com/TotallyMehis/StandUp
            if(gSG_Type == Game_CSGO || PrecacheSound(sExploded[1]))
            {
                PrefetchSound(sExploded[1]);

                FormatEx(sDownloadString, PLATFORM_MAX_PATH, "sound/%s", sExploded[1]);
                AddFileToDownloadsTable(sDownloadString);
            }

            else
            {
                LogError("\"sound/%s\" could not be accessed.", sExploded[1]);
            }
        }
    }

    delete fFile;
}

public void Shavit_OnFinish(int client, BhopStyle style, float time, int jumps)
{
    float fOldTime = 0.0;
    Shavit_GetPlayerPB(client, style, fOldTime);

    float fWRTime = 0.0;
    Shavit_GetWRTime(style, fWRTime);

    char[] sSound = new char[PLATFORM_MAX_PATH];

    bool bEveryone = false;

    if(gA_WorldSounds.Length != 0 && (fWRTime == 0.0 || time < fWRTime))
    {
        bEveryone = true;

        gA_WorldSounds.GetString(GetRandomInt(0, gA_WorldSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
    }

    else if(gA_PersonalSounds.Length != 0 && time < fOldTime)
    {
        gA_PersonalSounds.GetString(GetRandomInt(0, gA_PersonalSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
    }

	else if(gA_FirstSounds.Length != 0 && fOldTime == 0.0)
	{
		gA_FirstSounds.GetString(GetRandomInt(0, gA_FirstSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
	}

	else if(gA_WorseSounds.Length != 0 && time > fOldTime)
	{
		gA_WorseSounds.GetString(GetRandomInt(0, gA_WorseSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
	}

    if(StrContains(sSound, ".") != -1) // file has an extension?
    {
        PlayEventSound(client, bEveryone, sSound);
    }
}

public void PlayEventSound(int client, bool everyone, const char[] sound)
{
	int[] clients = new int[MaxClients];
	int count;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i))
		{
			continue;
		}

		if(everyone)
		{
			clients[count++] = i;

			continue;
		}

		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		// add player and his spectators
		if(i == client || (IsClientObserver(i) && (iObserverMode >= 3 || iObserverMode <= 5) && GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == client))
		{
			clients[count++] = i;
		}
	}

	if(count > 0)
	{
		if(gSG_Type == Game_CSGO)
		{
			char[] sPlay = new char[PLATFORM_MAX_PATH+8];
			FormatEx(sPlay, PLATFORM_MAX_PATH+8, "play */%s", sound);

			for(int i = 0; i < count; i++)
			{
				ClientCommand(clients[i], sPlay);
			}
		}

		else
		{
			EmitSound(clients, count, sound);
		}
	}
}
