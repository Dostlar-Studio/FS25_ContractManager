--
-- FS25_ContractManager - Ortak kontrat
--
-- Kontrati alan ciftlik (sahip) baska bir ciftligi davet eder, karşi taraf kabul edince
-- ortaklik baslar. Odul KATKIYA gore bolunur; katkiyi oyun tutmadigi icin mod olcer:
--   * teslimatli kontrat : kontrat istasyonuna bosaltilan litre (Guard bosaltma yolunda sayilir)
--   * tarla isi kontrati : getIsMissionWorkAllowed cagri sayaci (kim ne kadar calisti)
-- Iki kova da doluysa paylar ortalanir; yalnizca biri doluysa o kullanilir; hicbiri yoksa
-- esit bolunur.
--
-- Kararlar (2026-09-08): katkiya gore paylasim, davet/kabul akisi, limit ve kota yalnizca
-- sahibe islenir, itibar ortaga yarim yazilir.
--
-- Guard: ortak ciftlikler kontrat urununu tasiyabilsin diye kontrat "kendi ciftliginin
-- kontrati" gibi gorunur (getMatchingMissions sarmali). Aksi halde ortagin araci korumasiz
-- kalir ve sahibin aracindan ortaga aktarim engellenirdi.
--
-- Odeme: oyun dismiss'te tum tutari sahibe oder; hemen ardindan ortagin payi sahipten
-- ortaga aktarilir (negatif tutarda zarar da paylasilir).
--

ContractManagerPartnership = {
    list = {},       -- uniqueId -> { owner, partners = {farmId->true}, liters = {}, work = {} }
    pending = {},    -- uniqueId -> { farmId -> gecerlilik ms }
}

local Part = ContractManagerPartnership

local function settings()
    return ContractManagerSettings
end

local function nowMs()
    if g_currentMission ~= nil and type(g_currentMission.time) == "number" then
        return g_currentMission.time
    end
    return 0
end

function Part.isEnabled()
    return ContractManager:getRulesEnabled() and settings():get("partnership.enabled") == true
end

function Part.getMissionId(mission)
    if type(mission) == "string" then
        return mission
    end
    -- Istemcide mission.uniqueId nil'dir; SYNC sirasinda yapistirilan kopyayi da
    -- kabul et, yoksa ortaklik durumu istemcide hic gorunmez.
    if mission == nil then
        return nil
    end
    if ContractManager ~= nil and ContractManager.getMissionKey ~= nil then
        local key = ContractManager.getMissionKey(mission)
        if key ~= nil then
            return tostring(key)
        end
    end
    return mission.uniqueId ~= nil and tostring(mission.uniqueId) or nil
end

function Part.get(mission)
    local id = Part.getMissionId(mission)
    return id ~= nil and Part.list[id] or nil
end

---sahip veya ortak mi?
function Part.isMember(mission, farmId)
    local entry = Part.get(mission)
    if entry == nil or farmId == nil then
        return false
    end
    return entry.owner == farmId or entry.partners[farmId] == true
end

---yalnizca ortak (sahip degil)
function Part.isPartner(mission, farmId)
    local entry = Part.get(mission)
    return entry ~= nil and farmId ~= nil and entry.partners[farmId] == true
end

