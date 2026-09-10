--
-- FS25_ContractManager - Itibar (ciftlik puani)
--
-- Her ciftligin puani Registry istatistiginde tutulur (stats.reputation):
--   tamamlanan +gainComplete, basarisiz -lossFail, iptal -lossCancel, sure asimi -lossTimeout.
--   Puan [-maxPoints, maxPoints] arasinda kirpilir. Admin zorla iptali puan dusurmez.
-- Etkileri:
--   * Odul bonusu: puan > 0 iken odule (puan / maxPoints) * rewardBonusMaxPercent kadar ek.
--   * Ek kontrat hakki: puan >= extraSlotAt iken ciftlik limiti +1.
-- Sunucu puani hesaplar; istemciler kendi ciftliklerinin puanini REPUTATION bildirimiyle
-- ve StatsEvent ile alir (odul gosterimi icin). Odeme her zaman sunucuda hesaplanir.
--

ContractManagerReputation = {
    MIN_POINTS = -100,
    localReputation = {},   -- istemci: farmId -> puan (senkron kopya)
}

local Rep = ContractManagerReputation

local function settings()
    return ContractManagerSettings
end

function Rep.isEnabled()
    return ContractManager:getRulesEnabled() and settings():get("reputation.enabled") == true
end

function Rep.clamp(value)
    local maxPoints = settings():get("reputation.maxPoints") or 100
    return math.max(Rep.MIN_POINTS, math.min(maxPoints, value))
end

---puan farki (finishState'e gore)
function Rep.getDelta(finishState, adminCanceled)
    if adminCanceled then
        return 0
    end
    local s = settings()
    if finishState == MissionFinishState.SUCCESS then
        return s:get("reputation.gainComplete")
    elseif finishState == MissionFinishState.CANCELED then
        return -s:get("reputation.lossCancel")
    elseif finishState == MissionFinishState.TIMED_OUT then
        return -s:get("reputation.lossTimeout")
    end
    return -s:get("reputation.lossFail")
end

---sunucu: ciftlik puani (Registry'den); istemci: senkron kopya
function Rep.getReputation(farmId)
    if farmId == nil then
        return 0
    end
    if g_currentMission ~= nil and g_currentMission:getIsServer() and ContractManagerRegistry ~= nil then
        local stats = ContractManagerRegistry.stats[farmId]
        return stats ~= nil and (stats.reputation or 0) or 0
    end
    return Rep.localReputation[farmId] or 0
end

---odul bonusu yuzdesi (0..rewardBonusMaxPercent)
function Rep.getBonusPercent(farmId)
    if not Rep.isEnabled() then
        return 0
    end
    local points = Rep.getReputation(farmId)
    if points <= 0 then
        return 0
    end
    local maxPoints = settings():get("reputation.maxPoints") or 100
    local maxBonus = settings():get("reputation.rewardBonusMaxPercent") or 0
    return math.min(points, maxPoints) / maxPoints * maxBonus
end

---ek kontrat hakki (0 veya 1)
function Rep.getExtraSlots(farmId)
    if not Rep.isEnabled() then
        return 0
    end
    local threshold = settings():get("reputation.extraSlotAt") or 0
    if threshold <= 0 then
        return 0
    end
    return Rep.getReputation(farmId) >= threshold and 1 or 0
end

---sunucu: kontrat bitince puani guncelle ve ciftlige bildir
function Rep.onMissionFinished(mission, entry)
    if not Rep.isEnabled() or mission == nil or entry == nil or ContractManagerRegistry == nil then
        return
    end
    local delta = Rep.getDelta(entry.finishState, mission.cmAdminCanceled)
    if delta == 0 then
        return
    end
    Rep.applyDelta(entry.farmId, delta)

    -- ortak kontrat: ortaklara yarim puan (asagi yuvarlanir)
    if ContractManagerPartnership ~= nil then
        local half = delta >= 0 and math.floor(delta / 2) or -math.floor(-delta / 2)
        if half ~= 0 then
            for _, farmId in ipairs(ContractManagerPartnership.getFarms(mission)) do
                if farmId ~= entry.farmId then
                    Rep.applyDelta(farmId, half)
                end
            end
        end
    end
end

---bir ciftligin puanini degistir ve bildir
function Rep.applyDelta(farmId, delta)
    if farmId == nil or delta == 0 or ContractManagerRegistry == nil then
        return
    end
    local stats = ContractManagerRegistry:getFarmStats(farmId)
    local before = stats.reputation or 0
    stats.reputation = Rep.clamp(before + delta)
    if stats.reputation ~= before then
        ContractManager.info("Reputation farm %s: %d -> %d (%+d)", tostring(farmId), before, stats.reputation, delta)
        if ContractManagerNotificationEvent ~= nil and ContractManagerNotificationEvent.REPUTATION ~= nil then
            ContractManagerNotificationEvent.sendToFarm(ContractManagerNotificationEvent.REPUTATION, farmId, tostring(delta), stats.reputation)
        end
        ContractManager.publish(ContractManager.MESSAGE_REPUTATION_CHANGED, farmId, stats.reputation, delta)
    end
end

---istemci: senkron kopyayi guncelle
function Rep.setLocal(farmId, points)
    if farmId ~= nil and type(points) == "number" then
        Rep.localReputation[farmId] = points
    end
end

if g_messageCenter ~= nil and ContractManager.MESSAGE_CONTRACT_FINISHED ~= nil then
    g_messageCenter:subscribe(ContractManager.MESSAGE_CONTRACT_FINISHED, function(_, mission, entry)
        Rep.onMissionFinished(mission, entry)
    end, Rep)
end
