/*
 * shavit's Timer - Replay Bot
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

// I have no idea if this plugin will work with CS:S, sorry.

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <shavit>

#pragma semicolon 1
#pragma dynamic 131072 // let's make stuff faster
#pragma newdecls required // We're at 2015 :D

int gI_ReplayTick[MAX_STYLES];
int gI_ReplayBotClient[MAX_STYLES];
ArrayList gA_Frames[MAX_STYLES] =  {null, ...};
char gS_BotName[MAX_STYLES][MAX_NAME_LENGTH];
float gF_StartTick[MAX_STYLES];

int gI_PlayerFrames[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];

float gF_Tickrate;

bool gB_Record[MAXPLAYERS+1];

char gS_Map[128];

ConVar bot_quota = null;

public Plugin myinfo = 
{
	name = "[shavit] Replay Bot",
	author = "shavit, ofir",
	description = "A replay bot for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "http://forums.alliedmods.net/member.php?u=163134"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetReplayBotFirstFrame", Native_GetReplayBotFirstFrame);
	CreateNative("Shavit_GetReplayBotIndex", Native_GetReplayBotIndex);
	
	MarkNativeAsOptional("Shavit_GetReplayBotFirstFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotIndex");
	
	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-replay");

	return APLRes_Success;
}

public void OnPluginStart()
{
	bot_quota = FindConVar("bot_quota");
	
	CreateTimer(1.0, BotCheck, INVALID_HANDLE, TIMER_REPEAT);
	
	for(int i = 1; i <= MaxClients; i++)
	{
		OnClientPutInServer(i);
	}
	
	gF_Tickrate = (1.0 / GetTickInterval());
	
	// insert delete replay command here
}

public int Native_GetReplayBotFirstFrame(Handle handler, int numParams)
{
	BhopStyle style = GetNativeCell(1);
	
	SetNativeCellRef(2, gF_StartTick[style]);
}

public int Native_GetReplayBotIndex(Handle handler, int numParams)
{
	BhopStyle style = GetNativeCell(1);
	
	return gI_ReplayBotClient[style];
}

public Action BotCheck(Handle Timer)
{
	if(bot_quota.IntValue != MAX_STYLES)
	{
		bot_quota.SetInt(MAX_STYLES);
	}
	
	// resets bot
	if(gI_ReplayBotClient[Style_Forwards] == gI_ReplayBotClient[Style_Sideways])
	{
		gI_ReplayBotClient[Style_Forwards] = 0;
		gI_ReplayBotClient[Style_Sideways] = 0;
	}
	
	for(int i = 0; i < MAX_STYLES; i++)
	{
		if(gI_ReplayBotClient[i] == 0 || !IsValidClient(gI_ReplayBotClient[i]))
		{
			for(int j = 1; j <= MaxClients; j++)
			{
				if(!IsClientConnected(j) || !IsFakeClient(j) || view_as<bool>(j) == view_as<bool>(!gI_ReplayBotClient[i]))
				{
					continue;
				}
				
				gI_ReplayBotClient[i] = j;
			}
		}
		
		if(!IsValidClient(gI_ReplayBotClient[i]))
		{
			continue;
		}
		
		if(!IsPlayerAlive(gI_ReplayBotClient[i]))
		{
			CS_RespawnPlayer(gI_ReplayBotClient[i]);
		}
		
		if(GetPlayerWeaponSlot(gI_ReplayBotClient[i], CS_SLOT_KNIFE) == -1)
		{
			GivePlayerItem(gI_ReplayBotClient[i], "weapon_knife");
		}
		
		CS_SetClientContributionScore(gI_ReplayBotClient[i], 2000);
		
		char sStyle[16];
		FormatEx(sStyle, 16, "%s REPLAY", i == view_as<int>(Style_Forwards)? "NM":"SW");
		
		CS_SetClientClanTag(gI_ReplayBotClient[i], sStyle);
		
		char sName[MAX_NAME_LENGTH];
		GetClientName(gI_ReplayBotClient[i], sName, MAX_NAME_LENGTH);
		
		float fWRTime;
		Shavit_GetWRTime(view_as<BhopStyle>(i), fWRTime);
		
		if(gA_Frames[i] == null || fWRTime == 0.0)
		{
			FormatEx(sName, MAX_NAME_LENGTH, "%s unloaded", i == view_as<int>(Style_Forwards)? "NM":"SW");
			SetClientName(gI_ReplayBotClient[i], sName);
		}
		
		else if(!StrEqual(gS_BotName[i], sName))
		{
			SetClientName(gI_ReplayBotClient[i], gS_BotName[i]);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrContains(classname, "trigger_") != -1 || StrContains(classname, "_door") != -1)
	{
		SDKHook(entity, SDKHook_StartTouch, HookTriggers);
		SDKHook(entity, SDKHook_EndTouch, HookTriggers);
		SDKHook(entity, SDKHook_Touch, HookTriggers);
	}
}

public Action HookTriggers(int entity, int other)
{
	if(IsValidClient(other) && IsFakeClient(other))
	{
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public void OnMapStart()
{
	GetCurrentMap(gS_Map, 128);
	RemoveMapPath(gS_Map, gS_Map, 128);
	
	char sTempMap[140];
	FormatEx(sTempMap, 140, "maps/%s.nav", gS_Map);
	
	if(!FileExists(sTempMap))
	{
		File_Copy("maps/base.nav", sTempMap);
		
		ForceChangeLevel(gS_Map, ".nav file generate");
		
		return;
	}
	
	/*ConVar bot_zombie = FindConVar("bot_zombie");
	
	// idk if it exists in CS:S, safety check ;p
	if(bot_zombie != null)
	{
		bot_zombie.Flags = FCVAR_GAMEDLL|FCVAR_REPLICATED;
		bot_zombie.SetBool(true);
	}*/
	
	ConVar bot_stop = FindConVar("bot_stop");
	bot_stop.SetBool(true);
	
	if(Shavit_GetGameType() == Game_CSGO)
	{
		// I have literally no idea why the fuck does this return invalid handle.
		// FindConVar("bot_controllable").SetBool(false);
		
		ConVar bot_controllable = FindConVar("bot_controllable");
		bot_controllable.SetBool(false);
		
		delete bot_controllable;
	}
	
	ConVar bot_quota_mode = FindConVar("bot_quota_mode");
	bot_quota_mode.SetString("normal");
	
	ConVar mp_autoteambalance = FindConVar("mp_autoteambalance");
	mp_autoteambalance.SetBool(false);
	
	ConVar mp_limitteams = FindConVar("mp_limitteams");
	mp_limitteams.SetInt(0);
	
	ServerCommand("bot_kick");
	
	for(int i = 1; i <= MAX_STYLES; i++)
	{
		ServerCommand("bot_add");
	}
	
	ConVar bot_join_after_player = FindConVar("bot_join_after_player");
	bot_join_after_player.SetBool(false);
	
	ConVar bot_chatter = FindConVar("bot_chatter");
	bot_chatter.SetString("off");
	
	ConVar bot_auto_vacate = FindConVar("bot_auto_vacate");
	bot_auto_vacate.SetBool(false);
	
	/*ConVar mp_ignore_round_win_conditions = FindConVar("mp_ignore_round_win_conditions");
	mp_ignore_round_win_conditions.SetBool(true);*/
	
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot");
	
	if(!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}
	
	for(int i = 0; i < MAX_STYLES; i++)
	{
		gI_ReplayTick[i] = 0;
		gA_Frames[i] = new ArrayList(5);
		
		BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d", i);
		
		if(!DirExists(sPath))
		{
			CreateDirectory(sPath, 511);
		}
		
		if(!LoadReplay(view_as<BhopStyle>(i)))
		{
			FormatEx(gS_BotName[i], MAX_NAME_LENGTH, "%s unloaded", i == view_as<int>(Style_Forwards)? "NM":"SW");
		}
	}
}