function Part.getFarms(mission)
    local entry = Part.get(mission)
    if entry == nil then
        return {}
    end
    local farms = { entry.owner }
    local ids = {}
    for farmId in pairs(entry.partners) do ids[#ids + 1] = farmId end
    table.sort(ids)
    for _, farmId in ipairs(ids) do farms[#farms + 1] = farmId end
    return farms
end

function Part.countPartners(entry)
    local n = 0
    for _ in pairs(entry.partners) do n = n + 1 end
    return n
end

-- ---------------------------------------------------------------------------
-- katki
-- ---------------------------------------------------------------------------

local function ensureEntry(mission)
    local id = Part.getMissionId(mission)
    if id == nil then
        return nil
    end
    return Part.list[id]
end

function Part.addLiters(mission, farmId, liters)
    local entry = ensureEntry(mission)
    if entry == nil or farmId == nil or type(liters) ~= "number" or liters <= 0 then
        return
    end
    entry.liters[farmId] = (entry.liters[farmId] or 0) + liters
end

function Part.addWork(mission, farmId)
    local entry = ensureEntry(mission)
    if entry == nil or farmId == nil then
        return
    end
    entry.work[farmId] = (entry.work[farmId] or 0) + 1
end

local function bucketShares(bucket, farms)
    local total = 0
    for _, farmId in ipairs(farms) do
        total = total + (bucket[farmId] or 0)
    end
    if total <= 0 then
        return nil
    end
    local shares = {}
    for _, farmId in ipairs(farms) do
        shares[farmId] = (bucket[farmId] or 0) / total
    end
    return shares
end

---ciftlik -> pay (0..1). Katki yoksa esit boluner.
function Part.getShares(mission)
    local entry = Part.get(mission)
    if entry == nil then
        return {}
    end
    local farms = Part.getFarms(mission)
    local litersShares = bucketShares(entry.liters, farms)
    local workShares = bucketShares(entry.work, farms)
    local shares = {}
    for _, farmId in ipairs(farms) do
        if litersShares ~= nil and workShares ~= nil then
            shares[farmId] = (litersShares[farmId] + workShares[farmId]) / 2
        elseif litersShares ~= nil then
            shares[farmId] = litersShares[farmId]
        elseif workShares ~= nil then
            shares[farmId] = workShares[farmId]
        else
            shares[farmId] = 1 / #farms
        end
    end
    return shares
end

---Kontrata katilan HER ciftligin kendi kaydi: rol, katki, pay ve hak edis.
---Ortak kontrati "ciftlik basina ayri kontrat" gibi gostermek icin kullanilir.
---Saf: odul disaridan verilir, motora dokunmaz.
---Donus: { {farmId, isOwner, liters, work, share, payout}, ... } sahip once.
function Part.getParticipants(mission, reward)
    local entry = Part.get(mission)
    if entry == nil then
        return {}
    end
    reward = tonumber(reward) or 0
    local shares = Part.getShares(mission)
    local out = {}
    for _, farmId in ipairs(Part.getFarms(mission)) do
        local share = shares[farmId] or 0
        out[#out + 1] = {
            farmId = farmId,
            isOwner = entry.owner == farmId,
            liters = entry.liters[farmId] or 0,
            work = entry.work[farmId] or 0,
            share = share,
            payout = reward * share,
        }
    end
    return out
end

---Katki olculdu mu? (olculmediyse pay esit boluner, yuzde gostermek yaniltici olur)
function Part.hasContribution(mission)
    local entry = Part.get(mission)
    return entry ~= nil and (next(entry.liters) ~= nil or next(entry.work) ~= nil)
end

---Bekleyen davetler: { {farmId, minutesLeft}, ... } (saf; sirali)
function Part.getPendingInfo(mission)
    Part.prunePending()
    local id = Part.getMissionId(mission)
    local farms = id ~= nil and Part.pending[id] or nil
    if farms == nil then
        return {}
    end
    local now = nowMs()
    local out = {}
    for farmId, untilMs in pairs(farms) do
        out[#out + 1] = { farmId = farmId, minutesLeft = math.max(0, math.floor((untilMs - now) / 60000 + 0.5)) }
    end
    table.sort(out, function(a, b) return a.farmId < b.farmId end)
    return out
end

-- ---------------------------------------------------------------------------
-- davet / kabul / ayril (sunucu; saf, test edilir). Donus: ok, l10n anahtari
-- ---------------------------------------------------------------------------

function Part.prunePending()
    local now = nowMs()
    for id, farms in pairs(Part.pending) do
        for farmId, untilMs in pairs(farms) do
            if untilMs <= now then
                farms[farmId] = nil
            end
        end
        if next(farms) == nil then
            Part.pending[id] = nil
        end
    end
end

function Part.hasPendingInvite(mission, farmId)
    Part.prunePending()
    local id = Part.getMissionId(mission)
    local farms = id ~= nil and Part.pending[id] or nil
    return farms ~= nil and farms[farmId] ~= nil
end

function Part.invite(uniqueId, requesterFarmId, targetFarmId)
    if not Part.isEnabled() then
        return false, "cm_partDisabled"
    end
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.findMission(uniqueId) or nil
    if mission == nil then
        return false, "cm_adminNotFound"
    end
    if mission.status ~= MissionStatus.RUNNING and mission.status ~= MissionStatus.PREPARING then
        return false, "cm_adminNotActive"
    end
    if mission.farmId ~= requesterFarmId then
        return false, "cm_partNotOwner"
    end
    targetFarmId = tonumber(targetFarmId)
    if targetFarmId == nil or targetFarmId <= 0 or targetFarmId == mission.farmId then
        return false, "cm_adminNoFarm"
    end
    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil and g_farmManager:getFarmById(targetFarmId) == nil then
        return false, "cm_adminNoFarm"
    end
    local entry = Part.get(uniqueId)
    if entry ~= nil and entry.partners[targetFarmId] then
        return false, "cm_partAlready"
    end
    if entry ~= nil and Part.countPartners(entry) >= (settings():get("partnership.maxPartners") or 1) then
        return false, "cm_partFull"
    end
    Part.prunePending()
    local id = Part.getMissionId(uniqueId)
    Part.pending[id] = Part.pending[id] or {}
    Part.pending[id][targetFarmId] = nowMs() + (settings():get("partnership.inviteMinutes") or 10) * 60000
    if ContractManagerNotificationEvent ~= nil and ContractManagerNotificationEvent.PARTNER_INVITE ~= nil then
        ContractManagerNotificationEvent.sendToFarm(ContractManagerNotificationEvent.PARTNER_INVITE, targetFarmId,
            tostring(mission.title or "?"), mission.farmId or 0)
    end
    -- davet edilen istemci butonu gorebilsin diye durumu yay
    Part.broadcast(id)
    ContractManager.info("Partnership invite: contract %s, farm %s -> farm %d", tostring(uniqueId), tostring(requesterFarmId), targetFarmId)
    return true, "cm_partInvited"
end

function Part.accept(uniqueId, farmId)
    if not Part.isEnabled() then
        return false, "cm_partDisabled"
    end
    if not Part.hasPendingInvite(uniqueId, farmId) then
        return false, "cm_partNoInvite"
    end
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.findMission(uniqueId) or nil
    if mission == nil then
        return false, "cm_adminNotFound"
    end
    if mission.status ~= MissionStatus.RUNNING and mission.status ~= MissionStatus.PREPARING then
        return false, "cm_adminNotActive"
    end
    local id = Part.getMissionId(uniqueId)
    local entry = Part.list[id]
    if entry == nil then
        entry = { owner = mission.farmId, partners = {}, liters = {}, work = {} }
        Part.list[id] = entry
    end
    if Part.countPartners(entry) >= (settings():get("partnership.maxPartners") or 1) then
        return false, "cm_partFull"
    end
    entry.partners[farmId] = true
    Part.pending[id][farmId] = nil
    Part.broadcast(id)
    Part.notifyOwner(ContractManagerNotificationEvent.PARTNER_ACCEPTED, entry.owner, mission, farmId)
    ContractManager.info("Partnership: farm %s joined contract %s (owner %s)", tostring(farmId), tostring(uniqueId), tostring(entry.owner))
    ContractManager.publish(ContractManager.MESSAGE_PARTNERSHIP_CHANGED, mission, entry.owner, farmId)
    return true, "cm_partJoined"
end

---Sahibe bildirim: kabul/ret (pencere olarak gosterilir). Saf degil; sunucuda calisir.
function Part.notifyOwner(code, ownerFarmId, mission, actorFarmId)
    if ContractManagerNotificationEvent == nil or code == nil or ownerFarmId == nil or ownerFarmId == 0 then
        return false
    end
    ContractManagerNotificationEvent.sendToFarm(code, ownerFarmId, tostring(mission ~= nil and mission.title or "?"), actorFarmId or 0)
    return true
end

---Daveti reddet: bekleyen kayit silinir, davet eden bilgilendirilir.
function Part.decline(uniqueId, farmId)
    if not Part.isEnabled() then
        return false, "cm_partDisabled"
    end
    local id = Part.getMissionId(uniqueId)
    Part.prunePending()
    local farms = id ~= nil and Part.pending[id] or nil
    if farms == nil or farms[farmId] == nil then
        return false, "cm_partNoInvite"
    end
    farms[farmId] = nil
    if next(farms) == nil then
        Part.pending[id] = nil
    end
    Part.broadcast(id)
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.findMission(uniqueId) or nil
    if mission ~= nil then
        Part.notifyOwner(ContractManagerNotificationEvent.PARTNER_DECLINED, mission.farmId, mission, farmId)
    end
    return true, "cm_partDeclined"
end

function Part.leave(uniqueId, farmId)
    local id = Part.getMissionId(uniqueId)
    local entry = id ~= nil and Part.list[id] or nil
    if entry == nil or not entry.partners[farmId] then
        return false, "cm_partNotMember"
    end
    entry.partners[farmId] = nil
    if next(entry.partners) == nil then
        Part.list[id] = nil
    end
    Part.broadcast(id)
    return true, "cm_partLeft"
end

function Part.clearForMission(mission)
    local id = Part.getMissionId(mission)
    if id == nil then
        return
    end
    Part.pending[id] = nil
    if Part.list[id] ~= nil then
        Part.list[id] = nil
        Part.broadcast(id)
    end
end

-- ---------------------------------------------------------------------------
-- odeme bolusumu (sunucu): oyun tutarin tamamini sahibe oder, ortagin payi aktarilir
-- ---------------------------------------------------------------------------

function Part.splitPayment(mission)
    local entry = Part.get(mission)
    if entry == nil or g_currentMission == nil or not g_currentMission:getIsServer() then
        return 0
    end
    local total = 0
    if mission.getTotalReward ~= nil then
        local value = mission:getTotalReward()
        if type(value) == "number" then
            total = value
        end
    end
    if total == 0 or g_currentMission.addMoney == nil then
        return 0
    end
    local shares = Part.getShares(mission)
    local moved = 0
    for farmId, share in pairs(shares) do
        if farmId ~= entry.owner and share > 0 then
            local amount = total * share
            g_currentMission:addMoney(-amount, entry.owner, MoneyType.MISSIONS, true, true)
            g_currentMission:addMoney(amount, farmId, MoneyType.MISSIONS, true, true)
            moved = moved + amount
            ContractManager.info("Partnership payout: contract %s, farm %d gets %.0f (%.0f%%)",
                tostring(Part.getMissionId(mission)), farmId, amount, share * 100)
        end
    end
    return moved
end

-- ---------------------------------------------------------------------------
-- hook govdeleri
-- ---------------------------------------------------------------------------

---ortak ciftlikler kontrat tarlasinda calisabilsin + katki sayilsin
function Part.overwriteIsMissionWorkAllowed(manager, superFunc, farmId, x, z, workAreaType, vehicle)
    local allowed = superFunc(manager, farmId, x, z, workAreaType, vehicle)
    if allowed then
        if manager.getMissionAtWorldPosition ~= nil then
            local mission = manager:getMissionAtWorldPosition(x, z)
            if mission ~= nil and Part.get(mission) ~= nil then
                Part.addWork(mission, farmId)
            end
        end
        return true
    end
    if not Part.isEnabled() or manager.getMissionAtWorldPosition == nil then
        return false
    end
    local mission = manager:getMissionAtWorldPosition(x, z)
    if mission == nil or not Part.isPartner(mission, farmId) then
        return false
    end
    if mission.getIsWorkAllowed ~= nil and not mission:getIsWorkAllowed(mission.farmId, x, z, workAreaType, vehicle) then
        return false
    end
    Part.addWork(mission, farmId)
    return true
end

---teslim edilen litre katkisi (Guard bosaltma yolundan cagrilir)
function Part.onDelivered(vehicle, object, liters)
    if type(liters) ~= "number" or liters <= 0 or ContractGuard == nil then
        return
    end
    local farmId = ContractGuard:getVehicleFarmId(vehicle)
    if farmId == nil then
        return
    end
    for _, mission in ipairs(ContractGuard:getMissions()) do
        if Part.get(mission) ~= nil and Part.isMember(mission, farmId) then
            local station = ContractGuard:getAssignedStation(mission)
            if station ~= nil and (object == station or object.target == station) then
                Part.addLiters(mission, farmId, liters)
                return
            end
            if station ~= nil and station.unloadTriggers ~= nil then
                for _, trigger in ipairs(station.unloadTriggers) do
                    if trigger == object then
                        Part.addLiters(mission, farmId, liters)
                        return
                    end
                end
            end
        end
    end
end

function Part.afterDismiss(mission)
    if mission ~= nil and g_currentMission ~= nil and g_currentMission:getIsServer() then
        Part.splitPayment(mission)
        Part.clearForMission(mission)
    end
end

-- ---------------------------------------------------------------------------
-- kalicilik (Persistence cagirir)
-- ---------------------------------------------------------------------------

function Part:writeToXML(xmlId, baseKey)
    local ids = {}
    for id in pairs(Part.list) do ids[#ids + 1] = id end
    table.sort(ids)
    local index = 0
    for _, id in ipairs(ids) do
        local entry = Part.list[id]
        local key = string.format("%s.contract(%d)", baseKey, index)
        setXMLString(xmlId, key .. "#id", id)
        setXMLInt(xmlId, key .. "#owner", entry.owner or 0)
        local farmIndex = 0
        for _, farmId in ipairs(Part.getFarms(id)) do
            local fkey = string.format("%s.farm(%d)", key, farmIndex)
            setXMLInt(xmlId, fkey .. "#farmId", farmId)
            setXMLFloat(xmlId, fkey .. "#liters", entry.liters[farmId] or 0)
            setXMLFloat(xmlId, fkey .. "#work", entry.work[farmId] or 0)
            farmIndex = farmIndex + 1
        end
        index = index + 1
    end
end

function Part:readFromXML(xmlId, baseKey)
    Part.list = {}
    Part.pending = {}
    local index = 0
    while true do
        local key = string.format("%s.contract(%d)", baseKey, index)
        if not hasXMLProperty(xmlId, key) then
            break
        end
        local id = getXMLString(xmlId, key .. "#id")
        local owner = getXMLInt(xmlId, key .. "#owner")
        if id ~= nil and owner ~= nil then
            local entry = { owner = owner, partners = {}, liters = {}, work = {} }
            local farmIndex = 0
            while true do
                local fkey = string.format("%s.farm(%d)", key, farmIndex)
                if not hasXMLProperty(xmlId, fkey) then
                    break
                end
                local farmId = getXMLInt(xmlId, fkey .. "#farmId")
                if farmId ~= nil then
                    if farmId ~= owner then
                        entry.partners[farmId] = true
                    end
                    entry.liters[farmId] = getXMLFloat(xmlId, fkey .. "#liters") or 0
                    entry.work[farmId] = getXMLFloat(xmlId, fkey .. "#work") or 0
                end
                farmIndex = farmIndex + 1
            end
            Part.list[id] = entry
        end
        index = index + 1
    end
end

function Part.reset()
    Part.list = {}
    Part.pending = {}
end

-- ---------------------------------------------------------------------------
-- ag
-- ---------------------------------------------------------------------------

function Part.broadcast(uniqueId, connection)
    if ContractManagerPartnerEvent == nil then
        return
    end
    local ev = ContractManagerPartnerEvent.newSync(uniqueId)
    if connection ~= nil then
        connection:sendEvent(ev)
    elseif g_server ~= nil then
        g_server:broadcastEvent(ev, false)
    end
end

function Part.sendAllTo(connection)
    local sent = {}
    for id in pairs(Part.list) do
        sent[id] = true
        Part.broadcast(id, connection)
    end
    -- yalnizca bekleyen daveti olan kontratlar Part.list'te YOKTUR; onlar da gitmeli
    Part.prunePending()
    for id in pairs(Part.pending) do
        if not sent[id] then
            Part.broadcast(id, connection)
        end
    end
end

---istemci: uyelik durumunu uygula (katki verisi istemciye gonderilmez)
function Part.applyRemote(uniqueId, ownerFarmId, farms, pending)
    if uniqueId == nil or uniqueId == "" then
        return
    end
    -- Bekleyen davetler uyelikten BAGIMSIZ gelir: daveti alan ciftlik henuz ortak
    -- degildir, ama butonu gorebilmesi icin listeyi bilmesi gerekir.
    if pending ~= nil then
        if #pending == 0 then
            Part.pending[uniqueId] = nil
        else
            local now = nowMs()
            local farmsPending = {}
            for _, invite in ipairs(pending) do
                farmsPending[invite.farmId] = now + (invite.minutesLeft or 0) * 60000
            end
            Part.pending[uniqueId] = farmsPending
        end
    end
    if ownerFarmId == nil or ownerFarmId == 0 or farms == nil or #farms == 0 then
        Part.list[uniqueId] = nil
        return
    end
    local entry = { owner = ownerFarmId, partners = {}, liters = {}, work = {} }
    for _, farmId in ipairs(farms) do
        entry.partners[farmId] = true
    end
    Part.list[uniqueId] = entry
end

---istek yonlendirme (sunucu). Donus: ok, l10n anahtari
function Part.handle(kind, uniqueId, farmId, targetFarmId)
    local ok, key
    if kind == ContractManagerPartnerEvent.INVITE then
        ok, key = Part.invite(uniqueId, farmId, targetFarmId)
    elseif kind == ContractManagerPartnerEvent.ACCEPT then
        ok, key = Part.accept(uniqueId, farmId)
    elseif kind == ContractManagerPartnerEvent.LEAVE then
        ok, key = Part.leave(uniqueId, farmId)
    elseif kind == ContractManagerPartnerEvent.DECLINE then
        ok, key = Part.decline(uniqueId, farmId)
    else
        ok, key = false, "cm_adminFailed"
    end
    -- Teshis: olay basina tek satir. "kabul edildi ama gelmedi" turu sikayetlerde
    -- sunucunun ne gordugu bu satirdan okunur (2026-09-10).
    ContractManager.info("Partnership %s: contract=%s farm=%s target=%s -> %s (%s)",
        tostring(kind), tostring(uniqueId), tostring(farmId), tostring(targetFarmId), tostring(ok), tostring(key))
    return ok, key
end

-- ---------------------------------------------------------------------------
-- arayuz
-- ---------------------------------------------------------------------------

-- Metin yardimcisi tek yerde: ContractManager.text (Main.lua). Main once yuklenir.
local function text(key, fallback)
    return ContractManager.text(key, fallback)
end

local function farmName(farmId)
    if g_farmManager ~= nil and g_farmManager.getFarmById ~= nil then
        local farm = g_farmManager:getFarmById(farmId)
        if farm ~= nil and farm.name ~= nil then
            return tostring(farm.name)
        end
    end
    return "Farm " .. tostring(farmId)
end

---detay satiri: ortaklar ve (katki verisi varsa) paylar
function Part.getDetailRow(mission)
    local entry = Part.get(mission)
    if entry == nil then
        return nil
    end
    local shares = Part.getShares(mission)
    local hasContribution = next(entry.liters) ~= nil or next(entry.work) ~= nil
    local parts = {}
    for _, farmId in ipairs(Part.getFarms(mission)) do
        if hasContribution then
            parts[#parts + 1] = string.format("%s %d%%", farmName(farmId), math.floor((shares[farmId] or 0) * 100 + 0.5))
        else
            parts[#parts + 1] = farmName(farmId)
        end
    end
    return { title = text("cm_detailPartner"), value = table.concat(parts, " · ") }
end

function Part.onClickButton()
    local frame = g_inGameMenu ~= nil and g_inGameMenu.pageContracts or nil
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.getSelectedMission(frame) or nil
    local uniqueId = ContractManager.getMissionKey(mission)
    local objectId = ContractManager.getMissionObjectId(mission)
    if mission == nil or (uniqueId == nil and objectId == 0) then
        return
    end
    local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    if Part.isPartner(mission, farmId) then
        ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.LEAVE, uniqueId, nil, objectId)
    else
        ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.ACCEPT, uniqueId, nil, objectId)
    end
end

---Bu ciftlige bekleyen daveti olan kontrat (saf; test edilir). inviterFarmId verilirse sahibi o olmali.
function Part.findInvitedMission(farmId, inviterFarmId)
    if farmId == nil or g_missionManager == nil or g_missionManager.missions == nil then
        return nil
    end
    for _, mission in ipairs(g_missionManager.missions) do
        if Part.hasPendingInvite(mission, farmId) and (inviterFarmId == nil or mission.farmId == inviterFarmId) then
            return mission
        end
    end
    return nil
end

---Davet penceresinde Enter: daveti bul, sunucuya KABUL gonder. Kullanici Kontratlar sayfasina
---gitmek zorunda kalmasin (kullanici istegi 2026-09-11). Davet kalkmissa toast.
function Part.acceptInvite(inviterFarmId)
    local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    local mission = Part.findInvitedMission(farmId, inviterFarmId) or Part.findInvitedMission(farmId, nil)
    if mission == nil then
        if ContractManagerAdmin ~= nil and ContractManagerAdmin.showResult ~= nil then
            ContractManagerAdmin.showResult("cm_partInviteGone", false)
        end
        return false
    end
    ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.ACCEPT,
        ContractManager.getMissionKey(mission), nil, ContractManager.getMissionObjectId(mission))
    return true
end

-- Stok Kontratlar sayfasindan davet: hedef ciftlik burada secilir (sayfada secici yok).
Part.stockTarget = nil

---Stok sayfadaki davet hedefi; gecersizse listedeki ilk ciftlik (saf; test edilir)
function Part.resolveStockTarget(ids, current)
    if #ids == 0 then
        return nil
    end
    for _, id in ipairs(ids) do
        if id == current then
            return id
        end
    end
    return ids[1]
end

---Sonraki ciftlik (dongusel; saf)
function Part.nextStockTarget(ids, current)
    for index, id in ipairs(ids) do
        if id == current then
            return ids[index % #ids + 1]
        end
    end
    return ids[1]
end

local function otherFarmIds(farmId)
    if ContractManagerManagePage ~= nil and ContractManagerManagePage.getFarmIds ~= nil then
        return ContractManagerManagePage.getFarmIds(farmId)
    end
    return {}
end

local function farmLabel(farmId)
    if ContractManagerManagePage ~= nil and ContractManagerManagePage.farmName ~= nil then
        return ContractManagerManagePage.farmName(farmId)
    end
    return tostring(farmId)
end

---Sahip degilsek oyunun "Iptal" butonu kalmamali: ortak/davetli ciftlik baskasinin
---kontratini iptal edememeli (sunucu zaten reddeder ama buton yaniltici).
function Part.stripCancelButton(frame)
    if frame == nil or type(frame.menuButtonInfo) ~= "table" or InputAction == nil or InputAction.MENU_CANCEL == nil then
        return 0
    end
    local removed = 0
    for index = #frame.menuButtonInfo, 1, -1 do
        local info = frame.menuButtonInfo[index]
        if type(info) == "table" and info.inputAction == InputAction.MENU_CANCEL then
            table.remove(frame.menuButtonInfo, index)
            removed = removed + 1
        end
    end
    return removed
end

---Sahip icin davet butonlari (saf; frame.menuButtonInfo'ya ekler). Donus: eklenen sayi.
function Part.appendOwnerButtons(frame, mission, farmId)
    local ids = otherFarmIds(farmId)
    Part.stockTarget = Part.resolveStockTarget(ids, Part.stockTarget)
    if Part.stockTarget == nil then
        return 0
    end
    local entry = Part.get(mission)
    local partners = entry ~= nil and Part.countPartners(entry) or 0
    if partners >= (settings():get("partnership.maxPartners") or 1) then
        return 0
    end
    -- Pencere varsa tek buton: "Ortak davet et" -> ciftlik secme penceresi acilir.
    -- Pencere yuklenemediyse eski yol: "Davet et: X" + "Sonraki ciftlik".
    if Part.canUseDialog() then
        table.insert(frame.menuButtonInfo, { inputAction = InputAction.MENU_EXTRA_3,
            text = text("cm_pageInvite", "Invite partner"), callback = Part.onClickOpenDialog })
        return 1
    end
    local added = 1
    table.insert(frame.menuButtonInfo, { inputAction = InputAction.MENU_EXTRA_3,
        text = string.format(text("cm_partInviteTo", "Invite: %s"), farmLabel(Part.stockTarget)),
        callback = Part.onClickInvite })
    if #ids > 1 and InputAction.MENU_EXTRA_4 ~= nil then
        table.insert(frame.menuButtonInfo, { inputAction = InputAction.MENU_EXTRA_4,
            text = text("cm_partNextFarm", "Next farm"), callback = Part.onClickNextFarm })
        added = 2
    end
    return added
end

---Ciftlik secme penceresi kullanilabilir mi? (yuklenmisse ya da henuz denenmediyse)
function Part.canUseDialog()
    local D = ContractManagerFarmPickDialog
    return D ~= nil and D.open ~= nil and not D.loadFailed
end

function Part.onClickOpenDialog()
    local frame = g_inGameMenu ~= nil and g_inGameMenu.pageContracts or nil
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.getSelectedMission(frame) or nil
    if mission == nil then
        return
    end
    local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    local ids = otherFarmIds(farmId)
    local key, objectId = ContractManager.getMissionKey(mission), ContractManager.getMissionObjectId(mission)
    local opened = ContractManagerFarmPickDialog.open(ids, function(targetFarmId)
        Part.stockTarget = targetFarmId
        ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.INVITE, key, targetFarmId, objectId)
    end, Part.stockTarget)
    if not opened then
        -- pencere acilamadi: butonlar bir sonraki cizimde eski donguye doner
        Part.onClickNextFarm()
    end
end

function Part.appendMenuButton(frame)
    if not Part.isEnabled() or frame.menuButtonInfo == nil then
        return
    end
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.getSelectedMission(frame) or nil
    if mission == nil or (mission.status ~= MissionStatus.RUNNING and mission.status ~= MissionStatus.PREPARING) then
        return
    end
    local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    if mission.farmId == farmId then
        Part.appendOwnerButtons(frame, mission, farmId)
        return
    end
    Part.stripCancelButton(frame)
    local key
    if Part.isPartner(mission, farmId) then
        key = "cm_partLeaveButton"
    elseif Part.hasPendingInvite(mission, farmId) then
        key = "cm_partAcceptButton"
    else
        return
    end
    table.insert(frame.menuButtonInfo, { inputAction = InputAction.MENU_EXTRA_3, text = text(key), callback = Part.onClickButton })
    -- Davet varsa reddetmek de buradan yapilabilmeli, yoksa oyuncu daveti yalnizca
    -- suresi dolarak birakabiliyor.
    if key == "cm_partAcceptButton" and InputAction.MENU_EXTRA_4 ~= nil then
        table.insert(frame.menuButtonInfo, { inputAction = InputAction.MENU_EXTRA_4,
            text = text("cm_pageDecline"), callback = Part.onClickDecline })
    end
end

function Part.onClickInvite()
    local frame = g_inGameMenu ~= nil and g_inGameMenu.pageContracts or nil
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.getSelectedMission(frame) or nil
    if mission == nil or Part.stockTarget == nil then
        return
    end
    ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.INVITE,
        ContractManager.getMissionKey(mission), Part.stockTarget, ContractManager.getMissionObjectId(mission))
end

function Part.onClickNextFarm()
    local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
    Part.stockTarget = Part.nextStockTarget(otherFarmIds(farmId), Part.stockTarget)
    if ContractManagerAdmin ~= nil and ContractManagerAdmin.showLine ~= nil then
        ContractManagerAdmin.showLine(string.format(text("cm_partTargetSet", "Invite target: %s"), farmLabel(Part.stockTarget)), true)
    end
    -- butonlari yeniden kur (secili kontrat degismedi ama etiket degisti)
    local frame = g_inGameMenu ~= nil and g_inGameMenu.pageContracts or nil
    if frame ~= nil and frame.updateList ~= nil then
        pcall(frame.updateList, frame)
    end
end

function Part.onClickDecline()
    local frame = g_inGameMenu ~= nil and g_inGameMenu.pageContracts or nil
    local mission = ContractManagerAdmin ~= nil and ContractManagerAdmin.getSelectedMission(frame) or nil
    if mission == nil then
        return
    end
    ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.DECLINE,
        ContractManager.getMissionKey(mission), nil, ContractManager.getMissionObjectId(mission))
end

function Part:consoleInvite(uniqueId, farmId)
    if uniqueId == nil or tonumber(farmId) == nil then
        return "usage: cmInvitePartner <uniqueId> <farmId>  (see cmListContracts)"
    end
    local ok, key = ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.INVITE, uniqueId, tonumber(farmId))
    return tostring(key or "sent")
end

function Part:consoleAccept(uniqueId)
    if uniqueId == nil then
        return "usage: cmAcceptPartner <uniqueId>"
    end
    local ok, key = ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.ACCEPT, uniqueId)
    return tostring(key or "sent")
