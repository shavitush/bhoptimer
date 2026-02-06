CHANGELOG.md file for bhoptimer -- https://github.com/shavitush/bhoptimer
Note: Dates are UTC+0.



# v4.?.? - ? - 2026-0?-?? - rtldg
¿



# v4.0.1 - The release that fixes one thing and didn't merge enough - 2026-02-06 - rtldg
[`v4.0.0...v4.0.1`](https://github.com/shavitush/bhoptimer/compare/v4.0.0...v4.0.1)

See [v4.0.0](https://github.com/shavitush/bhoptimer/releases/tag/v4.0.0) for more recent changes.

## Changes:
- fix native name typos and cement `Shavit_AlsoSaveReplayTo` https://github.com/shavitush/bhoptimer/commit/8d6e99262f1dbdcedade445d0ebc45f1a3ff5d80
	- shavit-replay-recorder creates the `Shavit_AlsoSaveReplayTo` native, but the header file had the name as `Shavit_AdditionalReplayPath`.
	`Shavit_AdditionalReplayPath` was probably what I intended to use but I don't remember.  The name is fine, so keeping it as `Shavit_AlsoSaveReplayTo` means less churn for other plugins.
	- Also makes sure the sucker is marked as optional for plugins that don't depend on bhoptimer but may want to use if available (e.g. for alt timers).



# v4.0.0 - The release that breaks things and didn't merge enough - 2026-01-31 - rtldg
[`v3.5.1...v4.0.0`](https://github.com/shavitush/bhoptimer/compare/v3.5.1...v4.0.0)

Release numbers went from v3.5.1 to v4.0.0 because I broke some replay-recording functions to provide a better API for [srcwr💾](https://github.com/srcwr/srcwrfloppy).

### If you use these plugins, then you will have to update them:
- https://github.com/offstyles/offstyle-plugins
- https://github.com/KawaiiClan/bhoptimer-savestate

### If you use these plugins, then don't update bhoptimer until these are updated:
- https://github.com/BoomShotKapow/shavit-myreplay
- https://github.com/sourcejump/plugin-database
	- https://github.com/sourcejump/plugin-database/pull/1

## Changes:
- gamedata
	- Update CSGO m_afButtonDisabled signature https://github.com/shavitush/bhoptimer/commit/309cdf3acf7dc91582370c7e13ca2f50c9fe910e
	- move `shavit-mapfixes.cfg` out of `configs/` and into `gamedata/` https://github.com/shavitush/bhoptimer/commit/3757b8482c6cf303d06f361d7f4576ec020abfac
		- Easier to update this way.
	- Update TF2 gamedata (untested) https://github.com/shavitush/bhoptimer/commit/72a23e665b1ff88d623fa0abaf3b803372d9d7d1
- bug fixes
	- shavit-stats.sp - fix error due to IsPlayerAlive() being called on disconnected client https://github.com/shavitush/bhoptimer/pull/1188 @mourningsickness https://github.com/shavitush/bhoptimer/commit/14b967496211dc598c09af470fd02759da9fab9d
	- shavit-checkpoints.sp - fix aFrames and iPreFrames not always being set https://github.com/shavitush/bhoptimer/pull/1244 @mourningsickness https://github.com/shavitush/bhoptimer/commit/466bcf62dfc4fd509b47f3968cf3a1d8c1751297
	- Fix savestates not enabling recording (found by happydez) https://github.com/shavitush/bhoptimer/commit/4f43b628ae1f1f923ceb518528de074b2c765966\
	- shavit-replay-playback.sp - fix error in case where style == -1 https://github.com/shavitush/bhoptimer/pull/1254 @mourningsickness https://github.com/shavitush/bhoptimer/commit/b1e8e1504346e9475b413b387b7ee06fb9414dc7
	- (IMPORTANT) Fix the on-ground 0.5s start-timer check which stops shit like "lowjumps" (thanks to PixeL for informing and testing)
		- Fix the on-ground 0.5s start-timer check from 89e97df https://github.com/shavitush/bhoptimer/commit/00feb624c2c78c94d2780ce694eff0226379f5d2
		- Fix the on-ground 0.5s start-timer even further dot dot dot https://github.com/shavitush/bhoptimer/commit/128940ff193e2b0ff22c6cc8eaa660e7b7883a6f
	- change RemoveFromString() to hopefully not access out of bounds memory (olivia ran into this) https://github.com/shavitush/bhoptimer/commit/beaaccda056f2695dc02dffa8274957d2bf2b039
	- Fix duped maps in !nominate when there are multiple end-zones https://github.com/shavitush/bhoptimer/pull/1256 @Awesomerly https://github.com/shavitush/bhoptimer/commit/5ca44fe4b732f0fed42353f355a9efdff9ec3857
	- Load all replay frame cells into memory instead of only 8 https://github.com/shavitush/bhoptimer/commit/9e82623a8f976362b187022191b77dceb24d9ad4
		- Requires you to recompile any savestate plugins.  Read the commit message for more details.
	- reset gB_InCheckpointMenu OnClientDisconnect https://github.com/shavitush/bhoptimer/pull/1263 @mourningsickness https://github.com/shavitush/bhoptimer/commit/f1d0af4a9ccfc02679e81cab5bea6f4686034a4c
	- Prevent `jointeam` from being too spammable https://github.com/shavitush/bhoptimer/commit/f6367934434b6b4e425a377d053d6307731ff1da
		- This doesn't fix any exploits but might help mitigate against people trying to crash the server.
- quality of life
	- shavit-replay-playback.sp - close replay menu on spawn (if it's open) https://github.com/shavitush/bhoptimer/pull/1247 @mourningsickness https://github.com/shavitush/bhoptimer/commit/c0d5efb3097b2adccedf41371b37fd630c20d53d
	- shavit-zones.sp - make it so slay/stoptimer zones don't apply if paused https://github.com/shavitush/bhoptimer/pull/1251 @mourningsickness https://github.com/shavitush/bhoptimer/commit/326caccb0640b53754b5acdacb39d995ee9a14f3
	- shavit-misc.sp - don't stop timer on tpto if paused with pause movement enabled https://github.com/shavitush/bhoptimer/pull/1249 @mourningsickness https://github.com/shavitush/bhoptimer/commit/0b0be25c78a1479e0dc16e855805607da31de948
	- prevent prac warning spam in start zone https://github.com/shavitush/bhoptimer/pull/1258 @normalamron https://github.com/shavitush/bhoptimer/commit/71c674663f1948c05cb36032dcc691a4c41d1b50
	- Reset players hp [only] when needed @xhaooy https://github.com/shavitush/bhoptimer/commit/21a7b58c82c98136fbdd43c13ba33090241642f5
	- Try to make some HUD translation strings & menu things clearer https://github.com/shavitush/bhoptimer/commit/460664fe8d5bbe0f4e1dc2a2578eef84ee04ebe7
	- Disable triggers while zoning https://github.com/shavitush/bhoptimer/commit/4e9c9abdf4b467dea3f2b9262dba1eca4932b567
- misc
	- Clarify shavit_replay_timelimit 0.0/disabled not recording replays https://github.com/shavitush/bhoptimer/commit/70308f3d6ac765d6b437984b4144ba3806a9a34f
	- Include eventqueuefixfix in release zips (only needed on Windows) https://github.com/shavitush/bhoptimer/commit/378a2eae700c218e1d2568c4ae83241009ca49e4
	- bump to v4.0.0 https://github.com/shavitush/bhoptimer/commit/8ceacc4d248cf20ac180eaae81513ae2b784614e
		- including this because it also added `SHAVIT_VERSION_MAJOR`, `SHAVIT_VERSION_MINOR`, and `SHAVIT_VERSION_PATCH` which can be used in ifdefs now.
	- fix comment on `Shavit_OnTimeIncrementPost` https://github.com/shavitush/bhoptimer/commit/317169dfda5ff00f972aa04a403fc04dae5d6fd4
- features
	- add !worldrecord/!wr aliases (!serverrecord/!sr) (#1257)  https://github.com/shavitush/bhoptimer/pull/1257 @mourningsickness https://github.com/shavitush/bhoptimer/commit/7d3913bc3e52ef8249ad6733af70d767a2257230
	- Add tier selection menu to mapsleft and mapsdone menus (with "All" option, for current functionality) https://github.com/shavitush/bhoptimer/pull/1262 @mourningsickness https://github.com/shavitush/bhoptimer/commit/a350d7982ca92c0ebf592d4d2040432c2677ff5e
	- Make it easier to change the max tier https://github.com/shavitush/bhoptimer/commit/7cbb25054126f7bf331fb2f70ceb77525774decf
		- Some servers like to raise the max tier. This requires editing the code. Now with another plugin: you can set `shavit_rankings_default_tier`'s upper bounds and then blah blah. Not really tested though.
	- shavit-hud.sp - add perf% to center hud https://github.com/shavitush/bhoptimer/pull/1259 @mourningsickness https://github.com/shavitush/bhoptimer/commit/133c4e5b125fa942159fcadbe792982e2a6fe13f
	- shavit_core_pause_movement - add extra 2 cvars for pause https://github.com/shavitush/bhoptimer/pull/1250 @normalamron https://github.com/shavitush/bhoptimer/commit/7502325be87d0c5db17a9cc0475b27aced4bc8ae
	- Prioritize extend/dontchange/reroll for a tied vote https://github.com/shavitush/bhoptimer/pull/1265 https://github.com/shavitush/bhoptimer/commit/cceba51a00e6a2b0f29dbbd3136a87a996d82b2c
		- Adds `smc_mapvote_prioritize_special` (1 by default) to toggle this behavior.
	- [srcwr💾](https://github.com/srcwr/srcwrfloppy)
		- What: sourcemod extension (.dll/.so) to write replays with a background thread.
		- Why: reduces lag when people finish a run.
		- What this breaks:
			- `Shavit_ShouldSaveReplayCopy`, `Shavit_OnReplaySaved`, and `WriteReplayFrames`.
			- Why: poor API with the `makeCopy` params etc, and by changing it: we can write replays for third-party plugins (like https://github.com/BoomShotKapow/shavit-myreplay)
		- All the commits:
			- Use an extension to save replays asynchronously https://github.com/shavitush/bhoptimer/pull/1253 https://github.com/shavitush/bhoptimer/commit/16ccd0cc7ca2942baf3130b298c8ce57b5d236c5
			- https://github.com/shavitush/bhoptimer/commit/d08a3078e14abccd776e33f99351b54589c67427
			- https://github.com/shavitush/bhoptimer/commit/f14cbf5aff899e1d012e760b8a6a39c4184d7653
			- https://github.com/shavitush/bhoptimer/commit/871c67deac43356194897979ab953cfd38906140
			- https://github.com/shavitush/bhoptimer/commit/0ebfa900b9468c6413ebf10b61dd35cc27d20e34
			- add `Shavit_AdditionalReplayPath`, edit & rename `Shavit_ShouldSaveReplayCopy` to `Shavit_AddAdditionalReplayPathsHere`, edit `Shavit_OnReplaySaved`, edit `WriteReplayFrames`, and make compatible with srcwr💾 v4.0.0 https://github.com/shavitush/bhoptimer/commit/eb079a6d1e508069bdb2d9a375de2826cdb62b63



# v3.5.1 - small things - 2025-06-24 - rtldg
[`v3.5.0...v3.5.1`](https://github.com/shavitush/bhoptimer/compare/v3.5.0...v3.5.1)

- fix olivia's name in the author lists https://github.com/shavitush/bhoptimer/commit/f0ccf6dc0aa45aa72d7c428d5c8866aae28467e4
- shavit-wr.sp - add back buttons to !delete menus (QoL) https://github.com/shavitush/bhoptimer/commit/877b71aa4d8a7735ee0eec189dd0ef6a72249180 @mourningsickness @rtldg
- Keep all menus open forever https://github.com/shavitush/bhoptimer/commit/bb09568d9797b61b1a0cd290b56545f8a928b8e8
	- a few that were missed in a pass a couple years ago



# v3.5.0 - too much, too little, and too late - 2025-06-06 - rtldg
[`v3.4.2...v3.5.0`](https://github.com/shavitush/bhoptimer/compare/v3.4.2...v3.5.0)
this is too dense and unreadable. I'm sorry...

- random things
	- move around the absolute minimum time (0.11s) stuff https://github.com/shavitush/bhoptimer/commit/2dbb211742124484f4a420c61b4511b2c5f16b38
	- fix wrong variable used in `LessStupidGetMapDisplayName` (relevant for tf2 & csgo) https://github.com/shavitush/bhoptimer/commit/afa6b07da8e7540277ada3a85895da2c1395aed3
	- reset sv_enablebunnyhopping & sv_airaccelerate flags for late loading https://github.com/shavitush/bhoptimer/pull/1187 @xhaooy https://github.com/shavitush/bhoptimer/commit/830ebc1b734ef08bba99980c6caf7e5c963cb7c7
	- reset hp on restart https://github.com/shavitush/bhoptimer/pull/1187 @xhaooy https://github.com/shavitush/bhoptimer/commit/9eceb51ea6ce4700087d329dd4ffc409641ea0f3
	- fix showing 100% perf with no jumps on scroll @Nairdaa https://github.com/shavitush/bhoptimer/commit/a4c214c981c2feadd21f64bbd8737e0dc8bf8c04
	- fix some native definition & optional api things https://github.com/shavitush/bhoptimer/commit/9210b84d50cd69f39189651cb39aa7a37fe5098d
	- add note about `startinair` (the style setting) https://github.com/shavitush/bhoptimer/commit/86b36436df45f0c6ee26ee8c95676956fb722f7f
	- note for `autostrafe` (the style setting) option 4 / basic autostrafer https://github.com/shavitush/bhoptimer/compare/v3.4.2...master
	- round up fractional ticks when calculating finish time https://github.com/shavitush/bhoptimer/commit/afdf236fe95fd62bd03cab906949a896eea2666b
	- Godmode fix for DMG_CRUSH and point_hurt https://github.com/shavitush/bhoptimer/pull/1188 @azalty https://github.com/shavitush/bhoptimer/commit/ca609714106e3747644e4f618191f9f08846de86
	- fix hsw sync @Nairdaa https://github.com/shavitush/bhoptimer/commit/5a0b8c2df5c700e16c8b846e92583824b9a2a13e
	- get the shavit_misc_prespeed 1&&>=3 working again with the on-ground timer https://github.com/shavitush/bhoptimer/commit/309aa7a189c6a3c695985c91f633a462a327c337
	- add `bhop_wasd` to `shavit-mapfixes.cfg` https://github.com/shavitush/bhoptimer/commit/60c4f399f1101c08bb02b66b5650dc3c4c7e3ede
	- use correct gravity for LG https://github.com/shavitush/bhoptimer/pull/1197 @lilac1337 https://github.com/shavitush/bhoptimer/commit/f9bb0a39f8d60af13564af54ff305de7dd982c2e
		- the default LG style in bhoptimer has always been `"gravity" "0.6"` but btimes used 0.5 and a lot of people switch to 0.5 so this is just "fixing" the default in bhoptimer...
	- stripper cfg touchups https://github.com/shavitush/bhoptimer/commit/9b96f9dffdb71d0b144960c397d16a5ec2e40264
		- make all the filters use more normalized structures so that one sourcepawn stripper replacement can parse these files...
	- add jumpstats to readme https://github.com/shavitush/bhoptimer/pull/12007 @enimmy https://github.com/shavitush/bhoptimer/commit/835678d816e19d70df3aa9079d0145c93f2a6af8
	- add backwards hsw sync https://github.com/shavitush/bhoptimer/pull/1194 @Nairdaa https://github.com/shavitush/bhoptimer/commit/c2dbf6d779fb52d0a373bddd7e5431159657c302
	- drop support for sourcemod 1.10 https://github.com/shavitush/bhoptimer/commit/16a927cd9149cbae8b4694500f41dda5973a3134
		- Remove dhooks include file https://github.com/shavitush/bhoptimer/pull/1208 @Awesomerly https://github.com/shavitush/bhoptimer/commit/659d70af247de53bbfe8544cf80fc5f93f3f8429
	- use style runspeed instead of m_flMaxspeed for tas (and autoprestrafe) https://github.com/shavitush/bhoptimer/commit/3609adf2aa76fa84209d6f53d69eb067d554d3df
		- (autoprestrafe is broken on 250 runspeed otherwise...)
	- add a note for `a_or_d_only` in `shavit-styles.cfg` https://github.com/shavitush/bhoptimer/commit/2a23c058538a162f9d7cffdec90270c817a62482
	- document some API structs https://github.com/shavitush/bhoptimer/commit/fee7df2919455fdb5d2ffee9112287ec5e426702
	- Clarify logic for testing writeability with faketestfile_69.replay https://github.com/shavitush/bhoptimer/pull/1217 @Nairdaa https://github.com/shavitush/bhoptimer/commit/1b676441975267a629948efc9479acda3cc1325f
	- do something to not error on negative `sv_friction` and negative `sv_accelerate` https://github.com/shavitush/bhoptimer/commit/187bd2c97541503bcf5421770f7baf040b6000ef
		- like on `bhop_ins_mariooo`
	- fix some colors in advertisement messages not working https://github.com/shavitush/bhoptimer/commit/ad48aa3345878fab54d785980f0be656677a68e3
	- check & use `sv_autobunnyhopping` even if the game is not CS:GO (and it's in CS:S as of the 2025-02-18 update! Thank you @misyltoad) https://github.com/shavitush/bhoptimer/commit/94ebb97c79f0ff71dd7115ac6626d86e162df1a7
	- other gamedata stuff for 2025-02-18 update: https://github.com/shavitush/bhoptimer/pull/1226 https://github.com/shavitush/bhoptimer/commit/90a6714bebfc384055401032f396c1f82fb996d4
		- Make sure MaybeDoPhysicsUntouch() is called in ProcessMovementPost https://github.com/shavitush/bhoptimer/pull/1226/commits/2c093bb02d4ad99c3ca378426ce5ba96deed0767
	- swap sm_p to sm_noclip in shavit_misc_noclipme description https://github.com/shavitush/bhoptimer/pull/1230 @lilac1337 https://github.com/shavitush/bhoptimer/commit/78f55f9a1a9c9ca94bd9128c6294737f30933b57
	- add shavit_misc_unnocliponrestart to disable noclip on restart https://github.com/shavitush/bhoptimer/pull/1232 @mourningsickness https://github.com/shavitush/bhoptimer/commit/2726865399e9a25689f000600816fbc8070ec28b
	- Add FirstLogin to database and profile https://github.com/shavitush/bhoptimer/pull/1234 @mourningsickness https://github.com/shavitush/bhoptimer/commit/3d0cd963195e55e836e71028b28c469d5e4fff0a
		- Make firstlogin pull from old runs if possible https://github.com/shavitush/bhoptimer/commit/158edbe15880228cb393d0a9f4f5f2f27fbaa767
			- follow up commit to fix my bad sql https://github.com/shavitush/bhoptimer/commit/b29cc54d0b2285f0f10d502d262c6adf945296b1
	- Mark Steam Datagram Relay IPs https://github.com/shavitush/bhoptimer/commit/983a3c8e747cbf8104ab90f9477824ac803e2a6c
		- (shows "Steam Datagram Relay" for the player's country if that's how they last connected)
	- fix: prevent unnecessary jump when using !r or switching to TAS (brought to attention by @akanora) https://github.com/shavitush/bhoptimer/commit/7e1c3f0dc31b79a093da1995d40888a890da9cef
	- shavit-chat - fix chat messages near (or at) max length overflowing into a broken message https://github.com/shavitush/bhoptimer/pull/1241 @mourningsickness https://github.com/shavitush/bhoptimer/commit/49105001d3fbcec5060689f3b28a4816ff3e2340
		- this increases the user chat message buffer size
- menu & hud things
	- save `!wr` menu record page for back button https://github.com/shavitush/bhoptimer/commit/9423ef79add10b5d48e64eb1a90e845d781b9906
	- timeleft hud - show seconds starting at 150s https://github.com/shavitush/bhoptimer/commit/3a1e6a60cd810089ee0b4db37e99c0ad6c0e031b
	- untested In Start/End zone speed removal if !hud removed speed... https://github.com/shavitush/bhoptimer/commit/f6fdd7b0aa46bb09b64cc20a156f13b75208109d
	- increase menu-input blocker time https://github.com/shavitush/bhoptimer/commit/e8ff7fe66315395e61ec6697f5c427f38e00e5f2
		- this is the thing that's used when you have a checkpoint menu open and then a mapvote comes up, for example
	- add keyhint forwards and forceUpdate https://github.com/shavitush/bhoptimer/pull/1201 @enimmy https://github.com/shavitush/bhoptimer/commit/d57ec73adb70ad5ece0a688f71cd54619a57883d
	- allow the !recentrecords menu to be sorted by style https://github.com/shavitush/bhoptimer/commit/4652e36cc66b5296d91f6d4e2a22aff7c1459016
	- fix error spam from PR #1201 https://github.com/shavitush/bhoptimer/commit/23fa606920707c99749474653a5588e6681bf423
	- add player PB to !style menu https://github.com/shavitush/bhoptimer/pull/1239 @mourningsickness https://github.com/shavitush/bhoptimer/commit/b1a2f064327906f2ca063d807603309ed5015c74
- checkpoint things
	- Make sure CSS uses the ladder checkpoint stuff https://github.com/shavitush/bhoptimer/commit/c2a9017810d5df1a185d665d31e482a4a476d9cc
		- this also changes the checkpoint struct size because we need to save some internal ladder variables the engine uses
		- ALWAYS include this (so third-party plugins don't have to be rebuilt sometimes) https://github.com/shavitush/bhoptimer/commit/2013968f1c1970e380b77259389191a927d9da91
	- save m_afButtonDisabled & m_afButtonForced in checkpoints (mainly for player_speedmod) https://github.com/shavitush/bhoptimer/commit/bf5ec55a6a008d5d24c7aa8b8782b9c8f5f19b00
		- this makes kz_bhop_genkai a bit more bearable at times
		  this also isn't perfect since restarting doesn't reset them
		- csgo gamedata https://github.com/shavitush/bhoptimer/commit/d93ed2881620cc5263703a60da9c8cec8c3ed05b
	- Prevent gB_ForceJump when teleporting to a checkpoint in the start zone https://github.com/shavitush/bhoptimer/pull/1240 @akanora https://github.com/shavitush/bhoptimer/commit/cd4f1c924860ebdd0e9f2d3fa6a5f68886349a91
- zones things
	- make `shavit_zones_box_offset` a bool (which also affects height offset) & correct TF2 bounding box values https://github.com/shavitush/bhoptimer/pull/1179 @jedso https://github.com/shavitush/bhoptimer/commit/f7ff341131c09119f078124717a6f95b0d631e57
		- <details><summary>Summary</summary>
			Previously with offsets:
			- Zone is 62/2 units raised off the "ground".
			- Zone is 62/2 units shorter than the beams showed.
			Previously without offsets:
			- Zone is 62/2 units raised off the "ground".
			- Zone is 62/2 units shorter than the beams showed.
			Now with offsets:
			- Zone is 62/2 units raised off the "ground".
			- Zone is 62/2 units shorter than the beams showed.
			Now without offsets:
			- Zone is 0 units raised off the "ground".
			- Zone is 0 units shorter than the beams showed.
		</details>
	- wip shavit-zones-json stuff
		- https://github.com/shavitush/bhoptimer/commit/7a81b44655742864cdc2b9dc3eaffedbcc21bb8a
		- https://github.com/shavitush/bhoptimer/commit/9cf9d7ff27b4cb97b02b6f827cf27a1619502912
		- https://github.com/shavitush/bhoptimer/commit/12d7e5590d6c3b99562d4151bb4d66b05a61b4ba
		- https://github.com/shavitush/bhoptimer/commit/5fec9a2fe11439894bfae7e7f1f4eca0b67420cb
		- https://github.com/shavitush/bhoptimer/commit/960484585df68b60fa5b5026869074c6d6f82b4b
		- `!editmi` https://github.com/shavitush/bhoptimer/commit/62d508705fddfe9e72490b1cff76a0822c089204
	- make `ZF_Origin` store floats with decimals instead of as hexadecimal https://github.com/shavitush/bhoptimer/commit/2bcd20fac7903368b7d6c03768cbb383f8453a9d
		- (this is for hooking triggers/etc as a zone via origin/position)
	- fix stale zone cache entries being checked, preventing start/end zone placement sometimes https://github.com/shavitush/bhoptimer/commit/b468f9d67ab0598e62b1e7123ba14c31af19c5ee
	- fix `RecalcHighestStage` typo https://github.com/shavitush/bhoptimer/commit/7bd954880a3de396ab55a0bf6fb7508df6a11818 @Haze1337
	- Add teleport to stage start command https://github.com/shavitush/bhoptimer/pull/1207 @Awesomerly https://github.com/shavitush/bhoptimer/commit/2805cd94c631909946f994aadda4bbaedd5dd2ea
		- only works on maps that start with `surf_` right now....... very ksf-esque thing....
		- `!teleport` is added as an alias for `!tele`
		- `!rs` / `!stagerestart` / `!restartstage`
		- part 2: Make stage restart command take player to beginning in end zone https://github.com/shavitush/bhoptimer/pull/1215 @Awesomerly https://github.com/shavitush/bhoptimer/commit/4465e53d3b38e9efe0e4263270b54156992d8b5e
		- part 3: add `shavit_zones_enable_stage_restart` & make `!stagerestart` send you to startzone if your timer is stopped https://github.com/shavitush/bhoptimer/commit/da78976c56aedf2851156d35a51faca5edae13e6
	- force `sv_enablebunnyhopping 1` in Custom Speed Limit zones (for `_strafe`); make AirAccelerate & Custom Speed Limit zones check the player's track https://github.com/shavitush/bhoptimer/pull/1212 https://github.com/shavitush/bhoptimer/commit/7aca8755a4beab088788ed57dde22aef47cf6a07
		- part 2: fix bad casts that broke Custom Airaccelerate & Custom Speed Limit zones https://github.com/shavitush/bhoptimer/commit/ee0fe65b01b7fd616092f3b2998123480dc2dca2
	- Add no-jump and autobhop zones https://github.com/shavitush/bhoptimer/pull/1216 @Awesomerly https://github.com/shavitush/bhoptimer/commit/c9cfbefa277b703529f47d3e64106cd5fca4c1fe
		- some fixes https://github.com/shavitush/bhoptimer/commit/8ecc2a78290942325fcc5a8742a2c0261450a4ce
	- probably fix `exact_time_int` deprecation issue https://github.com/shavitush/bhoptimer/issues/1218 https://github.com/shavitush/bhoptimer/commit/e41ba9fa9525a808a54807ff0e0c4593fa8c3027
		- part 2: edit the DeprecateExactInt sql error handling a bit for https://github.com/shavitush/bhoptimer/commit/9434dc943866b3891dd18ea936e1e35e156c6f94
	- Add new zone types to hookzone menu https://github.com/shavitush/bhoptimer/pull/1221 @Awesomerly https://github.com/shavitush/bhoptimer/commit/7c8002557416e909d430709cf05e551129258f3b
	- unbreak sourcemod 1.12 builds https://github.com/shavitush/bhoptimer/commit/17e60114a4847f2b4bf27354f04a5e32f936d82f https://github.com/shavitush/bhoptimer/commit/54c04a0219650760165e1d0c119c85131cee3c5b https://github.com/shavitush/bhoptimer/commit/2dd385a8eb3f0eafe367ccfc93409035acb81079
	- make `!beamer` more reliable and stuck in walls less (if at all!) @rumourA https://github.com/shavitush/bhoptimer/commit/2bbb3865f8785b3d8ddbf93b9cb83e78ed625ae6
		- I love `!beamer` so much. I lie in bed and think about `!beamer`.
	- Make `func_rot_button` entities hookable just like `func_button` https://github.com/shavitush/bhoptimer/commit/04ad339fe81deb97fbb3880290d24e4891f526e0 https://github.com/shavitush/bhoptimer/commit/f54775044ccae66ad7a14948bc1a4eb11b0b676c
	- Fix not being able to overlap bonus+main endzones https://github.com/shavitush/bhoptimer/commit/420c8e02ea4c2520ad0d73eed2b8b9649379f265
	- Startzone speed limit flexibility https://github.com/shavitush/bhoptimer/pull/1219 @Awesomerly https://github.com/shavitush/bhoptimer/commit/354c2445c28b4a926fa516b1ae2299660c96f0ca
		- adds the "maxprestrafe" style key (& adds shavit_misc_prespeed 6):
		  "The max prestrafe that still allows your timer to start/restart. You generally do *not* need or want to change this unless for surf things (combined with style-setting "prespeed_type" "6" or cvar "shavit_misc_prespeed 6"). Default is 0.0 (disabled)."
	- fix shavit-zones cvar change callback errors (found by caliph) https://github.com/shavitush/bhoptimer/commit/0151ace718c8256b5f16ef39e6fcfd0a03d41765
- replay things
	- make salvage replay-files have frame-count in filename https://github.com/shavitush/bhoptimer/commit/1f8461f64b54cd03533b0deacc5285c17e55e00c
	- add `!specbot` to shavit-misc as an alias for `!spec` https://github.com/shavitush/bhoptimer/commit/bb49da4d9c12ede5929be933726ea783a77c4b85
	- make replay-frames resize failures *not* kill the server https://github.com/shavitush/bhoptimer/commit/3757993e5095085eb09eeaa2991a4337e08c436b
	- don't eat non-timer bot/fakeclient names - for nuko https://github.com/shavitush/bhoptimer/commit/4bbef8aa61f0d8e8059c0eee56c29f46cbeec153
	- use `bot_add` / `tf_bot_add` instead of the gamedata to call stuff 'BotAddCommand' things https://github.com/shavitush/bhoptimer/commit/5814a7c3d87d9139b5970994d1b2b53a94fa5f14
		- This was the only option for TF2 because Valve updated the compiler and now a lot of functions are inlined when they previously weren't and trying to hack things back with assembly patches is a nightmare.
		- part 2 (for CS:S & CS:GO too) https://github.com/shavitush/bhoptimer/commit/6751aa323b8bdeb9ff7a1bb5e96a8899ef7a0863
	- Allow updating replay bot name without being a WR https://github.com/shavitush/bhoptimer/pull/1209 @BoomShotKapow https://github.com/shavitush/bhoptimer/commit/654f9aa2392f7a2ee039083d0ca104fe96bcce4f
		- "This allows editing the replay bot's name through the frame_cache_t of the replay data, which is useful for personal replays. Without this change, the replay bot's name after calling Shavit_StartReplayFromFrameCache would be the current WR's player name."
		- More specifically: this is useful for personal-replay plugins and such.
	- shavit-replay-playback: hook triggers on late-load https://github.com/shavitush/bhoptimer/commit/e35e83584190bc63acc8e3a8edb175946c71375e
		- reloading shavit-replay-playback would mean bots would touch triggers
	- fix errors with looping replay bots that use disabled styles https://github.com/shavitush/bhoptimer/commit/feeb4ae445885064357c7f8265e0be381ea33c44
- rankings things
	- sqlite shavit-rankings support (& `GetWeightedPoints` deprecation) https://github.com/shavitush/bhoptimer/pull/1183 https://github.com/shavitush/bhoptimer/commit/787aa8ff346b378f2a2b068d51c136529ed34b1c
		- make sure it logs POW support for older Sourcemod versions (< 1.12) https://github.com/shavitush/bhoptimer/commit/fee8edeedafc417f5b413b0e8a1aadbf17c1e42d
	- fix a point recalculation query that was doing the wrong checks in a WHERE statement https://github.com/shavitush/bhoptimer/commit/7fb0f45c2c75714b4192f48e4b7ea030b0f9b5a9
	- fix database version parsing https://github.coim/shavitush/bhoptimer/pull/1222 @Awesomerly https://github.com/shavitush/bhoptimer/commit/e5976001cfb3b51f4e0517a51c17c723089f53af
- mapchooser things
	- fix maplist clearing after sm ReadMapList fix (I can't remember what the sm ReadMapList fix was, sorry) https://github.com/shavitush/bhoptimer/commit/888b4be951f73f5b93262be17046dc231d756a05
	- add map reroll to shavit-mapchooser https://github.com/shavitush/bhoptimer/pull/1184 @MicrowavedBunny https://github.com/shavitush/bhoptimer/commit/e4c58dd952d8cd4d41b6b3919fc5561bf3e8a875
	- fix maplist type 3 not clearing maps list https://github.com/shavitush/bhoptimer/commit/79c307fea80fcf918d221ad5c52e677e362cd58a
	- stop that random map change thing https://github.com/shavitush/bhoptimer/commit/d69bd1840745481c1b6980313651128f60f11ca0
		- something to do with rtv'ing *again* right before the map changes?
	- dumb https://github.com/shavitush/bhoptimer/pull/1195 @Nairdaa https://github.com/shavitush/bhoptimer/commit/c6c38b0816aa1f2f673fb11fefdc307485db3d0e
	- fixups for mapchooser nominate menu after sqlite support was added to shavit-rankings https://github.com/shavitush/bhoptimer/commit/66c730a897df94ec0d30703f4005e1596ae63107
	- make it grab tiers even if not mysql https://github.com/shavitush/bhoptimer/commit/b150073754a0a1c1098ff484bbb2e9a5e5600cec
- tf2 things
	- fix jump counter & shavit_core_blockprejump (still kind of fucky) https://github.com/shavitush/bhoptimer/commit/fefb0ffe6f680401b0547c3b624d1b1c1628db7b
	- silence tf_bot_count change notification https://github.com/shavitush/bhoptimer/commit/f1bea169d24e321d97c6b5bff22d4bc5ddc2c86d
	- only check for 'jointeam spectate' so we don't break the class menu popup https://github.com/shavitush/bhoptimer/commit/a6da4358de06937b095dcafd79050e4ea937844a
	- fix 0vel underwater & hook PreventBunnyJumping (still kind of fucky) https://github.com/shavitush/bhoptimer/commit/a7e3fe517cb355829a9f9979ca490e6a8ba6dbb6
	- update gamedata for tf2 vscript update https://github.com/shavitush/bhoptimer/commit/06bce65bcc03ed225091350099fc852674928761
	- fix tf2 Windows PhysicsCheckForEntityUntouch signature https://github.com/shavitush/bhoptimer/commit/e19f069a8c7cb1032f452634a2b6850661b8c401
	- don't let tf2 bots duck on surf ramps. it makes the spec view look fucky https://github.com/shavitush/bhoptimer/commit/31fcd7ecb5cdc03487e0e8a1f35cc983eb145de7
	- wip tf2 stuff post 2024-04-18 https://github.com/shavitush/bhoptimer/commit/7ce6233cf4e91f9cb52d3a184aac5c3a6328a1aa
	- working PreventBunnyJumping on Windows https://github.com/shavitush/bhoptimer/commit/5421c6006a18e562a5691a5b77d62b4be49dc6bc
	- fix error when you spawn and the observer target is a camera or something https://github.com/shavitush/bhoptimer/commit/9876d4c3db39829825bf45abad41bdca2672f240
- csgo things
	- update CSGO Windows MaintainBotQuota signature https://github.com/shavitush/bhoptimer/commit/83293832fd5bf77732a8d6568cf21267f28b035a
	- Update m_surfaceFriction signature for CSGO Linux https://github.com/shavitush/bhoptimer/commit/91f05dfbf9bbf33b439bc894222291020ab59248
	- update steamid-stocks to handle 64-bit ids on csgo https://github.com/shavitush/bhoptimer/commit/412812693f78cac7fa8a2146d3ebb52715e1cfd9
	- hopefully working csgo linux gamedata 2023-02-03 https://github.com/shavitush/bhoptimer/commit/7728c640bf7ecb6adcb4400b560961cb6237de7f
	- csgo linux gamedata 2023-02-03 v2 https://github.com/shavitush/bhoptimer/commit/2a254a32a1b7ed852ff5f476a8d321ce17a07b76



# v3.4.2 - Long overdue edition (Extended Director's Cut) - 2022-10-17 - rtldg
[`v3.4.1...v3.4.2`](https://github.com/shavitush/bhoptimer/compare/v3.4.1...v3.4.2)
https://github.com/shavitush/bhoptimer/releases/tag/v3.4.2

Bug fix release for v3.4.0 / v3.4.1. See the changelogs here: https://github.com/shavitush/bhoptimer/releases/tag/v3.4.0
https://github.com/shavitush/bhoptimer/releases/tag/v3.4.1

- mark `SteamWorks_SetHTTPRequestAbsoluteTimeoutMS` as optional in `shavit-zones-http` https://github.com/shavitush/bhoptimer/commit/f16b9aa7f3f9f5c19ec4fa1a71109811eaac1b73
- faster mysql query for the deprecate `exact_time_int` stuff (and more migration logging) https://github.com/shavitush/bhoptimer/commit/07727e1db08e1a8047de488d0ebb720ab35b7b55
	- the transaction batches turned out to be REALLY slow



# v3.4.1 - Long overdue edition (Director's Cut) - 2022-10-16 - rtldg
[`v3.4.0...v3.4.1`](https://github.com/shavitush/bhoptimer/compare/v3.4.0...v3.4.1)
https://github.com/shavitush/bhoptimer/releases/tag/v3.4.1
https://github.com/shavitush/bhoptimer/commit/d0d3c62ff56e64d5909592381e86ab6fe4e36023

Bug fix release for v3.4.0. See the changelog for v3.4.0 here: https://github.com/shavitush/bhoptimer/releases/tag/v3.4.0

- fix leaderboard times from mysql not parsing correctly (after the deprecation of exact_time_int in v3.4.0 https://github.com/shavitush/bhoptimer/commit/894b039e4ea0d599c2d32252d391c377c58f1bfd) https://github.com/shavitush/bhoptimer/commit/4fee1e4cc193a51f84447e585809017f1261c061
	- Mysql returns formatted floats with commas when it's >=1000 (like `2,095.12345123`). The comma makes `DBResultSet.FetchFloat` (`atof` internally) return `2` instead of `2095.12345123`.
- potentially fix segmented replay saving edge case & add some error logging if replay files can't be opened for writing https://github.com/shavitush/bhoptimer/commit/5ac888c3a0b20926e7b362a212217164519b5365



# v3.4.0 - Long overdue edition - 2022-10-14 - rtldg
[`v3.3.2...v3.4.0`](https://github.com/shavitush/bhoptimer/compare/v3.3.2...v3.4.0)
https://github.com/shavitush/bhoptimer/releases/tag/v3.4.0
https://github.com/shavitush/bhoptimer/commit/3db30bea9877bd69851efb9dde6b1a70a063d721

**Note: Release includes [eventqueuefix 1.3.1](https://github.com/hermansimensen/eventqueue-fix/pull/21) which works with Sourcemod 1.10/1.11 Windows/Linux**

Thanks to all the contributors who pushed this release along by making PRs which made me feel guilty for slacking.

- 😵‍💫 fixed broken implementation of `shavit_misc_bad_setlocalangles_fix` https://github.com/shavitush/bhoptimer/commit/e322606492cc2955dfd52415cb70432845f8fb1b
- added something to draw which zone axis is being edited https://github.com/shavitush/bhoptimer/commit/1c82605db50e3ded7dc31756be52eb2be16ec43a https://github.com/shavitush/bhoptimer/commit/ea8f14fa07874a700acd0782b247018abfb8d28a
- removed admin requirement for debug targetname hud setting https://github.com/shavitush/bhoptimer/commit/68a57b912341b9f02e8ce3b48b05773b58771d8c
- fixed `shavit_misc_noweapondrops` on TF2 https://github.com/shavitush/bhoptimer/pull/1160 @jedso https://github.com/shavitush/bhoptimer/commit/578636d52875a9a10bc1f857853032ebb6da57ba
- use a signature instead of netprop+offset to find surface friction used by shavit-tas https://github.com/shavitush/bhoptimer/pull/1158 @NukoOoOoOoO https://github.com/shavitush/bhoptimer/commit/21c62040623681431a8658ccfa412059646e9cd7
- fix the `velocity_limit` style setting being avoidable with +duck spam (mainly practical on auto + velocity_limit styles...) https://github.com/shavitush/bhoptimer/commit/5fc891d6fa2ac39ebbe8933e97a9ad4119a3900f
- added chat typo handler for `1r` -> `!r` & `1b` -> `!b` https://github.com/shavitush/bhoptimer/commit/bdea5036979b2868c93f826ae43010b9ac63cd04
- remove the steamid verification kick thing in OnClientPutInServer https://github.com/shavitush/bhoptimer/issues/1047 @BoomShotKapow https://github.com/shavitush/bhoptimer/commit/b78ae36a0ef72d15620d2b18017bbff18d41b9fc
- save tier list position in !nominate menu https://github.com/shavitush/bhoptimer/commit/864b46379b667dd6c1fc59059cce003d4238b934
- fix `shavit_stats_use_mapchooser` not being compatible with workshop maps https://github.com/shavitush/bhoptimer/issues/1168 https://github.com/shavitush/bhoptimer/commit/3d16f5ffa74fb72a9d1ef25c5c13790d1089c4c8 https://github.com/shavitush/bhoptimer/commit/a1a1c6adfa594968cc1f6df35f650ce06bef5fd5
- add translation for `!extend` & update `m_iRoundTime` https://github.com/shavitush/bhoptimer/pull/1172 @MSWS https://github.com/shavitush/bhoptimer/commit/f4cd4e9e6adce239e7574691531f6ce85fe32d81
- add `!autorestart` https://github.com/shavitush/bhoptimer/pull/1170 @MSWS https://github.com/shavitush/bhoptimer/commit/e3aab46e0157fadedc0532cd3cd27f4b0283bc95 https://github.com/shavitush/bhoptimer/commit/fdbbc11d2ad9e165a956180d3c7cc4addfc8ed37
- set forwardmove & sidemove on replay bots because why not https://github.com/shavitush/bhoptimer/commit/b115726abb6d800c8557d56af3435e3a94dafe0d
- make the autostage thing start at 1. starting at 2 was dumb https://github.com/shavitush/bhoptimer/commit/5ccd0efd0415f91c59d29f03c296c5d8f9f8fb24
- deprecate `exact_time_int` https://github.com/shavitush/bhoptimer/commit/894b039e4ea0d599c2d32252d391c377c58f1bfd https://github.com/shavitush/bhoptimer/commit/87c2b1e4368b7553ff5495a681dd566c54c57732 https://github.com/shavitush/bhoptimer/commit/236829cc333ca4adff2f461a4223de167b619ac9 https://github.com/shavitush/bhoptimer/commit/7a79fc03e8b67e737155f6cdd1c976c90a46f5c6 https://github.com/shavitush/bhoptimer/commit/fd687dd2d70525861a513cae96c52670ecb37983
- readd foreign keys to playertimes from users table https://github.com/shavitush/bhoptimer/issues/1175 https://github.com/shavitush/bhoptimer/pull/1176 @jedso https://github.com/shavitush/bhoptimer/pull/1176/commits
	- relevant https://github.com/shavitush/bhoptimer/commit/e4f2d35f6c7d4b9ca0442e431c29630458c7fe18 https://github.com/shavitush/bhoptimer/commit/2b2a1fcb12dd8efa5ef9501adbf15cef9d0458fc
- recreate mapzones table on sqlite with proper incrementing id https://github.com/shavitush/bhoptimer/pull/1177 @jedso https://github.com/shavitush/bhoptimer/pull/1177/commits
- show timer in hud when started (prespeeding) in start zone https://github.com/shavitush/bhoptimer/pull/1174 @lilac1337 https://github.com/shavitush/bhoptimer/commit/b868208520219746638e554bdc84b6ceb6010319
- mark ripext natives as optional in `shavit-zones-http.sp` https://github.com/shavitush/bhoptimer/commit/8eefcd5b68173abfb86c3ee909009a576e7cf8a8
- filter invalid maps in `!map`, `!nominate`, and map votes (to hopefully help with https://github.com/shavitush/bhoptimer/issues/1178) https://github.com/shavitush/bhoptimer/commit/09c0d228b4e1c89d9b746c3d36d1d12bf2091d46
- followup for ccname & chat rank bugs again https://github.com/shavitush/bhoptimer/commit/783fd4f0a7ee492c13e7c316394fc59c426616aa



# v3.3.2 - bug fixes 2 📲 👙 🍌 ⛩ 🕗 🖋 🐰 🚨 🐂 😘 - 2022-07-20 - rtldg
[`v3.3.1...v3.3.2`](https://github.com/shavitush/bhoptimer/compare/v3.3.1...v3.3.2)
https://github.com/shavitush/bhoptimer/releases/tag/v3.3.2
https://github.com/shavitush/bhoptimer/commit/e76ab45a55ab630b26852c47f87bcde6347806a5

- some czones bugfixes
	- fixed bonus 1 using the same settings as main (bug since 3.3.0) https://github.com/shavitush/bhoptimer/commit/684ade8dd9014b0e354b559afaafd3cb80699d7a
	- fixed czone cookies when using mysql but reverting all the fun space saving stuff https://github.com/shavitush/bhoptimer/commit/1e7459a6c4da93a0082d67053949e5076b17ca51
- made the !editzone adjust menu not have multiple pages https://github.com/shavitush/bhoptimer/commit/bf25061444437fb769b74a35693e92c648cce5c7
- some random things & doc updates https://github.com/shavitush/bhoptimer/commit/898c46379dc958f743088251369133cfa0f18c54 @BoomShotKapow https://github.com/shavitush/bhoptimer/commit/7878784887a6a2c9a07cd01d105c2ddf7b58c30c
	- also only increases strafe count when not-on-ground now
- added `bhop_avantasia` to mapfixes to set `rngfix_triggerjump 0` because of one of the roofs with the ac units or whatever they are @lilac1337 https://github.com/shavitush/bhoptimer/commit/cec78050472402b212b8361d4eb5697987460410
- made looping replay bots spawn on different ticks to hopefully help the people who get the occasional script execution timeout https://github.com/shavitush/bhoptimer/commit/f703aca4d6ccaad1a2a875979ea1dc8f964455d4



# v3.3.1 - bug fixes 🥤 - 2022-07-11 - rtldg
[`v3.3.0...v3.3.1`](https://github.com/shavitush/bhoptimer/compare/v3.3.0...v3.3.1)
https://github.com/shavitush/bhoptimer/releases/tag/v3.3.1
https://github.com/shavitush/bhoptimer/commit/5ba8ede632258ff3b0855ef792dce5369bec62da

A release for all the bugs that cropped up for the zones stuff & for the ccname thing.

I did make releases for a couple (v3.3.0-2 through v3.3.0-4) but that was sloppy versioning and then I was too busy to make a release with more of the bug fixes...

~~**Eventqueuefix note:** the release zip includes a version for Sourcemod 1.10 & for Sourcemod 1.11. The 1.11 version comes from @BoomShotKapow https://github.com/hermansimensen/eventqueue-fix/commit/ce28b301a3d187a96f9c437e81d9d5deefee2fd5. More info here https://github.com/hermansimensen/eventqueue-fix/issues/19. It's needs more testing according to @hermansimensen so feel free to help :)~~ nevermind

- fixed a couple of ccname bugs that came from v3.3.0 https://github.com/shavitush/bhoptimer/commit/0360b957e46ac46866313f9d7a97d6dc5635c208 https://github.com/shavitush/bhoptimer/commit/d78393f0842241ca78abc964629e8d14ae1debfb
- split mapzones form & target migration so the query can be compatible with sqlite https://github.com/shavitush/bhoptimer/commit/6dc1fb66e4a559ec397575956431dc617ad6f9ae
- `!addspawn` broke after `zones wip pr` so https://github.com/shavitush/bhoptimer/commit/bdfa61e3f9fb53f96531d76819d8f45a105ab4d2
- added `a_or_d_only` style setting so you can have a single merged style for a-only & d-only if you want https://github.com/shavitush/bhoptimer/commit/64bd95a73b8f6a64680df139ef8f8f9fa48fccbd https://github.com/shavitush/bhoptimer/commit/7e44264f13168934ba031e7d15159992f469ddd3 (https://github.com/shavitush/bhoptimer/pull/1150)
- reverted a change made to the `!top` query so we have the pretty commas separators again https://github.com/shavitush/bhoptimer/commit/1449b9b3d58f097a80ce802b0a9e783c4f1f7ea1
- added a menu for `!deletesetstart` https://github.com/shavitush/bhoptimer/commit/8900e4b6ff4d3d52575ae26df43fa4db52b64fe6
- fixed zones not deleting from the database if you create then delete them without reloading the map https://github.com/shavitush/bhoptimer/commit/fb42a370fe3ed28130f8bea0ff4cd82d6e191d94 https://github.com/shavitush/bhoptimer/commit/4ac0b4da5df1e01a5d5fef0fb834d57e2debe14c
- fixed zones sometimes not being created on maps that autohook buttons & other prebuilt zones https://github.com/shavitush/bhoptimer/commit/0f7360f3749b8920c494d5fc37e0b5edfd77bca9
- don't draw zone boxes around hooked buttons https://github.com/shavitush/bhoptimer/commit/27ec578c7d79200a1e66d014af761de156ef88cc
- added hooking by origin (`ZF_Origin` zone flag) & fixed a lot of broken button stuff https://github.com/shavitush/bhoptimer/commit/5c14dfcc60bff4a2306d86349fcc4a5f85c8ff42
	- really should've used a different struct member for `ZF_Origin/ZF_Hammerid` instead of using flags but whatever :^)
- made shavit-mapchooser not break if shavit-rankings throws errors about a sqlite db (https://github.com/shavitush/bhoptimer/issues/1149) https://github.com/shavitush/bhoptimer/commit/a778908e32473bdd852dee1227766ea8d87cf5cf
	- this is more of a bandaid until I make shavit-rankings queries for sqlite & postgresql (https://github.com/shavitush/bhoptimer/issues/1148)



# v3.3.0 - zone stuff & bloat - 2022-06-28 - rtldg
[`v3.2.0...v3.3.0-3`](https://github.com/shavitush/bhoptimer/compare/v3.2.0...v3.3.0-3)
https://github.com/shavitush/bhoptimer/releases/tag/v3.3.0
https://github.com/shavitush/bhoptimer/commit/1a86a2b643a324b38b648ffeeed83c1c19e30b6f
https://github.com/shavitush/bhoptimer/releases/tag/v3.3.0-3
https://github.com/shavitush/bhoptimer/commit/8aad5e6f005cc73408191ced645017df175a163f

**Note:** Contributors and more copyright attributions were added to files and plugins mostly by skimming through git blame. If a name was missed or should be added/removed, please let me know (also the ordering of names was pretty random)

Edit: bhoptimer-v3.3.0-2.zip = includes https://github.com/shavitush/bhoptimer/commit/0360b957e46ac46866313f9d7a97d6dc5635c208
Edit: bhoptimer-v3.3.0-3.zip = includes https://github.com/shavitush/bhoptimer/commit/6dc1fb66e4a559ec397575956431dc617ad6f9ae
Edit: bhoptimer-v3.3.0-4.zip = includes https://github.com/shavitush/bhoptimer/commit/bdfa61e3f9fb53f96531d76819d8f45a105ab4d2

## zone stuff
- main commits https://github.com/shavitush/bhoptimer/commit/e3aac2d24efc239cf8bc6d1296f0ede031b7f0b1 https://github.com/shavitush/bhoptimer/commit/4315221b86889c65c2b35d9d07bf3241e4c57315
- new cvars:
	- `shavit_zones_usesql`: Whether to automatically load zones from the database or not. If you're using standardized zones from some source with `shavit-zones-http`, then you'd change this cvar to `0` for example.
	- `shavit_zones_useprebuilt`: Whether to automatically hook `trigger_multiple` zones like `climb_zone*` and `mod_zone*`.
	- `shavit_zones_usebuttons`: Whether to automatically hook `climb_*` buttons...
- you can now hook trigger_multiples, func_buttons, and trigger_teleports by their hammerids or by `targetname` (trigger_multiple/func_button) / `target` (trigger_teleport).
	- trigger_teleports should usually be hooked by hammerid because hooking by target is a bit iffy.
	- there's a menu that shows all the hookable things and the player's distance to them. also a menu option to hook the thing the player is looking at...
	- oh yeah, it's `sm_hookzone` and also in the Timer Commands menu
- `shavit-zones-http.sp` added. maybe sourcejump can use it or something.
	- this plugin is also a good example of how to use the new APIs for adding zones from other plugins.
	- The dependencies & headers (sm-json & ripext) for this plugin are not included in the bhoptimer repo. You'll have to retrieve them yourself for now if you intend to compile this.
- zone points are now be normalized (sql migration and when sending to db). corner1 turns into the zone mins and corner2 turns into the maxs.
- a `"speed"` zone config thing was added for zones. you can add this key to `shavit-zones.cfg` to make zone beam textures move.
- api and stuff:
	- `zone_cache_t` is now usable for adding zones from other plugins.
		- forward `Shavit_LoadZonesHere()` is where you should add `zone_cache_t`'s from other plugins
	- removed `Shavit_GetStageZone()` as it doesn't work well with multiple stage zones.
	- added `Shavit_ReloadZones()`, `Shavit_UnloadZones()`, `Shavit_GetZoneCount()`, `Shavit_GetZone()`, `Shavit_AddZone()`, and `Shavit_RemoveZone()`
	- `MAX_ZONES` 64->128. `MAX_STAGES` 51->69.

## everything else
- added an option to use an duplicate other players' checkpoints (https://github.com/shavitush/bhoptimer/pull/1142) @sh4hrazad https://github.com/shavitush/bhoptimer/commit/487e3db9d09d704b67f66e928fcd36adfd990abf
	- You can toggle this with `shavit_checkpoints_useothers` (default: 1)
	- new parameters added to `Shavit_OnTeleportPre`, `Shavit_OnTeleport`, `Shavit_OnSavePre`, `Shavit_OnSave`, `Shavit_OnCheckpointMenuSelect`, and `Shavit_TeleportToCheckpoint`
- changed czone settings to let all zone types be configurable. made the settings for bonuses apply to every bonus https://github.com/shavitush/bhoptimer/commit/ab73e36a15bc426f4edeec13b8d44e8dffacd522
- added `Zone_Speedmod` so oblivious could have fun bonuses https://github.com/shavitush/bhoptimer/commit/acf47a11b1aa10ceaaaa1555e58611efca452098
	- avoid putting these inside of entites that trigger a map's `player_speedmod` because they'll probably override each other randomly
	- also gravity zones should show the gravity amount in zone edit menus now
- added the `!maprestart` & `!mapreload` aliases https://github.com/shavitush/bhoptimer/commit/a23348d843b623183aa3538ad67be6e9d5ee4446
- add csgo stripper:source configs for `workshop/2117675766/bhop_craton`, `workshop/1195609162/bhop_bless`, and `workshop/859067603/bhop_bless` https://github.com/shavitush/bhoptimer/commit/d816423eb69c1c199d1034b39e7412ad94abe17f
	- also a config for a shit `mod_zone_start` on `bhop_n0bs1_css` was added
- added `ent_fire` to cheat commands list since it can be used on csgo https://github.com/shavitush/bhoptimer/commit/bc62b92983f829e84c7f1c06af37b237dc0214ae
- added `HUD_SPECTATORSDEAD` / !hud option `Spectator list (only when dead)` to hide the spectators list when you're alive because people spectating me makes me nervous 😵‍💫 https://github.com/shavitush/bhoptimer/commit/22a68b491b659702284bf40575b9055416f4c9a5
- added `shavit_core_hijack_teleport_angles` (temporary?) TODO description https://github.com/shavitush/bhoptimer/commit/53463d8fb9a3d058d4c938c3bbf4d23882cc133a
- added an option to toggle the basic autostrafer on the autogain/velocity/oblivious autostrafer thing https://github.com/shavitush/bhoptimer/commit/c2e50761ec4cb085e3a66391a8517ccedcbb9e09
	- +`Shavit_SetAutogainBasicStrafer`, +`Shavit_GetAutogainBasicStrafer`, `sm_autogainbss`, `+/-autogainbss`
- slay zones were changed slightly so the player-killer has a 100% success rate..... but make it only slay if the timer is running https://github.com/shavitush/bhoptimer/commit/96ef03e458c5de59e52ac3dbf9f0ff862d8e9652
- made the !wr menu also print steamids to chat like the !profile menu does https://github.com/shavitush/bhoptimer/commit/7dddfe25f3e6a440fb3d584767592107210cbd3d
- added sm_beamer https://github.com/shavitush/bhoptimer/commit/d8a9dd7d7b73ad9c36788e48b85b1c968fe96010
- added `shavit_misc_bad_setlocalangles_fix` for CS:S/TF2. fixes some `func_rotating` things that stop rotating https://github.com/shavitush/bhoptimer/commit/79baadf54152fd3a817dbf34bf957c5d2472a661
- the player's current value from `player_speedmod`s is now reset to 1.0 on timer start. this shouldn't affect many things but it does help on `deathrun_steam_works` https://github.com/shavitush/bhoptimer/commit/8f11f9aaf157037f41607da0e7d9bd5a7157fe07
	- open an issue or join the discord if you encounter any problems with this please.
- fixed the `Timer Commands` admin menu category disappearing or being wiped when some bhoptimer plugins are reloaded https://github.com/shavitush/bhoptimer/commit/09917f91d97320afad9227798bbcd3b9184be8be
- `!ccmsg off` and `!ccname off` were changed slightly ||i can't remember what the difference is now|| https://github.com/shavitush/bhoptimer/commit/bfa9aa45e421353af0ff83e15ef1bab9e4a2e57a
- fixed some flag & admin checks for shavit-chat ranks when reloading or removing admin from people https://github.com/shavitush/bhoptimer/commit/41f50505f9dd1df6b4238997f45a5918883e99e5 https://github.com/shavitush/bhoptimer/commit/affac70f99ce069d5c4fe9cba4a98b7628407000
- added buttons, scrolls, and anglediff to `huddata_t` https://github.com/shavitush/bhoptimer/commit/8e0e5ec8c1b551f802fac23db04546e06b4dfc86
- added back button to admin command menus https://github.com/shavitush/bhoptimer/commit/7c251ef81dd95418947388126e026177e94c98ca
- sqlite now automatically runs migrations too https://github.com/shavitush/bhoptimer/commit/fa6ccdbdedf1b3008ab4fe32adac338e059fd3ff
- added `shavit_core_log_sql` and removed `Database2`/`Transaction2` methodmap nonsense https://github.com/shavitush/bhoptimer/commit/0f44dd1710c24ad97f2f0f6eb9aa562ea85baf24
- added an auto stage zone numbering thing for https://github.com/shavitush/bhoptimer/issues/1147 https://github.com/shavitush/bhoptimer/commit/d922cebf976ce0467cb362a0561981e323c16a6a
	- first stage thing is given `2`... I'm not really sure what I want to do for this...
- playtime saving sql queries from disconnecting players are now buffered & grouped into a transaction. so instead of on map change spamming like 12 queries, with the delay between queries for each, the timer will now just have to send one transaction to hopefully help with some slight sql query blockage on map change... https://github.com/shavitush/bhoptimer/commit/fa28502a0d796a403ad68217f39ad4cf441e8819
- added `shavit_replay_disable_hibernation` for CS:S. https://github.com/shavitush/bhoptimer/commit/9cbed1972be081ca404bb64c404913590493d618
- fixed `permission` style setting typo that came from the v3.1.0 release https://github.com/shavitush/bhoptimer/commit/1a03bdac13bbdb12fc0bbf21e7652b31b181ab31
- updated tf2 gamedata for the 2022-06-21 update https://github.com/shavitush/bhoptimer/commit/178d42e2fdb5768d9c94af785a5e35e378f9e0a5
- added some code to help deal with different sql db drivers. should help with porting queries to sqlite (shavit-rankings) & postgresql (sm 1.11) https://github.com/shavitush/bhoptimer/commit/448652888092705dfe3f3d3ee251ec9d993f41d5



# v3.2.0 - checkpoints & resettargetname stuffffff - 2022-04-27 - rtldg
[`v3.1.3...v3.2.0`](https://github.com/shavitush/bhoptimer/compare/v3.1.3...v3.2.0)
https://github.com/shavitush/bhoptimer/releases/tag/v3.2.0
https://github.com/shavitush/bhoptimer/commit/7c842afdf05e6c9b37174d7b1d6e21d685f6ce57

Lots of checkpoint API changes and also lots of changes to how the `shavit_misc_resettargetname` family works.

**Protip: If you don't have `eventqueuefix` on your server then you're going to suffer** through booster exploits & other broken shit.

**Update shavit-mapfixes.cfg every release.** It wasn't ever explicitly mentioned in release notes so I'll put it here.

Maps that have triggers in the start zone for resetting targetnames & classnames should now activate with @GAMMACASE's changes (https://github.com/shavitush/bhoptimer/pull/1123 / https://github.com/shavitush/bhoptimer/pull/1135) to the `shavit_misc_resettargetname` family, compared to previously where it wiped all events in the startzone and had a lot of cvars added to shavit-mapfixes.cfg to unbreak the maps.

If you have any new breakage on maps, let us know in the discord server or with a Github issue.


- added `Shavit_OnTeleportPre` and `Shavit_OnSavePre`. The return values of `Shavit_OnSave` and `Shavit_OnTeleport` are now ignored. https://github.com/shavitush/bhoptimer/commit/de8a82707b9fab615438844a2ea2f5ccc78957dc
- fixed replay prop playback breaking due to a bad index https://github.com/shavitush/bhoptimer/commit/70f29d3ca55a9f70d64f74ac9059c3cd1ab00a7a
- fixed replays not loading on the first map (and issues with creating replay directories too) (https://github.com/shavitush/bhoptimer/pull/1130) @Ciallo-Ani https://github.com/shavitush/bhoptimer/commit/d58d3ee1d569b22eded5a8f63e64544846b4d20e
- Changed the behaviour of `shavit_misc_resettargetname` (https://github.com/shavitush/bhoptimer/pull/1123) @GAMMACASE https://github.com/shavitush/bhoptimer/commit/0fee1862c8403e07d561cab45a9997dbe88a1041
	- Fix targetname and classname locking (https://github.com/shavitush/bhoptimer/pull/1135) @GAMMACASE https://github.com/shavitush/bhoptimer/commit/8f07c1d5106b28dea3c03eb842ec5c711cb0f1aa
- renamed `shavit_checkpoints_checkpoints` to `shavit_checkpoints_enabled` https://github.com/shavitush/bhoptimer/commit/b05393cf9fca682c7e959164a1ac15017c3efa3a
- improved handle handling in `Shavit_SetCheckpoint` and added `cheapCloneHandle` as a parameter for https://github.com/shavitush/bhoptimer/issues/1133 https://github.com/shavitush/bhoptimer/commit/91ec294f423def449dee616f9a4f7ea0b335abda
	- and a couple of other commits for that issue https://github.com/shavitush/bhoptimer/commit/8f59007d1d59c34c4b24c13de1c4fe207a3b20f5 https://github.com/shavitush/bhoptimer/commit/ea9a96271125659f252787840013b01e108633f5
- removed `Shavit_OnCheckpointCacheDeleted`. added `Shavit_SetTimesTeleported`, `Shavit_LoadCheckpointCache`, and `Shavit_SaveCheckpointCache` https://github.com/shavitush/bhoptimer/commit/86af6ca07ba18f6c401b662159a8323fea85ad60
- added max checkpoint counter to checkpoint menu https://github.com/shavitush/bhoptimer/commit/f642afe0162de51fe6359db7fd032fb772f95ab4
- moved shavit-mapchooser's `CheckRTV` to `OnClientDisconnect_Post` so it works properly :tm: https://github.com/shavitush/bhoptimer/commit/85ff178f473ae8cf714ad1f3505625052d3f84bf
- corrected native definition file for `Shavit_GetStageWR` https://github.com/shavitush/bhoptimer/commit/554606a21030648bfafbf20ccc1e3baa9fe3e335
- made `LowercaseString` faster :pepega: https://github.com/shavitush/bhoptimer/commit/3a6592cc5ee4e320402482eb9f386ac8ca438d8e
- added `bhop_drop`'s bonus to mapfixes https://github.com/shavitush/bhoptimer/commit/fda64ad1026ef2005c1d74c17d50bc1460097b60
- prevent nominations from being put twice on the map vote https://github.com/shavitush/bhoptimer/commit/ddb902e663b0fdb5071785af37aaed5cd0e189de
- changed oblivous autogain velocity stuff so boosters on `bhop_linear_gif` aren't affected by vertical velocity @defiy https://github.com/shavitush/bhoptimer/commit/76aaecdb6e84353b939fe29f8d267d5378565b65
- added `!nominatedmaps` and `!nominations` as aliases for `!nomlist` (https://github.com/shavitush/bhoptimer/pull/1136) @Nairdaa https://github.com/shavitush/bhoptimer/commit/d7785f91ce4535d7a7af1520b39c9124ca30a6d7
- removed reliable flag from centerhud and hinttext messages so they update faster and don't wait for an ack https://github.com/shavitush/bhoptimer/commit/ea3bd051242527268ee6bdfcf1a3011a2d6a3bcf https://github.com/shavitush/bhoptimer/commit/cf5bc4b7db5d9783179fc0578fc98af10a97a9ef
- merge checkpoint menus and shavit-kz.sp, etc (https://github.com/shavitush/bhoptimer/pull/1137) @sh4hrazad https://github.com/shavitush/bhoptimer/commit/6d208a8595f798d15f1cc0d56847e86134adc44b
	- fix normal checkpoint menu spams on changing the style from non-kz to kz styles
	- Added `kzcheckpoints_ontele` and `kzcheckpoints_onstart` style settings (merged in `shavit-kz.sp`).
- some currently disabled ladder checkpoint stuff has been added https://github.com/shavitush/bhoptimer/commit/1802f998fcb4ba65e9e32fd5da75cdf7a22d2d99 https://github.com/shavitush/bhoptimer/commit/158f0b854621ad208458ea73db545535d8af27a4
- made `Shavit_StartReplayFromFile` retrieve player name correctly https://github.com/shavitush/bhoptimer/commit/aa1f0eb169b3f957ee5531df4d0f65445b39a008
- removed `Shavit_Core_CookiesRetrieved`. tldr just check if client cookies are cached. https://github.com/shavitush/bhoptimer/commit/1230bf92663471568a8aa92bb33c3aa60c76c3ea
- added `shavit_hud_block_spotted_hint` for CSS https://github.com/shavitush/bhoptimer/commit/48ffd9bc714a7679b3cff070bc2cb26c0c897694
- made the buttons in wr submenu not do stuff https://github.com/shavitush/bhoptimer/commit/14e71dbbb492785941834fae63864b7923e767c8
- made the `Reset Checkpoints` buttons also trigger the `Shavit_OnDelete` callback. https://github.com/shavitush/bhoptimer/commit/b956ffb8aa93ca746bc50ac1766e23d550a2df8c
- added `fClosestReplayLength` to `huddata_t` and `Shavit_GetClosestReplayTime` https://github.com/shavitush/bhoptimer/commit/b2b2fe3344ec0bcb0bec97c48642f030a6691449
- `shavit_misc_weaponcommands` now has options 4 and 5 for all weapons/grenades... https://github.com/shavitush/bhoptimer/commit/a25417cc8ac2e892df9290a098d4d27946f78fd8 https://github.com/shavitush/bhoptimer/commit/c8ed191d11228d38abca455a9ca490a76d74aa26
	- might be buggy. let me know if there's problems.
```
// Enable sm_usp, sm_glock, sm_knife, and infinite ammo?
// 0 - Disabled
// 1 - Enabled
// 2 - Also give infinite reserve ammo for USP & Glocks.
// 3 - Also give infinite clip ammo for USP & Glocks.
// 4 - Also give infinite reserve for all weapons (and grenades).
// 5 - Also give infinite clip ammo for all weapons (and grenades).
// -
// Default: "2"
// Minimum: "0.000000"
// Maximum: "5.000000"
shavit_misc_weaponcommands "2"
```



# v3.1.3 - asdf - 2022-02-27 - rtldg
[`v3.1.2...v3.1.3`](https://github.com/shavitush/bhoptimer/compare/v3.1.2...v3.1.3)
https://github.com/shavitush/bhoptimer/releases/tag/v3.1.3
https://github.com/shavitush/bhoptimer/commit/d77fa13ebe679b7cca4493436e1fa045a15d3865

edit: bhoptimer-v3.1.3-1.zip = included eventqueuefix license. bhoptimer-v3.1.3-2.zip = bug fix commit included from https://github.com/shavitush/bhoptimer/commit/70f29d3ca55a9f70d64f74ac9059c3cd1ab00a7a

small things mainly and might as well push out a release instead of waiting another two weeks. hopefully nobody notices that half the `!czones` colors don't work because overlapping beams fucks with the color intensity. might have a bigger release next that messes with how the replays are stored and the replay format.

- included [eventqueuefix 1.2.1](https://github.com/hermansimensen/eventqueue-fix/tree/01eff5cc5f4d6d0f728563e538c9e203b565f304) in release zip so people use the correct eventqueuefix version for the timer
- `invert this duck autogain nsl boolean` https://github.com/shavitush/bhoptimer/commit/26dfdcc9275baa08fa32e23a0315ecaa96c50e8e
- added `player_speedmod` & `m_flLaggedMovementValue` values to debug targetname hud thing https://github.com/shavitush/bhoptimer/commit/9a5ff64fc5ed0f005f0a820f8eecdbf8b06b1a17
- `draw perfs keyhint even in startzone so the hud doesn't resize constantly` https://github.com/shavitush/bhoptimer/commit/987eebb3b072f7392579173a6a8831d4a09e622a
- `don't let mp_humanteam get in the way of jointeam 1 (for css spectatemenu prompt on first join)` https://github.com/shavitush/bhoptimer/commit/a0153de9f80f49c043762d25ddf8978870c02295
- two stats playtime bugfixes https://github.com/shavitush/bhoptimer/commit/253321ced6f502f1b457f7f94070dabd85e73505 https://github.com/shavitush/bhoptimer/commit/363627603b4edef059859fd1720db7807e26eee5
- fixed lowgrav & ladders sometimes breaking still (in 2022) https://github.com/shavitush/bhoptimer/commit/ef5ac148b3a7b4076ede6db766189042de8ed661
- added the `startinair` style setting which might be useful for non-bhop gamemodes like surf or tf2 stuff. might be exploitable so just let me know :^) https://github.com/shavitush/bhoptimer/commit/a6ade753fe33cde9eccb3f00788cb71d0807b726
- @NukoOoOoOoO added !czones so players can change zone colors & style https://github.com/shavitush/bhoptimer/commit/9c634868cb3b2f9b0c0e36ca653d1f3972292531 https://github.com/shavitush/bhoptimer/pull/1119
- multiple maps added to shavit-mapfixes.cfg
	- `bhop_blackshit` https://github.com/shavitush/bhoptimer/commit/2360d71494c7cbf09762d9afdc4d0facc679494f
	- `bhop_apathy` and `bhop_interloper` https://github.com/shavitush/bhoptimer/commit/614b16ce1711d160af7477690699d628387a76ac
- `don't start non-prespeed styles unless on ground for .5s` https://github.com/shavitush/bhoptimer/commit/89e97dfd3d5710ec5c25bafa78f0ded2c05d15a9
- modified `prespeed_ez_vel` to hopefully prevent invalid velocities & to make it work with just where the player is looking while standing still https://github.com/shavitush/bhoptimer/commit/98ee1799270690304585af6ec58415add80c426d
- make `shavit_zones_box_offset` affect zones when changed mid-map https://github.com/shavitush/bhoptimer/commit/840490cc54f9862b9450e39ed88c141e767d071c
- prevent "invalid" from showing up in the top left immediately after a new WR is made.https://github.com/shavitush/bhoptimer/commit/2e791a8237fd069019470686d4cc6effd880673b
	- adds a return value to `Shavit_GetWRName`
- make the scroll count !keys display work for (non-prop) replay bots https://github.com/shavitush/bhoptimer/commit/80e8480b7a0a94e8962e1d3da78602c703edf63d
	- adds `Shavit_GetReplayEntityFlags()`, although it might be removed in the "near" future
- prevent `shavit-replay-recorder` from overwriting faster replay files if `shavit-replay-playback` is unloaded https://github.com/shavitush/bhoptimer/commit/060ce5e660471c1ab6b84b0fc98d2b6e99a23e9e
- added more shavit-checkpoint forwards so third-party plugins can store custom data in checkpoints. https://github.com/shavitush/bhoptimer/commit/69445ebab582de152439d9a82c58aaffc71bc226
	- `mpbhops_but_working` now uses these to work with segmented checkpoints https://github.com/rtldg/mpbhops_but_working/blob/516b470feaa5180145acc28f28c05ff4793547ad/addons/sourcemod/scripting/mpbhops_but_working.sp#L116-L132
	- `StringMap customdata` was added to the bottom of `cp_cache_t`
	- includes `Shavit_OnCheckpointCacheSaved`, `Shavit_OnCheckpointCacheLoaded`, and `Shavit_OnCheckpointCacheDeleted`



# v3.1.2 - asdf - 2022-01-28 - rtldg
[`v3.1.1...v3.1.2`](https://github.com/shavitush/bhoptimer/compare/v3.1.1...v3.1.2)
https://github.com/shavitush/bhoptimer/releases/tag/v3.1.2
https://github.com/shavitush/bhoptimer/commit/d335ec72625b29f90668ab332f58323e528dd98f

- more robust max prestrafe limit thing to replace something from v3.1.1 https://github.com/shavitush/bhoptimer/commit/dd0059f15fc3045e67325deda4552984b968ca6f
- fix crash that came with the `player_speedmod` hook https://github.com/shavitush/bhoptimer/commit/0000000146955c76f2ad78096cc27f614dfddf3d
- added `bhop_lowg` to mapfixes https://github.com/shavitush/bhoptimer/commit/7399512f5e98b34d6547008998448d50a303dc08
- small change to `prespeed_ez_vel`'s internal stuff to maybe prevent the `-2147483648` velocity thing from happening and freezing you https://github.com/shavitush/bhoptimer/commit/00000008fd7b6cbe586fe900e118405dc67bb279



# v3.1.1 - asdf - 2022-01-19 - rtldg
[`v3.1.0...v3.1.1`](https://github.com/shavitush/bhoptimer/compare/v3.1.0...v3.1.1)
https://github.com/shavitush/bhoptimer/releases/tag/v3.1.1
https://github.com/shavitush/bhoptimer/commit/a1d30afdbe8352df489f5e16739efcdde56129f2

**Note:** If you get errors like this then just restart your server because it should be a one-off thing.
```
[shavit-rankings.smx] Timer (WR Holder Rank table creation 0/4) SQL query failed. Reason: View 'shavit.wrs' references invalid table(s) or column(s) or function(s) or definer/invoker of view lack rights to use them

[shavit-wr.smx] Timer (WR RetrieveWRMenu) SQL query failed. Reason: View 'shavit.wrs' references invalid table(s) or column(s) or function(s) or definer/invoker of view lack rights to use them
```

- made most of the shavit-timeleft time-remaining messages silent https://github.com/shavitush/bhoptimer/commit/6921f38214ed7561411d5bbb203857bade211794
- removed forgotten chat message when changing timescale https://github.com/shavitush/bhoptimer/commit/b4d13836ea9c104e7ed8c45240488e6b57185a4d
- added something to have an empty timer prefix with no preceding space https://github.com/shavitush/bhoptimer/commit/9adc56e2840624c648e1aab8ac2d85086704e7b0
- fixed shavit-stats error when not using shavit-mapchooser https://github.com/shavitush/bhoptimer/commit/6c88f45ba0cf7582a14bf1310988f32d8fb684aa
- make block_pstrafe do nothing when autostrafe is enabled https://github.com/shavitush/bhoptimer/commit/4167001b5cb8b1df446ab0d0868fd182f6448483
- replay bot name is filled with steamid by default (which is helpful for playing replays of a player who isn't in your db) https://github.com/shavitush/bhoptimer/commit/2909a3817922cee683d07f6600c5aa2e899be500
- fixed some pb menu bugginess https://github.com/shavitush/bhoptimer/commit/6d296caf36f3cd0dfde15181348e04b46f3b4cb1
- added !adverts https://github.com/shavitush/bhoptimer/commit/3d40d4f8098460ce18fd38da47cb7b48d5944a5e
- added reset-checkpoints back to tas menu https://github.com/shavitush/bhoptimer/commit/ecbc7edca2998c6728dea37f26966c6b8c835599
- prefix css expected hud rank with `#` https://github.com/shavitush/bhoptimer/commit/062efd4772ab97782dbf77bb56f546ce7f0e4416
- basic autostrafer implemented https://github.com/shavitush/bhoptimer/commit/e43c011711c05977cbf6251c067de2aad859f3b5
- moved some style-setting handling stuff around https://github.com/shavitush/bhoptimer/commit/c8c87347a5d36995c79db3f5b44215b88cf1a7db
- removed xutax_find_offsets https://github.com/shavitush/bhoptimer/commit/bacc5672fc72f1998cac0f297162acf2d35069c1
- add `!hideweps` as an alias for `!hidewep` https://github.com/shavitush/bhoptimer/commit/fda843a09f2497813b60a98bcb1c67203e4f5381
- added something to help with csgo (128 tick) tas autoprestrafe starting the timer earlier due to going faster than 290.0 https://github.com/shavitush/bhoptimer/commit/aef89e9bb4c016cface75525ed9bc2605f20ea49
- removed more unnecessary shavit-rankings point recalculations and removed column `points_calced_from` https://github.com/shavitush/bhoptimer/commit/b3b7de37e295ebc4fa56ccd9eaf7b918a6af60f6 https://github.com/shavitush/bhoptimer/commit/7a11acf2e66702827c0f871f487fff914ba32bd2
- fix bug that'd make players stuck when checkpointing replay bots https://github.com/shavitush/bhoptimer/commit/117d2d277c70d09aecd29990f25ee3b312b6f389
- hijack angles when autoprestrafing https://github.com/shavitush/bhoptimer/commit/345461a838365fdcc0ca419fc87da0a36ea3b064



# v3.1.0 - asdf - 2022-01-11 - rtldg
[`v3.0.8...v3.1.0`](https://github.com/shavitush/bhoptimer/compare/v3.0.8...v3.1.0)
https://github.com/shavitush/bhoptimer/releases/tag/v3.1.0
https://github.com/shavitush/bhoptimer/commit/0133300a400f70116776b71197fb2f4fb0a55e59

## important things
- `shavit-replay` was split into `shavit-replay-playback` and `shavit-replay-recorder`
	- **delete shavit-replay.smx or stuff will break**
- added `minimum_time` (default: 3.5) and `minimum_time_bonus` (default: 0.5) style keys https://github.com/shavitush/bhoptimer/commit/2fc72541494ca50a7d9856b9651726c669ec8d32 https://github.com/shavitush/bhoptimer/commit/98505fd99996d2d0fd5a0323899a63299c2f54ad https://github.com/shavitush/bhoptimer/commit/361826908e12fbb02db5a50b7275388382f8bf02
	- **You will need to adjust these for any meme dumb styles that let you go really fast like parkour, unreal, or thanos.**
## main changelog stuff
- **closestpos** has been updated to **v1.1.1**. https://github.com/rtldg/sm_closestpos/releases/tag/v1.1.1
- moved checkpoint code out of `shavit-misc` and into `shavit-checkpoints`
- sped up queries used for recalculating points
	- https://github.com/shavitush/bhoptimer/commit/4f8fd211f3f551dd21795b7f2ec4a95615c7aacb https://github.com/shavitush/bhoptimer/commit/22a87ce3eeb3a4a6900569437f997b38aa4ae366 https://github.com/shavitush/bhoptimer/commit/235cc9f24100c75a2fc65151db8f86534b7eaeb9 https://github.com/shavitush/bhoptimer/commit/838d33510b64d6e6a69320b1438e800199a18575 https://github.com/shavitush/bhoptimer/commit/60c614df9d95095e1529785a3fc40d97f80d5c13 https://github.com/shavitush/bhoptimer/commit/41882d3465cb13826053b33f56e85449471eb717 https://github.com/shavitush/bhoptimer/commit/673b172871fe6cf4a3535f06d4a657424f3aa4f6 https://github.com/shavitush/bhoptimer/commit/b8170c6799ec0087be111f22e10614786236cdd2
- `shavit-mapchooser` stuff
	- added `smc_mapvote_printtoconsole` https://github.com/shavitush/bhoptimer/commit/a3e3e0682b4d2e65a771c99e7cf9a48136c16fd2
	- fix an error introduced that involves novote & rtv https://github.com/shavitush/bhoptimer/commit/0164d159104822c2bc63261461a4a0ee25afb909
	- made `!map` with no args show the menu using the `shavit-mapchooser` list https://github.com/shavitush/bhoptimer/commit/3388c7b5d361c2dadc846bca8084ac77c82e7074
	- fix `!map` menu using wrong parameter for client https://github.com/shavitush/bhoptimer/commit/4f98303b4ca5d575698515a4b163de741efc9149
	- made rtv change the map immediately if novote wins https://github.com/shavitush/bhoptimer/commit/cf5105446041ed93dee060351521b5bc89a7e10c
	- added `Shavit_GetMapsArrayList()` and `Shavit_GetMapsStringMap()` https://github.com/shavitush/bhoptimer/commit/cdb4b5746e80254c04789f5ffeed5dd285ff6e50
	- remove nomination on disconnect https://github.com/shavitush/bhoptimer/commit/ad837a7d2463bcdf34108b99fa7132089be61ae2
- added `shavit_rankings_weighting_limit` https://github.com/shavitush/bhoptimer/commit/ae82d9a5ade63fff446d2ab2798cad793d94bda8
- add missing sync next to strafe count in CS:S hud https://github.com/shavitush/bhoptimer/commit/c5d4679c9a783501ba77ae4cde0814e20bde07f4
- changed `shavit_misc_botfootsteps` to `shavit_replay_bot_footsteps` https://github.com/shavitush/bhoptimer/commit/c33ea7c0d02f986f35d09a2b14a8563a2daf87d8
- turned replay reading & writing functions into stocks so they can be used by external plugins easier https://github.com/shavitush/bhoptimer/commit/ab0fc28c26a34ed0651f9d920aa1db96aad9d2ab
- removed `Shavit_OpenCheckpointMenu()`. Use `FakeClientCommand(client, "sm_checkpoints");` instead https://github.com/shavitush/bhoptimer/commit/0b31c6a6088b5851a2737b50f4ec0324973eba01
- removed `Shavit_OpenStatsMenu()`. Use `FakeClientCommand(client, "sm_profile steamid");` instead https://github.com/shavitush/bhoptimer/commit/1bb7b3e274449e75920eb30ca06ab394b8e075d5
- fixed bug that was changing human names on connect message https://github.com/shavitush/bhoptimer/commit/c81f958efbb96600da281970fffbbccffe6b679a
- added an alternate format for the `!keys` text that should work better for linux players https://github.com/shavitush/bhoptimer/commit/a0a2cce04a56ca4be0c4e207fe15e20fa56b1af3
- flashlight flag is now disabled when someone uses `!spec` https://github.com/shavitush/bhoptimer/commit/0f66a081a392d5c3ca608291d107e62b7c4fdf9e
- swapped to using `OnPlayerRunCmdPost` for recording replay frames https://github.com/shavitush/bhoptimer/commit/55b6253b30e1f0152e7c79077f03a7684fd774f7
- fixed `isBestReplay` and `isTooLong` being swapped in `Shavit_OnReplaySaved()` https://github.com/shavitush/bhoptimer/commit/4d8faa1099b801f6eac69e621e6f2845197def91 https://github.com/shavitush/bhoptimer/commit/de1d1d5145c1bdf1ce9e83d3c8cd8782bf175976
- fixed own playtime display & rank in `!playtime` menu https://github.com/shavitush/bhoptimer/commit/df2e9c402d44bcc3db31224502c504a5fa184957
- added some stripper configs for bad maps https://github.com/shavitush/bhoptimer/commit/09693df6ebc84ecb6d481b8595de216fc4110d7e https://github.com/shavitush/bhoptimer/commit/d59399b59ce36e55b37f501cdc0013658c8da053 https://github.com/shavitush/bhoptimer/commit/5a39f5ce45bcb03d54e219f2fc31b094d4620d96 https://github.com/shavitush/bhoptimer/commit/849bc0ed7664805dcf52808e448a92215880dd02 https://github.com/shavitush/bhoptimer/commit/3f3474f46344c472ddef18afbfb591dd18267a48
- made `!hide`'s set-transmit hook to also hide dead players like btimes (so players can't use a speclist cheat in csgo) https://github.com/shavitush/bhoptimer/commit/73b17941ce5c33a1889ad3e2fac88a287d947c04
- removed `shavit_misc_bhopsounds 0` https://github.com/shavitush/bhoptimer/commit/5d26e76ec2a11affbebbbfa9d3c2fddb21bec51a
- allow `!setstart` outside of the start-zone https://github.com/shavitush/bhoptimer/commit/b88367d07907719c01ec87896caae08b4bac3137
- removed `shavit_core_timernozone` https://github.com/shavitush/bhoptimer/commit/4b51bd711665891699b22b6875ba0b40918d6f5b
- split shavit.inc into .inc files for each plugin. shavit.inc now just includes all the separate .inc files.
- mapfixes for [`bhop_overthinker`'s bonus](https://github.com/shavitush/bhoptimer/commit/2d98efd16c5f795dffc30a0b28217d8ebdf53f3c), [`shavit_misc_resetclassname_main` to unbreak `bhop_japan`](https://github.com/shavitush/bhoptimer/commit/6573e0cbbc86337cc5ff275ab1d6a5bf6c59b0dc), [`kz_bhop_strafe_comjump2` and `kz_bhop_strafe_comjump2_v2`](https://github.com/shavitush/bhoptimer/commit/d37ca33ea4afe14c27f592102b4d893ce93bce2a), [`bhop_horseshit_5`](https://github.com/shavitush/bhoptimer/commit/b3f89493b066a85beab9f6cfec051c77f74013be), unbreak `bhop_decbble` 59ec8eb6e570c1ebc91cf7f8ad2f9fa7cadf5dd6, `bhop_appaisaniceman3` dedbba5ec9eb584393771744536799998869c837 5b8a14934395cad4e0c7c81d8320644234096929, and some more misc https://github.com/shavitush/bhoptimer/commit/5882e458db2e0c312bf9cd37d8d301ae7c75d552
- something to stop hsw tracking strafes on `w` 573e97e9dcf3a14623fcb3cc42f97c2a184b312d
- something that might let people unrtv after a non-rtv'd mapvote https://github.com/shavitush/bhoptimer/commit/cf7c1d85bb48bf1311a3bf054bbd979e7b491cd9
- replaced `shavit_misc_weaponsspawngood` with `!hud` settings that toggle USPs with silencers and glocks being given burst-fire. https://github.com/shavitush/bhoptimer/commit/8a31bc84aa68d9a79a695dc883bc87040e9a37ff https://github.com/shavitush/bhoptimer/commit/0591499471e49bcd64192ab8983567b930ece417
	- added `!hud` setting that lets you pick between spawning with a USP or glock.
	- added `Shavit_GetHUD2Settings()` in this commit
	- made weapons spawn with skins https://github.com/shavitush/bhoptimer/commit/8ce9cd97b4bd4c9ea08e8508e3b7f17439aa10c9
- Fixed SQL error that'd happen from inserting player names on CS:S due to steam names being `[32+1]` and CS:S names being `[32]` by introducing `SanerGetClientName`. https://github.com/shavitush/bhoptimer/commit/5312c312538d45a61842363fbcd35f79885f491c
- Fixed name changes not showing up in chat https://github.com/shavitush/bhoptimer/commit/f61ea0f070ae5c3ffa536222cc34120e3aa13b21
- added `!sm_drawallzones` and `shavit_zones_allowdrawallzones` https://github.com/shavitush/bhoptimer/commit/a68b21e9bd49ff56019b1166db3a6647bc8db836
- added `!tptozone` https://github.com/shavitush/bhoptimer/commit/9cb22987646b6b4d88432efccdd1245427c35e73
- added map list matches to !wr menu https://github.com/shavitush/bhoptimer/commit/bce7c04afea856a1041293d4a8861934096b8799 https://github.com/shavitush/bhoptimer/commit/64088b61476b8ebea42a2f08f80b671ac798a53e
- added `Shavit_GetReplayFolderPath()` https://github.com/shavitush/bhoptimer/commit/70ca6ace3d276be1082b9c2a21af017ff6c4394d
	- also `Shavit_GetReplayFolderPath_Stock` xd https://github.com/shavitush/bhoptimer/commit/4b711b1fabffbc63abdbc90ff02fd9151e61d250
- merged bhopstats into repo https://github.com/shavitush/bhoptimer/commit/aba539856ee0825b85757fb5fb76c1382d26e30b
- adjusted !keys alignment https://github.com/shavitush/bhoptimer/commit/03d44c9d2336aeb21e877aabd234b4a97684b319
- added `Shavit_Core_CookiesRetrieved()` and `Loading...` text to hud while player cookies are loading https://github.com/shavitush/bhoptimer/commit/f344fddcdf24ba8aee15e99bdabc0d08fc4a0c7a
- added `kzcheckpoints_ladders` style setting https://github.com/shavitush/bhoptimer/commit/48d8e0176982c49bba85e6a4f7f9e933bc391390
- added `climb_zone_*` parsing for prebuilt zones https://github.com/shavitush/bhoptimer/commit/30574923e519e554059128ee1ba29412194afe7b
- messed around with the csgo hud to hopefully make it look better https://github.com/shavitush/bhoptimer/commit/7e04e840c4099a8f7658d334c96130cf3a7dda68
- added `!addzone` & `!delzone` as aliases https://github.com/shavitush/bhoptimer/commit/bd596bec75114635bc04427c7608bb16c9addbdc
- fixed css perfs not showing if sync is not enabled https://github.com/shavitush/bhoptimer/commit/07b165b3add2d308051d4efcc076eabee03a5e07
- disable style setting `force_timescale` https://github.com/shavitush/bhoptimer/commit/4e16365991ae5e6c6d132807e2058bbde2a3f3fe
- merged `!ranks` menu and `!chatranks` menu https://github.com/shavitush/bhoptimer/commit/30935885d4d824828f6ce6a0a16080e0227883ab
- draw zone beams on `!r` or `!end` https://github.com/shavitush/bhoptimer/commit/b78a6ec4ecc8ebe8eff2df73fa1b5fae1a23dfda
- stop tracking style playtime when dead / spectating https://github.com/shavitush/bhoptimer/commit/fb62419006b8040749cdab3b60981a6a9069e891
- send message to player after using `!ccadd` on them https://github.com/shavitush/bhoptimer/commit/bc978b6add495905190b0a599bea2576fbcd93e3
- use mapchooser maps when possible for calculating !profile & !mapsleft/!mapsdone stats https://github.com/shavitush/bhoptimer/commit/da734db69945fdf63a93edcfba750ff07bee6c41 https://github.com/shavitush/bhoptimer/commit/c89e1d4400261f4938dedee6463a6b88ed4b940d https://github.com/shavitush/bhoptimer/commit/f8f336d21abbd93e7819a9fbf998d1a7facca90d
- make `!recentrecords` use the `shavit_wr_recentlimit` cvar correctly https://github.com/shavitush/bhoptimer/commit/183e75897145f79040bfd6a9edd1adc4021382b4
- add hacky fix for zone disappearing after hitting exit on the zone-edit menu https://github.com/shavitush/bhoptimer/commit/3c5958eb931d3c8897a9ca2cda46917af9fe3125
- added more commands to the anti-sv_cheats command list https://github.com/shavitush/bhoptimer/commit/79cd7f122572ef5a6e8928330740e7930c896923
- print steamids to chat when using `!profile <otherplayer>` https://github.com/shavitush/bhoptimer/commit/4d1a0b5eb39b25f45f0f181a859dd992ec403910
- allow you to use `!settier` on a map you're not on (`!settier N bhop_different_map`) https://github.com/shavitush/bhoptimer/commit/6d21e25679e383c42f7bf19eaa5ca8fb91a42d02
- added `Zone_NoTimerGravity` and `Zone_Gravity` https://github.com/shavitush/bhoptimer/commit/c55531168d5186e3ddb76fd9c7479b0692cbb015 https://github.com/shavitush/bhoptimer/commit/13d6d586b32dfb9e325a3eb3070a0d5c8b97af41
- change `shavit-zones.cfg` parsing so you don't have to include everything every zone type (especially for multiple bonus) https://github.com/shavitush/bhoptimer/commit/2067dc7c387d9067feb7d9dcff9403a41ff1650b
- don't display stop confirmation when in practice mode https://github.com/shavitush/bhoptimer/commit/f3ec01870ba5e37015287d68d29ebc44357b627f
- don't print practice mode warning when teleporting to practice mode checkpoint while already in practice mode https://github.com/shavitush/bhoptimer/commit/f5652c641e7e7df8261b66a92dfcd0918303b99c
- some random checks for times <= `0.11` so dumb times don't happen https://github.com/shavitush/bhoptimer/commit/bff7ace88745a19f57703a07e549d0e45715ce75
- allow pressing `climb_endbutton`'s without being on the ground https://github.com/shavitush/bhoptimer/commit/f02ac94bbf99d4d14ff86c3afa32ffa2491927c0
- fixed some buggy kz button restarting things https://github.com/shavitush/bhoptimer/commit/86b23b33a2da35f7527c4f27d07987255de5af09
	- `Shavit_MarkKZMap()` and `Shavit_IsKZMap()` now require track parameters
- any number of kz buttons should work on a map now https://github.com/shavitush/bhoptimer/commit/04eea994d8746b66f5488575cdad6ab16de2365a
- added `shavit_core_save_ips` so you can disable storing player ips in the `users` sql table if you want https://github.com/shavitush/bhoptimer/commit/729f060f91f1c90dab6f64db9b1628a16ee0e655
- based strafe count on input vel instead of button flags https://github.com/shavitush/bhoptimer/commit/0db2b30a778af4529e4df8f44e409efead9e3b99
	- this also solves the thing where using `+klook` and holding `+forward` would give you 0 strafes.
- some wip csgo hud stuff and more forwards 3295e235534828eddff10f68b8b55c965d4a35c7 7675b605673c827db8f7987ecb5f92b880aedaf2
	- `Shavit_PreOnTopLeftHUD`, `Shavit_PreOnDrawCenterHUD`, `Shavit_PreOnDrawKeysHUD`
- disable `shavit-rankings` SQL function creation if `shavit_rankings_weighting` is `1.0` https://github.com/shavitush/bhoptimer/commit/254eea7780af39c143bd3f7e809eede24e8a3075
- made scoreboard update on a 0.2s timer instead of 1.0s https://github.com/shavitush/bhoptimer/commit/a8016dff00384578879e2e99672761e396291c10
- unbreak `player_speedmod`s that disable buttons (like the one on `bhop_futile`) https://github.com/shavitush/bhoptimer/commit/1802dd8007169c60d709cd89789417cbff7443a8 https://github.com/shavitush/bhoptimer/commit/03c3af1a4f130f9beb1bf92bea376b29ab16acaa
- try to prevent bad mins/maxs values for zones by adjusting how offsets are applied https://github.com/shavitush/bhoptimer/commit/39c9d96924a799df3425e3d26090667e346b726d
	- `xc_fox_shrine_japan_v1` will crash if i make a 16unit zone at the top (maybe elsewhere too?) so that's why this was added.
- make `Shavit_OnTimeIncrement` unable to edit time (**this change breaks some tas plugins**) https://github.com/shavitush/bhoptimer/commit/a146b51fb16febf1847657fba7ef9e0c056d7476
	- also fixes usage of the end-zone-offset
		- bumped replay version number to help track which replays might be affected by this https://github.com/shavitush/bhoptimer/commit/94b3c41f41453e7f31cea5cc5731edecbd7356b1
- update velocity-difference if pause-movement is enabled https://github.com/shavitush/bhoptimer/commit/2e627fe3e2496b9fd8ce7d2b3aaba060893a15ac
- add `Shavit_GetReplayFolderPath_Stock` https://github.com/shavitush/bhoptimer/commit/4b711b1fabffbc63abdbc90ff02fd9151e61d250
- added style settings that override convars relevant to prespeed for #954 https://github.com/shavitush/bhoptimer/commit/396f2017c5beef679938a0fc0512d2b50637e58a
	- `prespeed_type` for `shavit_misc_prespeed`, `blockprejump` for `shavit_core_blockprejump`, `nozaxisspeed` for `shavit_core_nozaxisspeed`, and `restrictnoclip` for `shavit_misc_restrictnoclip`
- use all valve_fs search-paths for maps folder reader functions (so custom/maps/ folders work better for me) https://github.com/shavitush/bhoptimer/commit/3c59adce57f48b2f175c2f3180e859315a37c8b4
- `Refresh menu` is now shown on every page of zone editing menus https://github.com/shavitush/bhoptimer/commit/c68d50a4d01ef0044d380a88e44b3db782d31102
- ensure timescale-change callback is called on Shavit_LoadSnapshot https://github.com/shavitush/bhoptimer/commit/f14ae3a604dc332b0e2a3c0db9395b4e88e48dbe
- made style/track change callbacks actually change style/track before the callbacks happen https://github.com/shavitush/bhoptimer/commit/cd2a74240a6392411a5109180d814fe15638e7f5
- add `sm_prevcp`, `sm_nextcp`, and `sm_deletecp` https://github.com/shavitush/bhoptimer/commit/f89816449ab416344d19706d90a51c94d02f6e88
- hopefully stop timer commands menu from being wiped on plugins reload https://github.com/shavitush/bhoptimer/commit/1509e77728a2fa2fa5521ad269ef013929973d28
- made some of the admin menus, like time-deletion, reopen https://github.com/shavitush/bhoptimer/commit/aa7887ecf4ffed12095b1d48f9e38a3ed7842a85
- got more stoptimer confirmation menus working (style change, `!end`, `!r`) https://github.com/shavitush/bhoptimer/commit/53aeec31f2cab35ae9d8d3084d0c6a590364c63e https://github.com/shavitush/bhoptimer/commit/35391f36d11bfd84de5ce7eb620842e649f19261
	- adds `Shavit_OnEndPre`, `Shavit_GotoEnd()`, and `Shavit_OnStyleCommandPre`
- made `spectate` command use `!spec` handler https://github.com/shavitush/bhoptimer/commit/62c2a26e48645da7a238fdc3041e9057897769bd
- made the timer-increase-scale = `tas_timescale` * `timescale` https://github.com/shavitush/bhoptimer/commit/cd91255c5223a6e98389621a9f256b3767c059b6
- fix wrholderrank table creation error with versions of mysql 8.0 for #1097 https://github.com/shavitush/bhoptimer/commit/94d8d91a82e8ddc67b663d0e4a59b402e34d7191
- made points recalculate on wr-delete and remove recalculating on mapend (since it's unnecessary) https://github.com/shavitush/bhoptimer/commit/ede141d8c079a0da5830b305876fb891deb2f792
- made `shavit-wr` validmaps query combine mapzones&playertimes https://github.com/shavitush/bhoptimer/commit/43d6a31ac0a79b06314a2c5049acc09de48d6322
- delay `wrhrankXXX` queries by 10s on mapchange since they're slow and block cookies on databases with a lot (a lot) of runs https://github.com/shavitush/bhoptimer/commit/8827864fb878e50e0137bc073ecddb1ffb9fb00d
- made smc_display_timeleft display time until map vote in chat https://github.com/shavitush/bhoptimer/commit/01a2e616a65ac99a1dd9490b23110565b5718f3c
- made `!ihate!main` & advertisements messages silent https://github.com/shavitush/bhoptimer/commit/900083b321653a2fa5b16c27e3bb4a3c89a320a6
- made `shavit-hud` update topleft on track change & spectatee change https://github.com/shavitush/bhoptimer/commit/431fd18ecbace5b90d253d574693978b2f76ee96 b2d7b4d9bd4a07f7266a53d2917c404eabf89a4f
- show topleft when spectating idle central !replay bot https://github.com/shavitush/bhoptimer/commit/a750753a6282ea020328e80806113d5d4181af7e
- made debug targetname thing a !hud option instead of cvar https://github.com/shavitush/bhoptimer/compare/v3.0.8...master
- added style setting `prespeed_ez_vel` which can set the player velocity on first jump for prespeed styles https://github.com/shavitush/bhoptimer/commit/8e0736e3d3f3bd3fb92bf02f6853bd16c8c4061d https://www.youtube.com/watch?v=ae2mH78bzUI
- made everything in `specialstring` be set as regular styles. `key1;key2=something` would set `key1` to `1` and `key2` to `something` https://github.com/shavitush/bhoptimer/commit/73d21ea9d1397145fa3ac3b0cbe6b3037e50b02a https://github.com/shavitush/bhoptimer/commit/8a9fe142742b22488084ecc6f9aad67d82caeec7
- added `Shavit_IsClientUsingHide()` https://github.com/shavitush/bhoptimer/commit/4ec8a620be41c2af0051ffd961f4344e8767e81d
- various changes so bhoptimer will work with sourcemod 1.11 https://github.com/shavitush/bhoptimer/commit/3348e543164b25b24d2df7c8513f3683faf87c7f https://github.com/shavitush/bhoptimer/commit/ae0145430a06c7ee8b9e235cfdd4476a0fbb5753
- add menu parameter to `Shavit_OnCheckpointMenuMade` https://github.com/shavitush/bhoptimer/commit/794c379bf27d962858b1835c645b74f77f592237
- added `Shavit_GetZoneTrack()`, `Shavit_GetZoneType()`, and `Shavit_GetZoneID()` https://github.com/shavitush/bhoptimer/commit/baa824e872b40f077a1e5433602fe72ae0f9b12b https://github.com/shavitush/bhoptimer/commit/9c4f626076ec85415d84b67d95b3a1cc3daad7cf
- added `shavit_chat_enabled` if you want to use alternative chat processors https://github.com/shavitush/bhoptimer/commit/fa58b0f7fe3ae1c0407a400927c75e36a76d2358
- made player savestates save on player suicide https://github.com/shavitush/bhoptimer/commit/871f59c235dd16e1c9f7677d5599939773a0e03b
- added option to play replay bots at 0.5 speed in the `!replay` menu. https://github.com/shavitush/bhoptimer/commit/0cc406c96201c43b95f571130ad25e555c799680
	- adds `Shavit_GetReplayPlaybackSpeed()`
- implementation of `!pb/!times <target>` added for #636 https://github.com/shavitush/bhoptimer/commit/3be3b4e3b26a60ca350a11c7b08c6a2c52731b79 https://github.com/shavitush/bhoptimer/commit/590d1fb2905847a5c6cb8d3cdc6c589a89512adf
- made csgo use center-text for keys https://github.com/shavitush/bhoptimer/commit/46550e7a83617b901dffab4442b0d0fa1bee8b45 f474a944aead9ab9ec5aaa7a2107db17f8ce6319
- spec_next/spec_prev memory leak fix https://github.com/shavitush/bhoptimer/commit/f4d2d6d65318c86773760881edffd723bc9ce271
- **`shavit-tas.sp`, `tas`, `tas_timescale`, and more!** https://github.com/shavitush/bhoptimer/commit/4aac85d3fd5b05152086d82e023f47b5f2a828a3 https://github.com/shavitush/bhoptimer/commit/f193679a9d458460513d64cd20655feeb24c36e4 https://github.com/shavitush/bhoptimer/commit/1ce6acc5f40037a97c90d6ea77966842cc151f21 https://github.com/shavitush/bhoptimer/commit/2fa06031de94bc50ade28d24b10645d6f4de358d https://github.com/shavitush/bhoptimer/commit/e3ed6027ca758eb351a82426bcc2927b37c44850 https://github.com/shavitush/bhoptimer/commit/1633201e167036e96e437f6c724c75d9514be6ba https://github.com/shavitush/bhoptimer/commit/576c77313432a4ffb90814f951cd95c13022657b https://github.com/shavitush/bhoptimer/commit/da172f07aa69c437011cef60aac60cea69733fbb https://github.com/shavitush/bhoptimer/commit/ba5ad21661b6148231d6c0f2c19f2ae4882fcb80 https://github.com/shavitush/bhoptimer/commit/b34a4e6677aafc11351ec6a18be5fdadf2d88896 https://github.com/shavitush/bhoptimer/commit/c089b3af9df9d57be3d660a404fb73e464d3a72f https://github.com/shavitush/bhoptimer/commit/0286df9edd94eafba5ebe1c28875a7ea4afca1e2 https://github.com/shavitush/bhoptimer/commit/a115632b7b1673adaea7ee14b1c5a992c67aa76f https://github.com/shavitush/bhoptimer/commit/e8e8f716573bdf71ed793179c4bb62821c9ed87a
	- `tas_timescale`
		- greater than `0.0` = forced tas-timescale on this style (example: `"tas_timescale" "0.5"`)
		- `-1` = players can change their timescale manually
		- The implementation was based on [KiD-TAS](https://github.com/kidfearless/KiD-TAS/tree/rewind)
	- `autostrafe`
		- `-1` = players can toggle between the 1-tick autostrafer & the autogain velocity based one
		- `1`  = 1-tick autostrafer from @xutaxkamay (retrieved from [KiD-TAS](https://github.com/kidfearless/KiD-TAS/tree/rewind))
		- `2`  = faux autostrafer that gives velocity from @defiy (retrieved from [defiy/autogain](https://github.com/defiy/autogain))
		- `3`  = faux autostrafer that gives velocity (no speed loss version (for fun high speed turns)) from @defiy
			- not a "legit" tas mode since impossible turns are possible.
	- `autoprestrafe`
		- TAS Prestrafer for maximum ground movement speed.
	- `edgejump`
		- Automatically jumps when the player will fall off a ledge next tick.
		- Should jump out of the start-zone with a 0.0 zone offset.
	- `autojumponstart`
		- Automatically jumps when the player will leave the start zone.
	- `"tas" "1"` = Enables the TAS style settings unless they are explicitly disabled:
		- `tas_timescale -1`, `autostrafe 1`, `autoprestrafe 1`, `edgejump 1`, and `autojumponstart 1`
	- +/- timescale options show up in the segmented checkpoints menu when `tas_timescale` is enabled https://github.com/shavitush/bhoptimer/commit/578dd01e1a92295a8863cd9b6d3e486a6d53bd20
	- added `!tasmenu`/`!tasm`, `!ts <number>`, `!tsplus <number>`, and `!tsminus <number>`
	- `+autostrafe`/`-autostrafe`/`!autostrafe`, `+autoprestrafe`/`-autoprestrafe`/`!autoprestrafe`, `+edgejump`/`-edgejump`/`!edgejump`, `+autojumponstart`/`-autojumponstart`/`!autojumponstart`
	- added `Shavit_ShouldProcessFrame()`.
	- added `fplayer_speedmod`, `fNextFrameTime`, and `iLastMoveTypeTAS` to `timer_snapshot_t`
	- `Shavit_SetAutostrafeEnabled()`, `Shavit_GetAutostrafeEnabled()`, `Shavit_SetAutostrafeType()`, `Shavit_GetAutostrafeType()`, `Shavit_SetAutostrafePower()`, `Shavit_GetAutostrafePower()`, `Shavit_SetAutostrafeKeyOverride()`, `Shavit_GetAutostrafeKeyOverride()`, `Shavit_SetAutoPrestrafe()`, `Shavit_GetAutoPrestrafe()`, `Shavit_SetAutoJumpOnStart()`, `Shavit_GetAutoJumpOnStart()`, `Shavit_SetEdgeJump`, `Shavit_GetEdgeJump`

Maybe I should've released some of this sooner as 3.0.9, but oh well.

Shoutout to sirhephaestus for watching an 18 hour playthrough of The Witcher 1 game with me and shoutout to aho.



# v3.0.8 - asdf - 2021-10-04 - rtldg
[`v3.0.7...v3.0.8`](https://github.com/shavitush/bhoptimer/compare/v3.0.7...v3.0.8)
https://github.com/shavitush/bhoptimer/releases/tag/v3.0.8
https://github.com/shavitush/bhoptimer/commit/b2a95095e788f86724ef463f9d8dfae1077c01c3

## stuff
- fix replay bot being given a usp repeatedly on csgo https://github.com/shavitush/bhoptimer/commit/e7bf386d1401a98072b272de204fc13d2fc4fb8e
- hide `timeleft` from chat if `smc_hide_rtv_chat 1` https://github.com/shavitush/bhoptimer/commit/468e9bfee90ec170f736451a86cbf7d0dce33022
- fixed `sm_profile` without any args not working https://github.com/shavitush/bhoptimer/commit/468e9bfee90ec170f736451a86cbf7d0dce33022
- fixed `sm_mapsdone` without any args not working https://github.com/shavitush/bhoptimer/commit/0f250cc7805fb396dfae5b732bef1b7a9051567a
- added `bhop_symbiotic` to shavit-mapfixes.cfg https://github.com/shavitush/bhoptimer/commit/87f361ac3dacd70d3220d53ad9ecd8de81ee3b9c
- make the `Alphabetic` list in !nominate filter out maps following `smc_min_tier` and `smc_max_tier` https://github.com/shavitush/bhoptimer/commit/83a572ce96f44ba5075b7e17717ca146830dddab
- added map count to tier display string https://github.com/shavitush/bhoptimer/commit/7375900b83b8b7c25369b87c8a31195f2237e6c5
- added bhop_drop to mapfixes https://github.com/shavitush/bhoptimer/commit/b64ed479a98a093d331c1676b8ebd940a2c1db9d
- added `shavit_hud_debugtargetname` https://github.com/shavitush/bhoptimer/commit/b1a5339910025011b8e48428c0c89a84c776201b
- added `shavit_timelimit_minimum` & `shavit_timelimit_maximum` https://github.com/shavitush/bhoptimer/commit/35de5f571688c96578bc024400f9ac047ff0afcc
- added `shavit_timelimit_hidecvarchange` https://github.com/shavitush/bhoptimer/commit/ad48845d622ca4a8f65568cf6aeddac245b582ce
- change the dynamic time limit averaging from row-count to the minimum times thing https://github.com/shavitush/bhoptimer/commit/6b2f7093207d0c75a2d227050d3a0c7c29ef79ab
- add `shavit_misc_spec_scoreboard_order` https://github.com/shavitush/bhoptimer/commit/e53fb80373f5529d94fb8e030231d6a7987e3887
- add ranks to playtime menu https://github.com/shavitush/bhoptimer/commit/c52eb107555c811421abfa4e9af9e5cdb404ff27
- removed `shavit_misc_prespeed_startzone_message` and usage of `BHStartZoneDisallowed` https://github.com/shavitush/bhoptimer/commit/bfdfff0eb1b388ceed865b6439677a21f128e013
- fixed the completion message when spectating someone that I broke https://github.com/shavitush/bhoptimer/commit/480dbefabced91e007df92bee043ea3daa46767b
- prevent nominate/unnominate when the map vote is active or finished https://github.com/shavitush/bhoptimer/commit/c3e57b851c8f0867d5050317141a56ae032daec2
- added `sm_reloadmap` & `sm_restartmap` which reload the current map https://github.com/shavitush/bhoptimer/commit/f425294f546e34a70f616d346a04277eac674895
- some replay bot changes so bots join and have the true name earlier https://github.com/shavitush/bhoptimer/commit/f7fd2af33cf294717ab01b214ea94a1f02db8ec8
- adjust dynamic time limit to always multiply average https://github.com/shavitush/bhoptimer/commit/e174b950433b9b1637ae52f316e2a0cf016f07dd
- added matches menu when using !map https://github.com/shavitush/bhoptimer/commit/afed33e944f64b883cddac17020c9fe8d2d563ed https://github.com/shavitush/bhoptimer/commit/276d74b968d64254f0d8f054d85cae7bcca7410f



# v3.0.7 - asdf - 2021-09-23 - rtldg
[`v3.0.6...v3.0.7`](https://github.com/shavitush/bhoptimer/compare/v3.0.6...v3.0.7)
https://github.com/shavitush/bhoptimer/releases/tag/v3.0.7
https://github.com/shavitush/bhoptimer/commit/346d7f903c9118e3180dd6cc8936e0ed3f2ba597
https://github.com/shavitush/bhoptimer/commit/e7bf386d1401a98072b272de204fc13d2fc4fb8e (v3.0.7-1) (added with a single commit added for csgo handling of `shavit_replay_botweapon`)
https://github.com/shavitush/bhoptimer/commit/32f0e50905cba03437a67552fdf088bfffc9f642 (v3.0.7-2) (added to fix `!profile` with no arguments saying it was broken)

## stuff
- some name trim & buffer size stuff for !recent menu https://github.com/shavitush/bhoptimer/commit/60d9609b7d5e296ed30c70c8c98359506763033e https://github.com/shavitush/bhoptimer/commit/94f30693c0ff3ffb332f1c19ade53fbef77ecc30
- reverted shavit-wr change that resulted in handles leaking https://github.com/shavitush/bhoptimer/commit/8ee42d6490b484ff1e3babdec085b24a991332bb
- in-game player's cache is refreshed when they have a time of theirs deleted https://github.com/shavitush/bhoptimer/commit/b89348697256806a8adf24d0e6c21fa0618fb3d2
- added `!ihate!main` https://github.com/shavitush/bhoptimer/commit/195458307071492b297ca5e25dcf04e18bb8281f
- !wr menu remembers page https://github.com/shavitush/bhoptimer/commit/82c1605e94006318f5153dd613f7e2839b56f797
- !wrn, !wrsw, !bwrscroll, etc added https://github.com/shavitush/bhoptimer/commit/c80515496afb85b478674c89edee3d80df69a601
- added `Shavit_SetReplayCacheName` https://github.com/shavitush/bhoptimer/commit/36a468615d0cbed8788bed6564a314977e3b775a
- fixed prebuilt zones being cached twice https://github.com/shavitush/bhoptimer/commit/ea5e6b853579a9ec3b4cA1fcbb6816c0b17d643a
- added support for playing btimes replays (file names still need to be renamed) https://github.com/shavitush/bhoptimer/commit/fe1d01e1fbfc195e6c13cd07755fae6fba75c859
- tried to prevent zone beam flickering a bit https://github.com/shavitush/bhoptimer/commit/a62a5ca3bbe53e2b60f572b1e223af95f6528a5a https://github.com/shavitush/bhoptimer/commit/fe076df49e9ff475a3f98ec5486882b2ea9b1207
- fix thing that was wiping !wr menu cache https://github.com/shavitush/bhoptimer/commit/5eae3f686a5c794f6050781ed843fd84b3ee1f7c
- fix mvp star query not running https://github.com/shavitush/bhoptimer/commit/c25e3404b463ce99dfaa2c028d6081679290b5bd
- wrholder queries changed https://github.com/shavitush/bhoptimer/commit/8bc266241872a0d9362c9e204d4b78ad8bc52e75
- add more parameters to `Shavit_OnReplayStart` and `Shavit_OnReplayEnd` https://github.com/shavitush/bhoptimer/commit/f88885bafc976be31122fd2215c5de7d1b34aa78
- fixed tf2 linux bot creation https://github.com/shavitush/bhoptimer/commit/6e3bd85c14e87a4ea15ac384e802dbe02c97c107
- add dominatingme symbols for players who hold a wr on the current map https://github.com/shavitush/bhoptimer/commit/4d03e30e6fd2c607b0f3579f1f11b69a6cda269c
- fix tf2 uncrouch that would limit velocity https://github.com/shavitush/bhoptimer/commit/cfa724f7386bfc0263fd1aa3fbce54e16829731f
- added shavit_misc_prespeed_startzone_message https://github.com/shavitush/bhoptimer/commit/b602c5744073543a9811cd0e3668ab3a0b0842a9
- add playtime tracking. total time & also per-style. (replaces shavit-playtime by cam/whocodes) https://github.com/shavitush/bhoptimer/commit/670f220b76ed33bfab61181cc8b8e2d7a66b995b https://github.com/shavitush/bhoptimer/commit/d3b285f64517e836124bd86405d29e7bad6e86a1 https://github.com/shavitush/bhoptimer/commit/bf9b73180f5bfdf0420de36707c1a9dc9b18e8e1
- made !profile/!mapsdone/!mapsleft `<steamid>` work https://github.com/shavitush/bhoptimer/commit/b23542c1d8c7942192346380b05ae17b747f9e87 https://github.com/shavitush/bhoptimer/commit/0698a9d77ea7546f23204f5ba466e54a77dd9bc3
- `In End/Start Zone` is now only shown when you are inside a zone of your current track https://github.com/shavitush/bhoptimer/commit/ef5bf0c460416e89ca84d8bf6bb2a292041a9909
- fixed bullet sound/impact hook not working 100% of the time https://github.com/shavitush/bhoptimer/commit/24e6a0b9379475ee7d74c5a8edadc509c9c5fa14
- merged in shavit-mapchooser https://github.com/shavitush/bhoptimer/commit/d79cf72559e3eb6d7d0eb2c2335f4af9a78b76d6
	- many speed improvements. you can now use !map or !nominate with 6k maps and it won't lag :)
	- added `smc_prefix`, `smc_anti_spam`, `smc_maplist_type 4`, `smc_rtv_spectator_cooldown`, `smc_exclude_prefixes`, `smc_autocomplete_prefixes`, `smc_hide_rtv_chat`, `smc_nominate_delay`, `sm_extend` (alias of `sm_extendmap`), `smc_mapvote_extend_limit -1`
	- added something to stop segmented players from accidentally voting by blocking the menu for 1.75s https://github.com/shavitush/bhoptimer/commit/7342baabe4ca5e417f43392bdb794f63bffd87dd
	- duplicate maps don't show in the map vote menu anymore https://github.com/shavitush/bhoptimer/commit/fed35516f8a5ae8fa44610da7a43f7130167931c
- moved setting timescale for eventqueuefix events into the timer to handle some style settings (you'll also need to update eventqueuefix) https://github.com/shavitush/bhoptimer/commit/f8147a63f3e1f168a45fef7f3d639d88743792b0
- added `bhop_kirous` to shavit-mapfixes.cfg https://github.com/shavitush/bhoptimer/commit/3149fc63f605d599eb3b40e15f479f3e1575c329
- added track to zone log message https://github.com/shavitush/bhoptimer/commit/07a55bd2502035b203793cf86d7ff65623f2b76d
- !stats/!profile menu was made cooler by @NukoOoOoOoO & @Nairdaa https://github.com/shavitush/bhoptimer/pull/1077
- fixed being able to abuse endtouch boosters on segmented (requires eventqueuefix) https://github.com/shavitush/bhoptimer/commit/f4d8e557890765cb6fcac2e77c0e244df0376fa4
- migrated map names in db to be lowercase https://github.com/shavitush/bhoptimer/commit/f23bd4b96cc5fa7fcc45407022b88ea3b618f9f5
- updated csgo offsets for UpdateStepSound & GetPlayerMaxSpeed https://github.com/shavitush/bhoptimer/commit/5b522d31c5106ca945aa1b02463d4e0784eeb81a https://github.com/shavitush/bhoptimer/commit/06e9f2338b5a24661d617f141dff334089645768



# v3.0.6 - asdf - 2021-08-21 - rtldg
[`v3.0.5...v3.0.6`](https://github.com/shavitush/bhoptimer/compare/v3.0.5...v3.0.6)
https://github.com/shavitush/bhoptimer/releases/tag/v3.0.6
https://github.com/shavitush/bhoptimer/commit/c00ab666bedc92afdced75f89ce40ff8b2a1f129

- fix reset-checkpoints menu from being overlapped by the checkpoint menu reopening. thanks, haze https://github.com/shavitush/bhoptimer/commit/fc801e8a017d16789170575a85bde24879130986
- fixed some more errors that came up from the Shavit_OnDatabaseLoaded stuff https://github.com/shavitush/bhoptimer/commit/309421ad18f0644cc9e6e00537a8d3569e0c5f72 https://github.com/shavitush/bhoptimer/commit/599b276e42b2468a28014015d36d637ca548c990
- wr cache is now emptied on map end so you no longer see stale times on map change for a couple seconds https://github.com/shavitush/bhoptimer/commit/09f34bcef34d9e49783164dd9afb6edfba456dcc
- delayed bot name change to prevent crash in Host_Changelevel https://github.com/shavitush/bhoptimer/commit/f7cd8bf0721632601cd44e3ee25085e01a4dc5c2
- stopped timescale from being set to less-than-or-equal-to zero. this should fix the rare bug that'd cause people to be stuck on map change https://github.com/shavitush/bhoptimer/commit/455328610436a38614eebd11904f23014e6ef017



# v3.0.5 - asdf - 2021-08-20 - rtldg
[`v3.0.0...v3.0.5`](https://github.com/shavitush/bhoptimer/compare/v3.0.0...v3.0.5)
https://github.com/shavitush/bhoptimer/releases/tag/v3.0.5
https://github.com/shavitush/bhoptimer/commit/5687095144b87c64bc32ec1e7f43baf408270eac
https://github.com/shavitush/bhoptimer/commit/599b276e42b2468a28014015d36d637ca548c990 (v3.0.5-2) (replaced with zip with some more sql handle checks & a fix for the `Reset checkpoints` menu before you can fix it)

- The zone intersection checks now block start & end zones from intersecting. https://github.com/shavitush/bhoptimer/commit/6bcb16b3610cb488d57428a1db8838a103dec686 https://github.com/shavitush/bhoptimer/commit/e00b394356f40eaaf934871ebb17712f765f5139
- Fixed a number of things for replay bots using custom-frames
	- Fixed the broken `delay` parameter in `Shavit_StartReplay` and friends. https://github.com/shavitush/bhoptimer/commit/fc8b78ae43f76d89157be3a9f799e5f487d049f8
	- Fixed the HUD time when spectating a bot with custom-frames. https://github.com/shavitush/bhoptimer/commit/fc8b78ae43f76d89157be3a9f799e5f487d049f8 https://github.com/shavitush/bhoptimer/commit/11d2ae07859825d07ee6d2548c20bcdb5042c671
	- Added `Shavit_GetReplayCacheName` https://github.com/shavitush/bhoptimer/commit/f79335270d50a7f9796f1ad8c397b50b603de340 https://github.com/shavitush/bhoptimer/commit/d798de9cb2e5e98d65f4a15f1f72762b0fec85eb
- Added `kz_bhop_izanami` to `shavit-mapfixes.cfg` https://github.com/shavitush/bhoptimer/commit/f5a5f5e0c5f61676634f159782e1c0e86e0ee8fe
- Made the WR message2 (avg/max vel & perf percentage) only print for non-`autobhop` styles. https://github.com/shavitush/bhoptimer/commit/a373329499823b11685c2ef98323bf042ac9bde0
- Added `Shavit_OnRestartPre` to fix using `sm_r` to respawn from spectator. https://github.com/shavitush/bhoptimer/commit/3f14b65cc4a8c4b64c14a612218b0b1961fe33d2
	- The return value from `Shavit_OnRestart` is now ignored.
- Added `shavit_core_disable_sv_cheats` to block `sv_cheats` from being set. https://github.com/shavitush/bhoptimer/commit/140b43dd404af1fbb764c1992a0b06ea42e794fd https://github.com/shavitush/bhoptimer/commit/c5480e708751ad85c399ce217720fa94aad40f5e https://github.com/shavitush/bhoptimer/commit/9f313ee0cf7850c4b6e07ed8b46c298b96fb1d99 https://github.com/shavitush/bhoptimer/commit/4da5d528a631ebd661303fdeb47d8b1812e72274
	- The following commands can only be used by rcon admins now:
		- `ent_setpos`
		- `setpos`
		- `setpos_exact`
		- `setpos_player`
		- `explode <player>`
		- `explodevector <player> ...`
		- `kill <player>`
		- `killvector <player> ...`
		- `give`
		- Also, some of the cheat `impulse`s.
- The checkpoints menu will now reopen every 0.5s to help people who have bad internet https://github.com/shavitush/bhoptimer/commit/aa78c6fc0edf134ec296d2038e82157f02d1975c
- Weapons on the ground will now be removed every 10s if `shavit_misc_noweapondrops` is enabled. https://github.com/shavitush/bhoptimer/commit/c3ad16b418abef66cab9d4021a90933550f9b84d
- Nobody liked the replay postframes increasing the time at the end of the replay, so it was removed https://github.com/shavitush/bhoptimer/commit/2eb78a2a14aa722e33ef72f83368dbe02203ca3d
- Changed the `wrhrank*` family of TEMPORARY tables to be VIEWs instead https://github.com/shavitush/bhoptimer/commit/d4b61a474f2d77b35ff5ce07c630e406e8fce1cb
- Made sure [sm_closestpos](https://github.com/rtldg/sm_closestpos) handles are deleted when a replay is unloaded. https://github.com/shavitush/bhoptimer/commit/c8bcd75fa0fb5872e55fd11b7d566f83bd9deb3c
	- By the way, the releases page now has linux & windows binaries made from github actions. Thanks @fuckOff1703
- Prebuilt zones ([`mod_zone_*`](https://github.com/PMArkive/fly#trigger_multiple)) are inserted into the database now so things like `!mapsleft` work properly for them.
- Replay Props have been improved so you can now see entities that are outside your `AreaNum`! https://github.com/shavitush/bhoptimer/commit/2733faf57dff58d327b5922627d9e116db748a43
- Added `SHAVIT_LOG_QUERIES` https://github.com/shavitush/bhoptimer/commit/2b4d77d281d0c90be3871d51f73a09ac2b5a50ce



# v3.0.4 - asdf - 2021-08-08 - rtldg
https://github.com/shavitush/bhoptimer/releases/tag/v3.0.0
https://github.com/shavitush/bhoptimer/commit/eab31036a4b90f7d49898933559877434f96a990

- make mp_humanteam always apply
- prevent zones from being placed inside another zone
- fix grid snap visualization



# v3.0.3 - asdf - 2021-08-08 - rtldg
https://github.com/shavitush/bhoptimer/releases/tag/v3.0.0
https://github.com/shavitush/bhoptimer/commit/8009dbab88cafeddd6fb3b9d0cf686c311e6fb52 (probably...)

- added `shavit_misc_resettargetname_main` & `shavit_misc_resettargetname_bonus` to help with some more maps
- trim lines in convar_class so potentially remove erring crlfs
- reopen !replay menu only if still open
- fix some checkpoint/gravity/timescale/speed related stuff
- make mapname buffers all use PLATFORM_MAX_PATH
- add missing parameters to function declaration
- add bhop_space & bhop_crash_egypt to shavit-mapfixes.cfg
- make {styletag} & {style} work for !replay bots again



# v3.0.2 - asdf - 2021-07-31 - rtldg
https://github.com/shavitush/bhoptimer/releases/tag/v3.0.0
https://github.com/shavitush/bhoptimer/commit/8a8db13c4a74f9e9c0c22f2e4a5835432c9a85ed

- fix error from gH_SQL being null in OnMapEnd after server restart



# v3.0.1 - asdf - 2021-07-30 - rtldg
https://github.com/shavitush/bhoptimer/releases/tag/v3.0.0
https://github.com/shavitush/bhoptimer/commit/32658a029d0aa35ca646434a8518f700d62ac624

- update eventqueuefix header
- mark shavit-wr as required in notes
- fix shavit_misc_hideteamchanges on css
- make Shavit_OnDatabaseLoaded run after migration like it's supposed to



# v3.0.0 - Fluffytail Edition - 2021-07-29 - rtldg
[`v2.6.0...v3.0.0`](https://github.com/shavitush/bhoptimer/compare/v2.6.0...v3.0.0)
https://github.com/shavitush/bhoptimer/releases/tag/v3.0.0
https://github.com/shavitush/bhoptimer/commit/9adf78d311192f91ccf32edf9decb72fa1597313

(originally this was going to be v2.7.0 but it took too long and had too many changes so it became v3.0.0 and also the `very_good_yes` was deprecated with the bump to v3.0.0)

## This update breaks plugins using natives with enum structs along with removing some natives. Recompile any plugin that uses shavit.inc. Also `stylesettings_t` was removed so anything that uses that will need to be changed, but it's easy to fix.
## Also, make sure to post any errors or problems you find in the github issue tracker or in the `#timer-support-here` channel of the bhoptimer discord https://discord.gg/jyA9q5k

## Update Notes TL;DR (the most notable things):
- You can now make a total of 8 bonuses.
- `!r` now goes to the most recent track. `!main`/`!m` was added to go to the main track.
- Multiple replay bots can be spawned simultaneously. Also you can make replay bots that loop styles & tracks.
- The `!replay` menu now has options to skip forwards, skip backwards, and play at 2x speed.
- The stage times from the WR run will now be saved (if you add stage zones).
- Support added for [`hermansimensen/eventqueue-fix`](https://github.com/hermansimensen/eventqueue-fix) to allow timescaling map events and help prevent some map exploits.
- Postframes added to replays.
- More efficient time-difference calculation possible with [`rtldg/sm_closestpos`](https://github.com/rtldg/sm_closestpos)
- Times should now be slightly more accurate by basing off tick-interval instead of frame-time.

## Concommands
- added `sm_ccadd <steamid>` and `sm_ccdelete <steamid>` to give ccname&ccmsg access via steamid instead of adding them with admin flags or something (https://github.com/shavitush/bhoptimer/issues/861). https://github.com/shavitush/bhoptimer/commit/19c5ccb7f38cc793f974a2c118c1c10ccc20e71a
- `sm_recalcall` and `sm_recalcmap` should be faster now.
- added `sm_toggleadverts` for clients.
- Multiple bonus typo convenience commands added. `sm_b1`, `sm_b2`, etc through to `sm_b8`.
- Multiple stage typo convenience commands added. `sm_s1`, `sm_s2`, etc through `sm_s9`.
- `!r` now resets your timer back to the track you were previously on. `!main`/`!m` was added to move you back to the main track
- `sm_p` has been changed to be an alias of `sm_profile` instead of noclip. You'll probably want to use `sm_nc` now.
	- `sm_noclip` can now be used as an alias of the timer noclip commands. https://github.com/shavitush/bhoptimer/commit/dd756b95cc77eec8cc2ccafd855a86628a213d9e
- `sm_loadunzonedmap` to load the next unzoned map from the `maps` folder (doesn't include workshop maps or sub-folders).
- `sm_save` will now refresh an open checkpoint menu.

## Convars
- added `shavit_rankings_default_tier`. (https://github.com/shavitush/bhoptimer/issues/1041)
- renamed `shavit_stats_mvprankones` to `shavit_rankings_mvprankones`.
- renamed `shavit_stats_mvprankones_maintrack` to `shavit_rankings_mvprankones_maintrack`.
- `shavit_misc_prespeed` gained `5 - Limit horizontal speed to prestrafe but allow prespeeding.` https://github.com/shavitush/bhoptimer/commit/70ae9bc4cbdafdfa7ff0232161f876390ae0a381
- `shavit_hud_timedifference` renamed to `shavit_replay_timedifference`
- added `shavit_replay_timedifference_tick` to change often the time/velocity difference values are updated.
- `shavit_misc_hideradar` will now force `sv_disable_radar` on CS:GO. https://github.com/shavitush/bhoptimer/commit/6229900bafbc51bd2de4c463a40636e53fa865bd
- added `shavit_replay_dynamicbotlimit` to set how many replay bots can be spawned by players.
- added `shavit_replay_allowpropbots` to enable/disable Prop (prop_physics) Replay Bots.
- added `shavit_core_timeinmessages` to print the server time before chat messages and timer messages. https://github.com/shavitush/bhoptimer/commit/7df2e2c959cd1eb5ad271d0aa914e848512e7375
- added `shavit_misc_botfootsteps` to toggle replay bot footstep sounds. https://github.com/shavitush/bhoptimer/commit/c4520b7ab826ea5cfe395fc91c4607a81c0f39bb https://github.com/shavitush/bhoptimer/commit/3c5fa5e07b5c2b9556355b92923ccfe0bea7d840 https://github.com/shavitush/bhoptimer/commit/4d797d234712c0c4fae29d798088195b205a97c8
- added `{cr}` as an option for `shavit_misc_clantag`
- added `shavit_misc_weaponcommands 3` to give infinite clip ammo (useful for CSS which doesn't have `sv_infinite_ammo`). https://github.com/shavitush/bhoptimer/commit/6bd7b0af0ea38c27b8ccafa6fe69a626352e4f88
- added `shavit_replay_postruntime` to set how long postframes should record. https://github.com/shavitush/bhoptimer/commit/28e9d4029b7010d6933b8d775cb2098c6b09d379
- fixed `shavit_misc_godmode 1` (no fall damage) not working (https://github.com/shavitush/bhoptimer/pull/1051)
	- spectators being aimpunched has been fixed also. https://github.com/shavitush/bhoptimer/commit/4f23ec879173000861fddbb11304e890af1c3db6
- added `shavit_misc_weaponsspawngood` to make glocks spawn on burst-fire and USPs to spawn with a silencer on.
- added `shavit_core_pause_movement` to allow player movement/noclip while paused. (https://github.com/shavitush/bhoptimer/pull/1067)
- added `shavit_zones_prebuilt_visual_offset` to adjust the visual zones for maps like `bhop_amaranthglow` and `bhop_tranquility`
- added `shavit_misc_experimental_segmented_eyeangle_fix` to fix segmented replays have bad eye-angles when teleporting to a checkpoint. https://github.com/shavitush/bhoptimer/commit/aff3f95813d05ffe55a6e805515477918da42759

## Misc
- Allow !goto/!tpto from start/end zone (https://github.com/shavitush/bhoptimer/pull/963)
- only print the stage time message once per stage (https://github.com/shavitush/bhoptimer/pull/965)
- allow !resume when not on the ground (https://github.com/shavitush/bhoptimer/pull/966)
- Multiple bonuses (1-8) added (https://github.com/shavitush/bhoptimer/pull/982)
	- Bonus1 settings are copied to any bonuses that don't have settings in `shavit-zones.cfg`
- Persistent-data, savestates, and checkpoints have been improved.
	- Can now checkpoint onto a ladder thanks to `m_vecLadderNormal`.
	- Fixed segmented checkpoints from starting in practice mode sometimes (https://github.com/shavitush/bhoptimer/issues/1023)
	- Persistent data is now kept when changing map to the same map. This is done because of server hibernation causes map changes a lot on csgo which is annoying.
	- reduced some allocations and ArrayList cloning
	- fixed persistent data & savestates spawning you in the wall if you were ducked in a tunnel.
- Add support for https://github.com/hermansimensen/eventqueue-fix
	- boosters & map outputs can be saved in checkpoints to prevent cheesability
	- events are paused from running when the timer is paused (although this still needs to be worked on)
- increased top left WR hud buffer size to handle long player names (https://github.com/shavitush/bhoptimer/pull/1050)
- changed replay bot score from 2000 to 1337 (https://github.com/shavitush/bhoptimer/pull/1059)
- initial [DynamicChannels](https://github.com/Vauff/DynamicChannels) stuff added (which probably doesn't work too well)
- Fix exploit allowing extra height on spawn. https://github.com/shavitush/bhoptimer/commit/f7c878b8f1f75cb88a207c587d701d09507fb1a3
- Speculative exploit fix for passing through zones or something. https://github.com/shavitush/bhoptimer/commit/976fc90d87972bb379be743e74f2592926fd774b
- Speculative fix for timers starting when you're not on the ground. https://github.com/shavitush/bhoptimer/commit/3f7d3e3a5980ca644fc45762edf200f529c6860c
- Fixed bug that caused style command callbacks to register twice.
- Improve zone drawing cycle stuff.
- Various SQL query changes to hopefully improve the speed of some things.
- Replay bots now do a (jank) jump animation (https://github.com/shavitush/bhoptimer/pull/1046)
- Block SHSW on HSW while still allowing `+back` to be used in the air to stop. (https://github.com/shavitush/bhoptimer/pull/973)
- Removed restart warning for segmented styles.
- Fixed `player_speedmod` and timescaled styles interacting. For example the bhop_voyage hot air balloon level now works timescaled. https://github.com/shavitush/bhoptimer/commit/6db6b5f3cf70fb9bd5df99e7a63f079633b69460
  - edit 2021-11-08: also `speed` and `timescale` both affect styles now since some commit somewhere... slow mo was affected. just remove the `"speed" "0.5"` and it should work how it used to
- Setspawn/setstart for each player added. !sp / !ss / !delss / !delsp (https://github.com/shavitush/bhoptimer/pull/1028)
- Added velocity difference to the HUD from the closest replay time position. https://github.com/shavitush/bhoptimer/commit/8b48ae8c917f972e18af3a1456ce77e6714ba668
- Removed `base.nav` by embedding it in shavit-replay.sp.
- .nav files are now written for all maps on plugin start. https://github.com/shavitush/bhoptimer/commit/91ccae3509c3b92d2d1e419da79fe8619aba6179
- .nav files can now be loaded without needing to changelevel. https://github.com/shavitush/bhoptimer/commit/0448297994322ee2f5f8f69f75abcc9056d7d25c
- Show wrs and blank styles on `!wr notcurrentmap`. https://github.com/shavitush/bhoptimer/commit/dcb9595f1affe3c95badb5c93eaf62a10efa4711
- Menus now stay open forever unless closed.
- Zone editing and creation modifiers and grid-snap values will now be saved between menu usages. https://github.com/shavitush/bhoptimer/commit/11137e940706c4a0c1383c6f432923e9449b6cd6
- Changed TraceRay masks to use MASK_PLAYERSOLID for zone snapping. (https://github.com/shavitush/bhoptimer/pull/1032)
- fixed worse-time completion messages not printing for spectators.
- !keys menu had changed a bit.
	- `+left`/`+right` are now visible in the !keys menu (https://github.com/shavitush/bhoptimer/pull/980)
	- added angle difference arrows (similar btimes) to !keys. https://github.com/shavitush/bhoptimer/commit/3750c8edebb2d7a590b75dff9e64af836a592792
	- another https://github.com/shavitush/bhoptimer/commit/5a4acc49a444e308e47759a7724e71157081cbcc
- blocked pausing while ducking. https://github.com/shavitush/bhoptimer/commit/d272aae97b62371753d2c07f94f0eab2f4cabdd7
- fixed csgo team menu being open on join and also needing to be closed twice. https://github.com/shavitush/bhoptimer/commit/6386577ef4149c3676d79f37e9675e15a7c85518
- fix checkpoints not saving timescale. https://github.com/shavitush/bhoptimer/commit/5c772b06e387f00d1712fc47cadbba9784c8c9e4
- The `playertimes` table added `exact_time_int` which will be used to save the exact time value since there's some rounding problems with float-formatting & database handling. https://github.com/shavitush/bhoptimer/commit/a6be0127ee9d44c82cfe146e0da22d255398f825
- fix bug with shavit-timeleft repeatedly calling `Shavit_StopChatSound`.
- The weapon commands, `sm_glock`, `sm_usp`, and `sm_knife`, now have rate-limiting to prevent the server from spawning too many entities and crashing. https://github.com/shavitush/bhoptimer/commit/82918f194535b990215822fa13df53adb1b023ea
- fixed the original zone disappearing if you are editing zones and then cancel. https://github.com/shavitush/bhoptimer/commit/328f4301aaf7612ceccbf9195c2856d9571ea63e
- Spawns created by `shavit_misc_createspawnpoints` will only fill in missing spawnpoints now and will not create extra. https://github.com/shavitush/bhoptimer/commit/576534092becc4556f8d2faa90ef086e88588970 https://github.com/shavitush/bhoptimer/commit/fdacc94c3221e92cb225bfe6779fc62e506741f6
	- A couple of hooks have been added to make all spawnpoints valid for spawning and to skip "Team is full" checks for bots. https://github.com/shavitush/bhoptimer/commit/50d000c20eac229c65a3d8144e27fbfb58cde3e1 https://github.com/shavitush/bhoptimer/commit/d5713824ceb8484ed7de0f2dd94a75d31ecf81d1
- fixed a bug that'd give 2 completions on initial map finish. https://github.com/shavitush/bhoptimer/commit/7b4d2f5b23cc467f30273caca525148bfcb62d4f https://github.com/shavitush/bhoptimer/commit/ca6ad88b7b0b0d72b45872e1266531f6e651fa38
	- A migration was added to subtract 1 from all completions in the database to correct older times that were affected. https://github.com/shavitush/bhoptimer/commit/4f704a2fe45a5895522928c5287c9d1739b3613a
- The zone start-point and end-point are now blocked from being placed in the same x or y axis. aka: no zero-width zones. https://github.com/shavitush/bhoptimer/commit/57e6f9563d56f96c919fb6ac56c3cd677edca739
- More radio commands and pinging commands where added to the radio blocklist. https://github.com/shavitush/bhoptimer/commit/793116d476b91bcbd9cfd0b2c4f6f264f9e47187 https://github.com/shavitush/bhoptimer/commit/35de299212731c869d9447f5ae9f78965a3ef329
- `Shavit_PrintToChatAll` changed into a native to decrease some allocations and also to work with `Shavit_StopChatSound`. https://github.com/shavitush/bhoptimer/commit/cdc0c651b965213a1609ec23c9c65f4f5e1f204c
- CS:S and TF2 center hud thing now hides when the scoreboard is open so less flickering is shown. https://github.com/shavitush/bhoptimer/commit/00fa237c28b6aa7db42e98069649861d4def181c
- reset stamina on landing for csgo easybhop so you don't have to change `sv_staminalandcost` (unless you want to) https://github.com/shavitush/bhoptimer/commit/7117b38038a92981f7aaf381c2ddf43accdce582
- avg/max velocity added to run completion (2nd) message.
	- calculates based on the velocity from every frame instead of velocity on jump. (so it works well with surf)
- added support for https://github.com/rtldg/sm_closestpos (C++ extension) to improve closest position finding speed.
	- `sm_closestpos(0.000006s)` -- `sourcepawn(0.011590s)` (time needed to locate closest position with a long badges replay i had)
- Added looping, dynamicly spawning, and physics_prop replay bots. https://github.com/shavitush/bhoptimer/commit/9e43f67fc3a66554b3d8ec253332a8b511d1d9d1 (there's many more commits, but that's the initial one)
	- Looping bots will repeat any replays on tracks and styles specified for it in `shavit-replay.cfg`.
	- Dynamic bots allow multiple replay bots to be spawned by different players so replay bot hogging isn't as problematic.
	- Prop replay bots are physics_props that the client spectates and don't take a player slot.
		- Currently does not work well with area portals, func_illusionary stuff, and anything that is generally in a different "area".
	- `bot_join_after_player` is now used to determine whether to spawn bots in an empty server.
		- Here's some relevant convars to disable CS:GO server hibernation or bot-kicking:
		```
		sv_hibernate_postgame_delay 9999999
		sv_hibernate_punt_tv_clients 0
		sv_hibernate_when_empty 0
		bot_auto_vacate 0
		bot_join_after_player 0
		mp_autokick 0
		```
- Removed usage of `bot_quota` and started to call BotAddCommand directly which works really well and is really cool and I love it. bot_quota sucks. https://github.com/shavitush/bhoptimer/commit/57e9072b195ff24fcec9eb28316f2791c72a89d0
- Replay playback should work a bit better if the tickrate was changed by TickrateControl (https://github.com/shavitush/bhoptimer/pull/1018).
- Post-run frames / postframes added to replays. https://github.com/shavitush/bhoptimer/commit/28e9d4029b7010d6933b8d775cb2098c6b09d379
- usercmd mousex/mousey and forwardmove/sidemove added to replay file.
- When spectating replays, the percentage-complete now goes below 0% for preframes and above 100% for postframes.
- Fixed replay bots teleporting on the last frame of a replay and screwing up prediction.
- the `!replay` menu now includes +1s, -1s, +10s, -10s, and 2x speed options to rewind/fastforward. https://github.com/shavitush/bhoptimer/commit/a2735d8a2a322d6cb25d0617c49ee9563e3a3be9
- Stage stuff: https://github.com/shavitush/bhoptimer/commit/2697e6c5b1ed3de7464f60c7177f4eaba8acc6b6 and https://github.com/shavitush/bhoptimer/commit/96281d2f85fb570e15f18ae2ff5038b875763796
	- prebuilt map stages using mod_zone_checkpoint_X / mod_zone_bonus_X_checkpoint_X work now https://github.com/shavitush/bhoptimer/commit/2d39b90564826fc7fc97172d86868fbfe6bcc3e0
		- Check out https://github.com/PMArkive/fly#trigger_multiple for the format used for prebuilt map zones

## Timer configs
- `shavit-styles.cfg`
	- `force_timescale` added. https://github.com/shavitush/bhoptimer/commit/f997d4e54468d930da356031dd22f64d26f8b44d
- `shavit-zones.cfg`
	- Zone beams can now be changed for each zone type.
		- `beam` - the custom beam path for the zone type.
		- `vanilla_sprite` - whether to use the default sprite or the timer's sprite.
		- `no_halo` - whether the zone should have a halo drawn for it.
	- Added `beam_ignorez` to draw zone beams through walls (https://github.com/shavitush/bhoptimer/issues/618)
- `shavit-chat.cfg`
	- added `w` (WR Count) and `W` (rank out of WR holders) options to the `ranks` filtering
	- added `{pts}`, `{wrs}`, and `{wrrank}` for chat ranks
- `shavit-replay.cfg`
	- `"Looping Bots"` section added to configure looping bots.
	- You can grab the default config from here: https://github.com/shavitush/bhoptimer/blob/eab31036a4b90f7d49898933559877434f96a990/addons/sourcemod/configs/shavit-replay.cfg#L37-L84
- `shavit-mapfixes.cfg`.
	- Sets convars on certain maps.
	- Currently used to adjust prebuilt-zone visual-offsets on a few maps and to disable `shavit_misc_resettargetname` to the timer doesn't break some maps.

## API
- Constants, enums, and defines:
	- Added `MAX_STAGES`
	- There's 8 bonuses now. `Track_Bonus` (1) through `Track_Bonus_Last` (8)
	- Removed `Replay_Legacy`
	- Added `Replay_Dynamic` and `Replay_Prop`
	- enums `ReplayStatus` and `ReplayBotType` have been de-typed so the values can be used as ints.
	- `REPLAY_FORMAT_SUBVERSION` is now up to `0x08` (+4)! Progress!
- Added natives:
	- `Shavit_GetStyleSetting`, `Shavit_GetStyleSettingInt`, `Shavit_GetStyleSettingBool`, `Shavit_GetStyleSettingFloat`, `Shavit_HasStyleSetting`, `Shavit_SetStyleSettingFloat`, `Shavit_SetStyleSettingBool`, and `Shavit_SetStyleSettingInt`
		- Any key in `configs/shavit-styles.cfg` can now be grabbed with these
		- Probably will be used to replace `specialstring` usage eventually
	- `Shavit_WRHolders`, `Shavit_GetWRHolderRank`.
	- `Shavit_GetTimesTeleported` - Eventually the value from this will be stored in the database.
	- `Shavit_SetStart` / `Shavit_DeleteSetStart`.
	- `Shavit_GetClosestReplayStyle` - Returns the style currently being used for the client's time/velocity difference.
	- `Shavit_SetClosestReplayStyle` - Can be used to change the style used for the client's time/velocity difference to compare a Normal time to a Segmented time for example.
	- `Shavit_GetClosestReplayVelocityDifference` - Returns the velocity difference between the client and closest position of the target replay.
	- `Shavit_GetStyleStringsStruct` - Fills a `stylestrings_t` as an alternative to `Shavit_GetStyleStrings`.
	- `Shavit_GetChatStringsStruct` - Fills a `chatstrings_t` as an alternative to `Shavit_GetChatStrings`.
	- `Shavit_GetAvgVelocity` - Retrieves the player's average (2D) velocity throughout their run.
	- `Shavit_GetMaxVelocity` - Retrieves the player's highest (2D) velocity throughout their run.
	- `Shavit_DeleteWR`
	- `Shavit_IsReplayEntity` - Returns true if the entity is a replay bot client or replay bot physics prop.
	- `Shavit_GetReplayStarter` - Returns the client who started the replay entity.
	- `Shavit_GetReplayButtons` - Returns the buttons for the replay's current tick. Added since otherwise there'd be no way to grab a Replay_Prop's buttons. Also angle-difference so we can see it in !keys.
	- `Shavit_GetReplayCacheFrameCount` - Retrieves the frame count from the replay bot's frame_cache_t.
	- `Shavit_GetReplayCacheLength` - Retrieves the replay length from the replay bot's frame_cache_t.
	- `Shavit_StartReplayFromFrameCache` - Can be used to start replay bots with a custom frames. Useful for playing a replay downloaded from a global replay database or something.
	- `Shavit_StartReplayFromFile` - Can be used to start replay bots with a custom frames. Useful for playing a replay downloaded from a global replay database or something.
	- `Shavit_GetClientLastStage` - Retrieves the clients highest stage number in their current run.
	- `Shavit_GetStageWR` - Retrieves the WR run's stage time (if it exists).
	- `Shavit_GetLoopingBotByName` - Used to find a looping replay-bot client-index from the loop-config name.
- Stocks:
	- `GetSpectatorTarget` added to shavit.inc. Target might NOT be a client (like when watching a `Replay_Prop`)
	- `GetTrackName` added to shavit.inc.
	- `SteamIDToAuth` added to shavit.inc. Converts `STEAM_0:1:61` and `[U:1:123]` to `123`.
		- Now used by `sm_wipeplayer`, `sm_ccadd`, and `sm_ccdelete`.
- Changed natives:
	- `Shavit_OnStart` can **NOT** stop StartTimer anymore. Use `Shavit_OnStartPre` to stop StartTimer.
	- `Shavit_HijackAngles` now has a `int ticks` parameter.
	- `Shavit_GetWRCount` now has parameters for style and track.
	- `Shavit_GetClosestReplayTime(client, style, track)` -> `Shavit_GetClosestReplayTime(client)`
	- `void Shavit_GetReplayBotFirstFrame(int style, float &time)` -> `float Shavit_GetReplayBotFirstFrame(int entity)`
	- `Shavit_GetReplayBotIndex(int style)` -> `Shavit_GetReplayBotIndex(int style, int track)`
	- `Shavit_GetReplayBotCurrentFrame(int style)` -> `Shavit_GetReplayBotCurrentFrame(int entity)`
	- `Shavit_GetReplayTime(int style, int track)` -> `Shavit_GetReplayTime(int entity)`
	- `Shavit_StartReplay` now returns an replay entity index (`int`) instead of a `bool`.
	- `Shavit_GetReplayBotFirstFrame` renamed to `Shavit_GetReplayBotFirstFrameTime`
	- `Shavit_GetReplayPreFrame` renamed to `Shavit_GetReplayPreFrames`
	- `Shavit_GetReplayPostFrame` renamed to `Shavit_GetReplayPostFrames`
	- `Shavit_GetReplayCachePreFrame` renamed to `Shavit_GetReplayCachePreFrames`
	- `Shavit_GetReplayCachePostFrame` renamed to `Shavit_GetReplayCachePostFrames`
	- `Shavit_GetPlayerPreFrame` renamed to `Shavit_GetPlayerPreFrames`
	- `Shavit_GetTimeOffset` replaced with to `Shavit_GetZoneOffset`
- Changed Structures:
	- `timer_snapshot_t` now includes `fAvgVelocity`, `fMaxVelocity`, `fTimescale`, `iZoneIncrement`, and `fTimescaledTicks`.
		- `fTimeOffset` was replaced with `fZoneOffset`.
	- `cp_cache_t` now includes `iSteamID`, `aEvents`, `aOutputWaits`, and `vecLadderNormal`
		- `iTimerPreFrames` removed.
- Removed Structures:
	- `stylesettings_t` - Use some of the new GetStyleSetting natives.
- Removed natives:
	- `Shavit_GetStyleSettings` - Use some of the new Shavit_GetStyleSetting* natives instead.
	- `Shavit_GetGameType` - Use `GetEngineVersion` instead.
	- `Shavit_GetDB` - Use `Shavit_GetDatabase` instead.
	- `Shavit_GetTimer` - Use different natives.
	- `Shavit_GetWRTime` - Use `Shavit_GetWorldRecord` instead.
	- `Shavit_GetPlayerPB` - Use `Shavit_GetClientPB` instead.
	- `Shavit_GetPlayerTimerFrame`
	- `Shavit_SetPlayerTimerFrame`
- Changed forwards:
	- `Shavit_OnUserCmdPre` no longer has the `stylesettings_t` parameter. Use some of the Shavit_GetStyleSetting* natives with the option names from shavit-styles.cfg instead. Examples: `Shavit_GetStyleSettingBool(style, "unranked")` or `Shavit_GetStyleSettingInt(style, "prespeed")`
	- `Shavit_OnTimeIncrement` no longer has the `stylesettings_t` parameter.
	- `Shavit_OnTimeIncrementPost` no longer has the `stylesettings_t` parameter.
	- `Shavit_OnFinish` gained `float avgvel, float maxvel, int timestamp`
	- `Shavit_OnFinish_Post` gained `float avgvel, float maxvel, int timestamp`
	- `Shavit_OnFinishMessage` now has a `message2` parameter that is used to print an extra message to spectators and the player. Curently prints avg/max velocity and perf percentage. https://github.com/shavitush/bhoptimer/commit/435a23f065cf45ca97248ae80ad84ae64c3fee9d
	- `Shavit_OnWorldRecord` gained `float avgvel, float maxvel, int timestamp`
	- `Shavit_OnTopLeftHUD` will now run more often so plugins like https://github.com/rtldg/wrsj can show the SourceJump WR in the top-left all the time.
- Added forwards:
	- `Shavit_ShouldSaveReplayCopy` - Called when a player finishes a run and can be used to save a copy of the replay even if it is not a WR.
	- `Shavit_OnStartPre` - Used to potentially block StartTimer from starting a player's timer. Previously `Shavit_OnStart` would've been used.
	- `Shavit_OnReplaySaved` - Called when a replay (WR or copy) has been saved. **SourceJump replay uploader should use this now**



# v2.6.0 - Community Update Edition - 2020-11-23 - kidfearless
[`v2.5.7a...v2.6.0`](https://github.com/shavitush/bhoptimer/compare/v2.5.7a...v2.6.0)
https://github.com/shavitush/bhoptimer/releases/tag/v2.6.0
https://github.com/shavitush/bhoptimer/commit/06addf326f155b05f63acec78b816406a3aaaad5 (v2.6.0)
https://github.com/shavitush/bhoptimer/commit/cbda66670072ee3dddeb4e309b6ebfaea5291d7e (v2.6.0-1) -- Included fix for Shavit_SaveCheckpoint native

## This update breaks plugins using natives with enum structs. To fix simply recompile broken plugins with latest shavit.inc
## DHooks is no longer an optional requirement for the timer. You will need it installed in order to use the new precise ticking method

* GuessBestMapName moved to shavit.inc
* Tidied up shavit-chatsettings.cfg loading to throw a better exception if not present(Thanks gammacase)
* Added accountid validation to replay deletion (Thanks deadwinter)
* PB's are now reset on players if they are connected when their replay is deleted.
* Times are now incremented after a players movement has been processed in order to more accurately track times and prevent exploits.
* HUD default values can now be set from a convar.
* Turn binds now show up in keys panel
* Players can now enable seeing their rank for the given time in the top left hud.
* Checkpoints are now stored in an arraylist and can be deleted individually.
* Radar and flash are now removed constantly to prevent being displayed again.
* Stamina is now reset inside OnRestart as well.
* Added OnPlay forward to allow for dynamic wr sounds.
* Spectate bot if using the !replay command while alive.
* Implemented a fix for rounds restarting in single round servers into shavit-timelimit.
* Added enable/disable convars to minor shavit plugins.
* fix using -1 for shavit_misc_persistdata
* fix error that happens if you 'sm_tele 0' with no checkpoints
* don't set FL_ATCONTROLS when dead/spec so you can freecam while paused
* Added ProcessMovement forwards for easier access.

Big thanks to Gammacase, rtldg, nairdaa, deadwinter, carnifex, and SaengerItsWar for the majority of contributions to the development of the timer this update.

## Convars
* `shavit_core_useoffsets` - Calculates more accurate times by subtracting/adding tick offsets from the time the server uses to register that a player has left or entered a trigger.
* `shavit_hud_timedifference` - Enabled dynamic time differences in the hud.
	* Recommended to be left off.
* `shavit_hud_specnamesymbollength`  - Maximum player name length that should be displayed in spectators panel.
* `shavit_hud_default` - Default HUD settings as a bitflag
	* see description for bitflag values.
 * `shavit_hud2_default` - Default HUD2 settings as a bitflag
	 * see description for bitflag values.
* `shavit_sounds_enabled` -  Enables/Disables functionality of the shavit sounds plugin.
* `shavit_timelimit_gamestartfix` - If set to 1, will block the round from ending because another player joined. Useful for single round servers.
* `shavit_timelimit_enabled` - Enables/Disables functionality of the shavit timelimit plugin.
* `shavit_replay_timedifference_cheap` - Disabled 1 - only clip the search ahead to shavit_replay_timedifference_search 2 - only clip the search behind to players current frame 3 - clip the search to +/- shavit_replay_timedifference_search seconds to the players current frame.
	* Recommended value if set is 3.
* `shavit_replay_timedifference_search` - Time in seconds to search the players current frame for dynamic time differences 0 - Full Scan
	* Note: Higher values will result in worse performance
	* Recommended value if set is 10.

## API
* Changed Structures:
	* `timer_snapshot_t` now contains time and distance offsets.
* Changed natives:
	* `Shavit_DeleteReplay` now passes in the accountid to be validated against, 0 to skip.
* Added natives:
	* `Shavit_GetStageZone` - Retrieve the zone ID for a given stage number. Will return exception if stage number doesn't have a zone.
	* `Shavit_SetClientPB` - Sets the cached pb directly for the given client, style and track.
	* `Shavit_GetClientCompletions` - Retrieves the completions of a player.
	* `Shavit_StartReplay` - Starts a replay given a style and track.
* Changed forwards:
	* `Shavit_OnWRDeleted` - Added accountid of deleted record.
* Added forwards:
	* `Shavit_OnDelete` - Called when a player deletes a checkpoint.
	* `Shavit_OnPlaySound` - Called before a sound is played by shavit-sounds.
	* `Shavit_OnProcessMovement` - Called before the server & timer handle the ProcessMovement method.
	* `Shavit_OnProcessMovementPost` - Called After the server handles the ProcessMovement method, but before the timer handles the method.



# v2.5.7a - asdf - 2020-07-07 - kidfearless
[`v2.5.6...v2.5.7a`](https://github.com/shavitush/bhoptimer/compare/v2.5.6...v2.5.7a)
https://github.com/shavitush/bhoptimer/releases/tag/v2.5.7a
https://github.com/shavitush/bhoptimer/commit/7567cde52df2adf0461984db72fb60531c331f8e

## This update breaks plugins using natives with enum structs. To fix simply recompile broken plugins with latest shavit.inc
## If you have performance issues after this update, disable dynamic time difference.

* Added preruns to replays. Thanks @deadw1nter
* Added dynamic time difference. Thanks again rellog, and @deadw1nter
* Implemented hintfix for csgo players to reduce memory leaks.
* Fix for adminmenu late load or reload. Thanks @Kxnrl
* Added `jump_multiplier` and `jump_bonus` to shavit-styles
* Increased dynamic memory size
* Syntax fix for MySQL 8.0
* Fixed perf jump detection being slightly off

## Convars
* `shavit_hud_csgofix` - Apply the csgo color fix to the center hud? This will add a dollar sign and block sourcemod hooks to hint message
* `shavit_replay_preruntime` - Time (in seconds) to record before a player leaves start zone. (The value should NOT be too high)
* `shavit_replay_prerun_always` - Record prerun frames outside the start zone?
* `shavit_misc_restrictnoclip` - Should noclip be be restricted?
	* 0 - Disabled
	* 1 - No vertical velocity while in noclip in start zone
	* 2 - No noclip in start zone
* `shavit_zones_box_offset` - Offset zone trigger boxes by this many unit
	* 0 - matches players bounding box
	* 16 - matches players center

## API
* Added natives:
	* `Shavit_GetReplayStatus` - Gets the replay status.
	* `Shavit_SaveCheckpoint` - Saves a new checkpoint and returns the new checkpoint index.
	* `Shavit_GetCurrentCheckpoint` - Gets the current checkpoint index.
	* `Shavit_SetCurrentCheckpoint` - Sets the current checkpoint index.
	* `Shavit_GetPlayerPreFrame` - Returns the number of preframes in the players current run.
	* `Shavit_SetPlayerPreFrame` - Sets player's preframe length.
	* `Shavit_GetClosestReplayTime` - Gets time from replay frame that is closest to client.
	* `Shavit_GetPlayerTimerFrame` - returns the number of timer preframes in the players current run.
	* `Shavit_SetPlayerTimerFrame` - Sets player's timer preframe length.
* Added forwards:
	* `Shavit_OnCheckPointMenuMade` - Called after the checkpoint menu has been made and before it's sent to the client.
	* `Shavit_OnCheckpointMenuSelect` - Called when before a selection is processed in the main checkpoint menu.
	* `Shavit_OnTimescaleChanged` - Called when a clients dynamic timescale has been changed.



# v2.5.6 - asdf - 2020-01-23 - kidfearless
[`v2.5.5a...v2.5.6`](https://github.com/shavitush/bhoptimer/compare/v2.5.5a...v2.5.6)
https://github.com/shavitush/bhoptimer/releases/tag/v2.5.6
https://github.com/shavitush/bhoptimer/commit/c8467630ab94c295a740270b888f3d7a68ef54b7

## This update contains changes that may alter your plugin configs. Be sure to backup your plugin configs beforehand.
## This update contains changes to the shavit-zones translation files, as well as the zones config files. Update accordingly.

* Added stage zone to shavit-zones. Accessible via `sm_stages` and `sm_stage`.
* Moved convars into an auto-updating convar methodmap.
* Moved cp_cache_t enum struct into shavit.inc for native usage.
* Added dynamic timescales for styles like TAS.
* Fixed `Shavit_GetReplayBotCurrentFrame` pointing to the wrong native callback.
* Selecting an unfinished map from the !profile menu, will attempt to nominate it for the client.
* Removed extra bracket. Thanks @SaengerItsWar
* Permission flags inside shavit-styles.cfg no longer need a command override to work.
* Chat messages from `sm_tele` are now suppressed.
## Console Variables

* `shavit_misc_bhopsounds` - Should bhop (landing and jumping) sounds be muted? 0 - Disabled 1 - Blocked while !hide is enabled 2 - Always blocked

## API
* Added natives:
  * `Shavit_GetTotalCheckpoints` - Gets the total number of CPs that a client has saved.
  * `Shavit_GetCheckpoint` - Gets CP data for a client at the specified index. See cp_cache_t.
  * `Shavit_SetCheckpoint` - Sets CP data for a client at specified index. See cp_cache_t.
  * `Shavit_TeleportToCheckpoint` - Teleports client to the checkpoint at the given index.
  * `Shavit_ClearCheckpoints` - Clears all saved checkpoints for the specified client.
  * `Shavit_OpenCheckpointMenu` - Opens checkpoint menu for a client.
  * `Shavit_SetClientTimescale` - Sets the clients dynamic timescale. -1.0 to use the timescale of the client's style.
    * Note: Values above 1.0 won't scale into the replay bot.
  * `Shavit_GetClientTimescale` - Gets the clients dynamic timescale, or -1.0 if unset.
* New forward behavior:
  * `Shavit_OnTeleport` - now includes the checkpoint index that was teleported to.
  * `Shavit_OnSave` - now includes the index the checkpoint was saved to. As well as whether that checkpoint triggered an overflow and wiped a previous checkpoint.
  * `Shavit_OnEnterZone` - now passes the zone data for stage referencing.
  * `Shavit_OnLeaveZone` - now passes the zone data for stage referencing.
  *
* Added forwards:
  * `Shavit_OnTrackChanged` - Called when a player changes their bhop track.
  * `Shavit_OnReplaysLoaded` - Called when all replays files have been loaded.
  * `Shavit_OnTimescaleChanged` - Called when a clients dynamic timescale has been changed.



# v2.5.5a - asdf - 2019-08-08 - shavit
[`v2.5.5...v2.5.5a`](https://github.com/shavitush/bhoptimer/compare/v2.5.5...v2.5.5a)
https://github.com/shavitush/bhoptimer/releases/tag/v2.5.5a
https://github.com/shavitush/bhoptimer/commit/979c911a268f22bd94c930ed7f7722bd8426b326

## As usual, backup your database before ANY update in case something breaks.
## If you're suspicious of server's database being slower than it should be, after updating, follow this procedure:

Note that this only applies to installations where bhoptimer was first installed before the release of v2.5.5.

1. Run the following queries in your database:
```sql
# Note: if you use a table prefix, add it in front of the following keywords: playertimes, pt_auth, chat, ch_auth
ALTER TABLE `playertimes` DROP FOREIGN KEY `pt_auth`;
ALTER TABLE `chat` DROP FOREIGN KEY `ch_auth`;
```

2. Disable the `shavit-rankings` module if it's in use.
3. Start the server, lock it with a password so no one can enter it.
4. Run the command `sm_migration all` with root access.
5. Wait up to 1 minute.
6. Restart the server. If you desire to use the rankings module, enable it again.

Your database should be MUCH faster if it was misconfigured due to failed migrations.

---

* Improved measuring for perfect jumps (scroll styles).
* Added failsafe to prevent data loss when players finish maps when the database is locked.
* Fixed !end not working on maps with trigger zones.
* Fixed trigger zones not working if the running map is the first one since server start.
* Fixed replay plugin causing connect/disconnect messages to not show up.
* Added `sm_migration` command to re-apply database migrations if needed.
* Added logging when wiping player data.
* Added warning message when trying to wipe player data for invalid SteamIDs.
* Minor database optimizations.
* Fixed foreign keys not being removed/added properly for tables with prefixes, in database migrations.

## Console Variables

* `shavit_misc_wrmessages` - change this to set the amount of messages that show up when someone sets a WR. 0 to completely disable the message.

## API
* Added natives: (thanks @kidfearless!)
  * `Shavit_GetClientFrameCount`
  * `Shavit_GetReplayFrames`
* Added forwards:
  * `Shavit_OnFinishMessage` - allows you to modify the finish messages in chat.



# v2.5.5 - asdf - 2019-07-14 - shavit
[`v2.5.4...v2.5.5`](https://github.com/shavitush/bhoptimer/compare/v2.5.4...v2.5.5)
https://github.com/shavitush/bhoptimer/releases/tag/v2.5.5
https://github.com/shavitush/bhoptimer/commit/e4c8be08bc18884236b1b5842df58b83990f0f69

## This update features automatic database migrations. Backup your database and read [this gist](https://gist.github.com/shavitush/cfd329998c3d311ad5879f0052346bcc) before updating.

(gist enclosed in this spoiler text below:)
<details>
	31/05/2019
	if you are running v2.5.5 or above (from very_good_yes branch), there's some good news. unless you're on sqlite of course. if you're on sqlite, you might have to stick to the same version, or recreate your database
	i've added database migration and lots of optimizations, you don't need to do them on your end because the plugin will automatically do them for you!
	*however*, the first batch of database migrations contains 12 migrations, which is a lot. some of them take a while to execute, and some will be pretty much instant

	because of that, when you upgrade to from v2.5.4 or older, to v2.5.5 or newer i ask you to follow the following procedure:

	0. **DO A DATABASE BACKUP!! YOUR DATABASE MIGHT BREAK IF THE MIGRATION IS BEING INTERRUPTED AND YOU WILL LOSE DATA!!**
	1. if you have more than one server running the same database, take them all offline until this process is done
	2. close access to the game server that will perform the database migration. via password, server maintenance plugins, firewall, or whatever solution you can think  of
	3. update the game server to the latest version of bhoptimer, and start it. the server console will show "applying migration..." lines. let it run, it can take from 5 sec up to even 10 minutes, depending on the size of your database and your server's specs
	4. when the migration is done, you should see a `migrations` table in your database with entries from 0 all the way to 11 (as of v2.5.5. newer versions might have more). if you see this, it means that the migration is completed
	5. if the migration is completed, you can shut down the server, remove the password and put it back online :)

	frequent issues when migrating the database:
	```
	Timer (zone refresh) SQL query failed. Reason: Unknown column 'flags' in 'field list'
	```
	- this is fine. the error happens because the zones plugin has no way of knowing if the migration has happened already or not. it should go away right after finishing the migration

	```
	Timer (rankings, update all points) error! Reason: Incorrect integer value: '[U:1:steamid]' for column ..steamid at row X
	```
	- the database migration was interrupted or you haven't closed access to the server while migrating! run it again starting from step 1. i hope you have a backup, otherwise this will be a pain in the ass to fix and i will not manually fix your broken database, sorry.

	if you notice anything weird with the migration, let me know
</details>

Somewhat big update. I'm unmotivated recently so it'll probably be a while until next one.

* `prespeed` setting in style config now supports the value of 2. If it's set to 2, the value of `shavit_core_nozaxisspeed` will be respected by the style.
* Fixed an error that occurs when someone finishes a map without having any sound in the "noimprovement" section.
* Fixed record cache issues when maps have more than 1000 records combined between all styles/modes.
* After opening the KZ menu manually, it will be kept open unless interrupted by other menus.
* Fixed points recalculation for long map names.
* Fixed SQL query issues when using table prefix.
* Fixed foreign key constraints issues when running multiple bhoptimer servers on the same database.
* Added new CS:GO radio commands to the radio block list.
* Split replay loaders for the different kinds of replay formats. (technical change, helps me maintain the code)
* Fixed the very first frame of replays from version 1.4b and below not being played.
* Added `shavit_rankings_llrecalc` cvar, see the section below.
* Optimized chat plugin to not query the database for data saving unless it is needed.
* Added database migrations! Refer to [my gist](https://gist.github.com/shavitush/cfd329998c3d311ad5879f0052346bcc) about it.
* Optimized the database structure by A LOT. Wait a while (depends on how big your database is) after starting the server, after updating. You should wait at least 30 min for big databases before restarting the server.
* Added the ability to force invisible zones to be shown the players. The use case is making glitch zones visible to players while not doing it for all of them.
* Added custom sv_airaccelerate zones.
* Changed the behavior of No Speed Limit zones to Custom Speed Limit. All old zones are unlimited speed limit.
* Added GitHub Sponsors. Sponsoring itself is not usable right now because I'm not accepted yet though.
* Fixed "weapon <num> is not owned by client <num>" error.
* Added tracking for map completions. It is shown in the submenu of a record's details.
* Added "simplerladders", see cvar section.
* Optimized rankings plugin to not query the database for recalculations more times than needed.
* Split database handles per-plugin instead of using the same connection for all of them.
* Fixed sync for HSW. Thanks @Nairdaa!

## Console Variables

* `shavit_rankings_llrecalc` - Maximum amount of time (in minutes) since last login to recalculate points for a player. `sm_recalcall` does not respect this setting. 0 - disabled, don't filter anyone. This setting optimizes recalculation time by a lot.
* `shavit_core_simplerladders` - Allows using all keys on limited styles (such as sideways) after touching ladders. Touching the ground enables the restriction again.



# v2.5.4 - asdf - 2019-04-15 - shavit
[`v2.5.3...v2.5.4`](https://github.com/shavitush/bhoptimer/compare/v2.5.3...v2.5.4)
https://github.com/shavitush/bhoptimer/releases/tag/v2.5.4
https://github.com/shavitush/bhoptimer/commit/88b8b9a0799e95ac4680c20786d3b412f4a6d788

This is a hotfix update with some changes requested shortly after the v2.5.3 update.

* Added `force_groundkeys` style property. It forces the key blocking settings even when on ground. e.g. enabling this on W-Only will not allow prestrafing with the A/D keys.
* Fixed an issue that caused !r to not show up the menu that has "your timer will stop" warning.
* Slight reorganization the checkpoints menu. I moved the reset button one item below, and it now has a confirmation prompt when you try to reset your checkpoints.
* Fixed multiple issues with the KZ menu. Additionally, it will now not keep persisting when manually closed.
* Fixed an issue that caused autobhop WR submenus show the perfect jump %.
* Fixed a query error with the *!rr* command on servers running MySQL 5.7 and `ONLY_FULL_GROUP_BY`. Lower versions, and MariaDB servers are unaffected.



# v2.5.3 - asdf - 2019-04-14 - shavit
[`v2.5.2...v2.5.3`](https://github.com/shavitush/bhoptimer/compare/v2.5.2...v2.5.3)
https://github.com/shavitush/bhoptimer/releases/tag/v2.5.3
https://github.com/shavitush/bhoptimer/commit/2a1914010c943e8cfc4e3c5cfbcf9f22de2c052c

* Added pause button in KZ CP menu.
  * In addition, the KZ CP menu now persists and will re-open in case it disappears.
* Fixed error when a player uses !top before the rankings have been calculated.
* Removed the pointless round restarting logic in the Dynamic Timelimit module.
* Made the default method for zoning to be aiming.
* Added warning that shows up before using functionalities that can stop the timer when your time passes a defined number of seconds. See the new added console variable `shavit_misc_stoptimerwarning`. This is triggered on noclip/stop and style changing commands.
* Added `"noimprovement"` sound config file. The sound will play if you finish the map, but not beating your personal best.

## Console Variables

* `shavit_misc_stoptimerwarning` - the amount of seconds someone's timer needs to have to receive the "your timer will be stopped" warning upon using !stop, !nc or changing their style.

## API

* Added natives:
  * `Shavit_CanPause` - determines whether a player is able to pause or not. A value of 0 means that they can pause or resume their timer. Otherwise, this native retrieves flags: `CPR_ByConVar`, `CPR_NoTimer`, `CPR_InStartZone`, `CPR_NotOnGround`. Sample usage:

```sp
if((Shavit_CanPause(client) & CPR_ByConVar) > 0)
{
    // this code will be executed if the pause cvar is disabled
}
```

* New native behavior:
  * `Shavit_ResumeTimer` - now has a second parameter, `teleport`. True will teleport the player to the position they paused at.

* Added forwards:
  * `Shavit_OnTeleport` - called upon teleporting with a checkpoint
  * `Shavit_OnStopPre` - called when the timer is stopping. Ignored when `Shavit_StopTimer` is called with the `bypass` parameter set to true. Returning `false` here will prevent the timer from stopping.



# v2.5.2 - asdf - 2019-03-29 - shavit
[`v2.5.1...v2.5.2`](https://github.com/shavitush/bhoptimer/compare/v2.5.1...v2.5.2)
https://github.com/shavitush/bhoptimer/releases/tag/v2.5.2
https://github.com/shavitush/bhoptimer/commit/5fb84e6ace5fcd8e39a409550d167e7e1501dc60

* Fixed harmless error that occurs when a player is disconnecting before getting fully in-game.
* Fixed being able to break records by -0.000. Might or might not work. Probably does though.
* Added integrity checks to replay files.
* Fixed minor memory leak caused by loading corrupted replay files.



# v2.5.1 - asdf - 2019-03-29 - shavit
[`v2.5.0...v2.5.1`](https://github.com/shavitush/bhoptimer/compare/v2.5.0...v2.5.1)
https://github.com/shavitush/bhoptimer/releases/tag/v2.5.1
https://github.com/shavitush/bhoptimer/commit/c631f2f549beef5bc5ecad664236c51f03218d65

**Highly** recommended to update if you're on v2.5.0.

* Fixed a game breaking exploit related to persisted data.



# v2.5.0 - asdf - 2019-03-29 - shavit
[`v2.4.1...v2.5.0`](https://github.com/shavitush/bhoptimer/compare/v2.4.1...v2.5.0)
https://github.com/shavitush/bhoptimer/releases/tag/v2.5.0
https://github.com/shavitush/bhoptimer/commit/95d9cad3091003bb0da4c40c92522635604bb233

* **Added `enabled`, `inaccessible` and `kzcheckpoints` style modifiers.**
  * `enabled` - 0 to disable a style, -1 to disable it from being shown in all menus.
  * `inaccessible` - disables manual switching to the style. You may only switch to such a style using external modules (use case is TP mode for KZ).
  * `kzcheckpoints` - enables a new mode for checkpoints. They don't modify the timer, you don't keep your speed and they get reset as soon as you start a new run.
* **Added persisting for timer data (also known as "saveloc") on player disconnection.**
* Optimizations to database structure have been applied. If your initial installation was prior to this release, please follow the [database maintenance](https://github.com/shavitush/bhoptimer/wiki/4.3.-Extra:-Database-maintenance) wiki page's instructions.
* Optimizations to database queries have been applied as well.
* Improved cvar enforcing in replay plugin.
* Re-added the "No Speed Limit" text to CS:S HUD.
* Fixed foreign key error in chat module.
* Fixed errors in chat module when running SQLite.
* Changed default zone modifier setting to 16 units.
* !replay now opens the menu at the same page if playback fails.
* Fixed a bug that allowed teleporting to deleted checkpoints.
* Fixed a rare bug with replay playback.
* Fixed WR counter being inaccurate.
* Fixed compatibility with `ONLY_FULL_GROUP_BY` database servers.
* Removed very old table migration code due to it being slow.
* Now !style shows bonus rank 1 times if you're on bonus track.
* Added a decrease button for grid snap during zone setup.
* Added !mapsdone and !mapsleft commands.
* Maps left menu now shows map tier.
* Removed old delete function from admin menu.
* Fixed `mp_humanteam` setting being ignored.
* Changed zone setup to be easier for bonus zones.
* Transition to last frame of the replay will be smoother now.
* Fixed replay HUD bug for styles with speed multipliers.
* Fixed issues with the replay counter for HSW.
* Revamped spawn point addition. It also supports bonus track now.
* Fixed rare bug caused by slow databases.

# Console Variables

* `shavit_misc_hidechatcmds` - hides all commands in chat.
* `shavit_misc_persistdata` - controls minimum time (in seconds) to persist timer data for a player that disconnects.

# API

* Added forwards:
  * `Shavit_OnTeleport` - called upon teleporting with a checkpoint
  * `Shavit_OnSave` - called upon saving a checkpoint



# v2.4.1 - asdf - 2019-03-08 - shavit
[`v2.4.0...v2.4.1`](https://github.com/shavitush/bhoptimer/compare/v2.4.0...v2.4.1)
https://github.com/shavitush/bhoptimer/releases/tag/v2.4.1
https://github.com/shavitush/bhoptimer/commit/a0d205247a5bde6ea7edaf749af4dcad7b21c017

* **Fixed exploit related to checkpoints.**
* **Added `sm_wipeplayer` command.**
* **Added style ordering to menus.** Use `ordering` style config to order styles without changing their IDs.
* **Added the ability to stop replay playback as the requester.**
* **Improved logging of single-record deletion.*
* `!replay` command moves you to spectator, and refers you to the replay bot upon use now.
* Added PB split to HUD. The top-left HUD will split to two sections; "best" and "PB".
* Added map tier to start zone HUD.
* Fixed unintended behavior with checkpoints menu.
* Added the `{rank}` format specifier to custom clan tag console variable.
* `!r` shows the track in the message if start zone doesn't exist.
* Fixed HUD showing wrong time when playing with timescale.
* Fixed checkpoints not properly setting `targetname` and `classname`.
* Fixed error when certain commands are used from the server's console. This fix allows them to work now.
* Changed `!deleteall` so you can delete all records per-style rather than just per-track.
* Fixed an issue where *deleted* replays would not be overwritten.
* Added cooldown for replay playback/stop for non-admin users.
* Fixed replay bots breaking at certain interactions; such as stopping playback between the replay's end and its nullification and then requesting new playback.
* Improved smoothness of all replay playback.
* Fixed a bug that caused the last frame of replays seem out-of-place.

# API

* Added natives:
  * `Shavit_ChangeClientStyle`
  * `Shavit_ReloadLeaderboards`
  * `Shavit_DeleteReplay`
  * `Shavit_GetOrderedStyles`
  * `Shavit_IsPaused`

* Added forwards:
  * `Shavit_OnRankAssigned`

A relatively big update considering it's a minor version, have fun!



# v2.4.0 - asdf - 2019-02-02 - shavit
[`v2.3.6...v2.4.0`](https://github.com/shavitush/bhoptimer/compare/v2.3.6...v2.4.0)
https://github.com/shavitush/bhoptimer/releases/tag/v2.4.0
https://github.com/shavitush/bhoptimer/commit/1cd4b4c9c364cdade32456e7caa65ebc07528bd9

## Note: bhoptimer now requires SourceMod 1.10 or above.

* Revamped HUD for CS:GO. CS:GO HUD has been technically modified so it is easier to manipulate for developers.
* Restructured the whole plugin to use `enum struct`. Code should be easier to understand. As far as I'm aware other modules should not break. However, they will need to be modified if a recompilation is desired.
* Fixed chat colors in CS:GO.
* Deprecated `Shavit_GetPlayerPB` and `Shavit_GetWRTime`. Use `Shavit_GetClientPB` and `Shavit_GetWorldRecord` respectively.
* Added `shavit_rankings_weighting` cvar. This allows you to control the weighting in rankings. Set this to `1.0` to disable weighting and instead give users the exact amount of points shown in record submenus.
* Changed `users.name` collation to `utf8mb4_general_ci`. This is not an automatic migration and will require manual action for existing installations.
* Added `shavit_core_nochatsound` to get rid of the chat ticking sound from timer messages.
* Fixed exploit in chat plugin that allowed breakage of the chat in CS:S.
* Fixed RTLer not working in chat plugin.
* Fixed attempts to teleport a kicked/non spawning central bot resulting in logged errors and paused script execution.
* Changed !hud so it is easier to understand for the end-user. The menu now also has new settings that allow you to disable the main HUD's components individually.
* Added commands to toggle frequently changed HUD components. *!keys, !master, !center, !zonehud, !hideweapon, !truevel*
* Fixed exploit allowing users to submit segmented runs as if they were done in realtime.
* Fixed server crash exploit with checkpoints.



# v2.3.6 - asdf - 2018-12-23 - shavit
[`v2.3.5...v2.3.6`](https://github.com/shavitush/bhoptimer/compare/v2.3.5...v2.3.6)
https://github.com/shavitush/bhoptimer/releases/tag/v2.3.6
https://github.com/shavitush/bhoptimer/commit/98d9b29c1da86bf22df5586428cc5c006c0403c1

## bhoptimer v2.4.x and above will require SourceMod 1.10 (6371 or newer)

* Fixed out of bounds error in Shotgun Shot sound hook
* Prioritized custom spawns > server zones > prebuilt zones



# v2.3.5 - asdf - 2018-12-07 - shavit
[`v2.3.4...v2.3.5`](https://github.com/shavitush/bhoptimer/compare/v2.3.4...v2.3.5)
https://github.com/shavitush/bhoptimer/releases/tag/v2.3.5
https://github.com/shavitush/bhoptimer/commit/f527455a2d66f5ec278a3148bb9bda0be3726ecd

* Fixed some stats being off (map completion, ranks etc)
* Fixed targetnames and classnames not saving properly in checkpoints
* Updated run speed offset for CS:GO
* Made color formatting in `shavit-chatsettings.cfg` possible



# v2.3.4 - Pausing development for a while - 2018-11-03 - shavit
[`v2.3.3...v2.3.4`](https://github.com/shavitush/bhoptimer/compare/v2.3.3...v2.3.4)
https://github.com/shavitush/bhoptimer/releases/tag/v2.3.4
https://github.com/shavitush/bhoptimer/commit/398c9ee84e0c481e29ec1cfd3e2cf55ec7fca36e

* Added practice mode alert toggle to !hud.
* Fixed several issues with CP menu prev/next buttons.
* Replaced `halftime` style setting with `timescale`. I added backwards compatibility. See style config for usage example.
* Fixed replay unsyncing for a short time when hitting thin teleports while crouching.
* Optimized replay file writing to be much faster.
* Fixed issues with unicode inputs for username/chat settings. Might need to manually change the column collation to `utf8mb4_unicode_ci`.



# v2.3.3 - asdf - 2018-10-10 - shavit
[`v2.3.2...v2.3.3`](https://github.com/shavitush/bhoptimer/compare/v2.3.2...v2.3.3)
https://github.com/shavitush/bhoptimer/releases/tag/v2.3.3
https://github.com/shavitush/bhoptimer/commit/b8d0522e96e8867402915d5aa55e9f5fbf0b7ea5

* Fixed rankings SQL issues with optimized MySQL/MariaDB configs.
* Fixed PB in HUD showing rank 0 when it's rank 1.
* Removed code that is now unnecessary from shavit-sounds.
* Added `Shavit_OnReplayStart` and `Shavit_OnReplayEnd` forwards.



# v2.3.2 - asdf - 2018-10-03 - shavit
[`v2.3.1...v2.3.2`](https://github.com/shavitush/bhoptimer/compare/v2.3.1...v2.3.2)
https://github.com/shavitush/bhoptimer/releases/tag/v2.3.2
https://github.com/shavitush/bhoptimer/commit/73fdf77d36d1fd60fc2b3417c19454cabc349e50

* Fixed !ranks being broken for some setups.
* Fixed core loading when rankings is unloaded.



# v2.3.1 - asdf - 2018-09-22 - shavit
[`v2.3.0...v2.3.1`](https://github.com/shavitush/bhoptimer/compare/v2.3.0...v2.3.1)
https://github.com/shavitush/bhoptimer/releases/tag/v2.3.1
https://github.com/shavitush/bhoptimer/commit/e9a203ba946c58617e77619c45ff292ef1b7cf98

* Added !deletemap.
* FIxed !ranks showing titles as unranked even though they're not.
* Fixed memory leak in shavit-replay.
* Increased shavit_replay_timelimit's default to 2 hours
* Made replay plugin not record more frames after going past time limit.



# v2.3.0 - asdf - 2018-09-14 - shavit
[`v2.2.0...v2.3.0`](https://github.com/shavitush/bhoptimer/compare/v2.2.0...v2.3.0)
https://github.com/shavitush/bhoptimer/releases/tag/v2.3.0
https://github.com/shavitush/bhoptimer/commit/c774f41ac80ca2b77a210a6fe7d7cd8c58f7b37b

* Fixed errors.
* Reworked checkpoints to not be so poopoo.
* Fixed memory leak with checkpoints.
* Fixed low gravity styles being trash with boosters.
* Fixed HUD showing wrong speeds for slower/faster styles.
* Fixed shavit_misc_prespeed 4. Set to 4 and combine with shavit_core_nozaxisspeed 1 to get the same behavior that SourceCode timer has.
* Added shavit_replay_botweapon. Choose whatever weapon you want the bots to have.
* Added shavit_replay_botplususe. You can disable bots from using +use.
* Added !ranks command in chat module. This shows a list with all* the visible chat titles. Select an entry in the menu to preview the chat rank!
  * Easter eggs and privileged titles are excluded from this menu.
* Added `"easteregg"` and `"flag"` settings to chat titles. The former decides on if it shows up in the !ranks menu. The latter limits this title to the flag/override you choose.



# v2.2.0 - new chat processor - 2018-06-23 - shavit
[`v2.1.2...v2.2.0`](https://github.com/shavitush/bhoptimer/compare/v2.1.2...v2.2.0)
https://github.com/shavitush/bhoptimer/releases/tag/v2.2.0
https://github.com/shavitush/bhoptimer/commit/945b1c85d00216dfb469b41d0e6ea48e77f852a1

* Wrote a new chat processor for bhoptimer.
    * Uninstall any other chat processor you have installed.
* Changed clan tag `{time}` to display only at 1 second or above.
* Ensured segmented replays with deleted replay data are gone.
* Added `shavit_misc_speclist` for misc's !speclist.
* Added `shavit_hud_speclist` for HUD's spectator list.
* Fixed chat color injections.
* Fixed percentile ranking titles being broken.
* Fixed SQL error on new setups.
* Removed flat zone cvar, added shavit-zones config instead.
    * Removed custom spawn from cfg to prevent confusions.
* Made viewangle recording use verified angles instead. This makes replays smoother, and removes *most* (not all) of the flickering from segmented replays.
* Made CP save targetname/classname, both are very efficient now! Closer to real save states.
* Added shavit_misc_maxcp and shavit_misc_maxcp_seg.
* Fixed invalid client error on CP saving.
* Fixed top-left HUD not showing correct style/track data.
* Removed unused 'spawn point' zone setting.
* Minor optimizations all around the codebase.
* Fixed !save behaving differently from the !cp menu option.



# v2.1.2 - bug fixes and polishing - 2018-05-07 - shavit
[`v2.1.1...v2.1.2`](https://github.com/shavitush/bhoptimer/compare/v2.1.1...v2.1.2)
https://github.com/shavitush/bhoptimer/releases/tag/v2.1.2
https://github.com/shavitush/bhoptimer/commit/a5c68940c60740d53169da0be847a18c13eb5629

* Changed default +left/right block behavior.
   * 1 now blocks movement, 2 also stops timer.
* Segmented CP menu now pops up when changing between two segmented styles.
* Changed bot flag behavior to ensure bots properly get their entity flags applied.
* Fixed possible memory leak.
* Fixed chat/style setting errors on player connections.



# v2.1.1 - exploit fix - 2018-05-03 - shavit
[`v2.1.0...v2.1.1`](https://github.com/shavitush/bhoptimer/compare/v2.1.0...v2.1.1)
https://github.com/shavitush/bhoptimer/releases/tag/v2.1.1
https://github.com/shavitush/bhoptimer/commit/fda9d81bc7ca1bfb32bf8751f6aa24da962dc166

* **Fixed serious exploit to do with checkpoints. Update ASAP!**
* Reduced database load on server start.
* Removed perfect jump% from !wr on old, unmeasured records.



# v2.1.0 - segmented runs! - 2018-05-02 - shavit
[`v2.0.3...v2.1.0`](https://github.com/shavitush/bhoptimer/compare/v2.0.3...v2.1.0)
https://github.com/shavitush/bhoptimer/releases/tag/v2.1.0
https://github.com/shavitush/bhoptimer/commit/3e558558b003bd7e504fdc0ce9528ce0cbe383d3

* **Added support for segmented runs.** Use `"specialstring" "segments"` to allow a style to use segmented checkpoints. Use the !cp menu on supported styles! Segmented styles also work with replays.
* **Fixed multiple memory leaks.**
* Added Segmented (normal) as a style to the default setup.
* Added `shavit_replay_botshooting`. This cvar can allow you to disable attacking buttons for bots. 0 will make the bots not press mouse1/mouse2 at all. 1 will only allow shooting, 2 will only allow right clicking and 3 will allow everything.
* Added two natives: `Shavit_HijackAngles`, `Shavit_GetPerfectJumps`.
* Fixed a bug with replay data when loading a state after finishing the map.
* Now `mp_humanteam` is respected by shavit-misc. The TF2 equivalent also is.
* Now `shavit_replay_defaultteam` is always respected, regardless of if the map has a spawn point for the team.
* Rewrote admin menu integration. Use the `shavit_admin` override to grant access. The *Timer Commands* category now has replay removal too.
* Now weapons dropped by disconnected players will automatically clean up.
* Added record count in !delete menu, disabled buttons when unnecessary.
* Added perfect jump% measuring for scroll styles.



# v2.0.3 - small updates - 2018-04-29 - shavit
[`v2.0.2...v2.0.3`](https://github.com/shavitush/bhoptimer/compare/v2.0.2...v2.0.3)
https://github.com/shavitush/bhoptimer/releases/tag/v2.0.3
https://github.com/shavitush/bhoptimer/commit/c294408c431f315730e0bc71248009d74c1ddc73

* Added style permissions:
   - Added `Shavit_HasStyleAccess` native.
   - Added `permissions` setting to styles. Use like "p;style_tas" for example. First section is the flag needed, and the second section is the override for it.
* Micro optimization in spawn point generation.
* Scaled slide zones with speed/gravity.
* Reworked sounds to emit properly in CS:GO.
* Fixed typos in the code, and translations. Thanks @strafe!
* Fixed an issue where players get a wrong rank when actually unranked. Thanks Nairda for finding this!



# v2.0.2 - begone, bugs! - 2018-04-19 - shavit
[`v2.0.1...v2.0.2`](https://github.com/shavitush/bhoptimer/compare/v2.0.1...v2.0.2)
https://github.com/shavitush/bhoptimer/releases/tag/v2.0.2
https://github.com/shavitush/bhoptimer/commit/a0665072139c16aaac355953404982709f9ba816

* Addressed CP menu bugs.
* Addressed an issue where donor plugins not always allowing players to use custom titles.
* Addressed an issue that caused chat titles to not always show.
* Fixed CS:S HUD not showing track properly.
* Fixed pre-zoned maps not saving spawn points if you just started the server.
* Removed duck/unduck requirement for checkpoints. Upon teleporting, the plugin will automatically adjust you to the state of the checkpoint.
* Fixed the 'to X rank' parameter when using percentile ranking in titles.
* Reworked gun shot muting. Now it supports TF2, and I've fixed the issue that caused others' gun shots to not play at all in CS:GO.
* Added `shavit_core_defaultstyle`. Usage: style ID. Add an exclamation mark as the prefix to ignore style cookies (i.e. "!3" to force everyone to play scroll when they join).



# v2.0.1 - bug fixes - 2018-03-23 - shavit
[`v2.0.0...v2.0.1`](https://github.com/shavitush/bhoptimer/compare/v2.0.0...v2.0.1)
https://github.com/shavitush/bhoptimer/releases/tag/v2.0.1
https://github.com/shavitush/bhoptimer/commit/c28de91fd4a1a153099c7adc1b95d4be0453ce00

* **Fixed serious exploits that had to do with checkpoints.**
* Fixed not being able to change the teleport zones' track on creation.
* Fixed CS:S HUD not showing irregular tracks.
* Fixed HUD breaking apart after adding styles without server restarts.
* Removed minimum for `shavit_timelimit_default`.



# v2.0.0 - official release! - 2018-03-18 - shavit
[`1.4b-hotfix...v2.0.0`](https://github.com/shavitush/bhoptimer/compare/1.4b-hotfix...v2.0.0)
https://github.com/shavitush/bhoptimer/releases/tag/v2.0.0
https://github.com/shavitush/bhoptimer/commit/f9b67450db01c1954d28dd36fe2e9ab96c45c11c

We're out of beta now!
The last release was in September 21, 2015. There have been **too many** changes, but I'll try to mention the important ones.

* Added configuration files.
* There are multiple styles now. They're defined in `addons/sourcemod/configs/shavit-styles.cfg`.
* The database structure has been revamped. Visit [the wiki page](https://github.com/shavitush/bhoptimer/wiki/4.2.-Extra:-Updating-(Database)) for information.
* Added cvars for most features.
* Created a website for bhoptimer. See https://bhop.online/
* Revamped the whole zones plugin. You can setup aesthetic looking zones thanks to grid snapping, wall snapping and cursor zoning.
* Added many zone types: No speed limit, teleport zone, easybhop zone, slide zone.
* You can now choose the zone sprite.
* You can now edit zones after creating them. This includes manual editing of coordinations.
* The plugin has received massive optimizations. It's very lightweight now.
* Added a stats module. The main command is !stats (or !profile), it shows lots of useful information.
* Added a dynamic timelimits module. It sets the timelimit for the map relatively to the average completion time.
* Added replay bots. By default, there's a single bot that players can choose to playback with, the command is !replay. The recorded data is saved in an efficient structure (binary, rather than UTF) to make sure the server doesn't hiccup when data is saved.
* Added a rankings module. The design idea is simple: points given per record are relative to the map's length, tier and how good the record is compared to the rank 1 record. The style played also affects the amount of points given.
* Added bonus track.
* Added logging for admin actions.
* Added chat module. It integrates with rankings and allows players to use custom titles if they have access. See !chatranks and !cchelp.
* The target version is now SourceMod 1.9 as it offers functionality needed for accurate timing.
* Added checkpoints. You can save while spectating players or bots too. Teleporting will make sure you're at the exact same state you were in while saving (including timer data), so that you can't segment an impossible to achieve record.
* Added automatic integration with KZ maps with buttons, and the [Fly zoning standard](https://github.com/3331/fly).
* Added `+strafe` detection.
* Added strafe/sync counters.
* Added custom `sv_airaccelerate` values for styles.
* Added the ability to have custom physics for styles (i.e. HSW, SHSW, W-only etc).
* Made prespeed/prejump limitations more user-friendly.
* Added CS:S support.
* Added TF2 support.
* Fixed zones not rendering after a certain number.
* Added the !hud command, it allows players to make their HUD contain the information they want to see.
* Added commands to teleport to the end zones (!end, !bend).
* Added team join hooks for comfortable spawning.
* Added spectator lists.
* Redone player hiding.
* Added player teleportation.
* Added weapon commands (!usp, !glock, !knife) and ammo management.
* Added noclip commands (!p, !nc, +noclip etc).
* Allowed dropping all weapons.
* Added godmode.
* Added custom prespeed limitations.
* Removed clutter (like team changes) from chat.
* Hid radar.
* Changed weapons to disappear when dropped.
* Added auto-respawn.
* Added radio commands blocking.
* Added scoreboard manipulation (clan tags, score/deaths etc).
* Added configurable chat advertisements.
* Added player ragdoll removal.
* Added fuzzy search in !wr (so you can write `!wr arcane` rather than `!wr bhop_arcane_v1` for example).
* Added !rr command to see the recent world records.
* Fixed all reported bugs.



# v1.4b - hotfix - 2015-09-21 - shavit
[`1.4b...1.4b-hotfix`](https://github.com/shavitush/bhoptimer/compare/1.4b...1.4b-hotfix)
https://github.com/shavitush/bhoptimer/releases/tag/1.4b-hotfix
https://github.com/shavitush/bhoptimer/commit/489a6826d74a84ae8e65f9b92d17b3f4aba1f984

Fixed compilation for the SM 1.7.3 compiler.



# v1.4b - more plugins - 2015-09-20 - shavit
[`1.3b...1.4b`](https://github.com/shavitush/bhoptimer/compare/1.3b...1.4b)
https://github.com/shavitush/bhoptimer/releases/tag/1.4b
https://github.com/shavitush/bhoptimer/commit/519a647a53b79eb46fa3323ca44a1681ccda1f2a

### shavit-core:
- [x] + Add a cvar for autobhop.
- [x] + Add a cvar for +left/right blocks.
- [x] + Add cvars that prevent pausing/restarting.

### shavit-zones:
- [x] + Add a submenu that can adjust the zone's X/Y/Z axis before it's being confirmed.

### [NEW PLUGIN] shavit-stats:
- [x] + Show maps done (/SW)
- [x] + Show maps left (/SW)
- [x] + Show SteamID3
- [x] \* Make it actually work

### [NEW PLUGIN] shavit-timelimit:
- [x] + Take an average of X (default: 100) times on a map and use it to decide the timelimit/roundtime for the map.

### [NEW PLUGIN] shavit-replay:
- [x] + Properly working replay bot for forwards
- [x] + ^ same but also for sideways



# v1.3b - Freestyle zones update! - 2015-07-27 - shavit
[`1.1b...1.3b`](https://github.com/shavitush/bhoptimer/compare/1.1b...1.3b)
https://github.com/shavitush/bhoptimer/releases/tag/1.3b
https://github.com/shavitush/bhoptimer/commit/fd4bb2c67201ce30703a66a372a7d6d749db8171

### shavit-core:
- Handle freestyle zones

### shavit-zones:
- Allow creation of freestyle zones
- Make multiple freestyle zones possible (damn you Aoki and badges for making stuff difficult!)
- Handle deletion of multiple freestyle zones
- Handle drawing of end/freestyle zones properly

The update should (SHOULD, not promising anything!) also make remote MySQL databases work, even though I'm really against them and they could make the server lag hard.
And it also fixes many of the SQL issues that some server owners had.



# v1.1b - created github repo - 2015-07-09 - shavit
https://github.com/shavitush/bhoptimer/releases/tag/1.1b
https://github.com/shavitush/bhoptimer/commit/116cbab219b05ab033100e2ea2cbd1e52d0a1b92
