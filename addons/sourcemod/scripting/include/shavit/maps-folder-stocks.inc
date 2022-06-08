/*
 * shavit's Timer - maps-folder-stocks.inc file
 * by: rtldg, kidfearless
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
 *
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
			int zero[1];
			static int defaultNavMesh[51] = {
				-17958194, 16, 1, 128600, 16777217, 1, 1, 0, -1007845376, 1112014848, 1107304447, -1035468800,
				1139638272, 1107304447, 1107304447, 1107304447, 0, 0, 0, 0, 4, -415236096, 2046820547, 2096962,
				65858, 0, 49786, 536822394, 33636864, 0, 12745216, -12327104, 21102623, 3, -1008254976, 1139228672,
				1107304447, 1, 0, 0, 0, 4386816, 4386816, 4161536, 4161536, 4161536, 20938752, 16777216, 33554432, 0, 0
			};

			file.Write(defaultNavMesh, sizeof(defaultNavMesh), 4);
			file.Write(zero, 1, 1);
			delete file;
		}

		return true;
	}

	return false;
}

stock bool WriteNavMeshBz2(const char[] map, bool skipExistsCheck = false)
{
	char sTempMap[PLATFORM_MAX_PATH];
	FormatEx(sTempMap, PLATFORM_MAX_PATH, "maps/%s.nav.bz2", map);

	if (skipExistsCheck || !FileExists(sTempMap))
	{
		File file = OpenFile(sTempMap, "wb");

		if (file != null)
		{
			static int defaultNavMeshBz2[132/4] = {
				0x39685A42, 0x26594131, 0xB8955953, 0x0000B354,
				0xFEC56E4E, 0x80004004, 0x0040D800, 0x40100040,
				0x00011800, 0xA0114182, 0xA7127200, 0x915133AA,
				0x04B501A0, 0x64A03285, 0x31190D0D, 0x96F2A658,
				0x864651CE, 0xA93468D3, 0xD269C634, 0x66EE82B6,
				0x3B1D4103, 0xD4BE309C, 0x58DF5463, 0xC0076E1B,
				0x346C6DC1, 0x8B9FD47B, 0x0385015D, 0x3B260D99,
				0xF43C28F0, 0xD071CFB3, 0xC95DFC92, 0x4242E114,
				0xCC52E156
			};

			file.Write(defaultNavMeshBz2, sizeof(defaultNavMeshBz2), 4);
			delete file;
		}

		return true;
	}

	return false;
}

stock void CreateAllNavFiles()
{
	StringMap mapList = new StringMap();
	DirectoryListing dir = OpenDirectory("maps", true);

	if (dir == null)
	{
		return;
	}

	char fileName[PLATFORM_MAX_PATH];
	FileType type;

	// Loop through maps folder.
	// If .bsp, mark as need .nav
	// If .nav, mark as have .nav
	while (dir.GetNext(fileName, sizeof(fileName), type))
	{
		if (type != FileType_File)
		{
			continue;
		}

		int length = strlen(fileName);

		if (length < 5 || fileName[length-4] != '.') // a.bsp
		{
			continue;
		}

		if (fileName[length-3] == 'b' && fileName[length-2] == 's' && fileName[length-1] == 'p')
		{
			fileName[length-4] = 0;
			mapList.SetValue(fileName, false, false); // note: false for 'replace'
		}
		else if (fileName[length-3] == 'n' && fileName[length-2] == 'a' && fileName[length-1] == 'v')
		{
			fileName[length-4] = 0;
			mapList.SetValue(fileName, true, true); // note: true for 'replace'
		}
	}

	delete dir;

	// StringMap shenanigans are used so we don't call FileExists() 2000 times
	StringMapSnapshot snapshot = mapList.Snapshot();

	for (int i = 0; i < snapshot.Length; i++)
	{
		snapshot.GetKey(i, fileName, sizeof(fileName));

		bool hasNAV = false;
		mapList.GetValue(fileName, hasNAV);

		if (!hasNAV)
		{
			WriteNavMesh(fileName, true);
		}
	}

	delete snapshot;
	delete mapList;
}

stock bool ReadMapsFolderHandler(const char path[PLATFORM_MAX_PATH], bool is_stringmap, Handle data, bool lowercase, bool display, bool iter_subfolders, bool use_valve_fs, char[][] exclude_prefixes, int exclude_count)
{
	bool first_iteration = StrEqual(path, "maps");
	DirectoryListing dir = OpenDirectory(path, use_valve_fs, NULL_STRING);

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
