/*
 * shavit's Timer - TAS
 * by: xutaxkamay, KiD Fearless, rtldg
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
#include <sdktools>
#include <cstrike>
#include <convar_class>

#include <shavit/core>
#include <shavit/tas>
#include <shavit/tas-oblivious>
#include <shavit/tas-xutax>

#undef REQUIRE_PLUGIN
#include <shavit/checkpoints>
#include <shavit/zones>

#pragma newdecls required
#pragma semicolon 1

EngineVersion gEV_Type = Engine_Unknown;

float g_flAirSpeedCap = 30.0;
float g_flOldYawAngle[MAXPLAYERS + 1];
int g_iSurfaceFrictionOffset;
float g_fMaxMove = 400.0;
bool g_bEnabled[MAXPLAYERS + 1];
int g_iType[MAXPLAYERS + 1];
float g_fPower[MAXPLAYERS + 1] = {1.0, ...};

bool gB_ForceJump[MAXPLAYERS+1];

Convar gCV_AutoFindOffsets = null;
ConVar sv_airaccelerate = null;
ConVar sv_accelerate = null;
ConVar sv_friction = null;
ConVar sv_stopspeed = null;

public Plugin myinfo =
{
	name = "[shavit] TAS (XutaxKamay)",
	author = "xutaxkamay, KiD Fearless, rtldg",
	description = "TAS module for shavit's bhop timer featuring xutaxkamay's autostrafer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("SetXutaxStrafe", Native_SetAutostrafe);
	CreateNative("GetXutaxStrafe", Native_GetAutostrafe);
	CreateNative("SetXutaxType", Native_SetType);
	CreateNative("GetXutaxType", Native_GetType);
	CreateNative("SetXutaxPower", Native_SetPower);
	CreateNative("GetXutaxPower", Native_GetPower);

	RegPluginLibrary("shavit-tas");
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-misc.phrases");

	gEV_Type = GetEngineVersion();
	sv_airaccelerate = FindConVar("sv_airaccelerate");
	sv_accelerate = FindConVar("sv_accelerate");
	sv_friction = FindConVar("sv_friction");
	sv_stopspeed = FindConVar("sv_stopspeed");

	GameData gamedata = new GameData("shavit.games");

	if ((g_iSurfaceFrictionOffset = gamedata.GetOffset("m_surfaceFriction")) == -1)
	{
		LogError("[XUTAX] Invalid offset supplied, defaulting friction values");
	}

	delete gamedata;

	if (gEV_Type == Engine_CSGO)
	{
		g_fMaxMove = 450.0;
		ConVar sv_air_max_wishspeed = FindConVar("sv_air_max_wishspeed");
		sv_air_max_wishspeed.AddChangeHook(OnWishSpeedChanged);
		g_flAirSpeedCap = sv_air_max_wishspeed.FloatValue;

		if (g_iSurfaceFrictionOffset != -1)
		{
			g_iSurfaceFrictionOffset = FindSendPropInfo("CBasePlayer", "m_ubEFNoInterpParity") - g_iSurfaceFrictionOffset;
		}
	}
	else
	{
		if (g_iSurfaceFrictionOffset != -1)
		{
			g_iSurfaceFrictionOffset += FindSendPropInfo("CBasePlayer", "m_szLastPlaceName");
		}
	}

	RegAdminCmd("sm_xutax_scan", Command_ScanOffsets, ADMFLAG_CHEATS, "Scan for possible offset locations");

	gCV_AutoFindOffsets = new Convar("xutax_find_offsets", "1", "Attempt to autofind offsets", _, true, 0.0, true, 1.0);

	Convar.AutoExecConfig();
}

// doesn't exist in css so we have to cache the value
public void OnWishSpeedChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_flAirSpeedCap = StringToFloat(newValue);
}

public void OnClientConnected(int client)
{
	g_bEnabled[client] = false;
	g_iType[client] = Type_SurfOverride;
	g_fPower[client] = 1.0;
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity, int data)
{
	if (!IsValidClient(client, true) || IsFakeClient(client))
	{
		return;
	}

	if (!Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), TAS_STYLE_SETTING))
	{
		return;
	}

	if (Shavit_GetTimerStatus(client) != Timer_Running)
	{
		return;
	}

	if (type == Zone_Start)
	{
		if (GetEntityFlags(client) & FL_ONGROUND)
		{
			gB_ForceJump[client] = true;
		}
	}
}

int FindMenuItem(Menu menu, const char[] info)
{
	for (int i = 0; i < menu.ItemCount; i++)
	{
		char sInfo[64];
		menu.GetItem(i, sInfo, sizeof(sInfo));

		if (StrEqual(info, sInfo))
		{
			return i;
		}
	}

	return -1;
}

public Action Shavit_OnCheckpointMenuMade(int client, bool segmented, Menu menu)
{
	if (!Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), TAS_STYLE_SETTING))
	{
		return Plugin_Continue;
	}

	char sDisplay[64];
	bool tas_timescale = (Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(client), "tas_timescale") == -1.0);
	int delcurrentcheckpoint = -1;

	if (tas_timescale)
	{
		if ((delcurrentcheckpoint = FindMenuItem(menu, "del")) != -1)
		{
			menu.RemoveItem(delcurrentcheckpoint);
		}
	}

	FormatEx(sDisplay, 64, "%T\n ", "TasSettings", client);
	menu.AddItem("tassettings", sDisplay);
	//menu.ExitButton = false;

	if (delcurrentcheckpoint != -1)
	{
		FormatEx(sDisplay, 64, "%T", "MiscCheckpointDeleteCurrent", client);
		menu.AddItem("del", sDisplay, (Shavit_GetTotalCheckpoints(client) > 0) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	return Plugin_Changed;
}

public Action Shavit_OnCheckpointMenuSelect(int client, int param2, char[] info, int maxlength, int currentCheckpoint, int maxCPs)
{
	if (!Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), TAS_STYLE_SETTING))
	{
		return Plugin_Continue;
	}

	if (StrEqual(info, "tassettings"))
	{
		// OpenTasSettings(client);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

// TODO: Not good enough. Need to jump earlier to get 0.0 offset...
public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style, int mouse[2])
{
	if (!Shavit_ShouldProcessFrame(client))
	{
		return Plugin_Continue;
	}

	if (gB_ForceJump[client] && status == Timer_Running && Shavit_GetStyleSettingBool(style, TAS_STYLE_SETTING))
	{
		buttons |= IN_JUMP;
	}

	gB_ForceJump[client] = false;
	return Plugin_Changed;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
#if 0
	if (!g_bEnabled[client])
	{
		return Plugin_Continue;
	}
#endif

	if (!Shavit_ShouldProcessFrame(client))
	{
		return Plugin_Continue;
	}

	if (!IsPlayerAlive(client) || GetEntityMoveType(client) == MOVETYPE_NOCLIP || GetEntityMoveType(client) == MOVETYPE_LADDER || !(GetEntProp(client, Prop_Data, "m_nWaterLevel") <= 1))
	{
		return Plugin_Continue;
	}

	static int s_iOnGroundCount[MAXPLAYERS+1] = {1, ...};

	if (GetEntPropEnt(client, Prop_Send, "m_hGroundEntity") != -1)
	{
		s_iOnGroundCount[client]++;
	}
	else
	{
		s_iOnGroundCount[client] = 0;
	}

	float flSurfaceFriction = 1.0;

	if (g_iSurfaceFrictionOffset > 0)
	{
		flSurfaceFriction = GetEntDataFloat(client, g_iSurfaceFrictionOffset);

		if (gCV_AutoFindOffsets.BoolValue && s_iOnGroundCount[client] == 0 && !(flSurfaceFriction == 0.25 || flSurfaceFriction == 1.0))
		{
			FindNewFrictionOffset(client);
		}
	}

	if (s_iOnGroundCount[client] <= 1)
	{
		if (!!(buttons & (IN_FORWARD | IN_BACK)))
		{
			return Plugin_Continue;
		}

		if (!!(buttons & (IN_MOVERIGHT | IN_MOVELEFT)))
		{
			if (g_iType[client] == Type_Override)
			{
				return Plugin_Continue;
			}
			else if (g_iType[client] == Type_SurfOverride && IsSurfing(client))
			{
				return Plugin_Continue;
			}
		}

		if (true)
		{
			XutaxOnPlayerRunCmd(client, buttons, impulse, vel, angles, weapon, subtype, cmdnum, tickcount, seed, mouse,
				sv_airaccelerate.FloatValue, flSurfaceFriction, g_flAirSpeedCap, g_fMaxMove, g_flOldYawAngle[client], g_fPower[client]);
		}
		else
		{
			ObliviousOnPlayerRunCmd(client, buttons, impulse, vel, angles, weapon, subtype, cmdnum, tickcount, seed, mouse,
				sv_airaccelerate.FloatValue, flSurfaceFriction, g_flAirSpeedCap, g_fMaxMove,
				false /*no_speed_loss[client]*/);
		}
	}
	else
	{
		if (/*psh_enabled[client] &&*/ (vel[0] != 0.0 || vel[1] != 0.0))
		{
			float _delta_opt = ground_delta_opt(client, angles, vel, flSurfaceFriction,
				sv_accelerate.FloatValue, sv_friction.FloatValue, sv_stopspeed.FloatValue);

			float _tmp[3]; _tmp[0] = angles[0]; _tmp[2] = angles[2];
			_tmp[1] = normalize_yaw(angles[1] - _delta_opt);

			angles[1] = _tmp[1];
		}

		//return Plugin_Continue; // maybe??
	}

	g_flOldYawAngle[client] = angles[1];

	return Plugin_Continue;
}

