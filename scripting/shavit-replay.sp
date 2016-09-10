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

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <shavit>

#define REPLAY_FORMAT_V2 "{SHAVITREPLAYFORMAT}{V2}"

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

// game type
EngineVersion gEV_Type = Engine_Unknown;

// cache
int gI_ReplayTick[STYLE_LIMIT];
int gI_ReplayBotClient[STYLE_LIMIT];
ArrayList gA_Frames[STYLE_LIMIT] = {null, ...};
float gF_StartTick[STYLE_LIMIT];
ReplayStatus gRS_ReplayStatus[STYLE_LIMIT];
int gI_FrameCount[STYLE_LIMIT];

int gI_PlayerFrames[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];
bool gB_Record[MAXPLAYERS+1];

bool gB_Late = false;

// server specific
float gF_Tickrate = 0.0;
char gS_Map[256];
int gI_ExpectedBots = 0;
ConVar bot_quota = null;

// how do i call this
bool gB_HideNameChange = false;
bool gB_DontCallTimer = false;

// plugin cvars
ConVar gCV_Enabled = null;
ConVar gCV_ReplayDelay = null;
ConVar gCV_TimeLimit = null;
ConVar gCV_NameStyle = null;

// cached cvars
bool gB_Enabled = true;
float gF_ReplayDelay = 5.0;
float gF_TimeLimit = 5400.0;
int gI_NameStyle = 1;

// timer settings
int gI_Styles = 0;
char gS_StyleStrings[STYLE_LIMIT][STYLESTRINGS_SIZE][128];
any gA_StyleSettings[STYLE_LIMIT][STYLESETTINGS_SIZE];

public Plugin myinfo =
{
	name = "[shavit] Replay Bot",
	author = "shavit, ofir",
	description = "A replay bot for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetReplayBotFirstFrame", Native_GetReplayBotFirstFrame);
	CreateNative("Shavit_GetReplayBotIndex", Native_GetReplayBotIndex);
	CreateNative("Shavit_GetReplayBotCurrentFrame", Native_GetReplayBotIndex);
	CreateNative("Shavit_IsReplayDataLoaded", Native_IsReplayDataLoaded);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-replay");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// game specific
	gEV_Type = GetEngineVersion();
	gF_Tickrate = (1.0 / GetTickInterval());

	// late load
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && !IsFakeClient(i))
		{
			OnClientPutInServer(i);
		}
	}

	// plugin convars
	gCV_Enabled = CreateConVar("shavit_replay_enabled", "1", "Enable replay bot functionality?", 0, true, 0.0, true, 1.0);
	gCV_ReplayDelay = CreateConVar("shavit_replay_delay", "5.0", "Time to wait before restarting the replay after it finishes playing.", 0, true, 0.0, true, 10.0);
	gCV_TimeLimit = CreateConVar("shavit_replay_timelimit", "5400.0", "Maximum amount of time (in seconds) to allow saving to disk.\nDefault is 5400.0 (1:30 hours)\n0 - Disabled");
	gCV_NameStyle = CreateConVar("shavit_replay_namestyle", "1", "Replay bot naming style\n0 - [SHORT STYLE] <TIME> - PLAYER NAME\n1 - LONG STYLE - <TIME>", 0, true, 0.0, true, 1.0);

	gCV_Enabled.AddChangeHook(OnConVarChanged);
	gCV_ReplayDelay.AddChangeHook(OnConVarChanged);
	gCV_TimeLimit.AddChangeHook(OnConVarChanged);
	gCV_NameStyle.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	// hooks
	HookEvent("player_spawn", Player_Event, EventHookMode_Pre);
	HookEvent("player_death", Player_Event, EventHookMode_Pre);
	HookEvent("player_connect", BotEvents, EventHookMode_Pre);
	HookEvent("player_disconnect", BotEvents, EventHookMode_Pre);
	HookEventEx("player_connect_client", BotEvents, EventHookMode_Pre);

	// name change suppression
	HookUserMessage(GetUserMessageId("SayText2"), Hook_SayText2, true);

	// commands
	RegAdminCmd("sm_deletereplay", Command_DeleteReplay, ADMFLAG_RCON, "Open replay deletion menu.");
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gB_Enabled = gCV_Enabled.BoolValue;
	gF_ReplayDelay = gCV_ReplayDelay.FloatValue;
	gF_TimeLimit = gCV_TimeLimit.FloatValue;
	gI_NameStyle = gCV_NameStyle.IntValue;
}

