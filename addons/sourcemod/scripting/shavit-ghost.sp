#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "CodingCow"
#define PLUGIN_VERSION "1.00"

#define TIME_TO_TICKS(%1) RoundFloat(0.5 + %1 / GetTickInterval())

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>
#include <shavit>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "Ghost",
	author = PLUGIN_AUTHOR,
	description = "",
	version = PLUGIN_VERSION,
	url = ""
};

int g_BeamSprite;

ArrayList GhostData[MAXPLAYERS + 1];
ArrayList GhostData2[MAXPLAYERS + 1];

bool ghost[MAXPLAYERS + 1];
int ghostMode[MAXPLAYERS + 1];
bool recording[MAXPLAYERS + 1];
int cmdNum[MAXPLAYERS + 1];
int beamColor[MAXPLAYERS + 1][4];

Handle g_hGhostCookie;
Handle g_hGhostModeCookie;
Handle g_hTrailCookie;

public void OnPluginStart()
{
	g_hGhostCookie = RegClientCookie("GhostTrail", "Ghost Trails", CookieAccess_Protected);
	g_hTrailCookie = RegClientCookie("TrailColor", "Ghost Trail Color", CookieAccess_Protected);
	g_hGhostModeCookie = RegClientCookie("GhostMode", "Ghost Trail Mode", CookieAccess_Protected);
	
	RegConsoleCmd("sm_ghost", ghostToggle);
	RegConsoleCmd("sm_beam", BeamMenu);
	
	RegAdminCmd("sm_ghostusers", getUsers, ADMFLAG_ROOT);
	
	for (int i = 0; i <= MaxClients; i++)
	{
		delete GhostData[i];
		GhostData[i] = new ArrayList(4);
		delete GhostData2[i];
		GhostData2[i] = new ArrayList(4);
		ghost[i] = false;
		recording[i] = false;
		cmdNum[i] = 0;
		beamColor[i] =  { 255, 255, 255, 255 };
	}
	
	CreateTimer(600.0, advertise, _, TIMER_REPEAT);
}

public void OnConfigsExecuted()
{
	g_BeamSprite = PrecacheModel("sprites/laserbeam.vmt");
}

public void OnClientCookiesCached(int client)
{
	char cookieValue[32];
	GetClientCookie(client, g_hGhostCookie, cookieValue, sizeof(cookieValue));
	ghost[client] = view_as<bool>(StringToInt(cookieValue));
	
	char cookieValue2[32];
	GetClientCookie(client, g_hTrailCookie, cookieValue2, sizeof(cookieValue2));
	
	if(StrEqual(cookieValue2, "Red"))
		beamColor[client] =  { 255, 0, 0, 255 };
	else if(StrEqual(cookieValue2, "Green"))
		beamColor[client] =  { 0, 255, 0, 255 };
	else if(StrEqual(cookieValue2, "Blue"))
		beamColor[client] =  { 0, 0, 255, 255 };
	else
		beamColor[client] =  { 255, 255, 255, 255 };
	
	char cookieValue3[32];
	GetClientCookie(client, g_hGhostModeCookie, cookieValue3, sizeof(cookieValue3));
	ghostMode[client] = StringToInt(cookieValue3);
}

public void OnClientPutInServer(int client)
{
	delete GhostData[client];
	GhostData[client] = new ArrayList(4);
	delete GhostData2[client];
	GhostData2[client] = new ArrayList(4);
	recording[client] = false;
	cmdNum[client] = 0;
}

public void OnClientDisconnect(int client)
{
	delete GhostData[client];
	GhostData[client] = new ArrayList(4);
	delete GhostData2[client];
	GhostData2[client] = new ArrayList(4);
	ghost[client] = false;
	recording[client] = false;
	cmdNum[client] = 0;
	ghostMode[client] = 0;
}

public Action advertise(Handle timer)
{
	PrintToChatAll("[\x0CGhost\x01] type \x04!ghost \x01to race your personal best or the world record!");
}

