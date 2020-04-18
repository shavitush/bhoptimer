#pragma semicolon 1

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <shavit>
#include <smlib/entities>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "TAS Style",
	author = "Charles_(hypnos)",
	description = "TAS Style",
	version = "1.9.2",
	url = "https://hyps.dev/"
}

#define RUN 0
#define PAUSED 1
#define BACKWARD 2
#define FORWARD 3

#define AutoStrafeTrigger 1

int gi_Status[MAXPLAYERS+1];
Handle gh_Frames[MAXPLAYERS+1];
int gi_IndexCounter[MAXPLAYERS+1];
float gf_IndexCounter[MAXPLAYERS+1];
float gf_CounterSpeed[MAXPLAYERS+1];
bool gb_TASMenu[MAXPLAYERS+1];
float gf_TickRate;
float gf_TASTime[MAXPLAYERS+1];
float gf_TimeScale[MAXPLAYERS+1];
float gf_TimescaleTicksPassed[MAXPLAYERS+1];
int gi_LastButtons[MAXPLAYERS+1];

bool AutoStrafeEnabled[MAXPLAYERS + 1] = {false,...};
bool g_Strafing[MAXPLAYERS + 1];

float flYawBhop[MAXPLAYERS + 1];
float truevel[MAXPLAYERS + 1];
bool DirIsRight[MAXPLAYERS + 1];
int StrafeAxis[MAXPLAYERS + 1] = {1,...};
float AngDiff[MAXPLAYERS + 1];

bool g_bTAS[MAXPLAYERS + 1];

EngineVersion g_Engine = Engine_Unknown;

public void OnPluginStart() {
	g_Engine = GetEngineVersion();

	for (int i = 1; i <= MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}

	AddCommandListener(Listener, "");
	AddCommandListener(jointeam, "jointeam");
	AddCommandListener(sm_tas, "sm_tas");
	RegConsoleCmd("sm_tasmenu", Command_TASMenu);
	RegConsoleCmd("sm_tashelp", Command_TASHelp);

	gf_TickRate = (1.0 / GetTickInterval());

	RegConsoleCmd("sm_plusone", Command_PlusOne, "TAS adjustment +1 tick");
	RegConsoleCmd("sm_minusone", Command_MinusOne, "TAS adjustment -1 tick");
	
	RegConsoleCmd("+autostrafer", PlusStrafer, "");
	RegConsoleCmd("-autostrafer", MinusStrafer, "");
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle) {
	char[] sSpecial = new char[128];
	Shavit_GetStyleStrings(newstyle, sSpecialString, sSpecial, 128);

	if(StrContains(sSpecial, "tas", false) == -1) { //off
		g_bTAS[client] = false;
	}
	else { //on
		g_bTAS[client] = true;
		Shavit_PrintToChat(client, "This is a TAS style. Type !tashelp for more information.");
	}
}

public Action PlusStrafer(int client, int args) {
	g_Strafing[client] = true;
	return;
}

public Action MinusStrafer(int client, int args) {
	g_Strafing[client] = false;
	return;
}

public Action Command_PlusOne(int client, int args) {
	if(gi_Status[client] == PAUSED) {
		int frameSize = GetArraySize(gh_Frames[client]);
		int framenum = gi_IndexCounter[client];
		if(frameSize > 1 && framenum < frameSize-1) {
			float fAng[3];
			fAng[0] = GetArrayCell(gh_Frames[client], framenum, 3);
			fAng[1] = GetArrayCell(gh_Frames[client], framenum, 4);
			fAng[2] = 0.0;
			
			float pos2[3];
			pos2[0] = GetArrayCell(gh_Frames[client], framenum, 0);
			pos2[1] = GetArrayCell(gh_Frames[client], framenum, 1);
			pos2[2] = GetArrayCell(gh_Frames[client], framenum, 2);

			float pos[3];
			pos[0] = GetArrayCell(gh_Frames[client], framenum-1, 0);
			pos[1] = GetArrayCell(gh_Frames[client], framenum-1, 1);
			pos[2] = GetArrayCell(gh_Frames[client], framenum-1, 2);

			float fVel[3];
			MakeVectorFromPoints(pos, pos2, fVel);

			for (int i = 0; i < 3; i++) {
				fVel[i] *= RoundToFloor(gf_TickRate);
			}

			TeleportEntity(client, pos2, fAng, fVel);

			if(GetArrayCell(gh_Frames[client], framenum, 5) & IN_DUCK) {
				SetEntProp(client, Prop_Send, "m_bDucked", true);
				SetEntProp(client, Prop_Send, "m_bDucking", true);
			}
			else {
				SetEntProp(client, Prop_Send, "m_bDucked", false);
				SetEntProp(client, Prop_Send, "m_bDucking", false);
			}

			gf_IndexCounter[client] += gf_CounterSpeed[client];
			if(isRound(gf_IndexCounter[client])) {
				gi_IndexCounter[client]++;
			}
			gf_TASTime[client] += GetTickInterval() * gf_CounterSpeed[client];
		}
	} else { //TAS Status must be PAUSED to use this function
		Shavit_PrintToChat(client, "sm_plusone can only be used when TAS is Paused!");
	}
	return Plugin_Handled;
}

