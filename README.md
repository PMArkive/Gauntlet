# Gauntlet

## Setup

- Install [LiveSplit](https://livesplit.org/downloads/).
- Extract LiveSplit.Server.dll to your LiveSplit\Components folder.
- Extract gauntlet.smx to your cstrike\addons\sourcemod\plugins folder.
- Start your LiveSplit file ( BHOP_GAUNTLET.lsl in our case).
- Right click on LiveSplit -> Open Splits -> From URL... -> it would be https://raw.githubusercontent.com/xRz0/SplitTimes/main/Times.xml in our case
- Right click on Livesplit -> Control -> Start Server.
- Start CS and go to the first map from the gauntlet.


## CVARS and Commands

> CVARS 
- gauntlet_mapurl = Sets the url for the gauntlet mapzones. string
- gauntlet_custom = Use different types of maps (mixed map prefixes has to be set in LiveSplit). bool
- gauntlet_prefix = Sets the prefix for the maps (bhop in our case). string
- gauntlet_zones = Enable the plugin to save zones you create into a txt (for easier upload if you wanna share). bool

If you want to use mixed prefixes ( for example surf and bhop ) set gauntlet_custom to 1, gauntlet prefix to "" and write the prefixes into the LiveSplit splits monster_jam -> bhop_monster_jam.

> Commands
- sm_maps = Show the gauntlet maplist.
- sm_stuck = Unstuck?
- sm_split = Manual time split
- sm_savezones = "Save the zones for your gauntlet ( Helpful if you make a new gauntlet and want to share the zones for the maps ).

I would recommend to use the [css meme lan server](https://github.com/xRz0/css-LAN) for this!