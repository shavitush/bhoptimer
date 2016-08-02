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
* [Dynamic](https://forums.alliedmods.net/showthread.php?t=270519) for compilation and runtime of `shavit-chat`.
* [Simple Chat Processor \(Redux\)](https://forums.alliedmods.net/showthread.php?p=1820365) - for compilation and better runtime of `shavit-chat` (plugin can run without it). Use the scp.inc file I attached in `include/scp.inc` for transitional syntax support.

# Optional requirements:
* [DHooks](http://users.alliedmods.net/~drifter/builds/dhooks/2.0/) - required for static 250 prestrafe.
* [The RTLer](https://forums.alliedmods.net/showthread.php?p=1649882) - required for properly formatted RTL text within `shavit-chat`.
* [Simple Chat Processor \(Redux\)](https://forums.alliedmods.net/showthread.php?p=1820365) - for more proper parsing inside `shavit-chat`.

#  Installation:
1. If you want to use MySQL (**VERY RECOMMENDED**) add a database entry in addons/sourcemod/configs/databases.cfg, call it "shavit". The plugin also supports the "sqlite" driver. You can also skip this step and not modify databases.cfg.
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
4.1. Do the same for the `materials` folder.
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
- [x] Support "out of the box" installations and SQLite support.

Core
--
- [x] Fix chat colors for CS:S.
- [x] Add table prefix. (configs/shavit-prefix.txt)
- [x] Add shavit_core_nostaminareset ("easybhop")
- [x] ~~Make a global enumerator/variable with per-style settings (bitflags)~~ - configs are canceled, just recompile the plugin with your own edit of `shavit.inc`.
- [x] Add unranked styles.
- [x] Add a setting to not start timer if Z axis velocity is a thing (non-prespeed styles).
- [x] Add speed reset at timer start.
- [x] Add support for 100AA styles.
- [x] Measure strafe count/sync, also have it in the Shavit_OnFinish forward.
- [x] Add low gravity styles (0.6).
- [x] Better implementation of autobhop and +ds (doublestep fix).
- [ ] Add bonus timer.

HUD
--
- [x] HUD toggling command. (`sm_hud`)
- [x] Zone (start/end) HUD toggling command. (`sm_zonehud`)
- [x] [CS:GO] Replace "- Replay Bot -" for bots with an underlined and pretty text.
- [x] Remove `sm_zonehud` and make `sm_hud` a menu that can toggle HUD, zonehud and spectators list in a panel.
- [x] Add spectator list.
- [x] Show time in a "TIME/RECORD" format for replay bots.
- [x] Support zonehud for CS:S.
- [X] Redo CS:S HUD and use the HUD capabilities added in late 2013, attempt to look like [this HUD](https://i.imgur.com/pj8c7vP.png) because I'm very original!!!111one!1!!
- [x] Show [PAUSED] if needed.
- [x] Add potential map rank.
- [x] Add strafes/sync. (replace 'Player' with strafes and sync in csgo, use keyhinttext for sync in css)
- [x] Show 'time left' to HUD (CS:S only).
- [ ] Support for bonus timer.

Replay
--
- [x] Make a boolean native that confirms if a client is a replay bot with loaded data. (used for `shavit-hud`)
- [x] Stop recording frames (and clear cache) when the player is past the WR for the style.
- [x] Overall optimizations.
- [x] Remove replay bot data on deletion of the #1 record.
- [x] Make replay bots dead if there's no replay data loaded.
- [x] Clear player cache on spawn/death.
- [x] Add admin interface. (delete replay data, `sm_deletereplay` for RCON admins.
- [ ] Add a setting so there are two modes: one is that bots always play, and the other is that there are X bots (defined by server admin) and players can start their playback with a command. (`sm_replay`)

Stats
--
- [x] Make style names editable from shavit.inc (like I did to the rest of modules) (dynamic!)
- [x] Make a submenu per style, for aesthetics.
- [x] [rankings] Points implementation.
- [x] Make MVP count the amount of WRs the player has. (with cvar)
- [x] Generate mapsdone points on the fly.
- [x] Add map rank to mapsdone.
- [x] Show strafes/sync in mapsdone submenu.
- [ ] Rework on points sorting and show weighting percentages.

Miscellaneous
--
- [x] Allow changing the prespeed limitation.
- [x] Add weapon cleanup.
- [x] Support radar hiding for CS:S.
- [x] Fix respawn for auto team join.
- [x] Create extra spawn points for both teams because many bhop maps lack them. (`shavit_misc_createspawnpoints`)
- [x] Support map changing, specifically SourceMod's built-in mapchooser and MCE.
- [x] Make frags/score as -time and deaths as rank.
- [x] Add `sm_usp` `sm_glock` `sm_knife`.
- [ ] Add SSJ (Speed Sixth Jump).

Sounds **(NEW!)**
--
- [x] Play sounds (from config file | `configs/shavit-sounds.cfg`) on new events.
- [x] On new #1.
- [x] On personal best.
- [x] On map finish.
- [x] Add support for 'sound for X map rank'.

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
- [x] Add native that checks the total amount of players with over 0 points.
- [ ] Find a way to update newly calculated points for all records on a map with the least amount of queries possible.
- [ ] Implement map tiers or remove idealtime and use the WR time for each style instead.
- [ ] Remove deleted records from `playerpoints`.

Web Interface
--
- [x] Implement points.
- [ ] Compatibility for unix timestamps.

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
- [x] Implement [Simple Chat Processor \(Redux\)](https://forums.alliedmods.net/showthread.php?p=1820365) support and make my own chat processor a fallback solution.

Zones
--
- [x] Add teleport zones (multiple). Use the command `sm_tpzone` between the time of setting the zone and confirming the setup.
- [x] Use string explosion in ZoneAdjuster_Handler and ZoneEdge_Handler for code efficiency.
- [x] CANCELED: Migrate zone settings to use Dynamic. (i didn't think *too* far into it before i started)
- [x] Handle teleport zones. (teleport to a value from gV_Teleport)
- [x] Change zone sprite. (see configs/shavit-zones.cfg and shavit_zones_usecustomsprite)
- [x] Optimize InsideZone() so 8 points won't be always calculated (blame ofir™). Cut execution time by over 95%!!
- [x] Add grid snapping on zone creation.

World Records
--
- [x] Make `UpdateWRCache` smaller. Will result in extra optimization and more uhm.. dynamic!
- [x] Add a cvar that limits the amount of records in the WR menu. (default: 50 | `shavit_wr_recordlimit`)
- [x] Remove `sm_wrsw` and make `sm_wr` a dynamic menu with all difficulties. (dynamic!)
- [x] [rankings] Show points in WR menu.
- [x] Add native that checks the total amount of players with records on a style.
- [x] Cache the whole leaderboard per style, sorted and updated at record removal, insertion and updates.
- [x] Add `Shavit_GetRankForTime(BhopStyle style, float time)` which will calculate a map rank for the given time.
- [x] Show map rank on finish.
- [x] Use unix timestamps for future record dates and add backwards compatibility.
- [x] Calculate points on the fly (sub-menu) instead of grabbing them from `playerpoints`.
- [x] Add `sm_recent` `sm_recentrecords` `sm_rr`.
- [x] Add strafes/sync to the WR menu where available.
- [ ] Add `sm_bwr` `sm_bonuswr` `sm_bonusworldrecord`.

Time Limits
--
- [x] Make the query order by time and add proper limitations.
- [x] Optimize query.
