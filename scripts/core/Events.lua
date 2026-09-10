--
-- FS25_ContractManager - ag olaylari
--
-- ContractManagerSyncEvent: ayarlarin sunucu -> istemci senkronu.
--   * Istemci CURRENT_MISSION_START'ta bos "istek" gonderir (gec baglanan dahil).
--   * Sunucu ayni olayi dolu "durum" olarak geri yollar.
--   * Admin degisikliginden sonra sunucu broadcastState() ile herkese yayar (Faz 4).
-- Kalip FS25_SellingAdmin'de sunucuda dogrulandi.
--

ContractManagerSyncEvent = {}
local ContractManagerSyncEvent_mt = Class(ContractManagerSyncEvent, Event)

InitEventClass(ContractManagerSyncEvent, "ContractManagerSyncEvent")

function ContractManagerSyncEvent.emptyNew()
    local self = Event.new(ContractManagerSyncEvent_mt)
    self.isState = false
    return self
end

---istemci -> sunucu: "ayarlari gonder"
function ContractManagerSyncEvent.newRequest()
    local self = ContractManagerSyncEvent.emptyNew()
    self.isState = false
    return self
end

---sunucu -> istemci: ayarlarin tamami
function ContractManagerSyncEvent.newState()
    local self = ContractManagerSyncEvent.emptyNew()
    self.isState = true
    return self
end

function ContractManagerSyncEvent:writeStream(streamId, connection)
    if streamWriteBool(streamId, self.isState) then
        ContractManagerSettings:writeStream(streamId)
    end
end

function ContractManagerSyncEvent:readStream(streamId, connection)
    self.isState = streamReadBool(streamId)
    if self.isState then
        -- yalnizca sunucudan gelen durum kabul edilir; istemci ayar dayatamaz
        if connection ~= nil and not connection:getIsServer() then
            ContractManager.warning("Ignored settings state sent by a client")
            return
        end
        ContractManagerSettings:readStream(streamId)
    end
    self:run(connection)
end

function ContractManagerSyncEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then
        -- sunucudayiz, istemci durum istedi
        connection:sendEvent(ContractManagerSyncEvent.newState())
        if ContractManagerReservation ~= nil then
            ContractManagerReservation.sendAllTo(connection)
        end
        if ContractManagerPartnership ~= nil then
            ContractManagerPartnership.sendAllTo(connection)
        end
        if ContractManagerMissionInfo ~= nil then
            ContractManagerMissionInfo.sendAllTo(connection)
        end
        return
    end
    if self.isState then
        -- Her ayar degisikliginde sunucu tum ayarlari yayinlar; bunu Info olarak
        -- yazmak uzun oturumda log'un cogunu bu satir yapiyordu (45 satirin 33'u).
        ContractManager.debug("Settings received from server")
        if g_messageCenter ~= nil and g_messageCenter.publish ~= nil then
            g_messageCenter:publish(ContractManager.MESSAGE_SETTINGS_CHANGED)
        end
    end
end

---sunucu: guncel ayarlari tum istemcilere yay
function ContractManagerSyncEvent.broadcastState()
    if g_server ~= nil then
        g_server:broadcastEvent(ContractManagerSyncEvent.newState(), false)
    end
end

---istemci: sunucudan ayarlari iste
function ContractManagerSyncEvent.requestFromServer()
    if g_currentMission == nil or g_currentMission:getIsServer() or g_client == nil then
        return false
    end
    local ok = pcall(function()
        g_client:getServerConnection():sendEvent(ContractManagerSyncEvent.newRequest())
    end)
    if not ok then
        ContractManager.warning("Could not request settings from server")
    end
    return ok
end


if g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_START ~= nil then
    g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function()
        ContractManagerSyncEvent.requestFromServer()
    end, ContractManager)
end

-- ---------------------------------------------------------------------------
-- ContractManagerNotificationEvent: sunucu -> ciftlik uyeleri, genel bildirim.
-- code: TIME_WARNING (text = kontrat basligi, amount = kalan dakika)
-- ---------------------------------------------------------------------------

ContractManagerNotificationEvent = {}
local ContractManagerNotificationEvent_mt = Class(ContractManagerNotificationEvent, Event)

InitEventClass(ContractManagerNotificationEvent, "ContractManagerNotificationEvent")

