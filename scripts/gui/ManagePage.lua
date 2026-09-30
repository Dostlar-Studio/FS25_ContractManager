--
-- FS25_ContractManager - "Kontrat Yonetimi" ESC sayfasi
--
-- Konsol komutlarinin arayuz karsiligi. Uc filtre (Aktif / Yeni / Gecmis), altinda secili
-- kontratin detayi ve eylem butonlari: rezerve et/birak, ortak davet et, ortakligi kabul et/
-- ayril, devret, zorla iptal, ata, panoyu yenile. Hedef ciftlik bir dugmeyle sirayla secilir
-- (stok secim diyalogunun API'si yayinlanmadigi icin diyalog kullanilmaz).
--
-- Arayuz gui/ManagePage.xml'den stok profillerle yuklenir; sayfa kaydi FS25_SellingAdmin'de
-- dogrulanmis yordamla yapilir: pagingElement'e CONTROLLER eklenir, registerPage + addPageTab +
-- rebuildTabList, sonra dogrulama; tutmazsa geri alinir (TabbedMenu:addPage ESC menusunu cokertir).
--
-- Saf mantik (satir metinleri, eylem listesi, ciftlik dongusu) harness'ta test edilir;
-- GUI kurulumu tamamen pcall ile korunur.
--

ContractManagerManagePage = {}
local ContractManagerManagePage_mt = Class(ContractManagerManagePage, TabbedMenuFrameElement)

ContractManagerManagePage.PAGE_NAME = "contractManagerPage"
-- loadGui'nin ikinci parametresi; oyun sayfayi bu adla EKRAN olarak da kaydeder (bkz. unregisterScreen)
ContractManagerManagePage.SCREEN_NAME = "ContractManagerManagePage"
ContractManagerManagePage.FILTER_ACTIVE = 1
ContractManagerManagePage.FILTER_NEW = 2
ContractManagerManagePage.FILTER_HISTORY = 3
ContractManagerManagePage.SLICE_PREFIX = "contractManager"
ContractManagerManagePage.TAB_SLICE = "contractManager.pageTab"
-- Kaydirma cubugu zaten var; 12 satir panonun yarisini bile gostermiyordu
-- (sunucu ayari generation.maxTotal 50'ye kadar cikabiliyor).
ContractManagerManagePage.MAX_ROWS = 20
ContractManagerManagePage.MAX_DETAIL = 6
ContractManagerManagePage.MAX_PARTNER = 6

---Geri alinamayan ya da baskasini etkileyen eylemler once ONAY ister:
---butona basmak eylemi "kurar", ikinci basis calistirir. Modal diyalog
---kullanilmadi: FS25'in diyalog yardimcilari yayinlanmis kaynakta yok, dogrulanmamis
---API ile para paylasan bir islem tetiklenmez.
ContractManagerManagePage.CONFIRM_ACTIONS = {
    invite = true, transfer = true, cancel = true, assign = true,
    refresh = true, partnerLeave = true, partnerDecline = true,
}

local Page = ContractManagerManagePage

-- ---------------------------------------------------------------------------
-- saf yardimcilar (test edilir)
-- ---------------------------------------------------------------------------

-- Metin yardimcisi tek yerde: ContractManager.text (Main.lua). Main once yuklenir.
local function text(key, fallback)
    return ContractManager.text(key, fallback)
end

Page.text = text

function Page.farmName(farmId)
    if farmId == nil or farmId == 0 then
        return "-"
    end
    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if farm ~= nil and farm.name ~= nil then
            return tostring(farm.name)
        end
    end
    return "Farm " .. tostring(farmId)
end

function Page.needsConfirm(action)
    return Page.CONFIRM_ACTIONS[action] == true
end

---onay sorusu (saf). Hedef ciftlik gerektiren eylemlerde ciftlik adi yazilir.
---`missionTitle` verilirse soru hedefi adiyla yazar: hedefin kaymasi kullaniciya gorunur olsun.
function Page.confirmQuestion(action, targetFarmName, missionTitle)
    if missionTitle ~= nil and missionTitle ~= "" then
        return string.format("%s  (%s)",
            Page.confirmQuestion(action, targetFarmName), tostring(missionTitle))
    end
    if action == "invite" then
        return string.format(text("cm_pageConfirmInvite", "Send invite to %s?"), tostring(targetFarmName))
    end
    if action == "transfer" or action == "assign" then
        return string.format(text("cm_pageConfirmFarm", "Confirm for %s?"), tostring(targetFarmName))
    end
    return string.format(text("cm_pageConfirmGeneric", "Confirm: %s?"),
        text(Page.ACTION_TEXT[action] or action))
end

---ortak kontratin ciftlik basina satirlari (saf). Odul disaridan verilir.
---Her ciftlik kendi kontrati gibi gorunur: rol, katki, pay ve hak edis.
function Page.buildPartnerLines(mission, reward)
    local Part = ContractManagerPartnership
    if Part == nil or mission == nil or Part.get(mission) == nil then
        return {}
    end
    local lines = {}
    local measured = Part.hasContribution(mission)
    for _, p in ipairs(Part.getParticipants(mission, reward)) do
        if #lines >= Page.MAX_PARTNER then break end
        local role = text(p.isOwner and "cm_pageOwner" or "cm_pagePartner", p.isOwner and "owner" or "partner")
        if measured then
            lines[#lines + 1] = string.format("%s (%s) · %d%% · %s · %s",
                Page.farmName(p.farmId), role,
                math.floor(p.share * 100 + 0.5),
                Page.formatLiters(p.liters),
                Page.money(p.payout))
        else
            lines[#lines + 1] = string.format("%s (%s) · %s · %s",
                Page.farmName(p.farmId), role,
                text("cm_pageEqualSplit", "equal split"),
                Page.money(p.payout))
        end
    end
    for _, invite in ipairs(Part.getPendingInfo(mission)) do
        if #lines >= Page.MAX_PARTNER then break end
        lines[#lines + 1] = string.format(text("cm_pagePendingInvite", "Invite pending: %s (%d min)"),
            Page.farmName(invite.farmId), invite.minutesLeft)
    end
    return lines
end

---bolum basligi; sayac yalnizca anlamli oldugunda eklenir (saf)
function Page.sectionTitle(key, count)
    local title = text(key)
    if count ~= nil and count > 0 then
        return string.format("%s (%d)", title, count)
    end
    return title
end

---secicideki metinler (saf): ciftlik adlari
function Page.farmOptionTexts(ids)
    local texts = {}
    for index, id in ipairs(ids) do
        texts[index] = Page.farmName(id)
    end
    return texts
end

---verilen ciftligin secicideki sirasi; yoksa 1 (saf)
function Page.farmOptionIndex(ids, farmId)
    for index, id in ipairs(ids) do
        if id == farmId then
            return index
        end
    end
    return 1
end

---secilebilir ciftlikler (kendi ciftligi haric)
function Page.getFarmIds(excludeFarmId)
    local ids = {}
    if g_farmManager ~= nil and g_farmManager.getFarms ~= nil then
        local farms = g_farmManager:getFarms()
        if type(farms) == "table" then
            for _, farm in pairs(farms) do
                local id = type(farm) == "table" and farm.farmId or nil
                if type(id) == "number" and id > 0 and id ~= excludeFarmId then
                    ids[#ids + 1] = id
                end
            end
        end
    end
    if #ids == 0 and g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        for id = 1, 8 do
            if id ~= excludeFarmId and g_farmManager:getFarmById(id) ~= nil then
                ids[#ids + 1] = id
            end
        end
    end
    table.sort(ids)
    return ids
end

local function minutesText(mission)
    if mission == nil or mission.getMinutesLeft == nil then
        return nil
    end
    local ok, minutes = pcall(mission.getMinutesLeft, mission)
    if not ok or type(minutes) ~= "number" then
        return nil
    end
    if ContractManagerContractDetails ~= nil then
        return ContractManagerContractDetails.formatMinutes(minutes)
    end
    return string.format("%d", math.floor(minutes))
end

local function money(value)
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        local s = g_i18n:formatMoney(value or 0, 0, true, true)
        if s ~= nil then
            return s
        end
    end
    return tostring(math.floor((value or 0) + 0.5))
end

Page.money = money

---katki litresi (saf); 1000 ustu k ile kisaltilir ki satir tasmasin
function Page.formatLiters(liters)
    liters = math.floor((liters or 0) + 0.5)
    if liters >= 1000 then
        return string.format("%.1fk l", liters / 1000)
    end
    return string.format("%d l", liters)
end

---kontratin oduru; motor cagrisi korumali (saf mantik disi tek yer)
function Page.missionReward(mission)
    if mission == nil or mission.getReward == nil then
        return 0
    end
    local value = mission:getReward()
    return type(value) == "number" and value or 0
end

---kontrat satiri metni (saf)
function Page.formatMission(mission)
    if mission == nil then
        return "-"
    end
    local parts = {}
    parts[#parts + 1] = tostring(mission.title or (mission.type ~= nil and mission.type.name) or "?")
    local fieldId = nil
    if mission.field ~= nil and mission.field.getId ~= nil then
        fieldId = mission.field:getId()
    end
    if fieldId ~= nil and fieldId ~= 0 then
        parts[#parts + 1] = string.format("%s %s", text("cm_pageField", "Field"), tostring(fieldId))
    end
    if mission.farmId ~= nil and mission.farmId ~= 0 then
        parts[#parts + 1] = Page.farmName(mission.farmId)
    end
    if type(mission.completion) == "number" and mission.status == MissionStatus.RUNNING then
        parts[#parts + 1] = string.format("%%%d", math.floor(mission.completion * 100 + 0.5))
    end
    local reward = 0
    if mission.getReward ~= nil then
        local value = mission:getReward()
        if type(value) == "number" then reward = value end
    end
    parts[#parts + 1] = money(reward)
    local left = minutesText(mission)
    if left ~= nil and mission.status ~= MissionStatus.CREATED then
        parts[#parts + 1] = left
    end
    return table.concat(parts, " · ")
end

---gecmis satiri metni (saf)
-- Bitis durumu anahtari tek kaynaktan: SettingsTab.finishStateKey (oyunun MissionFinishState adlarindan kurulur)
function Page.formatHistory(entry)
    if entry == nil then
        return "-"
    end
    return string.format("%s %s · %s · %s · %s",
        text("cm_day", "Day"), tostring(entry.finishedDay or 0),
        text("cm_type_" .. tostring(entry.typeName), tostring(entry.typeName)),
        text(ContractManagerSettingsTab.finishStateKey(entry.finishState), "-"),
        money(entry.payout or entry.reward or 0))
end

-- ---------------------------------------------------------------------------
-- Sutunlar (1.23.0.0)
--
-- Eskiden satir tek uzun metindi: "Hasat · Tarla 12 · ARSLAN · %35 · 18.160 € · 42 dk".
-- Goz her satirda ayni bilgiyi farkli yerde ariyordu. Artik oyunun kendi liste
-- sayfalari gibi sabit sutunlar var; sayisal sutunlar saga dayali oldugu icin
-- rakamlar alt alta hizalaniyor. Hucre metinleri SAF uretilir (test edilir),
-- yerlesim profillerden gelir (gui/guiProfiles.xml cm_cell*).
-- ---------------------------------------------------------------------------

Page.CELL_NAMES = { "cellName", "cellFarm", "cellProgress", "cellReward", "cellTime" }

---Sutun basliklari (saf)
function Page.columnTitles()
    return {
        cellName = text("cm_colContract", "Contract"),
        cellFarm = text("cm_colFarm", "Farm"),
        cellProgress = text("cm_colProgress", "%"),
        cellReward = text("cm_colReward", "Reward"),
        cellTime = text("cm_colTime", "Time"),
    }
end

---Kontrat satirinin hucreleri (saf). Bos sutun "" doner, nil donmez.
function Page.missionCells(mission)
    local cells = { cellName = "-", cellFarm = "", cellProgress = "", cellReward = "", cellTime = "" }
    if mission == nil then
        return cells
    end
    local title = tostring(mission.title or (mission.type ~= nil and mission.type.name) or "?")
    local fieldId = nil
    if mission.field ~= nil and mission.field.getId ~= nil then
        fieldId = mission.field:getId()
    end
    if fieldId ~= nil and fieldId ~= 0 then
        title = string.format("%s · %s %s", title, text("cm_pageField", "Field"), tostring(fieldId))
    end
    cells.cellName = title
    if mission.farmId ~= nil and mission.farmId ~= 0 then
        cells.cellFarm = Page.farmName(mission.farmId)
    end
    if type(mission.completion) == "number" and mission.status == MissionStatus.RUNNING then
        cells.cellProgress = string.format("%%%d", math.floor(mission.completion * 100 + 0.5))
    end
    cells.cellReward = money(Page.missionReward(mission))
    local left = minutesText(mission)
    if left ~= nil and mission.status ~= MissionStatus.CREATED then
        cells.cellTime = left
    end
    return cells
end

---Gecmis satirinin hucreleri (saf). Durum sutunu ciftlik sutununda durur:
---gecmiste "kimin" degil "nasil bitti" onemli.
function Page.historyCells(entry)
    local cells = { cellName = "-", cellFarm = "", cellProgress = "", cellReward = "", cellTime = "" }
    if entry == nil then
        return cells
    end
    cells.cellName = text("cm_type_" .. tostring(entry.typeName), tostring(entry.typeName))
    cells.cellFarm = text(ContractManagerSettingsTab.finishStateKey(entry.finishState), "-")
    cells.cellReward = money(entry.payout or entry.reward or 0)
    cells.cellTime = string.format("%s %s", text("cm_day", "Day"), tostring(entry.finishedDay or 0))
    return cells
end

---Gecmis satirinin durum rengi (saf). Donus: r, g, b, a ya da nil (varsayilan renk).
---Oyunun paletinden: basarili yesil, basarisiz/sure asimi kirmizi, iptal gri.
function Page.historyStateColor(finishState)
    local Tab = ContractManagerSettingsTab
    local key = Tab ~= nil and Tab.finishStateKey(finishState) or nil
    if key == "cm_stateSuccess" then
        return 0.45, 0.72, 0.16, 1
    elseif key == "cm_stateFailed" or key == "cm_stateTimedOut" then
        return 0.84, 0.24, 0.24, 1
    elseif key == "cm_stateCanceled" then
        return 0.72, 0.72, 0.72, 1
    end
    return nil
end

---Detay satiri: solda etiket, sagda deger (saf). "Kalan: 42 dk" -> iki sutun.
function Page.splitDetailLine(line)
    if type(line) ~= "string" then
        return "", ""
    end
    local label, value = line:match("^(.-):%s(.*)$")
    if label == nil then
        return line, ""
    end
    return label, value
end

-- ---------------------------------------------------------------------------
-- Siralama (1.24.0.0)
--
-- Eskiden liste MOTOR SIRASINDAN ilk 12 kontrati alip kesiyordu: sunucuda pano 50
-- kontrata kadar cikabildigi icin oyuncu geri kalanini HIC goremiyordu ve en acil ya
-- da en yuksek odullu kontrat listede olmayabiliyordu. Artik once tumu siralanir,
-- sonra ilk MAX_ROWS gosterilir; baslikta "gosterilen/toplam" yazar.
-- ---------------------------------------------------------------------------

Page.SORT_SMART = 1     -- aktif: en acil once, yeni: en yuksek odul once, gecmis: en yeni once
Page.SORT_REWARD = 2
Page.SORT_TIME = 3
Page.SORT_FARM = 4
Page.SORT_KEYS = { "cm_sortSmart", "cm_sortReward", "cm_sortTime", "cm_sortFarm" }

function Page.sortModeTexts()
    local texts = {}
    for index, key in ipairs(Page.SORT_KEYS) do
        texts[index] = text(key, key)
    end
    return texts
end

---Siralama anahtarlari (saf). Donus: odul, kalan dakika, ciftlik adi, ad
local function sortKeys(row)
    local mission, entry = row.mission, row.entry
    if entry ~= nil then
        return entry.payout or entry.reward or 0, -(entry.finishedDay or 0),
            Page.farmName(entry.farmId), tostring(entry.typeName or "")
    end
    local minutes = math.huge
    if mission ~= nil and mission.getMinutesLeft ~= nil then
        local ok, value = pcall(mission.getMinutesLeft, mission)
        if ok and type(value) == "number" then
            minutes = value
        end
    end
    return Page.missionReward(mission), minutes,
        mission ~= nil and Page.farmName(mission.farmId) or "",
        mission ~= nil and tostring(mission.title or "") or ""
end

---Satirlari yerinde sirala (saf). `mode` nil ise akilli siralama.
---Esitlikte ad kullanilir: sira tazelemeler arasinda oynamasin.
function Page.sortRows(rows, mode, filter)
    mode = mode or Page.SORT_SMART
    local cache = {}
    for _, row in ipairs(rows) do
        local reward, minutes, farm, name = sortKeys(row)
        cache[row] = { reward = reward, minutes = minutes, farm = farm, name = name }
    end
    local function before(a, b)
        local ka, kb = cache[a], cache[b]
        if mode == Page.SORT_REWARD then
            if ka.reward ~= kb.reward then return ka.reward > kb.reward end
        elseif mode == Page.SORT_TIME then
            if ka.minutes ~= kb.minutes then return ka.minutes < kb.minutes end
        elseif mode == Page.SORT_FARM then
            if ka.farm ~= kb.farm then return ka.farm < kb.farm end
        else
            -- akilli: aktif kontratta sure baskin (en acil once), digerlerinde odul
            if filter == Page.FILTER_ACTIVE then
                if ka.minutes ~= kb.minutes then return ka.minutes < kb.minutes end
            end
            if ka.reward ~= kb.reward then return ka.reward > kb.reward end
        end
        return ka.name < kb.name
    end
    table.sort(rows, before)
    return rows
end

---filtreye gore satirlar (saf). Donus: gosterilecek satirlar, TOPLAM eslesen sayi.
---Kesme siralamadan SONRA yapilir; yoksa "en acil" kontrat listeye hic girmeyebilir.
function Page.buildRows(filter, farmId, isAdmin, sortMode)
    local rows = {}
    local missions = g_missionManager ~= nil and g_missionManager.missions or {}
    if filter == Page.FILTER_HISTORY then
        local registry = ContractManagerRegistry
        if registry ~= nil then
            -- Lua tuzagi: "isAdmin and nil or farmId" her zaman farmId doner
            local historyFarm = farmId
            if isAdmin then
                historyFarm = nil
            end
            for _, entry in ipairs(registry:getHistory(historyFarm)) do
                rows[#rows + 1] = { kind = "history", entry = entry, label = Page.formatHistory(entry) }
            end
        end
    else
        for _, mission in ipairs(missions) do
            local isNew = mission.status == MissionStatus.CREATED
            local isActive = mission.status == MissionStatus.RUNNING or mission.status == MissionStatus.PREPARING
            local wanted = (filter == Page.FILTER_NEW and isNew) or (filter == Page.FILTER_ACTIVE and isActive)
            if wanted and (isAdmin or filter == Page.FILTER_NEW or mission.farmId == farmId
                or (ContractManagerPartnership ~= nil and ContractManagerPartnership.isMember(mission, farmId))) then
                rows[#rows + 1] = { kind = "mission", mission = mission, label = Page.formatMission(mission) }
            end
        end
    end
    local total = #rows
    -- Gecmis zaten en yeniden eskiye geliyor; akilli sirada o sira korunur.
    if not (filter == Page.FILTER_HISTORY and (sortMode == nil or sortMode == Page.SORT_SMART)) then
        Page.sortRows(rows, sortMode, filter)
    end
    while #rows > Page.MAX_ROWS do
        table.remove(rows)
    end
    return rows, total
end

---Bolum basligi: kesilmisse "gosterilen/toplam" (saf)
function Page.listTitle(shown, total)
    local title = text("cm_pageContracts")
    if total == nil or total == 0 then
        return title
    end
    if total > shown then
        return string.format("%s (%d/%d)", title, shown, total)
    end
    return string.format("%s (%d)", title, total)
end

---secili kontrat icin acik eylemler (saf). Donus: sirali id listesi
function Page.getActions(mission, farmId, isAdmin, targetFarmId)
    local actions = {}
    if mission == nil then
        if isAdmin then
            actions[#actions + 1] = "refresh"
        end
        return actions
    end
    local isNew = mission.status == MissionStatus.CREATED
    local isActive = mission.status == MissionStatus.RUNNING or mission.status == MissionStatus.PREPARING
    local isOwner = mission.farmId == farmId
    local Res = ContractManagerReservation
    local Part = ContractManagerPartnership

    if isNew then
        if Res ~= nil and Res.isEnabled() then
            local r = Res.get(ContractManager.getMissionKey(mission))
            if r ~= nil and r.farmId == farmId then
                actions[#actions + 1] = "release"
            elseif r == nil then
                actions[#actions + 1] = "reserve"
            end
        end
        if isAdmin and targetFarmId ~= nil then
            actions[#actions + 1] = "assign"
        end
    elseif isActive then
        if Part ~= nil and Part.isEnabled() then
            if isOwner and targetFarmId ~= nil then
                actions[#actions + 1] = "invite"
            end
            if Part.isPartner(mission, farmId) then
                actions[#actions + 1] = "partnerLeave"
            elseif Part.hasPendingInvite(mission, farmId) then
                actions[#actions + 1] = "partnerAccept"
                actions[#actions + 1] = "partnerDecline"
            end
        end
        if isAdmin then
            actions[#actions + 1] = "cancel"
            -- "devret" 2026-09-10'da arayuzden askiya alinmisti, gerekce "konsol komutu duruyor"du.
            -- 1.14.2.0 konsolu kapatti ve devret yalnizca web panelinden yapilabilir hale geldi;
            -- buton geri acildi (2026-09-13).
            actions[#actions + 1] = "transfer"
        end
    end
    if isAdmin then
        actions[#actions + 1] = "refresh"
    end
    return actions
end

Page.ACTION_TEXT = {
    reserve = "cm_resReserveButton", release = "cm_resReleaseButton",
    invite = "cm_pageInvite", partnerAccept = "cm_partAcceptButton", partnerLeave = "cm_partLeaveButton",
    transfer = "cm_pageTransfer", cancel = "cm_adminCancelButton", assign = "cm_pageAssign",
    refresh = "cm_adminRefreshButton", partnerDecline = "cm_pageDecline",
}

---secili kontratin detay satirlari (saf)
function Page.buildDetailLines(mission, entry)
    local lines = {}
    if entry ~= nil then
        lines[#lines + 1] = Page.formatHistory(entry)
        lines[#lines + 1] = string.format("%s: %s", text("cm_detailPartner", "Farm"), Page.farmName(entry.farmId))
        return lines
    end
    if mission == nil then
        lines[#lines + 1] = text("cm_pageSelectHint", "-")
        return lines
    end
    lines[#lines + 1] = Page.formatMission(mission)
    if mission.getDetails ~= nil then
        local ok, details = pcall(mission.getDetails, mission)
        if ok and type(details) == "table" then
            for _, row in ipairs(details) do
                if #lines >= Page.MAX_DETAIL then break end
                lines[#lines + 1] = string.format("%s: %s", tostring(row.title), tostring(row.value))
            end
        end
    end
    return lines
end

-- ---------------------------------------------------------------------------
-- sayfa nesnesi
-- ---------------------------------------------------------------------------

function Page.new(target, customMt)
    local self = TabbedMenuFrameElement.new(target, customMt or ContractManagerManagePage_mt)
    self.filter = Page.FILTER_ACTIVE
    self.sortMode = Page.SORT_SMART
    self.selectedIndex = 0
    self.targetFarmId = nil
    self.pendingAction = nil   -- onay bekleyen eylem (bkz. CONFIRM_ACTIONS)
    self.rowElements = {}
    self.detailElements = {}
    self.partnerElements = {}
    self.actionElements = {}
    self.rows = {}
    return self
end

function Page:onClickFilterActive() self:setFilter(Page.FILTER_ACTIVE) end
function Page:onClickFilterNew() self:setFilter(Page.FILTER_NEW) end
function Page:onClickFilterHistory() self:setFilter(Page.FILTER_HISTORY) end

function Page:setFilter(filter)
    self.filter = filter
    self.selectedIndex = 0
    self.pendingAction = nil
    self:refresh()
end

function Page:getLocalFarmId()
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        return g_currentMission:getFarmId()
    end
    return nil
end

function Page:getIsAdmin()
    return ContractManagerSettingsTab ~= nil and ContractManagerSettingsTab.getIsLocalAdmin() or false
end

function Page:getSelected()
    return self.rows[self.selectedIndex]
end

---Kontrat hala panoda mi? Secim SIRA NUMARASINA bagli ve liste her `refresh`'te yeniden
---kuruluyor; onay beklerken araya giren bir degisiklik ayni indeksi BASKA kontrata
---kaydiriyordu ve "Zorla iptal" yanlis kontrata gidebiliyordu (2026-09-13 denetimi).
function Page.missionStillListed(mission)
    if mission == nil then
        return false
    end
    for _, m in ipairs(g_missionManager ~= nil and g_missionManager.missions or {}) do
        if m == mission then
            return true
        end
    end
    return false
end

---Onay basladiginda hedefi sabitle.
function Page:pinTarget()
    local row = self:getSelected()
    self.pendingMission = row ~= nil and row.mission or nil
    return self.pendingMission
end

---Calistirma aninda hedefi al. Donus: kontrat, "kayboldu mu".
function Page:takeTarget()
    local pinned = self.pendingMission
    self.pendingMission = nil
    if pinned == nil then
        local row = self:getSelected()
        return row ~= nil and row.mission or nil, false
    end
    if not Page.missionStillListed(pinned) then
        return nil, true
    end
    return pinned, false
end

function Page:onClickRow(index)
    self.selectedIndex = (self.selectedIndex == index) and 0 or index
    self.pendingAction = nil
    self.pendingMission = nil
    self:refresh()
end

---Secicide baska ciftlige gecildi. (Eski "tiklayinca sirayla degistir" davranisi
---kaldirildi; kullanici oyunun kendi ok tuslu secicisini istedi.)
function Page:onSortChanged()
    local option = self.sortRow ~= nil and self.sortRow.cmOption or nil
    if option == nil or option.getState == nil then
        return
    end
    local mode = option:getState()
    if mode == self.sortMode then
        return
    end
    self.sortMode = mode
    self.selectedIndex = 0   -- sira degisti, eski indeks baska kontrati gosterirdi
    self:refresh()
end

function Page:onFarmOptionChanged()
    local option = self.farmOption ~= nil and self.farmOption.cmOption or nil
    if option == nil or option.getState == nil then
        return
    end
    local ids = Page.getFarmIds(self:getLocalFarmId())
    local id = ids[option:getState()]
    if id == nil or id == self.targetFarmId then
        return
    end
    self.targetFarmId = id
    self.pendingAction = nil   -- hedef degisti, kurulu onay artik baska ciftlige aitti
    self:refresh()
end

---Oyunun kendi Evet/Hayir penceresi. Yayinlanmis kaynakta govdesi yok, bu yuzden
---varligi ve cagrisi korumali: acilamazsa satir ici iki adimli onaya duseriz.
function Page:showConfirmDialog(action)
    if YesNoDialog == nil or YesNoDialog.show == nil then
        return false
    end
    local pinned = self.pendingMission
    local question = Page.confirmQuestion(action, Page.farmName(self.targetFarmId),
        pinned ~= nil and pinned.title or nil)
    local title = text("cm_tabTitle", "Contract Manager")
    local ok = pcall(YesNoDialog.show, self.onConfirmDialog, self, question, title,
        text("cm_pageConfirmButton", "Confirm"), text("cm_pageDialogNo", "Cancel"))
    if not ok then
        return false
    end
    self.dialogAction = action
    return true
end

---Pencere yaniti. Imza dogrulanamadigi icin hangi argumanin boolean oldugunu aramak
---zorundayiz; yanlis okuma para paylastiran bir eylemi tetiklerdi.
function Page:onConfirmDialog(a, b)
    local yes = ContractManager.dialogAnswer(a, b)
    local action = self.dialogAction
    self.dialogAction = nil
    if yes ~= true or action == nil then
        self:refresh()
        return
    end
    self:runAction(action)
end

---Butona basildi. Geri alinamayan eylemlerde once onay: oyunun penceresi acilir,
---acilamazsa satir soruya doner ve ikinci basis calistirir.
function Page:onClickAction(action)
    if action == nil then
        return
    end
    if Page.needsConfirm(action) and self.pendingAction ~= action then
        self:pinTarget()
        if self:showConfirmDialog(action) then
            return
        end
        self.pendingAction = action   -- pencere yoksa: satir soruya doner
        self:refresh()
        return
    end
    self.pendingAction = nil
    self:runAction(action)
end

---eylem calistir (saf yonlendirme; olaylar kendi dogrulamasini yapar)
function Page:runAction(action)
    local mission, gone = self:takeTarget()
    if gone then
        -- onay beklerken kontrat panodan dustu: sessizce baska kontrata uygulama
        if ContractManagerAdmin ~= nil and ContractManagerAdmin.showResult ~= nil then
            ContractManagerAdmin.showResult("cm_adminNotFound", false)
        end
        self:refresh()
        return
    end
    -- Istemcide mission.uniqueId NIL'dir (sunucu onu hic gondermiyor), bu yuzden
    -- kontrat AG kimligiyle gosterilir; sunucu kendi uniqueId'sine cevirir.
    local uniqueId = ContractManager.getMissionKey(mission)
    local objectId = ContractManager.getMissionObjectId(mission)
    if action == "refresh" then
        ContractManagerAdminEvent.send(ContractManagerAdmin.ACTION_REFRESH)
    elseif mission == nil or (uniqueId == nil and objectId == 0) then
        return
    elseif action == "reserve" then
        ContractManagerReservationEvent.send(ContractManagerReservationEvent.RESERVE, uniqueId, objectId)
    elseif action == "release" then
        ContractManagerReservationEvent.send(ContractManagerReservationEvent.RELEASE, uniqueId, objectId)
    elseif action == "invite" then
        ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.INVITE, uniqueId, self.targetFarmId, objectId)
    elseif action == "partnerAccept" then
        ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.ACCEPT, uniqueId, nil, objectId)
    elseif action == "partnerLeave" then
        ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.LEAVE, uniqueId, nil, objectId)
    elseif action == "partnerDecline" then
        ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.DECLINE, uniqueId, nil, objectId)
    elseif action == "cancel" then
        ContractManagerAdminEvent.send(ContractManagerAdmin.ACTION_CANCEL, uniqueId, nil, objectId)
    elseif action == "assign" then
        ContractManagerAdminEvent.send(ContractManagerAdmin.ACTION_ASSIGN, uniqueId, self.targetFarmId, objectId)
    elseif action == "transfer" then
        ContractManagerAdminEvent.send(ContractManagerAdmin.ACTION_TRANSFER, uniqueId, self.targetFarmId, objectId)
    end
    self:refresh()
end

-- ---------------------------------------------------------------------------
-- eleman havuzu (klonlanan prefab'lar)
-- ---------------------------------------------------------------------------

local function updateFocusIds(element)
    if element == nil or FocusManager == nil then
        return
    end
    element.focusId = FocusManager:serveAutoFocusId()
    for _, child in pairs(element.elements or {}) do
        updateFocusIds(child)
    end
end

function Page:setRowText(element, value)
    if element == nil then
        return
    end
    if element.cmLastText ~= value then
        element.cmLastText = value
        element:setText(value)
    end
end

---Kabin icindeki hucreyi ADIYLA bul. elements[n] sirasina guvenmiyoruz: XML'e bir
---eleman eklenince sira kayiyor ve yanlis hucreye yaziliyordu.
local function childByName(box, name)
    for _, child in pairs(box ~= nil and box.elements or {}) do
        if child.name == name then
            return child
        end
    end
    return nil
end
Page.childByName = childByName

---Satir kabina hucre tablosu baglar. Hucre yoksa (eski XML) nil kalir; cagiran taraf
---tek metinli eski gorunume duser, sayfa hicbir durumda bos kalmaz.
local function attachCells(box)
    local cells, found = {}, 0
    for _, name in ipairs(Page.CELL_NAMES) do
        local cell = childByName(box, name)
        cells[name] = cell
        if cell ~= nil then
            found = found + 1
        end
        -- profildeki renk: durum rengi verilip geri alinirken buraya donulur
        if cell ~= nil and type(cell.textColor) == "table" then
            cell.cmBaseColor = { cell.textColor[1], cell.textColor[2], cell.textColor[3], cell.textColor[4] }
        end
    end
    -- Hic hucre yoksa tablo BIRAKILMAZ: setCells false donsun ve cagiran eski
    -- tek metinli gorunume dussun (eski XML ile calisan kurulumlar).
    box.cmCells = found > 0 and cells or nil
    return box.cmCells
end

---Hucrelere metin yaz; renk verilirse yalnizca durum sutununa uygulanir.
function Page:setCells(box, values, colorCell, r, g, b, a)
    local cells = box ~= nil and box.cmCells or nil
    if cells == nil then
        return false
    end
    for _, name in ipairs(Page.CELL_NAMES) do
        local cell = cells[name]
        if cell ~= nil then
            self:setRowText(cell, values[name] or "")
            if cell.setTextColor ~= nil then
                -- Renk her tazelemede yeniden verilir: onceki satirdan kalan renk kalmasin.
                if name == colorCell and r ~= nil then
                    cell:setTextColor(r, g, b, a)
                    cell.cmColored = true
                elseif cell.cmColored then
                    cell:setTextColor(unpack(cell.cmBaseColor or { 1, 1, 1, 1 }))
                    cell.cmColored = false
                end
            end
        end
    end
    return true
end

function Page:buildContent()
    local layout = self.manageLayout
    local headerPrefab, textPrefab, buttonPrefab = self.headerPrefab, self.textPrefab, self.buttonPrefab
    local optionPrefab = self.optionPrefab

    local function cloneText(labelKey)
        local header = headerPrefab:clone(layout)
        updateFocusIds(header)
        header:setText(text(labelKey))
        return header
    end

    -- kontrat listesi: siralama secicisi + sutun basligi + satirlar
    self.listHeader = cloneText("cm_pageContracts")
    do
        local box = optionPrefab:clone(layout)
        updateFocusIds(box)
        box.cmOption, box.cmLabel = box.elements[1], box.elements[2]
        box.cmPaintable = true
        box.cmLabel:setText(text("cm_sortLabel", "Sort"))
        if box.cmOption.setTexts ~= nil then
            box.cmOption:setTexts(Page.sortModeTexts())
            box.cmOption:setState(self.sortMode or Page.SORT_SMART)
        end
        -- Durum geri cagri argumanindan DEGIL secicinin kendisinden okunur
        -- (hedef ciftlik secicisinde dogrulanmis kalip).
        box.cmOption.onClickCallback = function() self:onSortChanged() end
        self.sortRow = box
    end
    if self.columnHeaderPrefab ~= nil then
        local header = self.columnHeaderPrefab:clone(layout)
        updateFocusIds(header)
        attachCells(header)
        local titles = Page.columnTitles()
        for _, name in ipairs(Page.CELL_NAMES) do
            local cell = header.cmCells[name]
            if cell ~= nil then
                cell:setText(titles[name] or "")
            end
        end
        self.columnHeader = header
    end
    -- Yeni sutunlu satir yoksa (eski XML) eski tek metinli satira duseriz.
    local rowPrefab = self.missionRowPrefab or buttonPrefab
    for index = 1, Page.MAX_ROWS do
        local box = rowPrefab:clone(layout)
        updateFocusIds(box)
        local button = childByName(box, "rowButton") or box.elements[1]
        local label = childByName(box, "buttonLabel")
        attachCells(box)
        button.onClickCallback = function() self:onClickRow(index) end
        button:setText(text("cm_pageSelect", "..."))
        box.cmButton, box.cmLabel, box.cmPaintable = button, label, true
        self.rowElements[index] = box
    end
    self.emptyRow = textPrefab:clone(layout)
    updateFocusIds(self.emptyRow)
    self.emptyRow.cmLabel = self.emptyRow.elements[1]
    self.emptyRow.cmPaintable = true

    -- secili kontrat: solda etiket, sagda deger
    local detailPrefab = self.detailRowPrefab or textPrefab
    local function cloneDetailRow()
        local box = detailPrefab:clone(layout)
        updateFocusIds(box)
        box.cmDetailLabel = childByName(box, "cellLabel")
        box.cmDetailValue = childByName(box, "cellValue")
        box.cmLabel = box.cmDetailLabel or box.elements[1]
        box.cmPaintable = true
        return box
    end

    self.detailHeader = cloneText("cm_pageSelected")
    for index = 1, Page.MAX_DETAIL do
        self.detailElements[index] = cloneDetailRow()
    end

    -- ortaklik (kontrata katilan ciftlikler)
    self.partnerHeader = cloneText("cm_pagePartners")
    for index = 1, Page.MAX_PARTNER do
        self.partnerElements[index] = cloneDetailRow()
    end

    -- eylemler
    self.actionHeader = cloneText("cm_pageActions")
    self.farmOption = optionPrefab:clone(layout)
    updateFocusIds(self.farmOption)
    self.farmOption.cmOption, self.farmOption.cmLabel = self.farmOption.elements[1], self.farmOption.elements[2]
    self.farmOption.cmPaintable = true
    self.farmOption.cmOption.onClickCallback = function() self:onFarmOptionChanged() end
    for index = 1, 6 do
        local box = buttonPrefab:clone(layout)
        updateFocusIds(box)
        box.cmButton, box.cmLabel, box.cmPaintable = box.elements[1], box.elements[2], true
        box.cmButton.onClickCallback = function()
            self:onClickAction(box.cmAction)
        end
        self.actionElements[index] = box
    end

    headerPrefab:delete()
    textPrefab:delete()
    buttonPrefab:delete()
    optionPrefab:delete()
    for _, prefab in pairs({ self.missionRowPrefab, self.columnHeaderPrefab, self.detailRowPrefab }) do
        prefab:delete()   -- pairs: biri eksikse digerleri yine silinir
    end
    self.missionRowPrefab, self.columnHeaderPrefab, self.detailRowPrefab = nil, nil, nil
end

---Detay/ortak satirini iki sutuna yaz; sutun yoksa eski tek metin.
function Page:setDetailRow(box, line)
    if box.cmDetailValue ~= nil and box.cmDetailLabel ~= nil then
        local label, value = Page.splitDetailLine(line)
        self:setRowText(box.cmDetailLabel, label)
        self:setRowText(box.cmDetailValue, value)
        return
    end
    self:setRowText(box.cmLabel, line)
end

---Satir arka planlari: oyunun ayar sayfasi bunu updateAlternatingElements ile yapar.
---O yoksa ayni etkiyi kendimiz veririz (baseReference duz beyaz dikdortgendir).
function Page:paintRows()
    local layout = self.manageLayout
    if layout == nil then
        return
    end
    local frame = g_inGameMenu ~= nil and g_inGameMenu.pageSettings or nil
    if frame ~= nil and frame.updateAlternatingElements ~= nil then
        if pcall(frame.updateAlternatingElements, frame, layout) then
            return
        end
    end
    local index = 0
    for _, element in ipairs(layout.elements or {}) do
        if element.cmPaintable and element:getIsVisible() then
            index = index + 1
            local alpha = (index % 2 == 0) and 0.35 or 0.15
            if element.setImageColor ~= nil then
                element:setImageColor(nil, 0, 0, 0, alpha)
            end
        end
    end
end

function Page:refresh()
    local farmId = self:getLocalFarmId()
    local isAdmin = self:getIsAdmin()
    local total
    self.rows, total = Page.buildRows(self.filter, farmId, isAdmin, self.sortMode)

    for index, box in ipairs(self.rowElements) do
        local row = self.rows[index]
        box:setVisible(row ~= nil)
        if row ~= nil then
            local cells, colorCell, r, g, b, a
            if row.entry ~= nil then
                cells = Page.historyCells(row.entry)
                colorCell = "cellFarm"   -- gecmiste bu sutun bitis durumudur
                r, g, b, a = Page.historyStateColor(row.entry.finishState)
            else
                cells = Page.missionCells(row.mission)
            end
            if not self:setCells(box, cells, colorCell, r, g, b, a) then
                self:setRowText(box.cmLabel, row.label)   -- sutunsuz eski gorunum
            end
            -- buton kisa etiket kullanir; "cm_pageSelected" bolum basliginin metnidir
            self:setRowText(box.cmButton, index == self.selectedIndex and text("cm_pageSelectedMark", "*") or text("cm_pageSelect", "..."))
        end
    end
    if self.columnHeader ~= nil then
        self.columnHeader:setVisible(#self.rows > 0)
    end
    if self.emptyRow ~= nil then
        self.emptyRow:setVisible(#self.rows == 0)
        if #self.rows == 0 then
            self:setRowText(self.emptyRow.cmLabel, text("cm_pageEmpty", "-"))
        end
    end
    if self.listHeader ~= nil then
        self:setRowText(self.listHeader, Page.listTitle(#self.rows, total))
    end
    if self.sortRow ~= nil then
        self.sortRow:setVisible(total > 1)
    end

    local row = self:getSelected()
    -- Liste bosken "Secili kontrat / listeden birini secin" satiri gereksiz tekrar.
    local showDetail = #self.rows > 0
    local lines = showDetail and Page.buildDetailLines(row and row.mission or nil, row and row.entry or nil) or {}
    if self.detailHeader ~= nil then
        self.detailHeader:setVisible(showDetail)
    end
    for index, box in ipairs(self.detailElements) do
        local line = lines[index]
        box:setVisible(line ~= nil)
        if line ~= nil then
            self:setDetailRow(box, line)
        end
    end

    -- ortaklik: kontrata katilan her ciftlik kendi satirinda
    local partnerLines = showDetail and Page.buildPartnerLines(row and row.mission or nil,
        Page.missionReward(row and row.mission or nil)) or {}
    if self.partnerHeader ~= nil then
        self.partnerHeader:setVisible(#partnerLines > 0)
    end
    for index, box in ipairs(self.partnerElements) do
        local line = partnerLines[index]
        box:setVisible(line ~= nil)
        if line ~= nil then
            self:setDetailRow(box, line)
        end
    end

    local actions = Page.getActions(row and row.mission or nil, farmId, isAdmin, self.targetFarmId)
    local needsFarm = false
    for _, action in ipairs(actions) do
        if action == "invite" or action == "assign" or action == "transfer" then needsFarm = true end
    end
    if self.farmOption ~= nil then
        local ids = Page.getFarmIds(farmId)
        -- Yalnizca hedef ciftlik GEREKTIREN bir eylem aciksa gorunur. Eskiden
        -- targetFarmId dolu oldugu icin kontrat listesi bosken bile duruyordu.
        self.farmOption:setVisible(#ids > 0 and needsFarm)
        local option = self.farmOption.cmOption
        if #ids > 0 and option ~= nil and option.setTexts ~= nil then
            -- metinler yalnizca ciftlik listesi degistiginde yazilir; setTexts
            -- her cagrida icerigi yeniden kuruyor, her tazelemede yapilmamali
            local signature = table.concat(ids, ",")
            if option.cmSignature ~= signature then
                option.cmSignature = signature
                option:setTexts(Page.farmOptionTexts(ids))
            end
            local wanted = Page.farmOptionIndex(ids, self.targetFarmId)
            if option:getState() ~= wanted then
                option:setState(wanted)
            end
        end
        self:setRowText(self.farmOption.cmLabel, text("cm_pageTargetFarm"))
    end
    if self.actionHeader ~= nil then
        self.actionHeader:setVisible(#actions > 0)
    end
    -- kurulu onay artik acik degilse dusur (ornegin yetki ya da durum degisti)
    if self.pendingAction ~= nil then
        local stillOpen = false
        for _, action in ipairs(actions) do
            if action == self.pendingAction then stillOpen = true end
        end
        if not stillOpen then
            self.pendingAction = nil
        end
    end
    for index, box in ipairs(self.actionElements) do
        local action = actions[index]
        box.cmAction = action
        box:setVisible(action ~= nil)
        if action ~= nil then
            if action == self.pendingAction then
                self:setRowText(box.cmButton, text("cm_pageConfirmButton", "Confirm"))
                self:setRowText(box.cmLabel, Page.confirmQuestion(action, Page.farmName(self.targetFarmId)))
            else
                self:setRowText(box.cmButton, text(Page.ACTION_TEXT[action] or action))
                self:setRowText(box.cmLabel, text("cm_pageAction_" .. action, ""))
            end
        end
    end

    if self.manageLayout ~= nil and self.manageLayout.invalidateLayout ~= nil then
        self.manageLayout:invalidateLayout()
    end
    pcall(Page.paintRows, self)
    if self.manageSlider ~= nil and self.manageSlider.setDataElement ~= nil then
        pcall(self.manageSlider.setDataElement, self.manageSlider, self.manageLayout)
    end
end

---Sayfa kapandi. Kendi bayragimizi tutuyoruz: oyunun `isOpen` alanina guvenmiyoruz
---(TabbedMenuFrameElement govdesi yayinlanmamis kaynakta yok).
function Page:onFrameClose()
    Page.isOpen = false
    Page.pendingMission = nil
    if ContractManagerManagePage:superClass().onFrameClose ~= nil then
        ContractManagerManagePage:superClass().onFrameClose(self)
    end
end

function Page:onFrameOpen()
    Page.isOpen = true
    ContractManagerManagePage:superClass().onFrameOpen(self)
    if self.targetFarmId == nil then
        local ids = Page.getFarmIds(self:getLocalFarmId())
        self.targetFarmId = ids[1]
    end
    pcall(function()
        self:refresh()
        if ContractManagerStatsEvent ~= nil then
            ContractManagerStatsEvent.request()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- menuye kayit (FS25_SellingAdmin'de dogrulanmis yordam)
-- ---------------------------------------------------------------------------

local function verifyRegistration(menu, page)
    local paging = menu.pagingElement
    if paging == nil or paging.getPageIdByElement == nil or paging.getIsPageDisabled == nil then
        return false, "PagingElement API"
    end
    local ok, pageId = pcall(paging.getPageIdByElement, paging, page)
    if not ok or pageId == nil then
        return false, "sayfa paging icinde yok"
    end
    if not pcall(paging.getIsPageDisabled, paging, pageId) then
        return false, "getIsPageDisabled patladi"
    end
    for _, frame in ipairs(menu.pageFrames or {}) do
        local okId, id = pcall(paging.getPageIdByElement, paging, frame)
        if not okId or id == nil then
            return false, "baska bir sayfa bozuldu"
        end
        if not pcall(paging.getIsPageDisabled, paging, id) then
            return false, "baska sayfada getIsPageDisabled patladi"
        end
    end
    return true
end

local function indexOf(list, value)
    for index, item in ipairs(list or {}) do
        if item == value then
            return index
        end
    end
    return nil
end

---Kenar cubugundaki sekme sirasi ile sayfa sirasi ESLESMEK ZORUNDA.
---Sekme listesi TabbedMenu.pageFrames'ten uretilir (rebuildTabList), secili sekmenin
---vurgusu ise pagingElement'in mappingIndex'inden gelir (setPage -> currentPageListIndex =
---pageMappingIndex). Yalnizca birini degistirirsek yanlis sekme isaretli gorunur.
---Bu yordam iki sirayi da ayni indekse tasir; tutmazsa cagiran geri alir.
function Page.orderMatches(menu)
    local paging = menu.pagingElement
    if paging == nil or paging.getPageIdByElement == nil then
        return false
    end
    local expected = 0
    for _, frame in ipairs(menu.pageFrames or {}) do
        local okId, pageId = pcall(paging.getPageIdByElement, paging, frame)
        if not okId or pageId == nil then
            return false
        end
        local okDis, disabled = pcall(paging.getIsPageDisabled, paging, pageId)
        if not okDis then
            return false
        end
        if not disabled then
            expected = expected + 1
            local okIdx, mapping = pcall(paging.getPageMappingIndex, paging, pageId)
            if not okIdx or mapping ~= expected then
                return false
            end
        end
    end
    return expected > 0
end

---Sayfayi hem pageFrames hem pagingElement.pages icinde `position`a tasir.
---Basarisizsa iki sirayi da eski haline dondurur ve false doner (sayfa yine calisir,
---yalnizca listenin sonunda kalir).
function Page.movePage(menu, page, position)
    local paging = menu.pagingElement
    if paging == nil or type(paging.pages) ~= "table" or paging.updatePageMapping == nil
        or paging.getPageIdByElement == nil or paging.getPageById == nil then
        return false
    end
    local frameIndex = indexOf(menu.pageFrames, page)
    if frameIndex == nil or position == nil or position < 1 or position >= frameIndex then
        return false   -- yalnizca YUKARI tasima; asagi tasimanin bir anlami yok
    end
    -- kaydin dizideki yerini alan adi tahmin etmeden bul
    local okId, pageId = pcall(paging.getPageIdByElement, paging, page)
    if not okId or pageId == nil then
        return false
    end
    local okRec, record = pcall(paging.getPageById, paging, pageId)
    if not okRec or record == nil then
        return false
    end
    local pageIndex = indexOf(paging.pages, record)
    if pageIndex == nil then
        return false
    end

    local framesBefore, pagesBefore = {}, {}
    for i, v in ipairs(menu.pageFrames) do framesBefore[i] = v end
    for i, v in ipairs(paging.pages) do pagesBefore[i] = v end

    table.remove(menu.pageFrames, frameIndex)
    table.insert(menu.pageFrames, position, page)
    table.remove(paging.pages, pageIndex)
    table.insert(paging.pages, math.min(position, #paging.pages + 1), record)

    local okMap = pcall(paging.updatePageMapping, paging)
    if okMap and Page.orderMatches(menu) then
        return true
    end
    -- Tutmadi: sayfa kimlikleri dizi indeksine bagli olabilir. Eski sirayi geri koy.
    for i = #menu.pageFrames, 1, -1 do menu.pageFrames[i] = nil end
    for i, v in ipairs(framesBefore) do menu.pageFrames[i] = v end
    for i = #paging.pages, 1, -1 do paging.pages[i] = nil end
    for i, v in ipairs(pagesBefore) do paging.pages[i] = v end
    pcall(paging.updatePageMapping, paging)
    return false
end

---Kontrat sayfasinin hemen ardi: yonetim sayfasinin dogal yeri.
function Page.preferredPosition(menu)
    local target = menu ~= nil and menu.pageContracts or nil
    if target == nil then
        return nil
    end
    local index = indexOf(menu.pageFrames, target)
    return index ~= nil and index + 1 or nil
end

---Yarim kalan kaydi tamamen geri al. `removePage` hata atmadan is gormeyebilir
---(kayda ORNEK verilmisti, removePage'e SINIF tablosu geciyorduk) ve pcall yine true doner;
---bu yuzden her durumda elle temizlik de yapilir. `pagingElement` ve `pageEnablingPredicates`
---atlanirsa pageFrames ile pagingElement.pages sayilari ayrisir ve yanlis sekme isaretli
---gorunur - movePage yorumlarinda tarif edilen durum. 2026-09-13 denetimi.
local function rollback(menu, page)
    if menu.removePage ~= nil then
        pcall(menu.removePage, menu, page)
    end
    pcall(function()
        for index = #(menu.pageFrames or {}), 1, -1 do
            if menu.pageFrames[index] == page then table.remove(menu.pageFrames, index) end
        end
        if type(menu.pageTabs) == "table" then menu.pageTabs[page] = nil end
        if type(menu.pageRoots) == "table" then menu.pageRoots[page] = nil end
        if type(menu.pageEnablingPredicates) == "table" then menu.pageEnablingPredicates[page] = nil end
        if type(menu.pageTypeControllers) == "table" then menu.pageTypeControllers[page] = nil end
        if menu.pagingElement ~= nil and menu.pagingElement.removeElement ~= nil then
            pcall(menu.pagingElement.removeElement, menu.pagingElement, page)
        end
        if type(menu.pagingElement) == "table" and type(menu.pagingElement.pages) == "table" then
            for index = #menu.pagingElement.pages, 1, -1 do
                local entry = menu.pagingElement.pages[index]
                if entry == page or (type(entry) == "table" and entry.element == page) then
                    table.remove(menu.pagingElement.pages, index)
                end
            end
        end
        if menu.rebuildTabList ~= nil then menu:rebuildTabList() end
    end)
    ContractManagerManagePage.installed = false
    ContractManagerManagePage.page = nil
end

---Ikonu oyunun dilim (slice) sistemine kaydeder.
---Kenar cubugu sekmesi ikonu dilim kimliginden cizer; addPageTab'e yalnizca dosya
---adi verilince sekme BOS kalir. Kayit basarisizsa dosya yoluna dusulur.
function Page.registerIconSlice()
    if Page.sliceRegistered ~= nil then
        return Page.sliceRegistered
    end
    Page.sliceRegistered = false
    if g_overlayManager == nil or g_overlayManager.addTextureConfigFile == nil
        or g_overlayManager.getSliceInfoById == nil then
        return false
    end
    local path = ContractManager.MOD_DIRECTORY .. "gui/textureConfig.xml"
    if not fileExists(path) then
        return false
    end
    -- customEnv VERILMEZ: getSliceInfoById kimligi "onek.dilim" olarak iki parcaya
    -- boler ve setImageSlice onu customEnv'siz arar. Onek bu yuzden benzersiz.
    if not pcall(g_overlayManager.addTextureConfigFile, g_overlayManager, path, Page.SLICE_PREFIX) then
        return false
    end
    local ok, slice = pcall(g_overlayManager.getSliceInfoById, g_overlayManager, Page.TAB_SLICE)
    Page.sliceRegistered = ok and slice ~= nil
    return Page.sliceRegistered
end

---Baslik seridindeki ikon. Stok slice adlari (gui.icon_ingameMenu_*) yayinlanmadigi
---icin kendi dilimimizi kullaniriz.
function Page.applyHeaderIcon(page)
    local icon = page ~= nil and page.cmHeaderIcon or nil
    if icon == nil then
        return
    end
    if Page.registerIconSlice() and icon.setImageSlice ~= nil then
        pcall(icon.setImageSlice, icon, nil, Page.TAB_SLICE)
        return
    end
    if icon.setImageFilename == nil then
        return
    end
    pcall(icon.setImageFilename, icon, ContractManager.MOD_DIRECTORY .. "gui/tabIcon.dds")
    -- DIKKAT: setImageUVs(state, v0,u0, v1,u1, v2,u2, v3,u3) SEKIZ AYRI SAYI ister.
    -- Tablo verilirse her karede "setOverlayUVs: Expected Float, Actual Table" hatasi
    -- atar; menu acikken log saniyede ~60 satir buyur ve oyun kasar (v1.8.1.0 hatasi).
    if icon.setImageUVs ~= nil then
        pcall(icon.setImageUVs, icon, nil, 0, 0, 0, 1, 1, 0, 1, 1)
    end
end

---Ayar: kenar cubugundaki sayfa acik mi? (yuklem; TabbedMenu:updatePages cagirir)
function Page.isEnabledBySetting()
    if ContractManagerSettings == nil or ContractManagerSettings.get == nil then
        return true
    end
    return ContractManagerSettings:get("ui.managePage") ~= false
end

---Ayar degisince sekmeyi guncelle (acik/kapali). Acik sayfadayken kapatilirsa oyun
---ilk etkin sayfaya gecer; updatePages bunu kendisi yapar.
function Page.onSettingsChanged()
    local menu = g_inGameMenu
    if not Page.installed or menu == nil or menu.updatePages == nil then
        return
    end
    pcall(menu.updatePages, menu)
end

---Sayfayi oyunun EKRAN kayitlarindan cikar (1.24.9.0). loadGui cerceve bayragi (isFrame) OLMADAN
---cagrilinca kontroloru bagimsiz bir ekran olarak da kaydeder: guis[ad], nameScreenTypes[ad],
---screens[sinif], screenControllers[sinif] (Gui.lua loadGui + addScreen). Ana menuye donuste oyunun
---temizligi ekranlari tek tek siler; sayfamiz hala ESC menusunun cocuguyken silinince kendini
---pagingElement'ten cikarir (GuiElement:delete -> parent:removeElement) ama menunun pageFrames'inde
---kalir; ardindan rebuildTabList getIsPageDisabled(nil) ile patlar (PagingElement.lua:249), temizlik
---yarida kalir ve her karede yeniden denenir: log yuz binlerce "Unknown entity id ... Overlay.lua:89
---delete" satiriyla dolar (GitHub bildirimi 2026-09-30, 1.21.3.0 ve 1.24.7.0; yerelde 2026-09-28 23:17
---logunda da var). Stok sayfalar menude FrameReference klonu olarak yasar, ekran degildir.
---Donus: bir kayit silindi mi.
function Page.unregisterScreen(page)
    if g_gui == nil or page == nil then
        return false
    end
    local name = Page.SCREEN_NAME
    local cls = (type(page.class) == "function" and page:class()) or Page
    local changed = false
    if type(g_gui.guis) == "table" and g_gui.guis[name] ~= nil then
        g_gui.guis[name] = nil
        changed = true
    end
    if type(g_gui.nameScreenTypes) == "table" and g_gui.nameScreenTypes[name] ~= nil then
        g_gui.nameScreenTypes[name] = nil
        changed = true
    end
    if type(g_gui.screenControllers) == "table" and g_gui.screenControllers[cls] == page then
        g_gui.screenControllers[cls] = nil
        if type(g_gui.screens) == "table" then
            g_gui.screens[cls] = nil
        end
        changed = true
    end
    return changed
end

---Harita kapanirken sayfayi ESC menusunden geri al: kurulumun tersi (1.24.9.0). Menu oyun
---acilisinda bir kez kurulur ve uygulama yeniden baslayana kadar yasar (TabbedMenu:addPage belgesi:
---"until restarting the game"); sayfa birakilirsa ana menuye donus temizligi onu yarim bir menude
---bulur. SIRA ONEMLI: once pageFrames ve menunun tablolari (pagingElement'ten cikarma bir yeniden
---cizimi tetiklerse liste tutarli olmali), sonra pagingElement (sayfa degistirmeden:
---neuterPageUpdates), sonra sekme listesi; sayfa en son, ust ogesi kalmamissa silinir.
---Donus: kaldirilacak bir sayfa var miydi.
function Page.uninstall()
    local page, menu = Page.page, g_inGameMenu
    Page.installed, Page.page, Page.isOpen = false, nil, false
    if page == nil then
        return false
    end
    if menu ~= nil then
        if menu.currentPage == page then
            menu.currentPage = nil
        end
        if menu.restorePage == page then
            menu.restorePage = nil
            menu.restorePageIndex = 1
            menu.restorePageScrollOffset = 0
        end
        for index = #(menu.pageFrames or {}), 1, -1 do
            if menu.pageFrames[index] == page then
                table.remove(menu.pageFrames, index)
            end
        end
        for index = #(menu.enabledPages or {}), 1, -1 do
            if menu.enabledPages[index] == page then
                table.remove(menu.enabledPages, index)
            end
        end
        if type(menu.pageTypeControllers) == "table" then
            for key, controller in pairs(menu.pageTypeControllers) do
                if controller == page then
                    menu.pageTypeControllers[key] = nil
                end
            end
        end
        for _, field in ipairs({ "pageRoots", "pageEnablingPredicates", "pageTabs", "disabledPages" }) do
            if type(menu[field]) == "table" then
                menu[field][page] = nil
            end
        end
        local paging = menu.pagingElement
        if paging ~= nil and paging.removeElement ~= nil then
            local neuter = paging.neuterPageUpdates
            paging.neuterPageUpdates = true
            local ok, err = pcall(paging.removeElement, paging, page)
            paging.neuterPageUpdates = neuter
            if not ok then
                ContractManager.warning("Management page: removing it from the menu failed: %s", tostring(err))
            end
        end
        if menu.rebuildTabList ~= nil then
            local ok, err = pcall(menu.rebuildTabList, menu)
            if not ok then
                ContractManager.warning("Management page: tab list rebuild after removal failed: %s", tostring(err))
            end
        end
    end
    Page.unregisterScreen(page)
    if page.parent == nil and page.delete ~= nil then
        local ok, err = pcall(page.delete, page)
        if not ok then
            ContractManager.warning("Management page: delete failed: %s", tostring(err))
        end
    end
    ContractManager.info("Management page removed from the in-game menu")
    return true
end

function Page.install()
    if Page.installed then
        return true
    end
    local menu = g_inGameMenu
    if menu == nil or g_gui == nil or menu.registerPage == nil or menu.addPageTab == nil
        or menu.pagingElement == nil or menu.pagingElement.addElement == nil then
        ContractManager.warning("In-game menu API missing; management page skipped")
        return false
    end
    local xmlPath = ContractManager.MOD_DIRECTORY .. "gui/ManagePage.xml"
    if not fileExists(xmlPath) then
        ContractManager.error("Management page: '%s' missing", xmlPath)
        return false
    end
    -- kendi profillerimiz (stok profillerden turer); sayfa yuklenmeden once gelmeli
    local profilePath = ContractManager.MOD_DIRECTORY .. "gui/guiProfiles.xml"
    if fileExists(profilePath) and g_gui.loadProfiles ~= nil then
        if not pcall(g_gui.loadProfiles, g_gui, profilePath) then
            ContractManager.warning("Management page: gui profiles could not be loaded")
        end
    end

    local page
    local ok, err = pcall(function()
        page = Page.new()
        page.name = Page.PAGE_NAME
        if g_gui:loadGui(xmlPath, Page.SCREEN_NAME, page) == nil and page.manageLayout == nil then
            error("loadGui returned nil")
        end
        page:buildContent()
        menu.pagingElement:addElement(page)
        -- Artik menunun parcasi: bagimsiz ekran kaydini kaldir (ana menuye donus temizligi, 1.24.9.0)
        Page.unregisterScreen(page)
        -- Sayfa ayarla acilip kapanabilir: TabbedMenu bu yuklemi updatePages() ile
        -- yeniden degerlendirir, sekme kaybolur/geri gelir. Ayrica kaldirma gerekmez.
        menu:registerPage(page, nil, Page.isEnabledBySetting)
        -- Sekme ikonu ModHub ikonu OLAMAZ: o DXT1/opak, sekmede siyah kare gorunur.
        -- gui/tabIcon.dds saydam zeminli beyaz siluettir, oyun kendi rengini uygular.
        -- 4. parametre dilim kimligi: stok sekmeler ikonu ondan cizer, yalnizca dosya
        -- adi verilirse sekme bos kalir.
        local sliceId = Page.registerIconSlice() and Page.TAB_SLICE or nil
        -- UV'ler TABLO olarak verilir. FS25'te GuiUtils.getUVs bir STRING'i yalnizca
        -- "px" ekliyse referans boyuta boler; eski modlardaki "0 0 1024 1024" yazimi
        -- burada {0,0,1024,1024} olarak kalir ve ikon doku disini ornekler (bos sekme).
        menu:addPageTab(page, ContractManager.MOD_DIRECTORY .. "gui/tabIcon.dds",
            GuiUtils.getUVs({0, 0, 256, 256}, {256, 256}), sliceId)
        Page.applyHeaderIcon(page)
        -- kenar cubugunda kontrat sayfasinin hemen altina tasi; tutmazsa sonda kalir
        local position = Page.preferredPosition(menu)
        if position ~= nil and not Page.movePage(menu, page, position) then
            ContractManager.debug("Management page stays at the end of the tab list")
        end
        if menu.rebuildTabList ~= nil then
            menu:rebuildTabList()
        end
    end)

    if not ok then
        ContractManager.error("Management page could not be installed: %s", tostring(err))
        if page ~= nil then rollback(menu, page) end
        return false
    end

    local verified, problem = verifyRegistration(menu, page)
    if not verified then
        ContractManager.error("Management page failed verification (%s); rolled back, menu intact", tostring(problem))
        rollback(menu, page)
        return false
    end

    Page.page = page
    Page.installed = true
    ContractManager.info("Management page installed (%d rows)", Page.MAX_ROWS)
    return true
end

if g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_START ~= nil then
    g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function()
        Page.install()
    end, Page)
end
if g_messageCenter ~= nil and ContractManager ~= nil and ContractManager.MESSAGE_SETTINGS_CHANGED ~= nil then
    g_messageCenter:subscribe(ContractManager.MESSAGE_SETTINGS_CHANGED, function() Page.onSettingsChanged() end, Page)
end

---Sunucudan veri gelince acik sayfayi tazele. Onceden sayfa YALNIZCA yerel tiklamalarda
---yenileniyordu: baskasi bir kontrati rezerve ettiginde ya da ortaklik degistiginde ekran
---eski veriyi gosteriyor, buton eski metniyle duruyordu. 2026-09-13 denetimi.
function Page.onRemoteChange()
    if Page.installed and Page.isOpen and Page.page ~= nil then
        pcall(function() Page.page:refresh() end)
    end
end

if g_messageCenter ~= nil and MessageType ~= nil then
    if MessageType.MISSION_DELETED ~= nil then
        g_messageCenter:subscribe(MessageType.MISSION_DELETED, function() Page.onRemoteChange() end, Page)
    end
end

---Harita kapanisi: sayfayi menuden geri al (1.24.9.0). Guard gibi olay dinleyicisi; oyun bunu ana
---menuye donus temizliginden ONCE cagiriyor (yerel log 2026-09-28: "[CM/Guard] Unloaded" 15.163,
---temizlik hatasi 15.825).
ContractManagerManagePageListener = {}
function ContractManagerManagePageListener:deleteMap()
    Page.uninstall()
end
if addModEventListener ~= nil then
    addModEventListener(ContractManagerManagePageListener)
end

