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
    VERSION = "1.24.2.0",
    -- Ag olaylarinin bicimi degistiginde ARTTIR. Sunucu ile istemci farkli protokolde ise
    -- sayilar sessizce bozuluyordu (1.14.2 dort tamsayi yaziyordu, 1.15 bes tane okuyordu).
    PROTOCOL = 2,
    LOG_PREFIX = "[CM]",

    -- savegame icindeki birlesik durum dosyasi ve devralinacak eski Guard dosyasi
    SAVEGAME_FILENAME = "FS25_ContractManager.xml",
    LEGACY_GUARD_SAVEGAME_FILENAME = "FS25_ContractGuard.xml",
    LEGACY_GUARD_MOD_NAME = "FS25_ContractGuard",
    BETTER_CONTRACTS_MOD_NAME = "FS25_BetterContracts",

    -- Faz 2'de Settings.lua'ya tasinir
    debugEnabled = false,    -- gelistirmede true: Debug.lua [CM/Debug] dokumu yazar
    consoleCommands = false, -- konsol komutlari (cm*) kapali: her islem oyun ici butonlarda var (kullanici karari 2026-09-13)
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
---Oyunun onay penceresinin yaniti. YesNoDialog geri cagriyi target VARSA `cb(target, deger)`,
---target YOKSA `cb(deger)` diye cagirir; imza yayinlanmamis oldugu icin iki argumani da tarariz.
---AdminTools target'siz cagirip IKINCI argumani okuyordu: "Evet" hicbir sey yapmiyordu (2026-09-13).
function ContractManager.dialogAnswer(a, b)
    if type(a) == "boolean" then
        return a
    end
    if type(b) == "boolean" then
        return b
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Stok Kontratlar sayfasinin alt buton cubugu (1.24.1.0)
--
-- Uc modul (ortaklik, rezervasyon, yonetici) ayni InGameMenuContractsFrame.setButtonsForState
-- fonksiyonuna AYRI AYRI ekleme yapiyordu ve hatalari pcall ile SESSIZCE yutuyordu.
-- Test sunucusunda (2026-09-22) "Panoyu yenile" iki kez goruldu: kanca tek, kurulum tek;
-- demek ki oyun ayni buton tablosunu cagrilar arasinda yeniden kullaniyor ve eklediklerimiz
-- BIRIKIYOR. Oyunun kaynagi yayinlanmadigi icin tablonun ne zaman yeniden kuruldugunu
-- bilemiyoruz; bu yuzden her iki durumda da dogru calisan bir yol:
--   * Her tablonun ILK gorulen (saf stok) hali saklanir; ayni tablo tekrar gelirse once
--     o hale geri dondurulur, sonra eklemeler yapilir. Yeni tablo gelirse yeni kopya alinir.
--   * Kanca oyunun SINIFINA bir kez takilir (sinif surec boyunca yasar, mod her harita
--     yuklemesinde yeniden calisir); cagrilan dagitici her yuklemede guncellenir.
--   * Bir ekleyicinin hatasi digerlerini durdurmaz ve LOGA yazilir (ekleyici basina bir kez).
-- Ekleyiciler stok girdilerini YERINDE degistirmemeli (saklanan kopya ayni nesneyi tutar);
-- degistirmek gerekirse tablodaki yuvaya yeni bir girdi konur.
-- ---------------------------------------------------------------------------

ContractManager.buttonAppenders = {}
local buttonSnapshots = setmetatable({}, { __mode = "k" })
local buttonErrorsReported = {}

---Ekleyici kaydet (ad benzersiz; ayni adla tekrar kayit onu gunceller). Kucuk sira once calisir.
function ContractManager.registerButtonAppender(name, order, fn)
    for _, entry in ipairs(ContractManager.buttonAppenders) do
        if entry.name == name then
            entry.fn, entry.order = fn, order
            table.sort(ContractManager.buttonAppenders, function(a, b) return a.order < b.order end)
            return
        end
    end
    table.insert(ContractManager.buttonAppenders, { name = name, order = order, fn = fn })
    table.sort(ContractManager.buttonAppenders, function(a, b) return a.order < b.order end)
end

---Tabloyu saf stok haline dondur (ilk goruldugunde kopyasini al). Donus: geri donduruldu mu.
function ContractManager.restoreStockButtons(list)
    if type(list) ~= "table" then
        return false
    end
    local snapshot = buttonSnapshots[list]
    if snapshot == nil then
        snapshot = {}
        for index, info in ipairs(list) do
            snapshot[index] = info
        end
        buttonSnapshots[list] = snapshot
        return false
    end
    for index = #list, 1, -1 do
        list[index] = nil
    end
    for index, info in ipairs(snapshot) do
        list[index] = info
    end
    return true
end

---Teshis (1.24.2.0): buton kurulurken sayfa ne goruyor? Test sunucusunda secili aktif
---kontrat varken "Zorla iptal" ve "Ortak davet et" CIKMADI (ikisi de secime bagli) ve
---"Panoyu yenile" yonetici olmayan oyuncuda goruldu; logda iz yoktu. Satir yalnizca
---icerik DEGISTIGINDE ve oturum basina en fazla BUTTON_PROBE_MAX kez yazilir.
ContractManager.BUTTON_PROBE_MAX = 12
local probeCount, probeLast = 0, nil

