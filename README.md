# Voxel Earth (Luanti)

Google Earth 3D Tiles → voxels → Luanti/Minetest.

Type `/visit Paris` in-game and it will:

- Geocode the location with the Google Maps API
- Download Google Earth 3D tiles around that point
- Voxelize the meshes with a Node.js pipeline
- Place the blocks in your Luanti world
- Teleport you above the imported area

This is a beta port of my Java/Bukkit code, wired up to Luanti with a Node shim.

---

## Install

1. **Drop the mod into Luanti**

   Copy the `luanti_earth` folder into your Luanti mods directory, e.g.:

   ```text
   luanti-5.14.0-win64/
     mods/
       luanti_earth/
         init.lua
         voxel_importer.lua
         tile_downloader.js
         voxelize_tiles.js
         voxelizer.worker.js
         rotateUtils.cjs
         colors.lua
         mod.conf
         package.json
         ...

2. **Install Node dependencies**

   From inside the `luanti_earth` folder:

   ```bash
   cd path/to/luanti_earth
   npm install
   ```

   This pulls in things like `three`, `axios`, `p-queue`, `yargs`, `jpeg-js`, etc.

3. **Enable the mod**

   * In the Luanti GUI: World → Configure → Mods → enable `luanti_earth`, **or**
   * Add to `world.mt`:

     ```ini
     load_mod_luanti_earth = true
     ```

4. **Give it HTTP + “insecure” permissions**

   The mod needs:

   * HTTP to talk to Google
   * Insecure env to run Node.js

   In `minetest.conf` / `luanti.conf`:

   ```ini
   secure.http_mods = luanti_earth
   secure.trusted_mods = luanti_earth
   ```

   Or do the same via Advanced Settings → `secure.http_mods` / `secure.trusted_mods`.

   Restart Luanti after changing this.

---

## Commands

All commands are server-only (`privs = {server = true}` except `/visit` which also needs `teleport`). 

Do `/grantme all` on the server for easy access.

### `/earth_apikey <key>`

Stores your Google API key in the world’s mod storage.

```text
/earth_apikey AIza...whatever
```

The key must have:

* Geocoding API enabled
* Maps 3D Tiles / Google Earth 3D tiles access enabled

I usually hard-code a key in plugins, but there’s no nice way to obfuscate it here, so you bring your own. If you’re stuck on that, ping me.

---

### `/visit <location>`

Main entry point.

Examples:

```text
/visit Paris
/visit "New York, NY"
/visit 40.7484,-73.9857
```

What it does:

1. Geocodes the text → lat/lng
2. Runs `tile_downloader.js` to grab and rotate 3D tiles
3. Runs `voxelize_tiles.js` to voxelize the GLBs → JSON
4. Uses `voxel_importer.lua` + `VoxelManip` to place the voxels at `(0, 50, 0)`
5. Teleports you up above the imported area

Tiles + voxel JSON are cached per-world in:

```text
worlds/<yourworld>/luanti_earth_cache/<location>/glb/
worlds/<yourworld>/luanti_earth_cache/<location>/json/
```

On first run, expect:

* Your terminal/console to print Node logs
* A bit of freezing while it downloads + voxelizes + places blocks

---

### `/earth_use_pure_colors <true|false>`

Toggles how colors map to blocks.

```text
/earth_use_pure_colors true
/earth_use_pure_colors false
```

* `true` (default):
  Uses custom `luanti_earth:color_<id>` nodes (256 pure color blocks) so the result is closer to the actual imagery.
* `false`:
  Maps voxel colors to “natural” blocks (stone, dirt, leaves, etc.) using a color palette.

This only affects *future* imports; it doesn’t retroactively remap existing areas.

---

### `/earth_load_voxels <absolute_path>`

Load a single voxel JSON file at your current position:

```text
/earth_load_voxels C:\Users\you\voxels\paris_tile_01_voxels.json
```

* Reads the JSON on the server
* Uses the same VoxelManip path as `/visit`
* Places blocks relative to your position

Useful when you’ve voxelized things manually via the CLI.

---

### `/earth_export_viz <input_json> <output_json>`

Dumb exporter for a simpler visualization format:

```text
/earth_export_viz C:\path\to\full_voxels.json C:\path\to\viz.json
```

Writes a stripped-down JSON that’s easier to feed into a web visualizer. Mostly for debugging.

---

## How it works

* `init.lua`

  * Registers `/earth_apikey`, `/visit`, `/earth_use_pure_colors`, `/earth_load_voxels`, `/earth_export_viz`
  * Uses `request_http_api()` at init (as required by Luanti)
  * Uses `request_insecure_environment()` to get `os_execute` so it can run Node

* `tile_downloader.js`

  * Talks to Google’s 3D Tiles API
  * Walks `root.json`, does bounding-volume culling
  * Downloads GLBs and rotates everything into a shared origin (`rotateUtils.cjs`)

* `voxelize_tiles.js` + `voxelizer.worker.js`

  * Load GLBs with `three` / `GLTFLoader`
  * Decode textures
  * Voxelize into a grid
  * Write `*_voxels.json` with:

    * grid coords `x,y,z`
    * world coords `wx,wy,wz`
    * per-voxel `r,g,b,a`

* `voxel_importer.lua`

  * Reads the voxel JSON
  * Uses world coords (if present) + an offset
  * Uses `VoxelManip` to set thousands of nodes in one go instead of calling `set_node` in a loop
  * Converts `r,g,b` → block name:

    * If pure mode: `luanti_earth:color_<id>`
    * Else: nearest match from the block palette

---

## Current state / caveats

* This is a thin Lua wrapper around older Node code I used for Java/Bukkit.
  There’s still some glue and “console popping up” behaviour.
* It is **not** feature complete:

  * No streaming “load more as you walk” yet
  * `/visit` just builds a single island at a fixed random spot and teleports you there
* Luanti still hiccups on large imports, even with VoxelManip. It’s much better than raw `set_node` loops, but it’s not magic.
* If you hit weird issues (0 tiles, all-white, etc.), check:

  * Luanti log for HTTP / security errors
  * Node output in your terminal
  * The cache folders for GLBs and JSON

TLDR- Drop it in, `npm install`, set an API key with `/earth_apikey`, and start poking `/visit Paris`, `/visit Rome`, etc.
