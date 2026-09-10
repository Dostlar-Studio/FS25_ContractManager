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
        pcall(g_i18n.setText, g_i18n, key, value)
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
-- kontrol tanimlari (saf)
-- ---------------------------------------------------------------------------

-- kind: bool | range | choice. zero: 0 degeri icin l10n etiketi. onlyIf: "betterContracts"
Tab.SPEC = {
    { section = "cm_secGuard" },
    { id = "guard.enabled", kind = "bool" },
    { id = "guard.blockCancelAfterProgress", kind = "bool" },
    { id = "guard.confiscateOnFail", kind = "bool" },

    { section = "cm_secReward" },
    { id = "reward.multiplier", kind = "range", min = 0.5, max = 5, step = 0.05, format = "x%.2f" },
    { id = "reward.failPenaltyPercent", kind = "range", min = 0, max = 100, step = 5, format = "%d %%", zero = "cm_valNone" },
    { id = "reward.leaseCostMultiplier", kind = "range", min = 0, max = 3, step = 0.1, format = "x%.1f", zero = "cm_valFree" },
    { id = "reward.penaltyStepPercent", kind = "range", min = 0, max = 25, step = 1, format = "+%d %%", zero = "cm_valNone" },
    { id = "reward.penaltyMaxPercent", kind = "range", min = 0, max = 100, step = 5, format = "%d %%" },
    { id = "reward.partialEnabled", kind = "bool" },
    { id = "reward.partialMinCompletion", kind = "range", min = 0, max = 100, step = 5, format = "%d %%", zero = "cm_valNone" },
    { id = "reward.partialFactor", kind = "range", min = 0, max = 100, step = 5, format = "%d %%", zero = "cm_valNone" },
    { id = "reward.min", kind = "range", min = 0, max = 100000, step = 2500, format = "money", zero = "cm_valNone" },
    { id = "reward.max", kind = "range", min = 0, max = 500000, step = 10000, format = "money", zero = "cm_valNone" },

    { section = "cm_secLimits" },
    { id = "limits.maxActivePerFarm", kind = "range", min = 0, max = 20, step = 1, format = "%d", zero = "cm_valUnlimited" },
    { id = "limits.quotaPerDay", kind = "range", min = 0, max = 20, step = 1, format = "%d", zero = "cm_valNone" },
    { id = "limits.quotaPerMonth", kind = "range", min = 0, max = 100, step = 5, format = "%d", zero = "cm_valNone" },

    { section = "cm_secGeneration" },
    { id = "generation.maxTotal", kind = "range", min = 0, max = 80, step = 5, format = "%d", zero = "cm_valGameDefault" },
    { id = "generation.maxPerType", kind = "range", min = 0, max = 20, step = 1, format = "%d", zero = "cm_valGameDefault" },
    { id = "generation.refreshMultiplier", kind = "range", min = 0.25, max = 4, step = 0.25, format = "x%.2f" },
    { id = "generation.cooldownPerFieldHours", kind = "range", min = 0, max = 240, step = 6, format = "%d h", zero = "cm_valNone" },

    { section = "cm_secDuration" },
    { id = "duration.multiplier", kind = "range", min = 0.5, max = 4, step = 0.25, format = "x%.2f" },
    { id = "duration.warnAtMinutes", kind = "choice",
      values = { "", "30,10", "60,15", "120,30", "240,60" },
      labels = { "cm_valNone", "30 / 10", "60 / 15", "120 / 30", "240 / 60" } },

    { section = "cm_secReputation" },
    { id = "reputation.enabled", kind = "bool" },
    { id = "reputation.gainComplete", kind = "range", min = 0, max = 50, step = 1, format = "+%d" },
    { id = "reputation.lossFail", kind = "range", min = 0, max = 50, step = 1, format = "-%d" },
    { id = "reputation.lossCancel", kind = "range", min = 0, max = 50, step = 1, format = "-%d" },
    { id = "reputation.lossTimeout", kind = "range", min = 0, max = 50, step = 1, format = "-%d" },
    { id = "reputation.maxPoints", kind = "range", min = 50, max = 500, step = 50, format = "%d" },
    { id = "reputation.rewardBonusMaxPercent", kind = "range", min = 0, max = 100, step = 5, format = "%d %%", zero = "cm_valNone" },
    { id = "reputation.extraSlotAt", kind = "range", min = 0, max = 200, step = 10, format = "%d", zero = "cm_valNone" },

    { section = "cm_secReservation" },
    { id = "reservation.enabled", kind = "bool" },
    { id = "reservation.minutes", kind = "range", min = 1, max = 60, step = 1, format = "%d min" },

    { section = "cm_secPartnership" },
    { id = "partnership.enabled", kind = "bool" },
    { id = "partnership.maxPartners", kind = "range", min = 1, max = 4, step = 1, format = "%d" },
    { id = "partnership.inviteMinutes", kind = "range", min = 1, max = 30, step = 1, format = "%d min" },

    { section = "cm_secChain" },
    { id = "chain.enabled", kind = "bool" },
    { id = "chain.bonusPercent", kind = "range", min = 0, max = 50, step = 5, format = "+%d %%", zero = "cm_valNone" },
    { id = "chain.windowDays", kind = "range", min = 0, max = 14, step = 1, format = "%d", zero = "cm_valUnlimited" },
    { id = "npc.enabled", kind = "bool" },
    { id = "npc.percentPerJob", kind = "range", min = 0, max = 10, step = 1, format = "+%d %%", zero = "cm_valNone" },
    { id = "npc.maxPercent", kind = "range", min = 0, max = 50, step = 5, format = "+%d %%", zero = "cm_valNone" },

    { section = "cm_secLease" },
    { id = "lease.enabled", kind = "bool" },
    { id = "lease.minReputation", kind = "range", min = 0, max = 200, step = 10, format = "%d", zero = "cm_valNone" },

    { section = "cm_secPricing" },
    { id = "pricing.distanceEnabled", kind = "bool" },
    { id = "pricing.distancePercentPerKm", kind = "range", min = 0, max = 30, step = 1, format = "+%d %%/km", zero = "cm_valNone" },
    { id = "pricing.distanceMaxPercent", kind = "range", min = 0, max = 100, step = 5, format = "+%d %%", zero = "cm_valNone" },
    { id = "pricing.smallFieldEnabled", kind = "bool" },
    { id = "pricing.smallFieldRefHa", kind = "range", min = 0.5, max = 10, step = 0.5, format = "%.1f ha" },
    { id = "pricing.smallFieldMaxPercent", kind = "range", min = 0, max = 100, step = 5, format = "+%d %%", zero = "cm_valNone" },
    { id = "pricing.typeDifficultyEnabled", kind = "bool" },

    { section = "cm_secSchedule" },
    { id = "schedule.enabled", kind = "bool" },
    { id = "schedule.weekendBonusPercent", kind = "range", min = 0, max = 100, step = 5, format = "+%d %%", zero = "cm_valNone" },
    { id = "schedule.happyHourStart", kind = "range", min = 0, max = 23, step = 1, format = "%02d:00" },
    { id = "schedule.happyHourEnd", kind = "range", min = 0, max = 23, step = 1, format = "%02d:00" },
    { id = "schedule.happyHourBonusPercent", kind = "range", min = 0, max = 100, step = 5, format = "+%d %%", zero = "cm_valNone" },

    { section = "cm_secMap" },
    { id = "map.showReserved", kind = "bool" },
    { id = "map.showAvailable", kind = "bool" },

    { section = "cm_secInterface" },
    { id = "ui.managePage", kind = "bool" },

    { section = "cm_secIntegrations" },
    { id = "integrations.discord", kind = "bool" },

}

