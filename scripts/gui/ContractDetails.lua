--
-- FS25_ContractManager - stok Kontratlar sayfasina ek detay satirlari
--
-- AbstractMission:getDetails() oyunun kontrat detay listesini (baslik/deger ciftleri)
-- uretir; stok sayfa bunu oldugu gibi cizer. Buraya satir eklemek yeni arayuz gerektirmez.
-- Eklenenler: kalan sure (calisan kontrat), olasi ceza (kural katmani acikken),
-- ciftligin aktif kontrat sayisi / limit.
-- Istemcide calisir: endDate ve reward stream'den gelir, ayarlar SyncEvent ile.
--

ContractManagerContractDetails = {}

local Details = ContractManagerContractDetails

-- Metin yardimcisi tek yerde: ContractManager.text (Main.lua). Main once yuklenir.
local function text(key, fallback)
    return ContractManager.text(key, fallback)
end

---dakika -> "1 g 3 s 20 dk" gibi kisa metin (saf; test edilir)
function Details.formatMinutes(minutes)
    minutes = math.max(0, math.floor((minutes or 0) + 0.5))
    local days = math.floor(minutes / 1440)
    local hours = math.floor((minutes % 1440) / 60)
    local mins = minutes % 60
    local parts = {}
    if days > 0 then parts[#parts + 1] = string.format("%d %s", days, text("cm_unitDay", "d")) end
    if hours > 0 then parts[#parts + 1] = string.format("%d %s", hours, text("cm_unitHour", "h")) end
    if mins > 0 or #parts == 0 then parts[#parts + 1] = string.format("%d %s", mins, text("cm_unitMinute", "min")) end
    return table.concat(parts, " ")
end

function Details.formatMoney(value)
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        local s = g_i18n:formatMoney(value, 0, true, true)
        if s ~= nil then
            return s
        end
    end
    return tostring(math.floor(value + 0.5))
end

function Details.formatLiters(liters)
    liters = math.max(0, math.floor((liters or 0) + 0.5))
    if g_i18n ~= nil and g_i18n.formatVolume ~= nil then
        local s = g_i18n:formatVolume(liters, 0)
        if s ~= nil then
            return s
        end
    end
    return string.format("%d l", liters)
end

function Details.fillTypeNameByIndex(index)
    if type(index) ~= "number" or index <= 0 or g_fillTypeManager == nil
        or g_fillTypeManager.getFillTypeTitleByIndex == nil then
        return nil
    end
    local title = g_fillTypeManager:getFillTypeTitleByIndex(index)
    if type(title) == "string" and title ~= "" then
        return title
    end
    return nil
end

---kontrat urununun adi (fillType); bilinmiyorsa nil
function Details.fillTypeName(mission)
    local index = nil
    if type(mission.fillTypeIndex) == "number" then
        index = mission.fillTypeIndex
    elseif type(mission.fillType) == "number" then
        index = mission.fillType
    elseif type(mission.fruitTypeIndex) == "number" and g_fruitTypeManager ~= nil
        and g_fruitTypeManager.getFillTypeIndexByFruitTypeIndex ~= nil then
        index = g_fruitTypeManager:getFillTypeIndexByFruitTypeIndex(mission.fruitTypeIndex)
    end
    if index == nil or g_fillTypeManager == nil or g_fillTypeManager.getFillTypeTitleByIndex == nil then
        return nil
    end
    local title = g_fillTypeManager:getFillTypeTitleByIndex(index)
    if type(title) == "string" and title ~= "" then
        return title
    end
    return nil
end

---Teslimatli kontratlarda (hasat, balya, ot...) urun akisini gosterir (saf).
---expectedLiters = teslim edilmesi gereken; depositedLiters = teslim edilen.
---Fazlasi ciftlige kalir, bu yuzden "kalan" ayrica yazilir.
function Details.buildDeliveryRows(mission)
    local rows = {}
    if mission == nil then
        return rows
    end
    -- DIKKAT: expectedLiters/depositedLiters istemciye AKTARILMIYOR (hicbir writeStream'de
    -- yok). Sunucu bunlari MissionInfo ile ayrica yayinlar; burada o olcumu okuyoruz.
    local info = ContractManagerMissionInfo ~= nil and ContractManagerMissionInfo.get(mission) or nil
    if info == nil or (info.expected or 0) <= 0 then
        return rows
    end
    local expected = info.expected
    local delivered = info.deposited or 0
    local name = Details.fillTypeName(mission) or Details.fillTypeNameByIndex(info.fillTypeIndex)
    if name ~= nil then
        rows[#rows + 1] = { title = text("cm_detailProduct", "Product"), value = name }
    end
    if (info.yieldLiters or 0) > 0 then
        rows[#rows + 1] = { title = text("cm_detailFieldYield", "Field yield (est.)"),
            value = Details.formatLiters(info.yieldLiters) }
    end
    rows[#rows + 1] = { title = text("cm_detailToDeliver", "To deliver"), value = Details.formatLiters(expected) }
    local running = mission.status == MissionStatus.RUNNING or mission.status == MissionStatus.PREPARING
    if running then
        rows[#rows + 1] = { title = text("cm_detailDelivered", "Delivered"), value = string.format("%s  (%d %%)",
            Details.formatLiters(delivered), math.floor(math.min(1, delivered / expected) * 100 + 0.5)) }
        rows[#rows + 1] = { title = text("cm_detailRemaining", "Still needed"),
            value = Details.formatLiters(math.max(0, expected - delivered)) }
    end
    -- Fazla urun ciftlige kalir; oyuncunun en cok merak ettigi kalem bu.
    rows[#rows + 1] = { title = text("cm_detailSurplus", "Surplus is yours"), value = text("cm_detailSurplusHint", "yes") }
    return rows
end

---Ortak (sahip olmayan uye) icin: rol + sahip ciftlik + tahmini pay (saf; test edilir).
---Sahip icin bos: onun bilgisi zaten katilimci satirinda.
function Details.buildPartnerShareRows(mission, farmId, reward)
    local rows = {}
    local Part = ContractManagerPartnership
    if Part == nil or mission == nil or Part.get == nil or Part.get(mission) == nil then
        return rows
    end
    if farmId == nil and g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        farmId = g_currentMission:getFarmId()
    end
    if farmId == nil or not Part.isPartner(mission, farmId) then
        return rows
    end
    if reward == nil and mission.getReward ~= nil then
        local value = mission:getReward()
        reward = type(value) == "number" and value or 0
    end
    local entry = Part.get(mission)
    local ownerName = entry ~= nil and entry.owner ~= nil and ContractManagerManagePage ~= nil
        and ContractManagerManagePage.farmName(entry.owner) or "?"
    rows[#rows + 1] = { title = text("cm_detailRole", "Your role"),
        value = string.format("%s · %s", text("cm_pagePartner", "partner"), ownerName) }
    for _, p in ipairs(Part.getParticipants(mission, reward or 0)) do
        if p.farmId == farmId then
            local shareText = Part.hasContribution(mission)
                and string.format("%d %%", math.floor(p.share * 100 + 0.5))
                or text("cm_pageEqualSplit", "equal split")
            rows[#rows + 1] = { title = text("cm_detailYourShare", "Your share"),
                value = string.format("%s · %s", shareText, Details.formatMoney(p.payout or 0)) }
        end
    end
    return rows
end

---ek satirlar (saf; test edilir). rows: { {title=, value=}, ... }
function Details.buildRows(mission)
    local rows = {}
    if mission == nil then
        return rows
    end

    -- kalan sure
    local running = mission.status == MissionStatus.RUNNING or mission.status == MissionStatus.PREPARING
    if running and mission.getMinutesLeft ~= nil then
        local ok, minutes = pcall(mission.getMinutesLeft, mission)
        if ok and type(minutes) == "number" then
            rows[#rows + 1] = { title = text("cm_detailTimeLeft"), value = Details.formatMinutes(minutes) }
        end
    end

    -- teslimat akisi (hasat/balya/ot gibi urun teslim eden kontratlar)
    for _, row in ipairs(Details.buildDeliveryRows(mission)) do
        rows[#rows + 1] = row
    end

    -- ilerleme: calisan kontratta HER ZAMAN (0 % dahil). Ortak ciftlik icin oyunun
    -- ilerleme cubugu gorunmeyebiliyor (stok sayfa sahibe gore yerlesim seciyor);
    -- bu satir ortagin da nerede oldugunu gormesini saglar. completion akisla gelir.
    if mission.status == MissionStatus.RUNNING or mission.status == MissionStatus.PREPARING then
        local completion = math.min(1, math.max(0, tonumber(mission.completion) or 0))
        rows[#rows + 1] = { title = text("cm_detailProgress", "Progress"),
            value = string.format("%d %%", math.floor(completion * 100 + 0.5)) }
    end

    -- olasi ceza (yalnizca bitmemis kontrat; bitmis olanda oyun zaten toplami gosterir)
    if mission.status ~= MissionStatus.FINISHED and mission.status ~= MissionStatus.DISMISSED
        and ContractManager:getRulesEnabled() then
        local percent = ContractManagerSettings:get("reward.failPenaltyPercent")
        if percent > 0 and mission.getReward ~= nil then
            local reward = mission:getReward()
            if type(reward) == "number" and reward > 0 then
                rows[#rows + 1] = { title = text("cm_detailPenalty"), value = Details.formatMoney(reward * percent / 100) }
            end
        end
    end

    -- ortak kontrat: katilimcilar; ortak isek rolumuz ve payimiz da ayri satir
    if ContractManagerPartnership ~= nil then
        local row = ContractManagerPartnership.getDetailRow(mission)
        if row ~= nil then rows[#rows + 1] = row end
        for _, extra in ipairs(Details.buildPartnerShareRows(mission)) do
            rows[#rows + 1] = extra
        end
    end

    -- zincir ve NPC bonusu
    if mission.status ~= MissionStatus.FINISHED and mission.status ~= MissionStatus.DISMISSED then
        if ContractManagerChain ~= nil then
            local b = ContractManagerChain.getBonusPercent(mission)
            if b > 0 then rows[#rows + 1] = { title = text("cm_detailChain"), value = string.format("+%d %%", b) } end
        end
        if ContractManagerNpc ~= nil then
            local b = ContractManagerNpc.getBonusPercent(mission)
            if b > 0 then rows[#rows + 1] = { title = text("cm_detailNpc"), value = string.format("+%d %%", math.floor(b + 0.5)) } end
        end
    end

    -- kalan kota
    if ContractManagerQuota ~= nil and mission.status == MissionStatus.CREATED then
        local farmId = g_currentMission ~= nil and g_currentMission.getFarmId ~= nil and g_currentMission:getFarmId() or nil
        local day, month = ContractManagerQuota.getRemaining(farmId)
        if day ~= nil or month ~= nil then
            rows[#rows + 1] = { title = text("cm_detailQuota"), value = string.format("%s / %s",
                day ~= nil and tostring(day) or "-", month ~= nil and tostring(month) or "-") }
        end
    end

    -- uzaklik / kucuk tarla / tur zorlugu
    if ContractManagerPricing ~= nil and mission.status ~= MissionStatus.FINISHED and mission.status ~= MissionStatus.DISMISSED then
        for _, row in ipairs(ContractManagerPricing.getDetailRows(mission, text)) do rows[#rows + 1] = row end
    end

    -- zamanli bonus
    if ContractManagerSchedule ~= nil and mission.status ~= MissionStatus.FINISHED and mission.status ~= MissionStatus.DISMISSED then
        local bonus = ContractManagerSchedule.getBonusPercent()
        if bonus > 0 then
            rows[#rows + 1] = { title = text("cm_detailEventBonus"), value = string.format("+%d %%", bonus) }
        end
    end

    -- rezervasyon
    if ContractManagerReservation ~= nil then
        local row = ContractManagerReservation.getDetailRow(mission)
        if row ~= nil then rows[#rows + 1] = row end
    end

    -- ciftligin aktif kontratlari / limit
    local farmId = nil
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        farmId = g_currentMission:getFarmId()
    end
    if farmId ~= nil and g_missionManager ~= nil and g_missionManager.missions ~= nil then
        local count = 0
        for _, m in ipairs(g_missionManager.missions) do
            if m.farmId == farmId and m.status ~= nil and m.status ~= MissionStatus.CREATED
                and m.status ~= MissionStatus.FINISHED and m.status ~= MissionStatus.DISMISSED then
                count = count + 1
            end
        end
        local limit = ContractManager:getRulesEnabled() and ContractManagerSettings:get("limits.maxActivePerFarm") or 0
        if limit > 0 and ContractManagerReputation ~= nil then
            limit = limit + ContractManagerReputation.getExtraSlots(farmId)
        end
        local limitText = limit > 0 and tostring(limit) or (MissionManager ~= nil and tostring(MissionManager.MAX_MISSIONS_PER_FARM or "-") or "-")
        rows[#rows + 1] = { title = text("cm_detailActive"), value = string.format("%d / %s", count, limitText) }
    end

    return rows
end

---Kiralama kapaliyken oyunun "Kiralama ucreti" satiri yaniltici: makine zaten
---verilmeyecek. Stok satiri basligindan bulup cikariyoruz (saf; test edilir).
function Details.stripLeaseRow(details, mission)
    if type(details) ~= "table" or ContractManagerLease == nil then
        return details
    end
    local farmId = mission ~= nil and mission.farmId or nil
    if ContractManagerLease.isAllowed(farmId) then
        return details
    end
    local title = text("contract_vehicleCosts", nil)
    if title == nil or title == "contract_vehicleCosts" then
        return details
    end
    for index = #details, 1, -1 do
        if details[index] ~= nil and details[index].title == title then
            table.remove(details, index)
        end
    end
    return details
end

function Details.overwriteGetDetails(mission, superFunc)
    local details = superFunc(mission)
    if type(details) ~= "table" then
        return details
    end
    pcall(Details.stripLeaseRow, details, mission)
    local ok, rows = pcall(Details.buildRows, mission)
    if ok then
        for _, row in ipairs(rows) do
            table.insert(details, row)
        end
    end
    return details
end

if AbstractMission ~= nil and AbstractMission.getDetails ~= nil then
    AbstractMission.getDetails = Utils.overwrittenFunction(AbstractMission.getDetails, Details.overwriteGetDetails)
else
    ContractManager.warning("AbstractMission.getDetails missing; extra contract details disabled")
end
