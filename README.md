### Build status
[![Build status](https://travis-ci.org/shavitush/bhoptimer.svg?branch=master)](https://travis-ci.org/shavitush/bhoptimer)

[AlliedModders thread](https://forums.alliedmods.net/showthread.php?t=265456)

[Download](https://github.com/shavitush/bhoptimer/releases)

# shavit's simple bhop timer
*a bhop server should be simple*

This is (nearly) an all-in-one server plugin for Counter-Strike: Source and Counter-Strike: Global Offensive that adds a timer system and many other utilities, so you can install it and have a proper bunnyhop server running.

Including a records system, map zones (start/end marks etc), HUD with useful information, chat processor, miscellaneous such as weapon commands/spawn point generator, bots that replay the best records of the map, sounds, statistics, rankings and more!

[Mapzones' setup demonstration](https://www.youtube.com/watch?v=oPKso2hoLw0)

# Requirements:
* Steam version of Counter-Strike: Source or Counter-Strike: Global Offensive.
* [SourceMod 1.8 or above](http://www.sourcemod.net/downloads.php)

# Optional requirements:
* `sv_disable_immunity_alpha` set to 1 in CS:GO for the `shavit_misc_playeropacity` setting to work.
* [DHooks](http://users.alliedmods.net/~drifter/builds/dhooks/2.0/) - required for 250/260 runspeed for all weapons.
* [The RTLer](https://forums.alliedmods.net/showthread.php?p=1649882) - required for properly formatted RTL text within `shavit-chat`.
* [Chat-Processor](https://forums.alliedmods.net/showthread.php?t=286913) - for more proper parsing inside `shavit-chat`.
* [Bunnyhop Statistics](https://forums.alliedmods.net/showthread.php?t=286135) - to show amount of scrolls for non-auto styles in the key display. CS:S only!
* [SteamWorks](https://forums.alliedmods.net/showthread.php?t=229556) - for the `{serverip}` advertisement variable.

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
4. Copy the files from the `sound` folder to the one on your server. Make sure to also have equivalent bz2 files on your FastDL server!  
4.1. Do the same for the `materials` folder.
5. Copy the `configs` folder to your server and modify them if you need to.  
5.1. Changing `shavit-prefix.txt` to contain your MySQL database prefix might be needed depending on your usage.
6. Copy the `translations` folder to your server.  
7. Restart your server.

# Required plugins:
`shavit-core` - compeletely required.
`shavit-zones` - compeletely required.
`shavit-wr` - required for `shavit-stats`, `shavit-replay`, `shavit-sounds` and `shavit-stats`.