public bool LoadReplay(BhopStyle style)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(FileExists(sPath))
	{
		Handle hFile = OpenFile(sPath, "r");
		
		ReadFileLine(hFile, gS_BotName[style], MAX_NAME_LENGTH);
		
		char sLine[320];
		char sExplodedLine[5][64];
		
		ReadFileLine(hFile, sLine, 320);
		
		int iSize = 0;
		
		while(!IsEndOfFile(hFile))
		{
			ReadFileLine(hFile, sLine, 320);
			ExplodeString(sLine, "|", sExplodedLine, 5, 64);
			
			gA_Frames[style].Resize(++iSize);
			
			SetArrayCell(gA_Frames[style], iSize - 1, StringToFloat(sExplodedLine[0]), 0);
			SetArrayCell(gA_Frames[style], iSize - 1, StringToFloat(sExplodedLine[1]), 1);
			SetArrayCell(gA_Frames[style], iSize - 1, StringToFloat(sExplodedLine[2]), 2);
			
			SetArrayCell(gA_Frames[style], iSize - 1, StringToFloat(sExplodedLine[3]), 3);
			SetArrayCell(gA_Frames[style], iSize - 1, StringToFloat(sExplodedLine[4]), 4);
		}
		
		delete hFile;
		
		return true;
	}
	
	return false;
}

