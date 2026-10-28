--
-- FS25_ContractManager - kontrat tarlasini teker ezmesinden koruma (1.27.1.0)
--
-- Oyun tekerlek ezmesini yalnizca aracin ciftliginin SAHIP oldugu arazide yapar (WheelDestruction:update,
-- getIsOwnedByFarmAtWorldPosition); NPC'nin tarlasi, dolayisiyla kontrat tarlasi, boylece korunur.
-- FS25_CropDestructionAnywhere bu kontrolu kaldirir: WheelDestruction.update'e eklenir ve temas eden her
-- tekerde self:destroyFruitArea cagirir. FDAY haritasinda bicilmis aniz da ezilir ve "tireTracks" durumuna
-- gecer; hasat kontrati bu pikselleri bicilmis saymaz. Ana sunucu 2026-10-27: ciftlik 8, tarla 13 arpa hasadi
-- %78'de takildi, sure asimi, %75 ceza.
-- Kural guard.protectFields (varsayilan acik): panodaki, hazirlanan ya da suren bir kontratin tarlasinda
-- WheelDestruction.destroyFruitArea calismaz, oyunun kendi korumasi geri gelir. Oyuncu tarlalarinda ve
-- kontratsiz NPC tarlalarinda davranis degismez (oyunun cagrisi zaten yalniz sahip olunan arazide gelir).
-- Karar zinciri: konum -> arazi parseli (g_farmlandManager) -> parselin tarlasi (farmland.field; oyun tarla
-- ile parseli 1:1 baglar, FieldManager:loadMapData) -> tarladaki kontrat (field.currentMission; kontrat
-- olusunca setField -> field:setMission(self), silinince setMission(nil)). Her cagrida sabit maliyet, tarama
-- yok. Sunucu da istemci de ayni karari verir: istemci yakindaki araclar icin ezmeyi kendisi de calistirir ve
-- tarla-kontrat bagi istemcide de kurulur (AbstractFieldMission:readStream -> setField).
--

ContractManagerFieldProtect = {
    blocked = 0,                                          -- bu oturumda engellenen ezme cagrisi
    logged = setmetatable({}, { __mode = "k" }),          -- kontrat -> ilk engel loglandi
}

local Protect = ContractManagerFieldProtect

function Protect.isEnabled()
    local s = ContractManagerSettings
    if s == nil or s.get == nil then
        return true
    end
    return s:get("guard.protectFields") ~= false
end

---Korunan durumlar: panoda, hazirlaniyor, suruyor. Biten kontratin tarlasi kontrat icin artik onemli degil.
function Protect.isProtectedStatus(status)
    return MissionStatus ~= nil and status ~= nil and (status == MissionStatus.CREATED
        or status == MissionStatus.PREPARING or status == MissionStatus.RUNNING)
end

---Konumdaki tarlanin korunan kontrati; yoksa nil
function Protect.getMissionAt(x, z)
    local manager = g_farmlandManager
    if manager == nil or x == nil or z == nil then
        return nil
    end
    local farmland = manager:getFarmlandAtWorldPosition(x, z)
    local field = farmland ~= nil and farmland.field or nil
    local mission = field ~= nil and field.currentMission or nil
    if mission ~= nil and Protect.isProtectedStatus(mission.status) then
        return mission
    end
    return nil
end

---Ezilecek alan (paralelkenar: kok x0/z0, genislik kosesi x1/z1, uzunluk kosesi x2/z2, dorduncu kose
---x1+x2-x0) korunan bir tarlaya degiyor mu? Kontrati dondurur. Oyunun kendi kontrolu yalniz koke bakar;
---tarla kenarinda yarisi iceride donen teker de iz birakmasin diye dort kose.
function Protect.getMissionInArea(x0, z0, x1, z1, x2, z2)
    if x0 == nil or z0 == nil or x1 == nil or z1 == nil or x2 == nil or z2 == nil then
        return nil
    end
    return Protect.getMissionAt(x0, z0)
        or Protect.getMissionAt(x1, z1)
        or Protect.getMissionAt(x2, z2)
        or Protect.getMissionAt(x1 + x2 - x0, z1 + z2 - z0)
end

local function statusName(status)
    if status == MissionStatus.CREATED then
        return "board"
    elseif status == MissionStatus.PREPARING then
        return "preparing"
    end
    return "running"
end

---Kancanin karari: bu ezme engellensin mi? Kontrat basina ilk engel loglanir (canli dogrulama icin).
function Protect.shouldBlock(x0, z0, x1, z1, x2, z2)
    if not Protect.isEnabled() then
        return false
    end
    local mission = Protect.getMissionInArea(x0, z0, x1, z1, x2, z2)
    if mission == nil then
        return false
    end
    Protect.blocked = Protect.blocked + 1
    if not Protect.logged[mission] then
        Protect.logged[mission] = true
        local field = mission.field
        local fieldId = field ~= nil and field.getId ~= nil and field:getId() or nil
        ContractManager.info("Field protection: wheels kept off contract field %s (%s, %s)", tostring(fieldId),
            tostring(mission.type ~= nil and mission.type.name or "?"), statusName(mission.status))
    end
    return true
end

---Kancayi oyunun sinifina BIR kez tak (sinif surec boyunca yasar, mod her harita yuklemesinde yeniden
---calisir). Karar fonksiyonu her yuklemede yenilenir ve harita kapaninca birakilir: modsuz yuklenen bir
---sonraki oyunda eski karar calismaz. Ornekler sinifi metatabloyla gorur (WheelDestruction.new), kanca
---onceden olusmus tekerlere de gecer. Donus: kanca yerinde mi.
function Protect.install()
    local cls = WheelDestruction
    if cls == nil or cls.destroyFruitArea == nil then
        return false
    end
    cls.cmFieldProtectGate = Protect.shouldBlock
    if cls.cmFieldProtectInstalled then
        return true
    end
    cls.destroyFruitArea = Utils.overwrittenFunction(cls.destroyFruitArea, function(self, superFunc, x0, z0, x1, z1, x2, z2)
        local gate = cls.cmFieldProtectGate
        if gate ~= nil and gate(x0, z0, x1, z1, x2, z2) then
            return
        end
        return superFunc(self, x0, z0, x1, z1, x2, z2)
    end)
    cls.cmFieldProtectInstalled = true
    return true
end

function Protect.uninstall()
    if WheelDestruction ~= nil and WheelDestruction.cmFieldProtectGate == Protect.shouldBlock then
        WheelDestruction.cmFieldProtectGate = nil
    end
end

function Protect:loadMap()
    Protect.blocked = 0
    Protect.logged = setmetatable({}, { __mode = "k" })
    if Protect.install() then
        ContractManager.info("Field protection ready (contract fields: %s)", Protect.isEnabled() and "on" or "off")
    else
        ContractManager.warning("Field protection not installed: WheelDestruction.destroyFruitArea not found")
    end
end

function Protect:deleteMap()
    if Protect.blocked > 0 then
        ContractManager.info("Field protection blocked %d wheel passes on contract fields", Protect.blocked)
    end
    Protect.uninstall()
end

Protect.install()

addModEventListener(Protect)
