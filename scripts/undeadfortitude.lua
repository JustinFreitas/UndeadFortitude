-- This extension contains 5e SRD mounted combat rules.  For license details see file: Open Gaming License v1.0a.txt
local USER_ISHOST = false

local ActionDamage_applyDamage
local ActionSave_onSave_Ruleset
local DEFAULT_UNDEAD_FORTITUDE_DC_MOD = 5
local HP_TEMPORARY = "hp.temporary"
local HP_TOTAL = "hp.total"
local HP_WOUNDS = "hp.wounds"
local HPTEMP = "hptemp"
local HPTOTAL = "hptotal"
local MSGFONT = "msgfont"
local NIL = "nil"
local UNCONSCIOUS_EFFECT_LABEL = "Unconscious"
local WOUNDS = "wounds"

-- Helper to safely check if a string is blank, preferring the modern StringManager method.
local function isBlankSafe(s)
    if StringManager.isBlank then
        return StringManager.isBlank(s)
    end
    if type(s) ~= "string" then
        return false
    end
    return (string.gsub(s, "%s+", "") == "")
end

-- Helper to safely get an actor from a node/string, preferring the modern getActor method.
local function getActorSafe(v)
    if ActorManager.getActor then
        return ActorManager.getActor(v)
    end
    return ActorManager.resolveActor(v)
end

-- Helper to safely get an actor's type and node, preferring modern non-deprecated methods.
local function getTypeAndNodeSafe(v)
    if ActorManager.isPC and ActorManager.getCreatureNode and ActorManager.getCTNode then
        local bIsPC = ActorManager.isPC(v)
        if bIsPC then
            return "pc", ActorManager.getCreatureNode(v)
        else
            return "ct", ActorManager.getCTNode(v) or ActorManager.getCreatureNode(v)
        end
    end
    if ActorManager.getTypeAndNode then
        return ActorManager.getTypeAndNode(v)
    end
    return ActorManager.getActorTypeAndNode(v)
end

-- Helper to safely check for effects, preferring the modern CoreRPG or 5E-specific EffectManager if available.
local function hasEffectSafe(rActor, sEffect, rTarget, bTargetedOnly)
    if EffectManager.hasEffect then
        return EffectManager.hasEffect(rActor, sEffect, rTarget, bTargetedOnly)
    end
    if EffectManager5E and EffectManager5E.hasEffect then
        return EffectManager5E.hasEffect(rActor, sEffect, rTarget, bTargetedOnly)
    end
    return EffectManager.hasEffect(rActor, sEffect)
end

-- Helper to safely fetch saves from the 5E ruleset.
local function getSaveSafe(nodeActor, sSave)
    if ActorManager5E and ActorManager5E.getSave then
        return ActorManager5E.getSave(nodeActor, sSave)
    end
    return 0, false, false, ""
end

-- Helper to safely call the ruleset's damage application function.
local function applyDamageFinal(rSource, rTarget, rRoll, bSecret, sDamage, nTotal)
    if type(ActionDamage_applyDamage) == "function" then
        ActionDamage_applyDamage(rSource, rTarget, rRoll)
    elseif ActionHealthD20 and type(ActionHealthD20.apply) == "function" then
         ActionHealthD20.apply(rSource, rTarget, rRoll)
    elseif ActionDamage then
        if type(ActionDamage.applyDamage) == "function" then
            ActionDamage.applyDamage(rSource, rTarget, rRoll)
        elseif type(ActionDamage.apply) == "function" then
            ActionDamage.apply(rSource, rTarget, rRoll)
        end
    end
end

