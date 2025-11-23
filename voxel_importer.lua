-- voxel_importer.lua
-- Reads voxel JSON files and provides functions to place blocks in Luanti

local voxel_importer = {}

-- Helper: resolve a node name to something that actually exists
local function get_safe_node(name)
    -- Use it if it exists
    if minetest and minetest.registered_nodes and minetest.registered_nodes[name] then
        return name
    end

    -- Log once so we notice bad mappings
    if minetest and minetest.log then
        minetest.log("warning",
            "[luanti_earth] Unknown node '" .. tostring(name) .. "', falling back to default:stone")
    end

    -- Prefer default:stone if available
    if minetest and minetest.registered_nodes and minetest.registered_nodes["default:stone"] then
        return "default:stone"
    end

    -- Last resort: pick any non-air node so we don't crash
    if minetest and minetest.registered_nodes then
        for nodename, _ in pairs(minetest.registered_nodes) do
            if nodename ~= "air" then
                if minetest and minetest.log then
                    minetest.log("warning",
                        "[luanti_earth] Using fallback node '" .. nodename .. "'")
                end
                return nodename
            end
        end
    end

    -- Absolutely nothing? Place air instead of exploding
    return "air"
end

-- Simple JSON parser (supports basic structures)
local function parse_json(str)
    -- Remove whitespace
    str = str:gsub("%s+", "")

    -- Try to use minetest.parse_json if available
    if minetest and minetest.parse_json then
        return minetest.parse_json(str)
    end

    -- Fallback: very basic parser for our specific format
    -- This is a simplified parser - for production, use a proper JSON library
    error("JSON parsing not available. Use minetest.parse_json or external library.")
end

-- Load voxel data from a JSON file
function voxel_importer.load_voxel_file(filepath)
    local file = io.open(filepath, "r")
    if not file then
        return nil, "Could not open file: " .. filepath
    end

    local content = file:read("*a")
    file:close()

    local success, data = pcall(parse_json, content)
    if not success then
        return nil, "JSON parse error: " .. tostring(data)
    end

    return data
end

-- Convert RGB to closest Luanti block type
-- This is a simple mapping - expand based on available blocks
function voxel_importer.rgb_to_block(r, g, b)
    local r_norm = r / 255
    local g_norm = g / 255
    local b_norm = b / 255

    -- Calculate luminance
    local lum = 0.299 * r_norm + 0.587 * g_norm + 0.114 * b_norm

    -- Simple color mapping to common blocks
    if lum < 0.2 then
        return get_safe_node("default:obsidian")
    elseif lum < 0.4 then
        return get_safe_node("default:stone")
    elseif lum > 0.8 then
        if r_norm > g_norm and r_norm > b_norm then
            return get_safe_node("default:brick")         -- Reddish bright
        elseif g_norm > r_norm then
            return get_safe_node("default:mossycobble")   -- Greenish
        else
            return get_safe_node("default:desert_stone")  -- Yellowish
        end
    else
        -- Mid-tone: use color bias
        if r_norm > g_norm and r_norm > b_norm then
            return get_safe_node("default:brick")
        elseif b_norm > r_norm and b_norm > g_norm then
            return get_safe_node("default:cobble")        -- Blueish/gray
        elseif g_norm > r_norm then
            return get_safe_node("default:dirt_with_grass")
        else
            return get_safe_node("default:dirt")
        end
    end
end

-- Place voxels in the world at a given offset
function voxel_importer.place_voxels(voxel_data, offset_pos, use_color)
    if not voxel_data or not voxel_data.voxels then
        return 0, "Invalid voxel data"
    end

    local placed = 0
    local offset = offset_pos or {x=0, y=0, z=0}

    for _, voxel in ipairs(voxel_data.voxels) do
        local pos = {
            x = offset.x + math.floor(voxel.x),
            y = offset.y + math.floor(voxel.y),
            z = offset.z + math.floor(voxel.z)
        }

        local block_name
        if use_color and voxel.r and voxel.g and voxel.b then
            block_name = voxel_importer.rgb_to_block(voxel.r, voxel.g, voxel.b)
        else
            block_name = get_safe_node("default:stone")
        end

        -- Place block with safety net again just in case
        local final_name = get_safe_node(block_name)
        minetest.set_node(pos, { name = final_name })
        placed = placed + 1
    end

    return placed
end

-- Export voxel data to a simpler format for visualization
function voxel_importer.export_for_viz(voxel_data, output_path)
    if not voxel_data or not voxel_data.voxels then
        return false, "Invalid voxel data"
    end

    local blocks = {}
    for _, voxel in ipairs(voxel_data.voxels) do
        table.insert(blocks, {
            x = voxel.x,
            y = voxel.y,
            z = voxel.z,
            r = voxel.r or 128,
            g = voxel.g or 128,
            b = voxel.b or 128
        })
    end

    -- Simple JSON serialization
    local json_str = "[\n"
    for i, b in ipairs(blocks) do
        json_str = json_str .. string.format(
            '  {"x":%d, "y":%d, "z":%d, "r":%d, "g":%d, "b":%d}',
            b.x, b.y, b.z, b.r, b.g, b.b
        )
        if i < #blocks then
            json_str = json_str .. ","
        end
        json_str = json_str .. "\n"
    end
    json_str = json_str .. "]"

    local file = io.open(output_path, "w")
    if not file then
        return false, "Could not open output file"
    end
    file:write(json_str)
    file:close()

    return true
end

return voxel_importer
