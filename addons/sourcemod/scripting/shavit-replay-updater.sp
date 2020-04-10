/*
 * shavit's Timer - Replay Bot Updater
 * by: KiD Fearless
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

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <convar_class>
#undef REQUIRE_EXTENSIONS
#include <dhooks>
#include <cstrike>
#include <tf2>
#include <tf2_stocks>

#undef REQUIRE_PLUGIN
#include <shavit>
#include <adminmenu>

#define REPLAY_FORMAT_V2 "{SHAVITREPLAYFORMAT}{V2}"
#define REPLAY_FORMAT_FINAL "{SHAVITREPLAYFORMAT}{FINAL}"
#define REPLAY_FORMAT_SUBVERSION 0x04
#define CELLS_PER_FRAME 8 // origin[3], angles[2], buttons, flags, movetype
#define FRAMES_PER_WRITE 100 // amounts of frames to write per read/write call

enum 
{
	ORIGIN_X,
	ORIGIN_Y,
	ORIGIN_Z,
	ANGLES_X,
	ANGLES_Y,
	BUTTONS,
	ENT_FLAGS,
	MOVE_TYPE
}

enum struct replaydata_t
{
	float origin[3];
	float angles[2];
	int buttons;
	// version >= 0x02
	int flags;
	MoveType movetype;
}

enum struct framecache_t
{
	int iFrameCount;
	float fTime;
	bool bNewFormat;
	int iReplayVersion;
	char sReplayName[MAX_NAME_LENGTH];
	int iPreFrames;
}

enum struct replay_t
{
	framecache_t cache;
	char sMap[160];
	int iStyle;
	int iTrack;
	ArrayList aFrames;
	int iAccount;
}

bool gB_Processed = false;

public void Shavit_OnStyleConfigLoaded(int styles)
{
	if(styles == -1)
	{
		styles = Shavit_GetStyleCount();
	}

	char folder[PLATFORM_MAX_PATH];
	Shavit_GetReplayBotFolder(folder, PLATFORM_MAX_PATH);

	for(int style = 0; style < styles; style++)
	{
		char path[PLATFORM_MAX_PATH];
		FormatEx(path, PLATFORM_MAX_PATH, "%s/%d", folder, style);

		DirectoryListing listing = OpenDirectory(path);

		if(listing == null)
		{
			ThrowError("shavit replay updater encountered a null directory");
			return;
		}

		char filename[PLATFORM_MAX_PATH];
		while(listing.GetNext(filename, PLATFORM_MAX_PATH))
		{
			if(filename[0] == '.')
			{
				continue;
			}

			File file = OpenFile(filename, "rb");
			if(file == null)
			{
				continue;
			}

			char sHeader[64];

			if(!file.ReadLine(sHeader, 64))
			{
				delete file;

				continue;
			}

			TrimString(sHeader);
			char sExplodedHeader[2][64];
			ExplodeString(sHeader, ":", sExplodedHeader, 2, 64);

			
			if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_FINAL))
			{
				int version = StringToInt(sExplodedHeader[0]);
				if(version < REPLAY_FORMAT_SUBVERSION)
				{
					UpdateCurrentReplayFormat(file, filename, version, style, track, path, pathlength);
				}
			}
			else if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_V2))
			{
				UpdateV2ReplayFormat(file, filename, version, style, track, path, pathlength);
			}
			else
			{
				UpdateOldReplayFormat();
			}

			delete listing;
		}

	}

	gB_Processed = true;
}

void UpdateCurrentReplayFormat(File file, char[] filename, int version, int style, int track, const char[] path)
{
	replay_t replay;
	
	// replay file integrity and PreFrames
	if(version >= 0x03)
	{
		file.ReadUint8(replay.iStyle);
		file.ReadUint8(replay.iTrack);
		file.ReadInt32(replay.cache.iPreFrames);
		file.ReadString(replay.sMap, 160);
	}
	else
	{
		int dot, slash;
		if(!GetDotsAndSlashes(filename, slash, dot))
		{
			delete file;
			return;
		}

		filename[dot] = '\0';
		strcopy(replay.sMap, 160, filename[slash+1]);

		replay.iStyle = style;
		replay.iTrack = track;
		replay.cache.iPreFrames = 0;
	}

	file.ReadInt32(replay.cache.iFrameCount);

	replay.aFrames = new ArrayList(sizeof(replaydata_t), replay.cache.iFrameCount);
	

	file.ReadInt32(view_as<int>(replay.cache.fTime));

	if(replay.cache.iReplayVersion >= 0x04)
	{
		file.ReadInt32(replay.iAccount);
	}
	else
	{
		char sAuthID[32];
		file.ReadString(sAuthID, 32);
		ReplaceString(sAuthID, 32, "[U:1:", "");
		ReplaceString(sAuthID, 32, "]", "");
		replay.iAccount = StringToInt(sAuthID);
	}

	int cells = CELLS_PER_FRAME;

	if(replay.cache.iReplayVersion == 0x01)
	{
		cells = 6;
	}

	any aReplayData[CELLS_PER_FRAME];

	for(int i = 0; i < replay.cache.iFrameCount; i++)
	{
		if(file.Read(aReplayData, cells, 4) >= 0)
		{
			replay.aFrames.SetArray(i, aReplayData, cells);
		}
	}

	delete file;

	UpdateReplay(replay, path);
}

void UpdateV2ReplayFormat(File file, char[] filename, int version, int style, int track, const char[] path)
{
	replay_t replay;

	replay.iStyle = style;
	replay.iTrack = track;
	replay.cache.iPreFrames = 0;
	
	int dot, slash;
	if(!GetDotsAndSlashes(filename, slash, dot))
	{
		delete file;
		return;
	}

	filename[dot] = '\0';
	strcopy(replay.sMap, 160, filename[slash+1]);

	replay.cache.iFrameCount = StringToInt(sExplodedHeader[0]);
	replay.aFrames = new ArrayList(sizeof(replaydata_t), replay.cache.iFrameCount);

	// TODO: Find solution to this
	replay.cache.fTime = 0.0;

	any aReplayData[6];

	for(int i = 0; i < iReplaySize; i++)
	{
		if(file.Read(aReplayData, 6, 4) >= 0)
		{
			replay.aFrames.SetArray(i, aReplayData, 6);
		}
	}

	delete file;

	UpdateReplay(replay, path);
}

void UpdateOldReplayFormat(File file, char[] filename, int version, int style, int track, const char[] path)
{
	replay_t replay;

	replay.iStyle = style;
	replay.cache.iPreFrames = 0;

	strcopy(replay.sMap, 160, "VALIDITY_BYPASS");

	replay.aFrames = new ArrayList(sizeof(replaydata_t));

	// TODO: Find solution to this
	replay.cache.fTime = 0.0;

	for(int i = 0; !file.EndOfFile(); i++)
	{
		file.ReadLine(sLine, 320);
		int iStrings = ExplodeString(sLine, "|", sExplodedLine, 6, 64);

		replay.cache.Resize(i + 1);
		replay.cache.Set(i, StringToFloat(sExplodedLine[0]), 0);
		replay.cache.Set(i, StringToFloat(sExplodedLine[1]), 1);
		replay.cache.Set(i, StringToFloat(sExplodedLine[2]), 2);
		replay.cache.Set(i, StringToFloat(sExplodedLine[3]), 3);
		replay.cache.Set(i, StringToFloat(sExplodedLine[4]), 4);
		replay.cache.Set(i, (iStrings == 6)? StringToInt(sExplodedLine[5]):0, 5);
	}

	replay.aFrames.iFrameCount = replay.aFrames.Length;

	delete file;

	UpdateReplay(replay, path);
}


bool UpdateReplay(replay_t replay, const char[] sPath)
{
	if(FileExists(sPath))
	{
		DeleteFile(sPath);
	}

	File fFile = OpenFile(sPath, "wb");
	fFile.WriteLine("%d:" ... REPLAY_FORMAT_FINAL, REPLAY_FORMAT_SUBVERSION);

	fFile.WriteString(replay.sMap, true);
	fFile.WriteInt8(replay.iStyle);
	fFile.WriteInt8(replay.iTrack);
	fFile.WriteInt32(replay.cache.iPreFrames);

	int iSize = replay.aFrames.Length;
	fFile.WriteInt32(iSize);
	fFile.WriteInt32(replay.cache.fTime);
	fFile.WriteInt32(replay.iAccount);

	any aFrameData[CELLS_PER_FRAME];
	any aWriteData[CELLS_PER_FRAME * FRAMES_PER_WRITE];
	int iFramesWritten = 0;

	for(int i = (preframes < 0 ? 0 : preframes); i < iSize; i++)
	{
		replay.aFrames.GetArray(i, aFrameData, CELLS_PER_FRAME);

		for(int j = 0; j < CELLS_PER_FRAME; j++)
		{
			aWriteData[(CELLS_PER_FRAME * iFramesWritten) + j] = aFrameData[j];
		}

		if(++iFramesWritten == FRAMES_PER_WRITE || i == iSize - 1)
		{
			fFile.Write(aWriteData, CELLS_PER_FRAME * iFramesWritten, 4);

			iFramesWritten = 0;
		}
	}

	delete fFile;
	delete replay.aFrames;
}

stock bool GetDotsAndSlashes(const char[] filename, int& slash = -1, int& dot = -1)
{
	int length = strlen(filename);

	for (int i = length - 1; i >= 0; i--)
	{
		if (filename[i] == '.')
		{
			dot = i;
		}
		else if(filename[i] == '/')
		{
			slash = i;
			return true;
		}
	}

	return dot != -1;
}