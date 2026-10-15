ContractGuardVehicle = {}

function ContractGuardVehicle.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Dischargeable, specializations)
end

function ContractGuardVehicle.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanDischargeToGround", ContractGuardVehicle.getCanDischargeToGround)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanDischargeToObject", ContractGuardVehicle.getCanDischargeToObject)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "dischargeToGround", ContractGuardVehicle.dischargeToGround)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "dischargeToObject", ContractGuardVehicle.dischargeToObject)
end

function ContractGuardVehicle.getCanDischargeToGround(self, superFunc, dischargeNode)
    local blocked, reason, fillTypeIndex = ContractGuard:isGroundDischargeBlocked(self, dischargeNode)
    if blocked then
        ContractGuard:setDischargeWarning(dischargeNode, reason, fillTypeIndex)
        return false
    end

    ContractGuard:clearDischargeWarning(dischargeNode)
    return superFunc(self, dischargeNode)
end

function ContractGuardVehicle.getCanDischargeToObject(self, superFunc, dischargeNode)
    local object = dischargeNode ~= nil and dischargeNode.dischargeObject or nil
    local blocked, reason, fillTypeIndex = ContractGuard:isObjectDischargeBlocked(self, dischargeNode, object)
    if blocked then
        ContractGuard:setDischargeWarning(dischargeNode, reason, fillTypeIndex)
        return false
    end

    ContractGuard:clearDischargeWarning(dischargeNode)
    return superFunc(self, dischargeNode)
end

function ContractGuardVehicle.dischargeToGround(self, superFunc, dischargeNode, emptyLiters)
    local blocked = ContractGuard:isGroundDischargeBlocked(self, dischargeNode)
    if blocked then
        return 0, false, false
    end
    return superFunc(self, dischargeNode, emptyLiters)
end

function ContractGuardVehicle.dischargeToObject(self, superFunc, dischargeNode, emptyLiters, object, targetFillUnitIndex)
    local blocked = ContractGuard:isObjectDischargeBlocked(self, dischargeNode, object)
    if blocked then
        return 0
    end
    -- Bosaltma her karede calisir: ortaklik yoksa katki yolu hic calismaz.
    local Part = ContractManagerPartnership
    local countDelivery = Part ~= nil and next(Part.list) ~= nil
    -- Dolum turu bosaltmadan ONCE: bosalan bolmede tur sifirlanabilir.
    local fillTypeIndex = nil
    if countDelivery and self.getDischargeFillType ~= nil then
        fillTypeIndex = self:getDischargeFillType(dischargeNode)
    end
    local dischargedLiters = superFunc(self, dischargeNode, emptyLiters, object, targetFillUnitIndex)
    if countDelivery then
        ContractManager.guard("Partnership delivery", Part.onDelivered, self, object, dischargedLiters, fillTypeIndex)
    end
    return dischargedLiters
end

---Yere dokme Guard'a takilinca oyun HICBIR uyari gostermez: tus yalniz getCanDischargeToGround true ise
---ilerler (Dischargeable.lua:2029). Oyuncu tusa basiyor, hicbir sey olmuyordu (1.26.0.0). Bosaltma kapaliyken
---basildiysa ve kapali kaldiysa, engelleyen Guard ise sebebi yazilir.
function ContractGuardVehicle.overwriteToggleDischargeToGround(self, superFunc, ...)
    local spec = self.spec_dischargeable
    local offState = Dischargeable.DISCHARGE_STATE_OFF
    local wasOff = spec ~= nil and spec.currentDischargeState == offState
    superFunc(self, ...)
    if not wasOff or spec.currentDischargeState ~= offState or g_currentMission == nil then
        return
    end
    local blocked, reason, fillTypeIndex = ContractGuard:isGroundDischargeBlocked(self, spec.currentDischargeNode)
    if blocked then
        g_currentMission:showBlinkingWarning(ContractGuard:getWarningText(reason, fillTypeIndex), 5000)
    end
end

-- Statik tus geri cagrisi: arac tuslarini kaydederken bu tablodan okunur, mod yuklenirken bir kez sarilir.
if Dischargeable ~= nil and Dischargeable.actionEventToggleDischargeToGround ~= nil then
    Dischargeable.cmGroundWarning = ContractGuardVehicle.overwriteToggleDischargeToGround
    if not Dischargeable.cmGroundWarningInstalled then
        Dischargeable.actionEventToggleDischargeToGround = Utils.overwrittenFunction(Dischargeable.actionEventToggleDischargeToGround,
            function(self, superFunc, ...)
                return Dischargeable.cmGroundWarning(self, superFunc, ...)
            end)
        Dischargeable.cmGroundWarningInstalled = true
    end
end
