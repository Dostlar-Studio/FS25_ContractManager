--
-- FS25_ContractManager - Kontrat zinciri
--
-- Tarla dongusu dort adimdir:
--   1 hazirlik (tas toplama, surme, gobleme)  2 ekim  3 bakim (gubre, ilac, ot, capa)
--   4 hasat (hasat, bicme, balya)
-- Ayni ciftlik ayni tarlada bir onceki adimi chain#windowDays gun icinde tamamladiysa,
-- siradaki adimin kontrati chain#bonusPercent ek odul alir. Zincir kaydi tarla basina
-- tek satirdir (son tamamlanan adim) ve savegame'e yazilir.
--
-- Kayit yalnizca sunucuda tutulur; istemcide bonus gosterimi icin kayit yoksa 0 doner.
--

ContractManagerChain = {
    -- kontrat turu -> zincir adimi
    STEPS = {
        stonePickMission = 1, plowMission = 1, cultivateMission = 1,
        sowMission = 2,
        fertilizeMission = 3, herbicideMission = 3, weedMission = 3, hoeMission = 3,
        harvestMission = 4, mowMission = 4, baleMission = 4, tedderMission = 4,
    },
}

local Chain = ContractManagerChain

local function settings()
    return ContractManagerSettings
end

function Chain.isEnabled()
    return ContractManager:getRulesEnabled() and settings():get("chain.enabled") == true
end

function Chain.getStep(mission)
    local typeName = mission ~= nil and mission.type ~= nil and mission.type.name or nil
    return typeName ~= nil and Chain.STEPS[typeName] or nil
end

function Chain.getFieldId(mission)
    local field = mission ~= nil and mission.field or nil
    if field == nil then
        return nil
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
    return nil
end

local function today()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    return env ~= nil and (env.currentMonotonicDay or 0) or 0
end

---bu kontrat zincirin devami mi? Donus: evet mi, bonus yuzdesi
function Chain.getBonusPercent(mission, farmId)
    if not Chain.isEnabled() or ContractManagerRegistry == nil then
        return 0
    end
    local step = Chain.getStep(mission)
    local fieldId = Chain.getFieldId(mission)
    if step == nil or step < 2 or fieldId == nil then
        return 0
    end
    if farmId == nil then
        farmId = mission.farmId
        if (farmId == nil or farmId == 0) and g_currentMission ~= nil and not g_currentMission:getIsServer()
            and g_currentMission.getFarmId ~= nil then
            farmId = g_currentMission:getFarmId()
        end
    end
    local record = ContractManagerRegistry.fieldChain[fieldId]
    if record == nil or record.farmId ~= farmId or record.step ~= step - 1 then
        return 0
    end
    local window = settings():get("chain.windowDays") or 0
    if window > 0 and today() - (record.day or 0) > window then
        return 0
    end
    return settings():get("chain.bonusPercent") or 0
end

---basarili kontrat: tarlanin zincir kaydini guncelle
function Chain.onMissionFinished(mission, entry)
    if not Chain.isEnabled() or ContractManagerRegistry == nil or entry == nil then
        return
    end
    if entry.finishState ~= MissionFinishState.SUCCESS then
        return
    end
    local step = Chain.getStep(mission)
    local fieldId = Chain.getFieldId(mission)
    if step == nil or fieldId == nil then
        return
    end
    ContractManagerRegistry.fieldChain[fieldId] = { farmId = entry.farmId, step = step, day = today() }
end

if g_messageCenter ~= nil and ContractManager.MESSAGE_CONTRACT_FINISHED ~= nil then
    g_messageCenter:subscribe(ContractManager.MESSAGE_CONTRACT_FINISHED, function(_, mission, entry)
        Chain.onMissionFinished(mission, entry)
    end, Chain)
end
