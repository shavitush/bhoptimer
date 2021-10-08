
// Originally from https://github.com/rumourA/End-Touch-Fix

#define EFL_CHECK_UNTOUCH (1<<24)

Handle gH_PhysicsCheckForEntityUntouch;

void LoadPhysicsUntouch(Handle gamedata)
{
	StartPrepSDKCall(SDKCall_Entity);

	if (!PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "PhysicsCheckForEntityUntouch"))
	{
		SetFailState("Failed to get PhysicsCheckForEntityUntouch");
	}

	gH_PhysicsCheckForEntityUntouch = EndPrepSDKCall();
}

bool GetCheckUntouch(int client)
{
	int flags = GetEntProp(client, Prop_Data, "m_iEFlags");
	return (flags & EFL_CHECK_UNTOUCH) != 0;
}

void MaybeDoPhysicsUntouch(int client)
{
	if (GetCheckUntouch(client))
	{
		SDKCall(gH_PhysicsCheckForEntityUntouch, client);
	}
}
