<?php
// ip address to the mysql server
define("DB_HOST", "localhost");

// mysql username
define("DB_USER", "root");

// mysql password
define("DB_PASSWORD", "");

// mysql database (schema) name
define("DB_SCHEMA", "shavit");

// amount of records that can be displayed
define("RECORD_LIMIT", "100");

// the page's title as seen in the homepage
define("HOMEPAGE_TITLE", "shavit's bhoptimer");

// title for the top left side of the screen
define("TOPLEFT_TITLE", "bhoptimer");

// mysql table prefix, leave empty unless changed in the server
define("MYSQL_PREFIX", "");

// header title
define("HEADER_TITLE", "Welcome!");

// setup multi styles here
$styles = array(
    "Forwards", // 0
    "Sideways", // 1
    "W-Only", // 2
    "Scroll", // 3
    "400 Velocity" // 4
);

define("DEFAULT_STYLE", 0); // 0 - forwards

// amount of records that can be displayed in 'latest records'
define("RECORD_LIMIT_LATEST", "10");
?>
