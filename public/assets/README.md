# Assets

Sprites are loaded through `manifest.json` (key -> file).
To use a PNG instead of a placeholder SVG, drop the file here and change its entry,
e.g. `"knight": "knight.png"`. Tile sprites (grass, dirt, wall, water) should tile seamlessly;
all sprites are drawn square. If a file fails to load the game falls back to plain shapes/colors.
