--
-- FS25_ContractManager - Ayarlar sayfasi alt sekmesi ("Kontrat Yoneticisi")
--
-- Oyunun stok Ayarlar sayfasina (g_inGameMenu.pageSettings) yeni bir alt sekme ekler.
-- Kalip FS25_BetterContracts v1.3 SettingsManager/UIHelper ile ayni: gui/SettingsPage.xml
-- g_gui:loadGui ile yuklenir, prefab'lar klonlanir, stok BinaryOption / MultiTextOption
-- kontrolleri kullanilir. Ozel cizim yok.
--
-- Iki katman:
--   * Saf mantik (SPEC, deger<->durum donusumu, etiketler, uygula): harness'ta test edilir.
--   * GUI kurulumu (init/build): oyunda calisir, tamamen pcall ile korunur; basarisiz olursa
--     log yazilir ve menu bozulmadan sekme atlanir.
--
-- Yetki: sunucu / master user kural kontrollerini gorur ve degistirir. Digerleri yalnizca
-- istatistik bolumunu gorur.
--

ContractManagerSettingsPage = {}
local ContractManagerSettingsPage_mt = Class(ContractManagerSettingsPage, FrameElement)

function ContractManagerSettingsPage.new(customMt)
    local self = FrameElement.new(nil, customMt or ContractManagerSettingsPage_mt)
    self.controls = {}
    return self
end

---sekme butonu: alt kategori secicisini bizim sayfaya cevir
function ContractManagerSettingsPage:onClickTab()
    local tab = ContractManagerSettingsTab
    if tab.modState ~= nil and g_inGameMenu ~= nil and g_inGameMenu.pageSettings ~= nil then
        g_inGameMenu.pageSettings.subCategoryPaging:setState(tab.modState, true)
    end
end

---stok kontrol tiklandi (BinaryOption / MultiTextOption): (state, element)
function ContractManagerSettingsPage:onClickOption(state, element)
    ContractManagerSettingsTab:onControlChanged(state, element)
end

-- ---------------------------------------------------------------------------

ContractManagerSettingsTab = {
    PREFIX = "cm_",
    HISTORY_ROWS = 5,
    BOARD_ROWS = 24,   -- siralamada gosterilen ciftlik sayisi (MAX_BOARD kadar)
    controls = {},
    controlsByKey = {},
    statsRows = {},
    built = false,
    modState = nil,
    pageNr = nil,
    stats = nil,      -- son alinan istatistik (farmId, stats, history)
}

local Tab = ContractManagerSettingsTab

local function S()
    return ContractManagerSettings
end

-- Metin yardimcisi tek yerde: ContractManager.text (Main.lua). Main once yuklenir.
local function text(key, fallback)
    return ContractManager.text(key, fallback)
end

-- ---------------------------------------------------------------------------
-- l10n koprusu: alt kategori BASLIGINI oyunun kendi kodu cozer
-- (InGameMenuSettingsFrame.HEADER_TITLES -> g_i18n). Oyun tarafi mod metinlerini
-- gormedigi icin "MISSING 'CM_TABTITLE' IN L10N_EN.XML" yaziyordu. Iki katman:
--   1) anahtari genel metin tablosuna yaz (tablo modun kendi tablosuysa zaten var, dokunmaz)
--   2) yine de cozulmediyse gorunen "MISSING ..." metnini yerinde duzelt
-- ---------------------------------------------------------------------------

---Anahtari oyunun genel metin tablosuna ekle (varsa dokunma). Donus: yazildi mi
function Tab.registerGlobalText(key)
    if g_i18n == nil or key == nil then
        return false
    end
    local value = text(key)
    if value == key then
        return false
    end
    if type(g_i18n.setText) == "function" then
        g_i18n:setText(key, value)
    end
    if type(g_i18n.texts) == "table" and g_i18n.texts[key] == nil then
        g_i18n.texts[key] = value
        return true
    end
    return false
end