public Action getUsers(int client, int args)
{
	for (int i = 0; i <= MaxClients; i++)
	{
		if(ghost[i])
			PrintToConsole(client, "%N | Ghost Enabled | %s", i, (ghostMode[i] == 0 ? "Personal Best" : "World Record"));
	}
	
	PrintToChat(client, "[\x0CGhost\x01] users logged in \x02Console");
	
	return Plugin_Handled;
}

public Action ghostToggle(int client, int args)
{
	Menu m = new Menu(ghostMenu);
	m.SetTitle("Ghost Menu");
	
	m.AddItem("Enable/Disable", "Enable/Disable");
	m.AddItem("Beam Color", "Beam Color");
	m.AddItem("Mode", (ghostMode[client] == 0 ? "Mode: Personal Best" : "Mode: World Record"));
	
	m.ExitButton = true;
	m.Display(client, 0);
	
	return Plugin_Handled;
}

public int ghostMenu(Menu menu, MenuAction action, int client, int param2)
{
	switch (action)
	{		
		case MenuAction_Select:
		{
			char info[16];
			if(menu.GetItem(param2, info, sizeof(info)))
			{
				if(StrEqual(info, "Enable/Disable"))
				{
					ghost[client] = !ghost[client];
					
					SetClientCookie(client, g_hGhostCookie, (ghost[client] ? "1" : "0"));
					
					if(ghost[client])
						GhostData[client].Clear();
					else
						cmdNum[client] = 0;
					
					PrintToChat(client, "[\x0CGhost\x01] Ghost: %s", (ghost[client] ? "\x04Enabled" : "\x02Disabled"));
				}
				else if(StrEqual(info, "Beam Color"))
				{
					BeamMenu(client, 0);
					return;
				}
				else if(StrEqual(info, "Mode"))
				{
					if(ghostMode[client] == 0)
					{
						ghostMode[client] = 1;
						
						ArrayList ar = Shavit_GetReplayFrames(Shavit_GetBhopStyle(client), Shavit_GetClientTrack(client));
	
						GhostData2[client] = ar.Clone();
					}
					else
					{
						ghostMode[client] = 0;
						GhostData2[client].Clear();
					}
						
					SetClientCookie(client, g_hGhostModeCookie, (ghostMode[client] == 0 ? "0" : "1"));
					
					PrintToChat(client, "[\x0CGhost\x01] Ghost Mode: %s", (ghostMode[client] == 0 ? "\x04Personal Best" : "\x0EWorld Record"));
					
					if(ghostMode[client] == 0)
						PrintToChat(client, "[\x0CGhost\x01] Complete the map and a Ghost will appear.");
				}
				
				ghostToggle(client, 0);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

public Action BeamMenu(int client, int args)
{
	Menu m = new Menu(beamColorMenu);
	m.SetTitle("Ghost Beam Color");
	m.AddItem("Red", "Red");
	m.AddItem("Green", "Green");
	m.AddItem("Blue", "Blue");
	m.AddItem("White", "White");
	m.ExitButton = true;
	m.Display(client, 0);
	
	return Plugin_Handled;
}

public int beamColorMenu(Menu menu, MenuAction action, int client, int param2)
{
	switch (action)
	{		
		case MenuAction_Select:
		{
			char info[16];
			if(menu.GetItem(param2, info, sizeof(info)))
			{
				char text[32];
				if(StrEqual(info, "Red"))
				{
					beamColor[client] =  { 255, 0, 0, 255 };
					Format(text, sizeof(text), "\x02Red");
				}
				else if(StrEqual(info, "Green"))
				{
					beamColor[client] =  { 0, 255, 0, 255 };
					Format(text, sizeof(text), "\x04Green");
				}
				else if(StrEqual(info, "Blue"))
				{
					beamColor[client] =  { 0, 0, 255, 255 };
					Format(text, sizeof(text), "\x0CBlue");
				}
				else if(StrEqual(info, "White"))
				{
					beamColor[client] =  { 255, 255, 255, 255 };
					Format(text, sizeof(text), "White");
				}
				
				PrintToChat(client, "[\x0CGhost\x01] Trail Color: %s", text);
				
				SetClientCookie(client, g_hTrailCookie, info);
				ghostToggle(client, 0);
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	if(ghost[client] && ghostMode[client] == 1)
	{				
		ArrayList ar = Shavit_GetReplayFrames(newstyle, track);
	
		GhostData2[client] = ar.Clone();
	}
}

public void Shavit_OnLeaveZone(int client, int type, int track, int id, int entity, int data)
{
	if(type == Zone_Start && ghost[client])
	{
		cmdNum[client] = 0;
		recording[client] = true;
	}
}

public void Shavit_OnEnterZone(int client, int type, int track, int id, int entity, int data)
{
	if(type == Zone_Start && ghost[client])
	{
		cmdNum[client] = 0;
		GhostData[client].Clear();
		
		if(ghostMode[client] == 1)
		{
			ArrayList ar = Shavit_GetReplayFrames(Shavit_GetBhopStyle(client), Shavit_GetClientTrack(client));
		
			GhostData2[client] = ar.Clone();
		}
	}
	else if(type == Zone_End && recording[client] && ghost[client] && ghostMode[client] == 0)
	{
		delete GhostData2[client];
		GhostData2[client] = GhostData[client].Clone();
		recording[client] = false;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsValidClient(client, true))
	{
		if(Shavit_InsideZone(client, Zone_Start, -1) || Shavit_InsideZone(client, Zone_End, -1))
			return Plugin_Continue;
	
		if(ghost[client] && ghostMode[client] == 0 && recording[client])
		{
			float pos[3];
			GetClientAbsOrigin(client, pos);
			
			float info[4];
			info[0] = pos[0];
			info[1] = pos[1];
			info[2] = pos[2];
			info[3] = (GetEntityFlags(client) & FL_ONGROUND ? 0.0 : 1.0);
			
			GhostData[client].PushArray(info);
		}
		
		if(ghost[client] && GhostData2[client].Length > 1)
		{
			if(ghostMode[client] == 0)
			{
				if(cmdNum[client] > GhostData2[client].Length - 1)
					cmdNum[client] = 0;
					
				if(cmdNum[client] > 0 && cmdNum[client] < GhostData2[client].Length)
				{
					float info[4];
					GhostData2[client].GetArray(cmdNum[client], info, sizeof(info));
					
					float pos[3];
					pos[0] = info[0];
					pos[1] = info[1];
					pos[2] = info[2];
					
					// Last Info
					float info2[4];
					GhostData2[client].GetArray(cmdNum[client] - 1, info2, sizeof(info2));
					
					float last_pos[3];
					last_pos[0] = info2[0];
					last_pos[1] = info2[1];
					last_pos[2] = info2[2];
					
					// SET ORB TO LOCATION		
					BeamEffect(client, last_pos, pos, 0.7, 1.0, 1.0, beamColor[client], 0.0, 0);
					
					for (int i = 0; i <= MaxClients; i++)
					{
						if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_SPECTATOR && GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == client)
						{
							BeamEffect(i, last_pos, pos, 0.7, 1.0, 1.0, beamColor[client], 0.0, 0);
						}
					}
					
					// If on ground draw square
					if(info[3] == 0.0 && info2[3] != 0.0)
					{
						float square[4][3];
						
						square[0][0] = pos[0] + 14.0;
						square[0][1] = pos[1] + 14.0;
						square[0][2] = pos[2];
						
						square[1][0] = pos[0] + 14.0;
						square[1][1] = pos[1] - 14.0;
						square[1][2] = pos[2];
						
						square[2][0] = pos[0] - 14.0;
						square[2][1] = pos[1] - 14.0;
						square[2][2] = pos[2];
						
						square[3][0] = pos[0] - 14.0;
						square[3][1] = pos[1] + 14.0;
						square[3][2] = pos[2];
						
						BeamEffect(client, square[0], square[1], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
						BeamEffect(client, square[1], square[2], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
						BeamEffect(client, square[2], square[3], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
						BeamEffect(client, square[3], square[0], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
						
						for (int i = 0; i <= MaxClients; i++)
						{
							if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_SPECTATOR && GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == client)
							{
								BeamEffect(i, square[0], square[1], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
								BeamEffect(i, square[1], square[2], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
								BeamEffect(i, square[2], square[3], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
								BeamEffect(i, square[3], square[0], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
							}
						}
					}
				}
				
				cmdNum[client]++;
			}
			else if(ghostMode[client] == 1)
			{
				float AvgLatency = GetClientAvgLatency(client, NetFlow_Outgoing);
				int AvgLatencyTicks = TIME_TO_TICKS(AvgLatency);
				int startTick = Shavit_GetReplayPreFrames(Shavit_GetBhopStyle(client), Shavit_GetClientTrack(client)) + AvgLatencyTicks;			
				if(cmdNum[client] == 0)
					cmdNum[client] = startTick;
				
				if(cmdNum[client] > GhostData2[client].Length - 1)
					cmdNum[client] = startTick;
					
				if(cmdNum[client] > startTick && cmdNum[client] < GhostData2[client].Length)
				{
					float info[8];
					GhostData2[client].GetArray(cmdNum[client], info, sizeof(info));
					
					float pos[3];
					pos[0] = info[0];
					pos[1] = info[1];
					pos[2] = info[2];
					
					// Last Info
					float info2[8];
					GhostData2[client].GetArray(cmdNum[client] - 1, info2, sizeof(info2));
					
					float last_pos[3];
					last_pos[0] = info2[0];
					last_pos[1] = info2[1];
					last_pos[2] = info2[2];
					
					// SET ORB TO LOCATION		
					BeamEffect(client, last_pos, pos, 0.7, 1.0, 1.0, beamColor[client], 0.0, 0);
					
					for (int i = 0; i <= MaxClients; i++)
					{
						if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_SPECTATOR && GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == client)
						{
							BeamEffect(i, last_pos, pos, 0.7, 1.0, 1.0, beamColor[client], 0.0, 0);
						}
					}
					
					// If on ground draw square
					if((info[6] & FL_ONGROUND) && !(info2[6] & FL_ONGROUND))
					{
						float square[4][3];
						
						square[0][0] = pos[0] + 14.0;
						square[0][1] = pos[1] + 14.0;
						square[0][2] = pos[2];
						
						square[1][0] = pos[0] + 14.0;
						square[1][1] = pos[1] - 14.0;
						square[1][2] = pos[2];
						
						square[2][0] = pos[0] - 14.0;
						square[2][1] = pos[1] - 14.0;
						square[2][2] = pos[2];
						
						square[3][0] = pos[0] - 14.0;
						square[3][1] = pos[1] + 14.0;
						square[3][2] = pos[2];
						
						BeamEffect(client, square[0], square[1], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
						BeamEffect(client, square[1], square[2], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
						BeamEffect(client, square[2], square[3], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
						BeamEffect(client, square[3], square[0], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
						
						for (int i = 0; i <= MaxClients; i++)
						{
							if(IsValidClient(i) && GetClientTeam(i) == CS_TEAM_SPECTATOR && GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == client)
							{
								BeamEffect(i, square[0], square[1], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
								BeamEffect(i, square[1], square[2], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
								BeamEffect(i, square[2], square[3], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
								BeamEffect(i, square[3], square[0], 0.7, 1.0, 1.0, { 255, 105, 180, 255}, 0.0, 0);
							}
						}
					}
				}
				
				cmdNum[client]++;
			}
		}
	}
	
	return Plugin_Continue;
}

public void BeamEffect(int client, float startvec[3], float endvec[3], float life, float width, float endwidth, const int color[4], float amplitude, int speed)
{
	TE_SetupBeamPoints(startvec, endvec, g_BeamSprite, 0, 0, 66, life, width, endwidth, 0, amplitude, color, speed);
	TE_SendToClient(client);
}