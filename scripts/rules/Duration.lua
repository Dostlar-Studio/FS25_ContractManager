--
-- FS25_ContractManager - Duration kurali
--
-- * Sure carpani: kontrat uretilirken verilen bitis tarihi, "simdi"ye gore kalan sureyi
--   carpanla olcekleyerek yeniden yazilir. setEndDate savegame yuklemede ve readStream'de
--   de cagrildigi icin o cagrilar bayrakla atlanir (o degerler zaten olcekli).
-- * Bitis uyarisi (yalnizca sunucu): calisan kontratlarda kalan dakika esiklerden birinin
--   altina inince ciftlige bir kez bildirim gider. Esikler "60,15" gibi oyun dakikasi.
--

ContractManagerDuration = {
    CHECK_INTERVAL_MS = 30000,
    timer = 0,
    thresholds = nil,
    thresholdsSource = nil,
}

local Duration = ContractManagerDuration

local function settings()
    return ContractManagerSettings
end

function Duration.isEnabled()
    return ContractManager:getRulesEnabled()
end

---"60,15" -> {60, 15} (buyukten kucuge, gecersizler atilir)
function Duration.parseThresholds(text)
    local list = {}
    if type(text) == "string" then
        for token in string.gmatch(text, "[^,;%s]+") do
            local value = tonumber(token)
            if value ~= nil and value > 0 then
                list[#list + 1] = value
            end
        end
    end
    table.sort(list, function(a, b) return a > b end)
    return list
end

function Duration.getThresholds()
    local source = settings():get("duration.warnAtMinutes")
    if Duration.thresholds == nil or Duration.thresholdsSource ~= source then
        Duration.thresholds = Duration.parseThresholds(source)
        Duration.thresholdsSource = source
    end
    return Duration.thresholds
end

-- ---------------------------------------------------------------------------
-- sure carpani
-- ---------------------------------------------------------------------------

function Duration.overwriteSetEndDate(mission, superFunc, endDay, endDayTime)
    superFunc(mission, endDay, endDayTime)

    if not Duration.isEnabled() or mission.cmLoadingEndDate or mission.cmDurationApplied then
        return
    end
    if mission.status ~= nil and mission.status ~= MissionStatus.CREATED then
        return
    end
    local multiplier = settings():get("duration.multiplier")
    if multiplier == 1 or mission.getMinutesLeft == nil or mission.setEndDateByOffset == nil then
        return
    end

    local minutesLeft = mission:getMinutesLeft()
    if type(minutesLeft) ~= "number" or minutesLeft <= 0 then
        return
    end

    mission.cmDurationApplied = true
    mission:setEndDateByOffset(minutesLeft * multiplier * 60 * 1000)
end

local function markLoading(mission, superFunc, ...)
    mission.cmLoadingEndDate = true
    local a, b, c = superFunc(mission, ...)
    mission.cmLoadingEndDate = nil
    mission.cmDurationApplied = true -- yuklenen kontratin suresi bir daha olceklenmez
    return a, b, c
end

Duration.overwriteLoadFromXMLFile = markLoading
Duration.overwriteReadStream = markLoading

-- ---------------------------------------------------------------------------
-- bitis uyarisi
-- ---------------------------------------------------------------------------

function Duration.checkMission(mission, thresholds)
    if mission.farmId == nil or mission.getMinutesLeft == nil then
        return
    end
    local running = true
    if mission.getIsRunning ~= nil then
        running = mission:getIsRunning()
    elseif mission.status ~= nil then
        running = mission.status == MissionStatus.RUNNING
    end
    if not running then
        return
    end
    local minutesLeft = mission:getMinutesLeft()
    if type(minutesLeft) ~= "number" then
        return
    end
    mission.cmWarned = mission.cmWarned or {}
    for _, threshold in ipairs(thresholds) do
        if minutesLeft <= threshold and not mission.cmWarned[threshold] then
            mission.cmWarned[threshold] = true
            local title = mission.title or (mission.getTitle ~= nil and mission:getTitle()) or "?"
            ContractManagerNotificationEvent.sendToFarm(ContractManagerNotificationEvent.TIME_WARNING, mission.farmId, tostring(title), math.floor(minutesLeft))
            ContractManager.publish(ContractManager.MESSAGE_CONTRACT_WARNING, mission, math.floor(minutesLeft))
            return -- ayni turda tek uyari
        end
    end
end

function Duration:update(dt)
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() or not Duration.isEnabled() then
        return
    end
    self.timer = self.timer + dt
    if self.timer < self.CHECK_INTERVAL_MS then
        return
    end
    self.timer = 0

    local thresholds = self.getThresholds()
    if #thresholds == 0 or g_missionManager == nil or g_missionManager.missions == nil then
        return
    end
    for _, m in ipairs(g_missionManager.missions) do
        self.checkMission(m, thresholds)
    end
end

function Duration:loadMap()
    self.timer = 0
end

function Duration:deleteMap()
    self.timer = 0
end

if AbstractMission ~= nil and AbstractMission.setEndDate ~= nil then
    AbstractMission.setEndDate = Utils.overwrittenFunction(AbstractMission.setEndDate, Duration.overwriteSetEndDate)
    if AbstractMission.loadFromXMLFile ~= nil then
        AbstractMission.loadFromXMLFile = Utils.overwrittenFunction(AbstractMission.loadFromXMLFile, Duration.overwriteLoadFromXMLFile)
    end
    if AbstractMission.readStream ~= nil then
        AbstractMission.readStream = Utils.overwrittenFunction(AbstractMission.readStream, Duration.overwriteReadStream)
    end
    addModEventListener(Duration)
else
    ContractManager.error("AbstractMission.setEndDate missing; duration rule disabled")
end
