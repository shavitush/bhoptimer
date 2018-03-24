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

#undef REQUIRE_PLUGIN
#include <shavit>
#include <bhopstats>

#pragma newdecls required
#pragma semicolon 1

#define HUD_DEFAULT				(HUD_MASTER|HUD_CENTER|HUD_ZONEHUD|HUD_OBSERVE|HUD_TOPLEFT|HUD_SYNC|HUD_TIMELEFT|HUD_2DVEL|HUD_SPECTATORS)

// game type (CS:S/CS:GO/TF2)
EngineVersion gEV_Type = Engine_Unknown;

// modules
bool gB_Replay = false;
bool gB_Zones = false;
bool gB_Sounds = false;
bool gB_BhopStats = false;

// cache
int gI_Cycle = 0;
int gI_GradientColors[3];
int gI_GradientDirection = -1;
int gI_Styles = 0;

Handle gH_HUDCookie = null;
int gI_HUDSettings[MAXPLAYERS+1];
int gI_NameLength = MAX_NAME_LENGTH;
int gI_LastScrollCount[MAXPLAYERS+1];
int gI_ScrollCount[MAXPLAYERS+1];
int gI_Buttons[MAXPLAYERS+1];
float gF_ConnectTime[MAXPLAYERS+1];
bool gB_FirstPrint[MAXPLAYERS+1];

bool gB_Late = false;

// hud handle
Handle gH_HUD = null;

// plugin cvars
ConVar gCV_GradientStepSize = null;
ConVar gCV_TicksPerUpdate = null;

// cached cvars
int gI_GradientStepSize = 5;
int gI_TicksPerUpdate = 5;

// timer settings
char gS_StyleStrings[STYLE_LIMIT][STYLESTRINGS_SIZE][128];
any gA_StyleSettings[STYLE_LIMIT][STYLESETTINGS_SIZE];

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

	if(IsSource2013(gEV_Type))
	{
		gI_NameLength = MAX_NAME_LENGTH;
	}

	else
	{
		gI_NameLength = 14; // 14 because long names will make it look spammy in CS:GO due to the font
	}

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
	gB_BhopStats = LibraryExists("bhopstats");

	// HUD handle
	gH_HUD = CreateHudSynchronizer();

	// plugin convars
	gCV_GradientStepSize = CreateConVar("shavit_hud_gradientstepsize", "15", "How fast should the start/end HUD gradient be?\nThe number is the amount of color change per 0.1 seconds.\nThe higher the number the faster the gradient.", 0, true, 1.0, true, 255.0);
	gCV_TicksPerUpdate = CreateConVar("shavit_hud_ticksperupdate", "5", "How often (in ticks) should the HUD update?\nPlay around with this value until you find the best for your server.\nThe maximum value is your tickrate.", 0, true, 1.0, true, (1.0 / GetTickInterval()));

	gCV_GradientStepSize.AddChangeHook(OnConVarChanged);
	gCV_TicksPerUpdate.AddChangeHook(OnConVarChanged);

	AutoExecConfig();

	// commands
	RegConsoleCmd("sm_hud", Command_HUD, "Opens the HUD settings menu");
	RegConsoleCmd("sm_options", Command_HUD, "Opens the HUD settings menu (alias for sm_hud");

	// cookies
	gH_HUDCookie = RegClientCookie("shavit_hud_setting", "HUD settings", CookieAccess_Protected);

	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);

				if(AreClientCookiesCached(i))
				{
					OnClientCookiesCached(i);
				}
			}
		}
	}
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	gI_GradientStepSize = gCV_GradientStepSize.IntValue;
	gI_TicksPerUpdate = gCV_TicksPerUpdate.IntValue;
}

public void OnMapStart()
{
	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(-1);
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
		Shavit_GetStyleSettings(i, gA_StyleSettings[i]);
		Shavit_GetStyleStrings(i, sStyleName, gS_StyleStrings[i][sStyleName], 128);
		Shavit_GetStyleStrings(i, sHTMLColor, gS_StyleStrings[i][sHTMLColor], 128);
	}
}

