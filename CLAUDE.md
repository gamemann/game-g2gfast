# game-g2gfast

A bunny-hop and surf timer game in the competitive-shooter shape: the genre's
movement, its units, its cvars, a timer with zones an admin draws from the console, first and
third person, and every player drawn as an avatar.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first, and
each addon's own `CLAUDE.md` before working in it. This file is only about what this
game decides.

## What this game is, versus game-playground

game-playground is a sandbox that happens to have a surf ramp. This is the *timer
server*: the thing one of those communities would actually migrate to. Everything it
adds over the addons is one of four decisions, and the decisions are the file.


## An admin's help can never make a time

dot-moderation's live tools are here (`G2GModTools`, built in `G2GServices`, commands on the module), and on a timer server the first rule about them is the product's: **no admin tool can help a run.** Noclip abandons the run it interrupts; `G2GPlayer._on_simulated` taints any run while a noclip, a speed step or a gravity step is on the player — every tick, because a noclipped player can fly into a start zone and out again and begin a new run; an admin's teleport ends the run like every teleport here. Taint is dot-timer's own "assisted" mark, so the run still finishes and shows and `can_record` refuses to file it. Freeze is deliberately not a taint: it can only cost a runner time.

Health, weapons and god mode exist only while `sv_deathmatch` is on, so god, buddha, hp, slay, give and strip answer "not running its deathmatch" rather than being absent — whether they mean anything is a cvar, not a build. `dedicated`'s live-tools section asserts the timer half: abandoned, tainted, refused a record, clean once it is off, and tainted by a speed step too.

**Blind and beacon were refused as "no client overlay" until 2026-09-24, and are two flags now**, on game-arena's pattern (0e818b3). `G2GPlayer.blinded` and `G2GPlayer.beacon` are set by the handlers and replicated in `G2GPlayerNet` after the movement specs — `net_blind` **owner-only**, because nobody else's screen changes and an opponent on the deathmatch layer who could read it would know when to go and find somebody; `net_beacon` to everybody. State rather than an event, so a joiner, a lost snapshot and a map change are corrected by the next snapshot. `G2GHud.blind_overlay` fades a near-black rect in over a quarter of a second, **under** the clock and the keys and sized to the viewport rather than to the HUD; `G2GBeacon` is a ring and a once-a-second ripple at the drawn position, sized to this game's 32-unit hull rather than the arena's, and a column through walls that the beaconed player's own camera does not draw; each ripple is `beacon_pulsed`, which `G2GClient` plays as `G2GPresentation.BEACON_SOUND` — the BLIP an octave under `timer_start`, positional, on SFX, and below the landing and the jump in priority so a ping can never take a voice from the rhythm. Three things differ from the arena on purpose:

