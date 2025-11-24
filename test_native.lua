-- test_native.lua
local modpath = "."
package.cpath = package.cpath .. ";" .. modpath .. "/?.dll"

local success, earth_native = pcall(require, "earth_native")
if not success then
    print("Failed to load module: " .. tostring(earth_native))
    os.exit(1)
end

print("Module loaded successfully!")

-- Test coordinates (Paris)
local lat = 48.8566
local lon = 2.3522
local radius = 50
local resolution = 50
local api_key = "yourkeyhere"

----------------------------------------------------------------
-- Simple JSON encoder for our voxel list
----------------------------------------------------------------
local function voxels_to_json(voxels)
    local parts = {}
    table.insert(parts, '{"voxels":[')

    for i, v in ipairs(voxels) do
        if i > 1 then
            table.insert(parts, ",")
        end

        -- All fields are integers, so no quoting needed for values
        table.insert(parts, string.format(
            '{"x":%d,"y":%d,"z":%d,"r":%d,"g":%d,"b":%d,"a":%d}',
            v.x or 0,
            v.y or 0,
            v.z or 0,
            v.r or 0,
            v.g or 0,
            v.b or 0,
            v.a or 255
        ))
    end

    table.insert(parts, "]}")
    return table.concat(parts)
end

----------------------------------------------------------------
-- Main test
----------------------------------------------------------------
print("Testing download_and_voxelize...")
local voxels = earth_native.download_and_voxelize(lat, lon, radius, resolution, api_key)

if not voxels then
    print("No voxels returned.")
    os.exit(1)
end

print("Received " .. #voxels .. " voxels.")
if #voxels > 0 then
    local v = voxels[1]
    print(string.format(
        "Sample voxel: x=%d y=%d z=%d r=%d g=%d b=%d",
        v.x, v.y, v.z, v.r, v.g, v.b
    ))
end

-- Write to voxels.json for the browser visualizer
local json = voxels_to_json(voxels)
local filename = "voxels.json"
local f, err = io.open(filename, "w")
if not f then
    print("Failed to write voxels.json: " .. tostring(err))
    os.exit(1)
end
f:write(json)
f:close()

print("Wrote " .. filename .. " with " .. #voxels .. " voxels.")
print("Open voxels.json, copy its contents, and paste into the visualizer textarea.")
print("Test complete.")