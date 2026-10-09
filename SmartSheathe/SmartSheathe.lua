-- Smart Sheathe: keeps your weapons drawn when the game puts them away on its own (looting, the end of combat).
-- The game has no sheathe event, so the sheath state is checked a few times a second. When it goes from drawn to
-- sheathed, the cause decides what happens:
--   - your Sheathe/Unsheathe key (ToggleSheath), sitting or an emote: left away, that was you
--   - mounting, a druid or shaman form, swimming, a taxi or vehicle, eating or drinking, dying: left away, the game
--     puts weapons away for those on purpose
--   - anything else (looting, leaving combat): drawn again once the loot window is closed and nothing is being cast
-- Optionally, weapons are also drawn when you target an enemy or enter combat.

local addonName, ns = ...

local SHEATHED = 1                 -- GetSheathState: 1 = sheathed, 2 = melee drawn, 3 = ranged drawn
local POLL_INTERVAL = 0.1
local USER_WINDOW = 1.5            -- a sheathe this soon after your own key press (or sitting) is yours
local REDRAW_DELAY = 0.3           -- let the game finish what it's doing before drawing again
local REDRAW_GIVE_UP = 30          -- a redraw still blocked after this long is dropped
local RETRY_AFTER = 1              -- a draw that didn't take is tried again after this long, once

local DEFAULTS = { drawOnTarget = false, drawOnCombat = false, sheatheAfterCombat = false, sheatheDelay = 3 }
local CHAR_DEFAULTS = { enabled = true }

local lastState
local userUntil = 0                -- sheathes before this time were done by you
local pendingSince                 -- when a redraw was queued (nil: none queued)
local pendingAt                    -- earliest time to try it
local tries = 0
local looting = false
local ourToggle = false
local sheatheTimer               -- counting down to sheathing after combat (nil: not counting)

local function Enabled()
    return SmartSheatheCharDB and SmartSheatheCharDB.enabled
end

local function Tracing()
    return SmartSheatheDB and SmartSheatheDB.trace == true
end

local function Trace(fmt, ...)
    if Tracing() then
        print(("|cff88ccffSmart Sheathe|r [%.1f] " .. fmt):format(GetTime(), ...))
    end
end

local function Sheathed()
    return GetSheathState() == SHEATHED
end

-- Forms that put weapons away: druid forms and Ghost Wolf (warrior stances and rogue stealth are forms too, but keep
-- weapons out)
local FORM_CLASSES = { DRUID = true, SHAMAN = true }

local EATING = { Food = true, Drink = true, ["Food & Drink"] = true, Refreshment = true }

-- Retail keeps auras secret in combat (reading them there is an error), and you can't eat or drink in combat anyway
local function EatingOrDrinking()
    if InCombatLockdown() or UnitAffectingCombat("player") then return false end
    for index = 1, 40 do
        local name
        if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
            local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, "player", index)
            if not ok then return false end
            name = aura and aura.name
        elseif UnitBuff then
            name = UnitBuff("player", index)
        end
        if not name then return false end
        if issecretvalue and issecretvalue(name) then return false end
        if EATING[name] then return true end
    end
    return false
end

-- Why weapons should stay away right now, or nil
local function GameReason()
    if UnitIsDeadOrGhost("player") then return "dead" end
    if IsMounted() then return "mounted" end
    if UnitOnTaxi("player") then return "taxi" end
    if UnitInVehicle and UnitInVehicle("player") then return "vehicle" end
    if IsSwimming() then return "swimming" end
    local _, class = UnitClass("player")
    if FORM_CLASSES[class] and (GetShapeshiftForm() or 0) > 0 then return "form" end
    if EatingOrDrinking() then return "eating" end
    return nil
end

