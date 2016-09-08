/**
 * =============================================================================
 * Dynamic for SourceMod (C)2016 Matthew J Dunn.   All rights reserved.
 * =============================================================================
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
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */
 
#if defined _dynamic_basic_included
  #endinput
#endif
#define _dynamic_basic_included

/*
	This methodmap is based on the Dynamic methodmap while using a StringMap methodmap
	for implementation. This methodmap doesn't implement the full features of the Dynamic
	methodmap (type conversion, object naming, plugin sharing, ect). This methodmap can
	be used for basic storage using the standard Dynamic methodmap Methods.
	
	Please see '\scripting\dynamic\examples\basic\' for an example usage of this methodmap
*/

methodmap Basic < StringMap
{
	public Basic()
	{
		return new StringMap();
	}
	
	public void Dispose(bool disposemembers=true)
	{
		delete this;
	}
	
	public int GetInt(const char[] membername, int defaultvalue=-1)
	{
		int value;
		if (this.GetValue(membername, value))
			return value;
		
		return defaultvalue;
	}
	
	public void SetInt(const char[] membername, int value)
	{
		this.SetValue(membername, value);
	}
	
	public bool GetBool(const char[] membername, bool defaultvalue=false)
	{
		bool value;
		if (this.GetValue(membername, value))
			return value;
		
		return defaultvalue;
	}
	
	public void SetBool(const char[] membername, bool value)
	{
		this.SetValue(membername, value);
	}
	
	public float GetFloat(const char[] membername, float defaultvalue=-1.0)
	{
		float value;
		if (this.GetValue(membername, value))
			return value;
		
		return defaultvalue;
	}
	
	public void SetFloat(const char[] membername, float value)
	{
		this.SetValue(membername, value);
	}
	
	public bool GetString(const char[] membername, char[] buffer, int length)
	{
		return this.GetString(membername, buffer, length);
	}
	
	public void SetString(const char[] membername, const char[] value)
	{
		this.SetString(membername, value);
	}
	
	public Dynamic GetObject(const char[] membername)
	{
		Dynamic value;
		if (this.GetValue(membername, value))
			return value;
		
		return INVALID_DYNAMIC_OBJECT;
	}
	
	public void SetObject(const char[] membername, Dynamic value)
	{
		this.SetValue(membername, value);
	}
	
	public Handle GetHandle(const char[] membername)
	{
		Handle value;
		if (this.GetValue(membername, value))
			return value;
		
		return null;
	}
	
	public void SetHandle(const char[] membername, Handle value)
	{
		this.SetValue(membername, value);
	}
	
	public bool GetVector(const char[] membername, float[3] vector)
	{
		return this.GetArray(membername, vector, sizeof(vector));
	}
	
	public void SetVector(const char[] membername, const float[3] value)
	{
		this.SetArray(membername, value, sizeof(value));
	}
}