public void SaveReplay(BhopStyle style)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);
	
	if(DirExists(sPath))
	{
		DeleteFile(sPath);
	}
	
	Handle hFile = OpenFile(sPath, "w");
	WriteFileLine(hFile, gS_BotName[style]);
	
	int iSize = gA_Frames[style].Length;
	
	char sBuffer[320];
	
	for(int i = 0; i < iSize; i++)
	{
		FormatEx(sBuffer, 320, "%f|%f|%f|%f|%f", GetArrayCell(gA_Frames[style], i, 0), GetArrayCell(gA_Frames[style], i, 1), GetArrayCell(gA_Frames[style], i, 2), GetArrayCell(gA_Frames[style], i, 3), GetArrayCell(gA_Frames[style], i, 4));
		
		WriteFileLine(hFile, sBuffer);
	}
}

public void OnClientPutInServer(int client)
{
	if(!IsClientConnected(client))
	{
		return;
	}
	
	if(IsFakeClient(client))
	{
		if(gI_ReplayBotClient[Style_Forwards] == 0)
		{
			gI_ReplayBotClient[Style_Forwards] = client;
			
			// strcopy(gS_BotName[Style_Sideways], MAX_NAME_LENGTH, "NM unloaded");
		}
		
		else if(gI_ReplayBotClient[Style_Sideways] == 0)
		{
			gI_ReplayBotClient[Style_Sideways] = client;
			
			// strcopy(gS_BotName[Style_Sideways], MAX_NAME_LENGTH, "SW unloaded");
		}
	}
	
	else
	{
		gA_PlayerFrames[client] = new ArrayList(5);
	}
}

public void OnClientDisconnect(int client)
{
	if(client == gI_ReplayBotClient[Style_Forwards])
	{
		gI_ReplayBotClient[Style_Forwards] = 0;
	}
	
	else if(client == gI_ReplayBotClient[Style_Sideways])
	{
		gI_ReplayBotClient[Style_Sideways] = 0;
	}
}

public void Shavit_OnStart(int client)
{
	if(!IsFakeClient(client))
	{
		gA_PlayerFrames[client].Clear();
		
		gI_PlayerFrames[client] = 0;
		
		gB_Record[client] = true;
	}
}

public void Shavit_OnFinish(int client, BhopStyle style, float time, int jumps)
{
	gB_Record[client] = false;
}

