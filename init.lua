-- Luanti Earth Mod
-- Loads voxelized Google Earth 3D tiles

local modpath = minetest.get_modpath("luanti_earth")

-- Load voxel importer
local voxel_importer = dofile(modpath .. "/voxel_importer.lua")

luanti_earth = {
    voxel_importer = voxel_importer,
    path = modpath,
    use_pure_colors = false -- Default to false
}

minetest.log("action", "[luanti_earth] Voxel-based mod loaded")

-- Load colors
local colors = dofile(modpath .. "/colors.lua")

-- Register pure color nodes
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

-- Chat command to toggle pure color mode
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

-- Chat command to load voxel data
minetest.register_chatcommand("earth_load_voxels", {
    params = "<voxel_json_path>",
    description = "Load and place voxelized tile data from a JSON file",
    privs = {server = true},
    func = function(name, param)
        if param == "" then
            return false, "Usage: /earth_load_voxels <path_to_voxel_json>"
        end
        
        minetest.chat_send_player(name, "Loading voxel data from: " .. param)
        
        -- Load voxel data
        local voxel_data, err = voxel_importer.load_voxel_file(param)
        if not voxel_data then
            return false, "Failed to load: " .. (err or "unknown error")
        end
        
        minetest.chat_send_player(name, string.format("Loaded %d voxels. Placing...", voxel_data.voxelCount or 0))
        
        -- Get player position as offset
        local player = minetest.get_player_by_name(name)
        local pos = player:get_pos()
        
        -- Place voxels with color mapping
        local placed = voxel_importer.place_voxels(voxel_data, pos, true)
        
        minetest.chat_send_player(name, string.format("Placed %d blocks!", placed))
        
        return true
    end
})

-- Chat command to export voxels for visualization
minetest.register_chatcommand("earth_export_viz", {
    params = "<input_json> <output_json>",
    description = "Export voxel data to simplified format for web visualizer",
    privs = {server = true},
    func = function(name, param)
        local input_path, output_path = string.match(param, "^(%S+)%s+(%S+)$")
        
        if not input_path or not output_path then
            return false, "Usage: /earth_export_viz <input_json> <output_json>"
        end
        
        -- Load voxel data  
        local voxel_data, err = voxel_importer.load_voxel_file(input_path)
        if not voxel_data then
            return false, "Failed to load: " .. (err or "unknown error")
        end
        
        -- Export for viz
        local success, err_msg = voxel_importer.export_for_viz(voxel_data, output_path)
        if not success then
            return false, "Export failed: " .. (err_msg or "unknown error")
        end
        
        return true, "Exported to: " .. output_path
    end
})