Tab.TYPE_WEIGHT_SPEC = { kind = "range", min = 0, max = 3, step = 0.25, format = "x%.2f", zero = "cm_valNever" }

---Bir spec bu oturumda gosterilsin mi?
function Tab.isSpecVisible(spec)
    if spec.onlyIf == "betterContracts" then
        return ContractManager:isBetterContractsLoaded()
    end
    return true
end

---range spec icin secenek sayisi
function Tab.getRangeCount(spec)
    return math.floor((spec.max - spec.min) / spec.step + 0.5) + 1
end

function Tab.formatValue(spec, value)
    if spec.zero ~= nil and value == 0 then
        return text(spec.zero, "-")
    end
    if spec.format == "money" then
        if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
            local s = g_i18n:formatMoney(value, 0, true, true)
            if s ~= nil then
                return s
            end
        end
        return tostring(value)
    end
    local ok, s = pcall(string.format, spec.format or "%s", value)
    return ok and s or tostring(value)
end

---kontrolun secenek metinleri
function Tab.buildTexts(spec)
    local texts = {}
    if spec.kind == "range" then
        for i = 1, Tab.getRangeCount(spec) do
            texts[i] = Tab.formatValue(spec, spec.min + (i - 1) * spec.step)
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

function Tab.valueToState(spec, value)
    if spec.kind == "bool" then
        return value and 2 or 1
    elseif spec.kind == "range" then
        if type(value) ~= "number" then
            value = spec.min
        end
        local state = math.floor((value - spec.min) / spec.step + 0.5) + 1
        return math.max(1, math.min(Tab.getRangeCount(spec), state))
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