---Bir metin "MISSING '<KEY>'" bicimindeyse aranan anahtara ait mi?
function Tab.isMissingTextFor(value, key)
    if type(value) ~= "string" or key == nil then
        return false
    end
    local upper = value:upper()
    return upper:find("MISSING", 1, true) ~= nil and upper:find(key:upper(), 1, true) ~= nil
end

---Eleman agacinda cozulememis basligi yerinde duzelt (stok eleman adlari yayinlanmiyor)
function Tab.fixMissingTexts(element, key, depth)
    depth = depth or 0
    if element == nil or depth > 8 then
        return 0
    end
    local fixed = 0
    if type(element.text) == "string" and element.setText ~= nil and Tab.isMissingTextFor(element.text, key) then
        element:setText(text(key))
        fixed = fixed + 1
    end
    for _, child in ipairs(element.elements or {}) do
        fixed = fixed + Tab.fixMissingTexts(child, key, depth + 1)
    end
    return fixed
end

-- ---------------------------------------------------------------------------
-- kontrol tanimlari (saf). Tek kaynak Settings.SPEC (1.27.0.0): sinirlar, bolum ve secenek listesi
-- orada. Eskiden burada ikinci bir liste vardi ve sinirlari dosyanin sinirlarindan farkliydi.
-- kind: bool | range | choice. zero: 0 degeri icin l10n etiketi. values: range'in secenek listesi.
-- ---------------------------------------------------------------------------

---Ayar (ya da tur alani) tanimindan ekran kontrolu tanimi (saf)
function Tab.controlSpec(spec, key)
    local ui = spec.ui or {}
    local out = { id = key, key = key, mpOnly = spec.mpOnly, format = ui.format, zero = ui.zero }
    if spec.type == "bool" then
        out.kind = "bool"
    elseif spec.type == "string" then
        out.kind = "choice"
        out.values = ui.values
        out.labels = ui.labels
    else
        out.kind = "range"
        out.min = spec.min
        out.max = spec.max
        out.values = ContractManagerSettings.getUiValues(spec)
    end
    return out
end

