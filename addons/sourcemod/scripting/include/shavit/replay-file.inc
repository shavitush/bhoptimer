/*
 * shavit's Timer - replay file stocks & format
 * by: shavit
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

#if defined _shavit_replay_file_included
	#endinput
#endif
#define _shavit_replay_file_included

// History of REPLAY_FORMAT_SUBVERSION:
// 0x01: standard origin[3], angles[2], and buttons
// 0x02: flags added movetype added
// 0x03: integrity stuff: style, track, and map added to header. preframe count added (unimplemented until later though)
// 0x04: steamid/accountid written as a 32-bit int instead of a string
// 0x05: postframes & fTickrate added
// 0x06: mousexy and vel added
// 0x07: fixed iFrameCount because postframes were included in the value when they shouldn't be
// 0x08: added zone-offsets to header
// 0x09: bumped with no actual file changes because time calculation in regards to offsets have been changed/fixed since it seems to have been using the end-zone-offset incorrectly (and should now be fine hopefully since 2021-12-21 / a146b51fb16febf1847657fba7ef9e0c056d7476)

#define REPLAY_FORMAT_V2 "{SHAVITREPLAYFORMAT}{V2}"
#define REPLAY_FORMAT_FINAL "{SHAVITREPLAYFORMAT}{FINAL}"
#define REPLAY_FORMAT_SUBVERSION 0x09

#define REPLAY_FRAMES_PER_WRITE 100 // amounts of frames to write per read/write call

enum struct replay_header_t
{
	char sReplayFormat[40];
	int iReplayVersion;
	char sMap[PLATFORM_MAX_PATH];
	int iStyle;
	int iTrack;
	int iPreFrames;
	int iFrameCount;
	float fTime;
	int iSteamID;
	int iPostFrames;
	float fTickrate;
	float fZoneOffset[2];
}

enum struct frame_t
{
	float pos[3];
	float ang[2];
	int buttons;
	// iReplayVersion >= 0x02
	int flags;
	MoveType mt;
	// Everything below is generally NOT loaded into memory for playback
	// iReplayVersion >= 0x06
	int mousexy; // `mousex | (mousey << 16)` // unpack with UnpackSignedShorts
	int vel; // basically `forwardmove | (sidemove << 16)` // unpack with UnpackSignedShorts
}

enum struct frame_cache_t
{
	int iFrameCount;
	float fTime;
	bool bNewFormat;
	int iReplayVersion;
	char sReplayName[MAX_NAME_LENGTH];
	int iPreFrames;
	ArrayList aFrames;
	// iReplayVersion >= 0x05
	int iPostFrames;
	float fTickrate;
	// blah blah not affected by iReplayVersion
	int iSteamID;
}

// Can be used to unpack frame_t.mousexy and frame_t.vel
stock void UnpackSignedShorts(int x, int out[2])
{
	out[0] =  ((x        & 0xFFFF) ^ 0x8000) - 0x8000;
	out[1] = (((x >> 16) & 0xFFFF) ^ 0x8000) - 0x8000;
}

stock bool LoadReplayCache(frame_cache_t cache, int style, int track, const char[] path, const char[] mapname)
{
	bool success = false;
	replay_header_t header;
	File fFile = ReadReplayHeader(path, header, style, track);

	if (fFile != null)
	{
		if (header.iReplayVersion > REPLAY_FORMAT_SUBVERSION)
		{
			// not going to try and read it
		}
		else if (header.iReplayVersion < 0x03 || (StrEqual(header.sMap, mapname, false) && header.iStyle == style && header.iTrack == track))
		{
			success = ReadReplayFrames(fFile, header, cache);
		}

		delete fFile;
	}

	return success;
}

stock bool ReadReplayFrames(File file, replay_header_t header, frame_cache_t cache)
{
	int total_cells = 6;
	int used_cells = 6;
	bool is_btimes = false;

	if (header.iReplayVersion > 0x01)
	{
		total_cells = 8;
		used_cells = 8;
	}

	// We have differing total_cells & used_cells because we want to save memory during playback since the latest two cells added (vel & mousexy) aren't needed and are only useful for replay file anticheat usage stuff....
	if (header.iReplayVersion >= 0x06)
	{
		total_cells = 10;
		used_cells = 8;
	}

	any aReplayData[sizeof(frame_t)];

	delete cache.aFrames;
	int iTotalSize = header.iFrameCount + header.iPreFrames + header.iPostFrames;
	cache.aFrames = new ArrayList(used_cells, iTotalSize);

	if (!header.sReplayFormat[0]) // old replay format. no header.
	{
		char sLine[320];
		char sExplodedLine[6][64];

		if(!file.Seek(0, SEEK_SET))
		{
			return false;
		}

		while (!file.EndOfFile())
		{
			file.ReadLine(sLine, 320);
			int iStrings = ExplodeString(sLine, "|", sExplodedLine, 6, 64);

			aReplayData[0] = StringToFloat(sExplodedLine[0]);
			aReplayData[1] = StringToFloat(sExplodedLine[1]);
			aReplayData[2] = StringToFloat(sExplodedLine[2]);
			aReplayData[3] = StringToFloat(sExplodedLine[3]);
			aReplayData[4] = StringToFloat(sExplodedLine[4]);
			aReplayData[5] = (iStrings == 6) ? StringToInt(sExplodedLine[5]) : 0;

			cache.aFrames.PushArray(aReplayData, 6);
		}

		cache.iFrameCount = cache.aFrames.Length;
	}
	else // assumes the file position will be at the start of the frames
	{
		is_btimes = StrEqual(header.sReplayFormat, "btimes");

		for (int i = 0; i < iTotalSize; i++)
		{
			if(file.Read(aReplayData, total_cells, 4) >= 0)
			{
				cache.aFrames.SetArray(i, aReplayData, used_cells);

				if (is_btimes && (aReplayData[5] & IN_BULLRUSH))
				{
					if (!header.iPreFrames)
					{
						header.iPreFrames = i;
						header.iFrameCount -= i;
					}
					else if (!header.iPostFrames)
					{
						header.iPostFrames = header.iFrameCount + header.iPreFrames - i;
						header.iFrameCount -= header.iPostFrames;
					}
				}
			}
		}
	}

	if (cache.aFrames.Length <= 10) // worthless replay so it doesn't get to load
	{
		delete cache.aFrames;
		return false;
	}

	cache.iFrameCount = header.iFrameCount;
	cache.fTime = header.fTime;
	cache.iReplayVersion = header.iReplayVersion;
	cache.bNewFormat = StrEqual(header.sReplayFormat, REPLAY_FORMAT_FINAL) || is_btimes;
	cache.sReplayName = "unknown";
	cache.iPreFrames = header.iPreFrames;
	cache.iPostFrames = header.iPostFrames;
	cache.fTickrate = header.fTickrate;
	cache.iSteamID = header.iSteamID;

	if (cache.iSteamID != 0)
	{
		FormatEx(cache.sReplayName, sizeof(cache.sReplayName), "[U:1:%u]", cache.iSteamID);
	}

	return true;
}

stock File ReadReplayHeader(const char[] path, replay_header_t header, int style = 0, int track = 0)
{
	replay_header_t empty_header;
	header = empty_header;

	File file = OpenFile(path, "rb");

	if (file == null)
	{
		return null;
	}

	char sHeader[64];

	if(!file.ReadLine(sHeader, 64))
	{
		delete file;
		return null;
	}

	TrimString(sHeader);
	char sExplodedHeader[2][64];
	ExplodeString(sHeader, ":", sExplodedHeader, 2, 64);

	strcopy(header.sReplayFormat, sizeof(header.sReplayFormat), sExplodedHeader[1]);

	if(StrEqual(header.sReplayFormat, REPLAY_FORMAT_FINAL)) // hopefully, the last of them
	{
		int version = StringToInt(sExplodedHeader[0]);

		header.iReplayVersion = version;

		// replay file integrity and PreFrames
		if(version >= 0x03)
		{
			file.ReadString(header.sMap, PLATFORM_MAX_PATH);
			file.ReadUint8(header.iStyle);
			file.ReadUint8(header.iTrack);

			file.ReadInt32(header.iPreFrames);

			// In case the replay was from when there could still be negative preframes
			if(header.iPreFrames < 0)
			{
				header.iPreFrames = 0;
			}
		}

		file.ReadInt32(header.iFrameCount);
		file.ReadInt32(view_as<int>(header.fTime));

		if (header.iReplayVersion < 0x07)
		{
			header.iFrameCount -= header.iPreFrames;
		}

		if(version >= 0x04)
		{
			file.ReadInt32(header.iSteamID);
		}
		else
		{
			char sAuthID[32];
			file.ReadString(sAuthID, 32);
			ReplaceString(sAuthID, 32, "[U:1:", "");
			ReplaceString(sAuthID, 32, "]", "");
			header.iSteamID = StringToInt(sAuthID);
		}

		if (version >= 0x05)
		{
			file.ReadInt32(header.iPostFrames);
			file.ReadInt32(view_as<int>(header.fTickrate));

			if (header.iReplayVersion < 0x07)
			{
				header.iFrameCount -= header.iPostFrames;
			}
		}

		if (version >= 0x08)
		{
			file.ReadInt32(view_as<int>(header.fZoneOffset[0]));
			file.ReadInt32(view_as<int>(header.fZoneOffset[1]));
		}
	}
	else if(StrEqual(header.sReplayFormat, REPLAY_FORMAT_V2))
	{
		header.iFrameCount = StringToInt(sExplodedHeader[0]);
	}
	else // old, outdated and slow - only used for ancient replays
	{
		// check for btimes replays
		file.Seek(0, SEEK_SET);
		any stuff[2];
		file.Read(stuff, 2, 4);

		int btimes_player_id = stuff[0];
		float run_time = stuff[1];

		if (btimes_player_id >= 0 && run_time > 0.0 && run_time < (10.0 * 60.0 * 60.0))
		{
			header.sReplayFormat = "btimes";
			header.fTime = run_time;

			file.Seek(0, SEEK_END);
			header.iFrameCount = (file.Position / 4 - 2) / 6;
			file.Seek(2*4, SEEK_SET);
		}
	}

	if (header.iReplayVersion < 0x03)
	{
		header.iStyle = style;
		header.iTrack = track;
	}

	if (header.iReplayVersion < 0x05)
	{
		header.fTickrate = (1.0 / GetTickInterval()); // just assume it's our own tickrate...
	}

	return file;
}

stock void WriteReplayHeader(File fFile, int style, int track, float time, int steamid, int preframes, int postframes, float fZoneOffset[2], int iSize, float tickrate, const char[] sMap)
{
	fFile.WriteLine("%d:" ... REPLAY_FORMAT_FINAL, REPLAY_FORMAT_SUBVERSION);

	fFile.WriteString(sMap, true);
	fFile.WriteInt8(style);
	fFile.WriteInt8(track);
	fFile.WriteInt32(preframes);

	fFile.WriteInt32(iSize - preframes - postframes);
	fFile.WriteInt32(view_as<int>(time));
	fFile.WriteInt32(steamid);

	fFile.WriteInt32(postframes);
	fFile.WriteInt32(view_as<int>(tickrate));

	fFile.WriteInt32(view_as<int>(fZoneOffset[0]));
	fFile.WriteInt32(view_as<int>(fZoneOffset[1]));
}

// file_a is usually used as the wr replay file.
// file_b is usually used as the duplicate/backup replay file.
stock void WriteReplayFrames(ArrayList playerrecording, int iSize, File file_a, File file_b)
{
	any aFrameData[sizeof(frame_t)];
	any aWriteData[sizeof(frame_t) * REPLAY_FRAMES_PER_WRITE];
	int iFramesWritten = 0;

	for(int i = 0; i < iSize; i++)
	{
		playerrecording.GetArray(i, aFrameData, sizeof(frame_t));

		for(int j = 0; j < sizeof(frame_t); j++)
		{
			aWriteData[(sizeof(frame_t) * iFramesWritten) + j] = aFrameData[j];
		}

		if(++iFramesWritten == REPLAY_FRAMES_PER_WRITE || i == iSize - 1)
		{
			if (file_a)
			{
				file_a.Write(aWriteData, sizeof(frame_t) * iFramesWritten, 4);
			}

			if (file_b)
			{
				file_b.Write(aWriteData, sizeof(frame_t) * iFramesWritten, 4);
			}

			iFramesWritten = 0;
		}
	}
}