-- What keeps a draw waiting for now (it's tried once this clears), or nil
local function Busy()
    if looting then return "looting" end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return "casting" end
    return nil
end

local function Draw(why)
    ourToggle = true
    ToggleSheath()
    ourToggle = false
    Trace("drawing weapons (%s)", why)
end

local function CancelRedraw(why)
    if pendingSince then
        Trace("redraw dropped (%s)", why)
        pendingSince = nil
    end
end

-- Your own sheathe/unsheathe: whatever it does next is your choice
local function MarkUser(why)
    userUntil = GetTime() + USER_WINDOW
    CancelRedraw(why)
end

hooksecurefunc("ToggleSheath", function()
    if not ourToggle then MarkUser("sheathe key") end
end)
-- Sitting puts weapons away too
if SitStandOrDescendStart then
    hooksecurefunc("SitStandOrDescendStart", function() MarkUser("sit") end)
end
hooksecurefunc("DoEmote", function() MarkUser("emote") end)

local function OnSheathed()
    if GetTime() < userUntil then
        Trace("sheathed by you")
        return
    end
    local reason = GameReason()
    if reason then
        Trace("sheathed (%s), left away", reason)
        return
    end
    -- sheathing after combat is counting down: the game just did it sooner (looting right after a fight)
    if sheatheTimer then
        sheatheTimer:Cancel()
        sheatheTimer = nil
        Trace("sheathed by the game after combat, left away (Sheathe After Combat is on)")
        return
    end
    Trace("sheathed by the game, drawing again")
    pendingSince = GetTime()
    pendingAt = pendingSince + REDRAW_DELAY
    tries = 0
end

local function TryRedraw(now)
    if not Sheathed() then
        pendingSince = nil
        return
    end
    if now - pendingSince > REDRAW_GIVE_UP then
        CancelRedraw("waited too long")
        return
    end
    -- mounting or a form can sheathe a moment before it counts as mounted or shifted
    local reason = GameReason()
    if reason then
        CancelRedraw(reason)
        return
    end
    if now < pendingAt or Busy() then return end
    if tries >= 2 then
        CancelRedraw("didn't take")
        return
    end
    tries = tries + 1
    pendingAt = now + RETRY_AFTER
    Draw("after the game put them away")
end

local elapsed = 0
local poller = CreateFrame("Frame")
poller:Hide()
poller:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < POLL_INTERVAL then return end
    elapsed = 0
    local state = GetSheathState()
    if lastState and state ~= lastState then
        if state == SHEATHED then
            OnSheathed()
        elseif lastState == SHEATHED then
            Trace("drawn")
            pendingSince = nil
        end
    end
    lastState = state
    if pendingSince then TryRedraw(GetTime()) end
end)

-- Drawing on a trigger (an enemy targeted, combat started), unless something the game sheathes for is going on
local function DrawFor(why)
    if not Enabled() or not Sheathed() or GameReason() then return end
    if GetTime() < userUntil then return end
    Draw(why)
end

local function HostileTarget()
    local attackable = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")
    if issecretvalue and issecretvalue(attackable) then return false end
    return attackable
end

-- Sheathing after combat: once you've been out of combat for the set delay (and nothing is being looted or cast),
-- weapons are put away. Counts as your own sheathe, so it isn't drawn again. Entering combat calls it off.
-- sheatheTimer is declared with the other state, since a game sheathe while it counts down is left away (OnSheathed).

local function CancelSheathe()
    if sheatheTimer then
        sheatheTimer:Cancel()
        sheatheTimer = nil
    end
end

local function SheatheAfterCombat()
    CancelSheathe()
    if not (Enabled() and SmartSheatheDB.sheatheAfterCombat) then return end
    local at = GetTime() + (SmartSheatheDB.sheatheDelay or DEFAULTS.sheatheDelay)
    sheatheTimer = C_Timer.NewTicker(0.25, function()
        if InCombatLockdown() then
            CancelSheathe()
            return
        end
        if GetTime() < at or Busy() then return end
        -- already away (your key, or the game while this counted down): nothing left to do
        if Sheathed() then
            CancelSheathe()
            return
        end
        CancelSheathe()
        CancelRedraw("sheathing after combat")
        userUntil = GetTime() + USER_WINDOW
        ourToggle = true
        ToggleSheath()
        ourToggle = false
        Trace("sheathing weapons (out of combat)")
    end)
end

local function UpdatePolling()
    poller:SetShown(Enabled() and true or false)
    lastState = GetSheathState()
    pendingSince = nil
end

-- Options page (Options > AddOns > Smart Sheathe), drawn in Blizzard's settings style by SettingsKit
local Kit = ns.SettingsKit

