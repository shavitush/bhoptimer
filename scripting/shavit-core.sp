/*
 * shavit's Timer - Core
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
#include <sdkhooks>
#include <sdktools>
#include <geoip>
#include <clientprefs>

#undef REQUIRE_PLUGIN
#define USES_STYLE_PROPERTIES
#define USES_STYLE_NAMES
#define USES_STYLE_VELOCITY_LIMITS
#include <shavit>
#include <adminmenu>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

//#define DEBUG

// game type (CS:S/CS:GO)
ServerGame gSG_Type = Game_Unknown; // deperecated and here for backwards compatibility
EngineVersion gEV_Type = Engine_Unknown;

// database handle
Database gH_SQL = null;
bool gB_MySQL = false;

// forwards
Handle gH_Forwards_Start = null;
Handle gH_Forwards_Stop = null;
Handle gH_Forwards_Finish = null;
Handle gH_Forwards_OnRestart = null;
Handle gH_Forwards_OnEnd = null;
Handle gH_Forwards_OnPause = null;
Handle gH_Forwards_OnResume = null;
Handle gH_Forwards_OnStyleChanged = null;

// timer variables
bool gB_TimerEnabled[MAXPLAYERS+1];
float gF_StartTime[MAXPLAYERS+1];
float gF_PauseStartTime[MAXPLAYERS+1];
float gF_PauseTotalTime[MAXPLAYERS+1];
bool gB_ClientPaused[MAXPLAYERS+1];
int gI_Jumps[MAXPLAYERS+1];
BhopStyle gBS_Style[MAXPLAYERS+1];
bool gB_Auto[MAXPLAYERS+1];
bool gB_OnGround[MAXPLAYERS+1];
int gI_ButtonCache[MAXPLAYERS+1];
int gI_Strafes[MAXPLAYERS+1];
float gF_AngleCache[MAXPLAYERS+1];
int gI_TotalMeasures[MAXPLAYERS+1];
int gI_GoodGains[MAXPLAYERS+1];
bool gB_DoubleSteps[MAXPLAYERS+1];
float gF_HSW_Requirement = 0.0;

// cookies
Handle gH_StyleCookie = null;
Handle gH_AutoBhopCookie = null;

// late load
bool gB_Late = false;

// modules
bool gB_Zones = false;

// cvars
ConVar gCV_Autobhop = null;
ConVar gCV_LeftRight = null;
ConVar gCV_Restart = null;
ConVar gCV_Pause = null;
ConVar gCV_NoStaminaReset = null;
ConVar gCV_AllowTimerWithoutZone = null;
ConVar gCV_BlockPreJump = null;
ConVar gCV_NoZAxisSpeed = null;
ConVar gCV_DefaultAA = null;

// table prefix
char gS_MySQLPrefix[32];

// server side
int gI_CachedDefaultAA = 2000;
ConVar sv_airaccelerate = null;

public Plugin myinfo =
{
	name = "[shavit] Core",
	author = "shavit",
	description = "The core for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// get game type
	CreateNative("Shavit_GetGameType", Native_GetGameType);

	// get database handle
	CreateNative("Shavit_GetDB", Native_GetDB);

	// timer natives
	CreateNative("Shavit_StartTimer", Native_StartTimer);
	CreateNative("Shavit_StopTimer", Native_StopTimer);
	CreateNative("Shavit_FinishMap", Native_FinishMap);
	CreateNative("Shavit_GetTimer", Native_GetTimer);
	CreateNative("Shavit_GetClientTime", Native_GetClientTime);
	CreateNative("Shavit_GetClientJumps", Native_GetClientJumps);
	CreateNative("Shavit_GetBhopStyle", Native_GetBhopStyle);
	CreateNative("Shavit_GetTimerStatus", Native_GetTimerStatus);
	CreateNative("Shavit_PauseTimer", Native_PauseTimer);
	CreateNative("Shavit_ResumeTimer", Native_ResumeTimer);
	CreateNative("Shavit_PrintToChat", Native_PrintToChat);
	CreateNative("Shavit_RestartTimer", Native_RestartTimer);
	CreateNative("Shavit_GetStrafeCount", Native_GetStrafeCount);
	CreateNative("Shavit_GetSync", Native_GetSync);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// forwards
	gH_Forwards_Start = CreateGlobalForward("Shavit_OnStart", ET_Event, Param_Cell);
	gH_Forwards_Stop = CreateGlobalForward("Shavit_OnStop", ET_Event, Param_Cell);
	gH_Forwards_Finish = CreateGlobalForward("Shavit_OnFinish", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnRestart = CreateGlobalForward("Shavit_OnRestart", ET_Event, Param_Cell);
	gH_Forwards_OnEnd = CreateGlobalForward("Shavit_OnEnd", ET_Event, Param_Cell);
	gH_Forwards_OnPause = CreateGlobalForward("Shavit_OnPause", ET_Event, Param_Cell);
	gH_Forwards_OnResume = CreateGlobalForward("Shavit_OnResume", ET_Event, Param_Cell);
	gH_Forwards_OnStyleChanged = CreateGlobalForward("Shavit_OnStyleChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);

	// game types
	gEV_Type = GetEngineVersion();

	if(gEV_Type == Engine_CSS)
	{
		gSG_Type = Game_CSS;
		gF_HSW_Requirement = 399.00;
	}

	else if(gEV_Type == Engine_CSGO)
	{
		gSG_Type = Game_CSGO;
		gF_HSW_Requirement = 449.00;
	}

	else
	{
		SetFailState("This plugin was meant to be used in CS:S and CS:GO *only*.");
	}

	// database connections
	SQL_SetPrefix();
	SQL_DBConnect();

	// hooks
	HookEvent("player_jump", Player_Jump);
	HookEvent("player_death", Player_Death);
	HookEvent("player_team", Player_Death);
	HookEvent("player_spawn", Player_Death);

	// commands START
	// style
	RegConsoleCmd("sm_style", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_styles", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_diff", Command_Style, "Choose your bhop style.");
	RegConsoleCmd("sm_difficulty", Command_Style, "Choose your bhop style.");
	gH_StyleCookie = RegClientCookie("shavit_style", "Style cookie", CookieAccess_Protected);

	// timer start
	RegConsoleCmd("sm_s", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_start", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_r", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_restart", Command_StartTimer, "Start your timer.");

	// teleport to end
	RegConsoleCmd("sm_end", Command_TeleportEnd, "Teleport to endzone.");

	// timer stop
	RegConsoleCmd("sm_stop", Command_StopTimer, "Stop your timer.");

	// timer pause / resume
	RegConsoleCmd("sm_pause", Command_TogglePause, "Toggle pause.");
	RegConsoleCmd("sm_unpause", Command_TogglePause, "Toggle pause.");
	RegConsoleCmd("sm_resume", Command_TogglePause, "Toggle pause");

	// autobhop toggle
	RegConsoleCmd("sm_auto", Command_AutoBhop, "Toggle autobhop.");
	RegConsoleCmd("sm_autobhop", Command_AutoBhop, "Toggle autobhop.");
	gH_AutoBhopCookie = RegClientCookie("shavit_autobhop", "Autobhop cookie", CookieAccess_Protected);

	// doublstep fixer
	AddCommandListener(Command_DoubleStep, "+ds");
	AddCommandListener(Command_DoubleStep, "-ds");
	// commands END

	#if defined DEBUG
	RegConsoleCmd("sm_finishtest", Command_FinishTest);
	#endif

	CreateConVar("shavit_version", SHAVIT_VERSION, "Plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);

	gCV_Autobhop = CreateConVar("shavit_core_autobhop", "1", "Enable autobhop?\nWill be forced to not work if STYLE_AUTOBHOP is not defined for a style!", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	gCV_LeftRight = CreateConVar("shavit_core_blockleftright", "1", "Block +left/right?", 0, true, 0.0, true, 1.0);
	gCV_Restart = CreateConVar("shavit_core_restart", "1", "Allow commands that restart the timer?", 0, true, 0.0, true, 1.0);
	gCV_Pause = CreateConVar("shavit_core_pause", "1", "Allow pausing?", 0, true, 0.0, true, 1.0);
	gCV_NoStaminaReset = CreateConVar("shavit_core_nostaminareset", "1", "Disables the built-in stamina reset.\nAlso known as 'easybhop'.\nWill be forced to not work if STYLE_EASYBHOP is not defined for a style!", 0, true, 0.0, true, 1.0);
	gCV_AllowTimerWithoutZone = CreateConVar("shavit_core_timernozone", "0", "Allow the timer to start if there's no start zone?", 0, true, 0.0, true, 1.0);
	gCV_BlockPreJump = CreateConVar("shavit_core_blockprejump", "1", "Prevents jumping in the start zone.", 0, true, 0.0, true, 1.0);
	gCV_NoZAxisSpeed = CreateConVar("shavit_core_nozaxisspeed", "1", "Don't start timer if vertical speed exists (btimes style).", 0, true, 0.0, true, 1.0);
	gCV_DefaultAA = CreateConVar("shavit_core_defaultaa", "1000", "Airaccelerate value to use for non-100AA styles, overrides sv_airaccelerate.\nRestart the server after you change this value to not cause issues.");

	AutoExecConfig();

	sv_airaccelerate = FindConVar("sv_airaccelerate");
	sv_airaccelerate.IntValue = gI_CachedDefaultAA = gCV_DefaultAA.IntValue;
	sv_airaccelerate.Flags &= ~FCVAR_NOTIFY;

	// late
	if(gB_Late)
	{
		OnAdminMenuReady(null);

		for(int i = 1; i <= MaxClients; i++)
		{
			OnClientPutInServer(i);
		}
	}

	gB_Zones = LibraryExists("shavit-zones");
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	Handle hTopMenu = INVALID_HANDLE;

	if(LibraryExists("adminmenu") && ((hTopMenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		AddToTopMenu(hTopMenu, "Timer Commands", TopMenuObject_Category, CategoryHandler, INVALID_TOPMENUOBJECT);
	}
}

public void CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayTitle)
	{
		strcopy(buffer, maxlength, "Timer Commands:");
	}

	else if(action == TopMenuAction_DisplayOption)
	{
		strcopy(buffer, maxlength, "Timer Commands");
	}
}

public void OnMapStart()
{
	// cvar forcing
	ConVar cvBhopping = FindConVar("sv_enablebunnyhopping");
	cvBhopping.BoolValue = true;

	ConVar cvAA = FindConVar("sv_airaccelerate");
	cvAA.IntValue = 2000;
}

public Action Command_StartTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gCV_Restart.BoolValue)
	{
		if(args != -1)
		{
			char[] sCommand = new char[16];
			GetCmdArg(0, sCommand, 16);

			Shavit_PrintToChat(client, "The command (\x03%s\x01) is disabled.", sCommand);
		}

		return Plugin_Handled;
	}

	if(gCV_AllowTimerWithoutZone.BoolValue || (gB_Zones && Shavit_ZoneExists(Zone_Start)))
	{
		Call_StartForward(gH_Forwards_OnRestart);
		Call_PushCell(client);
		Call_Finish();

		StartTimer(client);
	}

	else
	{
		Shavit_PrintToChat(client, "Your timer will not start as a start zone for the map is not defined.");
	}

	return Plugin_Handled;
}

public Action Command_TeleportEnd(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(gB_Zones && Shavit_ZoneExists(Zone_End))
	{
		Shavit_StopTimer(client);
		Call_StartForward(gH_Forwards_OnEnd);
		Call_PushCell(client);
		Call_Finish();
	}

	else
	{
		Shavit_PrintToChat(client, "You can't teleport as an end zone for the map is not defined.");
	}

	return Plugin_Handled;
}

public Action Command_StopTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Shavit_StopTimer(client);

	return Plugin_Handled;
}

public Action Command_TogglePause(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!gCV_Pause.BoolValue)
	{
		char[] sCommand = new char[16];
		GetCmdArg(0, sCommand, 16);

		Shavit_PrintToChat(client, "The command (\x03%s\x01) is disabled.", sCommand);

		return Plugin_Handled;
	}

	if(!(GetEntityFlags(client) & FL_ONGROUND))
	{
		Shavit_PrintToChat(client, "You are not allowed to pause when not on ground.");

		return Plugin_Handled;
	}

	if(gB_ClientPaused[client])
	{
		ResumeTimer(client);
	}

	else
	{
		PauseTimer(client);
	}

	return Plugin_Handled;
}

#if defined DEBUG
public Action Command_FinishTest(int client, int args)
{
	Shavit_FinishMap(client);

	return Plugin_Handled;
}
#endif

public Action Command_AutoBhop(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gB_Auto[client] = !gB_Auto[client];

	Shavit_PrintToChat(client, "Autobhop %s\x01.", gB_Auto[client]? "\x04enabled":"\x02disabled");

	char[] sAutoBhop = new char[4];
	IntToString(view_as<int>(gB_Auto[client]), sAutoBhop, 4);

	SetClientCookie(client, gH_AutoBhopCookie, sAutoBhop);

	return Plugin_Handled;
}

public Action Command_DoubleStep(int client, const char[] command, int args)
{
	gB_DoubleSteps[client] = (command[0] == '+');

	return Plugin_Handled;
}

public Action Command_Style(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu m = new Menu(StyleMenu_Handler);
	m.SetTitle("Choose a style:");

	for(int i = 0; i < sizeof(gS_BhopStyles); i++)
	{
		char[] sInfo = new char[8];
		IntToString(i, sInfo, 8);

		if(gI_StyleProperties[i] & STYLE_UNRANKED)
		{
			char sDisplay[64];
			FormatEx(sDisplay, 64, "[UNRANKED] %s", gS_BhopStyles[i]);
			m.AddItem(sInfo, sDisplay);
		}

		else
		{
			m.AddItem(sInfo, gS_BhopStyles[i]);
		}

	}

	// should NEVER happen
	if(m.ItemCount == 0)
	{
		m.AddItem("-1", "Nothing");
	}

	m.ExitButton = true;
	m.Display(client, 20);

	return Plugin_Handled;
}

public int StyleMenu_Handler(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] info = new char[16];
		m.GetItem(param2, info, 16);

		BhopStyle style = view_as<BhopStyle>(StringToInt(info));

		ChangeClientStyle(param1, style);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
}

public void ChangeClientStyle(int client, BhopStyle style)
{
	if(!IsValidClient(client))
	{
		return;
	}

	Call_StartForward(gH_Forwards_OnStyleChanged);
	Call_PushCell(client);
	Call_PushCell(gBS_Style[client]);
	Call_PushCell(style);
	Call_Finish();

	gBS_Style[client] = style;

	Shavit_PrintToChat(client, "You have selected to play \x03%s\x01.", gS_BhopStyles[view_as<int>(style)]);

	if(gI_StyleProperties[style] & STYLE_UNRANKED)
	{
		Shavit_PrintToChat(client, "\x02WARNING: \x01This style is unranked. Your times WILL NOT be saved and will be only displayed to you!");
	}

	StopTimer(client);

	if(gCV_AllowTimerWithoutZone.BoolValue || (gB_Zones && Shavit_ZoneExists(Zone_Start)))
	{
		Call_StartForward(gH_Forwards_OnRestart);
		Call_PushCell(client);
		Call_Finish();

		StartTimer(client);
	}

	char[] sStyle = new char[4];
	IntToString(view_as<int>(style), sStyle, 4);

	SetClientCookie(client, gH_StyleCookie, sStyle);
}

public void Player_Jump(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(gB_TimerEnabled[client])
	{
		gI_Jumps[client]++;
	}

	if(gI_StyleProperties[gBS_Style[client]] & STYLE_EASYBHOP && gCV_NoStaminaReset.BoolValue)
	{
		SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
	}

	if(gI_StyleProperties[gBS_Style[client]] & STYLE_LOWGRAV)
	{
		SetEntityGravity(client, 0.6);
	}

	if(gI_StyleProperties[gBS_Style[client]] & STYLE_SLOWMO)
	{
		SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 0.5);
	}
}

public void Player_Death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	ResumeTimer(client);
	StopTimer(client);
}

public int Native_GetGameType(Handle handler, int numParams)
{
	return view_as<int>(gSG_Type);
}

public int Native_GetDB(Handle handler, int numParams)
{
	SetNativeCellRef(1, gH_SQL);
}

public int Native_GetTimer(Handle handler, int numParams)
{
	// 1 - client
	int client = GetNativeCell(1);

	// 2 - time
	float time = CalculateTime(client);
	SetNativeCellRef(2, time);
	SetNativeCellRef(3, gI_Jumps[client]);
	SetNativeCellRef(4, gBS_Style[client]);
	SetNativeCellRef(5, gB_TimerEnabled[client]);
}

public int Native_GetClientTime(Handle handler, int numParams)
{
	// 1 - client
	int client = GetNativeCell(1);

	// 2 - time
	return view_as<int>(CalculateTime(client));
}

public int Native_GetClientJumps(Handle handler, int numParams)
{
	return gI_Jumps[GetNativeCell(1)];
}

public int Native_GetBhopStyle(Handle handler, int numParams)
{
	return view_as<int>(gBS_Style[GetNativeCell(1)]);
}

public int Native_GetTimerStatus(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	if(!gB_TimerEnabled[client])
	{
		return view_as<int>(Timer_Stopped);
	}

	else if(gB_ClientPaused[client])
	{
		return view_as<int>(Timer_Paused);
	}

	return view_as<int>(Timer_Running);
}

public int Native_StartTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	if(!IsFakeClient(client))
	{
		StartTimer(client);
	}
}

public int Native_StopTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	StopTimer(client);

	Call_StartForward(gH_Forwards_Stop);
	Call_PushCell(client);
	Call_Finish();
}

public int Native_FinishMap(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	Call_StartForward(gH_Forwards_Finish);
	Call_PushCell(client);
	Call_PushCell(view_as<int>(gBS_Style[client]));
	Call_PushCell(CalculateTime(client));
	Call_PushCell(gI_Jumps[client]);
	Call_PushCell(gI_Strafes[client]);
	Call_PushCell((gI_StyleProperties[gBS_Style[client]] & STYLE_MEASURESYNC)? (gI_GoodGains[client] == 0)? 0.0:(gI_GoodGains[client] / float(gI_TotalMeasures[client]) * 100.0):-1.0);
	Call_Finish();

	StopTimer(client);
}

public int Native_PauseTimer(Handle handler, int numParams)
{
	PauseTimer(GetNativeCell(1));
}

public int Native_ResumeTimer(Handle handler, int numParams)
{
	ResumeTimer(GetNativeCell(1));
}

public int Native_PrintToChat(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	int written = 0; // useless?

	char[] buffer = new char[255];
	FormatNativeString(0, 2, 3, 255, written, buffer);

	PrintToChat(client, "%s%s %s", (gEV_Type == Engine_CSS)? "":" ", PREFIX, buffer);

	return;
}

public int Native_RestartTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	Call_StartForward(gH_Forwards_OnRestart);
	Call_PushCell(client);
	Call_Finish();

	StartTimer(client);

	return;
}

public int Native_GetStrafeCount(Handle handler, int numParams)
{
	return gI_Strafes[GetNativeCell(1)];
}

public int Native_GetSync(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	return view_as<int>((gI_StyleProperties[gBS_Style[client]] & STYLE_MEASURESYNC)? (gI_GoodGains[client] == 0)? 0.0:(gI_GoodGains[client] / float(gI_TotalMeasures[client]) * 100.0):-1.0);
}

public void StartTimer(int client)
{
	if(!IsValidClient(client, true) || GetClientTeam(client) < 2 || IsFakeClient(client))
	{
		return;
	}

	float fSpeed[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);

	if(!gCV_NoZAxisSpeed.BoolValue || gI_StyleProperties[gBS_Style[client]] & STYLE_PRESPEED || fSpeed[2] == 0.0 || SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)) <= 280.0)
	{
		gF_StartTime[client] = GetEngineTime();
		gB_TimerEnabled[client] = true;
		gI_Strafes[client] = 0;
		gI_Jumps[client] = 0;
		gI_TotalMeasures[client] = 0;
		gI_GoodGains[client] = 0;

		Call_StartForward(gH_Forwards_Start);
		Call_PushCell(client);
		Call_Finish();
	}

	gF_PauseTotalTime[client] = 0.0;
	gB_ClientPaused[client] = false;

	SetEntityGravity(client, (gI_StyleProperties[gBS_Style[client]] & STYLE_LOWGRAV)? 0.6:0.0);
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", (gI_StyleProperties[gBS_Style[client]] & STYLE_SLOWMO)? 0.5:1.0);
}

public void StopTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	gB_TimerEnabled[client] = false;
	gI_Jumps[client] = 0;
	gF_StartTime[client] = 0.0;
	gF_PauseTotalTime[client] = 0.0;
	gB_ClientPaused[client] = false;
	gI_Strafes[client] = 0;
	gI_TotalMeasures[client] = 0;
	gI_GoodGains[client] = 0;
}

public void PauseTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	gF_PauseStartTime[client] = GetEngineTime();
	gB_ClientPaused[client] = true;

	Call_StartForward(gH_Forwards_OnPause);
	Call_PushCell(client);
	Call_Finish();
}

public void ResumeTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	gF_PauseTotalTime[client] += GetEngineTime() - gF_PauseStartTime[client];
	gB_ClientPaused[client] = false;

	Call_StartForward(gH_Forwards_OnResume);
	Call_PushCell(client);
	Call_Finish();
}

public float CalculateTime(int client)
{
	float time = 0.0;

	if(!gB_ClientPaused[client])
	{
		time = (GetEngineTime() - gF_StartTime[client] - gF_PauseTotalTime[client]);
	}

	else
	{
		time = (gF_PauseStartTime[client] - gF_StartTime[client] - gF_PauseTotalTime[client]);
	}

	if(gI_StyleProperties[gBS_Style[client]] & STYLE_SLOWMOTIME)
	{
		time /= 2.0;
	}

	return time;
}

public void OnClientDisconnect(int client)
{
	StopTimer(client);
}

public void OnClientCookiesCached(int client)
{
	char[] sCookie = new char[4];
	GetClientCookie(client, gH_AutoBhopCookie, sCookie, 4);
	gB_Auto[client] = (strlen(sCookie) > 0)? view_as<bool>(StringToInt(sCookie)):true;

	GetClientCookie(client, gH_StyleCookie, sCookie, 4);
	gBS_Style[client] = view_as<BhopStyle>(StringToInt(sCookie));
}

public void OnClientPutInServer(int client)
{
	gB_Auto[client] = true;
	gBS_Style[client] = view_as<BhopStyle>(0);

	StopTimer(client);
	gB_DoubleSteps[client] = false;

	if(AreClientCookiesCached(client))
	{
		OnClientCookiesCached(client);
	}

	if(!IsValidClient(client) || IsFakeClient(client) || gH_SQL == null)
	{
		return;
	}

	SDKHook(client, SDKHook_PreThink, PreThink);

	char[] sAuthID3 = new char[32];

	if(!GetClientAuthId(client, AuthId_Steam3, sAuthID3, 32))
	{
		KickClient(client, "Couldn't verify your, or the server's connection to Steam.");

		return;
	}

	char[] sName = new char[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);

	int iLength = ((strlen(sName) * 2) + 1);
	char[] sEscapedName = new char[iLength]; // dynamic arrays! I love you, SourcePawn 1.7!
	gH_SQL.Escape(sName, sEscapedName, iLength);

	char[] sIP = new char[64];
	GetClientIP(client, sIP, 64);

	char[] sCountry = new char[128];

	if(!GeoipCountry(sIP, sCountry, 128))
	{
		strcopy(sCountry, 128, "Local Area Network");
	}

	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "REPLACE INTO %susers (auth, name, country, ip, lastlogin) VALUES ('%s', '%s', '%s', '%s', %d);", gS_MySQLPrefix, sAuthID3, sEscapedName, sCountry, sIP, GetTime());

	gH_SQL.Query(SQL_InsertUser_Callback, sQuery, GetClientSerial(client));
}

public void SQL_InsertUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		int client = GetClientFromSerial(data);

		if(client == 0)
		{
			LogError("Timer error! Failed to insert a disconnected player's data to the table. Reason: %s", error);
		}

		else
		{
			LogError("Timer error! Failed to insert \"%N\"'s data to the table. Reason: %s", client, error);
		}

		return;
	}
}

public void SQL_SetPrefix()
{
	char[] sFile = new char[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/shavit-prefix.txt");

	File fFile = OpenFile(sFile, "r");

	if(fFile == null)
	{
		SetFailState("Cannot open \"configs/shavit-prefix.txt\". Make sure this file exists and that the server has read permissions to it.");
	}

	else
	{
		char[] sLine = new char[PLATFORM_MAX_PATH*2];

		while(fFile.ReadLine(sLine, PLATFORM_MAX_PATH*2))
		{
			TrimString(sLine);
			strcopy(gS_MySQLPrefix, 32, sLine);

			break;
		}
	}

	delete fFile;
}

public void SQL_DBConnect()
{
	if(gH_SQL != null)
	{
		delete gH_SQL;
	}

	char[] sError = new char[255];

	if(SQL_CheckConfig("shavit")) // can't be asynced as we have modules that require this database connection instantly
	{
		gH_SQL = SQL_Connect("shavit", true, sError, 255);

		if(gH_SQL == null)
		{
			SetFailState("Timer startup failed. Reason: %s", sError);
		}
	}

	else
	{
		gH_SQL = SQLite_UseDatabase("shavit", sError, 255);
	}

	// support unicode names
	gH_SQL.SetCharset("utf8");

	char[] sDriver = new char[8];
	gH_SQL.Driver.GetIdentifier(sDriver, 8);
	gB_MySQL = StrEqual(sDriver, "mysql", false);

	char[] sQuery = new char[512];
	FormatEx(sQuery, 512, "CREATE TABLE IF NOT EXISTS `%susers` (`auth` VARCHAR(32) NOT NULL, `name` VARCHAR(32), `country` VARCHAR(128), `ip` VARCHAR(64), `lastlogin` %s NOT NULL DEFAULT -1, `points` FLOAT NOT NULL DEFAULT 0, PRIMARY KEY (`auth`));", gS_MySQLPrefix, gB_MySQL? "INT":"INTEGER");

	// CREATE TABLE IF NOT EXISTS
	gH_SQL.Query(SQL_CreateTable_Callback, sQuery);
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Users' data table creation failed. Reason: %s", error);

		return;
	}

	char[] sQuery = new char[64];
	FormatEx(sQuery, 64, "SELECT lastlogin FROM %susers LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration1_Callback, sQuery, 0, DBPrio_High);

	FormatEx(sQuery, 64, "SELECT points FROM %susers LIMIT 1;", gS_MySQLPrefix);
	gH_SQL.Query(SQL_TableMigration2_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_TableMigration1_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		char[] sQuery = new char[128];
		FormatEx(sQuery, 128, "ALTER TABLE `%susers` ADD %s;", gS_MySQLPrefix, gB_MySQL? "(`lastlogin` INT NOT NULL DEFAULT -1)":"COLUMN `lastlogin` INTEGER NOT NULL DEFAULT -1");
		gH_SQL.Query(SQL_AlterTable1_Callback, sQuery);
	}
}

public void SQL_AlterTable1_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Table alteration 1 (core) failed. Reason: %s", error);

		return;
	}
}

public void SQL_TableMigration2_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		char[] sQuery = new char[128];
		FormatEx(sQuery, 128, "ALTER TABLE `%susers` ADD %s;", gS_MySQLPrefix, gB_MySQL? "(`points` FLOAT NOT NULL DEFAULT 0)":"COLUMN `points` FLOAT NOT NULL DEFAULT 0");
		gH_SQL.Query(SQL_AlterTable2_Callback, sQuery);
	}
}

public void SQL_AlterTable2_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Table alteration 2 (core) failed. Reason: %s", error);

		return;
	}
}

public void PreThink(int client)
{
	sv_airaccelerate.IntValue = (gI_StyleProperties[gBS_Style[client]] & STYLE_100AA)? 100:gI_CachedDefaultAA;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
	if(!IsPlayerAlive(client) || IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	if(gB_ClientPaused[client])
	{
		buttons = 0;
		vel = view_as<float>({0.0, 0.0, 0.0});

		return Plugin_Changed;
	}

	if(!(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_W) && !(gI_ButtonCache[client] & IN_FORWARD) && buttons & IN_FORWARD)
	{
		gI_Strafes[client]++;
	}

	if(!(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_A) && !(gI_ButtonCache[client] & IN_MOVELEFT) && buttons & IN_MOVELEFT)
	{
		gI_Strafes[client]++;
	}

	if(!(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_S) && !(gI_ButtonCache[client] & IN_BACK) && buttons & IN_BACK)
	{
		gI_Strafes[client]++;
	}

	if(!(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_D) && !(gI_ButtonCache[client] & IN_MOVERIGHT) && buttons & IN_MOVERIGHT)
	{
		gI_Strafes[client]++;
	}

	int iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	bool bInWater = (GetEntProp(client, Prop_Send, "m_nWaterLevel") >= 2);
	bool bOnLadder = (GetEntityMoveType(client) == MOVETYPE_LADDER);
	bool bInStart = Shavit_InsideZone(client, Zone_Start);

	if(gCV_LeftRight.BoolValue && gB_TimerEnabled[client] && (!gB_Zones || !bInStart && (buttons & IN_LEFT || buttons & IN_RIGHT)))
	{
		Shavit_StopTimer(client);
		Shavit_PrintToChat(client, "I've stopped your timer for using +left/+right. No cheating!");
	}

	// key blocking
	if(!Shavit_InsideZone(client, Zone_Freestyle))
	{
		// block E
		if(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_USE && buttons & IN_USE)
		{
			buttons &= ~IN_USE;
		}

		if(iGroundEntity == -1)
		{
			if(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_W && (buttons & IN_FORWARD || vel[0] > 0.0))
			{
				vel[0] = 0.0;
				buttons &= ~IN_FORWARD;
			}

			if(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_A && (buttons & IN_MOVELEFT || vel[1] < 0.0))
			{
				vel[1] = 0.0;
				buttons &= ~IN_MOVELEFT;
			}

			if(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_S && (buttons & IN_BACK || vel[0] < 0.0))
			{
				vel[0] = 0.0;
				buttons &= ~IN_BACK;
			}

			if(gI_StyleProperties[gBS_Style[client]] & STYLE_BLOCK_D && (buttons & IN_MOVERIGHT || vel[1] > 0.0))
			{
				vel[1] = 0.0;
				buttons &= ~IN_MOVERIGHT;
			}

			// HSW
			if(gI_StyleProperties[gBS_Style[client]] & STYLE_HSW_ONLY && ((vel[0] < gF_HSW_Requirement && vel[0] > -gF_HSW_Requirement) || !((vel[0] > 0 || buttons & IN_FORWARD) && ((vel[1] < 0 || buttons & IN_MOVELEFT) || (vel[1] > 0 || buttons & IN_MOVERIGHT)))))
			{
				vel[1] = 0.0;
				buttons &= ~IN_MOVELEFT;
				buttons &= ~IN_MOVERIGHT;
			}
		}
	}

	if(bInStart && gCV_BlockPreJump.BoolValue && !(gI_StyleProperties[gBS_Style[client]] & STYLE_PRESPEED))
	{
		if(vel[2] > 0 || buttons & IN_JUMP)
		{
			vel[2] = 0.0;
			buttons &= ~IN_JUMP;
		}
	}

	// autobhop
	if(gI_StyleProperties[gBS_Style[client]] & STYLE_AUTOBHOP && gCV_Autobhop.BoolValue && gB_Auto[client])
	{
		if(buttons & IN_JUMP && iGroundEntity == -1 && !bOnLadder && !bInWater)
		{
			buttons &= ~IN_JUMP;
		}

		else if(gB_DoubleSteps[client] && (iGroundEntity != -1 || bOnLadder || bInWater))
		{
			buttons |= IN_JUMP;
		}
	}

	else if(gB_DoubleSteps[client])
	{
		buttons |= IN_JUMP;
	}

	// velocity limit
	if(iGroundEntity != -1 && gI_StyleProperties[gBS_Style[client]] & STYLE_VEL_LIMIT && gF_VelocityLimit[gBS_Style[client]] != VELOCITY_UNLIMITED && (!gB_Zones || !Shavit_InsideZone(client, Zone_NoVelLimit)))
	{
		gB_OnGround[client] = true;

		float fSpeed[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", fSpeed);

		float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));
		float fScale = gF_VelocityLimit[gBS_Style[client]] / fSpeed_New;

		if(fScale < 1.0)
		{
			ScaleVector(fSpeed, fScale);

			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fSpeed);
		}
	}

	else
	{
		gB_OnGround[client] = false;
	}

	float fAngle = (angles[1] - gF_AngleCache[client]);

	while(fAngle > 180.0)
	{
		fAngle -= 360.0;
	}

	while(fAngle < -180.0)
	{
		fAngle += 360.0;
	}

	if(iGroundEntity == -1 && !(GetEntityFlags(client) & FL_INWATER) && fAngle != 0.0)
	{
		float fAbsVelocity[3];
		GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", fAbsVelocity);

		if(SquareRoot(Pow(fAbsVelocity[0], 2.0) + Pow(fAbsVelocity[1], 2.0)) > 0.0)
		{
			float fTempAngle = angles[1];

			float fAngles[3];
			GetVectorAngles(fAbsVelocity, fAngles);

			if(fTempAngle < 0.0)
			{
				fTempAngle += 360.0;
			}

			float fDirectionAngle = (fTempAngle - fAngles[1]);

			if(fDirectionAngle < 0.0)
			{
				fDirectionAngle = -fDirectionAngle;
			}

			if(fDirectionAngle < 22.5 || fDirectionAngle > 337.5)
			{
				gI_TotalMeasures[client]++;

				if((fAngle > 0.0 && vel[1] < 0.0) || (fAngle < 0.0 && vel[1] > 0.0))
				{
					gI_GoodGains[client]++;
				}
			}
		}
	}

	gI_ButtonCache[client] = buttons;
	gF_AngleCache[client] = angles[1];

	return Plugin_Continue;
}
