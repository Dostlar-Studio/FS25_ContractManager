--
-- FS25_ContractManager - hasattan ciftlige kalan urun ("fazlasi")
--
-- Hasat kontratinda tarladan cikan urunun tamami teslim edilmez: bir kismi ciftlige kalir ve
-- oyuncu onu istedigi yerde satabilir. Orani belirleyen sabitler SINIF UZERINDE durur:
--   HarvestMission.SUCCESS_FACTOR     oyun varsayilani 0.93 -> %7 ciftlige kalir
--   BaleMission.FILL_SUCCESS_FACTOR   oyun varsayilani 0.90 -> %10 ciftlige kalir
-- Teslim edilmesi gereken = expectedLiters * carpan; ciftlige kalan = expectedLiters * (1 - carpan).
-- Kalip FS25_BetterContracts kaynagindan dogrulandi (ayni iki sabiti ayni sekilde yazar).
--
-- DIKKAT: AbstractMission.SUCCESS_FACTOR BASKA BIR SEYDIR (tarlanin ne kadarinin islenmis
-- sayilacagi). Onu degistirmek teslim miktarini degistirmez; karistirilirsa ayar hicbir ise yaramaz.
--
-- Sabitler oyunun sinif tablolarinda yasar: hem sunucu hem istemci kendi tarafinda yazar
-- (ayar zaten senkron). Kural katmani kapaliysa (BetterContracts) oyunun degerleri geri konur.
--

ContractManagerHarvest = {
    originals = nil,      -- oyunun acilistaki degerleri (bir kez yakalanir)
    applied = false,
}

local Harvest = ContractManagerHarvest

Harvest.DEFAULT_KEEP_PERCENT = 7        -- HarvestMission.SUCCESS_FACTOR = 0.93
Harvest.DEFAULT_KEEP_PERCENT_BALE = 10  -- BaleMission.FILL_SUCCESS_FACTOR = 0.90
Harvest.MAX_KEEP_PERCENT = 60           -- teslimatin tamamen anlamsizlasmasini engelle

local function settings()
    return ContractManagerSettings
end

-- ---------------------------------------------------------------------------
-- saf yardimcilar (test edilir)
-- ---------------------------------------------------------------------------

---Oranlari 4 haneye yuvarla. Yuvarlanmazsa 1 - 0.93 = 0.0699999... cikar ve 10.000 litrede
---floor() bir litre eksik verir; sayilar oyuncuya yanlis gorunur.
local function round4(value)
    return math.floor(value * 10000 + 0.5) / 10000
end

---Yuzde -> carpan. %7 kalir => 0.93 teslim edilir. Aralik disi deger kirpilir.
function Harvest.factorFromPercent(percent)
    local value = tonumber(percent) or 0
    if value < 0 then value = 0 end
    if value > Harvest.MAX_KEEP_PERCENT then value = Harvest.MAX_KEEP_PERCENT end
    return round4(1 - value / 100)
end

---Kontrat balya teslimi mi? Balyalarin kendi sabiti var.
function Harvest.isBaleType(typeName)
    return type(typeName) == "string" and typeName:lower():find("bale") ~= nil
end

---Bu kontrat turunde ciftlige kalan oran (0..1).
function Harvest.getKeepRatio(typeName)
    local factor
    if Harvest.isBaleType(typeName) then
        factor = BaleMission ~= nil and tonumber(BaleMission.FILL_SUCCESS_FACTOR) or nil
        factor = factor or (1 - Harvest.DEFAULT_KEEP_PERCENT_BALE / 100)
    else
        factor = HarvestMission ~= nil and tonumber(HarvestMission.SUCCESS_FACTOR) or nil
        factor = factor or (1 - Harvest.DEFAULT_KEEP_PERCENT / 100)
    end
    if factor <= 0 or factor > 1 then
        factor = 1 - Harvest.DEFAULT_KEEP_PERCENT / 100
    end
    return round4(1 - factor)
end

---Toplam urunden teslim ve kalan paylari (BetterContracts ile ayni yuvarlama).
function Harvest.split(totalLiters, typeName)
    local total = math.max(0, tonumber(totalLiters) or 0)
    local keep = math.floor(total * Harvest.getKeepRatio(typeName))
    return math.ceil(total - keep), keep
end

