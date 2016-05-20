<?php
function formattoseconds($time)
{
  $iTemp = floor($time);

	$iHours = 0;

	if($iTemp > 3600)
	{
		$iHours = floor($iTemp / 3600.0);
		$iTemp %= 3600;
	}

	$sHours = "";

	if($iHours < 10)
	{
		$sHours = "0" . $iHours;
	}

	else
	{
		$sHours = $iHours;
	}

	$iMinutes = 0;

	if($iTemp >= 60)
	{
		$iMinutes = floor($iTemp / 60.0);
		$iTemp %= 60;
	}

	$sMinutes = "";

	if($iMinutes < 10)
	{
		$sMinutes = "0" . $iMinutes;
	}

	else
	{
		$sMinutes = $iMinutes;
	}

	$fSeconds = (($iTemp) + $time - floor($time));

	$sSeconds = "";

	if($fSeconds < 10)
	{
		$sSeconds = "0" . number_format($fSeconds, 3);
	}

	else
	{
		$sSeconds = number_format($fSeconds, 3);
	}

	if($iHours > 0)
	{
		$newtime = $sHours . ":" . $sMinutes . ":" . $sSeconds . "s";
	}

	else if($iMinutes > 0)
	{
		$newtime = $sMinutes . ":" . $sSeconds . "s";
	}

	else
	{
		$newtime = number_format($fSeconds, 3) . "s";
	}

  return $newtime;
}

function removeworkshop($mapname)
{
	if(strpos($mapname, "workshop/") !== false)
	{
		$pieces = explode("/", $mapname);

		return $pieces[2];
	}

	return $mapname;
}
?>
