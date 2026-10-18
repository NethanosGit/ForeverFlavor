local ADDON = ...

local DIR = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local FRAME_TEX = DIR .. "chrome-frame"
local BUTTON_TEX = DIR .. "chrome-buttons"
local ICON_FRAME_TEX = DIR .. "IconFrameGold"
local QUEST_ICONS = {
    available = DIR .. "availablequesticon",
    active = DIR .. "activequesticon",
}
local QUEST_ICON_SIZE = 16
local QUEST_ICON_GAP = 4

local DURATION = 10
local FADE = 0.4
local FADE_IN = 0.3
local WIDTH = 240
local MIN_HEIGHT = 100
local BORDER_SCALE = 1
local BG_INSET = 5
local BG_ALPHA = 0.85
local ICON_SIZE = 24
local ICON_LEFT, ICON_TOP = 22, -30
local TEXT_GAP = 16
local PAD_RIGHT = 24
local PAD_BOTTOM = 18
local CLOSE_SIZE = 16
local CLOSE_X, CLOSE_Y = -8, -4
local HINT_TEXT = "[Click to read...]"
local HINT_X, HINT_Y = 0, -5

local ICON_FRAME_OPEN, ICON_FRAME_CX, ICON_FRAME_CY = 0.4922, 0.4727, 0.4336
local ICON_FRAME_SIZE = ICON_SIZE / ICON_FRAME_OPEN
local ICON_FRAME_X = (0.5 - ICON_FRAME_CX) * ICON_FRAME_SIZE
local ICON_FRAME_Y = (ICON_FRAME_CY - 0.5) * ICON_FRAME_SIZE

local SHEET_W, SHEET_H = 1024, 512
local function Piece(w, h, l, r, t, b)
    return { w, h, l / SHEET_W, r / SHEET_W, t / SHEET_H, b / SHEET_H }
end

local CORNERS = {
    TopLeft = { Piece(95, 95, 466, 656, 268, 458), "TOPLEFT", -8, 16 },
    TopRight = { Piece(95, 95, 664, 854, 268, 458), "TOPRIGHT", 2, 16 },
    BottomLeft = { Piece(95, 100, 664, 854, 4, 204), "BOTTOMLEFT", -8, -8 },
    BottomRight = { Piece(95, 100, 4, 194, 268, 468), "BOTTOMRIGHT", 2, -8 },
}
local EDGES = {
    Top = Piece(128, 95, 202, 458, 268, 458),
    Bottom = Piece(128, 100, 400, 656, 4, 204),
    Left = Piece(95, 128, 4, 194, 4, 260),
    Right = Piece(95, 128, 202, 392, 4, 260),
}

local CLOSE_COORDS = {
    normal = { 292 / 512, 356 / 512, 148 / 512, 212 / 512 },
    pushed = { 436 / 512, 500 / 512, 148 / 512, 212 / 512 },
    disabled = { 364 / 512, 428 / 512, 148 / 512, 212 / 512 },
    highlight = { 4 / 512, 68 / 512, 220 / 512, 284 / 512 },
}

local LOOT_GLOBALS = {
    "LOOT_ITEM_SELF",
    "LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_PUSHED_SELF",
    "LOOT_ITEM_PUSHED_SELF_MULTIPLE",
    "LOOT_ITEM_CREATED_SELF",
    "LOOT_ITEM_CREATED_SELF_MULTIPLE",
}
local QUOTE_PREFIXES = { '"', "\226\128\156", "\226\128\158", "\194\171" }

local lootPatterns = {}
local infoCache = {}
local queue = {}
local toast, scanTip

local function ToPattern(text)
    local escaped = text:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
    escaped = escaped:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. escaped .. "$"
end

