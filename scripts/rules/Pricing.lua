--
-- FS25_ContractManager - Uzaklik ve zorluk carpani
--
-- Odule uc ek yuzde eklenir (ayri ayri acilip kapanir, hepsi toplanir):
--   * Uzaklik : kontrat konumu (tarla gosterge noktasi) ile ciftlik merkezi arasi km basina
--               distancePercentPerKm, en cok distanceMaxPercent. Ciftlik merkezi = ciftligin
--               ciftlik evi (spec_farmhouse), yoksa sahip oldugu arazilerin gosterge noktalarinin
--               ortalamasi. Konum 60 sn onbelleklenir.
--   * Kucuk tarla : alan smallFieldRefHa altindaysa (1 - alan/ref) * smallFieldMaxPercent.
--   * Tur zorlugu : TYPE_DIFFICULTY tablosundaki yuzde (taslanma, olu agac vb. zor isler).
-- Uzaklik icin ciftlik gerekir: kabul edilmis kontratta kontratin ciftligi, kabul oncesi
-- istemcide kendi ciftligi (gosterim), sunucuda kabul oncesi 0 (odeme kabul sonrasi).
--

ContractManagerPricing = {
    FARM_POS_TTL_MS = 60000,
    farmPositions = {},   -- farmId -> { x, z, atMs }
    TYPE_DIFFICULTY = {
        stonePickMission = 30, deadwoodMission = 25, treeTransportMission = 25, destructibleRockMission = 30,
        weedMission = 10, hoeMission = 10, baleWrapMission = 10, plowMission = 5,
    },
}

local Pricing = ContractManagerPricing

local function settings()
    return ContractManagerSettings
end

local function nowMs()
    if g_currentMission ~= nil and type(g_currentMission.time) == "number" then
        return g_currentMission.time
    end
    return 0
end

-- ---------------------------------------------------------------------------
-- konumlar
-- ---------------------------------------------------------------------------

function Pricing.getMissionPosition(mission)
    if mission == nil then
        return nil
    end
    if mission.getWorldPosition ~= nil then
        local ok, x, z = pcall(mission.getWorldPosition, mission)
        if ok and type(x) == "number" and type(z) == "number" and (x ~= 0 or z ~= 0) then
            return x, z
        end
    end
    -- yedek: tarlanin gosterge noktasi
    if mission.field ~= nil and mission.field.getIndicatorPosition ~= nil then
        local ok, x, z = pcall(mission.field.getIndicatorPosition, mission.field)
        if ok and type(x) == "number" and type(z) == "number" then
            return x, z
        end
    end
    return nil
end

local function farmhousePosition(farmId)
    local ps = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if ps == nil or type(ps.placeables) ~= "table" or getWorldTranslation == nil then
        return nil
    end
    for _, placeable in ipairs(ps.placeables) do
        if placeable.spec_farmhouse ~= nil and placeable.getOwnerFarmId ~= nil and placeable.rootNode ~= nil then
            local ok, owner = pcall(placeable.getOwnerFarmId, placeable)
            if ok and owner == farmId then
                local okPos, x, _, z = pcall(getWorldTranslation, placeable.rootNode)
                if okPos and type(x) == "number" then
                    return x, z
                end
            end
        end
    end
    return nil
end

local function farmlandCentroid(farmId)
    if g_farmlandManager == nil or g_farmlandManager.getOwnedFarmlandIdsByFarmId == nil then
        return nil
    end
    local ids = g_farmlandManager:getOwnedFarmlandIdsByFarmId(farmId)
    if type(ids) ~= "table" then
        return nil
    end
    local sx, sz, n = 0, 0, 0
    for _, id in ipairs(ids) do
        local fl = g_farmlandManager:getFarmlandById(id)
        if fl ~= nil and type(fl.xWorldPos) == "number" and type(fl.zWorldPos) == "number" then
            sx, sz, n = sx + fl.xWorldPos, sz + fl.zWorldPos, n + 1
        end
    end
    if n == 0 then
        return nil
    end
    return sx / n, sz / n
end

function Pricing.getFarmPosition(farmId)
    if farmId == nil or farmId == 0 then
        return nil
    end
    local cached = Pricing.farmPositions[farmId]
    if cached ~= nil and nowMs() - cached.atMs < Pricing.FARM_POS_TTL_MS then
        return cached.x, cached.z
    end
    local x, z = farmhousePosition(farmId)
    if x == nil then
        x, z = farmlandCentroid(farmId)
    end
    if x == nil then
        return nil
    end
    Pricing.farmPositions[farmId] = { x = x, z = z, atMs = nowMs() }
    return x, z