local page = Kit.NewPage("Smart Sheathe", {
    onDefaults = function()
        for key, value in pairs(DEFAULTS) do SmartSheatheDB[key] = value end
        for key, value in pairs(CHAR_DEFAULTS) do SmartSheatheCharDB[key] = value end
        UpdatePolling()
    end,
})

local function option(key)
    return function() return SmartSheatheDB[key] end, function(value) SmartSheatheDB[key] = value end
end

local needsEnabled = {
    indent = true,
    enabled = Enabled,
    disabledTooltip = "Smart Sheathe is off for this character.",
}

page:Header("General")
page:Checkbox("Enable on This Character",
    function() return SmartSheatheCharDB.enabled end,
    function(value)
        SmartSheatheCharDB.enabled = value
        UpdatePolling()
        page:Refresh()
    end,
    function()
        return ("Keep %s's weapons drawn. When the game puts them away (after looting or combat) they're drawn again; "
            .. "when you put them away with your Sheathe/Unsheathe key they stay away. Mounting, shapeshifting, "
            .. "swimming, eating and drinking are left alone. Saved per character, so it can stay off on a caster.")
            :format(UnitName("player") or "this character")
    end)

page:Header("Draw Weapons")
local getTarget, setTarget = option("drawOnTarget")
page:Checkbox("When Targeting an Enemy", getTarget, setTarget,
    "Draw your weapons when you target something you can attack (and that's still alive).", needsEnabled)
local getCombat, setCombat = option("drawOnCombat")
page:Checkbox("When Entering Combat", getCombat, setCombat,
    "Draw your weapons as soon as you enter combat, before you attack.", needsEnabled)

page:Header("Sheathe Weapons")
local getSheathe, setSheathe = option("sheatheAfterCombat")
page:Checkbox("After Combat", getSheathe, setSheathe,
    "Put your weapons away once you've been out of combat for the delay below. Entering combat again before then "
        .. "keeps them out.", needsEnabled)
local getDelay, setDelay = option("sheatheDelay")
page:Slider("Delay", 0.5, 10, 0.5, getDelay, setDelay,
    function(value) return ("%.1f sec"):format(value) end,
    "How long after combat ends to put your weapons away.", {
        indent = 2,
        enabled = function() return Enabled() and SmartSheatheDB.sheatheAfterCombat end,
        disabledTooltip = function()
            return Enabled() and "Turn on After Combat to set its delay." or needsEnabled.disabledTooltip
        end,
    })
Kit.Register(page)

-- Slash command: /smartsheathe (options), /smartsheathe on|off (this character), /smartsheathe trace
SLASH_SMARTSHEATHE1 = "/smartsheathe"
SlashCmdList["SMARTSHEATHE"] = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "on" or msg == "off" then
        SmartSheatheCharDB.enabled = msg == "on"
        UpdatePolling()
        page:Refresh()
        print(("Smart Sheathe: %s for %s."):format(msg == "on" and "on" or "off", UnitName("player")))
    elseif msg == "trace" then
        SmartSheatheDB.trace = not Tracing()
        print(("Smart Sheathe: trace %s."):format(Tracing() and "on" or "off"))
    else
        Kit.Open(page)
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("LOOT_OPENED")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        SmartSheatheDB = SmartSheatheDB or {}
        SmartSheatheCharDB = SmartSheatheCharDB or {}
        for key, value in pairs(DEFAULTS) do
            if SmartSheatheDB[key] == nil then SmartSheatheDB[key] = value end
        end
        for key, value in pairs(CHAR_DEFAULTS) do
            if SmartSheatheCharDB[key] == nil then SmartSheatheCharDB[key] = value end
        end
        page:Refresh()
    elseif event == "PLAYER_ENTERING_WORLD" then
        looting = false
        UpdatePolling()
    elseif event == "LOOT_OPENED" then
        looting = true
    elseif event == "LOOT_CLOSED" then
        looting = false
    elseif event == "PLAYER_TARGET_CHANGED" then
        if SmartSheatheDB.drawOnTarget and HostileTarget() then DrawFor("enemy targeted") end
    elseif event == "PLAYER_REGEN_DISABLED" then
        CancelSheathe()
        if SmartSheatheDB.drawOnCombat then DrawFor("entered combat") end
    elseif event == "PLAYER_REGEN_ENABLED" then
        SheatheAfterCombat()
    end
end)
