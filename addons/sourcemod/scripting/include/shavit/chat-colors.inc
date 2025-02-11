#if defined _shavit_chat_colors_included
	#endinput
#endif
#define _shavit_chat_colors_included

char gS_GlobalColorNames[][] =
{
	"{default}",
	"{def}",
	"{team}",
	"{green}"
};

char gS_GlobalColors[][] =
{
	"\x01",
	"\x01",
	"\x03",
	"\x04"
};

char gS_CSGOColorNames[][] =
{
	"{blue}",
	"{bluegrey}",
	"{darkblue}",
	"{darkred}",
	"{gold}",
	"{grey}",
	"{grey2}",
	"{lightgreen}",
	"{lightred}",
	"{lime}",
	"{orchid}",
	"{yellow}",
	"{palered}"
};

char gS_CSGOColors[][] =
{
	"\x0B",
	"\x0A",
	"\x0C",
	"\x02",
	"\x10",
	"\x08",
	"\x0D",
	"\x05",
	"\x0F",
	"\x06",
	"\x0E",
	"\x09",
	"\x07"
};


stock void FormatColors(char[] buffer, int size, bool colors, bool escape, bool csgo, bool funky_chars=true)
{
	if(colors)
	{
		for(int i = 0; i < sizeof(gS_GlobalColorNames); i++)
		{
			ReplaceString(buffer, size, gS_GlobalColorNames[i], gS_GlobalColors[i]);
		}

		if(csgo)
		{
			for(int i = 0; i < sizeof(gS_CSGOColorNames); i++)
			{
				ReplaceString(buffer, size, gS_CSGOColorNames[i], gS_CSGOColors[i]);
			}
		}

		if (funky_chars) ReplaceString(buffer, size, "^", "\x07");
		ReplaceString(buffer, size, "{RGB}", "\x07");
		if (funky_chars) ReplaceString(buffer, size, "&", "\x08");
		ReplaceString(buffer, size, "{RGBA}", "\x08");
	}

	if(escape)
	{
		ReplaceString(buffer, size, "%%", "");
	}
}
