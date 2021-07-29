# shavit's simple bhop timer
*a bhop server should be simple*

### Features
---

#### shavit-core (REQUIRED)
`bhoptimer`'s core.  
It handles connections to the database and exposes an API (natives/forwards) for developers and other modules.  
Calculations, gameplay mechanics and such are all handled by the core plugin.

Includes *but not limited to*: Custom chat messages and colors, snapshots, pausing/resuming, styles (configurable), automatic bunnyhopping, strafe/sync meters that work for most playstyles, double-step fixer (+ds), practice mode, +strafe blocking, +left/right blocking, pre-jump blocking, HSW style (including SHSW) that cannot be abused with joypads, per-style `sv_airaccelerate` values, teleportation commands (start/end).

#### shavit-zones (REQUIRED)
The zones plugins handles everything related to map zones (such as start/end zone etc) and is necessary for `bhoptimer` to operate.  
Zones are trigger based and are very lightweight.

The zones plugin includes some less common features such as: Multiple tracks (main/bonus), zone editing (after setup), snapping zones to walls/corners/grid, zone setup using the cursor's position, configurable sprite/colors for zone types, zone tracks (main/bonus - can be extended), manual adjustments of coordinates before confirmations, teleport zones, glitch zones, no-limit zones (for styles like 400-velocity), flat/3D boxes for zone rendering, an API and more.

It also contains support for built-in map timers (KZ) and the [Fly](https://github.com/3331/fly) zoning standard.

#### shavit-chat
The chat plugin manipulates chat messages sent by players.  
It includes custom chat names, tags, colors and all can be defined by the players/admins.  
Admins need the chat flag, or the "shavit_chat" override (good for a donator perk).  
There's a user-friendly command named !cchelp so the users can easily understand what's going on.  
In addition, it integrates with rankings and allows you to have titles for players according to their ranking, relative ranking or points in the server using !chatranks.

#### shavit-hud
The HUD plugin is `bhoptimer`'s OSD frontend.  
It shows most (if not all) of the information that the player needs to see.  
`shavit-hud` integrates with [Bunnyhop Statistics](https://github.com/shavitush/bhopstats) for CS:S.

Some features are: Per-player settings (!hud), truevel and gradient-like display (CS:GO).

#### shavit-misc
This plugin handles miscellaneous things used in bunnyhop servers.

Such as: Segmented runs, team handling (respawning/spectating too), spectators list (!specs), smart player hiding that works for spectating too, teleportation to other players, weapon commands (!knife/!usp/!glock) and ammo management, segmented checkpoints, noclipping (can be set to work for VIPs/admins only), drop-all, godmode, prespeed blocking, prespeed limitation, chat tidying, radar hiding, weapon drop cleaning, player collision removal, auto-respawning, spawn points generator, radio removal, scoreboard manipulation, model opacity changes, fixed runspeed, automatic and configurable chat advertisements, player ragdoll removal and WR messages.

#### shavit-rankings
Enables !rank, !top and introduces map tiers (!settier).  
Each record gets points assigned to it according to the map's tier and overall - how good the time is.  
This system doesn't allow "rank grinding" by beating all of the easy maps on the server but instead, awards the players that get the best times on the hardest maps and styles.

#### shavit-replay
Creates a replay bot that records the players' world records and playback them on command (!replay/automatic).  
The replay bot playback can be stopped (if central) and the saved replay can be deleted by server administrators.  
Replay bots will change their clan tags/names according to the server's configuration.

#### shavit-sounds
Will play custom sounds when event actions happen.  
Such as: Getting a world record, improving your own record, getting the worst record in the server, beating a map for the first time or setting a rank #X record.

#### shavit-stats
The statistics plugin is a statistics frontend for the players.  
It displays rankings, maps done, maps left, server records, SteamID, country, map completion, last login date and more useful information!

#### shavit-timelimit
Sets a dynamic map time limit according to the average completion time of the map.

#### shavit-wr (REQUIRED)
Saves the players' records to the database and allows players to see the server's records.  
The ability to see records for other maps also exists and can be lazily looked up (!wr map_name, or a part of the map's name).