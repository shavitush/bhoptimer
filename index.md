[![Discord server](https://discordapp.com/api/guilds/389675819959844865/widget.png?style=shield)](https://discord.gg/jyA9q5k)

### RECOMPILE ALL YOUR PLUGINS THAT USE `#include <shavit>` OR STUFF WILL BREAK

[AlliedModders thread](https://forums.alliedmods.net/showthread.php?t=265456)

[Download](https://github.com/shavitush/bhoptimer/releases)

# shavit's bhop timer

This is nearly an all-in-one server plugin suite for Counter-Strike: Source, Counter-Strike: Global Offensive, and Team Fortress 2 that adds a timer system and many other utilities, so you can install it and run a proper bunnyhop server.

Includes a records system, map zones (start/end marks etc), bonuses, HUD with useful information, chat processor, miscellaneous things such as weapon commands/spawn point generator, bots that replay the best records of the map, sounds, statistics, segmented running, a fair & competitive rankings system, and more!

[Mapzones Setup Demonstration](https://youtu.be/OXFMGm40F6c)

# Requirements:
* Steam version of Counter-Strike: Source, Counter-Strike: Global Offensive, or Team Fortress 2.
* [Metamod:Source](https://www.sourcemm.net/downloads.php?branch=stable) and [SourceMod 1.10 or above](https://www.sourcemod.net/downloads.php?branch=stable) installed.
* A MySQL database (preferably locally hosted) if your database is likely to grow big, or if you want to use the rankings plugin. MySQL server version of 5.5.5 or above (MariaDB equivalent works too) is required.
* [DHooks](https://github.com/peace-maker/DHooks2/releases)

# Optional requirements, for the best experience:
* [eventqueuefix](https://github.com/hermansimensen/eventqueue-fix)
  * Allows for timescaling boosters and is used to fix some exploits. (Use this instead of `boosterfix`)
* [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556)
  * Used to grab `{serverip}` in advertisements.
* [DynamicChannels](https://github.com/Vauff/DynamicChannels)

# Installation

* [Build from source](https://github.com/shavitush/bhoptimer/wiki/1.-Installation)
* [Download an existing release](https://github.com/shavitush/bhoptimer/releases) - installing is simply drag & drop into the  game server's directory.

# Configuration

The [wiki](https://github.com/shavitush/bhoptimer/wiki) contains most relevant information regarding configuration, under the 2nd category's pages.

Configuration files are in `cfg/sourcemod/plugin.shavit-*.cfg` and `addons/sourcemod/configs/shavit-*`.

# bhoptimer modules:

### shavit-core (REQUIRED)
`bhoptimer`'s core.
It handles connections to the database and exposes an API (natives/forwards) for developers and other modules.
Calculations, gameplay mechanics and such are all handled by the core plugin.

Includes *but not limited to*: Custom chat messages and colors, snapshots, pausing/resuming, styles (configurable), automatic bunnyhopping, strafe/sync meters that work for most playstyles, double-step fixer (+ds), practice mode, +strafe blocking, +left/right blocking, pre-jump blocking, HSW style (including SHSW) that cannot be abused with joypads, per-style `sv_airaccelerate` values, teleportation commands (start/end).

```
Player commands:
!style, !styles, !diff, !difficulty - Choose your bhop style.
!s, !start, !r, !restart - Start your timer.
!b, !bonus, !b1, !b2, etc - Start your timer on the bonus track.
!m, !main - Start your timer on the main track.
!end - Teleport to endzone.
!bend, !bonusend - Teleport to endzone of the bonus track.
!stop - Stop your timer.
!pause, !unpause, !resume - Toggle pause.
!auto, !autobhop - Toggle autobhop.

Admin commands:
!deletemap (RCON flag) - Deletes all map data.
!wipeplayer (BAN flag) - Wipes all bhoptimer data for specified player.
!migration (ROOT flag) - Force a database migration to run.
```

### shavit-wr (REQUIRED)
Saves the players' records to the database and allows players to see the server's records.
The ability to see records for other maps also exists and can be lazily looked up (!wr map_name, or a part of the map's name).

```
Player commands:
!wr, !worldrecord - View the leaderboard of a map. Usage: !wr [map]
!bwr, !bworldrecord, !bonusworldrecord - View the *bonus* leaderboard of a map. Usage: !bwr [map]
!recent, !recentrecords, !rr - View the recent #1 times set.
!pb, !time, !times - View a player's times on a specific map.

Admin commands: (RCON flag)
!delete, !deleterecord, !deleterecords - Opens a record deletion menu interface.
!deletall - Deletes all the records for this map.
```

### shavit-zones (REQUIRED)
The zones plugins handles everything related to map zones (such as start/end zone etc) and is necessary for `bhoptimer` to operate.
Zones are trigger based and are very lightweight.

The zones plugin includes some less common features such as: Multiple tracks (main/bonus), zone editing (after setup), snapping zones to walls/corners/grid, zone setup using the cursor's position, configurable sprite/colors for zone types, zone tracks (main/bonus - can be extended), manual adjustments of coordinates before confirmations, teleport zones, glitch zones, no-limit zones (for styles like 400-velocity), flat/3D boxes for zone rendering, an API and more.

It also contains support for built-in map timers (KZ) and the [Fly](https://github.com/PMArkive/fly) zoning standard.

```
Player commands:
!set, !setstart, !ss, !sp, !startpoint - Set your current position as the teleport location on restart.
!deletestart, !deletesetstart, !delss, !delsp - Delete your spawn point.
!drawallzones, !drawzones - Draws all zones (if the server has the cvar for this enabled).

Admin commands: (RCON flag)
!zones, !mapzones, !addzone - Opens the mapzones menu.
!deletezone, !delzone - Delete a mapzone.
!deleteallzones - Delete all mapzones.
!modifier - Changes the axis modifier for the zone editor. Usage: !modifier <number>
!addspawn - Adds a custom spawn location.
!delspawn - Deletes a custom spawn location.
!zoneedit, !editzone, !modifyzone - Modify an existing zone.
!setstart, !spawnpoint, !ss, !sp - Set your restart position & angles in a start zone.
!tptozone - Teleport to a zone.

Admin commands: (ROOT flag)
!reloadzonesettings - Reloads the zone settings.
```

### shavit-chat
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
!ccadd - Give a user ccname & ccmsg access by steamid. Usage: !ccadd <steamid>

Admin commands: (ROOT flag)
!ccdelete - Remove a user's ccname & ccmsg access that was granted by !ccadd. Usage: !ccdelete <steamid>
!cclist - Print the custom chat setting of all online players.
!reloadchatranks - Reloads the chatranks config file.
```

### shavit-hud
The HUD plugin is `bhoptimer`'s OSD frontend.
It shows most (if not all) of the information that the player needs to see.

Some features are: Per-player settings (!hud), truevel, and gradient-like display (CS:GO).

```
Player commands:
!hud, !options - Opens the HUD settings menu.
!keys, !showkeys, !showmykeys - Draw plugin keys on screen.
!master, !masterhud - Toggles the HUD.
!center, !centerhud - Toggles the center text HUD.
!zonehud - Toggles the zone HUD.
!hidewep, !hideweap, !hideweapon - Toggles weapon hiding.
!2dvel, !truevel, !truvel - Toggles 2D ('true') velocity.
```

### shavit-mapchooser
Replaces `mapchooser` to provide `bhoptimer` integration into nomination and map vote menus.

```
Admin commands: (CHANGEMAP flag)
!forcemapvote - Forces the map vote to happen.
!reloadmaplist - Reloads the maplist.
!reloadmap, !restartmap - Reloads the current map.
!loadunzonedmap - Loads a random map from the maps folder that is unzoned.
```

### shavit-checkpoints
This plugin handles checkpoint related things such as segmented runs & savestates/persistent-data.

```
Player commands:
!cp, !cpmenu, !checkpoint, !checkpoints - Opens the checkpoints menu.
!save - Saves a checkpoint.
!tele - Teleports to a checkpoint (default: 1). Usage: !tele [number]
!prevcp - Selects the previous checkpoint.
!nextcp - Selects the next checkpoint.
!deletecp - Deletes the current checkpoint.
```

### shavit-misc
This plugin handles miscellaneous things used in bunnyhop servers.

Such as: team handling (respawning/spectating too), spectators list (!specs), smart player hiding that works for spectating too, teleportation to other players, weapon commands (!knife/!usp/!glock) and ammo management, noclipping (can be set to work for VIPs/admins only), drop-all, godmode, prespeed blocking, prespeed limitation, chat tidying, radar hiding, weapon drop cleaning, player collision removal, auto-respawning, spawn points generator, radio removal, scoreboard manipulation, model opacity changes, fixed runspeed, automatic and configurable chat advertisements, player ragdoll removal, and WR messages.

```
Player commands:
!specs, !spectators - Show a list of spectators.
!spec, !spectate - Moves you to the spectators' team. Usage: !spec [target]
!hide, !unhide - Toggle players' hiding.
!tpto, !goto - Teleport to another player. Usage: !tpto [target]
!usp, !glock, !knife - Spawn a USP/Glock/Knife.
!nc, !prac, !practice, !noclipme, +noclip, sm_noclip - Toggles noclip.
!adverts - Prints all adverts to the client.
```

### shavit-rankings
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

### shavit-replay-playback
Creates a replay bot that records the players' world records and playback them on command (!replay/automatic).
The replay bot playback can be stopped (if central) and the saved replay can be deleted by server administrators.
Replay bots will change their clan tags/names according to the server's configuration.

```
Player commands:
!replay - Opens the replay bot menu.

Admin commands: (RCON flag)
!deletereplay - Open replay deletion menu.
```

### shavit-replay-recorder
This is now the actual plugin that records the replays. ||I wanted to split shavit-replay so I could deal with reloading plugins without losing replay data better.||

### shavit-sounds
Will play custom sounds when event actions happen.
Such as: Getting a world record, improving your own record, getting the worst record in the server, beating a map for the first time or setting a rank #X record.

### shavit-stats
The statistics plugin is a statistics frontend for the players.
It displays rankings, maps done, maps left, server records, SteamID, country, map completion, last login date, and more useful information!

```
Player commands:
!p, !profile, !stats - Show the player's profile. Usage: !profile [target]
!mapsdone - Shows the maps the player has finished.
!mapsleft - Shows maps that the player has not finished yet.
!playtime - Shows the top playtime list.
```

### shavit-timelimit
Sets a dynamic map time limit according to the average completion time of the map.

```
Admin commands: (CHANGEMAP flag)
!extend, !extendmap - Extend the map.
```

### shavit-tas
Provides autostrafers and other TAS related functionality.

```
Player commands:
+autostrafer/-autostrafer, !autostrafer - Toggle the autostrafer.
+autoprestrafe/-autoprestrafe, !autoprestrafe - Toggle automatically prestrafing.
+autojumponstart/-autojumponstart, !autojumponstart - Toggle jumping automatically on start.
+edgejump/-edgejump, !edgejump - Toggle edge jumping.
```

# Recommended plugins:
* [MomSurfFix](https://forums.alliedmods.net/showthread.php?p=2680743) ([github](https://github.com/GAMMACASE/MomSurfFix))
  - Makes surf ramps less likely to stop players. (Ramp bug / surf glitch)
* [RNGFix](https://forums.alliedmods.net/showthread.php?t=310825) ([github](https://github.com/jason-e/rngfix))
  - Makes slopes, teleporters, and more less random. Replaces `slopefix`
* [HeadBugFix](https://github.com/GAMMACASE/HeadBugFix)
  - Fixes head bounding boxes when ducking so it's not possible to touch triggers through a roof.
* [Showtriggers](https://forums.alliedmods.net/showthread.php?t=290356) ([github](https://github.com/1ci/showtriggers)) or [Eric's Edit](https://github.com/ecsr/showtriggers)
  - Allows players to toggle trigger visibility.
* [ShowPlayerClips](https://forums.alliedmods.net/showthread.php?p=2661942) ([github](https://github.com/GAMMACASE/ShowPlayerClips))
  - Allows players to toggle player clip visibility.
* [shavit-ssj](https://github.com/Nairdaa/shavit-ssj)
  - Speed of Sixth Jump + more, customisable settings with cookies remembering user prefered settings.
* [shavit-jhud](https://github.com/blankbhop/jhud)
  - Jump HUD for bhoptimer. !jhud for settings.
* [shavit-firstjumptick](https://github.com/Nairdaa/bhoptimer-firstjumptick)
  - Displays what tick the player first jumps at upon leaving the startzone. Very useful for strafe maps, where you tryhard to cut that tick or two. !fjt to enable.
* [sm_closestpos](https://github.com/rtldg/sm_closestpos)
  - C++ extension to efficiently find the closest replay position for calculating time-difference and velocity-difference.
* [mpbhops_but_better](https://github.com/rtldg/mpbhops_but_working)
  - A cleaner and faster mpbhops/mpbh plugin that also makes door vertical-boosters consistent and frozen.

### CS:GO
* [NoViewPunch](https://github.com/hermansimensen/NoViewPunch)
  - Removes the viewpunch from landing in CS:GO.
* [CS:GO Movement unlocker](https://forums.alliedmods.net/showthread.php?t=255298)
  - Enables prespeeding (no 240 velocity cap for runspeed anymore)