function onInit()
    USER_ISHOST = User.isHost()

    -- Initialize upvalues on all instances (Host and Client)
    if ActionHealthD20 and ActionHealthD20.apply then
        ActionDamage_applyDamage = ActionHealthD20.apply
    elseif ActionDamage then
        if ActionDamage.applyDamage then
            ActionDamage_applyDamage = ActionDamage.applyDamage
        elseif ActionDamage.apply then
            ActionDamage_applyDamage = ActionDamage.apply
        end
    end

    -- Capture ruleset result handlers from ActionsManager (Host and Client)
    -- This ensures we get the actual local functions even if they aren't in the global table.
    ActionSave_onSave_Ruleset = ActionsManager.getResultHandler("save")

    -- Register result handlers on all instances
    ActionsManager.registerResultHandler("save", onSaveNew)

	if USER_ISHOST then
		Comm.registerSlashHandler("uf", processChatCommand)
		Comm.registerSlashHandler("undeadfortitude", processChatCommand)
        
        -- Hook damage functions to intercept damage rolls
        if ActionHealthD20 and ActionHealthD20.apply then
            ActionHealthD20.apply = applyDamage_v2
        elseif ActionDamage then
            if ActionDamage.applyDamage then
                ActionDamage.applyDamage = applyDamage_FGU
            elseif ActionDamage.apply then
                ActionDamage.apply = applyDamage_FGU
            end
        end
    end
end

function getCTNodeForDisplayName(sDisplayName)
	for _,nodeCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
        if ActorManager.getDisplayName(nodeCT) == sDisplayName then
            return nodeCT
        end
    end

    return nil
end

function processChatCommand(_, sParams)
    local nodeCT = getCTNodeForDisplayName(sParams)
    if nodeCT == nil then
        displayChatMessage(sParams .. " was not found in the Combat Tracker, skipping Fortitude application.")
        return
    end

    applyUndeadFortitude(nodeCT)
end

function displayChatMessage(sFormattedText)
	if isBlankSafe(sFormattedText) then return end

	local msg = {font = MSGFONT, icon = "undeadfortitude_icon", secret = true, text = sFormattedText}
    Comm.addChatMessage(msg) -- local, not broadcast
end

function applyUndeadFortitude(nodeCT)
    local sTargetNodeType, nodeTarget = getTypeAndNodeSafe(nodeCT)
	if not nodeTarget then
		return
	end

    local sWounds
    if sTargetNodeType == "pc" then
        sWounds = HP_WOUNDS
    elseif sTargetNodeType == "ct" then
        sWounds = WOUNDS
	else
		return
	end

    local sDisplayName = ActorManager.getDisplayName(nodeTarget)
    if not hasEffectSafe(nodeTarget, UNCONSCIOUS_EFFECT_LABEL) then
        displayChatMessage(sDisplayName .. " is not an unconscious actor, skipping Fortitude application.")
        return
    end

    local aTargetHealthData = getTargetHealthData(sTargetNodeType, nodeTarget, {})
    local nWounds = aTargetHealthData.nTotalHP - 1
    DB.setValue(nodeTarget, sWounds, "number", nWounds)
    EffectManager.removeEffect(nodeCT, UNCONSCIOUS_EFFECT_LABEL)
    EffectManager.removeEffect(nodeCT, "Prone")
    displayChatMessage("Fortitude was applied to " .. sDisplayName .. ".")
end



