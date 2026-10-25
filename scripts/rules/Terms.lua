--
-- FS25_ContractManager - Sozlesme sartlari (1.27.0.0)
--
-- Kabul aninda kontratin para sartlari donar: carpan, taban/tavan, ceza (taban/adim/tavan), kismi odeme,
-- kiralama carpani ve fiyat yuzdeleri (uzaklik / kucuk tarla / zorluk, kabul eden ciftlikle). Yonetici
-- ayari sonradan degistirse de calisan kontratin odemesi degismez. 1.26.0.0'a kadar carpan bitise kadar
-- canli okunuyordu: yonetici her degisiklik yaptiginda kabul edilmis kontratlarin odemesi geriye donuk
-- degisiyordu. Performans primleri (itibar, etkinlik, zincir, NPC) burada degil: bitiste dondurulur
-- (Reward.freeze).
--
-- Sunucu: kabulde yakalar (MESSAGE_CONTRACT_ACCEPTED), Registry'nin aktif kaydina ve bitiste gecmis kaydina
-- yazar (bitis ile kapatma arasinda yeniden baslatmada kapatma bunu okur). Eski kayittan gelen sartsiz
-- kontrat gorev basinda o anki ayarla donar. Bitis saati de (finishedHour, mutlak oyun saati) kayda girer:
-- istemci kendiliginden kapanmaya kalan sureyi bununla gosterir (AutoClose).
-- Istemci: ContractManagerTermsEvent ile alir (kabulde, bitiste ve baglanirken).
--

ContractManagerTerms = {
    byObjectId = {},   -- istemci: objectId -> sartlar (kontrat nesnesi henuz yoksa da tutulur)
}

local Terms = ContractManagerTerms

local BOOL, FLOAT = "bool", "float"

-- Sira ag akisinin sirasidir (PROTOCOL).
Terms.FIELDS = {
    { key = "multiplier",           setting = "reward.multiplier",          type = FLOAT },
    { key = "minReward",            setting = "reward.min",                 type = FLOAT },
    { key = "maxReward",            setting = "reward.max",                 type = FLOAT },
    { key = "failPenaltyPercent",   setting = "reward.failPenaltyPercent",  type = FLOAT },
    { key = "penaltyStepPercent",   setting = "reward.penaltyStepPercent",  type = FLOAT },
    { key = "penaltyMaxPercent",    setting = "reward.penaltyMaxPercent",   type = FLOAT },
    { key = "partialEnabled",       setting = "reward.partialEnabled",      type = BOOL },
    { key = "partialMinCompletion", setting = "reward.partialMinCompletion", type = FLOAT },
    { key = "partialFactor",        setting = "reward.partialFactor",       type = FLOAT },
    { key = "leaseCostMultiplier",  setting = "reward.leaseCostMultiplier", type = FLOAT },
    { key = "pricingDistance",      type = FLOAT },
    { key = "pricingSize",          type = FLOAT },
    { key = "pricingType",          type = FLOAT },
    { key = "finishedHour",         type = FLOAT },   -- 0 = bitmedi
}

Terms.BY_SETTING = {}
for _, field in ipairs(Terms.FIELDS) do
    if field.setting ~= nil then
        Terms.BY_SETTING[field.setting] = field
    end
end

local function isServer()
    return g_currentMission ~= nil and g_currentMission:getIsServer()
end

---Mutlak oyun saati: gun * 24 + gun icindeki saat
function Terms.toHour(day, dayTime)
    return (day or 0) * 24 + (dayTime or 0) / 3600000
end

function Terms.nowHour()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil then
        return 0
    end
    return Terms.toHour(env.currentMonotonicDay, env.dayTime)
end

-- ---------------------------------------------------------------------------
-- yakalama ve okuma
-- ---------------------------------------------------------------------------

---Simdiki ayarlarla sartlar (saf: ayarlar + kabul eden ciftlige gore fiyat dokumu)
function Terms.capture(mission, farmId)
    local S = ContractManagerSettings
    local terms = {}
    for _, field in ipairs(Terms.FIELDS) do
        if field.setting ~= nil then
            terms[field.key] = S:get(field.setting)
        end
    end
    local b = nil
    if ContractManagerPricing ~= nil and mission ~= nil then
        b = ContractManagerPricing.getBreakdown(mission, farmId)
    end
    terms.pricingDistance = b ~= nil and b.distance or 0
    terms.pricingSize = b ~= nil and b.size or 0
    terms.pricingType = b ~= nil and b.type or 0
    terms.finishedHour = 0
    return terms
end

