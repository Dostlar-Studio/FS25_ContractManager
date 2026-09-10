--
-- FS25_ContractManager - Admin araclari
--
-- Sunucu yoneticisi (master user / host) icin:
--   * Panoyu yenile : kabul edilmemis tum kontratlar silinir, uretim hemen tetiklenir.
--   * Zorla iptal   : secili aktif kontrat, Guard'in "is basladi" engelini asarak iptal edilir;
--                     para cezasi uygulanmaz (admin karari), urun korumasi (musadere) aynen calisir.
--   * Ata           : kabul edilmemis bir kontrat baska bir ciftlige baslatilir (konsol komutu).
--
-- Arayuz: stok Kontratlar sayfasinin alt buton cubugu (menuButtonInfo, BetterContracts kalibi),
-- onay icin stok YesNoDialog. BetterContracts yukluyse ayni tus eylemlerini kullandigi icin
-- butonlar eklenmez; konsol komutlari yine calisir.
--
-- Tum eylemler ContractManagerAdminEvent ile sunucuda calisir; sunucu yetkiyi dogrular ve
-- sonucu yalnizca isteyen yoneticiye bildirir.
--

ContractManagerAdmin = {
    ACTION_CANCEL = 1,
    ACTION_REFRESH = 2,
    ACTION_ASSIGN = 3,
    ACTION_TRANSFER = 4,
    buttonsInstalled = false,
}

local Admin = ContractManagerAdmin

-- Metin yardimcisi tek yerde: ContractManager.text (Main.lua). Main once yuklenir.
local function text(key, fallback)
    return ContractManager.text(key, fallback)
end

-- ---------------------------------------------------------------------------
-- sunucu tarafi eylemler (saf; test edilir). Donus: ok, l10n sonuc anahtari
-- ---------------------------------------------------------------------------

function Admin.findMission(uniqueId)
    if g_missionManager == nil or uniqueId == nil then
        return nil
    end
    if g_missionManager.getMissionByUniqueId ~= nil then
        local m = g_missionManager:getMissionByUniqueId(uniqueId)
        if m ~= nil then
            return m
        end
    end
    for _, m in ipairs(g_missionManager.missions or {}) do
        if tostring(m.uniqueId) == tostring(uniqueId) then
            return m
        end
    end
    return nil
end

function Admin.cancel(uniqueId)
    local mission = Admin.findMission(uniqueId)
    if mission == nil then
        return false, "cm_adminNotFound"
    end
    if mission.status == MissionStatus.CREATED or mission.status == MissionStatus.FINISHED or mission.status == MissionStatus.DISMISSED then
        return false, "cm_adminNotActive"
    end
    mission.cmForceCancel = true     -- Guard iptal engelini asar
    mission.cmAdminCanceled = true   -- Reward cezasi uygulanmaz
    local ok, result = pcall(g_missionManager.cancelMission, g_missionManager, mission)
    mission.cmForceCancel = nil
    if ok and result then
        ContractManager.info("Admin force-cancelled contract %s (farm %s)", tostring(uniqueId), tostring(mission.farmId))
        return true, "cm_adminCancelled"
    end
    return false, "cm_adminFailed"
end

