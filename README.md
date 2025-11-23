# Voxel Earth Luanti - Node.js Pipeline

## Complete Workflow

### 1. Download and Rotate Tiles
```bash
# Download tiles for a location (e.g., San Francisco)
node download_and_rotate.js \
  --key $GOOGLE_MAPS_KEY \
  --lat 37.7749 --lng -122.4194 \
  --radius 800 \
  --out ./tiles \
  --parallel 16 \
  --debug-download
```

This will create:
- `tiles/*.glb` - Rotated and centered GLB files
- `tiles/*_downloaded.glb` - Original GLB files (if `--debug-download` is used)

### 2. Voxelize Tiles
```bash
# Voxelizethe downloaded tiles
node voxelize_tiles.js ./tiles ./voxels 200
```

Arguments:
- `./tiles` - Input directory with GLB files
- `./voxels` - Output directory for voxel JSON files
- `200` - Resolution (higher = more detail, but slower)

This will create:
- `voxels/*_voxels.json` - Voxel data with positions and colors

### 3. Visualize (Optional)
Open `visualizer.html` in a browser and paste the content of a voxel JSON file to preview it in 3D before loading into Luanti.

### 4. Load into Luanti
1. Copy the `luanti_earth` mod folder to your Minetest mods directory
2. Enable the mod in your world
3. Configure `minetest.conf`:
   ```ini
   secure.http_mods = luanti_earth
   ```
4. In-game, use:
   ```
   /earth_load_voxels <absolute_path _to_voxel_json>
   ```

## File Structure
```
luanti-earth/
├── download_and_rotate.js  # Node.js - Download & rotate tiles
├── voxelize_tiles.js        # Node.js - Voxelize GLBs
├── voxelize-model.js        # Node.js - Voxelization library
├── voxelizer.worker.js      # Node.js - Worker for voxelization
├── rotateUtils.cjs          # Node.js - ECEF to ENU rotation
├── visualizer.html          # Browser - Voxel visualizer
├── init.lua                 # Luanti - Mod entry point
├── voxel_importer.lua       # Luanti - Voxel data loader
├── mod.conf                 # Luanti - Mod configuration
└── package.json             # Node.js dependencies
```

## Dependencies
```bash
npm install
```

Required packages:
- `three` (for GLB loading and voxelization)
- `axios` (for HTTP requests)
- `p-queue` (for parallel processing)
- `yargs` (for CLI arguments)
- `draco3d` (for Draco decoding)

## Notes
- The voxelizer samples texture colors from the GLB files
- Colors are mapped to Luanti blocks based on luminance and hue
- You can customize the `rgb_to_block()` function in `voxel_importer.lua` to use different blocks