- **Neither taints a run.** A blind can only cost a runner time, like a freeze, and a beacon changes nothing the movement can feel. `dedicated` asserts a run made blind is not marked assisted.
- **Nothing re-applies them on a respawn, because nothing has to.** A respawn here is `G2GGame.spawn_player`, a teleport of the same node, so both flags simply stay — and this game never calls `DotModTools.respawned`, so adding them to `persist_on_respawn` would be a setting nothing reads.
- **A beacon changes no relevance.** Every player entity here is `always_relevant` already (`G2GNetBridge._build_entity`); copying the arena's `always_relevant = beacon` would CUT every runner the moment their beacon went off. `dedicated` and `headless_net` both assert it stays on, and both fired when the arena's line was put in (`headless_net` lost the ghost's replication with it).

`headless_net`'s **who is told** adds a second player owned by another peer, blinds and beacons both over one-in-five loss, and asserts this client is told its own blind and not the other's, and both beacons; armed by dropping `to_owner_only()`, two fired. `headless_presentation` asserts the overlay is the HUD's first child, fades, covers the viewport (armed by removing the sizing), and that a beacon pings once a second rather than once a frame. `tools/screenshot_hud.sh` renders `hud_beacon` and `hud_blind`.

## Layout

```
game/
  g2g_units.gd      genre units → metres. The ONLY place the ratio lives
  g2g_config.gd     every cvar, in genre units, layered like every DotConfig
  g2g_movement.gd   G2GConfig → DotFpsTunables. The only place units cross
  g2g_game.gd       the simulation: maps, timers, boards, players. Headless
  g2g_player.gd     controller + rig + camera + timer, joined
  g2g_rig.gd        the visible character: attachment nodes for the avatar slots
  g2g_avatars.gd    the stock schema, stock parts, and a player's own avatar
  g2g_camera.gd     first and third person, with the genre's field of view
  g2g_hud.gd        clock, keys, speed in u/s, PRACTICE, and an admin's blind
  g2g_beacon.gd     an admin's beacon: ring, ripple, a column through walls
  g2g_replays.gd    the best replay per map, track and style. What the ghost plays
  g2g_query.gd      what a server browser is told: map, tick rate, styles, the WR
  g2g_client.gd     one local player. Never loaded by a server
  g2g_module.gd     the DotServer bridge: sv_autobunnyhopping and friends, and
                    the netcode's owner on a dedicated server
  net/
    g2g_net_bridge.gd  joins a G2GGame to a DotNetManager. The ordering is the file
    g2g_player_net.gd  one player as a replicated entity; DotFpsNetSync's specs
    g2g_net_command.gd a DotFpsCommand as a DotNetInput
    g2g_net_link.gd    the @rpc surface, identical on both ends. Never edit one end
    g2g_events.gd      every event and request body, and the movement config's wire
    g2g_event.gd, g2g_request.gd  the two DotNetMessages: a kind and a body
  g2g_geometry.gd   boxes and ramps, in units
  g2g_map.gd        base for the built-in maps; a map declares its jumps here
  g2g_reach.gd      what a jump reaches, from the tunables; every declared jump, measured
  g2g_bsp_map.gd    base for an IMPORTED map: mesh, materials and zones from a
                    manifest. See Decision 11
  g2g_bsp_lightmapped.gdshader  albedo x the lighting the map's own compiler baked
  g2g_bsp_translucent.gdshader  the same, plus the ALPHA write. 20 surfaces of 420
  g2g_lighting.gd   which DotLightProfile this machine gets. The rest is dot-lighting
  g2g_map_catalogue.gd  finds every map by looking. There is no list of maps
  g2g_stats.gd      every per-player number, declared once. See Decision 12
  g2g_awards.gd     achievements as rules over those ids
  g2g_progress.gd   dot-stats and dot-achievements, joined to the runs
  g2g_arsenal.gd    the deathmatch half's weapons, items and match rules
  g2g_combat.gd     dot-combat + dot-loadout + dot-match, as a layer over the timer
  g2g_hunters.gd    dot-npc + dot-npc-ai + dot-npc-ai-director, along the course
  g2g_props.gd      practice blocks, frozen, and what they cost a record
  g2g_vote.gd       dot-vote over the map catalogue. Replaces the rtv that was not one
  g2g_services.gd   dot-chat + dot-voice + dot-moderation, on a dedicated server
  g2g_identity.gd   dot-cloud + dot-auth + dot-user + dot-platform
  g2g_client_extras.gd  the client halves of chat and voice
  g2g_browser.gd    dot-browser's client half: !servers, and what a row says
npcs/               two hunters and the body they share
props/              three practice blocks, in the genre's 32/64/128 sizes
maps/               bhop_g2g_intro, bhop_g2g_stages, surf_g2g_intro, and their .zones.json
  imported_map.tscn THE scene every imported map uses. In the build; the maps are not
  imported/<id>/    what tools/bsp_import.py wrote: <id>.bin, <id>.json, the lightmap
                    atlas and the textures. Data only -- no scene, no script.
                    Derived; gitignored; never hand-edited
  zones/<id>.json   what a .bsp does NOT say about itself: which volume is the finish,
                    and why. Hand-written, checked in, merged at import. See
                    Decision 11 and maps/zones/README.md
avatars/            six stock parts and the tint shader
textures/prototype/ the installed prototype set: one PNG per G2GTextures.Role, CC0,
                    and what the IMPORTED maps draw in. See its README
scenes/
  g2g_server.tscn   what a dot-server loads. A G2GGame under a plain Node
examples/           headless_run (170), headless_net (113), dedicated (174),
                    headless_imported (29 per map, plus one per track and stage),
                    headless_maps (27), jitter_probe (4 configurations)
tools/              export_zones.gd — run after changing a map
                    route_preview.gd/.tscn/.sh — render ONE TRACK of a hand-written
                    map from its own spawn, looking down it. bsp_preview orbits a
                    whole map, which on a map whose four routes span 5,800 units of
                    X makes every one of them a sliver
                    bsp_read.py, vtf.py, bsp_import.py — Source .bsp to a map
                    import_maps.sh — import a whole directory of them, idempotently
                    bsp_preview.gd/.tscn/.sh — render an imported map and exit
                    collision_probe.gd/.tscn — drop the player's hull on every
                    standable triangle in an imported map and count what it goes
                    through. `--trimesh` builds the old collider for comparison
```

**There is no `[input]` block in `project.godot`, and that is deliberate.** There was
one — `player_forward`, `player_back`, `player_left`, `player_right`, `player_jump`,
`player_crouch` — and nothing read any of them: [DotFpsSampler] keys off its own
`actions` dictionary of `dot_fps_*` names and `register_default_actions` adds them to
the [InputMap] at runtime for a project that has none. Six actions declared once and
read nowhere, which is the family's own detector for a setting that does not exist.
Removing them rather than wiring them up is what makes this game's client work
**inside another project**: it now ships in dot-server-deploy's browser shell,
whose `project.godot` has no input actions at all, and a game that depended on its own
would have had no controls there.

The keys are therefore the sampler's defaults. Duck is **Ctrl**, not Shift — the
README said Shift for as long as the dead block did, and neither was ever true.

## Where this game runs, besides here

`dot-server-deploy` vendors it: `setup.sh` copies `game/`, `scenes/`, `maps/` and
`avatars/` into that project, `content/g2gfast/game.yml` points at
`res://scenes/g2g_server.tscn` and `res://game/g2g_module.gd`, and the browser shell
maps content id `g2gfast` to `res://game/g2g.tscn`. That is the deployment shape — a
separate process, a real socket, a browser — and by this family's repeated lesson it is
where the bugs are. It found four; two of them are below and two were in other
repositories.

## Decision 1: everything the operator touches is in genre units

`sv_airaccelerate 1000`, `sv_gravity 800`, a run speed of 250 u/s, a surf ramp that is
"1024 wide at 60°". A bhop server operator knows what those mean and nobody knows what
19.05 m/s² is. So every cvar, every config field, every HUD number and every map file
speaks genre units, and **the conversion to the metres the simulation runs in happens
at exactly one boundary — `G2GMovement.tunables_for`** — with `G2GUnits` as the only
definition of the ratio. A conversion anywhere else is a second copy of the ratio, and
two copies drift.

The ratio is **1 unit = 0.01905 m** (0.75 inch), the scale the genre's maps were
built at, not the 1-inch
figure sometimes quoted. It is what the 72-unit hull, the 64-unit eye and every map in
the genre were built against; at the wrong scale a surf ramp is one the movement cannot
hold.

The jump is specified as a **launch velocity** (301.99 u/s) and converted to the height
the tunables want with `h = v²/2g` — 57 units under 800, the number every bhop player
knows — so it stays honest when an operator changes `sv_gravity`.

## Decision 2: auto-bhop is the server's, and the styles defer to it

`sv_autobunnyhopping` (`G2GConfig.auto_bhop`) is the setting this game exists to expose.
It reaches every player through `G2GGame.apply_movement`, which rebuilds the tunables
and hands them to everybody — **abandoning every run in progress**, because a run half on
one movement and half on another is a run on neither. Same rule as a tick-rate change.

**The shipped `DotFpsStyle.defaults()` force auto-hop ON**, which is right for a game
with no cvar and wrong here. The first version left them as shipped and
`sv_autobunnyhopping 0` reached every player's tunables and was then undone by the
style on top — silently. `_build_styles` now sets every style's `auto_hop` and
`easy_bhop` to `INHERIT`, except `prebhop`, whose whole identity is "no auto-hop".

**A movement cvar is validated before the config is written**, through the console's
own validator on a *copy* of the config. The first version wrote the field, validated,
and on failure returned — leaving the config invalid, after which every later cvar
wrote its field, found the config still invalid because of the first, and quietly did
nothing while the console reported them all as set.

### A thing that looked like a bug and is the genre's physics being faithful

A player holding jump from a standstill creeps at exactly 30 u/s — the air cap — for
ever. On the tick a jump fires the player is already airborne when acceleration runs,
so a held key never gets a ground-acceleration tick. Those games do precisely this
(`CheckJumpButton` runs before `WalkMove`), which is why every real bhop run begins with
a **prestrafe**. The headless suite's bot walks before it hops; an hour was spent
finding out why it had to.

## Decision 3: the genre's field of view, not Godot's

`fov_desired 90` is 90° **horizontal at 4:3**, and those games widen it on a wider
screen.
Godot's `Camera3D.fov` is vertical and fixed. `G2GUnits.source_fov_to_vertical`
converts through the 4:3 frame: 90 becomes 73.74° vertical, which on 16:9 shows 106.26°
horizontally — exactly what they show. Handing 90 straight to Godot gives 121° at
16:9 and a player who cannot aim and cannot say why. Tested to the hundredth of a
degree, with the naive number named so it stays a mistake.

`sensitivity` has its usual meaning too: degrees per count is `sensitivity × 0.022`, so a
player's 2.5 works unchanged.

**Third person is cosmetic.** `G2GCamera` keeps both cameras and flips `current`; the
first-person one culls the local rig's render layer so the player does not see the
inside of their own head, the third-person one sits on a `SpringArm3D` and draws
everything. The controller aims from the eye whichever is active.
`sv_allow_thirdperson 0` is server-side because third person sees over ledges first
person cannot, and it puts anybody already in it back.

**`show_own_body` is a third state, and it is not "first person with the cull off".** The
rig's three mounts are in two different places relative to the camera: the body mount is
40 cm below the eye and draws as a torso, arms and legs, while the head and hat mounts sit
*at* the eye — that is what they are for. So a switch that simply showed the whole rig
would put the camera inside a 40 cm cube and fill the view with one flat colour behind a
straight edge, which is exactly the artefact `G2GRig._set_layers_recursive` was written to
end and exactly what it looks like in a bug report. `G2GRig.owner_sees_head` is therefore
a second flag and the three states are *nothing* / *body only* / *everything*, settled in
one place in `G2GPlayer._apply_own_body`.

**The default is applied where the camera is built, not on the first frame that draws.**
`visible_to_owner` defaults to true because that is right for everybody else's rig, so the
local one was only ever *corrected*, once a frame, from `present()` — a `_process` body,
where a script error aborts the call and the game carries on. Any frame that did not
finish drew the player's own avatar at point-blank range. A default that has to be
corrected is not a default.

## Decision 4: one avatar schema, two sources of parts

`G2GAvatars.schema()` is a real `DotAvatarSchema` — body, head, hat — and the rig has one
attachment node per slot. **A stock character and a player's own avatar from the
platform are the same thing at different addresses**: the six stock parts ship in the
build under `res://avatars/`, a platform part names dot-cloud content, and
`DotAvatarBuilder` does not care which it got. A player with no avatar gets
`stock_avatar(id)`, a real document over the same schema, deterministic in the id so the
same player is the same colour on every machine.

`DotAvatarSchema.conform()` **edits the document in place** and returns what it changed.
`G2GAvatars.apply` runs it on a copy, or a server that could not draw one part would
quietly rewrite a player's own avatar. A part from a newer client is dropped, never
refused: a player is never invisible because their hat is from the future.

## The maps, and how they are textured

Three of them now: `bhop_g2g_intro`, `surf_g2g_intro` and `bhop_g2g_stages`, plus whatever has been imported.

**The default is an imported map, and not one of the three.** `G2GConfig.initial_map` is `surf_mesa`. A straight line of blocks over a flat plane is what a *suite* should run — and every example here still names one explicitly — but it is not what a player arriving at a server should be met by. It also makes the imported half the default path rather than the one nothing reaches unless somebody types a map name, which is this family's own rule about deployment shapes: a built-in map is a scene and a script and can never fail to be there, and an imported map is data at a path that has to be found, parsed and built.

**`bhop_g2g_stages` is the first one that is a map rather than a fixture.** The other
two are a straight line of blocks and a pair of ramps: they prove the movement and there
is one thing to do in each, once. It is the timer community's staged shape — five sections
with a line between each, one idea per section, so a player who fails knows which idea
they failed:

```
1  straight    blocks in a line, gaps growing.      Keep the speed.
2  the turn     the course bends 90 degrees.        Strafe through it.
3  the climb    blocks rising 24 units each.        Height costs speed.
4  the drop     a descent onto narrow blocks.       Do not overshoot.
5  the zigzag   blocks alternating left and right.  Both directions.
```

Everything is derived from `_course()`, which walks a position and a heading and returns
every block; the geometry and the zones both read that one list. On a map that *turns*
that is not a nicety — a hand-placed stage line on a course whose gaps somebody later
changes is a leaderboard nobody can compare, and nothing reports it: the run still
finishes, the splits are just taken somewhere else.

**And it had no finish, for as long as it has existed.** `_build` drew the finish pad 384 units along world -Z; `build_zones` placed the finish zone 384 units along the *course heading*, which the turn in stage 2 leaves at 90 degrees and every stage after it inherits. So the pad sits at -Z and the zone sits at -X, 543 units apart, overlapping by a 128 x 24 corner nothing lands on. A player ran the whole map, arrived on a pad drawn in the finish colour, stopped, and the timer counted on for ever. Nothing errored and nothing could: a run that has not finished is a legitimate thing for a run to be, and the pad was exactly where the geometry said to put it.

`_pad_centre()` answers "where is the finish" now and the geometry and the zone both call it — this map's own rule about `_course()`, applied to the one place that was still doing the arithmetic twice.

What let it survive is the more useful half. `headless_maps` asserted the zone set is well formed, `headless_run` asserted the sidecar matches, `headless_imported` drove a timer over the eight imported maps — **and every one of those checks is about the zones, not about the zones adding up to a run.** The check that says so has to cross from the zone set into the geometry, so it is a raycast: drop a ray down the middle of every START, END and STAGE volume and require it to land inside that volume. A zone hanging over nothing is a zone the run never reaches, and from inside the game it is indistinguishable from a map with no end zone in it. It fails on `bhop_g2g_stages` without the fix and passes with it.

The stale-list bug came along for the ride: `_test_zone_files_match` carried `["bhop_g2g_intro", "surf_g2g_intro"]` and there are three maps, so `bhop_g2g_stages` had never been checked against its own sidecar. The files happened to agree; the check was blind either way. It discovers now, which is what `tools/export_zones.gd` stopped carrying a list for.

Its bonus is a **surf** descent on a bhop map, deliberately. A bonus track is a whole
second route with its own records, and making it the same thing as the main route wastes
it; it is also the cheapest proof that a track is a route and not a game mode.

**Every stage zone carries a `destination`**, through `G2GMap.zone_stage`, because
dot-timer's `request_stage` hands the host the zone's destination and one drawn without
it resolves to `Vector3.ZERO` — a point in the sky over the start, reached with no error
at all.

**Surfaces are roles, not colours.** `G2GGeometry.box` used to take a `Color` and set a
flat `albedo_color`, so every surface in the game was one unbroken tone — which in this
genre is not cosmetic. A surf ramp is a plane ridden at 30 m/s and a bhop block is one
cleared in eight ticks, and both are judged by *how fast the surface is going past*; the
only cue for that is a repeating pattern with a known size. `G2GTextures` supplies one,
triplanar and in **world** space, so one square is 64 units — the grid this genre's maps
are built on — on every surface whatever its size. The old `COLOUR_*` constants are role
ids now and keep their names, so no map file changed.

## Decision 12: everything else this family ships, and the timer keeps running

This game had the timer, the movement, the maps and the boards. It now has the rest of
the family — twenty-six addons — and the rule every one of them was added under is the
same sentence:

> **A player who came to run must not be stopped by anything added for a player who
> came to do something else.**

That is not a slogan; it decides the shape of four of them.

```
game/
  g2g_stats.gd     every per-player number, declared once
  g2g_awards.gd    achievements as a document of rules over those ids
  g2g_progress.gd  the node joining the two to the game, and to nothing else
  g2g_arsenal.gd   two weapons, and why they are the genre's rather than an arena's
  g2g_combat.gd    dot-combat + dot-loadout + dot-match, as a LAYER
  g2g_hunters.gd   dot-npc + dot-npc-ai + dot-npc-ai-director, along the course
  g2g_props.gd     practice blocks, frozen, and what they do to a record
  g2g_vote.gd      dot-vote over the map catalogue
  g2g_services.gd  dot-chat + dot-voice + dot-moderation
  g2g_identity.gd  dot-cloud + dot-auth + dot-user + dot-platform
  g2g_client_extras.gd  the client halves of chat and voice
```

### Statistics are read, not counted a second time

`DotFpsStats` has counted jumps, perfect jumps, strafes and top speed on every
controller since dot-player-controller was written, and dot-timer counts runs and records.
`G2GProgress` reads those out and files the **difference**; it measures exactly one
thing itself, which is distance, because nothing else does.

**The difference is not optional and the reason is this game's own.**
`G2GGame._on_player_finished` calls `controller.stats.reset()` on every finish, so
filing the total on each sample would file the whole history on every sample and then
start again from nothing. A total that went *down* is a reset, and the whole new value
is filed rather than a negative one — the same rule `DotAchievementStatsLink` applies
one layer up, for the same reason.

**A best time is `LOWEST`, and getting that wrong is a personal best of zero for
everybody.** dot-stats' `merge` takes the incoming value whole when there is nothing
held, which is the distinction between "held zero" and "never seen"; `Under Thirty` is
the achievement that shows what happens without it, and it carries a second rule
requiring a finished run precisely because *a missing stat reads as zero and "at most
30" is satisfied by having never played*.

### Deathmatch is a layer, not a mode

`sv_deathmatch` adds hitboxes, health, an arsenal and a scoreboard and **takes nothing
away**: the timer still runs, and a player who never presses fire plays exactly the
game they played before. Surf and bhop communities have run deathmatch on their own
maps for twenty years and the reason is that a map whose movement everybody has learned
is a map where a fight is about movement.

The weapons are the genre's rather than an arena's, and that is the whole design: a
one-shot pistol and a knife, hitscan, **no magazine and no reload**. Reloading takes a
hand off the strafe keys, and every second a player spends not strafing on a surf map
is a second they spend falling. The rate of fire is the cost instead. Spread is wide
when moving and tight when still, so the fastest player on the map is the hardest to
hit and the worst shot.

Three things in the wiring that are not obvious:

- **Entity ids come from `DotEntityTable` and are not derived from anything.** They
  used to be the player's own id with the `u` taken off, which worked and taught the
  family why it should not: a derived id means a formula, a formula has an inverse, and
  two spellings of one id format are two ends of a serialisation that never meet. The
  `u` still comes off for the **userid** — a loadout's storage key and
  `session_by_userid` both want the account number, and neither wants a runtime handle.
  One function used to serve both, which was harmless while they were the same integer
  and would have been silent the day they stopped being.
- **The match carries no time limit.** The map's clock ends the map, and a second clock
  underneath it that ends the match is two authorities over one question — dot-vote's
  director already owns the first.
- **The ghost is not armed.** It is a replay: it cannot press a trigger, cannot be hurt
  in any way that means anything, and registering it would put a name on the scoreboard
  that never dies and never leaves.

### A timer map is a critical path, so the hunters have no navigation graph

A hunter cannot catch a runner who is running well — the fastest does 8 m/s and a bhop
player on a good line does forty. What a hunter punishes is **stopping**, which is what
the timer already punishes, made visible.

`DotNpcDirectorFlow` is literally "the map's own critical path" as a thing a position
can be measured along, and a timer map *is* one: start pad, stage lines, end zone. So
the route is built from the map's own zones — the same list `bhop_g2g_stages` derives
its geometry from — the director spawns **ahead** along it, and a hunter with nothing to
chase patrols it. The pathfinding a mesh would give is spent on a map whose route is
already known.

`require_navigable_spawn` is therefore **off**, and it has to be: there is no graph, so
a navigable-spawn requirement would refuse every spawn on the map.

### Blocks are frozen, and they cost you the record

What a records community actually places is a practice line, a temporary block on the
section everybody fails, and a marker at the spot people keep asking about. Every one
of those wants to stay where it was put, so a prop here is spawned **frozen** — the
opposite default from a sandbox's, and the reason `g2g_prop_body.gd` has a
`starts_frozen` export at all.

**`only_practice` is on, and it is what makes the feature safe to ship.** A board with
one time set over a placed block is a board nobody trusts, and the alternative —
trusting an admin to clear up — is a rule enforced by memory. The sizes are 32, 64 and
128 units, the grid this genre's maps are built on, converted at the one boundary
`G2GUnits` owns.

### The vote this game shipped with was not one

`G2GGame.rock_the_vote` forwards to `DotMapTimeLimit`, which counts votes against a
fraction and expires the map: a countdown and a tally. `G2GVote` is the ballot a
records community actually runs — nominations with caps and seconding, an instant
runoff so a six-option vote is not won by a fifth of the server, a cooldown, and an
**extend** option, because a player two stages into a run they have been learning for an
hour should not lose the map to a clock.

Two decisions in it:

- **`begin_on_apply` is off.** The map session's own `changed` is the one signal that
  says what is running, because it fires for an admin typing `g2g_map` as well. Both
  firing means two entries in the play history for one play, and a "not in the last
  five maps" cooldown that is quietly two or three.
- **The ghost is not a voter.** `_player_count` excludes it, because otherwise a
  one-player server passes a quorum of two and can rock the vote on its own.

### Chat is the policy; dot-server stays the transport

`G2GServices` hooks `player_chat` and **cancels** it, routes the text through
`DotChatRouter`, and hands each recipient's line back to dot-server's manager to put on
the wire. Exactly one of the two delivers a line, which is what stops them being two
chat systems.

The channel that is about this genre is `running`: everybody who is mid-run. It is a
`MEMBERS` channel and the membership rule — "their timer is going" — is a thing only
this game knows, which is exactly why dot-chat asks rather than deciding. The team key
falls back to it, because a timer server has no teams and a team message on one reaches
the single player whose team number matches.

**dot-moderation is built first, and the order is load-bearing.** It publishes
`dot_mute_source` on `_ready` and both routers look that name up when they start; a
router that started first would find nothing, warn once, and enforce no gag for the life
of the server. It is here at all because dot-server's mute is two booleans on a session
object and a session dies with its connection — on a records server that matters more
than usual, because a gag is how an admin stops somebody spamming `!wr` at everybody.

**Voice rides its own channel on the link.** A talk spurt is fifty frames a second per
speaker relayed to every listener; on the state channel it would sit in the same ordered
queue as the snapshots, so somebody holding the talk key would add a frame of latency to
everybody's movement — and on a server where a run is counted in ticks, latency must not
depend on whether anybody is talking. The speaker id is stamped from the transport's
sender and never read out of the payload.

Its default channel is **ALL**, which is the opposite of game-arena's, and both are
right: an arena is a room, and a course is long and thin with half the server two
hundred metres away.

**UDP on a desktop and TCP in a browser, and neither is chosen anywhere.** The two
voice calls are declared `unreliable`, which is what voice wants: a lost frame is 20 ms
of silence a jitter buffer conceals, and a resent one arrives after the frames either
side of it have already played. What that becomes on the wire is `DotTransportAuto`'s
decision, and it has one sensible answer either way — ENet honours the unreliable
channel as UDP, and a browser has no UDP at all, so WebSocket delivers it reliably and
in order over TCP whatever anybody asks for. The platform rule falls out rather than
being written, and neither game names a transport.

### The server browser, from the other end

`G2GQuery` has contributed the map, the tick rate, the styles and the world record
since the module was written, and **nothing had ever read any of it**. `G2GBrowser` is
dot-browser's client half: the list model, three protocols, local filters, favourites
and history — and `dedicated` now has a real browser ask a real `DotServer` over a real
UDP socket, which is the seam the family's notes name as untested.

Two things a reader of a query section gets wrong once, and both were got wrong here
first:

- **The map is not `entry.map`.** That is dot-server's `info.map`, which means "the
  content id of the loaded game" and is empty on a server that never switches games.
  dot-browser nests a game's own section under `rules["game"]` precisely so a game
  putting a field called `map` in it cannot overwrite the other one.
- **JSON has one number type.** `tick_rate` is contributed as an int and comes back as
  a float, so `game_field(entry, "tick_rate")` is `"100.0"`. `game_number` is the
  accessor; `wr` is a dictionary and has a third.

The list is a chat command rather than a screen — `!servers`, or F3 — because that is
what this genre's fingers already do, and because this client has a HUD and a keyboard
rather than a [DotScreenStack]. game-arena has the screen. The same addon does the same
work either way; where it is drawn is the half a game is supposed to decide.

## Validating

```bash
godot --headless --path . --import
godot --headless --path . --script tools/export_zones.gd
godot --headless --path . res://examples/headless_run.tscn   # 170 checks
godot --headless --path . res://examples/headless_presentation.tscn  # 85 checks
godot --headless --path . res://examples/headless_net.tscn   # 113 checks
godot --headless --path . res://examples/dedicated.tscn      # 174 checks, 16 sections
godot --headless --path . res://examples/jitter_probe.tscn   # 4 configurations
godot --headless --path . res://examples/headless_imported.tscn  # 29 per map, +1 per stage
godot --headless --path . res://examples/headless_maps.tscn      # 27 checks
godot --headless --path . res://examples/headless_stack.tscn     # 29 checks
```

`headless_maps` is the one that says there is no list of maps anywhere: it removes a
map from the catalogue that is still on disk and checks a rescan puts it back, and adds
one to the catalogue that is *not* on disk and checks a rescan takes it away. Counting
three maps proves nothing — a hardcoded list of three counts three too.

`headless_imported` skips cleanly when `maps/imported/` is empty, because an imported
map is optional content and a fresh clone that has never run the importer is not
broken. It iterates whatever is there rather than naming a map, for the reason the
catalogue does.

Its last two sections are the ones that say a map is a **level**. `_test_runnable`
drives a `DotTimer` over the map's own zone set and asserts a time comes out with every
split in it; `_test_stands_where_it_sends_you` teleports a player to each track's spawn
and each `!s<n>` destination and waits to see whether they are still there a second
later. A zone set can pass `problems()`, have no thin volumes and still be impossible to
finish, and a stage destination that is in the sky succeeds at every step and drops the
player out of the world.

`tools/bsp_preview.sh` renders each of them from its spawn, because four of the bugs in
this family's list were found by looking at a picture. It uses `xvfb-run`: `--headless`
gives a null renderer and saves a frame of nothing, which is worse than no screenshot
because it looks like one.

`jitter_probe` is the only one that measures a **rendered frame** rather than a
simulated tick, which is the whole class of bug the others cannot reach. See
Decision 10.

**Two checks in `headless_run` were measuring the wrong thing and only stopped when
dot-timer was fixed.** `DotTimer.effect_requested` was emitted by nothing, so this
game's maps had respawn zones that did nothing and a bot that missed the ramps fell out
of the level and kept falling. "Most of the descent is spent not grounded, which is
surf" was counting 1500 ticks of a bot nowhere near the map, and passed comfortably.
The bot is now put back on the start platform after about 500 ticks; the loop stops
there, is airborne for 94% of them, and the suite asserts the pit fired at all. The
bhop test's fixed 420-tick prestrafe had the same problem and now drives until the run
starts.


`headless_net` runs a server game and a client game in one process over a lossy
loopback: admission, prediction converging, the timer and a finish replicated to the
sub-tick fraction, a cvar changed under a live client, styles, tracks, a published
avatar, a map change, a bot, and leaving.

`dedicated` counts its sections and its checks since 2026-09-24 — it had neither, the one suite here without a total — and exits 1 when either is off; armed by raising `CHECKS` by one.

`dedicated` configures the server for **100** ticks in `server.cfg` — deliberately not
the project's 128 — and checks the game and the timer count at 100, because a test
using the same number at both ends would pass with the chain disconnected.


## Two layers, and the one line that had to tell them apart

`G2GRig` keeps a player's body on two visibility layers so the **owner's** first-person camera can cull it while every other camera still draws it — layers rather than `visible`, because a first-person player who is culled out of their own view still needs their shadow, which is the only cue a first-person view has for how tall they are and where they are standing.

Every part of that worked except the part that had to differ. `G2GCamera.first.cull_mask` correctly excludes `LAYER_LOCAL_BODY`, `third` correctly includes it, `G2GPlayer` correctly sets `rig.visible_to_owner = camera.is_third_person()` — and `_set_layers_recursive` then set **both** layers unconditionally, so the culled layer was never the only one. `owner_sees` arrived and was used for nothing but a `cast_shadow` ternary whose two branches were identical, which is the tell. The first-person camera therefore drew its own player's avatar at point-blank range and the bottom third of the screen was a magenta dome, on every map, in every frame, for every player.

**No assertion in this repository looked at a layer mask**, and none of the numbers involved were wrong — there was nothing to notice except the picture. It was found in a screen recording. `headless_presentation` checks it now, because the check is one bitwise AND against the camera's own cull mask and the alternative is noticing again.

## The player layer is reached, and third person here stays cosmetic

`G2GPlayerStack` was built, installed and instantiated, and most of it was not *asked*
anything. Three joins were made in one pass and each is a decision.

**The spawn director chooses the start now, and the map is the fallback.** It had every
track's start in it and `spawn_player` used the map directly beside it, so the director
answered nothing for the life of a server. What it adds over the map is the per-site
cooldown, the occupancy check and — with `sv_deathmatch` on — the protection window, which
`DotSpawnProtection.grant` only ever opens from inside `DotSpawnDirector.choose`.

**A start is per TRACK, which needed a condition dot-spawn did not have.**
`MetaEquals` compares a site against a constant fixed when the condition was built;
nothing compared one against the *request*. So a course whose every track starts somewhere
else either built one director per track or picked the site itself — and picking it
yourself is one line, which is what every game had done. `DotSpawnConditions.MetaMatchesRequest`
is the addition, and `DotSpawnRequest.make` carries an `extra` dictionary for it.

**The sites are checked against the loaded map rather than trusted to arrive in order.**
`map_ready` and the respawn that follows a map change are not ordered, and losing that race
means answering confidently from the previous map. See `docs/bugs-found.md`.

**`sv_deathmatch` is what opens the protection window**, and it is shut on a pure timer
server: there is nothing to be protected from, and a window with no attacker is a rule with
no purpose. The duration is `G2GArsenal`'s own match rule rather than a second copy.

### Third person stays `G2GCamera`'s, and does not become `DotTpsController`'s

game-playground now runs dot-player-controller's third-person half over a
`DotPlayerControllerSwitch`, and **this game deliberately does not.** Decision 3 already
says why in one line: *third person is cosmetic.* `G2GCamera` flips between two cameras
over **one motor**, so a run set in third person is comparable with one set in first.
`DotTpsController` is a genuinely different motor — camera-relative input, its own
acceleration, coyote time, a jump buffer — and a player who could switch to it mid-run
would be setting a time on movement nobody else was using. On a records server that is not
a feature, it is a leaderboard nobody can compare.

### And the HUD can be looked at

`tools/screenshot_hud.sh` renders the clock, the keys, the stage line and a notice.
`tools/bsp_preview.sh` draws MAPS and this game had nothing that drew its interface — the
only game in the family without one. Its first frame found a filed time drawn straight
through the clock.

## Decision 5: the movement configuration travels, not the tunables

`G2GNetBridge` sends a joining client the server's `G2GConfig` movement fields
(`G2GConfig.MOVEMENT_FIELDS`) and both ends derive `DotFpsTunables` through the same
`G2GMovement.tunables_for`. The alternative — sending the tunables — is one more
representation that can drift, and prediction only converges when the two ends
simulate with identical numbers. The server fingerprints what it derived and the
client compares; a mismatch is one log line rather than "the netcode feels bad".

That is also why `G2GConfig.snap_movement()` exists and why `G2GGame` calls it before
deriving anything: the wire carries float32, and a server simulating with the doubles
it read from a file while its clients simulate with what they received differs in the
last bit, silently. The values are rounded once, on the server, before anything reads
them.

The bridge is modelled on dot-2d-hungry's, the one in this family proven over a real
socket. What is specific to this game:

- **The tick is a whole-game property.** dot-net simulates per entity; here everybody
  moves and then every timer is fed the position its move produced. The first
  behaviour through on a tick runs the whole game (`ensure_game_ticked`); the rest find
  it done. The client's `client_tick` does the same for what it predicts and then feeds
  every timer, so a remote player's clock on your HUD advances with theirs.
- **Timers replicate as run identities, not per tick.** `DotTimerNet.RunState` carries
  the start tick and the sub-tick fractions; the client's clock does the counting
  between packets. A finish carries ticks and fractions, and the client reproduces the
  server's arithmetic to the digit — `headless_net` compares them at 1e-4 s, which is
  how it found `DotTimerNet.Finish.time()` subtracting the end fraction the run adds.
- **A peer receives nothing until it says READY.** dot-server's signon finishes and
  *then* the client builds its scene; a HELLO sent in between lands on nothing.
- **Bots are session ids without a peer.** Peer 0 is dot-net's broadcast address, so
  a bot is never a peer; `remove_player` handles both, `remove_peer` delegates.
- **A player's avatar comes from dot-platform's admission** (`G2GModule._avatar_for`,
  duck-typed through the `platform` module) and, failing that, from what the client
  publishes (`G2GClient.avatar`), and failing that the stock one. Every one goes
  through `G2GRig.dress`, which conforms it to the server's schema.

## Decision 6: the record's ghost is a player

The replay bot every community timer has: the server record's replay runs the map
as a `G2GPlayer`
with `replay` set and no timer. That one choice does three jobs. It draws through the
same rig everybody else does; it replicates through the same bridge, so a client —
browser included — sees the run without ever decoding a replay; and it counts as a
bot in the server query, which is what it is.

`sv_replay_bot` turns it on and off live, and off takes the current ghost away rather
than waiting for the next map — an operator who turns a bot off wants it gone now.
`g2g_ghost` says whose record is running and how far through it is.

`G2GReplays` keeps the fastest replay per map, track and style, in memory always and
on disk beside the records when there is a directory, using `DotTimerReplay`'s own
file format — so a replay set at 64 Hz plays on a 128 Hz server. **A replay is kept
only with an accepted record**, never with a merely faster run: a checkpoint-assisted
or tainted run is not a record and must not become the ghost everybody chases.

The bridge adopts any player the game made itself (`player_added`) as an entity with
no peer, and `ensure_game_ticked` applies received commands **only to players that
have a peer** — a bot is driven by something else, and an empty command applied on
top of a replay stands the ghost still. That rule was found by `dedicated`, whose
driven bots stopped hopping the moment the bridge started adopting them.

`!r`, `!wr`, `!top`, `!style`, `!track`, `!rtv` are chat triggers as well as console
commands, because twenty years of bhop servers taught everybody's fingers those.
`g2g_map` is not: changing the map from chat is an admin's, through the console.

## Decision 7: the client counts at the SERVER's tick rate

`HELLO` carries `tick_rate` and always did. Nothing read it back out.

`G2GGame._resolve_tick_rate` takes `Engine.physics_ticks_per_second`, which on a server
is `sv_tickrate` and on a client is whatever the host project exported — 128 in this
repository, **60 in dot-server-deploy's browser shell, which never sets one**. So a
client simulated at a rate the server did not, and three things are derived from that
number: the step prediction replays with, the divisor every replicated run time is
reconstituted through, and `DotNetClock`'s own rate.

Measured, by putting `headless_net`'s client on 60 against its 128 server: **correction
rate 0.96** — prediction never converging — and the client's clock reading a finish as
0.466 s where the server filed 0.218 s, which is 128/60 of it. On a leaderboard that is
every time on the board wrong by the ratio of two numbers nobody thought were related.

`G2GNetBridge._adopt_tick_rate` now applies it before `sync_from_server`, because the
clock converts its error and its input lead through `tick_rate`. All three copies move
together: `G2GGame.set_tick_rate` (which takes the timer manager with it and reads the
rate back rather than assigning it), `net.config.tick_rate`, and `net.clock.tick_rate`
— the last one being a copy taken at `setup()` that writing the config does not touch.

**`headless_net` could not have found this and now can.** Both halves run in one
process, so they read one `Engine.physics_ticks_per_second` and agreed no matter what
the wire said; the check that asserted "at one tick rate" was passing for that reason
rather than for a good one. The suite now puts the client on 60 deliberately, the way a
host project would, and asserts that HELLO is what corrects it.

The same shape found two more, both only visible in a browser:

- **A client's own configuration was invalid.** `G2GClient` clears `initial_map` when it
  is networked — correct, the server decides — and `G2GConfig.validate()` refused an
  empty one unconditionally, so `load_layered` failed and every networked client logged
  "the g2gfast configuration is not usable". Only an authoritative instance chooses a
  map.
- **dot-timer warned every client that its times would be wrong.** The rate/engine
  mismatch warning is real on a server and meaningless on a mirroring timer, which
  counts at the rate it was told precisely so a run set at 128 is comparable on a client
  rendering at 60. It is now guarded on `authoritative`.

## Decision 9: the local player is adopted, not looked up

`HELLO` says who you are. `JOIN` is what creates you — `G2GNetBridge._apply_join` calls
`game.add_player` — and it arrives afterwards. So `G2GClient._watch`, called from
`hello_received`, resolved `game.players.get(id)` **one message too early**, got null,
and never tried again: [member G2GClient.player] was null for the entire session on
every networked client.

**What that broke is a strange list, and the strangeness is the point.** The HUD binds by
id, so it worked. The camera follows the entity, so it worked. Movement worked, because
`DotFpsSampler.sample` polls the [InputMap] rather than reading events. What did not work
was everything below the `player == null` guard in `_unhandled_input` — **mouse look, F5,
Tab, R, C, V and M**. A client that connects, draws, shows a live HUD and walks around,
on which the mouse and the whole keyboard do nothing.

`_on_player_added` is the fix: connect [signal G2GGame.player_added] before anything can
create a player, keep the id in `_watch_id`, and adopt when the player named by it
appears. `_adopt` is also where the sampler is put on the player's tunables, which
`_on_hello` used to attempt against the null it had just fetched.

`headless_net` drives two bridges directly and never instantiates `G2GClient`, so nothing
in the suite had been through this. It now asserts the ordering the bug lived in — that
the local player does **not** exist when HELLO names it, and that `player_added` fires for
it — which is what a client has to be written against.

**How it was actually confirmed.** Not by a test: Playwright cannot move a pointer-locked
mouse — `movementX`/`movementY` come through as `0` on every synthetic event — so the
symptom the player reported is not directly reproducible in the harness. F5 is, and it
sits in the same `match` under the same guard: press it, screenshot, and third person is
either drawn or it is not. *When the thing you want to test is unreachable, test the
thing beside it that shares the failure.*

## Decision 10: the client draws BETWEEN ticks, and the engine runs at the server's rate

Reported as "very jittery in the browser", and every number in every suite was right.

The simulation was already correct. `G2GClient._physics_process` asks
`DotNetClock.advance` how many ticks a frame is worth, so a client on a 60 Hz engine
against a 128-tick server ran exactly the right ticks — **in bursts of two and three**,
2.133 of them per physics frame. Nothing rendered between ticks: `G2GPlayer.present`
drew `controller.state` directly, so the camera advanced 74 mm on six frames out of
seven and 112 mm on the seventh. **A 47% change in apparent speed, eight times a
second**, for as long as a browser client has existed.

Two halves, and **either one alone measures as no better than doing nothing**:

- **`DotFpsController.render_state` exists and nothing called it.** It has interpolated
  between the last two ticks since the controller was written, and its guard was
  `if drive != Drive.LOCAL: return state` — LOCAL being the one drive no networked game
  uses. So the cure was written, documented as the cure, and unreachable from every
  deployment shape that needed it. `_accumulator` is never advanced under EXTERNAL
  either, so even reaching it would have blended at a constant alpha of zero.
- **`_adopt_tick_rate` moved three copies of the tick rate and not the engine's.** The
  fraction a renderer interpolates at is a fraction through a *physics frame*, which is
  only a fraction through a tick while the two rates agree. At 60-against-128 the
  interpolation changes nothing measurable.

`examples/jitter_probe.tscn` runs all four combinations and fails unless exactly the
shipped one is smooth — because a probe that only tested the fix would have passed for
either half on its own.

| | drawn at the last tick | drawn between ticks |
| --- | --- | --- |
| **engine 60** | 47% spread | 47% spread |
| **engine 128** | 47% spread | **0%** |

**View angles are deliberately still not interpolated**, and they never juddered: mouse
motion is delivered once per frame and `DotFpsSampler.sample` consumes everything
pending, so whichever tick runs next absorbs exactly that frame's motion and the yaw
tracks the mouse per frame however many ticks ran. Blending it would add a tick of
latency to aiming to fix nothing.

The cost is real and worth naming: a browser client now steps Godot's physics 128 times
a second instead of 60. The work inside the tick is unchanged — the clock was already
producing 128 ticks a second — so what is added is the engine's own physics step, which
for a world of static geometry and one query-driven controller is close to free.

**Nothing headless could see any of this**, which is why it survived every suite:
every check in this repository asserts a simulated value, and every simulated value was
correct. `jitter_probe` is the first thing here that samples what a *frame* shows.

## Decision 8: the browser is asked for the mouse, not told

`G2GClient._ready()` set `Input.mouse_mode = MOUSE_MODE_CAPTURED`, which is right on a
desktop and impossible in a browser: pointer lock needs **transient user activation** —
a real click — and `_ready()` is the one moment in a client's life guaranteed not to
have one.

It is refused *silently*. `Input.mouse_mode` reads back as CAPTURED, the view still
turns with the mouse, and nothing anywhere reports a problem; what the player gets is a
cursor sitting on top of the game that wanders out of the window mid-run.

**This is the family's deployment-shape rule on a capability nothing had needed yet.**
game-hungario is the only other browser client in the family and it is 2D — it reads the
cursor's position and never locks it — so g2gfast is the first thing here that has ever
asked a browser for pointer lock, and the first place this could have been found.

- Desktop captures immediately. A player who launched a first-person game should not
  have to click their own window first.
- Web shows the cursor, says "Click to play" on the HUD, and captures on the first
  mouse-button press. That press is handled *before* the `player == null` guard, because
  a browser player clicks while the world is still loading more often than not, and a
  click swallowed for want of a player is a click that never captures anything.
- Escape **releases** and does not toggle, on both platforms. Escape is how a browser
  itself exits pointer lock and it then refuses to re-enter for about a second, so a
  toggle bound to it silently does nothing every other press on the web. One key that
  releases and one gesture that captures is the same contract everywhere — and it is
  what this file's own class documentation had claimed all along while the code toggled.

Verified with a real click in headless Chromium: `document.pointerLockElement` is null
before and set after. `tools/browser_check.mjs` never clicks, which is why nothing had
exercised this.

## Decision 11: an imported map is content, and it is read rather than rebuilt

`tools/bsp_import.py` turns a Source-engine `.bsp` into a map this game
loads: geometry, the textures the file carried inside itself, the lighting its
compiler baked, its start line, its finish, its stages, its bonus tracks and the
volumes that catch a player who fell off the ride. It was written against
`surf_kitsune` and `Surf_Mesa` in `godot/inspirations/`, and now runs over the eight
maps there.

**The scale is not converted, because there is nothing to convert.** Source stores map
coordinates at 0.75 inch per unit and [G2GUnits] already declares exactly that ratio,
for exactly this reason — a surf ramp imported at the 1-inch figure is a ramp the
movement cannot hold. A BSP coordinate *is* a genre unit. The whole transform is the
axis swap, because Source is Z-up and Godot is Y-up:

    godot = (src.x, src.z, -src.y)

**START and END zones are read, not guessed — and where there is nothing to read they
are written down by hand.** The paragraph that stood here said a map of this genre has
no convention for a start and a finish that survives compilation. That is true of
`surf_kitsune`, which really does drive its stages with
`OnTrigger !activator,AddOutput,targetname X` and a filter chain, and it was false of
five of the eight maps beside it, which carry `zone_start`, `map_end_zone`,
`startzone_s4`, `tm_bonus2_endzone` and `tm_checkpoint1` in the entity lump in plain
text, because they were built for a timer. **Reading a label the mapper wrote is not
guessing, and throwing it away cost every one of those maps its timer.** `zone_role()`
is the whole rule; `assign_tracks()` turns `bonus2`, `koga` and `b_` into track
numbers.

Three of the eight label nothing, and for those — and for the halves the labelled ones
are missing — there is **`maps/zones/<id>.json`**: one file per map, checked in, saying
which volume is the finish and *why*, in terms of what is in the .bsp rather than in
coordinates somebody typed. A zone there names its volume as an entity
(`"named": "startzone_s4"`), as the teleport aimed somewhere (`"teleport_to":
"endroomdest"`), as a box grown around a destination, or as the nearest trigger to a
point; anything that fails to resolve **stops the import**, because a finish line that
quietly resolved to nothing is a map nobody can finish and nothing about playing it
would say so. `maps/zones/README.md` is the format.

That directory is beside the repository and not beside the import for one reason:
`tools/import_maps.sh --force` rewrites every manifest, so a hand-written zone kept in
one would survive exactly until somebody re-imported the map it describes.

**The solid is the brushes, and the drawn faces are only the ones that ended up
visible.** The importer read the face lump and the map got `create_trimesh_collision()`
over what came out of it, which sounds right — a surf map is static geometry and a
trimesh is what a swept hull wants — and is a collider with most of itself missing.
vbsp deletes every face nobody can see, a mapper paints the rest `nodraw`, and a surf
ramp is routinely wrapped in `tools/toolsplayerclip`, which is invisible by definition
and is the reason the ramp is smooth to ride. **Between 31% and 77% of the sides of a
solid brush are not drawn**, over the eight maps in `inspirations/`. So the brush lumps
are read now — `LUMP_BRUSHES`, `LUMP_BRUSHSIDES` and the leaf tree that says which model
owns what — and each brush's half-spaces are solved into the convex hull the mapper
drew. That is the same geometry the genre's own player movement traces against, and it
is why it is **convex per brush and not one trimesh**: a concave shape is loose
triangles and a sliding hull catches on every interior edge between them, which on a
45-degree ramp at 3000 u/s is a run ended by a bump that is not there. Displacements
are the exception, because terrain is not convex in any useful way; they stay triangles,
welded across the map so the seams between them at least are shared.

Two things decide what is solid, and the contents flags are only one of them: a
`trigger_teleport`'s brushes carry `CONTENTS_SOLID` — 186 of them in `surf_beginner2`,
and they are the pits — so `SOLID_BRUSH_ENTITIES` in `bsp_read.py` decides by classname,
and a classname in neither list is left non-solid and **printed**, because the
alternative to a note is an invisible wall nobody can explain.

**What a surface is FOR comes from its slope, not from the name of its texture.** There
was a list of regexes over material names here — `concretefloor039a` is a ramp,
`nodraw` is a platform — on the reasoning that the name is the only intent a compiled
.bsp still carries. It is not, and the regexes scored almost nothing: `surf_beginner2`
came out 97% FLOOR, one grey mass with the ride invisible inside it. In this genre what
a surface is for is exactly what its angle lets a player do with it, and that is a
number in the plane lump. Face area by normal Z comes out in three clean bands on every
map: ~30–43% at +1.0, ~46–55% at 0.0 and a distinct 1.6–8.5% between — the ride. The
line between PLATFORM and RAMP is `G2GConfig.max_slope`, because a texture that says
"you can stand here" where the movement says otherwise is a texture that lies.

**A surface the .bsp carried no texture for gets the prototype set, not a flat
colour.** Most of a surf map is built from textures that live in the game's own VPKs
and were never inside the file — 97% of `surf_beginner2`'s triangles, 100% of
`surf_year3000`'s — and those used to be painted one flat `G2GTextures.ROLE_COLOURS`
tone each. They get `res://textures/prototype/` now, keyed by the role above, with UVs
built from a **tangent frame in the face's own plane** rather than an axis projection:
dropping the dominant axis is one line and stretches the grid by root two along exactly
the direction a player is travelling on a 45-degree ramp, so the one surface whose
texture is being read for speed is the one drawn at the wrong size. A frame in the
plane has no stretch and falls out with one axis running down the slope, which is the
line a surfer steers by. The mesh carries UVs in **64-unit squares** and the material
scales by the tile's share of that, because how many squares are in a tile is a
property of the image and which image is installed is not known until load.

**`surf_kitsune` renders as black silhouettes with neon wireframes on them, and that is
the map.** It is worth writing down because it looks exactly like a broken import and
was checked twice. Its own textures came out of the pakfile correctly: `grids_grid_*`
are 1024x1024 and mean 6 to 11 out of 255 — a black panel with one bright line on it —
so the map is black because it was built black. Raising [member G2GBspMap.ambient]
changes nothing there, which is the tell: ambient multiplies the albedo, and ten times
nearly nothing is nearly nothing. `surf_mesa` through the same path is a lit rock
canyon.

**Half of that has since turned out to be a bug after all, and the reasoning above is why it took so long to see.** Two of `surf_kitsune`'s black surfaces were the map and two were not, and the paragraph above could not tell them apart because it only ever asked whether the *albedo* was black. Its `grids_grid_*` panels are still exactly what it says — built black, on purpose, and they stay. Its `tools/toolsblack` panels are 1024x1024 pixels of flat zero with nothing in them at all, which is a missing texture wearing a correct decode, and they get the prototype set now. And every surface of every map, kitsune included, was being drawn in the transparent pass — see the ALPHA entry under *What building it found*. A map that is black for a stated good reason is the ideal place for a rendering bug to hide, because the explanation arrives before the question does.

`tools/collision_probe.gd` is how any of this is checked. It drops the player's hull on
every upward-facing triangle in a map and counts what it goes through, with `--trimesh`
to build the old collider from the same data for comparison — **32.8% → 1.1% on
`surf_beginner2`, 16.4% → 0.0% on `surf_kitsune`, 26.9% → 0.0% on `surf_year3000`**, and
what is left on the first is water. It is a tool and not an assertion because the answer
is a percentage of one map rather than a pass. The suite's own check — one bot, one
spawn, still standing three seconds later — passed on all eight maps the entire time.

**Solid is not the same question as rideable, and only the second one is what a surf map is.** `collision_probe` asks whether a surface holds a player up; nothing asked whether a player can *travel along* one, which is the entire activity. `tools/surf_probe.gd` sweeps the hull down the steepest line of every RAMP triangle and `tools/surf_run.gd` runs the real [DotFpsMotor] from one for four seconds. Both exist because a run that dies halfway down a ramp is invisible to every assertion here — the ramp is solid, the spawn is fine, the map is right in a screenshot, and the bot that stands on it for three seconds never moves.

What they say about `surf_mesa`, which is the map the complaint came from:

- **The slope rule is not the problem.** Zero of 13,086 simulated ticks reported grounded on a face steeper than `max_slope`, so a player is never *standing* on a ramp and friction is never applied to a ride. That was the first suspicion and it is wrong.
- **2.4% of ramp sweeps stop dead against a face that opposes the travel**, and two thirds of those clear when the hull is lifted eight units — so they are obstructions standing proud of the ride, not walls the mapper drew across it.
- **Roughly 40% of them are the displacement collider.** Rebuilding the map without it takes the dead stops from 98 to 58 out of 4000. That is the concave-shape warning three paragraphs up, arriving: a displacement is `ConcavePolygonShape3D`, which is loose triangles, and a hull sliding across one catches on the interior edges between them. `surf_mesa` is the worst case in the set — 183,552 displacement triangles and **zero** playerclip brushes, so nothing smooths the ride the way the other seven maps' clip brushes do.

Not yet fixed, and the fix is not one line: a displacement grid would have to become convex geometry the way a brush does, which is 91,000 quads on this map and cannot be 91,000 shapes. The measurement is written down here so the next attempt starts from a number.

**Second pass, with the real motor and a seeded sample, and the first pass's headline number was noise.** `tools/surf_run.gd` runs [DotFpsMotor] itself; `Array.shuffle()` uses the global RNG, so two runs sampled different triangles and a sweep over `max_slide_iterations` came out 5:1488, 8:2525, 12:1212, 16:619 — which reads as a result and is entirely which triangles got picked. Both probes seed now. **Every before-and-after in a tool that samples has to sample the same things, and a tool that does not say so will produce a trend on request.**

What the seeded numbers say, over ~15,000 simulated ticks per map:

- **The slide almost never fails.** Genuine wedges — iterations exhausted — are **1 tick on `surf_beginner2` and 0 on `surf_mesa`**. That was not visible before, because [member DotFpsMotor.stuck_ticks] counts the duplicate-plane early-out as well, and that path is the *intended* one. It reads 10% to 14% of ticks and is almost all the early-out. `ran_out` and `stopped_on_duplicate` are separate now; the counter that anybody would have reached for was reporting a working mechanism as a fault.
- **What actually fires is the duplicate-plane break, on 1481 and 2219 ticks.** `_remember_plane` treats normals within 2.56 degrees as the same plane, which is right for one long ramp and is the exact shape of an imported one: **a curved ramp is not a surface here, it is a fan of convex hulls a degree apart**, so the second contact of nearly every tick is a near-copy of the first. The move then breaks with most of the tick's motion unspent, keeping the velocity. A player holding 900 u/s on the HUD and crawling up a ramp is that, and it is what was reported.
- **The two maps fail for different reasons**, which is why one fix will not do. Rebuilt without the displacement collider, `surf_mesa` goes 2219 → 278 (87% of it is the terrain trimesh) and `surf_beginner2` goes 1482 → 1482, not one tick (all of it is brush hulls).

Two things were tried against it and neither is kept. The classic 1.001 **overbounce** is genuinely missing — `_resolve_planes` clips with `Vector3.slide`, an exact projection, while its own acceptance test carries a `-1e-5` tolerance because "a direction exactly in a plane reads as entering it about half the time" — and adding it moved the count the wrong way by 2%. **Clipping and continuing** instead of breaking took `surf_mesa` from 2 runs carried to 7 and `surf_beginner2` from 0 to 2, and took stalls from 7 to 9. Both are changes to collide-and-slide in an addon five games share and the netcode predicts against; neither earned that on those numbers. The diagnosis is here and the decision is not this file's to make.

**Two things the probes cost before they measured anything**, both in [docs/gdscript-hazards.md](../../docs/gdscript-hazards.md) now: `%g` is not a GDScript format specifier and a failed format returns the string unchanged rather than raising, so a probe printed its own placeholders; and `const X := PackedFloat32Array([...])` is not a constant expression, which fails at parse time with a message about constants rather than about packed arrays.

**A track with a start and no end is dropped, and said so.** `surf_summit`'s third
bonus has a start zone, eight checkpoints and no finish anywhere in the map. Left in,
it is a track a player can begin and never complete and one `DotTimerZoneSet.problems()`
refuses the whole map over; dropped silently it is a bonus that quietly does not exist.

**A teleport is the pit unless the map says otherwise.** Every `trigger_teleport` left
after the zones have claimed theirs becomes `DotTimerZone.Kind.RESPAWN`, which is what
it always was and the reliable half. `surf_kitsune` is where that is not enough: all 53
of its teleports aim at one of nine colour destinations, and the ones the size of a
room are the pit under that colour's section while the ones the size of a door are how
you leave one section for the next. Treated alike — which is what "every teleport is a
RESPAWN" does — **walking out of the first section ends the run and puts the player back
at the start, for ever.** `"doorways": {"max_horizontal": 512}` in the map's own file
opts into the measurement that separates them, and the doors become
`Kind.TELEPORT`, which keeps the run. It is opt-in because it is only true of a map
whose sections are joined by doors.

**The mesh is a binary and not a glTF, and the reason is one array.** The baked
lighting needs `ARRAY_TEX_UV2` to reach the shader, and every route through an
importer decides for you what a second UV set means: glTF's occlusion channel is
greyscale, so the coloured neon that is `surf_kitsune`'s entire character goes grey,
and its emissive channel is additive, so it washes out. Building the [ArrayMesh] from a
`PackedByteArray` costs one pass and keeps this repository's own convention anyway —
maps here are made in code.

**Imported maps are discovered, not listed.** `G2GMapCatalogue.scan` scans
`maps/imported/` for manifests. The three hand-written maps above it are a list because
they cannot appear without somebody editing this repository; an imported one arrives by
running a script, and a second place to remember it is the shape that has gone stale
four times in this tree — `setup.sh`, `tools/check.sh`, `package_check.sh` and the
bootstrap manifests. The manifest cannot be forgotten, because the map does not load
without it.

### What building it found

- **`dmodel_t` is 48 bytes and reading it as 52 still produces a perfect world.**
  Model 0 is the first record, so every field before the overrun lands correctly: the
  map rendered flawlessly, at the right scale, with correct materials — and every one
  of the 92 brush models after it was misaligned, so all 53 trigger volumes were
  garbage. Nothing errored, because a wrong AABB is a legitimate AABB. It showed only
  because the sizes came out **negative**. The family's own "a value produced correctly
  and consumed by nothing", with the halves swapped: one consumer was right and the
  other was reading noise, from the same table.

- **`Image.load_from_file` on a `res://` path works from source and ships nothing.**
  An export packs the *imported* `.ctex`, not the `.png` the importer consumed, so
  every texture in the map comes back null in an exported build — which for this game
  is the browser client, the one target that cannot be debugged by looking at it. Godot
  says so, in a warning that scrolls past with one per texture. `load()` is correct in
  both. This is Decision 8's shape again: a development path and a shipped path that
  are not the same path.

- **VTF mip levels are stored smallest-first**, so mip 0 — the full-size image — is at
  the *end* of the run. Walking forward and stopping at the first mip is the obvious
  reading and yields a 1x1 texture stretched over a wall.

- **Ignoring displacements deletes the terrain and nothing says so.** A displacement's
  face is the flat quad the mapper drew; the real surface is a grid of offsets from it.
  `Surf_Mesa` has 1434 of them, including ramps players ride, and drawing the quads
  instead produces a map that is complete, plausible and missing every rock face.

- **You cannot tell "the lightmap is unlit" from "the albedo is black" by looking**,
  and `surf_kitsune` is 5892 triangles of `tools/toolsblack`. There is no camera angle
  that separates them, because both render black through a multiply. `bsp_preview`'s
  `lm` mode overrides every material to show the baked lighting alone, which is the
  only thing that answers it. The family's "an interface is invisible to assertions",
  reached through a shader.

- **A script error inside a test aborts THAT TEST and not the run — again.** A call to
  `DotTimerZoneSet.all()`, which does not exist, removed a check while the suite
  printed **19 passed, 0 failed**. `headless_imported` asserts its own check count for
  that reason, which is the guard this tree already knew it needed.

- **One `ALPHA = base.a;` drew every imported map through itself, for as long as there have been imported maps.** Godot decides a spatial shader is transparent by whether it *writes* `ALPHA`, not by what it writes — so an unconditional write at the bottom of `fragment()` moved all 420 surfaces of all eight maps into the alpha pass, where depth is not written and geometry is sorted per surface instead of per pixel. What that looks like is not "the map is see-through": it is `surf_mesa`'s grey concrete floor reading as brown sand, because the terrain *behind* the floor was drawing in front of it, and half the map reading as black holes where a distant unlit surface won the sort. Every value involved was correct — the texture decoded, the UVs were right, the material was configured — and the only thing that could ever have found it is a person looking at a picture beside the original. `g2g_bsp_translucent.gdshader` is the ALPHA write now, on the 20 surfaces out of 420 whose own VMT said `$translucent` or `$alphatest`. The manifest had carried that flag since the importer learned to read a VMT and **nothing had ever read it**: this tree's own "a value produced correctly and consumed by nothing", for the fourth time, and the consumer that was missing is the one that would have made the write conditional.

- **Dividing a lightmap by 255 reads as a conversion and is not one.** `c * 2**e` is already the linear value Source's own `TexLightToLinear` returns; 255 is the range of the *mantissa byte*, not of anything the number means. Over `Surf_Mesa`'s 1.9 million luxels the median linear value is **8.1** and the 99th percentile is **398** — so the divide put the median luxel at 0.03 and the map came out about three times too dark, with every surface the sun did not reach directly reading as a hole rather than as a shadow. No fixed divisor could have worked: p10 to p99 is a factor of five hundred and any linear scale that keeps the top from clipping crushes the middle to black. `lightmap_key` exposes each map against its own median instead, through a Reinhard curve that never clips — so a map exposes itself, which is what "a map is content" has to mean when the content is somebody else's compile.

- **A texture that is flat black is a texture that is missing, and it decoded perfectly.** `tools/toolsblack` is 1024x1024 pixels of zero; so is `cs_italy/black`, and between them they cover **5.9 billion square units** of the eight maps. Drawn faithfully, that is indistinguishable from a load failure to anybody playing. They go to the prototype set now, by the same route as a texture that was never in the file, because "no texture" is what both of them are. The rule is flat **and** dark, not either: `grids/grid_white` is a black panel with one bright line — mean 12, deviation 30 — and it is most of what `surf_kitsune` is made of, so a rule keyed on darkness alone would repaint that whole map over a property it has on purpose.

- **Kenney's prototype set was installed, loaded, scaled correctly, drawn on every surface it should have been, and invisible.** The report was "I still don't see any usage of kenney prototype textures", and the set was on screen the whole time. Its tile is a flat field with a ONE pixel line on a 128 pixel square: **1.4% to 3.5% of the image is anything but the field colour**, against 52% for `grid_texture`, which draws a three pixel line and darkens alternate squares. Ink is the only thing that survives a mipmap — every texture converges to its own average with distance — so a tile that is 97% one colour *is* that colour a few metres out, and on a ramp seen edge-on, which is the angle a surfer spends the whole map at, it is that colour everywhere. Two whole maps rendering in flat orange and flat grey, correctly.

  `grid_texture`'s own comment had already worked this out and written it down — "a pure grid on a ramp seen edge-on collapses to nothing between the lines; the checker is what still carries speed at a glancing angle". The generated grid has a checker. The installed set did not, and nothing compared them, because **both are correct images and the difference only exists once one of them is on a ramp forty metres away**. The checker is composited onto Kenney's own pixels at load now, once per role: every pixel of theirs survives, the palette that tells a ramp from a wall is untouched, and the only thing that changes is the part a mipmap keeps.

- **And the constant beside it is 8, was doubted, and is right.** Measuring the tile to check gave four — lines on rows 0, 256, 512, 768 and 1023 of 1024 — and four is wrong. The lines alternate STRONG and FAINT: every 256 pixels they are 97 luma steps above the field and every 128 they are ten, so a threshold chosen to ignore block-compression noise ignores half the grid with it. The wrong answer was plausible, arithmetically tidy, and would have drawn every imported map at half scale on the one number that constant exists to hold still. Written down because the measurement is the part that was hard, not the number.

- **`tools/bsp_preview.sh`'s `ambient` and `light_boost` overrides had never changed a pixel.** The comment above them said to assign before `add_child`, because `_build()` runs from `_ready()`. It does not: `build_from` builds there and then, so every material already existed by the time either line ran and the assignment reached nothing. Two renders at different exposures came out **byte-identical**, which is the only reason it was noticed. The one tool in this repository whose entire job is to let a person look at the thing no assertion can see was silently ignoring half of what it was asked to show.

- **Every spawn on a map is a place a player can be put, and exactly one of them was ever checked.** `headless_imported` asserts the MAIN spawn is somewhere a player can stand. `tools/spawn_check.gd` asks it of all of them — the per-track spawns and every zone destination a teleport can land on — and finds **36 points inside solid geometry across five maps**: 18 of 83 on `surf_beginner2`, 9 of 77 on `surf_summit`, 5 of 70 on `surf_aquaflow` including its **main spawn**, 4 of 174 on `surf_kitsune`, and none on `surf_mesa`. A player put inside a brush is stuck there until they find the respawn key, and the map is perfect from every other angle — which is how this arrived, as "I get stuck when I spawn".

  **An overlap test alone proves nothing, and two probes were built on one before this was noticed.** Shapes have collision margins, so a capsule resting a millimetre above a floor overlaps it: "is the player in solid" answers yes for everybody standing anywhere, and a bhop probe built on it reported 70% to 75% of runs broken and **did not move when the motor was changed**. What separates a real bad spawn from a margin is how far up it takes to get clear — `surf_aquaflow`'s main spawn is clear only 64 units up, against a 72-unit player, and that number is not a margin.

  `floor_of` is one cause and is fixed: it returned `box[0][2]`, the bottom of the trigger VOLUME, and a mapper sinks a trigger into the ground on purpose so nobody can walk under its edge. It is not the only cause — a `destination` is wherever the mapper put an entity — so the lift is applied to every route rather than to that one.

  **And the lift cannot see displacements, which is where `surf_aquaflow`'s spawn actually is.** A brush is half-spaces and a point test against it is exact; a displacement is welded triangles with no inside. So `lift_out_of_solid` looks at a spawn buried in the reef and correctly reports it clear, and the 36 stand. The answer is almost certainly not in the importer at all: the game has a physics world, and one shape query per spawn at map load settles brushes and terrain alike in the one place that knows about both.

### What importing the other six found

The importer had been run on two maps. Running it on the eight in
`godot/inspirations/g2gfast/` — and then asking whether each one could be *finished*
rather than merely loaded — found five more, and four of them were in the two maps that
had already been imported and passing.

- **A brush model's bounds are relative to the entity's `origin` key, and the importer
  ignored it.** vbsp moves a brush entity's geometry so its origin sits at (0,0,0) and
  records where that was; only worldspawn, whose origin is the world's, is the same
  either way. So **every pit volume in both imported maps was drawn piled around the
  centre of the map**, where no player goes. Nothing errored and nothing could: a
  RESPAWN volume that is never entered is indistinguishable from one nobody has fallen
  into yet, and the suite's zone section counted them and measured their thickness
  without ever asking where they were. Confirmed against the faces rather than reasoned
  about — for every trigger in `surf_kitsune` the model's own vertices span exactly the
  model's bounds, and the origin is the offset to where the mapper drew it.

- **Three of the eight maps have LZMA-compressed lumps and nothing in the header says
  so.** `bspzip -repack -compress` is what every map host runs, because a 112 MB `.bsp`
  is a 112 MB download for every player who joins; it rewrites each lump as a
  `lzma_header_t` plus a raw LZMA1 stream and leaves the file's VBSP version at 20. The
  reader read the compressed bytes as structures, got a plausible plane array out of
  them, and died in the texture string table — which is simply the first lump whose
  contents are checked against anything. `surf_aquaflow`, `surf_arcade` and
  `surf_interference` could not be imported at all, and the failure named the wrong lump.

- **A spawn yaw was never converted.** Positions crossed the axis boundary and the
  angle beside them did not. Source measures yaw about +Z from +X and `DotFpsMotor`
  builds forward as `(-sin y, 0, -cos y)`; solving the two against each other gives
  `yaw - 90`, and the manifest was writing Source's number straight through. **No number
  is wrong when this is wrong** — the player stands in exactly the right place facing
  the wrong way, which on a map with an obvious route reads as the spawn being fine.

- **A spawn 8 units above the floor is a coin toss.** `Surf_Mesa`'s spawn destination
  sits 25 units over its platform. Dropped from 10168 the player lands; from 10170 the
  player lands; from **10169**, which is where an 8-unit lift put them, the player goes
  through the floor and keeps going — and moving them one unit in x, or 320 units in y,
  fixes it. One point, on one map, and it was the point the map shipped with. A capsule
  that starts that close to a triangle seam is a coin toss whichever way the collision
  backend rounds, so the answer is not to start there: the lift is 24 units, which is
  clear of the seam and still leaves a 94.5-unit player 9 units of headroom under
  Source's own minimum 128-unit ceiling. **The `--check-only` pass and every assertion
  about the zone set passed throughout**; what found it was the one check that puts a
  player on the map and waits.

- **Two brushes sharing a targetname are ONE entity in Source, and mappers use that.**
  `surf_summit`'s `tm_checkpoint1` is a pair, one in each of the map's two mirrored
  lanes. Emitted as two zones they are two stage zones with the same number, which
  `DotTimerZoneSet.problems()` refuses — correctly — so the map went from "no timer at
  all" to "no timer, and now it says why". They are unioned back into the one volume the
  map always meant.

And one in the suite, which is worth the same: **`headless_imported` had four zone
checks and not one of them asked whether a run could be finished.** A zone set with a
start, a finish, stages numbered 1..n and no thin volumes passes every one of them and
can still be impossible to complete. `_test_runnable` drives a `DotTimer` over the map's
own zones — start, away, each stage, finish — and asserts a time comes out with every
split in it; `_test_stands_where_it_sends_you` teleports a player to each track's spawn
and each `!s<n>` destination and waits to see whether they are still there. Those two
are what say these are levels rather than geometry, and writing them found the
`Surf_Mesa` spawn above and two more artefacts of stepping a timer by hand.

### Decision 13: a map says how it is lit, and that was being thrown away

Every one of these `.bsp` files carries its own lighting in the entity lump, and the importer read the geometry, the collision, the zones, the spawns and the baked lightmap and left all of it there. `light_environment` has the sun's pitch, yaw, colour and compiled brightness and a separate ambient colour; `env_fog_controller` has the fog's colour and range; `worldspawn` names the sky; `sky_camera` describes the 3D skybox. So every imported map was drawn under one hardcoded sun at (-55, -35) against one flat blue-grey background — `Surf_Mesa`, which asks for a low warm sun at -28 degrees in 235/222/177 with pale cyan fog from 5000 units, and `surf_beginner2`, which asks for one straight overhead in 255/211/168 with no fog at all, **came out looking like the same room**.

`lighting_of` writes it into the manifest and **dot-lighting** applies it — `DotLightDocument.from_dictionary` over the block, `DotLightRig.apply` over the world. [G2GLighting] is forty lines of caller now, and the one decision it keeps is which `DotLightProfile` a machine gets: `web()` in a browser, which drops shadows and keeps glow. That is doubly right here — a surf map is a large open volume, so the shadow pass costs the whole canyon, while the glow is what makes a neon strip read as a light, and a neon strip is how one of these maps signposts the route. Four things about that are worth keeping:

- **The sun lights the characters and not the world, and that is correct.** An imported map's surfaces are `unshaded` because the baked lightmap *is* their lighting. What changes how the world looks is the post-processing — the tone map, the fog, the glow and the colour behind everything — and those four are most of the difference between this and the engine these maps were built for.
- **The tone map is the largest single change and it costs nothing.** Godot defaults to `LINEAR`, which is not a tone map, it is a clip. The engine these came from ran a filmic curve, and the shoulder on it is why a bright sky and a dark rock face can both be readable in one frame.
- **The glow threshold is under 1.0 on purpose.** The lightmap atlas is an 8-bit sRGB PNG tone-mapped at import, so nothing in an imported map is ever above white; an HDR threshold would find nothing to bloom, on any map, for ever. The neon strips a surf map is signposted with sit near the top of that range, and this is what lets them read as light rather than as paint.
- **`_light`'s fourth number is not a multiplier on the first three.** It is the intensity the map's own compiler was given and it runs from 20 to 600 across these eight maps, so feeding it to `light_energy` gives a sun six hundred times too bright on one map and twenty times on the next. It is a ratio against a reference, soft-curved, because the range is two orders of magnitude.

**Calibrated against a reference frame — see Decision 14.** What follows was written before that and is kept because both cases are still real. `surf_aquaflow`'s fog is cyan at full density by 8536 units, which is exactly what the map says and makes an orbit preview one flat teal rectangle — correct, and a reminder that a preview outside the map is not a view a player has. And that map is 98% prototype-textured, where PLATFORM is Kenney's *Light* tile at a mean of 213, so a filmic curve over a map made almost entirely of near-white tiles is a white-out. Neither is the lighting being wrong; both are the lighting being applied faithfully to something else that needs a pass.

### Decision 14: the lighting was being flattened three times before it reached the screen

Decision 13 read a map's lighting and applied it. It still looked nothing like the engine these maps were built for, and the reason turned out to be measurable rather than a matter of taste. A reference frame of one of these maps as its own engine draws it spans a **linear luminance ratio of 303:1** between its fifth-percentile pixel and its ninety-fifth. The same view of our import spanned **7.9:1**. That single number is the whole of "why does theirs look so much better": a cave lit by one warm lamp was coming out as an evenly grey room, and no amount of correct geometry, correct textures or correct sun angle was going to change it.

Three things were compressing it, and only the third was interesting.

**The atlas encode was a tone map, and a tone map has no business there.** `build_lightmap` wrote Reinhard, `v / (v + median)`. Reinhard is a *display* operator: it takes a finished image to a displayable range. This atlas is not a finished image, it is a light term that still has to be multiplied by an albedo — and Reinhard compresses ratios everywhere, including the midtones where everything readable in a map lives. It is now expose, clip, gamma: divide by a white point, clip the top, write through 2.2. Every ratio below the clip survives exactly, because **gamma encoding is already the compression an 8-bit image needs** and a 500:1 linear range is what sRGB was designed to carry. Atlas contrast went from 3.5:1 to 226:1.

**The white point has to be a statistic an outlier cannot move.** Dividing by the 99th-percentile luxel is the obvious reading of "use the range" and it hands a whole map's exposure to its brightest few luxels: `Surf_Mesa` exposed perfectly and `surf_beginner2` — dim, with a handful of bright sources — went almost black. Anchored on the **median** instead, every map in the set lands in the same midtone and clips between 0% and 3.4%. That percentage is printed per map at import now, because it is the one number that says whether a map's exposure is sane.

**And two thirds of the map's triangles were reading their lighting from the wrong place.** A displacement is a flat quad plus a grid of offsets, and its lightmap is parameterised over **the quad**, not over the terrain that came out — the luxel extents say so plainly, being 12x12 or 7x12 where the displacement grid is always 9x9. The importer projected the *displaced* point through the face's lightmap axes, which overshoots the luxel range by however far the terrain bulges, and the clamp then parks whole hillsides on one edge luxel. Displacements are 67% of `Surf_Mesa`. They rendered as smooth bright gradients with no shadow anywhere, which is indistinguishable from a map that is simply lit flatly — and every check passed, because the atlas was right, the UVs were in range and the geometry was in the right place. Projecting the flat point moved the rendered median from 191 to 49 against an atlas median of 47. **The tell was that mismatch: a lightmap that renders nothing like its own histogram is being sampled somewhere other than where it was written.**

End to end, the same view went from 7.9:1 to **87:1**, with the median at 31 against the reference's 15.

**The tool that was supposed to catch all of this was lying.** `tools/bsp_preview.gd` builds its own neutral `WorldEnvironment` so a diagnostic render shows the map and nothing else — and added it beside the one the map now brings. A second `WorldEnvironment` does not merge and does not warn at runtime; one is simply used. Every render it had ever made was drawn under the map's own tone map, fog and glow while the code said otherwise. It removes the map's by name now and prints which it used, and takes `keepenv` for the question it could not otherwise answer.

**The sky is drawn from the map's own numbers.** `sky_name` names a texture set that lives inside the game these maps were authored for, is not in the file, and is not ours to copy. dot-lighting builds a procedural sky instead: the fog colour as the horizon, the ambient as the top, the sun at the map's own angle. A flat rectangle in the fog colour — what stood here before — is a blown highlight the moment the world around it is exposed correctly.

### What is not imported

- **Static props.** `Surf_Mesa` carries 17 `.mdl` models in its pakfile and the
  `sprp` game lump places them. Reading MDL/VVD/VTX is a second format family and
  nothing in these two maps' *ride* depends on them — they are scenery. The geometry a
  player touches is all brushes and displacements, and that is all this reads.
- **Skyboxes, water, animated and scrolling materials.** Sky faces are skipped, so an
  imported map has the viewport's background behind it.
- **Anything from the source game's own archives.** A `.bsp` embeds only what the mapper
  added: 84% of `surf_kitsune`'s triangles and 91% of `Surf_Mesa`'s. The rest — the stock
  texture library, which on these maps includes the ramp itself — is drawn in the
  [G2GTextures] prototype set instead, chosen by what the surface is FOR, which is what
  an untextured surface means here.

**These maps are third-party work.** `godot/inspirations/` is read-only reference in
the shape `external-study/` already has: reading a map for its dimensions, its ramp
angles and its stage layout is the point of having it. Shipping extracted geometry in a
released game is a different act and needs the author's permission.

### Maps are dropped in, not listed

There is no list of maps in this repository. `G2GMapCatalogue` scans, and a map is
whatever has a scene and a sidecar, or is just a manifest:

```
maps/<id>.tscn   + maps/<id>.zones.json    hand-written: a scene and a script
<root>/<id>/<id>.json                      imported: data, and nothing else
```

**An imported map has no scene and no script, and that is what makes it droppable.**
Every one of them is `maps/imported_map.tscn` — one scene, inside the build — pointed
at a different manifest through `DotMapDef.meta`. The obvious alternative, a generated
`<id>.gd` and `<id>.tscn` beside the data, was what this shipped first and it cannot
work for a map that arrives *after* the export: `res://` is a read-only PCK in a built
game, so a scene that is not in it does not exist. A script in a delivered dot-cloud
pack could not resolve `extends G2GBspMap` either — this family measured that and wrote
it down — so the same change fixes both.

The roots searched are `res://maps/imported` (baked into an export), `user://maps`
(where anything downloaded at runtime lands, and **the only way a shipped server can be
given a new map**), and whatever `g2g_maps_directory` names. First root wins, so a map
in the build is not silently replaced by one dropped in beside it.

```bash
cp somewhere/surf_whatever.bsp ../inspirations/g2gfast/
tools/import_maps.sh            # imports what is new, skips what is current
tools/import_maps.sh --prune    # and deletes imports whose .bsp is gone
tools/bsp_preview.sh            # and renders every one of them from its spawn
```

If the import prints `NO START` or `NO END` for the main track, the map labels neither
and needs a `maps/zones/<id>.json`. It is still offered — a map you can walk around is
worth having — but nothing will time a run on it.

and on a running server, `g2g_maps_reload` rescans without a restart.

**The rescan mutates the catalogue in place rather than replacing it.**
[DotMapRotation] holds the catalogue by reference and reads its pool live, so swapping
the object leaves the rotation offering exactly the maps that are no longer there.

**The map being played is deliberately not unloaded when it disappears from disk.** Its
scene is resident, the players on it are mid-run, and taking the world out from under
them to enforce a directory listing is worse than letting it finish and never be chosen
again. `g2g_maps_reload` says so in its reply.

This replaced **three** hardcoded copies of the same three map ids —
`G2GGame._map_catalogue`, `tools/export_zones.gd`, and the ad-hoc lists in the export
scripts. That is this tree's most repeated bug and it had reached this repository too.

**Verified by dropping one in**: a map copied into `user://maps/`, never in the build,
with no script, no scene and no `.import` files, loads and plays and renders
identically to the same map under `res://`.

### What making it dynamic found

- **A client could not be configured at all.** `G2GClient` built a bare `G2GConfig` and
  never called `load_layered()`, so the family's `defaults < JSON < env < argv` chain —
  which this file's Decision 1 is about — ran on the server, in every suite, and nowhere
  on the client. `--g2g-initial-map surf_kitsune` reached a dedicated server and went
  nowhere offline, which always played whatever the export defaulted to. It is the
  family's own convention missing from exactly one file, and no test could see it
  because every suite sets `config.initial_map` directly, which is the path that works.

- **Every imported pit volume was thin enough to fall through.** Source *sweeps* its
  trigger tests; `DotTimerZoneIndex` asks `contains(point)` once a tick. A mapper draws
  a `trigger_teleport` as a 16-unit plane because in Source that is enough — and at
  3500 u/s and 128 Hz a player travels 27 units between samples, so a falling surfer
  steps clean over the pit and falls for ever. **48 of surf_kitsune's 53 respawn volumes
  and 7 of Surf_Mesa's 10** were that thin. The importer now inflates a thin volume into
  a slab centred on the original plane — centred, because downward is right for a pit
  and wrong for a boundary trigger above the play space, and a centred slab is the
  honest approximation of the swept test Source was doing.

  This is the same failure this file already records twice: *the thing dot-timer's
  RESPAWN zones exist to prevent was the thing that did not happen*, and it announced
  itself as one warning line during an ordinary run. `headless_imported` now asserts
  `thin_zones()` is empty, which is the check `headless_run` has always made for the
  hand-written maps and nobody had extended to the imported ones.

## The detector, turned on this game's own new code

The family's rule is that **an exported setting whose name occurs exactly once in its
repository is a setting nothing reads**. The same grep over *methods* is worth as much
and had never been run: a public method whose name occurs once is a method nothing
calls. Turned on the twenty-six-addon pass it found seven, and the first is the one
that matters:

- **`G2GCombat.set_fire_command`, which meant `sv_deathmatch` was a mode nobody could
  shoot in.** The arsenals were built, the hitboxes were registered, the match was
  counting, and the fire command every tick read was one nothing ever set. The fix is a
  bit on `G2GNetCommand` rather than a request, and the reason is prediction: a shot
  happens on a tick and has to be replayed with the movement of that tick, so a trigger
  arriving reliably-and-separately would be replayed against a different tick's
  position every time. It is applied in `_net_apply_input`, which is the one place that
  runs on a replay as well as on a fresh tick — and **not retained across a lost
  packet**, unlike the movement: a held trigger that survives a hiccup is a weapon that
  empties itself during one.
- **`G2GArsenal.weapon_table`, which meant `DotLoadoutManager` was a manager of
  nothing.** It was built, given a schema and a store, and asked for nothing; everybody
  got a hard-coded knife and deagle. dot-loadout has never heard of a `DotWeapon` and
  dot-combat has never heard of a `DotItem`, and the table between them is the whole
  join.
- **`G2GClientExtras.receive_line`.** The client's `DotChatClient` was a history nothing
  fed. `G2GServices` routes a line through dot-chat and hands it to dot-server's manager
  to put on the wire, so on the client it arrives on `DotClientLink.chat_received` — not
  on anything dot-chat owns.
- **`G2GIdentity.avatar_for`.** dot-platform's module runs off `client_state_changed`
  because dot-server has no cancellable stage between authentication and content, so a
  player can be in the world with the platform still resolving them. The module's own
  `_avatar_for` now falls through to the hub, which falls through to the stock document.
- **`G2GProps.phys_gun`, `G2GHunters.spawn_one`, `G2GStats.finish_rate_of`** — a tool,
  an admin spawn and a derived figure, each reachable from nothing. `g2g_nudge`,
  `g2g_hunt spawn` and `!stats` are the doors.

Two things the new checks found that were not on the list:

- **A grab is once and a held prop moves every tick.** A layer that only called `grab`
  gives an admin a block that stays exactly where it was picked up, which reads as the
  physics gun not working rather than as a missing `hold`.
- **A GDScript lambda captures locals by value.** The shot counter was an `int`
  incremented inside a signal handler, so it stayed zero outside it — and the assertion
  reported a failure for a signal that had fired perfectly. This file's own family notes
  carry that warning, and the check was written wrong anyway.

## The characters are Kenney's, scaled to the genre's hull

`avatars/{body,head}_kenney_<a..r>.tscn` are 18 characters from Kenney's Blocky
Characters (CC0), generated by `tools/build_avatar_parts.gd` out of `avatars/kenney/`.
The two primitives that came first stay at the FRONT of `BODIES` and `HEADS`: `[0]` is
the schema's default, so a deployment without the art directory still resolves a default
part and an avatar document written before the art arrived still loads. A capsule is a
worse character and a better fallback.

**The scale is the whole job, and this game is the awkward one.** A Kenney character is
2.70 m; this game's player is 72 genre units, which is **1.372 m** — so an imported
character is very nearly TWICE the size of the thing it represents, standing with its
head above the camera, with every property of every node correct. The generator measures
the kit and derives the factor (0.508 here) rather than carrying a constant, because
game-arena runs the same kit against a 1.8 m capsule and gets 0.667: one number, written
down twice, would be this file's most repeated bug in a new place.

`G2GRig` mounts the body at 42% of the hull and the stock capsule is centred there, which
floats it about 13 cm — invisible on a capsule and a character standing in mid-air the
moment the part has legs. The body is foot-aligned; the head stays centred. **The rig is
not changed for this**, because arena mounts the same way and its parts are still
primitives: the art fits the rig.

`tools/avatar_preview.tscn` draws the parts inside a wireframe of the hull they have to
fit. Every one of those three was found by looking at a frame — "is this the right size"
is not a question an eyeball on a character alone can answer, and it is the same lesson
as the 0 x 0 `Control`s.

## Spectating, and effects with a rule

### `!spec`, which this game shipped without

**On a timer server, spectating is the point rather than a consolation for being dead.**
A record is set by one person, once, and everybody else on the server wants to watch it
being set — `!spec ada` is a command bhop and surf servers have had for fifteen years.

Two settings follow from that and both are the opposite of an arena's:

- **`force_camera` is 0.** There are no sides on a timer server, so restricting the
  camera to "your own team" restricts it to everybody and means nothing. It tightens to
  1 the moment `sv_deathmatch` is on, where a living player watching a living one is a
  free wallhack.
- **`allow_while_alive` is on.** Somebody standing in the start zone deciding whether to
  run is not dead, and refusing them the camera is a rule from a game this is not.

`!spec` with no argument watches whoever is **furthest into a run** — furthest rather
than fastest, because "who is nearly finished" is the question a spectator is asking and
somebody two seconds into a personal best is not the answer. The camera is driven once a
**frame**, for the reason `jitter_probe.tscn` exists.

### A movement effect is a style, and a style you did not choose is a record you did not set

This is the whole design of `G2GEffects` and the reason it is not four lines.

Everything in this game exists to make a run comparable with one somebody else set, on
another server, at another tick rate: sub-tick zone crossings, a rate taken from
`sv_tickrate` rather than an export, styles paired between dot-player-controller and
dot-timer by id. **An effect that quietly multiplies `max_speed` by 0.65 undoes all of
it**, and the player has no way of knowing it happened.

So effects here are split, and the split is enforced rather than documented:

| | |
| --- | --- |
| **Combat effects** — a bleed, a burn | Anybody, any time. They cannot change a time. |
| **Movement effects** — a maul, a haste | **Refused** while a ranked run is live. |

`G2GEffects.is_movement()` asks the *definition* whether it changes `move_speed_scale` or
`jump_scale`, rather than consulting a list of ids — so an effect added later is
classified by what it does rather than by somebody remembering to name it.

A server that wants hunted runs to count anyway sets `allow_movement_during_runs`, and
every such run is **tainted**. `DotTimerRun.tainted` has existed since dot-timer was
written and this is its first caller; it is what keeps a hunted run off a board beside a
clean one, which is the honest version of allowing it.

That is also what makes the hunters interesting rather than annoying: being chased has to
cost you something, and the thing it costs you is the record.

### Two id spaces meet at `entity_for`

This game keys players by `StringName`; dot-combat and dot-effects both key by `int`.
`G2GCombat.entity_for` is the direction that was missing — `player_id_for` had existed
since the class was written and nothing went the other way. A caller that hashed the name
instead would get a number that is stable, plausible, and **not** the one the health, the
hitboxes and the kill feed use.

Both directions are `DotEntityTable`'s now. `entity_for` is `id_for_key`, `player_id_for`
is `key_for_id` — which also stopped it walking every kit comparing ints on a call that
runs once per kill, once per respawn and once per hunter swipe. The paragraph above is
kept because the reasoning is what produced the addon: the comment that sat on
`player_id_for` is, word for word, what `DotEntityTable` exists to make unnecessary.

## `!spec` did nothing, and `g2g_map` deliberately still does

Two halves of the same gate, and they point opposite ways.

`G2GServices` hooks `player_command` as well as `player_chat`. Without it,
`DotChatRouter.command_entered` **could not fire**: dot-server's chat manager checks for
a command prefix before it fires `player_chat`, `_handle_command` returns on every path
including the unknown one, and its prefixes are `["!", "/"]` — identical to
`DotChatRules`'. So no `!` line ever reached the router.

`!rtv` survived that because `rtv` is also a console alias registered `.with_chat()`.
**`!spec` and `!spectate` are handled nowhere else and did nothing at all** — and the
module's own `_` branch said "left for dot-server's own chat commands", which was true
for `!r`, `!wr` and `!top` and quietly false for the two this game added later.

**`g2g_map` is the only command in its block without `.with_chat()`, and it is reachable from chat anyway.** It carries `CHANGEMAP` instead, and the flag is what answers — `examples/dedicated.gd` asserts that now, where it used to assert `not map_command.chat_allowed`.

The old assertion was written on sound reasoning — a map change destroys every run in progress, so a records server does not let a player do that by typing — and it was enforcing that reasoning in the wrong place. The chat check ran before the permission check and never asked who was typing, so the person it actually stopped was the operator holding `changemap`, typing `/map surf_beginner` into the chat box already in front of them. A player without the flag is refused either way, by the check that was always doing the work. `sv_chat_commands 0` puts the old behaviour back server-wide, and `allow_chat_change = false` on the dot-map block puts it back for the map change alone.

The episode is still worth the paragraph it takes: **a missing flag its neighbours have is evidence of nothing until you have checked whether a suite asserts the difference.** That assertion caught the flag being added once and sent the suite to 120/1 on the spot. What it could not tell anybody is whether the difference it was defending was the right one.

## The presentation layer, and the sentence every decision in it comes from

`G2GPresentation` holds dot-settings, dot-audio, dot-fx and dot-console, and every choice
in it is downstream of this project's own rule: **a player who came to run must not be
stopped by anything added for a player who came to do something else.**

- **Camera shake defaults to zero here and to one in every other game in the family.** A
  surf ramp is a precision input at 20 m/s; shaking the camera for a landing is not
  atmosphere, it is taking the run away. It is still a *setting*, because the same server
  runs a deathmatch layer and somebody in it may want one.
- **Full-screen flashes default to off**, same reason, same switch.
- **The effect budget is 24**, which is small on purpose. A frame here is a tick and a tick
  is 7.8 ms of somebody's time, and nothing drawn is allowed to cost one. That is safe
  because an effect never changes the simulation — which is the property that makes the
  whole addon shippable on a timer server.

The one thing audio genuinely adds is **the landing**. A bunny-hop is a rhythm, and a
rhythm you can only see is one you have to watch your feet for — so the landing is pitched
by the speed you landed at, which is the cheapest speedometer there is. It is **watched
rather than listened for**, for the reason game-hungario watches its own eating: a landing
fires on the authority, which on a netted client is somewhere else, so a client that hooked
a signal would be silent online and perfectly noisy offline.

**And that landing made no sound at all until now.** The catalogue named seven `.ogg` files nobody has produced, so the speedometer above was arithmetic reaching a path that does not exist — a decision made carefully and then inaudible. `sound_recipes()` maps each of the seven to a `DotAudioSynth` voice and `DotAudioSinkGodot` falls through to that bank when the path resolves to nothing, so the rhythm is audible without this repository shipping a byte of audio. The same restraint as the camera shake applies to the choice of voices: `land` is an impact rather than a thud with a body, because a long tail smears the rhythm it is there to mark. `tools/audio_probe.sh` is the only thing here that can tell "this game would make a noise" apart from "this game has a table of sounds" — a headless run has no audio device, so every assertion about audio in `headless_presentation` passes on a silent build.

**The server's console is bridged in with a prefix here and unprefixed everywhere else.**
The two consoles share names that mean opposite things — `!s3` on a client is a local
navigation and on a server is a teleport that ends a run — and an unprefixed remote console
is how somebody types something meant for their own client and loses the run they were
three stages into.

## The chat box, and a run nobody may lose to a keystroke

This game could be talked to and could not talk back: `DotChatClient` held the history, the HUD drew the notice, and no key opened anything to type in. It is dot-ui's `DotChatWindow` now, built by `G2GPresentation` beside the console, in the bottom-left corner — which is free here because the clock and the key display are along the bottom centre and the status line is along the top.

Three settings decide it, all `ACCOUNT`-scoped for the reason the sensitivity is: a runner who found their key once should never have to find it again.

| | |
| --- | --- |
| `chat_window` | `auto` / `on` / `off`. `auto` hides the box on a server already carrying chat somewhere the player can see it; `on` draws it regardless, which is how a relayed server and an in-game box run at once; `off` never does. |
| `chat_open_key` | `Y` by default. |
| `chat_team_key` | `U` by default. |

The log keeps drawing what other people said in all three cases. Off means "you type somewhere else", never "you are out of the conversation".

**`G2GPresentation.swallows_input()` covers the box, and `DotFpsSampler.suspended` is set beside it — and on a timer server the second one is the expensive half.** `swallows_input` keeps typed keys out of `_unhandled_input`; it can do nothing about `Input.is_action_pressed`, which is polled off the device every physics frame and does not care what consumed an event. A client that keeps reading movement while somebody types does not merely walk them into a wall here, it strafes them off a ramp and ends a run they have been building for minutes. **Nobody may lose a personal best by saying "gg".**

`auto` is answered by the server, because only the server can answer it: `G2GServices` points `DotChatManager.watch_relay` at the relay it built, and `G2GClientExtras` turns the payload that arrives into `chat_relay_changed`.

**And every line this game drew was blank until dot-chat was fixed.** `receive_wire` handed dot-server's `{kind, userid, name, text, admin}` to `DotChatClient.receive` expecting a refusal; `DotChatMessage.from_dictionary` defaulted every field, so it parsed as a valid message with no text and no sender, and the fallback underneath — the one that actually draws chat here — had been unreachable since it was written.

## A practice session taints every run in it

`G2GParty` is the sharpest disagreement the five games have about one addon.

A peer-to-peer host is a player's own machine, and it holds the tick rate, the zone
crossings, the sub-tick fractions and the map — which between them **are** a time. A host
who wanted to could file a world record by editing a number, and nothing on the receiving
end could tell.

So a run made in a peer-to-peer session is **tainted the moment it starts**, using
`DotTimerRun.tainted` — the field dot-timer has had since it was written, whose first
caller was this game's own effects layer, for the same sentence one level over: *a style
you did not choose is a record you did not set*, and a host you cannot vouch for is that
sentence about the machine instead of about the movement.

**Tainted rather than refused, and at the start rather than at the end.** A run you cannot
compare is still a run worth doing — practising a map with a friend on a machine neither of
you pays for is exactly what peer-to-peer is good at — and a run tainted on *finishing* is
one a player made believing it counted.

Migration is off: a time made of two machines' clocks is worse than no time at all.

## Three imported maps are not courses, and the suite used to say that was a failure

`maps/zones/README.md` has said since it was written that three of the eighteen imported maps have no finish and that **none of them is a mistake**: `buses_from_hell_fixed` is a vehicle map with no route to time, and `bhop_eazy` and `bhop_lego2` are section-chain maps whose sections are all labelled and whose END is not — nothing in either file distinguishes the last gate from the twenty-six before it. Guessing a finish would produce a leaderboard that looks right and measures a route the map does not have.

`headless_imported` asserted the opposite for every map it found, so it had been **exiting 1 on three maps behaving exactly as documented**. The check and the decision contradicted each other for as long as both existed, and the check was the one that was wrong. A suite that is red for a reason nobody intends to fix is a suite people stop reading, and it takes the real failures with it.

**The exemption is asserted in both directions, which is what stops it being a mute button.** `NOT_COURSES` maps are checked for *not* having a runnable main track: if one grows a finish, the list has gone stale and the failure is how anybody finds out. `NO_PIT` is a separate list of one for the same reason at a smaller scale — `bhop_eazy` and `bhop_lego2` do have pits and are still checked for them, and folding the two lists together would stop asking two maps a question they currently answer correctly. Armed by listing a real course in `NOT_COURSES`; it fails with both checks naming the list.

## One imported map lost 55 surfaces, and it was the renderer rather than the importer

`bhop_monster_jam` has **311 surfaces** and Godot's per-mesh limit is 256 (`RenderingServer.MAX_MESH_SURFACES`), so while `G2GBspMap` built one mesh the last 55 never reached it — `Condition "surfaces.size() == RenderingServerEnums::MAX_MESH_SURFACES" is true`, 55 times, at every load. It is the only one of the eighteen over the cap; the next largest is `bhop_mario_fxd` at 153.

**It cost rendering and not play**, because collision is built by `_build_collision` out of the manifest's convex-per-brush block rather than out of the drawn geometry — which is also why every collision and stands-on-it check passed on that map throughout.

`G2GBspMap` now starts a new `MeshInstance3D` every 256 surfaces. The first keeps the name `World`, which the suite and the probes look up; the rest are `World2`, `World3`. Each drawn surface also carries the index of the manifest surface it came from, because the materials used to be assigned by position in a second loop — the same index only while no surface is skipped, and one empty surface would have given every surface after it its neighbour's texture. `headless_imported` asserts that every surface a manifest lists is drawn, which fails on this map with the one-mesh build (256 of 311).

The probes that read `World` alone (`collision_probe`, `surf_probe`, `bhop_probe`) still see only the first 256 surfaces of this one map. They sample, so that is a smaller sample rather than a wrong answer.

## The timer's sounds were reachable from the suite and from nothing else

`G2GPresentation.on_run_started`, `on_split` and `on_run_finished` were written, catalogued with priority 100 because "they ARE the game", tested in `headless_presentation` by calling them directly — and never called by the client. Every run on every build started, split and finished in silence. `follow_runs` listens to the client's own `DotTimerManager` now, which is fed on a netted client too (`G2GGame.tick_timers_only`), so the start sounds on the tick the local prediction crosses the line rather than a round trip later. The personal-best fanfare is `record_accepted`, which only fires where records are filed: offline it plays, and a netted client — which is told a rank, not whether it beat its own time — plays the finish without it rather than guessing. The suite drives the timer's signals rather than the methods now, and a probe of the real offline client heard `timer_start` and `timer_finish` with the fix and neither without it.

## A trigger is one tick's input

`G2GCombat.tick` read the fire command with `get_meta("g2g_fire", null)`. A null default is the engine's *no default*, so every armed player who had not yet sent a command was an engine ERROR with a backtrace, every tick — 1,146 of them in one `dedicated` run, on a suite that reported 0 failed. And the command was never cleared: dot-net skips `_net_apply_input` for a tick whose packet never arrived, so the last trigger was replayed until the next packet — exactly the held trigger surviving a dropped packet that `G2GPlayerNet.last_attack` says does not happen. It is `has_meta` and consumed on read now; `previous` is left alone on a starved tick so a trigger really held across the gap is not read as a fresh press either. Both weapons are semi-automatic today, so the replay had no visible cost yet — it would have had one the day an automatic weapon was added.

## The second batch of imports, and three ways a pit was catching the wrong people

Eight bhop maps from `inspirations/bsp-maps/` were imported on 2026-09-23 — `bhop_badges_mini`, `bhop_evolve`, `bhop_grove`, `bhop_interloper`, `bhop_pandora2_fix`, `bhop_pit`, `bhop_supernova` and `bhop_tesquo_v2` — each with a `maps/zones/<id>.json` that carries an `attribution` block (author, the page it came from, the archive, the date) as well as its zones, because the credit is only ever written down in the archive and on its download page. Two were not imported and are not a gap in the importer: `bhop_zelda_final` is a puzzle map whose route runs through moving doors, keys and a quest counter, which is the map's entity logic and not geometry; and `bhop_grove_backwards` is `bhop_grove` plus a `trigger_look` that punishes facing forward, which is also logic. Without the logic the first cannot be finished and the second is a copy of grove.

Importing them found three faults in how a `trigger_teleport` becomes a RESPAWN zone, and **every one of them was already in maps that had been shipping** — the new maps only made them loud.

- **A filtered teleport is a condition, and it was imported as a pit.** The bhop genre's anti-standing trap is a `trigger_multiple` on each block that renames the player after a delay and renames them back after another, and a teleport on the block that only fires for the first name. This game does not run the map's outputs, so imported unconditionally every one of those fired on every landing: 258 on `bhop_mario_fxd`, 144 on `bhop_badges`, 185 on `bhop_lego2`, 124 on `bhop_arcane_v2`, all imported months ago. `"conditional_teleports": {"filters": [...]}` in a map's file drops them, **opt-in and by name**, because the same mechanism with a name that STAYS set is how a checkpoint pit is built (`bhop_pandora2_fix`'s `fcpN`), and those are real pits. The evidence that tells the two apart is in the entity lump — a trap's name is set and reset by the same trigger, a checkpoint's is set and left — and each file says which it saw. A teleport behind a `filter_activator_class` naming a class no player is (`filter1`..`filter4` on `bhop_tesquo_v2`) never fires in Source either, and that one is dropped automatically: there is nothing to decide.
- **A thickened pit swallowed the floor above it.** `MIN_ZONE_THICKNESS` grows a thin pit into a 192-unit slab centred on the plane, and a bhop map draws its pit a block's height under the blocks — so the slab reached up through them and standing on a block was standing in the pit. `inflate_pit` hangs the slab from the mapper's plane instead when the upper half has a solid top in it (19 of `bhop_aztec`'s 20 pits, 111 of `bhop_monster_jam`'s), and `clear_arrivals` trims any grown slab back off a spawn, stage or door it would contain, which is what fixed `bhop_pandora2_fix`'s stage 4 between two checkpoint planes 136 units apart and `surf_aquaflow`'s stage 2. A pit is also one zone **per brush** now rather than one box around a multi-brush trigger, because dot-timer's zones are boxes and the box around an L covers the elbow.
- **A door ended the run.** `doorways` makes a door a `TELEPORT` precisely so it keeps the run, and `G2GGame._on_effect_requested` handled `TELEPORT` with `G2GPlayer.teleport`, which stops the timer. So `surf_kitsune` — the map `doorways` was written for — could not be timed past its first section, and nothing said so. `teleport(..., keep_run)` is the fix and the handler is its only caller that passes true.