ContractManagerNotificationEvent.TIME_WARNING = 1
ContractManagerNotificationEvent.ADMIN_RESULT = 2
ContractManagerNotificationEvent.REPUTATION = 3   -- text = delta, amount = yeni puan
ContractManagerNotificationEvent.RESERVED = 4     -- text = rezerve eden ciftlik adi
ContractManagerNotificationEvent.LEASE_DENIED = 5 -- amount = gereken itibar (0 = tamamen kapali)
ContractManagerNotificationEvent.QUOTA = 6        -- text = "day"/"month", amount = sinir
ContractManagerNotificationEvent.PARTNER_INVITE = 7 -- text = kontrat basligi, amount = davet eden ciftlik
ContractManagerNotificationEvent.PARTNER_ACCEPTED = 8 -- sahibe: text = kontrat basligi, amount = kabul eden ciftlik
ContractManagerNotificationEvent.PARTNER_DECLINED = 9 -- sahibe: text = kontrat basligi, amount = reddeden ciftlik

function ContractManagerNotificationEvent.emptyNew()
    return Event.new(ContractManagerNotificationEvent_mt)
end

function ContractManagerNotificationEvent.new(code, farmId, text, amount)
    local self = ContractManagerNotificationEvent.emptyNew()
    self.code = code
    self.farmId = farmId
    self.text = text or ""
    self.amount = amount or 0
    return self
end

function ContractManagerNotificationEvent:readStream(streamId, connection)
    self.code = streamReadUInt8(streamId)
    self.farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    self.text = streamReadString(streamId)
    self.amount = streamReadInt32(streamId)
    self:run(connection)
end

function ContractManagerNotificationEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.code)
    streamWriteUIntN(streamId, self.farmId, FarmManager.FARM_ID_SEND_NUM_BITS)
    streamWriteString(streamId, self.text)
    streamWriteInt32(streamId, self.amount)
end

function ContractManagerNotificationEvent.buildText(code, text, amount)
    if code == ContractManagerNotificationEvent.TIME_WARNING then
        return string.format(g_i18n:getText("cm_timeWarning"), tostring(text), amount or 0)
    elseif code == ContractManagerNotificationEvent.RESERVED then
        if (amount or 0) > 0 then
            return string.format(g_i18n:getText("cm_resTakenBy"), tostring(text), amount)
        end
        return string.format(g_i18n:getText("cm_resBlocked"), tostring(text))
    elseif code == ContractManagerNotificationEvent.PARTNER_INVITE then
        return string.format(g_i18n:getText("cm_partInviteNotify"), tostring(text), amount or 0)
    elseif code == ContractManagerNotificationEvent.PARTNER_ACCEPTED then
        -- sira: (ciftlik no, kontrat basligi); Lua 5.1'de konumsal %2$d yok
        return string.format(g_i18n:getText("cm_partAcceptedNotify"), amount or 0, tostring(text))
    elseif code == ContractManagerNotificationEvent.PARTNER_DECLINED then
        return string.format(g_i18n:getText("cm_partDeclinedNotify"), amount or 0, tostring(text))
    elseif code == ContractManagerNotificationEvent.QUOTA then
        return string.format(g_i18n:getText(text == "day" and "cm_quotaDay" or "cm_quotaMonth"), amount or 0)
    elseif code == ContractManagerNotificationEvent.LEASE_DENIED then
        if (amount or 0) > 0 then
            return string.format(g_i18n:getText("cm_leaseDeniedRep"), amount)
        end
        return g_i18n:getText("cm_leaseDenied")
    end
    return nil
end

function ContractManagerNotificationEvent.showLocal(code, farmId, text, amount)
    if code == ContractManagerNotificationEvent.REPUTATION then
        if ContractManagerReputation ~= nil then
            ContractManagerReputation.setLocal(farmId, amount)
        end
        if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() == farmId
            and g_currentMission.addIngameNotification ~= nil then
            local delta = tonumber(text) or 0
            local kind = delta >= 0 and FSBaseMission.INGAME_NOTIFICATION_OK or FSBaseMission.INGAME_NOTIFICATION_CRITICAL
            g_currentMission:addIngameNotification(kind, string.format(g_i18n:getText("cm_repNotify"), delta, amount or 0))
        end
        return
    end
    if code == ContractManagerNotificationEvent.ADMIN_RESULT then
        -- ortaklik sonuclari (davet gitti / katildin / reddettin) pencerede; digerleri toast
        if ContractManagerNotificationEvent.POPUP_RESULT_KEYS[text] and ContractManagerInfoPopup ~= nil then
            ContractManagerInfoPopup.show(g_i18n:getText("cm_popupPartnerTitle"), g_i18n:getText(text), amount == 1)
        elseif ContractManagerAdmin ~= nil then
            ContractManagerAdmin.showResult(text, amount == 1)
        end
        return
    end
    if g_currentMission == nil or g_currentMission.getFarmId == nil or g_currentMission:getFarmId() ~= farmId then
        return
    end
    local line = ContractManagerNotificationEvent.buildText(code, text, amount)
    if line == nil then
        return
    end
    if ContractManagerNotificationEvent.POPUP_CODES[code] and ContractManagerInfoPopup ~= nil then
        ContractManagerInfoPopup.show(g_i18n:getText("cm_popupPartnerTitle"), line,
            code ~= ContractManagerNotificationEvent.PARTNER_DECLINED)
        return
    end
    if g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, line)
    end
