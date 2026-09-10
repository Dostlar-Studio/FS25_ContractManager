--
-- FS25_ContractManager - bilgi penceresi (ortaklik olaylari icin)
--
-- Davet gitti / davet geldi / kabul edildi / reddedildi gibi olaylarda kucuk bir toast
-- yerine oyunun diyalog kalibinda pencere. Mekanizma FarmPickDialog ile ayni (dogrulandi):
-- g_gui:loadGui kaydeder, g_gui:showDialog acar, DialogElement:close kapatir.
-- Pencere yuklenemezse toast'a duser; mesaj hicbir durumda kaybolmaz.
--

ContractManagerInfoPopup = {}

local Popup = ContractManagerInfoPopup

Popup.GUI_NAME = "ContractManagerInfoPopup"
Popup.instance = nil
Popup.loadFailed = false
Popup.queue = {}   -- ust uste gelen mesajlar sirayla gosterilir

---toast yedegi (pencere yoksa ya da yuklenemediyse)
function Popup.fallback(title, text, ok)
    if ContractManagerAdmin ~= nil and ContractManagerAdmin.showLine ~= nil then
        ContractManagerAdmin.showLine(string.format("%s: %s", tostring(title), tostring(text)), ok ~= false)
        return true
    end
    return false
end

if DialogElement ~= nil then
    local Popup_mt = Class(Popup, DialogElement)

    function Popup.new(target, customMt)
        return DialogElement.new(target, customMt or Popup_mt)
    end

    function Popup.ensureLoaded()
        if Popup.instance ~= nil then
            return true
        end
        if Popup.loadFailed or g_gui == nil or g_gui.loadGui == nil then
            return false
        end
        local xmlPath = ContractManager.MOD_DIRECTORY .. "gui/InfoPopup.xml"
        if not fileExists(xmlPath) then
            Popup.loadFailed = true
            return false
        end
        local instance = Popup.new()
        local ok = pcall(g_gui.loadGui, g_gui, xmlPath, Popup.GUI_NAME, instance)
        if not ok or instance.dialogText == nil then
            Popup.loadFailed = true
            ContractManager.warning("Info popup could not be loaded; falling back to notifications")
            return false
        end
        Popup.instance = instance
        return true
    end

    ---Goster. Acik bir pencere varsa kuyruga alinir, kapaninca sirayla gelir.
    function Popup.show(title, text, ok)
        if not Popup.ensureLoaded() then
            return Popup.fallback(title, text, ok)
        end
        if Popup.instance.isOpen then
            Popup.queue[#Popup.queue + 1] = { title = title, text = text, ok = ok }
            return true
        end
        local self = Popup.instance
        self.dialogTitle:setText(tostring(title or ""))
        self.dialogText:setText(tostring(text or ""))
        self.isOpen = true
        g_gui:showDialog(Popup.GUI_NAME)
        return true
    end

    function Popup:onClose()
        if DialogElement.onClose ~= nil then
            DialogElement.onClose(self)
        end
        self.isOpen = false
        local nextItem = table.remove(Popup.queue, 1)
        if nextItem ~= nil then
            Popup.show(nextItem.title, nextItem.text, nextItem.ok)
        end
    end
else
    function Popup.show(title, text, ok)
        return Popup.fallback(title, text, ok)
    end
end
