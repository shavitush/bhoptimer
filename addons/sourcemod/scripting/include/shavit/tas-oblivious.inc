/*
 * tas-oblivious.inc file
 * by: oblivious
 *
 * Originally from autogain (https://github.com/defiy/autogain) Mirror: https://github.com/PMArkive/autogain
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

#if defined _shavit_tas_oblivious_included
	#endinput
#endif
#define _shavit_tas_oblivious_included


stock float normalize_yaw(float _yaw)
{
	while (_yaw > 180.0) _yaw -= 360.0;
	while (_yaw < -180.0) _yaw += 360.0; return _yaw;
}

stock float get_length_2d(float vec[3])
{
	return SquareRoot(vec[0] * vec[0] + vec[1] * vec[1]);
}

stock float ground_delta_opt(int client, float angles[3], float move[3], float surface_friction,
	float accelerate, float friction, float stopspeed)
{
	float fore[3], side[3], wishvel[3];
	float wishspeed;

	GetAngleVectors(angles, fore, side, NULL_VECTOR);

	fore[2] = 0.0;
	side[2] = 0.0;
	NormalizeVector(fore, fore);
	NormalizeVector(side, side);

	wishvel[2] = 0.0;
	for(int i = 0; i < 2; i++)
		wishvel[i] = fore[i] * move[0] + side[i] * move[1];

	wishspeed = GetVectorLength(wishvel);

	if(wishspeed > GetEntPropFloat(client, Prop_Send, "m_flMaxspeed") && GetEntPropFloat(client, Prop_Send, "m_flMaxspeed") != 0.0) wishspeed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
	float speed = GetVectorLength(velocity);

	float interval_per_tick = GetTickInterval();

	float accelspeed = accelerate * wishspeed * interval_per_tick * surface_friction;

	float control = speed;
	if (control < stopspeed) control = stopspeed;
	float drop = control * friction * interval_per_tick * surface_friction;

	float newspeed = speed - drop;
	if (newspeed < 0.0) newspeed = 0.0;

	float tmp = wishspeed - accelspeed;

	if (tmp <= newspeed)
	{
		float gamma = RadToDeg(ArcCosine(tmp / newspeed));
		float vel_dir_ang = RadToDeg(ArcTangent2(velocity[1], velocity[0]));

		vel_dir_ang = normalize_yaw(vel_dir_ang);

		float accel_yaw = RadToDeg(ArcTangent2(wishvel[1], wishvel[0]));

		float diffm = vel_dir_ang - gamma;
		float diffp = vel_dir_ang + gamma;

		diffm = normalize_yaw(diffm - accel_yaw);
		diffp = normalize_yaw(diffp - accel_yaw);

		float delta_opt = 0.0;
		if (FloatAbs(diffm) <= FloatAbs(diffp))
			delta_opt = -diffm;
		else
			delta_opt = -diffp;
		delta_opt = normalize_yaw(delta_opt);

		return delta_opt;
	}

	return 0.0;
}

stock Action ObliviousOnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2],
	float air_accelerate, float surface_friction, float flAirSpeedCap, float flMaxMove,
	bool no_speed_loss)
{
	float flMaxSpeed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");

	bool set_back = true;
	if (vel[0] != 0.0 || vel[1] != 0.0)
		set_back = false;
	if (set_back)
		vel[1] = flMaxMove;

	float velocity[3], velocity_opt[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);

	velocity_opt[0] = velocity[0]; velocity_opt[1] = velocity[1]; velocity_opt[2] = velocity[2];

	float vel_yaw = ArcTangent2(velocity[1], velocity[0]) * 180.0 / FLOAT_PI;

	float delta_opt = -normalize_yaw(angles[1] - vel_yaw);

	if (get_length_2d(velocity) == 0.0)
		delta_opt = 90.0;

	if (vel[0] != 0.0 && vel[1] == 0.0)
	{
		float sign = vel[0] > 0.0 ? -1.0 : 1.0;
		delta_opt = -normalize_yaw(angles[1] - (vel_yaw + (90.0 * sign)));
	}
	if (vel[0] != 0.0 && vel[1] != 0.0)
	{
		float sign = vel[1] > 0.0 ? -1.0 : 1.0;
		if (vel[0] < 0.0)
			sign = -sign;
		delta_opt = -normalize_yaw(angles[1] - (vel_yaw + (45.0 * sign)));
	}

	float frac = 1.0;

	if (buttons & IN_DUCK && no_speed_loss)
		frac = 0.34;

	float _addspeed = 0.0;
	if (!set_back)
	{
		float _fore[3], _side[3], _wishvel[3], _wishdir[3];
		float _wishspeed, _wishspd, _currentspeed;

		GetAngleVectors(angles, _fore, _side, NULL_VECTOR);

		_fore[2] = 0.0; _side[2] = 0.0;
		NormalizeVector(_fore, _fore); NormalizeVector(_side, _side);

		for(int i = 0; i < 2; i++)
			_wishvel[i] = _fore[i] * vel[0] * frac + _side[i] * vel[1] * frac;

		_wishspeed = NormalizeVector(_wishvel, _wishdir);

		if(_wishspeed > flMaxSpeed && flMaxSpeed != 0.0) _wishspeed = flMaxSpeed;

		_wishspd = _wishspeed;
		if (_wishspd > flAirSpeedCap)
			_wishspd = flAirSpeedCap;

		_currentspeed = GetVectorDotProduct(velocity, _wishdir);
		_addspeed = _wishspd - _currentspeed;
		if (_addspeed < 0.0)
			_addspeed = 0.0;
	}

	float fore[3], side[3], wishvel[3], wishdir[3];
	float wishspeed, wishspd, addspeed, currentspeed;

	float tmp[3];
	tmp[0] = 0.0; tmp[2] = 0.0;
	tmp[1] = normalize_yaw(angles[1] + delta_opt);
	GetAngleVectors(tmp, fore, side, NULL_VECTOR);

	fore[2] = 0.0; side[2] = 0.0;
	NormalizeVector(fore, fore); NormalizeVector(side, side);

	for(int i = 0; i < 2; i++)
		wishvel[i] = fore[i] * vel[0] * frac + side[i] * vel[1] * frac;

	wishspeed = NormalizeVector(wishvel, wishdir);

	if(wishspeed > flMaxSpeed && wishspeed != 0.0) wishspeed = flMaxSpeed;

	wishspd = wishspeed;
	if (wishspd > flAirSpeedCap)
		wishspd = flAirSpeedCap;

	currentspeed = GetVectorDotProduct(velocity, wishdir);
	addspeed = wishspd - currentspeed;

	if (no_speed_loss)
	{
		if (_addspeed > addspeed)
		{
			addspeed = _addspeed - addspeed;
		}
		else
		{
			addspeed -= _addspeed;
		}
	}
	else
	{
		addspeed = addspeed - _addspeed;

		if (addspeed > flAirSpeedCap)
			addspeed = flAirSpeedCap;
	}

	if (buttons & IN_DUCK)
	{
		float vel2d[3]; vel2d[0] = velocity[0]; vel2d[1] = velocity[1];
		//PrintToChat(client, "%f %f\n", GetVectorLength(vel2d), addspeed);
	}

	if (addspeed < 0.0)
		addspeed = 0.0;

	float accelspeed = wishspeed * air_accelerate * GetTickInterval() * surface_friction;

	if (accelspeed > addspeed)
		accelspeed = addspeed;

	for (int i = 0; i < 3; i++)
		velocity_opt[i] += accelspeed * wishdir[i];

	float new_vel[3];

	float numer = velocity_opt[0] * velocity[0] + velocity_opt[1] * velocity[1];
	//float denom = SquareRoot(velocity_opt[0] * velocity_opt[0] + velocity_opt[1] * velocity_opt[1]) * SquareRoot(velocity[0] * velocity[0] + velocity[1] * velocity[1]);
	float denom = get_length_2d(velocity_opt) * get_length_2d(velocity);
	float ang = 0.0;
	if (denom > numer)
		ang = ArcCosine(numer / denom) * 180.0 / FLOAT_PI;
	if (vel[1] < 0.0) ang = -ang;

	float st = Sine(ang * FLOAT_PI / 180.0);
	float ct = Cosine(ang * FLOAT_PI / 180.0);

	new_vel[0] = (velocity_opt[0] * ct) - (velocity_opt[1] * st);
	new_vel[1] = (velocity_opt[0] * st) + (velocity_opt[1] * ct);
	new_vel[2] = velocity_opt[2];

	float base_vel[3];
	GetEntPropVector(client, Prop_Data, "m_vecBaseVelocity", base_vel);

	//PrintToChat(client, "%.2f, %.2f, %.2f", base_vel[0], base_vel[1], base_vel[2]);

	if (GetVectorLength(new_vel) < 99999.0 && GetVectorLength(new_vel) > 0.0)
	{
		SetEntPropVector(client, Prop_Data, "m_vecVelocity", new_vel);
		SetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", new_vel);
	}

	if (set_back)
		vel[1] = 0.0;

	return Plugin_Continue;
}