public int Native_GetReplayBotFirstFrame(Handle handler, int numParams)
{
	SetNativeCellRef(2, gF_StartTick[GetNativeCell(1)]);
}

public int Native_GetReplayBotCurrentFrame(Handle handler, int numParams)
{
	return gI_ReplayTick[GetNativeCell(1)];
}

public int Native_GetReplayBotIndex(Handle handler, int numParams)
{
	return gI_ReplayBotClient[GetNativeCell(1)];
}

public int Native_IsReplayDataLoaded(Handle handler, int numParams)
{
	BhopStyle style = view_as<BhopStyle>(GetNativeCell(1));

	return view_as<int>(ReplayEnabled(style) && gI_FrameCount[style] > 0);
}

public Action Cron(Handle Timer)
{
	if(!gB_Enabled)
	{
		bot_quota.IntValue = 0;

		return Plugin_Continue;
	}

	// make sure there are enough bots
	else if(bot_quota != null && bot_quota.IntValue != gI_ExpectedBots)
	{
		bot_quota.IntValue = gI_ExpectedBots;
	}

	// clear player cache if time is worse than wr
	// might cause issues if WR time is removed and someone else gets a new WR
	float[] fWRTimes = new float[gI_Styles];

	for(int i = 0; i < gI_Styles; i++)
	{
		Shavit_GetWRTime(view_as<BhopStyle>(i), fWRTimes[i]);

		if(gI_ReplayBotClient[i] != 0)
		{
			UpdateReplayInfo(gI_ReplayBotClient[i], view_as<BhopStyle>(i), fWRTimes[i]);
		}
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(gI_PlayerFrames[i] == 0 || !IsValidClient(i, true) || IsFakeClient(i))
		{
			continue;
		}

		BhopStyle style = Shavit_GetBhopStyle(i);

		if(!ReplayEnabled(style) || (fWRTimes[style] > 0.0 && Shavit_GetClientTime(i) > fWRTimes[style]))
		{
			ClearFrames(i);
		}
	}

	return Plugin_Continue;
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
	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
	}

	if(!gB_Enabled)
	{
		return;
	}

	bot_quota = FindConVar("bot_quota");
	bot_quota.Flags &= ~FCVAR_NOTIFY;

	GetCurrentMap(gS_Map, 256);
	GetMapDisplayName(gS_Map, gS_Map, 256);

	char[] sTempMap = new char[PLATFORM_MAX_PATH];
	FormatEx(sTempMap, PLATFORM_MAX_PATH, "maps/%s.nav", gS_Map);

	if(!FileExists(sTempMap))
	{
		if(!FileExists("maps/base.nav"))
		{
			SetFailState("Plugin startup FAILED: \"maps/base.nav\" does not exist.");
		}

		File_Copy("maps/base.nav", sTempMap);

		ForceChangeLevel(gS_Map, ".nav file generate");

		return;
	}

	ConVar bot_controllable = FindConVar("bot_controllable");

	if(bot_controllable != null)
	{
		bot_controllable.BoolValue = false;
	}

	ConVar bot_stop = FindConVar("bot_stop");
	bot_stop.BoolValue = true;

	ConVar bot_quota_mode = FindConVar("bot_quota_mode");
	bot_quota_mode.SetString("normal");

	ConVar mp_autoteambalance = FindConVar("mp_autoteambalance");
	mp_autoteambalance.BoolValue = false;

	ConVar mp_limitteams = FindConVar("mp_limitteams");
	mp_limitteams.IntValue = 0;

	ServerCommand("bot_kick");

	gI_ExpectedBots = 0;

	ConVar bot_join_after_player = FindConVar("bot_join_after_player");
	bot_join_after_player.BoolValue = false;

	ConVar bot_chatter = FindConVar("bot_chatter");
	bot_chatter.SetString("off");

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot");

	if(!DirExists(sPath))
	{
		CreateDirectory(sPath, 511);
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		gA_Frames[i] = new ArrayList(6);

		if(!ReplayEnabled(i))
		{
			continue;
		}

		gI_ExpectedBots++;
		gI_ReplayTick[i] = 0;
		gI_FrameCount[i] = 0;

		ServerCommand("bot_add");

		BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d", i);

		if(!DirExists(sPath))
		{
			CreateDirectory(sPath, 511);
		}

		if(!LoadReplay(view_as<BhopStyle>(i)))
		{
			gI_ReplayTick[i] = -1;
		}

		else
		{
			gRS_ReplayStatus[i] = Replay_Start;
			CreateTimer(gF_ReplayDelay / 2.0, StartReplay, i, TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	CreateTimer(1.0, Cron, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleSettings(view_as<BhopStyle>(i), gA_StyleSettings[i]);
		Shavit_GetStyleStrings(view_as<BhopStyle>(i), sStyleName, gS_StyleStrings[i][sStyleName], 128);
		Shavit_GetStyleStrings(view_as<BhopStyle>(i), sShortName, gS_StyleStrings[i][sShortName], 128);
	}

	gI_Styles = styles;
}

public bool LoadReplay(BhopStyle style)
{
	if(!ReplayEnabled(style))
	{
		return false;
	}

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(FileExists(sPath))
	{
		File fFile = OpenFile(sPath, "rb");

		char[] sHeader = new char[64];

		if(!fFile.ReadLine(sHeader, 64))
		{
			return false;
		}

		TrimString(sHeader);
		char[][] sExplodedHeader = new char[2][64];
		ExplodeString(sHeader, ":", sExplodedHeader, 2, 64);

		if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_V2)) // new replay format, fast!
		{
			int iReplaySize = StringToInt(sExplodedHeader[0]);
			gA_Frames[style].Resize(iReplaySize);

			any[] aReplayData = new any[6];

			for(int i = 0; i < iReplaySize; i++)
			{
				if(fFile.Read(aReplayData, 6, 4) >= 0)
				{
					gA_Frames[style].Set(i, view_as<float>(aReplayData[0]), 0);
					gA_Frames[style].Set(i, view_as<float>(aReplayData[1]), 1);
					gA_Frames[style].Set(i, view_as<float>(aReplayData[2]), 2);
					gA_Frames[style].Set(i, view_as<float>(aReplayData[3]), 3);
					gA_Frames[style].Set(i, view_as<float>(aReplayData[4]), 4);
					gA_Frames[style].Set(i, view_as<int>(aReplayData[5]), 5);
				}
			}
		}

		else // old, outdated and slow - only used for old replays
		{
			char[] sLine = new char[320];
			char[][] sExplodedLine = new char[6][64];

			for(int i = 0; !fFile.EndOfFile(); i++)
			{
				fFile.ReadLine(sLine, 320);
				int iStrings = ExplodeString(sLine, "|", sExplodedLine, 6, 64);

				gA_Frames[style].Resize(i + 1);
				gA_Frames[style].Set(i, StringToFloat(sExplodedLine[0]), 0);
				gA_Frames[style].Set(i, StringToFloat(sExplodedLine[1]), 1);
				gA_Frames[style].Set(i, StringToFloat(sExplodedLine[2]), 2);
				gA_Frames[style].Set(i, StringToFloat(sExplodedLine[3]), 3);
				gA_Frames[style].Set(i, StringToFloat(sExplodedLine[4]), 4);
				gA_Frames[style].Set(i, (iStrings == 6)? StringToInt(sExplodedLine[5]):0, 5);
			}
		}

		gI_FrameCount[style] = gA_Frames[style].Length;

		delete fFile;

		return true;
	}

	return false;
}