`headless_imported` asks both halves of it on every map now: *no spawn, stage or door lands inside a pit on its own track*, and *a door keeps the run*, driven through the real handler. The first failed on the old imports of `surf_interference` (its main spawn) and `surf_greensway`, and the second on three maps with the fix reverted. Three arrivals are still inside the mapper's OWN trigger rather than inside anything this importer added, and `ARRIVES_IN_PIT` lists them — asserted both ways, like `NOT_COURSES`.

The size check assumed every map is more than 1,000 units along X. `bhop_grove` is one corridor 704 units across and 32,192 long; it asks the longest side now.

## One rock-the-vote, not three

This game had three: the console's `rtv` and `g2g_rtv` went to the map session's own `DotMapTimeLimit`, `!rtv` in chat was claimed by the module and went to the ballot, and a client's `Ask.RTV` went to the map session again. A player who typed `rtv` at the console and one who typed `!rtv` in chat were voting in two different votes. And none of dot-vote's operator commands — `setnextmap`, `nominate_addmap`, `forcertv`, `votereload` — existed here; the module's own `nominate`, `nextmap` and `timeleft` stood in for three of the players' ones.

`G2GVote.install_commands` puts `DotVoteCommands` on the module, `vote` keeping its name so `!vote 2` still works. The chat handler claims `!rtv` and `!vote` only when the vote failed to load, so an unclaimed line reaches the console's — one path. `g2g_rtv` is the ballot's rock-the-vote too, and `G2GNetBridge.rtv_fn` sends a client's request there. Without a vote, `rtv` is registered as the map session's tally, which is then the only rock-the-vote there is.

