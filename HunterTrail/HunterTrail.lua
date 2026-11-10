-- Hunter Trail: a WoW Forever hunter leveling guide in a tabbed window.
-- /trail toggles the window. The minimap button does the same.
local ADDON, ns = ...

local TABS = ns.tabs
local WALK = ns.walkthrough
local MAX_LVL = 60

local C_GOLD  = "|cffffd100"
local C_NOTE  = "|cffff9933"
local C_GREEN = "|cffabd473"
local C_DIM   = "|cffa0a0a0"
local C_WHITE = "|cffffffff"
local C_CODE  = "|cff9fd8ff"
local R = "|r"

local defaults = {
  shown = true,
  point = "CENTER", relPoint = "CENTER", x = 200, y = 40,
  minimapAngle = 200,
  hideMinimap = false,
}

local db
local refresh
local frame, minimapButton
local tab = 1
local walk = 1
local followLevel = true
local playerLevel = 1

------------------------------------------------------------------------
-- Guide logic (no UI calls, so it can be tested outside the game)
------------------------------------------------------------------------

local function clampLevel(l)
  l = tonumber(l) or 1
  if l < 1 then return 1 end
  if l > MAX_LVL then return MAX_LVL end
  return l
end

local function walkFor(level)
  local l = clampLevel(level)
  for i, b in ipairs(WALK) do
    if l >= b.lo and l <= b.hi then return i end
  end
  return #WALK
end
ns.walkFor = walkFor

local function walkTabIndex()
  for i, t in ipairs(TABS) do if t.walkthrough then return i end end
  return 1
end
local WALK_TAB = walkTabIndex()

