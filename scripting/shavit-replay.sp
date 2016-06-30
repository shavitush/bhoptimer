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

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

#define USES_SHORT_STYLE_NAMES
#define USES_STYLE_PROPERTIES
#include <shavit>

ServerGame gSG_Type = Game_Unknown;

int gI_ReplayTick[MAX_STYLES];
int gI_ReplayBotClient[MAX_STYLES];
ArrayList gA_Frames[MAX_STYLES] = {null, ...};
char gS_BotName[MAX_STYLES][MAX_NAME_LENGTH];
float gF_StartTick[MAX_STYLES];

int gI_PlayerFrames[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];

float gF_Tickrate;

bool gB_Record[MAXPLAYERS+1];

char gS_Map[256];

ConVar bot_quota = null;

int gI_ExpectedBots = 0;

// Plugin ConVars
ConVar gCV_ReplayDelay = null;

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
	CreateNative("Shavit_GetReplayBotCurrentFrame", Native_GetReplayBotIndex);

	MarkNativeAsOptional("Shavit_GetReplayBotFirstFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotIndex");
	MarkNativeAsOptional("Shavit_GetReplayBotCurrentFrame");

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-replay");

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	gSG_Type = Shavit_GetGameType();
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

	// plugin convars
	gCV_ReplayDelay = CreateConVar("shavit_replay_delay", "1.5", "Time to wait before restarting the replay after it finishes playing.", 0, true, 0.0, true, 10.0);

	AutoExecConfig();

	// insert delete replay command here
}

public int Native_GetReplayBotFirstFrame(Handle handler, int numParams)
{
	SetNativeCellRef(2, gF_StartTick[GetNativeCell(1)]);
}

public int Native_GetReplayBotIndex(Handle handler, int numParams)
{
	return gI_ReplayBotClient[GetNativeCell(1)];
}

public int Native_GetReplayBotCurrentFrame(Handle handler, int numParams)
{
	return gI_ReplayTick[GetNativeCell(1)];
}

