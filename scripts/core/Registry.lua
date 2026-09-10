--
-- FS25_ContractManager - Registry
--
-- Kontrat yasam dongusunu izler (sunucu):
--   startMission OK  -> active[uniqueId] = kabul meta'si
--   finish           -> history'ye kayit, ciftlik istatistigi
--   dismiss          -> gercek odeme (getTotalReward) kayda islenir, active'den duser
-- Durum Persistence uzerinden savegame'e yazilir. Istemci kopyasi Faz 4'te (GUI)
-- senkron edilir; simdilik yalnizca sunucuda dolu.
--

ContractManagerRegistry = {
    HISTORY_LIMIT = 200,
    active = {},     -- uniqueId -> meta
    history = {},    -- dizi, en yeni sonda
    stats = {},      -- farmId -> { completed, failed, canceled, timedOut, earned, penalties, reputation }
    fieldCooldowns = {}, -- fieldId -> oyun saati (bitis)
    quota = {},          -- farmId -> { dayKey, dayCount, monthKey, monthCount }
    fieldChain = {},     -- fieldId -> { farmId, step, day }
    npcJobs = {},        -- farmId -> { npcKey -> sayac }
}

local Registry = ContractManagerRegistry

-- ---------------------------------------------------------------------------
-- yardimcilar
-- ---------------------------------------------------------------------------

local function getGameClock()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then
        return 0, 0
    end
    return env.currentMonotonicDay or 0, env.dayTime or 0
end

local function getMissionId(mission)
    if mission == nil then
        return nil
    end
    if mission.getUniqueId ~= nil then
        local id = mission:getUniqueId()
        if id ~= nil then
            return tostring(id)
        end
    end
    if mission.uniqueId ~= nil then
        return tostring(mission.uniqueId)
    end
    return nil
end

local function getTypeName(mission)
    if mission.type ~= nil and mission.type.name ~= nil then
        return mission.type.name
    end
    if mission.getMissionTypeName ~= nil then
        local name = mission:getMissionTypeName()
        if name ~= nil then
            return name
        end
    end
    return "unknown"
end

local function getFieldId(mission)
    local field = mission.field
    if field == nil then
        return 0
    end
    if field.getId ~= nil then
        local id = field:getId()
        if type(id) == "number" then
            return id
        end
    end
    if type(field.fieldId) == "number" then
        return field.fieldId
    end
    return 0
end

local function getReward(mission)
    if mission.getReward ~= nil then
        local reward = mission:getReward()
        if type(reward) == "number" then
            return reward
        end
    end
    return tonumber(mission.reward) or 0
end

local function getTotalReward(mission)
    if mission.getTotalReward ~= nil then
        local total = mission:getTotalReward()
        if type(total) == "number" then
            return total
        end
    end
    return 0
end

local function getCompletion(mission)
    if type(mission.completion) == "number" then
        return mission.completion
    end
    return 0
end

function Registry.newStats()
    return { completed = 0, failed = 0, canceled = 0, timedOut = 0, earned = 0, penalties = 0, reputation = 0, failStreak = 0 }
end

function Registry:getFarmStats(farmId)
    local stats = self.stats[farmId]
    if stats == nil then
        stats = self.newStats()
        self.stats[farmId] = stats
    end
    return stats
end

function Registry:getActiveMeta(mission)
    local id = getMissionId(mission)
    return id ~= nil and self.active[id] or nil
end

