--
-- FS25_ContractManager - Tarla bekleme suresi (yalnizca sunucu)
--
-- Bir tarlanin kontrati bitince (basari/basarisizlik/iptal fark etmez) o tarla
-- generation#cooldownPerFieldHours oyun saati boyunca yeni kontrat almaz. Oyun tarlayi
-- tryGenerateMission icinde kendi secer; oncesinde filtre yok. Bu yuzden uretilen kontrat
-- kaydedilirken (MissionManager:registerMission) tarlasi bekleme suresindeyse silinmeye
-- isaretlenir; oyun bir sonraki guncellemede temizler, panoda hic gorunmez.
-- Bekleme listesi Registry'de tutulur ve savegame'e yazilir.
--

ContractManagerCooldown = {}

local Cooldown = ContractManagerCooldown

local function settings()
    return ContractManagerSettings
end

function Cooldown.getHours()
    if not ContractManager:getRulesEnabled() then
        return 0
    end
    return settings():get("generation.cooldownPerFieldHours") or 0
end

---oyun saati (monoton gun * 24 + gun ici saat)
function Cooldown.nowHours()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then
        return 0
    end
    return (env.currentMonotonicDay or 0) * 24 + (env.dayTime or 0) / 3600000
end

local function fieldIdOf(mission)
    local field = mission ~= nil and mission.field or nil
    if field == nil then
        return nil
    end
    if field.getId ~= nil then
        local id = field:getId()
        if type(id) == "number" then return id end
    end
    if type(field.fieldId) == "number" then
        return field.fieldId
    end
    return nil
end

---kontrat bitince tarlayi bekleme listesine al
function Cooldown.onMissionFinished(mission)
    local hours = Cooldown.getHours()
    local fieldId = fieldIdOf(mission)
    if hours <= 0 or fieldId == nil or ContractManagerRegistry == nil then
        return
    end
    ContractManagerRegistry.fieldCooldowns[fieldId] = Cooldown.nowHours() + hours
end

function Cooldown.isFieldOnCooldown(fieldId)
    if fieldId == nil or ContractManagerRegistry == nil then
        return false
    end
    local untilHour = ContractManagerRegistry.fieldCooldowns[fieldId]
    if untilHour == nil then
        return false
    end
    if Cooldown.nowHours() >= untilHour then
        ContractManagerRegistry.fieldCooldowns[fieldId] = nil
        return false
    end
    return true
end

---kalan saat (GUI/panel icin), yoksa 0
function Cooldown.getRemainingHours(fieldId)
    if not Cooldown.isFieldOnCooldown(fieldId) then
        return 0
    end
    return ContractManagerRegistry.fieldCooldowns[fieldId] - Cooldown.nowHours()
end

---suresi dolanlari temizle (kayit oncesi)
function Cooldown.prune()
    if ContractManagerRegistry == nil then
        return
    end
    local now = Cooldown.nowHours()
    for fieldId, untilHour in pairs(ContractManagerRegistry.fieldCooldowns) do
        if now >= untilHour then
            ContractManagerRegistry.fieldCooldowns[fieldId] = nil
        end
    end
end

function Cooldown.afterRegisterMission(manager, mission, missionType)
    if mission == nil or Cooldown.getHours() <= 0 then
        return
    end
    local fieldId = fieldIdOf(mission)
    if fieldId ~= nil and Cooldown.isFieldOnCooldown(fieldId) then
        if manager.markMissionForDeletion ~= nil then
            manager:markMissionForDeletion(mission)
        end
        ContractManager.info("Contract on field %d dropped: field on cooldown (%.1f h left)", fieldId, Cooldown.getRemainingHours(fieldId))
    end
end

function Cooldown.afterMissionFinish(mission, finishState)
    if mission ~= nil and mission.isServer then
        Cooldown.onMissionFinished(mission)
    end
end

if MissionManager ~= nil and MissionManager.registerMission ~= nil and AbstractMission ~= nil and AbstractMission.finish ~= nil then
    MissionManager.registerMission = ContractManager.appendKeepingReturn(MissionManager.registerMission, Cooldown.afterRegisterMission)
    AbstractMission.finish = ContractManager.appendKeepingReturn(AbstractMission.finish, Cooldown.afterMissionFinish)
else
    ContractManager.warning("MissionManager.registerMission missing; field cooldown disabled")
end