public bool SaveReplay(BhopStyle style)
{
	if(!ReplayEnabled(style))
	{
		return false;
	}

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(FileExists(sPath))
	{
		DeleteFile(sPath);
	}

	int iSize = gA_Frames[style].Length;

	File fFile = OpenFile(sPath, "wb");
	fFile.WriteLine("%d:%s", iSize, REPLAY_FORMAT_V2);

	int iTickrate = RoundToZero(gF_Tickrate);
	int iArraySize = (iTickrate * 6);
	any[] aReplayData = new any[iArraySize];
	any[] aFrameData = new any[6];

	int iQueuedFrames = 0;

	for(int i = 0; i < iSize; iQueuedFrames = (++i % iTickrate))
	{
		gA_Frames[style].GetArray(i, aFrameData, 6);

		for(int x = 0; x < 6; x++)
		{
			aReplayData[((iQueuedFrames * 6) + x)] = aFrameData[x];
		}

		if(i == (iSize - 1) || (iQueuedFrames + 1) == iTickrate)
		{
			fFile.Write(aReplayData, iQueuedFrames * 6, 4);
		}
	}

	delete fFile;

	gI_FrameCount[style] = iSize;

	return true;
}

public bool DeleteReplay(BhopStyle style)
{
	if(!ReplayEnabled(style))
	{
		return false;
	}

	char[] sPath = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "data/replaybot/%d/%s.replay", style, gS_Map);

	if(!FileExists(sPath) || !DeleteFile(sPath))
	{
		return false;
	}

	gA_Frames[style].Clear();
	gI_FrameCount[style] = 0;
	gI_ReplayTick[style] = -1;

	if(gI_ReplayBotClient[style] != 0)
	{
		UpdateReplayInfo(gI_ReplayBotClient[style], style, 0.0);
	}

	return true;
}

