This is a game to demonstrate the capabilities of the [**Dot collection**](https://moddingcommunity.com/co/4-dot-assets) built on-top of [Godot 4](https://godotengine.org/) and [TMC's gaming platform](https://moddingcommunity.com/play). In this 3D game, players *surf* and *bunny hop* on *maps* to compete for world records through a timer. This is highly inspired off of Source Engine movement and includes some classic Surf Timer and Bunny Hop maps (WIP) from the game Counter-Strike: Source!

![Preview](https://github.com/gamemann/game-g2gfast/blob/main/images/preview.gif?raw=true)

*Play on my test server [here](https://moddingcommunity.com/g2gfast/s/g2gfast01/play)!*

**This project and the assets under it are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This project, along with every asset it is built on, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** It has its own headless test suite and that suite passes, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## How it plays
Each map has a start zone and an end zone. Leaving the start zone starts your timer and reaching the end stops it. Your best time on each map, track and style is a record, and the fastest one on the server is the world record. Some maps are split into stages, and some have bonus tracks.

The movement uses the classic units and cvars (`sv_airaccelerate`, `sv_autobunnyhopping` and the rest), so surfing and strafing feel the way they always have.

There are styles for a harder run: normal, sideways, half-sideways, backwards, low gravity and prebhop. A run made with an admin's help (noclip, a speed change and so on) is never saved.

The game comes with three maps of its own: `bhop_g2g_intro`, `bhop_g2g_stages` and `surf_g2g_intro`. The classic maps it imports live in a separate repository, [g2gfast-maps](https://github.com/gamemann/g2gfast-maps), and a server downloads them on demand.

## Controls

| Key | Action |
| --- | --- |
| **WASD** | Move |
| **Space** | Jump (hold it, if the server allows auto-hop) |
| **Ctrl** | Duck |
| **F5** | First or third person |
| **Tab** | Change style |
| **R** | Back to the start |
| **C** / **V** | Save a practice checkpoint / go back to it |
| **Y** / **U** | Chat / team chat |
| **M** | Next map (offline only; on a server, type `!rtv` to start a vote) |
| **Esc** / click | Release the mouse / take it back |
| **`** | The console. `settings` lists every setting |

In chat: `!r` (restart), `!wr` or `!top` (fastest times), `!style`, `!track bonus 1`, `!s <n>` (go to stage n), `!rs` (restart this stage), `!stats`, `!rtv`.

`show_own_body 1` in the console draws your own character in first person. It is off by default.

## Getting started
You need [Godot 4.7](https://godotengine.org/download). The game is built from many Dot addons, each in its own repository, so the easiest way to get everything is [dot-bootstrap](https://github.com/modcommunity/dot-bootstrap). It clones every project and links the addons into each one:

```bash
git clone https://github.com/modcommunity/dot-bootstrap.git
cd dot-bootstrap
./bootstrap.sh
cd projects/game-g2gfast
./game.sh
```

On Windows, run `bootstrap.ps1` instead and open the project in Godot.

`game.sh` does everything else:

| Command | What it does |
| --- | --- |
| `./game.sh` | Play offline, in a window |
| `./game.sh online` | Start a local server and the browser client, and print the link to open |
| `./game.sh online down` | Stop them |
| `./game.sh server` | Start a local dedicated server only |
| `./game.sh test` | Check every script and run every test suite |
| `./game.sh help` | All of the options |

`online` and `server` use [dot-server-deploy](https://github.com/modcommunity/dot-server-deploy), which bootstrap clones next to this one. Run its `./setup.sh` once first.

## Running a server
Settings are cvars, in the units you already know. Set them in the server's config, on the command line, or live from the console. `cvarlist sv_` lists them all.

```
sv_autobunnyhopping 1        // hold jump to keep hopping
sv_airaccelerate 1000        // 150 for surf
sv_gravity 800
sv_maxvelocity 3500
sv_crestlaunch 1.25          // how fast you must be going for a ramp's top to launch you (x run speed, 0 = never)
sv_allow_thirdperson 1
sv_replay_bot 1              // the server record runs as a visible ghost
sv_map_sync_timeout 30       // how long a map change waits for slow clients
sv_deathmatch 0              // players can shoot each other
sv_hunters 0                 // monsters walk the course
sv_props 0                   // players can place practice blocks
```

Console commands:

| Command | |
| --- | --- |
| `g2g_status` | What the server is doing |
| `g2g_map <id>` | Change the map, or list them with no id |
| `g2g_maps_reload` | Pick up maps added to `maps/` without a restart |
| `g2g_top` | Fastest times on this map |
| `g2g_ghost` | What the record ghost is running |
| `g2g_vote` | Open a map vote now |
| `g2g_hunt [clear\|spawn <id>]` | Show, clear or place hunters |
| `g2g_place_clear` | Clear every placed block |

When the map changes, every client is told first, downloads the map if it needs to, and the server switches once everybody is ready (or after `sv_map_sync_timeout`).

### Admin commands
These come from [dot-moderation](https://github.com/modcommunity/dot-moderation): `!noclip`, `!freeze`, `!slay`, `!blind`, `!beacon` and the rest. Any run that noclip, speed or gravity touches is not saved. `burn` is turned off, because there is nothing to burn on a course.

### The map vote
The vote for the next map is [dot-vote](https://github.com/modcommunity/dot-vote). The defaults are in `game/g2g_vote.gd`. To change them, put a file at `user://cfg/g2gfast_vote.json` (or use `DOT_VOTE_*` environment variables, or `--vote-*` arguments):

```json
{ "end_vote": true, "vote_lead_sec": 120, "include_extend": true, "extend_seconds": 600, "max_extends": 3 }
```

`end_vote: false` turns the end-of-map vote off, and `include_extend: false` takes "extend" off the ballot. dot-vote's README lists every setting.

## Maps
### Importing a map
The importer reads BSP version 20 maps. Put the `.bsp` files in `../inspirations/g2gfast/` and run:

```bash
tools/import_maps.sh      # imports anything new, skips what is already current
tools/bsp_preview.sh      # renders each map from its spawn, so you can look at it
```

The imported maps land in `maps/imported/`, which is a link to the g2gfast-maps checkout. A running server picks up new ones with `g2g_maps_reload`.

Collision comes from the map's brushes, not from what you can see, so invisible player clips and surf ramp clips work the way the mapper meant. Surfaces are coloured by their angle: one you can stand on, one you slide on, and a wall each look different.

### Zones
Most surf and bunny-hop maps name their own start and end zones, stages and bonuses, and the importer reads those. For a map that doesn't, write the zones in `maps/zones/<id>.json` (see `maps/zones/README.md`), or draw them in the game from the console:

```
g2g_zone start          // start drawing a start zone
g2g_zone_mark           // stand on one corner
g2g_zone_mark           // then the other
g2g_zone stage main 1   // the next zone: stage 1 of the main track
g2g_zone_save           // write them to disk
```

`g2g_zone_undo` removes the last one and `g2g_zone_list` lists them.

## Testing

```bash
./game.sh test                  # every script parses, then every suite runs
./game.sh test headless_run     # one suite
```

| Suite | What it covers |
| --- | --- |
| `headless_run` | The movement, the timer, the zones, and bots running every built-in map |
| `headless_net` | A server and a client in one process, over the network code |
| `headless_maps` | The map catalogue, map changes and the vote |
| `headless_presentation` | What a client draws and plays |
| `headless_stack` | The whole stack of addons together |
| `headless_imported` | Every imported map loads and has its zones |
| `dedicated` | A real server: boots, loads the game, runs its commands |

[`CLAUDE.md`](CLAUDE.md) has the design decisions and the reasoning behind them.

## Credits
`textures/prototype/` is Kenney's Prototype Textures (CC0). `textures/prototype/README.md` says which file came from where. The characters are from Kenney's character kits (CC0). The imported maps are credited to their authors in [g2gfast-maps](https://github.com/gamemann/g2gfast-maps).

## License
MIT. See [LICENSE](LICENSE). The Kenney textures are CC0, which is public domain.
