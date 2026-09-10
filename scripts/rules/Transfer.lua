--
-- FS25_ContractManager - Kontrat devri (yonetici)
--
-- Aktif bir kontrat baska bir ciftlige aktarilir: mission.farmId degisir, Registry meta ve
-- Guard baseline'i yeni ciftlige gore yeniden kurulur, rezervasyon kalkar. Kiralik makineli
-- kontrat devredilmez (arac sahipligi tasinmaz). Hedef ciftligin limiti dolu ise reddedilir.
--
-- Istemciler mission.farmId'yi oyunun akisiyla almaz (updateStream yalnizca durum/ilerleme
-- tasir); bu yuzden TransferEvent her istemcide farmId'yi yazar, eski ciftlikte harita
-- isareti ve ilerleme cubugunu kaldirir, yenisinde oyunun update() dongusu ekler.
--

ContractManagerTransfer = {}

local Transfer = ContractManagerTransfer

---sunucu (saf; test edilir). Donus: ok, l10n anahtari
function Transfer.execute(uniqueId, farmId)
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.findMission(uniqueId) or nil
    if mission == nil then
        return false, "cm_adminNotFound"
    end
    if mission.status ~= MissionStatus.RUNNING and mission.status ~= MissionStatus.PREPARING then
        return false, "cm_adminNotActive"
    end
    farmId = tonumber(farmId)
    if farmId == nil or farmId <= 0 or (g_farmManager ~= nil and g_farmManager.getFarmById ~= nil and g_farmManager:getFarmById(farmId) == nil) then
        return false, "cm_adminNoFarm"
    end
    if farmId == mission.farmId then
        return false, "cm_transferSameFarm"
    end
    if mission.spawnedVehicles then
        return false, "cm_transferLeased"
    end
    if g_missionManager ~= nil and g_missionManager.hasFarmReachedMissionLimit ~= nil and g_missionManager:hasFarmReachedMissionLimit(farmId) then
        return false, "cm_adminLimit"
    end

    local oldFarmId = mission.farmId
    Transfer.applyLocal(mission, farmId)

    -- Registry meta + Guard baseline yeni ciftlige gore
    if ContractManagerRegistry ~= nil then
        local meta = ContractManagerRegistry:getActiveMeta(mission)
        if meta ~= nil then meta.farmId = farmId end
    end
    if ContractGuard ~= nil and not ContractGuard.disabled and ContractGuard.isProtectedMission ~= nil and ContractGuard:isProtectedMission(mission) then
        mission.contractGuardBaselineLiters = nil
        pcall(ContractGuard.initializeMission, ContractGuard, mission, false)
    end
    if ContractManagerReservation ~= nil then
        ContractManagerReservation.clearForMission(mission)
    end

    if ContractManagerTransferEvent ~= nil and g_server ~= nil then
        g_server:broadcastEvent(ContractManagerTransferEvent.new(uniqueId, farmId), false)
    end
    ContractManager.info("Contract %s transferred from farm %s to farm %d", tostring(uniqueId), tostring(oldFarmId), farmId)
    ContractManager.publish(ContractManager.MESSAGE_CONTRACT_TRANSFERRED, mission, oldFarmId, farmId)
    return true, "cm_transferDone"
end

---her tarafta: farmId yaz, eski ciftligin gorsel izlerini kaldir
function Transfer.applyLocal(mission, farmId)
    mission.farmId = farmId
    local localFarm = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    if localFarm ~= farmId then
        if mission.removeHotspot ~= nil then pcall(mission.removeHotspot, mission) end
        if mission.progressBar ~= nil and g_currentMission ~= nil and g_currentMission.hud ~= nil and g_currentMission.hud.removeSideNotificationProgressBar ~= nil then
            pcall(g_currentMission.hud.removeSideNotificationProgressBar, g_currentMission.hud, mission.progressBar)
            mission.progressBar = nil
        end
    else
        mission.isHotspotAdded = false -- oyunun update() dongusu yeniden ekler
    end
end

-- ---------------------------------------------------------------------------
-- olay: sunucu -> istemci
-- ---------------------------------------------------------------------------

ContractManagerTransferEvent = {}
local ContractManagerTransferEvent_mt = Class(ContractManagerTransferEvent, Event)

InitEventClass(ContractManagerTransferEvent, "ContractManagerTransferEvent")

function ContractManagerTransferEvent.emptyNew()
    return Event.new(ContractManagerTransferEvent_mt)
end

function ContractManagerTransferEvent.new(uniqueId, farmId)
    local self = ContractManagerTransferEvent.emptyNew()
    self.uniqueId = uniqueId or ""
    self.farmId = farmId or 0
    return self
end

function ContractManagerTransferEvent:writeStream(streamId, connection)
    streamWriteString(streamId, tostring(self.uniqueId))
    streamWriteUIntN(streamId, self.farmId or 0, FarmManager.FARM_ID_SEND_NUM_BITS)
end

function ContractManagerTransferEvent:readStream(streamId, connection)
    self.uniqueId = streamReadString(streamId)
    self.farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    self:run(connection)
end

function ContractManagerTransferEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then
        return -- istemciden gelmez
    end
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.findMission(self.uniqueId) or nil
    if mission ~= nil then
        Transfer.applyLocal(mission, self.farmId)
    end
end

if addConsoleCommand ~= nil and ContractManagerAdmin ~= nil then
    function ContractManagerAdmin:consoleTransfer(uniqueId, farmId)
        if uniqueId == nil or tonumber(farmId) == nil then
            return "usage: cmTransferContract <uniqueId> <farmId>"
        end
        ContractManagerAdminEvent.send(ContractManagerAdmin.ACTION_TRANSFER, uniqueId, tonumber(farmId))
        return "transfer requested"
    end
    addConsoleCommand("cmTransferContract", "ContractManager: move an active contract to another farm", "consoleTransfer", ContractManagerAdmin)
end
