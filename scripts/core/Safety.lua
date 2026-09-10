--
-- FS25_ContractManager - Safety
--
-- Oyunun kendi kontrat kodunda her karede tekrarlayan bir hata oyunu kapatir
-- (2026-09-07: AbstractFieldMission.lua:472, completionPartitions bos/nil -> "attempt to
-- index nil with number", gubreleme kontrati, Recanto da Alvorada haritasi).
-- Bu kalkan getFieldCompletion'i pcall ile sarar: hata olursa kontrat basina BIR kez
-- teshis satiri yazar ve son bilinen ilerlemeyi dondurur; oyun kapanmaz.
--

ContractManagerSafety = {
    reported = {},   -- mission -> true
}

local Safety = ContractManagerSafety

local function describeMission(mission)
    local typeName = mission.type ~= nil and mission.type.name or "?"
    local fieldId, areaHa = "?", "?"
    if mission.field ~= nil then
        if mission.field.getId ~= nil then
            local ok, id = pcall(mission.field.getId, mission.field)
            if ok then fieldId = tostring(id) end
        end
        if mission.field.getAreaHa ~= nil then
            local ok, area = pcall(mission.field.getAreaHa, mission.field)
            if ok then areaHa = tostring(area) end
        end
    end
    local partitions = mission.completionPartitions ~= nil and tostring(#mission.completionPartitions) or "nil"
    return string.format("type=%s field=%s areaHa=%s modifier=%s partitions=%s index=%s initialized=%s",
        typeName, fieldId, areaHa, tostring(mission.completionModifier ~= nil), partitions,
        tostring(mission.currentPartitionCompletionIndex), tostring(mission.isFieldCompletionInitialized))
end

function Safety.overwriteGetFieldCompletion(mission, superFunc)
    local ok, result = pcall(superFunc, mission)
    if ok then
        return result
    end
    if not Safety.reported[mission] then
        Safety.reported[mission] = true
        ContractManager.error("Game field-completion code failed (%s); shielded. Details: %s", tostring(result), describeMission(mission))
    end
    -- modifier yok = kontrat henuz hazirlanmadi (kabul edilmemis kontratta baska bir mod getCompletion
    -- cagirmis). Bayragi geri al ki kabulde createModifier sonrasi initializeModifier yeniden calissin.
    if mission.completionModifier == nil then
        mission.isFieldCompletionInitialized = false
        mission.completionPartitions = nil
        mission.currentPartitionCompletionIndex = nil
        return mission.fieldPercentageDone or 0
    end
    -- bos parca listesi: tek parcayla kurtar, sonraki karede normal yol tekrar denenir
    if mission.completionPartitions ~= nil and #mission.completionPartitions == 0 then
        table.insert(mission.completionPartitions, { wasCalculated = false, percentageDone = 0, sumPixels = 0, area = 0, totalArea = 0 })
        mission.currentPartitionCompletionIndex = 1
    end
    return mission.fieldPercentageDone or 0
end

if AbstractFieldMission ~= nil and AbstractFieldMission.getFieldCompletion ~= nil then
    AbstractFieldMission.getFieldCompletion = Utils.overwrittenFunction(AbstractFieldMission.getFieldCompletion, Safety.overwriteGetFieldCompletion)
    ContractManager.info("Safety shield on AbstractFieldMission.getFieldCompletion")
end
