#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <shavit>

public Plugin:myinfo =
{
	name        = "[shavit] Lower/Uppercase Chat Triggers",
	author      = "shavit",
	description = "Allows both upper and lowercase chat triggers to be used.",
	version     = SHAVIT_VERSION,
	url         = "https://forums.alliedmods.net/showthread.php?t=265456"
};

public OnPluginStart()
{
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_SayTeam, "say_team");
}

public Action:Command_Say(client, const String:command[], argc)
{
	decl String:sText[300];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);

	if((sText[0] == '!') || (sText[0] == '/'))
	{
		if(IsCharUpper(sText[1]))
		{
			for(new i = 0; i <= strlen(sText); ++i)
			{
				sText[i] = CharToLower(sText[i]);
			}

			FakeClientCommand(client, "say %s", sText);
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action:Command_SayTeam(client, const String:command[], argc)
{
	decl String:sText[300];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);

	if((sText[0] == '!') || (sText[0] == '/'))
	{
		if(IsCharUpper(sText[1]))
		{
			for(new i = 0; i <= strlen(sText); ++i)
			{
				sText[i] = CharToLower(sText[i]);
			}

			FakeClientCommand(client, "say_team %s", sText);
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}
