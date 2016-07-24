// dynamic v0.0.15 by Neuro Toxin
// https://forums.alliedmods.net/showthread.php?t=270519
// https://github.com/ntoxin66/Dynamic/blob/master/scripting/include/dynamic.inc
#if defined _dynamic_included_
  #endinput
#endif
#define _dynamic_included_

#define INVALID_DYNAMIC_OBJECT			view_as<Dynamic>(-1)
#define INVALID_DYNAMIC_OFFSET			-1
#define DYNAMIC_MEMBERNAME_MAXLEN		64

enum Dynamic_MemberType
{
	DynamicType_Int = 0,
	DynamicType_Float = 1,
	DynamicType_String = 2,
	DynamicType_Object = 3,
	DynamicType_Bool = 4,
	DynamicType_Handle = 5,
	DynamicType_Vector = 6,
	DynamicType_Unknown = 7
}

typeset DynamicHookCB
{
	function void (Dynamic obj, int offset, const char[] member, Dynamic_MemberType type);
}

native int Dynamic_GetCollectionSize();

native Dynamic Dynamic_Initialise(int blocksize=64, int startsize=0);
native bool Dynamic_IsValid(int index, bool throwerror=false);
native bool Dynamic_Dispose(int index, bool disposemembers);

native bool Dynamic_SetName(Dynamic obj, const char[] objectname, bool replace);
native Dynamic Dynamic_FindByName(const char[] objectname);
native Dynamic Dynamic_GetParent(Dynamic obj);

native bool Dynamic_ReadConfig(Dynamic obj, const char[] path, bool use_valve_fs = false, int valuelength);
native bool Dynamic_WriteConfig(Dynamic obj, const char[] path, bool use_valve_fs = false);

native bool Dynamic_ReadKeyValues(Dynamic obj, const char[] path, bool use_valve_fs = false, int valuelength);
native bool Dynamic_WriteKeyValues(Dynamic obj, const char[] path, bool use_valve_fs = false);

native int Dynamic_GetMemberCount(Dynamic obj);
native int Dynamic_GetMemberOffset(Dynamic obj, const char[] membername);
native int Dynamic_GetMemberOffsetByIndex(Dynamic obj, int index);
native bool Dynamic_GetMemberNameByIndex(Dynamic obj, int index, char[] buffer, int size);
native bool Dynamic_GetMemberNameByOffset(Dynamic obj, int offset, char[] buffer, int size);
native Dynamic_MemberType Dynamic_GetMemberType(Dynamic obj, const char[] membername);
native Dynamic_MemberType Dynamic_GetMemberTypeByOffset(Dynamic obj, int offset);
native bool Dynamic_SortMembers(Dynamic obj, SortOrder order);

native int Dynamic_CallbackCount(Dynamic obj);
native bool Dynamic_HookChanges(Dynamic obj, DynamicHookCB callback);
native bool Dynamic_UnHookChanges(Dynamic obj, DynamicHookCB callback);

native int Dynamic_GetInt(Dynamic obj, const char[] membername, int defaultvalue=-1);
native int Dynamic_SetInt(Dynamic obj, const char[] membername, int value);
native int Dynamic_GetIntByOffset(Dynamic obj, int offset, int defaultvalue=-1);
native bool Dynamic_SetIntByOffset(Dynamic obj, int offset, int value);
native int Dynamic_PushInt(Dynamic obj, int value);
native int Dynamic_GetIntByIndex(Dynamic obj, int index, int defaultvalue=-1);

native float Dynamic_GetFloat(Dynamic obj, const char[] membername, float defaultvalue=-1.0);
native int Dynamic_SetFloat(Dynamic obj, const char[] membername, float value);
native float Dynamic_GetFloatByOffset(Dynamic obj, int offset, float defaultvalue=-1.0);
native bool Dynamic_SetFloatByOffset(Dynamic obj, int offset, float value);
native int Dynamic_PushFloat(Dynamic obj, float value);
native float Dynamic_GetFloatByIndex(Dynamic obj, int index, float defaultvalue=-1.0);

