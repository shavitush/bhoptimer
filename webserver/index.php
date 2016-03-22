<?php
require("config.php");
require("functions.php");
require("steamid.php");

$connection = new mysqli(DB_HOST, DB_USER, DB_PASSWORD, DB_SCHEMA);
$connection->set_charset("utf8");

$style = 0;

if(isset($_REQUEST["style"]))
{
    $style = $_REQUEST["style"];
}

$map = "";

if(isset($_REQUEST["map"]))
{
    $map = $_REQUEST["map"];
}
?>

<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="bhoptimer">

    <!-- favicon -->
    <link href="assets/icons/favicon.ico" rel="icon" type="image/x-icon" />

    <?php
	if(!$map)
	{
		echo("<title>" . HOMEPAGE_TITLE . "</title>");
	}

	else
	{
		echo("<title>".removeworkshop($_GET["map"])."</title>");
	} ?>

    <!-- HTML5 shim and Respond.js for IE8 support of HTML5 elements and media queries -->
    <!--[if lt IE 9]>
      <script src="https://oss.maxcdn.com/html5shiv/3.7.2/html5shiv.min.js"></script>
      <script src="https://oss.maxcdn.com/respond/1.4.2/respond.min.js"></script>
    <![endif]-->
    <!-- let's hope maxcdn won't shut down ._. -->

    <!-- load jquery, pretty sure we need it for bootstrap -->
    <!-- asyncloading it will show irrelevant errors in the brwoser console, but has to happen due to pagespeed optimizing -->
    <script async src="https://ajax.googleapis.com/ajax/libs/jquery/2.2.0/jquery.min.js"></script>

    <!-- bootstrap itself -->
    <script async src="assets/js/bootstrap.min.js"></script>
    <script async src="assets/js/ie10-viewport-bug-workaround.js"></script>

    <!-- Bootstrap core CSS | can't late-load -->
    <link async rel="stylesheet" type="text/css" href="assets/css/bootstrap.min.css">

    <script>
    $(document).ready(function()
    {
        $("tr").hover(function()
        {
            if(!$(this).hasClass("lead") && $(this).attr('id') != "ignore")
            {
                $(this).addClass("mark");
            }
        },

        function()
        {
            if(!$(this).hasClass("lead") && $(this).attr('id') != "ignore")
            {
                $(this).removeClass("mark");
            }
        });
    });
    </script>
  </head>

  <body>

    <nav class="navbar navbar-inverse navbar-fixed-top">
      <div class="container">
        <div class="navbar-header">
          <a class="navbar-brand" href="index.php"><?php echo("<i class=\"fa fa-clock-o\"></i> ".TOPLEFT_TITLE); ?></a>
        </div>
        <div id="navbar" class="navbar-collapse collapse">
            <form id="records" class="navbar-form navbar-right" method="GET">
                <div class="form-group">
                    <select name="style" class="form-control">
                        <option value="0" selected="selected">Forwards</option>
                        <option value="1">Sideways</option>
                    </select>
                </div>
                <div class="form-group">
                    <select name="map" class="form-control" required>
                        <option value="" selected="selected">None</option>
                        <?php
                        $result = mysqli_query($connection, "SELECT DISTINCT ".MYSQL_PREFIX."map FROM mapzones ORDER BY map ASC;");

                        if($result->num_rows > 0)
                        {
                            while($row = $result->fetch_assoc())
                			{
                                // $row["map"] - including workshop
                                // removeworkshop($row["map"]) - no workshop
                				echo("<option value=\"".$row["map"]."\">".removeworkshop($row["map"])."</option>");
                			}
                        }
                        ?>
                    </select>
                </div>

                <button type="submit" class="btn btn-success">Submit</button>
          </form>
        </div>
      </div>
    </nav>

    <div class="jumbotron">
      <div class="container">
        <?php
        if(!isset($_REQUEST["map"]))
        {
            ?>
            <h1><?php echo(HEADER_TITLE); ?></h1>
            <p>To show the records of any map, please select it using the menu at the top right of this page.<br/>
            Don't forget to select a style if you wish, and then tap 'Submit'!</p>
            <?php
        }

        else
        {
            $stmt = FALSE;

    		if($stmt = $connection->prepare("SELECT p.id, p.map, u.auth, u.name, p.time, p.jumps FROM playertimes p JOIN users u ON p.auth = u.auth WHERE map = ? AND style = ? ORDER BY time ASC;"))
    		{
    			$stmt->bind_param("ss", $_GET["map"], $_GET["style"]);
    			$stmt->execute();

    			$stmt->store_result();

    			$rows = $stmt->num_rows;

    			$stmt->bind_result($id, $map, $auth, $name, $time, $jumps);

    			if($rows > 0)
    			{
    				$first = true;

    				$rank = 1;

    				while($row = $stmt->fetch())
    				{
                        if($rank > RECORD_LIMIT)
                        {
                            break;
                        }

    					if($first)
    					{
    						?>
                            <p><span class="mark"><?php echo(getstylestring($style)); ?></span> Records (<?php echo(number_format($rows)); ?>) for <i><?php echo(removeworkshop($map)); ?></i>:</p>

    						<table class="table">
    						<tr id="ignore"><th>Rank</th>
    						<th>Record ID</th>
    						<th>SteamID3</th>
    						<th>Player</th>
    						<th>Time</th>
    						<th>Jumps</th></tr>

    						<?php
    					}
    					?>

                        <?php if($rank == 1)
                        {
                            ?>
                            <tr class="lead mark">
                            <?php
                        }

                        else
                        {
                            ?>
                            <tr>
                            <?php
                        }
                        ?>
                        <td>
                        <?php switch($rank)
                        {
                            case 1:
                            {
                                echo("<i class=\"fa fa-trophy\"></i> #".$rank);
                                break;
                            }

                            case 2:
                            {
                                echo("<i class=\"fa fa-star\"></i> #".$rank);
                                break;
                            }

                            case 3:
                            {
                                echo("<i class=\"fa fa-thumbs-up\"></i> #".$rank);
                                break;
                            }

                            default:
                            {
                                echo("#".$rank);
                                break;
                            }
                        }
                        ?></td>
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

    				?> </table> <?php
    			}

                else
        		{
                    ?> <h1>No results!</h1>
                    <p>Try another map, there may be some records!</p> <?php
        		}
    		}

    		if($stmt != FALSE)
    		{
    			$stmt->close();
    		}
        }
        ?>
      </div>
    </div>
  </body>

  <!-- load those lately because it makes the page load faster -->
  <!-- IE10 viewport hack for Surface/desktop Windows 8 bug -->
  <link rel="stylesheet" href="assets/css/ie10-viewport-bug-workaround.css">

  <!-- Custom styles for this template, if we'll ever use it -->
  <link rel="stylesheet" href="timer.css">

  <!-- font awesome -->
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.5.0/css/font-awesome.min.css">
</html>