public Action Command_MinusOne(int client, int args) {
	if(gi_Status[client] == PAUSED) {
		int frameSize = GetArraySize(gh_Frames[client]);
		int framenum = gi_IndexCounter[client];
		if(frameSize > 1 && framenum > 2) {
			float fAng[3];
			fAng[0] = GetArrayCell(gh_Frames[client], framenum, 3);
			fAng[1] = GetArrayCell(gh_Frames[client], framenum, 4);
			fAng[2] = 0.0;
			
			float pos2[3];
			pos2[0] = GetArrayCell(gh_Frames[client], framenum, 0);
			pos2[1] = GetArrayCell(gh_Frames[client], framenum, 1);
			pos2[2] = GetArrayCell(gh_Frames[client], framenum, 2);

			float pos[3];
			pos[0] = GetArrayCell(gh_Frames[client], framenum-1, 0);
			pos[1] = GetArrayCell(gh_Frames[client], framenum-1, 1);
			pos[2] = GetArrayCell(gh_Frames[client], framenum-1, 2);

			float fVel[3];
			MakeVectorFromPoints(pos2, pos, fVel);

			for (int i = 0; i < 3; i++) {
				fVel[i] *= RoundToFloor(gf_TickRate);
			}

			TeleportEntity(client, pos, fAng, fVel);

			if(GetArrayCell(gh_Frames[client], framenum, 5) & IN_DUCK) {
				SetEntProp(client, Prop_Send, "m_bDucked", true);
				SetEntProp(client, Prop_Send, "m_bDucking", true);
			}
			else {
				SetEntProp(client, Prop_Send, "m_bDucked", false);
				SetEntProp(client, Prop_Send, "m_bDucking", false);
			}

			gf_IndexCounter[client] -= gf_CounterSpeed[client];
			if(isRound(gf_IndexCounter[client]))
				gi_IndexCounter[client]--;
			gf_TASTime[client] -= GetTickInterval() * gf_CounterSpeed[client];
		}
	} else { //TAS Status must be PAUSED to use this function
		Shavit_PrintToChat(client, "sm_minusone can only be used when TAS is Paused!");
	}
	return Plugin_Handled;
}

public Action Command_TASMenu(int client, int args) {
	gb_TASMenu[client] = !gb_TASMenu[client];
	return Plugin_Handled;
}

public Action Command_TASHelp(int client, int args) {
	PrintToChat(client, "TAS Guide:\nRecommended Binds:\nbind mwheelup sm_minusone\nbind mwheeldown sm_plusone\nbind mouse1 +rewind\nbind mouse2 +fastforward\n\nOther Commands:\n+autostrafer - When bound hold to use wigglehack\n!tasmenu - Toggles TAS Menu");
	return Plugin_Handled;
}

public Action sm_tas(int client, const char[] command, int args)
{
	gb_TASMenu[client] = true;
	return Plugin_Continue;
}

public Action jointeam(int client, const char[] command, int args)
{
	if(g_bTAS[client]) {
		gi_Status[client] = RUN;
		gf_TASTime[client] = 0.0;
		gi_IndexCounter[client] = 0;
		FakeClientCommandEx(client, "sm_r");
	}
	return Plugin_Continue;
}