function Admin.refreshBoard()
    if g_missionManager == nil then
        return false, "cm_adminFailed"
    end
    -- HEMEN sil: markMissionForDeletion yalnizca kuyruga koyar, gercek silme bir
    -- sonraki update'te olur. Kuyrukta bekleyen kontratlar #missions icinde sayildigi
    -- icin uretim "pano dolu" sanip yenilerini uretmez. mission:delete() zaten
    -- removeMission cagirir (AbstractMission:delete).
    local doomed = {}
    for _, mission in ipairs(g_missionManager.missions or {}) do
        if mission.status == MissionStatus.CREATED then
            doomed[#doomed + 1] = mission
        end
    end
    for index = #doomed, 1, -1 do
        pcall(function() doomed[index]:delete() end)
    end
    local removed = #doomed
    -- uretim sayacini sifirla: getCanStartNewMissionGeneration generationTimer < 0 ister
    g_missionManager.generationTimer = -1
    local created = Admin.fillBoard(removed)
    ContractManager.info("Admin refreshed contract board: %d removed, %d generated immediately", removed, created)
    return true, "cm_adminRefreshed"
end

---Oyunun uretim dongusunu ELDE cevirir. Normalde update basina en fazla BIR kontrat
---uretilir (generateMission -> finishMissionGeneration -> generationTimer sifirlanir),
---bu yuzden pano yenilendikten sonra kontratlar damla damla gelirdi. Donus: uretilen sayi.
function Admin.fillBoard(target)
    local manager = g_missionManager
    if manager == nil or manager.startMissionGeneration == nil or manager.generateMission == nil then
        return 0
    end
    local maxTotal = MissionManager ~= nil and MissionManager.MAX_MISSIONS or 50
    target = math.max(0, math.min(target or 0, maxTotal))
    local typeCount = type(manager.missionTypes) == "table" and #manager.missionTypes or 1
    local created = 0
    for _ = 1, target do
        if #(manager.missions or {}) >= maxTotal then
            break
        end
        local before = #(manager.missions or {})
        manager.missionGenerationInProgress = false
        if not pcall(manager.startMissionGeneration, manager) then
            break
        end
        -- generateMission her cagrida BIR tur dener; basarida ya da tur listesi
        -- dolandiginda finishMissionGeneration cagirilir ve bayrak duser.
        local steps = 0
        while manager.missionGenerationInProgress and steps <= typeCount do
            if not pcall(manager.generateMission, manager) then
                break
            end
            steps = steps + 1
        end
        if #(manager.missions or {}) <= before then
            break -- bu turda hicbir tur uretemedi; zorlamanin anlami yok
        end
        created = created + 1
    end
    manager.generationTimer = -1
    return created
end

function Admin.assign(uniqueId, farmId)
    local mission = Admin.findMission(uniqueId)
    if mission == nil then
        return false, "cm_adminNotFound"
    end
    if mission.status ~= MissionStatus.CREATED then
        return false, "cm_adminAlreadyStarted"
    end
    farmId = tonumber(farmId)
    if farmId == nil or farmId <= 0 or (g_farmManager ~= nil and g_farmManager.getFarmById ~= nil and g_farmManager:getFarmById(farmId) == nil) then
        return false, "cm_adminNoFarm"
    end
    local ok, state = pcall(g_missionManager.startMission, g_missionManager, mission, farmId, false)
    if ok and state == MissionStartState.OK then
        ContractManager.info("Admin assigned contract %s to farm %d", tostring(uniqueId), farmId)
        return true, "cm_adminAssigned"
    end
    if ok and state == MissionStartState.LIMIT_REACHED then
        return false, "cm_adminLimit"
    end
    return false, "cm_adminFailed"
end

function Admin.execute(action, uniqueId, farmId)
    if action == Admin.ACTION_CANCEL then
        return Admin.cancel(uniqueId)
    elseif action == Admin.ACTION_REFRESH then
        return Admin.refreshBoard()
    elseif action == Admin.ACTION_ASSIGN then
        return Admin.assign(uniqueId, farmId)
    elseif action == Admin.ACTION_TRANSFER and ContractManagerTransfer ~= nil then
        return ContractManagerTransfer.execute(uniqueId, farmId)
    end
    return false, "cm_adminFailed"
end

-- ---------------------------------------------------------------------------
-- olay
-- ---------------------------------------------------------------------------

ContractManagerAdminEvent = {}
local ContractManagerAdminEvent_mt = Class(ContractManagerAdminEvent, Event)

InitEventClass(ContractManagerAdminEvent, "ContractManagerAdminEvent")

function ContractManagerAdminEvent.emptyNew()
    return Event.new(ContractManagerAdminEvent_mt)
end

---objectId: kontratin AG kimligi. Istemcide mission.uniqueId nil oldugu icin
---(sunucu onu hic gondermiyor) istekler kontrati bununla gosterir.
function ContractManagerAdminEvent.new(action, uniqueId, farmId, objectId)
    local self = ContractManagerAdminEvent.emptyNew()
    self.action = action
    self.uniqueId = uniqueId or ""
    self.farmId = farmId or 0
    self.objectId = objectId or 0
    return self
end

function ContractManagerAdminEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.action)
    streamWriteString(streamId, tostring(self.uniqueId or ""))
    streamWriteUIntN(streamId, self.farmId or 0, FarmManager.FARM_ID_SEND_NUM_BITS)
    NetworkUtil.writeNodeObjectId(streamId, self.objectId or 0)
