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
Popup.nextScheduled = false

---Harita kapanisi: bekleyen mesajlar sonraki oturuma tasinmaz, pencere acik sayilmaz.
function Popup.reset()
    Popup.queue = {}
    Popup.nextScheduled = false
    if Popup.instance ~= nil then
        Popup.instance.isOpen = false
        Popup.instance.action = nil
    end
end

---Kuyruktaki sonraki mesaji BIR SONRAKI karede ac. Oyunun Gui:closeDialog'u onClose'u, pencere listeden
---cikmadan ve currentListener degismeden ONCE cagirir (Gui.lua:589-613); o anda showDialog "zaten acik"
---deyip doner (540-541). Kapanirken siradakini acmak pencereyi hic acmiyor, isOpen takili kaliyor ve o
---oturumdaki TUM bilgi pencereleri kuyrukta bekliyordu (1.26.0.0). Kuyruk gorevi oyunun ana dongusunde,
---gorev guncellemesinden bagimsiz calisir; hemen calisirsa (yukleme) mesaj kuyrukta kalir, siradaki
---Popup.show onu once gosterir.
function Popup.scheduleNext()
    if Popup.nextScheduled or #Popup.queue == 0 or g_asyncTaskManager == nil or g_asyncTaskManager.addTask == nil then
        return
    end
    Popup.nextScheduled = true
    local queuing = true
    g_asyncTaskManager:addTask(function()
        Popup.nextScheduled = false
        if not queuing then
            Popup.showNext()
        end
    end)
    queuing = false
end

function Popup.showNext()
    if Popup.instance == nil or Popup.instance.isOpen or g_currentMission == nil then
        return false
    end
    local nextItem = table.remove(Popup.queue, 1)
    if nextItem == nil then
        return false
    end
    return Popup.show(nextItem.title, nextItem.text, nextItem.ok, nextItem.action)
end

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
        local ok = ContractManager.guard("Info popup load", g_gui.loadGui, g_gui, xmlPath, Popup.GUI_NAME, instance)
        if not ok or instance.dialogText == nil or instance.okButton == nil then
            Popup.loadFailed = true
            ContractManager.warning("Info popup could not be loaded; falling back to notifications")
            return false
        end
        Popup.instance = instance
        return true
    end

    ---Butonlari kur: eylem varsa Enter = eylem, Esc = daha sonra; yoksa tek Tamam.
    function Popup:applyAction(action)
        self.action = action
        local okText = action ~= nil and action.acceptText or ContractManager.text("cm_popupOk", "OK")
        if self.okButton.setText ~= nil then
            self.okButton:setText(tostring(okText))
        end
        for _, el in ipairs({ self.laterButton, self.buttonSeparator }) do
            if el ~= nil and el.setVisible ~= nil then
                el:setVisible(action ~= nil)
            end
        end
        if self.buttonBox ~= nil and self.buttonBox.invalidateLayout ~= nil then
            self.buttonBox:invalidateLayout()
        end
    end

    ---Goster. Acik bir pencere varsa kuyruga alinir, kapaninca sirayla gelir.
    ---action (istege bagli): { acceptText = "...", onAccept = function() end } -> Enter eylemi calistirir.
    function Popup.show(title, text, ok, action)
        if not Popup.ensureLoaded() then
            return Popup.fallback(title, text, ok)
        end
        local item = { title = title, text = text, ok = ok, action = action }
        if Popup.instance.isOpen or Popup.nextScheduled then
            Popup.queue[#Popup.queue + 1] = item
            return true
        end
        -- Kuyrukta kalmis mesaj varsa sira bozulmasin: once o gosterilir.
        if #Popup.queue > 0 then
            Popup.queue[#Popup.queue + 1] = item
            item = table.remove(Popup.queue, 1)
        end
        local self = Popup.instance
        self.dialogTitle:setText(tostring(item.title or ""))
        self.dialogText:setText(tostring(item.text or ""))
        self:applyAction(item.action)
        self.isOpen = true
        ContractManager.rememberCursor(self)
        g_gui:showDialog(Popup.GUI_NAME)
        return true
    end

    ---Kok <GUI onOpen> buraya baglidir (bkz. ContractManager.rememberCursor aciklamasi).
    function Popup:onOpen()
        if DialogElement.onOpen ~= nil then
            DialogElement.onOpen(self)
        end
        ContractManager.setCursor(true)
    end

    ---Enter / Tamam: eylem varsa calistir (hata pencereyi kilitlemesin), sonra kapat.
    function Popup:onClickOk()
        local action = self.action
        self.action = nil
        if action ~= nil and type(action.onAccept) == "function" then
            ContractManager.guard("Popup action", action.onAccept)
        end
        self:close()
    end

    ---Esc / Daha sonra: eylem calistirilmaz; davet Kontratlar sayfasinda durur.
    function Popup:onClickBack()
        self.action = nil
        self:close()
    end

    function Popup:onClose()
        if DialogElement.onClose ~= nil then
            DialogElement.onClose(self)
        end
        ContractManager.restoreCursor(self)
        self.isOpen = false
        self.action = nil
        Popup.scheduleNext()
    end
else
    function Popup.show(title, text, ok, action)
        return Popup.fallback(title, text, ok)
    end
end

ContractManagerInfoPopupListener = {}
function ContractManagerInfoPopupListener:deleteMap()
    Popup.reset()
end
if addModEventListener ~= nil then
    addModEventListener(ContractManagerInfoPopupListener)
end
