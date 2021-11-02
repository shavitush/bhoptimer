
#if defined _closestpos_included
 #endinput
#endif
#define _closestpos_included

methodmap ClosestPos < Handle {
	public native ClosestPos(ArrayList input, int offset=0, int startidx=0, int count=2147483647);
	public native int Find(float pos[3]);
};

public Extension __ext_closestpos =
{
	name = "ClosestPos",
	file = "closestpos.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
#if defined REQUIRE_EXTENSIONS
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_EXTENSIONS
public void __ext_closestpos_SetNTVOptional()
{
	MarkNativeAsOptional("ClosestPos.ClosestPos");
	MarkNativeAsOptional("ClosestPos.Find");
}
#endif
