### Build status
[![Build status](https://travis-ci.org/shavitush/bhoptimer.svg?branch=master)](https://travis-ci.org/shavitush/bhoptimer)

[AlliedModders thread](https://forums.alliedmods.net/showthread.php?t=265456)

[Download](https://github.com/Shavitush/bhoptimer/releases)

# shavit's simple bhop timer
a bhop server should be simple

[Mapzones' setup demonstration](https://www.youtube.com/watch?v=oPKso2hoLw0)

# Requirements:
* [SourceMod 1.8 and above](http://www.sourcemod.net/downloads.php)
* `clientprefs` plugin/extension. Comes built-in with SourceMod.
* [The RTLer](https://forums.alliedmods.net/showthread.php?p=1649882) is required to *compile* `shavit-chat` and you don't need Simple Chat Processor as listed in Ther RTLer's requirements.
* [Dynamic](https://forums.alliedmods.net/showthread.php?t=270519) for compilation and runtime of `shavit-chat` and `shavit-zones`.

# Optional requirements:
* [DHooks](http://users.alliedmods.net/~drifter/builds/dhooks/2.0/) - required for static 250 prestrafe (bhoptimer 1.2b and above)
* [The RTLer](https://forums.alliedmods.net/showthread.php?p=1649882) - required for properly formatted RTL text within `shavit-chat`.

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
4. Copy the files from the `sound` folder to the one on your server. Make sure to also have equivelant bz2 files on your FastDL server!
5. Copy the `configs` file to your server and modify `shavit-sounds.cfg` if you wish to.  
5.1. Changing `shavit-prefix.txt` to contain your MySQL database prefix might be needed depending on your usage.
6. Restart your server.

# Required plugins:
`shavit-core` - no other plugin will work without it.  
`shavit-zones` - required for `shavit-core` and for `shavit-misc`.  
`shavit-wr` - required for `shavit-stats`, `shavit-replay`, `shavit-sounds`, `shavit-stats` and `shavit-rankings`.  
`shavit-rankings` - required for `shavit-chat`.

# Todo for 1.5b release (out of beta!)
General
--
- [x] Migrate every menu to the 1.7 transitional syntax.
- [x] Migrate DBI to the 1.7 transitional syntax.
- [x] Migrate events to the 1.7 transitional syntax.
- [x] Migrate ADT_Arrays to ArrayList.
- [ ] **ENDGAME**: Migrate all the cached stuff (timer variables, HUD, chat cache) to Dynamic if I find it good and simple enough.

Core
--
- [x] Fix chat colors for CS:S.
- [x] Add table prefix. (configs/shavit-prefix.txt)
- [x] Add shavit_core_nostaminareset ("easybhop")
- [x] ~~Make a global enumerator/variable with per-style settings (bitflags)~~ - configs are canceled, just recompile the plugin with your own edit of `shavit.inc`.
- [x] Add unranked styles.
- [ ] Add native that will execute threaded MySQL queries and allow callbacks - including safety checks, to prevent error spams. (Migrate DBI to new syntax first!)
- [ ] Measure strafe sync, also have it in the Shavit_OnFinish forward.
- [ ] Add bonus timer.

HUD
--
- [x] HUD toggling command. (`sm_hud`)
- [x] Zone (start/end) HUD toggling command. (`sm_zonehud`)
- [x] [CS:GO] Replace "- Replay Bot -" for bots with an underlined and pretty text.
- [x] Remove `sm_zonehud` and make `sm_hud` a menu that can toggle HUD, zonehud and spectators list in a panel.
- [x] Add spectator list.
- [x] Show time in a "TIME/RECORD" format for replay bots.
- [ ] Support for bonus timer.

Replay
--
- [ ] Add admin interface. (delete replay data)
- [ ] Remove replay bot data on deletion of the #1 record.
- [ ] Make a boolean native that confirms if a client is a replay bot with loaded data. (used for `shavit-hud`)

WR
--
- [x] Make `UpdateWRCache` smaller. Will result in extra optimization and more uhm.. dynamic!
- [x] Add a cvar that limits the amount of records in the WR menu. (default: 50 | `shavit_wr_recordlimit`)
- [x] Remove `sm_wrsw` and make `sm_wr` a dynamic menu with all difficulties. (dynamic!)
- [x] [rankings] Show points in WR menu.
- [ ] Add strafe sync to the WR menu where available.
- [ ] Add `sm_bwr` `sm_bonuswr` `sm_bonusworldrecord`.
- [ ] Use unix timestamps for future record dates.

Stats
--
- [x] Make style names editable from shavit.inc (like I did to the rest of modules) (dynamic!)
- [x] Make a submenu per style, for aesthetics.
- [x] [rankings] Points implementation.
- [ ] Make MVP count the amount of WRs the player has.

Miscellaneous
--
- [x] Allow changing the prespeed limitation.
- [x] Add weapon cleanup.

Sounds **(NEW!)**
--
- [x] Play sounds (from config file | `configs/shavit-sounds.cfg`) on new events.
- [x] On new #1.
- [x] On personal best.
- [x] On map finish.

Rankings **(NEW!)**
--
- [x] Create tables. (`mappoints`, `playerpoints`)
- [x] Allow ROOT admins to set ideal points for map and time for the default style. (`sm_setpoints <time in seconds> <points>`)
- [x] Add `sm_points`.
- [x] Implement an algorithm that will calculate points for a record, will also take the time and style into account. Add a +25% bonus if the time is equal or better than the ideal one.
- [x] Use a weighting system for points calculation. The highest ranked time will be weighted 100% and worse times will be weighted as 5% less each time.
- [x] Calculate points for players once they connect to the server.
- [x] Add `sm_top` that will show the top X players, sort by points.
- [x] Calculate rank for players once they connect to the server.
- [x] Add `sm_rank`.
- [x] Calculate points per scored time once it's added to the database.
- [x] Recalculate points for every record on the current map when a ROOT admin changes the point value for it. (retroactive!)
- [x] Add natives. `float Shavit_GetPoints(int client)` `int Shavit_GetRank(int client)` `void Shavit_GetMapValues(float &points, float &idealtime)`

Web Interface
--
- [x] Implement points.

Chat **(NEW!)**
--
- [x] Add logic that processes chat without requiring an external plugin such as `Simple Chat Processor (Redux)`.
- [x] [RTLer](https://forums.alliedmods.net/showthread.php?p=1649882) support.
- [x] Custom chat titles/colors per individual player.
- [x] Custom chat titles/colors for rank ranges.
- [x] Update cache for a player when his rank updates.
- [x] Add `sm_ranks` `sm_chatranks`.
- [x] Add `Shavit_FormatChat` native.
- [x] Add random rgb and random rgba for CS:S parsing.

Zones
--
- [x] Add teleport zones (multiple).
- [x] Use string explosion in ZoneAdjuster_Handler and ZoneEdge_Handler for code efficiency.
- [ ] Make zones be trigger-based for high-performance. Also remove InsideZone() and use booleans instead (OnStartTouch/OnEndTouch).
- [ ] Migrate zone settings to use Dynamic.
- [ ] Handle teleport zones once everything is done. (teleport to a value from gV_Teleport)
