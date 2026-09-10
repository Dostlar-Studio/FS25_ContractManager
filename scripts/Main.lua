--
-- FS25_ContractManager - Kontrat Yoneticisi
--
-- Cati: tum katmanlarin paylastigi sabitler, log yardimcisi, cift yukleme kilidi.
-- Yukleme sirasi (modDesc): Main -> guard/* -> Debug. Faz 2'de core/* buraya eklenir.
--
-- @author  Dostlar STUDIO
-- @version 1.0.0.0
--

ContractManager = {
    MOD_NAME = g_currentModName,
    MOD_DIRECTORY = g_currentModDirectory,
    VERSION = "1.13.1.0",
    LOG_PREFIX = "[CM]",

    -- savegame icindeki birlesik durum dosyasi ve devralinacak eski Guard dosyasi
    SAVEGAME_FILENAME = "FS25_ContractManager.xml",
    LEGACY_GUARD_SAVEGAME_FILENAME = "FS25_ContractGuard.xml",
    LEGACY_GUARD_MOD_NAME = "FS25_ContractGuard",
    BETTER_CONTRACTS_MOD_NAME = "FS25_BetterContracts",

    -- Faz 2'de Settings.lua'ya tasinir
    debugEnabled = false,    -- gelistirmede true: Debug.lua [CM/Debug] dokumu yazar
    guardEnabled = true,
}

-- ---------------------------------------------------------------------------
-- log
-- ---------------------------------------------------------------------------

local function formatLine(fmt, ...)
    local ok, line = pcall(string.format, fmt, ...)
    return ok and line or tostring(fmt)
end

function ContractManager.info(fmt, ...)
    Logging.info("%s %s", ContractManager.LOG_PREFIX, formatLine(fmt, ...))
end

---Mod metni. Anahtar cozulemezse (oyun "Missing ..." doner) yedek metin.
---Yedi dosyada ayni 9 satir tekrar ediyordu; tek yer burasi.
function ContractManager.text(key, fallback)
    if g_i18n ~= nil then
        local value = g_i18n:getText(key)
        if type(value) == "string" and value ~= "" and value:sub(1, 7) ~= "Missing" then
            return value
        end
    end
    return fallback or key
end

-- ---------------------------------------------------------------------------
-- Hook tuzagi: Utils.appendedFunction ORIJINALIN DONUS DEGERINI ATAR
--
-- Oyunun yardimcisi `oldFunc(...)` cagirir ama `return newFunc(...)` doner. Donus
-- degeri kullanilan bir fonksiyona ekleme yapinca o deger nil olur. Canli sunucuda
-- boyle oldu: AbstractMission.dismiss'e ekleme yaptik, MissionDismissEvent onun
-- donusunu streamWriteBool'a veriyor ->
--   "'streamWriteBool': Argument 1 has wrong type. Expected: Bool. Actual: Nil"
-- (2026-09-09 sunucu logu, 8 kez).
--
-- Donusu onemli olan her fonksiyonda BU yardimci kullanilir.
-- ---------------------------------------------------------------------------
function ContractManager.appendKeepingReturn(oldFunc, appendFunc)
    if oldFunc == nil then
        return appendFunc
    end
    return function(...)
        local results = { oldFunc(...) }
        appendFunc(...)
        return unpack(results)
    end
end

-- ---------------------------------------------------------------------------
-- Kontrat kimligi (COK OYUNCULU TUZAK)
--
-- AbstractMission.uniqueId istemciye HIC gonderilmez: writeStream'de yok, yalnizca
-- sunucuda Utils.getUniqueId ile uretilip savegame'e yazilir. Bu yuzden istemcide
-- mission.uniqueId nil'dir ve uniqueId ile calisan her istek sessizce duser
-- (zorla iptal, devret, davet, rezervasyon...). Kontratlar Object turevidir ve
-- mission:register() ile ag nesnesi olur, yani AG NESNE KIMLIGI iki tarafta da
-- gecerlidir. Istekler onu tasir; sunucu nesneyi cozup kendi uniqueId'sine ceker.
-- ---------------------------------------------------------------------------

---Ag uzerinden gonderilecek kontrat kimligi. Yoksa 0.
function ContractManager.getMissionObjectId(mission)
    if mission == nil or NetworkUtil == nil or NetworkUtil.getObjectId == nil then
        return 0
    end
    local ok, id = pcall(NetworkUtil.getObjectId, mission)
    if ok and type(id) == "number" then
        return id
    end
    return 0
end

---Yerel kimlik: sunucuda mission.uniqueId, istemcide senkronla gelen kopya.
function ContractManager.getMissionKey(mission)
    if mission == nil then
        return nil
    end
    if mission.getUniqueId ~= nil then
        local id = mission:getUniqueId()
        if type(id) == "string" and id ~= "" then
            return id
        end
    end
    if type(mission.uniqueId) == "string" and mission.uniqueId ~= "" then
        return mission.uniqueId
    end
    -- istemcide sunucudan ogrenilen kimlik (bkz. ContractManager.rememberMissionKey)
    return mission.cmUniqueId
end

---Sunucu: uniqueId'den ag kimligine (SYNC yayinlari icin).
function ContractManager.getMissionObjectIdByKey(uniqueId)
    if uniqueId == nil or uniqueId == "" or g_missionManager == nil
        or g_missionManager.getMissionByUniqueId == nil then
        return 0
    end
    local mission = g_missionManager:getMissionByUniqueId(uniqueId)
    if mission ~= nil then
        return ContractManager.getMissionObjectId(mission)
    end
    return 0
end

---Sunucu: ag kimliginden kontratin kendi uniqueId'sine.
function ContractManager.resolveMissionKey(objectId, fallback)
    if objectId ~= nil and objectId ~= 0 and NetworkUtil ~= nil and NetworkUtil.getObject ~= nil then
        local ok, mission = pcall(NetworkUtil.getObject, objectId)
        if ok and mission ~= nil then
            local key = ContractManager.getMissionKey(mission)
            if key ~= nil then
                return key
            end
        end
    end
    if type(fallback) == "string" and fallback ~= "" then
        return fallback
    end
    return nil
end

---Istemci: sunucudan gelen kimligi kontrat nesnesine yapistir ki yerel
---aramalar (rezervasyon, ortaklik) eslesebilsin.
function ContractManager.rememberMissionKey(objectId, uniqueId)
    if objectId == nil or objectId == 0 or type(uniqueId) ~= "string" or uniqueId == ""
        or NetworkUtil == nil or NetworkUtil.getObject == nil then
        return nil
    end
    local ok, mission = pcall(NetworkUtil.getObject, objectId)
    if ok and mission ~= nil then
        mission.cmUniqueId = uniqueId
        return mission
    end
    return nil
end

---Rutin, sik tekrarlayan olaylar icin. debugEnabled kapaliyken hicbir sey yazmaz;
---aksi halde tek bir ayar degisikligi bile log'u satirlarca sisirir.
function ContractManager.debug(fmt, ...)
    if ContractManager.debugEnabled then
        Logging.info("%s %s", ContractManager.LOG_PREFIX, formatLine(fmt, ...))
    end
end

function ContractManager.warning(fmt, ...)
    Logging.warning("%s %s", ContractManager.LOG_PREFIX, formatLine(fmt, ...))
end

function ContractManager.error(fmt, ...)
    Logging.error("%s %s", ContractManager.LOG_PREFIX, formatLine(fmt, ...))
end

-- ---------------------------------------------------------------------------
-- cift yukleme kilidi
-- ---------------------------------------------------------------------------

---Eski bagimsiz Guard modu da yukluyse Guard katmanini kapat; ayni hook'lar iki kez
---kurulursa urun iki kez geri alinir.
function ContractManager:isLegacyGuardLoaded()
    return g_modIsLoaded ~= nil and g_modIsLoaded[self.LEGACY_GUARD_MOD_NAME] == true
end

if ContractManager:isLegacyGuardLoaded() then
    ContractManager.guardEnabled = false
    ContractManager.error(
        "%s is also active. The Guard layer of Contract Manager is DISABLED to avoid double protection; remove %s.",
        ContractManager.LEGACY_GUARD_MOD_NAME, ContractManager.LEGACY_GUARD_MOD_NAME
    )
end

-- ---------------------------------------------------------------------------
-- yardimcilar (katmanlarin ortak kullandigi)
-- ---------------------------------------------------------------------------

---Aktif gorevin savegame klasoru; yoksa nil.
function ContractManager:getSavegameDirectory()
    local mission = g_currentMission
    local missionInfo = mission ~= nil and mission.missionInfo or nil
    if missionInfo == nil or missionInfo.savegameDirectory == nil then
        return nil
    end
    return missionInfo.savegameDirectory
end

---FS25_BetterContracts da yuklu mu? Ayni noktalara (odul, ceza, limit, uretim) yazar.
function ContractManager:isBetterContractsLoaded()
    return g_modIsLoaded ~= nil and g_modIsLoaded[self.BETTER_CONTRACTS_MOD_NAME] == true
end

---Kural katmani (odul/limit/uretim/sure) etkin mi? Guard ve Registry bundan bagimsizdir.
function ContractManager:getRulesEnabled()
    if not self:isBetterContractsLoaded() then
        return true
    end
    if ContractManagerSettings ~= nil and ContractManagerSettings.get ~= nil then
        return ContractManagerSettings:get("compat.overrideBetterContracts") == true
    end
    return false
end

---Sunucu admin mi (dedicated admin veya sunucunun kendisi)?
function ContractManager:getIsAdmin()
    local mission = g_currentMission
    if mission == nil then
        return false
    end
    return mission:getIsServer() or mission.isMasterUser == true
end

if ContractManager:isBetterContractsLoaded() then
    ContractManager.warning("%s detected: reward/limit/generation/duration rules yield to it unless compat#overrideBetterContracts=true",
        ContractManager.BETTER_CONTRACTS_MOD_NAME)
end

-- messageCenter mesajlari (katmanlar arasi gevsek baglanti; Discord entegrasyonu bunlari dinler)
ContractManager.MESSAGE_SETTINGS_CHANGED = "CONTRACT_MANAGER_SETTINGS_CHANGED"   -- (key, value) veya bos
ContractManager.MESSAGE_CONTRACT_ACCEPTED = "CONTRACT_MANAGER_CONTRACT_ACCEPTED" -- (mission, meta)
ContractManager.MESSAGE_CONTRACT_FINISHED = "CONTRACT_MANAGER_CONTRACT_FINISHED" -- (mission, historyEntry)
ContractManager.MESSAGE_CONTRACT_PAID = "CONTRACT_MANAGER_CONTRACT_PAID"         -- (mission, historyEntry)
ContractManager.MESSAGE_CONTRACT_WARNING = "CONTRACT_MANAGER_CONTRACT_WARNING"   -- (mission, minutesLeft)
ContractManager.MESSAGE_GUARD_BLOCKED = "CONTRACT_MANAGER_GUARD_BLOCKED"         -- (code, farmId, fillTypeIndex, amount)
ContractManager.MESSAGE_REPUTATION_CHANGED = "CONTRACT_MANAGER_REPUTATION_CHANGED" -- (farmId, points, delta)
ContractManager.MESSAGE_CONTRACT_TRANSFERRED = "CONTRACT_MANAGER_CONTRACT_TRANSFERRED" -- (mission, oldFarmId, newFarmId)
ContractManager.MESSAGE_PARTNERSHIP_CHANGED = "CONTRACT_MANAGER_PARTNERSHIP_CHANGED" -- (mission, ownerFarmId, partnerFarmId)

function ContractManager.publish(message, ...)
    if g_messageCenter ~= nil and g_messageCenter.publish ~= nil and message ~= nil then
        g_messageCenter:publish(message, ...)
    end
end

ContractManager.info("v%s loading (guard=%s, debug=%s)",
    ContractManager.VERSION, tostring(ContractManager.guardEnabled), tostring(ContractManager.debugEnabled))