stock void FindNewFrictionOffset(int client, bool logOnly = false)
{
	if (gEV_Type == Engine_CSGO)
	{
		int startingOffset = FindSendPropInfo("CBasePlayer", "m_ubEFNoInterpParity");
		for (int i = 16; i >= -128; --i)
		{
			float friction = GetEntDataFloat(client, startingOffset + i);
			if (friction == 0.25 || friction == 1.0)
			{
				if (logOnly)
				{
					PrintToConsole(client, "Found offset canidate: %i", i * -1);
				}
				else
				{
					g_iSurfaceFrictionOffset = startingOffset - i;
					LogError("[XUTAX] Current offset is out of date. Please update to new offset: %i", i * -1);
				}
			}
		}
	}
	else
	{
		int startingOffset = FindSendPropInfo("CBasePlayer", "m_szLastPlaceName");
		for (int i = 1; i <= 128; ++i)
		{
			float friction = GetEntDataFloat(client, startingOffset + i);
			if (friction == 0.25 || friction == 1.0)
			{
				if(logOnly)
				{
					PrintToConsole(client, "Found offset canidate: %i", i);
				}
				else
				{
					g_iSurfaceFrictionOffset = startingOffset + i;
					LogError("[XUTAX] Current offset is out of date. Please update to new offset: %i", i);
				}
			}
		}
	}
}

public Action Command_ScanOffsets(int client, int args)
{
	FindNewFrictionOffset(client, .logOnly = true);

	return Plugin_Handled;
}

// natives
public any Native_SetAutostrafe(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool value = GetNativeCell(2);
	g_bEnabled[client] = value;
	return 0;
}

public any Native_GetAutostrafe(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return g_bEnabled[client];
}

public any Native_SetType(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int value = GetNativeCell(2);
	g_iType[client] = value;
	return 0;
}

public any Native_GetType(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return g_iType[client];
}

public any Native_SetPower(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	float value = GetNativeCell(2);
	g_fPower[client] = value;
	return 0;
}

public any Native_GetPower(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return g_fPower[client];
}