public void OnClientPutInServer(int client)
{
	if(IsClientSourceTV(client))
	{
		return;
	}

	if(!IsFakeClient(client))
	{
		gA_PlayerFrames[client] = new ArrayList(6);
	}

	else
	{
		for(int i = 0; i < gI_Styles; i++)
		{
			if(ReplayEnabled(i) && gI_ReplayBotClient[i] == 0)
			{
				gI_ReplayBotClient[i] = client;

				UpdateReplayInfo(client, view_as<BhopStyle>(i), -1.0);

				break;
			}
		}
	}
}

public void UpdateReplayInfo(int client, BhopStyle style, float time)
{
	if(!gB_Enabled || !IsValidClient(client) || !IsFakeClient(client))
	{
		return;
	}

	SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);

	CS_SetClientClanTag(client, "REPLAY");

	float fWRTime = 0.0;
	Shavit_GetWRTime(style, fWRTime);

	char[] sTime = new char[16];
	FormatSeconds((time == -1.0)? fWRTime:time, sTime, 16);

	char[] sName = new char[MAX_NAME_LENGTH];

	// switch because i may add more
	switch(gI_NameStyle)
	{
		case 0:
		{
			if(gI_FrameCount[style] == 0)
			{
				FormatEx(sName, MAX_NAME_LENGTH, "[%s] unloaded", gS_StyleStrings[style][sShortName]);
			}

			else
			{
				char[] sWRName = new char[MAX_NAME_LENGTH];
				Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH);

				FormatEx(sName, MAX_NAME_LENGTH, "[%s] %s - %s", gS_StyleStrings[style][sShortName], sWRName, sTime);
			}
		}

		case 1:
		{
			if(gI_FrameCount[style] == 0)
			{
				FormatEx(sName, MAX_NAME_LENGTH, "%s - N/A", gS_StyleStrings[style][sStyleName]);
			}

			else
			{
				FormatEx(sName, MAX_NAME_LENGTH, "%s - %s", gS_StyleStrings[style][sStyleName], sTime);
			}
		}
	}

	gB_HideNameChange = true;
	SetClientName(client, sName);

	int iScore = (gI_FrameCount[style] > 0)? 2000:-2000;

	if(gEV_Type == Engine_CSGO)
	{
		CS_SetClientContributionScore(client, iScore);
	}

	else
	{
		SetEntProp(client, Prop_Data, "m_iFrags", iScore);
	}

	SetEntProp(client, Prop_Data, "m_iDeaths", 0);

	gB_DontCallTimer = true;

	if((gI_FrameCount[style] == 0 || fWRTime == 0.0))
	{
		if(IsPlayerAlive(client))
		{
			ForcePlayerSuicide(client);
		}
	}

	else
	{
		if(!IsPlayerAlive(client))
		{
			CS_RespawnPlayer(client);
		}

		if(GetPlayerWeaponSlot(client, CS_SLOT_KNIFE) == -1)
		{
			GivePlayerItem(client, "weapon_knife");
		}
	}
}

