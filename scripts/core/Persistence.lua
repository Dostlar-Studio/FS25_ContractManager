--
-- FS25_ContractManager - Persistence
--
-- Savegame icindeki tek durum dosyasi: <savegame>/FS25_ContractManager.xml
--   <contractManager version="2">
--     <guard>    ... ContractGuard baseline'lari   (ContractGuard:writeToXML)
--     <registry> ... aktif meta / gecmis / istatistik (ContractManagerRegistry:writeToXML)
--
-- Yeni dosya yoksa eski bagimsiz FS25_ContractGuard.xml (kok: contractGuard) okunur;
-- ilk kayitta yeni bicime yazilir. Bu dosya modDesc'te guard/* SONRASINDA yuklenir:
-- loadMap sirasi kayit sirasidir ve Guard.loadMap'in once calismasi gerekir.
--
-- Yazma noktasi tek: FSCareerMissionInfo.saveToXMLFile (oyunun kendi kayit yolu).
-- addModEventListener saveSavegame'i cagirmaz.
--

ContractManagerPersistence = {
    FILE_VERSION = 2,
    ROOT = "contractManager",
    LEGACY_ROOT = "contractGuard",
    migratedFromLegacy = false,
    loadedFromFile = false,
}

local Persistence = ContractManagerPersistence

function Persistence:getFilename()
    local directory = ContractManager:getSavegameDirectory()
    if directory == nil then
        return nil
    end
    return directory .. "/" .. ContractManager.SAVEGAME_FILENAME
end

function Persistence:getLegacyFilename()
    local directory = ContractManager:getSavegameDirectory()
    if directory == nil then
        return nil
    end
    return directory .. "/" .. ContractManager.LEGACY_GUARD_SAVEGAME_FILENAME
end

function Persistence:reset()
    self.migratedFromLegacy = false
    self.loadedFromFile = false
    if ContractGuard ~= nil and ContractGuard.resetState ~= nil then
        ContractGuard:resetState()
    end
    if ContractManagerRegistry ~= nil then
        ContractManagerRegistry:reset()
    end
    if ContractManagerPartnership ~= nil then
        ContractManagerPartnership.reset()
    end
end

function Persistence:load()
    self:reset()

    local filename = self:getFilename()
    if filename == nil then
        return
    end

    if fileExists(filename) then
        local xmlId = loadXMLFile("ContractManagerSavegame", filename)
        if xmlId == nil or xmlId == 0 then
            ContractManager.warning("Could not load '%s'", filename)
            return
        end
        local version = getXMLInt(xmlId, self.ROOT .. "#version") or 0
        if ContractGuard ~= nil and ContractGuard.readFromXML ~= nil then
            ContractGuard:readFromXML(xmlId, self.ROOT .. ".guard")
        end
        if ContractManagerRegistry ~= nil then
            ContractManagerRegistry:readFromXML(xmlId, self.ROOT .. ".registry")
        end
        if ContractManagerPartnership ~= nil then
            ContractManagerPartnership:readFromXML(xmlId, self.ROOT .. ".partnerships")
        end
        delete(xmlId)
        self.loadedFromFile = true
        ContractManager.info("State loaded from '%s' (version %d)", filename, version)
        return
    end

    local legacy = self:getLegacyFilename()
    if legacy ~= nil and fileExists(legacy) then
        local xmlId = loadXMLFile("ContractGuardLegacySavegame", legacy)
        if xmlId == nil or xmlId == 0 then
            ContractManager.warning("Could not load legacy '%s'", legacy)
            return
        end
        if ContractGuard ~= nil and ContractGuard.readFromXML ~= nil then
            ContractGuard:readFromXML(xmlId, self.LEGACY_ROOT)
        end
        delete(xmlId)
        self.migratedFromLegacy = true
        self.loadedFromFile = true
        ContractManager.info("Migrated guard baselines from legacy '%s'; will be rewritten as '%s' on next save", legacy, filename)
    end
end

function Persistence:save()
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() then
        return false
    end

    local filename = self:getFilename()
    if filename == nil then
        ContractManager.warning("Savegame directory unavailable; state was not saved")
        return false
    end

    local xmlId = createXMLFile("ContractManagerSavegame", filename, self.ROOT)
    if xmlId == nil or xmlId == 0 then
        ContractManager.error("Could not create '%s'", filename)
        return false
    end

    setXMLInt(xmlId, self.ROOT .. "#version", self.FILE_VERSION)
    if ContractGuard ~= nil and ContractGuard.writeToXML ~= nil then
        ContractGuard:writeToXML(xmlId, self.ROOT .. ".guard")
    end
    if ContractManagerRegistry ~= nil then
        ContractManagerRegistry:writeToXML(xmlId, self.ROOT .. ".registry")
    end
    if ContractManagerPartnership ~= nil then
        ContractManagerPartnership:writeToXML(xmlId, self.ROOT .. ".partnerships")
    end

    saveXMLFile(xmlId)
    delete(xmlId)
    self.migratedFromLegacy = false
    return true
end

-- ---------------------------------------------------------------------------
-- mod olay dinleyicisi
-- ---------------------------------------------------------------------------

function Persistence:loadMap(mapName)
    local mission = g_currentMission
    if mission ~= nil and mission:getIsServer() then
        self:load()
    end
end

function Persistence:deleteMap()
    self:reset()
end

if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    FSCareerMissionInfo.saveToXMLFile = ContractManager.appendKeepingReturn(FSCareerMissionInfo.saveToXMLFile, function()
        Persistence:save()
        if ContractManagerSettings ~= nil then
            ContractManagerSettings:saveIfDirty()
        end
    end)
else
    ContractManager.error("FSCareerMissionInfo.saveToXMLFile not found; state will NOT persist across saves")
end

addModEventListener(Persistence)
