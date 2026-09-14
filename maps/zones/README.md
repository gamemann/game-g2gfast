# What a map does not say about itself

One file per map, named for its id, merged into the manifest by `tools/bsp_import.py`.

**Coordinates in here are Hammer's**, the ones the tools in `tools/` print — the axis swap and the yaw conversion happen once, in the importer, where every other coordinate's does. A file that mixed the two would be a file nobody can check against the map it describes.

Six of the eighteen maps beside this directory label their own zones on the trigger volumes: `zone_start`, `map_end_zone`, `startzone_s4`, `tm_bonus2_endzone`, `start_trigger`, `end_trigger`. Those are read straight out of the entity lump by `zone_role()` and need nothing here. This directory is for the rest, and for the halves the labelled ones are missing — and every entry says **why**, because a finish line is a judgement about a map somebody played, and the next person to look at it deserves the evidence rather than a number.

**The commonest thing a bhop map labels is a destination, not a volume.** Seven of the ten imported in the second pass name their start or their finish on an `info_teleport_destination` — `finish`, `end`, `START`, `Stage1` — which is a point rather than a volume and so is invisible to `zone_role()`, which reads targetnames off `trigger_multiple` and `trigger_once`. `"teleport_to"` is the rule that turns one back into a volume: the trigger aimed at the destination is the line, and `"max_horizontal"` separates the door-sized one from the room-sized pit that is usually aimed at the same place. That is how `bhop_mario_fxd`, `bhop_badges`, `bhop_monster_jam`, `bhop_arcane_v2`, `bhop_fur` and `bhop_aztec` are timed here.

**Three of the eighteen still have no finish, and none of them is a mistake.** `buses_from_hell_fixed` is not a course at all — no teleports, no destinations, eight `func_rotating` and a `game_ui`, which is a vehicle map. `bhop_eazy` and `bhop_lego2` are section-chain maps (`t11`..`t2727`, `s_1`..`s_30`) whose sections are all labelled and whose end is not: nothing in either file distinguishes the last gate from the twenty-six before it. Both load, draw and collide; a run on them wants zones drawn in-game, which is what the console is for. Guessing here would produce a board that looks right and measures a route the map does not have.

## What a zone may say

A volume, exactly one of:

| | |
| --- | --- |
| `"box": [[x,y,z],[x,y,z]]` | two corners, Hammer coordinates |
| `"named": "targetname"` | the brush volume of the entity(ies) with that name |
| `"teleport_to": "dest"` | the `trigger_teleport` aimed at that destination (`"all": true` to union them) |
| `"around": {"point": …, "extents": [x,y,z]}` | a box grown around a destination name, a list of them, or a literal point |
| `"near": {"class": "trigger_multiple", "point": [x,y,z], "within": 512}` | the nearest brush entity of that class |

Plus `"kind"`, `"track"`, `"number"` (a stage), `"destination"` (a name or a point), `"destination_yaw"`, and `"note"`.

`"doorways": {"max_horizontal": 512}` opts a map into the rule that a teleport volume narrower than that is a **door the player walks through** rather than the pit — `TELEPORT`, which keeps the run, rather than `RESPAWN`, which ends it. It is not on by default because it is only true of a map whose sections are joined by doors.

Anything a rule cannot resolve is an error and stops the import. That is deliberate: a finish line that silently resolved to nothing is a map that cannot be finished, and nothing about playing it would say so.