public void OnClientDisconnect(int client)
{
	if(!IsFakeClient(client))
	{
		return;
	}

	for(int i = 0; i < gI_Styles; i++)
	{
		if(client == gI_ReplayBotClient[i])
		{
			gI_ReplayBotClient[i] = 0;

			break;
		}
	}
}

public void Shavit_OnStart(int client)
{
	ClearFrames(client);

	gB_Record[client] = true;
}

public void Shavit_OnStop(int client)
{
	ClearFrames(client);
}

public void Shavit_OnFinish(int client, BhopStyle style, float time)
{
	float fWRTime = 0.0;
	Shavit_GetWRTime(style, fWRTime);

	if(!gB_Enabled || !ReplayEnabled(style) || (fWRTime > 0.0 && time > fWRTime))
	{
		ClearFrames(client);
	}

	gB_Record[client] = false;
}

public void Shavit_OnWorldRecord(int client, BhopStyle style, float time)
{
	if(!ReplayEnabled(style) || gI_PlayerFrames[client] == 0)
	{
		return;
	}

	if(!gB_Enabled || (gF_TimeLimit > 0.0 && time > gF_TimeLimit))
	{
		ClearFrames(client);

		return;
	}

	gA_Frames[style] = gA_PlayerFrames[client].Clone();

	ClearFrames(client);
	SaveReplay(style);

	if(gI_ReplayBotClient[style] != 0)
	{
		UpdateReplayInfo(gI_ReplayBotClient[style], style, time);
		CS_RespawnPlayer(gI_ReplayBotClient[style]);

		gRS_ReplayStatus[style] = Replay_Running;
		gI_ReplayTick[style] = 0;

		float vecPosition[3];
		vecPosition[0] = gA_Frames[style].Get(0, 0);
		vecPosition[1] = gA_Frames[style].Get(0, 1);
		vecPosition[2] = gA_Frames[style].Get(0, 2);

		TeleportEntity(gI_ReplayBotClient[style], vecPosition, NULL_VECTOR, NULL_VECTOR);
	}
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
	if(!IsPlayerAlive(client) || !gB_Enabled)
	{
		return Plugin_Continue;
	}

	float vecCurrentPosition[3];
	GetClientAbsOrigin(client, vecCurrentPosition);

	int iReplayBotStyle = view_as<int>(GetReplayStyle(client));

	if(iReplayBotStyle != -1 && ReplayEnabled(iReplayBotStyle))
	{
		buttons = 0;

		if(gA_Frames[iReplayBotStyle] == null || gI_FrameCount[iReplayBotStyle] <= 0) // if no replay is loaded
		{
			return Plugin_Changed;
		}

		if(gI_ReplayTick[iReplayBotStyle] != -1 && gI_FrameCount[iReplayBotStyle] >= 1)
		{
			float vecPosition[3];
			float vecAngles[3];

			if(gRS_ReplayStatus[iReplayBotStyle] != Replay_Running)
			{
				int iFrame = (gRS_ReplayStatus[iReplayBotStyle] == Replay_Start)? 0:(gI_FrameCount[iReplayBotStyle] - 1);

				vecPosition[0] = gA_Frames[iReplayBotStyle].Get(iFrame, 0);
				vecPosition[1] = gA_Frames[iReplayBotStyle].Get(iFrame, 1);
				vecPosition[2] = gA_Frames[iReplayBotStyle].Get(iFrame, 2);

				vecAngles[0] = gA_Frames[iReplayBotStyle].Get(iFrame, 3);
				vecAngles[1] = gA_Frames[iReplayBotStyle].Get(iFrame, 4);

				TeleportEntity(client, vecPosition, vecAngles, view_as<float>({0.0, 0.0, 0.0}));

				return Plugin_Changed;
			}

			if(++gI_ReplayTick[iReplayBotStyle] >= gI_FrameCount[iReplayBotStyle])
			{
				gI_ReplayTick[iReplayBotStyle] = 0;
				gRS_ReplayStatus[iReplayBotStyle] = Replay_End;

				CreateTimer(gF_ReplayDelay / 2.0, EndReplay, iReplayBotStyle, TIMER_FLAG_NO_MAPCHANGE);

				SetEntityMoveType(client, MOVETYPE_NONE);

				return Plugin_Changed;
			}

			if(gI_ReplayTick[iReplayBotStyle] == 1)
			{
				gF_StartTick[iReplayBotStyle] = GetEngineTime();
			}

			SetEntityMoveType(client, ((GetEntityFlags(client) & FL_ONGROUND) > 0)? MOVETYPE_WALK:MOVETYPE_NOCLIP);

			vecPosition[0] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 0);
			vecPosition[1] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 1);
			vecPosition[2] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 2);

			vecAngles[0] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 3);
			vecAngles[1] = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 4);

			buttons = gA_Frames[iReplayBotStyle].Get(gI_ReplayTick[iReplayBotStyle], 5);

			float vecVelocity[3];
			MakeVectorFromPoints(vecCurrentPosition, vecPosition, vecVelocity);
			ScaleVector(vecVelocity, gF_Tickrate);

			TeleportEntity(client, NULL_VECTOR, vecAngles, vecVelocity);

			return Plugin_Changed;
		}
	}

	else
	{
		if(gB_Record[client] && ReplayEnabled(Shavit_GetBhopStyle(client)) && Shavit_GetTimerStatus(client) == Timer_Running)
		{
			gA_PlayerFrames[client].Resize(gI_PlayerFrames[client] + 1);

			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[0], 0);
			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[1], 1);
			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[2], 2);

			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], angles[0], 3);
			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], angles[1], 4);

			gA_PlayerFrames[client].Set(gI_PlayerFrames[client], buttons, 5);

			gI_PlayerFrames[client]++;
		}
	}

	return Plugin_Continue;
}

