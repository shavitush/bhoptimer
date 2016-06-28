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

#define USES_STYLE_NAMES
#define USES_STYLE_HTML_COLORS
#include <shavit>
#include <clientprefs>

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

#define HUD_NONE				(0)
#define HUD_MASTER				(1 << 0) // master setting
#define HUD_CENTER				(1 << 1) // show hud as hint text
#define HUD_ZONEHUD				(1 << 2) // show colored start/end zone hud (csgo only)
#define HUD_OBSERVE				(1 << 3) // show the HUD of the player you spectate
#define HUD_SPECTATORS			(1 << 4) // show list of spectators
#define HUD_KEYOVERLAY			(1 << 5) // show a key overlay
#define HUD_HIDEWEAPON			(1 << 6) // hide the player's weapon

#define HUD_DEFAULT				(HUD_MASTER|HUD_CENTER|HUD_ZONEHUD|HUD_OBSERVE)

// game type (CS:S/CS:GO)
ServerGame gSG_Type = Game_Unknown;

bool gB_Replay = false;

int gI_StartCycle = 0;

char gS_StartColors[][] =
{
	"ff0000", "ff4000", "ff7f00", "ffbf00", "ffff00", "00ff00", "00ff80", "00ffff", "0080ff", "0000ff"
};

int gI_EndCycle = 0;

char gS_EndColors[][] =
{
	"ff0000", "ff4000", "ff7f00", "ffaa00", "ffd400", "ffff00", "bba24e", "77449c"
};

Handle gH_HUDCookie = null;
int gI_HUDSettings[MAXPLAYERS+1];
int gI_NameLength = MAX_NAME_LENGTH;

public Plugin myinfo =
{
	name = "[shavit] HUD",
	author = "shavit",
	description = "HUD for shavit's bhop timer.",
	version = SHAVIT_VERSION,
	url = "http://forums.alliedmods.net/member.php?u=163134"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Shavit_GetReplayBotFirstFrame");
	MarkNativeAsOptional("Shavit_GetReplayBotIndex");

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

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	gSG_Type = Shavit_GetGameType();

	if(gSG_Type == Game_CSS)
	{
		gI_NameLength = MAX_NAME_LENGTH;
	}

	else
	{
		gI_NameLength = 14; // 14 because long names will make it look spammy in CS:GO due to the font
	}
}

public void OnPluginStart()
{
	// prevent errors in case the replay bot isn't loaded
	gB_Replay = LibraryExists("shavit-replay");

	CreateTimer(0.1, UpdateHUD_Timer, INVALID_HANDLE, TIMER_REPEAT);

	RegConsoleCmd("sm_hud", Command_HUD, "Opens the HUD settings menu");

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
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-replay"))
	{
		gB_Replay = false;
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
	if(gSG_Type == Game_CSGO)
	{
		gI_StartCycle++;

		if(gI_StartCycle > (sizeof(gS_StartColors) - 1))
		{
			gI_StartCycle = 0;
		}

		gI_EndCycle++;

		if(gI_EndCycle > (sizeof(gS_EndColors) - 1))
		{
			gI_EndCycle = 0;
		}
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || !(gI_HUDSettings[i] & HUD_MASTER))
		{
			continue;
		}

		UpdateHUD(i);
		SetEntProp(i, Prop_Data, "m_bDrawViewmodel", gI_HUDSettings[i] & HUD_HIDEWEAPON? 0:1);

		if((GetClientMenu(i, null) == MenuSource_None || GetClientMenu(i, null) == MenuSource_RawPanel) && (gI_HUDSettings[i] & HUD_KEYOVERLAY || gI_HUDSettings[i] & HUD_SPECTATORS))
		{
			bool bShouldDraw = false;
			Panel pHUD = new Panel();

			UpdateKeyOverlay(i, pHUD, bShouldDraw);
			pHUD.DrawItem("", ITEMDRAW_RAWLINE);

			UpdateSpectatorList(i, pHUD, bShouldDraw);

			if(bShouldDraw)
			{
				pHUD.Send(i, PanelHandler_Nothing, 1);
			}

			delete pHUD;
		}
	}

	return Plugin_Continue;
}

