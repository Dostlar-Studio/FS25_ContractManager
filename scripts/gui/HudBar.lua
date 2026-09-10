--
-- FS25_ContractManager - HUD kontrat cubugu: sahip/ortak ayrimi + beklenen kazanc
--
-- Oyun cubugu AbstractMission:update icinde YALNIZCA `g_localPlayer.farmId == self.farmId`
-- ise kurar ve her kare "cizilecek" diye isaretler (SideNotification). Ortak ciftlik
-- kontratin sahibi olmadigi icin cubugu HIC gormuyordu.
--
-- Bu modul AbstractMission.update'e eklenir (istemci):
--   * sahip icin oyunun kurdugu cubugun metnine rol + beklenen kazanc yazar
--     (cubuk alanlari: title, text, progress, isVisible - SideNotification.lua'dan dogrulandi)
--   * ortak icin kendi cubugunu kurar, her kare isaretler, uyelik bitince kaldirir
--
-- Metin uretimi saf (test edilir); HUD cagrilari korumali.
--

ContractManagerHudBar = {}

local Hud = ContractManagerHudBar

Hud.REFRESH_MS = 1000   -- metin (pay/kazanc) bu aralikla yeniden hesaplanir; her kare degil

local function text(key, fallback)
    return ContractManager.text(key, fallback)
end

-- ---------------------------------------------------------------------------
-- saf: cubuk metni
-- ---------------------------------------------------------------------------

---Cubuk basligi (kalin, kisa): rol. Oyunun "CONTRACT:" basligi yerine gecer.
---Cubuk dar; rol ve kazanc SONA konursa kesilip gorunmuyor (canli test, 2026-09-10).
function Hud.buildTitle(isOwner, sharePercent)
    if isOwner == nil then
        return text("contract_title", "Contract")
    end
    local role = isOwner and text("cm_hudOwner", "Owner") or text("cm_hudPartner", "Partner")
    if not isOwner and sharePercent ~= nil then
        role = string.format("%s %d%%", role, math.floor(sharePercent + 0.5))
    end
    return role
end

---Cubuk metni: "<kazanc> · <kontrat basligi>". Kazanc basta: kesilirse kontrat adi kesilir.
function Hud.buildText(progressTitle, isOwner, payout, sharePercent)
    local parts = {}
    if payout ~= nil then
        parts[#parts + 1] = ContractManagerContractDetails ~= nil
            and ContractManagerContractDetails.formatMoney(payout) or tostring(math.floor(payout + 0.5))
    end
    parts[#parts + 1] = tostring(progressTitle or "")
    return table.concat(parts, " · ")
end

---Yerel ciftligin bu kontrattaki rolu ve beklenen kazanci (saf; odul disaridan).
---Donus: isOwner (nil = uye degil), payout, sharePercent
function Hud.describe(mission, farmId, reward)
    if mission == nil or farmId == nil then
        return nil, nil, nil
    end
    local Part = ContractManagerPartnership
    local entry = Part ~= nil and Part.get(mission) or nil
    if entry == nil then
        if mission.farmId == farmId then
            return true, reward, nil   -- ortaksiz sahip: tum odul
        end
        return nil, nil, nil
    end
    local isOwner = entry.owner == farmId
    if not isOwner and not Part.isPartner(mission, farmId) then
        return nil, nil, nil
    end
    local payout, share = nil, nil
    for _, p in ipairs(Part.getParticipants(mission, reward or 0)) do
        if p.farmId == farmId then
            payout = p.payout
            share = (p.share or 0) * 100
        end
    end
    return isOwner, payout, share
end

-- ---------------------------------------------------------------------------
-- HUD (istemci)
-- ---------------------------------------------------------------------------

local function localFarmId()
    if g_localPlayer ~= nil and g_localPlayer.farmId ~= nil then
        return g_localPlayer.farmId
    end
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        return g_currentMission:getFarmId()
    end
    return nil
end

local function reward(mission)
    if mission.getReward == nil then
        return 0
    end
    local value = mission:getReward()
    return type(value) == "number" and value or 0
end

---Ortak cubugunu kaldir (uyelik bitti / kontrat bitti / silindi)
function Hud.removePartnerBar(mission)
    if mission == nil or mission.cmPartnerBar == nil then
        return
    end
    local hud = g_currentMission ~= nil and g_currentMission.hud or nil
    if hud ~= nil and hud.removeSideNotificationProgressBar ~= nil then
        pcall(hud.removeSideNotificationProgressBar, hud, mission.cmPartnerBar)
    end
    mission.cmPartnerBar = nil
end

---AbstractMission.update'e eklenir. Oyunun kendi cubuk mantiginin ARDINDAN calisir.
function Hud.afterMissionUpdate(mission, dt)
    if mission == nil or g_currentMission == nil or g_currentMission.hud == nil then
        return
    end
    local running = mission.status == MissionStatus.RUNNING or mission.status == MissionStatus.FINISHED
    if not running then
        Hud.removePartnerBar(mission)
        return
    end
    local farmId = localFarmId()
    if farmId == nil then
        return
    end
    -- metin her kare degil, REFRESH_MS'de bir yenilenir (pay hesabi katilimci listesi kurar)
    mission.cmHudTimer = (mission.cmHudTimer or Hud.REFRESH_MS) + (dt or 0)
    local refresh = mission.cmHudTimer >= Hud.REFRESH_MS
    if refresh then
        mission.cmHudTimer = 0
    end

    local isOwner, payout, share = Hud.describe(mission, farmId, reward(mission))
    if isOwner == true then
        -- oyunun cubugu; yalnizca metnini zenginlestir
        if mission.progressBar ~= nil and refresh then
            mission.progressBar.title = Hud.buildTitle(true, nil)
            mission.progressBar.text = Hud.buildText(mission.progressTitle, true, payout, nil)
        end
        Hud.removePartnerBar(mission)
        return
    end
    if isOwner == nil then
        Hud.removePartnerBar(mission)
        return
    end
    -- ORTAK: oyun cubuk kurmaz; kendimiz kurar ve her kare isaretleriz
    local hud = g_currentMission.hud
    if mission.cmPartnerBar == nil then
        if hud.addSideNotificationProgressBar == nil then
            return
        end
        local ok, bar = pcall(hud.addSideNotificationProgressBar, hud,
            Hud.buildTitle(false, share), Hud.buildText(mission.progressTitle, false, payout, share), mission.completion or 0)
        if not ok or bar == nil then
            return
        end
        mission.cmPartnerBar = bar
    elseif refresh then
        mission.cmPartnerBar.title = Hud.buildTitle(false, share)
        mission.cmPartnerBar.text = Hud.buildText(mission.progressTitle, false, payout, share)
    end
    mission.cmPartnerBar.progress = mission.completion or 0
    if hud.markSideNotificationProgressBarForDrawing ~= nil then
        hud:markSideNotificationProgressBarForDrawing(mission.cmPartnerBar)
    end
end

if AbstractMission ~= nil and AbstractMission.update ~= nil then
    AbstractMission.update = ContractManager.appendKeepingReturn(AbstractMission.update, Hud.afterMissionUpdate)
end

-- kontrat silinince cubuk kalmasin
if g_messageCenter ~= nil and MessageType ~= nil and MessageType.MISSION_DELETED ~= nil then
    g_messageCenter:subscribe(MessageType.MISSION_DELETED, function(_, mission) Hud.removePartnerBar(mission) end, Hud)
end
