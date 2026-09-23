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
    VERSION = "1.24.6.0",
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
-- Stok Kontratlar sayfasinin alt buton cubugu
--
-- KOK SEBEP (1.24.6.0; 1.24.1.0-1.24.5.0 yanlis teshis uzerine kuruldu): FS25'in tanimladigi
-- menu eylemleri arasinda MENU_EXTRA_1 (X), MENU_EXTRA_2 (C) ve MENU_ACTIVATE (Bosluk) var,
-- MENU_EXTRA_3/4 YOK (sdk/xmlDoku/inputActions.xml). MENU_EXTRA_3'u FS25_BetterContracts kendi
-- modDesc'inde tanimliyor; o mod yokken oyunun InputAction tablosunda MENU_EXTRA_3 YOK. Oyunun
-- TabbedMenu:assignMenuButtonInfo'su eylemi gecersiz girdinin yuvasini GORUNUR yapar ama
-- metnini, eylemini ve geri cagrisini GUNCELLEMEZ: yuvada onceki cizimin yazisi kalir. Test
-- sunucusunda (2026-09-22/23) gorulen "Panoyu yenile" x2 ve kontrat sayfasinda "Yonetici olarak
-- giris yap" / "Ciftligi duzenle" hep davet butonunun (MENU_EXTRA_3 = nil) yuvasiydi.
-- "Oyun tabloyu yeniden kullaniyor, butonlar birikiyor" (1.24.1.0) ve "menuye liste degisti
-- denmiyor" (1.24.5.0) teshisleri YANLISTI; testler MENU_EXTRA_3'u kendileri tanimladigi icin
-- hatayi hic goremedi.
-- Kurallar:
--   * Butonlar ContractManager.addMenuButton ile eklenir: aday listesinden oyunda TANIMLI ve
--     listede KULLANILMAYAN ilk eylem secilir. Oyuncu eylemi C/Bosluk'u, yonetici araci X'i ister.
--   * Ekleyicilerden sonra dogrulama: gecersiz eylemli, ayni eylemi ikinci kez kullanan ya da
--     yuva sayisini (FS25 oyun menusu: 6) asan girdimiz cubuga GIRMEZ ve bir kez loglanir.
--     Ekleyiciler oncelik sirasiyla calisir; yer yetmezse sondaki (yonetici araci) duser.
--   * Her geciste once bir onceki geciste EKLEDIKLERIMIZ ayiklanir; yerine gectigimiz ya da
--     gizledigimiz stok girdi (listede yoksa) yerine geri konur. Stok girdi nesneleri yerinde
--     degistirilmez. Oyun tabloyu her cagrida yeni kursa da, ayni tabloyu yeniden doldursa da, hic
--     dokunmasa da sonuc ayni. Canli kanit taze tablodan yana (BetterContracts ayni noktaya her
--     cagrida ayni nesneyi ekliyor ve birikmiyor); teshis satirindaki reused= bunu olcer.
--   * Kanca oyunun SINIFINA bir kez takilir (sinif surec boyunca yasar, mod her harita
--     yuklemesinde yeniden calisir); cagrilan dagitici her yuklemede guncellenir.
--   * Bir ekleyicinin hatasi digerlerini durdurmaz ve LOGA yazilir (ekleyici basina bir kez).
-- ---------------------------------------------------------------------------

ContractManager.buttonAppenders = {}
-- Tus adaylari (oyunun eylem adlari); sira tercih sirasidir.
ContractManager.MENU_KEYS_PLAYER = { "MENU_EXTRA_2", "MENU_ACTIVATE", "MENU_EXTRA_1" }
ContractManager.MENU_KEYS_ADMIN = { "MENU_EXTRA_1", "MENU_EXTRA_2", "MENU_ACTIVATE" }
-- Oyun menusundeki buton yuvasi (InGameMenu menuButton[1..6]); calisirken menuden okunur.
ContractManager.MENU_BAR_SLOTS = 6

local ownButtons = setmetatable({}, { __mode = "k" })      -- bizim cubuga koydugumuz girdiler
local replacedStock = setmetatable({}, { __mode = "k" })   -- bizim girdi -> yerine gectigi stok girdi
local hiddenStock = setmetatable({}, { __mode = "k" })     -- liste -> { {index, info} } gizledigimiz stok girdiler
local lastListByFrame = setmetatable({}, { __mode = "k" }) -- sayfa -> onceki gecisin tablosu (reused= olcumu)
local buttonErrorsReported = {}
local buttonSkipsReported = {}

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