public void Shavit_OnWorldRecord(int client, BhopStyle style, float time, int jumps)
{
	gA_Frames[style] = gA_PlayerFrames[client].Clone();
	
	gI_ReplayTick[style] = 0;
	
	char sWRTime[16];
	FormatSeconds(time, sWRTime, 16);
	
	FormatEx(gS_BotName[style], MAX_NAME_LENGTH, "%s - %N", sWRTime, client);
	
	if(gI_ReplayBotClient[style] != 0)
	{
		SetClientName(gI_ReplayBotClient[style], gS_BotName[style]);
	}
	
	gA_PlayerFrames[client].Clear();
	
	SaveReplay(style);
}

public void Shavit_OnPause(int client)
{
	gB_Record[client] = false;
}

public void Shavit_OnResume(int client)
{
	gB_Record[client] = true;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
	float vecPosition[3];
	GetClientAbsOrigin(client, vecPosition);
	
	if(client == gI_ReplayBotClient[Style_Forwards] || client == gI_ReplayBotClient[Style_Sideways])
	{
		SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
		
		BhopStyle style = (client == gI_ReplayBotClient[Style_Forwards]? Style_Forwards:Style_Sideways);
		
		if(gA_Frames[style] == null) // if no replay is loaded
		{
			return Plugin_Continue;
		}
		
		float fWRTime;
		Shavit_GetWRTime(style, fWRTime);
		
		if(fWRTime != 0.0 && gI_ReplayTick[style] != -1)
		{
			if(gI_ReplayTick[style] >= gA_Frames[style].Length - 10)
			{
				gI_ReplayTick[style] = -1;
				
				CreateTimer(1.5, ResetReplay, style, TIMER_FLAG_NO_MAPCHANGE);
				
				return Plugin_Continue;
			}
			
			if(gI_ReplayTick[style] == 1)
			{
				gF_StartTick[style] = GetEngineTime();
			}
			
			gI_ReplayTick[style]++;
			
			float vecCurrentPosition[3];
			vecCurrentPosition[0] = GetArrayCell(gA_Frames[style], gI_ReplayTick[style] - 1, 0);
			vecCurrentPosition[1] = GetArrayCell(gA_Frames[style], gI_ReplayTick[style] - 1, 1);
			vecCurrentPosition[2] = GetArrayCell(gA_Frames[style], gI_ReplayTick[style] - 1, 2);
			
			float vecAngles[3];
			vecAngles[0] = GetArrayCell(gA_Frames[style], gI_ReplayTick[style] - 1, 3);
			vecAngles[1] = GetArrayCell(gA_Frames[style], gI_ReplayTick[style] - 1, 4);
			
			float vecVelocity[3];
			
			float fDistance = 0.0;
			
			if(gA_Frames[style].Length >= gI_ReplayTick[style] + 1)
			{
				float vecNextPosition[3];
				vecNextPosition[0] = GetArrayCell(gA_Frames[style], gI_ReplayTick[style], 0);
				vecNextPosition[1] = GetArrayCell(gA_Frames[style], gI_ReplayTick[style], 1);
				vecNextPosition[2] = GetArrayCell(gA_Frames[style], gI_ReplayTick[style], 2);
				
				fDistance = GetVectorDistance(vecPosition, vecNextPosition);
				
				MakeVectorFromPoints(vecCurrentPosition, vecNextPosition, vecVelocity);
				
				ScaleVector(vecVelocity, gF_Tickrate);
			}
			
			if(fDistance >= 25.0)
			{
				TeleportEntity(client, vecCurrentPosition, vecAngles, vecVelocity);
			}
			
			else
			{
				TeleportEntity(client, NULL_VECTOR, vecAngles, vecVelocity);
			}
		}
	}
	
	else
	{
		if(gB_Record[client] && !Shavit_InsideZone(client, Zone_Start))
		{
			gI_PlayerFrames[client]++;
			gA_PlayerFrames[client].Resize(gI_PlayerFrames[client]);
			
			SetArrayCell(gA_PlayerFrames[client], gI_PlayerFrames[client] - 1, vecPosition[0], 0);
			SetArrayCell(gA_PlayerFrames[client], gI_PlayerFrames[client] - 1, vecPosition[1], 1);
			SetArrayCell(gA_PlayerFrames[client], gI_PlayerFrames[client] - 1, vecPosition[2], 2);
			
			SetArrayCell(gA_PlayerFrames[client], gI_PlayerFrames[client] - 1, angles[0], 3);
			SetArrayCell(gA_PlayerFrames[client], gI_PlayerFrames[client] - 1, angles[1], 4);
		}
	}
	
	return Plugin_Continue;
}