public Action BotCheck(Handle Timer)
{
	if(bot_quota.IntValue != gI_ExpectedBots)
	{
		bot_quota.SetInt(gI_ExpectedBots);
	}

	// resets a bot's client index if there are two on the same one.
	for(int a = 0; a < MAX_STYLES; a++)
	{
		for(int b = 0; b < MAX_STYLES; b++)
		{
			if(gI_ReplayBotClient[a] == gI_ReplayBotClient[b])
			{
				gI_ReplayBotClient[a] = 0;
				gI_ReplayBotClient[b] = 0;
			}
		}
	}

	for(int i = 0; i < MAX_STYLES; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		if(!IsValidClient(gI_ReplayBotClient[i]))
		{
			for(int j = 1; j <= MaxClients; j++)
			{
				if(!IsClientConnected(j) || !IsFakeClient(j))
				{
					continue;
				}

				bool bContinue = false;

				for(int x = 0; x < MAX_STYLES; x++)
				{
					if(j == gI_ReplayBotClient[x])
					{
						bContinue = true;

						break;
					}
				}

				if(bContinue)
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

		if(gSG_Type == Game_CSGO)
		{
			CS_SetClientContributionScore(gI_ReplayBotClient[i], 2000);
		}

		char[] sStyle = new char[16];
		FormatEx(sStyle, 16, "%s REPLAY", gS_ShortBhopStyles[i]);

		CS_SetClientClanTag(gI_ReplayBotClient[i], sStyle);

		char[] sName = new char[MAX_NAME_LENGTH];
		GetClientName(gI_ReplayBotClient[i], sName, MAX_NAME_LENGTH);

		float fWRTime;
		Shavit_GetWRTime(view_as<BhopStyle>(i), fWRTime);

		if(gA_Frames[i] == null || fWRTime == 0.0)
		{
			char[] sCurrentName = new char[MAX_NAME_LENGTH];
			strcopy(sCurrentName, MAX_NAME_LENGTH, sName);

			FormatEx(sName, MAX_NAME_LENGTH, "%s unloaded", gS_ShortBhopStyles[i]);

			if(!StrEqual(sName, sCurrentName))
			{
				SetClientName(gI_ReplayBotClient[i], sName);
			}
		}

		else if(!StrEqual(gS_BotName[i], sName))
		{
			SetClientName(gI_ReplayBotClient[i], gS_BotName[i]);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// trigger_once | trigger_multiple.. etc
	// func_door | func_door_rotating
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
	GetCurrentMap(gS_Map, 256);
	GetMapDisplayName(gS_Map, gS_Map, 256);

	char[] sTempMap = new char[PLATFORM_MAX_PATH];
	FormatEx(sTempMap, PLATFORM_MAX_PATH, "maps/%s.nav", gS_Map);

	if(!FileExists(sTempMap))
	{
		if(!FileExists("maps/base.nav"))
		{
			SetFailState("Plugin startup FAILED: \"maps/base.nav\" does not exist.");

			return;
		}

		File_Copy("maps/base.nav", sTempMap);

		ForceChangeLevel(gS_Map, ".nav file generate");

		return;
	}

	ConVar bot_stop = FindConVar("bot_stop");
	bot_stop.SetBool(true);

	ConVar bot_controllable = FindConVar("bot_controllable");

	if(bot_controllable != null)
	{
		bot_controllable.SetBool(false);
	}

	ConVar bot_quota_mode = FindConVar("bot_quota_mode");
	bot_quota_mode.SetString("normal");

	ConVar mp_autoteambalance = FindConVar("mp_autoteambalance");
	mp_autoteambalance.SetBool(false);

	ConVar mp_limitteams = FindConVar("mp_limitteams");
	mp_limitteams.SetInt(0);

	ServerCommand("bot_kick");

	gI_ExpectedBots = 0;

	for(int i = 0; i < MAX_STYLES; i++)
	{
		if(ReplayEnabled(i))
		{
			// ServerCommand("bot_add");

			gI_ExpectedBots++;
		}
	}

	ConVar bot_join_after_player = FindConVar("bot_join_after_player");
	bot_join_after_player.SetBool(false);

	ConVar bot_chatter = FindConVar("bot_chatter");
	bot_chatter.SetString("off");

	ConVar bot_auto_vacate = FindConVar("bot_auto_vacate");
	bot_auto_vacate.SetBool(false);

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot");

	if(!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}

	for(int i = 0; i < MAX_STYLES; i++)
	{
		if(!ReplayEnabled(i))
		{
			continue;
		}

		gI_ReplayTick[i] = 0;
		gA_Frames[i] = new ArrayList(5);

		BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d", i);

		if(!DirExists(sPath))
		{
			CreateDirectory(sPath, 511);
		}

		if(!LoadReplay(view_as<BhopStyle>(i)))
		{
			FormatEx(gS_BotName[i], MAX_NAME_LENGTH, "%s unloaded", gS_ShortBhopStyles[i]);
		}
	}
}

public bool LoadReplay(BhopStyle style)
{
	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(FileExists(sPath))
	{
		File fFile = OpenFile(sPath, "r");

		fFile.ReadLine(gS_BotName[style], MAX_NAME_LENGTH);
		TrimString(gS_BotName[style]);

		char[] sLine = new char[320];
		char[][] sExplodedLine = new char[5][64];

		fFile.ReadLine(sLine, 320);

		int iSize = 0;

		while(!fFile.EndOfFile())
		{
			fFile.ReadLine(sLine, 320);
			ExplodeString(sLine, "|", sExplodedLine, 5, 64);

			gA_Frames[style].Resize(++iSize);

			gA_Frames[style].Set(iSize - 1, StringToFloat(sExplodedLine[0]), 0);
			gA_Frames[style].Set(iSize - 1, StringToFloat(sExplodedLine[1]), 1);
			gA_Frames[style].Set(iSize - 1, StringToFloat(sExplodedLine[2]), 2);

			gA_Frames[style].Set(iSize - 1, StringToFloat(sExplodedLine[3]), 3);
			gA_Frames[style].Set(iSize - 1, StringToFloat(sExplodedLine[4]), 4);
		}

		delete fFile;

		return true;
	}

	return false;
}

public void SaveReplay(BhopStyle style)
{
	if(!ReplayEnabled(style))
	{
		return;
	}

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(DirExists(sPath))
	{
		DeleteFile(sPath);
	}

	File fFile = OpenFile(sPath, "w");
	fFile.WriteLine(gS_BotName[style]);

	int iSize = gA_Frames[style].Length;

	char[] sBuffer = new char[320];

	for(int i = 0; i < iSize; i++)
	{
		FormatEx(sBuffer, 320, "%f|%f|%f|%f|%f", gA_Frames[style].Get(i, 0), gA_Frames[style].Get(i, 1), gA_Frames[style].Get(i, 2), gA_Frames[style].Get(i, 3), gA_Frames[style].Get(i, 4));

		fFile.WriteLine(sBuffer);
	}
}

public void OnClientPutInServer(int client)
{
	if(!IsClientConnected(client))
	{
		return;
	}

	gA_PlayerFrames[client] = new ArrayList(5);
}

public void OnClientDisconnect(int client)
{
	for(int i = 0; i < MAX_STYLES; i++)
	{
		if(client == gI_ReplayBotClient[i])
		{
			gI_ReplayBotClient[i] = 0;
		}
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
	if(!ReplayEnabled(style))
	{
		return;
	}

	gA_Frames[style] = gA_PlayerFrames[client].Clone();
	gI_ReplayTick[style] = 0;

	char[] sWRTime = new char[16];
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

	int iReplayBotStyle = -1;

	for(int i = 0; i < MAX_STYLES; i++)
	{
		if(client == gI_ReplayBotClient[i])
		{
			iReplayBotStyle = i;

			break;
		}
	}

	if(iReplayBotStyle != -1 && ReplayEnabled(iReplayBotStyle))
	{
		SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);

		if(gA_Frames[iReplayBotStyle] == null) // if no replay is loaded
		{
			return Plugin_Continue;
		}

		float fWRTime;
		Shavit_GetWRTime(view_as<BhopStyle>(iReplayBotStyle), fWRTime);

		if(fWRTime != 0.0 && gI_ReplayTick[iReplayBotStyle] != -1)
		{
			if(gI_ReplayTick[iReplayBotStyle] >= gA_Frames[iReplayBotStyle].Length - 10)
			{
				gI_ReplayTick[iReplayBotStyle] = -1;

				CreateTimer(gCV_ReplayDelay.FloatValue, ResetReplay, iReplayBotStyle, TIMER_FLAG_NO_MAPCHANGE);

				return Plugin_Continue;
			}

			if(gI_ReplayTick[iReplayBotStyle] < 10)
			{
				gF_StartTick[iReplayBotStyle] = GetEngineTime();
			}

			gI_ReplayTick[iReplayBotStyle]++;

			float vecCurrentPosition[3];
			vecCurrentPosition[0] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle] - 1, 0);
			vecCurrentPosition[1] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle] - 1, 1);
			vecCurrentPosition[2] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle] - 1, 2);

			float vecAngles[3];
			vecAngles[0] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle] - 1, 3);
			vecAngles[1] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle] - 1, 4);

			float vecVelocity[3];

			float fDistance = 0.0;

			if(gA_Frames[iReplayBotStyle].Length >= gI_ReplayTick[iReplayBotStyle] + 1)
			{
				float vecNextPosition[3];
				vecNextPosition[0] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 0);
				vecNextPosition[1] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 1);
				vecNextPosition[2] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 2);

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

	else if(gB_Record[client] && !Shavit_InsideZone(client, Zone_Start))
	{
		gI_PlayerFrames[client]++;
		gA_PlayerFrames[client].Resize(gI_PlayerFrames[client]);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client] - 1, vecPosition[0], 0);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client] - 1, vecPosition[1], 1);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client] - 1, vecPosition[2], 2);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client] - 1, angles[0], 3);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client] - 1, angles[1], 4);
	}

	return Plugin_Continue;
}

public Action ResetReplay(Handle Timer, any data)
{
	gI_ReplayTick[data] = 0;
}

public bool ReplayEnabled(any style)
{
	if(gI_StyleProperties[style] & STYLE_UNRANKED || gI_StyleProperties[style] & STYLE_NOREPLAY)
	{
		return false;
	}

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
	File file_source = OpenFile(source, "rb");

	if(file_source == null)
	{
		return false;
	}

	File file_destination = OpenFile(destination, "wb");

	if(file_destination == null)
	{
		delete file_source;

		return false;
	}

	int[] buffer = new int[32];
	int cache = 0;

	while(!IsEndOfFile(file_source))
	{
		cache = ReadFile(file_source, buffer, 32, 1);

		WriteFile(file_destination, buffer, cache, 1);
	}

	delete file_source;
	delete file_destination;

	return true;
}
