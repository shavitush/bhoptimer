// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2025 rtldg <rtldg@protonmail.com>

#if defined _srcwrfloppy_included
	#endinput
#endif
#define _srcwrfloppy_included
#pragma semicolon 1


typeset ReplaySavedCallback {
	function void(bool saved, any value);
}


// Don't modify the `playerrecording` ArrayList until the ReplaySavedCallback is called... OR ELSE!!!!
native void SRCWRFloppy_AsyncSaveReplay(
	  ReplaySavedCallback callback // what to call when saved
	, any value // what to pass along to the callback
	, ArrayList paths
	, char[] header
	, int headersize
	, ArrayList playerrecording
	, int totalframes
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
public void __ext_srcwrfloppy_SetNTVOptional()
{
	MarkNativeAsOptional("SRCWRFloppy_AsyncSaveReplay");
}
#endif