public Action Shavit_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int style, any stylesettings[STYLESETTINGS_SIZE])
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
	char[] sHUDSettings = new char[8];
	GetClientCookie(client, gH_HUDCookie, sHUDSettings, 8);

	if(strlen(sHUDSettings) == 0)
	{
		IntToString(HUD_DEFAULT, sHUDSettings, 8);

		SetClientCookie(client, gH_HUDCookie, sHUDSettings);
		gI_HUDSettings[client] = HUD_DEFAULT;
	}

	else
	{
		gI_HUDSettings[client] = StringToInt(sHUDSettings);
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

	char[] sInfo = new char[16];
	char[] sHudItem = new char[64];
	IntToString(HUD_MASTER, sInfo, 16);
	FormatEx(sHudItem, 64, "%T", "HudMaster", client);
	menu.AddItem(sInfo, sHudItem);

	IntToString(HUD_CENTER, sInfo, 16);
	FormatEx(sHudItem, 64, "%T", "HudCenter", client);
	menu.AddItem(sInfo, sHudItem);

	IntToString(HUD_ZONEHUD, sInfo, 16);
	FormatEx(sHudItem, 64, "%T", "HudZoneHud", client);
	menu.AddItem(sInfo, sHudItem);

	IntToString(HUD_OBSERVE, sInfo, 16);
	FormatEx(sHudItem, 64, "%T", "HudObserve", client);
	menu.AddItem(sInfo, sHudItem);

	IntToString(HUD_SPECTATORS, sInfo, 16);
	FormatEx(sHudItem, 64, "%T", "HudSpectators", client);
	menu.AddItem(sInfo, sHudItem);

	IntToString(HUD_KEYOVERLAY, sInfo, 16);
	FormatEx(sHudItem, 64, "%T", "HudKeyOverlay", client);
	menu.AddItem(sInfo, sHudItem);

	IntToString(HUD_HIDEWEAPON, sInfo, 16);
	FormatEx(sHudItem, 64, "%T", "HudHideWeapon", client);
	menu.AddItem(sInfo, sHudItem);

	IntToString(HUD_TOPLEFT, sInfo, 16);
	FormatEx(sHudItem, 64, "%T", "HudTopLeft", client);
	menu.AddItem(sInfo, sHudItem);

	if(IsSource2013(gEV_Type))
	{
		IntToString(HUD_SYNC, sInfo, 16);
		FormatEx(sHudItem, 64, "%T", "HudSync", client);
		menu.AddItem(sInfo, sHudItem);

		IntToString(HUD_TIMELEFT, sInfo, 16);
		FormatEx(sHudItem, 64, "%T", "HudTimeLeft", client);
		menu.AddItem(sInfo, sHudItem);
	}

	IntToString(HUD_2DVEL, sInfo, 16);
	FormatEx(sHudItem, 64, "%T", "Hud2dVel", client);
	menu.AddItem(sInfo, sHudItem);

	if(gB_Sounds)
	{
		IntToString(HUD_NOSOUNDS, sInfo, 16);
		FormatEx(sHudItem, 64, "%T", "HudNoRecordSounds", client);
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
		char[] sCookie = new char[16];
		menu.GetItem(param2, sCookie, 16);
		int iSelection = StringToInt(sCookie);

		gI_HUDSettings[param1] ^= iSelection;
		IntToString(gI_HUDSettings[param1], sCookie, 16); // string recycling Kappa

		if(gEV_Type == Engine_TF2 && iSelection == HUD_CENTER && (gI_HUDSettings[param1] & HUD_MASTER) > 0)
		{
			FillerHintText(param1);
		}

		SetClientCookie(param1, gH_HUDCookie, sCookie);

		ShowHUDMenu(param1, GetMenuSelectionPosition());
	}

	else if(action == MenuAction_DisplayItem)
	{
		char[] sInfo = new char[16];
		char[] sDisplay = new char[64];
		int style = 0;
		menu.GetItem(param2, sInfo, 16, style, sDisplay, 64);

		Format(sDisplay, 64, "[%s] %s", ((gI_HUDSettings[param1] & StringToInt(sInfo)) > 0)? "x":" ", sDisplay);

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
	if(GetGameTickCount() % gI_TicksPerUpdate == 0)
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
			gI_GradientColors[2] += gI_GradientStepSize;

			if(gI_GradientColors[2] >= 255)
			{
				gI_GradientColors[2] = 255;
				gI_GradientDirection = 1;
			}
		}

		case 1:
		{
			gI_GradientColors[0] -= gI_GradientStepSize;

			if(gI_GradientColors[0] <= 0)
			{
				gI_GradientColors[0] = 0;
				gI_GradientDirection = 2;
			}
		}

		case 2:
		{
			gI_GradientColors[1] += gI_GradientStepSize;

			if(gI_GradientColors[1] >= 255)
			{
				gI_GradientColors[1] = 255;
				gI_GradientDirection = 3;
			}
		}

		case 3:
		{
			gI_GradientColors[2] -= gI_GradientStepSize;

			if(gI_GradientColors[2] <= 0)
			{
				gI_GradientColors[2] = 0;
				gI_GradientDirection = 4;
			}
		}

		case 4:
		{
			gI_GradientColors[0] += gI_GradientStepSize;

			if(gI_GradientColors[0] >= 255)
			{
				gI_GradientColors[0] = 255;
				gI_GradientDirection = 5;
			}
		}

		case 5:
		{
			gI_GradientColors[1] -= gI_GradientStepSize;

			if(gI_GradientColors[1] <= 0)
			{
				gI_GradientColors[1] = 0;
				gI_GradientDirection = 0;
			}
		}

		default:
		{
			gI_GradientColors[0] = 255;
			gI_GradientDirection = 0;
		}
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i) || (gI_HUDSettings[i] & HUD_MASTER) == 0)
		{
			continue;
		}

		TriggerHUDUpdate(i);
	}
}

