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

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

// game type (CS:S/CS:GO)
ServerGame gSG_Type = Game_Unknown;

bool gB_Replay = false;

bool gB_ZoneHUD[MAXPLAYERS+1] = {true, ...};
bool gB_HUD[MAXPLAYERS+1] = {true, ...};

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

// cvars
ConVar gCV_ZoneHUD = null;

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

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	gSG_Type = Shavit_GetGameType();
}

public void OnPluginStart()
{
	// prevent errors in case the replay bot isn't loaded
	gB_Replay = LibraryExists("shavit-replay");

	CreateTimer(0.1, UpdateHUD_Timer, INVALID_HANDLE, TIMER_REPEAT);

	RegConsoleCmd("sm_togglehud", Command_ToggleHUD, "Toggle the timer's HUD");
	RegConsoleCmd("sm_hud", Command_ToggleHUD, "Toggle the timer's HUD");

	RegConsoleCmd("sm_zonehud", Command_ToggleZoneHUD, "Toggle the timer's flashing zone HUD");

	// cvars
	gCV_ZoneHUD = CreateConVar("shavit_hud_zonehud", "1", "Enable \"zonehud\" server-sided? (The colored start/end zone display in CS:GO)", 0, true, 0.0, true, 1.0);

	AutoExecConfig();
}

public void OnClientPutInServer(int client)
{
	gB_HUD[client] = true;
	gB_ZoneHUD[client] = true;
}

public Action Command_ToggleHUD(int client, int args)
{
	gB_HUD[client] = !gB_HUD[client];

	Shavit_PrintToChat(client, "HUD %s\x01.", gB_HUD[client]? "\x04enabled":(gSG_Type == Game_CSGO? "\x02disabled":"\x07F54242disabled"));

	return Plugin_Handled;
}

public Action Command_ToggleZoneHUD(int client, int args)
{
	if(!gCV_ZoneHUD.BoolValue)
	{
		Shavit_PrintToChat(client, "This feature is disabled.");

		return Plugin_Handled;
	}

	if(gSG_Type != Game_CSGO)
	{
		Shavit_PrintToChat(client, "Zone HUD is not supported for this game, sorry.");

		return Plugin_Handled;
	}

	gB_ZoneHUD[client] = !gB_ZoneHUD[client];

	Shavit_PrintToChat(client, "Zone HUD %s\x01.", gB_ZoneHUD[client]? "\x04enabled":(gSG_Type == Game_CSGO? "\x02disabled":"\x07F54242disabled"));

	return Plugin_Handled;
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
	if(gCV_ZoneHUD.BoolValue && gSG_Type == Game_CSGO)
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
		if(!IsValidClient(i) || !gB_HUD[i])
		{
			continue;
		}

		UpdateHUD(i);
	}

	return Plugin_Continue;
}

public void UpdateHUD(int client)
{
	int target = client;

	if(IsClientObserver(client))
	{
		if(GetEntProp(client, Prop_Send, "m_iObserverMode") >= 3)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if(IsValidClient(iTarget, true))
			{
				target = iTarget;
			}
		}
	}

	char[] sHintText = new char[512];

	bool bZoneHUD = false;

	if(gCV_ZoneHUD.BoolValue && gB_ZoneHUD[client] && gSG_Type == Game_CSGO)
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

	else if(!IsFakeClient(target))
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
