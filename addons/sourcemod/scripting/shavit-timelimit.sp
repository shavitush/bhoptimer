/*
 * shavit's Timer - Dynamic Timelimits
 * by: shavit, Nickelony, Sirhephaestus, rtldg
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
 *
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

// original idea from ckSurf.

#include <sourcemod>
#include <convar_class>
#include <dhooks>

#include <shavit/core>
#include <shavit/wr>

#undef REQUIRE_PLUGIN

#undef REQUIRE_EXTENSIONS
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

// #define DEBUG

// database handle
Database gH_SQL = null;

// base cvars
ConVar mp_do_warmup_period = null;
ConVar mp_freezetime = null;
ConVar mp_ignore_round_win_conditions = null;
ConVar mp_timelimit = null;
ConVar mp_roundtime = null;

// cvars
Convar gCV_Config = null;
Convar gCV_DefaultLimit = null;
Convar gCV_DynamicTimelimits = null;
Convar gCV_MinimumLimit = null;
Convar gCV_MaximumLimit = null;
Convar gCV_ForceMapEnd = null;
Convar gCV_MinimumTimes = null;
Convar gCV_PlayerAmount = null;
Convar gCV_Style = null;
Convar gCV_GameStartFix = null;
Convar gCV_InstantMapChange = null;
Convar gCV_Enabled = null;
Convar gCV_HideCvarChanges = null;
Convar gCV_Hide321CountDown = null;

// misc cache
bool gB_BlockRoundEndEvent = false;
bool gB_AlternateZeroPrint = false;
Handle gH_Timer = null;
EngineVersion gEV_Type = Engine_Unknown;
chatstrings_t gS_ChatStrings;

Handle gH_Forwards_OnCountdownStart = null;

// table prefix
char gS_MySQLPrefix[32];

bool gB_Late = false;

public Plugin myinfo =
{
	name = "[shavit] Dynamic Timelimits",
	author = "shavit, Nickelony, Sirhephaestus, rtldg",
	description = "Sets a dynamic value of mp_timelimit and mp_roundtime, based on average map times on the server.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int maxlength)
{
	gB_Late = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	gEV_Type = GetEngineVersion();

	gH_Forwards_OnCountdownStart = CreateGlobalForward("Shavit_OnCountdownStart", ET_Event);

	LoadTranslations("shavit-common.phrases");

	mp_do_warmup_period = FindConVar("mp_do_warmup_period");
	mp_freezetime = FindConVar("mp_freezetime");
	mp_ignore_round_win_conditions = FindConVar("mp_ignore_round_win_conditions");
	mp_timelimit = FindConVar("mp_timelimit");
	mp_roundtime = FindConVar("mp_roundtime");

	if(mp_roundtime != null)
	{
		mp_roundtime.SetBounds(ConVarBound_Upper, false);
	}

	HookEventEx("server_cvar", Hook_ServerCvar, EventHookMode_Pre);

	gCV_Config = new Convar("shavit_timelimit_config", "1", "Enables the following game settings:\n\"mp_do_warmup_period\" \"0\"\n\"mp_freezetime\" \"0\"\n\"mp_ignore_round_win_conditions\" \"1\"", 0, true, 0.0, true, 1.0);
	gCV_DefaultLimit = new Convar("shavit_timelimit_default", "60.0", "Default timelimit to use in case there isn't an average.", 0);
	gCV_DynamicTimelimits = new Convar("shavit_timelimit_dynamic", "1", "Use dynamic timelimits.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_MinimumLimit = new Convar("shavit_timelimit_minimum", "20.0", "Minimum timelimit to use.\nREQUIRES \"shavit_timelimit_dynamic\" TO BE ENABLED!", 0);
	gCV_MaximumLimit = new Convar("shavit_timelimit_maximum", "120.0", "Maximum timelimit to use.\nREQUIRES \"shavit_timelimit_dynamic\" TO BE ENABLED!\n0 - No maximum", 0);
	gCV_ForceMapEnd = new Convar("shavit_timelimit_forcemapend", "1", "Force the map to end after the timelimit.\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_MinimumTimes = new Convar("shavit_timelimit_minimumtimes", "5", "Minimum amount of times required to calculate an average.\nREQUIRES \"shavit_timelimit_dynamic\" TO BE ENABLED!", 0, true, 1.0);
	gCV_PlayerAmount = new Convar("shavit_timelimit_playertime", "25", "Limited amount of times to grab from the database to calculate an average.\nREQUIRES \"shavit_timelimit_dynamic\" TO BE ENABLED!\nSet to 0 to have it \"unlimited\".", 0);
	gCV_Style = new Convar("shavit_timelimit_style", "1", "If set to 1, calculate an average only from times that the first (default: forwards) style was used to set.\nREQUIRES \"shavit_timelimit_dynamic\" TO BE ENABLED!", 0, true, 0.0, true, 1.0);
	gCV_GameStartFix = new Convar("shavit_timelimit_gamestartfix", "1", "If set to 1, will block the round from ending because another player joined. Useful for single round servers.", 0, true, 0.0, true, 1.0);
	gCV_Enabled = new Convar("shavit_timelimit_enabled", "1", "Enables/Disables functionality of the plugin.", 0, true, 0.0, true, 1.0);
	gCV_InstantMapChange = new Convar("shavit_timelimit_instantmapchange", "1", "If set to 1 then it will changelevel to the next map after the countdown. Requires the 'nextmap' to be set.", 0, true, 0.0, true, 1.0);
	gCV_HideCvarChanges = new Convar("shavit_timelimit_hidecvarchange", "0", "Whether to hide changes to mp_timelimit & mp_roundtime from chat.", 0, true, 0.0, true, 1.0);
	gCV_Hide321CountDown = new Convar("shavit_timelimt_hide321countdown", "0", "Whether to hide 3.. 2.. 1.. countdown messages.", 0, true, 0.0, true, 1.0);

	gCV_ForceMapEnd.AddChangeHook(OnConVarChanged);
	gCV_Enabled.AddChangeHook(OnConVarChanged);

	Convar.AutoExecConfig();

	RegAdminCmd("sm_extend", Command_Extend, ADMFLAG_CHANGEMAP, "Admin command for extending map");
	RegAdminCmd("sm_extendmap", Command_Extend, ADMFLAG_CHANGEMAP, "Admin command for extending map");

	HookEvent("round_end", round_end, EventHookMode_Pre);

	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = GetTimerDatabaseHandle();

	if(gB_Late)
		Shavit_OnChatConfigLoaded();
}

public void OnMapStart()
{
	gB_BlockRoundEndEvent = false;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(view_as<bool>(StringToInt(newValue)) && gEV_Type != Engine_TF2)
	{
		delete gH_Timer;
		gH_Timer = CreateTimer(1.0, Timer_PrintToChat, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		delete gH_Timer;
	}
}

public Action Hook_ServerCvar(Event event, const char[] name, bool dontBroadcast)
{
	if (gCV_HideCvarChanges.BoolValue)
	{
		char cvarname[32];
		GetEventString(event, "cvarname", cvarname, sizeof(cvarname));

		if (StrEqual(cvarname, "mp_timelimit", true) || StrEqual(cvarname, "mp_roundtime", true))
		{
			event.BroadcastDisabled = true;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

public void OnConfigsExecuted()
{
	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	if(gCV_Config.BoolValue)
	{
		if(mp_do_warmup_period != null)
		{
			mp_do_warmup_period.BoolValue = false;
		}

		if(mp_freezetime != null)
		{
			mp_freezetime.IntValue = 0;
		}

		if(mp_ignore_round_win_conditions != null)
		{
			mp_ignore_round_win_conditions.BoolValue = true;
		}
	}

	if(gCV_DynamicTimelimits.BoolValue)
	{
		StartCalculating();
	}
	else
	{
		SetLimit(RoundToNearest(gCV_DefaultLimit.FloatValue));
	}

	if(gCV_ForceMapEnd.BoolValue && gH_Timer == null && gEV_Type != Engine_TF2)
	{
		gH_Timer = CreateTimer(1.0, Timer_PrintToChat, 0, TIMER_REPEAT);
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

void StartCalculating()
{
	char sMap[PLATFORM_MAX_PATH];
	GetLowercaseMapName(sMap);

	char sQuery[512];
	FormatEx(sQuery, 512, "SELECT COUNT(*), SUM(t.time) FROM (SELECT r.time, r.style FROM %splayertimes r WHERE r.map = '%s' AND r.track = 0 %sORDER BY r.time LIMIT %d) t;", gS_MySQLPrefix, sMap, (gCV_Style.BoolValue)? "AND style = 0 ":"", gCV_PlayerAmount.IntValue);

	#if defined DEBUG
	PrintToServer("%s", sQuery);
	#endif

	QueryLog(gH_SQL, SQL_GetMapTimes, sQuery, 0, DBPrio_Low);
}

public void SQL_GetMapTimes(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (TIMELIMIT time selection) SQL query failed. Reason: %s", error);

		return;
	}

	results.FetchRow();
	int iRows = results.FetchInt(0);

	if(iRows >= gCV_MinimumTimes.IntValue)
	{
		float fTimeSum = results.FetchFloat(1);
		float fAverage = (fTimeSum / 60 / gCV_MinimumTimes.IntValue);

		if(fAverage <= 1)
		{
			fAverage *= 10;
		}
		else if(fAverage <= 2)
		{
			fAverage *= 9;
		}
		else if(fAverage <= 4)
		{
			fAverage *= 8;
		}
		else if(fAverage <= 8)
		{
			fAverage *= 7;
		}
		else if(fAverage <= 10)
		{
			fAverage *= 6;
		}
		else
		{
			fAverage *= 5;
		}

		fAverage += 5; // I give extra 5 minutes, so players can actually retry the map until they get a good time.

		if(fAverage < gCV_MinimumLimit.FloatValue)
		{
			fAverage = gCV_MinimumLimit.FloatValue;
		}
		else if(fAverage > gCV_MaximumLimit.FloatValue)
		{
			fAverage = gCV_MaximumLimit.FloatValue;
		}

		SetLimit(RoundToCeil(fAverage / 10) * 10);
	}
	else
	{
		SetLimit(RoundToNearest(gCV_DefaultLimit.FloatValue));
	}
}

void SetLimit(int time)
{
	mp_timelimit.IntValue = time;

	if(mp_roundtime != null)
	{
		mp_roundtime.IntValue = time;
		GameRules_SetProp("m_iRoundTime", time * 60); 
	}
}

public Action Timer_PrintToChat(Handle timer)
{
	if(!gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	int timelimit = 0;

	if(!GetMapTimeLimit(timelimit) || timelimit == 0)
	{
		return Plugin_Continue;
	}

	int timeleft = 0;
	GetMapTimeLeft(timeleft);

	if (gCV_InstantMapChange.BoolValue && timeleft <= 5)
	{
		if (timeleft)
		{
			if (timeleft == 5)
			{
				Call_StartForward(gH_Forwards_OnCountdownStart);
				Call_Finish();
			}

			if (1 <= timeleft <= 3 && !gCV_Hide321CountDown.BoolValue)
			{
				Shavit_StopChatSound();
				Shavit_PrintToChatAll("%d..", timeleft);
			}

			if (timeleft == 1)
			{
				CreateTimer(0.9001, Timer_ChangeMap, 0, TIMER_FLAG_NO_MAPCHANGE);
			}
		}

		return Plugin_Continue;
	}

	if(timeleft <= 0 && timeleft >= -3)
	{
		Shavit_StopChatSound();
	}

	char timebuf[12];

	switch(timeleft)
	{
		case 3600, 1800, 1200, 600, 300, 120:
		{
			IntToString(timeleft/60, timebuf, sizeof(timebuf));
			Shavit_StopChatSound();
			Shavit_PrintToChatAll("%T", "Minutes", LANG_SERVER, timebuf);
		}
		case 60, 30, 15:
		{
			IntToString(timeleft, timebuf, sizeof(timebuf));
			Shavit_PrintToChatAll("%T", "Seconds", LANG_SERVER, timebuf);
		}

		case 0: // case 0 is hit twice....
		{
			if (!gB_AlternateZeroPrint)
			{
				Call_StartForward(gH_Forwards_OnCountdownStart);
				Call_Finish();
			}

			Shavit_PrintToChatAll("%d..", gB_AlternateZeroPrint ? 4 : 5);
			gB_AlternateZeroPrint = !gB_AlternateZeroPrint;
		}
		case -1:
		{
			Shavit_PrintToChatAll("3..");
		}
		case -2:
		{
			Shavit_PrintToChatAll("2..");

			if (gEV_Type != Engine_CSGO)
			{
				gB_BlockRoundEndEvent = true;
				// needs to be when timeleft is under 0 otherwise the round will restart and the map won't change
				CS_TerminateRound(0.0, CSRoundEnd_Draw, true);
			}
		}
		case -3:
		{
			Shavit_PrintToChatAll("1..");

			if (gEV_Type == Engine_CSGO)
			{
				gB_BlockRoundEndEvent = true;
				// needs to be when timeleft is under 0 otherwise the round will restart and the map won't change
				CS_TerminateRound(0.0, CSRoundEnd_Draw, true);
			}
		}
	}

	return Plugin_Continue;
}

public Action Timer_ChangeMap(Handle timer, any data)
{
	char map[PLATFORM_MAX_PATH];

	if (GetNextMap(map, sizeof(map)))
	{
		ForceChangeLevel(map, "bhoptimer instant map change after timelimit");
	}

	return Plugin_Stop;
}

public Action CS_OnTerminateRound(float &fDelay, CSRoundEndReason &iReason)
{
	if(gCV_Enabled.BoolValue && gCV_GameStartFix.BoolValue && iReason == CSRoundEnd_GameStart)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action round_end(Event event, const char[] name, bool dontBroadcast)
{
	if (gB_BlockRoundEndEvent)
	{
		event.BroadcastDisabled = true; // stop the "Event.RoundDraw" sound from playing client-side
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public Action Command_Extend(int client, int args)
{
	int extendtime = 10 * 60;

	if (args > 0)
	{
		char sArg[8];
		GetCmdArg(1, sArg, sizeof(sArg));
		extendtime = RoundFloat(StringToFloat(sArg) * 60);
	}
	else
	{
		ConVar smc_mapvote_extend_time = FindConVar("smc_mapvote_extend_time");

		if (smc_mapvote_extend_time)
		{
			extendtime = RoundFloat(smc_mapvote_extend_time.FloatValue * 60.0);
		}
	}

	ExtendMapTimeLimit(extendtime);
	Shavit_PrintToChatAll("%T", "Extended", LANG_SERVER, gS_ChatStrings.sVariable2, client, gS_ChatStrings.sText, gS_ChatStrings.sVariable, extendtime / 60,  gS_ChatStrings.sText);
	return Plugin_Handled;
}