-- ---------------------------------------------------------------------------
-- sabitlerin yazilmasi
-- ---------------------------------------------------------------------------

---Orijinaller OYUNUN sinif tablosunda: harita yeniden yuklenince mod tablosu sifirlanir
---ve bizim yazdigimiz deger "oyunun degeri" sanilirdi; boylece oyunun gercek degeri bir daha
---geri konulamazdi (bkz. Generation.captureOriginals). 2026-09-13 denetimi.
function Harvest.captureOriginals()
    if HarvestMission ~= nil and HarvestMission.cmOriginalSuccessFactor == nil then
        HarvestMission.cmOriginalSuccessFactor = tonumber(HarvestMission.SUCCESS_FACTOR)
    end
    if BaleMission ~= nil and BaleMission.cmOriginalFillSuccessFactor == nil then
        BaleMission.cmOriginalFillSuccessFactor = tonumber(BaleMission.FILL_SUCCESS_FACTOR)
    end
    Harvest.originals = {
        harvest = HarvestMission ~= nil and HarvestMission.cmOriginalSuccessFactor or nil,
        bale = BaleMission ~= nil and BaleMission.cmOriginalFillSuccessFactor or nil,
    }
end

function Harvest.isEnabled()
    return ContractManager:getRulesEnabled()
end

function Harvest.applyConstants()
    if HarvestMission == nil and BaleMission == nil then
        return false
    end
    Harvest.captureOriginals()
    local orig = Harvest.originals
    local s = settings()

    if not Harvest.isEnabled() or s == nil then
        -- BetterContracts kendi degerlerini yaziyor: dokunma, oyunun degerini geri koy
        if HarvestMission ~= nil and orig.harvest ~= nil then HarvestMission.SUCCESS_FACTOR = orig.harvest end
        if BaleMission ~= nil and orig.bale ~= nil then BaleMission.FILL_SUCCESS_FACTOR = orig.bale end
        return false
    end

    if HarvestMission ~= nil then
        HarvestMission.SUCCESS_FACTOR = Harvest.factorFromPercent(s:get("harvest.keepPercent"))
    end
    if BaleMission ~= nil then
        BaleMission.FILL_SUCCESS_FACTOR = Harvest.factorFromPercent(s:get("harvest.keepPercentBale"))
    end
    Harvest.applied = true
    return true
end

function Harvest.onMissionStart()
    if not Harvest.applyConstants() then
        return
    end
    ContractManager.info("Harvest rule: farm keeps %d%% of the harvest (%d%% of bales)",
        settings():get("harvest.keepPercent"), settings():get("harvest.keepPercentBale"))
end

---Ayar degisti. Sabitleri yeniden yaz VE kontrat olcumlerini gecersiz kil: panodaki
---kontratlar uretildikleri andaki oranla gorunmeye devam ediyordu (canli, 2026-09-15).
function Harvest.onSettingsChanged(key)
    if not Harvest.applied then
        return
    end
    Harvest.applyConstants()
    if key ~= nil and tostring(key):sub(1, 8) ~= "harvest." then
        return
    end
    if ContractManagerMissionInfo ~= nil and ContractManagerMissionInfo.markAllDirty ~= nil then
        ContractManagerMissionInfo.markAllDirty()
    end
end

if g_messageCenter ~= nil and MessageType ~= nil and MessageType.CURRENT_MISSION_START ~= nil then
    g_messageCenter:subscribe(MessageType.CURRENT_MISSION_START, function() Harvest.onMissionStart() end, Harvest)
    g_messageCenter:subscribe(ContractManager.MESSAGE_SETTINGS_CHANGED,
        function(_, key) Harvest.onSettingsChanged(key) end, Harvest)
end

