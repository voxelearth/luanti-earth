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

-- Palette of blocks with their average RGB values
-- Priority: Mineclonia (mcl_*) > Minetest Game (default, wool)
-- Strict filtering: Full, solid blocks only. No falling blocks (sand, gravel).
local BLOCK_PALETTE = {
    -- === Mineclonia: Colored Blocks (High Priority for Pure Color Mode) ===
    {name="mcl_color:concrete_white",      r=207, g=213, b=214, pure=true},
    {name="mcl_color:concrete_orange",     r=224, g=97,  b=0,   pure=true},
    {name="mcl_color:concrete_magenta",    r=169, g=48,  b=159, pure=true},
    {name="mcl_color:concrete_light_blue", r=35,  g=137, b=198, pure=true},
    {name="mcl_color:concrete_yellow",     r=240, g=175, b=21,  pure=true},
    {name="mcl_color:concrete_lime",       r=94,  g=168, b=24,  pure=true},
    {name="mcl_color:concrete_pink",       r=213, g=101, b=142, pure=true},
    {name="mcl_color:concrete_gray",       r=54,  g=57,  b=61,  pure=true},
    {name="mcl_color:concrete_silver",     r=125, g=125, b=115, pure=true},
    {name="mcl_color:concrete_cyan",       r=21,  g=119, b=136, pure=true},
    {name="mcl_color:concrete_purple",     r=100, g=31,  b=156, pure=true},
    {name="mcl_color:concrete_blue",       r=44,  g=46,  b=143, pure=true},
    {name="mcl_color:concrete_brown",      r=96,  g=59,  b=31,  pure=true},
    {name="mcl_color:concrete_green",      r=73,  g=91,  b=36,  pure=true},
    {name="mcl_color:concrete_red",        r=142, g=32,  b=32,  pure=true},
    {name="mcl_color:concrete_black",      r=8,   g=10,  b=15,  pure=true},

    {name="mcl_wool:white",                r=233, g=236, b=236, pure=true},
    {name="mcl_wool:orange",               r=240, g=118, b=19,  pure=true},
    {name="mcl_wool:magenta",              r=189, g=68,  b=179, pure=true},
    {name="mcl_wool:light_blue",           r=58,  g=175, b=217, pure=true},
    {name="mcl_wool:yellow",               r=248, g=197, b=39,  pure=true},
    {name="mcl_wool:lime",                 r=112, g=185, b=25,  pure=true},
    {name="mcl_wool:pink",                 r=237, g=141, b=172, pure=true},
    {name="mcl_wool:gray",                 r=62,  g=68,  b=71,  pure=true},
    {name="mcl_wool:silver",               r=142, g=142, b=134, pure=true},
    {name="mcl_wool:cyan",                 r=21,  g=137, b=145, pure=true},
    {name="mcl_wool:purple",               r=121, g=42,  b=172, pure=true},
    {name="mcl_wool:blue",                 r=53,  g=57,  b=157, pure=true},
    {name="mcl_wool:brown",                r=114, g=71,  b=40,  pure=true},
    {name="mcl_wool:green",                r=84,  g=109, b=27,  pure=true},
    {name="mcl_wool:red",                  r=160, g=39,  b=34,  pure=true},
    {name="mcl_wool:black",                r=20,  g=21,  b=25,  pure=true},

    -- === Mineclonia: Natural Blocks ===
    {name="mcl_core:stone",                r=125, g=125, b=125},
    {name="mcl_core:cobble",               r=100, g=100, b=100},
    {name="mcl_core:stonebrick",           r=110, g=110, b=110},
    {name="mcl_core:andesite",             r=115, g=115, b=115},
    {name="mcl_core:diorite",              r=180, g=180, b=180},
    {name="mcl_core:granite",              r=150, g=110, b=100},
    {name="mcl_core:dirt",                 r=134, g=96,  b=67},
    {name="mcl_core:coarse_dirt",          r=119, g=85,  b=59},
    {name="mcl_core:podzol",               r=90,  g=63,  b=42},
    {name="mcl_core:grass_block_green",    r=100, g=150, b=50}, -- Approximate
    {name="mcl_core:mycelium",             r=110, g=100, b=110},
    {name="mcl_core:clay",                 r=160, g=165, b=178},
    {name="mcl_core:sandstone",            r=216, g=203, b=155},
    {name="mcl_core:red_sandstone",        r=176, g=86,  b=35},
    {name="mcl_core:obsidian",             r=20,  g=18,  b=29},
    {name="mcl_core:bedrock",              r=50,  g=50,  b=50},
    {name="mcl_core:snow",                 r=249, g=254, b=254}, -- Snow block
    {name="mcl_core:ice",                  r=160, g=190, b=255},
    {name="mcl_core:packed_ice",           r=170, g=200, b=255},
    {name="mcl_core:blue_ice",             r=180, g=210, b=255},
    {name="mcl_core:prismarine",           r=99,  g=156, b=157},
    {name="mcl_core:prismarine_bricks",    r=99,  g=171, b=164},
    {name="mcl_core:dark_prismarine",      r=51,  g=91,  b=75},
    {name="mcl_deepslate:deepslate",       r=80,  g=80,  b=80},
    {name="mcl_deepslate:cobbled_deepslate",r=70, g=70,  b=70},
    {name="mcl_nether:netherrack",         r=110, g=50,  b=50},
    {name="mcl_nether:nether_bricks",      r=44,  g=21,  b=26},
    {name="mcl_nether:red_nether_bricks",  r=69,  g=7,   b=9},
    {name="mcl_nether:basalt",             r=80,  g=80,  b=85},
    {name="mcl_nether:blackstone",         r=40,  g=35,  b=40},
    {name="mcl_end:end_stone",             r=222, g=222, b=175},
    {name="mcl_end:end_bricks",            r=220, g=225, b=180},
    {name="mcl_end:purpur_block",          r=169, g=125, b=169},

    -- === Minetest Game: Colored Blocks (Fallback/Pure) ===
    {name="wool:white",              r=230, g=230, b=230, pure=true},
    {name="wool:grey",               r=100, g=100, b=100, pure=true},
    {name="wool:dark_grey",          r=50,  g=50,  b=50,  pure=true},
    {name="wool:black",              r=20,  g=20,  b=20,  pure=true},
    {name="wool:red",                r=200, g=0,   b=0,   pure=true},
    {name="wool:green",              r=0,   g=200, b=0,   pure=true},
    {name="wool:blue",               r=0,   g=0,   b=200, pure=true},
    {name="wool:yellow",             r=255, g=255, b=0,   pure=true},
    {name="wool:cyan",               r=0,   g=255, b=255, pure=true},
    {name="wool:magenta",            r=255, g=0,   b=255, pure=true},
    {name="wool:orange",             r=255, g=128, b=0,   pure=true},
    {name="wool:violet",             r=128, g=0,   b=255, pure=true},
    {name="wool:brown",              r=100, g=50,  b=0,   pure=true},
    {name="wool:pink",               r=255, g=150, b=150, pure=true},

    -- === Minetest Game: Natural Blocks ===
    {name="default:stone",           r=128, g=128, b=128},
    {name="default:cobble",          r=100, g=100, b=100},
    {name="default:stonebrick",      r=110, g=110, b=110},
    {name="default:dirt",            r=92,  g=64,  b=51},
    {name="default:dirt_with_grass", r=100, g=150, b=50},
    {name="default:sandstone",       r=235, g=220, b=170},
    {name="default:desert_stone",    r=200, g=100, b=50},
    {name="default:clay",            r=150, g=150, b=160},
    {name="default:snowblock",       r=240, g=240, b=240},
    {name="default:ice",             r=150, g=200, b=255},
    {name="default:obsidian",        r=20,  g=20,  b=20},
    {name="default:glass",           r=200, g=220, b=255},
    {name="default:leaves",          r=50,  g=100, b=50},
    {name="default:jungleleaves",    r=30,  g=80,  b=30},
    {name="default:pine_needles",    r=40,  g=70,  b=40},
    {name="default:acacia_leaves",   r=80,  g=120, b=40},
    {name="default:wood",            r=150, g=100, b=50},
    {name="default:junglewood",      r=100, g=50,  b=30},
    {name="default:pine_wood",       r=120, g=80,  b=40},
    {name="default:acacia_wood",     r=180, g=50,  b=30},
    {name="default:brick",           r=150, g=50,  b=50},
}