**The map session's clock no longer ends a map when there is a vote.** It ran beside the vote's at the same length, and on expiry changed to the rotation's next map — so a map the players had voted to *extend* was ended on the old clock anyway. `G2GGame.rotation_ends_maps` is off once the module has a ballot; the session's clock still counts and decides nothing.

**And the HUD's time left is the vote's clock, not the session's (2026-09-24).** The status line drew `game.maps.time_limit`, which on a client is a clock the client started when it loaded the map and nothing the server decides ever reaches — so an extend added ten minutes on the server and none on any screen, and under `trigger: rtv_only` it counted down a limit the server did not have. `G2GVote.advance` keeps a `DotVoteClockView` of what every client believes and emits `clock_due` only when that belief is stale — an extend, a new map, a clock stopped for a ballot — so a quiet map sends nothing; the module puts it on the wire as `G2GEvents.Kind.CLOCK` (last, after VOTE), and a joining peer is told the current one in `_admit` through `G2GNetBridge.clock_fn`. The client's bridge adopts every CLOCK into one `clock_view` the HUD holds and counts down between messages. **No clock at all is drawn when the vote has none** — no "no limit", the slot is gone — and a HUD nothing has told (offline, where the local session is the real clock) keeps the session's. `headless_net`'s **the vote's clock over the link** extends a real `G2GVote` and asserts the client's number moves by the extension, that three quiet seconds send nothing, and that an rtv-only vote with no limit leaves no clock on the HUD; it was armed by making the view never stale on a count, and the extend check fired. `tools/screenshot_hud.sh` has `hud_clock` and `hud_no_clock`. The server's own `describe_lines` "time left" reads the vote's clock too since the same day — see below — and a client shell exported before `DotVoteClockView` existed cannot load this client — the shell needs a rebuild before this game's pack is published.