native bool Dynamic_GetString(Dynamic obj, const char[] membername, char[] buffer, int length);
native int Dynamic_SetString(Dynamic obj, const char[] membername, const char[] value, int length=0);
native bool Dynamic_GetStringByOffset(Dynamic obj, int offset, char[] buffer, int length);
native bool Dynamic_SetStringByOffset(Dynamic obj, int offset, const char[] value, int length=0);
native int Dynamic_PushString(Dynamic obj, const char[] value);
native bool Dynamic_GetStringByIndex(Dynamic obj, int index, char[] buffer, int length);
native int Dynamic_GetStringLength(Dynamic obj, const char[] membername);
native int Dynamic_GetStringLengthByOffset(Dynamic obj, int offset);

native Dynamic Dynamic_GetObject(Dynamic obj, const char[] membername);
native int Dynamic_SetObject(Dynamic obj, const char[] membername, Dynamic value);
native Dynamic Dynamic_GetObjectByOffset(Dynamic obj, int offset);
native bool Dynamic_SetObjectByOffset(Dynamic obj, int offset, Dynamic value);
native int Dynamic_PushObject(Dynamic obj, Dynamic value);
native Dynamic Dynamic_GetObjectByIndex(Dynamic obj, int index);
native bool Dynamic_SetObjectByIndex(Dynamic obj, int index, Dynamic value);

native bool Dynamic_GetBool(Dynamic obj, const char[] membername, bool defaultvalue=false);
native int Dynamic_SetBool(Dynamic obj, const char[] membername, bool value);
native bool Dynamic_GetBoolByOffset(Dynamic obj, int offset, bool defaultvalue=false);
native bool Dynamic_SetBoolByOffset(Dynamic obj, int offset, bool value);
native int Dynamic_PushBool(Dynamic obj, bool value);
native bool Dynamic_GetBoolByIndex(Dynamic obj, int index, bool defaultvalue=false);

native Handle Dynamic_GetHandle(Dynamic obj, const char[] membername);
native int Dynamic_SetHandle(Dynamic obj, const char[] membername, Handle value);
native Handle Dynamic_GetHandleByOffset(Dynamic obj, int offset);
native bool Dynamic_SetHandleByOffset(Dynamic obj, int offset, Handle value);
native int Dynamic_PushHandle(Dynamic obj, Handle value);
native Handle Dynamic_GetHandleByIndex(Dynamic obj, int index);

native bool Dynamic_GetVector(Dynamic obj, const char[] membername, float[3] vector);
native int Dynamic_SetVector(Dynamic obj, const char[] membername, const float[3] value);
native bool Dynamic_GetVectorByOffset(Dynamic obj, int offset, float[3] vector);
native bool Dynamic_SetVectorByOffset(Dynamic obj, int offset, const float[3] value);
native int Dynamic_PushVector(Dynamic obj, const float value[3]);
native bool Dynamic_GetVectorByIndex(Dynamic obj, int index, float[3] vector);