end

-- Pencereyle gosterilen olaylar (toast yerine). Kullanici istegi: davet gitti, geldi,
-- kabul edildi, reddedildi hepsi pencere olsun.
ContractManagerNotificationEvent.POPUP_CODES = {
    [ContractManagerNotificationEvent.PARTNER_INVITE] = true,
    [ContractManagerNotificationEvent.PARTNER_ACCEPTED] = true,
    [ContractManagerNotificationEvent.PARTNER_DECLINED] = true,
}
ContractManagerNotificationEvent.POPUP_RESULT_KEYS = {
    cm_partInvited = true, cm_partJoined = true, cm_partDeclined = true, cm_partLeft = true,
}

function ContractManagerNotificationEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then
        return -- istemciler bildirim uretemez
    end
    ContractManagerNotificationEvent.showLocal(self.code, self.farmId, self.text, self.amount)
end

function ContractManagerNotificationEvent.sendToFarm(code, farmId, text, amount)
    if g_server == nil or farmId == nil then
        return
    end
    if g_client ~= nil then
        ContractManagerNotificationEvent.showLocal(code, farmId, text, amount)
    end
    g_server:broadcastEvent(ContractManagerNotificationEvent.new(code, farmId, text, amount), false)
end

-- ---------------------------------------------------------------------------
-- yetki: baglantinin kullanicisi master user mu? (FS25_SellingAdmin'de dogrulanmis kalip)
-- ---------------------------------------------------------------------------

function ContractManager.getIsConnectionAdmin(connection)
    if g_currentMission == nil or g_currentMission.userManager == nil or connection == nil then
        return false
    end
    local ok, user = pcall(g_currentMission.userManager.getUserByConnection, g_currentMission.userManager, connection)
    if not ok or user == nil or user.getIsMasterUser == nil then
        return false
    end
    local okAdmin, isAdmin = pcall(user.getIsMasterUser, user)
    return okAdmin and isAdmin == true
end

-- ---------------------------------------------------------------------------
-- ContractManagerSettingChangeEvent: istemci (admin) -> sunucu, tek ayar degisikligi.
-- Sunucu yetkiyi dogrular, uygular, SyncEvent ile herkese yayar. Yetkisiz istemciye
-- gercek durum geri gonderilir ki ekrani yanlis kalmasin.
-- ---------------------------------------------------------------------------

ContractManagerSettingChangeEvent = {}
local ContractManagerSettingChangeEvent_mt = Class(ContractManagerSettingChangeEvent, Event)

InitEventClass(ContractManagerSettingChangeEvent, "ContractManagerSettingChangeEvent")

ContractManagerSettingChangeEvent.TYPE_BOOL = 1
ContractManagerSettingChangeEvent.TYPE_NUMBER = 2
ContractManagerSettingChangeEvent.TYPE_STRING = 3

function ContractManagerSettingChangeEvent.emptyNew()
    return Event.new(ContractManagerSettingChangeEvent_mt)
end

function ContractManagerSettingChangeEvent.new(key, value)
    local self = ContractManagerSettingChangeEvent.emptyNew()
    self.key = key
    self.value = value
    return self
end

function ContractManagerSettingChangeEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.key or "")
    local t = type(self.value)
    if t == "boolean" then
        streamWriteUInt8(streamId, ContractManagerSettingChangeEvent.TYPE_BOOL)
        streamWriteBool(streamId, self.value)
    elseif t == "number" then
        streamWriteUInt8(streamId, ContractManagerSettingChangeEvent.TYPE_NUMBER)
        streamWriteFloat32(streamId, self.value)
    else
        streamWriteUInt8(streamId, ContractManagerSettingChangeEvent.TYPE_STRING)
        streamWriteString(streamId, tostring(self.value or ""))
    end
end

function ContractManagerSettingChangeEvent:readStream(streamId, connection)
    self.key = streamReadString(streamId)
    local valueType = streamReadUInt8(streamId)
    if valueType == ContractManagerSettingChangeEvent.TYPE_BOOL then
        self.value = streamReadBool(streamId)
    elseif valueType == ContractManagerSettingChangeEvent.TYPE_NUMBER then
        self.value = streamReadFloat32(streamId)
    else
        self.value = streamReadString(streamId)
    end
    self:run(connection)
end

function ContractManagerSettingChangeEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return -- sunucudan istemciye bu olay gonderilmez
    end
    if not ContractManager.getIsConnectionAdmin(connection) then
        ContractManager.warning("Rejected setting change '%s' from a non-admin client", tostring(self.key))
        if connection ~= nil and ContractManagerSyncEvent ~= nil then
            connection:sendEvent(ContractManagerSyncEvent.newState())
        end
        return
    end
    ContractManagerSettingsTab.applyOnServer(self.key, self.value)
