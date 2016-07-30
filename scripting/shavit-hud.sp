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
#include <clientprefs>

#undef REQUIRE_PLUGIN
#define USES_STYLE_NAMES
#define USES_STYLE_HTML_COLORS
#define USES_STYLE_PROPERTIES
#include <shavit>

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 131072

#define HUD_NONE				(0)
#define HUD_MASTER				(1 << 0) // master setting
#define HUD_CENTER				(1 << 1) // show hud as hint text
#define HUD_ZONEHUD				(1 << 2) // show start/end zone hud
#define HUD_OBSERVE				(1 << 3) // show the HUD of the player you spectate
#define HUD_SPECTATORS			(1 << 4) // show list of spectators
#define HUD_KEYOVERLAY			(1 << 5) // show a key overlay
#define HUD_HIDEWEAPON			(1 << 6) // hide the player's weapon
#define HUD_TOPLEFT				(1 << 7) // show top left white HUD with WR/PB times (css only)
#define HUD_SYNC				(1 << 8) // shows sync at right side of the screen (css only)

#define HUD_DEFAULT				(HUD_MASTER|HUD_CENTER|HUD_ZONEHUD|HUD_OBSERVE|HUD_TOPLEFT|HUD_SYNC)

// game type (CS:S/CS:GO)
ServerGame gSG_Type = Game_Unknown;

// modules
bool gB_Replay = false;
bool gB_Zones = false;

// zone colors
char gS_StartColors[][] =
{
	"ff0000", "ff4000", "ff7f00", "ffbf00", "ffff00", "00ff00", "00ff80", "00ffff", "0080ff", "0000ff"
};

char gS_EndColors[][] =
{
	"ff0000", "ff4000", "ff7f00", "ffaa00", "ffd400", "ffff00", "bba24e", "77449c"
};

// cache
int gI_Cycle = 0;

Handle gH_HUDCookie = null;
int gI_HUDSettings[MAXPLAYERS+1];
int gI_NameLength = MAX_NAME_LENGTH;

// css hud
Handle gH_HUD = null;

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

	if(late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientCookiesCached(i);
			}
		}
	}

	RegPluginLibrary("shavit-hud");

	return APLRes_Success;
}

public void OnPluginStart()
{
	// game-specific
	gSG_Type = Shavit_GetGameType();

	if(gSG_Type == Game_CSS)
	{
		gH_HUD = CreateHudSynchronizer();
		gI_NameLength = MAX_NAME_LENGTH;
	}

	else
	{
		gI_NameLength = 14; // 14 because long names will make it look spammy in CS:GO due to the font
	}

	// prevent errors in case the replay bot isn't loaded
	gB_Replay = LibraryExists("shavit-replay");
	gB_Zones = LibraryExists("shavit-zones");

	// cron
	CreateTimer(0.10, UpdateHUD_Timer, INVALID_HANDLE, TIMER_REPEAT);

	// commands
	RegConsoleCmd("sm_hud", Command_HUD, "Opens the HUD settings menu");

	// cookies
	gH_HUDCookie = RegClientCookie("shavit_hud_setting", "HUD settings", CookieAccess_Protected);
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

public Action Command_HUD(int client, int args)
{
	return ShowHUDMenu(client);
}

public Action ShowHUDMenu(int client)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu m = new Menu(MenuHandler_HUD, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	m.SetTitle("HUD settings:");

	char[] sInfo = new char[16];
	IntToString(HUD_MASTER, sInfo, 16);
	m.AddItem(sInfo, "Master");

	IntToString(HUD_CENTER, sInfo, 16);
	m.AddItem(sInfo, "Center text");

	IntToString(HUD_ZONEHUD, sInfo, 16);
	m.AddItem(sInfo, "Zone HUD");

	IntToString(HUD_OBSERVE, sInfo, 16);
	m.AddItem(sInfo, "Show the HUD of the player you spectate");

	IntToString(HUD_SPECTATORS, sInfo, 16);
	m.AddItem(sInfo, "Spectator list");

	IntToString(HUD_KEYOVERLAY, sInfo, 16);
	m.AddItem(sInfo, "Key overlay");

	IntToString(HUD_HIDEWEAPON, sInfo, 16);
	m.AddItem(sInfo, "Hide weapons");

	if(gSG_Type == Game_CSS)
	{
		IntToString(HUD_TOPLEFT, sInfo, 16);
		m.AddItem(sInfo, "Top left HUD (WR/PB)");

		IntToString(HUD_SYNC, sInfo, 16);
		m.AddItem(sInfo, "Sync");
	}

	m.ExitButton = true;
	m.Display(client, 60);

	return Plugin_Handled;
}

public int MenuHandler_HUD(Menu m, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char[] sCookie = new char[16];
		m.GetItem(param2, sCookie, 16);
		int iSelection = StringToInt(sCookie);

		gI_HUDSettings[param1] ^= iSelection;
		IntToString(gI_HUDSettings[param1], sCookie, 16); // string recycling Kappa

		SetClientCookie(param1, gH_HUDCookie, sCookie);

		ShowHUDMenu(param1);
	}

	else if(action == MenuAction_DisplayItem)
	{
		char[] sInfo = new char[16];
		char[] sDisplay = new char[64];
		int style = 0;
		m.GetItem(param2, sInfo, 16, style, sDisplay, 64);

		Format(sDisplay, 64, "[%s] %s", (gI_HUDSettings[param1] & StringToInt(sInfo))? "x":" ", sDisplay);

		return RedrawMenuItem(sDisplay);
	}

	else if(action == MenuAction_End)
	{
		delete m;
	}

	return 0;
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
}