-- Load colors for pure mode
local colors = dofile(minetest.get_modpath("luanti_earth") .. "/colors.lua")
local color_cache = {}

-- Helper to parse hex to RGB
local function hex_to_rgb(hex)
    hex = hex:gsub("#","")
    return tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
end

-- Pre-calculate RGB values for palette
local PURE_PALETTE = {}
for id, hex in pairs(colors) do
    local r, g, b = hex_to_rgb(hex)
    table.insert(PURE_PALETTE, {id=id, r=r, g=g, b=b})
end

-- Convert RGB to closest Luanti block type using Euclidean distance
function voxel_importer.rgb_to_block(r, g, b)
    -- Check pure color mode setting
    local use_pure = false
    if luanti_earth and luanti_earth.use_pure_colors then
        use_pure = true
    end

    if use_pure then
        -- Pure Color Mode: Match against generated color nodes
        local min_dist = math.huge
        local best_id = "0"

        for _, col in ipairs(PURE_PALETTE) do
            local dr = r - col.r
            local dg = g - col.g
            local db = b - col.b
            local dist_sq = dr*dr + dg*dg + db*db

            if dist_sq < min_dist then
                min_dist = dist_sq
                best_id = col.id
            end
        end
        return "luanti_earth:color_" .. best_id
    else
        -- Natural Mode: Match against existing blocks
        local min_dist = math.huge
        local best_block = "default:stone" -- Fallback

        for _, block in ipairs(BLOCK_PALETTE) do
            -- Skip pure-only blocks in natural mode (if any were marked pure-only, but we removed that flag usage)
            -- Actually, we can just use the full palette now.
            
            local dr = r - block.r
            local dg = g - block.g
            local db = b - block.b
            local dist_sq = dr*dr + dg*dg + db*db

            if dist_sq < min_dist then
                min_dist = dist_sq
                best_block = block.name
            end
        end
        return get_safe_node(best_block)
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
