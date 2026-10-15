--
-- FS25_ContractManager - Persistence
--
-- Savegame icindeki tek durum dosyasi: <savegame>/FS25_ContractManager.xml
--   <contractManager version="2">
--     <guard>    ... ContractGuard baseline'lari   (ContractGuard:writeToXML)
--     <registry> ... aktif meta / gecmis / istatistik (ContractManagerRegistry:writeToXML)
--
-- Bu dosya modDesc'te guard/* SONRASINDA yuklenir: loadMap sirasi kayit sirasidir ve
-- Guard.loadMap'in once calismasi gerekir.
--
-- Yazma noktasi tek: FSCareerMissionInfo.saveToXMLFile (oyunun kendi kayit yolu).
-- addModEventListener saveSavegame'i cagirmaz.
--

ContractManagerPersistence = {
    FILE_VERSION = 2,
    ROOT = "contractManager",
}

local Persistence = ContractManagerPersistence

function Persistence:getFilename()
    local directory = ContractManager:getSavegameDirectory()
    if directory == nil then
        return nil
    end
    return directory .. "/" .. ContractManager.SAVEGAME_FILENAME
end

function Persistence:reset()
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
    if filename == nil or not fileExists(filename) then
        return
    end

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
    ContractManager.info("State loaded from '%s' (version %d)", filename, version)
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

---Ayarlarin gecikmeli yazma sayaci (oyun kaydini beklemeden).
function Persistence:update(dt)
    if ContractManagerSettings ~= nil then
        ContractManagerSettings:updateSaveTimer(dt)
    end
end

if FSCareerMissionInfo ~= nil and FSCareerMissionInfo.saveToXMLFile ~= nil then
    -- Oyunun kayit akisinda: hatamiz oyunun kaydini yarida kesmesin (kanca siniri korumali, 1.26.0.0).
    FSCareerMissionInfo.saveToXMLFile = ContractManager.appendKeepingReturn(FSCareerMissionInfo.saveToXMLFile, function()
        ContractManager.guard("Savegame write", Persistence.save, Persistence)
        if ContractManagerSettings ~= nil then
            ContractManager.guard("Settings write", ContractManagerSettings.saveIfDirty, ContractManagerSettings)
        end
    end)
else
    ContractManager.error("FSCareerMissionInfo.saveToXMLFile not found; state will NOT persist across saves")
end

addModEventListener(Persistence)
