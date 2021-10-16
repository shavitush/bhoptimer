
enum
{
	ZF_ForceRender = (1 << 0),
	ZF_Prebuilt    = (1 << 1), // comes from mod_zone_* entities
};

#if 0
enum struct zone_cache_t
{
	bool bZoneInitialized;
	int iType;
	int iTrack; // 0 - main, 1 - bonus1 etc
	int iEntity;
	int iDatabaseID; // when ZF_Prebuilt, this is the entity's m_iHammerID
	int iFlags;
	int iData;
	float fCorner1[3];
	float fCorner2[3];
	float fDestination[3];
}
#else
enum struct zone_cache_t
{
	bool bZoneInitialized;
	bool bPrebuilt; // comes from mod_zone_* entities
	int iZoneType;
	int iZoneTrack; // 0 - main, 1 - bonus etc
	int iEntityID;
	int iDatabaseID;
	int iZoneFlags;
	int iZoneData;
}
#endif

native void Shavit_RemoveAllZones();

native int Shavit_GetZoneCount();

native void Shavit_GetZone(int index, any[] zonecache, int size = sizeof(zone_cache_t));

native int Shavit_AddZone(any[] zonecache, int size = sizeof(zone_cache_t));
