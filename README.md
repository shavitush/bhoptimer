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

# Todo for 1.3b release
shavit-core:
- [x] + Handle freestyle zones

shavit-zones:
- [x] + Allow creation of freestyle zones
- [x] + Make multiple freestyle zones possible (damn you Aoki and badges for making stuff difficult!)
- [x] + Handle deletion of multiple freestyle zones
- [ ] + Handle drawing of end/freestyle zones properly

# Todo for 1.4b release
[NEW PLUGIN] shavit-stats:
[NEW PLUGIN] shavit-ranks:
[NEW PLUGIN] shavit-replay: