--
-- FS25_ContractManager - Kontrat rezervasyonu (cok oyunculu)
--
-- Bir oyuncu kabul edilmemis bir kontrati kendi ciftligi adina reservation#minutes gercek
-- dakika boyunca rezerve eder; o surede baska ciftlik kontrati baslatamaz (startMission
-- NO_ACCESS doner ve ciftlige bildirim gider). Ciftlik basina ayni anda tek rezervasyon.
-- Rezervasyon kabul, bitis/silme veya sure dolunca kalkar.
--
-- Durum sunucuda (list[uniqueId] = {farmId, untilMs}); istemcilere ReservationEvent ile
-- yayilir, istemci kalan saniyeyi kendi saatine gore tutar. Gec baglanan istemci ayar
-- senkronu isterken rezervasyonlari da alir. Savegame'e yazilmaz (kisa omurlu).
--
-- Arayuz: stok Kontratlar sayfasi alt cubugunda "Rezerve et / Rezervasyonu birak"
-- (oyunun tanimladigi bos bir tus; BetterContracts yukluyse eklenmez) ve detay satiri.
--

ContractManagerReservation = {
    list = {},          -- uniqueId -> { farmId, untilMs, farmName }
    buttonsInstalled = false,
}

local Res = ContractManagerReservation

local function settings()
    return ContractManagerSettings
end

-- Metin yardimcisi tek yerde: ContractManager.text (Main.lua). Main once yuklenir.
local function text(key, fallback)
    return ContractManager.text(key, fallback)
end

---Tek oyunculuda her zaman kapali (1.25.0.0): kontrati kapacak baska ciftlik yok.
function Res.isEnabled()
    return ContractManager:getRulesEnabled() and settings():get("reservation.enabled") == true
        and settings():isAvailable("reservation.enabled")
end

---gercek zaman ms (oyunun mission.time'i; timescale'den bagimsiz)
function Res.nowMs()
    if g_currentMission ~= nil and type(g_currentMission.time) == "number" then
        return g_currentMission.time
    end
    return 0
end

function Res.getFarmName(farmId)
    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if farm ~= nil and farm.name ~= nil then
            return tostring(farm.name)
        end
    end
    return "Farm " .. tostring(farmId)
end

---suresi dolanlari temizle
function Res.prune()
    local now = Res.nowMs()
    for id, r in pairs(Res.list) do
        if r.untilMs <= now then
            Res.list[id] = nil
        end
    end
end

---gecerli rezervasyon (varsa) ve kalan saniye
function Res.get(uniqueId)
    local r = Res.list[uniqueId]
    if r == nil then
        return nil, 0
    end
    local left = r.untilMs - Res.nowMs()
    if left <= 0 then
        Res.list[uniqueId] = nil
        return nil, 0
    end
    return r, math.floor(left / 1000)
end

function Res.getFarmReservation(farmId)
    Res.prune()
    for id, r in pairs(Res.list) do
        if r.farmId == farmId then
            return id, r
        end
    end
    return nil
end

---baska ciftlik tarafindan rezerve mi?
function Res.isBlockedFor(uniqueId, farmId)
    if not Res.isEnabled() then
        return false
    end
    local r = Res.get(uniqueId)
    return r ~= nil and r.farmId ~= farmId
end

-- ---------------------------------------------------------------------------
-- sunucu: rezerve et / birak (saf; test edilir). Donus: ok, l10n anahtari
-- ---------------------------------------------------------------------------

function Res.reserve(uniqueId, farmId)
    if not Res.isEnabled() then
        return false, "cm_resDisabled"
    end
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.findMission(uniqueId) or nil
    if mission == nil then
        return false, "cm_adminNotFound"
    end
    if mission.status ~= MissionStatus.CREATED then
        return false, "cm_resAlreadyStarted"
    end
    local existing = Res.get(uniqueId)
    if existing ~= nil and existing.farmId ~= farmId then
        return false, "cm_resTakenByOther"
    end
    local otherId = Res.getFarmReservation(farmId)
    if otherId ~= nil and otherId ~= uniqueId then
        return false, "cm_resFarmLimit"
    end
    local minutes = settings():get("reservation.minutes") or 10
    Res.list[uniqueId] = { farmId = farmId, untilMs = Res.nowMs() + minutes * 60000, farmName = Res.getFarmName(farmId) }
    Res.broadcast(uniqueId)
    ContractManager.info("Contract %s reserved by farm %s for %d min", tostring(uniqueId), tostring(farmId), minutes)
    return true, "cm_resReserved"
end

function Res.release(uniqueId, farmId, force)
    local r = Res.list[uniqueId]
    if r == nil then
        return false, "cm_resNone"
    end
    if not force and r.farmId ~= farmId then
        return false, "cm_resTakenByOther"
    end
    Res.list[uniqueId] = nil
    Res.broadcast(uniqueId)
    return true, "cm_resReleased"
end

function Res.clearForMission(mission)
    local id = ContractManager.getMissionKey(mission)
    if id ~= nil and Res.list[id] ~= nil then
        Res.list[id] = nil
        Res.broadcast(id)
    end
