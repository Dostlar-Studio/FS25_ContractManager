ContractGuard = {
    VERSION = (ContractManager ~= nil and ContractManager.VERSION) or "1.0.0.0",
    WARNING_WRONG_DESTINATION = 1,
    WARNING_GROUND = 2,
    WARNING_CROSS_FARM = 3,
    UPDATE_INTERVAL_MS = 1000,
    MIN_TRACKED_LITERS = 1,
    loaded = false,
    updateTimer = 0,
    savedBaselines = {}
}

ContractGuard.KNOWN_DELIVERY_MISSION_TYPES = {
    harvestMission = true,
    chaffMission = true,
    fruitCollectMission = true,
    mowBaleMission = true
}

function ContractGuard:getMissionTypeName(mission)
    if mission ~= nil and mission.type ~= nil then
        return mission.type.name
    end
    return nil
end

function ContractGuard:getMissionFillType(mission)
    if mission == nil then
        return nil
    end
    if type(mission.fillTypeIndex) == "number" then
        return mission.fillTypeIndex
    end
    if type(mission.fillType) == "number" then
        return mission.fillType
    end
    if type(mission.fruitTypeIndex) == "number" and g_fruitTypeManager ~= nil then
        return g_fruitTypeManager:getFillTypeIndexByFruitTypeIndex(mission.fruitTypeIndex)
    end
    return nil
end

function ContractGuard:isProtectedMission(mission)
    if mission == nil or mission.farmId == nil or mission.field == nil then
        return false
    end
    if not self:getSetting("guard.enabled", true) then
        return false
    end

    local typeName = self:getMissionTypeName(mission)
    if typeName ~= nil and self.KNOWN_DELIVERY_MISSION_TYPES[typeName] then
        return self:getMissionFillType(mission) ~= nil
    end

    if HarvestMission ~= nil and mission.isa ~= nil and mission:isa(HarvestMission) then
        return self:getMissionFillType(mission) ~= nil
    end

    return type(mission.expectedLiters) == "number"
        and mission.depositedLiters ~= nil
        and self:getMissionFillType(mission) ~= nil
        and (mission.sellingStation ~= nil or mission.tryToResolveSellingStation ~= nil)
end

function ContractGuard:isMissionActive(mission)
    return mission ~= nil
        and (mission.status == MissionStatus.RUNNING or mission.status == MissionStatus.PREPARING)
end

function ContractGuard:getMissions()
    if g_missionManager == nil then
        return {}
    end
    if g_missionManager.getMissions ~= nil then
        return g_missionManager:getMissions()
    end
    return g_missionManager.missions or {}
end

function ContractGuard:getMatchingMissions(farmId, fillTypeIndex)
    local result = {}
    if farmId == nil or fillTypeIndex == nil then
        return result
    end

    for _, mission in ipairs(self:getMissions()) do
        if self:isMissionActive(mission)
            and (mission.farmId == farmId
                or (ContractManagerPartnership ~= nil and ContractManagerPartnership.isMember(mission, farmId)))
            and self:isProtectedMission(mission)
            and self:getMissionFillType(mission) == fillTypeIndex then
            table.insert(result, mission)
        end
    end
    return result
end

function ContractGuard:getAssignedStation(mission)
    if mission == nil then
        return nil
    end

    if mission.sellingStation == nil and mission.tryToResolveSellingStation ~= nil then
        pcall(mission.tryToResolveSellingStation, mission)
    end

    if type(mission.sellingStation) == "table" then
        return mission.sellingStation
    end
    if type(mission.deliveryStation) == "table" then
        return mission.deliveryStation
    end
    if type(mission.unloadingStation) == "table" then
        return mission.unloadingStation
    end
    return nil
end

function ContractGuard:isAssignedDestination(object, missions)
    if object == nil then
        return false, false
    end

    local resolvedStation = false
    for _, mission in ipairs(missions) do
        local station = self:getAssignedStation(mission)
        if station ~= nil then
            resolvedStation = true
            if object == station or object.target == station then
                return true, true
            end
            if station.unloadTriggers ~= nil then
                for _, trigger in ipairs(station.unloadTriggers) do
                    if trigger == object then
                        return true, true
                    end
                end
            end
        end
    end
    return false, resolvedStation
