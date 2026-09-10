--
-- FS25_ContractManager - Discord Bridge web paneli entegrasyonu (yalnizca sunucu)
--
-- 1) Anlik goruntu bolumu: DiscordBridge.Collectors.STEPS'e "contractManager" adimi eklenir;
--    state.json icinde ayarlar, kontrol tanimlari (spec), kontrat turleri, ciftlik istatistigi
--    ve son kontratlar yer alir. Panel bunu okuyup formu kurar.
-- 2) Komutlar: DiscordBridge.CommandInbox.actions'a "cmSet" ve "cmAdmin" eklenir.
--    Kopru komut dosyasini FTP ile yazar; kutu yasi ve tekrarı kendisi denetler (nonce +
--    issuedAt). Panelde yalnizca admin rolu komut gonderebilir (kopru tarafi), burada da
--    sonuc yine sunucuda uygulanir.
--      cmSet   : text = ayar anahtari ("reward.multiplier" | "type:<ad>:enabled"), value = deger
--      cmAdmin : text = refresh | cancel | assign, value = uniqueId, farmId
--
-- Kopru modu bu moddan SONRA yuklendigi icin kayit gorev basinda yapilir.
--

ContractManagerPanel = {
    SECTION = "contractManager",
    HISTORY_LIMIT = 20,
    installed = false,
}

local Panel = ContractManagerPanel

-- Metin yardimcisi tek yerde: ContractManager.text (Main.lua). Main once yuklenir.
local function text(key, fallback)
    return ContractManager.text(key, fallback)
end

-- ---------------------------------------------------------------------------
-- anlik goruntu bolumu (saf; test edilir)
-- ---------------------------------------------------------------------------

