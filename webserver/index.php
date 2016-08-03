<?php
require 'config.php';
require 'functions.php';
require 'steamid.php';

$connection = new mysqli(DB_HOST, DB_USER, DB_PASSWORD, DB_SCHEMA);
$connection->set_charset('utf8');

$style = 0;

if (isset($_REQUEST['style'])) {
    $style = $_REQUEST['style'];
}

$map = '';

if (isset($_REQUEST['map'])) {
    $map = $_REQUEST['map'];
}

$rr = isset($_REQUEST['rr']);
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
    if (!$map) {
        echo '<title>'.HOMEPAGE_TITLE.'</title>';
    } else {
        echo '<title>'.removeworkshop($_GET['map']).'</title>';
    } ?>

    <!-- HTML5 shim and Respond.js for IE8 support of HTML5 elements and media queries -->
    <!--[if lt IE 9]>
      <script src="https://oss.maxcdn.com/html5shiv/3.7.2/html5shiv.min.js"></script>
      <script src="https://oss.maxcdn.com/respond/1.4.2/respond.min.js"></script>
    <![endif]-->
    <!-- let's hope maxcdn won't shut down ._. -->

    <!-- load jquery, pretty sure we need it for bootstrap -->
    <!-- asyncloading it will show irrelevant errors in the browser console, but has to happen due to pagespeed optimizing -->
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
          <a class="navbar-brand" href="index.php"><?php echo '<i class="fa fa-clock-o"></i> '.TOPLEFT_TITLE; ?></a>
          <a class="navbar-brand" href="index.php?rr=1">Recent Records</a>
        </div>
        <div id="navbar" class="navbar-collapse collapse">
            <form id="records" class="navbar-form navbar-right" method="GET">
                <div class="form-group">
                    <select name="style" class="form-control">
                        <?php
                        for ($i = 0; $i < count($styles); $i++) {
                            ?> <option value="<?php echo $i; ?>" <?php if ($i == DEFAULT_STYLE || $style == $i) {
                                echo 'selected="selected"';
                            } ?>><?php echo $styles[$i]; ?></option> <?php

                        }
                        ?>
                    </select>
                </div>
                <div class="form-group">
                    <select name="map" class="form-control" required>
                        <option value="" selected="selected">None</option>
                        <?php
                        $result = mysqli_query($connection, 'SELECT DISTINCT '.MYSQL_PREFIX.'map FROM mapzones ORDER BY map ASC;');

                        if ($result->num_rows > 0) {
                            while ($row = $result->fetch_assoc()) {
                                // $row["map"] - including workshop
                                // removeworkshop($row["map"]) - no workshop
                                ?> <option value="<?php echo $row['map']; ?>" <?php if ($row['map'] == $map) {
                                    echo 'selected="selected"';
                                } ?>><?php echo removeworkshop($row['map']); ?></option> <?php

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

    <div class="container-fluid">
      <div class="row-fluid">
        <div class="col-md-10 col-md-offset-1">
          <div class="panel panel-default">
            <div class="panel-heading cam-heading center">
              <?php echo HOMEPAGE_TITLE; ?> <strong>-</strong> Record Database
            </div>
            <div class="panel-body table-responsive">
        <?php
        if (!isset($_REQUEST['map']) && !$rr) {
            ?>
            <h1><?php echo HEADER_TITLE; ?></h1>
            <p>
                To view the records of any map, please select it using the menu at the top right of this page.<br/>
                Don't forget to select a style if you wish, and then tap 'Submit'!</p>

            <p>
                Alternatively, you may click <a href="index.php?rr=1">Recent Records</a> to view the latest <?php echo RECORD_LIMIT_LATEST; ?> records.
            </p>
            <?php

        } else {
            $results = false;
            $stmt = false;

            if ($rr && ((USES_RANKINGS == '0' && $stmt = $connection->prepare('SELECT p.map, u.name, p.style, p.time, p.jumps, u.auth, p.date FROM '.MYSQL_PREFIX.'playertimes p JOIN (SELECT style, MIN(time) time FROM '.MYSQL_PREFIX.'playertimes GROUP BY style, map) s ON p.style = s.style AND p.time = s.time JOIN '.MYSQL_PREFIX.'users u ON p.auth = u.auth GROUP BY style, map ORDER BY date DESC;')) || $stmt = $connection->prepare('SELECT pt.map, u.name, pt.style, pt.time, pt.jumps, u.auth, pt.date, pp.points FROM '.MYSQL_PREFIX.'playertimes pt JOIN '.MYSQL_PREFIX.'playerpoints pp JOIN (SELECT style, MIN(time) time FROM '.MYSQL_PREFIX.'playertimes GROUP BY style, map) s ON pt.style = s.style AND pt.time = s.time AND pt.id = pp.recordid JOIN '.MYSQL_PREFIX.'users u ON pt.auth = u.auth GROUP BY style, map ORDER BY date DESC;'))) {
                echo $connection->error;

                $stmt->execute();

                $stmt->store_result();

                $results = ($rows = $stmt->num_rows) > 0;

                if (USES_RANKINGS == '1') {
                    $stmt->bind_result($map, $name, $style, $time, $jumps, $auth, $date, $pp);
                } else {
                    $stmt->bind_result($map, $name, $style, $time, $jumps, $auth, $date);
                }

                if ($rows > 0) {
                    $records = 0;

                    $first = true;

                    while ($row = $stmt->fetch()) {
                        if ($first) {
                            ?>
                            <table class="table table-striped table-hover">
                                <thead id="ignore">
                                    <th>Map</th>
                                    <th>Player</th>
                                    <th>Style</th>
                                    <th>Time</th>
                                    <th>Jumps</th>
                                    <th>Points</th>
                                    <th>SteamID 3</th>
                                    <th>Date <small>(YYYY-MM-DD)</small></th>
                                </thead>
                            <?php

                            $first = false;
                        } ?>

    					<tr>
                            <td><?php echo removeworkshop($map); ?></td>
        					<td><?php echo $name; ?></td>
        					<td><?php echo $styles[$style]; ?></td>
        					<td><?php echo formattoseconds($time); ?></td>
        					<td><?php echo number_format($jumps); ?></td>
                            <td><?php if (USES_RANKINGS == '1') {
                            echo number_format($pp, 2);
                        } else {
                            echo '---';
                        } ?></td>
                            <td><?php
                            $steamid = SteamID::Parse($auth, SteamID::FORMAT_STEAMID3);
                        echo '<a href="https://steamcommunity.com/profiles/'.$steamid->Format(SteamID::FORMAT_STEAMID64).'/" target="_blank">'.$auth.'</a>'; ?></td>

        					<td><?php if ($date[4] == '-')
		                        {
		                            echo $date;
		                        }

		                        else
		                        {
		                            echo date('Y-m-d H:i:s', $date);
		                        } ?></td>
                        </tr>

                        <?php
                        if (++$records > RECORD_LIMIT_LATEST) {
                            break;
                        }
                    }
                }
            } elseif ((USES_RANKINGS == '0' && $stmt = $connection->prepare('SELECT p.id, u.auth, u.name, p.time, p.jumps, p.date FROM '.MYSQL_PREFIX.'playertimes p JOIN '.MYSQL_PREFIX.'users u ON p.auth = u.auth WHERE map = ? AND style = ? ORDER BY time ASC;')) || $stmt = $connection->prepare('SELECT pt.id, u.auth, u.name, pt.time, pt.jumps, pt.date, pp.points FROM '.MYSQL_PREFIX.'playertimes pt JOIN '.MYSQL_PREFIX.'playerpoints pp JOIN '.MYSQL_PREFIX.'users u ON pt.auth = u.auth AND pt.id = pp.recordid WHERE pt.map = ? AND pt.style = ? ORDER BY time ASC;')) {
                $stmt->bind_param('ss', $map, $style);
                $stmt->execute();

                $stmt->store_result();

                $results = ($rows = $stmt->num_rows) > 0;

                if (USES_RANKINGS == '1') {
                    $stmt->bind_result($id, $auth, $name, $time, $jumps, $date, $pp);
                } else {
                    $stmt->bind_result($id, $auth, $name, $time, $jumps, $date);
                }

                if ($rows > 0) {
                    $first = true;

                    $rank = 1;

                    while ($row = $stmt->fetch()) {
                        if ($first) {
                            ?>
                            <p><span class="mark"><?php echo $styles[$style]; ?></span> Records (<?php echo number_format($rows); ?>) for <i><?php echo removeworkshop($map); ?></i>:</p>

    						<table class="table table-striped table-hover">
    						<thead id="ignore"><th>Rank</th>
    						<th>Record ID</th>
    						<th>SteamID 3</th>
    						<th>Player</th>
    						<th>Time</th>
    						<th>Jumps</th>
    						<th>Points</th>
                            <th>Date <small>(YYYY-MM-DD)</small></th></thead>

    						<?php

                            $first = false;
                        } ?>

                        <?php if ($rank == 1) {
                            ?>
                            <tr class="warning">
                            <?php

                        } else {
                            ?>
                            <tr class="default">
                            <?php

                        } ?>
                        <td>
                        <?php switch ($rank) {
                            case 1:
                            {
                                echo '<i class="fa fa-trophy" style="color:#C98910"></i>';
                                break;
                            }

                            case 2:
                            {
                                echo '<i class="fa fa-trophy" style="color:#A8A8A8"></i>';
                                break;
                            }

                            case 3:
                            {
                                echo '<i class="fa fa-trophy" style="color:#965A38"></i>';
                                break;
                            }

                            default:
                            {
                                echo '#'.$rank;
                                break;
                            }
                        } ?></td>
    					<td><?php echo $id; ?></td>
    					<td><?php
                        $steamid = SteamID::Parse($auth, SteamID::FORMAT_STEAMID3);
                        echo '<a href="http://steamcommunity.com/profiles/'.$steamid->Format(SteamID::FORMAT_STEAMID64).'/" target="_blank">'.$auth.'</a>'; ?></td>
    					<td><?php echo $name; ?></td>
    					<td>

    					<?php
                        echo formattoseconds($time); ?></td>
    					<td><?php echo number_format($jumps); ?></td>
                        <td><?php if (USES_RANKINGS == '1') {
                            echo number_format($pp, 2);
                        } else {
                            echo '---';
                        } ?></td>
                        <td><?php if ($date[4] == '-')
                        {
                            echo $date;
                        }

                        else
                        {
                            echo date('Y-m-d H:i:s', $date);
                        } ?></td></tr>

    					<?php

                        if (++$rank > RECORD_LIMIT) {
                            break;
                        }
                    } ?> </table> <?php

                }
            }

            if ($stmt != false) {
                $stmt->close();
            }

            if (!$results) {
                ?> <h1>No results!</h1>
                <p>Try another map, there may be some records!</p> <?php

            }
        }
        ?>
      </div>
    </div>
  </div>
</div>
</div>
</div>

</body>

  <!-- load those lately because it makes the page load faster -->
  <!-- IE10 viewport hack for Surface/desktop Windows 8 bug -->
  <link rel="stylesheet" href="assets/css/ie10-viewport-bug-workaround.css">

  <!-- Custom styles for this template -->
  <?php
  if (PAGE_STYLE == '0') {
      echo '<link rel="stylesheet" href="timer.css">';
  } else {
      echo '<link rel="stylesheet" href="timer-red.css">';
  }
  ?>

  <!-- font awesome -->
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.5.0/css/font-awesome.min.css">
</html>
