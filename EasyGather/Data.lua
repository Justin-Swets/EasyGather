local _, ns = ...

-- [node name as shown on the minimap / in the world] =
--   { prof = profession, skill = required skill, item = itemID of the main drop, itemName = AH search name }
local NODES = {}
ns.NODES = NODES

local function M(node, skill, item, itemName)
    NODES[node] = { prof = "Mining", skill = skill, item = item, itemName = itemName }
end

local function H(node, skill, item)
    NODES[node] = { prof = "Herbalism", skill = skill, item = item, itemName = node }
end

-- Mining -------------------------------------------------------------------
M("Copper Vein",                     1,   2770,  "Copper Ore")
M("Tin Vein",                        65,  2771,  "Tin Ore")
M("Incendicite Mineral Vein",        65,  3340,  "Incendicite Ore")
M("Silver Vein",                     75,  2775,  "Silver Ore")
M("Ooze Covered Silver Vein",        75,  2775,  "Silver Ore")
M("Lesser Bloodstone Deposit",       75,  4278,  "Lesser Bloodstone Ore")
M("Iron Deposit",                    125, 2772,  "Iron Ore")
M("Indurium Mineral Vein",           150, 5833,  "Indurium Ore")
M("Gold Vein",                       155, 2776,  "Gold Ore")
M("Ooze Covered Gold Vein",          155, 2776,  "Gold Ore")
M("Mithril Deposit",                 175, 3858,  "Mithril Ore")
M("Ooze Covered Mithril Deposit",    175, 3858,  "Mithril Ore")
M("Truesilver Deposit",              230, 7911,  "Truesilver Ore")
M("Ooze Covered Truesilver Deposit", 230, 7911,  "Truesilver Ore")
M("Dark Iron Deposit",               230, 11370, "Dark Iron Ore")
M("Small Thorium Vein",              245, 10620, "Thorium Ore")
M("Ooze Covered Thorium Vein",       245, 10620, "Thorium Ore")
M("Rich Thorium Vein",               275, 10620, "Thorium Ore")
M("Ooze Covered Rich Thorium Vein",  275, 10620, "Thorium Ore")
M("Hakkari Thorium Vein",            275, 10620, "Thorium Ore")
M("Small Obsidian Chunk",            305, 22202, "Small Obsidian Shard")
M("Large Obsidian Chunk",            305, 22203, "Large Obsidian Shard")

-- Herbalism ----------------------------------------------------------------
H("Peacebloom",          1,   2447)
H("Silverleaf",          1,   765)
H("Earthroot",           15,  2449)
H("Mageroyal",           50,  785)
H("Briarthorn",          70,  2450)
H("Stranglekelp",        85,  3820)
H("Bruiseweed",          100, 2453)
H("Wild Steelbloom",     115, 3355)
H("Grave Moss",          120, 3369)
H("Kingsblood",          125, 3356)
H("Liferoot",            150, 3357)
H("Fadeleaf",            160, 3818)
H("Goldthorn",           170, 3821)
H("Khadgar's Whisker",   185, 3358)
H("Wintersbite",         195, 3819)
H("Firebloom",           205, 4625)
H("Purple Lotus",        210, 8831)
H("Arthas' Tears",       220, 8836)
H("Sungrass",            230, 8838)
H("Blindweed",           235, 8839)
H("Ghost Mushroom",      245, 8845)
H("Gromsblood",          250, 8846)
H("Golden Sansam",       260, 13464)
H("Dreamfoil",           270, 13463)
H("Mountain Silversage", 280, 13465)
H("Plaguebloom",         285, 13466)
H("Icecap",              290, 13467)
H("Black Lotus",         300, 13468)
H("Bloodvine",           300, 19726)

-- Reverse lookups used by the AH scanner.
ns.ITEMS = {}   -- [itemID] = itemName
for _, info in pairs(NODES) do
    ns.ITEMS[info.item] = info.itemName
end
