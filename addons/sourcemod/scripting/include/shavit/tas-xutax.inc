/*
 * tas-xutax.inc file
 * by: xutaxkamay, KiD Fearless
 *
 * Retrieved from KiD-TAS (https://github.com/kidfearless/KiD-TAS)
 * and edited to be part of shavit's Timer (https://github.com/shavitush/bhoptimer)
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

#if defined _shavit_tas_xutax_included
	#endinput
#endif
#define _shavit_tas_xutax_included

// reference code for CGameMovement::AirAccelerate & CGameMovement::AirMove at:
// https://github.com/ValveSoftware/source-sdk-2013/blob/0d8dceea4310fde5706b3ce1c70609d72a38efdf/mp/src/game/shared/gamemovement.cpp#L1707-L1799


stock float AngleNormalize(float flAngle)
{
	if (flAngle > 180.0)
		flAngle -= 360.0;
	else if (flAngle < -180.0)
		flAngle += 360.0;

	return flAngle;
}

stock float Vec2DToYaw(float vec[2])
{
	float flYaw = 0.0;

	if (vec[0] != 0.0 || vec[1] != 0.0)
	{
		float vecNormalized[2];

		float flLength = SquareRoot(vec[0] * vec[0] + vec[1] * vec[1]);

		vecNormalized[0] = vec[0] / flLength;
		vecNormalized[1] = vec[1] / flLength;

		// Credits to Valve.
		flYaw = ArcTangent2(vecNormalized[1], vecNormalized[0]) * (180.0 / FLOAT_PI);

		flYaw = AngleNormalize(flYaw);
	}

	return flYaw;
}

/*
 * So our problem here is to find a wishdir that no matter the angles we choose, it should go to the direction we want.
 * So forward/right vector changing but not sidemove and forwardmove for the case where we modify our angles. (1)
 * But in our case we want sidemove and forwardmove values changing and not the forward/right vectors. (2)
 * So our unknown variables is fmove and smove to know the (2) case. But we know the (1) case so we can solve this into a linear equation.
 * To make it more simplier, we know the wishdir values and forward/right vectors, but we do not know the fowardmove and sidemove variables
 * and that's what we want to solve.
 * That's what is doing this function, but only in 2D since we can only move forward or side.
 * But, for noclip (3D) it's a different story that I will let you discover, same method, but 3 equations and 3 unknown variables (forwardmove, sidemove, upmove).
 */

stock void Solve2DMovementsVars(float vecWishDir[2], float vecForward[2], float vecRight[2], float &flForwardMove, float &flSideMove, float flMaxMove)
{
	// wishdir[0] = foward[0] * forwardmove + right[0] * sidemove;
	// wishdir[1] = foward[1] * forwardmove + right[1] * sidemove;

	// Let's translate this to letters.
	// v = a * b + c * d
	// w = e * b + f * d
	// v = wishdir[0]; w = wishdir[1]...

	// Now let's solve it with online solver https://quickmath.com/webMathematica3/quickmath/equations/solve/advanced.jsp
	// https://cdn.discordapp.com/attachments/609163806085742622/675477245178937385/c3ca4165c30b3b342e57b903a3ded367-3.png

	float v = vecWishDir[0];
	float w = vecWishDir[1];
	float a = vecForward[0];
	float c = vecRight[0];
	float e = vecForward[1];
	float f = vecRight[1];

	float flDivide = (c * e - a * f);
	if(flDivide == 0.0)
	{
		flForwardMove = flMaxMove;
		flSideMove = 0.0;
	}
	else
	{
		flForwardMove = (c * w - f * v) / flDivide;
		flSideMove = (e * v - a * w) / flDivide;
	}
}

