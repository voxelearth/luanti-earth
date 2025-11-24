-- reproduce_crash.lua
local modpath = "."
package.cpath = package.cpath .. ";" .. modpath .. "/?.dll"

local success, earth_native = pcall(require, "earth_native")
if not success then
    print("Failed to load module: " .. tostring(earth_native))
    os.exit(1)
end

print("Module loaded successfully!")

-- FFI Setup
local ffi = require("ffi")
ffi.cdef[[
    int start_download_and_voxelize(double lat, double lon, double radius, int resolution, const char* api_key);
    int get_job_status(int job_id);
    int get_job_result_size(int job_id);
    int get_job_result(int job_id, char* buffer, int max_len);
    void free_job(int job_id);
]]

-- Load DLL
local lib_path = "native/build/Release/earth_native.dll"
local earth_lib = ffi.load(lib_path)

if not earth_lib then
    print("Failed to load DLL: " .. lib_path)
    return
end

-- Parameters
local lat = 48.8566
local lon = 2.3522
local radius = 200
local resolution = 100
local api_key = "test_key" -- Dummy key, downloader handles it

print("Starting async job...")
local job_id = earth_lib.start_download_and_voxelize(lat, lon, radius, resolution, api_key)
print("Job ID: " .. job_id)

-- Poll loop
while true do
    local status = earth_lib.get_job_status(job_id)
    if status == 0 then
        -- Running
        -- print("Job running...")
        -- In a real game, we would yield here. In this script, we sleep or busy wait.
        -- Lua 5.1 doesn't have sleep, so we just busy wait a bit or rely on OS scheduling.
    elseif status == 1 then
        print("Job done!")
        local size = earth_lib.get_job_result_size(job_id)
        print("Result size: " .. size)
        
        if size > 0 then
            local buf = ffi.new("char[?]", size)
            local copied = earth_lib.get_job_result(job_id, buf, size)
            print("Copied bytes: " .. copied)
            
            -- Verify some data
            local voxel_bytes = ffi.string(buf, copied)
            print("Received " .. #voxel_bytes .. " bytes.")
            
            -- Basic parsing check
            local function read_int32_le(str, offset)
                local b1, b2, b3, b4 = string.byte(str, offset, offset + 3)
                local n = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
                if n > 2147483647 then n = n - 4294967296 end
                return n
            end

            if #voxel_bytes >= 16 then
                local x = read_int32_le(voxel_bytes, 1)
                local y = read_int32_le(voxel_bytes, 5)
                local z = read_int32_le(voxel_bytes, 9)
                local r = string.byte(voxel_bytes, 13)
                local g = string.byte(voxel_bytes, 14)
                local b = string.byte(voxel_bytes, 15)
                print("Sample voxel: x=" .. x .. " y=" .. y .. " z=" .. z .. " r=" .. r .. " g=" .. g .. " b=" .. b)
            end
        else
            print("Job finished but returned no data.")
        end
        
        earth_lib.free_job(job_id)
        break
    else
        print("Job failed with status: " .. status)
        earth_lib.free_job(job_id)
        break
    end
end

print("Done.")