--
-- FS25_ContractManager - Kontrat Yoneticisi
--
-- Cati: tum katmanlarin paylastigi sabitler, log ve ortak yardimcilar. modDesc'te ilk yuklenir.
--
-- @author  Dostlar STUDIO
-- @version 1.0.0.0
--

ContractManager = {
    MOD_NAME = g_currentModName,
    MOD_DIRECTORY = g_currentModDirectory,
    VERSION = "1.27.0.0",
    -- Ag olaylarinin bicimi degistiginde ARTTIR. Sunucu ile istemci farkli protokolde ise
    -- sayilar sessizce bozuluyordu (1.14.2 dort tamsayi yaziyordu, 1.15 bes tane okuyordu).
    -- 3 (1.26.0.0): ayar senkronuna 1.24.8.0'da harvest.grassContracts eklenmisti (artirilmamisti);
    -- devir olayina ag kimligi, ortaklik senkronuna paylar eklendi.
    -- 4 (1.27.0.0): ayarlar ekran sirasiyla yayinlanir, duration.autoCloseHours ve tur basina pano siniri
    -- (type max) eklendi; kural durumu (itibar/seri/zincir/NPC) ve sozlesme sartlari olaylari geldi.
    PROTOCOL = 4,
    LOG_PREFIX = "[CM]",

    -- savegame icindeki birlesik durum dosyasi
    SAVEGAME_FILENAME = "FS25_ContractManager.xml",
    BETTER_CONTRACTS_MOD_NAME = "FS25_BetterContracts",

    debugEnabled = false,    -- gelistirmede true: ContractManager.debug satirlari loga yazilir
}

-- ---------------------------------------------------------------------------
-- log
-- ---------------------------------------------------------------------------

-- string.format belirtecleri: sayi bekleyenler; %s / %q metin ya da sayi alir
local NUMERIC_CONVERSIONS = { d = true, i = true, o = true, u = true, x = true, X = true, c = true,
    e = true, E = true, f = true, g = true, G = true }