public void OnConfigsExecuted()
{
	ConVar sv_hudhint_sound = FindConVar("sv_hudhint_sound");

	if(sv_hudhint_sound != null)
	{
		sv_hudhint_sound.SetBool(false);
	}
}

public Action UpdateHUD_Timer(Handle Timer)
{
	if(++gI_Cycle >= 65535)
	{
		gI_Cycle = 0;
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || !(gI_HUDSettings[i] & HUD_MASTER))
		{
			continue;
		}

		TriggerHUDUpdate(i);
	}

	return Plugin_Continue;
}

public void TriggerHUDUpdate(int client)
{
	UpdateHUD(client);
	SetEntProp(client, Prop_Data, "m_bDrawViewmodel", gI_HUDSettings[client] & HUD_HIDEWEAPON? 0:1);

	if(gSG_Type == Game_CSS)
	{
		UpdateTopLeftHUD(client, true);
	}

	if((gI_HUDSettings[client] & HUD_KEYOVERLAY || gI_HUDSettings[client] & HUD_SPECTATORS) && (!gB_Zones || !Shavit_IsClientCreatingZone(client)) && (GetClientMenu(client, null) == MenuSource_None || GetClientMenu(client, null) == MenuSource_RawPanel))
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

public void UpdateHUD(int client)
{
	int target = GetHUDTarget(client);

	if(!(gI_HUDSettings[client] & HUD_OBSERVE) && client != target)
	{
		return;
	}

	float fSpeed[3];
	GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);

	float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));

	char[] sHintText = new char[512];
	strcopy(sHintText, 512, "");

	if(gI_HUDSettings[client] & HUD_ZONEHUD)
	{
		if(Shavit_InsideZone(target, Zone_Start))
		{
			if(gSG_Type == Game_CSGO)
			{
				FormatEx(sHintText, 64, "<font size=\"45\" color=\"#%s\">Start Zone</font>", gS_StartColors[gI_Cycle % sizeof(gS_StartColors)]);
			}

			else
			{
				FormatEx(sHintText, 32, "In Start Zone\n\n%d", RoundToZero(fSpeed_New));
			}
		}

		else if(Shavit_InsideZone(target, Zone_End))
		{
			if(gSG_Type == Game_CSGO)
			{
				FormatEx(sHintText, 64, "<font size=\"45\" color=\"#%s\">End Zone</font>", gS_EndColors[gI_Cycle % sizeof(gS_EndColors)]);
			}

			else
			{
				FormatEx(sHintText, 32, "In End Zone\n\n%d", RoundToZero(fSpeed_New));
			}
		}
	}

	if(strlen(sHintText) > 0)
	{
		PrintHintText(client, sHintText);
	}

	else if(gI_HUDSettings[client] & HUD_CENTER)
	{
		if(!IsFakeClient(target))
		{
			float fTime;
			int iJumps;
			BhopStyle bsStyle;
			bool bStarted;
			Shavit_GetTimer(target, fTime, iJumps, bsStyle, bStarted);

			float fWR;
			Shavit_GetWRTime(bsStyle, fWR);

			float fPB;
			Shavit_GetPlayerPB(target, bsStyle, fPB);

			char[] sPB = new char[32];
			FormatSeconds(fPB, sPB, 32);

			char[] sTime = new char[32];
			FormatSeconds(fTime, sTime, 32, false);

			if(gSG_Type == Game_CSGO)
			{
				strcopy(sHintText, 512, "<font size=\"18\" face=\"Stratum2\">");

				if(bStarted)
				{
					char[] sColor = new char[8];

					if(fTime < fWR || fWR == 0.0)
					{
						strcopy(sColor, 8, "00FF00");
					}

					else if(fPB != 0.0 && fTime < fPB)
					{
						strcopy(sColor, 8, "FFA500");
					}

					else
					{
						strcopy(sColor, 8, "FF0000");
					}

					Format(sHintText, 512, "%sTime: <font color='#%s'>%s</font> (%d)%s", sHintText, sColor, sTime, Shavit_GetRankForTime(bsStyle, fTime), Shavit_GetTimerStatus(target) == Timer_Paused? " [PAUSED]":"");
				}

				Format(sHintText, 512, "%s\nStyle: <font color='#%s'>%s</font>", sHintText, gS_StyleHTMLColors[bsStyle], gS_BhopStyles[bsStyle]);
				Format(sHintText, 512, "%s\t%sStrafes: %d (%.02f)", sHintText, (strlen(gS_BhopStyles[bsStyle]) <= 6)? "\t":"", Shavit_GetStrafeCount(target), Shavit_GetSync(target));
				Format(sHintText, 512, "%s\nSpeed: %.02f", sHintText, fSpeed_New);

				if(bStarted)
				{
					Format(sHintText, 512, "%s\tJumps: %d", sHintText, iJumps);
				}

				Format(sHintText, 512, "%s</font>", sHintText);
			}

			else
			{
				if(bStarted)
				{
					if(Shavit_GetTimerStatus(target) == Timer_Running)
					{
						FormatEx(sHintText, 512, "%s\nTime: %s (%d)\nJumps: %d\nStrafes: %d\nSpeed: %d", gS_BhopStyles[bsStyle], sTime, Shavit_GetRankForTime(bsStyle, fTime), iJumps, Shavit_GetStrafeCount(target), RoundToZero(fSpeed_New));
					}

					else
					{
						strcopy(sHintText, 16, "[PAUSED]");
					}

					if(gI_HUDSettings[client] & HUD_SYNC)
					{
						char[] sSync = new char[16];
						FormatEx(sSync, 16, "Sync: %.02f", Shavit_GetSync(target));

						Handle hKeyHintText = StartMessageOne("KeyHintText", client);
						BfWriteByte(hKeyHintText, 1);
						BfWriteString(hKeyHintText, sSync);
						EndMessage();
					}
				}

				else
				{
					IntToString(RoundToZero(fSpeed_New), sHintText, 8);
				}
			}

			PrintHintText(client, sHintText);
		}

		else if(gB_Replay)
		{
			BhopStyle bsStyle = view_as<BhopStyle>(0);

			for(int i = 0; i < MAX_STYLES; i++)
			{
				if(Shavit_GetReplayBotIndex(view_as<BhopStyle>(i)) == target)
				{
					bsStyle = view_as<BhopStyle>(i);

					break;
				}
			}

			float fStart = 0.0;
			Shavit_GetReplayBotFirstFrame(bsStyle, fStart);

			float fTime = GetEngineTime() - fStart;

			float fWR = 0.0;
			Shavit_GetWRTime(bsStyle, fWR);

			if(fTime > fWR || !Shavit_IsReplayDataLoaded(bsStyle))
			{
				PrintHintText(client, "No replay data loaded");

				return;
			}

			char[] sTime = new char[32];
			FormatSeconds(fTime, sTime, 32, false);

			char[] sWR = new char[32];
			FormatSeconds(fWR, sWR, 32, false);

			if(gSG_Type == Game_CSGO)
			{
				FormatEx(sHintText, 512, "<font face='Stratum2'>");
				Format(sHintText, 512, "%s\t<u><font color='#%s'>%s Replay</font></u>", sHintText, gS_StyleHTMLColors[bsStyle], gS_BhopStyles[bsStyle]);
				Format(sHintText, 512, "%s\n\tTime: <font color='#00FF00'>%s</font>/%s", sHintText, sTime, sWR);
				Format(sHintText, 512, "%s\n\tSpeed: %.02f", sHintText, fSpeed_New);
				Format(sHintText, 512, "%s</font>", sHintText);
			}

			else
			{
				FormatEx(sHintText, 512, "%s Replay", gS_BhopStyles[bsStyle], sHintText);
				Format(sHintText, 512, "%s\nTime: %s/%s", sHintText, sTime, sWR);
				Format(sHintText, 512, "%s\nSpeed: %d", sHintText, RoundToZero(fSpeed_New));
			}

			PrintHintText(client, sHintText);
		}
	}
}

