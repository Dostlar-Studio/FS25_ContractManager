--
-- FS25_ContractManager - Zamanli kurallar (gercek zaman)
--
-- * Hafta sonu bonusu: Cumartesi/Pazar odule schedule#weekendBonusPercent eklenir.
-- * Mutlu saat: her gun schedule#happyHourStart..happyHourEnd (gercek saat) arasinda
--   schedule#happyHourBonusPercent eklenir. Baslangic > bitis ise gece yarisini asar.
-- Iki bonus toplanir. Gercek saat motorun getDate'inden alinir (makinenin yerel saati);
-- odeme sunucuda hesaplanir, istemci gosterimi kendi saatine gore olur (saat dilimi farki
-- gosterimde kucuk sapma yaratabilir).
--

ContractManagerSchedule = {}

local Schedule = ContractManagerSchedule

local function settings()
    return ContractManagerSettings
end

function Schedule.isEnabled()
    return ContractManager:getRulesEnabled() and settings():get("schedule.enabled") == true
end

---gercek zaman: haftanin gunu (0 = Pazar) ve saat; test icin degistirilebilir
function Schedule.now()
    if Schedule.override ~= nil then
        return Schedule.override.weekday, Schedule.override.hour
    end
    if getDate == nil then
        return nil, nil
    end
    local ok, s = pcall(getDate, "%w %H")
    if not ok or type(s) ~= "string" then
        return nil, nil
    end
    local w, h = s:match("(%d+) (%d+)")
    return tonumber(w), tonumber(h)
end

function Schedule.isHappyHour(hour)
    local startHour = settings():get("schedule.happyHourStart") or 0
    local endHour = settings():get("schedule.happyHourEnd") or 0
    if startHour == endHour then
        return false
    end
    if startHour < endHour then
        return hour >= startHour and hour < endHour
    end
    return hour >= startHour or hour < endHour -- gece yarisini asar
end

---toplam bonus yuzdesi
function Schedule.getBonusPercent()
    if not Schedule.isEnabled() then
        return 0
    end
    local weekday, hour = Schedule.now()
    if weekday == nil then
        return 0
    end
    local bonus = 0
    if weekday == 0 or weekday == 6 then
        bonus = bonus + (settings():get("schedule.weekendBonusPercent") or 0)
    end
    if hour ~= nil and Schedule.isHappyHour(hour) then
        bonus = bonus + (settings():get("schedule.happyHourBonusPercent") or 0)
    end
    return bonus
end

function Schedule.getMultiplier()
    return 1 + Schedule.getBonusPercent() / 100
end