---Oyun bu eylemi kabul eder mi? (TabbedMenu:assignMenuButtonInfo ile ayni olcut)
function ContractManager.isMenuActionValid(action)
    return action ~= nil and InputAction ~= nil and InputAction[action] ~= nil
end

---Alt cubuktaki yuva sayisi. Ikinci donus: menuden mi olculdu (false = varsayilan 6).
---Baska modlar yuva ekleyebilir (ana sunucuda FS25_additionalGameSettings iki yuva daha ekliyor).
function ContractManager.getMenuBarSlots()
    local menu = g_inGameMenu
    if menu ~= nil and type(menu.menuButton) == "table" and #menu.menuButton > 0 then
        return #menu.menuButton, true
    end
    return ContractManager.MENU_BAR_SLOTS, false
end

---Listede kullanilmayan, oyunda tanimli ilk aday eylem; yoksa nil.
function ContractManager.pickMenuAction(list, candidates)
    local used = {}
    for _, info in ipairs(type(list) == "table" and list or {}) do
        if type(info) == "table" and info.inputAction ~= nil then
            used[info.inputAction] = true
        end
    end
    for _, name in ipairs(candidates or {}) do
        local action = InputAction ~= nil and InputAction[name] or nil
        if action ~= nil and not used[action] then
            return action
        end
    end
    return nil
end

---Bir butonun neden cubukta olmadigi, (buton, sebep) basina bir kez. Kod hatasi uyari olarak yazilir.
local function reportButtonSkip(label, reason, isError)
    local key = tostring(label) .. "|" .. tostring(reason)
    if buttonSkipsReported[key] then
        return
    end
    buttonSkipsReported[key] = true
    local log = isError and ContractManager.warning or ContractManager.info
    log("Contracts page button '%s' not shown: %s", tostring(label), tostring(reason))
end

---Cubuga buton ekle. Donus: kullanilan eylem; yer ya da bos tus yoksa nil (sebep loglanir).
function ContractManager.addMenuButton(list, candidates, text, callback)
    if type(list) ~= "table" then
        return nil
    end
    local slots = ContractManager.getMenuBarSlots()
    if #list >= slots then
        reportButtonSkip(text, string.format("button bar full (%d slots)", slots), false)
        return nil
    end
    local action = ContractManager.pickMenuAction(list, candidates)
    if action == nil then
        reportButtonSkip(text, "no free menu key", false)
        return nil
    end
    local info = { inputAction = action, text = text, callback = callback }
    table.insert(list, info)
    ownButtons[info] = true
    return action
end

---Stok girdiyi yuvasinda yenisiyle degistir. Stok nesne YERINDE degistirilmez; sonraki geciste
---stripOwnButtons onu geri koyar.
function ContractManager.replaceMenuButton(list, index, info)
    if type(list) ~= "table" or list[index] == nil or type(info) ~= "table" then
        return false
    end
    replacedStock[info] = replacedStock[list[index]] or list[index]
    list[index] = info
    ownButtons[info] = true
    return true
end