public void UpdateKeyOverlay(int client, Panel panel, bool &draw)
{
	if(!(gI_HUDSettings[client] & HUD_KEYOVERLAY))
	{
		return;
	}

	int target = GetHUDTarget(client);

	if((!(gI_HUDSettings[client] & HUD_OBSERVE) && client != target) || !IsValidClient(target) || IsClientObserver(target))
	{
		return;
	}

	int buttons = GetClientButtons(target);

	// that's a very ugly way, whatever :(
	char[] sPanelLine = new char[128];

	if(gI_StyleProperties[Shavit_GetBhopStyle(target)] & STYLE_AUTOBHOP) // don't include [JUMP] for autobhop styles
	{
		FormatEx(sPanelLine, 128, "[%s]\n    %s\n%s   %s   %s", buttons & IN_DUCK? "DUCK":"----", buttons & IN_FORWARD? "W":"-", buttons & IN_MOVELEFT? "A":"-", buttons & IN_BACK? "S":"-", buttons & IN_MOVERIGHT? "D":"-");
	}

	else
	{
		FormatEx(sPanelLine, 128, "[%s] [%s]\n    %s\n%s   %s   %s", buttons & IN_JUMP? "JUMP":"----", buttons & IN_DUCK? "DUCK":"----", buttons & IN_FORWARD? "W":"-", buttons & IN_MOVELEFT? "A":"-", buttons & IN_BACK? "S":"-", buttons & IN_MOVERIGHT? "D":"-");
	}

	panel.DrawItem(sPanelLine, ITEMDRAW_RAWLINE);

	draw = true;
}