end

function Part:consoleLeave(uniqueId)
    if uniqueId == nil then
        return "usage: cmLeavePartner <uniqueId>"
    end
    local ok, key = ContractManagerPartnerEvent.send(ContractManagerPartnerEvent.LEAVE, uniqueId)
    return tostring(key or "sent")
end

-- ---------------------------------------------------------------------------
-- kurulum
-- ---------------------------------------------------------------------------

if MissionManager ~= nil and MissionManager.getIsMissionWorkAllowed ~= nil then
    MissionManager.getIsMissionWorkAllowed = Utils.overwrittenFunction(MissionManager.getIsMissionWorkAllowed, Part.overwriteIsMissionWorkAllowed)
end
---Oyunun listesi yalnizca sahibin kontratlarini verir (farmId == farmId). Davet edilen
---ya da ortak olan ciftlik kontrati AKTIF listesinde goremezdi, dolayisiyla kabul/reddet
---butonlarina hic ulasamazdi. Listeyi genisletiyoruz; iptal butonu sahip disinda kaldirilir.
function Part.overwriteGetMissionsByFarmId(manager, superFunc, farmId)
    local list = superFunc(manager, farmId)
    if not Part.isEnabled() or type(list) ~= "table" or farmId == nil then
        return list
    end
    local seen = {}
    for _, m in ipairs(list) do seen[m] = true end
    for _, m in ipairs(manager.missions or {}) do
        if not seen[m] and (Part.isMember(m, farmId) or Part.hasPendingInvite(m, farmId)) then
            list[#list + 1] = m
        end
    end
    return list
end

if MissionManager ~= nil and MissionManager.getMissionsByFarmId ~= nil then
    MissionManager.getMissionsByFarmId = Utils.overwrittenFunction(MissionManager.getMissionsByFarmId, Part.overwriteGetMissionsByFarmId)
end

if AbstractMission ~= nil and AbstractMission.dismiss ~= nil then
    -- dismiss'in donusu MissionDismissEvent tarafindan streamWriteBool'a veriliyor
    AbstractMission.dismiss = ContractManager.appendKeepingReturn(AbstractMission.dismiss, Part.afterDismiss)
end
if g_messageCenter ~= nil and MessageType ~= nil and MessageType.MISSION_DELETED ~= nil then
    g_messageCenter:subscribe(MessageType.MISSION_DELETED, function(_, mission)
        if g_currentMission ~= nil and g_currentMission:getIsServer() then
            Part.clearForMission(mission)
        end
    end, Part)
end

if addConsoleCommand ~= nil then
    addConsoleCommand("cmInvitePartner", "ContractManager: invite a farm to share your contract", "consoleInvite", Part)
    addConsoleCommand("cmAcceptPartner", "ContractManager: accept a partnership invite", "consoleAccept", Part)
    addConsoleCommand("cmLeavePartner", "ContractManager: leave a shared contract", "consoleLeave", Part)
end
if InGameMenuContractsFrame ~= nil and InGameMenuContractsFrame.setButtonsForState ~= nil
    and not ContractManager:isBetterContractsLoaded() then
    InGameMenuContractsFrame.setButtonsForState = Utils.appendedFunction(InGameMenuContractsFrame.setButtonsForState, function(frame, state)
        pcall(Part.appendMenuButton, frame)
    end)
end