end

function ContractManagerAdminEvent:readStream(streamId, connection)
    self.action = streamReadUInt8(streamId)
    self.uniqueId = streamReadString(streamId)
    self.farmId = streamReadUIntN(streamId, FarmManager.FARM_ID_SEND_NUM_BITS)
    self.objectId = NetworkUtil.readNodeObjectId(streamId)
    self:run(connection)
end

function ContractManagerAdminEvent:run(connection)
    if connection ~= nil and connection:getIsServer() then
        return -- sunucudan istemciye gonderilmez
    end
    if not ContractManager.getIsConnectionAdmin(connection) then
        ContractManager.warning("Rejected admin action %s from a non-admin client", tostring(self.action))
        return
    end
    -- ag kimligini sunucunun kendi uniqueId'sine cevir (istemcide uniqueId yok)
    local uniqueId = ContractManager.resolveMissionKey(self.objectId, self.uniqueId)
    local ok, key = Admin.execute(self.action, uniqueId, self.farmId)
    if connection ~= nil and ContractManagerNotificationEvent ~= nil then
        connection:sendEvent(ContractManagerNotificationEvent.new(ContractManagerNotificationEvent.ADMIN_RESULT, 0, key, ok and 1 or 0))
    end
end

---yerel: host ise dogrudan calistir ve goster, istemci ise sunucuya gonder
function ContractManagerAdminEvent.send(action, uniqueId, farmId, objectId)
    if g_currentMission ~= nil and g_currentMission:getIsServer() then
        local ok, key = Admin.execute(action, ContractManager.resolveMissionKey(objectId, uniqueId), farmId)
        Admin.showResult(key, ok)
        return ok, key
    end
    if g_client ~= nil then
        pcall(function()
            g_client:getServerConnection():sendEvent(ContractManagerAdminEvent.new(action, uniqueId, farmId, objectId))
        end)
    end
    return nil
end

---Hazir metni gosterir (l10n anahtari degil). showResult bunu kullanir.
function Admin.showLine(line, ok)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil and FSBaseMission ~= nil then
        local kind = ok and FSBaseMission.INGAME_NOTIFICATION_OK or FSBaseMission.INGAME_NOTIFICATION_CRITICAL
        g_currentMission:addIngameNotification(kind, line)
    end
end

function Admin.showResult(key, ok)
    local line = text(key, key)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil and FSBaseMission ~= nil then
        local kind = ok and FSBaseMission.INGAME_NOTIFICATION_OK or FSBaseMission.INGAME_NOTIFICATION_CRITICAL
        g_currentMission:addIngameNotification(kind, line)
    end
    -- acik kontrat sayfasini tazele
    if g_inGameMenu ~= nil and g_inGameMenu.pageContracts ~= nil and g_inGameMenu.pageContracts.updateList ~= nil then
        pcall(g_inGameMenu.pageContracts.updateList, g_inGameMenu.pageContracts)
    end
end

-- ---------------------------------------------------------------------------
-- stok Kontratlar sayfasi butonlari
-- ---------------------------------------------------------------------------

function Admin.getSelectedMission(frame)
    if frame == nil or frame.getSelectedContract == nil then
        return nil
    end
    local ok, contract = pcall(frame.getSelectedContract, frame)
    if ok and type(contract) == "table" then
        return contract.mission
    end
    return nil
end

function Admin.onClickRefresh()
    YesNoDialog.show(function(_, yes)
        if yes then
            ContractManagerAdminEvent.send(Admin.ACTION_REFRESH)
        end
    end, nil, text("cm_adminConfirmRefresh"))
end

