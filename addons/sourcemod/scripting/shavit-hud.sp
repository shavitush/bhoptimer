/*
 * shavit's Timer - HUD
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
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <convar_class>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <bhopstats>

#pragma newdecls required
#pragma semicolon 1

// HUD2 - these settings will *disable* elements for the main hud
#define HUD2_TIME				(1 << 0)
#define HUD2_SPEED				(1 << 1)
#define HUD2_JUMPS				(1 << 2)
#define HUD2_STRAFE				(1 << 3)
#define HUD2_SYNC				(1 << 4)
#define HUD2_STYLE				(1 << 5)
#define HUD2_RANK				(1 << 6)
#define HUD2_TRACK				(1 << 7)
#define HUD2_SPLITPB			(1 << 8)
#define HUD2_MAPTIER			(1 << 9)
#define HUD2_TIMEDIFFERENCE		(1 << 10)
#define HUD2_PERFS				(1 << 11)
#define HUD2_TOPLEFT_RANK		(1 << 12)

#define HUD_DEFAULT				(HUD_MASTER|HUD_CENTER|HUD_ZONEHUD|HUD_OBSERVE|HUD_TOPLEFT|HUD_SYNC|HUD_TIMELEFT|HUD_2DVEL|HUD_SPECTATORS)
#define HUD_DEFAULT2			(HUD2_PERFS)

#define MAX_HINT_SIZE 225

enum ZoneHUD
{
	ZoneHUD_None,
	ZoneHUD_Start,
	ZoneHUD_End
};

enum struct huddata_t
{
	int iTarget;
	float fTime;
	int iSpeed;
	int iStyle;
	int iTrack;
	int iJumps;
	int iStrafes;
	int iRank;
	float fSync;
	float fPB;
	float fWR;
	bool bReplay;
	bool bPractice;
	TimerStatus iTimerStatus;
	ZoneHUD iZoneHUD;
}

enum struct color_t
{
	int r;
	int g;
	int b;
}

// game type (CS:S/CS:GO/TF2)
EngineVersion gEV_Type = Engine_Unknown;

// forwards
Handle gH_Forwards_OnTopLeftHUD = null;

// modules
bool gB_Replay = false;
bool gB_Zones = false;
bool gB_Sounds = false;
bool gB_Rankings = false;
bool gB_BhopStats = false;

// cache
int gI_Cycle = 0;
color_t gI_Gradient;
int gI_GradientDirection = -1;
int gI_Styles = 0;
char gS_Map[160];

Handle gH_HUDCookie = null;
Handle gH_HUDCookieMain = null;
int gI_HUDSettings[MAXPLAYERS+1];
int gI_HUD2Settings[MAXPLAYERS+1];
int gI_LastScrollCount[MAXPLAYERS+1];
int gI_ScrollCount[MAXPLAYERS+1];
int gI_Buttons[MAXPLAYERS+1];
float gF_ConnectTime[MAXPLAYERS+1];
bool gB_FirstPrint[MAXPLAYERS+1];
int gI_PreviousSpeed[MAXPLAYERS+1];
int gI_ZoneSpeedLimit[MAXPLAYERS+1];

bool gB_Late = false;

// hud handle
Handle gH_HUD = null;

// plugin cvars
Convar gCV_GradientStepSize = null;
Convar gCV_TicksPerUpdate = null;
Convar gCV_SpectatorList = null;
Convar gCV_UseHUDFix = null;
Convar gCV_SpecNameSymbolLength = null;
Convar gCV_DefaultHUD = null;
Convar gCV_DefaultHUD2 = null;
Convar gCV_EnableDynamicTimeDifference = null;

// timer settings
stylestrings_t gS_StyleStrings[STYLE_LIMIT];
chatstrings_t gS_ChatStrings;

public Plugin myinfo =
{
	name = "[shavit] HUD",
	author = "shavit",
	description = "HUD for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// forwards
	gH_Forwards_OnTopLeftHUD = CreateGlobalForward("Shavit_OnTopLeftHUD", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);

	// natives
	CreateNative("Shavit_ForceHUDUpdate", Native_ForceHUDUpdate);
	CreateNative("Shavit_GetHUDSettings", Native_GetHUDSettings);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-hud");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-hud.phrases");

	// game-specific
	gEV_Type = GetEngineVersion();

	if(gEV_Type == Engine_TF2)
	{
		HookEvent("player_changeclass", Player_ChangeClass);
		HookEvent("player_team", Player_ChangeClass);
		HookEvent("teamplay_round_start", Teamplay_Round_Start);
	}

	// prevent errors in case the replay bot isn't loaded
	gB_Replay = LibraryExists("shavit-replay");
	gB_Zones = LibraryExists("shavit-zones");
	gB_Sounds = LibraryExists("shavit-sounds");
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_BhopStats = LibraryExists("bhopstats");

	// HUD handle
	gH_HUD = CreateHudSynchronizer();

	// plugin convars
	gCV_GradientStepSize = new Convar("shavit_hud_gradientstepsize", "15", "How fast should the start/end HUD gradient be?\nThe number is the amount of color change per 0.1 seconds.\nThe higher the number the faster the gradient.", 0, true, 1.0, true, 255.0);
	gCV_TicksPerUpdate = new Convar("shavit_hud_ticksperupdate", "5", "How often (in ticks) should the HUD update?\nPlay around with this value until you find the best for your server.\nThe maximum value is your tickrate.", 0, true, 1.0, true, (1.0 / GetTickInterval()));
	gCV_SpectatorList = new Convar("shavit_hud_speclist", "1", "Who to show in the specators list?\n0 - everyone\n1 - all admins (admin_speclisthide override to bypass)\n2 - players you can target", 0, true, 0.0, true, 2.0);
	gCV_UseHUDFix = new Convar("shavit_hud_csgofix", "1", "Apply the csgo color fix to the center hud?\nThis will add a dollar sign and block sourcemod hooks to hint message", 0, true, 0.0, true, 1.0);
	gCV_EnableDynamicTimeDifference = new Convar("shavit_hud_timedifference", "0", "Enabled dynamic time differences in the hud", 0, true, 0.0, true, 1.0);
	gCV_SpecNameSymbolLength = new Convar("shavit_hud_specnamesymbollength", "32", "Maximum player name length that should be displayed in spectators panel", 0, true, 0.0, true, float(MAX_NAME_LENGTH));

	char defaultHUD[8];
	IntToString(HUD_DEFAULT, defaultHUD, 8);
	gCV_DefaultHUD = new Convar("shavit_hud_default", defaultHUD, "Default HUD settings as a bitflag\n"
		..."HUD_MASTER				1\n"
		..."HUD_CENTER				2\n"
		..."HUD_ZONEHUD				4\n"
		..."HUD_OBSERVE				8\n"
		..."HUD_SPECTATORS			16\n"
		..."HUD_KEYOVERLAY			32\n"
		..."HUD_HIDEWEAPON			64\n"
		..."HUD_TOPLEFT				128\n"
		..."HUD_SYNC					256\n"
		..."HUD_TIMELEFT				512\n"
		..."HUD_2DVEL				1024\n"
		..."HUD_NOSOUNDS				2048\n"
		..."HUD_NOPRACALERT			4096\n");
		
	IntToString(HUD_DEFAULT2, defaultHUD, 8);
	gCV_DefaultHUD2 = new Convar("shavit_hud2_default", defaultHUD, "Default HUD2 settings as a bitflag\n"
		..."HUD2_TIME				1\n"
		..."HUD2_SPEED				2\n"
		..."HUD2_JUMPS				4\n"
		..."HUD2_STRAFE				8\n"
		..."HUD2_SYNC				16\n"
		..."HUD2_STYLE				32\n"
		..."HUD2_RANK				64\n"
		..."HUD2_TRACK				128\n"
		..."HUD2_SPLITPB				256\n"
		..."HUD2_MAPTIER				512\n"
		..."HUD2_TIMEDIFFERENCE		1024\n"
		..."HUD2_PERFS				2048\n"
		..."HUD2_TOPLEFT_RANK				4096");

	Convar.AutoExecConfig();

	// commands
	RegConsoleCmd("sm_hud", Command_HUD, "Opens the HUD settings menu.");
	RegConsoleCmd("sm_options", Command_HUD, "Opens the HUD settings menu. (alias for sm_hud)");

	// hud togglers
	RegConsoleCmd("sm_keys", Command_Keys, "Toggles key display.");
	RegConsoleCmd("sm_showkeys", Command_Keys, "Toggles key display. (alias for sm_keys)");
	RegConsoleCmd("sm_showmykeys", Command_Keys, "Toggles key display. (alias for sm_keys)");

	RegConsoleCmd("sm_master", Command_Master, "Toggles HUD.");
	RegConsoleCmd("sm_masterhud", Command_Master, "Toggles HUD. (alias for sm_master)");

	RegConsoleCmd("sm_center", Command_Center, "Toggles center text HUD.");
	RegConsoleCmd("sm_centerhud", Command_Center, "Toggles center text HUD. (alias for sm_center)");

	RegConsoleCmd("sm_zonehud", Command_ZoneHUD, "Toggles zone HUD.");

	RegConsoleCmd("sm_hideweapon", Command_HideWeapon, "Toggles weapon hiding.");
	RegConsoleCmd("sm_hideweap", Command_HideWeapon, "Toggles weapon hiding. (alias for sm_hideweapon)");
	RegConsoleCmd("sm_hidewep", Command_HideWeapon, "Toggles weapon hiding. (alias for sm_hideweapon)");

	RegConsoleCmd("sm_truevel", Command_TrueVel, "Toggles 2D ('true') velocity.");
	RegConsoleCmd("sm_truvel", Command_TrueVel, "Toggles 2D ('true') velocity. (alias for sm_truevel)");
	RegConsoleCmd("sm_2dvel", Command_TrueVel, "Toggles 2D ('true') velocity. (alias for sm_truevel)");

	// cookies
	gH_HUDCookie = RegClientCookie("shavit_hud_setting", "HUD settings", CookieAccess_Protected);
	gH_HUDCookieMain = RegClientCookie("shavit_hud_settingmain", "HUD settings for hint text.", CookieAccess_Protected);

	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);

				if(AreClientCookiesCached(i) && !IsFakeClient(i))
				{
					OnClientCookiesCached(i);
				}
			}
		}
	}
}

public void OnMapStart()
{
	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
		Shavit_OnChatConfigLoaded();
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = true;
	}

	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = true;
	}

	else if(StrEqual(name, "shavit-sounds"))
	{
		gB_Sounds = true;
	}

	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}

	else if(StrEqual(name, "bhopstats"))
	{
		gB_BhopStats = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = false;
	}

	else if(StrEqual(name, "shavit-zones"))
	{
		gB_Zones = false;
	}

	else if(StrEqual(name, "shavit-sounds"))
	{
		gB_Sounds = false;
	}

	else if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}

	else if(StrEqual(name, "bhopstats"))
	{
		gB_BhopStats = false;
	}
}

public void OnConfigsExecuted()
{
	ConVar sv_hudhint_sound = FindConVar("sv_hudhint_sound");

	if(sv_hudhint_sound != null)
	{
		sv_hudhint_sound.SetBool(false);
	}
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	gI_Styles = styles;

	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i].sStyleName, sizeof(stylestrings_t::sStyleName));
		Shavit_GetStyleStrings(i, sHTMLColor, gS_StyleStrings[i].sHTMLColor, sizeof(stylestrings_t::sHTMLColor));
	}
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style, stylesettings_t stylsettings)
{
	gI_Buttons[client] = buttons;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(i == client || (IsValidClient(i) && GetHUDTarget(i) == client))
		{
			TriggerHUDUpdate(i, true);
		}
	}

	return Plugin_Continue;
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStrings(sMessagePrefix, gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix));
	Shavit_GetChatStrings(sMessageText, gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	Shavit_GetChatStrings(sMessageWarning, gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning));
	Shavit_GetChatStrings(sMessageVariable, gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
	Shavit_GetChatStrings(sMessageVariable2, gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2));
	Shavit_GetChatStrings(sMessageStyle, gS_ChatStrings.sStyle, sizeof(chatstrings_t::sStyle));
}

public void OnClientPutInServer(int client)
{
	gI_LastScrollCount[client] = 0;
	gI_ScrollCount[client] = 0;
	gB_FirstPrint[client] = false;

	if(IsFakeClient(client))
	{
		SDKHook(client, SDKHook_PostThinkPost, PostThinkPost);
	}
}

public void PostThinkPost(int client)
{
	int buttons = GetClientButtons(client);

	if(gI_Buttons[client] != buttons)
	{
		gI_Buttons[client] = buttons;

		for(int i = 1; i <= MaxClients; i++)
		{
			if(i != client && (IsValidClient(i) && GetHUDTarget(i) == client))
			{
				TriggerHUDUpdate(i, true);
			}
		}
	}
}

public void OnClientCookiesCached(int client)
{
	char sHUDSettings[8];
	GetClientCookie(client, gH_HUDCookie, sHUDSettings, 8);

	if(strlen(sHUDSettings) == 0)
	{
		gCV_DefaultHUD.GetString(sHUDSettings, 8);

		SetClientCookie(client, gH_HUDCookie, sHUDSettings);
		gI_HUDSettings[client] = gCV_DefaultHUD.IntValue;
	}

	else
	{
		gI_HUDSettings[client] = StringToInt(sHUDSettings);
	}

	GetClientCookie(client, gH_HUDCookieMain, sHUDSettings, 8);

	if(strlen(sHUDSettings) == 0)
	{
		gCV_DefaultHUD2.GetString(sHUDSettings, 8);

		SetClientCookie(client, gH_HUDCookieMain, sHUDSettings);
		gI_HUD2Settings[client] = gCV_DefaultHUD2.IntValue;
	}

	else
	{
		gI_HUD2Settings[client] = StringToInt(sHUDSettings);
	}
}

public void Player_ChangeClass(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if((gI_HUDSettings[client] & HUD_MASTER) > 0 && (gI_HUDSettings[client] & HUD_CENTER) > 0)
	{
		CreateTimer(0.5, Timer_FillerHintText, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void Teamplay_Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.5, Timer_FillerHintTextAll, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_FillerHintTextAll(Handle timer, any data)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			FillerHintText(i);
		}
	}

	return Plugin_Stop;
}

public Action Timer_FillerHintText(Handle timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client != 0)
	{
		FillerHintText(client);
	}

	return Plugin_Stop;
}

void FillerHintText(int client)
{
	PrintHintText(client, "...");
	gF_ConnectTime[client] = GetEngineTime();
	gB_FirstPrint[client] = true;
}

void ToggleHUD(int client, int hud, bool chat)
{
	if(!(1 <= client <= MaxClients))
	{
		return;
	}

	char sCookie[16];
	gI_HUDSettings[client] ^= hud;
	IntToString(gI_HUDSettings[client], sCookie, 16);
	SetClientCookie(client, gH_HUDCookie, sCookie);

	if(chat)
	{
		char sHUDSetting[64];

		switch(hud)
		{
			case HUD_MASTER: FormatEx(sHUDSetting, 64, "%T", "HudMaster", client);
			case HUD_CENTER: FormatEx(sHUDSetting, 64, "%T", "HudCenter", client);
			case HUD_ZONEHUD: FormatEx(sHUDSetting, 64, "%T", "HudZoneHud", client);
			case HUD_OBSERVE: FormatEx(sHUDSetting, 64, "%T", "HudObserve", client);
			case HUD_SPECTATORS: FormatEx(sHUDSetting, 64, "%T", "HudSpectators", client);
			case HUD_KEYOVERLAY: FormatEx(sHUDSetting, 64, "%T", "HudKeyOverlay", client);
			case HUD_HIDEWEAPON: FormatEx(sHUDSetting, 64, "%T", "HudHideWeapon", client);
			case HUD_TOPLEFT: FormatEx(sHUDSetting, 64, "%T", "HudTopLeft", client);
			case HUD_SYNC: FormatEx(sHUDSetting, 64, "%T", "HudSync", client);
			case HUD_TIMELEFT: FormatEx(sHUDSetting, 64, "%T", "HudTimeLeft", client);
			case HUD_2DVEL: FormatEx(sHUDSetting, 64, "%T", "Hud2dVel", client);
			case HUD_NOSOUNDS: FormatEx(sHUDSetting, 64, "%T", "HudNoRecordSounds", client);
			case HUD_NOPRACALERT: FormatEx(sHUDSetting, 64, "%T", "HudPracticeModeAlert", client);
		}

		if((gI_HUDSettings[client] & hud) > 0)
		{
			Shavit_PrintToChat(client, "%T", "HudEnabledComponent", client,
				gS_ChatStrings.sVariable, sHUDSetting, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);
		}

		else
		{
			Shavit_PrintToChat(client, "%T", "HudDisabledComponent", client,
				gS_ChatStrings.sVariable, sHUDSetting, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		}
	}
}

public Action Command_Master(int client, int args)
{
	ToggleHUD(client, HUD_MASTER, true);

	return Plugin_Handled;
}

public Action Command_Center(int client, int args)
{
	ToggleHUD(client, HUD_CENTER, true);

	return Plugin_Handled;
}

public Action Command_ZoneHUD(int client, int args)
{
	ToggleHUD(client, HUD_ZONEHUD, true);

	return Plugin_Handled;
}

public Action Command_HideWeapon(int client, int args)
{
	ToggleHUD(client, HUD_HIDEWEAPON, true);

	return Plugin_Handled;
}

public Action Command_TrueVel(int client, int args)
{
	ToggleHUD(client, HUD_2DVEL, true);

	return Plugin_Handled;
}

public Action Command_Keys(int client, int args)
{
	ToggleHUD(client, HUD_KEYOVERLAY, true);

	return Plugin_Handled;
}

public Action Command_HUD(int client, int args)
{
	return ShowHUDMenu(client, 0);
}

Action ShowHUDMenu(int client, int item)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_HUD, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	menu.SetTitle("%T", "HUDMenuTitle", client);

	char sInfo[16];
	char sHudItem[64];
	FormatEx(sInfo, 16, "!%d", HUD_MASTER);
	FormatEx(sHudItem, 64, "%T", "HudMaster", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_CENTER);
	FormatEx(sHudItem, 64, "%T", "HudCenter", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_ZONEHUD);
	FormatEx(sHudItem, 64, "%T", "HudZoneHud", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_OBSERVE);
	FormatEx(sHudItem, 64, "%T", "HudObserve", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_SPECTATORS);
	FormatEx(sHudItem, 64, "%T", "HudSpectators", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_KEYOVERLAY);
	FormatEx(sHudItem, 64, "%T", "HudKeyOverlay", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_HIDEWEAPON);
	FormatEx(sHudItem, 64, "%T", "HudHideWeapon", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_TOPLEFT);
	FormatEx(sHudItem, 64, "%T", "HudTopLeft", client);
	menu.AddItem(sInfo, sHudItem);

	if(IsSource2013(gEV_Type))
	{
		FormatEx(sInfo, 16, "!%d", HUD_SYNC);
		FormatEx(sHudItem, 64, "%T", "HudSync", client);
		menu.AddItem(sInfo, sHudItem);

		FormatEx(sInfo, 16, "!%d", HUD_TIMELEFT);
		FormatEx(sHudItem, 64, "%T", "HudTimeLeft", client);
		menu.AddItem(sInfo, sHudItem);
	}

	FormatEx(sInfo, 16, "!%d", HUD_2DVEL);
	FormatEx(sHudItem, 64, "%T", "Hud2dVel", client);
	menu.AddItem(sInfo, sHudItem);

	if(gB_Sounds)
	{
		FormatEx(sInfo, 16, "!%d", HUD_NOSOUNDS);
		FormatEx(sHudItem, 64, "%T", "HudNoRecordSounds", client);
		menu.AddItem(sInfo, sHudItem);
	}

	FormatEx(sInfo, 16, "!%d", HUD_NOPRACALERT);
	FormatEx(sHudItem, 64, "%T", "HudPracticeModeAlert", client);
	menu.AddItem(sInfo, sHudItem);

	// HUD2 - disables selected elements
	FormatEx(sInfo, 16, "@%d", HUD2_TIME);
	FormatEx(sHudItem, 64, "%T", "HudTimeText", client);
	menu.AddItem(sInfo, sHudItem);

	if(gB_Replay)
	{
		FormatEx(sInfo, 16, "@%d", HUD2_TIMEDIFFERENCE);
		FormatEx(sHudItem, 64, "%T", "HudTimeDifference", client);
		menu.AddItem(sInfo, sHudItem);
	}

	FormatEx(sInfo, 16, "@%d", HUD2_SPEED);
	FormatEx(sHudItem, 64, "%T", "HudSpeedText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_JUMPS);
	FormatEx(sHudItem, 64, "%T", "HudJumpsText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_STRAFE);
	FormatEx(sHudItem, 64, "%T", "HudStrafeText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_SYNC);
	FormatEx(sHudItem, 64, "%T", "HudSync", client);
	menu.AddItem(sInfo, sHudItem);
	
	FormatEx(sInfo, 16, "@%d", HUD2_PERFS);
	FormatEx(sHudItem, 64, "%T", "HudPerfs", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_STYLE);
	FormatEx(sHudItem, 64, "%T", "HudStyleText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_RANK);
	FormatEx(sHudItem, 64, "%T", "HudRankText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_TRACK);
	FormatEx(sHudItem, 64, "%T", "HudTrackText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_SPLITPB);
	FormatEx(sHudItem, 64, "%T", "HudSplitPbText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_TOPLEFT_RANK);
	FormatEx(sHudItem, 64, "%T", "HudTopLeftRankText", client);
	menu.AddItem(sInfo, sHudItem);

	if(gB_Rankings)
	{
		FormatEx(sInfo, 16, "@%d", HUD2_MAPTIER);
		FormatEx(sHudItem, 64, "%T", "HudMapTierText", client);
		menu.AddItem(sInfo, sHudItem);
	}

	menu.ExitButton = true;
	menu.DisplayAt(client, item, 60);

	return Plugin_Handled;
}

public int MenuHandler_HUD(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sCookie[16];
		menu.GetItem(param2, sCookie, 16);

		int type = (sCookie[0] == '!')? 1:2;
		ReplaceString(sCookie, 16, "!", "");
		ReplaceString(sCookie, 16, "@", "");

		int iSelection = StringToInt(sCookie);

		if(type == 1)
		{
			gI_HUDSettings[param1] ^= iSelection;
			IntToString(gI_HUDSettings[param1], sCookie, 16);
			SetClientCookie(param1, gH_HUDCookie, sCookie);
		}

		else
		{
			gI_HUD2Settings[param1] ^= iSelection;
			IntToString(gI_HUD2Settings[param1], sCookie, 16);
			SetClientCookie(param1, gH_HUDCookieMain, sCookie);
		}

		if(gEV_Type == Engine_TF2 && iSelection == HUD_CENTER && (gI_HUDSettings[param1] & HUD_MASTER) > 0)
		{
			FillerHintText(param1);
		}

		ShowHUDMenu(param1, GetMenuSelectionPosition());
	}

	else if(action == MenuAction_DisplayItem)
	{
		char sInfo[16];
		char sDisplay[64];
		int style = 0;
		menu.GetItem(param2, sInfo, 16, style, sDisplay, 64);

		int type = (sInfo[0] == '!')? 1:2;
		ReplaceString(sInfo, 16, "!", "");
		ReplaceString(sInfo, 16, "@", "");

		if(type == 1)
		{
			Format(sDisplay, 64, "[%s] %s", ((gI_HUDSettings[param1] & StringToInt(sInfo)) > 0)? "＋":"－", sDisplay);
		}

		else
		{
			Format(sDisplay, 64, "[%s] %s", ((gI_HUD2Settings[param1] & StringToInt(sInfo)) == 0)? "＋":"－", sDisplay);
		}

		return RedrawMenuItem(sDisplay);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OnGameFrame()
{
	if((GetGameTickCount() % gCV_TicksPerUpdate.IntValue) == 0)
	{
		Cron();
	}
}

void Cron()
{
	if(++gI_Cycle >= 65535)
	{
		gI_Cycle = 0;
	}

	switch(gI_GradientDirection)
	{
		case 0:
		{
			gI_Gradient.b += gCV_GradientStepSize.IntValue;

			if(gI_Gradient.b >= 255)
			{
				gI_Gradient.b = 255;
				gI_GradientDirection = 1;
			}
		}

		case 1:
		{
			gI_Gradient.r -= gCV_GradientStepSize.IntValue;

			if(gI_Gradient.r <= 0)
			{
				gI_Gradient.r = 0;
				gI_GradientDirection = 2;
			}
		}

		case 2:
		{
			gI_Gradient.g += gCV_GradientStepSize.IntValue;

			if(gI_Gradient.g >= 255)
			{
				gI_Gradient.g = 255;
				gI_GradientDirection = 3;
			}
		}

		case 3:
		{
			gI_Gradient.b -= gCV_GradientStepSize.IntValue;

			if(gI_Gradient.b <= 0)
			{
				gI_Gradient.b = 0;
				gI_GradientDirection = 4;
			}
		}

		case 4:
		{
			gI_Gradient.r += gCV_GradientStepSize.IntValue;

			if(gI_Gradient.r >= 255)
			{
				gI_Gradient.r = 255;
				gI_GradientDirection = 5;
			}
		}

		case 5:
		{
			gI_Gradient.g -= gCV_GradientStepSize.IntValue;

			if(gI_Gradient.g <= 0)
			{
				gI_Gradient.g = 0;
				gI_GradientDirection = 0;
			}
		}

		default:
		{
			gI_Gradient.r = 255;
			gI_GradientDirection = 0;
		}
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i) || (gI_HUDSettings[i] & HUD_MASTER) == 0)
		{
			continue;
		}

		if((gI_Cycle % 50) == 0)
		{
			float fSpeed[3];
			GetEntPropVector(GetHUDTarget(i), Prop_Data, "m_vecVelocity", fSpeed);
			gI_PreviousSpeed[i] = RoundToNearest(((gI_HUDSettings[i] & HUD_2DVEL) == 0)? GetVectorLength(fSpeed):(SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0))));
		}
		
		TriggerHUDUpdate(i);
	}
}

void TriggerHUDUpdate(int client, bool keysonly = false) // keysonly because CS:S lags when you send too many usermessages
{
	if(!keysonly)
	{
		UpdateMainHUD(client);
		SetEntProp(client, Prop_Data, "m_bDrawViewmodel", ((gI_HUDSettings[client] & HUD_HIDEWEAPON) > 0)? 0:1);
		UpdateTopLeftHUD(client, true);
	}

	if(IsSource2013(gEV_Type))
	{
		if(!keysonly)
		{
			UpdateKeyHint(client);
		}

		UpdateCenterKeys(client);
	}

	else if(((gI_HUDSettings[client] & HUD_KEYOVERLAY) > 0 || (gI_HUDSettings[client] & HUD_SPECTATORS) > 0) && (!gB_Zones || !Shavit_IsClientCreatingZone(client)) && (GetClientMenu(client, null) == MenuSource_None || GetClientMenu(client, null) == MenuSource_RawPanel))
	{
		bool bShouldDraw = false;
		Panel pHUD = new Panel();

		UpdateKeyOverlay(client, pHUD, bShouldDraw);
		pHUD.DrawItem("", ITEMDRAW_RAWLINE);

		UpdateSpectatorList(client, pHUD, bShouldDraw);

		if(bShouldDraw)
		{
			pHUD.Send(client, PanelHandler_Nothing, 1);
		}

		delete pHUD;
	}
}

void AddHUDLine(char[] buffer, int maxlen, const char[] line, int lines)
{
	if(lines > 0)
	{
		Format(buffer, maxlen, "%s\n%s", buffer, line);
	}
	else
	{
		StrCat(buffer, maxlen, line);
	}
}

void GetRGB(int color, color_t arr)
{
	arr.r = ((color >> 16) & 0xFF);
	arr.g = ((color >> 8) & 0xFF);
	arr.b = (color & 0xFF);
}

int GetHex(color_t color)
{
	return (((color.r & 0xFF) << 16) + ((color.g & 0xFF) << 8) + (color.b & 0xFF));
}

int GetGradient(int start, int end, int steps)
{
	color_t aColorStart;
	GetRGB(start, aColorStart);

	color_t aColorEnd;
	GetRGB(end, aColorEnd);

	color_t aColorGradient;
	aColorGradient.r = (aColorStart.r + RoundToZero((aColorEnd.r - aColorStart.r) * steps / 100.0));
	aColorGradient.g = (aColorStart.g + RoundToZero((aColorEnd.g - aColorStart.g) * steps / 100.0));
	aColorGradient.b = (aColorStart.b + RoundToZero((aColorEnd.b - aColorStart.b) * steps / 100.0));

	return GetHex(aColorGradient);
}

public void Shavit_OnEnterZone(int client, int type, int track, int id, int entity)
{
	if(type == Zone_CustomSpeedLimit)
	{
		gI_ZoneSpeedLimit[client] = Shavit_GetZoneData(id);
	}
}


int AddHUDToBuffer_Source2013(int client, huddata_t data, char[] buffer, int maxlen)
{
	int iLines = 0;
	char sLine[128];

	if(data.bReplay)
	{
		if(data.iStyle != -1 && Shavit_GetReplayStatus(data.iStyle) != Replay_Idle && data.fTime <= data.fWR && Shavit_IsReplayDataLoaded(data.iStyle, data.iTrack))
		{
			char sTrack[32];

			if(data.iTrack != Track_Main && (gI_HUD2Settings[client] & HUD2_TRACK) == 0)
			{
				GetTrackName(client, data.iTrack, sTrack, 32);
				Format(sTrack, 32, "(%s) ", sTrack);
			}

			if((gI_HUD2Settings[client] & HUD2_STYLE) == 0)
			{
				FormatEx(sLine, 128, "%s %s%T", gS_StyleStrings[data.iStyle].sStyleName, sTrack, "ReplayText", client);
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}

			char sPlayerName[MAX_NAME_LENGTH];
			Shavit_GetReplayName(data.iStyle, data.iTrack, sPlayerName, MAX_NAME_LENGTH);
			AddHUDLine(buffer, maxlen, sPlayerName, iLines);
			iLines++;

			if((gI_HUD2Settings[client] & HUD2_TIME) == 0)
			{
				char sTime[32];
				FormatSeconds(data.fTime, sTime, 32, false);

				char sWR[32];
				FormatSeconds(data.fWR, sWR, 32, false);

				FormatEx(sLine, 128, "%s / %s\n(%.1f％)", sTime, sWR, ((data.fTime < 0.0 ? 0.0 : data.fTime / data.fWR) * 100));
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}

			if((gI_HUD2Settings[client] & HUD2_SPEED) == 0)
			{
				FormatEx(sLine, 128, "%d u/s", data.iSpeed);
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}
		}

		else
		{
			FormatEx(sLine, 128, "%T", (gEV_Type == Engine_TF2)? "NoReplayDataTF2":"NoReplayData", client);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		return iLines;
	}

	if((gI_HUDSettings[client] & HUD_ZONEHUD) > 0 && data.iZoneHUD != ZoneHUD_None)
	{
		if(gB_Rankings && (gI_HUD2Settings[client] & HUD2_MAPTIER) == 0)
		{
			FormatEx(sLine, 128, "%T", "HudZoneTier", client, Shavit_GetMapTier(gS_Map));
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if(data.iZoneHUD == ZoneHUD_Start)
		{
			FormatEx(sLine, 128, "%T ", "HudInStartZone", client, data.iSpeed);
		}

		else
		{
			FormatEx(sLine, 128, "%T ", "HudInEndZone", client, data.iSpeed);
		}

		AddHUDLine(buffer, maxlen, sLine, iLines);

		return ++iLines;
	}

	if(data.iTimerStatus != Timer_Stopped)
	{
		if((gI_HUD2Settings[client] & HUD2_STYLE) == 0)
		{
			AddHUDLine(buffer, maxlen, gS_StyleStrings[data.iStyle].sStyleName, iLines);
			iLines++;
		}

		if(data.bPractice || data.iTimerStatus == Timer_Paused)
		{
			FormatEx(sLine, 128, "%T", (data.iTimerStatus == Timer_Paused)? "HudPaused":"HudPracticeMode", client);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if((gI_HUD2Settings[client] & HUD2_TIME) == 0)
		{
			char sTime[32];
			FormatSeconds(data.fTime, sTime, 32, false);

			char sTimeDiff[32];
			
			if(gB_Replay && gCV_EnableDynamicTimeDifference.BoolValue && Shavit_GetReplayFrameCount(data.iStyle, data.iTrack) != 0 && (gI_HUD2Settings[client] & HUD2_TIMEDIFFERENCE) == 0)
			{
				float fClosestReplayTime = Shavit_GetClosestReplayTime(data.iTarget, data.iStyle, data.iTrack);

				if(fClosestReplayTime != -1.0)
				{
					float fDifference = data.fTime - fClosestReplayTime;
					FormatSeconds(fDifference, sTimeDiff, 32, false);
					Format(sTimeDiff, 32, " (%s%s)", (fDifference >= 0.0)? "+":"", sTimeDiff);
				}
			}

			if((gI_HUD2Settings[client] & HUD2_RANK) == 0)
			{
				FormatEx(sLine, 128, "%T: %s%s (%d)", "HudTimeText", client, sTime, sTimeDiff, data.iRank);
			}

			else
			{
				FormatEx(sLine, 128, "%T: %s%s", "HudTimeText", client, sTime, sTimeDiff);
			}
			
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if((gI_HUD2Settings[client] & HUD2_JUMPS) == 0)
		{
			FormatEx(sLine, 128, "%T: %d", "HudJumpsText", client, data.iJumps);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if((gI_HUD2Settings[client] & HUD2_STRAFE) == 0)
		{
			FormatEx(sLine, 128, "%T: %d", "HudStrafeText", client, data.iStrafes);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}
	}

	if((gI_HUD2Settings[client] & HUD2_SPEED) == 0)
	{
		// timer: Speed: %d
		// no timer: straight up number
		if(data.iTimerStatus != Timer_Stopped)
		{
			FormatEx(sLine, 128, "%T: %d", "HudSpeedText", client, data.iSpeed);
		}

		else
		{
			IntToString(data.iSpeed, sLine, 128);
		}

		AddHUDLine(buffer, maxlen, sLine, iLines);
		iLines++;

		char limit[16];
		Shavit_GetStyleSetting(data.iStyle, "velocity_limit", limit, 16);
		if(StringToFloat(limit) > 0.0 && Shavit_InsideZone(data.iTarget, Zone_CustomSpeedLimit, -1))
		{
			if(gI_ZoneSpeedLimit[data.iTarget] == 0)
			{
				FormatEx(sLine, 128, "%T", "HudNoSpeedLimit", data.iTarget);
			}

			else
			{
				FormatEx(sLine, 128, "%T", "HudCustomSpeedLimit", client, gI_ZoneSpeedLimit[data.iTarget]);
			}

			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}
	}

	if(data.iTimerStatus != Timer_Stopped && data.iTrack != Track_Main && (gI_HUD2Settings[client] & HUD2_TRACK) == 0)
	{
		char sTrack[32];
		GetTrackName(client, data.iTrack, sTrack, 32);

		AddHUDLine(buffer, maxlen, sTrack, iLines);
		iLines++;
	}

	return iLines;
}

int AddHUDToBuffer_CSGO(int client, huddata_t data, char[] buffer, int maxlen)
{
	int iLines = 0;
	char sLine[128];

	if(data.bReplay)
	{
		StrCat(buffer, maxlen, "<span class='fontSize-l'>");

		if(data.iStyle != -1 && data.fTime <= data.fWR && Shavit_IsReplayDataLoaded(data.iStyle, data.iTrack))
		{
			char sPlayerName[MAX_NAME_LENGTH];
			Shavit_GetReplayName(data.iStyle, data.iTrack, sPlayerName, MAX_NAME_LENGTH);

			char sTrack[32];

			if(data.iTrack != Track_Main && (gI_HUD2Settings[client] & HUD2_TRACK) == 0)
			{
				GetTrackName(client, data.iTrack, sTrack, 32);
				Format(sTrack, 32, "(%s) ", sTrack);
			}

			FormatEx(sLine, 128, "<u><span color='#%s'>%s %s%T</span></u> <span color='#DB88C2'>%s</span>", gS_StyleStrings[data.iStyle].sHTMLColor, gS_StyleStrings[data.iStyle].sStyleName, sTrack, "ReplayText", client, sPlayerName);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;

			if((gI_HUD2Settings[client] & HUD2_TIME) == 0)
			{	
				char sTime[32];
				FormatSeconds(data.fTime, sTime, 32, false);

				char sWR[32];
				FormatSeconds(data.fWR, sWR, 32, false);

				FormatEx(sLine, 128, "%s / %s (%.1f％)", sTime, sWR, ((data.fTime < 0.0 ? 0.0 : data.fTime / data.fWR) * 100));
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}

			if((gI_HUD2Settings[client] & HUD2_SPEED) == 0)
			{
				FormatEx(sLine, 128, "%d u/s", data.iSpeed);
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}
		}

		else
		{
			FormatEx(sLine, 128, "%T", "NoReplayData", client);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		StrCat(buffer, maxlen, "</span>");

		return iLines;
	}

	if((gI_HUDSettings[client] & HUD_ZONEHUD) > 0 && data.iZoneHUD != ZoneHUD_None)
	{
		char sZoneHUD[64];
		FormatEx(sZoneHUD, 64, "<span class='fontSize-xxl' color='#%06X'>", ((gI_Gradient.r << 16) + (gI_Gradient.g << 8) + (gI_Gradient.b)));
		StrCat(buffer, maxlen, sZoneHUD);

		if(data.iZoneHUD == ZoneHUD_Start)
		{
			if(gB_Rankings && (gI_HUD2Settings[client] & HUD2_MAPTIER) == 0)
			{
				if(data.iTrack == Track_Main)
				{
					FormatEx(sZoneHUD, 32, "%T", "HudZoneTier", client, Shavit_GetMapTier(gS_Map));
				}

				else
				{
					GetTrackName(client, data.iTrack, sZoneHUD, 32);
				}

				Format(sZoneHUD, 32, "\t\t%s\n\n", sZoneHUD);
				AddHUDLine(buffer, maxlen, sZoneHUD, iLines);
				iLines++;
			}
			
			FormatEx(sZoneHUD, 64, "%T</span>", "HudInStartZoneCSGO", client, data.iSpeed);
		}

		else
		{
			FormatEx(sZoneHUD, 64, "%T</span>", "HudInEndZoneCSGO", client, data.iSpeed);
		}
		
		StrCat(buffer, maxlen, sZoneHUD);

		return ++iLines;
	}

	StrCat(buffer, maxlen, "<span class='fontSize-l'>");

	if(data.iTimerStatus != Timer_Stopped)
	{
		if(data.bPractice || data.iTimerStatus == Timer_Paused)
		{
			FormatEx(sLine, 128, "%T", (data.iTimerStatus == Timer_Paused)? "HudPaused":"HudPracticeMode", client);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if(data.iTimerStatus != Timer_Stopped && data.iTrack != Track_Main && (gI_HUD2Settings[client] & HUD2_TRACK) == 0)
		{
			char sTrack[32];
			GetTrackName(client, data.iTrack, sTrack, 32);

			AddHUDLine(buffer, maxlen, sTrack, iLines);
			iLines++;
		}

		if((gI_HUD2Settings[client] & HUD2_TIME) == 0)
		{
			int iColor = 0xFF0000; // red, worse than both pb and wr
			
			if(data.iTimerStatus == Timer_Paused) iColor = 0xA9C5E8; // blue sky
			else if(data.fTime < data.fWR || data.fWR == 0.0) iColor = GetGradient(0x00FF00, 0x96172C, RoundToZero((data.fTime / data.fWR) * 100));
			else if(data.fPB != 0.0 && data.fTime < data.fPB) iColor = 0xFFA500; // orange

			char sTime[32];
			FormatSeconds(data.fTime, sTime, 32, false);
			
			char sTimeDiff[32];
			
			if(gB_Replay && gCV_EnableDynamicTimeDifference.BoolValue && Shavit_GetReplayFrameCount(data.iStyle, data.iTrack) != 0 && (gI_HUD2Settings[client] & HUD2_TIMEDIFFERENCE) == 0)
			{
				float fClosestReplayTime = Shavit_GetClosestReplayTime(data.iTarget, data.iStyle, data.iTrack);

				if(fClosestReplayTime != -1.0)
				{
					float fDifference = data.fTime - fClosestReplayTime;
					FormatSeconds(fDifference, sTimeDiff, 32, false);
					Format(sTimeDiff, 32, " (%s%s)", (fDifference >= 0.0)? "+":"", sTimeDiff);
				}
			}

			if((gI_HUD2Settings[client] & HUD2_RANK) == 0)
			{
				FormatEx(sLine, 128, "<span color='#%06X'>%s%s</span> (#%d)", iColor, sTime, sTimeDiff, data.iRank);
			}

			else
			{
				FormatEx(sLine, 128, "<span color='#%06X'>%s%s</span>", iColor, sTime, sTimeDiff);
			}
			
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}
	}

	if((gI_HUD2Settings[client] & HUD2_SPEED) == 0)
	{
		int iColor = 0xA0FFFF;
		
		if((data.iSpeed - gI_PreviousSpeed[client]) < 0)
		{
			iColor = 0xFFC966;
		}

		FormatEx(sLine, 128, "<span color='#%06X'>%d u/s</span>", iColor, data.iSpeed);
		AddHUDLine(buffer, maxlen, sLine, iLines);
		iLines++;
	}

	if(data.iTimerStatus != Timer_Stopped)
	{
		if((gI_HUD2Settings[client] & HUD2_JUMPS) == 0)
		{
			FormatEx(sLine, 128, "%d %T", data.iJumps, "HudJumpsText", client);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if((gI_HUD2Settings[client] & HUD2_STRAFE) == 0)
		{
			if((gI_HUD2Settings[client] & HUD2_SYNC) == 0)
			{
				FormatEx(sLine, 128, "%d %T (%.1f%%)", data.iStrafes, "HudStrafeText", client, data.fSync);
			}

			else
			{
				FormatEx(sLine, 128, "%d %T", data.iStrafes, "HudStrafeText", client);
			}

			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}
	}

	if((gI_HUD2Settings[client] & HUD2_STYLE) == 0)
	{
		FormatEx(sLine, 128, "<span color='#%s'>%s</span>", gS_StyleStrings[data.iStyle].sHTMLColor, gS_StyleStrings[data.iStyle].sStyleName);
		AddHUDLine(buffer, maxlen, sLine, iLines);
		iLines++;
	}

	StrCat(buffer, maxlen, "</span>");

	return iLines;
}

void UpdateMainHUD(int client)
{
	int target = GetHUDTarget(client);

	if((gI_HUDSettings[client] & HUD_CENTER) == 0 ||
		((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) ||
		(gEV_Type == Engine_TF2 && (!gB_FirstPrint[target] || GetEngineTime() - gF_ConnectTime[target] < 1.5))) // TF2 has weird handling for hint text
	{
		return;
	}

	float fSpeed[3];
	GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);

	float fSpeedHUD = ((gI_HUDSettings[client] & HUD_2DVEL) == 0)? GetVectorLength(fSpeed):(SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)));
	bool bReplay = (gB_Replay && IsFakeClient(target));
	ZoneHUD iZoneHUD = ZoneHUD_None;
	int iReplayStyle = 0;
	int iReplayTrack = 0;
	float fReplayTime = 0.0;
	float fReplayLength = 0.0;

	if(!bReplay)
	{
		if(Shavit_InsideZone(target, Zone_Start, -1))
		{
			iZoneHUD = ZoneHUD_Start;
		}
		
		else if(Shavit_InsideZone(target, Zone_End, -1))
		{
			iZoneHUD = ZoneHUD_End;
		}
	}

	else
	{
		iReplayStyle = Shavit_GetReplayBotStyle(target);
		iReplayTrack = Shavit_GetReplayBotTrack(target);

		if(iReplayStyle != -1)
		{
			fReplayTime = Shavit_GetReplayTime(iReplayStyle, iReplayTrack);
			fReplayLength = Shavit_GetReplayLength(iReplayStyle, iReplayTrack);

			char sSpeed[16];
			Shavit_GetStyleSetting(iReplayStyle, "speed", sSpeed, 16);
			float fSpeed2 = StringToFloat(sSpeed);
			if(fSpeed2 != 1.0)
			{
				fSpeedHUD /= fSpeed2;
			}
		}
	}

	huddata_t huddata;
	huddata.iTarget = target;
	huddata.iSpeed = RoundToNearest(fSpeedHUD);
	huddata.iZoneHUD = iZoneHUD;
	huddata.iStyle = (bReplay)? iReplayStyle:Shavit_GetBhopStyle(target);
	huddata.iTrack = (bReplay)? iReplayTrack:Shavit_GetClientTrack(target);
	huddata.fTime = (bReplay)? fReplayTime:Shavit_GetClientTime(target);
	huddata.iJumps = (bReplay)? 0:Shavit_GetClientJumps(target);
	huddata.iStrafes = (bReplay)? 0:Shavit_GetStrafeCount(target);
	huddata.iRank = (bReplay)? 0:Shavit_GetRankForTime(huddata.iStyle, huddata.fTime, huddata.iTrack);
	huddata.fSync = (bReplay)? 0.0:Shavit_GetSync(target);
	huddata.fPB = (bReplay)? 0.0:Shavit_GetClientPB(target, huddata.iStyle, huddata.iTrack);
	huddata.fWR = (bReplay)? fReplayLength:Shavit_GetWorldRecord(huddata.iStyle, huddata.iTrack);
	huddata.iTimerStatus = (bReplay)? Timer_Running:Shavit_GetTimerStatus(target);
	huddata.bReplay = bReplay;
	huddata.bPractice = (bReplay)? false:Shavit_IsPracticeMode(target);

	char sBuffer[512];
	
	if(IsSource2013(gEV_Type))
	{
		if(AddHUDToBuffer_Source2013(client, huddata, sBuffer, 512) > 0)
		{
			PrintHintText(client, "%s", sBuffer);
		}
	}
	
	else
	{
		StrCat(sBuffer, 512, "<pre>");
		int iLines = AddHUDToBuffer_CSGO(client, huddata, sBuffer, 512);
		StrCat(sBuffer, 512, "</pre>");

		if(iLines > 0)
		{
			if(gCV_UseHUDFix.BoolValue)
			{
				PrintCSGOHUDText(client, "%s", sBuffer);
			}
			else
			{
				PrintHintText(client, "%s", sBuffer);
			}
		}
	}
}

void UpdateKeyOverlay(int client, Panel panel, bool &draw)
{
	if((gI_HUDSettings[client] & HUD_KEYOVERLAY) == 0)
	{
		return;
	}

	int target = GetHUDTarget(client);

	if(((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) || !IsValidClient(target) || IsClientObserver(target))
	{
		return;
	}

	// to make it shorter
	int buttons = gI_Buttons[target];
	int style = (IsFakeClient(target))? Shavit_GetReplayBotStyle(target):Shavit_GetBhopStyle(target);

	if(!(0 <= style < gI_Styles))
	{
		style = 0;
	}

	char sPanelLine[128];
	char autobhop[4];
	Shavit_GetStyleSetting(style, "autobhop", autobhop, 4);

	if(gB_BhopStats && !StringToInt(autobhop))
	{
		FormatEx(sPanelLine, 64, " %d%s%d\n", gI_ScrollCount[target], (gI_ScrollCount[target] > 9)? "   ":"     ", gI_LastScrollCount[target]);
	}

	Format(sPanelLine, 128, "%s［%s］　［%s］\n　　 %s\n%s　 %s 　%s\n　%s　　%s", sPanelLine,
		(buttons & IN_JUMP) > 0? "Ｊ":"ｰ", (buttons & IN_DUCK) > 0? "Ｃ":"ｰ",
		(buttons & IN_FORWARD) > 0? "Ｗ":"ｰ", (buttons & IN_MOVELEFT) > 0? "Ａ":"ｰ",
		(buttons & IN_BACK) > 0? "Ｓ":"ｰ", (buttons & IN_MOVERIGHT) > 0? "Ｄ":"ｰ",
		(buttons & IN_LEFT) > 0? "Ｌ":" ", (buttons & IN_RIGHT) > 0? "Ｒ":" ");

	panel.DrawItem(sPanelLine, ITEMDRAW_RAWLINE);

	draw = true;
}

public void Bunnyhop_OnTouchGround(int client)
{
	gI_LastScrollCount[client] = BunnyhopStats.GetScrollCount(client);
}

public void Bunnyhop_OnJumpPressed(int client)
{
	gI_ScrollCount[client] = BunnyhopStats.GetScrollCount(client);
}

void UpdateCenterKeys(int client)
{
	if((gI_HUDSettings[client] & HUD_KEYOVERLAY) == 0)
	{
		return;
	}

	int target = GetHUDTarget(client);

	if(((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) || !IsValidClient(target) || IsClientObserver(target))
	{
		return;
	}

	int buttons = gI_Buttons[target];

	char sCenterText[64];
	FormatEx(sCenterText, 64, "　%s　　%s\n　　 %s\n%s　 %s 　%s\n　%s　　%s",
		(buttons & IN_JUMP) > 0? "Ｊ":"ｰ", (buttons & IN_DUCK) > 0? "Ｃ":"ｰ",
		(buttons & IN_FORWARD) > 0? "Ｗ":"ｰ", (buttons & IN_MOVELEFT) > 0? "Ａ":"ｰ",
		(buttons & IN_BACK) > 0? "Ｓ":"ｰ", (buttons & IN_MOVERIGHT) > 0? "Ｄ":"ｰ",
		(buttons & IN_LEFT) > 0? "Ｌ":" ", (buttons & IN_RIGHT) > 0? "Ｒ":" ");

	int style = (IsFakeClient(target))? Shavit_GetReplayBotStyle(target):Shavit_GetBhopStyle(target);

	if(!(0 <= style < gI_Styles))
	{
		style = 0;
	}

	char autobhop[4];
	Shavit_GetStyleSetting(style, "autobhop", autobhop, 4);

	if(gB_BhopStats && !StringToInt(autobhop))
	{
		Format(sCenterText, 64, "%s\n　　%d　%d", sCenterText, gI_ScrollCount[target], gI_LastScrollCount[target]);
	}

	PrintCenterText(client, "%s", sCenterText);
}

void UpdateSpectatorList(int client, Panel panel, bool &draw)
{
	if((gI_HUDSettings[client] & HUD_SPECTATORS) == 0)
	{
		return;
	}

	int target = GetHUDTarget(client);

	if(((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) || !IsValidClient(target))
	{
		return;
	}

	int[] iSpectatorClients = new int[MaxClients];
	int iSpectators = 0;
	bool bIsAdmin = CheckCommandAccess(client, "admin_speclisthide", ADMFLAG_KICK);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(i == client || !IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetClientTeam(i) < 1 || GetHUDTarget(i) != target)
		{
			continue;
		}

		if((gCV_SpectatorList.IntValue == 1 && !bIsAdmin && CheckCommandAccess(i, "admin_speclisthide", ADMFLAG_KICK)) ||
			(gCV_SpectatorList.IntValue == 2 && !CanUserTarget(client, i)))
		{
			continue;
		}

		iSpectatorClients[iSpectators++] = i;
	}

	if(iSpectators > 0)
	{
		char sName[MAX_NAME_LENGTH];
		char sSpectators[32];
		char sSpectatorsPersonal[32];
		char sSpectatorWatching[32];
		FormatEx(sSpectatorsPersonal, 32, "%T", "SpectatorPersonal", client);
		FormatEx(sSpectatorWatching, 32, "%T", "SpectatorWatching", client);
		FormatEx(sSpectators, 32, "%s (%d):", (client == target)? sSpectatorsPersonal:sSpectatorWatching, iSpectators);
		panel.DrawItem(sSpectators, ITEMDRAW_RAWLINE);

		for(int i = 0; i < iSpectators; i++)
		{
			if(i == 7)
			{
				panel.DrawItem("...", ITEMDRAW_RAWLINE);

				break;
			}

			GetClientName(iSpectatorClients[i], sName, sizeof(sName));
			ReplaceString(sName, sizeof(sName), "#", "?");
			TrimPlayerName(sName, sName, sizeof(sName));

			panel.DrawItem(sName, ITEMDRAW_RAWLINE);
		}

		draw = true;
	}
}

void UpdateTopLeftHUD(int client, bool wait)
{
	if((!wait || gI_Cycle % 25 == 0) && (gI_HUDSettings[client] & HUD_TOPLEFT) > 0)
	{
		int target = GetHUDTarget(client);

		int track = 0;
		int style = 0;

		if(!IsFakeClient(target))
		{
			style = Shavit_GetBhopStyle(target);
			track = Shavit_GetClientTrack(target);
		}

		else
		{
			style = Shavit_GetReplayBotStyle(target);
			track = Shavit_GetReplayBotTrack(target);
		}

		if(!(0 <= style < gI_Styles) || !(0 <= track <= TRACKS_SIZE))
		{
			return;
		}

		float fWRTime = Shavit_GetWorldRecord(style, track);

		if(fWRTime != 0.0)
		{
			char sWRTime[16];
			FormatSeconds(fWRTime, sWRTime, 16);

			char sWRName[MAX_NAME_LENGTH];
			Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH, track);

			char sTopLeft[128];
			FormatEx(sTopLeft, 128, "WR: %s (%s)", sWRTime, sWRName);

			float fTargetPB = Shavit_GetClientPB(target, style, track);
			char sTargetPB[64];
			FormatSeconds(fTargetPB, sTargetPB, 64);
			Format(sTargetPB, 64, "%T: %s", "HudBestText", client, sTargetPB);

			float fSelfPB = Shavit_GetClientPB(client, style, track);
			char sSelfPB[64];
			FormatSeconds(fSelfPB, sSelfPB, 64);
			Format(sSelfPB, 64, "%T: %s", "HudBestText", client, sSelfPB);

			if((gI_HUD2Settings[client] & HUD2_SPLITPB) == 0 && target != client)
			{
				if(fTargetPB != 0.0)
				{
					if((gI_HUD2Settings[client]& HUD2_TOPLEFT_RANK) == 0)
					{
						Format(sTopLeft, 128, "%s\n%s (#%d) (%N)", sTopLeft, sTargetPB, Shavit_GetRankForTime(style, fTargetPB, track), target);
					}
					else 
					{
						Format(sTopLeft, 128, "%s\n%s (%N)", sTopLeft, sTargetPB, target);
					}
				}

				if(fSelfPB != 0.0)
				{
					if((gI_HUD2Settings[client]& HUD2_TOPLEFT_RANK) == 0)
					{
						Format(sTopLeft, 128, "%s\n%s (#%d) (%N)", sTopLeft, sSelfPB, Shavit_GetRankForTime(style, fSelfPB, track), client);
					}
					else 
					{
						Format(sTopLeft, 128, "%s\n%s (%N)", sTopLeft, sSelfPB, client);
					}
				}
			}

			else if(fSelfPB != 0.0)
			{
				Format(sTopLeft, 128, "%s\n%s (#%d)", sTopLeft, sSelfPB, Shavit_GetRankForTime(style, fSelfPB, track));
			}

			Action result = Plugin_Continue;
			Call_StartForward(gH_Forwards_OnTopLeftHUD);
			Call_PushCell(client);
			Call_PushCell(target);
			Call_PushStringEx(sTopLeft, 128, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
			Call_PushCell(128);
			Call_Finish(result);
			
			if(result != Plugin_Continue && result != Plugin_Changed)
			{
				return;
			}

			SetHudTextParams(0.01, 0.01, 2.5, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
			ShowSyncHudText(client, gH_HUD, "%s", sTopLeft);
		}
	}
}

void UpdateKeyHint(int client)
{
	if((gI_Cycle % 10) == 0 && ((gI_HUDSettings[client] & HUD_SYNC) > 0 || (gI_HUDSettings[client] & HUD_TIMELEFT) > 0))
	{
		char sMessage[256];
		int iTimeLeft = -1;

		if((gI_HUDSettings[client] & HUD_TIMELEFT) > 0 && GetMapTimeLeft(iTimeLeft) && iTimeLeft > 0)
		{
			FormatEx(sMessage, 256, (iTimeLeft > 60)? "%T: %d minutes":"%T: <1 minute", "HudTimeLeft", client, (iTimeLeft / 60), "HudTimeLeft", client);
		}

		int target = GetHUDTarget(client);

		if(IsValidClient(target) && (target == client || (gI_HUDSettings[client] & HUD_OBSERVE) > 0))
		{
			int style = Shavit_GetBhopStyle(target);

			char sync[4];
			Shavit_GetStyleSetting(style, "sync", sync, 4);

			char autobhop[4];
			Shavit_GetStyleSetting(style, "autobhop", autobhop, 4);

			if((gI_HUDSettings[client] & HUD_SYNC) > 0 && Shavit_GetTimerStatus(target) == Timer_Running && StringToInt(sync) && !IsFakeClient(target) && (!gB_Zones || !Shavit_InsideZone(target, Zone_Start, -1)))
			{
				Format(sMessage, 256, "%s%s%T: %.01f", sMessage, (strlen(sMessage) > 0)? "\n\n":"", "HudSync", client, Shavit_GetSync(target));

				if(!StringToInt(autobhop) && (gI_HUD2Settings[client] & HUD2_PERFS) == 0)
				{	
					Format(sMessage, 256, "%s\n%T: %.1f", sMessage, "HudPerfs", client, Shavit_GetPerfectJumps(target));
				}
			}

			if((gI_HUDSettings[client] & HUD_SPECTATORS) > 0)
			{
				int[] iSpectatorClients = new int[MaxClients];
				int iSpectators = 0;
				bool bIsAdmin = CheckCommandAccess(client, "admin_speclisthide", ADMFLAG_KICK);

				for(int i = 1; i <= MaxClients; i++)
				{
					if(i == client || !IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetClientTeam(i) < 1 || GetHUDTarget(i) != target)
					{
						continue;
					}

					if((gCV_SpectatorList.IntValue == 1 && !bIsAdmin && CheckCommandAccess(i, "admin_speclisthide", ADMFLAG_KICK)) ||
						(gCV_SpectatorList.IntValue == 2 && !CanUserTarget(client, i)))
					{
						continue;
					}

					iSpectatorClients[iSpectators++] = i;
				}

				if(iSpectators > 0)
				{
					Format(sMessage, 256, "%s%s%spectators (%d):", sMessage, (strlen(sMessage) > 0)? "\n\n":"", (client == target)? "S":"Other S", iSpectators);
					char sName[MAX_NAME_LENGTH];
					
					for(int i = 0; i < iSpectators; i++)
					{
						if(i == 7)
						{
							Format(sMessage, 256, "%s\n...", sMessage);

							break;
						}

						GetClientName(iSpectatorClients[i], sName, sizeof(sName));
						ReplaceString(sName, sizeof(sName), "#", "?");
						TrimPlayerName(sName, sName, sizeof(sName));
						Format(sMessage, 256, "%s\n%s", sMessage, sName);
					}
				}
			}
		}

		if(strlen(sMessage) > 0)
		{
			Handle hKeyHintText = StartMessageOne("KeyHintText", client);
			BfWriteByte(hKeyHintText, 1);
			BfWriteString(hKeyHintText, sMessage);
			EndMessage();
		}
	}
}

int GetHUDTarget(int client)
{
	int target = client;

	if(IsClientObserver(client))
	{
		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		if(iObserverMode >= 3 && iObserverMode <= 5)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if(IsValidClient(iTarget, true))
			{
				target = iTarget;
			}
		}
	}

	return target;
}

public int PanelHandler_Nothing(Menu m, MenuAction action, int param1, int param2)
{
	// i don't need anything here
	return 0;
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	if(IsClientInGame(client))
	{
		UpdateTopLeftHUD(client, false);
	}
}

public int Native_ForceHUDUpdate(Handle handler, int numParams)
{
	int[] clients = new int[MaxClients];
	int count = 0;

	int client = GetNativeCell(1);

	if(client < 0 || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(200, "Invalid client index %d", client);

		return -1;
	}

	clients[count++] = client;

	if(view_as<bool>(GetNativeCell(2)))
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(i == client || !IsValidClient(i) || GetHUDTarget(i) != client)
			{
				continue;
			}

			clients[count++] = client;
		}
	}

	for(int i = 0; i < count; i++)
	{
		TriggerHUDUpdate(clients[i]);
	}

	return count;
}

public int Native_GetHUDSettings(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(200, "Invalid client index %d", client);

		return -1;
	}

	return gI_HUDSettings[client];
}

void PrintCSGOHUDText(int client, const char[] format, any ...)
{
	char buff[MAX_HINT_SIZE];
	VFormat(buff, sizeof(buff), format, 3);
	Format(buff, sizeof(buff), "</font>%s ", buff);
	
	for(int i = strlen(buff); i < sizeof(buff); i++)
	{
		buff[i] = '\n';
	}
	
	Protobuf pb = view_as<Protobuf>(StartMessageOne("TextMsg", client, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS));
	pb.SetInt("msg_dst", 4);
	pb.AddString("params", "#SFUI_ContractKillStart");
	pb.AddString("params", buff);
	pb.AddString("params", NULL_STRING);
	pb.AddString("params", NULL_STRING);
	pb.AddString("params", NULL_STRING);
	pb.AddString("params", NULL_STRING);
	
	EndMessage();
}

// https://forums.alliedmods.net/showthread.php?t=216841
void TrimPlayerName(const char[] name, char[] outname, int len)
{
	int count, finallen;
	for(int i = 0; name[i]; i++)
	{
		count += ((name[i] & 0xc0) != 0x80) ? 1 : 0;
		
		if(count <= gCV_SpecNameSymbolLength.IntValue)
		{
			outname[i] = name[i];
			finallen = i;
		}
	}
	
	outname[finallen + 1] = '\0';
	
	if(count > gCV_SpecNameSymbolLength.IntValue)
		Format(outname, len, "%s...", outname);
}