end

function ContractGuard:getVehicleFarmId(vehicle)
    if vehicle == nil then
        return nil
    end

    local activeFarmId
    if vehicle.getActiveFarm ~= nil then
        activeFarmId = vehicle:getActiveFarm()
        if activeFarmId ~= nil and activeFarmId ~= FarmManager.SPECTATOR_FARM_ID then
            return activeFarmId
        end
    end

    if vehicle.getOwnerFarmId ~= nil then
        return vehicle:getOwnerFarmId()
    end
    return activeFarmId
end

function ContractGuard:isVehicleObject(object)
    return object ~= nil and object.isa ~= nil and Vehicle ~= nil and object:isa(Vehicle)
end

function ContractGuard:getDischargeContext(vehicle, dischargeNode)
    if vehicle == nil or dischargeNode == nil or vehicle.getDischargeFillType == nil then
        return nil, nil, {}
    end

    local fillTypeIndex = vehicle:getDischargeFillType(dischargeNode)
    local farmId = self:getVehicleFarmId(vehicle)
    if fillTypeIndex == nil or farmId == nil or farmId == FarmManager.SPECTATOR_FARM_ID then
        return farmId, fillTypeIndex, {}
    end
    return farmId, fillTypeIndex, self:getMatchingMissions(farmId, fillTypeIndex)
end

function ContractGuard:isGroundDischargeBlocked(vehicle, dischargeNode)
    local _, fillTypeIndex, missions = self:getDischargeContext(vehicle, dischargeNode)
    if #missions > 0 then
        return true, self.WARNING_GROUND, fillTypeIndex
    end
    return false, nil, fillTypeIndex
end

function ContractGuard:isObjectDischargeBlocked(vehicle, dischargeNode, object)
    local farmId, fillTypeIndex, missions = self:getDischargeContext(vehicle, dischargeNode)
    if #missions == 0 or object == nil then
        return false, nil, fillTypeIndex
    end

    if self:isVehicleObject(object) then
        local targetFarmId = self:getVehicleFarmId(object)
        if targetFarmId == farmId then
            return false, nil, fillTypeIndex
        end
        return true, self.WARNING_CROSS_FARM, fillTypeIndex
    end

    local isAssigned, hasResolvedStation = self:isAssignedDestination(object, missions)
    if isAssigned then
        return false, nil, fillTypeIndex
    end

    -- Teslim istasyonu cozulemediyse (istemci henuz senkron degil ya da sunucuda
    -- beklenmedik bir mission tipi) koruma kilit olusturmasin: fail-open.
    -- Kilitlenmis bir kontrat, kacirilmis bir hirsizliktan daha kotu.
    if not hasResolvedStation then
        self:warnUnresolvedStation(missions)
        return false, nil, fillTypeIndex
    end
    return true, self.WARNING_WRONG_DESTINATION, fillTypeIndex
end

-- Sunucuda, istasyonu cozulemeyen her mission icin bir kez log'a dusur.
function ContractGuard:warnUnresolvedStation(missions)
    if g_server == nil then
        return
    end
    for _, mission in ipairs(missions) do
        if not mission.contractGuardStationWarned then
            mission.contractGuardStationWarned = true
            Logging.warning(
                "[CM/Guard] Delivery station of mission '%s' could not be resolved; destination protection disabled for it",
                tostring(self:getMissionId(mission))
            )
        end
    end
end

function ContractGuard:getFillTypeTitle(fillTypeIndex)
    local fillType = nil
    if fillTypeIndex ~= nil and g_fillTypeManager ~= nil then
        fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    end
    if fillType ~= nil and fillType.title ~= nil then
        return fillType.title
    end
    return "?"
end

function ContractGuard:setDischargeWarning(dischargeNode, reason, fillTypeIndex)
    if dischargeNode == nil then
        return
    end

    if not dischargeNode.contractGuardWarningActive then
        dischargeNode.contractGuardPreviousWarning = dischargeNode.customNotAllowedWarning
        dischargeNode.contractGuardWarningActive = true
    end

    local key = "cg_warningWrongDestination"
    if reason == self.WARNING_GROUND then
        key = "cg_warningGroundBlocked"
    elseif reason == self.WARNING_CROSS_FARM then
        key = "cg_warningCrossFarm"
    end
    -- Ceviri metinlerinin ucunde de %s var; bicimlendirilmezse ekranda ham "%s" gorunur.
    dischargeNode.customNotAllowedWarning = string.format(g_i18n:getText(key), self:getFillTypeTitle(fillTypeIndex))
