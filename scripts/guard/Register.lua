local modName = g_currentModName
local specializationName = modName .. ".contractGuardVehicle"

local function hasDischargeableSpecialization(typeEntry)
    if SpecializationUtil.hasSpecialization(Dischargeable, typeEntry.specializations) then
        return true
    end

    -- Some FS25 base types retain the registered name but expose a proxied
    -- specialization object while the asynchronous type setup is running.
    for _, name in ipairs(typeEntry.specializationNames or {}) do
        local normalizedName = string.lower(name)
        if normalizedName == "dischargeable" or normalizedName:sub(-14) == ".dischargeable" then
            return true
        end
    end
    return false
end

local function injectContractGuardSpecialization(typeManager)
    if typeManager.typeName ~= "vehicle" then
        return
    end
    if ContractGuard == nil or ContractGuard.disabled then
        Logging.info("[CM/Guard] Guard disabled; vehicle protection not installed")
        return
    end

    local installed = 0
    local candidates = 0
    local alreadyInstalled = 0
    local totalTypes = 0
    for typeName, typeEntry in pairs(typeManager:getTypes()) do
        totalTypes = totalTypes + 1
        if typeEntry ~= nil and hasDischargeableSpecialization(typeEntry) then
            candidates = candidates + 1
            if typeEntry.specializationsByName[specializationName] == nil then
                typeManager:addSpecialization(typeName, specializationName)
                if typeEntry.specializationsByName[specializationName] ~= nil then
                    installed = installed + 1
                else
                    Logging.error("[CM/Guard] Could not protect vehicle type '%s'", tostring(typeName))
                end
            else
                alreadyInstalled = alreadyInstalled + 1
            end
        end
    end

    Logging.info(
        "[CM/Guard] Protection installed=%d existing=%d candidates=%d totalTypes=%d",
        installed,
        alreadyInstalled,
        candidates,
        totalTypes
    )
end

TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes, injectContractGuardSpecialization)
