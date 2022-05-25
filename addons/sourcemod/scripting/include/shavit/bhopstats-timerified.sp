/*
 * Bunnyhop Statistics API - Plugin
 * by: shavit
 *
 * Originally from Bunnyhop Statistics API (https://github.com/shavitush/bhopstats)
 * but edited to be part of shavit's Timer (https://github.com/shavitush/bhoptimer)
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

#pragma newdecls required
#pragma semicolon 1

bool gB_OnGround[MAXPLAYERS+1];
bool gB_PlayerTouchingGround[MAXPLAYERS+1];

int gI_Scrolls[MAXPLAYERS+1];
int gI_Buttons[MAXPLAYERS+1];
bool gB_JumpHeld[MAXPLAYERS+1];

int gI_Jumps[MAXPLAYERS+1];
int gI_PerfectJumps[MAXPLAYERS+1];

Handle gH_Forwards_OnJumpPressed = null;
Handle gH_Forwards_OnJumpReleased = null;
Handle gH_Forwards_OnTouchGround = null;
Handle gH_Forwards_OnLeaveGround = null;

public void Bhopstats_CreateNatives()
{
	CreateNative("Shavit_Bhopstats_GetScrollCount", Native_GetScrollCount);
	CreateNative("Shavit_Bhopstats_IsOnGround", Native_IsOnGround);
	CreateNative("Shavit_Bhopstats_IsHoldingJump", Native_IsHoldingJump);
	CreateNative("Shavit_Bhopstats_GetPerfectJumps", Native_Bhopstats_GetPerfectJumps);
	CreateNative("Shavit_Bhopstats_ResetPerfectJumps", Native_ResetPerfectJumps);
}

public void Bhopstats_CreateForwards()
{
	gH_Forwards_OnJumpPressed = CreateGlobalForward("Shavit_Bhopstats_OnJumpPressed", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnJumpReleased = CreateGlobalForward("Shavit_Bhopstats_OnJumpReleased", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnTouchGround = CreateGlobalForward("Shavit_Bhopstats_OnTouchGround", ET_Event, Param_Cell);
	gH_Forwards_OnLeaveGround = CreateGlobalForward("Shavit_Bhopstats_OnLeaveGround", ET_Event, Param_Cell, Param_Cell, Param_Cell);
}

public void Bhopstats_OnClientPutInServer(int client)
{
	gB_OnGround[client] = false;
	gB_PlayerTouchingGround[client] = false;

	gI_Scrolls[client] = 0;
	gI_Buttons[client] = 0;
	gB_JumpHeld[client] = false;

	gI_Jumps[client] = 0;
	gI_PerfectJumps[client] = 0;

	SDKHook(client, SDKHook_PostThinkPost, Bhopstats_PostThinkPost);
}

public int Native_GetScrollCount(Handle handler, int numParams)
{
	return gI_Scrolls[GetNativeCell(1)];
}

public int Native_IsOnGround(Handle handler, int numParams)
{
	return view_as<int>(gB_OnGround[GetNativeCell(1)]);
}

public int Native_IsHoldingJump(Handle handler, int numParams)
{
	return view_as<int>(gI_Buttons[GetNativeCell(1)] & IN_JUMP);
}

public int Native_Bhopstats_GetPerfectJumps(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	return view_as<int>((float(gI_PerfectJumps[client]) / gI_Jumps[client]) * 100.0);
}

public int Native_ResetPerfectJumps(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	gI_Jumps[client] = 0;
	gI_PerfectJumps[client] = 0;

	return 0;
}

public void Bhopstats_PostThinkPost(int client)
{
	if(!IsPlayerAlive(client))
	{
		return;
	}

	int buttons = GetClientButtons(client);
	bool bOldOnGround = gB_OnGround[client];

	int iGroundEntity;

	if (gB_ReplayPlayback && IsFakeClient(client))
	{
		iGroundEntity = (Shavit_GetReplayEntityFlags(client) & FL_ONGROUND) ? 0 : -1;
	}
	else
	{
		iGroundEntity = GetEntPropEnt(client, Prop_Send, "m_hGroundEntity");
	}

	bool bOnLadder = (GetEntityMoveType(client) == MOVETYPE_LADDER);
	gB_OnGround[client] = (iGroundEntity != -1 || GetEntProp(client, Prop_Send, "m_nWaterLevel") >= 2 || bOnLadder);

	gB_JumpHeld[client] = (buttons & IN_JUMP && !(gI_Buttons[client] & IN_JUMP));

	if(gB_PlayerTouchingGround[client] && gB_OnGround[client])
	{
		Call_StartForward(gH_Forwards_OnTouchGround);
		Call_PushCell(client);
		Call_Finish();

		gB_PlayerTouchingGround[client] = false;
	}
	else if(!gB_PlayerTouchingGround[client] && ((gB_JumpHeld[client] && iGroundEntity != -1) || iGroundEntity == -1 || bOnLadder))
	{
		Call_StartForward(gH_Forwards_OnLeaveGround);
		Call_PushCell(client);
		Call_PushCell(gB_JumpHeld[client]);
		Call_PushCell(bOnLadder);
		Call_Finish();

		gB_PlayerTouchingGround[client] = true;
		gI_Scrolls[client] = 0;
	}

	if(gB_JumpHeld[client])
	{
		gI_Scrolls[client]++;

		Call_StartForward(gH_Forwards_OnJumpPressed);
		Call_PushCell(client);
		Call_PushCell(gB_OnGround[client]);
		Call_Finish();

		if(gB_OnGround[client])
		{
			gI_Jumps[client]++;

			if(!bOldOnGround)
			{
				gI_PerfectJumps[client]++;
			}
		}
	}
	else if(gI_Buttons[client] & IN_JUMP && !(buttons & IN_JUMP))
	{
		Call_StartForward(gH_Forwards_OnJumpReleased);
		Call_PushCell(client);
		Call_PushCell(gB_OnGround[client]);
		Call_Finish();
	}

	gI_Buttons[client] = buttons;
}