end

function ContractGuard:clearDischargeWarning(dischargeNode)
    if dischargeNode ~= nil and dischargeNode.contractGuardWarningActive then
        dischargeNode.customNotAllowedWarning = dischargeNode.contractGuardPreviousWarning
        dischargeNode.contractGuardPreviousWarning = nil
        dischargeNode.contractGuardWarningActive = nil
    end
end

function ContractGuard:getMissionId(mission)
    if mission == nil then
        return nil
    end
    if mission.getUniqueId ~= nil then
        return mission:getUniqueId()
    end
    return mission.uniqueId
end

function ContractGuard:getItemSystemItems()
    local itemSystem = g_currentMission ~= nil and g_currentMission.itemSystem or nil
    if itemSystem == nil then
        return {}
    end
    if itemSystem.getItems ~= nil then
        local ok, items = pcall(itemSystem.getItems, itemSystem)
        if ok and type(items) == "table" then
            return items
        end
    end
    return itemSystem.items or itemSystem.itemsById or {}
end

function ContractGuard:isObjectOwnedByFarm(object, farmId)
    if object == nil or farmId == nil then
        return false
    end
    if object.getOwnerFarmId ~= nil and object:getOwnerFarmId() == farmId then
        return true
    end
    if object.getActiveFarm ~= nil and object:getActiveFarm() == farmId then
        return true
    end
    return false
end

function ContractGuard:collectFillEntries(farmId, fillTypeIndex)
    local entries = {}
    local vehicleSystem = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    local vehicles = vehicleSystem ~= nil and vehicleSystem.vehicles or {}

    for _, vehicle in pairs(vehicles) do
        if self:isObjectOwnedByFarm(vehicle, farmId)
            and vehicle.getNumFillUnits ~= nil
            and vehicle.getFillUnitFillType ~= nil
            and vehicle.getFillUnitFillLevel ~= nil then
            local numFillUnits = vehicle:getNumFillUnits()
            for fillUnitIndex = 1, numFillUnits do
                if vehicle:getFillUnitFillType(fillUnitIndex) == fillTypeIndex then
                    local amount = vehicle:getFillUnitFillLevel(fillUnitIndex)
                    if amount ~= nil and amount > self.MIN_TRACKED_LITERS then
                        table.insert(entries, {
                            kind = "vehicle",
                            object = vehicle,
                            fillUnitIndex = fillUnitIndex,
                            amount = amount
                        })
                    end
                end
            end
        end
    end

    for _, item in pairs(self:getItemSystemItems()) do
        if item ~= nil
            and item.isa ~= nil
            and Bale ~= nil
            and item:isa(Bale)
            and self:isObjectOwnedByFarm(item, farmId)
            and item.getFillType ~= nil
            and item:getFillType() == fillTypeIndex
            and item.getFillLevel ~= nil then
            local amount = item:getFillLevel()
            if amount ~= nil and amount > self.MIN_TRACKED_LITERS then
                table.insert(entries, {
                    kind = "bale",
                    object = item,
                    amount = amount
                })
            end
        end
    end

    return entries
end

function ContractGuard:getFarmFillVolume(farmId, fillTypeIndex)
    local total = 0
    for _, entry in ipairs(self:collectFillEntries(farmId, fillTypeIndex)) do
        total = total + entry.amount
    end
    return total
end