public void UpdateSpectatorList(int client, Panel panel, bool &draw)
{
	if(!(gI_HUDSettings[client] & HUD_SPECTATORS))
	{
		return;
	}

	int target = GetHUDTarget(client);

	if((!(gI_HUDSettings[client] & HUD_OBSERVE) && client != target) || !IsValidClient(target))
	{
		return;
	}

	int[] iSpectatorClients = new int[MaxClients];
	int iSpectators = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(i == client || !IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") != target)
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
		FormatEx(sSpectators, 32, "%spectators (%d):", (client == target)? "S":"Other s", iSpectators);
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

			panel.DrawItem(sName, ITEMDRAW_RAWLINE);
		}

		draw = true;
	}
}

public void UpdateTopLeftHUD(int client, bool wait)
{
	if((!wait || gI_Cycle % 25 == 0) && gI_HUDSettings[client] & HUD_TOPLEFT)
	{
		int target = GetHUDTarget(client);

		BhopStyle style = Shavit_GetBhopStyle(target);

		float fWRTime = 0.0;
		Shavit_GetWRTime(style, fWRTime);

		if(fWRTime != 0.0)
		{
			char[] sWRTime = new char[16];
			FormatSeconds(fWRTime, sWRTime, 16);

			char[] sWRName = new char[MAX_NAME_LENGTH];
			Shavit_GetWRName(style, sWRName, MAX_NAME_LENGTH);

			float fPBTime = 0.0;
			Shavit_GetPlayerPB(target, style, fPBTime);

			char[] sPBTime = new char[16];
			FormatSeconds(fPBTime, sPBTime, MAX_NAME_LENGTH);

			char[] sTopLeft = new char[64];
			FormatEx(sTopLeft, 64, "WR: %s (%s)\nBest: %s", sWRTime, sWRName, fPBTime != 0.0? sPBTime:"N/A");

			SetHudTextParams(0.01, 0.01, 2.5, 255, 255, 255, 255);
			ShowSyncHudText(client, gH_HUD, sTopLeft);
		}
	}
}

public int GetHUDTarget(int client)
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

public void Shavit_OnStyleChanged(int client)
{
	UpdateTopLeftHUD(client, false);
}

public int Native_ForceHUDUpdate(Handle handler, int numParams)
{
	int[] clients = new int[MaxClients];
	int count = 0;

	int client = GetNativeCell(1);

	if(!IsValidClient(client))
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