stock float GetThetaAngleInAir(float flVelocity[2], float flAirAccelerate, float flMaxSpeed, float flSurfaceFriction, float flFrametime, float flAirSpeedCap)
{
	// In order to solve this, we must check that accelspeed < 30
	// so it applies the correct strafing method.
	// So there is basically two cases:
	// if 30 - accelspeed <= 0 -> We use the perpendicular of velocity.
	// but if 30 - accelspeed > 0 the dot product must be equal to = 30 - accelspeed
	// in order to get the best gain.
	// First case is theta == 90
	// How to solve the second case?
	// here we go
	// d = velocity2DLength * cos(theta)
	// cos(theta) = d / velocity2D
	// theta = arcos(d / velocity2D)

	float flAccelSpeed = flAirAccelerate * flMaxSpeed * flSurfaceFriction * flFrametime;

	float flWantedDotProduct = flAirSpeedCap - flAccelSpeed;

	if (flWantedDotProduct > 0.0)
	{
		float flVelLength2D = SquareRoot(flVelocity[0] * flVelocity[0] + flVelocity[1] * flVelocity[1]);
		if(flVelLength2D == 0.0)
		{
			return 90.0;
		}
		float flCosTheta = flWantedDotProduct / flVelLength2D;

		if (flCosTheta > 1.0)
		{
			flCosTheta = 1.0;
		}
		else if(flCosTheta < -1.0)
		{
			flCosTheta = -1.0;
		}


		float flTheta = ArcCosine(flCosTheta) * (180.0 / FLOAT_PI);

		return flTheta;
	}
	else
	{
		return 90.0;
	}
}


// Same as above, but this time we calculate max delta angle
// so we can change between normal strafer and autostrafer depending on the player's viewangles difference.
/*float GetMaxDeltaInAir(float flVelocity[2], float flAirAccelerate, float flMaxSpeed, float flSurfaceFriction, float flFrametime)
{
	float flAccelSpeed = flAirAccelerate * flMaxSpeed * flSurfaceFriction * flFrametime;

	if (flAccelSpeed >= g_flAirSpeedCap)
	{
		flAccelSpeed = g_flAirSpeedCap;
	}

	float flVelLength2D = SquareRoot(flVelocity[0] * flVelocity[0] + flVelocity[1] * flVelocity[1]);

	float flMaxDelta = ArcTangent2(flAccelSpeed, flVelLength2D)  * (180 / FLOAT_PI);

	return flMaxDelta;
}*/

stock float SimulateAirAccelerate(float flVelocity[2], float flWishDir[2], float flAirAccelerate, float flMaxSpeed, float flSurfaceFriction, float flFrametime, float flVelocityOutput[2], float flAirSpeedCap)
{
	float flWishSpeedCapped = flMaxSpeed;

	// Cap speed
	if( flWishSpeedCapped > flAirSpeedCap )
		flWishSpeedCapped = flAirSpeedCap;

	// Determine veer amount
	float flCurrentSpeed = flVelocity[0] * flWishDir[0] + flVelocity[1] * flWishDir[1];

	// See how much to add
	float flAddSpeed = flWishSpeedCapped - flCurrentSpeed;

	// If not adding any, done.
	if( flAddSpeed <= 0.0 )
	{
		return;
	}

	// Determine acceleration speed after acceleration
	float flAccelSpeed = flAirAccelerate * flMaxSpeed * flFrametime * flSurfaceFriction;

	// Cap it
	if( flAccelSpeed > flAddSpeed )
	{
		flAccelSpeed = flAddSpeed;
	}

	flVelocityOutput[0] = flVelocity[0] + flAccelSpeed * flWishDir[0];
	flVelocityOutput[1] = flVelocity[1] + flAccelSpeed * flWishDir[1];
}

