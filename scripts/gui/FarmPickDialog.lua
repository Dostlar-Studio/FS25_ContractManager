--
-- FS25_ContractManager - ciftlik secme penceresi (ortak daveti)
--
-- Stok Kontratlar sayfasinda "Ortak davet et" basilinca acilir: oyunun kendi diyalog
-- kalibi (fs25_dialog* profilleri) + MultiTextOption secici + Gonder/Vazgec.
-- Dogrulanmis mekanizma: g_gui:loadGui kaydeder (self.guis[name]), g_gui:showDialog acar,
-- DialogElement:close -> closeDialogByName kapatir.
--
-- Pencere yuklenemezse (eski oyun surumu, eksik profil) cagiran taraf eski "Sonraki
-- ciftlik" dongusune duser; hicbir zaman sessizce is kaybolmaz.
--

ContractManagerFarmPickDialog = {}

local Dialog = ContractManagerFarmPickDialog

Dialog.GUI_NAME = "ContractManagerFarmPickDialog"
Dialog.instance = nil
Dialog.loadFailed = false

-- ---------------------------------------------------------------------------
-- saf yardimcilar (test edilir)
-- ---------------------------------------------------------------------------

---secicideki metinler; ad cozucu disaridan verilir
function Dialog.buildOptionTexts(farmIds, nameOf)
    local texts = {}
    for index, farmId in ipairs(farmIds or {}) do
        texts[index] = nameOf(farmId)
    end
    return texts
end

---seci indeksinden ciftlik kimligi; sinir disi ise nil
function Dialog.farmIdAt(farmIds, state)
    if type(state) ~= "number" or farmIds == nil then
        return nil
    end
    return farmIds[state]
end

-- ---------------------------------------------------------------------------
-- pencere
-- ---------------------------------------------------------------------------

if DialogElement ~= nil then
    local Dialog_mt = Class(Dialog, DialogElement)

    function Dialog.new(target, customMt)
        local self = DialogElement.new(target, customMt or Dialog_mt)
        self.farmIds = {}
        self.callback = nil
        return self
    end

    ---Pencereyi bir kez yukle; basarisizsa false (cagiran eski yola duser).
    function Dialog.ensureLoaded()
        if Dialog.instance ~= nil then
            return true
        end
        if Dialog.loadFailed or g_gui == nil or g_gui.loadGui == nil then
            return false
        end
        local xmlPath = ContractManager.MOD_DIRECTORY .. "gui/FarmPickDialog.xml"
        if not fileExists(xmlPath) then
            Dialog.loadFailed = true
            return false
        end
        local instance = Dialog.new()
        local ok = pcall(g_gui.loadGui, g_gui, xmlPath, Dialog.GUI_NAME, instance)
        if not ok or instance.farmOption == nil then
            Dialog.loadFailed = true
            ContractManager.warning("Farm pick dialog could not be loaded; falling back to farm cycling")
            return false
        end
        Dialog.instance = instance
        return true
    end

    ---Ac: farmIds secenekler, callback(farmId) Gonder'de. Donus: acildi mi.
    function Dialog.open(farmIds, callback, preselectFarmId)
        if farmIds == nil or #farmIds == 0 or not Dialog.ensureLoaded() then
            return false
        end
        local self = Dialog.instance
        self.farmIds = farmIds
        self.callback = callback
        local names = Dialog.buildOptionTexts(farmIds, function(id)
            if ContractManagerManagePage ~= nil and ContractManagerManagePage.farmName ~= nil then
                return ContractManagerManagePage.farmName(id)
            end
            return tostring(id)
        end)
        self.farmOption:setTexts(names)
        local state = 1
        for index, id in ipairs(farmIds) do
            if id == preselectFarmId then state = index end
        end
        self.farmOption:setState(state)
        g_gui:showDialog(Dialog.GUI_NAME)
        return true
    end

    function Dialog:onClickSend()
        local farmId = Dialog.farmIdAt(self.farmIds, self.farmOption ~= nil and self.farmOption:getState() or nil)
        local callback = self.callback
        self:close()
        if farmId ~= nil and callback ~= nil then
            callback(farmId)
        end
    end
end
