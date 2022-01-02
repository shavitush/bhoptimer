

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <convar_class>

#pragma newdecls required
#pragma semicolon 1

float g_flAirSpeedCap = 30.0;
float g_flOldYawAngle[MAXPLAYERS + 1];
ConVar g_ConVar_sv_airaccelerate;
int g_iSurfaceFrictionOffset;
float g_fMaxMove = 400.0;
EngineVersion g_Game;
bool g_bEnabled[MAXPLAYERS + 1];
int g_iType[MAXPLAYERS + 1];
float g_fPower[MAXPLAYERS + 1] = {1.0, ...};
bool g_bTASEnabled;

Convar g_ConVar_AutoFind_Offset;


public Plugin myinfo =
{
	name = "Perfect autostrafe",
	author = "xutaxkamay",
	description = "",
	version = "1.2",
	url = "https://steamcommunity.com/id/xutaxkamay/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("SetXutaxStrafe", Native_SetAutostrafe);
	CreateNative("GetXutaxStrafe", Native_GetAutostrafe);
	CreateNative("SetXutaxType", Native_SetType);
	CreateNative("GetXutaxType", Native_GetType);
	CreateNative("SetXutaxPower", Native_SetPower);
	CreateNative("GetXutaxPower", Native_GetPower);

	RegPluginLibrary("xutax-strafe");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_Game = GetEngineVersion();
	g_ConVar_sv_airaccelerate = FindConVar("sv_airaccelerate");

	GameData gamedata = new GameData("KiD-TAS.games");

	g_iSurfaceFrictionOffset = gamedata.GetOffset("m_surfaceFriction");
	delete gamedata;

	if(g_iSurfaceFrictionOffset == -1)
	{
		LogError("[XUTAX] Invalid offset supplied, defaulting friction values");
	}

	if(g_Game == Engine_CSGO)
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
	else if(g_Game == Engine_CSS)
	{
		if (g_iSurfaceFrictionOffset != -1)
		{
			g_iSurfaceFrictionOffset += FindSendPropInfo("CBasePlayer", "m_szLastPlaceName");
		}
	}
	else
	{
		SetFailState("This plugin is for CSGO/CSS only.");
	}

	RegAdminCmd("sm_xutax_scan", Command_ScanOffsets, ADMFLAG_CHEATS, "Scan for possible offset locations");

	g_ConVar_AutoFind_Offset = new Convar("xutax_find_offsets", "1", "Attempt to autofind offsets", _, true, 0.0, true, 1.0);

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

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (!g_bEnabled[client])
	{
		return Plugin_Continue;
	}

	if (!Shavit_ShouldProcessFrame(client))
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

	if (IsPlayerAlive(client)
		&& s_iOnGroundCount[client] <= 1
		&& !(GetEntityMoveType(client) & MOVETYPE_LADDER)
		&& (GetEntProp(client, Prop_Data, "m_nWaterLevel") <= 1))
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
	}

	g_flOldYawAngle[client] = angles[1];

	return Plugin_Continue;
}

stock void FindNewFrictionOffset(int client, bool logOnly = false)
{
	if(g_Game == Engine_CSGO)
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
