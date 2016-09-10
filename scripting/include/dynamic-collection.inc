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

#if defined _dynamic_collection_included
  #endinput
#endif
#define _dynamic_collection_included

/*
	This methodmap is used to store typed collections based on Dynamic methodmaps. Internally
	an ArrayList is used for storage. This methodmap can be inherited by your own methodmaps
	where you can override the Items method to return your custom methodmap type which MUST
	inherit a Dynamic methodmap.
	
	Please see '\scripting\dynamic\examples\collections\' for an example usage of this methodmap
*/

methodmap Collection < ArrayList
{
	public Collection()
	{
		return view_as<Collection>(new ArrayList());
	}
	
	public void Clear(bool disposemembers=true)
	{
		if (disposemembers)
		{
			int count = this.Length;
			Dynamic member;
			for (int i = 0; i < count; i++)
			{
				member = view_as<Dynamic>(i);
				if (!member.IsValid)
					continue;
					
				member.Dispose();
			}
		}
		
		this.Clear();
	}
	
	public void Dispose(bool disposemembers=true)
	{
		if (disposemembers)
			this.Clear(true);
		
		CloseHandle(this);
	}
	
	public Dynamic Items(int index)
	{
		return this.Get(index);
	}
	
	property int Count
	{
		public get()
		{
			return this.Length;
		}
	}
	
	public int AddItem(Dynamic item)
	{
		this.Push(item);
	}
	
	public int FindItem(Dynamic item)
	{
		int count = this.Length;
		for (int i = 0; i < count; i++)
		{
			if (this.Get(i) == item)
				return i;
		}
		return -1;
	}
	
	public void RemoveItem(Dynamic item)
	{
		int index = this.FindItem(item);
		if (index == -1)
			return;
			
		this.Erase(index);
	}
	
	public void RemoveIndex(int index)
	{
		this.Erase(index);
	}
}