// The idea is to get the maximum angle
stock float GetMaxDeltaInAir(float flVelocity[2], float flMaxSpeed, float flSurfaceFriction, bool bLeft, float flAirAccelerate, float flAirSpeedCap)
{
	float flFrametime = GetTickInterval();

	float flTheta = GetThetaAngleInAir(flVelocity, flAirAccelerate, flMaxSpeed, flSurfaceFriction, flFrametime, flAirSpeedCap);

	// Convert velocity 2D to angle.
	float flYawVelocity = Vec2DToYaw(flVelocity);

	// Get the best yaw direction on the right.
	float flBestYawRight = AngleNormalize(flYawVelocity + flTheta);

	// Get the best yaw direction on the left.
	float flBestYawLeft = AngleNormalize(flYawVelocity - flTheta);

	float flTemp[3], vecBestLeft3D[3], vecBestRight3D[3];

	flTemp[0] = 0.0;
	flTemp[1] = flBestYawLeft;
	flTemp[2] = 0.0;

	GetAngleVectors(flTemp, vecBestLeft3D, NULL_VECTOR, NULL_VECTOR);

	flTemp[0] = 0.0;
	flTemp[1] = flBestYawRight;
	flTemp[2] = 0.0;

	GetAngleVectors(flTemp, vecBestRight3D, NULL_VECTOR, NULL_VECTOR);

	float vecBestRight[2], vecBestLeft[2];

	vecBestRight[0] = vecBestRight3D[0];
	vecBestRight[1] = vecBestRight3D[1];

	vecBestLeft[0] = vecBestLeft3D[0];
	vecBestLeft[1] = vecBestLeft3D[1];

	float flCalcVelocityLeft[2], flCalcVelocityRight[2];

	// Simulate air accelerate function in order to get the new max gain possible on both side.
	SimulateAirAccelerate(flVelocity, vecBestLeft, flAirAccelerate, flMaxSpeed, flFrametime, flSurfaceFriction, flCalcVelocityLeft, flAirSpeedCap);
	SimulateAirAccelerate(flVelocity, vecBestRight, flAirAccelerate, flMaxSpeed, flFrametime, flSurfaceFriction, flCalcVelocityRight, flAirSpeedCap);

	float flNewBestYawLeft = Vec2DToYaw(flCalcVelocityLeft);
	float flNewBestYawRight = Vec2DToYaw(flCalcVelocityRight);

	// Then get the difference in order to find the maximum angle.
	if (bLeft)
	{
		return FloatAbs(AngleNormalize(flYawVelocity - flNewBestYawLeft));
	}
	else
	{
		return FloatAbs(AngleNormalize(flYawVelocity - flNewBestYawRight));
	}

	// Do an estimate otherwhise.
	// return FloatAbs(AngleNormalize(flNewBestYawLeft - flNewBestYawRight) / 2.0);
}

stock void GetIdealMovementsInAir(float flYawWantedDir, float flVelocity[2], float flMaxSpeed, float flSurfaceFriction, float &flForwardMove, float &flSideMove, bool bPreferRight, float flAirAccelerate, float flMaxMove, float flAirSpeedCap)
{
	float flFrametime = GetTickInterval();
	float flYawVelocity = Vec2DToYaw(flVelocity);

	// Get theta angle
	float flTheta = GetThetaAngleInAir(flVelocity, flAirAccelerate, flMaxSpeed, flSurfaceFriction, flFrametime, flAirSpeedCap);

	// Get the best yaw direction on the right.
	float flBestYawRight = AngleNormalize(flYawVelocity + flTheta);

	// Get the best yaw direction on the left.
	float flBestYawLeft = AngleNormalize(flYawVelocity - flTheta);

	float vecBestDirLeft[3], vecBestDirRight[3];
	float tempAngle[3];

	tempAngle[0] = 0.0;
	tempAngle[1] = flBestYawRight;
	tempAngle[2] = 0.0;

	GetAngleVectors(tempAngle, vecBestDirRight, NULL_VECTOR, NULL_VECTOR);

	tempAngle[0] = 0.0;
	tempAngle[1] = flBestYawLeft;
	tempAngle[2] = 0.0;

	GetAngleVectors(tempAngle, vecBestDirLeft, NULL_VECTOR, NULL_VECTOR);

	// Our wanted direction.
	float vecBestDir[2];

	// Let's follow the most the wanted direction now with max possible gain.
	float flDiffYaw = AngleNormalize(flYawWantedDir - flYawVelocity);

	if (flDiffYaw > 0.0)
	{
		vecBestDir[0] = vecBestDirRight[0];
		vecBestDir[1] = vecBestDirRight[1];
	}
	else if(flDiffYaw < 0.0)
	{
		vecBestDir[0] = vecBestDirLeft[0];
		vecBestDir[1] = vecBestDirLeft[1];
	}
	else
	{
		// Going straight.
		if (bPreferRight)
		{
			vecBestDir[0] = vecBestDirRight[0];
			vecBestDir[1] = vecBestDirRight[1];
		}
		else
		{
			vecBestDir[0] = vecBestDirLeft[0];
			vecBestDir[1] = vecBestDirLeft[1];
		}
	}

	float vecForwardWantedDir3D[3], vecRightWantedDir3D[3];
	float vecForwardWantedDir[2], vecRightWantedDir[2];

	tempAngle[0] = 0.0;
	tempAngle[1] = flYawWantedDir;
	tempAngle[2] = 0.0;

	// Convert our yaw wanted direction to vectors.
	GetAngleVectors(tempAngle, vecForwardWantedDir3D, vecRightWantedDir3D, NULL_VECTOR);

	vecForwardWantedDir[0] = vecForwardWantedDir3D[0];
	vecForwardWantedDir[1] = vecForwardWantedDir3D[1];

	vecRightWantedDir[0] = vecRightWantedDir3D[0];
	vecRightWantedDir[1] = vecRightWantedDir3D[1];

	// Solve the movement variables from our wanted direction and the best gain direction.
	Solve2DMovementsVars(vecBestDir, vecForwardWantedDir, vecRightWantedDir, flForwardMove, flSideMove, flMaxMove);

	float flLengthMovements = SquareRoot(flForwardMove * flForwardMove + flSideMove * flSideMove);

	if(flLengthMovements != 0.0)
	{
		flForwardMove /= flLengthMovements;
		flSideMove /= flLengthMovements;
	}
}