end

---sunucu: tek kaydi herkese yay (cleared ise bosaltir)
function Res.broadcast(uniqueId, connection)
    if ContractManagerReservationEvent == nil then
        return
    end
    local r, left = Res.get(uniqueId)
    local ev = ContractManagerReservationEvent.new(uniqueId, r ~= nil and r.farmId or 0, left, r ~= nil and r.farmName or "")
    if connection ~= nil then
        connection:sendEvent(ev)
    elseif g_server ~= nil then
        g_server:broadcastEvent(ev, false)
        if ContractManagerMapMarkers ~= nil and g_client ~= nil then
            pcall(ContractManagerMapMarkers.onReservationChanged, uniqueId)
        end
    end
end

---sunucu: tum aktif rezervasyonlari bir baglantiya gonder (gec baglanan istemci)
function Res.sendAllTo(connection)
    Res.prune()
    for id in pairs(Res.list) do
        Res.broadcast(id, connection)
    end
end

---istemci: yayini uygula
---Sunucudan senkron gelince acik yonetim sayfasi tazelensin (varsa).
local function notifyPage()
    if ContractManagerManagePage ~= nil and ContractManagerManagePage.onRemoteChange ~= nil then
        ContractManagerManagePage.onRemoteChange()
    end
end

function Res.applyRemote(uniqueId, farmId, secondsLeft, farmName)
    if farmId == 0 or secondsLeft <= 0 then
        Res.list[uniqueId] = nil
    else
        Res.list[uniqueId] = { farmId = farmId, untilMs = Res.nowMs() + secondsLeft * 1000, farmName = farmName }
    end
    if ContractManagerMapMarkers ~= nil then
        pcall(ContractManagerMapMarkers.onReservationChanged, uniqueId)
    end
    notifyPage()
end

-- ---------------------------------------------------------------------------
-- hook: baska ciftligin rezervasyonu kabulu engeller; kabul/bitis rezervasyonu siler
-- ---------------------------------------------------------------------------

function Res.overwriteStartMission(manager, superFunc, mission, farmId, spawnVehicles)
    local missionKey = ContractManager.getMissionKey(mission)
    if mission ~= nil and Res.isBlockedFor(missionKey, farmId) then
        local r = Res.get(missionKey)
        if ContractManagerNotificationEvent ~= nil and ContractManagerNotificationEvent.RESERVED ~= nil then
            local _, secondsLeft = Res.get(missionKey)
            ContractManagerNotificationEvent.sendToFarm(ContractManagerNotificationEvent.RESERVED, farmId,
                r ~= nil and r.farmName or "?", math.max(0, math.ceil((secondsLeft or 0) / 60)))
        end
        return MissionStartState.NO_ACCESS
    end
    local result = superFunc(manager, mission, farmId, spawnVehicles)
    if result == MissionStartState.OK then
        Res.clearForMission(mission)
    end
    return result
end

function Res.afterMissionFinish(mission, finishState)
    if mission ~= nil and mission.isServer then
        Res.clearForMission(mission)
    end
end

-- ---------------------------------------------------------------------------
-- stok Kontratlar sayfasi butonu
-- ---------------------------------------------------------------------------

function Res.onClickReserve()
    local frame = g_inGameMenu ~= nil and g_inGameMenu.pageContracts or nil
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.getSelectedMission(frame) or nil
    local uniqueId = ContractManager.getMissionKey(mission)
    local objectId = ContractManager.getMissionObjectId(mission)
    if mission == nil or (uniqueId == nil and objectId == 0) then
        return
    end
    local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    local r = Res.get(uniqueId)
    if r ~= nil and r.farmId == farmId then
        ContractManagerReservationEvent.send(ContractManagerReservationEvent.RELEASE, uniqueId, objectId)
    else
        ContractManagerReservationEvent.send(ContractManagerReservationEvent.RESERVE, uniqueId, objectId)
    end
end

function Res.appendMenuButton(frame)
    if not Res.isEnabled() or frame.menuButtonInfo == nil then
        return
    end
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.getSelectedMission(frame) or nil
    if mission == nil or mission.status ~= MissionStatus.CREATED then
        return
    end
    local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    local r, secondsLeft = Res.get(ContractManager.getMissionKey(mission))
    local key = (r ~= nil and r.farmId == farmId) and "cm_resReleaseButton" or "cm_resReserveButton"
    if r ~= nil and r.farmId ~= farmId then
        -- Baskasinin rezervasyonu. Stok "Kontrati kabul et" butonu sunucuya bastan
        -- reddedilecek bir istek gonderiyor ve oyun yalnizca "Basarisiz" diyor.
        -- Butonu ele alip sebebi yaziyoruz: kim rezerve etti, ne zaman serbest kalir.
        Res.replaceAcceptButton(frame, r, secondsLeft)
        return
    end
    ContractManager.addMenuButton(frame.menuButtonInfo, ContractManager.MENU_KEYS_PLAYER, text(key), Res.onClickReserve)
end

