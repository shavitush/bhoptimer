# shavit's simple bhop timer
*a bhop server should be simple*

### Features
---

###### shavit-core (REQUIRED)
`bhoptimer`'s core.  
It handles connections to the database and exposes an API (natives/forwards) for developers and other modules.  
Calculations, gameplay mechanics and such are all handled by the core plugin.

Includes *but not limited to*: Custom chat messages and colors, snapshots, pausing/resuming, styles (configurable), automatic bunnyhopping, strafe/sync meters that work for most playstyles, double-step fixer (+ds), practice mode, +strafe blocking, +left/right blocking, pre-jump blocking, HSW style (including SHSW) that cannot be abused with joypads, per-style `sv_airaccelerate` values, teleportation commands (start/end).

###### shavit-zones (REQUIRED)
The zones plugins handles everything related to map zones (such as start/end zone etc) and is necessary for `bhoptimer` to operate.  
Zones are trigger based and are very lightweight.

The zones plugin includes some less common features such as: Zone editing (after setup), snapping zones to walls/corners/grid, zone setup using the cursor's position, configurable sprite/colors for zoone types, zone tracks (main/bonus - can be extended), manual adjustments of coordinates before confirmations, teleport zones, glitch zones, no-limit zones (for styles like 400-velocity), flat/3D boxes for zone rendering, an API and more.

###### shavit-hud
The HUD plugin is `bhoptimer`'s OSD frontend.  
It shows most (if not all) of the information that the player needs to see.  
`shavit-hud` integrates with [Bunnyhop Statistics](https://github.com/shavitush/bhopstats) for CS:S.

Some features are: Per-player settings (!hud), truevel and gradient-like display (CS:GO).

###### shavit-misc
This plugin handles miscellaneous things used in bunnyhop servers.

Such as: Team handling (respawning/spectating too), spectators list (!specs), smart player hiding that works for spectating too, teleportation to other players, weapon commands (!knife/!usp/!glock) and ammo management, segmented checkpoints, noclipping (can be set to work for VIPs/admins only), drop-all, godmode, prespeed blocking, prespeed limitation, chat tidying, radar hiding, weapon drop cleaning, player collision removal, auto-respawning, spawn points generator, radio remobal, scoreboard manipulation, model opacity changes, fixed runspeed, automatic and configurable chat advertisements, player ragdoll removal and WR messages.