---string.format, ama ASLA firlatmaz: belirtecler ve argumanlar once denetlenir; uymuyorsa (eksik ya da
---yanlis turde arguman, bilinmeyen belirtec) sablon ve argumanlar yan yana yazilir. %s'e verilen nil/tablo
---tostring ile yazilir. Log satirlari ve ayar etiketleri bununla bicimlenir (pcall gerekmez, 1.26.0.0).
function ContractManager.formatSafe(template, ...)
    template = tostring(template)
    local count = select("#", ...)
    local args = { ... }
    local index, position, valid = 0, 1, true
    while valid do
        local start = string.find(template, "%", position, true)
        if start == nil then
            break
        end
        local flags, width, dot, precision, conversion = string.match(template, "^%%([-+ #0]*)(%d*)(%.?)(%d*)(.?)", start)
        if conversion == "%" and flags == "" and width == "" and dot == "" and precision == "" then
            position = start + 2
        else
            index = index + 1
            local value = args[index]
            if index > count or #flags > 5 or #width > 2 or #precision > 2 then
                valid = false
            elseif NUMERIC_CONVERSIONS[conversion] then
                valid = tonumber(value) ~= nil
            elseif conversion == "s" or conversion == "q" then
                if type(value) ~= "string" and type(value) ~= "number" then
                    args[index] = tostring(value)
                end
            else
                valid = false
            end
            position = start + 2 + #flags + #width + #dot + #precision
        end
    end
    if valid then
        return string.format(template, unpack(args, 1, count))
    end
    local parts = { template }
    for i = 1, count do
        parts[#parts + 1] = tostring(args[i])
    end
    return table.concat(parts, " ")
end

local formatLine = ContractManager.formatSafe

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

---Para metni oyunun biriminde ve dilinde. Tek yer: bes dosyada ayni satirlar tekrar ediyordu (1.26.0.0).
function ContractManager.formatMoney(value)
    value = tonumber(value) or 0
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        local s = g_i18n:formatMoney(value, 0, true, true)
        if s ~= nil then
            return s
        end
    end
    return tostring(math.floor(value + 0.5))
end

---Acik Kontrat Yonetimi sayfasini tazele (kapaliysa bir sey yapmaz). Sunucudan gelen ya da baska oyuncunun
---yaptigi degisikliklerde cagrilir; oynayan host kendi yayinini almadigi icin yayin noktasinda da cagrilir.
function ContractManager.refreshManagePage()
    if ContractManagerManagePage ~= nil and ContractManagerManagePage.onRemoteChange ~= nil then
        ContractManagerManagePage.onRemoteChange()
    end
end

---Kontrat turunun okunur adi. Oyun turleri ham adla kaydeder (missionType.name = "plowMission"); ayar ekrani,
---gecmis ve siralama bunu oldugu gibi yaziyordu, cm_type_* anahtari hic yoktu (1.26.0.0). Ceviri yoksa
---(baska modun turu) ad sadelestirilir: "destructibleRockMission" -> "Destructible rock".
function ContractManager.typeTitle(name)
    if name == nil or name == "" then
        return "?"
    end
    name = tostring(name)
    local plain = name:gsub("Mission$", ""):gsub("(%l)(%u)", "%1 %2"):lower()
    plain = (plain:gsub("^%l", string.upper))
    return ContractManager.text("cm_type_" .. name, plain ~= "" and plain or name)
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
-- Tek hata siniri (1.26.0.0)
--
-- Oyunun bizi cagirdigi noktalarda (kancalar, olaylar, baska modlarin fonksiyonlari) modun bir
-- hatasi oyunun kendi akisini yarida kesmesin diye kullanilir. Hata YUTULMAZ: etiket basina ilk
-- GUARD_LOG_MAX hata loglanir (her karede calisan kancalarda log tasmasin). Donus pcall gibidir:
-- true + fn'in donusleri ya da false + hata. Firlatmayan oyun fonksiyonlari bununla SARILMAZ.
-- ---------------------------------------------------------------------------
ContractManager.GUARD_LOG_MAX = 3
ContractManager.guardErrors = {}

local function guardResult(label, ok, ...)
    if not ok and label ~= nil then
        local key = tostring(label)
        local count = (ContractManager.guardErrors[key] or 0) + 1
        ContractManager.guardErrors[key] = count
        if count <= ContractManager.GUARD_LOG_MAX then
            ContractManager.warning("%s failed: %s%s", key, tostring((...)),
                count == ContractManager.GUARD_LOG_MAX and " (further errors of this kind are not logged)" or "")
        end
    end
    return ok, ...
end

function ContractManager.guard(label, fn, ...)
    return guardResult(label, pcall(fn, ...))
end

---Hatayi CAGIRAN raporlar (kendi teshis satirini yazar, ornek: Safety kalkani): guard gibi, ama loglamaz.
function ContractManager.attempt(fn, ...)
    return ContractManager.guard(nil, fn, ...)
end

---Istemci: olayi sunucuya gonder. Baglanti yoksa (ana menuye donus sirasinda) false. Alti yerde ayni
---korumali "g_client:getServerConnection():sendEvent(...)" kalibi vardi (1.26.0.0).
function ContractManager.sendToServer(event)
    local connection = g_client ~= nil and g_client.getServerConnection ~= nil and g_client:getServerConnection() or nil
    if connection == nil or event == nil then
        return false
    end
    return (ContractManager.guard("Send to server", connection.sendEvent, connection, event))
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
    local id = NetworkUtil.getObjectId(mission)
    return type(id) == "number" and id or 0
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
        local mission = NetworkUtil.getObject(objectId)
        if type(mission) == "table" then
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
    local mission = NetworkUtil.getObject(objectId)
    if type(mission) == "table" then
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
--     cagrida ayni nesneyi ekliyor ve birikmiyor).
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

---Girdi bizim mi (addMenuButton/replaceMenuButton ile konmus ya da dogrulamadan gecmis)?
function ContractManager.isOwnMenuButton(info)
    return info ~= nil and ownButtons[info] == true
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

---Menuye "buton listesi degisti" de. Oyunun kendi setButtonsForState'i bunu zaten yapiyor
---olmali (BetterContracts ayni noktaya yalnizca ekleme yapiyor ve butonu gorunuyor); bayrak
---koymak zararsiz oldugu icin guvence olarak birakildi. Bayrak menuyu yeniden kurdurabilirse
---diye kendimizi tekrar cagirmamak icin koruma var.
local markingDirty = false
function ContractManager.markButtonsDirty(frame)
    if frame == nil or markingDirty or frame.setMenuButtonInfoDirty == nil then
        return false
    end
    markingDirty = true
    local marked = ContractManager.guard("Contracts page buttons", frame.setMenuButtonInfoDirty, frame)
    markingDirty = false
    return marked
