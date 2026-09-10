--
-- FS25_ContractManager - Settings
--
-- modSettings/FS25_ContractManager.xml okur/yazar. Tum degerler SPEC tablosunda
-- tanimlidir: tur, varsayilan, sinir. Bozuk deger varsayilana duser ve loglanir.
-- Diske yazma yalnizca dirty iken ve saveIfDirty() cagrilinca olur (menu kapanisi,
-- oyun kaydi) - her degisiklikte yazmak oyunu kasar.
--
-- Kontrat tur ayarlari (enabled/weight) dinamiktir: tur adlari oyun icinde
-- g_missionManager.missionTypes'tan gelir; dosyada olmayan tur varsayilanla doner.
--

ContractManagerSettings = {
    FILENAME = "FS25_ContractManager.xml",
    ROOT = "contractManager",
    FILE_VERSION = 1,
    values = {},
    types = {},          -- name -> { enabled = bool, weight = number }
    dirty = false,
    loaded = false,
}

local Settings = ContractManagerSettings
local BOOL, INT, FLOAT, STRING = "bool", "int", "float", "string"

-- id: kod icinde kullanilan yol; xml: dosya anahtari (ROOT'suz)
Settings.SPEC = {
    { id = "guard.enabled",                 xml = "guard#enabled",                 type = BOOL,   default = true },
    { id = "guard.confiscateOnFail",        xml = "guard#confiscateOnFail",        type = BOOL,   default = true },
    { id = "guard.blockCancelAfterProgress",xml = "guard#blockCancelAfterProgress",type = BOOL,   default = true },

    { id = "generation.maxTotal",           xml = "generation#maxTotal",           type = INT,    default = 0,    min = 0,   max = 200 },   -- 0 = oyun varsayilani
    { id = "generation.maxPerType",         xml = "generation#maxPerType",         type = INT,    default = 0,    min = 0,   max = 50 },    -- 0 = oyun varsayilani
    { id = "generation.refreshMultiplier",  xml = "generation#refreshMultiplier",  type = FLOAT,  default = 1.0,  min = 0.1, max = 10 },
    { id = "generation.cooldownPerFieldHours", xml = "generation#cooldownPerFieldHours", type = INT, default = 0, min = 0, max = 720 },

    { id = "limits.maxActivePerFarm",       xml = "limits#maxActivePerFarm",       type = INT,    default = 3,    min = 0,   max = 50 },    -- 0 = sinirsiz
    { id = "limits.quotaPerDay",            xml = "limits#quotaPerDay",            type = INT,    default = 0,    min = 0,   max = 50 },    -- 0 = kapali
    { id = "limits.quotaPerMonth",          xml = "limits#quotaPerMonth",          type = INT,    default = 0,    min = 0,   max = 200 },   -- 0 = kapali

    { id = "reward.multiplier",             xml = "reward#multiplier",             type = FLOAT,  default = 1.25, min = 0.1, max = 10 },
    { id = "reward.min",                    xml = "reward#min",                    type = INT,    default = 0,    min = 0,   max = 10000000 },
    { id = "reward.max",                    xml = "reward#max",                    type = INT,    default = 0,    min = 0,   max = 10000000 }, -- 0 = tavan yok
    { id = "reward.failPenaltyPercent",     xml = "reward#failPenaltyPercent",     type = INT,    default = 10,   min = 0,   max = 100 },
    { id = "reward.penaltyStepPercent",     xml = "reward#penaltyStepPercent",     type = INT,    default = 0,    min = 0,   max = 50 },    -- ardisik basarisizlik basina ek
    { id = "reward.penaltyMaxPercent",      xml = "reward#penaltyMaxPercent",      type = INT,    default = 50,   min = 0,   max = 100 },
    { id = "reward.partialEnabled",         xml = "reward#partialEnabled",         type = BOOL,   default = false },
    { id = "reward.partialMinCompletion",   xml = "reward#partialMinCompletion",   type = INT,    default = 50,   min = 0,   max = 100 },
    { id = "reward.partialFactor",          xml = "reward#partialFactor",          type = INT,    default = 100,  min = 0,   max = 100 },
    { id = "reward.leaseCostMultiplier",    xml = "reward#leaseCostMultiplier",    type = FLOAT,  default = 1.0,  min = 0,   max = 10 },

    { id = "duration.multiplier",           xml = "duration#multiplier",           type = FLOAT,  default = 1.0,  min = 0.1, max = 10 },
    { id = "duration.warnAtMinutes",        xml = "duration#warnAtMinutes",        type = STRING, default = "60,15" },

    { id = "reputation.enabled",            xml = "reputation#enabled",            type = BOOL,   default = true },
    { id = "reputation.gainComplete",       xml = "reputation#gainComplete",       type = INT,    default = 10,   min = 0,   max = 100 },
    { id = "reputation.lossFail",           xml = "reputation#lossFail",           type = INT,    default = 20,   min = 0,   max = 100 },
    { id = "reputation.lossCancel",         xml = "reputation#lossCancel",         type = INT,    default = 15,   min = 0,   max = 100 },
    { id = "reputation.lossTimeout",        xml = "reputation#lossTimeout",        type = INT,    default = 20,   min = 0,   max = 100 },
    { id = "reputation.maxPoints",          xml = "reputation#maxPoints",          type = INT,    default = 100,  min = 10,  max = 1000 },
    { id = "reputation.rewardBonusMaxPercent", xml = "reputation#rewardBonusMaxPercent", type = INT, default = 25, min = 0, max = 100 },
    { id = "reputation.extraSlotAt",        xml = "reputation#extraSlotAt",        type = INT,    default = 50,   min = 0,   max = 1000 }, -- 0 = kapali

    { id = "reservation.enabled",           xml = "reservation#enabled",           type = BOOL,   default = true },
    { id = "reservation.minutes",           xml = "reservation#minutes",           type = INT,    default = 10,   min = 1,   max = 120 },

    { id = "schedule.enabled",              xml = "schedule#enabled",              type = BOOL,   default = false },
    { id = "schedule.weekendBonusPercent",  xml = "schedule#weekendBonusPercent",  type = INT,    default = 25,   min = 0,   max = 200 },
    { id = "schedule.happyHourStart",       xml = "schedule#happyHourStart",       type = INT,    default = 20,   min = 0,   max = 23 },
    { id = "schedule.happyHourEnd",         xml = "schedule#happyHourEnd",         type = INT,    default = 22,   min = 0,   max = 23 },
    { id = "schedule.happyHourBonusPercent",xml = "schedule#happyHourBonusPercent",type = INT,    default = 0,    min = 0,   max = 200 },

    { id = "map.showReserved",              xml = "map#showReserved",              type = BOOL,   default = true },
    { id = "map.showAvailable",             xml = "map#showAvailable",             type = BOOL,   default = false },

    { id = "pricing.distanceEnabled",       xml = "pricing#distanceEnabled",       type = BOOL,   default = false },
    { id = "pricing.distancePercentPerKm",  xml = "pricing#distancePercentPerKm",  type = INT,    default = 5,    min = 0,   max = 50 },
    { id = "pricing.distanceMaxPercent",    xml = "pricing#distanceMaxPercent",    type = INT,    default = 30,   min = 0,   max = 200 },
    { id = "pricing.smallFieldEnabled",     xml = "pricing#smallFieldEnabled",     type = BOOL,   default = false },
    { id = "pricing.smallFieldRefHa",       xml = "pricing#smallFieldRefHa",       type = FLOAT,  default = 2.0,  min = 0.5, max = 20 },
    { id = "pricing.smallFieldMaxPercent",  xml = "pricing#smallFieldMaxPercent",  type = INT,    default = 20,   min = 0,   max = 100 },
    { id = "pricing.typeDifficultyEnabled", xml = "pricing#typeDifficultyEnabled", type = BOOL,   default = false },

    { id = "lease.enabled",                 xml = "lease#enabled",                 type = BOOL,   default = true },
    { id = "lease.minReputation",           xml = "lease#minReputation",           type = INT,    default = 0,    min = 0,   max = 1000 }, -- 0 = kapali

    { id = "chain.enabled",                 xml = "chain#enabled",                 type = BOOL,   default = false },
    { id = "chain.bonusPercent",            xml = "chain#bonusPercent",            type = INT,    default = 15,   min = 0,   max = 100 },
    { id = "chain.windowDays",              xml = "chain#windowDays",              type = INT,    default = 3,    min = 0,   max = 30 },    -- 0 = sinirsiz

    { id = "npc.enabled",                   xml = "npc#enabled",                   type = BOOL,   default = false },
    { id = "npc.percentPerJob",             xml = "npc#percentPerJob",             type = INT,    default = 2,    min = 0,   max = 20 },
    { id = "npc.maxPercent",                xml = "npc#maxPercent",                type = INT,    default = 20,   min = 0,   max = 100 },

    { id = "partnership.enabled",           xml = "partnership#enabled",           type = BOOL,   default = false },
    { id = "partnership.maxPartners",       xml = "partnership#maxPartners",       type = INT,    default = 1,    min = 1,   max = 4 },
    { id = "partnership.inviteMinutes",     xml = "partnership#inviteMinutes",     type = INT,    default = 10,   min = 1,   max = 60 },

    { id = "integrations.discord",          xml = "integrations#discord",          type = BOOL,   default = true },

    -- Arayuz: kenar cubugundaki "Kontrat Yonetimi" sayfasi. Kapatilinca sekme kaybolur
    -- (TabbedMenu predicate + updatePages); stok Kontratlar sayfasi calismaya devam eder.
    { id = "ui.managePage",                 xml = "ui#managePage",                 type = BOOL,   default = true },

    -- FS25_BetterContracts yukluyken kural katmani (odul/limit/uretim/sure) varsayilan olarak
    -- geri cekilir; true yaparsan iki mod ust uste uygulanir (carpanlar carpilir).
    { id = "compat.overrideBetterContracts", xml = "compat#overrideBetterContracts", type = BOOL,   default = false },
}

Settings.SPEC_BY_ID = {}
for _, spec in ipairs(Settings.SPEC) do
    Settings.SPEC_BY_ID[spec.id] = spec
end

Settings.TYPE_DEFAULT = { enabled = true, weight = 1.0 }
Settings.TYPE_WEIGHT_MIN = 0
Settings.TYPE_WEIGHT_MAX = 10

-- ---------------------------------------------------------------------------
-- sema
-- ---------------------------------------------------------------------------

local XML_TYPE = { [BOOL] = XMLValueType.BOOL, [INT] = XMLValueType.INT, [FLOAT] = XMLValueType.FLOAT, [STRING] = XMLValueType.STRING }

Settings.xmlSchema = XMLSchema.new("contractManagerSettings")
Settings.xmlSchema:register(XMLValueType.INT, Settings.ROOT .. "#version", "Dosya surumu", Settings.FILE_VERSION)
for _, spec in ipairs(Settings.SPEC) do
    Settings.xmlSchema:register(XML_TYPE[spec.type], Settings.ROOT .. "." .. spec.xml, spec.id, spec.default)
end
Settings.xmlSchema:register(XMLValueType.STRING, Settings.ROOT .. ".types.type(?)#name", "Kontrat turu adi")
Settings.xmlSchema:register(XMLValueType.BOOL, Settings.ROOT .. ".types.type(?)#enabled", "Tur uretilsin mi", true)
Settings.xmlSchema:register(XMLValueType.FLOAT, Settings.ROOT .. ".types.type(?)#weight", "Tur agirligi", 1.0)

-- ---------------------------------------------------------------------------
-- dogrulama
-- ---------------------------------------------------------------------------

---Degeri spec'e gore dogrular. Donus: gecerli deger, duzeltildi mi
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
        self.dirty = true
    end
    return clean
end

function Settings:getTypeConfig(typeName)
    local entry = self.types[typeName]
    if entry == nil then
        return self.TYPE_DEFAULT.enabled, self.TYPE_DEFAULT.weight
    end
    return entry.enabled, entry.weight
end

function Settings:setTypeConfig(typeName, enabled, weight)
    if type(typeName) ~= "string" or typeName == "" then
        return
    end
    if type(enabled) ~= "boolean" then
        enabled = self.TYPE_DEFAULT.enabled
    end
    if type(weight) ~= "number" or weight ~= weight then
        weight = self.TYPE_DEFAULT.weight
    end
    weight = math.max(self.TYPE_WEIGHT_MIN, math.min(self.TYPE_WEIGHT_MAX, weight))

    local entry = self.types[typeName]
    if entry == nil or entry.enabled ~= enabled or entry.weight ~= weight then
        self.types[typeName] = { enabled = enabled, weight = weight }
        self.dirty = true
    end
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
    self.loaded = true

    local path = self:getPath()
    if not fileExists(path) then
        self.dirty = true
        self:save()
        ContractManager.info("Settings file created: %s", path)
        return
    end

    local ok, xmlFile = pcall(XMLFile.load, "contractManagerSettings", path, self.xmlSchema)
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
        self:setTypeConfig(name, xmlFile:getValue(key .. "#enabled"), xmlFile:getValue(key .. "#weight"))
        index = index + 1
    end
    xmlFile:delete()

    -- setTypeConfig dirty isaretler; dosyadan okunan durum kirli sayilmaz
    self.dirty = fixedCount > 0
    ContractManager.info("Settings loaded (%d types, %d corrected)", index, fixedCount)
end

function Settings:save()
    local path = self:getPath()
    local ok, xmlFile = pcall(XMLFile.create, "contractManagerSettings", path, self.ROOT, self.xmlSchema)
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
        xmlFile:setValue(key .. "#enabled", entry.enabled)
        xmlFile:setValue(key .. "#weight", entry.weight)
    end

    xmlFile:save()
    xmlFile:delete()
    self.dirty = false
    return true
end

function Settings:saveIfDirty()
    if self.dirty then
        return self:save()
    end
    return false
end

-- ---------------------------------------------------------------------------
-- ag senkronu (sunucu -> istemci). Sira SPEC sirasidir; iki taraf ayni mod surumu.
-- ---------------------------------------------------------------------------

function Settings:writeStream(streamId)
    for _, spec in ipairs(self.SPEC) do
        local value = self:get(spec.id)
        if spec.type == BOOL then
            streamWriteBool(streamId, value)
        elseif spec.type == INT then
            streamWriteInt32(streamId, value)
        elseif spec.type == FLOAT then
            streamWriteFloat32(streamId, value)
        else
            streamWriteString(streamId, value)
        end
    end
    local names = self:getTypeNames()
    streamWriteUInt8(streamId, math.min(#names, 255))
    for i = 1, math.min(#names, 255) do
        local entry = self.types[names[i]]
        streamWriteString(streamId, names[i])
        streamWriteBool(streamId, entry.enabled)
        streamWriteFloat32(streamId, entry.weight)
    end
end

function Settings:readStream(streamId)
    for _, spec in ipairs(self.SPEC) do
        local value
        if spec.type == BOOL then
            value = streamReadBool(streamId)
        elseif spec.type == INT then
            value = streamReadInt32(streamId)
        elseif spec.type == FLOAT then
            value = streamReadFloat32(streamId)
        else
            value = streamReadString(streamId)
        end
        self.values[spec.id] = self.sanitize(spec, value)
    end
    self.types = {}
    local count = streamReadUInt8(streamId)
    for _ = 1, count do
        local name = streamReadString(streamId)
        local enabled = streamReadBool(streamId)
        local weight = streamReadFloat32(streamId)
        self:setTypeConfig(name, enabled, weight)
    end
    -- istemcideki kopya diske yazilmaz
    self.dirty = false
    self.loaded = true
end

-- ---------------------------------------------------------------------------
-- baslatma: sunucu ve tek oyuncu dosyadan okur; istemci sunucudan alir.
-- Yukleme aninda g_currentMission yok, o yuzden burada herkes dosyayi okur;
-- istemci baglaninca sunucu kopyasi bunun uzerine yazilir.
-- ---------------------------------------------------------------------------

Settings:load()
