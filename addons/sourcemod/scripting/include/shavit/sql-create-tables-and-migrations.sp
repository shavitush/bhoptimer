/*
 * shavit's Timer - SQL table creation and migrations
 * by: shavit, rtldg, jedso
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
 *
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

enum
{
	Migration_RemoveWorkshopMaptiers, // 0
	Migration_RemoveWorkshopMapzones,
	Migration_RemoveWorkshopPlayertimes,
	Migration_LastLoginIndex,
	Migration_RemoveCountry,
	Migration_ConvertIPAddresses, // 5
	Migration_ConvertSteamIDsUsers,
	Migration_ConvertSteamIDsPlayertimes,
	Migration_ConvertSteamIDsChat,
	Migration_PlayertimesDateToInt,
	Migration_AddZonesFlagsAndData, // 10
	Migration_AddPlayertimesCompletions,
	Migration_AddCustomChatAccess,
	Migration_AddPlayertimesExactTimeInt,
	Migration_FixOldCompletionCounts, // old completions accidentally started at 2
	Migration_AddPrebuiltToMapZonesTable, // 15
	Migration_AddPlaytime,
	// sorry, this is kind of dumb but it's better than trying to manage which ones have
	// finished and which tables exist etc etc in a transaction or a completion counter...
	Migration_Lowercase_maptiers,
	Migration_Lowercase_mapzones,
	Migration_Lowercase_playertimes,
	Migration_Lowercase_stagetimeswr, // 20
	Migration_Lowercase_startpositions,
	Migration_AddPlayertimesPointsCalcedFrom, // points calculated from wr float added to playertimes
	Migration_RemovePlayertimesPointsCalcedFrom, // lol
	Migration_NormalizeMapzonePoints,
	Migration_AddMapzonesForm, // 25
	Migration_AddMapzonesTarget,
	Migration_DeprecateExactTimeInt,
	Migration_AddPlayertimesAuthFK,
	Migration_FixSQLiteMapzonesROWID,
	Migration_AddUsersFirstLogin, // 30
	Migration_MoreFirstLoginStuff,
	MIGRATIONS_END
};

char gS_MigrationNames[][] = {
	"RemoveWorkshopMaptiers",
	"RemoveWorkshopMapzones",
	"RemoveWorkshopPlayertimes",
	"LastLoginIndex",
	"RemoveCountry",
	"ConvertIPAddresses",
	"ConvertSteamIDsUsers",
	"ConvertSteamIDsPlayertimes",
	"ConvertSteamIDsChat",
	"PlayertimesDateToInt",
	"AddZonesFlagsAndData",
	"AddPlayertimesCompletions",
	"AddCustomChatAccess",
	"AddPlayertimesExactTimeInt",
	"FixOldCompletionCounts",
	"AddPrebuiltToMapZonesTable",
	"AddPlaytime",
	"Lowercase_maptiers",
	"Lowercase_mapzones",
	"Lowercase_playertimes",
	"Lowercase_stagetimeswr",
	"Lowercase_startpositions",
	"AddPlayertimesPointsCalcedFrom",
	"RemovePlayertimesPointsCalcedFrom",
	"NormalizeMapzonePoints",
	"AddMapzonesForm",
	"AddMapzonesTarget",
	"DeprecateExactTimeInt",
	"AddPlayertimesAuthFK",
	"FixSQLiteMapzonesROWID",
	"AddUsersFirstLogin",
	"MoreFirstLoginStuff",
};

static Database gH_SQL;
static int gI_Driver;
static char gS_SQLPrefix[32];

bool gB_MigrationsApplied[255];
char SQLitePTQuery[1024]; // used in Migration_AddPlayertimesAuthFK if db created <= v3.3.2
char SQLiteMapzonesQuery[1024]; // used in Migration_FixSQLiteMapzonesROWID if db created <= v3.3.2

public void RunOnDatabaseLoadedForward()
{
	static GlobalForward hOnDatabasedLoaded;

	if (hOnDatabasedLoaded == null)
	{
		hOnDatabasedLoaded = new GlobalForward("Shavit_OnDatabaseLoaded", ET_Ignore);
	}

	Call_StartForward(hOnDatabasedLoaded);
	Call_Finish(hOnDatabasedLoaded);
}

public void SQL_CreateTables(Database hSQL, const char[] prefix, int driver)
{
	gH_SQL = hSQL;
	gI_Driver = driver;
	strcopy(gS_SQLPrefix, sizeof(gS_SQLPrefix), prefix);

	Transaction trans = new Transaction();

	char sQuery[2048];
	char sOptionalINNODB[16];

	if (driver == Driver_mysql)
	{
		sOptionalINNODB = "ENGINE=INNODB";
	}

	//
	//// shavit-core
	//

	if (driver == Driver_mysql)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%susers` (`auth` INT NOT NULL, `name` VARCHAR(32) COLLATE 'utf8mb4_general_ci', `ip` INT, `lastlogin` INT NOT NULL DEFAULT -1, `firstlogin` INT NOT NULL DEFAULT -1, `points` FLOAT NOT NULL DEFAULT 0, `playtime` FLOAT NOT NULL DEFAULT 0, PRIMARY KEY (`auth`), INDEX `points` (`points`), INDEX `lastlogin` (`lastlogin`)) ENGINE=INNODB;",
			gS_SQLPrefix);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%susers` (`auth` INT NOT NULL PRIMARY KEY, `name` VARCHAR(32), `ip` INT, `lastlogin` INTEGER NOT NULL DEFAULT -1, `firstlogin` INTEGER NOT NULL DEFAULT -1, `points` FLOAT NOT NULL DEFAULT 0, `playtime` FLOAT NOT NULL DEFAULT 0);",
			gS_SQLPrefix);
	}

	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%smigrations` (`code` TINYINT NOT NULL, PRIMARY KEY (`code`));",
		gS_SQLPrefix);
	AddQueryLog(trans, sQuery);

	//
	//// shavit-chat
	//

	if (driver == Driver_mysql)
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

	AddQueryLog(trans, sQuery);

	//
	//// shavit-rankings
	//

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%smaptiers` (`map` VARCHAR(255) NOT NULL, `tier` INT NOT NULL DEFAULT 1, PRIMARY KEY (`map`)) %s;",
		gS_SQLPrefix, sOptionalINNODB);
	AddQueryLog(trans, sQuery);

	//
	//// shavit-stats
	//

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%sstyleplaytime` (`auth` INT NOT NULL, `style` TINYINT NOT NULL, `playtime` FLOAT NOT NULL, PRIMARY KEY (`auth`, `style`));",
		gS_SQLPrefix);
	AddQueryLog(trans, sQuery);

	//
	//// shavit-wr
	//

	if (driver == Driver_mysql)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%splayertimes` (`id` INT NOT NULL AUTO_INCREMENT, `style` TINYINT NOT NULL DEFAULT 0, `track` TINYINT NOT NULL DEFAULT 0, `time` FLOAT NOT NULL, `auth` INT NOT NULL, `map` VARCHAR(255) NOT NULL, `points` FLOAT NOT NULL DEFAULT 0, `jumps` INT, `date` INT, `strafes` INT, `sync` FLOAT, `perfs` FLOAT DEFAULT 0, `completions` SMALLINT DEFAULT 1, PRIMARY KEY (`id`), INDEX `map` (`map`, `style`, `track`, `time`), INDEX `auth` (`auth`, `date`, `points`), INDEX `time` (`time`), INDEX `map2` (`map`), CONSTRAINT `%spt_auth` FOREIGN KEY (`auth`) REFERENCES `%susers` (`auth`) ON UPDATE RESTRICT ON DELETE RESTRICT) ENGINE=INNODB;",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix);
	}
	else
	{
		// id  style  track  time  auth  map  points  exact_time_int
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%splayertimes` (`id` INTEGER PRIMARY KEY, `style` TINYINT NOT NULL DEFAULT 0, `track` TINYINT NOT NULL DEFAULT 0, `time` FLOAT NOT NULL, `auth` INT NOT NULL, `map` VARCHAR(255) NOT NULL, `points` FLOAT NOT NULL DEFAULT 0, `jumps` INT, `date` INT, `strafes` INT, `sync` FLOAT, `perfs` FLOAT DEFAULT 0, `completions` SMALLINT DEFAULT 1, CONSTRAINT `%spt_auth` FOREIGN KEY (`auth`) REFERENCES `%susers` (`auth`) ON UPDATE RESTRICT ON DELETE RESTRICT);",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix);
		strcopy(SQLitePTQuery, sizeof(SQLitePTQuery), sQuery);
	}

	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%sstagetimeswr` (`style` TINYINT NOT NULL, `track` TINYINT NOT NULL DEFAULT 0, `map` VARCHAR(255) NOT NULL, `stage` TINYINT NOT NULL, `auth` INT NOT NULL, `time` FLOAT NOT NULL, PRIMARY KEY (`style`, `track`, `map`, `stage`)) %s;",
		gS_SQLPrefix, sOptionalINNODB);
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%sstagetimespb` (`style` TINYINT NOT NULL, `track` TINYINT NOT NULL DEFAULT 0, `map` VARCHAR(255) NOT NULL, `stage` TINYINT NOT NULL, `auth` INT NOT NULL, `time` FLOAT NOT NULL, PRIMARY KEY (`style`, `track`, `auth`, `map`, `stage`)) %s;",
		gS_SQLPrefix, sOptionalINNODB);
	AddQueryLog(trans, sQuery);

	if (driver == Driver_sqlite)
	{
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrs;", gS_SQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrs_min;", gS_SQLPrefix);
		AddQueryLog(trans, sQuery);
	}

	FormatEx(sQuery, sizeof(sQuery),
		"%s %swrs_min AS SELECT MIN(time) time, map, track, style FROM %splayertimes GROUP BY map, track, style;",
		driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_SQLPrefix, gS_SQLPrefix);
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		"%s %swrs AS SELECT a.* FROM %splayertimes a JOIN %swrs_min b ON a.time = b.time AND a.map = b.map AND a.track = b.track AND a.style = b.style;",
		driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix);
	AddQueryLog(trans, sQuery);

	//
	//// shavit-wr
	//

	if (driver == Driver_mysql)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%smapzones` (`id` INT AUTO_INCREMENT, `map` VARCHAR(255) NOT NULL, `type` INT, `corner1_x` FLOAT, `corner1_y` FLOAT, `corner1_z` FLOAT, `corner2_x` FLOAT, `corner2_y` FLOAT, `corner2_z` FLOAT, `destination_x` FLOAT NOT NULL DEFAULT 0, `destination_y` FLOAT NOT NULL DEFAULT 0, `destination_z` FLOAT NOT NULL DEFAULT 0, `track` INT NOT NULL DEFAULT 0, `flags` INT NOT NULL DEFAULT 0, `data` INT NOT NULL DEFAULT 0, `form` TINYINT, `target` VARCHAR(63), PRIMARY KEY (`id`)) %s;",
			gS_SQLPrefix, sOptionalINNODB);
		AddQueryLog(trans, sQuery);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `%smapzones` (`id` INTEGER PRIMARY KEY, `map` VARCHAR(255) NOT NULL, `type` INT, `corner1_x` FLOAT, `corner1_y` FLOAT, `corner1_z` FLOAT, `corner2_x` FLOAT, `corner2_y` FLOAT, `corner2_z` FLOAT, `destination_x` FLOAT NOT NULL DEFAULT 0, `destination_y` FLOAT NOT NULL DEFAULT 0, `destination_z` FLOAT NOT NULL DEFAULT 0, `track` INT NOT NULL DEFAULT 0, `flags` INT NOT NULL DEFAULT 0, `data` INT NOT NULL DEFAULT 0, `form` TINYINT, `target` VARCHAR(63));",
			gS_SQLPrefix);
		AddQueryLog(trans, sQuery);
		strcopy(SQLiteMapzonesQuery, sizeof(SQLiteMapzonesQuery), sQuery);
	}

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE TABLE IF NOT EXISTS `%sstartpositions` (`auth` INTEGER NOT NULL, `track` TINYINT NOT NULL, `map` VARCHAR(255) NOT NULL, `pos_x` FLOAT, `pos_y` FLOAT, `pos_z` FLOAT, `ang_x` FLOAT, `ang_y` FLOAT, `ang_z` FLOAT, `angles_only` BOOL, PRIMARY KEY (`auth`, `track`, `map`)) %s;",
		gS_SQLPrefix, sOptionalINNODB);
	AddQueryLog(trans, sQuery);

	hSQL.Execute(trans, Trans_CreateTables_Success, Trans_CreateTables_Error, 0, DBPrio_High);
}

public void Trans_CreateTables_Error(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	static char tablenames[][32] = {
		"users",
		"migrations",
		"chat",
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

	if (0 <= failIndex < sizeof(tablenames))
	{
		LogError("Timer failed to create sql table %s. Reason: %s", tablenames[failIndex], error);
	}
	else
	{
		LogError("Timer failed to create sql tables. failIndex=%d. numQueries=%d. Reason: %s", failIndex, numQueries, error);
	}
}

public void Trans_CreateTables_Success(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	char sQuery[128];
	FormatEx(sQuery, 128, "SELECT code FROM %smigrations;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_SelectMigrations_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_SelectMigrations_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError("Timer error! Migrations selection failed. Reason: %s", error);

		return;
	}

	// this is ugly, i know. but it works and is more elegant than previous solutions so.. let it be =)
	bool bMigrationApplied[255] = { false, ... };

	while (results.FetchRow())
	{
		bMigrationApplied[results.FetchInt(0)] = true;
	}

	gB_MigrationsApplied = bMigrationApplied;
	DoNextMigration();
}

void DoNextMigration()
{
	for (int i = 0; i < MIGRATIONS_END; i++)
	{
		if (!gB_MigrationsApplied[i])
		{
			gB_MigrationsApplied[i] = true;
			PrintToServer("--- Applying database migration %d %s ---", i, gS_MigrationNames[i]);
			PrintToChatAll("--- Applying database migration %d %s ---", i, gS_MigrationNames[i]);
			ApplyMigration(i);
			return;
		}
	}

	RunOnDatabaseLoadedForward();
}

void ApplyMigration(int migration)
{
	switch (migration)
	{
		case Migration_RemoveWorkshopMaptiers, Migration_RemoveWorkshopMapzones, Migration_RemoveWorkshopPlayertimes: ApplyMigration_RemoveWorkshopPath(migration);
		case Migration_LastLoginIndex: ApplyMigration_LastLoginIndex();
		case Migration_RemoveCountry: ApplyMigration_RemoveCountry();
		case Migration_ConvertIPAddresses: ApplyMigration_ConvertIPAddresses();
		case Migration_ConvertSteamIDsUsers: ApplyMigration_ConvertSteamIDs();
		case Migration_ConvertSteamIDsPlayertimes, Migration_ConvertSteamIDsChat: return; // this is confusing, but the above case handles all of them
		case Migration_PlayertimesDateToInt: ApplyMigration_PlayertimesDateToInt();
		case Migration_AddZonesFlagsAndData: ApplyMigration_AddZonesFlagsAndData();
		case Migration_AddPlayertimesCompletions: ApplyMigration_AddPlayertimesCompletions();
		case Migration_AddCustomChatAccess: ApplyMigration_AddCustomChatAccess();
		case Migration_AddPlayertimesExactTimeInt: ApplyMigration_AddPlayertimesExactTimeInt();
		case Migration_FixOldCompletionCounts: ApplyMigration_FixOldCompletionCounts();
		case Migration_AddPrebuiltToMapZonesTable: ApplyMigration_AddPrebuiltToMapZonesTable();
		case Migration_AddPlaytime: ApplyMigration_AddPlaytime();
		case Migration_Lowercase_maptiers: ApplyMigration_LowercaseMaps("maptiers", migration);
		case Migration_Lowercase_mapzones: ApplyMigration_LowercaseMaps("mapzones", migration);
		case Migration_Lowercase_playertimes: ApplyMigration_LowercaseMaps("playertimes", migration);
		case Migration_Lowercase_stagetimeswr: ApplyMigration_LowercaseMaps("stagetimewrs", migration);
		case Migration_Lowercase_startpositions: ApplyMigration_LowercaseMaps("startpositions", migration);
		case Migration_AddPlayertimesPointsCalcedFrom: ApplyMigration_AddPlayertimesPointsCalcedFrom();
		case Migration_RemovePlayertimesPointsCalcedFrom: ApplyMigration_RemovePlayertimesPointsCalcedFrom();
		case Migration_NormalizeMapzonePoints: ApplyMigration_NormalizeMapzonePoints();
		case Migration_AddMapzonesForm: ApplyMigration_AddMapzonesForm();
		case Migration_AddMapzonesTarget: ApplyMigration_AddMapzonesTarget();
		case Migration_DeprecateExactTimeInt: ApplyMigration_DeprecateExactTimeInt();
		case Migration_AddPlayertimesAuthFK: ApplyMigration_AddPlayertimesAuthFK();
		case Migration_FixSQLiteMapzonesROWID: ApplyMigration_FixSQLiteMapzonesROWID();
		case Migration_AddUsersFirstLogin: ApplyMigration_AddUsersFirstLogin();
		case Migration_MoreFirstLoginStuff: ApplyMigration_MoreFirstLoginStuff();
	}
}

void ApplyMigration_LastLoginIndex()
{
	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%susers` ADD INDEX `lastlogin` (`lastlogin`);", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_LastLoginIndex, DBPrio_High);
}

void ApplyMigration_RemoveCountry()
{
	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%susers` DROP COLUMN `country`;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_RemoveCountry, DBPrio_High);
}

void ApplyMigration_PlayertimesDateToInt()
{
	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%splayertimes` CHANGE COLUMN `date` `date` INT;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_PlayertimesDateToInt, DBPrio_High);
}

void ApplyMigration_AddZonesFlagsAndData()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%smapzones` ADD COLUMN `flags` INT NULL AFTER `track`, ADD COLUMN `data` INT NULL AFTER `flags`;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddZonesFlagsAndData, DBPrio_High);
}

void ApplyMigration_AddPlayertimesCompletions()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%splayertimes` ADD COLUMN `completions` SMALLINT DEFAULT 1 AFTER `perfs`;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddPlayertimesCompletions, DBPrio_High);
}

void ApplyMigration_AddCustomChatAccess()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%schat` ADD COLUMN `ccaccess` INT NOT NULL DEFAULT 0 %s;", gS_SQLPrefix, (gI_Driver == Driver_mysql) ? "AFTER `ccmessage`" : "");
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddCustomChatAccess, DBPrio_High);
}

void ApplyMigration_AddPlayertimesExactTimeInt()
{
#if 0
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%splayertimes` ADD COLUMN `exact_time_int` INT NOT NULL DEFAULT 0 %s;", gS_SQLPrefix, (gI_Driver == Driver_mysql) ? "AFTER `completions`" : "");
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddPlayertimesExactTimeInt, DBPrio_High);
#else
	SQL_TableMigrationSingleQuery_Callback(null, null, "", Migration_AddPlayertimesExactTimeInt);
#endif
}

void ApplyMigration_FixOldCompletionCounts()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "UPDATE `%splayertimes` SET completions = completions - 1 WHERE completions > 1;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_FixOldCompletionCounts, DBPrio_High);
}

void ApplyMigration_AddPrebuiltToMapZonesTable()
{
#if 0
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%smapzones` ADD COLUMN `prebuilt` BOOL;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddPrebuiltToMapZonesTable, DBPrio_High);
#else
	SQL_TableMigrationSingleQuery_Callback(null, null, "", Migration_AddPrebuiltToMapZonesTable);
#endif
}

// double up on this migration because some people may have used shavit-playtime which uses INT but I want FLOAT
void ApplyMigration_AddPlaytime()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%susers` MODIFY COLUMN `playtime` FLOAT NOT NULL DEFAULT 0;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_Migration_AddPlaytime2222222_Callback, sQuery, Migration_AddPlaytime, DBPrio_High);
}

public void SQL_Migration_AddPlaytime2222222_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%susers` ADD COLUMN `playtime` FLOAT NOT NULL DEFAULT 0 %s;", gS_SQLPrefix, (gI_Driver == Driver_mysql) ? "AFTER `points`" : "");
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddPlaytime, DBPrio_High);
}

void ApplyMigration_LowercaseMaps(const char[] table, int migration)
{
	char sQuery[192];
	FormatEx(sQuery, 192, "UPDATE `%s%s` SET map = LOWER(map);", gS_SQLPrefix, table);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, migration, DBPrio_High);
}

void ApplyMigration_AddPlayertimesPointsCalcedFrom()
{
#if 0
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%splayertimes` ADD COLUMN `points_calced_from` FLOAT NOT NULL DEFAULT 0 %s;", gS_SQLPrefix, (gI_Driver == Driver_mysql) ? "AFTER `points`" : "");
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddPlayertimesPointsCalcedFrom, DBPrio_High);
#else
	SQL_TableMigrationSingleQuery_Callback(null, null, "", Migration_AddPlayertimesPointsCalcedFrom);
#endif
}

void ApplyMigration_RemovePlayertimesPointsCalcedFrom()
{
	char sQuery[192];
	FormatEx(sQuery, 192, "ALTER TABLE `%splayertimes` DROP COLUMN `points_calced_from`;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_RemovePlayertimesPointsCalcedFrom, DBPrio_High);
}

void ApplyMigration_NormalizeMapzonePoints() // TODO: test with sqlite lol
{
	char sQuery[666], greatest[16], least[16], id[16];
	greatest = (gI_Driver != Driver_sqlite) ? "GREATEST" : "MAX";
	least = (gI_Driver != Driver_sqlite) ? "LEAST" : "MIN";
	id = (gI_Driver != Driver_sqlite) ? "id" : "rowid";

	FormatEx(sQuery, sizeof(sQuery),
		"UPDATE `%smapzones` A, `%smapzones` B SET \
		A.corner1_x=%s(B.corner1_x, B.corner2_x), \
		A.corner1_y=%s(B.corner1_y, B.corner2_y), \
		A.corner1_z=%s(B.corner1_z, B.corner2_z), \
		A.corner2_x=%s(B.corner1_x, B.corner2_x), \
		A.corner2_y=%s(B.corner1_y, B.corner2_y), \
		A.corner2_z=%s(B.corner1_z, B.corner2_z)  \
		WHERE A.%s = B.%s;",
		gS_SQLPrefix, gS_SQLPrefix,
		least, least, least,
		greatest, greatest, greatest,
		id, id
	);

	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_NormalizeMapzonePoints, DBPrio_High);
}

void ApplyMigration_AddMapzonesForm()
{
	char sQuery[192];
	FormatEx(sQuery, sizeof(sQuery), "ALTER TABLE `%smapzones` ADD COLUMN `form` TINYINT;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddMapzonesForm, DBPrio_High);
}

void ApplyMigration_AddMapzonesTarget()
{
	char sQuery[192];
	FormatEx(sQuery, sizeof(sQuery), "ALTER TABLE `%smapzones` ADD COLUMN `target` VARCHAR(63);", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddMapzonesTarget, DBPrio_High);
}

void ApplyMigration_DeprecateExactTimeInt()
{
	char query[256];
	FormatEx(query, sizeof(query), "SELECT id, time, exact_time_int FROM %splayertimes WHERE exact_time_int != 0;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_Migration_DeprecateExactTimeInt_Query, query);
}

public void SQL_Migration_DeprecateExactTimeInt_Query(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null || error[0] != '\0')
	{
		LogError("DeprecateExactTimeInt query failed... %s (%s). Finishing this migration though because things are probably fine...", results == null ? "results=null" : "", error);
		InsertMigration(Migration_DeprecateExactTimeInt);
		return;
	}

	if (results.RowCount == 0)
	{
		// Nothing to queue, yay!
		InsertMigration(Migration_DeprecateExactTimeInt);
		return;
	}

	ArrayStack stack = new ArrayStack(3);

	while (results.FetchRow())
	{
		int things[3];
		things[0] = results.FetchInt(0);
		things[1] = view_as<int>(results.FetchFloat(1));
		things[2] = results.FetchInt(2);
		stack.PushArray(things);
	}

	PrintToServer("--- DeprecateExactTimeInt to edit %d rows ---", results.RowCount);
	PrintToChatAll("--- DeprecateExactTimeInt to edit %d rows ---", results.RowCount);

	SQL_Migration_DeprecateExactTimeInt_Main(stack);
}

void SQL_Migration_DeprecateExactTimeInt_Main(ArrayStack stack)
{
	Transaction trans = new Transaction();
	int queries = 0;

	while (!stack.Empty)
	{
		int things[3];
		stack.PopArray(things);

		int id = things[0];
		float time = view_as<float>(things[1]);
		float exact_time = view_as<float>(things[2]);
		// https://github.com/shavitush/bhoptimer/issues/1218
		// An issue popped up where we were no longer using/setting exact_time_int before this migration was added
		// so it was possible for someone to beat their time and then this migration would reset it to the old exact_time_int time which was a big fat oopsie.
		// Now we min() it here! (which we couldn't do nicely in SQL).
		float min_time = time < exact_time ? time : exact_time;

		char query[512];
		FormatEx(query, sizeof(query),
			"UPDATE %splayertimes SET time = %.9f WHERE id = %d;",
			gS_SQLPrefix, min_time, id);
		AddQueryLog(trans, query);

		// We do these queries/transactions in batches because AFAIR there is some SQL driver crash issue that likes to pop up with tons of queries... epic swag skibidi sigma rizz. Have you noticed that baby gronk (which was mid) has died out?
		if (++queries > 200)
			break;
	}

	PrintToServer("--- DeprecateExactTimeInt starting transaction with %d rows (%f) ---", queries, GetEngineTime());
	PrintToChatAll("--- DeprecateExactTimeInt starting transaction with %d rows (%f) ---", queries, GetEngineTime());

	if (stack.Empty)
		delete stack;

	gH_SQL.Execute(trans, Trans_DeprecateExactTimeIntSuccess, Trans_DeprecateExactTimeIntFailed, stack);
}

public void Trans_DeprecateExactTimeIntSuccess(Database db, ArrayStack stack, int numQueries, DBResultSet[] results, any[] queryData)
{
	PrintToServer("--- DeprecateExactTimeInt did transaction with %d rows (%f) ---", numQueries, GetEngineTime());
	PrintToChatAll("--- DeprecateExactTimeInt did transaction with %d rows (%f) ---", numQueries, GetEngineTime());

	if (!stack)
	{
		InsertMigration(Migration_DeprecateExactTimeInt);
		return;
	}

	SQL_Migration_DeprecateExactTimeInt_Main(stack);
}

public void Trans_DeprecateExactTimeIntFailed(Database db, ArrayStack stack, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	delete stack;
	LogError("Timer (core) error! ExactTimeInt migration failed. %d %d Reason: %s", numQueries, failIndex, error);
}

void ApplyMigration_FixSQLiteMapzonesROWID()
{
	if (gI_Driver != Driver_sqlite)
	{
		InsertMigration(Migration_FixSQLiteMapzonesROWID);
		return;
	}

	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT sql FROM sqlite_master WHERE name = '%smapzones';", gS_SQLPrefix);

	QueryLog(gH_SQL, SQL_FixSQLiteMapzonesROWID_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_FixSQLiteMapzonesROWID_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError("Timer error! SQLiteMapzonesROWID migration failed. Reason: %s", error);
		return;
	}

	Transaction trans = new Transaction();
	char sQuery[512];
	char sMapzonesMasterSQL[1024];

	results.FetchRow();
	results.FetchString(0, sMapzonesMasterSQL, sizeof(sMapzonesMasterSQL));

	if (StrContains(sMapzonesMasterSQL, "`id` INT AUTO_INCREMENT") != -1)
	{
		FormatEx(sQuery, sizeof(sQuery), "CREATE TEMPORARY TABLE temp_mapzones AS SELECT * FROM `%smapzones`;", gS_SQLPrefix);
		AddQueryLog(trans, sQuery);

		FormatEx(sQuery, sizeof(sQuery), "DROP TABLE `%smapzones`;", gS_SQLPrefix);
		AddQueryLog(trans, sQuery);

		// Re-use mapzones table creation query
		AddQueryLog(trans, SQLiteMapzonesQuery);

		// Can't do SELECT * FROM temp_mapzones because DBs created < v3.3.0 have an extra `prebuilt` column
		FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `%smapzones` SELECT `id`, `map`, `type`, `corner1_x`, `corner1_y`, `corner1_z`, `corner2_x`, `corner2_y`, `corner2_z`, `destination_x`, `destination_y`, `destination_z`, `track`, `flags`, `data`, `form`, `target` FROM temp_mapzones;", gS_SQLPrefix);
		AddQueryLog(trans, sQuery);

		FormatEx(sQuery, sizeof(sQuery), "DROP TABLE `temp_mapzones`;");
		AddQueryLog(trans, sQuery);

		gH_SQL.Execute(trans, Trans_FixSQLiteMapzonesROWID_Success, Trans_FixSQLiteMapzonesROWID_Error, 0, DBPrio_High);
	}
	else
	{
		InsertMigration(Migration_FixSQLiteMapzonesROWID);
	}
}

public void Trans_FixSQLiteMapzonesROWID_Success(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	InsertMigration(Migration_FixSQLiteMapzonesROWID);
}

public void Trans_FixSQLiteMapzonesROWID_Error(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer error! SQLiteMapzonesROWID migration transaction failed. Reason: %s", error);
}

void ApplyMigration_AddUsersFirstLogin()
{
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "ALTER TABLE %susers ADD `firstlogin` INT NOT NULL DEFAULT -1 %s;", gS_SQLPrefix, (gI_Driver == Driver_mysql) ? "AFTER `lastlogin`" : "");
	QueryLog(gH_SQL, ApplyMigration_AddUsersFirstLogin2222222_Callback, sQuery, Migration_AddUsersFirstLogin, DBPrio_High);
}

public void ApplyMigration_AddUsersFirstLogin2222222_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %susers SET firstlogin = lastlogin WHERE lastlogin > 1188518400;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_AddUsersFirstLogin, DBPrio_High);
}

public void ApplyMigration_MoreFirstLoginStuff()
{
	char query[512];
	Transaction trans = new Transaction();

	if (gI_Driver == Driver_mysql)
	{
		FormatEx(query, sizeof(query),
			"UPDATE %susers JOIN ( \
				SELECT auth, MIN(FLOOR(`date` - `time`)) as min_date \
				FROM %splayertimes \
				WHERE `date` > 1188518400 \
				GROUP BY auth \
			) as pt ON %susers.auth = pt.auth \
			SET firstlogin = pt.min_date \
			WHERE firstlogin <= 0;",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix
		);
		AddQueryLog(trans, query);
		FormatEx(query, sizeof(query),
			"UPDATE %susers JOIN ( \
				SELECT auth, MIN(FLOOR(`date` - `time`)) as min_date \
				FROM %splayertimes \
				WHERE `date` > 1188518400 \
				GROUP BY auth \
			) as pt ON %susers.auth = pt.auth \
			SET firstlogin = LEAST(firstlogin, pt.min_date) \
			WHERE firstlogin > 0;",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix
		);
		AddQueryLog(trans, query);
	}
	else // sqlite & postgresql use the same syntax here
	{
		FormatEx(query, sizeof(query),
			"UPDATE %susers SET firstlogin = pt.min_date \
			FROM ( \
				SELECT auth, MIN(FLOOR(date - time)) as min_date \
				FROM %splayertimes \
				WHERE date > 1188518400 \
				GROUP BY auth \
			) as pt \
			WHERE %susers.auth = pt.auth AND firstlogin <= 0;",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix
		);
		AddQueryLog(trans, query);
		FormatEx(query, sizeof(query),
			"UPDATE %susers SET firstlogin = MIN(firstlogin, pt.min_date) \
			FROM ( \
				SELECT auth, MIN(FLOOR(date - time)) as min_date \
				FROM %splayertimes \
				WHERE date > 1188518400 \
				GROUP BY auth \
			) as pt \
			WHERE %susers.auth = pt.auth AND firstlogin > 0;",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix
		);
		AddQueryLog(trans, query);
	}
	gH_SQL.Execute(trans, Trans_MigrationSimple, TransMigrationSimple_Error, Migration_MoreFirstLoginStuff);
}

public void SQL_TableMigrationSingleQuery_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	InsertMigration(data);

	// i hate hardcoding REEEEEEEE
	if (data == Migration_ConvertSteamIDsChat)
	{
		char sQuery[256];
		// deleting rows that cause data integrity issues
		FormatEx(sQuery, 256,
			"DELETE t1 FROM %splayertimes t1 LEFT JOIN %susers t2 ON t1.auth = t2.auth WHERE t2.auth IS NULL;",
			gS_SQLPrefix, gS_SQLPrefix);
		QueryLog(gH_SQL, SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);

#if 0
		FormatEx(sQuery, 256,
			"ALTER TABLE `%splayertimes` ADD CONSTRAINT `%spt_auth` FOREIGN KEY (`auth`) REFERENCES `%susers` (`auth`) ON UPDATE CASCADE ON DELETE CASCADE;",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix);
		QueryLog(gH_SQL, SQL_TableMigrationIndexing_Callback, sQuery);
#endif

		FormatEx(sQuery, 256,
			"DELETE t1 FROM %schat t1 LEFT JOIN %susers t2 ON t1.auth = t2.auth WHERE t2.auth IS NULL;",
			gS_SQLPrefix, gS_SQLPrefix);
		QueryLog(gH_SQL, SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);

#if 0
		FormatEx(sQuery, 256,
			"ALTER TABLE `%schat` ADD CONSTRAINT `%sch_auth` FOREIGN KEY (`auth`) REFERENCES `%susers` (`auth`) ON UPDATE CASCADE ON DELETE CASCADE;",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix);
		QueryLog(gH_SQL, SQL_TableMigrationIndexing_Callback, sQuery);
#endif
	}
}

void ApplyMigration_AddPlayertimesAuthFK()
{
	// More details about this migration here https://github.com/shavitush/bhoptimer/issues/1175
	char sQuery[512];

	if (gI_Driver == Driver_mysql)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"SELECT COUNT(*) \
			FROM information_schema.REFERENTIAL_CONSTRAINTS \
			WHERE CONSTRAINT_SCHEMA = DATABASE() \
				AND REFERENCED_TABLE_NAME = '%susers' \
				AND CONSTRAINT_NAME = '%spt_auth';",
			gS_SQLPrefix, gS_SQLPrefix
		);
	}
	else if (gI_Driver == Driver_sqlite)
	{
		FormatEx(sQuery, sizeof(sQuery), "SELECT sql FROM sqlite_master WHERE name = '%splayertimes';", gS_SQLPrefix);
	}
	else // PostgreSQL unaffected
	{
		InsertMigration(Migration_AddPlayertimesAuthFK);
		return;
	}

	QueryLog(gH_SQL, SQL_TableMigrationPlayertimesAuthFK_Callback, sQuery);
}

public void SQL_TableMigrationPlayertimesAuthFK_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if (results == null)
	{
		LogError("Timer error! Playertimes auth FK migration selection failed. Reason: %s", error);
		return;
	}

	Transaction trans = new Transaction();
	char sQuery[512];

	results.FetchRow();

	if (gI_Driver == Driver_mysql)
	{
		if (results.FetchInt(0)) // pt_auth CONSTRAINT exists
		{
			// Remove in case it has CASCADE referential actions (<= v3.0.8)
			FormatEx(sQuery, sizeof(sQuery), "ALTER TABLE `%splayertimes` DROP FOREIGN KEY `%spt_auth`;", gS_SQLPrefix, gS_SQLPrefix);
			AddQueryLog(trans, sQuery);
		}

		// add missing users to users table
		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO `%susers` (auth) SELECT p1.auth FROM `%splayertimes` p1 LEFT JOIN `%susers` u1 ON u1.auth = p1.auth WHERE u1.auth IS NULL;",
			gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix
		);
		AddQueryLog(trans, sQuery);

		FormatEx(sQuery, sizeof(sQuery), "ALTER TABLE `%splayertimes` ADD CONSTRAINT `%spt_auth` FOREIGN KEY (`auth`) REFERENCES `%susers` (`auth`) ON UPDATE RESTRICT ON DELETE RESTRICT;", gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix);
		AddQueryLog(trans, sQuery);
	}
	else
	{
		char sPlayertimesMasterSQL[1024];
		results.FetchString(0, sPlayertimesMasterSQL, sizeof(sPlayertimesMasterSQL));

		char sConstraintTest[64];
		FormatEx(sConstraintTest, sizeof(sConstraintTest), "CONSTRAINT `%spt_auth`", gS_SQLPrefix);

		if (StrContains(sPlayertimesMasterSQL, sConstraintTest) == -1 // >= v3.1.0
			|| StrContains(sPlayertimesMasterSQL, "(`auth`) ON UPDATE CASCADE ON DELETE CASCADE") != -1) // <= v3.0.8
		{
			// add missing users to users table
			FormatEx(sQuery, sizeof(sQuery),
				"INSERT INTO `%susers` (auth) SELECT p1.auth FROM `%splayertimes` p1 LEFT JOIN `%susers` u1 ON u1.auth = p1.auth WHERE u1.auth IS NULL;",
				gS_SQLPrefix, gS_SQLPrefix, gS_SQLPrefix
			);
			AddQueryLog(trans, sQuery);

			FormatEx(sQuery, sizeof(sQuery), "CREATE TEMPORARY TABLE temp_pt AS SELECT * FROM `%splayertimes`;", gS_SQLPrefix);
			AddQueryLog(trans, sQuery);

			FormatEx(sQuery, sizeof(sQuery), "DROP TABLE `%splayertimes`;", gS_SQLPrefix);
			AddQueryLog(trans, sQuery);

			// Re-use playertimes table creation query
			AddQueryLog(trans, SQLitePTQuery);

			FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `%splayertimes` (id, style, track, time, auth, map, points, jumps, date, strafes, sync, perfs, completions) SELECT id, style, track, time, auth, map, points, jumps, date, strafes, sync, perfs, completions FROM temp_pt;", gS_SQLPrefix);
			AddQueryLog(trans, sQuery);

			FormatEx(sQuery, sizeof(sQuery), "DROP TABLE `temp_pt`;");
			AddQueryLog(trans, sQuery);
		}
		else // db was created > v3.3.2
		{
			InsertMigration(Migration_AddPlayertimesAuthFK);
			return;
		}
	}

	gH_SQL.Execute(trans, Trans_AddPlayertimesAuthFK_Success, Trans_AddPlayertimesAuthFK_Error, 0, DBPrio_High);
}

public void Trans_AddPlayertimesAuthFK_Success(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	InsertMigration(Migration_AddPlayertimesAuthFK);
}

public void Trans_AddPlayertimesAuthFK_Error(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer error! Playertimes auth FK migration transaction failed. Reason: %s", error);
}

void ApplyMigration_ConvertIPAddresses(bool index = true)
{
	char sQuery[128];

	if (index)
	{
		FormatEx(sQuery, 128, "ALTER TABLE `%susers` ADD INDEX `ip` (`ip`);", gS_SQLPrefix);
		QueryLog(gH_SQL, SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);
	}

	FormatEx(sQuery, 128, "SELECT DISTINCT ip FROM %susers WHERE ip LIKE '%%.%%';", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationIPAddresses_Callback, sQuery);
}

public void SQL_TableMigrationIPAddresses_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if (results == null || results.RowCount == 0)
	{
		InsertMigration(Migration_ConvertIPAddresses);

		return;
	}

	Transaction trans = new Transaction();
	int iQueries = 0;

	while (results.FetchRow())
	{
		char sIPAddress[32];
		results.FetchString(0, sIPAddress, 32);

		char sQuery[256];
		FormatEx(sQuery, 256, "UPDATE %susers SET ip = %d WHERE ip = '%s';", gS_SQLPrefix, IPStringToAddress(sIPAddress), sIPAddress);

		AddQueryLog(trans, sQuery);

		if (++iQueries >= 10000)
		{
			break;
		}
	}

	gH_SQL.Execute(trans, Trans_IPAddressMigrationSuccess, Trans_IPAddressMigrationFailed, iQueries);
}

public void Trans_IPAddressMigrationSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	// too many queries, don't do all at once to avoid server crash due to too many queries in the transaction
	if (data >= 10000)
	{
		ApplyMigration_ConvertIPAddresses(false);

		return;
	}

	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%susers` DROP INDEX `ip`;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);

	FormatEx(sQuery, 128, "ALTER TABLE `%susers` CHANGE COLUMN `ip` `ip` INT;", gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, Migration_ConvertIPAddresses, DBPrio_High);
}

public void Trans_IPAddressMigrationFailed(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (core) error! IP address migration failed. Reason: %s", error);
}

void ApplyMigration_ConvertSteamIDs()
{
	char sTables[][] =
	{
		"users",
		"playertimes",
		"chat"
	};

	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%splayertimes` DROP CONSTRAINT `%spt_auth`;", gS_SQLPrefix, gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);

	FormatEx(sQuery, 128, "ALTER TABLE `%schat` DROP CONSTRAINT `%sch_auth`;", gS_SQLPrefix, gS_SQLPrefix);
	QueryLog(gH_SQL, SQL_TableMigrationIndexing_Callback, sQuery, 0, DBPrio_High);

	for (int i = 0; i < sizeof(sTables); i++)
	{
		DataPack hPack = new DataPack();
		hPack.WriteCell(Migration_ConvertSteamIDsUsers + i);
		hPack.WriteString(sTables[i]);

		FormatEx(sQuery, 128, "UPDATE %s%s SET auth = REPLACE(REPLACE(auth, \"[U:1:\", \"\"), \"]\", \"\") WHERE auth LIKE '[%%';", sTables[i], gS_SQLPrefix);
		QueryLog(gH_SQL, SQL_TableMigrationSteamIDs_Callback, sQuery, hPack, DBPrio_High);
	}
}

public void SQL_TableMigrationIndexing_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	// nothing
}

public void SQL_TableMigrationSteamIDs_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int iMigration = data.ReadCell();
	char sTable[16];
	data.ReadString(sTable, 16);
	delete data;

	char sQuery[128];
	FormatEx(sQuery, 128, "ALTER TABLE `%s%s` CHANGE COLUMN `auth` `auth` INT;", gS_SQLPrefix, sTable);
	QueryLog(gH_SQL, SQL_TableMigrationSingleQuery_Callback, sQuery, iMigration, DBPrio_High);
}

void ApplyMigration_RemoveWorkshopPath(int migration)
{
	char sTables[][] =
	{
		"maptiers",
		"mapzones",
		"playertimes"
	};

	DataPack hPack = new DataPack();
	hPack.WriteCell(migration);
	hPack.WriteString(sTables[migration]);

	char sQuery[192];
	FormatEx(sQuery, 192, "SELECT map FROM %s%s WHERE map LIKE 'workshop%%' GROUP BY map;", gS_SQLPrefix, sTables[migration]);
	QueryLog(gH_SQL, SQL_TableMigrationWorkshop_Callback, sQuery, hPack, DBPrio_High);
}

public void SQL_TableMigrationWorkshop_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int iMigration = data.ReadCell();
	char sTable[16];
	data.ReadString(sTable, 16);
	delete data;

	if (results == null || results.RowCount == 0)
	{
		// no error logging here because not everyone runs the rankings/wr modules
		InsertMigration(iMigration);

		return;
	}

	Transaction trans = new Transaction();

	while (results.FetchRow())
	{
		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(0, sMap, sizeof(sMap));

		char sDisplayMap[PLATFORM_MAX_PATH];
		GetMapDisplayName(sMap, sDisplayMap, sizeof(sDisplayMap));

		char sQuery[256];
		FormatEx(sQuery, 256, "UPDATE %s%s SET map = '%s' WHERE map = '%s';", gS_SQLPrefix, sTable, sDisplayMap, sMap);

		AddQueryLog(trans, sQuery);
	}

	gH_SQL.Execute(trans, Trans_MigrationSimple, INVALID_FUNCTION, iMigration);
}

public void Trans_MigrationSimple(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	InsertMigration(data);
}

public void TransMigrationSimple_Error(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer failed on migration %d. failIndex=%d, numQueries=%d, reason: '%s'", data, failIndex, numQueries, error);
}

void InsertMigration(int migration)
{
	char sQuery[128];
	FormatEx(sQuery, 128, "INSERT INTO %smigrations (code) VALUES (%d);", gS_SQLPrefix, migration);
	QueryLog(gH_SQL, SQL_MigrationApplied_Callback, sQuery, migration);
}

public void SQL_MigrationApplied_Callback(Database db, DBResultSet results, const char[] error, any migration)
{
	PrintToServer("--- FINISHED database migration %d %s ---", migration, gS_MigrationNames[migration]);
	PrintToChatAll("--- FINISHED database migration %d %s ---", migration, gS_MigrationNames[migration]);
	DoNextMigration();
}