function onSaveNew(rSource, rTarget, rRoll)
    -- Passthrough to ruleset handler
    if type(ActionSave_onSave_Ruleset) == "function" then
        ActionSave_onSave_Ruleset(rSource, rTarget, rRoll)
    end

    if rRoll.bUndeadFortitude == nil then
        return
    end

    -- Explicitly decode advantage/disadvantage using 5E-specific managers to ensure we don't just sum all dice.
    if ActionD20 and ActionD20.decodeAdvantage then
        ActionD20.decodeAdvantage(rRoll)
    elseif ActionsManager2 and ActionsManager2.decodeAdvantage then
        ActionsManager2.decodeAdvantage(rRoll)
    end

    local nModDC
    if rRoll.sModDC == nil or rRoll.sModDC == NIL then
        nModDC = DEFAULT_UNDEAD_FORTITUDE_DC_MOD
    else
        nModDC = tonumber(rRoll.sModDC)
    end

    local nDamage = tonumber(rRoll.nDamage)
    local nDC
    if rRoll.sStaticDC == nil or rRoll.sStaticDC == NIL then
        nDC = nModDC + nDamage
    else
        nDC = tonumber(rRoll.sStaticDC)
    end

    local msgShort = {font = MSGFONT}
	local msgLong = {font = MSGFONT}
    local nConSave = ActionsManager.total(rRoll)
	msgShort.text = rRoll.sTrimmedFortitudeTraitNameForSave
	msgLong.text = rRoll.sTrimmedFortitudeTraitNameForSave .. " [" .. nConSave ..  "]"
    msgLong.text = msgLong.text .. "[vs. DC " .. nDC .. "]"
	msgShort.text = msgShort.text .. " ->"
	msgLong.text = msgLong.text .. " ->"
    msgShort.text = msgShort.text .. " [for " .. ActorManager.getDisplayName(rSource) .. "]"
    msgLong.text = msgLong.text .. " [for " .. ActorManager.getDisplayName(rSource) .. "]"
	msgShort.icon = "roll_cast"

	if nConSave >= nDC then
		msgLong.text = msgLong.text .. " [SUCCESS]"
	else
		msgLong.text = msgLong.text .. " [FAILURE]"
	end

    local bSecret = (rRoll.bSecret == "1" or rRoll.bSecret == true)
    ActionsManager.outputResult(bSecret, rSource, nil, msgLong, msgShort)

    -- Undead Fortitude processing
    local nAllHP = tonumber(rRoll.nTotalHP or 0) + tonumber(rRoll.nTempHP or 0)
    local rOriginalAttacker = nil
    if rRoll.sOriginalAttacker then
        rOriginalAttacker = getActorSafe(rRoll.sOriginalAttacker)
    end
    local rActualSource = rOriginalAttacker or rSource

    if nConSave >= nDC then
        -- Undead Fortitude save was made!
        -- Calculate specific damage amount needed to leave exactly 1 HP.
        local nDamageToApply = nAllHP - tonumber(rRoll.nWounds or 0) - 1
        local sDamage = string.gsub(rRoll.sDamage, "=%-?%d+", "=" .. nDamageToApply)
        local rDamageRoll = {
            sType = "damage",
            sDesc = sDamage,
            nTotal = tonumber(nDamageToApply),
            aDice = {},
            bSecret = bSecret
        }
        applyDamageFinal(rActualSource, rTarget or rSource, rDamageRoll, bSecret, sDamage, nDamageToApply)
    else
        -- Undead Fortitude save was NOT made
        if tonumber(rRoll.nWounds or 0) < tonumber(rRoll.nTotalHP or 0) then
            local rDamageRoll = {
                sType = "damage",
                sDesc = rRoll.sDamage,
                nTotal = tonumber(rRoll.nDamage),
                aDice = {},
                bSecret = bSecret
            }
            applyDamageFinal(rActualSource, rTarget or rSource, rDamageRoll, bSecret, rRoll.sDamage, tonumber(rRoll.nDamage))
        end
    end
end



function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
 end

function hasFortitudeTrait(sTargetNodeType, nodeTarget, rRoll)
    local aTraits
	if sTargetNodeType == "pc" then
        aTraits = DB.getChildren(nodeTarget, "traitlist")
    elseif sTargetNodeType == "ct" then
        aTraits = DB.getChildren(nodeTarget, "traits")
	else
		return
	end

    for _, aTrait in pairs(aTraits) do
        local aDecomposedTraitName = getDecomposedTraitName(aTrait)
        if aDecomposedTraitName.nFortitudeStart ~= nil then
            return getFortitudeData(aDecomposedTraitName, aTraits, sTargetNodeType, nodeTarget, rRoll)
        end
    end
end



