--
-- FS25_ContractManager - Harita isaretleri (istemci tarafi, gorsel)
--
-- Oyun yalnizca kabul edilmis kontratin tarlasini haritada gosterir (mission.mapHotspot,
-- AbstractFieldMissionHotspot). Burada:
--   * map#showReserved  : kendi ciftliginin rezerve ettigi kontratin tarlasi isaretlenir.
--   * map#showAvailable : panodaki tum kabul edilmemis kontratlarin tarlalari isaretlenir.
-- Isaretler oyunun kendi hotspot nesneleridir (mission:addHotspots / removeHotspot);
-- ozel cizim yok. Kabul edilince oyunun update() dongusu kendi isaretini yonetir.
--
-- Isaretler kontrat NESNESINE baglidir (1.26.0.0): istemcide panodaki kontratin uniqueId'si yok (sunucu
-- gondermez), kimlik anahtarli tablo "Tum kontratlari goster"i istemcide hic calistirmiyordu.
--

ContractManagerMapMarkers = {
    marked = setmetatable({}, { __mode = "k" }),   -- kontrat -> true (bizim ekledigimiz)
    SYNC_INTERVAL_MS = 5000,
    syncTimer = 0,
}

local Markers = ContractManagerMapMarkers

local function settings()
    return ContractManagerSettings
end

local function localFarmId()
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        return g_currentMission:getFarmId()
    end
    return nil
end

function Markers.shouldMark(mission)
    if mission == nil or mission.status ~= MissionStatus.CREATED or mission.addHotspots == nil then
        return false
    end
    if settings():get("map.showAvailable") then
        return true
    end
    local missionKey = ContractManager.getMissionKey(mission)
    if missionKey ~= nil and settings():get("map.showReserved") and settings():isAvailable("map.showReserved")
        and ContractManagerReservation ~= nil and ContractManagerReservation.isEnabled() then
        local r = ContractManagerReservation.get(missionKey)
        if r ~= nil and r.farmId == localFarmId() then
            return true
        end
    end
    return false
end

function Markers.mark(mission)
    if mission == nil or Markers.marked[mission] then
        return
    end
    mission:addHotspots()
    Markers.marked[mission] = true
end

function Markers.unmark(mission)
    if mission == nil or not Markers.marked[mission] then
        return
    end
    Markers.marked[mission] = nil
    if mission.status == MissionStatus.CREATED and mission.removeHotspot ~= nil then
        mission:removeHotspot()
    end
end

---tum kabul edilmemis kontratlari ayarlara gore esitle
function Markers.refresh()
    if g_missionManager == nil or g_missionManager.missions == nil or g_currentMission == nil then
        return
    end
    local seen = {}
    for _, mission in ipairs(g_missionManager.missions) do
        seen[mission] = true
        if Markers.shouldMark(mission) then
            Markers.mark(mission)
        else
            Markers.unmark(mission)
        end
    end
    for mission in pairs(Markers.marked) do
        if not seen[mission] then Markers.marked[mission] = nil end
    end
end

function Markers.onReservationChanged(uniqueId)
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.findMission(uniqueId) or nil
    if mission == nil then
        return
    end
    if Markers.shouldMark(mission) then
        Markers.mark(mission)
    else
        Markers.unmark(mission)
    end
end

function Markers.onMissionDeleted(mission)
    if mission ~= nil then
        Markers.marked[mission] = nil
    end
end

---Istemcide yeni kontrat gelince oyun mesaj yayinlamaz (MISSION_GENERATED yalniz sunucuda): isaretler
---ayar aciksa seyrek araliklarla esitlenir. Ayar kapaliyken ve dedicated sunucuda hic calismaz.
function Markers:update(dt)
    if g_client == nil or not (settings():get("map.showAvailable") or settings():get("map.showReserved")) then
        return
    end
    Markers.syncTimer = Markers.syncTimer + (dt or 0)
    if Markers.syncTimer < Markers.SYNC_INTERVAL_MS then
        return
    end
    Markers.syncTimer = 0
    ContractManager.guard("Map markers", Markers.refresh)
end

function Markers:deleteMap()
    Markers.marked = setmetatable({}, { __mode = "k" })
    Markers.syncTimer = 0
end

if g_messageCenter ~= nil and MessageType ~= nil then
    if MessageType.CURRENT_MISSION_START ~= nil then
        g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function() ContractManager.guard("Map markers", Markers.refresh) end, Markers)
    end
    if MessageType.MISSION_GENERATED ~= nil then
        g_messageCenter:subscribe(MessageType.MISSION_GENERATED, function(_, mission)
            if mission ~= nil and Markers.shouldMark(mission) then ContractManager.guard("Map markers", Markers.mark, mission) end
        end, Markers)
    end
    if MessageType.MISSION_DELETED ~= nil then
        g_messageCenter:subscribe(MessageType.MISSION_DELETED, function(_, mission) Markers.onMissionDeleted(mission) end, Markers)
    end
    g_messageCenter:subscribe(ContractManager.MESSAGE_SETTINGS_CHANGED, function() ContractManager.guard("Map markers", Markers.refresh) end, Markers)
end
if addModEventListener ~= nil then
    addModEventListener(Markers)
end
