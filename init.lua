-- Luanti Earth Mod
-- Loads voxelized Google Earth 3D tiles

--------------------------------------------------
-- Mod name / paths
--------------------------------------------------

local modname   = minetest.get_current_modname()
local modpath   = minetest.get_modpath(modname)
local worldpath = minetest.get_worldpath()

-- All cache / downloaded data goes into the world folder,
-- not into mods/, to satisfy Luanti security.
local cache_root = worldpath .. "/luanti_earth_cache"

-- Ensure root cache dir exists
minetest.mkdir(cache_root)

-- Seed RNG once so /visit spawn positions are different each time
math.randomseed(os.time())

-- Keep random within a safe chunk of the map (Minetest map limit is ~±30927)
local RANDOM_SPAWN_RANGE = 20000

--------------------------------------------------
-- HTTP API (needs secure.http_mods = luanti_earth)
--------------------------------------------------

local http = minetest.request_http_api and minetest.request_http_api()
if not http then
    minetest.log("warning",
        "[" .. modname .. "] HTTP API unavailable. " ..
        "Is " .. modname .. " in secure.http_mods?")
end

--------------------------------------------------
-- Insecure environment for external commands
-- (needs secure.trusted_mods = luanti_earth)
--------------------------------------------------

local insecure_env = minetest.request_insecure_environment
                     and minetest.request_insecure_environment()

local os_execute = insecure_env and insecure_env.os
                   and insecure_env.os.execute

if not os_execute then
    minetest.log("warning",
        "[" .. modname .. "] No insecure os.execute available. " ..
        "Add " .. modname .. " to secure.trusted_mods to enable Node.js calls.")
end

--------------------------------------------------
-- Load voxel importer
--------------------------------------------------

local voxel_importer = dofile(modpath .. "/voxel_importer.lua")

luanti_earth = {
    voxel_importer = voxel_importer,
    path = modpath,
    use_pure_colors = true -- Default to true for pretty custom blocks
}

minetest.log("action", "[luanti_earth] Voxel-based mod loaded")

--------------------------------------------------
-- Load colors and register pure color nodes
--------------------------------------------------

local colors = dofile(modpath .. "/colors.lua")

for i = 0, 255 do
    local hex = colors[tostring(i)]
    if hex then
        minetest.register_node("luanti_earth:color_" .. i, {
            description = "Pure Color " .. i .. " (" .. hex .. ")",
            tiles = {"default_stone.png^[colorize:" .. hex .. ":255"},
            groups = {cracky = 3, oddly_breakable_by_hand = 3},
            is_ground_content = false,
        })
    end
end

--------------------------------------------------
-- Progress bar helper
--------------------------------------------------

local function make_progress_bar(pct, width)
    width = width or 20
    if pct < 0 then pct = 0 end
    if pct > 100 then pct = 100 end
    local filled = math.floor((pct / 100) * width + 0.5)
    local bar = string.rep("#", filled) .. string.rep(".", width - filled)
    return "[" .. bar .. "] " .. pct .. "%"
end

local function send_progress(name, pct, stage)
    minetest.chat_send_player(name, make_progress_bar(pct) .. " " .. stage)
end

--------------------------------------------------
-- Chat command to toggle pure color mode
--------------------------------------------------

minetest.register_chatcommand("earth_use_pure_colors", {
    params = "<true/false>",
    description = "Toggle pure color mode (prioritizes solid colored blocks)",
    privs = {server = true},
    func = function(name, param)
        if param == "true" then
            luanti_earth.use_pure_colors = true
            minetest.chat_send_player(name, "Pure color mode ENABLED. Future imports will prioritize solid colored blocks.")
        elseif param == "false" then
            luanti_earth.use_pure_colors = false
            minetest.chat_send_player(name, "Pure color mode DISABLED. Future imports will use natural blocks.")
        else
            return false, "Usage: /earth_use_pure_colors <true/false>"
        end
        return true
    end
})

--------------------------------------------------
-- API key storage & commands
--------------------------------------------------

local storage = minetest.get_mod_storage()

minetest.register_chatcommand("earth_apikey", {
    params = "<key>",
    description = "Set Google API Key for 3D Tiles",
    privs = {server = true},
    func = function(name, param)
        if not param or param == "" then
            return false, "Usage: /earth_apikey <key>"
        end
        storage:set_string("google_api_key", param)
        return true, "API Key saved."
    end
})

--------------------------------------------------
-- Helper to get safe filename
--------------------------------------------------

local function get_safe_filename(str)
    return str:gsub("[^%w%-_]", "_")
end

--------------------------------------------------
-- /visit command: geocode + download + voxelize + import
--------------------------------------------------