public Action ResetReplay(Handle Timer, any data)
{
	gI_ReplayTick[data] = 0;
}

// https://forums.alliedmods.net/showthread.php?p=2307350
/**
 * Copy a substring from source to destination
 * 
 * @param source		String to copy from
 * @param start			position to start at, 0 numbered. Negative means to start that many characters from the end.
 * @param len			number of characters to copy.  Negative means to not copy that many characters from the end.
 * @param destination	String to copy to
 * @param maxlen		Length of destination string.  Must be 1 or greater.
 * 
 * @return				True on success, false if number of characters copied would be negative.
 * NOTE:				There is no mechanism to get the remaining characters of a string.
 * 						Instead, use strcopy with source[start] for that.
 */
stock bool SubString(const char[] source, int start, int len, char[] destination, int maxlen)
{
	if(maxlen < 1)
	{
		ThrowError("Destination size must be 1 or greater, but was %d", maxlen);
	}
	
	if(len == 0)
	{
		destination[0] = '\0';
		
		return true;
	}
	
	if(start < 0)
	{
		start = strlen(source) + start;
		
		if(start < 0)
		{
			start = 0;
		}
	}
	
	if(len < 0)
	{
		len = strlen(source) + len - start;
		
		if(len < 0)
		{
			return false;
		}
	}
	
	int realLength = len + 1 < maxlen? len + 1:maxlen;
	
	strcopy(destination, realLength, source[start]);
	
	return true;
}

/**
 * Remove the path from the map name
 * This was intended to remove workshop paths.
 * Used internally by MapEqual and FindMapStringInArray.
 * 
 * @param map			Map name
 * @param destination	String to copy map name to
 * @param maxlen		Length of destination string
 * 
 * @return				True if path was removed, false if map and destination are the same
 */
stock bool RemoveMapPath(const char[] map, char[] destination, int maxlen)
{
	if(strlen(map) < 1)
	{
		ThrowError("Bad map name: %s", map);
	}
	
	int pos = FindCharInString(map, '/', true);
	
	if(pos == -1)
	{
		pos = FindCharInString(map, '\\', true);
		
		if(pos == -1)
		{
			strcopy(destination, maxlen, map);
			return false;
		}
	}

	int len = strlen(map) - 1 - pos;
	
	SubString(map, pos + 1, len, destination, maxlen);
	
	return true;
}

/*
 * Copies file source to destination
 * Based on code of javalia:
 * http://forums.alliedmods.net/showthread.php?t=159895
 *
 * @param source		Input file
 * @param destination	Output file
 */
stock bool File_Copy(const char[] source, const char[] destination)
{
	Handle file_source = OpenFile(source, "rb");

	if(file_source == null)
	{
		return false;
	}

	Handle file_destination = OpenFile(destination, "wb");

	if(file_destination == null)
	{
		delete file_source;
		
		return false;
	}

	int buffer[32];
	int cache;

	while(!IsEndOfFile(file_source))
	{
		cache = ReadFile(file_source, buffer, 32, 1);
		
		WriteFile(file_destination, buffer, cache, 1);
	}

	delete file_source;
	delete file_destination;

	return true;
}
