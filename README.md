[AlliedModders thread](https://forums.alliedmods.net/showthread.php?t=265456)

[Download](https://github.com/Shavitush/bhoptimer/releases)

# shavit's simple bhop timer
a bhop server should be simple

[Mapzones' setup demonstration](https://www.youtube.com/watch?v=oPKso2hoLw0)

# Requirements:
* [SourceMod 1.7 and above](http://www.sourcemod.net/downloads.php)

# Optional requirements:
* [DHooks](http://users.alliedmods.net/~drifter/builds/dhooks/2.0/) - required for static 250 prestrafe (bhoptimer 1.2b and above)

#  Installation:
1. Add a database entry in addons/sourcemod/configs/databases.cfg, call it "shavit"
```
"Databases"
{
	"driver_default"		"mysql"

	// When specifying "host", you may use an IP address, a hostname, or a socket file path

	"default"
	{
		"driver"			"default"
		"host"				"localhost"
		"database"			"sourcemod"
		"user"				"root"
		"pass"				""
		//"timeout"			"0"
		//"port"			"0"
	}

	"shavit"
	{
		"driver"         "mysql"
		"host"           "localhost"
		"database"       "shavit"
		"user"           "root"
		"pass"           ""
	}
}
```
2. Copy the desired .smx files to your plugins (addons/sourcemod/plugins) folder
2.1. Copy shavit.games.txt to /gamedata if you have DHooks installed.
3. Copy base.nav to the `maps` folder.
4. Restart your server.

# Required plugins:
shavit-core - no other plugin will work without it.  
shavit-zones - wouldn't really call it required but it's actually needed to get your timer to start/finish.

# Todo for 1.5b release (out of beta!)
- [x] Migrate every menu to the new syntax.
- [ ] Migrate DBI to the new syntax.

~ shavit-core:
- [x] Fix chat colors for CS:S.
- [x] Add table prefix. (`shavit_core_sqlprefix`)
- [x] Add shavit_core_nostaminareset ("easybhop")
- [ ] Make a global enumerator/variable with per-style settings (bitflags)
- [ ] Add native that will execute threaded MySQL queries and allow callbacks - including safety checks, to prevent error spams.
- [ ] Measure strafe sync, also have it in the Shavit_OnFinish forward.
- [ ] (might be canceled!) Add style configuration through mysql (`style` table) and allow it to be custom with some options. (Style name, autobhop, block each key individually and velocity limit)
- [ ] If the above will be canceled, load style settings from a config and use [Dynamic](https://forums.alliedmods.net/showthread.php?t=270519) to cache per-style settings.
- [ ] Add unranked styles.

~ shavit-hud:
- [x] HUD toggling command. (`sm_hud`)
- [x] Zone (start/end) HUD toggling command. (`sm_zonehud`)
- [x] [CS:GO] Replace "- Replay Bot -" for bots with an underlined and pretty text.
- [ ] Show time in a "TIME/RECORD" format including percentage for replay bots.
- [ ] Remove `sm_zonehud` and make `sm_hud` a menu that can toggle HUD, zonehud and spectators list in a panel.

~ shavit-replay
- [ ] Add admin interface. (delete replay data)
- [ ] Remove replay bot data on deletion of the #1 record.
- [ ] Make a boolean native that confirms if a client is a replay bot with loaded data. (used for `shavit-hud`)

~ shavit-wr
- [x] Make `UpdateWRCache` smaller. Will result in extra optimization and more uhm.. dynamic!
- [x] Add a cvar that limits the amount of records in the WR menu. (default: 50 | `shavit_wr_recordlimit`)
- [x] Remove `sm_wrsw` and make `sm_wr` a dynamic menu with all difficulties. (dynamic!)
- [ ] Add strafe sync to the WR menu where available.

~ shavit-zones
- [ ] Optimize `InsideZone()` so `CreateZonePoints()` will not be needed for simple (not rotated) zones.

~ shavit-stats
- [x] Make style names editable from shavit.inc (like I did to the rest of modules) (dynamic!)

~ [NEW PLUGIN] shavit-ranks:
- [ ] Create table.
- [ ] to be added.
