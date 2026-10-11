# Real SM64 models for Star Kingdom Defense

This tool turns Mario, Bowser, Goombas, Boos and the rest into model files for Roblox Studio, using your own
Super Mario 64 ROM. This repository contains no Nintendo data: the models are made on your computer, and only
you decide whether to import them.

> Studio uploads imported meshes and textures to your Roblox account, and Roblox moderation reviews them even in a
> private game. Importing Nintendo's models is at your own risk. Keep the game private.

## 1. Make the models (about 10 seconds)

You need Python 3 (from [python.org](https://www.python.org/downloads/)) and your **Super Mario 64 (USA)** ROM as
a `.z64` or `.v64` file.

```
cd tools/sm64_import
python sm64_to_roblox.py --rom "C:\path\to\Super Mario 64 (USA).z64"
```

The first run downloads the SM64 decompilation source from GitHub (about 30 MB) into `sm64-src`, since the models'
geometry is read from it. If you already have it, pass `--sm64 path\to\sm64`.

This writes one model per game id into `sm64_models`:

| Units | | Enemies | |
|---|---|---|---|
| mushling | Goomba | grumble | Goomba |
| fusebuddy | Bob-omb Buddy | sprinter | Spiny |
| shellback | Koopa Troopa | shellguard | Bully |
| buzzwing | Fly Guy | splitter / minibomb | Bob-omb |
| spooky | Boo | flutter | Fly Guy |
| cloudrider | Lakitu | phantom | Boo |
| shroombanker | Toad | skyray | Swoop |
| flamebloom | Piranha Plant | kinggrumble | King Bob-omb |
| stoneslammer | Whomp | sandwyvern | Klepto |
| chainchomper | Chain Chomp | frostgolem | Chill Bully |
| starsage | Hoot | lavatitan | Big Bully |
| captaincomet | Mario | shadowmonarch | Bowser |
| infernodrake | Bowser | | |
| starprincess | Princess Peach | | |

Each model comes as `<id>.glb` (texture included) and as `<id>.obj` + `.mtl` + `.png`. There's also
`set_names.lua`.

## 2. Import them into Studio

1. Open the game in Roblox Studio.
2. Go to **Home → Import 3D** (or **File → Import 3D**) and select all the `.glb` files in `sm64_models`.
3. In the import window, keep the default settings and click **Import**. The models appear in the Workspace, each
   named after its file (`captaincomet`, `grumble`, ...).
4. Open **View → Command Bar**, paste the whole content of `set_names.lua`, and press Enter. It moves the models
   into `ReplicatedStorage → CustomModels` and gives them their SM64 names.
5. Press **Play**. Every unit, enemy, statue, summon card and the boss bar now shows the SM64 characters and names.

The game scales each model to the right size automatically. If the models face backwards in a battle, run this in
the Command Bar:

```lua
for _, m in game.ReplicatedStorage.CustomModels:GetChildren() do m:SetAttribute("FaceYaw", 180) end
```

To go back to the built-in models, delete the `CustomModels` folder.

## How it works

The script reads each actor's geo layout and display lists from the decomp's C files. It walks them the way SM64's
renderer does, including the N64 vertex buffer that lets Mario's limbs join seamlessly, and poses the model on the
first frame of one of its animations. Textures are decoded from the ROM (MIO0-compressed banks, RGBA16/IA/I
formats), and the lights and vertex colours are baked into one texture atlas. The model is turned to face -Z and
written as glTF and OBJ. Everything uses the Python standard library.

To use a different SM64 actor for a unit, edit the `ACTORS` table at the top of `sm64_to_roblox.py`. Each entry is
the actor's geo layout name from `actors/<name>/geo.inc.c`, the animation to pose it with, and the name to show.

## No importing: build the meshes into the place

With `--luau sm64_luau` the script also writes the models as data files that the game turns into meshes itself
when it starts (EditableMesh). Nothing needs importing or uploading:

```
python sm64_to_roblox.py --rom "Super Mario 64 (USA).z64" --luau sm64_luau
cd ../..
rojo build sm64.project.json -o StarKingdomDefense_SM64.rbxlx
```

Open `StarKingdomDefense_SM64.rbxlx` and press Play. This works in Studio. In a published game, Roblox may only
allow EditableMesh for ID-verified accounts. Both `sm64_luau` and the `_SM64` place file are git-ignored; don't
share them.