**`g2g_status` says the vote's time left, and "no limit" when the vote has none (2026-09-24).** `G2GGame.describe_lines` read `maps.time_limit` after the vote had taken the map's end over, so an operator asking how long was left was told a limit an extend had already moved — the HUD's bug, one screen over. The game does not know the vote exists, so the module hands it `G2GGame.clock_fn = vote.clock_state` beside `rotation_ends_maps = false`, and `time_left_text()` reads that: `m:ss`, `(stopped)` while a ballot holds it, `no limit` with no clock — words here where the HUD shows nothing, because a status line is read when somebody asks and a missing row reads as a diagnostic that forgot. A server with no vote keeps the session's, which is then the real clock. `dedicated` extends the vote through the console's view and asserts the line moves by the extension while the session's clock does not, and that rtv-only with no duration says `no limit`; armed by putting the old line back, three checks fired.

**The vote's cues reach the client.** `G2GVote.cue_due` carries each `cue` and countdown second, the module broadcasts it as `G2GEvents.Kind.VOTE`, and the client plays it through `G2GPresentation`'s catalogue — on voices the run does not use, and below the timer's four in priority, because a ballot opening must never cost a runner the sound of their own split. No countdown before a ballot here: a runner is not in a fight. `dedicated` asserts the reply to `!rtv` and `g2g_rtv` is the ballot's (its delay) rather than the session's (a tally), and `headless_net` sends a cue, a second and an RTV request across the link.