function Tab.stateToValue(spec, state)
    if spec.kind == "bool" then
        return state == 2
    elseif spec.kind == "range" then
        local value = spec.min + (state - 1) * spec.step
        -- kayan nokta gurultusunu adim hassasiyetine yuvarla
        local digits = 0
        local s = spec.step
        while s < 1 and digits < 6 do s = s * 10; digits = digits + 1 end
        local factor = 10 ^ digits
        return math.floor(value * factor + 0.5) / factor
    elseif spec.kind == "choice" then
        return spec.values[state] or spec.values[1]
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- deger erisimi: "type:<ad>:enabled" / "type:<ad>:weight" veya ayar id'si
-- ---------------------------------------------------------------------------

function Tab.parseTypeKey(key)
    local name, field = string.match(key or "", "^type:(.+):(%a+)$")
    return name, field
end

function Tab.getValue(key)
    local name, field = Tab.parseTypeKey(key)
    if name ~= nil then
        local enabled, weight = S():getTypeConfig(name)
        if field == "enabled" then return enabled end
        return weight
    end
    return S():get(key)
end

---Degeri ayarlara yazar (dogrulama Settings'te). Donus: uygulanan deger.
function Tab.applyValue(key, value)
    local name, field = Tab.parseTypeKey(key)
    if name ~= nil then
        local enabled, weight = S():getTypeConfig(name)
        if field == "enabled" then
            S():setTypeConfig(name, value == true, weight)
        else
            S():setTypeConfig(name, enabled, tonumber(value) or weight)
        end
        local e, w = S():getTypeConfig(name)
        if field == "enabled" then return e end
        return w
    end
    return S():set(key, value)
end

---Sunucuda: yetkili degisikligi uygula ve herkese yay.
---DEGISIM KAPISI: kaydiracta gezinmek her adimda ayri bir istek gonderiyor; her biri
---TUM ayar tablosunu butun istemcilere yayinliyor ve orada 127 kontrolluk arayuzu
---yeniden kuruyordu. Sunucu logunda calisma kisminin %57'si tek bir satirdi
---(2026-09-09 incelemesi). Deger gercekten degismediyse hicbir sey yapilmaz.
function Tab.applyOnServer(key, value)
    local before = Tab.getValue(key)
    local applied = Tab.applyValue(key, value)
    if before ~= nil and applied ~= nil and before == applied then
        return applied
    end
    if ContractManagerSyncEvent ~= nil then
        ContractManagerSyncEvent.broadcastState()
    end
    ContractManager.publish(ContractManager.MESSAGE_SETTINGS_CHANGED, key, applied)
    ContractManager.info("Setting '%s' -> %s", tostring(key), tostring(applied))
    return applied
end

function Tab.getIsLocalAdmin()
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

-- ---------------------------------------------------------------------------
-- kontrol degisimi
-- ---------------------------------------------------------------------------

function Tab:onControlChanged(state, element)
    local spec = element ~= nil and element.cmSpec or nil
    if spec == nil then
        return
    end
    if not Tab.getIsLocalAdmin() then
        self:populate() -- yetkisiz: gorunumu geri al
        return
    end
    local value = Tab.stateToValue(spec, state)
    if ContractManagerSettingChangeEvent ~= nil then
        ContractManagerSettingChangeEvent.send(spec.key, value)
    else
        Tab.applyOnServer(spec.key, value)
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

function Tab:createSection(i18nKey)
    local page = self.page
    local header = page.subTitlePrefab:clone(page.settingsLayout)
    header:setText(text(i18nKey))
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
    option.cmSpec = { key = key, kind = spec.kind, min = spec.min, max = spec.max, step = spec.step,
        format = spec.format, zero = spec.zero, values = spec.values, labels = spec.labels }
    if spec.kind ~= "bool" then
        option:setTexts(Tab.buildTexts(spec))
    end

    local title = box.elements[2]
    local name, field = Tab.parseTypeKey(key)
    if name ~= nil then
        local typeTitle = text("cm_type_" .. name, name)
        title:setText(string.format("%s: %s", typeTitle, text(field == "enabled" and "cm_typeEnabled" or "cm_typeWeight")))
    else
        title:setText(text(self.PREFIX .. key:gsub("%.", "_")))
    end

    local tooltip = option.elements[1]
    if tooltip ~= nil and tooltip.setText ~= nil then
        if name ~= nil then
            tooltip:setText(text(field == "enabled" and "cm_typeEnabled_tooltip" or "cm_typeWeight_tooltip", ""))
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
                self:createSection(spec.section)
            else
                self:createControl(spec, spec.id)
            end
        end
    end

    -- kontrat turleri (dinamik)
    if g_missionManager ~= nil and g_missionManager.missionTypes ~= nil and #g_missionManager.missionTypes > 0 then
        self:createSection("cm_secTypes")
        for _, missionType in ipairs(g_missionManager.missionTypes) do
            local name = missionType.name
            self:createControl({ kind = "bool" }, "type:" .. name .. ":enabled")
            self:createControl(self.TYPE_WEIGHT_SPEC, "type:" .. name .. ":weight")
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
    local isAdmin = Tab.getIsLocalAdmin()
    if self.page ~= nil and self.page.cmNoPermissionText ~= nil then
        self.page.cmNoPermissionText:setVisible(not isAdmin)
    end
    for _, control in ipairs(self.controls) do
        if control.cmAdminOnly then
            control:setVisible(isAdmin)
        end
        if control.cmOption ~= nil and isAdmin then
            local spec = control.cmOption.cmSpec
            local state = Tab.valueToState(spec, Tab.getValue(spec.key))
            control.cmOption:setState(state)
        end
    end
    self:populateStats()
    if self.page ~= nil and self.page.settingsLayout ~= nil then
        self.page.settingsLayout:invalidateLayout()
    end
end

local FINISH_STATE_KEYS = { "cm_stateNone", "cm_stateSuccess", "cm_stateFailed", "cm_stateCanceled", "cm_stateTimedOut" }

function Tab.formatMoney(value)
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        local s = g_i18n:formatMoney(value or 0, 0, true, true)
        if s ~= nil then
            return s
        end
    end
    return tostring(math.floor((value or 0) + 0.5))
end

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
        lines[#lines + 1] = string.format("%s: %d (%s +%d%%%s)", text("cm_statReputation"), rep, text("cm_statBonus"), math.floor(bonus + 0.5),
            extra > 0 and (", " .. text("cm_statExtraSlot")) or "")
    end
    lines[#lines + 1] = string.format("%s: %d", text("cm_statCompleted"), stats.completed or 0)
    lines[#lines + 1] = string.format("%s: %d", text("cm_statFailed"), stats.failed or 0)
    lines[#lines + 1] = string.format("%s: %d", text("cm_statCanceled"), stats.canceled or 0)
    lines[#lines + 1] = string.format("%s: %d", text("cm_statTimedOut"), stats.timedOut or 0)
    lines[#lines + 1] = string.format("%s: %s", text("cm_statEarned"), Tab.formatMoney(stats.earned))
    lines[#lines + 1] = string.format("%s: %s", text("cm_statPenalties"), Tab.formatMoney(stats.penalties))
    for _, entry in ipairs(history or {}) do
        local stateKey = FINISH_STATE_KEYS[(entry.finishState or 0) + 1] or "cm_stateNone"
        lines[#lines + 1] = string.format("%s %d · %s · %s · %s",
            text("cm_day"), entry.finishedDay or 0,
            text("cm_type_" .. tostring(entry.typeName), tostring(entry.typeName)),
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
        pcall(function()
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
    FocusManager.setGui = Utils.appendedFunction(FocusManager.setGui, function(_, gui)
        for _, control in ipairs(controls) do
            if not control.focusId or not FocusManager.currentFocusData.idToElementMapping[control.focusId] then
                FocusManager:loadElementFromCustomValues(control, nil, nil, false, false)
            end
        end
        page.settingsLayout:invalidateLayout()
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
        Tab.modState = #frame.subCategoryPaging.texts
        pcall(function()
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
                local layout = page.settingsLayout
                frame.settingsSlider:setDataElement(layout)
                pcall(Tab.fixMissingTexts, frame, "cm_tabTitle")
                if #layout.elements > 0 then
                    FocusManager:linkElements(frame.subCategoryPaging, FocusManager.TOP, layout.elements[#layout.elements].elements[1])
                    FocusManager:linkElements(frame.subCategoryPaging, FocusManager.BOTTOM, layout:findFirstFocusable(true))
                end
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

    local ok, err = pcall(function()
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
            pcall(Tab.populate, Tab)
        end
    end, Tab)
end