function ContractGuard:initializeMission(mission, fromLoadedGame)
    if not self:isProtectedMission(mission) or mission.contractGuardBaselineLiters ~= nil then
        return
    end

    local missionId = self:getMissionId(mission)
    local fillTypeIndex = self:getMissionFillType(mission)
    local saved = missionId ~= nil and self.savedBaselines[missionId] or nil
    local baseline

    if saved ~= nil and saved.farmId == mission.farmId and saved.fillTypeIndex == fillTypeIndex then
        baseline = saved.baselineLiters
    elseif fromLoadedGame then
        -- Secure default for a running contract created before this mod was installed.
        baseline = 0
        Logging.warning("[CM/Guard] No saved baseline for running mission '%s'; using strict baseline 0", tostring(missionId))
    else
        baseline = self:getFarmFillVolume(mission.farmId, fillTypeIndex)
    end

    mission.contractGuardBaselineLiters = math.max(0, baseline or 0)
    Logging.info(
        "[CM/Guard] Tracking mission '%s' farm=%s fillType=%s baseline=%.1f",
        tostring(missionId),
        tostring(mission.farmId),
        tostring(fillTypeIndex),
        mission.contractGuardBaselineLiters
    )
end

function ContractGuard:missionHasProgress(mission)
    if not self:isProtectedMission(mission) then
        return false
    end
    if (mission.depositedLiters or 0) > self.MIN_TRACKED_LITERS then
        return true
    end
    if (mission.fieldPercentageDone or 0) > 0.0001 then
        return true
    end

    if mission.contractGuardBaselineLiters == nil then
        self:initializeMission(mission, true)
    end
    local current = self:getFarmFillVolume(mission.farmId, self:getMissionFillType(mission))
    return current > (mission.contractGuardBaselineLiters or 0) + self.MIN_TRACKED_LITERS
end

function ContractGuard:confiscateMissionProduct(mission)
    if not self:isProtectedMission(mission) then
        return 0
    end
    if mission.contractGuardBaselineLiters == nil then
        self:initializeMission(mission, true)
    end

    local fillTypeIndex = self:getMissionFillType(mission)
    local entries = self:collectFillEntries(mission.farmId, fillTypeIndex)
    local current = 0
    for _, entry in ipairs(entries) do
        current = current + entry.amount
    end

    local remaining = math.max(0, current - (mission.contractGuardBaselineLiters or 0))
    local requested = remaining

    for _, entry in ipairs(entries) do
        if remaining <= self.MIN_TRACKED_LITERS then
            break
        end

        local take = math.min(entry.amount, remaining)
        local removed = 0
        if entry.kind == "vehicle" and entry.object.addFillUnitFillLevel ~= nil then
            local applied = entry.object:addFillUnitFillLevel(
                mission.farmId,
                entry.fillUnitIndex,
                -take,
                fillTypeIndex,
                ToolType.UNDEFINED,
                nil
            )
            removed = math.abs(applied or 0)
        elseif entry.kind == "bale" and entry.object.setFillLevel ~= nil then
            local newFillLevel = math.max(0, entry.amount - take)
            entry.object:setFillLevel(newFillLevel)
            removed = entry.amount - newFillLevel
            if newFillLevel <= self.MIN_TRACKED_LITERS and entry.object.delete ~= nil then
                entry.object:delete()
            end
        end
        remaining = math.max(0, remaining - removed)
    end

    local removedTotal = requested - remaining
    if removedTotal > self.MIN_TRACKED_LITERS then
        Logging.warning(
            "[CM/Guard] Confiscated %.1f liters from failed mission '%s' (farm %s)",
            removedTotal,
            tostring(self:getMissionId(mission)),
            tostring(mission.farmId)
        )
    end
    return removedTotal
end

function ContractGuard:isBaleDeliveryBlocked(trigger, bale)
    if trigger == nil or bale == nil or bale.getOwnerFarmId == nil or bale.getFillType == nil then
        return false
    end

    local farmId = bale:getOwnerFarmId()
    local fillTypeIndex = bale:getFillType()
    local missions = self:getMatchingMissions(farmId, fillTypeIndex)
    if #missions == 0 then
        return false
    end

    local isAssigned, hasResolvedStation = self:isAssignedDestination(trigger, missions)
    if isAssigned then
        return false
    end
    if not hasResolvedStation then
        self:warnUnresolvedStation(missions)
        return false
    end
    return true
end

-- ---------------------------------------------------------------------------
-- durum: Persistence xmlId ve temel anahtari verir (yeni dosya: contractManager.guard,
-- eski bagimsiz dosya: contractGuard). Bu katman dosya acmaz.
-- ---------------------------------------------------------------------------