for _, key in ipairs(LOOT_GLOBALS) do
    local text = _G[key]
    if type(text) == "string" then
        lootPatterns[#lootPatterns + 1] = ToPattern(text)
    end
end

local function IsQuote(text)
    for _, prefix in ipairs(QUOTE_PREFIXES) do
        if text:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function ItemID(link)
    return tonumber(link:match("item:(%d+)"))
end

local function FindInBags(id)
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link and ItemID(link) == id then
                return bag, slot
            end
        end
    end
end

local function ScanTooltip(link, bag, slot)
    scanTip:ClearLines()
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    if bag then
        scanTip:SetBagItem(bag, slot)
    else
        scanTip:SetHyperlink(link)
    end
    local info = {}
    for i = 1, scanTip:NumLines() do
        local line = _G["ForeverFlavorScanTipTextLeft" .. i]
        local text = line and line:GetText()
        if text then
            if i > 1 and not info.flavor and IsQuote(text) then
                info.flavor = text
            elseif text == ITEM_STARTS_QUEST then
                info.startsQuest = true
            elseif text == ITEM_BIND_QUEST then
                info.questItem = true
            elseif text == ITEM_READABLE then
                info.readable = true
            end
        end
    end
    return info
end

local function GetInfo(link)
    local id = ItemID(link)
    if not id then
        return nil
    end
    local bag, slot = FindInBags(id)
    if bag then
        return ScanTooltip(link, bag, slot)
    end
    local cached = infoCache[id]
    if cached then
        return cached
    end
    local info = ScanTooltip(link)
    if GetItemInfo(link) then
        infoCache[id] = info
    end
    return info
end

local function FindQuestForItem(itemName)
    local wanted = itemName:lower()
    for index = 1, GetNumQuestLogEntries() do
        local title, _, _, _, isHeader = GetQuestLogTitle(index)
        if title and not isHeader then
            for objective = 1, GetNumQuestLeaderBoards(index) do
                local text = GetQuestLogLeaderBoard(objective, index)
                if text and text:lower():find(wanted, 1, true) then
                    return title
                end
            end
            if title:lower():find(wanted, 1, true) then
                return title
            end
        end
    end
end

local delayed = {}
local delayFrame = CreateFrame("Frame")
delayFrame:Hide()
delayFrame:SetScript("OnUpdate", function(self, dt)
    for i = #delayed, 1, -1 do
        local entry = delayed[i]
        entry.wait = entry.wait - dt
        if entry.wait <= 0 then
            table.remove(delayed, i)
            entry.fn()
        end
    end
    if #delayed == 0 then
        self:Hide()
    end
end)

local function After(seconds, fn)
    delayed[#delayed + 1] = { wait = seconds, fn = fn }
    delayFrame:Show()
end

local function BuildBorder(frame)
    local back = CreateFrame("Frame", nil, frame)
    back:SetAllPoints(frame)
    back:SetFrameLevel(frame:GetFrameLevel())

    local bg = back:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(0, 0, 0, BG_ALPHA)
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", BG_INSET, -BG_INSET)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -BG_INSET, BG_INSET)

    local pieces = {}
    for name, spec in pairs(CORNERS) do
        local info, point, x, y = spec[1], spec[2], spec[3], spec[4]
        local t = back:CreateTexture(nil, "BORDER")
        t:SetTexture(FRAME_TEX)
        t:SetTexCoord(info[3], info[4], info[5], info[6])
        t:SetSize(info[1] * BORDER_SCALE, info[2] * BORDER_SCALE)
        t:SetPoint(point, frame, point, x * BORDER_SCALE, y * BORDER_SCALE)
        pieces[name] = t
    end

    local function Edge(name)
        local info = EDGES[name]
        local t = back:CreateTexture(nil, "BORDER")
        t:SetTexture(FRAME_TEX)
        t:SetTexCoord(info[3], info[4], info[5], info[6])
        pieces[name] = t
        return t, info
    end

    local top, topInfo = Edge("Top")
    top:SetHeight(topInfo[2] * BORDER_SCALE)
    top:SetPoint("TOPLEFT", pieces.TopLeft, "TOPRIGHT", 0, 0)
    top:SetPoint("TOPRIGHT", pieces.TopRight, "TOPLEFT", 0, 0)

    local bottom, bottomInfo = Edge("Bottom")
    bottom:SetHeight(bottomInfo[2] * BORDER_SCALE)
    bottom:SetPoint("BOTTOMLEFT", pieces.BottomLeft, "BOTTOMRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", pieces.BottomRight, "BOTTOMLEFT", 0, 0)

    local left, leftInfo = Edge("Left")
    left:SetWidth(leftInfo[1] * BORDER_SCALE)
    left:SetPoint("TOPLEFT", pieces.TopLeft, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", pieces.BottomLeft, "TOPLEFT", 0, 0)

    local right, rightInfo = Edge("Right")
    right:SetWidth(rightInfo[1] * BORDER_SCALE)
    right:SetPoint("TOPRIGHT", pieces.TopRight, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", pieces.BottomRight, "TOPRIGHT", 0, 0)

    frame.Back = back
    frame.BorderPieces = pieces
end

local function BuildCloseButton(frame)
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", CLOSE_X, CLOSE_Y)
    button:SetFrameLevel(frame:GetFrameLevel() + 10)

    local function Skin(setter, getter, coords)
        button[setter](button, BUTTON_TEX)
        button[getter](button):SetTexCoord(unpack(coords))
    end
    Skin("SetNormalTexture", "GetNormalTexture", CLOSE_COORDS.normal)
    Skin("SetPushedTexture", "GetPushedTexture", CLOSE_COORDS.pushed)
    Skin("SetDisabledTexture", "GetDisabledTexture", CLOSE_COORDS.disabled)
    button:SetHighlightTexture(BUTTON_TEX, "ADD")
    button:GetHighlightTexture():SetTexCoord(unpack(CLOSE_COORDS.highlight))

    button:SetScript("OnClick", function()
        PlaySound("igMainMenuClose")
        frame:Dismiss()
    end)
    frame.CloseButton = button
end

local function BuildToast()
    local frame = CreateFrame("Frame", "ForeverFlavorToast", UIParent)
    frame:SetSize(WIDTH, MIN_HEIGHT)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -180)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self.dragged = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnMouseDown", function(self)
        self.dragged = false
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and not self.dragged then
            self:Activate()
        end
    end)
    frame:Hide()

    BuildBorder(frame)

    local content = CreateFrame("Frame", nil, frame)
    content:SetAllPoints(frame)
    content:SetFrameLevel(frame:GetFrameLevel() + 1)

    frame.Icon = content:CreateTexture(nil, "ARTWORK")
    frame.Icon:SetSize(ICON_SIZE, ICON_SIZE)
    frame.Icon:SetPoint("TOPLEFT", frame, "TOPLEFT", ICON_LEFT, ICON_TOP)
    frame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local ornament = CreateFrame("Frame", nil, frame)
    ornament:SetAllPoints(frame)
    ornament:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.IconFrame = ornament:CreateTexture(nil, "OVERLAY")
    frame.IconFrame:SetTexture(ICON_FRAME_TEX)
    frame.IconFrame:SetSize(ICON_FRAME_SIZE, ICON_FRAME_SIZE)
    frame.IconFrame:SetPoint("CENTER", frame.Icon, "CENTER", ICON_FRAME_X, ICON_FRAME_Y)

    local textLeft = ICON_LEFT + ICON_SIZE + TEXT_GAP
    frame.TextWidth = WIDTH - textLeft - PAD_RIGHT

    frame.Name = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.Name:SetPoint("TOPLEFT", frame, "TOPLEFT", textLeft, ICON_TOP + 2.5)
    frame.Name:SetWidth(frame.TextWidth)
    frame.Name:SetJustifyH("LEFT")

    frame.Flavor = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.Flavor:SetPoint("TOPLEFT", frame.Name, "BOTTOMLEFT", 0, -6)
    frame.Flavor:SetWidth(frame.TextWidth)
    frame.Flavor:SetJustifyH("LEFT")
    frame.Flavor:SetJustifyV("TOP")

    frame.QuestIcon = content:CreateTexture(nil, "ARTWORK")
    frame.QuestIcon:SetSize(QUEST_ICON_SIZE, QUEST_ICON_SIZE)
    frame.QuestIcon:SetPoint("TOPLEFT", frame.Name, "BOTTOMLEFT", 0, -4)
    frame.QuestIcon:Hide()

    frame.Hint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.Hint:SetPoint("TOP", frame, "TOP", HINT_X, HINT_Y)
    frame.Hint:SetText(HINT_TEXT)
    frame.Hint:Hide()

    BuildCloseButton(frame)

    frame.elapsed = 0
    frame.fading = 0
    frame.fadingIn = 0
    frame:SetScript("OnUpdate", function(self, dt)
        if self.fadingIn > 0 then
            self.fadingIn = self.fadingIn + dt
            if self.fadingIn >= FADE_IN then
                self.fadingIn = 0
                self:SetAlpha(1)
            else
                self:SetAlpha(self.fadingIn / FADE_IN)
            end
            return
        end
        if MouseIsOver(self) then
            self.elapsed = 0
            self.fading = 0
            self:SetAlpha(1)
            return
        end
        if self.fading > 0 then
            self.fading = self.fading + dt
            if self.fading >= FADE then
                self:Dismiss()
            else
                self:SetAlpha(1 - self.fading / FADE)
            end
            return
        end
        self.elapsed = self.elapsed + dt
        if self.elapsed >= DURATION then
            self.fading = 0.001
        end
    end)

    frame.Dismiss = function(self)
        self:Hide()
        self:SetAlpha(1)
        self.fadingIn = 0
        self.elapsed = 0
        self.fading = 0
        self.current = nil
        self.entry = nil
        local nextEntry = table.remove(queue, 1)
        if nextEntry then
            self:Present(nextEntry)
        end
    end

    frame.Activate = function(self)
        local entry = self.entry
        if not (entry and entry.interactive) then
            return
        end
        local bag, slot = FindInBags(entry.id)
        if not bag then
            DEFAULT_CHAT_FRAME:AddMessage("ForeverFlavor: item not found in your bags.")
            return
        end
        UseContainerItem(bag, slot)
        self:Dismiss()
    end

    frame.Present = function(self, entry)
        self.current = entry.id
        self.entry = entry
        if not entry.test then
            ForeverFlavorCharDB.seen[entry.id] = true
        end
        if entry.interactive then
            self.Hint:Show()
        else
            self.Hint:Hide()
        end
        self.Icon:SetTexture(entry.icon)
        local r, g, b = GetItemQualityColor(entry.quality or 1)
        self.Name:SetText(entry.name)
        self.Name:SetTextColor(r, g, b)
        local shift = 0
        if entry.questIcon then
            self.QuestIcon:SetTexture(QUEST_ICONS[entry.questIcon])
            self.QuestIcon:Show()
            if entry.flavor ~= "" then
                shift = QUEST_ICON_SIZE + QUEST_ICON_GAP
            end
        else
            self.QuestIcon:Hide()
        end
        self.Flavor:ClearAllPoints()
        self.Flavor:SetPoint("TOPLEFT", self.Name, "BOTTOMLEFT", shift, -6)
        self.Flavor:SetWidth(self.TextWidth - shift)
        self.Flavor:SetText(entry.flavor)
        local body = self.Flavor:GetStringHeight()
        if entry.questIcon then
            body = math.max(body, QUEST_ICON_SIZE)
        end
        local height = -ICON_TOP + self.Name:GetStringHeight() + 6 + body + PAD_BOTTOM
        self:SetHeight(math.max(MIN_HEIGHT, height))
        self.elapsed = 0
        self.fading = 0
        self.fadingIn = 0.001
        self:SetAlpha(0)
        self:Show()
    end

    return frame
end

local function Enqueue(entry)
    if toast.current == entry.id then
        toast.elapsed = 0
        return
    end
    for _, queued in ipairs(queue) do
        if queued.id == entry.id then
            return
        end
    end
    if toast:IsShown() then
        queue[#queue + 1] = entry
    else
        toast:Present(entry)
    end
end

local function Print(text)
    DEFAULT_CHAT_FRAME:AddMessage("ForeverFlavor: " .. text)
end

local function HandleLink(link, verbose)
    local id = ItemID(link)
    if not verbose and id and ForeverFlavorCharDB.seen[id] then
        return
    end
    local info = GetInfo(link)
    local name, _, quality, _, _, _, _, _, equipLoc, icon = GetItemInfo(link)
    if not (info and name) then
        return
    end
    local interactive = info.readable or info.startsQuest
    local isEquipment = equipLoc and equipLoc ~= ""
    local questRelated = isEquipment or info.questItem or info.startsQuest
    if not (interactive or (info.flavor and questRelated)) then
        if verbose then
            Print("not readable, not a quest starter, and no flavor text on equipment or quest items.")
        end
        return
    end
    local questName = interactive and FindQuestForItem(name) or nil
    local questIcon
    if questName then
        questIcon = "active"
    elseif info.startsQuest then
        questIcon = "available"
    end
    Enqueue({
        id = id,
        test = verbose,
        name = name,
        quality = quality,
        icon = icon,
        flavor = info.flavor or questName or "",
        questIcon = questIcon,
        interactive = interactive,
    })
end

local function OnLoot(message)
    for _, pattern in ipairs(lootPatterns) do
        if message:match(pattern) then
            local link = message:match("|c%x+|Hitem:.-|h%[.-%]|h|r")
            if link then
                After(0.5, function()
                    HandleLink(link)
                end)
            end
            return
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("CHAT_MSG_LOOT")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then
            return
        end
        ForeverFlavorCharDB = ForeverFlavorCharDB or {}
        ForeverFlavorCharDB.seen = ForeverFlavorCharDB.seen or {}
        scanTip = CreateFrame("GameTooltip", "ForeverFlavorScanTip", nil, "GameTooltipTemplate")
        toast = BuildToast()
        self:UnregisterEvent("ADDON_LOADED")
    else
        OnLoot(arg1)
    end
end)

SLASH_FOREVERFLAVOR1 = "/ff"
SLASH_FOREVERFLAVOR2 = "/foreverflavor"
local function ResolveLink(arg)
    local link = arg:match("|c%x+|Hitem:.-|h%[.-%]|h|r")
    if link then
        return link
    end
    local id = tonumber(arg)
    if id then
        return "item:" .. id
    end
    return select(2, GetItemInfo(arg))
end

local retry = CreateFrame("Frame")
retry:Hide()
retry:SetScript("OnUpdate", function(self, dt)
    self.wait = self.wait - dt
    if self.wait > 0 then
        return
    end
    self:Hide()
    self.callback()
end)

local function WhenCached(link, callback, tries)
    tries = tries or 0
    if GetItemInfo(link) or tries >= 6 then
        callback(GetItemInfo(link) ~= nil)
        return
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:SetHyperlink(link)
    retry.wait = 0.5
    retry.callback = function()
        WhenCached(link, callback, tries + 1)
    end
    retry:Show()
end

SlashCmdList["FOREVERFLAVOR"] = function(msg)
    local command, arg = (msg or ""):match("^(%a+)%s*(.*)$")
    if command == "reset" then
        wipe(ForeverFlavorCharDB.seen)
        Print("seen items cleared for this character.")
        return
    end
    if command ~= "test" then
        Print("/ff test [itemLink|itemID], /ff reset")
        return
    end
    if arg ~= "" then
        local link = ResolveLink(arg)
        if not link then
            Print("unknown item.")
            return
        end
        WhenCached(link, function(cached)
            if not cached then
                Print("item not in client cache; link it in chat first.")
            else
                HandleLink(link, true)
            end
        end)
        return
    end
    Enqueue({
        id = -1,
        test = true,
        name = "Thunderfury Blessed Blade of the Windseeker",
        quality = 5,
        icon = "Interface\\Icons\\INV_Box_01",
        flavor = "\"Several crystalline shards from Hallowfall sit upon a plush pillow within the ornately carved box.\"",
        questIcon = "available",
        interactive = true,
    })
end
