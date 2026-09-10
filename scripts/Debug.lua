--
-- FS25_ContractManager - teshis modulu (Faz 0/1)
--
-- Kaynakta (gameSource.zip) bulunmayan kontrat sabitlerini, enum'lari, kontrat tur
-- siniflarini ve ESC menu sayfa adlarini log.txt'ye doker. Gorev basladiktan
-- DUMP_DELAY_MS sonra bir kez calisir. ContractManager.debugEnabled=false ile kapanir.
--
-- Kullanici log'dan "[CM/Debug]" gecen satirlari verir.
--

ContractManagerDebug = {
    PREFIX = "[CM/Debug]",
    DUMP_DELAY_MS = 15000,
    timer = 0,
    dumped = false,
    armed = false,
}

local function out(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    print(ContractManagerDebug.PREFIX .. " " .. (ok and line or tostring(fmt)))
end

local function classNameOf(value)
    if type(value) ~= "table" or ClassUtil == nil or ClassUtil.getClassNameByObject == nil then
        return nil
    end
    local ok, name = pcall(ClassUtil.getClassNameByObject, value)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = tostring(k)
    end
    table.sort(keys)
    return keys
end

local function short(v)
    local t = type(v)
    if t == "string" then
        return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "table" then
        return "table(" .. (classNameOf(v) or "?") .. ")"
    end
    return t
end

---Bir tablodaki fonksiyon olmayan alanlari tek satir halinde yaz
local function dumpValues(label, t)
    if type(t) ~= "table" then
        out("%s: <%s>", label, type(t))
        return
    end
    for _, k in ipairs(sortedKeys(t)) do
        local v = rawget(t, k)
        if v == nil then
            v = t[k]
        end
        if type(v) ~= "function" then
            out("%s.%s = %s", label, k, short(v))
        end
    end
end

local function dumpConstants()
    out("---- constants")
    for _, name in ipairs({ "MissionManager", "AbstractMission", "AbstractFieldMission" }) do
        local cls = _G[name]
        if type(cls) == "table" then
            for _, k in ipairs(sortedKeys(cls)) do
                local v = rawget(cls, k)
                if type(v) == "number" or type(v) == "string" then
                    out("%s.%s = %s", name, k, short(v))
                end
            end
        else
            out("%s: MISSING", name)
        end
    end
end

local function dumpEnums()
    out("---- enums")
    for _, name in ipairs({ "MissionStatus", "MissionFinishState", "MissionStartState" }) do
        local e = _G[name]
        if type(e) == "table" then
            local parts = {}
            for _, k in ipairs(sortedKeys(e)) do
                if type(e[k]) ~= "function" then
                    parts[#parts + 1] = k .. "=" .. tostring(e[k])
                end
            end
            out("%s: %s", name, table.concat(parts, ", "))
        else
            out("%s: MISSING", name)
        end
    end
end

local function dumpGlobals()
    out("---- globals")
    local names = {
        "HarvestMission", "BaleMission", "MowBaleMission", "ChaffMission", "FruitCollectMission",
        "TransportMission", "DeadwoodMission", "TreeTransportMission", "DestructibleRockMission",
        "PlowMission", "SowMission", "StonePickMission", "FertilizeMission", "SprayMission",
        "CultivateMission", "WeedMission", "LimeMission", "RollMission", "HoeMission",
        "MissionStartedEvent", "MissionFinishedEvent", "MissionStartEvent", "MissionCancelEvent", "MissionDismissEvent",
        "InGameMenuContractsFrame", "ContractsFrame", "g_missionManager", "g_inGameMenu",
    }
    for _, name in ipairs(names) do
        out("%s: %s", name, _G[name] ~= nil and type(_G[name]) or "nil")
    end
end

local function dumpMissionTypes()
    out("---- missionTypes")
    if g_missionManager == nil or g_missionManager.missionTypes == nil then
        out("g_missionManager.missionTypes: nil")
        return
    end
    for i, mt in ipairs(g_missionManager.missionTypes) do
        local cls = mt.classObject
        local own = {}
        for _, fn in ipairs({ "getReward", "getRewardPerHa", "tryGenerateMission", "canRun", "getCompletion", "validate", "setEndDate" }) do
            if type(cls) == "table" and rawget(cls, fn) ~= nil then
                own[#own + 1] = fn
            end
        end
        local parent = nil
        if type(cls) == "table" and cls.superClass ~= nil then
            local ok, p = pcall(cls.superClass, cls)
            if ok then
                parent = classNameOf(p)
            end
        end
        out("type[%d] name=%s typeId=%s class=%s parent=%s max=%s num=%s own={%s}",
            i, tostring(mt.name), tostring(mt.typeId), tostring(classNameOf(cls)), tostring(parent),
            tostring(mt.data and mt.data.maxNumInstances), tostring(mt.data and mt.data.numInstances),
            table.concat(own, ","))
    end
end

local function dumpMissions()
    out("---- missions (one instance per type)")
    if g_missionManager == nil or g_missionManager.missions == nil then
        return
    end
    dumpValues("g_missionManager", g_missionManager)
    local seen = {}
    for _, mission in ipairs(g_missionManager.missions) do
        local typeName = mission.type ~= nil and mission.type.name or "?"
        if not seen[typeName] then
            seen[typeName] = true
            out("mission type=%s class=%s", typeName, tostring(classNameOf(mission)))
            dumpValues("  m", mission)
            local ok, minutes = pcall(mission.getMinutesLeft, mission)
            out("  getMinutesLeft=%s", ok and tostring(minutes) or ("ERR " .. tostring(minutes)))
            local ok2, reward = pcall(mission.getReward, mission)
            out("  getReward=%s", ok2 and tostring(reward) or ("ERR " .. tostring(reward)))
        end
    end
end

local function dumpMenuPages()
    out("---- inGameMenu pages")
    if g_inGameMenu == nil or g_inGameMenu.pageFrames == nil then
        out("g_inGameMenu.pageFrames: nil")
        return
    end
    for i, frame in ipairs(g_inGameMenu.pageFrames) do
        out("page[%d] class=%s name=%s", i, tostring(classNameOf(frame)), tostring(frame.name))
    end
end

function ContractManagerDebug:dump()
    self.dumped = true
    out("==== dump start (v%s) ====", tostring(ContractManager.VERSION))
    local steps = { dumpConstants, dumpEnums, dumpGlobals, dumpMissionTypes, dumpMissions, dumpMenuPages }
    for _, step in ipairs(steps) do
        local ok, err = pcall(step)
        if not ok then
            out("step failed: %s", tostring(err))
        end
    end
    out("==== dump end ====")
end

function ContractManagerDebug:loadMap()
    self.armed = true
    self.timer = 0
end

function ContractManagerDebug:deleteMap()
    self.armed = false
    self.dumped = false
end

function ContractManagerDebug:update(dt)
    if not self.armed or self.dumped then
        return
    end
    self.timer = self.timer + dt
    if self.timer >= self.DUMP_DELAY_MS then
        self:dump()
    end
end

if ContractManager ~= nil and ContractManager.debugEnabled then
    addModEventListener(ContractManagerDebug)
    out("armed; dump %d ms after map load", ContractManagerDebug.DUMP_DELAY_MS)
end
