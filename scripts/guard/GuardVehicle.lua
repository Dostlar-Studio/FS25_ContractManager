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
    local dischargedLiters = superFunc(self, dischargeNode, emptyLiters, object, targetFillUnitIndex)
    if ContractManagerPartnership ~= nil then
        pcall(ContractManagerPartnership.onDelivered, self, object, dischargedLiters)
    end
    return dischargedLiters
end