public Action Listener(int client, const char[] command, int args)
{
	if(!g_bTAS[client])
	{
		return Plugin_Continue;
	}
	if(StrEqual(command, "+rewind"))
	{
		gi_Status[client] = BACKWARD;
		return Plugin_Handled;
	}
	else if(StrEqual(command, "+fastforward"))
	{
		gi_Status[client] = FORWARD;
		return Plugin_Handled;
	}
	else if(StrEqual(command, "-rewind") || StrEqual(command, "-fastforward"))
	{
		gi_Status[client] = PAUSED;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	if(gh_Frames[client] != INVALID_HANDLE)
		ClearArray(gh_Frames[client]);
	else
		gh_Frames[client] = CreateArray(11, 0);

	gf_CounterSpeed[client] = 1.0;
	gf_TASTime[client] = 0.0;
	gf_TimeScale[client] = 1.0;
	gi_Status[client] = RUN;
	gb_TASMenu[client] = true;
	AutoStrafeEnabled[client] = false;
	g_Strafing[client] = false;
}


float GetClientVelo(int client)
{
	float vVel[3];
	
	vVel[0] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[0]");
	vVel[1] = GetEntPropFloat(client, Prop_Send, "m_vecVelocity[1]");
	
	
	return GetVectorLength(vVel);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (IsClientInGame(client) && !IsClientSourceTV(client) && !IsClientReplay(client) && IsClientConnected(client) && GetClientMenu(client) == MenuSource_None && g_bTAS[client] && IsPlayerAlive(client))
	{
		DrawPanel(client);
	}

	if(IsClientInGame(client))
	{
		if(!g_bTAS[client])
		{
			return Plugin_Continue;
		}

		if(Shavit_GetTimerStatus(client) != Timer_Running) {
			return Plugin_Continue;
		} else if(IsPlayerAlive(client) && !IsFakeClient(client)) {
			if(gi_Status[client] == RUN) { // Record Frames
				SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", gf_TimeScale[client]);
				float fTimescale = GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
				gf_TimescaleTicksPassed[client] += fTimescale;
				truevel[client] = GetClientVelo(client);
				/*
							AUTO STRAFER START
														*/
				if(buttons & IN_FORWARD && vel[0] <= 50.0)
					vel[0] = 450.0;

				float yaw_change = 0.0;
				if(vel[0] > 50.0)
					yaw_change = 30.0 * FloatAbs(30.0 / vel[0]);

				if (AutoStrafeEnabled[client] == true && Shavit_GetTimerStatus(client) == Timer_Running && g_bTAS[client] && !(GetEntityFlags(client) & FL_ONGROUND) && (GetEntityMoveType(client) != MOVETYPE_NOCLIP) && !(buttons & IN_FORWARD) && !(buttons & IN_BACK) && !(buttons & IN_MOVELEFT) && !(buttons & IN_MOVERIGHT))
				{
					if(mouse[0] > 0)
					{
						angles[1] += yaw_change;
						//buttons |= IN_MOVERIGHT;
						if(g_Engine == Engine_CSS) {
							vel[1] = 400.0;
						} else if(g_Engine == Engine_CSGO){
							vel[1] = 450.0;
						}
					}
					else if(mouse[0] < 0)
					{
						angles[1] -= yaw_change;
						//buttons |= IN_MOVELEFT;
						if(g_Engine == Engine_CSS) {
							vel[1] = -400.0;
						} else if(g_Engine == Engine_CSGO){
							vel[1] = -450.0;
						}
					}
				}
				/*
							AUTO STRAFER END
														*/

				/*
							WIGGLEHACK START
														*/
				if (g_Strafing[client] == true && Shavit_GetTimerStatus(client) == Timer_Running && g_bTAS[client] && !(GetEntityFlags(client) & FL_ONGROUND) && (GetEntityMoveType(client) != MOVETYPE_NOCLIP) && !(buttons & IN_FORWARD) && !(buttons & IN_BACK) && !(buttons & IN_MOVELEFT) && !(buttons & IN_MOVERIGHT))
				{
					if(gf_TimescaleTicksPassed[client] >= 1.0) {
						//Don't subtract 1 from gf_TimescaleTicksPassed[client] because it happens later and this code won't always run depending on if wiggle hack is on.

						if(AngDiff[client] < AutoStrafeTrigger * -1) {
							if(g_Engine == Engine_CSS) {
								vel[StrafeAxis[client]] = -400.0;
							} else if(g_Engine == Engine_CSGO){
								vel[StrafeAxis[client]] = -450.0;
							}
						}
						else if(AngDiff[client] > AutoStrafeTrigger) {
							if(g_Engine == Engine_CSS) {
								vel[StrafeAxis[client]] = 400.0;
							} else if(g_Engine == Engine_CSGO){
								vel[StrafeAxis[client]] = 450.0;
							}
						} else if (!(GetEntityFlags(client) & FL_ONGROUND) && (GetEntityMoveType(client) != MOVETYPE_NOCLIP)) {
							if (!(truevel[client] == 0.0)) {
								flYawBhop[client] = 0.0;
								float x = 30.0;
								float y = truevel[client];
								float z = x/y;
								z = FloatAbs(z);
								flYawBhop[client] = x * z;
							}
						
							if (DirIsRight[client] == true) {
								angles[1] += flYawBhop[client];
								//buttons |= ~IN_MOVERIGHT;
								DirIsRight[client] = false;
								if(g_Engine == Engine_CSS) {
									vel[StrafeAxis[client]] = 400.0;
								} else if(g_Engine == Engine_CSGO){
									vel[StrafeAxis[client]] = 450.0;
								}
							}
							else {
								angles[1] -= flYawBhop[client];
								//buttons |= ~IN_MOVELEFT;
								DirIsRight[client] = true;
								if(g_Engine == Engine_CSS) {
									vel[StrafeAxis[client]] = -400.0;
								} else if(g_Engine == Engine_CSGO){
									vel[StrafeAxis[client]] = -450.0;
								}
							}
						}
					}
				}
				/*
							WIGGLEHACK END
														*/

				if(gf_TimescaleTicksPassed[client] >= 1.0) {
					gf_TimescaleTicksPassed[client] -= 1.0;

					gf_TASTime[client] += GetTickInterval();

					int framenum = GetArraySize(gh_Frames[client])+1;
					if(gi_IndexCounter[client] != framenum-2) {
						//UnPaused in diff tick
						framenum = gi_IndexCounter[client]+1;
					}
					ResizeArray(gh_Frames[client], framenum);
					
					float lpos[3];
					float lang[3];
					float vVel[3];

					GetEntPropVector(client, Prop_Send, "m_vecOrigin", lpos);
					GetClientEyeAngles(client, lang);
					Entity_GetAbsVelocity(client, vVel);

					SetArrayCell(gh_Frames[client], framenum-1, lpos[0], 0);
					SetArrayCell(gh_Frames[client], framenum-1, lpos[1], 1);
					SetArrayCell(gh_Frames[client], framenum-1, lpos[2], 2);
					SetArrayCell(gh_Frames[client], framenum-1, lang[0], 3);
					SetArrayCell(gh_Frames[client], framenum-1, lang[1], 4);
					SetArrayCell(gh_Frames[client], framenum-1, buttons, 5);
					SetArrayCell(gh_Frames[client], framenum-1, GetEntityFlags(client), 6);
					SetArrayCell(gh_Frames[client], framenum-1, GetEntityMoveType(client), 7);
					SetArrayCell(gh_Frames[client], framenum-1, vVel[0], 8);
					SetArrayCell(gh_Frames[client], framenum-1, vVel[1], 9);
					SetArrayCell(gh_Frames[client], framenum-1, vVel[2], 10);
					gi_IndexCounter[client] = framenum-1;
					gf_IndexCounter[client] = framenum-1.0;
				} else if(!(GetEntityFlags(client) & FL_ONGROUND)) {
					vel[0] = 0.0;
					vel[1] = 0.0;
				}

				// Fix boosters
				if(GetEntityFlags(client) & FL_BASEVELOCITY)
				{
					float vBaseVel[3];
					Entity_GetBaseVelocity(client, vBaseVel);
					
					if(vBaseVel[2] > 0)
					{
						vBaseVel[2] *= 1.0 / GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
					}
					
					Entity_SetBaseVelocity(client, vBaseVel);
				}
			} else if(gi_Status[client] == PAUSED) {
				if(!(gi_LastButtons[client] & IN_JUMP) && (buttons & IN_JUMP)) {
					gi_Status[client] = RUN;
					ResumePlayer(client);
				} else {
					vel[0] = 0.0;
					vel[1] = 0.0;
					vel[2] = 0.0;
					int frameSize = GetArraySize(gh_Frames[client]);
					int framenum = gi_IndexCounter[client];
					if(frameSize > 1 && framenum > 1) {
						float fAng[3];
						fAng[0] = GetArrayCell(gh_Frames[client], framenum, 3);
						fAng[1] = GetArrayCell(gh_Frames[client], framenum, 4);
						fAng[2] = 0.0;
						
						float pos[3];
						pos[0] = GetArrayCell(gh_Frames[client], framenum, 0);
						pos[1] = GetArrayCell(gh_Frames[client], framenum, 1);
						pos[2] = GetArrayCell(gh_Frames[client], framenum, 2);

						TeleportEntity(client, pos, fAng, view_as<float>({0.0, 0.0, 0.0}));
						//gf_TASTime[client] -= GetTickInterval();

						if(GetArrayCell(gh_Frames[client], framenum, 6) & FL_DUCKING) {
							SetEntProp(client, Prop_Send, "m_bDucked", true);
							SetEntProp(client, Prop_Send, "m_bDucking", true);
							buttons |= IN_DUCK;
						} else {
							SetEntProp(client, Prop_Send, "m_bDucked", false);
							SetEntProp(client, Prop_Send, "m_bDucking", false);
						}

						SetEntityFlags(client, GetArrayCell(gh_Frames[client], framenum, 6));
					}

					if(GetEntityFlags(client) & FL_ONGROUND)
						buttons &= ~IN_JUMP;
				}
			} else if(gi_Status[client] == BACKWARD) {
				vel[0] = 0.0;
				vel[1] = 0.0;
				vel[2] = 0.0;
				int frameSize = GetArraySize(gh_Frames[client]);
				int framenum = gi_IndexCounter[client];
				if(frameSize > 1 && framenum > 2) {
					float fAng[3];
					fAng[0] = GetArrayCell(gh_Frames[client], framenum, 3);
					fAng[1] = GetArrayCell(gh_Frames[client], framenum, 4);
					fAng[2] = 0.0;
					
					float pos2[3];
					pos2[0] = GetArrayCell(gh_Frames[client], framenum, 0);
					pos2[1] = GetArrayCell(gh_Frames[client], framenum, 1);
					pos2[2] = GetArrayCell(gh_Frames[client], framenum, 2);

					float pos[3];
					pos[0] = GetArrayCell(gh_Frames[client], framenum-1, 0);
					pos[1] = GetArrayCell(gh_Frames[client], framenum-1, 1);
					pos[2] = GetArrayCell(gh_Frames[client], framenum-1, 2);

					float fVel[3];
					MakeVectorFromPoints(pos2, pos, fVel);

					for (int i = 0; i < 3; i++) {
						fVel[i] *= RoundToFloor(gf_TickRate);
					}

					TeleportEntity(client, pos, fAng, fVel);

					gf_IndexCounter[client] -= gf_CounterSpeed[client];
					if(isRound(gf_IndexCounter[client]))
						gi_IndexCounter[client]--;
					gf_TASTime[client] -= GetTickInterval() * gf_CounterSpeed[client];
				}
				else if(frameSize > 1) {
					gi_Status[client] = PAUSED;
				}
			}
			else if(gi_Status[client] == FORWARD) {
				vel[0] = 0.0;
				vel[1] = 0.0;
				vel[2] = 0.0;
				int frameSize = GetArraySize(gh_Frames[client]);
				int framenum = gi_IndexCounter[client];
				if(frameSize > 1 && framenum < frameSize-1) {
					float fAng[3];
					fAng[0] = GetArrayCell(gh_Frames[client], framenum, 3);
					fAng[1] = GetArrayCell(gh_Frames[client], framenum, 4);
					fAng[2] = 0.0;
					
					float pos2[3];
					pos2[0] = GetArrayCell(gh_Frames[client], framenum, 0);
					pos2[1] = GetArrayCell(gh_Frames[client], framenum, 1);
					pos2[2] = GetArrayCell(gh_Frames[client], framenum, 2);

					float pos[3];
					pos[0] = GetArrayCell(gh_Frames[client], framenum-1, 0);
					pos[1] = GetArrayCell(gh_Frames[client], framenum-1, 1);
					pos[2] = GetArrayCell(gh_Frames[client], framenum-1, 2);

					float fVel[3];
					MakeVectorFromPoints(pos, pos2, fVel);

					for (int i = 0; i < 3; i++) {
						fVel[i] *= RoundToFloor(gf_TickRate);
					}

					TeleportEntity(client, pos2, fAng, fVel);

					gf_IndexCounter[client] += gf_CounterSpeed[client];
					if(isRound(gf_IndexCounter[client])) {
						gi_IndexCounter[client]++;
					}
					gf_TASTime[client] += GetTickInterval() * gf_CounterSpeed[client];
				}
				else if(frameSize > 1) {
					gi_Status[client] = PAUSED;
				}
			} else {
				vel[0] = 0.0;
				vel[1] = 0.0;
				vel[2] = 0.0;
				gi_Status[client] = PAUSED;
			}
		}
	}
	gi_LastButtons[client] = buttons;
	return Plugin_Continue;
}

bool DrawPanel(int client)
{
	if(!gb_TASMenu[client] || !g_bTAS[client])
		return false;
	Handle hPanel = CreatePanel();

	DrawPanelText(hPanel, "Tool Assisted Speedrun:\n ");
	if(gi_Status[client] == PAUSED)
		DrawPanelItem(hPanel, "Resume");
	else
		DrawPanelItem(hPanel, "Pause");

	if(gi_Status[client] != BACKWARD)
		DrawPanelItem(hPanel, "+rewind");
	else
		DrawPanelItem(hPanel, "-rewind");

	if(gi_Status[client] != FORWARD)
		DrawPanelItem(hPanel, "+fastforward");
	else
		DrawPanelItem(hPanel, "-fastforward");

	char sBuffer[256];
	FormatEx(sBuffer, sizeof(sBuffer), "Timescale: %.01f", gf_TimeScale[client]);
	DrawPanelItem(hPanel, sBuffer);
	/* FormatEx(sBuffer, sizeof(sBuffer), "Edit Speed: %.01f", gf_CounterSpeed[client]);
	DrawPanelItem(hPanel, sBuffer); */

	DrawPanelText(hPanel, " ");

	SetPanelCurrentKey(hPanel, 5);
	FormatEx(sBuffer, sizeof(sBuffer), "Toggle autostrafe %s", AutoStrafeEnabled[client]?"[ON]":"[OFF]");
	DrawPanelItem(hPanel, sBuffer);
	
	FormatEx(sBuffer, sizeof(sBuffer), "Toggle wigglehack %s", g_Strafing[client]?"[ON]":"[OFF]");
	DrawPanelItem(hPanel, sBuffer);
	
	DrawPanelText(hPanel, " ");
	DrawPanelText(hPanel, "----------------------------");
	DrawPanelText(hPanel, " ");

	SetPanelCurrentKey(hPanel, 8);
	DrawPanelItem(hPanel, "Restart");
	DrawPanelItem(hPanel, "Exit");
	SendPanelToClient(hPanel, client, Panel_Handler, MENU_TIME_FOREVER);
	return true;
}

public int Panel_Handler(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!g_bTAS[param1])
		{
			gb_TASMenu[param1] = false;
			return;
		}
		if(Shavit_GetTimerStatus(param1) == Timer_Running)
		{
			if(param2 == 1)
			{
				if(gi_Status[param1] == PAUSED)
				{
					gi_Status[param1] = RUN;
					ResumePlayer(param1);
				}
				else
				{
					if(Shavit_InsideZone(param1, Zone_Start, -1))
						return;

					gi_Status[param1] = PAUSED;
				}
			}
			else if(param2 == 2)
			{
				if(Shavit_InsideZone(param1, Zone_Start, -1))
					return;

				if(gi_Status[param1] != BACKWARD)
				{
					gi_Status[param1] = BACKWARD;
				}
				else
				{
					//ResumePlayer(param1);
					//gi_Status[param1] = RUN;
					gi_Status[param1] = PAUSED;
				}
			}
			else if(param2 == 3)
			{
				if(Shavit_InsideZone(param1, Zone_Start, -1))
					return;

				if(gi_Status[param1] != FORWARD)
				{
					gi_Status[param1] = FORWARD;
				}
				else
				{
					//ResumePlayer(param1);
					//gi_Status[param1] = RUN;
					gi_Status[param1] = PAUSED;
				}
			}
			/* else if(param2 == 4)
			{
				gf_IndexCounter[param1] = 1.0 * RoundToFloor(gf_IndexCounter[param1]);
				gf_CounterSpeed[param1] += 1.0;
				if(gf_CounterSpeed[param1] >= 4.0)
					gf_CounterSpeed[param1] = 1.0;
			} */
			else if(param2 == 5) {
				AutoStrafeEnabled[param1] = !AutoStrafeEnabled[param1];
			}
			else if(param2 == 6) {
				g_Strafing[param1] = !g_Strafing[param1];
			}
			else if(param2 == 4) {
				if(!Shavit_InsideZone(param1, Zone_Start, -1) && gi_Status[param1] == RUN){
					Shavit_PrintToChat(param1, "Timescale can only be updated when paused or inside the start zone!");
					return;
				}

				gf_TimeScale[param1] += 0.1;
				if(gf_TimeScale[param1] >= 1.1)
					gf_TimeScale[param1] = 0.2;
	
				SetEntPropFloat(param1, Prop_Send, "m_flLaggedMovementValue", gf_TimeScale[param1]);
			}
			else if(param2 == 8)
			{
				gi_Status[param1] = RUN;
				gf_TASTime[param1] = 0.0;
				gi_IndexCounter[param1] = 0;
				FakeClientCommandEx(param1, "sm_r"); //TODO: Check track, if bonus use sm_b
			}
			else if(param2 == 9)
			{
				gb_TASMenu[param1] = false;
				Shavit_PrintToChat(param1, "Type !tasmenu to reopen the menu.");
			}
		}
	}
}

