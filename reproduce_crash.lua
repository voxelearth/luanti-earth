-- reproduce_crash.lua
local modpath = "."
package.cpath = package.cpath .. ";" .. modpath .. "/?.dll"

local success, earth_native = pcall(require, "earth_native")
if not success then
    print("Failed to load module: " .. tostring(earth_native))
    os.exit(1)
end

print("Module loaded successfully!")

-- Parameters from init.lua that cause crash
local lat = 48.8566
local lon = 2.3522
local radius = 200
local resolution = 100

print("Testing download_and_voxelize with HIGH load...")
local voxel_bytes = earth_native.download_and_voxelize(lat, lon, radius, resolution, api_key)
local end_time = os.clock()

if not voxel_bytes or #voxel_bytes == 0 then
    print("No voxels returned.")
    os.exit(1)
end

local voxel_count = math.floor(#voxel_bytes / 16)
print("Received " .. #voxel_bytes .. " bytes (" .. voxel_count .. " voxels).")

if voxel_count > 0 then
    -- Helper to read int32 little endian
    local function read_int32_le(str, offset)
        local b1 = string.byte(str, offset)
        local b2 = string.byte(str, offset + 1)
        local b3 = string.byte(str, offset + 2)
        local b4 = string.byte(str, offset + 3)
        local n = b1 + b2*256 + b3*65536 + b4*16777216
        if n > 2147483647 then n = n - 4294967296 end
        return n
    end

    local x = read_int32_le(voxel_bytes, 1)
    local y = read_int32_le(voxel_bytes, 5)
    local z = read_int32_le(voxel_bytes, 9)
    local r = string.byte(voxel_bytes, 13)
    local g = string.byte(voxel_bytes, 14)
    local b = string.byte(voxel_bytes, 15)
    
    print(string.format(
        "Sample voxel: x=%d y=%d z=%d r=%d g=%d b=%d",
        x, y, z, r, g, b
    ))
end
