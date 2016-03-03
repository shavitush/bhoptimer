<?php
require("config.php");
require("functions.php");
require("steamid.php");

$connection = new mysqli(DB_HOST, DB_USER, DB_PASSWORD, DB_SCHEMA);
$connection->set_charset("utf8");

$map = isset($_GET["map"]);

function removeworkshop($mapname)
{
	if(strpos($mapname, "workshop/") !== false)
	{
		$pieces = explode("/", $mapname);

		return $pieces[2];
	}

	return $mapname;
}

$style = 0;

if(isset($_GET["style"]))
{
	$style = $_GET["style"];
}
?>

<html>
<head>
	<meta charset="UTF-8">

	<style>
	table, th, td
	{
		border: 1px solid black;
		text-align: left;
	}

	.name
	{
		color: darkcyan;
	}

	.time
	{
		color: red;
	}
	</style>

	<?php
	if(!$map)
	{
		echo("<title>" . HOMEPAGE_TITLE . "</title>");
	}

	else
	{
		echo("<title>[" . ($style == 0? "NM":"SW") . " Records] " . removeworkshop($_GET["map"]) . "</title>");
	} ?>
</head>

<body>
	<p><a href="timer.php">Home</a></p>

	<p><form method="GET" acton="#">
		<?php
		if(isset($_GET["map"]))
		{
			echo("<input name=\"map\" type=\"text\" value=" . $_GET["map"] . "></input>");
		}

		else
		{
			echo("<input name=\"map\" type=\"text\"></input>");
		}
		?>

		<select name="style">
			<option value="0">Forwards</option>
			<option value="1">Sideways</option>
		</select>

		<input type="submit" value="Show results"></input>
	</form></p>

	<?php
	if($map)
	{
		$stmt = FALSE;

		if($stmt = $connection->prepare("SELECT p.id, p.map, u.auth, u.name, p.time, p.jumps FROM playertimes p JOIN users u ON p.auth = u.auth WHERE map = ? AND style = ? ORDER BY time ASC LIMIT " . RECORD_LIMIT . ";"))
		{
			$stmt->bind_param("ss", $_GET["map"], $_GET["style"]);
			$stmt->execute();

			$stmt->store_result();

			$rows = $stmt->num_rows;

			$stmt->bind_result($id, $map, $auth, $name, $time, $jumps);

			echo "<p>Number of records: " . number_format($rows) . ".</p>";

			if($rows > 0)
			{
				$first = true;

				$rank = 1;

				while($row = $stmt->fetch())
				{
					if($first)
					{
						echo("<h1>[" . ($style == 0? "Forwards":"Sideways") . " Records] " . removeworkshop($_GET["map"]) . "</h1>");

						?>
						<table>
						<tr><th>Rank</th>
						<th>Record ID</th>
						<th>SteamID3</th>
						<th>Player</th>
						<th>Time</th>
						<th>Jumps</th></tr>

						<?php
					}
					?>

					<tr><td>#<?php echo($rank); ?></td>
					<td><?php echo($id); ?></td>
					<td><?php
					$steamid = SteamID::Parse($auth, SteamID::FORMAT_STEAMID3);
					echo("<a href=\"http://steamcommunity.com/profiles/" . $steamid->Format(SteamID::FORMAT_STEAMID64) . "/\">" . $auth . "</a>"); ?></td>
					<td class="name"><?php echo($name); ?></td>
					<td class="time">

					<?php
					echo(formattoseconds($time));
					?></td>
					<td><?php echo(number_format($jumps)); ?></td></tr>

					<?php

					$first = false;

					$rank++;
				}

				echo("</table>");
			}
		}

		else
		{
			echo "<h2>No results. Press <a href=\"timer.php\">Home</a> to get the map list.</h2>";
		}

		if($stmt != FALSE)
		{
			$stmt->close();
		}
	}

	else
	{
		$result = mysqli_query($connection, "SELECT DISTINCT map FROM mapzones ORDER BY map ASC;");

		if($result->num_rows > 0)
		{
			echo '<h2>Click a map name in order to auto-fill the form.</h2>';

			while($row = $result->fetch_assoc())
			{
				echo "<a onclick=\"document.all.map.value = '" . $row["map"] . "'\";>" . removeworkshop($row["map"]) . "</a></br>";
			}
		}

		else
		{
			echo "No results";
		}
	}
	?>
</body>
</html>
<?php $connection->close(); ?>
