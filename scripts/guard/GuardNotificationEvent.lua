ContractGuardNotificationEvent = {}
local ContractGuardNotificationEvent_mt = Class(ContractGuardNotificationEvent, Event)

InitEventClass(ContractGuardNotificationEvent, "ContractGuardNotificationEvent")

ContractGuardNotificationEvent.CANCEL_BLOCKED = 1
ContractGuardNotificationEvent.FORCED_PURGE = 2
ContractGuardNotificationEvent.BALE_BLOCKED = 3

function ContractGuardNotificationEvent.emptyNew()
    return Event.new(ContractGuardNotificationEvent_mt)
end

function ContractGuardNotificationEvent.new(code, farmId, fillTypeIndex, amount)
    local self = ContractGuardNotificationEvent.emptyNew()
    self.code = code
    self.farmId = farmId
    self.fillTypeIndex = fillTypeIndex or 0
    self.amount = amount or 0
    return self
end

function ContractGuardNotificationEvent:readStream(streamId, connection)
    self.code = streamReadUInt8(streamId)
    self.farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    self.fillTypeIndex = streamReadUIntN(streamId, FillTypeManager.SEND_NUM_BITS)
    self.amount = streamReadFloat32(streamId)
    self:run(connection)
end

function ContractGuardNotificationEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.code)
    streamWriteUIntN(streamId, self.farmId, FarmManager.FARM_ID_SEND_NUM_BITS)
    streamWriteUIntN(streamId, self.fillTypeIndex, FillTypeManager.SEND_NUM_BITS)
    streamWriteFloat32(streamId, self.amount)
end

function ContractGuardNotificationEvent.getFillTypeTitle(fillTypeIndex)
    local fillType = nil
    if g_fillTypeManager ~= nil then
        fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
    end
    if fillType ~= nil and fillType.title ~= nil then
        return fillType.title
    end
    return "?"
end

-- Bildirim metnini uretir; nil donerse gosterilecek bir sey yok.
function ContractGuardNotificationEvent.buildText(code, fillTypeIndex, amount)
    local fillTypeTitle = ContractGuardNotificationEvent.getFillTypeTitle(fillTypeIndex)
    if code == ContractGuardNotificationEvent.CANCEL_BLOCKED then
        return string.format(g_i18n:getText("cg_cancelBlocked"), fillTypeTitle)
    elseif code == ContractGuardNotificationEvent.FORCED_PURGE then
        local formattedAmount = g_i18n:formatVolume(amount or 0, 0)
        return string.format(g_i18n:getText("cg_forcedPurge"), fillTypeTitle, formattedAmount)
    elseif code == ContractGuardNotificationEvent.BALE_BLOCKED then
        return string.format(g_i18n:getText("cg_baleBlocked"), fillTypeTitle)
    end
    return nil
end

-- Yerel oyuncuya goster (istemci veya oynayan host). Ciftlik eslesmezse sessiz.
function ContractGuardNotificationEvent.showLocal(code, farmId, fillTypeIndex, amount)
    if g_currentMission == nil or g_currentMission.getFarmId == nil or g_currentMission:getFarmId() ~= farmId then
        return
    end
    local text = ContractGuardNotificationEvent.buildText(code, fillTypeIndex, amount)
    if text ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, text)
    end
end

function ContractGuardNotificationEvent:run(connection)
    -- Yalnizca sunucudan gelen olaylar gecerli; istemciler bildirim uretemez.
    if connection ~= nil and not connection:getIsServer() then
        return
    end
    ContractGuardNotificationEvent.showLocal(self.code, self.farmId, self.fillTypeIndex, self.amount)
end

function ContractGuardNotificationEvent.sendToFarm(code, farmId, fillTypeIndex, amount)
    if g_server == nil or farmId == nil then
        return
    end
    -- broadcastEvent(event, false) olayi host'ta lokal CALISTIRMAZ; tek oyunculu ve
    -- oynayan-host senaryosunda bildirimi dogrudan goster.
    if g_client ~= nil then
        ContractGuardNotificationEvent.showLocal(code, farmId, fillTypeIndex, amount)
    end
    g_server:broadcastEvent(ContractGuardNotificationEvent.new(code, farmId, fillTypeIndex, amount), false)
    if ContractManager ~= nil and ContractManager.publish ~= nil then
        ContractManager.publish(ContractManager.MESSAGE_GUARD_BLOCKED, code, farmId, fillTypeIndex, amount)
    end
end