A timer server has no leading score, so nothing here calls `note_score`; `trigger: score_limit` is a setting this game has no use for.

## No message preloads itself

`g2g_event.gd` and `g2g_request.gd` each began by preloading themselves, for a typed `of()` factory. mg-buses-from-hell measured that line (8ed866c) as enough to leak the whole script graph at exit on Godot 4.7.2: a script that `extends DotNetMessage` and preloads ITSELF, first loaded by a module inside a running `DotServer` — which is how every deployed server loads a game. Both are built with `new(kind, body)` now, an `_init` whose arguments default because dot-net's registry decodes with a bare `new()`.

`dedicated`'s last section, **exiting clean**, reads every `DotNetMessage` script under `game/` as text and fails on a self-preload. It is on the source deliberately: the leak is printed by the engine after `quit()`, where no assertion can reach.

**Here it was not the cause, and the leak is still open.** `dedicated` exits with 407 ObjectDB instances, 303 resources, a VariantPools page and six dummy material, shader and texture RIDs — exactly as many before the change as after (2026-09-23). `--verbose` shows the same "every script still loaded" shape buses had (324 `GDScript`s, 55 native class wrappers), so something else is holding the graph up. The one self-preload this game has that buses does not is `g2g_browser.gd` (`extends Node`); it has not been tried.