end

---yerel: sunucu/host ise dogrudan uygula, istemci ise sunucuya gonder
function ContractManagerSettingChangeEvent.send(key, value)
    if g_currentMission ~= nil and g_currentMission:getIsServer() then
        return ContractManagerSettingsTab.applyOnServer(key, value)
    end
    if g_client ~= nil then
        local ok = pcall(function()
            g_client:getServerConnection():sendEvent(ContractManagerSettingChangeEvent.new(key, value))
        end)
        if not ok then
            ContractManager.warning("Could not send setting change to server")
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- ContractManagerStatsEvent: istemci ciftliginin istatistigini ister, sunucu yanitlar.
-- ---------------------------------------------------------------------------

ContractManagerStatsEvent = {}
local ContractManagerStatsEvent_mt = Class(ContractManagerStatsEvent, Event)

InitEventClass(ContractManagerStatsEvent, "ContractManagerStatsEvent")

ContractManagerStatsEvent.STAT_FIELDS = { "completed", "failed", "canceled", "timedOut", "earned", "penalties", "reputation" }
ContractManagerStatsEvent.MAX_BOARD = 32   -- haritada 8'den fazla ciftlik olabilir
ContractManagerStatsEvent.MAX_HISTORY = 5

function ContractManagerStatsEvent.emptyNew()
    local self = Event.new(ContractManagerStatsEvent_mt)
    self.isResponse = false
    return self
end

function ContractManagerStatsEvent.newRequest(farmId)
    local self = ContractManagerStatsEvent.emptyNew()
    self.farmId = farmId
    return self
end

