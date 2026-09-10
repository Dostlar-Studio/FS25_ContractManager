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
ContractManagerManagePage.FILTER_ACTIVE = 1
ContractManagerManagePage.FILTER_NEW = 2
ContractManagerManagePage.FILTER_HISTORY = 3
ContractManagerManagePage.SLICE_PREFIX = "contractManager"
ContractManagerManagePage.TAB_SLICE = "contractManager.pageTab"
ContractManagerManagePage.MAX_ROWS = 12
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
function Page.confirmQuestion(action, targetFarmName)
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
local FINISH_TEXT = { [2] = "cm_stateSuccess", [3] = "cm_stateFailed", [4] = "cm_stateTimedOut", [5] = "cm_stateCanceled" }

function Page.formatHistory(entry)
    if entry == nil then
        return "-"
    end
    return string.format("%s %s · %s · %s · %s",
        text("cm_day", "Day"), tostring(entry.finishedDay or 0),
        text("cm_type_" .. tostring(entry.typeName), tostring(entry.typeName)),
        text(FINISH_TEXT[entry.finishState or 0] or "cm_stateNone", "-"),
        money(entry.payout or entry.reward or 0))
end

---filtreye gore satirlar (saf). Donus: { {kind="mission"|"history", mission=, entry=, label=}, ... }
function Page.buildRows(filter, farmId, isAdmin)
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
                if #rows >= Page.MAX_ROWS then break end
                rows[#rows + 1] = { kind = "history", entry = entry, label = Page.formatHistory(entry) }
            end
        end
        return rows
    end
    for _, mission in ipairs(missions) do
        local isNew = mission.status == MissionStatus.CREATED
        local isActive = mission.status == MissionStatus.RUNNING or mission.status == MissionStatus.PREPARING
        local wanted = (filter == Page.FILTER_NEW and isNew) or (filter == Page.FILTER_ACTIVE and isActive)
        if wanted and (isAdmin or filter == Page.FILTER_NEW or mission.farmId == farmId
            or (ContractManagerPartnership ~= nil and ContractManagerPartnership.isMember(mission, farmId))) then
            if #rows >= Page.MAX_ROWS then break end
            rows[#rows + 1] = { kind = "mission", mission = mission, label = Page.formatMission(mission) }
        end
    end
    return rows
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
            -- "devret" arayuzden ASKIYA ALINDI (kullanici istegi, 2026-09-10).
            -- Kural katmani (rules/Transfer.lua), olay ve cmTransferContract konsol
            -- komutu duruyor; yalnizca buton gosterilmiyor.
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

function Page:onClickRow(index)
    self.selectedIndex = (self.selectedIndex == index) and 0 or index
    self.pendingAction = nil
    self:refresh()
end

---Secicide baska ciftlige gecildi. (Eski "tiklayinca sirayla degistir" davranisi
---kaldirildi; kullanici oyunun kendi ok tuslu secicisini istedi.)
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
    local question = Page.confirmQuestion(action, Page.farmName(self.targetFarmId))
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
    local yes = nil
    if type(a) == "boolean" then
        yes = a
    elseif type(b) == "boolean" then
        yes = b
    end
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
    local row = self:getSelected()
    local mission = row ~= nil and row.mission or nil
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
    if element.cmLastText ~= value then
        element.cmLastText = value
        element:setText(value)
    end
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

    -- kontrat listesi
    self.listHeader = cloneText("cm_pageContracts")
    for index = 1, Page.MAX_ROWS do
        local box = buttonPrefab:clone(layout)
        updateFocusIds(box)
        local button, label = box.elements[1], box.elements[2]
        button.onClickCallback = function() self:onClickRow(index) end
        button:setText(text("cm_pageSelect", "..."))
        box.cmButton, box.cmLabel, box.cmPaintable = button, label, true
        self.rowElements[index] = box
    end
    self.emptyRow = textPrefab:clone(layout)
    updateFocusIds(self.emptyRow)
    self.emptyRow.cmLabel = self.emptyRow.elements[1]
    self.emptyRow.cmPaintable = true

    -- secili kontrat
    self.detailHeader = cloneText("cm_pageSelected")
    for index = 1, Page.MAX_DETAIL do
        local box = textPrefab:clone(layout)
        updateFocusIds(box)
        box.cmLabel = box.elements[1]
        box.cmPaintable = true
        self.detailElements[index] = box
    end

    -- ortaklik (kontrata katilan ciftlikler)
    self.partnerHeader = cloneText("cm_pagePartners")
    for index = 1, Page.MAX_PARTNER do
        local box = textPrefab:clone(layout)
        updateFocusIds(box)
        box.cmLabel = box.elements[1]
        box.cmPaintable = true
        self.partnerElements[index] = box
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
    self.rows = Page.buildRows(self.filter, farmId, isAdmin)

    for index, box in ipairs(self.rowElements) do
        local row = self.rows[index]
        box:setVisible(row ~= nil)
        if row ~= nil then
            self:setRowText(box.cmLabel, row.label)
            -- buton kisa etiket kullanir; "cm_pageSelected" bolum basliginin metnidir
            self:setRowText(box.cmButton, index == self.selectedIndex and text("cm_pageSelectedMark", "*") or text("cm_pageSelect", "..."))
        end
    end
    if self.emptyRow ~= nil then
        self.emptyRow:setVisible(#self.rows == 0)
        if #self.rows == 0 then
            self:setRowText(self.emptyRow.cmLabel, text("cm_pageEmpty", "-"))
        end
    end
    if self.listHeader ~= nil then
        self:setRowText(self.listHeader, Page.sectionTitle("cm_pageContracts", #self.rows))
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
            self:setRowText(box.cmLabel, line)
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
            self:setRowText(box.cmLabel, line)
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

function Page:onFrameOpen()
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

local function rollback(menu, page)
    if menu.removePage ~= nil and pcall(menu.removePage, menu, ContractManagerManagePage) then
        pcall(function() if menu.rebuildTabList ~= nil then menu:rebuildTabList() end end)
        return
    end
    pcall(function()
        for index = #(menu.pageFrames or {}), 1, -1 do
            if menu.pageFrames[index] == page then table.remove(menu.pageFrames, index) end
        end
        if type(menu.pageTabs) == "table" then menu.pageTabs[page] = nil end
        if type(menu.pageRoots) == "table" then menu.pageRoots[page] = nil end
        if menu.rebuildTabList ~= nil then menu:rebuildTabList() end
    end)
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
        if g_gui:loadGui(xmlPath, "ContractManagerManagePage", page) == nil and page.manageLayout == nil then
            error("loadGui returned nil")
        end
        page:buildContent()
        menu.pagingElement:addElement(page)
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
