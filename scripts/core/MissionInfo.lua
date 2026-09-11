--
-- FS25_ContractManager - kontratin urun bilgisi (sunucu -> istemci)
--
-- TUZAK: hasat/ot gibi teslimatli kontratlarin `expectedLiters` ve `depositedLiters`
-- alanlari HarvestMission gibi alt siniflarda yasar ve HICBIR writeStream'de gecmez.
-- AbstractFieldMission:writeStream yalnizca tarla kimligini yazar. Yani istemcide bu
-- alanlar NIL'dir; kontrat detay panelinde "teslim edilecek / teslim edilen" satirlari
-- bu yuzden hic gorunmuyordu (2026-09-10). uniqueId ile ayni sinif hata.
--
-- Cozum: sunucu bu sayilari kendi olculerinden okuyup istemcilere yayinlar. Kontrat
-- AG NESNESIDIR, bu yuzden kimlik olarak NetworkUtil nesne kimligi kullanilir.
--
-- Gonderim noktalari:
--   * istemci baglaninca hepsi (sendAllTo)
--   * kontrat uretilince / kabul edilince (Registry hook'lari)
--   * calisan kontratlarda teslimat ilerledikce (throttle: PUSH_INTERVAL_MS + esik)
--

ContractManagerMissionInfo = {
    byObjectId = {},   -- istemci: objectId -> { expected, deposited, fillTypeIndex, yieldLiters }
    lastSent = {},     -- sunucu: objectId -> son gonderilen deposited
    timer = 0,
}

local Info = ContractManagerMissionInfo

Info.PUSH_INTERVAL_MS = 5000     -- calisan kontratlar icin en sik yayin araligi
Info.PUSH_DELTA_LITERS = 250     -- bu kadar degismeden tekrar yayinlanmaz

-- ---------------------------------------------------------------------------
-- olcum (sunucu; saf yardimcilar test edilir)
-- ---------------------------------------------------------------------------

Info.SUCCESS_FACTOR_DEFAULT = 0.93   -- oyunun AbstractMission.SUCCESS_FACTOR'u okunamazsa
Info.DELIVERY_TYPES = { harvestMission = true, mowMission = true }   -- urun teslim eden kontrat turleri

---Oyunun basari carpani: teslim edilmesi gereken = tarla verimi * carpan (AbstractFieldMission
---getFieldCompletion ayni sabiti kullanir). Okunamazsa varsayilan.
function Info.getSuccessFactor()
    local factor = AbstractMission ~= nil and tonumber(AbstractMission.SUCCESS_FACTOR) or nil
    if factor == nil or factor <= 0 or factor > 1 then
        return Info.SUCCESS_FACTOR_DEFAULT
    end
    return factor
end

function Info.isDeliveryType(mission)
    local typeName = mission ~= nil and mission.type ~= nil and mission.type.name or nil
    return typeName ~= nil and Info.DELIVERY_TYPES[typeName] == true
end

---Kontratin teslimat sayilari. Teslimatsiz kontratta nil.
---HarvestMission sinifi yayinlanmadi: `expectedLiters` uretimde mi baslangicta mi doluyor bilinmiyor.
---Bos ise (pano kontrati) tarla veriminden tahmin edilir; `estimated` bayragi istemciye gider.
function Info.measure(mission)
    if mission == nil then
        return nil
    end
    local yieldLiters = Info.estimateFieldYield(mission)
    local expected = tonumber(mission.expectedLiters) or 0
    local estimated = false
    if expected <= 0 then
        if not Info.isDeliveryType(mission) or yieldLiters <= 0 then
            return nil
        end
        expected = yieldLiters * Info.getSuccessFactor()
        estimated = true
    end
    return {
        expected = math.max(0, math.floor(expected + 0.5)),
        deposited = math.max(0, math.floor((tonumber(mission.depositedLiters) or 0) + 0.5)),
        fillTypeIndex = Info.resolveFillType(mission) or 0,
        yieldLiters = yieldLiters,
        estimated = estimated,
    }
end

---Kontratin urun turu (fruitType index). Alan adi yayinlanmamis sinifta yasadigi icin sirayla
---denenir: kontrat, tarla durumu, tarla. FruitType.UNKNOWN sayilmaz.
function Info.resolveFruitType(mission)
    if mission == nil then
        return nil
    end
    local unknown = FruitType ~= nil and FruitType.UNKNOWN or nil
    local function valid(v)
        return type(v) == "number" and v > 0 and v ~= unknown
    end
    if valid(mission.fruitTypeIndex) then return mission.fruitTypeIndex end
    if valid(mission.fruitType) then return mission.fruitType end
    local field = mission.field
    if type(field) == "table" then
        local state = field.fieldState
        if type(state) == "table" and valid(state.fruitTypeIndex) then return state.fruitTypeIndex end
        if valid(field.fruitTypeIndex) then return field.fruitTypeIndex end
        if type(field.getFruitType) == "function" then
            local ok, v = pcall(field.getFruitType, field)
            if ok and valid(v) then return v end
        end
    end
    return nil
end

function Info.resolveFillType(mission)
    if mission == nil then
        return nil
    end
    if type(mission.fillTypeIndex) == "number" then
        return mission.fillTypeIndex
    end
    if type(mission.fillType) == "number" then
        return mission.fillType
    end
    local fruitTypeIndex = Info.resolveFruitType(mission)
    if fruitTypeIndex ~= nil and g_fruitTypeManager ~= nil
        and g_fruitTypeManager.getFillTypeIndexByFruitTypeIndex ~= nil then
        local index = g_fruitTypeManager:getFillTypeIndexByFruitTypeIndex(fruitTypeIndex)
        if type(index) == "number" then
            return index
        end
    end
    return nil
end

---Tarladan cikacak TAHMINI toplam urun (litre). Oyun bunu dogrudan vermiyor;
---urun turunun m2 basina verimi ile tarla alanindan hesaplanir. Veri eksikse 0.
function Info.estimateFieldYield(mission)
    if mission == nil or mission.field == nil or mission.field.getAreaHa == nil then
        return 0
    end
    local areaHa = mission.field:getAreaHa()
    if type(areaHa) ~= "number" or areaHa <= 0 then
        return 0
    end
    local literPerSqm = Info.getLiterPerSqm(mission)
    if literPerSqm == nil or literPerSqm <= 0 then
        return 0
    end
    return math.max(0, math.floor(areaHa * 10000 * literPerSqm + 0.5))
end

function Info.getLiterPerSqm(mission)
    local fruitTypeIndex = Info.resolveFruitType(mission)
    if fruitTypeIndex == nil or g_fruitTypeManager == nil or g_fruitTypeManager.getFruitTypeByIndex == nil then
        return nil
    end
    local fruitType = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    if type(fruitType) ~= "table" then
        return nil
    end
    return tonumber(fruitType.literPerSqm)
end

-- ---------------------------------------------------------------------------
-- istemci tarafi depo
-- ---------------------------------------------------------------------------

---Istemci: gelen olcumu sakla ve kontrat nesnesine yapistir.
function Info.applyRemote(objectId, data)
    if objectId == nil or objectId == 0 then
        return nil
    end
    if data == nil then
        Info.byObjectId[objectId] = nil
        return nil
    end
    Info.byObjectId[objectId] = data
    local mission = nil
    if NetworkUtil ~= nil and NetworkUtil.getObject ~= nil then
        local ok, object = pcall(NetworkUtil.getObject, objectId)
        if ok then
            mission = object
        end
    end
    if mission ~= nil then
        mission.cmInfo = data
    end
    return mission
end

---Kontratin olcumu: sunucuda dogrudan alanlardan, istemcide senkronla gelenden.
function Info.get(mission)
    if mission == nil then
        return nil
    end
    local direct = Info.measure(mission)
    if direct ~= nil then
        return direct
    end
    if type(mission.cmInfo) == "table" then
        return mission.cmInfo
    end
    if ContractManager ~= nil and ContractManager.getMissionObjectId ~= nil then
        local objectId = ContractManager.getMissionObjectId(mission)
        if objectId ~= 0 then
            return Info.byObjectId[objectId]
        end
    end
    return nil
end

function Info.reset()
    Info.byObjectId = {}
    Info.lastSent = {}
    Info.timer = 0
end

-- ---------------------------------------------------------------------------
-- yayin (sunucu)
-- ---------------------------------------------------------------------------

function Info.broadcast(mission, connection)
    if ContractManagerMissionInfoEvent == nil or mission == nil then
        return false
    end
    local objectId = ContractManager.getMissionObjectId(mission)
    if objectId == 0 then
        return false
    end
    local data = Info.measure(mission)
    if data == nil then
        return false
    end
    -- kontratin ilk yayini loga: sunucu logundan hangi alanin doldugu gorulsun (alan adlari yayinlanmamis sinifta)
    if Info.lastSent[objectId] == nil and connection == nil then
        ContractManager.info("MissionInfo '%s': toDeliver=%d%s yield=%d fillType=%d deposited=%d",
            tostring(mission.title or mission.progressTitle or "?"), data.expected, data.estimated and " (est)" or "",
            data.yieldLiters or 0, data.fillTypeIndex or 0, data.deposited or 0)
    end
    local event = ContractManagerMissionInfoEvent.new(objectId, data)
    if connection ~= nil then
        connection:sendEvent(event)
    elseif g_server ~= nil then
        g_server:broadcastEvent(event, false)
    else
        return false
    end
    Info.lastSent[objectId] = data.deposited
    return true
end

function Info.sendAllTo(connection)
    if g_missionManager == nil then
        return
    end
    for _, mission in ipairs(g_missionManager.missions or {}) do
        Info.broadcast(mission, connection)
    end
end

---Teslimat ilerledikce yayinla, ama her karede degil: sabit aralik + litre esigi.
function Info.shouldPush(objectId, deposited)
    local last = Info.lastSent[objectId]
    if last == nil then
        return true
    end
    return math.abs((deposited or 0) - last) >= Info.PUSH_DELTA_LITERS
end

function Info:update(dt)
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() or g_missionManager == nil then
        return
    end
    Info.timer = Info.timer + (dt or 0)
    if Info.timer < Info.PUSH_INTERVAL_MS then
        return
    end
    Info.timer = 0
    for _, m in ipairs(g_missionManager.missions or {}) do
        if m.status == MissionStatus.RUNNING or m.status == MissionStatus.PREPARING then
            local data = Info.measure(m)
            if data ~= nil then
                local objectId = ContractManager.getMissionObjectId(m)
                if objectId ~= 0 and Info.shouldPush(objectId, data.deposited) then
                    Info.broadcast(m)
                end
            end
        end
    end
end

function Info:loadMap()
    Info.reset()
end

function Info:deleteMap()
    Info.reset()
end

addModEventListener(Info)
