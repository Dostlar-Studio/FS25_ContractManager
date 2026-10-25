--
-- FS25_ContractManager - kural durumu senkronu (sunucu -> istemci, 1.27.0.0)
--
-- Odul ve ceza gosterimi icin istemcinin bilmesi gereken sunucu kayitlari: ciftlik basina itibar ve art arda
-- basarisizlik serisi, tarla zincirleri ve NPC is sayaclari. 1.26.0.0'a kadar hicbiri istemciye gitmiyordu:
-- zincir ve NPC primi oyuncularin ekraninda (liste, ayrinti, HUD) hep 0'di, sunucu ise primli oduyordu (ana
-- sunucuda ikisi de acik); itibar primi ancak ayar sekmesi acilip istatistik istenince gorunuyordu; ceza
-- onizlemesi seriyi bilmiyordu.
-- Sunucu degisiklikte (kontrat bitisi, itibar, ciftlik silinmesi) kirli isaretler, BROADCAST_DELAY_MS sonra
-- tek yayin yapar (ayni bitiste birden cok kayit degisir). Yeni baglanan istemci SyncEvent yanitinda alir.
-- Istemci gelen tabloyu kendi Registry kopyasina (fieldChain, npcJobs) ve itibar kopyasina yazar: Chain/Npc/
-- Reputation iki tarafta ayni kodla hesaplar.
--

ContractManagerRuleState = {
    BROADCAST_DELAY_MS = 2000,
    timer = nil,     -- sunucu: nil = bekleyen yayin yok
    farms = {},      -- istemci: farmId -> { reputation, failStreak }
}

local RuleState = ContractManagerRuleState

local function isServer()
    return g_currentMission ~= nil and g_currentMission:getIsServer()
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

---Art arda basarisizlik serisi: istemcide senkron kopya, sunucuda (ya da kopya yoksa) kayit
function RuleState.getFailStreak(farmId)
    if farmId == nil then
        return 0
    end
    local farm = not isServer() and RuleState.farms[farmId] or nil
    if farm ~= nil then
        return farm.failStreak or 0
    end
    local stats = ContractManagerRegistry ~= nil and ContractManagerRegistry.stats[farmId] or nil
    return stats ~= nil and (stats.failStreak or 0) or 0
end