function getTargetHealthData_FGU(sTargetNodeType, nodeTarget, rRoll)
    local nTotalHP = DB.getValue(nodeTarget, HP_TOTAL, 0)
    local nTempHP = DB.getValue(nodeTarget, HP_TEMPORARY, 0)
    local nWounds = DB.getValue(nodeTarget, HP_WOUNDS, 0)
	if sTargetNodeType == "pc" then
		nTotalHP = DB.getValue(nodeTarget, HP_TOTAL, 0)
		nTempHP = DB.getValue(nodeTarget, HP_TEMPORARY, 0)
		nWounds = DB.getValue(nodeTarget, HP_WOUNDS, 0)
    elseif sTargetNodeType == "ct" then
		nTotalHP = DB.getValue(nodeTarget, HPTOTAL, 0)
		nTempHP = DB.getValue(nodeTarget, HPTEMP, 0)
		nWounds = DB.getValue(nodeTarget, WOUNDS, 0)
	elseif sTargetNodeType == "ct" and ActorManager.isRecordType(nodeTarget, "vehicle") then
		if (rRoll.sSubtargetPath or "") ~= "" then
			nTotalHP = DB.getValue(DB.getPath(rRoll.sSubtargetPath, "hp"), 0)
			nWounds = DB.getValue(DB.getPath(rRoll.sSubtargetPath, WOUNDS), 0)
			nTempHP = 0
		else
			nTotalHP = DB.getValue(nodeTarget, HPTOTAL, 0)
			nTempHP = DB.getValue(nodeTarget, HPTEMP, 0)
			nWounds = DB.getValue(nodeTarget, WOUNDS, 0)
		end
	end

    return {
        nTotalHP = nTotalHP,
        nTempHP = nTempHP,
        nWounds = nWounds
    }
end

function getTargetHealthData(sTargetNodeType, nodeTarget, rRoll)
    return getTargetHealthData_FGU(sTargetNodeType, nodeTarget, rRoll)
end

function getFortitudeData(aDecomposedTraitName, aTraits, sTargetNodeType, nodeTarget, rRoll)
    local bUndead = false
    if trim(aDecomposedTraitName.sFortitudeTraitPrefix):lower():match("undead") then
        bUndead = true
    end

    local sTrimmedSuffixLower = trim(aDecomposedTraitName.sFortitudeTraitSuffix):lower()
    local nStaticDC = tonumber(sTrimmedSuffixLower:match("dc%s*(-?%d+)"))
    local nModDC = tonumber(sTrimmedSuffixLower:match("mod%s*(-?%d+)"))
    local bNoMods = trim(sTrimmedSuffixLower):find("no%s*mods")
    local aTargetHealthData = getTargetHealthData(sTargetNodeType, nodeTarget, rRoll)
    return {
        nTotalHP = aTargetHealthData.nTotalHP,
        nTempHP = aTargetHealthData.nTempHP,
        nWounds = aTargetHealthData.nWounds,
        aTraits = aTraits,
        bUndead = bUndead,
        nStaticDC = nStaticDC,
        nModDC = nModDC,
        bNoMods = bNoMods,
        sTrimmedFortitudeTraitNameForSave = aDecomposedTraitName.sTrimmedFortitudeTraitNameForSave
    }
end

function getDecomposedTraitName(aTrait)
    local sTraitName = DB.getText(aTrait, "name")
    local sTraitNameLower = sTraitName:lower()
    local nFortitudeStart, nFortitudeEnd = sTraitNameLower:find("fortitude")
    local sFortitudeTraitPrefix, sFortitudeTraitSuffix, sTrimmedFortitudeTraitNameForSave
    if nFortitudeStart ~= nil and nFortitudeEnd ~= nil then
        sFortitudeTraitPrefix = sTraitName:sub(1, nFortitudeStart - 1)
        sFortitudeTraitSuffix = sTraitName:sub(nFortitudeEnd + 1)
        sTrimmedFortitudeTraitNameForSave = trim(sTraitName:sub(1, nFortitudeEnd))
    end

    return {
        sTraitName = sTraitName,
        sTraitNameLower = sTraitNameLower,
        nFortitudeStart = nFortitudeStart,
        nFortitudeEnd = nFortitudeEnd,
        sFortitudeTraitPrefix = sFortitudeTraitPrefix,
        sFortitudeTraitSuffix = sFortitudeTraitSuffix,
        sTrimmedFortitudeTraitNameForSave = sTrimmedFortitudeTraitNameForSave
    }
end