**`g2g_browser.gd`'s self-preload has been tried now (2026-09-24), and it was fifteen objects of it.** Removing it took `dedicated` from 411 to 396. The same run ruled three more out: `g2g_paths.gd`, `g2g_net_command.gd` and `g2g_net_link.gd` also preload themselves, and removing all three together moved the count by nothing. The rest of what holds the graph is not a self-preload.

**What 9515974 added was two scripts, not two objects a Callable held.** `dedicated` went 409 → 411 with that commit. The game half (`clock_fn = vote.clock_state`) moves nothing — the new code under the old suite leaks 409 — and a `--verbose` diff of the two runs is exactly two more `GDScript` instances, `dot_vote_rules.gd` and `dot_vote_clock.gd`, which the new check's typed `vote.director.rules`/`.clock` and `DotVoteRules.Trigger` load for the first time. Every loaded script is in the graph that leaks, so any check that names a new type adds to the count; untyping the check would lower the number and fix nothing. The remaining non-script instances are the static caches — `G2GTextures._materials`, `_grid`, `_installed` and `G2GCombat._shared_catalogue`, which are the four material, one shader and one texture RID lines — and clearing them at exit takes 14 more off; they are process-lifetime caches by design and are left.

## Things deliberately not here

- **A second transport.** The bridge speaks through `DotClientLink`'s RPCs on one
  `MultiplayerAPI`; browser and desktop clients on one server is the family-wide gap
  in PLATFORM.md.