public void ResumePlayer(int client)
{
	int frameSize = GetArraySize(gh_Frames[client]);
	int framenum = gi_IndexCounter[client];
	if(frameSize > 1 && framenum > 1)
	{
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));

		float fAng[3];
		fAng[0] = GetArrayCell(gh_Frames[client], framenum, 3);
		fAng[1] = GetArrayCell(gh_Frames[client], framenum, 4);
		fAng[2] = 0.0;
		
		float pos2[3];
		pos2[0] = GetArrayCell(gh_Frames[client], framenum, 0);
		pos2[1] = GetArrayCell(gh_Frames[client], framenum, 1);
		pos2[2] = GetArrayCell(gh_Frames[client], framenum, 2);

		float pos[3];
		pos[0] = GetArrayCell(gh_Frames[client], framenum-1, 0);
		pos[1] = GetArrayCell(gh_Frames[client], framenum-1, 1);
		pos[2] = GetArrayCell(gh_Frames[client], framenum-1, 2);
		
		float fVel[3];
		fVel[0] = GetArrayCell(gh_Frames[client], framenum, 8);
		fVel[1] = GetArrayCell(gh_Frames[client], framenum, 9);
		fVel[2] = GetArrayCell(gh_Frames[client], framenum, 10);

		TeleportEntity(client, pos2, fAng, fVel);

		if(GetArrayCell(gh_Frames[client], framenum, 6) & FL_DUCKING) {
			SetEntProp(client, Prop_Send, "m_bDucked", true);
			SetEntProp(client, Prop_Send, "m_bDucking", true);
		} else {
			SetEntProp(client, Prop_Send, "m_bDucked", false);
			SetEntProp(client, Prop_Send, "m_bDucking", false);
		}

		SetEntityFlags(client, GetArrayCell(gh_Frames[client], framenum, 6));
	}
}

