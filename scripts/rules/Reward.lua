--
-- FS25_ContractManager - Reward kurali
--
-- Odul = carpan * oyunun hesapladigi odul, sonra taban/tavan (tavan 0 = yok).
-- Ceza  = basarisiz/iptal/sure asimi kontratta odulun %N'i; getTotalReward'dan duser
--         (oyun bunu dismiss'te addMoney ile oder) ve bitis detaylarinda satir olarak gorunur.
-- Kiralama = getVehicleCosts * leaseCostMultiplier.
--
-- getReward alt siniflarda override edilir ve ust sinifi cagirir; iki seviye sarmalanirsa
-- carpan iki kez uygulanir. Bu yuzden gorev nesnesinde yeniden giris bayragi tutulur:
-- ilk (en dis) cagri carpani uygular, icerideki cagrilar ham degeri gecirir.
--
-- Istemcide de calisir (liste/detay gosterimi); ayarlar SyncEvent ile gelir.
--

ContractManagerReward = {
    wrappedClasses = {},   -- class -> true
}

local Reward = ContractManagerReward

local function settings()
    return ContractManagerSettings
end

function Reward.isEnabled()
    return ContractManager:getRulesEnabled()
end

---Ham odule carpan + taban/tavan uygular
function Reward.apply(base)
    if type(base) ~= "number" then
        return base
    end
    local s = settings()
    local value = base * s:get("reward.multiplier")
    local minReward = s:get("reward.min")
    local maxReward = s:get("reward.max")
    if base > 0 then
        if minReward > 0 and value < minReward then
            value = minReward
        end
        if maxReward > 0 and value > maxReward then
            value = maxReward
        end
    end
    return value
end

---Bitmis ve basarisiz kontrat icin ceza tutari (pozitif sayi), degilse 0
function Reward.getPenalty(mission)
    if not Reward.isEnabled() or mission == nil then
        return 0
    end
    if mission.cmAdminCanceled then
        return 0
    end
    -- DIKKAT: para AbstractMission:dismiss() icinde hesaplanir ve o fonksiyon durumu
    -- ONCE DISMISSED yapar, getTotalReward'i SONRA cagirir. Yalnizca FINISHED kabul
    -- edilirse ceza ekranda gorunur ama HIC KESILMEZ (2026-09-09 canli sunucu).
    -- Gercek olcut asagidaki finishState kontrolu; durum ikisinden biri olabilir.
    if mission.status ~= MissionStatus.FINISHED and mission.status ~= MissionStatus.DISMISSED then
        return 0
    end
    local state = mission.finishState
    if state == nil or state == MissionFinishState.SUCCESS or state == MissionFinishState.NONE then
        return 0
    end
    local percent = Reward.getPenaltyPercent(mission.farmId)
    if percent <= 0 then
        return 0
    end
    local reward = 0
    if mission.getReward ~= nil then
        local ok, value = pcall(mission.getReward, mission)
        if ok and type(value) == "number" then
            reward = value
        end
    end
    return math.max(0, reward * percent / 100)
end

---ardisik basarisizlik serisine gore ceza yuzdesi (ilk basarisizlik taban cezayi kullanir)
function Reward.getPenaltyPercent(farmId)
    local s = settings()
    local base = s:get("reward.failPenaltyPercent") or 0
    local step = s:get("reward.penaltyStepPercent") or 0
    if step <= 0 or farmId == nil or ContractManagerRegistry == nil then
        return base
    end
    local stats = ContractManagerRegistry.stats[farmId]
    local streak = stats ~= nil and (stats.failStreak or 0) or 0
    streak = math.max(0, streak - 1)
    return math.min(s:get("reward.penaltyMaxPercent") or 100, base + streak * step)
end

---basarisiz kontratta tamamlanma oranina gore kismi odeme (0 = yok)
function Reward.getPartialReward(mission)
    if not Reward.isEnabled() or mission == nil or mission.cmAdminCanceled then
        return 0
    end
    if not settings():get("reward.partialEnabled") then
        return 0
    end
    local state = mission.finishState
    if state == nil or state == MissionFinishState.SUCCESS or state == MissionFinishState.NONE then
        return 0
    end
    local completion = tonumber(mission.completion) or 0
    if completion <= 0 or completion < (settings():get("reward.partialMinCompletion") or 0) / 100 then
        return 0
    end
    local reward = 0
    if mission.getReward ~= nil then
        local ok, value = pcall(mission.getReward, mission)
        if ok and type(value) == "number" then
            reward = value
        end
    end
    return math.max(0, reward * math.min(completion, 1) * (settings():get("reward.partialFactor") or 100) / 100)
end

-- ---------------------------------------------------------------------------
-- hook govdeleri
-- ---------------------------------------------------------------------------

function Reward.overwriteGetActualReward(mission, superFunc)
    local value = superFunc(mission)
    if type(value) == "number" and value > 0 then
        return value
    end
    return Reward.getPartialReward(mission)
end

function Reward.overwriteGetReward(mission, superFunc)
    if not Reward.isEnabled() or mission.cmInReward then
        return superFunc(mission)
    end
    mission.cmInReward = true
    local base = superFunc(mission)
    mission.cmInReward = nil
    local value = Reward.apply(base)
    -- itibar bonusu: kabul edilmis kontratta ciftligin puani; kabul oncesi istemcide kendi ciftligi (gosterim)
    if ContractManagerReputation ~= nil and type(value) == "number" and value > 0 then
        local farmId = mission.farmId
        if farmId == nil and g_currentMission ~= nil and not g_currentMission:getIsServer() and g_currentMission.getFarmId ~= nil then
            farmId = g_currentMission:getFarmId()
        end
        local bonus = ContractManagerReputation.getBonusPercent(farmId)
        if bonus > 0 then
            value = value * (1 + bonus / 100)
        end
    end
    if ContractManagerSchedule ~= nil and type(value) == "number" and value > 0 then
        value = value * ContractManagerSchedule.getMultiplier()
    end
    if ContractManagerPricing ~= nil and type(value) == "number" and value > 0 then
        value = value * ContractManagerPricing.getMultiplier(mission)
    end
    if type(value) == "number" and value > 0 then
        local extra = 0
        if ContractManagerChain ~= nil then extra = extra + ContractManagerChain.getBonusPercent(mission) end
        if ContractManagerNpc ~= nil then extra = extra + ContractManagerNpc.getBonusPercent(mission) end
        if extra > 0 then
            value = value * (1 + extra / 100)
        end
    end
    return value
end

function Reward.overwriteGetTotalReward(mission, superFunc)
    local total = superFunc(mission)
    local penalty = Reward.getPenalty(mission)
    if penalty > 0 then
        return total - penalty
    end
    return total
end

function Reward.overwriteGetVehicleCosts(mission, superFunc)
    local costs = superFunc(mission)
    if not Reward.isEnabled() or type(costs) ~= "number" then
        return costs
    end
    return costs * settings():get("reward.leaseCostMultiplier")
end

function Reward.appendedGetFinishedDetails(mission, superFunc)
    local details = superFunc(mission)
    local penalty = Reward.getPenalty(mission)
    if penalty > 0 and type(details) == "table" then
        local title = g_i18n ~= nil and g_i18n:getText("cm_penalty") or "Penalty"
        local value = tostring(penalty)
        if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
            value = g_i18n:formatMoney(penalty, 0, true, true)
        end
        table.insert(details, { title = title, value = value })
    end
    return details
end

---Bir kontrat sinifinin KENDI getReward'ini sarmala (bir kez)
function Reward.wrapClass(cls, name)
    if type(cls) ~= "table" or Reward.wrappedClasses[cls] then
        return false
    end
    local own = rawget(cls, "getReward")
    if type(own) ~= "function" then
        return false
    end
    cls.getReward = Utils.overwrittenFunction(own, Reward.overwriteGetReward)
    Reward.wrappedClasses[cls] = true
    ContractManager.info("Reward hook on %s.getReward", tostring(name))
    return true
end

---Oyun icindeki tum kontrat turlerinin siniflarini sarmala (gorev basinda; sinif
---listesi ancak o zaman dolu)
function Reward.wrapMissionTypes()
    if g_missionManager == nil or g_missionManager.missionTypes == nil then
        return 0
    end
    local count = 0
    for _, missionType in ipairs(g_missionManager.missionTypes) do
        if Reward.wrapClass(missionType.classObject, missionType.name) then
            count = count + 1
        end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- kurulum
-- ---------------------------------------------------------------------------

if AbstractMission ~= nil then
    if AbstractFieldMission ~= nil then
        Reward.wrapClass(AbstractFieldMission, "AbstractFieldMission")
    end
    if AbstractMission.getTotalReward ~= nil then
        AbstractMission.getTotalReward = Utils.overwrittenFunction(AbstractMission.getTotalReward, Reward.overwriteGetTotalReward)
    end
    if AbstractMission.getActualReward ~= nil then
        AbstractMission.getActualReward = Utils.overwrittenFunction(AbstractMission.getActualReward, Reward.overwriteGetActualReward)
    end
    if AbstractMission.getVehicleCosts ~= nil then
        AbstractMission.getVehicleCosts = Utils.overwrittenFunction(AbstractMission.getVehicleCosts, Reward.overwriteGetVehicleCosts)
    end
    if AbstractMission.getFinishedDetails ~= nil then
        AbstractMission.getFinishedDetails = Utils.overwrittenFunction(AbstractMission.getFinishedDetails, Reward.appendedGetFinishedDetails)
    end
    if g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_START ~= nil then
        g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function()
            Reward.wrapMissionTypes()
        end, Reward)
    end
else
    ContractManager.error("AbstractMission missing; reward rule disabled")
end
