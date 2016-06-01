// teleport to end
RegConsoleCmd("sm_end", Command_TeleportEnd, "Teleport to endzone.");

public Action Command_TeleportEnd(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(gB_Zones && Shavit_ZoneExists(Zone_End))
	{
		Shavit_StopTimer(client);
		Call_StartForward(gH_Forwards_OnEnd);
		Call_PushCell(client);
		Call_Finish();
	}

	else
	{
		Shavit_PrintToChat(client, "You can't teleport as an end zone for the map is not defined.");
	}

	return Plugin_Handled;
}