end

---Dagitici: onceki eklemelerimizi ayikla, ekleyicileri sirayla calistir, sonucu dogrula.
function ContractManager.runButtonAppenders(frame, state)
    if frame == nil or type(frame.menuButtonInfo) ~= "table" or markingDirty then
        return
    end
    local stripped = ContractManager.stripOwnButtons(frame.menuButtonInfo)
    local stock = {}
    for _, info in ipairs(frame.menuButtonInfo) do
        stock[info] = true
    end
    for _, entry in ipairs(ContractManager.buttonAppenders) do
        -- bir ekleyicinin hatasi digerlerini ve oyunun cubugunu durdurmaz; loga yazilir (etiket basina sinirli)
        ContractManager.guard("Contracts page button '" .. tostring(entry.name) .. "'", entry.fn, frame)
    end
    ContractManager.sanitizeButtons(frame.menuButtonInfo, stock)
    if stripped > 0 or ContractManager.countAddedButtons(frame.menuButtonInfo) > 0 then
        ContractManager.markButtonsDirty(frame)
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
            ContractManager.guard("Contracts page buttons", dispatch, frame, state)
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
        return g_inputBinding:getShowMouseCursor() == true
    end
    return false
end

function ContractManager.setCursor(visible)
    if g_inputBinding ~= nil and g_inputBinding.setShowMouseCursor ~= nil then
        g_inputBinding:setShowMouseCursor(visible == true)
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
---Cok oyunculu oturum mu? (1.25.0.0) Tek oyunculuda yalnizca bir ciftlik vardir: ortaklik,
---rezervasyon ve ciftlikler arasi devir anlamsizdir, otomatik kapanir. Oyun bilgisi henuz yoksa
---(erken yukleme, test) kisitlama yapilmaz. Dedicated sunucu ve istemciler cok oyunculudur.
function ContractManager.isMultiplayer()
    local mission = g_currentMission
    local info = mission ~= nil and mission.missionDynamicInfo or nil
    if type(info) ~= "table" or info.isMultiplayer == nil then
        return true
    end
    return info.isMultiplayer == true
end

---Odul/prim gosteriminde kontratin ciftligi: kabul edilmis kontratta kontratin ciftligi; kabul edilmemiste
---istemcide oyuncunun kendi ciftligi (panodaki kontrati o ciftlik icin gosterir), sunucuda nil (odeme kabulden
---sonra hesaplanir). Alti dosyada alti ayri bicimde yaziliydi (1.27.0.0).
function ContractManager.getDisplayFarmId(mission)
    local farmId = mission ~= nil and mission.farmId or nil
    if farmId ~= nil and farmId ~= 0 then
        return farmId
    end
    local current = g_currentMission
    if current ~= nil and not current:getIsServer() and current.getFarmId ~= nil then
        return current:getFarmId()
    end
    return nil
end

---Bu bilgisayardaki oyuncu kural ayarlarini degistirebilir ve yonetici araclarini gorebilir mi? (sunucu/host ya da
---yonetici girisi yapmis oyuncu). Ayar sekmesi, stok sayfadaki yonetici butonlari ve Yonetim sayfasi ayni karari
---verir; 1.27.0.0'a kadar bu karar ayar sekmesinin (GUI) dosyasindaydi.
function ContractManager.isLocalAdmin()
    local mission = g_currentMission
    if mission == nil then
        return false
    end
    if mission:getIsServer() then
        return true
    end
    if g_inGameMenu ~= nil and (g_inGameMenu.isServer or g_inGameMenu.isMasterUser) then
        return true
    end
    return mission.isMasterUser == true
end

function ContractManager:getRulesEnabled()
    if not self:isBetterContractsLoaded() then
        return true
    end
    if ContractManagerSettings ~= nil and ContractManagerSettings.get ~= nil then
        return ContractManagerSettings:get("compat.overrideBetterContracts") == true
    end
    return false
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
ContractManager.MESSAGE_CONTRACT_AUTO_CLOSED = "CONTRACT_MANAGER_CONTRACT_AUTO_CLOSED" -- (mission, amount)

function ContractManager.publish(message, ...)
    if g_messageCenter ~= nil and g_messageCenter.publish ~= nil and message ~= nil then
        g_messageCenter:publish(message, ...)
    end
end

ContractManager.info("v%s loading", ContractManager.VERSION)