public void UpdateHUD(int client)
{
	int target = GetHUDTarget(client);

	if(!(gI_HUDSettings[client] & HUD_OBSERVE) && client != target)
	{
		return;
	}

	char[] sHintText = new char[512];

	bool bZoneHUD = false;

	if(gI_HUDSettings[client] & HUD_ZONEHUD && gSG_Type == Game_CSGO)
	{
		if(Shavit_InsideZone(target, Zone_Start))
		{
			FormatEx(sHintText, 512, "<font size=\"45\" color=\"#%s\">Start Zone</font>", gS_StartColors[gI_StartCycle]);
			bZoneHUD = true;
		}

		else if(Shavit_InsideZone(target, Zone_End))
		{
			FormatEx(sHintText, 512, "<font size=\"45\" color=\"#%s\">End Zone</font>", gS_EndColors[gI_EndCycle]);
			bZoneHUD = true;
		}
	}

	if(bZoneHUD)
	{
		PrintHintText(client, sHintText);
	}

	else if(gI_HUDSettings[client] & HUD_CENTER && !IsFakeClient(target))
	{
		float fTime;
		int iJumps;
		BhopStyle bsStyle;
		bool bStarted;
		Shavit_GetTimer(target, fTime, iJumps, bsStyle, bStarted);

		float fWR;
		Shavit_GetWRTime(bsStyle, fWR);

		float fSpeed[3];
		GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);

		float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));

		float fPB;
		Shavit_GetPlayerPB(target, bsStyle, fPB);

		char[] sPB = new char[32];
		FormatSeconds(fPB, sPB, 32);

		char[] sTime = new char[32];
		FormatSeconds(fTime, sTime, 32, false);

		if(gSG_Type == Game_CSGO)
		{
			strcopy(sHintText, 512, "<font face='Stratum2'>");

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

				Format(sHintText, 512, "%sTime: <font color='#%s'>%s</font>", sHintText, sColor, sTime);
			}

			Format(sHintText, 512, "%s\nStyle: <font color='#%s'>%s</font>", sHintText, gS_StyleHTMLColors[bsStyle], gS_BhopStyles[bsStyle]);

			if(fPB > 0.00)
			{
				Format(sHintText, 512, "%s\tPB: %s", sHintText, sPB);
			}

			Format(sHintText, 512, "%s\nSpeed: %.02f%s", sHintText, fSpeed_New, fSpeed_New < 10? "\t":"");

			if(bStarted)
			{
				Format(sHintText, 512, "%s\tJumps: %d", sHintText, iJumps);
			}

			Format(sHintText, 512, "%s\nPlayer: <font color='#BF6821'>%N</font>", sHintText, target);

			Format(sHintText, 512, "%s</font>", sHintText);
		}

		else
		{
			if(bStarted)
			{
				FormatEx(sHintText, 512, "Time: %s", sTime);

				Format(sHintText, 512, "%s\nStyle: %s", sHintText, gS_BhopStyles[bsStyle]);
			}

			else
			{
				FormatEx(sHintText, 512, "Style: %s", gS_BhopStyles[bsStyle]);
			}

			if(fPB > 0.00)
			{
				Format(sHintText, 512, "%s\nPB: %s", sHintText, sPB);
			}

			Format(sHintText, 512, "%s\nSpeed: %.02f%s", sHintText, fSpeed_New, fSpeed_New < 10? "\t":"");

			if(bStarted)
			{
				Format(sHintText, 512, "%s\nJumps: %d", sHintText, iJumps);
			}

			Format(sHintText, 512, "%s\nPlayer: %N", sHintText, target);
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

		/* I give up, please someone else do it
		float fStart = 0.0;
		Shavit_GetReplayBotFirstFrame(bsStyle, fStart);

		float fTime = GetEngineTime() - fStart;

		float fWR;
		Shavit_GetWRTime(bsStyle, fWR);

		if(fTime - 1.0 > fWR) // 1.0 - safety check
		{
			PrintHintText(client, "No replay data loaded");

			return;
		}

		char sWR[32];
		FormatSeconds(fWR, sWR, 32, false);

		char sTime[32];
		FormatSeconds(fTime, sTime, 32, false);*/

		float fSpeed[3];
		GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);

		float fSpeed_New = SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0));

		if(gSG_Type == Game_CSGO)
		{
			FormatEx(sHintText, 512, "<font face='Stratum2'>");
			Format(sHintText, 512, "%s\t<u><font color='#%s'>%s Replay</font></u>", sHintText, gS_StyleHTMLColors[bsStyle], gS_BhopStyles[bsStyle]);
			Format(sHintText, 512, "%s\n\tSpeed: %.02f", sHintText, fSpeed_New);
			Format(sHintText, 512, "%s</font>", sHintText);
		}

		else
		{
			FormatEx(sHintText, 512, "\t- %s Replay -", gS_BhopStyles[bsStyle], sHintText);
			Format(sHintText, 512, "%s\nSpeed: %.02f", sHintText, fSpeed_New);
		}

		PrintHintText(client, sHintText);
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
	FormatEx(sPanelLine, 128, "[%s] [%s]\n    %s\n%s   %s   %s", buttons & IN_JUMP? "JUMP":"----", buttons & IN_DUCK? "DUCK":"----", buttons & IN_FORWARD? "W":"-", buttons & IN_MOVELEFT? "A":"-", buttons & IN_BACK? "S":"-", buttons & IN_MOVERIGHT? "D":"-");
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
		if(i == client || !IsValidClient(i) || !IsClientObserver(i) || GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") != target)
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
		FormatEx(sSpectators, 32, "%spectators (%d):", client == target? "S":"Other s", iSpectators);
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