minetest.register_chatcommand("visit", {
    params = "<location>",
    description = "Teleport to a real-world location (e.g. /visit Paris)",
    privs = {server = true, teleport = true},
    func = function(name, param)
        if not param or param == "" then
            return false, "Usage: /visit <location>"
        end

        local api_key = storage:get_string("google_api_key")
        if not api_key or api_key == "" then
            return false, "API Key not set. Use /earth_apikey <key> first."
        end

        local player = minetest.get_player_by_name(name)
        if not player then
            return false, "Player not found"
        end

        if not http then
            return false,
                "HTTP API unavailable. Add luanti_earth to secure.http_mods and restart the server."
        end

        -- Add mod path to package.cpath to find the DLL
        package.cpath = package.cpath .. ";" .. modpath .. "/?.dll"
        
        local has_native, earth_native = pcall(require, "earth_native")
        if not has_native then
            minetest.chat_send_player(name, "Native module not found. Attempting to build...")
            -- Try to build if missing (windows only)
            local build_cmd = '"' .. modpath .. '\\native\\build.bat"'
            os.execute(build_cmd)
            has_native, earth_native = pcall(require, "earth_native")
            if not has_native then
                return false, "Failed to load native module: " .. tostring(earth_native)
            end
        end

        minetest.chat_send_player(name, "Geocoding '" .. param .. "'...")
        send_progress(name, 5, "Geocoding location...")

        -- 1. Geocode
        local url = "https://maps.googleapis.com/maps/api/geocode/json?address=" ..
                    minetest.urlencode(param) .. "&key=" .. api_key

        http.fetch({url = url, timeout = 10}, function(res)
            if not res.succeeded then
                minetest.chat_send_player(name, "Geocoding failed: Request failed")
                return
            end

            local data = minetest.parse_json(res.data)
            if not data or not data.results or #data.results == 0 then
                minetest.chat_send_player(name, "Geocoding failed: Location not found")
                return
            end

            local loc = data.results[1].geometry.location
            local lat, lng = loc.lat, loc.lng
            minetest.chat_send_player(name, "Found: " .. lat .. ", " .. lng)
            send_progress(name, 10, "Location resolved")

            --------------------------------------------------
            -- 2. Download & Voxelize (Native C++)
            --------------------------------------------------
            minetest.chat_send_player(name, "Downloading and Voxelizing (Native C++)...")
            send_progress(name, 30, "Processing tiles...")

            -- Call native function
            -- args: lat, lon, radius, resolution, api_key
            local voxels = earth_native.download_and_voxelize(lat, lng, 200, 100, api_key)
            
            if not voxels or #voxels == 0 then
                minetest.chat_send_player(name, "No voxels generated.")
                send_progress(name, 0, "Failed")
                return
            end

            send_progress(name, 80, "Processing complete")

            --------------------------------------------------
            -- 3. Import into the world
            --------------------------------------------------
            minetest.chat_send_player(name, "Importing " .. #voxels .. " voxels...")
            send_progress(name, 90, "Importing voxels...")

            local spawn_pos = {
                x = math.random(-RANDOM_SPAWN_RANGE, RANDOM_SPAWN_RANGE),
                y = 50,
                z = math.random(-RANDOM_SPAWN_RANGE, RANDOM_SPAWN_RANGE),
            }

            -- Wrap in expected format
            local voxel_data = { voxels = voxels }
            
            -- Place voxels
            local count = voxel_importer.place_voxels(voxel_data, spawn_pos, true)

            minetest.chat_send_player(name, "Imported " .. count .. " blocks at (" ..
                spawn_pos.x .. ", " .. spawn_pos.y .. ", " .. spawn_pos.z .. ").")
            send_progress(name, 100, "Done")

            player:set_pos({x = spawn_pos.x, y = spawn_pos.y + 20, z = spawn_pos.z})
            minetest.chat_send_player(name, "Teleported to " .. param)
        end)
    end
})
    end
})

--------------------------------------------------
-- /earth_load_voxels: load voxel JSON at player pos
--------------------------------------------------

minetest.register_chatcommand("earth_load_voxels", {
    params = "<voxel_json_path>",
    description = "Load and place voxelized tile data from a JSON file",
    privs = {server = true},
    func = function(name, param)
        if param == "" then
            return false, "Usage: /earth_load_voxels <path_to_voxel_json>"
        end

        minetest.chat_send_player(name, "Loading voxel data from: " .. param)
        send_progress(name, 10, "Loading voxel JSON...")

        -- Load voxel data
        local voxel_data, err = voxel_importer.load_voxel_file(param)
        if not voxel_data then
            send_progress(name, 0, "Load failed")
            return false, "Failed to load: " .. (err or "unknown error")
        end

        minetest.chat_send_player(name,
            string.format("Loaded %d voxels. Placing...", voxel_data.voxelCount or 0))
        send_progress(name, 40, "Placing voxels...")

        -- Get player position as offset
        local player = minetest.get_player_by_name(name)
        if not player then
            send_progress(name, 0, "Player not found")
            return false, "Player not found."
        end

        local pos = player:get_pos()

        -- Place voxels with color mapping
        local placed = voxel_importer.place_voxels(voxel_data, pos, true)

        send_progress(name, 100, "Done")
        minetest.chat_send_player(name,
            string.format("Placed %d blocks!", placed))

        return true
    end
})

--------------------------------------------------
-- /earth_export_viz: export for web visualizer
--------------------------------------------------

minetest.register_chatcommand("earth_export_viz", {
    params = "<input_json> <output_json>",
    description = "Export voxel data to simplified format for web visualizer",
    privs = {server = true},
    func = function(name, param)
        local input_path, output_path = string.match(param, "^(%S+)%s+(%S+)$")

        if not input_path or not output_path then
            return false, "Usage: /earth_export_viz <input_json> <output_json>"
        end

        minetest.chat_send_player(name,
            "Exporting voxel data from " .. input_path .. " to " .. output_path .. "...")
        send_progress(name, 20, "Loading voxel JSON...")

        -- Load voxel data
        local voxel_data, err = voxel_importer.load_voxel_file(input_path)
        if not voxel_data then
            send_progress(name, 0, "Load failed")
            return false, "Failed to load: " .. (err or "unknown error")
        end

        send_progress(name, 60, "Writing export JSON...")

        -- Export for viz
        local success, err_msg = voxel_importer.export_for_viz(voxel_data, output_path)
        if not success then
            send_progress(name, 0, "Export failed")
            return false, "Export failed: " .. (err_msg or "unknown error")
        end

        send_progress(name, 100, "Export complete")
        return true, "Exported to: " .. output_path
    end
})