-- ---------------------------------------------------------------------------
-- Cim hasadi kontratlari (1.24.8.0)
--
-- Oyun sahipsiz tarlalara rastgele urun ekerken (FieldManager, availableFruitTypeIndices) cimi de
-- secebiliyor. Haritada "missionOnlyGrass" isaretli OLMAYAN boyle bir tarlaya bicme/ot/balya degil
-- HASAT kontrati uretiyor. Hasat kontrati bicme makinesine izin vermez (AbstractFieldMission
-- .workAreaTypes; FS25_ContractBoost bunu ancak istege bagli ayarla ekliyor): oyuncu bicmeye baslayinca
-- oyun "araziye erisim yok" diyor. Cim ancak dogrudan kesim tablali silaj makinesiyle (DIRECTCUTTER)
-- hasat edilebiliyor. Ana sunucu 2026-09-29: ciftlik 8 uc cim hasadini hic baslamadan iptal etti,
-- cezasi 36.644.
-- Kural: harvest.grassContracts kapaliyken (varsayilan) cim tarlasina hasat kontrati URETILMEZ.
-- Yalnizca uretim aninda (mission == nil) bakilir; panodaki ve alinmis kontratlara dokunulmaz
-- (oyunun validate'i isAvailableForField'i kontratla cagirir; o yolda karar oyununkidir).
-- ---------------------------------------------------------------------------

Harvest.skippedGrass = 0

---Cim urununun indeksi (FruitType.GRASS, yoksa adla)
function Harvest.getGrassFruitIndex()
    if FruitType ~= nil and type(FruitType.GRASS) == "number" then
        return FruitType.GRASS
    end
    if g_fruitTypeManager ~= nil and g_fruitTypeManager.getFruitTypeIndexByName ~= nil then
        return g_fruitTypeManager:getFruitTypeIndexByName("GRASS")
    end
    return nil
end

---Tarlada su an cim mi var? (oyunun tarla durumu: getFieldState, yoksa fieldState)
function Harvest.isGrassField(field)
    if type(field) ~= "table" then
        return false
    end
    local state = field.getFieldState ~= nil and field:getFieldState() or field.fieldState
    local grass = Harvest.getGrassFruitIndex()
    return type(state) == "table" and grass ~= nil and state.fruitTypeIndex == grass
end

---Uretim kapisi (saf): bu tarlaya hasat kontrati uretilsin mi? Yalniz yeni kontrat icin karar verir.
function Harvest.allowHarvestOnField(field, mission)
    if mission ~= nil or not Harvest.isEnabled() then
        return true
    end
    local s = settings()
    if s == nil or s:get("harvest.grassContracts") == true then
        return true
    end
    if Harvest.isGrassField(field) then
        Harvest.skippedGrass = Harvest.skippedGrass + 1
        if Harvest.skippedGrass == 1 then
            ContractManager.info("Grass harvest contracts are not generated (harvest.grassContracts = false); mowers are not allowed on them")
        end
        return false
    end
    return true
end

---Kancayi oyunun sinifina BIR kez tak (sinif surec boyunca yasar, mod her harita yuklemesinde yeniden
---calisir); cagrilan karar fonksiyonu her yuklemede guncellenir. Donus: kanca yerinde mi.
function Harvest.installGrassFilter()
    local cls = HarvestMission
    if cls == nil or cls.isAvailableForField == nil then
        return false
    end
    cls.cmGrassGate = Harvest.allowHarvestOnField
    if cls.cmGrassGateInstalled then
        return true
    end
    cls.isAvailableForField = Utils.overwrittenFunction(cls.isAvailableForField, function(field, superFunc, mission)
        if not superFunc(field, mission) then
            return false
        end
        local gate = HarvestMission ~= nil and HarvestMission.cmGrassGate or nil
        if gate ~= nil then
            return gate(field, mission) == true
        end
        return true
    end)
    cls.cmGrassGateInstalled = true
    return true
end

---Kontrat bir cim hasadi mi? (istemcide de calisir: urun turu ya da sunucunun yayinladigi dolum turu)
function Harvest.isGrassHarvestMission(mission)
    if mission == nil or mission.type == nil or mission.type.name ~= "harvestMission" then
        return false
    end
    local Info = ContractManagerMissionInfo
    local grassFruit = Harvest.getGrassFruitIndex()
    if Info ~= nil and Info.resolveFruitType ~= nil and grassFruit ~= nil and Info.resolveFruitType(mission) == grassFruit then
        return true
    end
    local info = Info ~= nil and Info.get ~= nil and Info.get(mission) or nil
    local grassFill = g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeIndexByName ~= nil
        and g_fillTypeManager:getFillTypeIndexByName("GRASS") or nil
    return info ~= nil and grassFill ~= nil and info.fillTypeIndex == grassFill
end

Harvest.installGrassFilter()

