// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2025 rtldg <rtldg@protonmail.com>

#if defined _floppy_included
	#endinput
#endif
#define _floppy_included
#pragma semicolon 1


typeset ReplaySavedCallback {
	function void(bool saved, any value, char[] sPath);
}


// Don't modify the `playerrecording` ArrayList until the ReplaySavedCallback is called... OR ELSE!!!!
native void SRCWRFloppy_AsyncSaveReplay(
	// required & will throw an error if you don't use the supported versions...
	  char[] replayfmt
	, int replaysubversion
	// what to call when saved
	, ReplaySavedCallback callback
	// what to pass along to the callback
	, any value

	, char[] replayFolder
	, char[] map
	// copy of SaveReplay() params
	, int style
	, int track
	, float time
	, int steamid
	, int preframes
	, ArrayList playerrecording
	, int iSize
	, int postframes
	, int timestamp
	, float fZoneOffset[2]
	, bool saveCopy
	, bool saveWR
	, float tickrate
);


public Extension __ext_srcwrfloppy =
{
	name = "srcwr💾",
	file = "srcwr💾.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_EXTENSIONS
public void __ext_floppy_SetNTVOptional()
{
	MarkNativeAsOptional("SRCWRFloppy_AsyncSaveReplay");
}
#endif