public bool isRound(float num) {
	return RoundToFloor(num) == num;
}

public void Shavit_OnRestart(int client, int track) {
	if(g_bTAS[client]) {
		gi_Status[client] = RUN;
		gf_TASTime[client] = 0.0;
		gi_IndexCounter[client] = 0;
	}
}


public Action Shavit_OnStart(int client) {
	if(gi_Status[client] == RUN && g_bTAS[client]) {
		gf_TASTime[client] = 0.0;
		gi_IndexCounter[client] = 0;
		ClearArray(gh_Frames[client]);
	}
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity) {
	if(g_bTAS[client])
		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", gf_TimeScale[client]);

	return;
}

public void Shavit_OnFinish_Post(int client) {
	if(g_bTAS[client]) {
		gi_Status[client] = RUN;
		gf_TASTime[client] = 0.0;
		gi_IndexCounter[client] = 0;
	}
}

public Action Shavit_OnFinishPre(int client, timer_snapshot_t snapshot) {
	if(g_bTAS[client]) {
		//Edit time to equal the gf_TASTime[client]
		snapshot.fCurrentTime = gf_TASTime[client];

		//Overwrite Replay Data with gh_Frames[client]
		Shavit_SetReplayData(client, view_as<ArrayList>(gh_Frames[client]));
	}
	return Plugin_Changed;
}

public void Shavit_OnTimeIncrement(int client, timer_snapshot_t snapshot, float &time, stylesettings_t stylesettings) {
	//Update Time on each tick
	if(g_bTAS[client])
		time = gf_TASTime[client] - snapshot.fCurrentTime;
}