- **A sandbox.** There are practice blocks now (`sv_props`), and they are deliberately
  not a sandbox: frozen on placement, admin-only by default, and a run made while
  anything is placed cannot be ranked. game-playground is the sandbox.
- **A chat window.** `DotChatClient` holds the history, the channels and the unread
  counts on the client the moment anybody writes a screen for it; what a player gets
  today is the HUD's notice line.
- **A server browser SCREEN.** The browser itself is wired in and asks a real
  `DotServer`; what it draws is a chat listing, and a table a player can click a row
  of is a `DotScreen` and a stack this client does not have.
- **A master server.** `DotBrowserSourceBackbone` reads a listing that nothing is yet
  publishing, and there is no heartbeat — so a browser here finds what somebody typed
  into it and nothing else. That gap is the family's, not this game's.
- **A map-sync client.** game-arena has one; this game does not need one, because
  `G2GGame` drives a `DotMapSession` on every instance including a mirroring client
  and the bridge already sends a map change as a game event. Adding `DotMapSyncClient`
  on top would be a second thing loading the same map, which is two owners of one
  world.
- **A texture set for the hand-built maps.** `G2GTextures` generates a prototype grid
  and the hand-built maps draw in it. `res://textures/prototype/` holds an installed
  set, and **the imported `.bsp` maps are the half that uses it** — see Decision 11.

  **Kenney's prototype kit is installed, and it draws the imported maps only.** That
  split is the second measurement of it, and it went the other way from the first for
  one half. The entry here used to say the kit was a downgrade, on two findings:

  - **The tint is a MULTIPLY**, so the source has to be light, and Kenney's *Dark* set
    is a dark base with light lines that multiplies to nearly black. **This one is
    solved rather than lived with.** An installed set carries its own colour per role —
    the vendored one spends a whole colour on each — so nothing tints it; the multiply
    only ever applied to the greyscale grid, and `material_for` says so now.
  - **The *Light* set is too low-contrast at this tiling**, and that finding stands. It
    was re-rendered on `surf_g2g_intro` beside the generated grid and it is still worse:
    a near-flat saturated panel whose white lines are gone by mid-distance, under six
    brand colours rather than a palette — a mint floor beneath a magenta ramp. A
    movement game whose floor has no readable scale is harder to play, not prettier.

  The two halves of the game are not the same pipeline, and that is why the answer
  differs. A hand-built map is a sunlit `StandardMaterial3D` over a large plane, which is
  what `grid_texture()` was designed against. An imported map is unshaded through the
  lightmap its own compiler baked — which breaks a flat tile up for free — and, more to
  the point, **its alternative is not the grid, it is no texture at all**: a flat role
  colour over 97% of the map. Against that, the kit is not a close call.

  What would still be better for the hand-built half is a light, high-contrast set whose
  line weight survives the tiling. The generated grid is the specification for that.


## `the needle`, and the first route here a bot runs end to end

`bhop_g2g_intro` bonus 2 is ten blocks at a constant 96-unit gap whose width closes from 192 down to 48, with two stage splits on it. Everything else on this map is about SPEED: the main route's gap grows until only a player who kept the last block's momentum crosses it, and bonus 1 is a warm-up. The needle asks for none of that and is still hard, because a block 48 units across is 16 units wider than the player and the whole of it is aim. It is also the practice route this map did not have, for the player who cannot yet chain hops and was refused by everything here at the tenth block.

**A constant gap is the one shape a scripted bot can complete, and that is why the route is shaped like one.** A bot cannot strafe, so it cannot gain, so any route that demands a gain is a route no check can ever drive from a start line to a finish. Every other bonus in this repository is checked by putting a bot on the pad, driving it, and asserting where it ENDED. `headless_run` drives this one through both stage splits into the finish zone, which means the geometry, the zones, the splits and the end line are all proved by something other than reading them: a block moved 100 units fails this and fails nothing else anywhere.

**Two numbers were measured rather than chosen, and both are worth keeping.**

**96 rather than 160.** At a 160-unit gap a hopping bot carried the prestrafe across two gaps and fell at the third, every time. A chained hop takes off wherever the last one landed rather than at the lip, so the distance actually available is the jump minus however far onto the block the bot arrived, and that margin bleeds a little every landing. *A gap a standing jump clears is not a gap a chain of them clears* — which is the number the main route encodes in its first block and nowhere says out loud.

**Jumped AT the gaps, not held.** A bot holding jump with `sv_autobunnyhopping 1` leaves the ground on the tick it lands, so `accelerate` never gets a grounded tick and there is no strafe to gain with in the air: it bleeds to `sv_maxairwishspeed`, which is 30 u/s, and 30 u/s clears nothing on this map. `_needle_jumps_at` presses jump only in the last thirty units of a block, which keeps the bot grounded for the rest of each one — and it reads the window out of the **map's** constants, so moving a block moves the jump with it.

That matters beyond this route. `_test_bhop_run` asserts a top speed of 240 u/s while holding jump, and that number is the **prestrafe** being carried into the first hop rather than anything hopping achieved. The check is true and it is not evidence that the bot is running.

## The bonus tracks had no respawn zone

A `DotTimerZone` carries a track, and a RESPAWN zone on track 0 catches nobody running track 1. `bhop_g2g_intro`'s main route has had one since the map was written and **neither of its bonuses had one at all** — so a player who missed a bonus platform fell out of the world for ever, with nothing in the log to say so, while the identical mistake on the main route put them back on the pad. Found by driving a bot off the needle: it was still falling 1,370 metres down.

`surf_g2g_intro` was given per-bonus respawn zones when its second bonus was added, and `headless_run.zones_have_respawn_on_bonuses` was written at the same time — **asked on the surf map only.** So the guard existed, passed, and was never once pointed at the map that was broken. It is asked on this map now too. Same shape as the stale copied list this tree has had in `setup.sh`, both check scripts, both bootstraps and `tools/export_zones.gd`: the fix went to one place and the question was never asked of the others. **And it happened a third time**: `bhop_g2g_stages`' surf bonus had a start, a finish and a spawn and no pit, because the helper was asked of whichever map a section had loaded and no section loads that one. The helper is gone; dot-timer's `DotTimerZoneSet.route_problems()` (`[track-zone-1]`) asks every route for a start, a finish, a spawn and a pit of its own, `_test_zone_files_match` asks it of every hand-written map, and `headless_imported` of every imported one — where four maps' bonuses have no pit at all, because the importer puts every teleport on the main track (`BONUSES_WITHOUT_PITS`, asserted both ways, `[track-zone-2]`).

## What a jump reaches, asked of the three hand-written maps

`[reach-1]` asked this of game-playground and game-arena and both were wrong: a jump course unfinishable past platform three, and three maps of routes nothing had ever climbed, under suites that passed throughout. Asked here, **every jump the three maps declare is inside reach** — and the question found two things the maps' own comments never said.

**This genre has two reaches, and a gap is sized for one of them.** `G2GReach` holds both, read off the `DotFpsTunables` the server applies rather than off copied constants, so `sv_gravity` and `sv_enablebunnyhopping` move every answer with no second number to update:

- **RUN** is a jump from the lip at run speed. Ground acceleration gets a player back to 250 u/s in about thirty units, so anybody who lands anywhere on a block can run to its edge and take it however badly the last hop went. It clears **189 units flat, 166 onto a 24-unit step, 222 down 48** — the landing height is the whole point, because the airtime everybody writes down is the time back to the height you left.
- **CHAIN** is a hop inside a run of auto-hops, and it is a different quantity rather than a longer one. With the key held there is no grounded tick to walk to the lip on, so a hop takes off where the last one landed and the hops have to average a whole block period — the gap *and* the block. Speed is what makes a period, and strafing is the only thing that makes speed, so a chain is judged by simulating it with a perfect strafe every tick (`v² + 30²` a tick, which is `DotFpsMotor.accelerate`'s own arithmetic). **That is an upper bound on purpose**: a chain it refuses is one nobody can run, and how much of a perfect strafe a chain needs is printed rather than asserted, because that is the number that says how hard it is and no threshold on it would be anything but a guess.

**A map declares which bodies are a route and which reach it is for, and nothing else.** `G2GMap.add_course(name, track, kind, bodies)` is called from `_build` with the bodies `G2GGeometry.box` just returned; the rise, the clear air and the landing depth are read off their transforms and box shapes. That is game-arena's `climbs` pattern, and it cannot drift from the geometry because it IS the geometry — widening the needle's gap to 200 fails nine routes, and a 60-unit climb step fails seven. The clear air is the least distance between the two footprints, not game-arena's larger axis gap, because the stages map's zigzag is 80 units across as well as the gap along and the player flies the diagonal. No hull credit is spent anywhere: the capsule can stand about eleven units past a lip on this slope limit, and that is the margin.

What `headless_run` prints, all passing:

| course | reach | widest | needs |
| --- | --- | --- | --- |
| `bhop_g2g_intro` main | CHAIN, 17 hops | 288 | 44% of a perfect strafe |
| `bhop_g2g_intro` warm-up | RUN, 3 | 128 | inside 189 |
| `bhop_g2g_intro` the needle | RUN, 11 | 96 | inside 189 |
| `bhop_g2g_stages` main | CHAIN, 40 hops | 288 | 54% |

`surf_g2g_intro` declares nothing, and says why in its header: every way from one surface to the next on it is a drop onto something below, and only riding it answers whether the thing below is there.

**`!s2` and `!s3` on `bhop_g2g_intro` put a player where nobody can continue.** A stage restart is a chain that begins at run speed rather than at whatever the stages before it built, and from blocks 10 and 14 the gaps ahead need more than even a perfect strafe adds in the hops available — from 14, the next gap is 275 units and a perfect single hop from 250 u/s covers 245. `!s1` needs 78%; the stages map's four restarts need 49% to 81%. The restarts are printed and **not** asserted: they are the same three destinations `[stage-yaw-1]` is already waiting on Christian for, and the only fixes are moving a stage line on a scored track or putting `!s3` somewhere that is not stage 3.

**And with `sv_enablebunnyhopping 0`, neither bhop map's main route exists.** The landing cap trims every take-off to 275 u/s, one hop of strafing cannot span the period, and `bhop_g2g_intro` falls at its sixth gap and `bhop_g2g_stages` at its fourth. That is asserted, which is also the proof the chain arithmetic refuses something rather than approving everything. An operator turning the cvar off is turning these two maps into the needle and the warm-up.

## `surf_g2g_intro`'s single bank, driven from its pad into its finish

Bonus 1 is now run end to end, which closes this repository's half of `[bonus-run-2]`. The bank is level along its length, so nothing but the entry speed carries a rider down it and gravity pulls them toward its low lip the whole way; `_test_single_bank` holds strafe into the bank while the bot is below a line and lets go above it, and never touches forward. The line is read off the map — `bonus_bank_lip_x()` plus a hull width — which is why bonus 1's numbers are named constants now rather than literals in `_build`. It asserts the run starts, the bot reaches the bank's far end, and it lands in the finish **without being put back**; nothing in it can pass on a respawn, which is the failure `[bonus-run-2]` found the transfer's check committing. Shortening the bank fails two of the three.

**The `[surf-ramp-1]` answer for this route is the same as the main run's.** The bot loses under 150 units of height on the bank — the drop onto it and the line it holds — and then falls 753 onto the pad. The descent of this route is the fall off the end of the bank, not the bank.

Two things driving it found, and neither is fixed here:

- **A surfer holding into a bank can freeze in mid-air with its speed intact.** With the bot's line one hull width up from the lip it finishes; at several other lines it stops dead within a few hundred ticks and never moves again — position fixed to the unit, `velocity` still reading 222 u/s, `is_grounded()` false, `stuck_ticks` 0, and `DotFpsMotor.duplicate_plane_ticks` rising by one every tick. It is the duplicate-plane early-out this file's Decision 11 already measured on imported ramps, taken to its limit on a flat hand-built one: a velocity lying exactly in the plane the capsule rests on meets that plane again at fraction zero, the slide stops the move, and the next tick is the same tick. Even on the line that works, 697 of 1,786 ticks end that way. It is dot-player-controller's, it is predicted against by the netcode, and it is the reason the bot's line is where it is.
- **The finish only catches a slow rider.** Only the strip of bank between its lip and the pad's far edge lies over the pad, and the end zone is 512 units deep and tops out 455 units under the line the bot rides — so a rider leaving the bank faster than about 470 to 590 u/s, depending on where on that strip, passes over the whole zone and lands in the pit. A bot holding forward-and-right, which is a real strafe, left the bank at 866 u/s and was put back from 1,578 units past the pad's far edge. On a surf route, going well is what fails it. Not changed: it is a scored track, and the two fixes — a longer pad and zone, or a taller zone — respectively leave every existing time comparable and make every future one faster than it, which is Christian's call.

