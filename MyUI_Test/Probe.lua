-- MyUI_Test :: Probe.lua
-- PLAN "Safe to try": what does the client keep, and where? READ ONLY. It
-- calls no setter, saves no layout and writes nothing but MyUITestDB.probe.
--
-- It takes a reading at PLAYER_LOGIN -- before MyUI touches the layout
-- (PLAYER_ENTERING_WORLD) -- one a few seconds later, one on a spec change,
-- and one whenever /myuiprobe is typed. Comparing them answers:
--   * is the active Edit Mode layout kept per spec?
--   * does one character's new layout shift another's active one?
--   * does opening MyUI's map change the minimapZoom setting?
--
-- Characters are numbered, never named: the report can be pasted anywhere.

local ADDON, T = ...

local Probe = {}
T.Probe = Probe

Probe.KEEP = 60
Probe.CVARS = { "minimapZoom", "synchronizeSettings" }

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
end

local function DB()
    MyUITestDB = type(MyUITestDB) == "table" and MyUITestDB or {}
    local db = MyUITestDB
    db.probe = db.probe or { who = {}, n = 0, readings = {} }
    return db.probe
end

-- A number per character. The GUID stays in this file's saved variables.
local function Who(db)
    local guid = Call(_G.UnitGUID, "player") or "unknown"
    if not db.who[guid] then
        db.n = db.n + 1
        db.who[guid] = db.n
    end
    return db.who[guid]
end

function Probe.Read(stage)
    local db = DB()
    local r = { stage = stage, who = Who(db), at = Call(_G.time), cvars = {}, layouts = {} }
    local spec = _G.C_SpecializationInfo and _G.C_SpecializationInfo.GetSpecialization or _G.GetSpecialization
    r.spec = Call(spec)
    local info = _G.C_EditMode and Call(_G.C_EditMode.GetLayouts)
    if type(info) == "table" then
        local meta = _G.Enum and _G.Enum.EditModePresetLayoutsMeta
        r.presets = meta and meta.NumValues
        r.active = info.activeLayout
        for i, l in ipairs(info.layouts or {}) do
            r.layouts[i] = { type = l.layoutType, name = l.layoutName }
        end
        local mine = r.presets and r.active and info.layouts and info.layouts[r.active - r.presets]
        r.activeName = mine and mine.layoutName or (r.active and "preset:" .. r.active)
    end
    for _, name in ipairs(Probe.CVARS) do
        r.cvars[name] = Call(_G.C_CVar and _G.C_CVar.GetCVar or _G.GetCVar, name)
    end
    table.insert(db.readings, r)
    while #db.readings > Probe.KEEP do table.remove(db.readings, 1) end
    return r
end

function Probe.Line(r)
    local names = {}
    for i, l in ipairs(r.layouts) do
        -- MyUI's layouts by name; anyone else's only by kind and position.
        local shown = tostring(l.name):match("^MyUI") and l.name or "other"
        names[i] = ("%d:%s/%s"):format(i, tostring(l.type), shown)
    end
    local active = tostring(r.activeName)
    if not active:match("^MyUI") and not active:match("^preset:") then active = "other" end
    return ("char %d spec %s [%s] active %s=%s zoom %s sync %s {%s}"):format(
        r.who, tostring(r.spec), r.stage, tostring(r.active), active,
        tostring(r.cvars.minimapZoom), tostring(r.cvars.synchronizeSettings), table.concat(names, " "))
end

function Probe.Report()
    local out = {}
    for i, r in ipairs(DB().readings) do out[i] = Probe.Line(r) end
    return out
end

local driver = CreateFrame("Frame", "MyUITestProbe")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
driver:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        Probe.Read("login")
        C_Timer.After(5, function() Probe.Read("settled") end)
    elseif unit == nil or unit == "player" then
        C_Timer.After(2, function() Probe.Read("spec") end)
    end
end)

SLASH_MYUIPROBE1 = "/myuiprobe"
SlashCmdList["MYUIPROBE"] = function()
    Probe.Read("asked")
    for _, line in ipairs(Probe.Report()) do print(line) end
end