methodmap Dynamic
{
	public Dynamic(int blocksize=64, int startsize=0)
	{
		return Dynamic_Initialise(blocksize, startsize);
	}

	property int IsValid
	{
		public get()
		{
			return Dynamic_IsValid(view_as<int>(this), false);
		}
	}

	property Dynamic Parent
	{
		public get()
		{
			return Dynamic_GetParent(this);
		}
	}

	property int MemberCount
	{
		public get()
		{
			return Dynamic_GetMemberCount(this);
		}
	}

	public void Dispose(bool disposemembers=true)
	{
		Dynamic_Dispose(view_as<int>(this), disposemembers);
	}

	public bool SetName(const char[] objectname, bool replace=false)
	{
		return Dynamic_SetName(this, objectname, replace);
	}

	public static Dynamic FindByName(const char[] objectname)
	{
		return Dynamic_FindByName(objectname);
	}

	public bool ReadConfig(const char[] path, bool use_valve_fs = false, int valuelength = 256)
	{
		return Dynamic_ReadConfig(this, path, use_valve_fs, valuelength);
	}

	public bool WriteConfig(const char[] path)
	{
		return Dynamic_WriteConfig(this, path);
	}

	public bool ReadKeyValues(const char[] path, bool use_valve_fs = false, int valuelength = 256)
	{
		return Dynamic_ReadKeyValues(this, path, use_valve_fs, valuelength);
	}

	public bool WriteKeyValues(const char[] path)
	{
		return Dynamic_WriteKeyValues(this, path);
	}

	public static Dynamic GetSettings()
	{
		return view_as<Dynamic>(0);
	}

	public static Dynamic GetPlayerSettings(int client)
	{
		return view_as<Dynamic>(client);
	}

	public int GetInt(const char[] membername, int defaultvalue=-1)
	{
		return Dynamic_GetInt(this, membername, defaultvalue);
	}

	public int SetInt(const char[] membername, int value)
	{
		return Dynamic_SetInt(this, membername, value);
	}

	public int GetIntByOffset(int offset, int defaultvalue=-1)
	{
		return Dynamic_GetIntByOffset(this, offset, defaultvalue);
	}

	public void SetIntByOffset(int offset, int value)
	{
		Dynamic_SetIntByOffset(this, offset, value);
	}

	public int PushInt(int value)
	{
		return Dynamic_PushInt(this, value);
	}

	public int GetIntByIndex(int index, int defaultvalue=-1)
	{
		return Dynamic_GetIntByIndex(this, index, defaultvalue);
	}

	public bool GetBool(const char[] membername, bool defaultvalue = false)
	{
		return Dynamic_GetBool(this, membername, defaultvalue);
	}

	public int SetBool(const char[] membername, bool value)
	{
		return Dynamic_SetBool(this, membername, value);
	}

	public bool GetBoolByOffset(int offset, bool defaultvalue = false)
	{
		return Dynamic_GetBoolByOffset(this, offset, defaultvalue);
	}

	public void SetBoolByOffset(int offset, bool value)
	{
		Dynamic_SetBoolByOffset(this, offset, value);
	}

	public int PushBool(bool value)
	{
		return Dynamic_PushBool(this, value);
	}

	public bool GetBoolByIndex(int index, bool defaultvalue = false)
	{
		return Dynamic_GetBoolByIndex(this, index, defaultvalue);
	}

	public float GetFloat(const char[] membername, float defaultvalue=-1.0)
	{
		return Dynamic_GetFloat(this, membername, defaultvalue);
	}

	public int SetFloat(const char[] membername, float value)
	{
		return Dynamic_SetFloat(this, membername, value);
	}

	public float GetFloatByOffset(int offset, float defaultvalue=-1.0)
	{
		return Dynamic_GetFloatByOffset(this, offset, defaultvalue);
	}

	public void SetFloatByOffset(int offset, float value)
	{
		Dynamic_SetFloatByOffset(this, offset, value);
	}

	public int PushFloat(float value)
	{
		return Dynamic_PushFloat(this, value);
	}

	public float GetFloatByIndex(int index, float defaultvalue=-1.0)
	{
		return Dynamic_GetFloatByIndex(this, index, defaultvalue);
	}

	public bool GetString(const char[] membername, char[] buffer, int length)
	{
		return Dynamic_GetString(this, membername, buffer, length);
	}

	public int SetString(const char[] membername, const char[] value, int length=0)
	{
		return Dynamic_SetString(this, membername, value, length);
	}

	public int GetStringByOffset(int offset, char[] buffer, int length)
	{
		return Dynamic_GetStringByOffset(this, offset, buffer, length);
	}

	public void SetStringByOffset(const int offset, const char[] value, int length=0)
	{
		Dynamic_SetStringByOffset(this, offset, value, length);
	}

	public int PushString(const char[] value, int length)
	{
		return Dynamic_PushString(this, value);
	}

	public bool GetStringByIndex(int index, char[] buffer, int length)
	{
		return Dynamic_GetStringByIndex(this, index, buffer, length);
	}

	public int GetStringLength(const char[] membername)
	{
		return Dynamic_GetStringLength(this, membername);
	}

	public int GetStringLengthByOffset(int offset)
	{
		return Dynamic_GetStringLengthByOffset(this, offset);
	}

	public Dynamic GetObject(const char[] membername)
	{
		return Dynamic_GetObject(this, membername);
	}

	public int SetObject(const char[] membername, Dynamic value)
	{
		return Dynamic_SetObject(this, membername, value);
	}

	public Dynamic GetObjectByOffset(int offset)
	{
		return Dynamic_GetObjectByOffset(this, offset);
	}

	public void SetObjectByOffset(int offset, Dynamic value)
	{
		Dynamic_SetObjectByOffset(this, offset, value);
	}

	public int PushObject(Dynamic value)
	{
		return Dynamic_PushObject(this, value);
	}

	public Dynamic GetObjectByIndex(int index)
	{
		return Dynamic_GetObjectByIndex(this, index);
	}

	public bool SetObjectByIndex(int index, Dynamic value)
	{
		return Dynamic_SetObjectByIndex(this, index, value);
	}

	public Handle GetHandle(const char[] membername)
	{
		return Dynamic_GetHandle(this, membername);
	}

	public int SetHandle(const char[] membername, Handle value)
	{
		return Dynamic_SetHandle(this, membername, value);
	}

	public Handle GetHandleByOffset(int offset)
	{
		return Dynamic_GetHandleByOffset(this, offset);
	}

	public void SetHandleByOffset(int offset, Handle value)
	{
		Dynamic_SetHandleByOffset(this, offset, value);
	}

	public int PushHandle(Handle value)
	{
		return Dynamic_PushHandle(this, value);
	}

	public Handle GetHandleByIndex(int index)
	{
		return Dynamic_GetHandleByIndex(this, index);
	}

	public bool GetVector(const char[] membername, float[3] vector)
	{
		return Dynamic_GetVector(this, membername, vector);
	}

	public int SetVector(const char[] membername, const float[3] value)
	{
		return Dynamic_SetVector(this, membername, value);
	}

	public bool GetVectorByOffset(int offset, float[3] vector)
	{
		return Dynamic_GetVectorByOffset(this, offset, vector);
	}

	public void SetVectorByOffset(int offset, const float[3] value)
	{
		Dynamic_SetVectorByOffset(this, offset, value);
	}

	public int PushVector(const float value[3])
	{
		return Dynamic_PushVector(this, value);
	}

	public bool GetVectorByIndex(int index, float[3] vector)
	{
		return Dynamic_GetVectorByIndex(this, index, vector);
	}

	public void HookChanges(DynamicHookCB callback)
	{
		Dynamic_HookChanges(this, callback);
	}

	public void UnHookChanges(DynamicHookCB callback)
	{
		Dynamic_UnHookChanges(this, callback);
	}

	public int CallbackCount()
	{
		Dynamic_CallbackCount(this);
	}

	public int GetMemberOffset(const char[] membername)
	{
		return Dynamic_GetMemberOffset(this, membername);
	}

	public Dynamic_MemberType GetMemberType(int offset)
	{
		return Dynamic_GetMemberTypeByOffset(this, offset);
	}

	public bool GetMemberNameByIndex(int index, char[] buffer, int length)
	{
		return Dynamic_GetMemberNameByIndex(this, index, buffer, length);
	}

	public int GetMemberOffsetByIndex(int index)
	{
		return Dynamic_GetMemberOffsetByIndex(this, index);
	}

	public bool GetMemberNameByOffset(int offset, char[] buffer, int length)
	{
		return Dynamic_GetMemberNameByOffset(this, offset, buffer, length);
	}

	public bool SortMembers(SortOrder order = Sort_Ascending)
	{
		return Dynamic_SortMembers(this, order);
	}
}

