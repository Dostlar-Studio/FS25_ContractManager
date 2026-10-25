--
-- FS25_ContractManager - Reward kurali
--
-- ODUL HATTI (1.27.0.0): oyunun odulu -> sozlesme carpani -> kayitli asamalar (itibar, etkinlik, fiyat,
-- zincir, NPC; Reward.registerModifier) -> taban/tavan. Ayni hesap (Reward.quote) odemeyi, kontrat
-- ayrintisini, HUD'u ve ortak payini besler. 1.27.0.0'a kadar asamalar getReward icinde sabit sirayla
-- yaziliydi ve ekranlar her birini ayrica yeniden hesapliyordu: itibar primi ayrintida hic yoktu, taban/tavan
-- primlerden ONCE uygulandigi icin tavan odenen tutari sinirlamiyordu.
-- Ceza  = basarisiz/iptal/sure asimi kontratta odulun %N'i; getTotalReward'dan duser
--         (oyun bunu dismiss'te addMoney ile oder) ve bitis detaylarinda satir olarak gorunur.
-- Kiralama = getVehicleCosts * leaseCostMultiplier.
-- Sozlesme sartlari (carpan, taban/tavan, ceza, kismi odeme, kiralama, fiyat yuzdeleri) KABULDE donar
-- (Terms.lua); kabul edilmemis kontratta canli ayar kullanilir. Performans primleri (itibar, etkinlik,
-- zincir, NPC) canli hesaplanir ve bitiste dondurulur (Reward.freeze).
--
-- getReward alt siniflarda override edilir ve ust sinifi cagirir; iki seviye sarmalanirsa
-- carpan iki kez uygulanir. Bu yuzden gorev nesnesinde yeniden giris bayragi tutulur:
-- ilk (en dis) cagri carpani uygular, icerideki cagrilar ham degeri gecirir.
--
-- Istemcide de calisir (liste/detay gosterimi): ayarlar SyncEvent, sartlar TermsEvent, itibar/seri/zincir/NPC
-- RuleStateEvent ile gelir.
--

ContractManagerReward = {
    wrappedClasses = {},   -- class -> true
    modifiers = {},        -- sirali asamalar (registerModifier)
}

local Reward = ContractManagerReward

local function settings()
    return ContractManagerSettings
end

function Reward.isEnabled()
    return ContractManager:getRulesEnabled()
end

---Kontratin sozlesme degeri: kabul edilmisse kabuldeki (donmus) deger, degilse canli ayar
function Reward.term(mission, settingId)
    if mission ~= nil and ContractManagerTerms ~= nil then
        return ContractManagerTerms.value(mission, settingId)
    end
    return settings():get(settingId)
end

local term = Reward.term

-- ---------------------------------------------------------------------------
-- asamalar
-- ---------------------------------------------------------------------------

local function byOrder(a, b)
    return a.order < b.order
end

---Odul asamasi kaydet. def = {
---  id, order,
---  kind = "factor"   -> kendi carpani: deger * (1 + yuzde / 100)
---       | "additive" -> ayni turdekilerle TOPLANIP tek carpan olur (zincir + NPC: 1.26.0.0'a kadarki odemeyle birebir),
---  percent = function(mission, farmId) -> yuzde (0 = asama yok),
---  detailKey = ayrinti satirinin l10n anahtari  |  detailRows = function(mission, stage, textFn) -> satirlar }
---Ayni id ile tekrar kayit tanimi gunceller. Yeni bir prim = tek kayit + yuzde fonksiyonu.
function Reward.registerModifier(def)
    for i, existing in ipairs(Reward.modifiers) do
        if existing.id == def.id then
            Reward.modifiers[i] = def
            table.sort(Reward.modifiers, byOrder)
            return
        end
    end
    Reward.modifiers[#Reward.modifiers + 1] = def
    table.sort(Reward.modifiers, byOrder)
end

---Fiyat yuzdeleri: kabul edilmis kontratta kabuldeki, degilse canli (uzaklik / kucuk tarla / zorluk)
function Reward.getPricing(mission)
    if ContractManagerTerms ~= nil then
        return ContractManagerTerms.getPricing(mission)
    end
    if ContractManagerPricing ~= nil then
        return ContractManagerPricing.getBreakdown(mission)
    end
    return { distance = 0, size = 0, type = 0, total = 0 }
end

-- Yerlesik asamalar. Moduller bu dosyadan once ya da sonra yuklenebildigi icin tanimlar burada, modullere
-- cagri aninda bakilir.
Reward.registerModifier({ id = "reputation", order = 10, kind = "factor", detailKey = "cm_detailReputation",
    percent = function(mission, farmId)
        return ContractManagerReputation ~= nil and ContractManagerReputation.getBonusPercent(farmId) or 0
    end })
Reward.registerModifier({ id = "schedule", order = 20, kind = "factor", detailKey = "cm_detailEventBonus",
    percent = function()
        return ContractManagerSchedule ~= nil and ContractManagerSchedule.getBonusPercent() or 0
    end })
Reward.registerModifier({ id = "pricing", order = 30, kind = "factor",
    percent = function(mission)
        return Reward.getPricing(mission).total or 0
    end,
    detailRows = function(mission, stage, textFn)
        if ContractManagerPricing == nil then
            return {}
        end
        return ContractManagerPricing.rowsFromBreakdown(Reward.getPricing(mission), textFn)
    end })
Reward.registerModifier({ id = "chain", order = 40, kind = "additive", detailKey = "cm_detailChain",
    percent = function(mission, farmId)
        return ContractManagerChain ~= nil and ContractManagerChain.getBonusPercent(mission, farmId) or 0
    end })
Reward.registerModifier({ id = "npc", order = 41, kind = "additive", detailKey = "cm_detailNpc",
    percent = function(mission, farmId)
        return ContractManagerNpc ~= nil and ContractManagerNpc.getBonusPercent(mission, farmId) or 0
    end })

---Odul hesabi (saf; test edilir). base: oyunun odulu; farmId verilmezse kontratin ciftligi (istemcide kabul
---oncesi kendi ciftligi). Donus: { base, multiplier, stages = { {id, percent, kind, def} } (yalniz sifir
---olmayanlar), beforeLimits, total, limitedBy = "min" | "max" | nil }
function Reward.quote(mission, base, farmId)
    local q = { base = base, multiplier = 1, stages = {}, beforeLimits = base, total = base }
    if type(base) ~= "number" then
        return q
    end
    if farmId == nil then
        farmId = ContractManager.getDisplayFarmId(mission)
    end
    q.multiplier = term(mission, "reward.multiplier") or 1
    local value = base * q.multiplier
    if base > 0 then
        local additive = 0
        for _, def in ipairs(Reward.modifiers) do
            local percent = tonumber(def.percent(mission, farmId)) or 0
            if percent ~= 0 then
                q.stages[#q.stages + 1] = { id = def.id, percent = percent, kind = def.kind, def = def }
                if def.kind == "additive" then
                    additive = additive + percent
                else
                    value = value * (1 + percent / 100)
                end
            end
        end
        if additive ~= 0 then
            value = value * (1 + additive / 100)
        end
    end
    q.beforeLimits = value
    -- Taban/tavan EN SONDA: odenen tutarin siniri (1.26.0.0'a kadar primlerden once uygulaniyordu).
    if base > 0 then
        local minReward = term(mission, "reward.min") or 0
        local maxReward = term(mission, "reward.max") or 0
        if minReward > 0 and value < minReward then
            value = minReward
            q.limitedBy = "min"
        end
        if maxReward > 0 and value > maxReward then
            value = maxReward
            q.limitedBy = "max"
        end
    end
    q.total = value
    return q
end

---Oyunun kendi odulu (asamasiz): yeniden giris bayragiyla sarmalayicidan gecer
function Reward.getBaseReward(mission)
    if mission == nil or mission.getReward == nil then
        return 0
    end
    local was = mission.cmInReward
    mission.cmInReward = true
    local ok, value = ContractManager.guard("Contract base reward", mission.getReward, mission)
    mission.cmInReward = was
    return ok and tonumber(value) or 0
end

---Gosterim icin hesap (ayrinti, ekranlar). Bitmis kontratta dondurulan toplam, asamalar bos.
function Reward.getQuote(mission, farmId)
    if mission == nil then
        return Reward.quote(nil, 0, farmId)
    end
    if not Reward.isEnabled() then
        local base = mission.getReward ~= nil and tonumber(mission:getReward()) or 0
        return { base = base, multiplier = 1, stages = {}, beforeLimits = base, total = base }
    end
    if type(mission.cmFrozenReward) == "number" then
        local total = mission.cmFrozenReward
        return { base = total, multiplier = 1, stages = {}, beforeLimits = total, total = total, frozen = true }
    end
    return Reward.quote(mission, Reward.getBaseReward(mission), farmId)
end

---Ayrinti satirlari: sifir olmayan her asama, hattaki sirayla (saf; test edilir)
function Reward.getDetailRows(mission, textFn)
    local rows = {}
    if mission == nil or not Reward.isEnabled() then
        return rows
    end
    local q = Reward.getQuote(mission)
    for _, stage in ipairs(q.stages) do
        local def = stage.def
        if def.detailRows ~= nil then
            for _, row in ipairs(def.detailRows(mission, stage, textFn)) do
                rows[#rows + 1] = row
            end
        elseif def.detailKey ~= nil then
            rows[#rows + 1] = { title = textFn(def.detailKey), value = string.format("+%d %%", math.floor(stage.percent + 0.5)) }
        end
    end
    return rows
end

---Kontrat basariyla biterse ciftlik(ler)e gececek tahmini tutar: odul - kiralik arac bedeli + geri odeme (oyunun
---getTotalReward'i gibi; calinan urun bedeli bitiste belli olur). HUD ve ortak payi bunu boler, odeme de
---getTotalReward'i boler. 1.26.0.0'a kadar ekran ham odulu boluyordu (kiralama bedeli dusulmeden).
function Reward.getExpectedNet(mission)
    if mission == nil or mission.getReward == nil then
        return 0
    end
    local reward = tonumber(mission:getReward()) or 0
    local costs = 0
    if mission.getActualVehicleCosts ~= nil then
        costs = tonumber(mission:getActualVehicleCosts()) or 0
    end
    local reimbursement = 0
    if mission.getReimbursement ~= nil then
        reimbursement = tonumber(mission:getReimbursement()) or 0
    end
    return reward - costs + reimbursement
end

-- ---------------------------------------------------------------------------
-- ceza
-- ---------------------------------------------------------------------------

---Ciftligin art arda basarisizlik serisi: sunucuda kayit, istemcide senkron kopya (RuleState)
function Reward.getFailStreak(farmId)
    if farmId == nil then
        return 0
    end
    if ContractManagerRuleState ~= nil then
        return ContractManagerRuleState.getFailStreak(farmId)
    end
    local stats = ContractManagerRegistry ~= nil and ContractManagerRegistry.stats[farmId] or nil
    return stats ~= nil and (stats.failStreak or 0) or 0
end

---Ceza yuzdesi (saf): taban + (seri - 1) * adim, tavanla kirpilmis. seri = bu basarisizlik dahil art arda sayi.
---Tavan HER ZAMAN uygulanir: eskiden adim 0 iken atlaniyordu; taban 100 / tavan 75 ayarinda adim 0 -> %100,
---adim acilinca -> %75 (artan cezayi acmak cezayi dusuruyordu, 1.26.0.0).
function Reward.computePenaltyPercent(base, step, cap, streak)
    base = base or 0
    step = step or 0
    cap = cap or 100
    if step <= 0 then
        return math.min(cap, base)
    end
    return math.min(cap, base + math.max(0, (streak or 1) - 1) * step)
end

---Ciftligin SON basarisizligi icin yuzde (bitiste dondurulur: seri o an bu basarisizligi icerir).
---`mission` verilirse kontratin kabuldeki ceza sartlari kullanilir.
function Reward.getPenaltyPercent(farmId, mission)
    return Reward.computePenaltyPercent(term(mission, "reward.failPenaltyPercent"),
        term(mission, "reward.penaltyStepPercent"), term(mission, "reward.penaltyMaxPercent"),
        Reward.getFailStreak(farmId))
end

---Bu kontrat SIMDI basarisiz olsa kesilecek yuzde (ayrintidaki onizleme). Seri bir artacagi icin bir adim
---yukari; 1.27.0.0'a kadar onizleme kesilecek cezadan bir adim dusuk gosteriyordu.
function Reward.getPenaltyPreviewPercent(mission, farmId)
    if farmId == nil then
        farmId = ContractManager.getDisplayFarmId(mission)
    end
    return Reward.computePenaltyPercent(term(mission, "reward.failPenaltyPercent"),
        term(mission, "reward.penaltyStepPercent"), term(mission, "reward.penaltyMaxPercent"),
        Reward.getFailStreak(farmId) + 1)
end

---Bitmis ve basarisiz kontrat icin ceza tutari (pozitif sayi), degilse 0
function Reward.getPenalty(mission)
    if not Reward.isEnabled() or mission == nil then
        return 0
    end
    if mission.cmAdminCanceled then
        return 0
    end
    -- DIKKAT: para AbstractMission:dismiss() icinde hesaplanir ve o fonksiyon durumu
    -- ONCE DISMISSED yapar, getTotalReward'i SONRA cagirir. Yalnizca FINISHED kabul
    -- edilirse ceza ekranda gorunur ama HIC KESILMEZ (2026-09-09 canli sunucu).
    -- Gercek olcut asagidaki finishState kontrolu; durum ikisinden biri olabilir.
    if mission.status ~= MissionStatus.FINISHED and mission.status ~= MissionStatus.DISMISSED then
        return 0
    end
    local state = mission.finishState
    if state == nil or state == MissionFinishState.SUCCESS or state == MissionFinishState.NONE then
        return 0
    end
    -- Kiralik araclar yuklenemedi: oyun kontrati kendisi FAILED bitirir (AbstractMission.lua:373); oyuncunun
    -- hatasi degil, ceza yok (1.26.0.0).
    if state == MissionFinishState.FAILED and mission.failedToLoadVehicles then
        return 0
    end
    local percent = Reward.getFrozenPenaltyPercent(mission)
    if percent <= 0 then
        return 0
    end
    local reward = 0
    if mission.getReward ~= nil then
        local value = mission:getReward()
        if type(value) == "number" then
            reward = value
        end
    end
    return math.max(0, reward * percent / 100)
end

---Bitiste dondurulan ceza yuzdesi (Registry yazar). Yoksa (eski kayit, yeniden baslatma) gecmis kaydindaki
---deger, o da yoksa canli hesap. Eskiden kapatma anindaki seri okunuyordu: kapatilmadan biriken uc
---basarisizligin ucu de son serinin yuzdesini oduyordu (1.26.0.0).
function Reward.getFrozenPenaltyPercent(mission)
    if type(mission.cmFrozenPenaltyPercent) == "number" then
        return mission.cmFrozenPenaltyPercent
    end
    local entry = Reward.historyEntry(mission)
    if entry ~= nil and type(entry.penaltyPercent) == "number" then
        return entry.penaltyPercent
    end
    return Reward.getPenaltyPercent(mission.farmId, mission)
end

---Sunucu: kontratin gecmis kaydi (bitiste yazilir). Istemcide gecmis kimliksiz gelir -> nil.
function Reward.historyEntry(mission)
    if g_server == nil or ContractManagerRegistry == nil or ContractManagerRegistry.findHistoryEntry == nil then
        return nil
    end
    local key = ContractManager.getMissionKey(mission)
    return key ~= nil and ContractManagerRegistry:findHistoryEntry(key) or nil
end

---basarisiz kontratta tamamlanma oranina gore kismi odeme (0 = yok); sartlar kabuldeki
function Reward.getPartialReward(mission)
    if not Reward.isEnabled() or mission == nil or mission.cmAdminCanceled then
        return 0
    end
    if not term(mission, "reward.partialEnabled") then
        return 0
    end
    local state = mission.finishState
    if state == nil or state == MissionFinishState.SUCCESS or state == MissionFinishState.NONE then
        return 0
    end
    local completion = tonumber(mission.completion) or 0
    if completion <= 0 or completion < (term(mission, "reward.partialMinCompletion") or 0) / 100 then
        return 0
    end
    local reward = 0
    if mission.getReward ~= nil then
        local value = mission:getReward()
        if type(value) == "number" then
            reward = value
        end
    end
    return math.max(0, reward * math.min(completion, 1) * (term(mission, "reward.partialFactor") or 100) / 100)
end

-- ---------------------------------------------------------------------------
-- hook govdeleri
-- ---------------------------------------------------------------------------

function Reward.overwriteGetActualReward(mission, superFunc)
    local value = superFunc(mission)
    if type(value) == "number" and value > 0 then
        return value
    end
    return Reward.getPartialReward(mission)
end

---Kontrat bitiminde odulu dondur. Odeme zinciri su sirayla isliyor:
---finish() -> Registry bitisi isler -> MESSAGE_CONTRACT_FINISHED -> ITIBAR DEGISIR
---   -> dismiss() -> getTotalReward() -> getReward() -> itibar bonusu ARTIK YENI PUANI okur.
---Yani oyuncunun ekranda gordugu tutar ile hesabina gecen tutar farkliydi (2026-09-13).
---Schedule bonusu gercek duvar saatinden okundugu icin ayni sorun orada daha da buyuktu.
function Reward.freeze(mission)
    if mission == nil or mission.getReward == nil then
        return nil
    end
    local value = mission:getReward()
    if type(value) == "number" then
        mission.cmFrozenReward = value
    end
    return mission.cmFrozenReward
end

function Reward.overwriteGetReward(mission, superFunc)
    if not Reward.isEnabled() or mission.cmInReward then
        return superFunc(mission)
    end
    -- bitiste dondurulmus deger varsa odeme, ceza ve gosterim hep ayni sayiyi kullanir
    if type(mission.cmFrozenReward) == "number" then
        return mission.cmFrozenReward
    end
    -- Sunucu bitis ile kapatma arasinda yeniden baslarsa dondurulmus deger bellekte yoktur: bitiste gecmise
    -- yazilan tutar gecerlidir. Eskiden yeniden hesaplaniyordu ve zincir/NPC/itibar bonusu degisiyordu
    -- (ana sunucu: bir kayitta odeme dondurulandan %10 fazla, 1.26.0.0).
    if mission.status == MissionStatus.FINISHED or mission.status == MissionStatus.DISMISSED then
        local entry = Reward.historyEntry(mission)
        if entry ~= nil and type(entry.reward) == "number" then
            mission.cmFrozenReward = entry.reward
            return entry.reward
        end
    end
    mission.cmInReward = true
    -- Oyunun kendi getReward'i hata atarsa bayrak temizlenmeden kalirdi ve o kontrat
    -- bundan sonra HEP ham oyun odulunu dondururdu (carpan, itibar, bonuslar kaybolurdu).
    -- Hata asagida loglanip YENIDEN firlatilir (yutulmaz).
    local ok, base = ContractManager.attempt(superFunc, mission)
    mission.cmInReward = nil
    if not ok then
        ContractManager.warning("getReward failed for contract %s: %s",
            tostring(ContractManager.getMissionKey(mission)), tostring(base))
        error(base, 0)
    end
    return Reward.quote(mission, base).total
end

function Reward.overwriteGetTotalReward(mission, superFunc)
    local total = superFunc(mission)
    local penalty = Reward.getPenalty(mission)
    if penalty > 0 then
        return total - penalty
    end
    return total
end

function Reward.overwriteGetVehicleCosts(mission, superFunc)
    local costs = superFunc(mission)
    if not Reward.isEnabled() or type(costs) ~= "number" then
        return costs
    end
    return costs * (term(mission, "reward.leaseCostMultiplier") or 1)
end

function Reward.appendedGetFinishedDetails(mission, superFunc)
    local details = superFunc(mission)
    local penalty = Reward.getPenalty(mission)
    if penalty > 0 and type(details) == "table" then
        local title = g_i18n ~= nil and g_i18n:getText("cm_penalty") or "Penalty"
        table.insert(details, { title = title, value = ContractManager.formatMoney(penalty) })
    end
    return details
end

---Bir kontrat sinifinin KENDI getReward'ini sarmala (bir kez)
function Reward.wrapClass(cls, name)
    if type(cls) ~= "table" or Reward.wrappedClasses[cls] then
        return false
    end
    local own = rawget(cls, "getReward")
    if type(own) ~= "function" then
        return false
    end
    cls.getReward = Utils.overwrittenFunction(own, Reward.overwriteGetReward)
    Reward.wrappedClasses[cls] = true
    ContractManager.info("Reward hook on %s.getReward", tostring(name))
    return true
end

---Oyun icindeki tum kontrat turlerinin siniflarini sarmala (gorev basinda; sinif
---listesi ancak o zaman dolu)
function Reward.wrapMissionTypes()
    if g_missionManager == nil or g_missionManager.missionTypes == nil then
        return 0
    end
    local count = 0
    for _, missionType in ipairs(g_missionManager.missionTypes) do
        if Reward.wrapClass(missionType.classObject, missionType.name) then
            count = count + 1
        end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- kurulum
-- ---------------------------------------------------------------------------

if AbstractMission ~= nil then
    if AbstractFieldMission ~= nil then
        Reward.wrapClass(AbstractFieldMission, "AbstractFieldMission")
    end
    if AbstractMission.getTotalReward ~= nil then
        AbstractMission.getTotalReward = Utils.overwrittenFunction(AbstractMission.getTotalReward, Reward.overwriteGetTotalReward)
    end
    if AbstractMission.getActualReward ~= nil then
        AbstractMission.getActualReward = Utils.overwrittenFunction(AbstractMission.getActualReward, Reward.overwriteGetActualReward)
    end
    if AbstractMission.getVehicleCosts ~= nil then
        AbstractMission.getVehicleCosts = Utils.overwrittenFunction(AbstractMission.getVehicleCosts, Reward.overwriteGetVehicleCosts)
    end
    if AbstractMission.getFinishedDetails ~= nil then
        AbstractMission.getFinishedDetails = Utils.overwrittenFunction(AbstractMission.getFinishedDetails, Reward.appendedGetFinishedDetails)
    end
    if g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_START ~= nil then
        g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function()
            Reward.wrapMissionTypes()
        end, Reward)
    end
else
    ContractManager.error("AbstractMission missing; reward rule disabled")
end