function processFortitude(aFortitudeData, nTotal, sDamage, rSource, rTarget, bSecret)
    local nDamageTotal = tonumber(nTotal or 0)
    local nAllHP = aFortitudeData.nTotalHP + aFortitudeData.nTempHP
    if aFortitudeData.nWounds + nDamageTotal >= nAllHP
       and (aFortitudeData.bNoMods or not aFortitudeData.bUndead or not string.find(sDamage or "", "%[TYPE:.*radiant.*%]"))
       and (aFortitudeData.bNoMods or not string.find(sDamage or "", "%[CRITICAL%]"))
       and not hasEffectSafe(rTarget, UNCONSCIOUS_EFFECT_LABEL)
       and aFortitudeData.nTotalHP > aFortitudeData.nWounds then
        local rRoll = { }
        rRoll.sType = "save"
        rRoll.aDice = { "d20" }
        local nMod, bADV, bDIS, sAddText = getSaveSafe(rTarget, "constitution")
        rRoll.nMod = nMod
        rRoll.sDesc = "[SAVE] Constitution for " .. aFortitudeData.sTrimmedFortitudeTraitNameForSave
        rRoll.sSaveDesc = ""
        if sAddText and sAddText ~= "" then
            rRoll.sDesc = rRoll.sDesc .. " " .. sAddText
        end

        if bADV then
            rRoll.sDesc = rRoll.sDesc .. " [ADV]"
        end

        if bDIS then
            rRoll.sDesc = rRoll.sDesc .. " [DIS]"
        end

        rRoll.bSecret = bSecret
        rRoll.bUndeadFortitude = "true"
        rRoll.nDamage = nDamageTotal
        rRoll.sDamage = sDamage
        rRoll.nTotalHP = aFortitudeData.nTotalHP
        rRoll.nTempHP = aFortitudeData.nTempHP
        rRoll.nWounds = aFortitudeData.nWounds
        rRoll.sModDC = tostring(aFortitudeData.nModDC)
        rRoll.sStaticDC = tostring(aFortitudeData.nStaticDC)
        rRoll.sTrimmedFortitudeTraitNameForSave = aFortitudeData.sTrimmedFortitudeTraitNameForSave
        if rSource ~= nil then
            rRoll.sOriginalAttacker = ActorManager.getCreatureNodeName(rSource)
        end

        ModifierStack.reset()  -- Modifiers were being applied to the save from the original dmg roll.  Clear it before save.
        ActionsManager.applyModifiersAndRoll(rTarget, rTarget, false, rRoll)
        return true
    end
end



function applyDamage_FGU(rSource, rTarget, rRoll)
	local sTargetNodeType, nodeTarget = getTypeAndNodeSafe(rTarget)
	if not nodeTarget then return end

    local aFortitudeData = hasFortitudeTrait(sTargetNodeType, nodeTarget, rRoll)
     local bFortitudeTriggered
    if aFortitudeData then
        bFortitudeTriggered = processFortitude(aFortitudeData, rRoll.nTotal, rRoll.sDesc, rSource, rTarget, false)
    end

    if not bFortitudeTriggered then
        applyDamageFinal(rSource, rTarget, rRoll)
    end
end

function applyDamage_v2(rSource, rTarget, rRoll)
	local sTargetNodeType, nodeTarget = getTypeAndNodeSafe(rTarget)
	if not nodeTarget then return end

    -- We only intercept if it's actually damage (ActionHealthD20.apply handles heals too!)
    local isDamageRoll = true
    if rRoll and rRoll.sDesc then
        if rRoll.sDesc:match("%[HEAL") or rRoll.sDesc:match("%[RECOVERY") or rRoll.sDesc:match("%[FHEAL") or rRoll.sDesc:match("%[REGEN") then
            isDamageRoll = false
        elseif (rRoll.nTotal or 0) < 0 then
            isDamageRoll = false
        end
    end

    local aFortitudeData = hasFortitudeTrait(sTargetNodeType, nodeTarget, rRoll)
    local bFortitudeTriggered
    if aFortitudeData and isDamageRoll then
        bFortitudeTriggered = processFortitude(aFortitudeData, rRoll.nTotal, rRoll.sDesc, rSource, rTarget, rRoll.bSecret)
    end

    if not bFortitudeTriggered then
        applyDamageFinal(rSource, rTarget, rRoll)
    end
end
