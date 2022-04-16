/*
 * shavit's Timer - area_and_cluster_stages.sp
 * by: carnifex
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

// originally sourced from https://github.com/hermansimensen/mapstages

Address IVEngineServer;
Handle gH_GetCluster;
Handle gH_GetArea;

void LoadDHooks_mapstages(GameData gamedata)
{
	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CreateInterface"))
	{
		SetFailState("Failed to get CreateInterface");
	}

	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	Handle CreateInterface = EndPrepSDKCall();

	if (CreateInterface == null)
	{
		SetFailState("Unable to prepare SDKCall for CreateInterface");
	}

	char interfaceName[64];
	if (!GameConfGetKeyValue(gamedata, "IVEngineServer", interfaceName, sizeof(interfaceName)))
	{
		SetFailState("Failed to get IVEngineServer interface name");
	}

	IVEngineServer = SDKCall(CreateInterface, interfaceName, 0);

	if (!IVEngineServer)
	{
		SetFailState("Failed to get IVEngineServer pointer");
	}

	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "GetClusterForOrigin"))
	{
		SetFailState("Couldn't find GetClusterForOrigin offset");
	}
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	gH_GetCluster = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Raw);
	if (!PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "GetArea"))
	{
		SetFailState("Couldn't find GetArea offset");
	}
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	gH_GetArea = EndPrepSDKCall();

	delete CreateInterface;
}

public int GetClusterForOrigin(const float pos[3])
{
	return SDKCall(gH_GetCluster, IVEngineServer, pos);
}

public int GetAreaForOrigin(const float pos[3])
{
	return SDKCall(gH_GetArea, IVEngineServer, pos);
}
