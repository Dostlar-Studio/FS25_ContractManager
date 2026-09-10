--
-- FS25_ContractManager - Kiralik makine kontrolu
--
-- lease#enabled = false : hicbir kontratta kiralik makine yok (FS25_DisableContractMachines'in
--                         yaptigi; o mod da yukluyse ikisi ayni sonucu verir, catisma yok).
-- lease#minReputation   : 0 = kapali; >0 ise ciftligin itibari bu puanin altindayken kiralama yok.
--
-- Iki katman:
--   * Arayuz: AbstractMission:hasLeasableVehicles() istemcide kontrat sayfasindaki
--     "makineli baslat" secenegini belirler; burada false donunce secenek kaybolur.
--   * Sunucu: MissionManager:startMission(..., spawnVehicles) - izin yoksa spawnVehicles
--     false'a cevrilir, kontrat makinesiz baslar ve ciftlige bildirim gider.
--

ContractManagerLease = {}

local Lease = ContractManagerLease

local function settings()
    return ContractManagerSettings
end

function Lease.isEnabled()
    return ContractManager:getRulesEnabled()
end

---farmId icin kiralama izni; farmId nil ise (kabul oncesi istemci) yerel ciftlik
function Lease.isAllowed(farmId)
    if not Lease.isEnabled() then
        return true
    end
    if not settings():get("lease.enabled") then
        return false
    end
    local minRep = settings():get("lease.minReputation") or 0
    if minRep > 0 and ContractManagerReputation ~= nil and ContractManagerReputation.isEnabled() then
        if farmId == nil and g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
            farmId = g_currentMission:getFarmId()
        end
        if farmId ~= nil and ContractManagerReputation.getReputation(farmId) < minRep then
            return false
        end
    end
    return true
end

function Lease.overwriteHasLeasableVehicles(mission, superFunc)
    if not Lease.isAllowed(mission.farmId) then
        return false
    end
    return superFunc(mission)
end

function Lease.overwriteStartMission(manager, superFunc, mission, farmId, spawnVehicles)
    if spawnVehicles and not Lease.isAllowed(farmId) then
        spawnVehicles = false
        if ContractManagerNotificationEvent ~= nil and ContractManagerNotificationEvent.LEASE_DENIED ~= nil then
            ContractManagerNotificationEvent.sendToFarm(ContractManagerNotificationEvent.LEASE_DENIED, farmId, "", settings():get("lease.minReputation") or 0)
        end
        ContractManager.info("Leased vehicles denied for farm %s (lease rule)", tostring(farmId))
    end
    return superFunc(manager, mission, farmId, spawnVehicles)
end

if AbstractMission ~= nil and AbstractMission.hasLeasableVehicles ~= nil then
    AbstractMission.hasLeasableVehicles = Utils.overwrittenFunction(AbstractMission.hasLeasableVehicles, Lease.overwriteHasLeasableVehicles)
    if AbstractFieldMission ~= nil and rawget(AbstractFieldMission, "hasLeasableVehicles") ~= nil then
        AbstractFieldMission.hasLeasableVehicles = Utils.overwrittenFunction(AbstractFieldMission.hasLeasableVehicles, Lease.overwriteHasLeasableVehicles)
    end
end
if MissionManager ~= nil and MissionManager.startMission ~= nil then
    MissionManager.startMission = Utils.overwrittenFunction(MissionManager.startMission, Lease.overwriteStartMission)
end
