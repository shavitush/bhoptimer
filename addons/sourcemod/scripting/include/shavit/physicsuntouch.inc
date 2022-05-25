/*
 * physicsuntouch.inc
 * by: rumour
 *
 * Originally from EndTouch Fix (https://github.com/rumourA/End-Touch-Fix)
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

#if defined _physicuntouch_included
	#endinput
#endif
#define _physicuntouch_included


#define EFL_CHECK_UNTOUCH (1<<24)

Handle gH_PhysicsCheckForEntityUntouch;

stock void LoadPhysicsUntouch(Handle gamedata)
{
	StartPrepSDKCall(SDKCall_Entity);

	if (!PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "PhysicsCheckForEntityUntouch"))
	{
		SetFailState("Failed to get PhysicsCheckForEntityUntouch");
	}

	gH_PhysicsCheckForEntityUntouch = EndPrepSDKCall();
}

stock bool GetCheckUntouch(int client)
{
	int flags = GetEntProp(client, Prop_Data, "m_iEFlags");
	return (flags & EFL_CHECK_UNTOUCH) != 0;
}

stock void MaybeDoPhysicsUntouch(int client)
{
	if (GetCheckUntouch(client))
	{
		SDKCall(gH_PhysicsCheckForEntityUntouch, client);
	}
}
