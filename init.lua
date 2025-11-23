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

        minetest.chat_send_player(name, "Geocoding '" .. param .. "'...")
        send_progress(name, 5, "Geocoding location...")

        -- 1. Geocode
        local url = "https://maps.googleapis.com/maps/api/geocode/json?address=" ..
                    minetest.urlencode(param) .. "&key=" .. api_key

        http.fetch({url = url, timeout = 10}, function(res)
            if not res.succeeded then
                minetest.chat_send_player(name, "Geocoding failed: Request failed")
                send_progress(name, 0, "Geocoding failed")
                return
            end

            local data = minetest.parse_json(res.data)
            if not data or not data.results or #data.results == 0 then
                minetest.chat_send_player(name, "Geocoding failed: Location not found")
                send_progress(name, 0, "Location not found")
                return
            end

            local loc = data.results[1].geometry.location
            local lat, lng = loc.lat, loc.lng
            minetest.chat_send_player(name, "Found: " .. lat .. ", " .. lng)
            send_progress(name, 10, "Location resolved")

            --------------------------------------------------
            -- 2. Prepare directories (in world folder)
            --------------------------------------------------
            local location_name = get_safe_filename(param)
            local cache_dir = cache_root .. "/" .. location_name
            local glb_dir   = cache_dir .. "/glb"
            local json_dir  = cache_dir .. "/json"

            -- Use Luanti's mkdir (recursive) – safe in world dir
            minetest.mkdir(cache_dir)
            minetest.mkdir(glb_dir)
            minetest.mkdir(json_dir)

            --------------------------------------------------
            -- Ensure we have permission to run external commands
            --------------------------------------------------
            if not os_execute then
                minetest.chat_send_player(name,
                    "Server not configured to allow external commands.\n" ..
                    "Add luanti_earth to secure.trusted_mods and restart.")
                send_progress(name, 0, "Missing insecure environment")
                return
            end

            --------------------------------------------------
            -- 3. Download Tiles (Node.js)
            --------------------------------------------------
            minetest.chat_send_player(name, "Downloading 3D Tiles... (this can take a bit)")
            send_progress(name, 25, "Downloading 3D Tiles...")

            local node_cmd_dl = string.format(
                'node "%s/tile_downloader.js" --key "%s" --lat %f --lng %f --radius 200 --out "%s"',
                modpath, api_key, lat, lng, glb_dir
            )

            local ret_dl = os_execute(node_cmd_dl)
            if ret_dl ~= 0 and ret_dl ~= true then
                minetest.chat_send_player(name,
                    "Download failed. Make sure you ran 'npm install' in the Voxel Earth mod folder.")
                send_progress(name, 0, "Download failed")
                return
            end

            send_progress(name, 50, "Download complete")

            --------------------------------------------------
            -- 4. Voxelize (Node.js)
            --------------------------------------------------
            minetest.chat_send_player(name, "Voxelizing tiles...")
            send_progress(name, 60, "Voxelizing tiles...")

            local node_cmd_vox = string.format(
                'node "%s/voxelize_tiles.js" "%s" "%s" 100',
                modpath, glb_dir, json_dir
            )

            local ret_vox = os_execute(node_cmd_vox)
            if ret_vox ~= 0 and ret_vox ~= true then
                minetest.chat_send_player(name,
                    "Voxelization failed.")
                send_progress(name, 0, "Voxelization failed")
                return
            end

            send_progress(name, 80, "Voxelization complete")

            --------------------------------------------------
            -- 5. Import into the world
            --------------------------------------------------
            minetest.chat_send_player(name, "Importing voxels into the world...")
            send_progress(name, 90, "Importing voxels...")

            -- Pick a random location **far away** to avoid overlapping visits
            local spawn_pos = {
                x = math.random(-RANDOM_SPAWN_RANGE, RANDOM_SPAWN_RANGE),
                y = 50,
                z = math.random(-RANDOM_SPAWN_RANGE, RANDOM_SPAWN_RANGE),
            }

            -- Import from JSON dir; true = use_color / pure mode auto-detect
            local count = voxel_importer.import_from_directory(json_dir, spawn_pos, true)

            minetest.chat_send_player(name, "Imported " .. count .. " blocks at (" ..
                spawn_pos.x .. ", " .. spawn_pos.y .. ", " .. spawn_pos.z .. ").")
            send_progress(name, 100, "Done")

            -- Teleport player slightly above the structure
            player:set_pos({x = spawn_pos.x, y = spawn_pos.y + 20, z = spawn_pos.z})
            minetest.chat_send_player(name, "Teleported to " .. param)
        end)
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
