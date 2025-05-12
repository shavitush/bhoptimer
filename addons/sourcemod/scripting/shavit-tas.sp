/*
 * shavit's Timer - TAS
 * by: xutaxkamay, KiD Fearless, rtldg
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

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <convar_class>

#include <shavit/core>
#include <shavit/tas>
#include <shavit/tas-oblivious>
#include <shavit/tas-xutax>

#undef REQUIRE_PLUGIN
#include <shavit/checkpoints>
#include <shavit/replay-recorder>
#include <shavit/zones>

#pragma newdecls required
#pragma semicolon 1

bool gB_Late = false;
EngineVersion gEV_Type = Engine_Unknown;

float g_flAirSpeedCap = 30.0;
float g_flOldYawAngle[MAXPLAYERS + 1];
int g_iSurfaceFrictionOffset;
float g_fMaxMove = 400.0;

bool gB_Autostrafer[MAXPLAYERS + 1];
AutostrafeType gI_Type[MAXPLAYERS + 1];
AutostrafeOverride gI_Override[MAXPLAYERS + 1];
bool gB_Prestrafe[MAXPLAYERS + 1];
bool gB_AutoJumpOnStart[MAXPLAYERS + 1];
bool gB_EdgeJump[MAXPLAYERS + 1];
float g_fPower[MAXPLAYERS + 1] = {1.0, ...};
bool gB_AutogainBasicStrafer[MAXPLAYERS + 1];

bool gB_ForceJump[MAXPLAYERS+1];
int gI_LastRestart[MAXPLAYERS+1];

ConVar sv_airaccelerate = null;
ConVar sv_accelerate = null;
ConVar sv_friction = null;
ConVar sv_stopspeed = null;

chatstrings_t gS_ChatStrings;

bool gB_GlobalTraceResult = false;

bool gB_ReplayRecorder = false;

public Plugin myinfo =
{
	name = "[shavit] TAS",
	author = "xutaxkamay, oblivious, KiD Fearless, rtldg",
	description = "TAS module for shavit's bhop timer featuring xutaxkamay's autostrafer and oblivious's autogain.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_SetAutostrafeEnabled", Native_SetAutostrafeEnabled);
	CreateNative("Shavit_GetAutostrafeEnabled", Native_GetAutostrafeEnabled);
	CreateNative("Shavit_SetAutostrafeType", Native_SetAutostrafeType);
	CreateNative("Shavit_GetAutostrafeType", Native_GetAutostrafeType);
	CreateNative("Shavit_SetAutostrafePower", Native_SetAutostrafePower);
	CreateNative("Shavit_GetAutostrafePower", Native_GetAutostrafePower);
	CreateNative("Shavit_SetAutostrafeKeyOverride", Native_SetAutostrafeKeyOverride);
	CreateNative("Shavit_GetAutostrafeKeyOverride", Native_GetAutostrafeKeyOverride);
	CreateNative("Shavit_SetAutoPrestrafe", Native_SetAutoPrestrafe);
	CreateNative("Shavit_GetAutoPrestrafe", Native_GetAutoPrestrafe);
	CreateNative("Shavit_SetAutoJumpOnStart", Native_SetAutoJumpOnStart);
	CreateNative("Shavit_GetAutoJumpOnStart", Native_GetAutoJumpOnStart);
	CreateNative("Shavit_SetEdgeJump", Native_SetEdgeJump);
	CreateNative("Shavit_GetEdgeJump", Native_GetEdgeJump);
	CreateNative("Shavit_SetAutogainBasicStrafer", Native_SetAutogainBasicStrafer);
	CreateNative("Shavit_GetAutogainBasicStrafer", Native_GetAutogainBasicStrafer);

	gB_Late = late;
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

	Address surfaceFrictionAddress;

	if (gEV_Type == Engine_CSGO)
		surfaceFrictionAddress = gamedata.GetAddress("m_surfaceFriction");
	else
		surfaceFrictionAddress = gamedata.GetMemSig("CBasePlayer->m_surfaceFriction");

	if (surfaceFrictionAddress == Address_Null)
	{
		g_iSurfaceFrictionOffset = -1;
		LogError("[XUTAX] The address of m_surfaceFriction is null, defaulting friction values");
	}
	else
	{
		if (gEV_Type == Engine_CSGO)
		{
			g_iSurfaceFrictionOffset = view_as<int>(surfaceFrictionAddress);
		}
		else
		{
			int instr = LoadFromAddress(surfaceFrictionAddress, NumberType_Int32);
			// The lowest two bytes are the beginning of a `mov`.
			// The offset is 100% definitely totally always 16-bit.
			// We could just put the offset into the gamedata too but SHUT UP!
			g_iSurfaceFrictionOffset = instr >> 16;
		}
	}

	delete gamedata;

	if (gEV_Type == Engine_CSGO)
	{
		g_fMaxMove = 450.0;
		ConVar sv_air_max_wishspeed = FindConVar("sv_air_max_wishspeed");
		sv_air_max_wishspeed.AddChangeHook(OnWishSpeedChanged);
		g_flAirSpeedCap = sv_air_max_wishspeed.FloatValue;
	}

	AddCommandListener(CommandListener_Toggler, "+autostrafer");
	AddCommandListener(CommandListener_Toggler, "-autostrafer");
	AddCommandListener(CommandListener_Toggler, "+autostrafe");
	AddCommandListener(CommandListener_Toggler, "-autostrafe");
	AddCommandListener(CommandListener_Toggler, "+autoprestrafe");
	AddCommandListener(CommandListener_Toggler, "-autoprestrafe");
	AddCommandListener(CommandListener_Toggler, "+autojumponstart");
	AddCommandListener(CommandListener_Toggler, "-autojumponstart");
	AddCommandListener(CommandListener_Toggler, "+edgejump");
	AddCommandListener(CommandListener_Toggler, "-edgejump");
	AddCommandListener(CommandListener_Toggler, "+autogainbss");
	AddCommandListener(CommandListener_Toggler, "-autogainbss");

	RegConsoleCmd("sm_autostrafer", Command_Toggler, "Usage: !autostrafe [1|0]");
	RegConsoleCmd("sm_autostrafe", Command_Toggler, "Usage: !autostrafe [1|0]");
	RegConsoleCmd("sm_autoprestrafe", Command_Toggler, "Usage: !autoprestrafe [1|0}");
	RegConsoleCmd("sm_autojumponstart", Command_Toggler, "Usage: !autojumponstart [1|0}");
	RegConsoleCmd("sm_edgejump", Command_Toggler, "Usage: !edgejump [1|0}");
	RegConsoleCmd("sm_autogainbss", Command_Toggler, "Usage: !autogainbss [1|0}");

	RegConsoleCmd("sm_tasm", Command_TasSettingsMenu, "Opens the TAS settings menu.");
	RegConsoleCmd("sm_tasmenu", Command_TasSettingsMenu, "Opens the TAS settings menu.");

	//Convar.AutoExecConfig();

	if (gB_Late)
	{
		Shavit_OnChatConfigLoaded();

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i))
			{
				OnClientConnected(i);

				if (IsClientInGame(i))
				{
					OnClientPutInServer(i);
				}
			}
		}
	}

	gB_ReplayRecorder = LibraryExists("shavit-replay-recorder");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "shavit-replay-recorder"))
	{
		gB_ReplayRecorder = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "shavit-replay-recorder"))
	{
		gB_ReplayRecorder = false;
	}
}

// doesn't exist in css so we have to cache the value
public void OnWishSpeedChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_flAirSpeedCap = StringToFloat(newValue);
}

public void OnClientConnected(int client)
{
	gB_Autostrafer[client] = true;
	gI_Override[client] = AutostrafeOverride_Surf_W_Okay;
	gI_Type[client] = AutostrafeType_1Tick;
	gB_AutoJumpOnStart[client] = true;
	gB_EdgeJump[client] = true;
	gB_Prestrafe[client] = true;
	g_fPower[client] = 1.0;
	gB_AutogainBasicStrafer[client] = true;
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client))
	{
		SDKHook(client, SDKHook_PostThinkPost, PostThinkPost);
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public Action Shavit_OnStart(int client, int track)
{
	gB_ForceJump[client] = false;
	return Plugin_Continue;
}

public void Shavit_OnRestart(int client, int track)
{
	gI_LastRestart[client] = GetGameTickCount();
}

public Action Shavit_OnTeleportPre(int client, int index, int target)
{
	// to prevent gB_ForceJump when teleporting to a checkpoint in the start zone
	gI_LastRestart[client] = GetGameTickCount();
}

public void Shavit_OnEnterZone(int client, int type, int track, int id, int entity, int data)
{
	if (!IsValidClient(client, true) || IsFakeClient(client))
	{
		return;
	}

	if (type == Zone_Start)
	{
		if (Shavit_GetClientTrack(client) == track)
		{
			gB_ForceJump[client] = false;
		}
	}
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity, int data)
{
	if (type != Zone_Start)
	{
		return;
	}

	if (!IsValidClient(client, true) || IsFakeClient(client))
	{
		return;
	}

	if (!Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), "autojumponstart"))
	{
		return;
	}

	if (Shavit_GetTimerStatus(client) != Timer_Running)
	{
		return;
	}

	// You can be inside multiple startzones...
	if (Shavit_InsideZone(client, type, track))
	{
		return;
	}

	// Shavit_OnLeaveZone() will be called a couple times because of the shavit-zones event-clearing thing that happens on restart.
	// 5 is a good value that works, but we'll use 6 just-in-case.
	if (GetGameTickCount() - gI_LastRestart[client] < 6)
	{
		return;
	}

	if (GetEntityFlags(client) & FL_ONGROUND)
	{
		if (gB_AutoJumpOnStart[client])
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

bool HasAnyTasStyleSettings(int style)
{
	if (Shavit_GetStyleSettingBool(style, "tas")
	||  Shavit_GetStyleSettingBool(style, "tas_timescale")
	||  Shavit_GetStyleSettingBool(style, "autoprestrafe")
	||  Shavit_GetStyleSettingBool(style, "edgejump")
	||  Shavit_GetStyleSettingBool(style, "autojumponstart"))
	{
		return true;
	}

	return false;
}

public Action Shavit_OnCheckpointMenuMade(int client, bool segmented, Menu menu)
{
	if (!HasAnyTasStyleSettings(Shavit_GetBhopStyle(client)))
	{
		return Plugin_Continue;
	}

	char sDisplay[64];
	bool tas_timescale = (Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(client), "tas_timescale") == -1.0);

	FormatEx(sDisplay, 64, "%T\n ", "TasSettings", client);

	if (tas_timescale)
	{
		int pos = FindMenuItem(menu, "del");
		menu.InsertItem(pos, "tassettings", sDisplay);
	}
	else
	{
		menu.AddItem("tassettings", sDisplay);
	}

	menu.ExitButton = gEV_Type != Engine_CSGO;

	return Plugin_Changed;
}

public Action Shavit_OnCheckpointMenuSelect(int client, int param2, char[] info, int maxlength, int currentCheckpoint, int maxCPs)
{
	if (StrEqual(info, "tassettings"))
	{
		OpenTasSettingsMenu(client);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style, int mouse[2])
{
	if (!Shavit_ShouldProcessFrame(client))
	{
		return Plugin_Continue;
	}

	if (gB_ForceJump[client] && (Shavit_GetStyleSettingBool(style, "edgejump") || Shavit_GetStyleSettingBool(style, "autojumponstart")))
	{
		buttons |= IN_JUMP;
	}

	gB_ForceJump[client] = false;
	return Plugin_Changed;
}

bool TRFilter_OnlyZones(int entity, any data)
{
	int zoneid = Shavit_GetZoneID(entity);

	if (zoneid == -1 || Shavit_GetZoneTrack(zoneid) != data)
	{
		return true;
	}

	gB_GlobalTraceResult = true;
	return false;
}

#if 0
public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (IsFakeClient(client))
	{
		return;
	}
#else
public void PostThinkPost(int client)
{
#endif

	if (gB_ForceJump[client])
	{
		return;
	}

	int style = Shavit_GetBhopStyle(client);
	bool edgejump = (gB_EdgeJump[client] && Shavit_GetStyleSettingBool(style, "edgejump"));
	bool autojumponstart = (gB_AutoJumpOnStart[client] && Shavit_GetStyleSettingBool(style, "autojumponstart"));

	if (!edgejump && !autojumponstart)
	{
		return;
	}

	if (!Shavit_ShouldProcessFrame(client))
	{
		return;
	}

	if (!IsPlayerAlive(client) || GetEntityMoveType(client) != MOVETYPE_WALK || !(GetEntProp(client, Prop_Data, "m_nWaterLevel") <= 1))
	{
		return;
	}

	if (!(GetEntityFlags(client) & FL_ONGROUND))
	{
		return;
	}

	float origin[3], absvel[3], nextpos[3];
	GetClientAbsOrigin(client, origin);
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", absvel);
	ScaleVector(absvel, GetTickInterval());
	float mins[3], maxs[3];
	GetEntPropVector(client, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(client, Prop_Send, "m_vecMaxs", maxs);

	if (autojumponstart)
	{
		int track = Shavit_GetClientTrack(client);
		if (Shavit_InsideZone(client, Zone_Start, track))
		{
			float blah[3]; blah = absvel;
			ScaleVector(blah, 3.0); // 2 isn't always enough... so 3 it is :)
			AddVectors(origin, blah, nextpos);

			gB_GlobalTraceResult = false;
			TR_EnumerateEntitiesHull(nextpos, nextpos, mins, maxs, PARTITION_TRIGGER_EDICTS, TRFilter_OnlyZones, track);

			if (!gB_GlobalTraceResult)
			{
				gB_ForceJump[client] = true;
			}
		}
	}

	if (edgejump && !gB_ForceJump[client])
	{
		float lower[3];
		AddVectors(origin, absvel, nextpos);
		AddVectors(nextpos, view_as<float>({0.0, 0.0, -10.0}), lower);

		TR_TraceHullFilter(nextpos, lower, mins, maxs, MASK_PLAYERSOLID, TRFilter_NoPlayers, client);
		gB_ForceJump[client] = !TR_DidHit();
	}
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (IsFakeClient(client))
	{
		return Plugin_Continue;
	}

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

#if 0
		if (buttons & IN_FORWARD)
		{
			buttons &= ~IN_FORWARD;
			vel[0] = 0.0;
		}
#endif
	}

	float flSurfaceFriction = 1.0;

	if (g_iSurfaceFrictionOffset > 0)
	{
		flSurfaceFriction = GetEntDataFloat(client, g_iSurfaceFrictionOffset);
	}

	int style = Shavit_GetBhopStyle(client);
	AutostrafeType type = view_as<AutostrafeType>(Shavit_GetStyleSettingInt(style, "autostrafe"));

	if (type == AutostrafeType_Any)
	{
		type = gI_Type[client];
	}

	float oldyaw = g_flOldYawAngle[client];
	g_flOldYawAngle[client] = angles[1];

	if (s_iOnGroundCount[client] <= 1)
	{
		if (!type || !gB_Autostrafer[client] || IsSurfing(client))
		{
			return Plugin_Continue;
		}

		if (type != AutostrafeType_Autogain && type != AutostrafeType_AutogainNoSpeedLoss)
		{
			if (!!(buttons & IN_BACK))
			{
				return Plugin_Continue;
			}

			if (!!(buttons & IN_FORWARD))
			{
				if (gI_Override[client] != AutostrafeOverride_Surf_W_Okay)
				{
					return Plugin_Continue;
				}
			}

			if (!!(buttons & (IN_MOVERIGHT | IN_MOVELEFT)))
			{
				if (gI_Override[client] == AutostrafeOverride_All)
				{
					return Plugin_Continue;
				}
				/*
				else if (gI_Override[client] == AutostrafeOverride_Surf && IsSurfing(client))
				{
					return Plugin_Continue;
				}
				*/
			}
		}

		if (type == AutostrafeType_1Tick)
		{
			XutaxOnPlayerRunCmd(client, buttons, impulse, vel, angles, weapon, subtype, cmdnum, tickcount, seed, mouse,
				sv_airaccelerate.FloatValue, flSurfaceFriction, g_flAirSpeedCap, g_fMaxMove, oldyaw, g_fPower[client]);
		}
		else if (type == AutostrafeType_Autogain || type == AutostrafeType_AutogainNoSpeedLoss)
		{
			if (gB_AutogainBasicStrafer[client])
			{
				float delta = AngleNormalize(angles[1] - oldyaw);

				if (delta < 0.0)
				{
					vel[1] = g_fMaxMove;
				}
				else if (delta > 0.0)
				{
					vel[1] = -g_fMaxMove;
				}
			}

			ObliviousOnPlayerRunCmd(client, buttons, impulse, vel, angles, weapon, subtype, cmdnum, tickcount, seed, mouse,
				sv_airaccelerate.FloatValue, flSurfaceFriction, g_flAirSpeedCap, g_fMaxMove,
				(type == AutostrafeType_AutogainNoSpeedLoss));
		}
		else if (type == AutostrafeType_Basic)
		{
			float delta = AngleNormalize(angles[1] - oldyaw);

			if (delta < 0.0)
			{
				vel[1] = g_fMaxMove;
			}
			else if (delta > 0.0)
			{
				vel[1] = -g_fMaxMove;
			}
		}
	}
	else
	{
		if (gB_Prestrafe[client]
		&&  (vel[0] != 0.0 || vel[1] != 0.0)
		&&  Shavit_GetStyleSettingBool(style, "autoprestrafe"))
		{
			float _delta_opt = ground_delta_opt(client, angles, vel, flSurfaceFriction,
				sv_accelerate.FloatValue, sv_friction.FloatValue, sv_stopspeed.FloatValue);

			float _tmp[3]; _tmp[0] = angles[0]; _tmp[2] = angles[2];
			_tmp[1] = normalize_yaw(angles[1] - _delta_opt);

			if (gB_ReplayRecorder)
			{
				Shavit_HijackAngles(client, angles[0], angles[1], 2, true);
			}

			angles[1] = _tmp[1];
		}
	}

	return Plugin_Continue;
}

