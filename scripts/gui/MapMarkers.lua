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

ContractManagerMapMarkers = {
    marked = {},   -- uniqueId -> true (bizim ekledigimiz)
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
    local missionKey = ContractManager.getMissionKey(mission)
    if mission == nil or missionKey == nil or mission.status ~= MissionStatus.CREATED or mission.addHotspots == nil then
        return false
    end
    if settings():get("map.showAvailable") then
        return true
    end
    if settings():get("map.showReserved") and ContractManagerReservation ~= nil then
        local r = ContractManagerReservation.get(missionKey)
        if r ~= nil and r.farmId == localFarmId() then
            return true
        end
    end
    return false
end

function Markers.mark(mission)
    local missionKey = ContractManager.getMissionKey(mission)
    if missionKey == nil or Markers.marked[missionKey] then
        return
    end
    local ok = pcall(mission.addHotspots, mission)
    if ok then
        Markers.marked[missionKey] = true
    end
end

function Markers.unmark(mission)
    local missionKey = ContractManager.getMissionKey(mission)
    if missionKey == nil or not Markers.marked[missionKey] then
        return
    end
    Markers.marked[missionKey] = nil
    if mission.status == MissionStatus.CREATED and mission.removeHotspot ~= nil then
        pcall(mission.removeHotspot, mission)
    end
end

---tum kabul edilmemis kontratlari ayarlara gore esitle
function Markers.refresh()
    if g_missionManager == nil or g_missionManager.missions == nil or g_currentMission == nil then
        return
    end
    local seen = {}
    for _, mission in ipairs(g_missionManager.missions) do
        local key = ContractManager.getMissionKey(mission)
        if key ~= nil then
            seen[key] = true
            if Markers.shouldMark(mission) then
                Markers.mark(mission)
            else
                Markers.unmark(mission)
            end
        end
    end
    for id in pairs(Markers.marked) do
        if not seen[id] then Markers.marked[id] = nil end
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
    local missionKey = ContractManager.getMissionKey(mission)
    if missionKey ~= nil then
        Markers.marked[missionKey] = nil
    end
end

if g_messageCenter ~= nil and MessageType ~= nil then
    if MessageType.CURRENT_MISSION_START ~= nil then
        g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function() pcall(Markers.refresh) end, Markers)
    end
    if MessageType.MISSION_GENERATED ~= nil then
        g_messageCenter:subscribe(MessageType.MISSION_GENERATED, function(_, mission)
            if mission ~= nil and Markers.shouldMark(mission) then pcall(Markers.mark, mission) end
        end, Markers)
    end
    if MessageType.MISSION_DELETED ~= nil then
        g_messageCenter:subscribe(MessageType.MISSION_DELETED, function(_, mission) Markers.onMissionDeleted(mission) end, Markers)
    end
    g_messageCenter:subscribe(ContractManager.MESSAGE_SETTINGS_CHANGED, function() pcall(Markers.refresh) end, Markers)
end