function ContractGuard:resetState()
    self.savedBaselines = {}
end

function ContractGuard:readFromXML(xmlId, baseKey)
    self.savedBaselines = {}
    local index = 0
    while hasXMLProperty(xmlId, string.format("%s.missions.mission(%d)", baseKey, index)) do
        local key = string.format("%s.missions.mission(%d)", baseKey, index)
        local missionId = getXMLString(xmlId, key .. "#id")
        if missionId ~= nil then
            self.savedBaselines[missionId] = {
                farmId = getXMLInt(xmlId, key .. "#farmId"),
                fillTypeIndex = getXMLInt(xmlId, key .. "#fillTypeIndex"),
                baselineLiters = getXMLFloat(xmlId, key .. "#baselineLiters") or 0
            }
        end
        index = index + 1
    end
end

function ContractGuard:writeToXML(xmlId, baseKey)
    local index = 0
    for _, mission in ipairs(self:getMissions()) do
        if self:isMissionActive(mission) and self:isProtectedMission(mission) then
            self:initializeMission(mission, true)
            local missionId = self:getMissionId(mission)
            if missionId ~= nil then
                local key = string.format("%s.missions.mission(%d)", baseKey, index)
                setXMLString(xmlId, key .. "#id", missionId)
                setXMLInt(xmlId, key .. "#farmId", mission.farmId)
                setXMLInt(xmlId, key .. "#fillTypeIndex", self:getMissionFillType(mission))
                setXMLFloat(xmlId, key .. "#baselineLiters", mission.contractGuardBaselineLiters or 0)
                index = index + 1
            end
        end
    end
end

function ContractGuard:loadMap(mapName)
    self.mission = g_currentMission
    self.loaded = true
    self.updateTimer = 0
    Logging.info("[CM/Guard] Loaded v%s (server-authoritative protection enabled)", self.VERSION)
end

function ContractGuard:update(dt)
    if not self.loaded or self.mission == nil or not self.mission:getIsServer() then
        return
    end

    self.updateTimer = self.updateTimer + dt
    if self.updateTimer < self.UPDATE_INTERVAL_MS then
        return
    end
    self.updateTimer = 0

    for _, mission in ipairs(self:getMissions()) do
        -- Izlenen kontratta yapilacak is yok. En ucuz kontrol basta olsun: bu dongu
        -- sunucuda saniyede bir tum kontratlari geziyor, isProtectedMission ise tur
        -- tablosuna ve fillType cozumune bakiyor.
        if mission.contractGuardBaselineLiters == nil
            and self:isMissionActive(mission) and self:isProtectedMission(mission) then
            self:initializeMission(mission, true)
        end
    end
end

function ContractGuard:deleteMap()
    self.loaded = false
    self.mission = nil
    self.updateTimer = 0
    self.savedBaselines = {}
    Logging.info("[CM/Guard] Unloaded")
end

-- ayar okuma (Settings yuklu degilse varsayilan: acik)
function ContractGuard:getSetting(id, default)
    if ContractManagerSettings ~= nil and ContractManagerSettings.get ~= nil then
        local value = ContractManagerSettings:get(id)
        if value ~= nil then
            return value
        end
    end
    return default
end

function ContractGuard.overwriteStartMission(manager, superFunc, mission, farmId, spawnVehicles)
    local result = superFunc(manager, mission, farmId, spawnVehicles)
    if result == MissionStartState.OK and ContractGuard:isProtectedMission(mission) then
        ContractGuard:initializeMission(mission, false)
    end
    return result
end

function ContractGuard.overwriteCancelMission(manager, superFunc, mission)
    if mission ~= nil
        and not mission.cmForceCancel
        and ContractGuard:getSetting("guard.blockCancelAfterProgress", true)
        and ContractGuard:isMissionActive(mission)
        and ContractGuard:isProtectedMission(mission)
        and ContractGuard:missionHasProgress(mission) then
        local fillTypeIndex = ContractGuard:getMissionFillType(mission)
        ContractGuardNotificationEvent.sendToFarm(
            ContractGuardNotificationEvent.CANCEL_BLOCKED,
            mission.farmId,
            fillTypeIndex,
            0
        )
        Logging.warning(
            "[CM/Guard] Blocked cancellation of mission '%s' for farm %s after work started",
            tostring(ContractGuard:getMissionId(mission)),
            tostring(mission.farmId)
        )
        return false
    end
    return superFunc(manager, mission)
