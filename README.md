[![Discord server](https://discordapp.com/api/guilds/389675819959844865/widget.png?style=shield)](https://discord.gg/jyA9q5k)

### Build status
[![Build status](https://travis-ci.org/shavitush/bhoptimer.svg?branch=master)](https://travis-ci.org/shavitush/bhoptimer)

[AlliedModders thread](https://forums.alliedmods.net/showthread.php?t=265456)

[Download](https://github.com/shavitush/bhoptimer/releases)

# shavit's bhop timer

This is (nearly) an all-in-one server plugin for Counter-Strike: Source, Counter-Strike: Global Offensive and Team Fortress 2 that adds a timer system and many other utilities, so you can install it and run a proper bunnyhop server.

Includes a records system, map zones (start/end marks etc), bonuses, HUD with useful information, chat processor, miscellaneous such as weapon commands/spawn point generator, bots that replay the best records of the map, sounds, statistics, segmented running, a fair & competitive rankings system and more!

[Mapzones Setup Demonstration](https://youtu.be/OXFMGm40F6c)

# Requirements:
* Steam version of Counter-Strike: Source or Counter-Strike: Global Offensive.
* [SourceMod 1.10 or above](http://www.sourcemod.net/downloads.php?branch=dev)
* A MySQL database (preferably locally hosted) if your database is likely to grow big, or if you want to use the rankings plugin. MySQL server version of 5.5.5 or above (MariaDB equivalent works too) is highly recommended.

# Optional requirements, for the best experience:
* [DHooks](http://users.alliedmods.net/~drifter/builds/dhooks/2.1/)
* [Bunnyhop Statistics](https://forums.alliedmods.net/showthread.php?t=286135)
* [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556)

#  Installation:
Refer to the [wiki page](https://github.com/shavitush/bhoptimer/wiki/1.-Installation-(from-source)).

# Required plugins:
`shavit-core` - completely required.  
`shavit-zones` - completely required.  
`shavit-wr` - required for `shavit-stats`, `shavit-replay`, `shavit-rankings` and `shavit-sounds`.