function Panel.buildSection()
    local S = ContractManagerSettings
    local out = {
        version = ContractManager.VERSION,
        rulesEnabled = ContractManager:getRulesEnabled(),
        betterContracts = ContractManager:isBetterContractsLoaded(),
        guardEnabled = ContractManager.guardEnabled,
        settings = {},
        spec = {},
        types = {},
        farms = {},
        history = {},
        cooldowns = {},
    }
    out.partnerships = {}
    if ContractManagerPartnership ~= nil then
        for id, entry in pairs(ContractManagerPartnership.list) do
            local shares = ContractManagerPartnership.getShares(id)
            local farms = {}
            for _, farmId in ipairs(ContractManagerPartnership.getFarms(id)) do
                farms[#farms + 1] = { farmId = farmId, share = math.floor((shares[farmId] or 0) * 100 + 0.5) }
            end
            out.partnerships[#out.partnerships + 1] = { uniqueId = id, owner = entry.owner, farms = farms }
        end
    end
    out.reservations = {}
    if ContractManagerReservation ~= nil then
        ContractManagerReservation.prune()
        for id, r in pairs(ContractManagerReservation.list) do
            out.reservations[#out.reservations + 1] = { uniqueId = id, farmId = r.farmId, farmName = r.farmName, secondsLeft = math.max(0, math.floor((r.untilMs - ContractManagerReservation.nowMs()) / 1000)) }
        end
    end
    if ContractManagerRegistry ~= nil and ContractManagerCooldown ~= nil then
        ContractManagerCooldown.prune()
        for fieldId, untilHour in pairs(ContractManagerRegistry.fieldCooldowns) do
            out.cooldowns[#out.cooldowns + 1] = { fieldId = fieldId, hoursLeft = math.floor((untilHour - ContractManagerCooldown.nowHours()) * 10 + 0.5) / 10 }
        end
    end
    for _, spec in ipairs(S.SPEC) do
        out.settings[spec.id] = S:get(spec.id)
        out.spec[#out.spec + 1] = { id = spec.id, type = spec.type, default = spec.default, min = spec.min, max = spec.max }
    end
    if g_missionManager ~= nil and g_missionManager.missionTypes ~= nil then
        for _, mt in ipairs(g_missionManager.missionTypes) do
            local enabled, weight = S:getTypeConfig(mt.name)
            out.types[#out.types + 1] = {
                name = mt.name, enabled = enabled, weight = weight,
                maxNumInstances = mt.data ~= nil and mt.data.maxNumInstances or nil,
                numInstances = mt.data ~= nil and mt.data.numInstances or nil,
            }
        end
    end
    local R = ContractManagerRegistry
    if R ~= nil then
        local farmIds = {}
        for farmId in pairs(R.stats) do farmIds[#farmIds + 1] = farmId end
        table.sort(farmIds)
        for _, farmId in ipairs(farmIds) do
            local st = R.stats[farmId]
            out.farms[#out.farms + 1] = { farmId = farmId, completed = st.completed, failed = st.failed, canceled = st.canceled,
                timedOut = st.timedOut, earned = st.earned, penalties = st.penalties, reputation = st.reputation or 0 }
        end
        for i, e in ipairs(R:getHistory(nil)) do
            if i > Panel.HISTORY_LIMIT then break end
            out.history[#out.history + 1] = { id = e.id, typeName = e.typeName, farmId = e.farmId, fieldId = e.fieldId,
                finishState = e.finishState, reward = e.reward, payout = e.payout, finishedDay = e.finishedDay, acceptedDay = e.acceptedDay }
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- komutlar (saf; test edilir). Donus: ok, mesaj
-- ---------------------------------------------------------------------------

---string degeri anahtarin turune gore cevir
function Panel.parseValue(key, raw)
    local S = ContractManagerSettings
    local name, field = ContractManagerSettingsTab.parseTypeKey(key)
    local kind
    if name ~= nil then
        kind = field == "enabled" and "bool" or "float"
    else
        local spec = S.SPEC_BY_ID[key]
        if spec == nil then return nil, "unknown setting: " .. tostring(key) end
        kind = spec.type
    end
    if kind == "bool" then
        if type(raw) == "boolean" then return raw end
        local s = tostring(raw or ""):lower()
        if s == "true" or s == "1" or s == "on" or s == "yes" then return true end
        if s == "false" or s == "0" or s == "off" or s == "no" then return false end
        return nil, "expected true/false"
    elseif kind == "int" or kind == "float" then
        local n = tonumber(raw)
        if n == nil then return nil, "expected number" end
        return n
    end
    return tostring(raw or "")
end

function Panel.commandSet(cmd)
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return false, "server only"
    end
    local key = cmd.text
    if key == nil or key == "" then
        return false, "missing key"
    end
    local value, err = Panel.parseValue(key, cmd.value)
    if err ~= nil then
        return false, err
    end
    local applied = ContractManagerSettingsTab.applyOnServer(key, value)
    if applied == nil then
        return false, "setting not applied: " .. tostring(key)
    end
    return true, string.format("%s = %s", key, tostring(applied))
end

function Panel.commandAdmin(cmd)
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return false, "server only"
    end
    local A = ContractManagerAdmin
    local action = tostring(cmd.text or ""):lower()
    local map = { refresh = A.ACTION_REFRESH, cancel = A.ACTION_CANCEL, assign = A.ACTION_ASSIGN, transfer = A.ACTION_TRANSFER }
    if map[action] == nil then
        return false, "unknown admin action: " .. action
    end
    local ok, key = A.execute(map[action], cmd.value ~= "" and cmd.value or nil, tonumber(cmd.farmId))
    return ok, text(key, key)
end

-- ---------------------------------------------------------------------------
-- kayit
-- ---------------------------------------------------------------------------

function Panel.install()
    if Panel.installed or DiscordBridge == nil then
        return false
    end
    local mission = g_currentMission
    if mission == nil or not mission:getIsServer() then
        return false
    end
    local count = 0
    local C = DiscordBridge.Collectors
    if C ~= nil and type(C.STEPS) == "table" then
        local exists = false
        for _, step in ipairs(C.STEPS) do
            if step[1] == Panel.SECTION then exists = true end
        end
        if not exists then
            table.insert(C.STEPS, { Panel.SECTION, run = function(ctx) return Panel.buildSection() end })
        end
        count = count + 1
    end
    local Inbox = DiscordBridge.CommandInbox
    if Inbox ~= nil and type(Inbox.actions) == "table" then
        Inbox.actions.cmSet = Panel.commandSet
        Inbox.actions.cmAdmin = Panel.commandAdmin
        count = count + 1
    end
    Panel.installed = count > 0
    if Panel.installed then
        ContractManager.info("Discord Bridge panel hooks installed (snapshot section + cmSet/cmAdmin)")
    end
    return Panel.installed
end

if g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_START ~= nil then
    g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function()
        Panel.install()
    end, Panel)
end
