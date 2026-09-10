--
-- FS25_ContractManager - Kontrat kotasi (yalnizca sunucu)
--
-- Ciftlik basina donem basina kabul edilebilecek kontrat sayisi:
--   limits#quotaPerDay   : oyun gunu basina (0 = kapali)
--   limits#quotaPerMonth : oyun ayi basina (0 = kapali; ay = daysPerPeriod gun)
-- Sayaclar Registry.quota'da tutulur, donem anahtari degisince sifirlanir ve savegame'e
-- yazilir. Kota dolunca startMission LIMIT_REACHED doner ve ciftlige bildirim gider.
--
-- Aktif kontrat limitinden (limits#maxActivePerFarm) farklidir: o "ayni anda kac tane",
-- bu "bu donemde kac tane kabul edildi".
--

ContractManagerQuota = {}

local Quota = ContractManagerQuota

local function settings()
    return ContractManagerSettings
end

function Quota.isEnabled()
    return ContractManager:getRulesEnabled()
end

---donem anahtarlari: gun ve ay (oyun takvimi)
function Quota.getPeriodKeys()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then
        return 0, 0
    end
    local day = env.currentMonotonicDay or 0
    local daysPerPeriod = env.daysPerPeriod
    if type(daysPerPeriod) ~= "number" or daysPerPeriod < 1 then
        daysPerPeriod = 1
    end
    return day, math.floor(day / daysPerPeriod)
end

---ciftligin sayac kaydi; donem degistiyse sifirlanir
function Quota.getRecord(farmId)
    if ContractManagerRegistry == nil or farmId == nil then
        return nil
    end
    local dayKey, monthKey = Quota.getPeriodKeys()
    local record = ContractManagerRegistry.quota[farmId]
    if record == nil then
        record = { dayKey = dayKey, dayCount = 0, monthKey = monthKey, monthCount = 0 }
        ContractManagerRegistry.quota[farmId] = record
    end
    if record.dayKey ~= dayKey then
        record.dayKey, record.dayCount = dayKey, 0
    end
    if record.monthKey ~= monthKey then
        record.monthKey, record.monthCount = monthKey, 0
    end
    return record
end

---kota doldu mu? Donus: doldu mu, "day"/"month", sinir
function Quota.isExceeded(farmId)
    if not Quota.isEnabled() then
        return false
    end
    local record = Quota.getRecord(farmId)
    if record == nil then
        return false
    end
    local perDay = settings():get("limits.quotaPerDay") or 0
    if perDay > 0 and record.dayCount >= perDay then
        return true, "day", perDay
    end
    local perMonth = settings():get("limits.quotaPerMonth") or 0
    if perMonth > 0 and record.monthCount >= perMonth then
        return true, "month", perMonth
    end
    return false
end

function Quota.count(farmId)
    local record = Quota.getRecord(farmId)
    if record ~= nil then
        record.dayCount = record.dayCount + 1
        record.monthCount = record.monthCount + 1
    end
end

---kalan hak (gosterim icin): gun, ay; sinirsizsa nil
function Quota.getRemaining(farmId)
    if not Quota.isEnabled() then
        return nil, nil
    end
    local record = Quota.getRecord(farmId)
    if record == nil then
        return nil, nil
    end
    local perDay = settings():get("limits.quotaPerDay") or 0
    local perMonth = settings():get("limits.quotaPerMonth") or 0
    local day = perDay > 0 and math.max(0, perDay - record.dayCount) or nil
    local month = perMonth > 0 and math.max(0, perMonth - record.monthCount) or nil
    return day, month
end

function Quota.overwriteStartMission(manager, superFunc, mission, farmId, spawnVehicles)
    local exceeded, period, limit = Quota.isExceeded(farmId)
    if exceeded then
        if ContractManagerNotificationEvent ~= nil and ContractManagerNotificationEvent.QUOTA ~= nil then
            ContractManagerNotificationEvent.sendToFarm(ContractManagerNotificationEvent.QUOTA, farmId, period, limit)
        end
        ContractManager.info("Contract refused for farm %s: %s quota %d reached", tostring(farmId), tostring(period), limit)
        return MissionStartState.LIMIT_REACHED
    end
    local result = superFunc(manager, mission, farmId, spawnVehicles)
    if result == MissionStartState.OK then
        Quota.count(farmId)
    end
    return result
end

if MissionManager ~= nil and MissionManager.startMission ~= nil then
    MissionManager.startMission = Utils.overwrittenFunction(MissionManager.startMission, Quota.overwriteStartMission)
end
