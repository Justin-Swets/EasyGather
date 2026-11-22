local ADDON, ns = ...
local NODES, ITEMS = ns.NODES, ns.ITEMS

local db
local skills = {}     -- ["Mining"] = 150
local iconCache = {}
local dirty = true    -- force a minimap pin refresh

local function Print(...) print("|cff33ff99EasyGather|r:", ...) end
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

-- API shims (old globals vs. modern C_ namespaces)
local ItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local Coin = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
local CVar = (C_CVar and C_CVar.GetCVar) or GetCVar

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
-- A plain, readable string, or nil for secret / unusable values.
local function Clear(v)
    if v == nil then return nil end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    if type(v) ~= "string" then return nil end
    if not pcall(function() return v == v end) then return nil end
    return v
end

-- Remove textures, atlases and color codes (old |cAARRGGBB and modern |cnNAME: styles).
local function Strip(s)
    s = s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|cn[^:]*:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (s:match("^%s*(.-)%s*$"))
end

local function Icon(name)
    if iconCache[name] then return iconCache[name] end
    local info = NODES[name]
    local icon = info and ItemIcon and ItemIcon(info.item)
    if icon then iconCache[name] = icon; return icon end
    return (info and info.prof == "Mining") and "Interface\\Icons\\Trade_Mining" or "Interface\\Icons\\INV_Misc_Flower_02"
end

local SKILL_LINE = { [186] = "Mining", [182] = "Herbalism" }

local function UpdateSkills()
    wipe(skills)
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        -- Modern clients (Forever): GetProfessions() -> prof1, prof2, ...
        for _, index in pairs({ GetProfessions() }) do
            local ok, name, _, rank, _, _, _, skillLine = pcall(GetProfessionInfo, index)
            if ok and rank then
                local prof = SKILL_LINE[skillLine] or ((name == "Mining" or name == "Herbalism") and name)
                if prof then skills[prof] = rank end
            end
        end
    elseif type(GetNumSkillLines) == "function" then
        for i = 1, GetNumSkillLines() do
            local name, isHeader, _, rank = GetSkillLineInfo(i)
            if not isHeader and (name == "Mining" or name == "Herbalism") then
                skills[name] = rank
            end
        end
    end
    dirty = true
end

-- red = can't gather, orange/yellow/green = skill-up chance, grey = trivial
local function SkillColor(prof, req)
    local rank = skills[prof]
    if not rank then return "|cff9d9d9d" end
    if rank < req then return "|cffff2020" end
    if rank < req + 25 then return "|cffff8040" end
    if rank < req + 50 then return "|cffffff00" end
    if rank < req + 100 then return "|cff40c040" end
    return "|cff9d9d9d"
end

local function Ago(t)
    local d = time() - t
    if d < 3600 then return math.floor(d / 60) .. "m ago" end
    if d < 86400 then return math.floor(d / 3600) .. "h ago" end
    return math.floor(d / 86400) .. "d ago"
end

-- Copper price for one item (and when we saw it), or nil.
local function PriceValue(info)
    -- Prefer Auctionator's database when it's installed.
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetAuctionPriceByItemID then
        local ok, p = pcall(api.GetAuctionPriceByItemID, ADDON, info.item)
        if ok and p and p > 0 then return p end
    end
    local rec = db and db.prices[info.item]
    if rec then return rec.p, rec.t end
end

local function PriceText(info)
    local p, t = PriceValue(info)
    if not p then return "|cff9d9d9dno AH data|r" end
    return Coin(p) .. (t and (" |cff9d9d9d(" .. Ago(t) .. ")|r") or "")
end

local function CanGather(info)
    local rank = info and skills[info.prof]
    return rank ~= nil and rank >= info.skill
end

-------------------------------------------------------------------------------
-- Scarce drops: anything a node gives besides its main item, not counting the
-- common stones (gems, elemental earth, Black Vitriol, Swiftthistle, Wildvine...)
-------------------------------------------------------------------------------
local STONES = { [2835] = true, [2836] = true, [2838] = true, [7912] = true, [12365] = true }

local function IsScarce(nodeName, itemID)
    local info = NODES[nodeName]
    return info and itemID ~= info.item and not STONES[itemID]
end

local function ItemName(itemID)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    if not name and GetItemInfo then name = GetItemInfo(itemID) end
    return Clear(name) or ("item " .. itemID)
end

-- "12% (3 of 25)" for a node type, or nil before the first gather.
local function ScarceText(nodeName)
    local r = db and db.scarce and db.scarce[nodeName]
    if not r or r.n == 0 then return nil end
    return ("%d%% (%d of %d)"):format(math.floor(r.hits * 100 / r.n + 0.5), r.hits, r.n)
end