end

function ContractGuard.beforeMissionFinish(mission, finishState)
    if mission == nil
        or not mission.isServer
        or finishState == MissionFinishState.SUCCESS
        or not ContractGuard:getSetting("guard.confiscateOnFail", true)
        or not ContractGuard:isProtectedMission(mission)
        or not ContractGuard:missionHasProgress(mission) then
        return
    end

    local removed = ContractGuard:confiscateMissionProduct(mission)
    if removed > ContractGuard.MIN_TRACKED_LITERS then
        ContractGuardNotificationEvent.sendToFarm(
            ContractGuardNotificationEvent.FORCED_PURGE,
            mission.farmId,
            ContractGuard:getMissionFillType(mission),
            removed
        )
    end
end

function ContractGuard.overwriteBaleUnloadTriggerUpdate(trigger, superFunc, dt)
    if not trigger.isServer or trigger.balesInTrigger == nil or #trigger.balesInTrigger == 0 then
        return superFunc(trigger, dt)
    end

    local allowed = {}
    local blocked = {}
    for _, bale in ipairs(trigger.balesInTrigger) do
        if ContractGuard:isBaleDeliveryBlocked(trigger, bale) then
            table.insert(blocked, bale)
            if bale.contractGuardBlockedTrigger ~= trigger then
                bale.contractGuardBlockedTrigger = trigger
                ContractGuardNotificationEvent.sendToFarm(
                    ContractGuardNotificationEvent.BALE_BLOCKED,
                    bale:getOwnerFarmId(),
                    bale:getFillType(),
                    0
                )
            end
        else
            if bale.contractGuardBlockedTrigger == trigger then
                bale.contractGuardBlockedTrigger = nil
            end
            table.insert(allowed, bale)
        end
    end

    trigger.balesInTrigger = allowed
    superFunc(trigger, dt)

    for _, bale in ipairs(blocked) do
        if bale ~= nil and bale.nodeId ~= nil and bale.nodeId ~= 0 then
            table.addElement(trigger.balesInTrigger, bale)
        end
    end
end

-- Oyunun beklenen mission API'si yoksa (surum farki) modu temiz sekilde devre disi birak;
-- nil global indekslemek yukleme aninda tum modu patlatir.
local function hasRequiredApi()
    return MissionStatus ~= nil and MissionStatus.RUNNING ~= nil and MissionStatus.PREPARING ~= nil
        and MissionStartState ~= nil and MissionStartState.OK ~= nil
        and MissionFinishState ~= nil and MissionFinishState.SUCCESS ~= nil
        and MissionManager ~= nil and MissionManager.startMission ~= nil and MissionManager.cancelMission ~= nil
        and AbstractMission ~= nil and AbstractMission.finish ~= nil
end

if ContractManager ~= nil and not ContractManager.guardEnabled then
    Logging.warning("[CM/Guard] Guard layer disabled by Contract Manager (legacy FS25_ContractGuard active)")
    ContractGuard.disabled = true
    return
end

if not hasRequiredApi() then
    Logging.error("[CM/Guard] Expected mission API not found; guard layer disabled")
    ContractGuard.disabled = true
    return
end

MissionManager.startMission = Utils.overwrittenFunction(MissionManager.startMission, ContractGuard.overwriteStartMission)
MissionManager.cancelMission = Utils.overwrittenFunction(MissionManager.cancelMission, ContractGuard.overwriteCancelMission)
AbstractMission.finish = Utils.prependedFunction(AbstractMission.finish, ContractGuard.beforeMissionFinish)

if BaleUnloadTrigger ~= nil and BaleUnloadTrigger.update ~= nil then
    BaleUnloadTrigger.update = Utils.overwrittenFunction(BaleUnloadTrigger.update, ContractGuard.overwriteBaleUnloadTriggerUpdate)
end

addModEventListener(ContractGuard)