---Stok girdiyi bu gecis icin cubuktan kaldir (ornek: sahip olmayanda oyunun Iptal'i). Nesne
---saklanir; sonraki geciste stripOwnButtons, listede yoksa ayni yerine geri koyar. Donus: girdi.
function ContractManager.hideMenuButton(list, index)
    if type(list) ~= "table" or list[index] == nil then
        return nil
    end
    local info = table.remove(list, index)
    if not ownButtons[info] then
        local hidden = hiddenStock[list] or {}
        hidden[#hidden + 1] = { index = index, info = info }
        hiddenStock[list] = hidden
    end
    return info
end

---Onceki geciste eklediklerimizi ayikla; yerine gectigimiz ve gizledigimiz stok girdileri (oyun
---onlari yeniden koymadiysa) geri koy. Donus: degisen girdi sayisi.
function ContractManager.stripOwnButtons(list)
    if type(list) ~= "table" then
        return 0
    end
    local count = 0
    for index = #list, 1, -1 do
        local info = list[index]
        if info ~= nil and ownButtons[info] then
            local original = replacedStock[info]
            if original ~= nil then
                list[index] = original
            else
                table.remove(list, index)
            end
            count = count + 1
        end
    end
    local hidden = hiddenStock[list]
    if hidden ~= nil then
        hiddenStock[list] = nil
        local present = {}
        for _, info in ipairs(list) do
            present[info] = true
        end
        -- gizlenme sirasinin tersiyle: her kayit kendi anindaki yerine doner
        for i = #hidden, 1, -1 do
            local entry = hidden[i]
            if not present[entry.info] then
                table.insert(list, math.min(entry.index, #list + 1), entry.info)
                present[entry.info] = true
                count = count + 1
            end
        end
    end
    return count
end

---Listede bizim girdimiz kac tane
function ContractManager.countAddedButtons(list)
    local count = 0
    for _, info in ipairs(type(list) == "table" and list or {}) do
        if ownButtons[info] then
            count = count + 1
        end
    end
    return count
end

---Ekleyicilerden sonra: bu geciste gelen girdileri (stock kumesinde olmayanlar) dogrula.
---Gecersiz eylem, ayni eylemin ikinci kullanimi ya da yuva sayisini asan girdi cikarilir ve bir
---kez loglanir; cikarilan bir degisiklik girdisinin yerine stok girdi geri konur. Stok girdilere
---dokunulmaz. Donus: cikarilan sayi.
function ContractManager.sanitizeButtons(list, stock)
    if type(list) ~= "table" then
        return 0
    end
    stock = stock or {}
    local slots = ContractManager.getMenuBarSlots()
    local used, kept, removed = {}, {}, 0
    for _, info in ipairs(list) do
        if stock[info] then
            kept[#kept + 1] = info
            if type(info) == "table" and info.inputAction ~= nil then
                used[info.inputAction] = true
            end
        else
            local action = type(info) == "table" and info.inputAction or nil
            local reason, isError = nil, false
            if not ContractManager.isMenuActionValid(action) then
                reason, isError = string.format("input action %s does not exist in this game", tostring(action)), true
            elseif used[action] then
                reason, isError = string.format("key %s already used on this page", tostring(action)), true
            elseif #kept >= slots then
                reason = string.format("button bar full (%d slots)", slots)
            end
            if reason == nil then
                kept[#kept + 1] = info
                used[action] = true
                ownButtons[info] = true
            else
                removed = removed + 1
                reportButtonSkip(type(info) == "table" and info.text or "?", reason, isError)
                local original = replacedStock[info]
                if original ~= nil then
                    kept[#kept + 1] = original
                end
            end
        end
    end
    if removed > 0 then
        for index = #list, 1, -1 do
            list[index] = nil
        end
        for index, info in ipairs(kept) do
            list[index] = info
        end
    end
    return removed
end

---Teshis: buton kurulurken sayfa ne goruyor ve cubuga ne gidiyor. Her FARKLI durum oturum
---basina bir kez yazilir (en fazla BUTTON_PROBE_MAX); secimi iki kontrat arasinda gidip gelmek
---tavani tuketmez (1.24.5.0'da 12 satir bir dakikada doldu).
ContractManager.BUTTON_PROBE_MAX = 40
local probeCount, probeSeen = 0, {}
local menuKeysReported = false

---Teshis sayaclarini sifirla (testler; her durum/sebep yeniden bir kez loglanir)
function ContractManager.resetButtonDiagnostics()
    probeCount, probeSeen, menuKeysReported = 0, {}, false
    buttonSkipsReported = {}
end

local function describeBar(list)
    local parts = {}
    for _, info in ipairs(type(list) == "table" and list or {}) do
        local action = type(info) == "table" and info.inputAction or nil
        parts[#parts + 1] = tostring(action) .. (ownButtons[info] and "*" or "")
    end
    return table.concat(parts, ",")
end

---reused: bu sayfa bir onceki geciste AYNI tabloyu mu verdi (oyunun tablo modeli; nil = bilinmiyor)
function ContractManager.describeButtonState(frame, state, reused)
    local getter = frame ~= nil and frame.getSelectedContract or nil
    local okCall, contract = false, nil
    if getter ~= nil then
        okCall, contract = pcall(getter, frame)
    end
    local mission = (okCall and type(contract) == "table") and contract.mission or nil
    local myFarm = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    -- getIsLocalAdmin firlatmaz; bu fonksiyon zaten probeButtonState'in kalkani altinda calisir
    local localAdmin = nil
    if ContractManagerSettingsTab ~= nil and ContractManagerSettingsTab.getIsLocalAdmin ~= nil then
        localAdmin = ContractManagerSettingsTab.getIsLocalAdmin()
    end
    -- cubuga giden girdiler, sirayla; * = bizim
    local list = frame ~= nil and frame.menuButtonInfo or nil
    local slots = ContractManager.getMenuBarSlots()
    return string.format("state=%s getter=%s call=%s contract=%s mission=%s status=%s owner=%s myFarm=%s admin=%s slots=%d entries=%s ours=%d reused=%s bar=[%s]",
        tostring(state), tostring(getter ~= nil), tostring(okCall), type(contract),
        tostring(mission ~= nil), tostring(mission ~= nil and mission.status or nil),
        tostring(mission ~= nil and mission.farmId or nil), tostring(myFarm), tostring(localAdmin),
        slots, tostring(type(list) == "table" and #list or nil),
        ContractManager.countAddedButtons(list), tostring(reused), describeBar(list))
end

function ContractManager.probeButtonState(frame, state, reused)
    if probeCount >= ContractManager.BUTTON_PROBE_MAX then
        return false
    end
    local ok, line = pcall(ContractManager.describeButtonState, frame, state, reused)
    if not ok or probeSeen[line] then
        return false
    end
    probeSeen[line] = true
    probeCount = probeCount + 1
    ContractManager.info("Contracts page buttons: %s", line)
    return true
end

---Menuye "buton listesi degisti" de. Oyunun kendi setButtonsForState'i bunu zaten yapiyor
---olmali (BetterContracts ayni noktaya yalnizca ekleme yapiyor ve butonu gorunuyor); bayrak
---koymak zararsiz oldugu icin guvence olarak birakildi. Bayrak menuyu yeniden kurdurabilirse
---diye kendimizi tekrar cagirmamak icin koruma var.
local markingDirty = false
function ContractManager.markButtonsDirty(frame)
    if frame == nil or markingDirty then
        return false
    end
    markingDirty = true
    local marked = false
    if frame.setMenuButtonInfoDirty ~= nil then
        marked = pcall(frame.setMenuButtonInfoDirty, frame)
    end
    if not marked and g_inGameMenu ~= nil and g_inGameMenu.updateButtonsPanel ~= nil then
        marked = pcall(g_inGameMenu.updateButtonsPanel, g_inGameMenu, frame)
    end
    markingDirty = false
    return marked
end

---Dagitici: onceki eklemelerimizi ayikla, ekleyicileri sirayla calistir, sonucu dogrula.
function ContractManager.runButtonAppenders(frame, state)
    if frame == nil or type(frame.menuButtonInfo) ~= "table" or markingDirty then
        return
    end
    local reused = lastListByFrame[frame] == frame.menuButtonInfo
    lastListByFrame[frame] = frame.menuButtonInfo
    local stripped = ContractManager.stripOwnButtons(frame.menuButtonInfo)
    local stock = {}
    for _, info in ipairs(frame.menuButtonInfo) do
        stock[info] = true
    end
    for _, entry in ipairs(ContractManager.buttonAppenders) do
        local ok, err = pcall(entry.fn, frame)
        if not ok and not buttonErrorsReported[entry.name] then
            buttonErrorsReported[entry.name] = true
            ContractManager.warning("Contracts page button '%s' failed: %s", entry.name, tostring(err))
        end
    end
    ContractManager.sanitizeButtons(frame.menuButtonInfo, stock)
    if stripped > 0 or ContractManager.countAddedButtons(frame.menuButtonInfo) > 0 then
        ContractManager.markButtonsDirty(frame)
    end
    ContractManager.probeButtonState(frame, state, reused)
end

---Oyundaki menu tuslari: kurulumda bir kez loglanir (hangi tus var, cubukta kac yuva). Kurulum
---aninda menu henuz yoksa yuva sayisi varsayilandir ve oyle yazilir; gercek sayi teshis
---satirindaki slots= alanindadir.
function ContractManager.reportMenuKeys()
    if menuKeysReported then
        return false
    end
    menuKeysReported = true
    local parts = {}
    for _, name in ipairs({ "MENU_EXTRA_1", "MENU_EXTRA_2", "MENU_ACTIVATE", "MENU_EXTRA_3" }) do
        parts[#parts + 1] = name .. "=" .. (ContractManager.isMenuActionValid(name) and "ok" or "absent")
    end
    local slots, measured = ContractManager.getMenuBarSlots()
    ContractManager.info("Contracts page keys: %s; bar slots %d%s", table.concat(parts, " "), slots, measured and "" or " (default)")
    return true
end

---Kancayi oyunun sinifina bir kez tak. Donus: kanca yerinde mi.
function ContractManager.installButtonBar()
    local cls = InGameMenuContractsFrame
    if cls == nil or cls.setButtonsForState == nil then
        return false
    end
    cls.cmButtonDispatch = ContractManager.runButtonAppenders
    ContractManager.reportMenuKeys()
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