void TriggerHUDUpdate(int client, bool keysonly = false) // keysonly because CS:S lags when you send too many usermessages
{
	if(!keysonly)
	{
		UpdateHUD(client);
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

void UpdateHUD(int client)
{
	int target = GetHUDTarget(client);

	if(((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) ||
		(gEV_Type == Engine_TF2 && (!gB_FirstPrint[target] || GetEngineTime() - gF_ConnectTime[target] < 1.5))) // TF2 has weird handling for hint text
	{
		return;
	}

	int style = Shavit_GetBhopStyle(target);

	float fSpeed[3];
	GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);

	int iSpeed = RoundToNearest(((gI_HUDSettings[client] & HUD_2DVEL) == 0)? GetVectorLength(fSpeed):(SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0))));

	char[] sHintText = new char[512];
	strcopy(sHintText, 512, "");

	if(!IsFakeClient(target) && (gI_HUDSettings[client] & HUD_ZONEHUD) > 0)
	{
		if(Shavit_InsideZone(target, Zone_Start, -1))
		{
			if(gEV_Type == Engine_CSGO)
			{
				FormatEx(sHintText, 128, "       <font size='34' color='#%06X'>%T</font>\n\t  %T: %d", ((gI_GradientColors[0] << 16) + (gI_GradientColors[1] << 8) + (gI_GradientColors[2])), "HudStartZone", client, "HudSpeedText", client, iSpeed);
			}

			else
			{
				// yes, this space is intentional
				FormatEx(sHintText, 32, "%T ", "HudInStartZone", client, iSpeed);
			}
		}

		else if(Shavit_InsideZone(target, Zone_End, -1))
		{
			if(gEV_Type == Engine_CSGO)
			{
				FormatEx(sHintText, 128, "       <font size='34' color='#%06X'>%T</font>\n\t  %T: %d", ((gI_GradientColors[0] << 16) + (gI_GradientColors[1] << 8) + (gI_GradientColors[2])), "HudEndZone", client, "HudSpeedText", client, iSpeed);
			}

			else
			{
				FormatEx(sHintText, 32, "%T ", "HudInEndZone", client, iSpeed);
			}
		}
	}

	if(strlen(sHintText) > 0)
	{
		PrintHintText(client, sHintText);
	}

	else if((gI_HUDSettings[client] & HUD_CENTER) > 0)
	{
		int track = Shavit_GetClientTrack(target);

		if(!IsFakeClient(target))
		{
			char[] sTrack = new char[32];

			if(track != Track_Main)
			{
				GetTrackName(client, track, sTrack, 32);
			}

			float time = Shavit_GetClientTime(target);
			int jumps = Shavit_GetClientJumps(target);
			TimerStatus status = Shavit_GetTimerStatus(target);
			int strafes = Shavit_GetStrafeCount(target);
			int rank = Shavit_GetRankForTime(style, time, track);

			float fWR = 0.0;
			Shavit_GetWRTime(style, fWR, track);

			float fPB = 0.0;
			Shavit_GetPlayerPB(target, style, fPB, track);

			char[] sPB = new char[32];
			FormatSeconds(fPB, sPB, 32);

			char[] sTime = new char[32];
			FormatSeconds(time, sTime, 32, false);

			if(gEV_Type == Engine_CSGO)
			{
				strcopy(sHintText, 512, "<font size='18' face=''>");

				if(status >= Timer_Running)
				{
					char[] sColor = new char[8];

					if(status == Timer_Paused)
					{
						strcopy(sColor, 8, "A9C5E8");
					}

					else if(time < fWR || fWR == 0.0)
					{
						strcopy(sColor, 8, "00FF00");
					}

					else if(fPB != 0.0 && time < fPB)
					{
						strcopy(sColor, 8, "FFA500");
					}

					else
					{
						strcopy(sColor, 8, "FF0000");
					}

					if(track != Track_Main)
					{
						Format(sHintText, 512, "%s[<font color='#FFFFFF'>%s</font>] ", sHintText, sTrack);
					}

					Format(sHintText, 512, "%s<font color='#%s'>%s</font> (%d)", sHintText, sColor, sTime, rank);
				}

				else if(fPB > 0.0)
				{
					Format(sHintText, 512, "%s%T: %s (#%d)", sHintText, "HudBestText", client, sPB, (Shavit_GetRankForTime(style, fPB, track) - 1));
				}

				if(status >= Timer_Running)
				{
					Format(sHintText, 512, "%s\n%T: %d%s\t%T: <font color='#%s'>%s</font>", sHintText, "HudJumpsText", client, jumps, (jumps < 1000)? "\t":"", "HudStyleText", client, gS_StyleStrings[style][sHTMLColor], gS_StyleStrings[style][sStyleName]);
				}

				else
				{
					Format(sHintText, 512, "%s\n%T: <font color='#%s'>%s</font>", sHintText, "HudStyleText", client, gS_StyleStrings[style][sHTMLColor], gS_StyleStrings[style][sStyleName]);
				}

				Format(sHintText, 512, "%s\n%T: %d", sHintText, "HudSpeedText", client, iSpeed);

				if(status >= Timer_Running)
				{
					if(gA_StyleSettings[style][bSync])
					{
						Format(sHintText, 512, "%s%s\t%T: %d (%.02f%%)", sHintText, (iSpeed < 1000)? "\t":"", "HudStrafeText", client, strafes, Shavit_GetSync(target));
					}

					else
					{
						Format(sHintText, 512, "%s%s\t%T: %d", sHintText, (iSpeed < 1000)? "\t":"", "HudStrafeText", client, strafes);
					}
				}
			}

			else
			{
				if(status != Timer_Stopped)
				{
					char[] sFirstLine = new char[64];
					strcopy(sFirstLine, 64, gS_StyleStrings[style][sStyleName]);

					if(Shavit_IsPracticeMode(target))
					{
						Format(sFirstLine, 64, "%s %T", sFirstLine, "HudPracticeMode", client);
					}

					FormatEx(sHintText, 512, "%s\n%T: %s (%d)\n%T: %d\n%T: %d\n%T: %d%s", sFirstLine, "HudTimeText", client, sTime, rank, "HudJumpsText", client, jumps, "HudStrafeText", client, strafes, "HudSpeedText", client, iSpeed, (gA_StyleSettings[style][fVelocityLimit] > 0.0 && Shavit_InsideZone(target, Zone_NoVelLimit, -1))? "\nNo Speed Limit":"");
					
					if(Shavit_GetTimerStatus(target) == Timer_Paused)
					{
						Format(sHintText, 512, "%s\n%T", sHintText, "HudPaused", client);
					}

					if(track != Track_Main)
					{
						Format(sHintText, 512, "%s\n%s", sHintText, sTrack);
					}
				}

				else
				{
					IntToString(iSpeed, sHintText, 8);
				}
			}

			PrintHintText(client, "%s", sHintText);
		}

		else if(gB_Replay)
		{
			style = Shavit_GetReplayBotStyle(target);

			if(style == -1)
			{
				PrintHintText(client, "%T", (gEV_Type != Engine_TF2)? "NoReplayData":"NoReplayDataTF2", client);

				return;
			}

			track = Shavit_GetReplayBotTrack(target);

			float fReplayTime = Shavit_GetReplayTime(style, track);
			float fReplayLength = Shavit_GetReplayLength(style, track);

			if(fReplayTime < 0.0 || fReplayTime > fReplayLength || !Shavit_IsReplayDataLoaded(style, track))
			{
				return;
			}

			char[] sReplayTime = new char[32];
			FormatSeconds(fReplayTime, sReplayTime, 32, false);

			char[] sReplayLength = new char[32];
			FormatSeconds(fReplayLength, sReplayLength, 32, false);

			char[] sTrack = new char[32];

			if(track != Track_Main)
			{
				GetTrackName(client, track, sTrack, 32);
				Format(sTrack, 32, "(%s) ", sTrack);
			}

			if(gEV_Type == Engine_CSGO)
			{
				FormatEx(sHintText, 512, "<font face=''>");
				Format(sHintText, 512, "%s\t<u><font color='#%s'>%s %T</font></u>", sHintText, gS_StyleStrings[style][sHTMLColor], gS_StyleStrings[style][sStyleName], "ReplayText", client);
				Format(sHintText, 512, "%s\n\t%T: <font color='#00FF00'>%s</font> / %s", sHintText, "HudTimeText", client, sReplayTime, sReplayLength);
				Format(sHintText, 512, "%s\n\t%T: %d", sHintText, "HudSpeedText", client, iSpeed);
			}

			else
			{
				char[] sPlayerName = new char[MAX_NAME_LENGTH];
				Shavit_GetReplayName(style, track, sPlayerName, MAX_NAME_LENGTH);

				FormatEx(sHintText, 512, "%s %s%T", gS_StyleStrings[style][sStyleName], sTrack, "ReplayText", client);
				Format(sHintText, 512, "%s\n%s", sHintText, sPlayerName);
				Format(sHintText, 512, "%s\n%T: %s/%s", sHintText, "HudTimeText", client, sReplayTime, sReplayLength);
				Format(sHintText, 512, "%s\n%T: %d", sHintText, "HudSpeedText", client, iSpeed);
			}

			PrintHintText(client, "%s", sHintText);
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

	char[] sPanelLine = new char[128];

	int style = (IsFakeClient(target))? Shavit_GetReplayBotStyle(target):Shavit_GetBhopStyle(target);

	if(style < 0 || style > gI_Styles)
	{
		style = 0;
	}

	if(gB_BhopStats && !gA_StyleSettings[style][bAutobhop])
	{
		FormatEx(sPanelLine, 64, " %d%s%d\n", gI_ScrollCount[target], (gI_ScrollCount[target] > 9)? "   ":"     ", gI_LastScrollCount[target]);
	}

	Format(sPanelLine, 128, "%s［%s］　［%s］\n　　 %s\n%s　 %s 　%s", sPanelLine,
		(buttons & IN_JUMP) > 0? "Ｊ":"ｰ", (buttons & IN_DUCK) > 0? "Ｃ":"ｰ",
		(buttons & IN_FORWARD) > 0? "Ｗ":"ｰ", (buttons & IN_MOVELEFT) > 0? "Ａ":"ｰ",
		(buttons & IN_BACK) > 0? "Ｓ":"ｰ", (buttons & IN_MOVERIGHT) > 0? "Ｄ":"ｰ");

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

	char[] sCenterText = new char[64];
	FormatEx(sCenterText, 64, "　%s　　%s\n　　 %s\n%s　 %s 　%s", 
		(buttons & IN_JUMP) > 0? "Ｊ":"ｰ", (buttons & IN_DUCK) > 0? "Ｃ":"ｰ",
		(buttons & IN_FORWARD) > 0? "Ｗ":"ｰ", (buttons & IN_MOVELEFT) > 0? "Ａ":"ｰ",
		(buttons & IN_BACK) > 0? "Ｓ":"ｰ", (buttons & IN_MOVERIGHT) > 0? "Ｄ":"ｰ");

	int style = (IsFakeClient(target))? Shavit_GetReplayBotStyle(target):Shavit_GetBhopStyle(target);

	if(style < 0 || style > gI_Styles)
	{
		style = 0;
	}

	if(gB_BhopStats && !gA_StyleSettings[style][bAutobhop])
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
		if(i == client || !IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") != target || GetClientTeam(i) < 1
			|| (!bIsAdmin && CheckCommandAccess(i, "admin_speclisthide", ADMFLAG_KICK)))
		{
			continue;
		}

		int iObserverMode = GetEntProp(i, Prop_Send, "m_iObserverMode");

		if(iObserverMode >= 3 && iObserverMode <= 5)
		{
			iSpectatorClients[iSpectators++] = i;
		}
	}

	if(iSpectators > 0)
	{
		char[] sSpectators = new char[32];
		char[] sSpectatorsPersonal = new char[64];
		char[] sSpectatorWatching = new char[64];
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

			char[] sName = new char[gI_NameLength];
			GetClientName(iSpectatorClients[i], sName, gI_NameLength);
			ReplaceString(sName, gI_NameLength, "#", "?");

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
		int track = Shavit_GetClientTrack(target);
		int style = Shavit_GetBhopStyle(target);

		float fWRTime = 0.0;
		Shavit_GetWRTime(style, fWRTime, track);

		if(fWRTime != 0.0)
		{
			char[] sWRTime = new char[16];
			FormatSeconds(fWRTime, sWRTime, 16);

			char[] sWRName = new char[MAX_NAME_LENGTH];
			Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH, track);

			float fPBTime = 0.0;
			Shavit_GetPlayerPB(target, style, fPBTime, track);

			char[] sPBTime = new char[16];
			FormatSeconds(fPBTime, sPBTime, MAX_NAME_LENGTH);

			char[] sTopLeft = new char[128];

			if(fPBTime != 0.0)
			{
				FormatEx(sTopLeft, 128, "WR: %s (%s)\n%T: %s (#%d)", sWRTime, sWRName, "HudBestText", client, sPBTime, (Shavit_GetRankForTime(style, fPBTime, track) - 1));
			}

			else
			{
				FormatEx(sTopLeft, 128, "WR: %s (%s)", sWRTime, sWRName);
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
		char[] sMessage = new char[256];
		int iTimeLeft = -1;

		if((gI_HUDSettings[client] & HUD_TIMELEFT) > 0 && GetMapTimeLeft(iTimeLeft) && iTimeLeft > 0)
		{
			FormatEx(sMessage, 256, (iTimeLeft > 60)? "%T: %d minutes":"%T: <1 minute", "HudTimeLeft", client, (iTimeLeft / 60), "HudTimeLeft", client);
		}

		int target = GetHUDTarget(client);

		if(IsValidClient(target) && (target == client || (gI_HUDSettings[client] & HUD_OBSERVE) > 0))
		{
			if((gI_HUDSettings[client] & HUD_SYNC) > 0 && Shavit_GetTimerStatus(target) == Timer_Running && gA_StyleSettings[Shavit_GetBhopStyle(target)][bSync] && !IsFakeClient(target) && (!gB_Zones || !Shavit_InsideZone(target, Zone_Start, -1)))
			{
				Format(sMessage, 256, "%s%s%T: %.02f", sMessage, (strlen(sMessage) > 0)? "\n\n":"", "HudSync", client, Shavit_GetSync(target));
			}

			if((gI_HUDSettings[client] & HUD_SPECTATORS) > 0)
			{
				int[] iSpectatorClients = new int[MaxClients];
				int iSpectators = 0;
				bool bIsAdmin = CheckCommandAccess(client, "admin_speclisthide", ADMFLAG_KICK);

				for(int i = 1; i <= MaxClients; i++)
				{
					if(i == client || !IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") != target
						|| GetClientTeam(i) < 1 || (!bIsAdmin && CheckCommandAccess(i, "admin_speclisthide", ADMFLAG_KICK)))
					{
						continue;
					}

					int iObserverMode = GetEntProp(i, Prop_Send, "m_iObserverMode");

					if(iObserverMode >= 3 && iObserverMode <= 5)
					{
						iSpectatorClients[iSpectators++] = i;
					}
				}

				if(iSpectators > 0)
				{
					Format(sMessage, 256, "%s%s%spectators (%d):", sMessage, (strlen(sMessage) > 0)? "\n\n":"", (client == target)? "S":"Other S", iSpectators);

					for(int i = 0; i < iSpectators; i++)
					{
						if(i == 7)
						{
							Format(sMessage, 256, "%s\n...", sMessage);

							break;
						}

						char[] sName = new char[gI_NameLength];
						GetClientName(iSpectatorClients[i], sName, gI_NameLength);
						ReplaceString(sName, gI_NameLength, "#", "?");
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

void GetTrackName(int client, int track, char[] output, int size)
{
	if(track < 0 || track >= TRACKS_SIZE)
	{
		FormatEx(output, size, "%T", "Track_Unknown", client);

		return;
	}

	static char sTrack[16];
	FormatEx(sTrack, 16, "Track_%d", track);
	FormatEx(output, size, "%T", sTrack, client);
}