public Action EndReplay(Handle Timer, any data)
{
	gI_ReplayTick[data] = 0;
	gRS_ReplayStatus[data] = Replay_Start;

	CreateTimer(gF_ReplayDelay / 2.0, StartReplay, data, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Stop;
}

public Action StartReplay(Handle Timer, any data)
{
	if(gRS_ReplayStatus[data] == Replay_Running)
	{
		return Plugin_Stop;
	}

	gRS_ReplayStatus[data] = Replay_Running;

	return Plugin_Stop;
}

public bool ReplayEnabled(any style)
{
	return (!gA_StyleSettings[style][bUnranked] && !gA_StyleSettings[style][bNoReplay]);
}

public void Player_Event(Event event, const char[] name, bool dontBroadcast)
{
	if(!gB_Enabled)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsFakeClient(client))
	{
		event.BroadcastDisabled = true;

		if(!gB_DontCallTimer)
		{
			CreateTimer(0.10, DelayedUpdate, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}

		gB_DontCallTimer = false;
	}

	else
	{
		ClearFrames(client);
	}
}

public Action DelayedUpdate(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return Plugin_Stop;
	}

	UpdateReplayInfo(client, GetReplayStyle(client), -1.0);

	return Plugin_Stop;
}

public void BotEvents(Event event, const char[] name, bool dontBroadcast)
{
	if(!gB_Enabled)
	{
		return;
	}

	if(event.GetBool("bot"))
	{
		event.BroadcastDisabled = true;

		int client = GetClientOfUserId(event.GetInt("userid"));

		if(IsValidClient(client))
		{
			BhopStyle style = GetReplayStyle(client);

			if(style != view_as<BhopStyle>(-1))
			{
				UpdateReplayInfo(client, style, -1.0);
			}
		}
	}
}

