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

---Kontratin teslimat sayilari. Teslimatsiz kontratta nil.
function Info.measure(mission)
    if mission == nil or type(mission.expectedLiters) ~= "number" or mission.expectedLiters <= 0 then
        return nil
    end
    return {
        expected = math.max(0, math.floor(mission.expectedLiters + 0.5)),
        deposited = math.max(0, math.floor((tonumber(mission.depositedLiters) or 0) + 0.5)),
        fillTypeIndex = Info.resolveFillType(mission) or 0,
        yieldLiters = Info.estimateFieldYield(mission),
    }
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
    if type(mission.fruitTypeIndex) == "number" and g_fruitTypeManager ~= nil
        and g_fruitTypeManager.getFillTypeIndexByFruitTypeIndex ~= nil then
        local index = g_fruitTypeManager:getFillTypeIndexByFruitTypeIndex(mission.fruitTypeIndex)
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
    if mission == nil or type(mission.fruitTypeIndex) ~= "number"
        or g_fruitTypeManager == nil or g_fruitTypeManager.getFruitTypeByIndex == nil then
        return nil
    end
    local fruitType = g_fruitTypeManager:getFruitTypeByIndex(mission.fruitTypeIndex)
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