---Ekran satirlari: Settings.SPEC sirasiyla, bolum degisince bolum basligi (saf; test edilir). Bolumdeki
---butun ayarlar yalnizca cok oyunculuysa baslik da "yalnizca cok oyunculu" isaretlenir.
function Tab.buildSpecList()
    local specs = ContractManagerSettings.SPEC
    local list = {}
    local i = 1
    while i <= #specs do
        local section = specs[i].section
        local j, allMp = i, true
        while j <= #specs and specs[j].section == section do
            allMp = allMp and specs[j].mpOnly == true
            j = j + 1
        end
        list[#list + 1] = { section = section, mpOnly = allMp or nil }
        for k = i, j - 1 do
            list[#list + 1] = Tab.controlSpec(specs[k], specs[k].id)
        end
        i = j
    end
    return list
end

Tab.SPEC = Tab.buildSpecList()

---Kontrat turu alaninin kontrolu: "type:<ad>:<alan>"
function Tab.typeControlSpec(typeName, field)
    local fieldSpec = ContractManagerSettings.TYPE_FIELD_BY_NAME[field]
    if fieldSpec == nil then
        return nil
    end
    return Tab.controlSpec(fieldSpec, "type:" .. typeName .. ":" .. field)
end

---Bir spec bu oturumda gosterilsin mi?
function Tab.isSpecVisible(spec)
    if spec.onlyIf == "betterContracts" then
        return ContractManager:isBetterContractsLoaded()
    end
    return true
end

---range spec icin secenek sayisi
function Tab.getRangeCount(spec, values)
    return #(values or spec.values or {})
end

function Tab.formatValue(spec, value)
    if spec.zero ~= nil and value == 0 then
        return text(spec.zero, "-")
    end
    if spec.format == "money" then
        return ContractManager.formatMoney(value)
    end
    -- Birimler oyuncunun dilinden: eskiden her dilde "6 h", "10 min", "2.5 ha" yaziliyordu (1.26.0.0).
    if spec.format == "hours" then
        return string.format("%d %s", value, text("cm_unitHour", "h"))
    elseif spec.format == "minutes" then
        return string.format("%d %s", value, text("cm_unitMinute", "min"))
    elseif spec.format == "area" then
        if g_i18n ~= nil and g_i18n.formatArea ~= nil then
            local s = g_i18n:formatArea(value, 1)
            if s ~= nil then
                return s
            end
        end
        return string.format("%.1f ha", value)
    end
    return ContractManager.formatSafe(spec.format or "%s", value)
end

---Listede olmayan gecerli deger (web panelinden ya da dosyadan gelen) listeye kendi yerinde eklenir:
---ekran gercek degeri gostersin, kontrole dokunmak degeri en yakin adima kaydirmasin (1.27.0.0; ana
---sunucuda aylik kota 6 iken ekran 5 gosteriyordu). Donus: liste - degismediyse spec.values'un kendisi.
function Tab.valuesWith(spec, value)
    local values = spec.values or {}
    if spec.kind ~= "range" or type(value) ~= "number" or value ~= value then
        return values
    end
    if (spec.min ~= nil and value < spec.min) or (spec.max ~= nil and value > spec.max) then
        return values
    end
    for _, v in ipairs(values) do
        if math.abs(v - value) < 1e-6 then
            return values
        end
    end
    local out, inserted = {}, false
    for _, v in ipairs(values) do
        if not inserted and value < v then
            out[#out + 1] = value
            inserted = true
        end
        out[#out + 1] = v
    end
    if not inserted then
        out[#out + 1] = value
    end
    return out
end

---kontrolun secenek metinleri (`values` verilmezse spec'in listesi)
function Tab.buildTexts(spec, values)
    local texts = {}
    if spec.kind == "range" then
        for i, value in ipairs(values or spec.values or {}) do
            texts[i] = Tab.formatValue(spec, value)
        end
    elseif spec.kind == "choice" then
        for i, label in ipairs(spec.labels) do
            local raw = spec.values[i]
            if label:sub(1, 3) == "cm_" then
                texts[i] = text(label, raw)
            else
                texts[i] = label
            end
        end
    end
    return texts
end

---Degerin secenek listesindeki sirasi; listede yoksa en yakini (`values` verilmezse spec'in listesi)
function Tab.valueToState(spec, value, values)
    if spec.kind == "bool" then
        return value and 2 or 1
    elseif spec.kind == "range" then
        values = values or spec.values or {}
        if type(value) ~= "number" then
            return 1
        end
        local best, bestDiff = 1, math.huge
        for i, v in ipairs(values) do
            local diff = math.abs(v - value)
            if diff < bestDiff then
                best, bestDiff = i, diff
            end
        end
        return best
    elseif spec.kind == "choice" then
        for i, v in ipairs(spec.values) do
            if v == value then
                return i
            end
        end
        return 1
    end
    return 1
end

function Tab.stateToValue(spec, state, values)
    if spec.kind == "bool" then
        return state == 2
    elseif spec.kind == "range" then
        values = values or spec.values or {}
        return values[state] or values[1]
    elseif spec.kind == "choice" then
        return spec.values[state] or spec.values[1]
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- kontrol degisimi (deger erisimi ve yetki core'da: ContractManagerSettings / ContractManager.isLocalAdmin)
-- ---------------------------------------------------------------------------

function Tab:onControlChanged(state, element)
    local spec = element ~= nil and element.cmSpec or nil
    if spec == nil then
        return
    end
    if not ContractManager.isLocalAdmin() or Tab.isMpOnlyLocked(spec) then
        self:populate() -- yetkisiz ya da tek oyunculuda kilitli: gorunumu geri al
        return
    end
    local value = Tab.stateToValue(spec, state, element.cmValues)
    if ContractManagerSettingChangeEvent ~= nil then
        ContractManagerSettingChangeEvent.send(spec.key, value)
    else
        S().applyOnServer(spec.key, value, "host")
    end
end

-- ---------------------------------------------------------------------------
-- GUI kurulumu (oyun ici; tamamen korumali)
-- ---------------------------------------------------------------------------

local function updateFocusIds(element)
    if element == nil then
        return
    end
    element.focusId = FocusManager:serveAutoFocusId()
    for _, child in pairs(element.elements or {}) do
        updateFocusIds(child)
    end
end

---Tek oyunculuda kullanilamayan satir/bolum mu? (1.25.0.0)
function Tab.isMpOnlyLocked(spec)
    return spec ~= nil and spec.mpOnly == true and not ContractManager.isMultiplayer()
end

---Sonuk gosterim (saf; test edilir): kilitliyken secenek devre disi ve acik/kapali satiri "kapali"
---gosterir; cok oyunculuda secenek normal calisir. Donus: kilitli mi.
function Tab.applyMpOnlyState(option, spec)
    if option == nil or spec == nil then
        return false
    end
    local locked = Tab.isMpOnlyLocked(spec)
    if option.setDisabled ~= nil then
        option:setDisabled(locked)
    end
    if locked and spec.kind == "bool" and option.setState ~= nil then
        option:setState(Tab.valueToState(spec, false))
    end
    return locked
end

-- tur alani -> satir basligi anahtari (ipucu: anahtar .. "_tooltip")
Tab.TYPE_FIELD_TEXT = { enabled = "cm_typeEnabled", weight = "cm_typeWeight", max = "cm_typeMax" }

---Kontrole degeri yaz (saf; test edilir). Deger listede yoksa liste o degerle yeniden kurulur, yoksa
---ekran en yakin adimi gosterirdi; deger listeye donunce eski liste geri gelir.
function Tab.showValue(option, value)
    local spec = option.cmSpec
    if spec.kind == "range" then
        local values = Tab.valuesWith(spec, value)
        if values ~= option.cmValues then
            option.cmValues = values
            option:setTexts(Tab.buildTexts(spec, values))
        end
    end
    option:setState(Tab.valueToState(spec, value, option.cmValues))
    Tab.applyMpOnlyState(option, spec)
end

function Tab:createSection(i18nKey, spec)
    local page = self.page
    local header = page.subTitlePrefab:clone(page.settingsLayout)
    if Tab.isMpOnlyLocked(spec) then
        header:setText(string.format("%s (%s)", text(i18nKey), text("cm_mpOnlyShort", "multiplayer only")))
    else
        header:setText(text(i18nKey))
    end
    header.focusId = FocusManager:serveAutoFocusId()
    header.cmAdminOnly = true
    table.insert(self.controls, header)
    return header
end

function Tab:createControl(spec, key)
    local page = self.page
    local template = spec.kind == "bool" and page.binaryPrefab or page.multiPrefab
    local box = template:clone(page.settingsLayout)
    updateFocusIds(box)
    box.id = self.PREFIX .. key .. "Box"

    local option = box.elements[1]
    option.focusOnHighlight = true
    option.target = page
    option:setCallback("onClickCallback", "onClickOption")
    option.id = self.PREFIX .. key
    option:setDisabled(false)
    -- kontrol tanimi degismez (Tab.SPEC / Tab.typeControlSpec); o anki secenek listesi kontrolde tutulur
    option.cmSpec = spec
    option.cmValues = spec.values
    if spec.kind ~= "bool" then
        option:setTexts(Tab.buildTexts(spec))
    end

    local title = box.elements[2]
    local name, field = S().parseTypeKey(key)
    local typeKey = name ~= nil and Tab.TYPE_FIELD_TEXT[field] or nil
    if typeKey ~= nil then
        title:setText(string.format("%s: %s", ContractManager.typeTitle(name), text(typeKey)))
    else
        title:setText(text(self.PREFIX .. key:gsub("%.", "_")))
    end

    local tooltip = option.elements[1]
    if tooltip ~= nil and tooltip.setText ~= nil and Tab.isMpOnlyLocked(spec) then
        tooltip:setText(text("cm_mpOnly_tooltip", "Multiplayer only. In single player this feature is off."))
    elseif tooltip ~= nil and tooltip.setText ~= nil then
        if typeKey ~= nil then
            tooltip:setText(text(typeKey .. "_tooltip", ""))
        else
            tooltip:setText(text(self.PREFIX .. key:gsub("%.", "_") .. "_tooltip", ""))
        end
    end

    box.cmAdminOnly = true
    box.cmOption = option
    table.insert(self.controls, box)
    self.controlsByKey[key] = box
    return box
end

function Tab:createRow()
    local page = self.page
    local row = page.rowPrefab:clone(page.settingsLayout)
    updateFocusIds(row)
    row.cmText = row.elements[1]
    row.cmAdminOnly = false
    table.insert(self.controls, row)
    table.insert(self.statsRows, row)
    return row
end

function Tab:buildControls()
    for _, spec in ipairs(self.SPEC) do
        if Tab.isSpecVisible(spec) then
            if spec.section ~= nil then
                self:createSection(spec.section, spec)
            else
                self:createControl(spec, spec.id)
            end
        end
    end

    -- kontrat turleri (dinamik): uretilsin mi, agirlik, panoda en cok
    if g_missionManager ~= nil and g_missionManager.missionTypes ~= nil and #g_missionManager.missionTypes > 0 then
        self:createSection("cm_secTypes")
        for _, missionType in ipairs(g_missionManager.missionTypes) do
            for _, field in ipairs(S().TYPE_FIELDS) do
                self:createControl(Tab.typeControlSpec(missionType.name, field.name), "type:" .. missionType.name .. ":" .. field.name)
            end
        end
    end

    -- istatistik (salt okunur)
    local statsHeader = self:createSection("cm_secStats")
    statsHeader.cmAdminOnly = false
    for _ = 1, 8 + self.HISTORY_ROWS + self.BOARD_ROWS do
        self:createRow()
    end
end

---kontrolleri ayarlardan doldur, yetkiye gore gorunurluk
function Tab:populate()
    if not self.built then
        return
    end
    local isAdmin = ContractManager.isLocalAdmin()
    if self.page ~= nil and self.page.cmNoPermissionText ~= nil then
        self.page.cmNoPermissionText:setVisible(not isAdmin)
    end
    for _, control in ipairs(self.controls) do
        if control.cmAdminOnly then
            control:setVisible(isAdmin)
        end
        if control.cmOption ~= nil and isAdmin then
            Tab.showValue(control.cmOption, S():getValue(control.cmOption.cmSpec.key))
        end
    end
    self:populateStats()
    if self.page ~= nil and self.page.settingsLayout ~= nil then
        self.page.settingsLayout:invalidateLayout()
    end
end

-- Bitis durumu -> l10n anahtari. Oyunun sabitleri 1 TABANLI (canli sonda: NONE=1 SUCCESS=2 FAILED=3
-- TIMED_OUT=4 CANCELED=5); tablo oyunun kendi adlarindan kurulur, oyun yoksa (harness) sabit degerler.
local FINISH_KEY_BY_NAME = { NONE = "cm_stateNone", SUCCESS = "cm_stateSuccess", FAILED = "cm_stateFailed",
    TIMED_OUT = "cm_stateTimedOut", CANCELED = "cm_stateCanceled" }
local FINISH_FALLBACK = { [1] = "cm_stateNone", [2] = "cm_stateSuccess", [3] = "cm_stateFailed", [4] = "cm_stateTimedOut", [5] = "cm_stateCanceled" }
local finishKeyCache = nil

---bitis durumu kodunun l10n anahtari (saf; test edilir)
function Tab.finishStateKey(state)
    if finishKeyCache == nil then
        finishKeyCache = {}
        if type(MissionFinishState) == "table" then
            for name, value in pairs(MissionFinishState) do
                if FINISH_KEY_BY_NAME[name] ~= nil and type(value) == "number" then
                    finishKeyCache[value] = FINISH_KEY_BY_NAME[name]
                end
            end
        end
        if next(finishKeyCache) == nil then
            finishKeyCache = FINISH_FALLBACK
        end
    end
    return finishKeyCache[state] or "cm_stateNone"
end

Tab.formatMoney = ContractManager.formatMoney

---istatistik satirlarinin metinleri (saf; test edilir)
function Tab.buildStatsLines(stats, history, board)
    local lines = {}
    if stats == nil then
        lines[1] = text("cm_statsLoading", "...")
        return lines
    end
    if ContractManagerReputation ~= nil and ContractManagerReputation.isEnabled() then
        local rep = stats.reputation or 0
        local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
        ContractManagerReputation.setLocal(farmId, rep)
        local bonus = ContractManagerReputation.getBonusPercent(farmId)
        local extra = ContractManagerReputation.getExtraSlots(farmId)
        lines[#lines + 1] = string.format("%s: %d (%s +%d %%%s)", text("cm_statReputation"), rep, text("cm_statBonus"), math.floor(bonus + 0.5),
            extra > 0 and (", " .. text("cm_statExtraSlot")) or "")
    end
    lines[#lines + 1] = string.format("%s: %d", text("cm_statCompleted"), stats.completed or 0)
    lines[#lines + 1] = string.format("%s: %d", text("cm_statFailed"), stats.failed or 0)
    lines[#lines + 1] = string.format("%s: %d", text("cm_statCanceled"), stats.canceled or 0)
    lines[#lines + 1] = string.format("%s: %d", text("cm_statTimedOut"), stats.timedOut or 0)
    -- Ust uste basarisizlik odul carpanini dusuruyor (Reward.lua:92) ama oyuncu bunu
    -- hicbir yerde gormuyordu; yalnizca seri varken yazilir.
    if (stats.failStreak or 0) > 0 then
        lines[#lines + 1] = string.format("%s: %d", text("cm_statStreak"), stats.failStreak)
    end
    lines[#lines + 1] = string.format("%s: %s", text("cm_statEarned"), Tab.formatMoney(stats.earned))
    lines[#lines + 1] = string.format("%s: %s", text("cm_statPenalties"), Tab.formatMoney(stats.penalties))
    for i, entry in ipairs(history or {}) do
        -- satir butcesi: 8 + HISTORY_ROWS + BOARD_ROWS. Kapak olmazsa siralamanin kuyrugu sessizce kesilir.
        if i > Tab.HISTORY_ROWS then break end
        local stateKey = Tab.finishStateKey(entry.finishState)
        lines[#lines + 1] = string.format("%s %d · %s · %s · %s",
            text("cm_day"), entry.finishedDay or 0,
            ContractManager.typeTitle(entry.typeName),
            text(stateKey),
            Tab.formatMoney(entry.payout or entry.reward or 0))
    end
    if board ~= nil and #board > 0 then
        lines[#lines + 1] = text("cm_boardTitle")
        for i, row in ipairs(board) do
            if i > Tab.BOARD_ROWS then break end
            lines[#lines + 1] = string.format("%d. %s · %s %d · %d %s · %s", i, tostring(row.name), text("cm_statReputation"), math.floor((row.reputation or 0) + 0.5),
                math.floor((row.completed or 0) + 0.5), text("cm_statCompleted"):lower(), Tab.formatMoney(row.earned))
        end
    end
    return lines
end

function Tab:populateStats()
    local lines = Tab.buildStatsLines(self.stats and self.stats.stats or nil, self.stats and self.stats.history or nil, self.stats and self.stats.board or nil)
    for i, row in ipairs(self.statsRows) do
        local line = lines[i]
        if line ~= nil then
            row:setVisible(true)
            if row.cmLastText ~= line then
                row.cmLastText = line
                row.cmText:setText(line)
            end
        else
            row:setVisible(false)
        end
    end
end

function Tab:onStatsReceived(farmId, stats, history, board)
    self.stats = { farmId = farmId, stats = stats, history = history, board = board }
    if self.built then
        ContractManager.guard("Settings tab statistics", function()
            self:populateStats()
            if self.page ~= nil and self.page.settingsLayout ~= nil then
                self.page.settingsLayout:invalidateLayout()
            end
        end)
    end
end

function Tab:requestStats()
    if ContractManagerStatsEvent ~= nil then
        ContractManagerStatsEvent.request()
    end
end

-- ---------------------------------------------------------------------------
-- stok Ayarlar sayfasina ekleme (BetterContracts SettingsManager kalibi)
-- ---------------------------------------------------------------------------

local function addElementAtPosition(element, target, pos)
    if element.parent ~= nil then
        element.parent:removeElement(element)
    end
    table.insert(target.elements, pos, element)
    element.parent = target
end

---Alt kategori secicisinde CM sekmesinin sirasi (saf). Secici metinleri alt kategori NUMARALARIDIR (asagidaki
---onClickCallback de boyle okur). Eskiden son sira varsayiliyordu: CM'den SONRA ayar sekmesi ekleyen bir mod
---kurulunca CM sekme dugmesi o modun sayfasini aciyordu (1.26.0.0).
function Tab.findPagingState(texts, subCategory)
    if subCategory == nil then
        return nil
    end
    for state, value in ipairs(texts or {}) do
        if tonumber(value) == subCategory then
            return state
        end
    end
    return nil
end

function Tab:insertIntoSettingsPage()
    local pageSettings = g_inGameMenu.pageSettings
    local page = self.page
    local cmPage = page.cmPage
    local cmTab = page.cmTab
    local pos = #pageSettings.subCategoryTabs + 1
    self.pageNr = pos

    addElementAtPosition(cmPage, pageSettings.subCategoryPages[1].parent, pos)
    addElementAtPosition(cmTab, pageSettings.subCategoryBox, pos)
    pageSettings:updateAbsolutePosition()

    cmPage:setTarget(pageSettings, cmPage.target)
    cmTab:setTarget(pageSettings, cmTab.target)

    -- FocusManager hedef adi: stok sayfanin adi (aksi halde kontroller odak almaz)
    page.name = pageSettings.name

    self:buildControls()

    -- prefab'lar artik cmPage'in altinda (stok sayfaya tasindi); kontrolcu uzerinden bulunmaz
    for _, prefabId in ipairs({ "subTitlePrefab", "binaryPrefab", "multiPrefab", "rowPrefab" }) do
        local prefab = cmPage:getDescendantById(prefabId) or page[prefabId]
        if prefab ~= nil and prefab.delete ~= nil then
            prefab:delete()
        end
    end

    pageSettings.subCategoryPages[pos] = cmPage
    pageSettings.subCategoryTabs[pos] = cmTab

    -- odak: stok sayfa acilirken kontrollerimizi kaydet
    local controls = self.controls
    -- Bu kanca HER ekran acilisinda (magaza, harita, her diyalog) ~130 kontrolu tariyordu.
    -- Yalnizca oyunun ayar ekrani acilirken calissin. 2026-09-13 denetimi.
    -- Oyunun odak yoneticisine ek: hatamiz oyunun menu odagini bozmasin (kanca siniri korumali, 1.26.0.0).
    local function registerFocus()
        for _, control in ipairs(controls) do
            if not control.focusId or not FocusManager.currentFocusData.idToElementMapping[control.focusId] then
                FocusManager:loadElementFromCustomValues(control, nil, nil, false, false)
            end
        end
        page.settingsLayout:invalidateLayout()
    end
    FocusManager.setGui = Utils.appendedFunction(FocusManager.setGui, function(_, gui)
        if gui ~= nil and gui ~= "ingameMenu" and gui ~= "InGameMenu" then
            return
        end
        ContractManager.guard("Settings tab focus", registerFocus)
    end)

    local currentGui = FocusManager.currentGui
    FocusManager:setGui(pageSettings.name)
    FocusManager:removeElement(cmPage)
    FocusManager:removeElement(cmTab)
    FocusManager:loadElementFromCustomValues(cmPage)
    FocusManager:loadElementFromCustomValues(cmTab)
    FocusManager:setGui(currentGui)
    page.settingsLayout:invalidateLayout()

    -- baslik ve ikon (stok updateSubCategoryPages bunlari okur)
    InGameMenuSettingsFrame.SUB_CATEGORY.CONTRACTMANAGER = pos
    InGameMenuSettingsFrame.HEADER_SLICES[pos] = "gui.icon_ingameMenu_contracts"
    InGameMenuSettingsFrame.HEADER_TITLES[pos] = "cm_tabTitle"
    Tab.registerGlobalText("cm_tabTitle")

    -- sayfa acilisi: yetki + degerler + istatistik istegi
    pageSettings.onFrameOpen = Utils.appendedFunction(pageSettings.onFrameOpen, function(frame)
        local texts = frame.subCategoryPaging.texts
        Tab.modState = Tab.findPagingState(texts, InGameMenuSettingsFrame.SUB_CATEGORY.CONTRACTMANAGER) or #texts
        ContractManager.guard("Settings tab open", function()
            Tab:populate()
            Tab:requestStats()
            frame:updateAlternatingElements(page.settingsLayout)
            Tab.fixMissingTexts(frame, "cm_tabTitle")
        end)
    end)

    -- alt kategori degisimi: kaydirici ve odak baglantilari
    pageSettings.subCategoryPaging.onClickCallback = Utils.overwrittenFunction(pageSettings.subCategoryPaging.onClickCallback,
        function(frame, superFunc, state)
            local result = superFunc(frame, state)
            local value = frame.subCategoryPaging.texts[state]
            if value ~= nil and tonumber(value) == InGameMenuSettingsFrame.SUB_CATEGORY.CONTRACTMANAGER then
                -- hatamiz oyunun alt sekme gecisini bozmasin (kanca siniri korumali, 1.26.0.0)
                ContractManager.guard("Settings tab paging", function()
                    local layout = page.settingsLayout
                    frame.settingsSlider:setDataElement(layout)
                    Tab.fixMissingTexts(frame, "cm_tabTitle")
                    if #layout.elements > 0 then
                        FocusManager:linkElements(frame.subCategoryPaging, FocusManager.TOP, layout.elements[#layout.elements].elements[1])
                        FocusManager:linkElements(frame.subCategoryPaging, FocusManager.BOTTOM, layout:findFirstFocusable(true))
                    end
                end)
            end
            return result
        end)
end

function Tab:init()
    if self.built then
        return true
    end
    if g_gui == nil or g_inGameMenu == nil or g_inGameMenu.pageSettings == nil or InGameMenuSettingsFrame == nil then
        ContractManager.warning("Settings tab: in-game menu not available, tab skipped")
        return false
    end

    local xmlPath = ContractManager.MOD_DIRECTORY .. "gui/SettingsPage.xml"
    if not fileExists(xmlPath) then
        ContractManager.error("Settings tab: '%s' missing", xmlPath)
        return false
    end

    local ok, err = ContractManager.attempt(function()
        self.page = ContractManagerSettingsPage.new()
        local loaded = g_gui:loadGui(xmlPath, "ContractManagerSettingsFrame", self.page)
        if loaded == nil and self.page.cmPage == nil then
            error("loadGui returned nil")
        end
        self:insertIntoSettingsPage()
    end)

    if not ok then
        ContractManager.error("Settings tab could not be installed: %s", tostring(err))
        return false
    end

    self.built = true
    ContractManager.info("Settings tab installed at sub category %d (%d controls)", self.pageNr or 0, #self.controls)
    return true
end

if g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_START ~= nil then
    g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function()
        Tab:init()
    end, Tab)
    g_messageCenter:subscribe(ContractManager.MESSAGE_SETTINGS_CHANGED, function()
        if Tab.built then
            ContractManager.guard("Settings tab refresh", Tab.populate, Tab)
        end
    end, Tab)
end