function ContractManagerStatsEvent.newResponse(farmId)
    local self = ContractManagerStatsEvent.emptyNew()
    self.isResponse = true
    self.farmId = farmId
    local registry = ContractManagerRegistry
    self.stats = registry ~= nil and registry:getFarmStats(farmId) or {}
    self.history = {}
    if registry ~= nil then
        for i, entry in ipairs(registry:getHistory(farmId)) do
            if i > ContractManagerStatsEvent.MAX_HISTORY then break end
            self.history[#self.history + 1] = entry
        end
    end
    self.board = ContractManagerStatsEvent.buildBoard()
    return self
end

---siralama: tum ciftlikler, itibar > tamamlanan > kazanc
function ContractManagerStatsEvent.buildBoard()
    local board = {}
    local registry = ContractManagerRegistry
    if registry == nil then return board end
    for farmId, st in pairs(registry.stats) do
        local name = "Farm " .. tostring(farmId)
        if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
            local farm = g_farmManager:getFarmById(farmId)
            if farm ~= nil and farm.name ~= nil then name = tostring(farm.name) end
        end
        board[#board + 1] = { farmId = farmId, name = name, reputation = st.reputation or 0, completed = st.completed or 0, earned = st.earned or 0 }
    end
    table.sort(board, function(a, b)
        if a.reputation ~= b.reputation then return a.reputation > b.reputation end
        if a.completed ~= b.completed then return a.completed > b.completed end
        return a.earned > b.earned
    end)
    while #board > ContractManagerStatsEvent.MAX_BOARD do table.remove(board) end
    return board
end

function ContractManagerStatsEvent:writeStream(streamId, connection)
    streamWriteUIntN(streamId, self.farmId or 0, FarmManager.FARM_ID_SEND_NUM_BITS)
    if streamWriteBool(streamId, self.isResponse) then
        for _, field in ipairs(ContractManagerStatsEvent.STAT_FIELDS) do
            streamWriteFloat32(streamId, self.stats[field] or 0)
        end
        streamWriteUInt8(streamId, #self.history)
        for _, entry in ipairs(self.history) do
            streamWriteString(streamId, tostring(entry.typeName or ""))
            streamWriteUInt8(streamId, entry.finishState or 0)
            streamWriteFloat32(streamId, entry.reward or 0)
            streamWriteFloat32(streamId, entry.payout or entry.reward or 0)
            streamWriteInt32(streamId, entry.finishedDay or 0)
        end
        streamWriteUInt8(streamId, #(self.board or {}))
        for _, row in ipairs(self.board or {}) do
            streamWriteUIntN(streamId, row.farmId or 0, FarmManager.FARM_ID_SEND_NUM_BITS)
            streamWriteString(streamId, row.name or "")
            streamWriteFloat32(streamId, row.reputation or 0)
            streamWriteFloat32(streamId, row.completed or 0)
            streamWriteFloat32(streamId, row.earned or 0)
        end
    end
end

function ContractManagerStatsEvent:readStream(streamId, connection)
    self.farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    self.isResponse = streamReadBool(streamId)
    if self.isResponse then
        self.stats = {}
        for _, field in ipairs(ContractManagerStatsEvent.STAT_FIELDS) do
            self.stats[field] = streamReadFloat32(streamId)
        end
        self.history = {}
        local count = streamReadUInt8(streamId)
        for _ = 1, count do
            self.history[#self.history + 1] = {
                typeName = streamReadString(streamId),
                finishState = streamReadUInt8(streamId),
                reward = streamReadFloat32(streamId),
                payout = streamReadFloat32(streamId),
                finishedDay = streamReadInt32(streamId),
            }
        end
        self.board = {}
        local rows = streamReadUInt8(streamId)
        for _ = 1, rows do
            self.board[#self.board + 1] = {
                farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS),
                name = streamReadString(streamId),
                reputation = streamReadFloat32(streamId),
                completed = streamReadFloat32(streamId),
                earned = streamReadFloat32(streamId),
            }
        end
    end
    self:run(connection)
end

function ContractManagerStatsEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then
        -- sunucu: istek geldi; yalnizca istemcinin KENDI ciftligini yanitla
        local farmId = self.farmId
        if g_currentMission ~= nil and g_currentMission.userManager ~= nil and g_farmManager ~= nil then
            local ok, user = pcall(g_currentMission.userManager.getUserByConnection, g_currentMission.userManager, connection)
            if ok and user ~= nil and user.getId ~= nil and g_farmManager.getFarmByUserId ~= nil then
                local farm = g_farmManager:getFarmByUserId(user:getId())
                if farm ~= nil and farm.farmId ~= nil then
                    farmId = farm.farmId
                end
            end
        end
        connection:sendEvent(ContractManagerStatsEvent.newResponse(farmId))
        return
    end
    if self.isResponse and ContractManagerSettingsTab ~= nil then
        if ContractManagerReputation ~= nil then
            ContractManagerReputation.setLocal(self.farmId, self.stats.reputation)
            for _, row in ipairs(self.board or {}) do ContractManagerReputation.setLocal(row.farmId, row.reputation) end
        end
        ContractManagerSettingsTab:onStatsReceived(self.farmId, self.stats, self.history, self.board)
    end
end

---yerel: sunucu/host ise dogrudan doldur, istemci ise sunucudan iste
function ContractManagerStatsEvent.request()
    if g_currentMission == nil or g_currentMission.getFarmId == nil then
        return
    end
    local farmId = g_currentMission:getFarmId()
    if g_currentMission:getIsServer() then
        local response = ContractManagerStatsEvent.newResponse(farmId)
        ContractManagerSettingsTab:onStatsReceived(farmId, response.stats, response.history, response.board)
        return
    end
    if g_client ~= nil then
        pcall(function()
            g_client:getServerConnection():sendEvent(ContractManagerStatsEvent.newRequest(farmId))
        end)
    end
end

-- ---------------------------------------------------------------------------
-- ContractManagerReservationEvent
--   istemci -> sunucu: RESERVE / RELEASE (uniqueId); sunucu istemcinin ciftligini kendisi bulur
--   sunucu -> istemci: SYNC (uniqueId, farmId, kalan sn, ciftlik adi); farmId 0 = kalkti
-- ---------------------------------------------------------------------------

ContractManagerReservationEvent = {}
local ContractManagerReservationEvent_mt = Class(ContractManagerReservationEvent, Event)

InitEventClass(ContractManagerReservationEvent, "ContractManagerReservationEvent")

ContractManagerReservationEvent.RESERVE = 1
ContractManagerReservationEvent.RELEASE = 2
ContractManagerReservationEvent.SYNC = 3

function ContractManagerReservationEvent.emptyNew()
    return Event.new(ContractManagerReservationEvent_mt)
end

---objectId: kontratin AG kimligi. Istemcide mission.uniqueId nil'dir (sunucu onu
---gondermiyor), bu yuzden istekler kontrati bununla gosterir; SYNC'te ise istemci
---ag kimliginden kontrati bulup sunucunun uniqueId'sini uzerine yapistirir.
function ContractManagerReservationEvent.new(uniqueId, farmId, secondsLeft, farmName)
    local self = ContractManagerReservationEvent.emptyNew()
    self.kind = ContractManagerReservationEvent.SYNC
    self.uniqueId = uniqueId or ""
    -- Kontratin AG kimligi de gitmeli, yoksa istemci hangi kontrat oldugunu bulamaz:
    -- rememberMissionKey calismaz, getMissionKey nil kalir, "Rezervasyonu birak"
    -- butonu HIC cikmaz ve rezervasyon detay satiri/harita isareti olu kalir.
    -- (PartnerEvent.newSync bunu bastan beri yapiyordu; burada atlanmisti.)
    self.objectId = ContractManager.getMissionObjectIdByKey(uniqueId)
    self.farmId = farmId or 0
    self.secondsLeft = secondsLeft or 0
    self.farmName = farmName or ""
    return self
end

function ContractManagerReservationEvent.newRequest(kind, uniqueId, objectId)
    local self = ContractManagerReservationEvent.emptyNew()
    self.kind = kind
    self.uniqueId = uniqueId or ""
    self.objectId = objectId or 0
    self.farmId = 0
    self.secondsLeft = 0
    self.farmName = ""
    return self
end

function ContractManagerReservationEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.kind)
    streamWriteString(streamId, tostring(self.uniqueId))
    streamWriteUIntN(streamId, self.farmId or 0, FarmManager.FARM_ID_SEND_NUM_BITS)
    streamWriteInt32(streamId, self.secondsLeft or 0)
    streamWriteString(streamId, tostring(self.farmName or ""))
    NetworkUtil.writeNodeObjectId(streamId, self.objectId or 0)
end

function ContractManagerReservationEvent:readStream(streamId, connection)
    self.kind = streamReadUInt8(streamId)
    self.uniqueId = streamReadString(streamId)
    self.farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    self.secondsLeft = streamReadInt32(streamId)
    self.farmName = streamReadString(streamId)
    self.objectId = NetworkUtil.readNodeObjectId(streamId)
    self:run(connection)
end

---baglantinin kullanicisinin ciftligi (sunucu)
function ContractManagerReservationEvent.getConnectionFarmId(connection)
    if g_currentMission == nil or g_currentMission.userManager == nil or g_farmManager == nil then
        return nil
    end
    local ok, user = pcall(g_currentMission.userManager.getUserByConnection, g_currentMission.userManager, connection)
    if not ok or user == nil or user.getId == nil or g_farmManager.getFarmByUserId == nil then
        return nil
    end
    local farm = g_farmManager:getFarmByUserId(user:getId())
    if farm ~= nil then
        return farm.farmId
    end
    return nil
end

function ContractManagerReservationEvent:run(connection)
    local Res = ContractManagerReservation
    if Res == nil then
        return
    end
    if connection ~= nil and not connection:getIsServer() then
        -- sunucu: istemci istegi
        local farmId = ContractManagerReservationEvent.getConnectionFarmId(connection)
        if farmId == nil or farmId == 0 then
            return
        end
        local ok, key
        if self.kind == ContractManagerReservationEvent.RESERVE then
            local uniqueId = ContractManager.resolveMissionKey(self.objectId, self.uniqueId)
            ok, key = Res.reserve(uniqueId, farmId)
        elseif self.kind == ContractManagerReservationEvent.RELEASE then
            local uniqueId = ContractManager.resolveMissionKey(self.objectId, self.uniqueId)
            ok, key = Res.release(uniqueId, farmId, false)
        else
            return
        end
        if ContractManagerNotificationEvent ~= nil then
            connection:sendEvent(ContractManagerNotificationEvent.new(ContractManagerNotificationEvent.ADMIN_RESULT, 0, key, ok and 1 or 0))
        end
        return
    end
    if self.kind == ContractManagerReservationEvent.SYNC then
        -- kontrata sunucunun kimligini yapistir ki yerel aramalar eslesebilsin
        ContractManager.rememberMissionKey(self.objectId, self.uniqueId)
        Res.applyRemote(self.uniqueId, self.farmId, self.secondsLeft, self.farmName)
    end
end

---yerel: host ise dogrudan, istemci ise sunucuya
function ContractManagerReservationEvent.send(kind, uniqueId, objectId)
    local Res = ContractManagerReservation
    if g_currentMission ~= nil and g_currentMission:getIsServer() then
        local farmId = g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
        local ok, key
        if kind == ContractManagerReservationEvent.RESERVE then
            ok, key = Res.reserve(uniqueId, farmId)
        else
            ok, key = Res.release(uniqueId, farmId, false)
        end
        if ContractManagerAdmin ~= nil then ContractManagerAdmin.showResult(key, ok) end
        return ok, key
    end
    if g_client ~= nil then
        pcall(function()
            g_client:getServerConnection():sendEvent(ContractManagerReservationEvent.newRequest(kind, uniqueId, objectId))
        end)
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- ContractManagerMissionInfoEvent: kontratin urun/teslimat olcumu (sunucu -> istemci)
--   expectedLiters ve depositedLiters HICBIR writeStream'de gecmiyor; istemcide nil.
--   Kontrat ag nesnesi oldugu icin kimlik olarak nesne kimligi kullanilir.
-- ---------------------------------------------------------------------------

ContractManagerMissionInfoEvent = {}
local ContractManagerMissionInfoEvent_mt = Class(ContractManagerMissionInfoEvent, Event)

InitEventClass(ContractManagerMissionInfoEvent, "ContractManagerMissionInfoEvent")

function ContractManagerMissionInfoEvent.emptyNew()
    return Event.new(ContractManagerMissionInfoEvent_mt)
end

function ContractManagerMissionInfoEvent.new(objectId, data)
    local self = ContractManagerMissionInfoEvent.emptyNew()
    self.objectId = objectId or 0
    self.expected = data ~= nil and data.expected or 0
    self.deposited = data ~= nil and data.deposited or 0
    self.fillTypeIndex = data ~= nil and data.fillTypeIndex or 0
    self.yieldLiters = data ~= nil and data.yieldLiters or 0
    return self
end

function ContractManagerMissionInfoEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObjectId(streamId, self.objectId or 0)
    streamWriteInt32(streamId, self.expected or 0)
    streamWriteInt32(streamId, self.deposited or 0)
    streamWriteInt32(streamId, self.fillTypeIndex or 0)
    streamWriteInt32(streamId, self.yieldLiters or 0)
end

function ContractManagerMissionInfoEvent:readStream(streamId, connection)
    self.objectId = NetworkUtil.readNodeObjectId(streamId)
    self.expected = streamReadInt32(streamId)
    self.deposited = streamReadInt32(streamId)
    self.fillTypeIndex = streamReadInt32(streamId)
    self.yieldLiters = streamReadInt32(streamId)
    self:run(connection)
end

function ContractManagerMissionInfoEvent:run(connection)
    if ContractManagerMissionInfo == nil then
        return
    end
    -- yalnizca sunucudan istemciye anlamli
    if connection ~= nil and not connection:getIsServer() then
        return
    end
    ContractManagerMissionInfo.applyRemote(self.objectId, {
        expected = self.expected,
        deposited = self.deposited,
        fillTypeIndex = self.fillTypeIndex,
        yieldLiters = self.yieldLiters,
    })
end

-- ---------------------------------------------------------------------------
-- ContractManagerPartnerEvent: ortak kontrat
--   istemci -> sunucu: INVITE (uniqueId, hedef ciftlik) / ACCEPT / LEAVE / DECLINE
--   sunucu -> istemci: SYNC (uniqueId, sahip, ortak ciftlikler)
-- Sunucu istegi gonderenin ciftligini kendisi bulur; istemci ciftlik uyduramaz.
-- ---------------------------------------------------------------------------

ContractManagerPartnerEvent = {}
local ContractManagerPartnerEvent_mt = Class(ContractManagerPartnerEvent, Event)

InitEventClass(ContractManagerPartnerEvent, "ContractManagerPartnerEvent")

ContractManagerPartnerEvent.INVITE = 1
ContractManagerPartnerEvent.ACCEPT = 2
ContractManagerPartnerEvent.LEAVE = 3
ContractManagerPartnerEvent.SYNC = 4
ContractManagerPartnerEvent.DECLINE = 5
ContractManagerPartnerEvent.MAX_FARMS = 5

function ContractManagerPartnerEvent.emptyNew()
    return Event.new(ContractManagerPartnerEvent_mt)
end

---objectId: kontratin AG kimligi (istemcide uniqueId yok, bkz. ContractManager.getMissionKey)
function ContractManagerPartnerEvent.newRequest(kind, uniqueId, targetFarmId, objectId)
    local self = ContractManagerPartnerEvent.emptyNew()
    self.kind = kind
    self.uniqueId = uniqueId or ""
    self.objectId = objectId or 0
    self.pending = {}
    self.targetFarmId = targetFarmId or 0
    self.farms = {}
    return self
end

function ContractManagerPartnerEvent.newSync(uniqueId)
    local self = ContractManagerPartnerEvent.emptyNew()
    self.kind = ContractManagerPartnerEvent.SYNC
    self.uniqueId = uniqueId or ""
    -- SYNC'te kontratin ag kimligi de gider ki istemci hangi kontrat oldugunu bulabilsin
    self.objectId = ContractManager.getMissionObjectIdByKey(uniqueId)
    self.targetFarmId = 0
    self.farms = {}
    self.pending = {}
    local Part = ContractManagerPartnership
    local entry = Part ~= nil and Part.get(uniqueId) or nil
    if entry ~= nil then
        self.targetFarmId = entry.owner or 0
        for _, farmId in ipairs(Part.getFarms(uniqueId)) do
            if farmId ~= entry.owner and #self.farms < ContractManagerPartnerEvent.MAX_FARMS then
                self.farms[#self.farms + 1] = farmId
            end
        end
    end
    -- BEKLEYEN DAVETLER de gitmeli: istemci bunlari bilmezse hasPendingInvite hep
    -- false doner ve davet edilen oyuncuda "Ortakligi kabul et / Daveti reddet"
    -- butonlari HIC cikmaz (bildirim gelir ama yapacak bir sey yoktur).
    if Part ~= nil and Part.getPendingInfo ~= nil then
        for _, invite in ipairs(Part.getPendingInfo(uniqueId)) do
            if #self.pending < ContractManagerPartnerEvent.MAX_FARMS then
                self.pending[#self.pending + 1] = { farmId = invite.farmId, minutesLeft = invite.minutesLeft }
            end
        end
    end
    return self
end

function ContractManagerPartnerEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.kind)
    streamWriteString(streamId, tostring(self.uniqueId))
    streamWriteUIntN(streamId, self.targetFarmId or 0, FarmManager.FARM_ID_SEND_NUM_BITS)
    streamWriteUInt8(streamId, #self.farms)
    for _, farmId in ipairs(self.farms) do
        streamWriteUIntN(streamId, farmId, FarmManager.FARM_ID_SEND_NUM_BITS)
    end
    NetworkUtil.writeNodeObjectId(streamId, self.objectId or 0)
    streamWriteUInt8(streamId, #self.pending)
    for _, invite in ipairs(self.pending) do
        streamWriteUIntN(streamId, invite.farmId, FarmManager.FARM_ID_SEND_NUM_BITS)
        streamWriteUInt8(streamId, math.min(255, math.max(0, invite.minutesLeft or 0)))
    end
end

function ContractManagerPartnerEvent:readStream(streamId, connection)
    self.kind = streamReadUInt8(streamId)
    self.uniqueId = streamReadString(streamId)
    self.targetFarmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    self.farms = {}
    local count = streamReadUInt8(streamId)
    for _ = 1, count do
        self.farms[#self.farms + 1] = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    end
    self.objectId = NetworkUtil.readNodeObjectId(streamId)
    self.pending = {}
    local pendingCount = streamReadUInt8(streamId)
    for _ = 1, pendingCount do
        local farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
        local minutesLeft = streamReadUInt8(streamId)
        self.pending[#self.pending + 1] = { farmId = farmId, minutesLeft = minutesLeft }
    end
    self:run(connection)
end

function ContractManagerPartnerEvent:run(connection)
    local Part = ContractManagerPartnership
    if Part == nil then
        return
    end
    if connection ~= nil and not connection:getIsServer() then
        local farmId = ContractManagerReservationEvent ~= nil
            and ContractManagerReservationEvent.getConnectionFarmId(connection) or nil
        if farmId == nil or farmId == 0 then
            return
        end
        local uniqueId = ContractManager.resolveMissionKey(self.objectId, self.uniqueId)
        local ok, key = Part.handle(self.kind, uniqueId, farmId, self.targetFarmId)
        if ContractManagerNotificationEvent ~= nil then
            connection:sendEvent(ContractManagerNotificationEvent.new(ContractManagerNotificationEvent.ADMIN_RESULT, 0, key, ok and 1 or 0))
        end
        return
    end
    if self.kind == ContractManagerPartnerEvent.SYNC then
        -- kontrata sunucunun kimligini yapistir ki isPartner/getShares eslesebilsin
        local resolved = ContractManager.rememberMissionKey(self.objectId, self.uniqueId)
        Part.applyRemote(self.uniqueId, self.targetFarmId, self.farms, self.pending)
        -- Teshis: senkron geldi mi, kontrat nesnesi bulundu mu? objectId=0 ya da
        -- resolved=false ise istemci ortakligi HIC goremez (kimlik eslesmez).
        ContractManager.info("Partnership sync: contract=%s objectId=%s resolved=%s owner=%s partners=%d pending=%d",
            tostring(self.uniqueId), tostring(self.objectId), tostring(resolved ~= nil),
            tostring(self.targetFarmId), #(self.farms or {}), #(self.pending or {}))
    end
end

---yerel: host ise dogrudan, istemci ise sunucuya
function ContractManagerPartnerEvent.send(kind, uniqueId, targetFarmId, objectId)
    local Part = ContractManagerPartnership
    if g_currentMission ~= nil and g_currentMission:getIsServer() then
        local farmId = g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
        local ok, key = Part.handle(kind, ContractManager.resolveMissionKey(objectId, uniqueId), farmId, targetFarmId)
        if ContractManagerAdmin ~= nil then
            ContractManagerAdmin.showResult(key, ok)
        end
        return ok, key
    end
    if g_client ~= nil then
        pcall(function()
            g_client:getServerConnection():sendEvent(ContractManagerPartnerEvent.newRequest(kind, uniqueId, targetFarmId, objectId))
        end)
    end
    return nil
end
