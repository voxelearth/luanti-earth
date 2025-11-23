-- test_color_matching.lua
-- Standalone script to verify color matching logic

-- Mock minetest environment
minetest = {
    registered_nodes = {
        ["default:stone"] = true,
        ["default:cobble"] = true,
        ["default:stonebrick"] = true,
        ["default:dirt"] = true,
        ["default:dirt_with_grass"] = true,
        ["default:sand"] = true,
        ["default:desert_sand"] = true,
        ["default:sandstone"] = true,
        ["default:desert_stone"] = true,
        ["default:gravel"] = true,
        ["default:clay"] = true,
        ["default:snow"] = true,
        ["default:snowblock"] = true,
        ["default:ice"] = true,
        ["default:water_source"] = true,
        ["default:lava_source"] = true,
        ["default:obsidian"] = true,
        ["default:glass"] = true,
        ["default:leaves"] = true,
        ["default:jungleleaves"] = true,
        ["default:pine_needles"] = true,
        ["default:acacia_leaves"] = true,
        ["default:wood"] = true,
        ["default:junglewood"] = true,
        ["default:pine_wood"] = true,
        ["default:acacia_wood"] = true,
        ["default:brick"] = true,
        ["wool:white"] = true,
        ["wool:grey"] = true,
        ["wool:dark_grey"] = true,
        ["wool:black"] = true,
        ["wool:red"] = true,
        ["wool:green"] = true,
        ["wool:blue"] = true,
        ["wool:yellow"] = true,
        ["wool:cyan"] = true,
        ["wool:magenta"] = true,
        ["wool:orange"] = true,
        ["wool:violet"] = true,
        ["wool:brown"] = true,
        ["wool:pink"] = true,
        -- Mineclonia mocks
        ["mcl_color:concrete_white"] = true,
        ["mcl_color:concrete_red"] = true,
        ["mcl_color:concrete_green"] = true,
        ["mcl_color:concrete_blue"] = true,
        ["mcl_color:concrete_silver"] = true,
        ["mcl_color:concrete_lime"] = true,
        ["mcl_core:stone"] = true,
        ["mcl_core:dirt"] = true,
        ["mcl_core:grass_block_green"] = true,
        ["mcl_core:snow"] = true,
    },
    log = function(level, msg) print("["..level.."] "..msg) end
}

-- Mock global luanti_earth object
luanti_earth = { use_pure_colors = false }

-- Load the importer
local voxel_importer = require("voxel_importer")

-- Test cases
local test_colors = {
    {r=128, g=128, b=128, expected="default:stone"},
    {r=255, g=0,   b=0,   expected="wool:red"},
    {r=0,   g=255, b=0,   expected="wool:green"},
    {r=0,   g=0,   b=255, expected="wool:blue"},
    {r=100, g=150, b=50,  expected="default:dirt_with_grass"},
    {r=235, g=220, b=170, expected="default:sandstone"},
    {r=20,  g=20,  b=20,  expected="default:obsidian"},
    {r=255, g=255, b=255, expected="wool:white"},
}

print("Running Color Matching Tests (Natural Mode)...")
print("--------------------------------")

for _, tc in ipairs(test_colors) do
    local result = voxel_importer.rgb_to_block(tc.r, tc.g, tc.b)
    print(string.format("RGB(%3d, %3d, %3d) -> %-25s (Expected ~ %s)", 
        tc.r, tc.g, tc.b, result, tc.expected))
end

print("\nRunning Color Matching Tests (Pure Color Mode)...")
print("--------------------------------")
luanti_earth.use_pure_colors = true

local pure_tests = {
    {r=128, g=128, b=128, expected="mcl_color:concrete_silver"}, -- or wool:grey
    {r=200, g=0,   b=0,   expected="mcl_color:concrete_red"},
    {r=100, g=150, b=50,  expected="mcl_color:concrete_green"}, -- Should NOT be dirt/grass
}

for _, tc in ipairs(pure_tests) do
    local result = voxel_importer.rgb_to_block(tc.r, tc.g, tc.b)
    print(string.format("RGB(%3d, %3d, %3d) -> %-25s (Expected ~ %s)", 
        tc.r, tc.g, tc.b, result, tc.expected))
end

print("--------------------------------")
print("Done.")
