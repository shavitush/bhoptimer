[![Discord server](https://discordapp.com/api/guilds/389675819959844865/widget.png?style=shield)](https://discord.gg/jyA9q5k)

### Build status
[![Build status](https://travis-ci.org/shavitush/bhoptimer.svg?branch=master)](https://travis-ci.org/shavitush/bhoptimer)

[AlliedModders thread](https://forums.alliedmods.net/showthread.php?t=265456)

[Download](https://github.com/shavitush/bhoptimer/releases)

# shavit's simple bhop timer
*a bhop server should be simple*

This is (nearly) an all-in-one server plugin for Counter-Strike: Source, Counter-Strike: Global Offensive and Team Fortress 2 that adds a timer system and many other utilities, so you can install it and have a proper bunnyhop server running.

Including a records system, map zones (start/end marks etc), bonuses, HUD with useful information, chat processor, miscellaneous such as weapon commands/spawn point generator, bots that replay the best records of the map, sounds, statistics, a fair & competitive rankings system and more!

[Mapzones' setup demonstration](https://youtu.be/OXFMGm40F6c)

# Requirements:
* Steam version of Counter-Strike: Source or Counter-Strike: Global Offensive.
* [SourceMod 1.9 or above](http://www.sourcemod.net/downloads.php)

# Optional requirements:
* [DHooks](http://users.alliedmods.net/~drifter/builds/dhooks/2.1/) - required for 250/260 runspeed for all weapons.
* [Bunnyhop Statistics](https://forums.alliedmods.net/showthread.php?t=286135) - to show amount of scrolls for non-auto styles in the key display. Required for TF2 servers.
* [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556) - for the `{serverip}` advertisement variable.
* [Chat-Processor](https://github.com/Drixevel/Chat-Processor) - if you're enabling the `shavit-chat` module.
* A MySQL database (preferably locally hosted) if your database is likely to grow or want to use the rankings plugin. MySQL server version of 5.5.5 or above (MariaDB equivalent works too) is recommended.

#  Installation:
Refer to the [wiki page](https://github.com/shavitush/bhoptimer/wiki/1.-Installation).

# Required plugins:
`shavit-core` - compeletely required.  
`shavit-zones` - compeletely required.  
`shavit-wr` - required for `shavit-stats`, `shavit-replay`, `shavit-rankings` and `shavit-sounds`.
