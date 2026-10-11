# Star Kingdom Defense

A Mario-inspired tower defense game for Roblox. Summon units of four rarities, build a team of six, defend your
castle across five campaign maps, clear daily challenges for Trait Crystals, and roll traits that buff your units.

Every character, map and effect is built from Roblox parts in code, so the game works with no uploaded meshes, images
or sounds and contains no Nintendo assets.

**Want the real Super Mario 64 characters?** [`tools/sm64_import`](tools/sm64_import/README.md) turns your own SM64
ROM into models for Studio's 3D Importer: Mario, Bowser, Peach, Goombas, Boos, Chain Chomps and more. Imported models
replace the built-in ones everywhere, with their SM64 names.

## Play it

1. Install [Roblox Studio](https://create.roblox.com/).
2. Download `StarKingdomDefense.rbxlx` from this repository and double-click it (or open it from Studio's File menu).
3. Press **Play** (F5).

To keep your progress between sessions:

1. Publish the place with **File → Publish to Roblox**.
2. Turn on **Game Settings → Security → Enable Studio Access to API Services**.

Without this the game still runs, but every session starts fresh. The output window says so once.

In the published game each battle runs in its own reserved server: starting a stage saves your data and teleports
you there, and leaving teleports you back to a lobby server. In Studio, where teleports don't work, battles run in an
arena next to the lobby instead.

**Admin panel**: press F2 (or the red ADMIN button) to give gems, crystals, levels, units and traits, unlock maps and
control the current battle. It's open to anyone in Studio, to the game's owner, and to the user ids in `ADMINS` at the
top of the admin section in `src/server/Main.server.luau`.

## How to play

- **Lobby**: use the menu tiles on the left, or walk up to the castle's battle gate (Play) or the Summon Hall
  pedestal (Summon) and press E.
- **Play**: pick a map and stage. Click a unit in the hotbar (or press 1–6), then click the ground to place it. Hold
  Shift to keep placing, and press Q or right-click to cancel. Click a placed unit to upgrade it with T (4 upgrades),
  change its targeting with R (First / Last / Strongest / Closest) or sell it for 60% with X.
- **Waves** arrive on a timer, even while enemies are still alive. When the field is clear the next wave comes after
  3 seconds, and once a wave has finished spawning you can skip ahead. Every wave pays a cash bonus.
- **Units level up** (up to Lvl 50, +1.2% damage per level) from the XP each battle gives the team. Each summoned
  unit also rolls **stat grades** from C to SSS for damage (DMG), attack speed (SPA) and range (RNG).
- Units can't go on the path or right next to each other. A green range circle means the spot is valid.
- Enemies come from the purple portal. Each one that reaches your castle costs castle health; a boss ends the run.
- Cash comes from kills, wave-clear bonuses and farm units. You can start the next wave early and play at 1x, 2x or 3x
  speed.

## Content

### Units (summon with gems: 50 for x1, 450 for x10)

| Rarity (rate) | Unit | Role |
|---|---|---|
| Common (60%) | Mushling | Ground melee |
| | Fuse Buddy | Ground splash |
| | Shellback | Ground + air shooter |
| | Buzzwing | Anti-air (double damage to flyers) |
| Rare (30%) | Spooky | Slows enemies 35% |
| | Cloud Rider | Ground + air splash |
| | Shroom Banker | Farm: cash every wave |
| | Flame Bloom | Burn damage over time |
| Legendary (8.5%) | Stone Slammer | Ground AoE slam that stuns |
| | Chain Chomper | Triple damage to bosses |
| | Star Sage | Aura: +25% damage and lets nearby units hit flyers |
| Mythic (1.5%) | Captain Comet | Chain lightning (4 targets, ground + air) |
| | Inferno Drake | Fire-breath cone with burn |
| | Starlight Princess | +15% damage to every unit, cash every wave |

Pity: a Legendary or better is guaranteed within 50 summons and a Mythic within 120. Units you don't need can be
released for gems.

### Enemies

- **Ground**: Grumble, Dash Grumble (fast), Shellguard (armored), Fuse Brute (splits into two Mini Fuses).
- **Flying** (only units that hit air can target them): Flutter Guy, Phantom, Sky Ray.
- **Bosses**:

  | Boss | Map | Ability |
  |---|---|---|
  | King Grumble | Mushroom Meadow | Summons Grumbles |
  | Sandstorm Wyvern | Dusty Dunes | Flying boss that dashes |
  | Frost Golem | Frosty Peaks | Freezes nearby units |
  | Magma Titan | Magma Fortress | Turns invulnerable and heals |
  | Shadow Monarch | Star Castle | Summons Phantoms and stuns units |

### Campaign

There are five maps with five stages each: Mushroom Meadow, Dusty Dunes, Frosty Peaks, Magma Fortress and Star
Castle. Stage 5 of each map is the boss stage, and beating it unlocks the next map. First clears pay gems and a Trait
Crystal (3 for a boss stage).

### Challenges (Trait Crystals, once per day each)

| Challenge | Modifier |
|---|---|
| Sky Swarm | Extra flyers every wave |
| Speed Demons | Enemies move 50% faster |
| Common Folk | Common units only |
| Budget Cuts | Half the starting cash, 40% less cash from kills |
| Iron Hide | Enemies have double health |
| Small Squad | At most 6 units on the map |
| Boss Rush | Every boss, one after another |

### Traits (1 Trait Crystal per roll; a unit holds one trait)

| Rarity (rate) | Traits |
|---|---|
| Common (55%) | Strong I (+8% damage), Quick I (+8% attack speed), Keen I (+8% range), Thrifty (-10% cost) |
| Rare (32%) | Strong II (+18% damage), Quick II (+18% attack speed), Hawkeye (+20% range and hits air), Prospector (+25% kill cash) |
| Legendary (11%) | Titan Slayer (+60% vs bosses), Frostbite (attacks slow), Blazing (attacks burn), Overclock (+30% speed, +10% damage) |
| Mythic (2%) | Superstar (+50% damage, +25% speed, +15% range), Chain Reaction (attacks chain to 2 more), Midas Touch (+100% kill cash, +100 per wave), Time Stop (+20% damage, chance to stun) |

## Editing the game

The source is a [Rojo](https://rojo.space/) project:

```
default.project.json     place layout (lobby floor and spawn, where each folder goes)
src/shared/              ReplicatedStorage.Shared: game data and rules used by server and client
  Units.luau             units: stats, rarity, attack type
  Enemies.luau           enemies and boss abilities
  Traits.luau            traits
  Maps.luau              campaign maps (paths, themes) and wave generation
  Challenges.luau        challenges and their modifiers
  Rarities.luau          rarity colors, summon and trait odds, pity
  Stats.luau             effective unit stats, costs and placement rules
  Progression.luau       unit levels and XP, C-SSS stat grades
  ModelFactory.luau      every unit and enemy model, built from parts
src/server/              ServerScriptService.Server
  Main.server.luau       remotes: summons, traits, team, starting and ending battles, rewards
  Battle.luau            the battle simulation: waves, enemies, units, auras, abilities
  MapBuilder.luau        builds a map's ground, path, scenery, portal and castle
  DataService.luau       DataStore saving
  Lobby.luau             the lobby: castle and battle gate, Summon Hall, unit statues
src/client/              StarterPlayerScripts.Client: lobby windows, battle HUD, placement, effects
  Ui.luau                the UI kit: windows, buttons, icons, unit cards, stat chips, viewports
  SummonFx.luau          the summon animation
  Animator.luau          unit and enemy animations on the SM64 models
  AdminPanel.luau        the admin panel
  Travel.luau            the loading screen between servers
  Audio.luau             music and sound effects (SM64's own, from tools/sm64_import/sm64_audio.py)
tools/sm64_import/       makes real SM64 models from your own ROM (see its README)
```

Most balance changes are a number in `src/shared`. To use your own models, put a Model named after a unit or enemy id
(for example `captaincomet` or `grumble`) in a Folder `ReplicatedStorage/CustomModels`. It replaces the built-in model,
scaled automatically, and a `DisplayName` attribute on it renames the character in the UI.

To work on the code with live sync, install Rojo, run `rojo serve`, and connect from the Rojo plugin in Studio. To rebuild the place file, run:

```
rojo build -o StarKingdomDefense.rbxlx
```