function Admin.onClickCancel()
    local frame = g_inGameMenu ~= nil and g_inGameMenu.pageContracts or nil
    local mission = Admin.getSelectedMission(frame)
    if mission == nil or (ContractManager.getMissionKey(mission) == nil
        and ContractManager.getMissionObjectId(mission) == 0) then
        Admin.showResult("cm_adminNotFound", false)
        return
    end
    local title = mission.title or "?"
    YesNoDialog.show(function(_, yes)
        if yes then
            ContractManagerAdminEvent.send(Admin.ACTION_CANCEL, ContractManager.getMissionKey(mission),
                nil, ContractManager.getMissionObjectId(mission))
        end
    end, nil, string.format(text("cm_adminConfirmCancel"), tostring(title)))
end

function Admin.appendMenuButtons(frame)
    if not ContractManagerSettingsTab.getIsLocalAdmin() or frame.menuButtonInfo == nil then
        return
    end
    table.insert(frame.menuButtonInfo, {
        inputAction = InputAction.MENU_EXTRA_1,
        text = text("cm_adminRefreshButton"),
        callback = Admin.onClickRefresh,
    })
    local mission = Admin.getSelectedMission(frame)
    if mission ~= nil and mission.status ~= nil and mission.status ~= MissionStatus.CREATED
        and mission.status ~= MissionStatus.FINISHED and mission.status ~= MissionStatus.DISMISSED then
        table.insert(frame.menuButtonInfo, {
            inputAction = InputAction.MENU_EXTRA_2,
            text = text("cm_adminCancelButton"),
            callback = Admin.onClickCancel,
        })
    end
end

function Admin.installButtons()
    if Admin.buttonsInstalled then
        return true
    end
    if InGameMenuContractsFrame == nil or InGameMenuContractsFrame.setButtonsForState == nil then
        ContractManager.warning("Contracts frame API missing; admin buttons skipped")
        return false
    end
    if ContractManager:isBetterContractsLoaded() then
        ContractManager.info("BetterContracts present; admin buttons skipped (console commands available)")
        return false
    end
    InGameMenuContractsFrame.setButtonsForState = Utils.appendedFunction(InGameMenuContractsFrame.setButtonsForState, function(frame, state)
        pcall(Admin.appendMenuButtons, frame)
    end)
    Admin.buttonsInstalled = true
    ContractManager.info("Admin buttons installed on contracts page")
    return true
end

-- ---------------------------------------------------------------------------
-- konsol komutlari (yalnizca yonetici; sunucuda dogrulanir)
-- ---------------------------------------------------------------------------

function Admin:consoleList()
    if g_missionManager == nil then
        return "no mission manager"
    end
    local lines = {}
    for _, m in ipairs(g_missionManager.missions or {}) do
        lines[#lines + 1] = string.format("%s | %s | farm=%s | status=%s | %s",
            tostring(m.uniqueId), tostring(m.type ~= nil and m.type.name or "?"), tostring(m.farmId), tostring(m.status), tostring(m.title))
    end
    return table.concat(lines, "\n")
end

function Admin:consoleRefresh()
    ContractManagerAdminEvent.send(Admin.ACTION_REFRESH)
    return "contract board refresh requested"
end

function Admin:consoleCancel(uniqueId)
    if uniqueId == nil then
        return "usage: cmCancelContract <uniqueId>  (see cmListContracts)"
    end
    ContractManagerAdminEvent.send(Admin.ACTION_CANCEL, uniqueId)
    return "cancel requested for " .. tostring(uniqueId)
end

function Admin:consoleAssign(uniqueId, farmId)
    if uniqueId == nil or tonumber(farmId) == nil then
        return "usage: cmAssignContract <uniqueId> <farmId>"
    end
    ContractManagerAdminEvent.send(Admin.ACTION_ASSIGN, uniqueId, tonumber(farmId))
    return "assign requested"
end

if addConsoleCommand ~= nil then
    addConsoleCommand("cmListContracts", "ContractManager: list contracts with ids", "consoleList", Admin)
    addConsoleCommand("cmRefreshContracts", "ContractManager: remove unaccepted contracts and regenerate", "consoleRefresh", Admin)
    addConsoleCommand("cmCancelContract", "ContractManager: force-cancel a contract by uniqueId", "consoleCancel", Admin)
    addConsoleCommand("cmAssignContract", "ContractManager: start an unaccepted contract for a farm", "consoleAssign", Admin)
end

if g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_START ~= nil then
    g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function()
        Admin.installButtons()
    end, Admin)
end
