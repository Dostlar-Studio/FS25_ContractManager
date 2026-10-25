--
-- FS25_ContractManager - Settings
--
-- modSettings/FS25_ContractManager.xml okur/yazar. TEK SEMA (1.27.0.0): her ayarin verisi (tur,
-- varsayilan, sinir), ayar ekranindaki bolumu ve secenek listesi SPEC'te. Ayar ekrani (SettingsTab),
-- web paneli (DiscordBridgePanel) ve ag senkronu buradan okur. 1.27.0.0'a kadar ekranin sinirlari
-- SettingsTab'da ikinci kez yaziliydi ve farkliydi: web panelinden 6 yapilan aylik kota ekranda 5
-- gorunuyor, dokununca kayiyordu; odul tavani dosyada 10 milyona izin verip ekranda 500 binde kaliyordu.
-- Bozuk deger varsayilana duser ve loglanir.
-- Diske yazma yalnizca dirty iken olur: degisiklikten SAVE_DELAY_MS sonra (markDirty ->
-- updateSaveTimer) ve ayrica oyun kaydinda (saveIfDirty). Her degisiklikte hemen yazmak
-- oyunu kasar (kaydirac suruklerken her adim bir yazma olurdu), yalniz oyun kaydinda
-- yazmak ise degisikligi kaybettirir: sunucu gece kayit ALMADAN yeniden basliyor.
--
-- Kontrat tur ayarlari (TYPE_FIELDS: enabled/weight/max) dinamiktir: tur adlari oyun icinde
-- g_missionManager.missionTypes'tan gelir; dosyada olmayan tur varsayilanla doner.
--
-- Ayar servisi de burada (1.27.0.0'a kadar GUI dosyasindaydi): anahtar cozumu ("type:<ad>:<alan>"),
-- deger okuma/yazma ve sunucuda uygulayip yayinlama. Ag olaylari ve web paneli GUI'ye bagli degil.
--

ContractManagerSettings = {
    FILENAME = "FS25_ContractManager.xml",
    ROOT = "contractManager",
    FILE_VERSION = 1,
    values = {},
    types = {},          -- name -> { enabled = bool, weight = number, max = number }
    dirty = false,
    loaded = false,
    SAVE_DELAY_MS = 3000,   -- degisiklikten sonra diske yazmadan once beklenen sure
    saveTimer = nil,        -- nil = bekleyen yazma yok
}

local Settings = ContractManagerSettings
local BOOL, INT, FLOAT, STRING = "bool", "int", "float", "string"

-- ---------------------------------------------------------------------------
-- secenek listeleri (ayar ekrani). Liste ayarin [min, max] araligini UCTAN UCA kapsar; kalabalik
-- araliklarda adim buyur. Listede olmayan gecerli bir deger (dosyadan ya da web panelinden) ekranda
-- kendi yerine eklenerek gosterilir (SettingsTab.valuesWith).
-- ---------------------------------------------------------------------------

---from..to arasi esit adimlar; kayan nokta gurultusu adim hassasiyetine yuvarlanir (saf)
function Settings.steps(from, to, step)
    local digits = 0
    local s = step
    while s < 1 and digits < 6 do
        s = s * 10
        digits = digits + 1
    end
    local factor = 10 ^ digits
    local list = {}
    for i = 0, math.floor((to - from) / step + 0.5) do
        list[#list + 1] = math.floor((from + i * step) * factor + 0.5) / factor
    end
    return list
end

---listeleri sirayla birlestir (saf)
function Settings.join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, value in ipairs(list) do
            out[#out + 1] = value
        end
    end
    return out
end

local steps, join = Settings.steps, Settings.join

-- ---------------------------------------------------------------------------
-- sema. Sira = ayar ekranindaki sira = ag senkronundaki sira. id "grup.ad"; dosya anahtari "grup#ad".
-- ui: range icin `step` (min..max esit adim) ya da `values` (acik liste), `format`, `zero` (0'in etiketi);
--     metin secimi icin `values` + `labels`. mpOnly: yalnizca cok oyunculu oyunda anlamli.
-- ---------------------------------------------------------------------------

Settings.SPEC = {}

local function group(section, entries)
    for _, spec in ipairs(entries) do
        spec.section = section
        spec.xml = spec.xml or (string.gsub(spec.id, "%.", "#", 1))
        Settings.SPEC[#Settings.SPEC + 1] = spec
    end
end

local COUNT_50 = join(steps(0, 20, 1), { 25, 30, 40, 50 })
local POINTS_100 = join(steps(0, 50, 1), steps(60, 100, 10))
local POINTS_1000 = join(steps(0, 200, 10), { 250, 300, 400, 500, 750, 1000 })

group("cm_secGuard", {
    { id = "guard.enabled",                  type = BOOL, default = true },
    { id = "guard.blockCancelAfterProgress", type = BOOL, default = true },
    { id = "guard.confiscateOnFail",         type = BOOL, default = true },
    { id = "guard.warnProductLoss",          type = BOOL, default = true },
})

group("cm_secReward", {
    { id = "reward.multiplier", type = FLOAT, default = 1.25, min = 0.1, max = 10,
      ui = { values = join({ 0.1, 0.2, 0.3, 0.4 }, steps(0.5, 5, 0.05), { 5.5, 6, 7, 8, 9, 10 }), format = "x%.2f" } },
    { id = "reward.failPenaltyPercent", type = INT, default = 10, min = 0, max = 100,
      ui = { step = 5, format = "%d %%", zero = "cm_valNone" } },
    { id = "reward.leaseCostMultiplier", type = FLOAT, default = 1.0, min = 0, max = 10,
      ui = { values = join(steps(0, 3, 0.1), { 4, 5, 7.5, 10 }), format = "x%.1f", zero = "cm_valFree" } },
    -- ardisik basarisizlik basina ek ceza
    { id = "reward.penaltyStepPercent", type = INT, default = 0, min = 0, max = 50,
      ui = { step = 1, format = "+%d %%", zero = "cm_valNone" } },
    { id = "reward.penaltyMaxPercent", type = INT, default = 50, min = 0, max = 100,
      ui = { step = 5, format = "%d %%" } },
    { id = "reward.partialEnabled", type = BOOL, default = false },
    { id = "reward.partialMinCompletion", type = INT, default = 50, min = 0, max = 100,
      ui = { step = 5, format = "%d %%", zero = "cm_valNone" } },
    { id = "reward.partialFactor", type = INT, default = 100, min = 0, max = 100,
      ui = { step = 5, format = "%d %%", zero = "cm_valNone" } },
    { id = "reward.min", type = INT, default = 0, min = 0, max = 10000000,
      ui = { values = join(steps(0, 100000, 2500), { 125000, 150000, 200000, 250000, 500000, 1000000, 2500000, 5000000, 10000000 }),
             format = "money", zero = "cm_valNone" } },
    -- 0 = tavan yok
    { id = "reward.max", type = INT, default = 0, min = 0, max = 10000000,
      ui = { values = join(steps(0, 500000, 10000), { 600000, 750000, 1000000, 1500000, 2000000, 3000000, 5000000, 10000000 }),
             format = "money", zero = "cm_valNone" } },
})

-- hasattan ciftlige kalan pay: HarvestMission.SUCCESS_FACTOR / BaleMission.FILL_SUCCESS_FACTOR
group("cm_secHarvest", {
    { id = "harvest.keepPercent",     type = INT, default = 7,  min = 0, max = 60, ui = { step = 1, format = "%d %%", zero = "cm_valNone" } },
    { id = "harvest.keepPercentBale", type = INT, default = 10, min = 0, max = 60, ui = { step = 1, format = "%d %%", zero = "cm_valNone" } },
    -- cim tarlasina HASAT kontrati: bicme makinesi giremez ("araziye erisim yok"); kapaliyken uretilmez
    { id = "harvest.grassContracts", type = BOOL, default = false },
})

group("cm_secLimits", {
    -- 0 = sinirsiz
    { id = "limits.maxActivePerFarm", type = INT, default = 3, min = 0, max = 50,
      ui = { values = COUNT_50, format = "%d", zero = "cm_valUnlimited" } },
    -- 0 = kapali
    { id = "limits.quotaPerDay", type = INT, default = 0, min = 0, max = 50,
      ui = { values = COUNT_50, format = "%d", zero = "cm_valNone" } },
    { id = "limits.quotaPerMonth", type = INT, default = 0, min = 0, max = 200,
      ui = { values = join(steps(0, 50, 1), steps(55, 100, 5), { 125, 150, 175, 200 }), format = "%d", zero = "cm_valNone" } },
})

group("cm_secGeneration", {
    -- 0 = oyun varsayilani. Oyunun tavani 80 (Generation.MAX_TOTAL_CAP); 1.27.0.0'a kadar dosya 200'e izin veriyordu
    -- ama 80 ustu zaten 80 uygulaniyordu.
    { id = "generation.maxTotal", type = INT, default = 0, min = 0, max = 80,
      ui = { step = 5, format = "%d", zero = "cm_valGameDefault" } },
    -- 0 = oyun varsayilani; turun kendi siniri (TYPE_FIELDS.max) bunu ezer
    { id = "generation.maxPerType", type = INT, default = 0, min = 0, max = 50,
      ui = { values = COUNT_50, format = "%d", zero = "cm_valGameDefault" } },
    { id = "generation.refreshMultiplier", type = FLOAT, default = 1.0, min = 0.1, max = 10,
      ui = { values = join({ 0.1 }, steps(0.25, 4, 0.25), { 5, 6, 8, 10 }), format = "x%.2f" } },
    { id = "generation.cooldownPerFieldHours", type = INT, default = 0, min = 0, max = 720,
      ui = { values = join(steps(0, 240, 6), { 288, 336, 480, 720 }), format = "hours", zero = "cm_valNone" } },
})

group("cm_secDuration", {
    { id = "duration.multiplier", type = FLOAT, default = 1.0, min = 0.1, max = 10,
      ui = { values = join({ 0.1, 0.25 }, steps(0.5, 4, 0.25), { 5, 6, 8, 10 }), format = "x%.2f" } },
    { id = "duration.warnAtMinutes", type = STRING, default = "60,15",
      ui = { values = { "", "30,10", "60,15", "120,30", "240,60" },
             labels = { "cm_valNone", "30 / 10", "60 / 15", "120 / 30", "240 / 60" } } },
    -- 1.27.0.0: biten ama kapatilmayan kontrat bu kadar oyun saati sonra kendiliginden kapanir (0 = hic).
    -- Kapatilmayan basarisiz kontratin cezasi da hic kesilmiyordu (AutoClose.lua).
    { id = "duration.autoCloseHours", type = INT, default = 48, min = 0, max = 720,
      ui = { values = join({ 0 }, steps(6, 48, 6), { 72, 96, 120, 168, 240, 336, 720 }), format = "hours", zero = "cm_valNever" } },
})

group("cm_secReputation", {
    { id = "reputation.enabled", type = BOOL, default = true },
    { id = "reputation.gainComplete", type = INT, default = 10, min = 0, max = 100, ui = { values = POINTS_100, format = "+%d" } },
    { id = "reputation.lossFail",     type = INT, default = 20, min = 0, max = 100, ui = { values = POINTS_100, format = "-%d" } },
    { id = "reputation.lossCancel",   type = INT, default = 15, min = 0, max = 100, ui = { values = POINTS_100, format = "-%d" } },
    { id = "reputation.lossTimeout",  type = INT, default = 20, min = 0, max = 100, ui = { values = POINTS_100, format = "-%d" } },
    { id = "reputation.maxPoints", type = INT, default = 100, min = 10, max = 1000,
      ui = { values = join({ 10, 25 }, steps(50, 500, 50), { 600, 700, 800, 900, 1000 }), format = "%d" } },
    { id = "reputation.rewardBonusMaxPercent", type = INT, default = 25, min = 0, max = 100,
      ui = { step = 5, format = "%d %%", zero = "cm_valNone" } },
    -- 0 = kapali
    { id = "reputation.extraSlotAt", type = INT, default = 50, min = 0, max = 1000, ui = { values = POINTS_1000, format = "%d", zero = "cm_valNone" } },
})

group("cm_secReservation", {
    { id = "reservation.enabled", type = BOOL, default = true, mpOnly = true },
    { id = "reservation.minutes", type = INT, default = 10, min = 1, max = 120, mpOnly = true,
      ui = { values = join(steps(1, 60, 1), { 75, 90, 105, 120 }), format = "minutes" } },
})

group("cm_secPartnership", {
    { id = "partnership.enabled", type = BOOL, default = false, mpOnly = true },
    { id = "partnership.maxPartners", type = INT, default = 1, min = 1, max = 4, mpOnly = true, ui = { step = 1, format = "%d" } },
    { id = "partnership.inviteMinutes", type = INT, default = 10, min = 1, max = 60, mpOnly = true,
      ui = { values = join(steps(1, 30, 1), { 35, 40, 45, 50, 55, 60 }), format = "minutes" } },
})

group("cm_secChain", {
    { id = "chain.enabled", type = BOOL, default = false },
    { id = "chain.bonusPercent", type = INT, default = 15, min = 0, max = 100, ui = { step = 5, format = "+%d %%", zero = "cm_valNone" } },
    -- 0 = sinirsiz
    { id = "chain.windowDays", type = INT, default = 3, min = 0, max = 30,
      ui = { values = join(steps(0, 14, 1), { 21, 30 }), format = "%d", zero = "cm_valUnlimited" } },
    { id = "npc.enabled", type = BOOL, default = false },
    { id = "npc.percentPerJob", type = INT, default = 2,  min = 0, max = 20,  ui = { step = 1, format = "+%d %%", zero = "cm_valNone" } },
    { id = "npc.maxPercent",    type = INT, default = 20, min = 0, max = 100, ui = { step = 5, format = "+%d %%", zero = "cm_valNone" } },
})

group("cm_secLease", {
    { id = "lease.enabled", type = BOOL, default = true },
    -- 0 = kapali
    { id = "lease.minReputation", type = INT, default = 0, min = 0, max = 1000, ui = { values = POINTS_1000, format = "%d", zero = "cm_valNone" } },
})

group("cm_secPricing", {
    { id = "pricing.distanceEnabled", type = BOOL, default = false },
    { id = "pricing.distancePercentPerKm", type = INT, default = 5,  min = 0, max = 50,  ui = { step = 1, format = "+%d %%/km", zero = "cm_valNone" } },
    { id = "pricing.distanceMaxPercent",   type = INT, default = 30, min = 0, max = 200, ui = { step = 5, format = "+%d %%", zero = "cm_valNone" } },
    { id = "pricing.smallFieldEnabled", type = BOOL, default = false },
    { id = "pricing.smallFieldRefHa", type = FLOAT, default = 2.0, min = 0.5, max = 20, ui = { step = 0.5, format = "area" } },
    { id = "pricing.smallFieldMaxPercent", type = INT, default = 20, min = 0, max = 100, ui = { step = 5, format = "+%d %%", zero = "cm_valNone" } },
    { id = "pricing.typeDifficultyEnabled", type = BOOL, default = false },
})

group("cm_secSchedule", {
    { id = "schedule.enabled", type = BOOL, default = false },
    { id = "schedule.weekendBonusPercent", type = INT, default = 25, min = 0, max = 200, ui = { step = 5, format = "+%d %%", zero = "cm_valNone" } },
    { id = "schedule.happyHourStart", type = INT, default = 20, min = 0, max = 23, ui = { step = 1, format = "%02d:00" } },
    { id = "schedule.happyHourEnd",   type = INT, default = 22, min = 0, max = 23, ui = { step = 1, format = "%02d:00" } },
    { id = "schedule.happyHourBonusPercent", type = INT, default = 0, min = 0, max = 200, ui = { step = 5, format = "+%d %%", zero = "cm_valNone" } },
})

group("cm_secMap", {
    { id = "map.showReserved",  type = BOOL, default = true, mpOnly = true },
    { id = "map.showAvailable", type = BOOL, default = false },
})

-- Arayuz: kenar cubugundaki "Kontrat Yonetimi" sayfasi. Kapatilinca sekme kaybolur
-- (TabbedMenu predicate + updatePages); stok Kontratlar sayfasi calismaya devam eder.
group("cm_secInterface", {
    { id = "ui.managePage", type = BOOL, default = true },
})

-- FS25_BetterContracts yukluyken kural katmani (odul/limit/uretim/sure) varsayilan olarak
-- geri cekilir; true yaparsan iki mod ust uste uygulanir (carpanlar carpilir).
group("cm_secCompat", {
    { id = "compat.overrideBetterContracts", type = BOOL, default = false },
})

group("cm_secIntegrations", {
    { id = "integrations.discord", type = BOOL, default = true },
})

Settings.SPEC_BY_ID = {}
---Yalnizca cok oyunculu oyunda anlamli ayarlar (1.25.0.0). Tek oyunculuda ETKILERI kapalidir ve ayar
---ekraninda sonuk gorunurler; KAYITLI DEGER DEGISMEZ (ayni ayar dosyasi cok oyunculuda kullanilirsa
---yoneticinin secimi yerinde kalir). SPEC'teki mpOnly isaretinden kurulur.
Settings.MP_ONLY = {}
for _, spec in ipairs(Settings.SPEC) do
    Settings.SPEC_BY_ID[spec.id] = spec
    if spec.mpOnly then
        Settings.MP_ONLY[spec.id] = true
    end
end

-- Kontrat turu basina alanlar. Anahtar "type:<tur adi>:<alan>" (ayar ekrani, web paneli, ag).
Settings.TYPE_FIELDS = {
    { name = "enabled", type = BOOL, default = true },
    { name = "weight", type = FLOAT, default = 1.0, min = 0, max = 10,
      ui = { values = join(steps(0, 3, 0.25), { 4, 5, 7.5, 10 }), format = "x%.2f", zero = "cm_valNever" } },
    -- 1.27.0.0: panoda bu turden en cok kac kontrat (0 = genel tur siniri, o da 0 ise oyun varsayilani).
    -- Ana sunucuda pano 30 kontratin 20'si hasatken oyuncularin yaptigi turler hic cikmiyordu.
    { name = "max", type = INT, default = 0, min = 0, max = 50,
      ui = { values = COUNT_50, format = "%d", zero = "cm_valGameDefault" } },
}
Settings.TYPE_FIELD_BY_NAME = {}
Settings.TYPE_DEFAULT = {}
for _, field in ipairs(Settings.TYPE_FIELDS) do
    Settings.TYPE_FIELD_BY_NAME[field.name] = field
    Settings.TYPE_DEFAULT[field.name] = field.default
end
Settings.TYPE_WEIGHT_MIN = Settings.TYPE_FIELD_BY_NAME.weight.min
Settings.TYPE_WEIGHT_MAX = Settings.TYPE_FIELD_BY_NAME.weight.max

---Ayarin (ya da tur alaninin) ekran secenek listesi; range olmayanda nil
function Settings.getUiValues(spec)
    local ui = spec ~= nil and spec.ui or nil
    if ui == nil or (spec.type ~= INT and spec.type ~= FLOAT) then
        return nil
    end
    if ui.values == nil and ui.step ~= nil then
        ui.values = steps(spec.min, spec.max, ui.step)
    end
    return ui.values
end

-- ---------------------------------------------------------------------------
-- sema (XML)
-- ---------------------------------------------------------------------------

local XML_TYPE = { [BOOL] = XMLValueType.BOOL, [INT] = XMLValueType.INT, [FLOAT] = XMLValueType.FLOAT, [STRING] = XMLValueType.STRING }

Settings.xmlSchema = XMLSchema.new("contractManagerSettings")
Settings.xmlSchema:register(XMLValueType.INT, Settings.ROOT .. "#version", "Dosya surumu", Settings.FILE_VERSION)
for _, spec in ipairs(Settings.SPEC) do
    Settings.xmlSchema:register(XML_TYPE[spec.type], Settings.ROOT .. "." .. spec.xml, spec.id, spec.default)
end
Settings.xmlSchema:register(XMLValueType.STRING, Settings.ROOT .. ".types.type(?)#name", "Kontrat turu adi")
for _, field in ipairs(Settings.TYPE_FIELDS) do
    Settings.xmlSchema:register(XML_TYPE[field.type], Settings.ROOT .. ".types.type(?)#" .. field.name, "Tur: " .. field.name, field.default)
end

-- ---------------------------------------------------------------------------
-- dogrulama
-- ---------------------------------------------------------------------------

---Degeri spec'e gore dogrular (ayar ya da tur alani). Donus: gecerli deger, duzeltildi mi
function Settings.sanitize(spec, value)
    if spec.type == BOOL then
        if type(value) == "boolean" then
            return value, false
        end
        return spec.default, true
    elseif spec.type == STRING then
        if type(value) == "string" then
            return value, false
        end
        return spec.default, true
    else
        if type(value) ~= "number" or value ~= value then -- NaN
            return spec.default, true
        end
        local clamped = value
        if spec.min ~= nil and clamped < spec.min then clamped = spec.min end
        if spec.max ~= nil and clamped > spec.max then clamped = spec.max end
        if spec.type == INT then
            clamped = math.floor(clamped + 0.5)
        end
        return clamped, clamped ~= value
    end
end

-- ---------------------------------------------------------------------------
-- erisim
-- ---------------------------------------------------------------------------

function Settings:resetToDefaults()
    self.values = {}
    for _, spec in ipairs(self.SPEC) do
        self.values[spec.id] = spec.default
    end
    self.types = {}
end

---Bu ayar bu oturumda kullanilabilir mi? (tek oyunculuda MP_ONLY ayarlar hayir)
function Settings:isAvailable(id)
    if Settings.MP_ONLY[id] and ContractManager ~= nil and ContractManager.isMultiplayer ~= nil then
        return ContractManager.isMultiplayer()
    end
    return true
end

function Settings:get(id)
    local value = self.values[id]
    if value == nil then
        local spec = self.SPEC_BY_ID[id]
        if spec == nil then
            ContractManager.warning("Unknown setting '%s'", tostring(id))
            return nil
        end
        return spec.default
    end
    return value
end

---Degeri dogrulayip yazar. Donus: uygulanan deger. Degisiklik varsa dirty olur.
function Settings:set(id, value)
    local spec = self.SPEC_BY_ID[id]
    if spec == nil then
        ContractManager.warning("Unknown setting '%s' ignored", tostring(id))
        return nil
    end
    local clean, fixed = self.sanitize(spec, value)
    if fixed then
        ContractManager.warning("Setting '%s' value %s adjusted to %s", id, tostring(value), tostring(clean))
    end
    if self.values[id] ~= clean then
        self.values[id] = clean
        self:markDirty()
    end
    return clean
end

---Tur ayari: enabled, weight, max (tanimsiz tur varsayilanla)
function Settings:getTypeConfig(typeName)
    local entry = self.types[typeName]
    local d = self.TYPE_DEFAULT
    if entry == nil then
        return d.enabled, d.weight, d.max
    end
    return entry.enabled, entry.weight, entry.max or d.max
end

---Tur ayarini dogrulayip yazar. `max` verilmezse (eski cagri bicimi) mevcut deger korunur.
function Settings:setTypeConfig(typeName, enabled, weight, max)
    if type(typeName) ~= "string" or typeName == "" then
        return
    end
    local fields = self.TYPE_FIELD_BY_NAME
    enabled = self.sanitize(fields.enabled, enabled)
    weight = self.sanitize(fields.weight, weight)
    local entry = self.types[typeName]
    if max == nil then
        max = entry ~= nil and entry.max or fields.max.default
    end
    max = self.sanitize(fields.max, max)
    if entry == nil or entry.enabled ~= enabled or entry.weight ~= weight or entry.max ~= max then
        self.types[typeName] = { enabled = enabled, weight = weight, max = max }
        self:markDirty()
    end
end

function Settings:getTypeValue(typeName, field)
    local enabled, weight, max = self:getTypeConfig(typeName)
    if field == "enabled" then return enabled end
    if field == "weight" then return weight end
    if field == "max" then return max end
    return nil
end

---Tek tur alanini yazar. Donus: uygulanan deger (bilinmeyen alan nil).
function Settings:setTypeValue(typeName, field, value)
    if self.TYPE_FIELD_BY_NAME[field] == nil then
        return nil
    end
    local enabled, weight, max = self:getTypeConfig(typeName)
    if field == "enabled" then
        enabled = value
    elseif field == "weight" then
        weight = tonumber(value) or weight
    else
        max = tonumber(value) or max
    end
    self:setTypeConfig(typeName, enabled, weight, max)
    return self:getTypeValue(typeName, field)
end

---Sirali tur adlari (dosya ve stream icin deterministik)
function Settings:getTypeNames()
    local names = {}
    for name in pairs(self.types) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-- ---------------------------------------------------------------------------
-- ayar servisi: anahtar = ayar id'si ya da "type:<ad>:<alan>"
-- ---------------------------------------------------------------------------

---"type:<ad>:<alan>" -> ad, alan. Bilinmeyen alan ya da ayar anahtari nil.
function Settings.parseTypeKey(key)
    local name, field = string.match(key or "", "^type:(.+):(%a+)$")
    if name == nil or Settings.TYPE_FIELD_BY_NAME[field] == nil then
        return nil
    end
    return name, field
end

---Anahtarin tanimi (ayar ya da tur alani; tur/sinir/ekran bilgisi). Bilinmeyen anahtar nil.
function Settings:getKeySpec(key)
    local name, field = Settings.parseTypeKey(key)
    if name ~= nil then
        return self.TYPE_FIELD_BY_NAME[field]
    end
    return self.SPEC_BY_ID[key]
end

function Settings:getValue(key)
    local name, field = Settings.parseTypeKey(key)
    if name ~= nil then
        return self:getTypeValue(name, field)
    end
    if self.SPEC_BY_ID[key] == nil then
        return nil
    end
    return self:get(key)
end

---Degeri yazar (dogrulama burada). Donus: uygulanan deger, bilinmeyen anahtar nil.
function Settings:applyValue(key, value)
    local name, field = Settings.parseTypeKey(key)
    if name ~= nil then
        return self:setTypeValue(name, field, value)
    end
    return self:set(key, value)
end

---Sunucuda: yetkili degisikligi uygula ve herkese yay.
---DEGISIM KAPISI: kaydiracta gezinmek her adimda ayri bir istek gonderiyor; her biri
---TUM ayar tablosunu butun istemcilere yayinliyor ve orada 127 kontrolluk arayuzu
---yeniden kuruyordu. Sunucu logunda calisma kisminin %57'si tek bir satirdi
---(2026-09-09 incelemesi). Deger gercekten degismediyse hicbir sey yapilmaz.
---Bilinmeyen anahtar yayin uretmez (1.27.0.0'a kadar "nil -> nil" yayinlaniyordu).
---`who`: degisikligi yapanin adi (oyuncu, "host" ya da "web: <ad>"). Log ve Discord olayi
---bunu tasir; "ayari kim degistirdi" sorusu canlida cevapsiz kalmisti (2026-09-17).
function Settings.applyOnServer(key, value, who)
    local self = Settings
    local before = self:getValue(key)
    local applied = self:applyValue(key, value)
    if applied == nil then
        return nil
    end
    if before ~= nil and before == applied then
        return applied
    end
    if ContractManagerSyncEvent ~= nil then
        ContractManagerSyncEvent.broadcastState()
    end
    who = (type(who) == "string" and who ~= "") and who or "unknown"
    ContractManager.publish(ContractManager.MESSAGE_SETTINGS_CHANGED, key, applied, who)
    ContractManager.info("Setting '%s': %s -> %s (changed by %s)",
        tostring(key), tostring(before), tostring(applied), who)
    return applied
end

-- ---------------------------------------------------------------------------
-- dosya
-- ---------------------------------------------------------------------------

function Settings:getPath()
    local directory = getUserProfileAppPath() .. "modSettings/"
    createFolder(directory)
    return directory .. self.FILENAME
end

function Settings:load()
    self:resetToDefaults()
    self.dirty = false

    local path = self:getPath()
    if not fileExists(path) then
        self.dirty = true
        self:save()
        ContractManager.info("Settings file created: %s", path)
        return
    end

    -- bozuk dosya oyunun XML katmaninda firlatabilir: korumali, varsayilanlarla devam
    local ok, xmlFile = ContractManager.guard("Settings file load", XMLFile.load, "contractManagerSettings", path, self.xmlSchema)
    if not ok or xmlFile == nil then
        ContractManager.warning("Settings file unreadable, defaults in use: %s", path)
        return
    end

    local fixedCount = 0
    for _, spec in ipairs(self.SPEC) do
        local raw = xmlFile:getValue(self.ROOT .. "." .. spec.xml)
        if raw ~= nil then
            local clean, fixed = self.sanitize(spec, raw)
            if fixed then
                fixedCount = fixedCount + 1
                ContractManager.warning("Setting '%s' = %s invalid, using %s", spec.id, tostring(raw), tostring(clean))
            end
            self.values[spec.id] = clean
        end
    end

    local index = 0
    while true do
        local key = string.format("%s.types.type(%d)", self.ROOT, index)
        local name = xmlFile:getValue(key .. "#name")
        if name == nil then
            break
        end
        self:setTypeConfig(name, xmlFile:getValue(key .. "#enabled"), xmlFile:getValue(key .. "#weight"),
            xmlFile:getValue(key .. "#max") or self.TYPE_DEFAULT.max)
        index = index + 1
    end
    xmlFile:delete()

    -- setTypeConfig dirty isaretler; dosyadan okunan durum kirli sayilmaz.
    -- Duzeltilen deger varsa duzeltilmis hali gecikmeli olarak diske yazilir.
    self.dirty = false
    self.saveTimer = nil
    if fixedCount > 0 then
        self:markDirty()
    end
    ContractManager.info("Settings loaded (%d types, %d corrected)", index, fixedCount)
end

function Settings:save()
    local path = self:getPath()
    local ok, xmlFile = ContractManager.guard("Settings file save", XMLFile.create, "contractManagerSettings", path, self.ROOT, self.xmlSchema)
    if not ok or xmlFile == nil then
        ContractManager.warning("Settings file could not be written: %s", path)
        return false
    end

    xmlFile:setValue(self.ROOT .. "#version", self.FILE_VERSION)
    for _, spec in ipairs(self.SPEC) do
        xmlFile:setValue(self.ROOT .. "." .. spec.xml, self.values[spec.id])
    end
    for i, name in ipairs(self:getTypeNames()) do
        local key = string.format("%s.types.type(%d)", self.ROOT, i - 1)
        local entry = self.types[name]
        xmlFile:setValue(key .. "#name", name)
        for _, field in ipairs(self.TYPE_FIELDS) do
            xmlFile:setValue(key .. "#" .. field.name, entry[field.name])
        end
    end

    xmlFile:save()
    xmlFile:delete()
    self.dirty = false
    self.saveTimer = nil
    return true
end

function Settings:saveIfDirty()
    if self.dirty then
        return self:save()
    end
    return false
end

---Degisiklik isareti + gecikmeli yazma sayaci.
---Sayac YALNIZ bosken kurulur: aksi halde kaydiraci surukleyen oyuncu her adimda sayaci
---sifirlayip yazmayi suresiz erteleyebilirdi.
function Settings:markDirty()
    self.dirty = true
    if self.saveTimer == nil then
        self.saveTimer = self.SAVE_DELAY_MS
    end
end

---Sunucuda her kare (Persistence:update). Sayac dolunca kirli ayarlar diske yazilir.
---NEDEN: eskiden tek yazma noktasi oyun kaydiydi. Sunucu her gece kayit ALMADAN yeniden
---baslatildigi icin son kayittan sonra yapilan ayar degisikligi kayboluyordu
---(2026-09-17 canli log incelemesi: hasat payi elle degistirildi, restart sonrasi eski deger).
---Istemci kendi modSettings dosyasina YAZMAZ; onun degerleri sunucudan senkronla gelir.
function Settings:updateSaveTimer(dt)
    if self.saveTimer == nil then
        return false
    end
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return false
    end
    self.saveTimer = self.saveTimer - (dt or 0)
    if self.saveTimer > 0 then
        return false
    end
    self.saveTimer = nil
    return self:saveIfDirty()
end

-- ---------------------------------------------------------------------------
-- ag senkronu (sunucu -> istemci). Sira SPEC sirasidir; iki taraf ayni mod surumu (PROTOCOL).
-- ---------------------------------------------------------------------------

local function writeValue(streamId, valueType, value)
    if valueType == BOOL then
        streamWriteBool(streamId, value)
    elseif valueType == INT then
        streamWriteInt32(streamId, value)
    elseif valueType == FLOAT then
        streamWriteFloat32(streamId, value)
    else
        streamWriteString(streamId, value)
    end
end

local function readValue(streamId, valueType)
    if valueType == BOOL then
        return streamReadBool(streamId)
    elseif valueType == INT then
        return streamReadInt32(streamId)
    elseif valueType == FLOAT then
        return streamReadFloat32(streamId)
    end
    return streamReadString(streamId)
end

function Settings:writeStream(streamId)
    for _, spec in ipairs(self.SPEC) do
        writeValue(streamId, spec.type, self:get(spec.id))
    end
    local names = self:getTypeNames()
    streamWriteUInt8(streamId, math.min(#names, 255))
    for i = 1, math.min(#names, 255) do
        local entry = self.types[names[i]]
        streamWriteString(streamId, names[i])
        for _, field in ipairs(self.TYPE_FIELDS) do
            writeValue(streamId, field.type, entry[field.name])
        end
    end
end

---`discard` true ise degerler okunur ama UYGULANMAZ: akisi bozmadan reddetmek icin.
function Settings:readStream(streamId, discard)
    for _, spec in ipairs(self.SPEC) do
        local value = readValue(streamId, spec.type)
        if not discard then
            self.values[spec.id] = self.sanitize(spec, value)
        end
    end
    if not discard then
        self.types = {}
    end
    local count = streamReadUInt8(streamId)
    for _ = 1, count do
        local name = streamReadString(streamId)
        local read = {}
        for _, field in ipairs(self.TYPE_FIELDS) do
            read[field.name] = readValue(streamId, field.type)
        end
        if not discard then
            self:setTypeConfig(name, read.enabled, read.weight, read.max)
        end
    end
    if discard then
        return
    end
    -- istemcideki kopya diske yazilmaz
    self.dirty = false
end

-- ---------------------------------------------------------------------------
-- baslatma: sunucu ve tek oyuncu dosyadan okur; istemci sunucudan alir.
-- Yukleme aninda g_currentMission yok, o yuzden burada herkes dosyayi okur;
-- istemci baglaninca sunucu kopyasi bunun uzerine yazilir.
-- ---------------------------------------------------------------------------

Settings:load()