---Kontratin sartlari: nesnede; sunucuda kayitlarda (aktif, bitmisse gecmis); istemcide senkron onbellekte.
---Kabul edilmemis kontratta nil (odul canli ayarla hesaplanir).
function Terms.get(mission)
    if mission == nil then
        return nil
    end
    if type(mission.cmTerms) == "table" then
        return mission.cmTerms
    end
    if mission.status == nil or mission.status == MissionStatus.CREATED then
        return nil
    end
    local terms = nil
    if isServer() then
        local R = ContractManagerRegistry
        local id = ContractManager.getMissionKey(mission)
        if R ~= nil and id ~= nil then
            local meta = R.active[id]
            terms = meta ~= nil and meta.terms or nil
            if terms == nil and (mission.status == MissionStatus.FINISHED or mission.status == MissionStatus.DISMISSED) then
                local entry = R:findHistoryEntry(id)
                terms = entry ~= nil and entry.terms or nil
            end
        end
    else
        local objectId = ContractManager.getMissionObjectId(mission)
        terms = objectId ~= 0 and Terms.byObjectId[objectId] or nil
    end
    if terms ~= nil then
        mission.cmTerms = terms
    end
    return terms
end

---Sozlesme degeri: kabul edilmisse kabuldeki, degilse canli ayar
function Terms.value(mission, settingId)
    local field = Terms.BY_SETTING[settingId]
    if field ~= nil then
        local terms = Terms.get(mission)
        if terms ~= nil and terms[field.key] ~= nil then
            return terms[field.key]
        end
    end
    return ContractManagerSettings:get(settingId)
end

---Fiyat yuzdeleri { distance, size, type, total }: kabul edilmisse kabuldeki, degilse canli
function Terms.getPricing(mission)
    local terms = Terms.get(mission)
    if terms ~= nil and terms.pricingDistance ~= nil then
        local b = { distance = terms.pricingDistance or 0, size = terms.pricingSize or 0, type = terms.pricingType or 0 }
        b.total = b.distance + b.size + b.type
        return b
    end
    if ContractManagerPricing ~= nil then
        return ContractManagerPricing.getBreakdown(mission)
    end
    return { distance = 0, size = 0, type = 0, total = 0 }
end

-- ---------------------------------------------------------------------------
-- sunucu: kabul, bitis, eski kayit
-- ---------------------------------------------------------------------------

---Sartlari kontrata ve kayitlara yaz (aktif kayit; bitmisse gecmis kaydi), istemcilere yolla
function Terms.attach(mission, terms)
    if mission == nil or terms == nil then
        return
    end
    mission.cmTerms = terms
    local R = ContractManagerRegistry
    local id = ContractManager.getMissionKey(mission)
    if R ~= nil and id ~= nil then
        if R.active[id] ~= nil then
            R.active[id].terms = terms
        elseif R.findHistoryEntry ~= nil then
            local entry = R:findHistoryEntry(id)
            if entry ~= nil then
                entry.terms = terms
            end
        end
    end
    Terms.broadcast(mission)
end

function Terms.onAccepted(mission, meta)
    if not isServer() or mission == nil then
        return
    end
    local farmId = meta ~= nil and meta.farmId or mission.farmId
    local terms = Terms.capture(mission, farmId)
    if meta ~= nil then
        meta.terms = terms
    end
    Terms.attach(mission, terms)
end

---Bitis: bitis saati sartlara (ve gecmis kaydina) yazilir; sartsiz kontrat (eski kayit) burada donar
function Terms.onFinished(mission, entry)
    if not isServer() or mission == nil then
        return
    end
    local terms = Terms.get(mission) or Terms.capture(mission, mission.farmId)
    if entry ~= nil and entry.finishedDay ~= nil then
        terms.finishedHour = Terms.toHour(entry.finishedDay, entry.finishedDayTime)
    else
        terms.finishedHour = Terms.nowHour()
    end
    if entry ~= nil then
        entry.terms = terms
    end
    Terms.attach(mission, terms)
end

---Gorev basinda (sunucu): sartsiz kabul edilmis kontrat (1.27.0.0 oncesi kayit) o anki ayarla donar. Bitmis ama
---gecmiste bitis saati olmayan kontratin bitis saati "simdi" sayilir. Donus: sart verilen kontrat sayisi.
function Terms.ensureAll()
    if not isServer() or g_missionManager == nil then
        return 0
    end
    local count = 0
    for _, mission in ipairs(g_missionManager.missions or {}) do
        local status = mission.status
        if status ~= nil and status ~= MissionStatus.CREATED and Terms.get(mission) == nil then
            local terms = Terms.capture(mission, mission.farmId)
            if status == MissionStatus.FINISHED or status == MissionStatus.DISMISSED then
                local entry = ContractManagerReward ~= nil and ContractManagerReward.historyEntry(mission) or nil
                if entry ~= nil and entry.finishedDay ~= nil then
                    terms.finishedHour = Terms.toHour(entry.finishedDay, entry.finishedDayTime)
                else
                    terms.finishedHour = Terms.nowHour()
                end
            end
            Terms.attach(mission, terms)
            count = count + 1
        end
    end
    if count > 0 then
        ContractManager.info("Contract terms: %d accepted contract(s) from an older save took the current settings", count)
    end
    return count
end

-- ---------------------------------------------------------------------------
-- kayit (Registry cagirir: aktif ve gecmis kaydinin "terms" alt anahtari)
-- ---------------------------------------------------------------------------