---Rezervasyon sebebini oyuncuya yazar (istemci tarafi).
function Res.reservedMessage(r, secondsLeft)
    local minutes = math.max(0, math.ceil((secondsLeft or 0) / 60))
    return string.format(text("cm_resTakenBy", "Reserved by %s; free in %d min."),
        r ~= nil and tostring(r.farmName or "?") or "?", minutes)
end

---Oyunun "Kontrati kabul et" butonu BOSLUK'ta (MENU_ACTIVATE). Canli ekran 2026-09-24: oyuncu
---profilinde MENU_ACCEPT=Enter, MENU_ACTIVATE=Bosluk ve buton "BOSLUK KONTRATI KABUL ET" yaziyordu.
---1.10.0.0-1.24.6.0 butonu yalniz MENU_ACCEPT'te aradi, hic bulamadi; baskasinin rezervasyonunda
---oyuncu stok butona basip yalniz "Basarisiz" goruyordu. Once Bosluk, sonra Enter denenir; bizim
---girdilerimiz (ornek: Bosluk'taki "Sonraki ciftlik") atlanir.
Res.ACCEPT_ACTIONS = { "MENU_ACTIVATE", "MENU_ACCEPT" }

---Listede oyunun Kabul girdisi: yuva, girdi (yoksa nil)
function Res.findAcceptButton(list)
    if type(list) ~= "table" or InputAction == nil then
        return nil
    end
    for _, name in ipairs(Res.ACCEPT_ACTIONS) do
        local action = InputAction[name]
        if action ~= nil then
            for index, info in ipairs(list) do
                if type(info) == "table" and info.inputAction == action and not ContractManager.isOwnMenuButton(info) then
                    return index, info
                end
            end
        end
    end
    return nil
end

function Res.replaceAcceptButton(frame, r, secondsLeft)
    if frame == nil or type(frame.menuButtonInfo) ~= "table" then
        return false
    end
    local index, info = Res.findAcceptButton(frame.menuButtonInfo)
    if index == nil then
        return false
    end
    -- Stok girdi YERINDE degistirilmez (oyun ayni girdi nesnesini sonraki cizimlerde
    -- kullanir); yuvaya yeni bir girdi konur, stok hali bir sonraki geciste geri gelir.
    return ContractManager.replaceMenuButton(frame.menuButtonInfo, index, {
        inputAction = info.inputAction,
        text = text("cm_resReservedButton", "Reserved"),
        callback = function()
            if ContractManagerAdmin ~= nil and ContractManagerAdmin.showLine ~= nil then
                ContractManagerAdmin.showLine(Res.reservedMessage(r, secondsLeft), false)
            end
        end,
    })
end

function Res.installButton()
    if Res.buttonsInstalled or InGameMenuContractsFrame == nil or InGameMenuContractsFrame.setButtonsForState == nil then
        return false
    end
    if ContractManager:isBetterContractsLoaded() then
        return false
    end
    ContractManager.registerButtonAppender("reservation", 20, Res.appendMenuButton)
    if not ContractManager.installButtonBar() then
        return false
    end
    Res.buttonsInstalled = true
    return true
end

---detay satiri (ContractDetails cagirir)
function Res.getDetailRow(mission)
    if mission == nil or ContractManager.getMissionKey(mission) == nil or not Res.isEnabled() then
        return nil
    end
    local r, left = Res.get(ContractManager.getMissionKey(mission))
    if r == nil then
        return nil
    end
    return { title = text("cm_detailReserved"), value = string.format("%s · %d %s", tostring(r.farmName), math.ceil(left / 60), text("cm_unitMinute", "min")) }
end

---Harita yeniden yuklendiginde (panelden durdur-baslat) surec olmez ama oyun saati
---sifirdan baslar. Sifirlama kancasi yoktu: eski oturumun rezervasyonlari tasiniyor ve
---`untilMs` degerleri cok ileride gorundugu icin o ciftlik HICBIR kontrati rezerve
---edemiyordu. 2026-09-13 denetimi.
function Res.reset()
    Res.list = {}
end

function Res:loadMap()
    Res.reset()
end

function Res:deleteMap()
    Res.reset()
end

if addModEventListener ~= nil then
    addModEventListener(Res)
end

if MissionManager ~= nil and MissionManager.startMission ~= nil and AbstractMission ~= nil and AbstractMission.finish ~= nil then
    MissionManager.startMission = Utils.overwrittenFunction(MissionManager.startMission, Res.overwriteStartMission)
    AbstractMission.finish = ContractManager.appendKeepingReturn(AbstractMission.finish, Res.afterMissionFinish)
    if g_messageCenter ~= nil and MessageType ~= nil then
        if MessageType.CURRENT_MISSION_START ~= nil then
            g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function() Res.installButton() end, Res)
        end
        if MessageType.MISSION_DELETED ~= nil then
            g_messageCenter:subscribe(MessageType.MISSION_DELETED, function(_, mission)
                if g_currentMission ~= nil and g_currentMission:getIsServer() then Res.clearForMission(mission) end
            end, Res)
        end
    end
end
