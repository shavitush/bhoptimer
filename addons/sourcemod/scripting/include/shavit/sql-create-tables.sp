#include <shavit-bhoptimer/shavit-sql-types.inc>
#include <shavit-bhoptimer/shavit-sql-migrations.sp>

bool gB_MySQL;
char gS_SQLPrefix[32];

char gS_TableNames[][32] = {
	"users",
	"migrations",
	"maptiers",
	"styleplaytime",
	"playertimes",
	"stagetimeswr",
	"stagetimespb",
	"wrs_min",
	"wrs",
	"mapzones",
	"startpositions",
};

public void Shavit__RunDatabaseLoadedForward()
{
	static GlobalForward hOnDatabasedLoaded;

	if (hOnDatabasedLoaded == null)
	{
		hOnDatabasedLoaded = new GlobalForward("Shavit_OnDatabaseLoaded", ET_Ignore);
	}

	Call_StartForward(hOnDatabasedLoaded);
	Call_Finish(hOnDatabasedLoaded);
}

public void Shavit__CreateTables(Database2 hSQL, const char[] prefix, bool mysql)
{
	gB_MySQL = mysql;
	strcopy(gS_SQLPrefix, sizeof(gS_SQLPrefix), prefix);

	Transaction2 hTrans = new Transaction2();

	char sQuery[2048];
	char sOptionalINNODB[16];

	if (gB_MySQL)
	{
		sOptionalINNODB = "ENGINE=INNODB";
	}

	//
	//// shavit-core
	//

	if (gB_MySQL)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%susers` (`auth` INT NOT NULL, `name` VARCHAR(32) COLLATE 'utf8mb4_general_ci', `ip` INT, `lastlogin` INT NOT NULL DEFAULT -1, `points` FLOAT NOT NULL DEFAULT 0, `playtime` FLOAT NOT NULL DEFAULT 0, PRIMARY KEY (`auth`), INDEX `points` (`points`), INDEX `lastlogin` (`lastlogin`)) ENGINE=INNODB;",
			gS_SQLPrefix);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%susers` (`auth` INT NOT NULL PRIMARY KEY, `name` VARCHAR(32), `ip` INT, `lastlogin` INTEGER NOT NULL DEFAULT -1, `points` FLOAT NOT NULL DEFAULT 0, `playtime` FLOAT NOT NULL DEFAULT 0);",
			gS_SQLPrefix);
	}

	hTrans.AddQuery(sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%smigrations` (`code` TINYINT NOT NULL, UNIQUE INDEX `code` (`code`));",
		gS_SQLPrefix);
	hTrans.AddQuery(sQuery);

	//
	//// shavit-chat
	//

	if (gB_MySQL)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%schat` (`auth` INT NOT NULL, `name` INT NOT NULL DEFAULT 0, `ccname` VARCHAR(128) COLLATE 'utf8mb4_unicode_ci', `message` INT NOT NULL DEFAULT 0, `ccmessage` VARCHAR(16) COLLATE 'utf8mb4_unicode_ci', `ccaccess` INT NOT NULL DEFAULT 0, PRIMARY KEY (`auth`), CONSTRAINT `%sch_auth` FOREIGN KEY (`auth`) REFERENCES `%susers` (`auth`) ON UPDATE CASCADE ON DELETE CASCADE) ENGINE=INNODB;",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%schat` (`auth` INT NOT NULL, `name` INT NOT NULL DEFAULT 0, `ccname` VARCHAR(128), `message` INT NOT NULL DEFAULT 0, `ccmessage` VARCHAR(16), `ccaccess` INT NOT NULL DEFAULT 0, PRIMARY KEY (`auth`), CONSTRAINT `%sch_auth` FOREIGN KEY (`auth`) REFERENCES `%susers` (`auth`) ON UPDATE CASCADE ON DELETE CASCADE);",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix);
	}

	hTrans.AddQuery(sQuery);

	//
	//// shavit-rankings
	//

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%smaptiers` (`map` VARCHAR(255), `tier` INT NOT NULL DEFAULT 1, PRIMARY KEY (`map`)) %s;",
		gS_SQLPrefix, sOptionalINNODB);
	hTrans.AddQuery(sQuery);

	//
	//// shavit-stats
	//

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%sstyleplaytime` (`auth` INT NOT NULL, `style` INT NOT NULL, `playtime` FLOAT NOT NULL, PRIMARY KEY (`auth`, `style`));",
		gS_SQLPrefix);
	hTrans.AddQuery(sQuery);

	//
	//// shavit-wr
	//

	if (gB_MySQL)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%splayertimes` (`id` INT NOT NULL AUTO_INCREMENT, `auth` INT, `map` VARCHAR(255), `time` FLOAT, `jumps` INT, `style` TINYINT, `date` INT, `strafes` INT, `sync` FLOAT, `points` FLOAT NOT NULL DEFAULT 0, `track` TINYINT NOT NULL DEFAULT 0, `perfs` FLOAT DEFAULT 0, `completions` SMALLINT DEFAULT 1, `exact_time_int` INT DEFAULT 0, PRIMARY KEY (`id`), INDEX `map` (`map`, `style`, `track`, `time`), INDEX `auth` (`auth`, `date`, `points`), INDEX `time` (`time`)) ENGINE=INNODB;",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%splayertimes` (`id` INTEGER PRIMARY KEY, `auth` INT, `map` VARCHAR(255), `time` FLOAT, `jumps` INT, `style` TINYINT, `date` INT, `strafes` INT, `sync` FLOAT, `points` FLOAT NOT NULL DEFAULT 0, `track` TINYINT NOT NULL DEFAULT 0, `perfs` FLOAT DEFAULT 0, `completions` SMALLINT DEFAULT 1, `exact_time_int` INT DEFAULT 0);",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix);
	}

	hTrans.AddQuery(sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%sstagetimeswr` (`style` TINYINT NOT NULL, `track` TINYINT NOT NULL DEFAULT 0, `map` VARCHAR(255) NOT NULL, `stage` TINYINT NOT NULL, `auth` INT NOT NULL, `time` FLOAT NOT NULL, PRIMARY KEY (`style`, `track`, `map`, `stage`)) %s;",
		gS_SQLPrefix, sOptionalINNODB);
	hTrans.AddQuery(sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%sstagetimespb` (`style` TINYINT NOT NULL, `track` TINYINT NOT NULL DEFAULT 0, `map` VARCHAR(255) NOT NULL, `stage` TINYINT NOT NULL, `auth` INT NOT NULL, `time` FLOAT NOT NULL, PRIMARY KEY (`style`, `track`, `auth`, `map`, `stage`)) %s;",
		gS_SQLPrefix, sOptionalINNODB);
	hTrans.AddQuery(sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"%s %swrs_min AS SELECT MIN(time) time, map, track, style FROM %splayertimes GROUP BY map, track, style;",
		gB_MySQL ? "CREATE OR REPLACE VIEW" : "CREATE VIEW IF NOT EXISTS",
		gS_SQLPrefix, gS_SQLPrefix);
	hTrans.AddQuery(sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"%s %swrs AS SELECT a.* FROM %splayertimes a JOIN %swrs_min b ON a.time = b.time AND a.map = b.map AND a.track = b.track AND a.style = b.style;",
		gB_MySQL ? "CREATE OR REPLACE VIEW" : "CREATE VIEW IF NOT EXISTS",
		gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix);
	hTrans.AddQuery(sQuery);

	//
	//// shavit-wr
	//

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%smapzones` (`id` INT AUTO_INCREMENT, `map` VARCHAR(128), `type` INT, `corner1_x` FLOAT, `corner1_y` FLOAT, `corner1_z` FLOAT, `corner2_x` FLOAT, `corner2_y` FLOAT, `corner2_z` FLOAT, `destination_x` FLOAT NOT NULL DEFAULT 0, `destination_y` FLOAT NOT NULL DEFAULT 0, `destination_z` FLOAT NOT NULL DEFAULT 0, `track` INT NOT NULL DEFAULT 0, `flags` INT NOT NULL DEFAULT 0, `data` INT NOT NULL DEFAULT 0, `prebuilt` BOOL, PRIMARY KEY (`id`)) %s;",
		gS_SQLPrefix, sOptionalINNODB);
	hTrans.AddQuery(sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%sstartpositions` (`auth` INTEGER NOT NULL, `track` INTEGER NOT NULL, `map` VARCHAR(128) NOT NULL, `pos_x` FLOAT, `pos_y` FLOAT, `pos_z` FLOAT, `ang_x` FLOAT, `ang_y` FLOAT, `ang_z` FLOAT, `angles_only` BOOL, PRIMARY KEY (`auth`, `track`, `map`)) %s;",
		gS_SQLPrefix, sOptionalINNODB);
	hTrans.AddQuery(sQuery);

	hSQL.Execute(hTrans, Trans_CreateTables_Success, Trans_CreateTables_Error, 0, DBPrio_High);
}

public void Trans_CreateTables_Error(Database2 db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	if (0 <= failIndex < sizeof(gS_TableNames))
	{
		LogError("Timer (create %s) error. Reason: %s", gS_TableNames[failIndex], error);
	}
	else
	{
		LogError("Timer (create tables) error. failIndex=%d. numQueries=%d. Reason: %s", failIndex, numQueries, error);
	}
}

public void Trans_RankingsSetupSuccess(Database2 db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	// migrations or Shavit__RunDatabaseLoadedForward
	if (gB_MySQL)
	{
		// migrations
	}
	else
	{
		Shavit__RunDatabaseLoadedForward();
	}
}