function Terms.writeXML(xmlId, key, terms)
    if type(terms) ~= "table" then
        return
    end
    for _, field in ipairs(Terms.FIELDS) do
        local value = terms[field.key]
        if field.type == BOOL then
            if value ~= nil then
                setXMLBool(xmlId, key .. "#" .. field.key, value == true)
            end
        elseif type(value) == "number" then
            setXMLFloat(xmlId, key .. "#" .. field.key, value)
        end
    end
end

---Kayittan sartlar; yoksa (1.27.0.0 oncesi kayit) nil
function Terms.readXML(xmlId, key)
    if getXMLFloat(xmlId, key .. "#multiplier") == nil then
        return nil
    end
    local terms = {}
    for _, field in ipairs(Terms.FIELDS) do
        if field.type == BOOL then
            terms[field.key] = getXMLBool(xmlId, key .. "#" .. field.key) == true
        else
            terms[field.key] = getXMLFloat(xmlId, key .. "#" .. field.key)
        end
    end
    return terms
end

-- ---------------------------------------------------------------------------
-- ag (sunucu -> istemci)
-- ---------------------------------------------------------------------------

ContractManagerTermsEvent = {}
local ContractManagerTermsEvent_mt = Class(ContractManagerTermsEvent, Event)

InitEventClass(ContractManagerTermsEvent, "ContractManagerTermsEvent")

function ContractManagerTermsEvent.emptyNew()
    return Event.new(ContractManagerTermsEvent_mt)
end

function ContractManagerTermsEvent.new(objectId, terms)
    local self = ContractManagerTermsEvent.emptyNew()
    self.objectId = objectId or 0
    self.terms = terms or {}
    return self
end

function ContractManagerTermsEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObjectId(streamId, self.objectId or 0)
    for _, field in ipairs(Terms.FIELDS) do
        local value = self.terms[field.key]
        if field.type == BOOL then
            streamWriteBool(streamId, value == true)
        else
            streamWriteFloat32(streamId, tonumber(value) or 0)
        end
    end
end

function ContractManagerTermsEvent:readStream(streamId, connection)
    self.objectId = NetworkUtil.readNodeObjectId(streamId)
    self.terms = {}
    for _, field in ipairs(Terms.FIELDS) do
        if field.type == BOOL then
            self.terms[field.key] = streamReadBool(streamId)
        else
            self.terms[field.key] = streamReadFloat32(streamId)
        end
    end
    self:run(connection)
end

function ContractManagerTermsEvent:run(connection)
    if connection ~= nil and not connection:getIsServer() then
        return -- istemci sart uyduramaz
    end
    Terms.applyRemote(self.objectId, self.terms)
end

---Istemci: gelen sartlari sakla ve kontrat nesnesine yapistir
function Terms.applyRemote(objectId, terms)
    if objectId == nil or objectId == 0 or terms == nil then
        return nil
    end
    Terms.byObjectId[objectId] = terms
    local mission = nil
    if NetworkUtil ~= nil and NetworkUtil.getObject ~= nil then
        mission = NetworkUtil.getObject(objectId)
    end
    if type(mission) == "table" then
        mission.cmTerms = terms
        mission.cmHudCache = nil
    end
    return mission
end

---Sunucu: kontratin sartlarini herkese (ya da tek baglantiya) yolla
function Terms.broadcast(mission, connection)
    if ContractManagerTermsEvent == nil or mission == nil or type(mission.cmTerms) ~= "table" then
        return false
    end
    local objectId = ContractManager.getMissionObjectId(mission)
    if objectId == 0 then
        return false
    end
    local event = ContractManagerTermsEvent.new(objectId, mission.cmTerms)
    if connection ~= nil then
        connection:sendEvent(event)
    elseif g_server ~= nil then
        g_server:broadcastEvent(event, false)
    else
        return false
    end
    return true
end

---Sunucu: yeni baglanan istemciye kabul edilmis butun kontratlarin sartlari
function Terms.sendAllTo(connection)
    if g_missionManager == nil then
        return 0
    end
    local sent = 0
    for _, mission in ipairs(g_missionManager.missions or {}) do
        if Terms.get(mission) ~= nil and Terms.broadcast(mission, connection) then
            sent = sent + 1
        end
    end
    return sent
end

function Terms:loadMap()
    Terms.byObjectId = {}
end

function Terms:deleteMap()
    Terms.byObjectId = {}
end

if g_messageCenter ~= nil then
    -- Kabul ve bitis oyunun kendi akisinda yayinlanir: hatamiz o akisi durdurmasin (kanca siniri korumali).
    g_messageCenter:subscribe(ContractManager.MESSAGE_CONTRACT_ACCEPTED, function(_, mission, meta)
        ContractManager.guard("Contract terms (accept)", Terms.onAccepted, mission, meta)
    end, Terms)
    g_messageCenter:subscribe(ContractManager.MESSAGE_CONTRACT_FINISHED, function(_, mission, entry)
        ContractManager.guard("Contract terms (finish)", Terms.onFinished, mission, entry)
    end, Terms)
    if MessageType ~= nil and MessageType.CURRENT_MISSION_START ~= nil then
        g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function()
            ContractManager.guard("Contract terms (load)", Terms.ensureAll)
        end, Terms)
    end
end

addModEventListener(Terms)