function ContractManager.describeButtonState(frame, state)
    local getter = frame ~= nil and frame.getSelectedContract or nil
    local okCall, contract = false, nil
    if getter ~= nil then
        okCall, contract = pcall(getter, frame)
    end
    local mission = (okCall and type(contract) == "table") and contract.mission or nil
    local menu = g_inGameMenu
    local myFarm = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    return string.format("state=%s getter=%s call=%s contract=%s mission=%s status=%s owner=%s myFarm=%s admin(mission=%s menu=%s menuServer=%s)",
        tostring(state), tostring(getter ~= nil), tostring(okCall), type(contract),
        tostring(mission ~= nil), tostring(mission ~= nil and mission.status or nil),
        tostring(mission ~= nil and mission.farmId or nil), tostring(myFarm),
        tostring(g_currentMission ~= nil and g_currentMission.isMasterUser or nil),
        tostring(menu ~= nil and menu.isMasterUser or nil), tostring(menu ~= nil and menu.isServer or nil))
end

function ContractManager.probeButtonState(frame, state)
    if probeCount >= ContractManager.BUTTON_PROBE_MAX then
        return false
    end
    local ok, line = pcall(ContractManager.describeButtonState, frame, state)
    if not ok or line == probeLast then
        return false
    end
    probeLast = line
    probeCount = probeCount + 1
    ContractManager.info("Contracts page buttons: %s", line)
    return true
end

---Dagitici: stok hale don, sonra ekleyicileri sirayla calistir.
function ContractManager.runButtonAppenders(frame, state)
    if frame == nil or type(frame.menuButtonInfo) ~= "table" then
        return
    end
    ContractManager.probeButtonState(frame, state)
    ContractManager.restoreStockButtons(frame.menuButtonInfo)
    for _, entry in ipairs(ContractManager.buttonAppenders) do
        local ok, err = pcall(entry.fn, frame)
        if not ok and not buttonErrorsReported[entry.name] then
            buttonErrorsReported[entry.name] = true
            ContractManager.warning("Contracts page button '%s' failed: %s", entry.name, tostring(err))
        end
    end
end

---Kancayi oyunun sinifina bir kez tak. Donus: kanca yerinde mi.
function ContractManager.installButtonBar()
    local cls = InGameMenuContractsFrame
    if cls == nil or cls.setButtonsForState == nil then
        return false
    end
    cls.cmButtonDispatch = ContractManager.runButtonAppenders
    if cls.cmButtonHookInstalled then
        return true
    end
    cls.setButtonsForState = Utils.appendedFunction(cls.setButtonsForState, function(frame, state)
        local dispatch = InGameMenuContractsFrame ~= nil and InGameMenuContractsFrame.cmButtonDispatch or nil
        if dispatch ~= nil then
            dispatch(frame, state)
        end
    end)
    cls.cmButtonHookInstalled = true
    return true
end

-- ---------------------------------------------------------------------------
-- Fare imleci (mod pencereleri)
--
-- Oyunun tabani (ScreenElement:onOpen/onClose) imleci gosterip geri alir, AMA yalnizca
-- kok <GUI> etiketinde onOpen/onClose geri cagrilari TANIMLIYSA: Gui:showDialog/closeDialog
-- kok elemanin onOpenCallback/onCloseCallback'ini cagirir. Tanimli degilse ne tabanin
-- kodu ne de bizim onClose'umuz calisir (FarmMarket'te canlida yasandi: pencere kapandi,
-- imlec ekranda kaldi, hareket kisitlandi - 2026-09-13).
-- ---------------------------------------------------------------------------

function ContractManager.cursorVisible()
    if g_inputBinding ~= nil and g_inputBinding.getShowMouseCursor ~= nil then
        local ok, value = pcall(g_inputBinding.getShowMouseCursor, g_inputBinding)
        if ok then
            return value == true
        end
    end
    return false
end

function ContractManager.setCursor(visible)
    if g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor ~= nil then
        pcall(g_inputBinding.setShowMouseCursor, g_inputBinding, visible == true)
    end
end

---Pencere acilmadan ONCE cagrilir: o anki imlec durumunu pencerede saklar.
---Tabanin lastMouseCursorState'i guvenilmez oldugu icin kendi durumumuzu tutuyoruz.
function ContractManager.rememberCursor(dialog)
    if dialog ~= nil then
        dialog.cmCursorWas = ContractManager.cursorVisible()
    end
end

---Kapanista: acilis oncesindeki duruma don (dunyada gizli, menude gorunur).
function ContractManager.restoreCursor(dialog)
    ContractManager.setCursor(dialog ~= nil and dialog.cmCursorWas == true)
end

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
ContractManager.MESSAGE_PRODUCT_LOST = "CONTRACT_MANAGER_PRODUCT_LOST"           -- (mission, liters)
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