local function render(lines, out)
  for _, s in ipairs(lines) do
    local c = s:sub(1, 1)
    local rest = s:sub(2)
    if s == "" then
      out[#out + 1] = " "
    elseif c == "#" then
      out[#out + 1] = C_GOLD .. rest .. R
    elseif c == "-" then
      out[#out + 1] = "  - " .. rest
    elseif c == "!" then
      out[#out + 1] = C_NOTE .. "[Unconfirmed] " .. R .. C_DIM .. rest .. R
    elseif c == "=" then
      out[#out + 1] = "    " .. C_CODE .. rest .. R
    else
      out[#out + 1] = s
    end
  end
  return out
end

local function talentLines(level, out)
  out[#out + 1] = " "
  out[#out + 1] = C_GOLD .. "Talent order, 25-60" .. R
  for _, t in ipairs(ns.talentFallback) do
    local lv = (t[1] == t[2]) and tostring(t[1]) or (t[1] .. "-" .. t[2])
    local here = level >= t[1] and level <= t[2]
    local mark = here and (C_GREEN .. "> " .. R) or "  "
    out[#out + 1] = mark .. C_WHITE .. lv .. R .. "  " .. t[3]
  end
end

-- Returns subtitle and body text for a tab
function ns.TabText(t, level, w)
  level = clampLevel(level)
  local def = TABS[t]
  local out = {}
  local sub = def.name
  if def.walkthrough then
    w = w or walkFor(level)
    local b = WALK[w]
    sub = "Level Walkthrough  " .. b.lo .. "-" .. b.hi
    if w == walkFor(level) then sub = sub .. "  " .. C_GREEN .. "(you are here)" .. R end
    render(b.lines, out)
  else
    render(def.lines, out)
    if def.talents then talentLines(level, out) end
  end
  return sub, table.concat(out, "\n")
end

-- Tables shown under the text on the Pets, Gear and Dungeons tabs.
-- ns.TableFor returns the columns ({x, width}) and rows ({cells, rule alpha}).
local function gold(t) return C_GOLD .. t .. R end
local function columns(widths)
  local cols, x = {}, 2
  for i, w in ipairs(widths) do cols[i] = { x, w }; x = x + w + 2 end
  return cols
end

-- Items you've collected, keyed by item name, so Gear and Dungeons share one check.
-- Saved per character in HunterTrailCharDB.got (set on load).
ns.got = {}
function ns.IsGot(item) return ns.got[item] == true end
function ns.SetGot(item, on) ns.got[item] = on and true or nil end
local function itemText(item)
  if ns.IsGot(item) then return C_DIM .. item .. R end
  return item
end

local grids = {}

grids.pets = function(level)
  local rows = { { cells = { gold("Pet"), gold("Lvl"), gold("Tame at"), gold("Zone"), gold("Where to look") }, rule = 0.5 } }
  for _, p in ipairs(ns.rarePets or {}) do
    local ready = level >= p.tameAt
    rows[#rows + 1] = { rule = 0.15, cells = {
      p.name .. "\n" .. C_DIM .. p.family .. R,
      p.level,
      (ready and C_GREEN or C_WHITE) .. p.tameAt .. R,
      p.zone,
      p.where,
    } }
  end
  return columns({ 104, 26, 34, 74, 156 }), rows
end

grids.gear = function(level)
  local rows = { { cells = { gold("Lvl"), gold("Slot"), "", gold("Item"), gold("Where it comes from") }, rule = 0.5 } }
  local list = ns.gear or {}
  for i, g in ipairs(list) do
    local first = (i == 1) or (list[i - 1][1] ~= g[1])
    local last = (i == #list) or (list[i + 1][1] ~= g[1])
    local lvl = ""
    if first then lvl = (level >= g[1] and C_GREEN or C_WHITE) .. g[1] .. R end
    rows[#rows + 1] = { rule = last and 0.45 or 0.12, check = g[3], cells = { lvl, C_DIM .. g[2] .. R, "", itemText(g[3]), g[4] } }
  end
  return columns({ 22, 46, 14, 142, 170 }), rows, 3
end

grids.dungeons = function(level)
  local rows = { { cells = { gold("Levels"), gold("Dungeon"), "", gold("Item drop"), gold("Dropped by") }, rule = 0.5 } }
  for _, d in ipairs(ns.dungeons or {}) do
    local range = d[1] == d[2] and tostring(d[1]) or (d[1] .. "-" .. d[2])
    local inRange = level >= d[1] and level <= d[2]
    local name = d[3]
    if d[4] then name = name .. "\n" .. C_DIM .. d[4] .. R end
    local lv = (inRange and C_GREEN or C_WHITE) .. range .. R
    local drops = d[5]
    if #drops == 0 then
      rows[#rows + 1] = { rule = 0.45, cells = { lv, name, "", C_DIM .. "None on the gear list" .. R, "" } }
    end
    for i, drop in ipairs(drops) do
      local boss = drop[2]
      if boss:sub(1, 5) == "Quest" then boss = C_DIM .. boss .. R end
      rows[#rows + 1] = {
        rule = (i == #drops) and 0.45 or 0.12,
        check = drop[1],
        cells = { i == 1 and lv or "", i == 1 and name or "", "", itemText(drop[1]), boss },
      }
    end
  end
  return columns({ 36, 90, 14, 146, 108 }), rows, 3
end

-- Quests share the checkbox store with items, under a "quest:" key so a quest never ticks an item of the same name
grids.quests = function(level)
  local rows = { { cells = { "", gold("Lvl"), gold("Quest"), gold("Where and what to do"), gold("Reward") }, rule = 0.5 } }
  for _, q in ipairs(ns.classQuests or {}) do
    local key = "quest:" .. q[2]
    local lv = (level >= q[1] and C_GREEN or C_WHITE) .. q[1] .. R
    local name = ns.IsGot(key) and (C_DIM .. q[2] .. R) or q[2]
    local reward = q[4] or (C_DIM .. "Not listed" .. R)
    rows[#rows + 1] = { rule = 0.15, check = key, cells = { "", lv, name, q[3], reward } }
  end
  return columns({ 14, 22, 92, 170, 88 }), rows, 1
end

grids.petSkills = function(level)
  local rows = { { cells = { gold("Skill"), gold("Pet lvl"), gold("Cost"), gold("Learn it from") }, rule = 0.5 } }
  for _, k in ipairs(ns.petSkills or {}) do
    local lv = (level >= k[2] and C_GREEN or C_WHITE) .. k[2] .. R
    local from = k[4]
    if k[5] then from = from .. "\n" .. C_DIM .. k[5] .. R end
    rows[#rows + 1] = { rule = 0.15, cells = { k[1], lv, k[3] .. " TP", from } }
  end
  return columns({ 70, 34, 34, 256 }), rows
end

grids.training = function(level)
  local rows = { { cells = { gold("Lvl"), gold("New spells"), gold("New ranks") }, rule = 0.5 } }
  local nextShown = false
  for _, v in ipairs(ns.trainerVisits or {}) do
    local color = C_WHITE
    if not nextShown and v[1] >= level then color = C_GREEN; nextShown = true end
    local new = #v[2] > 0 and table.concat(v[2], ", ") or (C_DIM .. "None" .. R)
    rows[#rows + 1] = { rule = 0.15, cells = { color .. v[1] .. R, new, table.concat(v[3], ", ") } }
  end
  return columns({ 22, 150, 226 }), rows
end

grids.ammo = function(level)
  local rows = { { cells = { gold("Lvl"), gold("Item"), gold("Bonus"), gold("Where to get it") }, rule = 0.5 } }
  for _, a in ipairs(ns.ammo or {}) do
    local lv = a[1] and ((level >= a[1] and C_GREEN or C_WHITE) .. a[1] .. R) or (C_DIM .. "Quest" .. R)
    rows[#rows + 1] = { rule = 0.15, cells = { lv, a[2], a[3], a[4] } }
  end
  return columns({ 30, 100, 40, 222 }), rows
end

-- Profession routes: Leatherworking, Cooking and First Aid share one layout.
local function profGrid(key)
  return function()
    local rows = { { cells = { gold("Skill"), gold("Make"), gold("Crafts"), gold("Each one takes"), gold("Learn it from") }, rule = 0.5 } }
    for _, r in ipairs((ns.profRoutes or {})[key] or {}) do
      rows[#rows + 1] = { rule = 0.15, cells = { C_GREEN .. r[1] .. R, r[2], r[3], r[4], r[5] or (C_DIM .. "Not listed" .. R) } }
    end
    return columns({ 44, 100, 32, 120, 98 }), rows
  end
end
grids.lwRoute = profGrid("lw")
grids.cookRoute = profGrid("cook")
grids.faRoute = profGrid("fa")

function ns.TableFor(def, level)
  local make = def and def.grid and grids[def.grid]
  if not make then return nil end
  return make(clampLevel(level))
end

-- Everything drawn under a tab's intro text, in order: extra text and tables.
-- A tab lists them in "after" (grid names and line lists). A tab with only "grid" gets that one table.
function ns.BlocksFor(def, level)
  local list = def.after or (def.grid and { def.grid }) or {}
  local blocks = {}
  for _, b in ipairs(list) do
    if type(b) == "string" then
      local cols, rows, checkCol = grids[b](clampLevel(level))
      blocks[#blocks + 1] = { cols = cols, rows = rows, checkCol = checkCol }
    else
      blocks[#blocks + 1] = { text = table.concat(render(b, {}), "\n") }
    end
  end
  return blocks
end

local function nextTalent(level)
  for _, t in ipairs(ns.talentFallback) do
    if level >= t[1] and level <= t[2] then return "now: " .. t[3] end
    if t[1] > level then return "at " .. t[1] .. ": " .. t[3] end
  end
end
ns.nextTalent = nextTalent

-- Stop here when loaded outside the game (for testing)
if not CreateFrame then return end

------------------------------------------------------------------------
-- Window
------------------------------------------------------------------------

local tabButtons = {}

local function savePosition()
  local point, _, relPoint, x, y = frame:GetPoint(1)
  db.point, db.relPoint, db.x, db.y = point or "CENTER", relPoint or "CENTER", x or 0, y or 0
end

local function applyPosition()
  frame:ClearAllPoints()
  frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
end

-- Table cells and row lines, reused between tabs
local cellPool, rulePool, checkPool, textPool = {}, {}, {}, {}
local usedCells, usedRules, usedChecks, usedTexts = 0, 0, 0, 0

local function hideTable()
  for _, c in ipairs(cellPool) do c:Hide() end
  for _, r in ipairs(rulePool) do r:Hide() end
  for _, b in ipairs(checkPool) do b:Hide() end
  for _, t in ipairs(textPool) do t:Hide() end
  usedCells, usedRules, usedChecks, usedTexts = 0, 0, 0, 0
end

-- Extra text between tables, styled like the tab's main text
local function layoutText(text, y)
  usedTexts = usedTexts + 1
  local f = textPool[usedTexts]
  if not f then
    f = frame.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f:SetWidth(404)
    f:SetJustifyH("LEFT")
    f:SetJustifyV("TOP")
    f:SetSpacing(2)
    textPool[usedTexts] = f
  end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", frame.child, "TOPLEFT", 2, -y)
  f:SetText(text)
  f:Show()
  return y + f:GetStringHeight()
end

-- A small "got it" checkbox. Clicking it saves the item and redraws in place.
local function newCheck()
  local b = CreateFrame("CheckButton", nil, frame.child)
  b:SetSize(16, 16)
  b:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  b:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  b:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
  b:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  b:SetScript("OnClick", function(self)
    ns.SetGot(self.item, self:GetChecked())
    refresh(true)
  end)
  return b
end

local function layoutTable(cols, rows, y, checkCol)
  for _, rowDef in ipairs(rows) do
    local h = 0
    if checkCol and rowDef.check then
      usedChecks = usedChecks + 1
      local b = checkPool[usedChecks]
      if not b then b = newCheck(); checkPool[usedChecks] = b end
      b.item = rowDef.check
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", frame.child, "TOPLEFT", cols[checkCol][1] - 2, -(y - 2))
      b:SetChecked(ns.IsGot(rowDef.check))
      b:Show()
      h = 12
    end
    for k, col in ipairs(cols) do
      usedCells = usedCells + 1
      local c = cellPool[usedCells]
      if not c then
        c = frame.child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c:SetJustifyH("LEFT")
        c:SetJustifyV("TOP")
        c:SetWordWrap(true)
        cellPool[usedCells] = c
      end
      c:ClearAllPoints()
      c:SetPoint("TOPLEFT", frame.child, "TOPLEFT", col[1], -y)
      c:SetWidth(col[2])
      c:SetText(rowDef.cells[k] or "")
      c:Show()
      h = math.max(h, c:GetStringHeight())
    end
    usedRules = usedRules + 1
    local line = rulePool[usedRules]
    if not line then
      line = frame.child:CreateTexture(nil, "ARTWORK")
      rulePool[usedRules] = line
    end
    line:SetColorTexture(0.67, 0.83, 0.45, rowDef.rule or 0.15)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", frame.child, "TOPLEFT", 2, -(y + h + 3))
    line:SetSize(404, 1)
    line:Show()
    y = y + h + 8
  end
  return y
end

function refresh(keepScroll)
  if not frame then return end
  local sub, body = ns.TabText(tab, playerLevel, walk)
  frame.sub:SetText(sub)
  local info = "Level " .. playerLevel
  local nt = nextTalent(playerLevel)
  if nt then info = info .. "   " .. C_DIM .. "Talent " .. nt .. R end
  frame.level:SetText(info)
  frame.body:SetText(body)
  hideTable()
  local height = frame.body:GetStringHeight()
  for _, b in ipairs(ns.BlocksFor(TABS[tab], playerLevel)) do
    if b.text then
      height = layoutText(b.text, height + 6)
    else
      height = layoutTable(b.cols, b.rows, height + 8, b.checkCol)
    end
  end
  frame.child:SetHeight(height + 12)
  if not keepScroll then frame.scroll:SetVerticalScroll(0) end

  for i, b in ipairs(tabButtons) do
    if i == tab then
      b.text:SetTextColor(1, 1, 1)
      b.sel:Show()
    else
      b.text:SetTextColor(1, 0.82, 0)
      b.sel:Hide()
    end
  end

  local isWalk = TABS[tab].walkthrough
  frame.prev:SetShown(isWalk)
  frame.nxt:SetShown(isWalk)
  frame.mine:SetShown(isWalk)
end

local function setTab(t)
  if t < 1 then t = #TABS elseif t > #TABS then t = 1 end
  tab = t
  db.tabName = TABS[t].name
  refresh()
end

local function setWalk(w)
  if w < 1 then w = #WALK elseif w > #WALK then w = 1 end
  walk = w
  followLevel = (w == walkFor(playerLevel))
  tab = WALK_TAB
  db.tabName = TABS[tab].name
  refresh()
end

local function makeButton(parent, label, width)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(width, 22)
  btn:SetText(label)
  return btn
end

local function makeTabButton(parent, i, name)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(150, 22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -40 - (i - 1) * 24)

  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(0.67, 0.83, 0.45, 0.25)
  b.sel:Hide()

  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.08)

  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.text:SetPoint("LEFT", 6, 0)
  b.text:SetPoint("RIGHT", -4, 0)
  b.text:SetJustifyH("LEFT")
  b.text:SetText(name)

  b:SetScript("OnClick", function()
    if TABS[i].walkthrough and followLevel then walk = walkFor(playerLevel) end
    setTab(i)
  end)
  return b
end

local function buildFrame()
  frame = CreateFrame("Frame", "HunterTrailFrame", UIParent, "BackdropTemplate")
  frame:SetSize(600, 470)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if self.SetUserPlaced then self:SetUserPlaced(false) end
    savePosition()
  end)
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0.05, 0.06, 0.08, 0.92)
  frame:SetBackdropBorderColor(0.67, 0.83, 0.45, 1)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("Hunter Trail")

  frame.level = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.level:SetPoint("LEFT", title, "RIGHT", 12, 0)
  frame.level:SetPoint("RIGHT", frame, "RIGHT", -34, 0)
  frame.level:SetJustifyH("LEFT")
  frame.level:SetWordWrap(false)

  -- Left column of tabs, one per guide section
  for i, t in ipairs(TABS) do
    tabButtons[i] = makeTabButton(frame, i, t.name)
  end

  local divider = frame:CreateTexture(nil, "ARTWORK")
  divider:SetColorTexture(0.67, 0.83, 0.45, 0.4)
  divider:SetPoint("TOPLEFT", frame, "TOPLEFT", 166, -40)
  divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 166, 14)
  divider:SetWidth(1)

  frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.sub:SetPoint("TOPLEFT", frame, "TOPLEFT", 178, -42)
  frame.sub:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
  frame.sub:SetJustifyH("LEFT")

  -- Bracket buttons for the Level Walkthrough tab
  frame.mine = makeButton(frame, "My level", 76)
  frame.mine:SetPoint("BOTTOMRIGHT", -12, 12)
  frame.mine:SetScript("OnClick", function()
    followLevel = true
    setWalk(walkFor(playerLevel))
  end)
  frame.nxt = makeButton(frame, ">", 30)
  frame.nxt:SetPoint("RIGHT", frame.mine, "LEFT", -6, 0)
  frame.nxt:SetScript("OnClick", function() setWalk(walk + 1) end)
  frame.prev = makeButton(frame, "<", 30)
  frame.prev:SetPoint("RIGHT", frame.nxt, "LEFT", -4, 0)
  frame.prev:SetScript("OnClick", function() setWalk(walk - 1) end)

  -- Scrolling body (mouse wheel)
  local scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 176, -64)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 42)
  scroll:EnableMouseWheel(true)
  frame.scroll = scroll

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(410, 10)
  scroll:SetScrollChild(child)
  frame.child = child

  frame.body = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.body:SetPoint("TOPLEFT", child, "TOPLEFT", 2, 0)
  frame.body:SetWidth(404)
  frame.body:SetJustifyH("LEFT")
  frame.body:SetJustifyV("TOP")
  frame.body:SetSpacing(2)

  scroll:SetScript("OnMouseWheel", function(self, delta)
    local maxScroll = math.max(0, child:GetHeight() - self:GetHeight())
    local v = self:GetVerticalScroll() - delta * 40
    if v < 0 then v = 0 elseif v > maxScroll then v = maxScroll end
    self:SetVerticalScroll(v)
  end)

  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 178, 18)
  hint:SetText("Scroll for more. Drag to move.")

  frame:SetScript("OnShow", function() db.shown = true; refresh() end)
  frame:SetScript("OnHide", function() db.shown = false end)

  -- Escape closes it
  table.insert(UISpecialFrames, "HunterTrailFrame")

  applyPosition()
end

local function toggle()
  if frame:IsShown() then frame:Hide() else frame:Show() end
end

------------------------------------------------------------------------
-- Minimap button (drag to move it around the minimap)
------------------------------------------------------------------------

local function placeMinimapButton()
  local a = math.rad(db.minimapAngle or 200)
  local r = (Minimap:GetWidth() / 2) + 10
  minimapButton:ClearAllPoints()
  minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function buildMinimapButton()
  local b = CreateFrame("Button", "HunterTrailMinimapButton", Minimap)
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("AnyUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("CENTER", 0, 1)

  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastCall")
  icon:SetSize(18, 18)
  icon:SetPoint("CENTER", 0, 1)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(52, 52)
  border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function() toggle() end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local s = Minimap:GetEffectiveScale()
      cx, cy = cx / s, cy / s
      db.minimapAngle = math.deg(math.atan2(cy - my, cx - mx))
      placeMinimapButton()
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Hunter Trail")
    GameTooltip:AddLine("Click to show or hide your leveling guide.", 1, 1, 1)
    GameTooltip:AddLine("Drag to move this button.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  minimapButton = b
  placeMinimapButton()
  if db.hideMinimap then b:Hide() end
end

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------

local function say(msg)
  DEFAULT_CHAT_FRAME:AddMessage(C_GREEN .. "Hunter Trail:" .. R .. " " .. msg)
end

local function findTab(word)
  for i, t in ipairs(TABS) do
    if string.lower(t.name):find(word, 1, true) == 1 then return i end
  end
end

SLASH_HUNTERTRAIL1 = "/trail"
SLASH_HUNTERTRAIL2 = "/huntertrail"
SlashCmdList["HUNTERTRAIL"] = function(msg)
  msg = string.lower(msg or "")
  msg = msg:match("^%s*(.-)%s*$")
  if not frame then return end
  local n = tonumber(msg)
  local found = (msg ~= "" and not n) and findTab(msg) or nil
  if msg == "" then
    toggle()
  elseif n then
    frame:Show()
    setWalk(walkFor(n))
  elseif msg == "reset" then
    db.point, db.relPoint, db.x, db.y = defaults.point, defaults.relPoint, defaults.x, defaults.y
    applyPosition()
    frame:Show()
    say("window moved back to the middle of the screen.")
  elseif msg == "minimap" then
    db.hideMinimap = not db.hideMinimap
    if db.hideMinimap then minimapButton:Hide() else minimapButton:Show() end
    say(db.hideMinimap and "minimap button hidden. /trail minimap brings it back." or "minimap button shown.")
  elseif found then
    frame:Show()
    if TABS[found].walkthrough and followLevel then walk = walkFor(playerLevel) end
    setTab(found)
  else
    say("/trail  show or hide")
    say("/trail 40  open the walkthrough for a level")
    say("/trail talents, /trail macros, /trail pet ...  open a tab by its first word")
    say("/trail reset  move the window back to the middle")
    say("/trail minimap  hide or show the minimap button")
  end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    HunterTrailDB = HunterTrailDB or {}
    db = HunterTrailDB
    HunterTrailCharDB = HunterTrailCharDB or {}
    HunterTrailCharDB.got = HunterTrailCharDB.got or {}
    ns.got = HunterTrailCharDB.got
    for k, v in pairs(defaults) do
      if db[k] == nil then db[k] = v end
    end
    -- The open tab is saved by name, so removing or reordering tabs never opens the wrong one
    db.tab = nil
    tab = WALK_TAB
    for i, t in ipairs(TABS) do
      if t.name == db.tabName then tab = i end
    end
  elseif event == "PLAYER_LOGIN" then
    playerLevel = UnitLevel("player") or 1
    walk = walkFor(playerLevel)
    buildFrame()
    buildMinimapButton()
    if db.shown then frame:Show(); refresh() else frame:Hide() end
  elseif event == "PLAYER_LEVEL_UP" then
    playerLevel = tonumber(arg1) or UnitLevel("player") or playerLevel
    local before = walk
    if followLevel then walk = walkFor(playerLevel) end
    if walk ~= before then say("new walkthrough section: levels " .. WALK[walk].lo .. "-" .. WALK[walk].hi .. ". /trail to open.") end
    for _, t in ipairs(ns.talentFallback) do
      if t[1] == playerLevel then say("talent at " .. playerLevel .. ": " .. t[3]) end
    end
    refresh()
  end
end)
