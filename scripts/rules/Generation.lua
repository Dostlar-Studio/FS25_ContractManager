--
-- FS25_ContractManager - Generation kurali (yalnizca sunucu; uretim sunucuda olur)
--
-- * Toplam kontrat sayisi: MissionManager.MAX_MISSIONS (0 = oyun varsayilani, tavan 80).
-- * Yenileme araligi: MISSION_GENERATION_INTERVAL = orijinal * refreshMultiplier.
-- * Tur basina ust sinir: missionType.data.maxNumInstances (0 = oyun varsayilani).
-- * Tur acik/kapali ve goreli agirlik: her turun statik tryGenerateMission'i sarmalanir.
--   Agirlik goreli: p = weight / (etkin turler arasindaki en buyuk weight). Hepsi 1.0 iken
--   davranis degismez; bir turu 2.0 yapmak digerlerini yari olasilikla dener.
--
-- Orijinal sabitler ilk uygulamada saklanir; ayar 0'a donerse geri yazilir.
--

ContractManagerGeneration = {
    MAX_TOTAL_CAP = 80,
    originals = nil,      -- { maxMissions, interval }
    originalMaxPerType = {}, -- typeName -> oyunun varsayilani
    wrapped = {},         -- class -> true
    applied = false,
}

local Generation = ContractManagerGeneration

local function settings()
    return ContractManagerSettings
end

function Generation.isEnabled()
    return ContractManager:getRulesEnabled()
end

function Generation.captureOriginals()
    if Generation.originals ~= nil or MissionManager == nil then
        return
    end
    Generation.originals = {
        maxMissions = MissionManager.MAX_MISSIONS,
        interval = MissionManager.MISSION_GENERATION_INTERVAL,
    }
end

---Sabitleri ve tur ust sinirlarini ayara gore yaz
function Generation.applyConstants()
    if MissionManager == nil then
        return
    end
    Generation.captureOriginals()
    local orig = Generation.originals
    local s = settings()

    if not Generation.isEnabled() then
        if type(orig.maxMissions) == "number" then MissionManager.MAX_MISSIONS = orig.maxMissions end
        if type(orig.interval) == "number" then MissionManager.MISSION_GENERATION_INTERVAL = orig.interval end
    else
        local maxTotal = s:get("generation.maxTotal")
        if maxTotal > 0 then
            MissionManager.MAX_MISSIONS = math.min(maxTotal, Generation.MAX_TOTAL_CAP)
        elseif type(orig.maxMissions) == "number" then
            MissionManager.MAX_MISSIONS = orig.maxMissions
        end
        if type(orig.interval) == "number" then
            MissionManager.MISSION_GENERATION_INTERVAL = orig.interval * s:get("generation.refreshMultiplier")
        end
    end

    if g_missionManager ~= nil and g_missionManager.missionTypes ~= nil then
        local maxPerType = Generation.isEnabled() and s:get("generation.maxPerType") or 0
        for _, missionType in ipairs(g_missionManager.missionTypes) do
            if missionType.data ~= nil then
                if Generation.originalMaxPerType[missionType.name] == nil then
                    Generation.originalMaxPerType[missionType.name] = missionType.data.maxNumInstances
                end
                if maxPerType > 0 then
                    missionType.data.maxNumInstances = maxPerType
                else
                    missionType.data.maxNumInstances = Generation.originalMaxPerType[missionType.name]
                end
            end
        end
    end
    Generation.applied = true
end

---Etkin turler arasindaki en buyuk agirlik (goreli olasilik icin payda)
function Generation.getMaxWeight()
    local maxWeight = 0
    if g_missionManager ~= nil and g_missionManager.missionTypes ~= nil then
        for _, missionType in ipairs(g_missionManager.missionTypes) do
            local enabled, weight = settings():getTypeConfig(missionType.name)
            if enabled and weight > maxWeight then
                maxWeight = weight
            end
        end
    end
    if maxWeight <= 0 then
        maxWeight = 1
    end
    return maxWeight
end

---Bu tur simdi uretilmeye calisilsin mi?
function Generation.shouldAttempt(typeName, randomValue)
    if not Generation.isEnabled() then
        return true
    end
    local enabled, weight = settings():getTypeConfig(typeName)
    if not enabled or weight <= 0 then
        return false
    end
    local p = weight / Generation.getMaxWeight()
    if p >= 1 then
        return true
    end
    randomValue = randomValue or math.random()
    return randomValue < p
end

function Generation.wrapMissionType(missionType)
    local cls = missionType.classObject
    if type(cls) ~= "table" or Generation.wrapped[cls] then
        return false
    end
    local original = rawget(cls, "tryGenerateMission")
    if type(original) ~= "function" then
        return false
    end
    local typeName = missionType.name
    cls.tryGenerateMission = function(...)
        if not Generation.shouldAttempt(typeName) then
            return nil
        end
        return original(...)
    end
    Generation.wrapped[cls] = true
    return true
end

function Generation.wrapMissionTypes()
    if g_missionManager == nil or g_missionManager.missionTypes == nil then
        return 0
    end
    local count = 0
    for _, missionType in ipairs(g_missionManager.missionTypes) do
        if Generation.wrapMissionType(missionType) then
            count = count + 1
        end
    end
    return count
end

function Generation.onMissionStart()
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() then
        return
    end
    Generation.applyConstants()
    local wrapped = Generation.wrapMissionTypes()
    ContractManager.info("Generation rule: MAX_MISSIONS=%s interval=%s wrappedTypes=%d enabled=%s",
        tostring(MissionManager.MAX_MISSIONS), tostring(MissionManager.MISSION_GENERATION_INTERVAL), wrapped, tostring(Generation.isEnabled()))
end

function Generation.onSettingsChanged()
    local mission = g_currentMission
    if mission ~= nil and mission:getIsServer() and Generation.applied then
        Generation.applyConstants()
    end
end

if MissionManager ~= nil and g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_START ~= nil then
    g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function() Generation.onMissionStart() end, Generation)
    g_messageCenter:subscribe(ContractManager.MESSAGE_SETTINGS_CHANGED, function() Generation.onSettingsChanged() end, Generation)
else
    ContractManager.error("MissionManager or message center missing; generation rule disabled")
end