end

function Pricing.getDistanceKm(mission, farmId)
    local mx, mz = Pricing.getMissionPosition(mission)
    local fx, fz = Pricing.getFarmPosition(farmId)
    if mx == nil or fx == nil then
        return nil
    end
    local dx, dz = mx - fx, mz - fz
    return math.sqrt(dx * dx + dz * dz) / 1000
end

-- ---------------------------------------------------------------------------
-- yuzdeler
-- ---------------------------------------------------------------------------

function Pricing.isEnabled()
    return ContractManager:getRulesEnabled()
end

function Pricing.resolveFarmId(mission)
    if mission == nil then
        return nil
    end
    if mission.farmId ~= nil and mission.farmId ~= 0 then
        return mission.farmId
    end
    if g_currentMission ~= nil and not g_currentMission:getIsServer() and g_currentMission.getFarmId ~= nil then
        return g_currentMission:getFarmId()
    end
    return nil
end

-- getBreakdown sicak yoldadir: getReward her cizimde sorulabilir ve o da buraya gelir.
-- Pahali olan kisim yuzde hesabi degil, motora giden sorgular: tarla/ciftlik konumu ve
-- tarla alani. Bunlar oturum boyunca degismedigi icin kontrat basina onbellege alinir.
-- Yuzdeler HER CAGRIDA yeniden hesaplanir, boylece ayar degisimi aninda yansir.
-- Zayif anahtar: kontrat silinince kayit da duser.
Pricing.geometryCache = setmetatable({}, { __mode = "k" })

function Pricing.clearCache()
    Pricing.geometryCache = setmetatable({}, { __mode = "k" })
end

---kontratin olculeri (uzaklik km + tarla alani ha); motor sorgulari burada onbelleklenir
function Pricing.getGeometry(mission, farmId)
    local cached = Pricing.geometryCache[mission]
    if cached ~= nil and cached.farmId == farmId then
        return cached
    end
    local entry = { farmId = farmId }
    entry.km = Pricing.getDistanceKm(mission, farmId)
    if mission.field ~= nil and mission.field.getAreaHa ~= nil then
        local area = mission.field:getAreaHa()
        if type(area) == "number" then
            entry.areaHa = area
        end
    end
    Pricing.geometryCache[mission] = entry
    return entry
end

---{ distance = %, size = %, type = %, total = % }
function Pricing.getBreakdown(mission)
    local out = { distance = 0, size = 0, type = 0, total = 0 }
    if not Pricing.isEnabled() or mission == nil then
        return out
    end
    -- ciftlik degisince (kabul, devir) uzaklik da degisir: anahtarin parcasi
    local geometry = Pricing.getGeometry(mission, Pricing.resolveFarmId(mission))
    local s = settings()

    if s:get("pricing.distanceEnabled") then
        local km = geometry.km
        if km ~= nil then
            out.distance = math.min(s:get("pricing.distanceMaxPercent") or 0, km * (s:get("pricing.distancePercentPerKm") or 0))
        end
    end

    if s:get("pricing.smallFieldEnabled") and geometry.areaHa ~= nil then
        local area = geometry.areaHa
        local ref = s:get("pricing.smallFieldRefHa") or 2
        if ref > 0 and area < ref then
            out.size = (1 - area / ref) * (s:get("pricing.smallFieldMaxPercent") or 0)
        end
    end

    if s:get("pricing.typeDifficultyEnabled") then
        local typeName = mission.type ~= nil and mission.type.name or nil
        out.type = Pricing.TYPE_DIFFICULTY[typeName] or 0
    end

    out.total = out.distance + out.size + out.type
    return out
end

function Pricing.getMultiplier(mission)
    return 1 + Pricing.getBreakdown(mission).total / 100
end

---detay satirlari
function Pricing.getDetailRows(mission, textFn)
    local rows = {}
    local b = Pricing.getBreakdown(mission)
    if b.distance > 0 then
        rows[#rows + 1] = { title = textFn("cm_detailDistance"), value = string.format("+%d %%", math.floor(b.distance + 0.5)) }
    end
    if b.size > 0 then
        rows[#rows + 1] = { title = textFn("cm_detailSmallField"), value = string.format("+%d %%", math.floor(b.size + 0.5)) }
    end
    if b.type > 0 then
        rows[#rows + 1] = { title = textFn("cm_detailDifficulty"), value = string.format("+%d %%", math.floor(b.type + 0.5)) }
    end
    return rows
end
