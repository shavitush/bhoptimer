public void Shavit_OnEnd(int client)
{
	if(gCV_TeleportToStart.BoolValue && !IsFakeClient(client) && !EmptyZone(gV_MapZones[1][0]) && !EmptyZone(gV_MapZones[1][1]))
	{
		float vCenter[3];
		MakeVectorFromPoints(gV_MapZones[1][0], gV_MapZones[1][1], vCenter);

		// calculate center
		vCenter[0] /= 2;
		vCenter[1] /= 2;
		
		AddVectors(gV_MapZones[1][0], vCenter, vCenter);

		vCenter[2] = gV_MapZones[1][0][2];

		TeleportEntity(client, vCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
	}
}