-- "Citrine x2, Aquamarine x1" (most common first, up to 3).
local function ScarceItems(nodeName)
    local r = db and db.scarce and db.scarce[nodeName]
    if not r then return nil end
    local list = {}
    for id, c in pairs(r.items) do list[#list + 1] = { id, c } end
    if #list == 0 then return nil end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local out = {}
    for i = 1, math.min(3, #list) do out[i] = ItemName(list[i][1]) .. " x" .. list[i][2] end
    return table.concat(out, ", ")
end

local function AddScarceLines(tt, nodeName)
    local text = ScarceText(nodeName)
    if not text then return end
    tt:AddLine("Scarce drops: " .. text, 0.45, 0.75, 1)
    local items = ScarceItems(nodeName)
    if items then tt:AddLine("  " .. items, 0.7, 0.7, 0.7, true) end
end

-------------------------------------------------------------------------------
-- Tooltips: minimap blips, world nodes and our own pins
-------------------------------------------------------------------------------
-- Node names sorted longest first, for finding names inside longer text.
local NAMES_BY_LENGTH = {}
for name in pairs(NODES) do NAMES_BY_LENGTH[#NAMES_BY_LENGTH + 1] = name end
table.sort(NAMES_BY_LENGTH, function(a, b) return #a > #b end)

local debugMode = false

-- Diagnostics are kept in saved variables (written on /reload or logout), newest last.
local lastLogMsg
local function Log(msg)
    if msg == lastLogMsg then return end
    lastLogMsg = msg
    if debugMode then Print(msg) end
    if not db then return end
    db.log = db.log or {}
    table.insert(db.log, date("%H:%M:%S ") .. msg)
    while #db.log > 60 do table.remove(db.log, 1) end
end
ns.Log = Log
local augmented = setmetatable({}, { __mode = "k" })   -- [tooltip] = key of what we added
local lastHover = {}        -- last world node hovered: { name, t }
local buildingPinTip = false -- our pin tooltips add their own lines

-- Collect readable text: the tooltip's data first (works when the shown text is secret),
-- then its first font string.
local function TooltipStrings(tt, data)
    local out = {}
    if type(data) == "table" and type(data.lines) == "table" then
        for i, line in ipairs(data.lines) do
            local t = type(line) == "table" and Clear(line.leftText)
            if t then out[#out + 1] = t end
            if i >= 6 then break end
        end
    end
    if #out == 0 and tt.GetName then
        local tname = tt:GetName()
        local fs = tname and _G[tname .. "TextLeft1"]
        local t = fs and Clear(fs:GetText())
        if t then out[1] = t end
    end
    return out
end

local function FindNodes(strings)
    local found, seen = {}, {}
    for _, s in ipairs(strings) do
        s = s:gsub("|n", "\n")
        for part in s:gmatch("[^\n]+") do
            local name = Strip(part)
            if NODES[name] then
                if not seen[name] then seen[name] = true; found[#found + 1] = name end
            elseif #name <= 50 then
                -- Fallback: a node name inside a short line (longest names win).
                for _, n in ipairs(NAMES_BY_LENGTH) do
                    if name:find(n, 1, true) then
                        if not seen[n] then seen[n] = true; found[#found + 1] = n end
                        break
                    end
                end
            end
        end
    end
    return found
end

local function Augment(tt, data, source)
    if buildingPinTip or not tt or (tt.IsForbidden and tt:IsForbidden()) then return end
    local strings = TooltipStrings(tt, data)
    local found = FindNodes(strings)

    if debugMode then
        local raw = {}
        for i, s in ipairs(strings) do raw[i] = (s:gsub("|", "||")) end
        local owner = tt.GetOwner and tt:GetOwner()
        local ownerName = owner and not Secret(owner) and owner.GetName and owner:GetName()
        local dataLines = type(data) == "table" and type(data.lines) == "table" and #data.lines or "-"
        Log(("[%s] tip=%s owner=%s lines=%s dataLines=%s readable=%d nodes=%s text=%s"):format(
            source or "?", tostring(tt.GetName and tt:GetName()), tostring(ownerName),
            tostring(tt.NumLines and tt:NumLines()), tostring(dataLines), #strings,
            #found > 0 and table.concat(found, ", ") or "none",
            #raw > 0 and table.concat(raw, " / ") or "<nothing readable>"))
    end
    if #found == 0 then return end
    if source == "Object" and #found == 1 then lastHover.name, lastHover.t = found[1], GetTime() end

    local key = table.concat(found, ";")
    if augmented[tt] == key and tt:NumLines() > 1 then return end
    augmented[tt] = key

    for _, name in ipairs(found) do
        local info = NODES[name]
        local label = (#found > 1 and (name .. ": ") or "") .. info.prof .. " " .. info.skill
        tt:AddDoubleLine(SkillColor(info.prof, info.skill) .. label .. "|r", PriceText(info))
        AddScarceLines(tt, name)
    end
    if not data then tt:Show() end
    if debugMode then Log("  added " .. #found .. " line(s), tooltip now " .. tostring(tt:NumLines()) .. " lines") end
end

-- Every hook runs inside pcall so nothing the client withholds can raise an error.
local errorCount = 0
local function SafeAugment(tt, data, source)
    local ok, err = pcall(Augment, tt, data, source)
    if not ok then
        errorCount = errorCount + 1
        if debugMode or errorCount <= 5 then Log("tooltip error (" .. tostring(source) .. "): " .. tostring(err)) end
    end
end

-- Covers our own pins and any tooltip built with plain text.
GameTooltip:HookScript("OnShow", function(tt) SafeAugment(tt, nil, "OnShow") end)
GameTooltip:HookScript("OnTooltipCleared", function(tt) augmented[tt] = nil end)
hooksecurefunc(GameTooltip, "SetText", function(tt)
    if tt:IsShown() then SafeAugment(tt, nil, "SetText") end
end)

-- Hovering a node in the world. (Minimap blip names are secret values on Forever,
-- so no addon can read them; that tooltip is left alone.)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and Enum.TooltipDataType.Object then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object, function(tt, data)
        SafeAugment(tt, data, "Object")
    end)
end

ns.SetDebug = function(on) debugMode = on end

local function PinEnter(self)
    local n, info = self.node, NODES[self.node.name]
    buildingPinTip = true
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(n.name)
    if info then
        GameTooltip:AddDoubleLine(SkillColor(info.prof, info.skill) .. info.prof .. " " .. info.skill .. "|r", PriceText(info))
        if not CanGather(info) then
            local rank = skills[info.prof]
            GameTooltip:AddLine(rank and ("Your %s is too low (%d)"):format(info.prof, rank)
                or ("You don't know " .. info.prof), 1, 0.25, 0.25)
        end
    end
    AddScarceLines(GameTooltip, n.name)
    local count = n.count or 0
    if count > 0 then
        GameTooltip:AddLine(("Gathered %d time%s, last %s"):format(count, count == 1 and "" or "s", Ago(n.t)), 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine("Not gathered yet", 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
    augmented[GameTooltip] = n.name
    buildingPinTip = false
end
local function PinLeave() GameTooltip:Hide() end

-------------------------------------------------------------------------------
-- Node tracker
-------------------------------------------------------------------------------
local function Round(v, p) local m = 10 ^ p; return math.floor(v * m + 0.5) / m end

-- World coordinates (yards): first value grows north, second grows west.
local vec = CreateVector2D and CreateVector2D(0, 0)
local function MapToWorld(mapID, x, y)
    if not (vec and C_Map.GetWorldPosFromMapPos) then return end
    vec:SetXY(x, y)
    local inst, pos = C_Map.GetWorldPosFromMapPos(mapID, vec)
    if pos then
        local wn, ww = pos:GetXY()
        return wn, ww, inst
    end
end

local function PlayerPos()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    local wn, ww, inst = MapToWorld(mapID, x, y)
    return mapID, x, y, wn, ww, inst
end

local UpdateWorldMap -- forward
local mapToggle      -- world map checkbox
local MakeMapToggle  -- forward
local MakeDot        -- forward
local TickGPH        -- forward

-- gathered = false for a node we tried but lacked the skill for.
local function RecordNode(name, gathered)
    local mapID, x, y, wn, ww, inst = PlayerPos()
    if not mapID then return end
    local list = db.nodes[mapID]
    if not list then list = {}; db.nodes[mapID] = list end

    for _, n in ipairs(list) do
        if n.name == name then
            local close
            if wn and n.wn then
                close = (n.wn - wn) ^ 2 + (n.ww - ww) ^ 2 < 25 * 25          -- within 25 yards
            else
                close = (n.x - x) ^ 2 + (n.y - y) ^ 2 < 0.004 ^ 2
            end
            if close then
                if gathered then n.count, n.t = (n.count or 0) + 1, time() end
                return
            end
        end
    end

    list[#list + 1] = {
        name = name, x = Round(x, 4), y = Round(y, 4),
        wn = wn and Round(wn, 1), ww = ww and Round(ww, 1), inst = inst,
        count = gathered and 1 or 0, t = time(),
    }
    dirty = true
    if UpdateWorldMap then UpdateWorldMap() end
    Print(("New node saved%s: %s (%.1f, %.1f)"):format(gathered and "" or " (skill too low)", name, x * 100, y * 100))
end

-------------------------------------------------------------------------------
-- Minimap pins
-------------------------------------------------------------------------------
-- Minimap diameter in yards per zoom level.
local MM_SIZE = {
    outdoor = { [0] = 466 + 2/3, 400, 333 + 1/3, 266 + 2/3, 200, 133 + 1/3 },
    indoor  = { [0] = 300, 240, 180, 120, 80, 50 },
}
local mmPins = {}
local last = {}

local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local function RoundTex(tex, parent, size)
    tex:SetSize(size, size)
    tex:SetPoint("CENTER")
    local m = parent:CreateMaskTexture()
    m:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(tex)
    tex:AddMaskTexture(m)
end

-- A tiny red dot, small enough to sit inside the game's own node icon so you
-- can still see whether the node is spawned.
function MakeDot(p, size)
    p.dot = p:CreateTexture(nil, "OVERLAY", nil, 7)
    p.dot:SetColorTexture(1, 0.1, 0.1)
    if p.CreateMaskTexture then
        RoundTex(p.dot, p, size)
    else
        p.dot:SetSize(size, size)
        p.dot:SetPoint("CENTER")
    end
end

local function GetMMPin(i)
    local p = mmPins[i]
    if not p then
        p = CreateFrame("Frame", nil, Minimap)
        p:SetSize(6, 6)
        p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        MakeDot(p, 4)
        p:EnableMouse(true)
        p:SetScript("OnEnter", PinEnter)
        p:SetScript("OnLeave", PinLeave)
        mmPins[i] = p
    end
    return p
end

local function UpdateMinimap()
    local used = 0
    local _, _, _, pn, pw, inst = PlayerPos()

    if db.minimap and pn then
        local zoom = Minimap:GetZoom()
        local rotate = CVar("rotateMinimap") == "1"
        local facing = rotate and GetPlayerFacing and (GetPlayerFacing() or 0) or 0
        local indoors = IsIndoors and IsIndoors() or false

        if not dirty and pn == last.n and pw == last.w and facing == last.f
            and zoom == last.z and indoors == last.i then
            return
        end
        dirty = false
        last.n, last.w, last.f, last.z, last.i = pn, pw, facing, zoom, indoors

        local radius = ((indoors and MM_SIZE.indoor or MM_SIZE.outdoor)[zoom] or 466) / 2
        local pxPerYard = (Minimap:GetWidth() / 2) / radius
        local s, c = math.sin(facing), math.cos(facing)
        local maxR2 = (radius * 0.92) ^ 2

        for _, list in pairs(db.nodes) do
            for _, n in ipairs(list) do
                if n.inst == inst and n.wn then
                    local dy = n.wn - pn          -- north = up
                    local dx = pw - n.ww          -- east = right
                    if math.abs(dx) < radius and math.abs(dy) < radius then
                        if rotate then dx, dy = dx * c + dy * s, -dx * s + dy * c end
                        if dx * dx + dy * dy < maxR2 then
                            used = used + 1
                            local p = GetMMPin(used)
                            p.node = n
                            p:ClearAllPoints()
                            p:SetPoint("CENTER", Minimap, "CENTER", dx * pxPerYard, dy * pxPerYard)
                            p:Show()
                        end
                    end
                end
            end
        end
    end

    for i = used + 1, #mmPins do mmPins[i]:Hide() end
end

-------------------------------------------------------------------------------
-- World map pins
-------------------------------------------------------------------------------
local wmPins = {}
local wmMap, wmScale

local function MapCanvas()
    if not WorldMapFrame then return end
    if WorldMapFrame.GetCanvas then
        local ok, c = pcall(WorldMapFrame.GetCanvas, WorldMapFrame)
        if ok and c then return c end
    end
    return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

local function DrawWorldMap()
    if mapToggle and db then mapToggle:SetChecked(db.worldmap and true or false) end
    for _, p in ipairs(wmPins) do p:Hide() end
    if not (db and db.worldmap and WorldMapFrame and WorldMapFrame:IsShown()) then return end

    local canvas = MapCanvas()
    if not canvas then return end
    local mapID = WorldMapFrame:GetMapID()
    wmMap, wmScale = mapID, canvas:GetScale()
    local list = mapID and db.nodes[mapID]
    if not list then return end

    local w, h = canvas:GetSize()
    local size = 14 / (wmScale > 0 and wmScale or 1)
    for i, n in ipairs(list) do
        local p = wmPins[i]
        if not p then
            p = CreateFrame("Frame", nil, canvas)
            p.border = p:CreateTexture(nil, "BORDER")
            p.border:SetColorTexture(0, 0, 0, 0.9)
            p.border:SetPoint("TOPLEFT", -1, 1)
            p.border:SetPoint("BOTTOMRIGHT", 1, -1)
            p.tex = p:CreateTexture(nil, "OVERLAY")
            p.tex:SetAllPoints()
            p.x = p:CreateTexture(nil, "OVERLAY", nil, 7)
            p.x:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
            p.x:SetAllPoints()
            p:EnableMouse(true)
            p:SetScript("OnEnter", PinEnter)
            p:SetScript("OnLeave", PinLeave)
            wmPins[i] = p
        end
        p:SetParent(canvas)
        p:SetFrameStrata("HIGH")   -- above the map's own layers
        p:SetFrameLevel(canvas:GetFrameLevel() + 5000)
        p:SetSize(size, size)
        p.node = n
        p.tex:SetTexture(Icon(n.name))
        p.x:SetShown(not CanGather(NODES[n.name]))
        p:ClearAllPoints()
        p:SetPoint("CENTER", canvas, "TOPLEFT", n.x * w, -n.y * h)
        p:Show()
    end
end

UpdateWorldMap = function()
    local ok, err = pcall(DrawWorldMap)
    if not ok then Log("worldmap error: " .. tostring(err)) end
end

-- Checkbox on the big map: show or hide the nodes you've gathered from.
function MakeMapToggle()
    if mapToggle or not WorldMapFrame then return end
    local area = WorldMapFrame.ScrollContainer or WorldMapFrame
    local cb = CreateFrame("CheckButton", "EasyGatherMapToggle", WorldMapFrame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPRIGHT", area, "TOPRIGHT", -96, -6)
    cb:SetFrameLevel(area:GetFrameLevel() + 2500)
    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.6)
    bg:SetPoint("TOPLEFT", -2, 1)
    bg:SetPoint("BOTTOMRIGHT", 88, -1)
    local label = cb.text or cb.Text or _G["EasyGatherMapToggleText"]
    if not label then
        label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 0, 0)
    end
    label:SetFontObject("GameFontHighlightSmall")
    label:SetText("My gathered nodes")
    cb:SetChecked(db.worldmap and true or false)
    cb:SetScript("OnClick", function(self)
        db.worldmap = self:GetChecked() and true or false
        UpdateWorldMap()
    end)
    cb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("EasyGather")
        GameTooltip:AddLine("Show the nodes you have gathered from on this map.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mapToggle = cb
end

-------------------------------------------------------------------------------
-- Auction house price scan (modern C_AuctionHouse, with a legacy fallback)
-------------------------------------------------------------------------------
local MODERN = C_AuctionHouse and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.MakeItemKey and true

local scan = CreateFrame("Frame")
scan:Hide()
scan.queue, scan.i, scan.waiting, scan.wait = nil, 0, false, 0

local function AHFrame() return AuctionHouseFrame or AuctionFrame end
local function AHOpen() local fr = AHFrame(); return fr and fr:IsShown() end

-- Passive browsing only overwrites stale or higher prices; a scan always overwrites.
local function StorePrice(itemID, unit, force)
    if not (itemID and ITEMS[itemID] and unit and unit > 0) then return end
    local rec = db.prices[itemID]
    if force or not rec or unit < rec.p or time() - rec.t > 600 then
        db.prices[itemID] = { p = math.floor(unit), t = time() }
    end
end

local function Answered(itemID)
    if scan:IsShown() and scan.current == itemID then scan.waiting = false end
end

local function ReadCommodityResults(itemID)
    if not itemID or Secret(itemID) or not ITEMS[itemID] then return end
    local best
    local ok, n = pcall(C_AuctionHouse.GetNumCommoditySearchResults, itemID)
    for i = 1, (ok and n or 0) do
        local ok2, r = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
        if ok2 and r and r.unitPrice and (not best or r.unitPrice < best) then best = r.unitPrice end
    end
    StorePrice(itemID, best, scan:IsShown())
    Answered(itemID)
end

local function ReadItemResults(itemKey)
    local itemID = type(itemKey) == "table" and itemKey.itemID
    if not itemID or Secret(itemID) or not ITEMS[itemID] then return end
    local best
    local ok, n = pcall(C_AuctionHouse.GetNumItemSearchResults, itemKey)
    for i = 1, (ok and n or 0) do
        local ok2, r = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
        local price = ok2 and r and r.buyoutAmount
        if price and price > 0 and (not best or price < best) then best = price end
    end
    StorePrice(itemID, best, scan:IsShown())
    Answered(itemID)
end

local function ReadLegacyResults(force)
    if not GetNumAuctionItems then return end
    local best = {}
    for i = 1, GetNumAuctionItems("list") do
        local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = GetAuctionItemInfo("list", i)
        if itemID and ITEMS[itemID] and buyout and buyout > 0 and count and count > 0 then
            local unit = buyout / count
            if not best[itemID] or unit < best[itemID] then best[itemID] = unit end
        end
    end
    for itemID, unit in pairs(best) do StorePrice(itemID, unit, force) end
end

local function StartScan()
    if not AHOpen() then
        Print("Open the Auction House first.")
        return
    end
    local q, seen = {}, {}
    for itemID, name in pairs(ITEMS) do
        if not seen[name] then seen[name] = true; q[#q + 1] = itemID end
    end
    table.sort(q)
    scan.queue, scan.i, scan.waiting, scan.current = q, 0, false, nil
    scan:Show()
    Print(("Scanning %d items..."):format(#q))
end

local function Ready()
    if MODERN then
        return not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
    end
    return CanSendAuctionQuery and CanSendAuctionQuery()
end

local function Send(itemID)
    if MODERN then
        -- Plain item key and no sorts, like Blizzard's own buy page does it.
        local ok, key = pcall(C_AuctionHouse.MakeItemKey, itemID)
        return ok and key and pcall(C_AuctionHouse.SendSearchQuery, key, {}, false)
    end
    QueryAuctionItems(ITEMS[itemID], nil, nil, 0, false, 0, false, true)
    return true
end

scan:SetScript("OnUpdate", function(self, elapsed)
    if not AHOpen() then
        self:Hide(); Print("Scan stopped (AH closed).")
        return
    end
    if self.waiting then
        self.wait = self.wait + elapsed
        if self.wait < 6 then return end
        self.waiting = false            -- no answer (or nothing listed), move on
    end
    if not Ready() then return end
    self.i = self.i + 1
    local itemID = self.queue[self.i]
    if not itemID then
        self:Hide(); Print("Scan complete.")
        return
    end
    self.current, self.wait = itemID, 0
    self.waiting = Send(itemID) and true or false
end)

local function MakeScanButton()
    local parent = AHFrame()
    if scan.button or not parent then return end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(110, 22)
    b:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -30, 2)   -- sits just above the AH window
    b:SetText("Scan Ore/Herbs")
    b:SetScript("OnClick", StartScan)
    scan.button = b
end

-------------------------------------------------------------------------------
-- Gold per hour: gathered mats (AH value), vendorable grey/white mob loot, coin
-------------------------------------------------------------------------------
local ItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local ItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- A plain number, or nil for secret / missing values.
local function Num(v)
    if type(v) ~= "number" or Secret(v) then return nil end
    return v
end

local function AHPrice(itemID)
    if ITEMS[itemID] then return (PriceValue({ item = itemID })) end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if api and api.GetAuctionPriceByItemID then
        local ok, p = pcall(api.GetAuctionPriceByItemID, ADDON, itemID)
        if ok and Num(p) and p > 0 then return p end
    end
end

local function Session()
    local ses = db.session
    if not ses then
        ses = { secs = 0, gathered = 0, junk = 0, coin = 0 }
        db.session = ses
    end
    return ses
end

-- Text money in AHledger's style: 3g 43s 39c with colored letters.
local function Money(v)
    v = math.floor((v or 0) + 0.5)
    if v <= 0 then return "0|cffeda55fc|r" end
    local g, s, c = math.floor(v / 10000), math.floor(v / 100) % 100, v % 100
    local G, S, C = "|cffffd700g|r", "|cffc7c7cfs|r", "|cffeda55fc|r"
    if g >= 10 then return s > 0 and ("%d%s %d%s"):format(g, G, s, S) or (g .. G) end
    if g > 0 then return ("%d%s %d%s %d%s"):format(g, G, s, S, c, C) end
    if s > 0 then return ("%d%s %d%s"):format(s, S, c, C) end
    return c .. C
end

-- A thin bar in the same style as AHledger's, attached right below it.
local GREY, ACCENT, R = "|cff9d9d9d", "|cff33ff99", "|r"
local SEGMENT_GAP = 16

local gph = CreateFrame("Frame", "EasyGatherBar", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
gph:SetSize(300, 24)
gph:SetFrameStrata("MEDIUM")
gph:SetClampedToScreen(true)
gph:EnableMouse(true)
if gph.SetBackdrop then
    gph:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    gph:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
    gph:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.9)
end
gph:Hide()

local segments = {}
local function Segment(onClick, onEnter)
    local b = CreateFrame("Button", nil, gph)
    b:SetHeight(20)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 0, 0)
    b.text:SetJustifyH("LEFT")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(_, button) if onClick then onClick(button) end end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        onEnter(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
    segments[#segments + 1] = b
    return b
end

local function Layout()
    local x = 8
    for _, b in ipairs(segments) do
        local w = math.max(10, math.floor((b.text:GetStringWidth() or 60) + 0.5))
        b:SetWidth(w)
        b:ClearAllPoints()
        b:SetPoint("LEFT", gph, "LEFT", x, 0)
        x = x + w + SEGMENT_GAP
    end
    gph:SetWidth(math.max(60, x - SEGMENT_GAP + 8))
end

-- Sit just below AHledger's bar (it follows that bar when you move it);
-- without AHledger, take its usual spot at the top of the screen.
local anchoredTo
local function Anchor()
    local target = _G.AHledgerBar
    if target and not target:IsShown() then target = nil end
    if anchoredTo == (target or UIParent) then return end
    anchoredTo = target or UIParent
    gph:ClearAllPoints()
    if target then
        gph:SetPoint("TOP", target, "BOTTOM", 0, 2)
    else
        gph:SetPoint("TOP", UIParent, "TOP", 0, -4)
    end
end

local function Duration(secs)
    secs = math.floor(secs)
    return ("%dh %02dm"):format(math.floor(secs / 3600), math.floor(secs / 60) % 60)
end

local ResetGPH -- forward
local segMark = Segment(function(button) if button == "RightButton" then ResetGPH() end end, function(tt)
    tt:AddLine(ACCENT .. "EasyGather" .. R .. " gold per hour")
    tt:AddLine("Counts time you are logged in, carried over /reload and logout.", 0.8, 0.8, 0.8, true)
    tt:AddLine(GREY .. "Right-click: reset the session.  Minimap button right-click: hide this bar." .. R, nil, nil, nil, true)
end)
segMark.text:SetText(ACCENT .. "EG" .. R)
local segRate = Segment(nil, function(tt)
    tt:AddLine("Gold per hour", 1, 1, 1)
    tt:AddLine("Gathered + vendor loot + coin, divided by session time.", 0.8, 0.8, 0.8, true)
end)
local segGather = Segment(nil, function(tt)
    tt:AddLine("Gathered", 1, 1, 1)
    tt:AddLine("Ore, herbs and other node loot at AH price (vendor price when there is no AH data).", 0.8, 0.8, 0.8, true)
end)
local segScarce = Segment(nil, function(tt)
    tt:AddLine("Scarce drops (all nodes)", 1, 1, 1)
    local hits, gathers = 0, 0
    for _, r in pairs(db.scarce) do hits, gathers = hits + r.hits, gathers + r.n end
    if gathers > 0 then
        tt:AddDoubleLine("Overall", ("%d%% (%d of %d gathers)"):format(math.floor(hits * 100 / gathers + 0.5), hits, gathers),
            1, 1, 1, 0.45, 0.75, 1)
    end
    tt:AddLine("How often a node gave something rare besides its main item (gems, elemental earth, Swiftthistle...). Stones are not counted.", 0.8, 0.8, 0.8, true)
    local list = {}
    for name, r in pairs(db.scarce) do if r.n > 0 then list[#list + 1] = name end end
    -- Highest percentage first; more gathers wins a tie.
    table.sort(list, function(a, b)
        local ra, rb = db.scarce[a], db.scarce[b]
        local pa, pb = ra.hits / ra.n, rb.hits / rb.n
        if pa ~= pb then return pa > pb end
        return ra.n > rb.n
    end)
    if #list == 0 then tt:AddLine("No gathers recorded yet.", 0.7, 0.7, 0.72)
    else tt:AddLine("Top 5 by scarce rate:", 1, 0.82, 0) end
    for i = 1, math.min(5, #list) do
        local name = list[i]
        tt:AddDoubleLine(name, ScarceText(name), 1, 1, 1, 0.45, 0.75, 1)
        local items = ScarceItems(name)
        if items then tt:AddLine("  " .. items, 0.7, 0.7, 0.7, true) end
    end
end)
local segJunk = Segment(nil, function(tt)
    tt:AddLine("Vendor loot", 1, 1, 1)
    tt:AddLine("Grey and white items from mobs, at vendor sell price.", 0.8, 0.8, 0.8, true)
end)
local segCoin = Segment(nil, function(tt)
    tt:AddLine("Coin", 1, 1, 1)
    tt:AddLine("Money looted this session.", 0.8, 0.8, 0.8, true)
end)
local segTime = Segment(function(button) if button == "RightButton" then ResetGPH() end end, function(tt)
    tt:AddLine("Session time", 1, 1, 1)
    tt:AddLine(GREY .. "Right-click: reset the session." .. R)
end)

local function UpdateGPH()
    if not gph:IsShown() then return end
    Anchor()
    local ses = Session()
    local total = ses.gathered + ses.junk + ses.coin
    segRate.text:SetText(GREY .. "Gold/hr " .. R .. (ses.secs >= 60 and Money(total * 3600 / ses.secs) or (GREY .. "-" .. R)))
    segGather.text:SetText(GREY .. "Gathered " .. R .. Money(ses.gathered))
    -- Overall scarce rate across every node type gathered.
    local hits, gathers = 0, 0
    for _, r in pairs(db.scarce) do hits, gathers = hits + r.hits, gathers + r.n end
    if gathers > 0 then
        segScarce.text:SetText(GREY .. "Scarce " .. R .. "|cff73bfff"
            .. math.floor(hits * 100 / gathers + 0.5) .. "%" .. R)
    else
        segScarce.text:SetText(GREY .. "Scarce -" .. R)
    end
    segJunk.text:SetText(GREY .. "Vendor " .. R .. Money(ses.junk))
    segCoin.text:SetText(GREY .. "Coin " .. R .. Money(ses.coin))
    segTime.text:SetText(GREY .. "Time " .. R .. Duration(ses.secs))
    Layout()
end

local function ToggleGPH()
    db.gphHidden = not db.gphHidden
    gph:SetShown(not db.gphHidden)
    UpdateGPH()
end

ResetGPH = function()
    db.session = nil
    Session()
    UpdateGPH()
    Print("Gold per hour session reset.")
end

local gphTick = 0
function TickGPH(elapsed)
    local ses = Session()
    ses.secs = ses.secs + elapsed
    gphTick = gphTick + elapsed
    if gphTick >= 1 then gphTick = 0; UpdateGPH() end
end

local function MakeGPHFrame()
    db.gphPos = nil   -- the old floating window's position
    anchoredTo = nil
    Anchor()
    gph:SetShown(not db.gphHidden)
    UpdateGPH()
end

-- Loot: count each loot window once, when it opens.
local lootCounted, lootOpen, lootClosedAt, lastMoney = false, false, 0, nil
local lastGather = {}   -- node name and time of the last successful gather

local function SourceKind(slot)
    if not GetLootSourceInfo then return end
    local ok, guid = pcall(GetLootSourceInfo, slot)
    guid = ok and Clear(guid)
    return guid and guid:match("^(%a+)")   -- "Creature", "GameObject", ...
end

local function CountLoot()
    lootOpen = true
    if lootCounted then return end
    lootCounted = true
    local ses = Session()
    -- Loot that opens right after a gather belongs to that node.
    local node = lastGather.name and GetTime() - (lastGather.t or 0) < 5 and lastGather.name
    local scarceHit = false
    lastGather.name = nil
    for slot = 1, (GetNumLootItems and GetNumLootItems() or 0) do
        local link = GetLootSlotLink and Clear(GetLootSlotLink(slot))
        local itemID = link and ItemInfoInstant and Num((ItemInfoInstant(link)))
        if itemID then
            local _, _, qty, _, quality = GetLootSlotInfo(slot)
            qty, quality = Num(qty) or 1, Num(quality)
            if qty < 1 then qty = 1 end
            local kind = SourceKind(slot)
            if node and kind ~= "Creature" and IsScarce(node, itemID) then
                local r = db.scarce[node]
                if not r then r = { n = 0, hits = 0, items = {} }; db.scarce[node] = r end
                r.items[itemID] = (r.items[itemID] or 0) + qty
                scarceHit = true
            end
            local sell = Num(select(11, ItemInfo(link)))
            if ITEMS[itemID] or kind == "GameObject" then
                local price = AHPrice(itemID) or sell
                if price and price > 0 then ses.gathered = ses.gathered + price * qty end
            elseif (kind == "Creature" or kind == "Vehicle") and quality and quality <= 1
                and sell and sell > 0 then
                ses.junk = ses.junk + sell * qty
            end
        end
    end
    if node then
        local r = db.scarce[node]
        if not r then r = { n = 0, hits = 0, items = {} }; db.scarce[node] = r end
        r.n = r.n + 1
        if scarceHit then r.hits = r.hits + 1 end
        db.lastNode = node
    end
    UpdateGPH()
end

local function OnMoney()
    local m = Num(GetMoney())
    if not m then return end
    if lastMoney and m > lastMoney and (lootOpen or GetTime() - lootClosedAt < 2) then
        local ses = Session()
        ses.coin = ses.coin + (m - lastMoney)
        UpdateGPH()
    end
    lastMoney = m
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local f = CreateFrame("Frame")
local pendingCasts = {}

-- Registered through pcall: a client that lacks an event (e.g. the legacy AH
-- events on a modern client) throws an error, which would stop the whole file.
for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL",
    "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
    "UI_ERROR_MESSAGE", "AUCTION_HOUSE_SHOW",
    "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "PLAYER_MONEY",
    "AUCTION_ITEM_LIST_UPDATE",                                       -- legacy AH
    "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", -- modern AH
}) do
    pcall(f.RegisterEvent, f, e)
end

-------------------------------------------------------------------------------
-- Minimap button (drag to move, left-click toggles pins, right-click lists zone)
-------------------------------------------------------------------------------
local function CountNodes()
    local total, zone = 0, 0
    local mapID = C_Map.GetBestMapForUnit("player")
    for id, list in pairs(db.nodes) do
        total = total + #list
        if id == mapID then zone = #list end
    end
    return total, zone
end

local function ListZone()
    local mapID = C_Map.GetBestMapForUnit("player")
    local list = mapID and db.nodes[mapID] or {}
    local counts = {}
    for _, n in ipairs(list) do counts[n.name] = (counts[n.name] or 0) + 1 end
    local info = mapID and C_Map.GetMapInfo(mapID)
    Print(("%d nodes saved in %s:"):format(#list, info and info.name or "this zone"))
    for name, c in pairs(counts) do
        local nd = NODES[name]
        print(("  %s%s|r (%s %d) x%d - %s"):format(SkillColor(nd.prof, nd.skill), name, nd.prof, nd.skill, c, PriceText(nd)))
    end
end

local function TogglePins()
    local on = not (db.minimap or db.worldmap)
    db.minimap, db.worldmap, dirty = on, on, true
    UpdateWorldMap()
    Print("Node pins " .. (on and "on" or "off"))
end

local function MakeMinimapButton()
    local b = CreateFrame("Button", "EasyGatherMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Trade_Mining")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    local function Place()
        local a = math.rad(db.buttonAngle or 200)
        local r = Minimap:GetWidth() / 2 + 10
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
    end
    Place()

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            db.buttonAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            Place()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            if IsShiftKeyDown() then ListZone() else ToggleGPH() end
        else
            TogglePins()
        end
    end)
    b:SetScript("OnEnter", function(self)
        local total, zone = CountNodes()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("EasyGather")
        GameTooltip:AddLine(("Nodes saved: %d (%d in this zone)"):format(total, zone), 1, 1, 1)
        GameTooltip:AddLine("Pins: " .. ((db.minimap or db.worldmap) and "|cff40ff40on|r" or "|cffff4040off|r"), 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click: toggle node pins", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: show/hide gold per hour", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift-right-click: list nodes in this zone", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if db.hideButton then b:Hide() end
end

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        EasyGatherDB = EasyGatherDB or {}
        db = EasyGatherDB
        db.nodes = db.nodes or {}
        db.prices = db.prices or {}
        db.scarce = db.scarce or {}
        db.recent, db.ring, db.ringInset = nil, nil, nil   -- old ring text settings
        if db.minimap == nil then db.minimap = true end
        if db.worldmap == nil then db.worldmap = true end

    elseif event == "PLAYER_LOGIN" then
        pcall(UpdateSkills)   -- a missing API must not block the rest of login
        MakeMinimapButton()
        MakeGPHFrame()
        lastMoney = Num(GetMoney())
        Print("loaded. Type /eg for commands.")
        if WorldMapFrame then
            WorldMapFrame:HookScript("OnShow", function()
                pcall(MakeMapToggle)
                UpdateWorldMap()
            end)
        end

    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        pcall(UpdateSkills)

    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, target, castGUID = ...
        if unit ~= "player" or Secret(target) or Secret(castGUID) then return end
        wipe(pendingCasts)
        if target and castGUID and NODES[target] then
            pendingCasts[castGUID] = target
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, castGUID = ...
        if unit ~= "player" or not castGUID or Secret(castGUID) then return end
        if pendingCasts[castGUID] then
            RecordNode(pendingCasts[castGUID], true)
            lastGather.name, lastGather.t = pendingCasts[castGUID], GetTime()
            wipe(pendingCasts)
        end

    elseif event == "UNIT_SPELLCAST_FAILED" then
        -- Tried a node without enough skill: remember it so it gets a red X pin.
        local unit, castGUID = ...
        if unit ~= "player" or not castGUID or Secret(castGUID) then return end
        local name = pendingCasts[castGUID]
        if name then
            if not CanGather(NODES[name]) then RecordNode(name, false) end
            wipe(pendingCasts)
        end

    elseif event == "UI_ERROR_MESSAGE" then
        -- Some clients refuse an unskilled gather before any cast starts; use the
        -- node the mouse was just on (its world tooltip name is readable).
        local _, msg = ...
        msg = Clear(msg)
        local name = lastHover.name
        local info = name and NODES[name]
        if msg and info and GetTime() - (lastHover.t or 0) < 5 and not CanGather(info)
            and (msg:find(info.prof, 1, true) or msg:find("Requires", 1, true)) then
            RecordNode(name, false)
            lastHover.name = nil
        end

    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        pcall(CountLoot)

    elseif event == "LOOT_CLOSED" then
        lootCounted, lootOpen, lootClosedAt = false, false, GetTime()

    elseif event == "PLAYER_MONEY" then
        pcall(OnMoney)

    elseif event == "AUCTION_HOUSE_SHOW" then
        MakeScanButton()

    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        ReadLegacyResults(scan:IsShown())
        scan.waiting = false

    elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
        ReadCommodityResults(...)

    elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
        ReadItemResults(...)
    end
end)

-- Pin refresh loop (cheap: skips work when nothing moved).
local acc = 0
f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.05 or not db then return end
    TickGPH(acc)
    acc = 0
    UpdateMinimap()
    if WorldMapFrame and WorldMapFrame:IsShown() then
        local canvas = MapCanvas()
        if canvas and (WorldMapFrame:GetMapID() ~= wmMap or canvas:GetScale() ~= wmScale) then
            UpdateWorldMap()
        end
    end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
SLASH_EASYGATHER1, SLASH_EASYGATHER2 = "/eg", "/easygather"
SlashCmdList.EASYGATHER = function(msg)
    local cmd, arg = strsplit(" ", strlower(strtrim(msg or "")), 2)

    if cmd == "scan" then
        StartScan()

    elseif cmd == "minimap" then
        db.minimap = not db.minimap; dirty = true
        Print("Minimap pins " .. (db.minimap and "on" or "off"))

    elseif cmd == "map" then
        db.worldmap = not db.worldmap; UpdateWorldMap()
        Print("World map pins " .. (db.worldmap and "on" or "off"))

    elseif cmd == "list" then
        ListZone()

    elseif cmd == "gph" then
        ToggleGPH()
        Print("Gold per hour window " .. (db.gphHidden and "hidden" or "shown"))

    elseif cmd == "reset" then
        ResetGPH()

    elseif cmd == "debug" then
        ns.debug = not ns.debug
        ns.SetDebug(ns.debug)
        if ns.debug then db.log = {} end
        Print("Debug logging " .. (ns.debug and "on" or "off"))

    elseif cmd == "button" then
        db.hideButton = not db.hideButton
        local b = EasyGatherMinimapButton
        if b then b:SetShown(not db.hideButton) end
        Print("Minimap button " .. (db.hideButton and "hidden" or "shown"))

    elseif cmd == "clear" then
        if arg == "all" then
            wipe(db.nodes)
            Print("All saved nodes cleared.")
        else
            local mapID = C_Map.GetBestMapForUnit("player")
            if mapID then db.nodes[mapID] = nil end
            Print("Saved nodes for this zone cleared.")
        end
        dirty = true; UpdateWorldMap()

    else
        Print("commands:")
        print("  /eg scan  - scan AH prices for ores/herbs (AH must be open)")
        print("  /eg list  - nodes saved in this zone")
        print("  /eg minimap | map  - toggle pins")
        print("  /eg gph  - show/hide the gold per hour bar")
        print("  /eg reset  - start a new gold per hour session")
        print("  /eg button  - show/hide the minimap button")
        print("  /eg clear [all]  - clear this zone (or everything)")
        print("  Minimap button: left-click pins, right-click gold bar, shift-right-click zone list")
    end
end