---Ciftlige gore gecmis (en yeni once). farmId nil ise hepsi.
function Registry:getHistory(farmId)
    local result = {}
    for i = #self.history, 1, -1 do
        local entry = self.history[i]
        if farmId == nil or entry.farmId == farmId then
            result[#result + 1] = entry
        end
    end
    return result
end

function Registry:findHistoryEntry(id)
    for i = #self.history, 1, -1 do
        if self.history[i].id == id then
            return self.history[i]
        end
    end
    return nil
end

function Registry:reset()
    self.active = {}
    self.history = {}
    self.stats = {}
    self.fieldCooldowns = {}
    self.quota = {}
    self.fieldChain = {}
    self.npcJobs = {}
end

-- ---------------------------------------------------------------------------
-- yasam dongusu
-- ---------------------------------------------------------------------------

function Registry:onMissionStarted(mission, farmId)
    local id = getMissionId(mission)
    if id == nil then
        return
    end
    local day, dayTime = getGameClock()
    self.active[id] = {
        id = id,
        typeName = getTypeName(mission),
        farmId = farmId or mission.farmId or 0,
        fieldId = getFieldId(mission),
        acceptedDay = day,
        acceptedDayTime = dayTime,
        rewardAtAccept = getReward(mission),
    }
    ContractManager.info("Contract %s (%s) accepted by farm %s", id, self.active[id].typeName, tostring(self.active[id].farmId))
    ContractManager.publish(ContractManager.MESSAGE_CONTRACT_ACCEPTED, mission, self.active[id])
end

function Registry:onMissionFinished(mission, finishState)
    local id = getMissionId(mission)
    if id == nil then
        return
    end
    local meta = self.active[id]
    if meta == nil then
        -- savegame'den once kabul edilmis ve kaydi olmayan kontrat: asgari meta
        meta = {
            id = id, typeName = getTypeName(mission), farmId = mission.farmId or 0,
            fieldId = getFieldId(mission), acceptedDay = 0, acceptedDayTime = 0, rewardAtAccept = 0,
        }
    end

    local day, dayTime = getGameClock()
    local entry = {
        id = id,
        typeName = meta.typeName,
        farmId = meta.farmId,
        fieldId = meta.fieldId,
        acceptedDay = meta.acceptedDay,
        acceptedDayTime = meta.acceptedDayTime,
        finishedDay = day,
        finishedDayTime = dayTime,
        finishState = finishState or 0,
        reward = getReward(mission),
        completion = getCompletion(mission),
        payout = nil, -- dismiss'te dolar
    }
    self.history[#self.history + 1] = entry
    while #self.history > self.HISTORY_LIMIT do
        table.remove(self.history, 1)
    end

    local stats = self:getFarmStats(entry.farmId)
    if not mission.cmAdminCanceled then
        if finishState == MissionFinishState.SUCCESS then
            stats.failStreak = 0
        else
            stats.failStreak = (stats.failStreak or 0) + 1
        end
    end
    if finishState == MissionFinishState.SUCCESS then
        stats.completed = stats.completed + 1
    elseif finishState == MissionFinishState.CANCELED then
        stats.canceled = stats.canceled + 1
    elseif finishState == MissionFinishState.TIMED_OUT then
        stats.timedOut = stats.timedOut + 1
    else
        stats.failed = stats.failed + 1
    end

    self.active[id] = nil
    ContractManager.info("Contract %s finished state=%s farm=%s reward=%d", id, tostring(finishState), tostring(entry.farmId), entry.reward)
    ContractManager.publish(ContractManager.MESSAGE_CONTRACT_FINISHED, mission, entry)
end

function Registry:onMissionDismissed(mission)
    local id = getMissionId(mission)
    if id == nil then
        return
    end
    self.active[id] = nil
    local entry = self:findHistoryEntry(id)
    if entry == nil or entry.payout ~= nil then
        return
    end
    entry.payout = getTotalReward(mission)
    local stats = self:getFarmStats(entry.farmId)
    if entry.payout >= 0 then
        stats.earned = stats.earned + entry.payout
    else
        stats.penalties = stats.penalties - entry.payout
    end
    ContractManager.publish(ContractManager.MESSAGE_CONTRACT_PAID, mission, entry)
end

-- ---------------------------------------------------------------------------
-- savegame (eski XML API; Persistence xmlId ve temel anahtari verir)
-- ---------------------------------------------------------------------------

local ACTIVE_FIELDS = { "typeName", "farmId", "fieldId", "acceptedDay", "acceptedDayTime", "rewardAtAccept" }
local HISTORY_FIELDS = { "typeName", "farmId", "fieldId", "acceptedDay", "acceptedDayTime",
    "finishedDay", "finishedDayTime", "finishState", "reward", "completion", "payout" }

local function writeRecord(xmlId, key, record, fields)
    setXMLString(xmlId, key .. "#id", record.id)
    for _, field in ipairs(fields) do
        local value = record[field]
        if type(value) == "string" then
            setXMLString(xmlId, key .. "#" .. field, value)
        elseif type(value) == "number" then
            setXMLFloat(xmlId, key .. "#" .. field, value)
        end
    end
end

local function readRecord(xmlId, key, fields)
    local id = getXMLString(xmlId, key .. "#id")
    if id == nil then
        return nil
    end
    local record = { id = id }
    for _, field in ipairs(fields) do
        if field == "typeName" then
            record[field] = getXMLString(xmlId, key .. "#" .. field) or "unknown"
        else
            record[field] = getXMLFloat(xmlId, key .. "#" .. field)
        end
    end
    return record
end

function Registry:writeToXML(xmlId, baseKey)
    local ids = {}
    for id in pairs(self.active) do
        ids[#ids + 1] = id
    end
    table.sort(ids)
    for i, id in ipairs(ids) do
        writeRecord(xmlId, string.format("%s.active.mission(%d)", baseKey, i - 1), self.active[id], ACTIVE_FIELDS)
    end

    for i, entry in ipairs(self.history) do
        writeRecord(xmlId, string.format("%s.history.mission(%d)", baseKey, i - 1), entry, HISTORY_FIELDS)
    end

    local farmIds = {}
    for farmId in pairs(self.stats) do
        farmIds[#farmIds + 1] = farmId
    end
    table.sort(farmIds)
    for i, farmId in ipairs(farmIds) do
        local key = string.format("%s.stats.farm(%d)", baseKey, i - 1)
        local stats = self.stats[farmId]
        setXMLInt(xmlId, key .. "#farmId", farmId)
        for field, value in pairs(stats) do
            setXMLFloat(xmlId, key .. "#" .. field, value)
        end
    end

    if ContractManagerCooldown ~= nil then ContractManagerCooldown.prune() end
    local fieldIds = {}
    for fieldId in pairs(self.fieldCooldowns) do fieldIds[#fieldIds + 1] = fieldId end
    table.sort(fieldIds)
    for i, fieldId in ipairs(fieldIds) do
        local key = string.format("%s.cooldowns.field(%d)", baseKey, i - 1)
        setXMLInt(xmlId, key .. "#fieldId", fieldId)
        setXMLFloat(xmlId, key .. "#until", self.fieldCooldowns[fieldId])
    end

    local quotaIds = {}
    for farmId in pairs(self.quota) do quotaIds[#quotaIds + 1] = farmId end
    table.sort(quotaIds)
    for i, farmId in ipairs(quotaIds) do
        local key = string.format("%s.quota.farm(%d)", baseKey, i - 1)
        local q = self.quota[farmId]
        setXMLInt(xmlId, key .. "#farmId", farmId)
        setXMLFloat(xmlId, key .. "#dayKey", q.dayKey or 0)
        setXMLFloat(xmlId, key .. "#dayCount", q.dayCount or 0)
        setXMLFloat(xmlId, key .. "#monthKey", q.monthKey or 0)
        setXMLFloat(xmlId, key .. "#monthCount", q.monthCount or 0)
    end

    local chainIds = {}
    for fieldId in pairs(self.fieldChain) do chainIds[#chainIds + 1] = fieldId end
    table.sort(chainIds)
    for i, fieldId in ipairs(chainIds) do
        local key = string.format("%s.chain.field(%d)", baseKey, i - 1)
        local c = self.fieldChain[fieldId]
        setXMLInt(xmlId, key .. "#fieldId", fieldId)
        setXMLInt(xmlId, key .. "#farmId", c.farmId or 0)
        setXMLInt(xmlId, key .. "#step", c.step or 0)
        setXMLFloat(xmlId, key .. "#day", c.day or 0)
    end

    local npcFarmIds = {}
    for farmId in pairs(self.npcJobs) do npcFarmIds[#npcFarmIds + 1] = farmId end
    table.sort(npcFarmIds)
    local npcIndex = 0
    for _, farmId in ipairs(npcFarmIds) do
        local keys = {}
        for npcKey in pairs(self.npcJobs[farmId]) do keys[#keys + 1] = npcKey end
        table.sort(keys)
        for _, npcKey in ipairs(keys) do
            local key = string.format("%s.npc.entry(%d)", baseKey, npcIndex)
            setXMLInt(xmlId, key .. "#farmId", farmId)
            setXMLString(xmlId, key .. "#npc", npcKey)
            setXMLFloat(xmlId, key .. "#count", self.npcJobs[farmId][npcKey])
            npcIndex = npcIndex + 1
        end
    end
end

function Registry:readFromXML(xmlId, baseKey)
    self:reset()

    local index = 0
    while true do
        local key = string.format("%s.active.mission(%d)", baseKey, index)
        if not hasXMLProperty(xmlId, key) then
            break
        end
        local record = readRecord(xmlId, key, ACTIVE_FIELDS)
        if record ~= nil then
            self.active[record.id] = record
        end
        index = index + 1
    end

    index = 0
    while true do
        local key = string.format("%s.history.mission(%d)", baseKey, index)
        if not hasXMLProperty(xmlId, key) then
            break
        end
        local record = readRecord(xmlId, key, HISTORY_FIELDS)
        if record ~= nil then
            self.history[#self.history + 1] = record
        end
        index = index + 1
    end

    index = 0
    while true do
        local key = string.format("%s.stats.farm(%d)", baseKey, index)
        if not hasXMLProperty(xmlId, key) then
            break
        end
        local farmId = getXMLInt(xmlId, key .. "#farmId")
        if farmId ~= nil then
            local stats = self:getFarmStats(farmId)
            for field in pairs(stats) do
                stats[field] = getXMLFloat(xmlId, key .. "#" .. field) or 0
            end
        end
        index = index + 1
    end

    index = 0
    while true do
        local key = string.format("%s.cooldowns.field(%d)", baseKey, index)
        if not hasXMLProperty(xmlId, key) then
            break
        end
        local fieldId = getXMLInt(xmlId, key .. "#fieldId")
        local untilHour = getXMLFloat(xmlId, key .. "#until")
        if fieldId ~= nil and untilHour ~= nil then
            self.fieldCooldowns[fieldId] = untilHour
        end
        index = index + 1
    end

    index = 0
    while true do
        local key = string.format("%s.quota.farm(%d)", baseKey, index)
        if not hasXMLProperty(xmlId, key) then break end
        local farmId = getXMLInt(xmlId, key .. "#farmId")
        if farmId ~= nil then
            self.quota[farmId] = {
                dayKey = getXMLFloat(xmlId, key .. "#dayKey") or 0,
                dayCount = getXMLFloat(xmlId, key .. "#dayCount") or 0,
                monthKey = getXMLFloat(xmlId, key .. "#monthKey") or 0,
                monthCount = getXMLFloat(xmlId, key .. "#monthCount") or 0,
            }
        end
        index = index + 1
    end

    index = 0
    while true do
        local key = string.format("%s.chain.field(%d)", baseKey, index)
        if not hasXMLProperty(xmlId, key) then break end
        local fieldId = getXMLInt(xmlId, key .. "#fieldId")
        if fieldId ~= nil then
            self.fieldChain[fieldId] = {
                farmId = getXMLInt(xmlId, key .. "#farmId") or 0,
                step = getXMLInt(xmlId, key .. "#step") or 0,
                day = getXMLFloat(xmlId, key .. "#day") or 0,
            }
        end
        index = index + 1
    end

    index = 0
    while true do
        local key = string.format("%s.npc.entry(%d)", baseKey, index)
        if not hasXMLProperty(xmlId, key) then break end
        local farmId = getXMLInt(xmlId, key .. "#farmId")
        local npcKey = getXMLString(xmlId, key .. "#npc")
        if farmId ~= nil and npcKey ~= nil then
            self.npcJobs[farmId] = self.npcJobs[farmId] or {}
            self.npcJobs[farmId][npcKey] = getXMLFloat(xmlId, key .. "#count") or 0
        end
        index = index + 1
    end
end

-- ---------------------------------------------------------------------------
-- hook'lar (sunucu tarafi; istemcide startMission/dismiss zaten cagrilmaz)
-- ---------------------------------------------------------------------------

function Registry.overwriteStartMission(manager, superFunc, mission, farmId, spawnVehicles)
    local result = superFunc(manager, mission, farmId, spawnVehicles)
    if result == MissionStartState.OK then
        Registry:onMissionStarted(mission, farmId)
        Registry.pushMissionInfo(mission)
    end
    return result
end

function Registry.afterMissionFinish(mission, finishState)
    if mission ~= nil and mission.isServer then
        Registry:onMissionFinished(mission, finishState)
        Registry.pushMissionInfo(mission)
    end
end

---Kontrat panosu degistiginde istemcilere urun olcumunu yolla (expectedLiters
---istemciye aktarilmadigi icin detay paneli bunsuz bos kalir).
function Registry.pushMissionInfo(mission)
    if ContractManagerMissionInfo ~= nil and g_currentMission ~= nil and g_currentMission:getIsServer() then
        pcall(ContractManagerMissionInfo.broadcast, mission)
    end
end

function Registry.beforeDismissMission(manager, mission)
    if mission ~= nil then
        Registry:onMissionDismissed(mission)
    end
end

if MissionManager ~= nil and MissionManager.startMission ~= nil and AbstractMission ~= nil and AbstractMission.finish ~= nil then
    MissionManager.startMission = Utils.overwrittenFunction(MissionManager.startMission, Registry.overwriteStartMission)
    AbstractMission.finish = ContractManager.appendKeepingReturn(AbstractMission.finish, Registry.afterMissionFinish)
    if MissionManager.registerMission ~= nil then
        MissionManager.registerMission = ContractManager.appendKeepingReturn(MissionManager.registerMission,
            function(manager, mission) Registry.pushMissionInfo(mission) end)
    end
    if MissionManager.dismissMission ~= nil then
        -- MissionManager:dismissMission `return true` yapar ve MissionDismissEvent bu
        -- degeri istemciye streamWriteBool ile geri yollar. Utils.prependedFunction'a
        -- guvenmeyip donusu ACIKCA geciriyoruz; kaybolursa sunucu her iptalde
        -- "'streamWriteBool': Expected: Bool. Actual: Nil" hatasi atiyor (canli sunucu,
        -- 2026-09-09, 8 kez).
        MissionManager.dismissMission = Utils.overwrittenFunction(MissionManager.dismissMission,
            function(manager, superFunc, mission)
                Registry.beforeDismissMission(manager, mission)
                return superFunc(manager, mission)
            end)
    end
    ContractManager.info("Registry hooks installed")
else
    ContractManager.error("Mission API missing; registry disabled")
    Registry.disabled = true
end
