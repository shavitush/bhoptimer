/*
 * shavit's Timer - maps-folder-stocks.inc file
 * by: rtldg, kidfearless
 *
 * This file is part of shavit's Timer.
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

#if defined _shavit_mapsfolderstocks_included
	#endinput
#endif
#define _shavit_mapsfolderstocks_included

stock bool WriteNavMesh(const char[] map, bool skipExistsCheck = false)
{
	char sTempMap[PLATFORM_MAX_PATH];
	FormatEx(sTempMap, PLATFORM_MAX_PATH, "maps/%s.nav", map);

	if (skipExistsCheck || !FileExists(sTempMap))
	{
		File file = OpenFile(sTempMap, "wb");

		if (file != null)
		{
			static int defaultNavMesh[205] = {
				0xCE, 0xFA, 0xED, 0xFE, 0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x58, 0xF6, 0x01, 0x00, 
				0x01, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
				0x00, 0x80, 0xED, 0xC3, 0x00, 0x00, 0x48, 0x42, 0xFF, 0x1F, 0x00, 0x42, 0x00, 0x00, 0x48, 0xC2, 
				0x00, 0x80, 0xED, 0x43, 0xFF, 0x1F, 0x00, 0x42, 0xFF, 0x1F, 0x00, 0x42, 0xFF, 0x1F, 0x00, 0x42, 
				0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
				0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0xE7, 0xC3, 0x00, 0x00, 0x7A, 0x42, 0xFF, 0x1F, 0x00, 
				0x42, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7A, 0xC2, 0x00, 0x00, 0x7A, 0x42, 0xFF, 0x1F, 
				0x00, 0x42, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7A, 0xC2, 0x00, 0x40, 0xE7, 0x43, 0xFF, 
				0x1F, 0x00, 0x42, 0x01, 0x03, 0x00, 0x00, 0x00, 0x00, 0x40, 0xE7, 0xC3, 0x00, 0x40, 0xE7, 0x43, 
				0xFF, 0x1F, 0x00, 0x42, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 
				0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x42, 0x00, 0x00, 0xF0, 0x42, 0x00, 0x00, 0x80, 0x3F, 0x00, 
				0x00, 0x80, 0x3F, 0x00, 0x00, 0x80, 0x3F, 0x00, 0x00, 0x80, 0x3F, 0x01, 0x00, 0x00, 0x00, 0x01, 
				0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
			};

			file.Write(defaultNavMesh, 205, 1);
			delete file;
		}

		return true;
	}

	return false;
}

stock bool ReadMapsFolderHandler(const char path[PLATFORM_MAX_PATH], bool is_stringmap, Handle data, bool lowercase, bool display, bool iter_subfolders, bool use_valve_fs, char[][] exclude_prefixes, int exclude_count)
{
	bool first_iteration = StrEqual(path, "maps");
	DirectoryListing dir = OpenDirectory(path, use_valve_fs);

	if (dir == null)
	{
		return false;
	}

	char buffer[PLATFORM_MAX_PATH];
	FileType type;

	while (dir.GetNext(buffer, sizeof(buffer), type))
	{
		if (type == FileType_Directory)
		{
			if (buffer[0] == '.' && (buffer[1] == 0 || (buffer[1] == '.' && buffer[2] == 0)))
			{
				continue;
			}

			if (iter_subfolders)
			{
				char subfolder[PLATFORM_MAX_PATH];
				FormatEx(subfolder, sizeof(subfolder), "%s/%s", path, buffer);
				ReadMapsFolderHandler(subfolder, is_stringmap, data, lowercase, display, iter_subfolders, use_valve_fs, exclude_prefixes, exclude_count);
			}
		}
		else if (type == FileType_File)
		{
			int length = strlen(buffer);

			if (length < 5 || buffer[length-4] != '.') // a.bsp
			{
				continue;
			}

			if ((buffer[length-3] == 'b' && buffer[length-2] == 's' && buffer[length-1] == 'p') ||
			    (buffer[length-3] == 'u' && buffer[length-2] == 'g' && buffer[length-1] == 'c'))
			{
				buffer[length-4] = 0;

				if (lowercase)
				{
					LowercaseString(buffer);
				}

				bool skip = false;

				for (int i = 0; i < exclude_count; i++)
				{
					if (strncmp(buffer, exclude_prefixes[i], strlen(exclude_prefixes[i]), lowercase) == 0)
					{
						skip = true;
						break;
					}
				}

				if (skip)
				{
					continue;
				}

				if (!display && !first_iteration)
				{
					char temp[PLATFORM_MAX_PATH];
					int skip_this = 5; // strlen("maps/")
					FormatEx(temp, sizeof(temp), "%s/%s", path[skip_this], buffer);
					buffer = temp;
				}

				if (is_stringmap)
				{
					view_as<StringMap>(data).SetValue(buffer, false, false);
				}
				else
				{
					view_as<ArrayList>(data).PushString(buffer);
				}
			}
		}
	}

	delete dir;
	return true;
}

static char empty_excludes[][] = {""};

stock bool ReadMapsFolderStringMap(StringMap data, bool lowercase=true, bool display=false, bool iter_subfolders=true, bool use_valve_fs=true, char[][] exclude_prefixes=empty_excludes, int exclude_count=0)
{
	return ReadMapsFolderHandler("maps", true, data, lowercase, display, iter_subfolders, use_valve_fs, exclude_prefixes, exclude_count);
}

// don't forget to declare your ArrayList like below :)))
//// ArrayList maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
stock bool ReadMapsFolderArrayList(ArrayList data, bool lowercase=true, bool display=false, bool iter_subfolders=true, bool use_valve_fs=true, char[][] exclude_prefixes=empty_excludes, int exclude_count=0)
{
	return ReadMapsFolderHandler("maps", false, data, lowercase, display, iter_subfolders, use_valve_fs, exclude_prefixes, exclude_count);
}
