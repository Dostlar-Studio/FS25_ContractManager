--
-- FS25_ContractManager - Limits kurali
--
-- Ciftlik basina ayni anda aktif kontrat limiti. MissionManager:startMission icinde
-- hasFarmReachedMissionLimit cagrilir ve LIMIT_REACHED donerse oyun kendi uyarisini
-- gosterir; startMission'a dokunmaya gerek yok. 0 = sinirsiz.
-- MAX_MISSIONS_PER_FARM sabiti de guncellenir (arayuz metinleri bunu okuyabilir).
--

ContractManagerLimits = {
    originalMaxPerFarm = nil,
}

local Limits = ContractManagerLimits

function Limits.getFarmLimit()
    if not ContractManager:getRulesEnabled() then
        return nil -- oyunun kendi kurali
    end
    return ContractManagerSettings:get("limits.maxActivePerFarm")
end

function Limits.countStarted(manager, farmId)
    local total = 0
    for _, mission in ipairs(manager.missions or {}) do
        if mission.farmId == farmId then
            local started = true
            if mission.getWasStarted ~= nil then
                started = mission:getWasStarted()
            elseif mission.status ~= nil then
                started = mission.status ~= MissionStatus.CREATED
            end
            if started then
                total = total + 1
            end
        end
    end
    return total
end

function Limits.overwriteHasFarmReachedMissionLimit(manager, superFunc, farmId)
    local limit = Limits.getFarmLimit()
    if limit == nil then
        return superFunc(manager, farmId)
    end
    if limit <= 0 then
        return false
    end
    if ContractManagerReputation ~= nil then
        limit = limit + ContractManagerReputation.getExtraSlots(farmId)
    end
    return Limits.countStarted(manager, farmId) >= limit
end

---Sabiti ayara gore yaz (ayar degisince de cagrilir)
function Limits.applyConstant()
    if MissionManager == nil then
        return
    end
    if Limits.originalMaxPerFarm == nil and type(MissionManager.MAX_MISSIONS_PER_FARM) == "number" then
        Limits.originalMaxPerFarm = MissionManager.MAX_MISSIONS_PER_FARM
    end
    local limit = Limits.getFarmLimit()
    if limit == nil then
        if Limits.originalMaxPerFarm ~= nil then
            MissionManager.MAX_MISSIONS_PER_FARM = Limits.originalMaxPerFarm
        end
    elseif limit > 0 then
        MissionManager.MAX_MISSIONS_PER_FARM = limit
    else
        MissionManager.MAX_MISSIONS_PER_FARM = 999
    end
end

if MissionManager ~= nil and MissionManager.hasFarmReachedMissionLimit ~= nil then
    MissionManager.hasFarmReachedMissionLimit = Utils.overwrittenFunction(MissionManager.hasFarmReachedMissionLimit, Limits.overwriteHasFarmReachedMissionLimit)
    if g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_START ~= nil then
        g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function() Limits.applyConstant() end, Limits)
        g_messageCenter:subscribe(ContractManager.MESSAGE_SETTINGS_CHANGED, function() Limits.applyConstant() end, Limits)
    end
else
    ContractManager.error("MissionManager.hasFarmReachedMissionLimit missing; limit rule disabled")
end
