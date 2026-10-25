--
-- FS25_ContractManager - biten kontrati kendiliginden kapatma (1.27.0.0, yalnizca sunucu)
--
-- FS25'te biten kontrat (basarili, basarisiz, sure asimi) oyuncu "kapat" diyene kadar panoda kalir; para ve
-- ceza ancak kapatilinca islenir (AbstractMission:dismiss -> getTotalReward). Ana sunucuda oyuncusuz yonetim
-- ciftliginin bir hasat kontrati gun 110'dan beri kapatilmamisti: tarlayi tutuyordu ve basarisiz kontratin
-- cezasi hic kesilmiyordu (kapatmamak cezadan kacmanin yolu oluyordu).
-- Ayar duration.autoCloseHours (oyun saati, 0 = hic): biten kontrat bu sure sonra sunucuda kapatilir. Para
-- oyuncunun "kapat"i ile AYNI yoldan islenir (MissionManager:dismissMission -> dismiss -> getTotalReward;
-- gecmis kaydi, ortak payi ve ceza dahil); ciftlige bildirim gider. Bitis saati sozlesme sartlarinda
-- (Terms.finishedHour) tutulur: kayit yeniden yuklense de sure kaldigi yerden isler, istemci kalan sureyi gorur.
--

ContractManagerAutoClose = {
    CHECK_INTERVAL_MS = 30000,
    timer = 0,
}

local AutoClose = ContractManagerAutoClose

local function settings()
    return ContractManagerSettings
end

function AutoClose.isEnabled()
    return ContractManager:getRulesEnabled() and (settings():get("duration.autoCloseHours") or 0) > 0
end

---Kontratin bitis saati (mutlak oyun saati): sozlesme sartlarindaki, yoksa gecmis kaydindaki; bilinmiyorsa nil
function AutoClose.getFinishedHour(mission)
    local Terms = ContractManagerTerms
    if Terms == nil or mission == nil then
        return nil
    end
    local terms = Terms.get(mission)
    if terms ~= nil and (terms.finishedHour or 0) > 0 then
        return terms.finishedHour
    end
    local entry = ContractManagerReward ~= nil and ContractManagerReward.historyEntry(mission) or nil
    if entry ~= nil and entry.finishedDay ~= nil then
        return Terms.toHour(entry.finishedDay, entry.finishedDayTime)
    end
    return nil
end

---Kapanmaya kalan oyun saati (saf). nil = kapanmaz ya da bitis saati bilinmiyor.
function AutoClose.hoursLeft(finishedHour, nowHour, limitHours)
    if finishedHour == nil or limitHours == nil or limitHours <= 0 then
        return nil
    end
    return math.max(0, finishedHour + limitHours - (nowHour or 0))
end

---Ayrinti satiri icin (istemcide de): bitmis kontratin kapanmasina kalan oyun saati, yoksa nil
function AutoClose.getHoursLeft(mission)
    if mission == nil or mission.status ~= MissionStatus.FINISHED or not AutoClose.isEnabled() or ContractManagerTerms == nil then
        return nil
    end
    return AutoClose.hoursLeft(AutoClose.getFinishedHour(mission), ContractManagerTerms.nowHour(),
        settings():get("duration.autoCloseHours"))
end

---Suresi dolan bitmis kontratlar (saf; test edilir). Kapatma listeyi degistirdigi icin once toplanir.
function AutoClose.findDue(missions, nowHour, limitHours)
    local due = {}
    for _, mission in ipairs(missions or {}) do
        if mission.status == MissionStatus.FINISHED then
            local left = AutoClose.hoursLeft(AutoClose.getFinishedHour(mission), nowHour, limitHours)
            if left ~= nil and left <= 0 then
                due[#due + 1] = mission
            end
        end
    end
    return due
end

---Sunucu: kontrati oyuncunun "kapat"i ile ayni yoldan kapat. Donus: kapatildi mi
function AutoClose.close(mission)
    if mission == nil or g_missionManager == nil or g_missionManager.dismissMission == nil then
        return false
    end
    local farmId = mission.farmId
    if farmId == nil or farmId == 0 then
        return false
    end
    -- silinmis ciftlik: para yazilacak yer yok, kontrati oyun kendisi kaldirir
    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil and g_farmManager:getFarmById(farmId) == nil then
        return false
    end
    local title = mission.title or (mission.getTitle ~= nil and mission:getTitle()) or "?"
    local amount = mission.getTotalReward ~= nil and (tonumber(mission:getTotalReward()) or 0) or 0
    local key = ContractManager.getMissionKey(mission)
    local ok = ContractManager.guard("Contract auto close", g_missionManager.dismissMission, g_missionManager, mission)
    if not ok then
        return false
    end
    amount = math.floor(amount + 0.5)
    ContractManager.info("Contract %s auto-closed for farm %s: %d", tostring(key), tostring(farmId), amount)
    if ContractManagerNotificationEvent ~= nil and ContractManagerNotificationEvent.AUTO_CLOSED ~= nil then
        ContractManagerNotificationEvent.sendToFarm(ContractManagerNotificationEvent.AUTO_CLOSED, farmId, tostring(title), amount)
    end
    ContractManager.publish(ContractManager.MESSAGE_CONTRACT_AUTO_CLOSED, mission, amount)
    return true
end

function AutoClose:update(dt)
    local current = g_currentMission
    if current == nil or not current:getIsServer() then
        return
    end
    AutoClose.timer = AutoClose.timer + (dt or 0)
    if AutoClose.timer < AutoClose.CHECK_INTERVAL_MS then
        return
    end
    AutoClose.timer = 0
    if not AutoClose.isEnabled() or g_missionManager == nil or ContractManagerTerms == nil then
        return
    end
    local due = AutoClose.findDue(g_missionManager.missions, ContractManagerTerms.nowHour(),
        settings():get("duration.autoCloseHours"))
    for _, mission in ipairs(due) do
        AutoClose.close(mission)
    end
end

function AutoClose:loadMap()
    AutoClose.timer = 0
end

function AutoClose:deleteMap()
    AutoClose.timer = 0
end

addModEventListener(AutoClose)
