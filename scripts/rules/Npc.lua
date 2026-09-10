--
-- FS25_ContractManager - NPC iliskisi
--
-- Her ciftlik icin her NPC'ye ayri sayac tutulur: o NPC'nin kontratini basariyla
-- bitirdikce sayac artar. Odule eklenen bonus:
--   min(sayac * npc#percentPerJob, npc#maxPercent)
-- Sayaclar Registry.npcJobs'ta, savegame'e yazilir. Istemcide sayac yoksa bonus 0 gorunur;
-- odeme her zaman sunucuda hesaplanir.
--

ContractManagerNpc = {}

local Npc = ContractManagerNpc

local function settings()
    return ContractManagerSettings
end

function Npc.isEnabled()
    return ContractManager:getRulesEnabled() and settings():get("npc.enabled") == true
end

---NPC anahtari: once index, yoksa ad
function Npc.getKey(mission)
    if mission == nil or mission.getNPC == nil then
        return nil
    end
    local npc = mission:getNPC()
    if type(npc) ~= "table" then
        return nil
    end
    if type(npc.index) == "number" then
        return "i" .. tostring(npc.index)
    end
    local name = npc.title or npc.name
    if type(name) == "string" and name ~= "" then
        return "n" .. name
    end
    return nil
end

function Npc.getJobCount(farmId, key)
    if ContractManagerRegistry == nil or farmId == nil or key == nil then
        return 0
    end
    local farm = ContractManagerRegistry.npcJobs[farmId]
    return farm ~= nil and (farm[key] or 0) or 0
end

function Npc.getBonusPercent(mission, farmId)
    if not Npc.isEnabled() then
        return 0
    end
    local key = Npc.getKey(mission)
    if key == nil then
        return 0
    end
    if farmId == nil then
        farmId = mission.farmId
        if (farmId == nil or farmId == 0) and g_currentMission ~= nil and not g_currentMission:getIsServer()
            and g_currentMission.getFarmId ~= nil then
            farmId = g_currentMission:getFarmId()
        end
    end
    local count = Npc.getJobCount(farmId, key)
    if count <= 0 then
        return 0
    end
    local perJob = settings():get("npc.percentPerJob") or 0
    local maxPercent = settings():get("npc.maxPercent") or 0
    return math.min(maxPercent, count * perJob)
end

function Npc.onMissionFinished(mission, entry)
    if not Npc.isEnabled() or ContractManagerRegistry == nil or entry == nil then
        return
    end
    if entry.finishState ~= MissionFinishState.SUCCESS then
        return
    end
    local key = Npc.getKey(mission)
    if key == nil or entry.farmId == nil then
        return
    end
    local farm = ContractManagerRegistry.npcJobs[entry.farmId]
    if farm == nil then
        farm = {}
        ContractManagerRegistry.npcJobs[entry.farmId] = farm
    end
    farm[key] = (farm[key] or 0) + 1
end

if g_messageCenter ~= nil and ContractManager.MESSAGE_CONTRACT_FINISHED ~= nil then
    g_messageCenter:subscribe(ContractManager.MESSAGE_CONTRACT_FINISHED, function(_, mission, entry)
        Npc.onMissionFinished(mission, entry)
    end, Npc)
end