---Sunucu kayitlarindan yayin verisi (saf; sirali)
function RuleState.collect()
    local data = { farms = {}, chains = {}, npc = {} }
    local R = ContractManagerRegistry
    if R == nil then
        return data
    end
    for _, farmId in ipairs(sortedKeys(R.stats)) do
        local st = R.stats[farmId]
        if farmId ~= 0 and #data.farms < 255 then
            data.farms[#data.farms + 1] = { farmId = farmId, reputation = st.reputation or 0, failStreak = st.failStreak or 0 }
        end
    end
    for _, fieldId in ipairs(sortedKeys(R.fieldChain)) do
        local c = R.fieldChain[fieldId]
        if #data.chains < 65535 then
            data.chains[#data.chains + 1] = { fieldId = fieldId, farmId = c.farmId or 0, step = c.step or 0, day = c.day or 0 }
        end
    end
    for _, farmId in ipairs(sortedKeys(R.npcJobs)) do
        for _, key in ipairs(sortedKeys(R.npcJobs[farmId])) do
            if #data.npc < 65535 then
                data.npc[#data.npc + 1] = { farmId = farmId, key = key, count = R.npcJobs[farmId][key] or 0 }
            end
        end
    end
    return data
end

---Istemci: gelen durumu uygula (itibar kopyasi, seri, zincir ve NPC kayitlari)
function RuleState.apply(data)
    if data == nil then
        return
    end
    RuleState.farms = {}
    for _, f in ipairs(data.farms or {}) do
        RuleState.farms[f.farmId] = { reputation = f.reputation or 0, failStreak = f.failStreak or 0 }
        if ContractManagerReputation ~= nil then
            ContractManagerReputation.setLocal(f.farmId, f.reputation or 0)
        end
    end
    local R = ContractManagerRegistry
    if R ~= nil then
        R.fieldChain = {}
        for _, c in ipairs(data.chains or {}) do
            R.fieldChain[c.fieldId] = { farmId = c.farmId, step = c.step, day = c.day }
        end
        R.npcJobs = {}
        for _, n in ipairs(data.npc or {}) do
            R.npcJobs[n.farmId] = R.npcJobs[n.farmId] or {}
            R.npcJobs[n.farmId][n.key] = n.count
        end
    end
    -- acik sayfadaki tutarlar degisti
    ContractManager.refreshManagePage()
end

-- ---------------------------------------------------------------------------
-- ag olayi
-- ---------------------------------------------------------------------------

ContractManagerRuleStateEvent = {}
local ContractManagerRuleStateEvent_mt = Class(ContractManagerRuleStateEvent, Event)

InitEventClass(ContractManagerRuleStateEvent, "ContractManagerRuleStateEvent")

function ContractManagerRuleStateEvent.emptyNew()
    return Event.new(ContractManagerRuleStateEvent_mt)
end

function ContractManagerRuleStateEvent.new(data)
    local self = ContractManagerRuleStateEvent.emptyNew()
    self.data = data or { farms = {}, chains = {}, npc = {} }
    return self
end

function ContractManagerRuleStateEvent:writeStream(streamId, connection)
    local data = self.data
    streamWriteUInt8(streamId, #data.farms)
    for _, f in ipairs(data.farms) do
        streamWriteUIntN(streamId, f.farmId, FarmManager.FARM_ID_SEND_NUM_BITS)
        streamWriteFloat32(streamId, f.reputation or 0)
        streamWriteUInt16(streamId, math.max(0, math.min(65535, f.failStreak or 0)))
    end
    streamWriteUInt16(streamId, #data.chains)
    for _, c in ipairs(data.chains) do
        streamWriteInt32(streamId, c.fieldId)
        streamWriteUIntN(streamId, c.farmId or 0, FarmManager.FARM_ID_SEND_NUM_BITS)
        streamWriteUInt8(streamId, math.max(0, math.min(255, c.step or 0)))
        streamWriteFloat32(streamId, c.day or 0)
    end
    streamWriteUInt16(streamId, #data.npc)
    for _, n in ipairs(data.npc) do
        streamWriteUIntN(streamId, n.farmId, FarmManager.FARM_ID_SEND_NUM_BITS)
        streamWriteString(streamId, tostring(n.key))
        streamWriteFloat32(streamId, n.count or 0)
    end
end

function ContractManagerRuleStateEvent:readStream(streamId, connection)
    local data = { farms = {}, chains = {}, npc = {} }
    for _ = 1, streamReadUInt8(streamId) do
        data.farms[#data.farms + 1] = {
            farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS),
            reputation = streamReadFloat32(streamId),
            failStreak = streamReadUInt16(streamId),
        }
    end
    for _ = 1, streamReadUInt16(streamId) do
        data.chains[#data.chains + 1] = {
            fieldId = streamReadInt32(streamId),
            farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS),
            step = streamReadUInt8(streamId),
            day = streamReadFloat32(streamId),
        }
    end
    for _ = 1, streamReadUInt16(streamId) do
        data.npc[#data.npc + 1] = {
            farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS),
            key = streamReadString(streamId),
            count = streamReadFloat32(streamId),
        }
    end
    self.data = data
    self:run(connection)
end

function ContractManagerRuleStateEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then
        return -- istemci durum uyduramaz
    end
    RuleState.apply(self.data)
end

-- ---------------------------------------------------------------------------
-- sunucu: yayin
-- ---------------------------------------------------------------------------

function RuleState.sendTo(connection)
    if connection ~= nil then
        connection:sendEvent(ContractManagerRuleStateEvent.new(RuleState.collect()))
    end
end

function RuleState.broadcast()
    if g_server ~= nil then
        g_server:broadcastEvent(ContractManagerRuleStateEvent.new(RuleState.collect()), false)
        return true
    end
    return false
end

---Sunucu: degisiklik oldu; yayin gecikmeyle (bir bitiste itibar, seri, zincir ve NPC ayni anda degisir)
function RuleState.markDirty()
    if isServer() and RuleState.timer == nil then
        RuleState.timer = RuleState.BROADCAST_DELAY_MS
    end
end

function RuleState:update(dt)
    if RuleState.timer == nil then
        return
    end
    RuleState.timer = RuleState.timer - (dt or 0)
    if RuleState.timer > 0 then
        return
    end
    RuleState.timer = nil
    if isServer() then
        RuleState.broadcast()
    end
end

function RuleState:loadMap()
    RuleState.farms = {}
    RuleState.timer = nil
end

function RuleState:deleteMap()
    RuleState.farms = {}
    RuleState.timer = nil
end

if g_messageCenter ~= nil then
    local function dirty()
        RuleState.markDirty()
    end
    g_messageCenter:subscribe(ContractManager.MESSAGE_CONTRACT_FINISHED, dirty, RuleState)
    g_messageCenter:subscribe(ContractManager.MESSAGE_REPUTATION_CHANGED, dirty, RuleState)
    if MessageType ~= nil and MessageType.FARM_DELETED ~= nil then
        g_messageCenter:subscribe(MessageType.FARM_DELETED, dirty, RuleState)
    end
end

addModEventListener(RuleState)
