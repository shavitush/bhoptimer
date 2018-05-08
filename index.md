# shavit's bhoptimer

bhoptimer is (nearly) an all-in-one server plugin for the games Counter-Strike: Source, Counter-Strike: Global Offensive and Team Fortress 2.  
It's responsible for adding a 'timer system' and many other utilities, so you can install it and have a proper bunnyhop (or any other movement gamemode) server running smoothly!

It includes a records system, map zones (start/end marks and such), bonuses, HUD-type OSD with useful information, chat processor and rankings integration, miscellaneous such as weapon commands/spawn point generator, bots that replay the best records of the map, record sounds, interesting statistics, a fair & competitive rankings system and more!

## Requirements

* Legal copy of either CS:S, CS:GO or TF2.
* [Metamod: Source](http://sourcemm.net/downloads.php?branch=stable)
* [SourceMod 1.9 or above](hthttp://www.sourcemod.net/downloads.php?branch=dev)

# Optional Requirements

Install these for the best experience.

* [DHooks](http://users.alliedmods.net/%7Edrifter/builds/dhooks/2.1/)
* [Bunnyhop Statistics](https://forums.alliedmods.net/showthread.php?t=286135)

## Installation

* [Build from source](https://github.com/shavitush/bhoptimer/wiki/1.-Installation)
* [Download an existing release](https://github.com/shavitush/bhoptimer/releases) - installing is simply drag & drop into the  game server's directory.

## Configuration

The [wiki](https://github.com/shavitush/bhoptimer/wiki) contains most relevant information regarding configuration, under the 2nd category's pages.

Configuration files are in `cfg/sourcemod/plugin.shavit-*.cfg` and `addons/sourcemod/configs/shavit-*`.

## Modules

#### shavit-core (REQUIRED)
`bhoptimer`'s core.  
It handles connections to the database and exposes an API (natives/forwards) for developers and other modules.  
Calculations, gameplay mechanics and such are all handled by the core plugin.

Includes *but not limited to*: Custom chat messages and colors, snapshots, pausing/resuming, styles (configurable), automatic bunnyhopping, strafe/sync meters that work for most playstyles, double-step fixer (+ds), practice mode, +strafe blocking, +left/right blocking, pre-jump blocking, HSW style (including SHSW) that cannot be abused with joypads, per-style `sv_airaccelerate` values, teleportation commands (start/end).

```
Player commands:
!style, !styles, !diff, !difficulty - Choose your bhop style.
!s, !start, !r, !restart - Start your timer.
!b, !bonus - Start your timer on the bonus track.
!end - Teleport to endzone.
!bend, !bonusend - Teleport to endzone of the bonus track.
!stop - Stop your timer.
!pause, !unpause, !resume - Toggle pause.
!auto, !autobhop - Toggle autobhop.
```

#### shavit-zones (REQUIRED)
The zones plugins handles everything related to map zones (such as start/end zone etc) and is necessary for `bhoptimer` to operate.  
Zones are trigger based and are very lightweight.

The zones plugin includes some less common features such as: Multiple tracks (main/bonus), zone editing (after setup), snapping zones to walls/corners/grid, zone setup using the cursor's position, configurable sprite/colors for zone types, zone tracks (main/bonus - can be extended), manual adjustments of coordinates before confirmations, teleport zones, glitch zones, no-limit zones (for styles like 400-velocity), flat/3D boxes for zone rendering, an API and more.

It also contains support for built-in map timers (KZ) and the [Fly](https://github.com/3331/fly) zoning standard.

```
Admin commands: (RCON flag)
!zones, !mapzones - Opens the mapzones menu.
!deletezone - Delete a mapzone.
!deleteallzones - Delete all mapzones.
!modifier - Changes the axis modifier for the zone editor. Usage: !modifier <number>
!addspawn - Adds a custom spawn location.
!delspawn - Deletes a custom spawn location.
!zoneedit, !editzone, !modifyzone - Modify an existing zone.

Admin commands: (ROOT flag)
!reloadzonesettings - Reloads the zone settings.
```

#### shavit-chat
The chat plugin manipulates chat messages sent by players.  
It includes custom chat names, tags, colors and all can be defined by the players/admins.  
Admins need the chat flag, or the "shavit_chat" override (good for a donator perk).  
There's a user-friendly command named !cchelp so the users can easily understand what's going on.  
In addition, it integrates with rankings and allows you to have titles for players according to their ranking, relative ranking or points in the server using !chatranks.

```
Player commands:
!cchelp - Provides help with setting a custom chat name/message color.
!ccname - Toggles/sets a custom chat name. Usage: !ccname <text> or !ccname "off" to disable.
!ccmsg, !ccmessage - Toggles/sets a custom chat message color. Usage: !ccmsg <color> or !ccmsg "off" to disable.
!chatrank, !chatranks - View a menu with the chat ranks available to you.

Admin commands: (CHAT flag)
!cclist - Print the custom chat setting of all online players.

Admin commands: (ROOT flag)
!reloadchatranks - Reloads the chatranks config file.
```

#### shavit-hud
The HUD plugin is `bhoptimer`'s OSD frontend.  
It shows most (if not all) of the information that the player needs to see.  
`shavit-hud` integrates with [Bunnyhop Statistics](https://github.com/shavitush/bhopstats) for CS:S.

Some features are: Per-player settings (!hud), truevel and gradient-like display (CS:GO).

```
Player commands:
!hud, !options - Opens the HUD settings menu.
```

#### shavit-misc
This plugin handles miscellaneous things used in bunnyhop servers.

Such as: Team handling (respawning/spectating too), spectators list (!specs), smart player hiding that works for spectating too, teleportation to other players, weapon commands (!knife/!usp/!glock) and ammo management, segmented checkpoints, noclipping (can be set to work for VIPs/admins only), drop-all, godmode, prespeed blocking, prespeed limitation, chat tidying, radar hiding, weapon drop cleaning, player collision removal, auto-respawning, spawn points generator, radio removal, scoreboard manipulation, model opacity changes, fixed runspeed, automatic and configurable chat advertisements, player ragdoll removal and WR messages.

```
Player commands:
!specs, !spectators - Show a list of spectators.
!spec, !spectate - Moves you to the spectators' team. Usage: !spec [target]
!hide, !unhide - Toggle players' hiding.
!tpto, !goto - Teleport to another player. Usage: !tpto [target]
!usp, !glock, !knife - Spawn a USP/Glock/Knife.
!cp, !cpmenu, !checkpoint, !checkpoints - Opens the checkpoints menu.
!save - Saves checkpoint (default: 1). Usage: !save [number]
!tele - Teleports to checkpoint (default: 1). Usage: !tele [number]
!p, !prac, !practice, !nc, !noclipme, +noclip - Toggles noclip.
```

#### shavit-rankings
Enables !rank, !top and introduces map tiers (!settier).  
Each record gets points assigned to it according to the map's tier and overall - how good the time is.  
This system doesn't allow "rank grinding" by beating all of the easy maps on the server but instead, awards the players that get the best times on the hardest maps and styles.

```
Player commands:
!tier, !maptier - Prints the map's tier to chat.
!rank - Show your or someone else's rank. Usage: !rank [name]
!top - Show the top 100 players.

Admin commands: (RCON flag)
!settier, !setmaptier - Change the map's tier. Usage: !settier <tier>
!recalcmap - Recalculate the current map's records' points.

Admin commands: (ROOT flag)
!recalcall - Recalculate the points for every map on the server. Run this after you change the ranking multiplier for a style or after you install the plugin.
```

#### shavit-replay
Creates a replay bot that records the players' world records and playback them on command (!replay/automatic).  
The replay bot playback can be stopped (if central) and the saved replay can be deleted by server administrators.  
Replay bots will change their clan tags/names according to the server's configuration.

```
Player commands:
!replay - Opens the central bot menu. For admins: '!replay stop' to stop the playback.

Admin commands: (RCON flag)
!deletereplay - Open replay deletion menu.
```

#### shavit-sounds
Will play custom sounds when event actions happen.  
Such as: Getting a world record, improving your own record, getting the worst record in the server, beating a map for the first time or setting a rank #X record.

#### shavit-stats
The statistics plugin is a statistics frontend for the players.  
It displays rankings, maps done, maps left, server records, SteamID, country, map completion, last login date and more useful information!

```
Player commands:
!profile, !stats - Show the player's profile. Usage: !profile [target]
```

#### shavit-timelimit
Sets a dynamic map time limit according to the average completion time of the map.

#### shavit-wr
Saves the players' records to the database and allows players to see the server's records.  
The ability to see records for other maps also exists and can be lazily looked up (!wr map_name, or a part of the map's name).

```
Player commands:
!wr, !worldrecord - View the leaderboard of a map. Usage: !wr [map]
!bwr, !bworldrecord, !bonusworldrecord - View the *bonus* leaderboard of a map. Usage: !bwr [map]
!recent, !recentrecords, !rr - View the recent #1 times set.

Admin commands: (RCON flag)
!delete, !deleterecord, !deleterecords - Opens a record deletion menu interface.
!deletall - Deletes all the records for this map.
!deletestylerecords - Deletes all the records for a style.
```