#if !defined REQUIRE_PLUGIN
public __pl_dynamic_SetNTVOptional()
{
	MarkNativeAsOptional("Dynamic_Initialise");
	MarkNativeAsOptional("Dynamic_IsValid");
	MarkNativeAsOptional("Dynamic_Dispose");
	MarkNativeAsOptional("Dynamic_SetName");
	MarkNativeAsOptional("Dynamic_FindByName");
	MarkNativeAsOptional("Dynamic_GetParent");
	MarkNativeAsOptional("Dynamic_ReadConfig");
	MarkNativeAsOptional("Dynamic_WriteConfig");
	MarkNativeAsOptional("Dynamic_ReadKeyValues");
	MarkNativeAsOptional("Dynamic_WriteKeyValues");
	MarkNativeAsOptional("Dynamic_GetInt");
	MarkNativeAsOptional("Dynamic_SetInt");
	MarkNativeAsOptional("Dynamic_GetIntByOffset");
	MarkNativeAsOptional("Dynamic_SetIntByOffset");
	MarkNativeAsOptional("Dynamic_PushInt");
	MarkNativeAsOptional("Dynamic_GetIntByIndex");
	MarkNativeAsOptional("Dynamic_GetBool");
	MarkNativeAsOptional("Dynamic_SetBool");
	MarkNativeAsOptional("Dynamic_GetBoolByOffset");
	MarkNativeAsOptional("Dynamic_SetBoolByOffset");
	MarkNativeAsOptional("Dynamic_PushBool");
	MarkNativeAsOptional("Dynamic_GetBoolByIndex");
	MarkNativeAsOptional("Dynamic_GetFloat");
	MarkNativeAsOptional("Dynamic_SetFloat");
	MarkNativeAsOptional("Dynamic_GetFloatByOffset");
	MarkNativeAsOptional("Dynamic_SetFloatByOffset");
	MarkNativeAsOptional("Dynamic_PushFloat");
	MarkNativeAsOptional("Dynamic_GetFloatByIndex");
	MarkNativeAsOptional("Dynamic_GetString");
	MarkNativeAsOptional("Dynamic_SetString");
	MarkNativeAsOptional("Dynamic_GetStringByOffset");
	MarkNativeAsOptional("Dynamic_SetStringByOffset");
	MarkNativeAsOptional("Dynamic_PushString");
	MarkNativeAsOptional("Dynamic_GetStringByIndex");
	MarkNativeAsOptional("Dynamic_GetStringLength");
	MarkNativeAsOptional("Dynamic_GetStringLengthByOffset");
	MarkNativeAsOptional("Dynamic_GetObject");
	MarkNativeAsOptional("Dynamic_SetObject");
	MarkNativeAsOptional("Dynamic_GetObjectByOffset");
	MarkNativeAsOptional("Dynamic_SetObjectByOffset");
	MarkNativeAsOptional("Dynamic_PushObject");
	MarkNativeAsOptional("Dynamic_GetObjectByIndex");
	MarkNativeAsOptional("Dynamic_SetObjectByIndex");
	MarkNativeAsOptional("Dynamic_GetHandle");
	MarkNativeAsOptional("Dynamic_SetHandle");
	MarkNativeAsOptional("Dynamic_GetHandleByOffset");
	MarkNativeAsOptional("Dynamic_SetHandleByOffset");
	MarkNativeAsOptional("Dynamic_PushHandle");
	MarkNativeAsOptional("Dynamic_GetHandleByIndex");
	MarkNativeAsOptional("Dynamic_GetVector");
	MarkNativeAsOptional("Dynamic_SetVector");
	MarkNativeAsOptional("Dynamic_GetVectorByOffset");
	MarkNativeAsOptional("Dynamic_SetVectorByOffset");
	MarkNativeAsOptional("Dynamic_PushVector");
	MarkNativeAsOptional("Dynamic_GetVectorByIndex");
	MarkNativeAsOptional("Dynamic_GetCollectionSize");
	MarkNativeAsOptional("Dynamic_GetMemberCount");
	MarkNativeAsOptional("Dynamic_HookChanges");
	MarkNativeAsOptional("Dynamic_UnHookChanges");
	MarkNativeAsOptional("Dynamic_CallbackCount");
	MarkNativeAsOptional("Dynamic_GetMemberOffset");
	MarkNativeAsOptional("Dynamic_GetMemberOffsetByIndex");
	MarkNativeAsOptional("Dynamic_GetMemberType");
	MarkNativeAsOptional("Dynamic_GetMemberTypeByOffset");
	MarkNativeAsOptional("Dynamic_GetMemberNameByIndex");
	MarkNativeAsOptional("Dynamic_GetMemberNameByOffset");
	MarkNativeAsOptional("Dynamic_SortMembers");
}
#endif

public SharedPlugin __pl_dynamic =
{
	name = "dynamic",
	file = "dynamic.smx",
	#if defined REQUIRE_PLUGIN
		required = 1,
	#else
		required = 0,
	#endif
};
