--
-- FS25_ContractManager - FS25_DiscordBridge entegrasyonu (yalnizca sunucu)
--
-- Kopru modu yukluyse (DiscordBridge.EventLog.emit) kontrat olaylarini NDJSON gunlugune
-- yazar; kopru dosyayi FTP ile ceker ve Discord'a iletir. HTTP yok - FS25 Lua'sinda yok.
-- Kopru yoksa veya integrations#discord kapaliysa sessizdir.
--
-- Mod yukleme sirasi alfabetik: ContractManager, DiscordBridge'den ONCE yuklenir; bu yuzden
-- kopru varligi her olayda (gec) kontrol edilir, yukleme aninda degil.
--
-- Olay turleri (kopru alerts.ts ile eslesir):
--   cm_contract_accepted  {id,title,typeName,farmId,fieldId,reward,minutesLeft}
--   cm_contract_finished  {id,title,typeName,farmId,fieldId,finishState,finishStateName,reward,penalty}
--   cm_contract_paid      {id,title,farmId,payout}
--   cm_contract_warning   {id,title,farmId,minutesLeft}
--   cm_guard_blocked      {code,codeName,farmId,fillType,amount}
--   cm_settings_changed   {key,value}
--

ContractManagerDiscord = {
    emitted = 0,
    dropped = 0,
}

local Discord = ContractManagerDiscord

-- oyunun enum degerlerinden ad tablosu (degerler surume gore degisebilir; tahmin etme)
local FINISH_STATE_NAMES = {}
local function stateName(value)
    if MissionFinishState ~= nil and FINISH_STATE_NAMES[value] == nil then
        for name, v in pairs(MissionFinishState) do
            if type(v) == "number" then
                local lower = name:lower():gsub("_(%l)", function(c) return c:upper() end)
                FINISH_STATE_NAMES[v] = lower
            end
        end
    end
    return FINISH_STATE_NAMES[value] or tostring(value)
end
local GUARD_CODE_NAMES = { [1] = "cancelBlocked", [2] = "forcedPurge", [3] = "baleBlocked" }

function Discord.getEmitter()
    if DiscordBridge == nil or DiscordBridge.EventLog == nil then
        return nil
    end
    local emit = DiscordBridge.EventLog.emit
    if type(emit) ~= "function" then
        return nil
    end
    return emit
end

function Discord.isEnabled()
    if ContractManagerSettings == nil or not ContractManagerSettings:get("integrations.discord") then
        return false
    end
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() then
        return false
    end
    return Discord.getEmitter() ~= nil
end

---Olay yaz. Kopru yoksa sessizce duser. Donus: yazildi mi
function Discord.emit(eventType, payload)
    if not Discord.isEnabled() then
        Discord.dropped = Discord.dropped + 1
        return false
    end
    local ok, err = pcall(Discord.getEmitter(), eventType, payload)
    if not ok then
        ContractManager.warning("Discord emit failed: %s", tostring(err))
        return false
    end
    Discord.emitted = Discord.emitted + 1
    return true
end

-- ---------------------------------------------------------------------------
-- olay govdeleri (saf; test edilir)
-- ---------------------------------------------------------------------------

local function missionTitle(mission)
    if mission == nil then return nil end
    if mission.title ~= nil then return tostring(mission.title) end
    if mission.getTitle ~= nil then
        local t = mission:getTitle()
        if t ~= nil then return tostring(t) end
    end
    return nil
end

local function minutesLeft(mission)
    if mission ~= nil and mission.getMinutesLeft ~= nil then
        local ok, m = pcall(mission.getMinutesLeft, mission)
        if ok and type(m) == "number" then
            return math.floor(m)
        end
    end
    return nil
end

function Discord.payloadAccepted(mission, meta)
    return {
        id = meta.id, title = missionTitle(mission), typeName = meta.typeName, farmId = meta.farmId,
        fieldId = meta.fieldId, reward = math.floor((meta.rewardAtAccept or 0) + 0.5), minutesLeft = minutesLeft(mission),
    }
end

function Discord.payloadFinished(mission, entry)
    local penalty = 0
    if ContractManagerReward ~= nil and ContractManagerReward.getPenalty ~= nil then
        penalty = ContractManagerReward.getPenalty(mission) or 0
    end
    return {
        id = entry.id, title = missionTitle(mission), typeName = entry.typeName, farmId = entry.farmId,
        fieldId = entry.fieldId, finishState = entry.finishState,
        finishStateName = stateName(entry.finishState),
        reward = math.floor((entry.reward or 0) + 0.5), penalty = math.floor(penalty + 0.5),
        reputation = ContractManagerReputation ~= nil and ContractManagerReputation.getReputation(entry.farmId) or nil,
    }
end

function Discord.payloadPaid(mission, entry)
    return { id = entry.id, title = missionTitle(mission), farmId = entry.farmId, payout = math.floor((entry.payout or 0) + 0.5) }
end

function Discord.payloadWarning(mission, minutes)
    return { id = mission.uniqueId, title = missionTitle(mission), farmId = mission.farmId, minutesLeft = minutes }
end

function Discord.payloadGuard(code, farmId, fillTypeIndex, amount)
    local fillType = nil
    if g_fillTypeManager ~= nil and fillTypeIndex ~= nil then
        local ft = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
        if ft ~= nil then fillType = ft.name or ft.title end
    end
    return { code = code, codeName = GUARD_CODE_NAMES[code] or tostring(code), farmId = farmId, fillType = fillType, amount = math.floor((amount or 0) + 0.5) }
end

-- ---------------------------------------------------------------------------
-- mesaj abonelikleri (Registry / Duration / Guard / Settings yayinlar)
-- ---------------------------------------------------------------------------

function Discord.install()
    if g_messageCenter == nil or g_messageCenter.subscribe == nil then
        return
    end
    g_messageCenter:subscribe(ContractManager.MESSAGE_CONTRACT_ACCEPTED, function(_, mission, meta)
        Discord.emit("cm_contract_accepted", Discord.payloadAccepted(mission, meta))
    end, Discord)
    g_messageCenter:subscribe(ContractManager.MESSAGE_CONTRACT_FINISHED, function(_, mission, entry)
        Discord.emit("cm_contract_finished", Discord.payloadFinished(mission, entry))
    end, Discord)
    g_messageCenter:subscribe(ContractManager.MESSAGE_CONTRACT_PAID, function(_, mission, entry)
        Discord.emit("cm_contract_paid", Discord.payloadPaid(mission, entry))
    end, Discord)
    g_messageCenter:subscribe(ContractManager.MESSAGE_CONTRACT_WARNING, function(_, mission, minutes)
        Discord.emit("cm_contract_warning", Discord.payloadWarning(mission, minutes))
    end, Discord)
    g_messageCenter:subscribe(ContractManager.MESSAGE_GUARD_BLOCKED, function(_, code, farmId, fillTypeIndex, amount)
        Discord.emit("cm_guard_blocked", Discord.payloadGuard(code, farmId, fillTypeIndex, amount))
    end, Discord)
    g_messageCenter:subscribe(ContractManager.MESSAGE_CONTRACT_TRANSFERRED, function(_, mission, oldFarmId, newFarmId)
        Discord.emit("cm_contract_transferred", { id = mission and mission.uniqueId, title = mission and mission.title, fromFarmId = oldFarmId, farmId = newFarmId })
    end, Discord)
    g_messageCenter:subscribe(ContractManager.MESSAGE_SETTINGS_CHANGED, function(_, key, value)
        if key ~= nil then
            Discord.emit("cm_settings_changed", { key = tostring(key), value = value })
        end
    end, Discord)
end

Discord.install()