stock Action XutaxOnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2],
	float flAirAccelerate, float flSurfaceFriction, float flAirSpeedCap, float flMaxMove, float flOldYawAngle, float fPower)
{
	// clear out forward because Surf_W_Okay is nice...
	vel[0] = 0.0;

	float flFowardMove, flSideMove;
	float flMaxSpeed = GetEntPropFloat(client, Prop_Data, "m_flMaxspeed");
	float flVelocity[3], flVelocity2D[2];

	GetEntPropVector(client, Prop_Data, "m_vecVelocity", flVelocity);

	flVelocity2D[0] = flVelocity[0];
	flVelocity2D[1] = flVelocity[1];

	// PrintToChat(client, "%f", SquareRoot(flVelocity2D[0] * flVelocity2D[0] + flVelocity2D[1] * flVelocity2D[1]));

	GetIdealMovementsInAir(angles[1], flVelocity2D, flMaxSpeed, flSurfaceFriction, flFowardMove, flSideMove, true, flAirAccelerate, flMaxMove, flAirSpeedCap);

	float flAngleDifference = AngleNormalize(angles[1] - flOldYawAngle);
	float flCurrentAngles = FloatAbs(flAngleDifference);


	// Right
	if (flAngleDifference < 0.0)
	{
		float flMaxDelta = GetMaxDeltaInAir(flVelocity2D, flMaxSpeed, flSurfaceFriction, true, flAirAccelerate, flAirSpeedCap);

		if (flCurrentAngles <= flMaxDelta * fPower)
		{
			vel[0] = flFowardMove * flMaxMove;
			vel[1] = flSideMove * flMaxMove;
		}
		else
		{
			vel[1] = flMaxMove;
		}
	}
	else if (flAngleDifference > 0.0)
	{
		float flMaxDelta = GetMaxDeltaInAir(flVelocity2D, flMaxSpeed, flSurfaceFriction, false, flAirAccelerate, flAirSpeedCap);

		if (flCurrentAngles <= flMaxDelta * fPower)
		{
			vel[0] = flFowardMove * flMaxMove;
			vel[1] = flSideMove * flMaxMove;
		}
		else
		{
			vel[1] = -flMaxMove;
		}
	}
	else
	{
		vel[0] = flFowardMove * flMaxMove;
		vel[1] = flSideMove * flMaxMove;
	}

	return Plugin_Continue;
}