public Action Hook_SayText2(UserMsg msg_id, any msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if(!gB_HideNameChange || !gB_Enabled)
	{
		return Plugin_Continue;
	}

	char[] sMessage = new char[24];

	if(GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pbmsg = msg;
		pbmsg.ReadString("msg_name", sMessage, 24);
	}

	else
	{
		BfRead bfmsg = msg;
		bfmsg.ReadByte();
		bfmsg.ReadByte();
		bfmsg.ReadString(sMessage, 24, false);
	}

	if(StrEqual(sMessage, "#Cstrike_Name_Change"))
	{
		gB_HideNameChange = false;

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public void ClearFrames(int client)
{
	gA_PlayerFrames[client].Clear();
	gI_PlayerFrames[client] = 0;
}

public void Shavit_OnWRDeleted(BhopStyle style)
{
	DeleteReplay(style);
}

public Action Command_DeleteReplay(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu m = new Menu(DeleteReplay_Callback);
	m.SetTitle("Delete a replay:");

	for(int i = 0; i < gI_Styles; i++)
	{
		if(!ReplayEnabled(i) || gI_FrameCount[i] == 0)
		{
			continue;
		}

		char[] sInfo = new char[4];
		IntToString(i, sInfo, 4);

		m.AddItem(sInfo, gS_StyleStrings[i][sStyleName]);
	}

	if(m.ItemCount == 0)
	{
		m.AddItem("-1", "No replays available.");
	}

	m.ExitButton = true;
	m.Display(client, 20);

	return Plugin_Handled;
}

public int DeleteReplay_Callback(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[4];
		m.GetItem(param2, sInfo, 4);
		BhopStyle style = view_as<BhopStyle>(StringToInt(sInfo));

		if(style == view_as<BhopStyle>(-1))
		{
			return 0;
		}

		Menu submenu = new Menu(DeleteConfirmation_Callback);
		submenu.SetTitle("Confirm deletion of %s replay?", gS_StyleStrings[style][sStyleName]);

		for(int i = 1; i <= GetRandomInt(2, 4); i++)
		{
			submenu.AddItem("-1", "NO");
		}

		submenu.AddItem(sInfo, "Yes, I understand this action cannot be reversed!");

		for(int i = 1; i <= GetRandomInt(2, 4); i++)
		{
			submenu.AddItem("-1", "NO");
		}

		submenu.ExitButton = true;
		submenu.Display(param1, 20);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public int DeleteConfirmation_Callback(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sInfo = new char[4];
		m.GetItem(param2, sInfo, 4);
		BhopStyle style = view_as<BhopStyle>(StringToInt(sInfo));

		if(DeleteReplay(style))
		{
			LogAction(param1, param1, "Deleted replay for %s on map %s.", gS_StyleStrings[style][sStyleName], gS_Map);

			Shavit_PrintToChat(param1, "Deleted replay for \x05%s\x01.", gS_StyleStrings[style][sStyleName]);
		}

		else
		{
			Shavit_PrintToChat(param1, "Could not delete replay for \x05%s\x01.", gS_StyleStrings[style][sStyleName]);
		}
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public BhopStyle GetReplayStyle(int client)
{
	for(int i = 0; i < gI_Styles; i++)
	{
		if(gI_ReplayBotClient[i] == client)
		{
			return view_as<BhopStyle>(i);
		}
	}

	return view_as<BhopStyle>(-1);
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

		file_destination.Write(buffer, cache, 1);
	}

	delete file_source;
	delete file_destination;

	return true;
}
