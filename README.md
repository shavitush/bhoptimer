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
3. Restart your server.

# Required plugins:
shavit-core - no other plugin will work without it.
shavit-zones - wouldn't really call it required but it's actually needed to get your timer to start/finish.

# Todo for 1.2b release < DONE!
- [x] + create a github repo

shavit-core:
- [x] * make a better check of game engine instead of using a directory
- [x] + sm_pause
- [x] + sm_resume
- [x] + add natives/forwards for sm_pause/resume and polish code

shavit-misc:
- [x] + cvar "shavit_misc_godmode"
0 - nothing
1 - only world damage
2 - only player damage
3 - full godmode
- [x] + 250 maxspeed for every pistol

shavit-zones:
- [x] + player slaying zone
- [x] + cvar "shavit_zones_style"
0 - 3d (default)
1 - 2d