void OpenTasSettingsMenu(int client, int pos=0)
{
	char display[64];
	Menu menu = new Menu(MenuHandler_TasSettings, MENU_ACTIONS_DEFAULT);
	menu.SetTitle("%T\n ", "TasSettings", client);

	int style = Shavit_GetBhopStyle(client);

	bool autostrafe_allowed = Shavit_GetStyleSettingBool(style, "autostrafe");
	bool autostrafe = (gB_Autostrafer[client] && autostrafe_allowed);
	FormatEx(display, sizeof(display), "[%s] %T", autostrafe ? "＋":"－", "Autostrafer", client);
	menu.AddItem("autostrafe", display, autostrafe_allowed ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	bool autojumponstart_allowed = Shavit_GetStyleSettingBool(style, "autojumponstart");
	bool autojumponstart = (gB_AutoJumpOnStart[client] && autojumponstart_allowed);
	FormatEx(display, sizeof(display), "[%s] %T", autojumponstart ? "＋":"－", "AutoJumpOnStart", client);
	menu.AddItem("autojump", display, autojumponstart_allowed ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	bool autoprestrafe_allowed = Shavit_GetStyleSettingBool(style, "autoprestrafe");
	bool autoprestrafe = (gB_Prestrafe[client] && autoprestrafe_allowed);
	FormatEx(display, sizeof(display), "[%s] %T\n ", autoprestrafe ? "＋":"－", "AutoPrestrafe", client);
	menu.AddItem("prestrafe", display, autoprestrafe_allowed ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	AutostrafeType tastype = view_as<AutostrafeType>(Shavit_GetStyleSettingInt(style, "autostrafe"));
	bool tastype_editable = (tastype == AutostrafeType_Any);
	tastype = tastype_editable ? gI_Type[client] : tastype;

	FormatEx(display, sizeof(display), "%T: %T\n ", "Autostrafer_type", client,
		(tastype == AutostrafeType_Disabled ? "TASDisabled" : (tastype == AutostrafeType_1Tick ? "Autostrafer_1tick" : (tastype == AutostrafeType_Autogain ? "Autostrafer_autogain" : tastype == AutostrafeType_Basic ? "Autostrafer_basic" : "Autostrafer_autogain_nsl"))), client);
	menu.AddItem("type", display, (tastype_editable ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));

	bool tas_timescale = (Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(client), "tas_timescale") == -1.0);

	float ts = Shavit_GetClientTimescale(client);
	char buf[10];
	PrettyishTimescale(buf, sizeof(buf), ts, 0.1, 1.0, 0.0);
	FormatEx(display, sizeof(display), "--%T\n%T: %s", "Timescale", client, "CurrentTimescale", client, buf);
	menu.AddItem("tsminus", display, (tas_timescale && ts > 0.1) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FormatEx(display, sizeof(display), "++%T\n ", "Timescale", client);
	menu.AddItem("tsplus", display, (tas_timescale && ts != 1.0) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	bool edgejump_allowed = Shavit_GetStyleSettingBool(style, "edgejump");
	bool edgejump = (gB_EdgeJump[client] && edgejump_allowed);
	FormatEx(display, sizeof(display), "[%s] %T", edgejump ? "＋":"－", "EdgeJump", client);
	menu.AddItem("edgejump", display, edgejump_allowed ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	AutostrafeOverride ov = gI_Override[client];
	FormatEx(display, sizeof(display), "%T: %T", "AutostrafeOverride", client,
		(ov == AutostrafeOverride_Normal ? "AutostrafeOverride_Normal" : (ov == AutostrafeOverride_Surf ? "AutostrafeOverride_Surf" : (ov == AutostrafeOverride_Surf_W_Okay ? "AutostrafeOverride_Surf_W_Okay" : "AutostrafeOverride_All"))), client);
	menu.AddItem("override", display);

	FormatEx(display, sizeof(display), "[%s] %T", gB_AutogainBasicStrafer[client] ? "＋":"－", "AutogainBasicStrafer", client);
	menu.AddItem("autogainbss", display,
		(tastype == AutostrafeType_Autogain || tastype == AutostrafeType_AutogainNoSpeedLoss) ?
		ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	if (Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), "segments"))
	{
		menu.ExitBackButton = true;
	}
	else
	{
		menu.ExitButton = true;
	}

	menu.DisplayAt(client, pos, MENU_TIME_FOREVER);
}

public int MenuHandler_TasSettings(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, sizeof(info));

		if (StrEqual(info, "autostrafe"))
		{
			gB_Autostrafer[param1] = !gB_Autostrafer[param1];
		}
		else if (StrEqual(info, "autojump"))
		{
			gB_AutoJumpOnStart[param1] = !gB_AutoJumpOnStart[param1];
		}
		else if (StrEqual(info, "edgejump"))
		{
			gB_EdgeJump[param1] = !gB_EdgeJump[param1];
		}
		else if (StrEqual(info, "prestrafe"))
		{
			gB_Prestrafe[param1] = !gB_Prestrafe[param1];
		}
		else if (StrEqual(info, "autogainbss"))
		{
			gB_AutogainBasicStrafer[param1] = !gB_AutogainBasicStrafer[param1];
		}
		else if (StrEqual(info, "type"))
		{
			AutostrafeType tastype = view_as<AutostrafeType>(Shavit_GetStyleSettingInt(Shavit_GetBhopStyle(param1), "autostrafe"));

			if (tastype == AutostrafeType_Any)
			{
				gI_Type[param1] = (gI_Type[param1] == AutostrafeType_1Tick ? AutostrafeType_Autogain : gI_Type[param1] == AutostrafeType_Basic ? AutostrafeType_1Tick : AutostrafeType_Basic);
			}
		}
		else if (StrEqual(info, "override"))
		{
			if (++gI_Override[param1] >= AutostrafeOverride_Size)
			{
				gI_Override[param1] = AutostrafeOverride_Normal;
			}
		}
		else if (StrEqual(info, "tsplus"))
		{
			if (Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(param1), "tas_timescale") == -1.0)
			{
				FakeClientCommand(param1, "sm_tsplus");
			}
		}
		else if (StrEqual(info, "tsminus"))
		{
			if (Shavit_GetStyleSettingFloat(Shavit_GetBhopStyle(param1), "tas_timescale") == -1.0)
			{
				FakeClientCommand(param1, "sm_tsminus");
			}
		}

		OpenTasSettingsMenu(param1, GetMenuSelectionPosition());
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		FakeClientCommandEx(param1, "sm_cp");
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void Command_Toggler_Internal(int client, const char[] asdfcommand, int x)
{
	if (!IsValidClient(client))
	{
		return;
	}

	char command[32];
	strcopy(command, sizeof(command), asdfcommand);

	if (StrEqual(command, "autostrafer"))
	{
		command = "autostrafe";
	}

	if (!StrEqual(command, "autogainbss"))
	{
		if (!Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), command))
		{
			return;
		}
	}

	bool set;
	char translation[32];

	if (StrEqual(command, "autostrafe"))
	{
		set = gB_Autostrafer[client] = (x == -1) ? !gB_Autostrafer[client] : (x != 0);
		translation = "Autostrafer";
	}
	else if (StrEqual(command, "autoprestrafe"))
	{
		set = gB_Prestrafe[client] = (x == -1) ? !gB_Prestrafe[client] : (x != 0);
		translation = "AutoPrestrafe";
	}
	else if (StrEqual(command, "autojumponstart"))
	{
		set = gB_AutoJumpOnStart[client] = (x == -1) ? !gB_AutoJumpOnStart[client] : (x != 0);
		translation = "AutoJumpOnStart";
	}
	else if (StrEqual(command, "edgejump"))
	{
		set = gB_EdgeJump[client] = (x == -1) ? !gB_EdgeJump[client] : (x != 0);
		translation = "EdgeJump";
	}
	else if (StrEqual(command, "autogainbss"))
	{
		set = gB_AutogainBasicStrafer[client] = (x == -1) ? !gB_AutogainBasicStrafer[client] : (x != 0);
		translation = "AutogainBasicStrafer";
	}

	Shavit_StopChatSound();
	Shavit_PrintToChat(client, "%T: %s%T", translation, client, (set ? gS_ChatStrings.sVariable : gS_ChatStrings.sWarning), (set ? "TASEnabled" : "TASDisabled"), client);
}

public Action CommandListener_Toggler(int client, const char[] command, int args)
{
	Command_Toggler_Internal(client, command[1], (command[0] == '+') ? 1 : 0);
	return Plugin_Stop;
}

public Action Command_Toggler(int client, int args)
{
	char command[32];
	GetCmdArg(0, command, sizeof(command));

	int x = -1;

	if (args > 0)
	{
		char arg[5];
		GetCmdArg(1, arg, sizeof(arg));
		x = StringToInt(arg);
	}

	Command_Toggler_Internal(client, command[3], x);
	return Plugin_Handled;
}

public Action Command_TasSettingsMenu(int client, int args)
{
	if (IsValidClient(client))
	{
		OpenTasSettingsMenu(client);
	}

	return Plugin_Handled;
}

// natives
public any Native_SetAutostrafeEnabled(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool value = GetNativeCell(2);
	gB_Autostrafer[client] = value;
	return 0;
}

public any Native_GetAutostrafeEnabled(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return gB_Autostrafer[client];
}

public any Native_SetAutostrafeType(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	AutostrafeType value = view_as<AutostrafeType>(GetNativeCell(2));
	gI_Type[client] = value;
	return 0;
}

public any Native_GetAutostrafeType(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return gI_Type[client];
}

public any Native_SetAutostrafePower(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	float value = GetNativeCell(2);
	g_fPower[client] = value;
	return 0;
}

public any Native_GetAutostrafePower(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return g_fPower[client];
}

public any Native_SetAutostrafeKeyOverride(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	AutostrafeOverride value = view_as<AutostrafeOverride>(GetNativeCell(2));
	gI_Override[client] = value;
	return 0;
}

public any Native_GetAutostrafeKeyOverride(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return gI_Override[client];
}

public any Native_SetAutoPrestrafe(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool value = GetNativeCell(2);
	gB_Prestrafe[client] = value;
	return 0;
}

public any Native_GetAutoPrestrafe(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return gB_Prestrafe[client];
}

public any Native_SetAutoJumpOnStart(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool value = GetNativeCell(2);
	gB_AutoJumpOnStart[client] = value;
	return 0;
}

public any Native_GetAutoJumpOnStart(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return gB_AutoJumpOnStart[client];
}

public any Native_SetEdgeJump(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool value = GetNativeCell(2);
	gB_EdgeJump[client] = value;
	return 0;
}

public any Native_GetEdgeJump(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return gB_EdgeJump[client];
}

public any Native_SetAutogainBasicStrafer(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	bool value = GetNativeCell(2);
	gB_AutogainBasicStrafer[client] = value;
	return 0;
}

public any Native_GetAutogainBasicStrafer(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return gB_AutogainBasicStrafer[client];
}
