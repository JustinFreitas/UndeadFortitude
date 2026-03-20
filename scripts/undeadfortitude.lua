-- This extension contains 5e SRD mounted combat rules.  For license details see file: Open Gaming License v1.0a.txt
USER_ISHOST = false

local ActionDamage_applyDamage
local ActionSave_onSave
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

function onInit()
    USER_ISHOST = User.isHost()

	if USER_ISHOST then
		Comm.registerSlashHandler("uf", processChatCommand)
		Comm.registerSlashHandler("undeadfortitude", processChatCommand)
        ActionSave_onSave = ActionSave.onSave
        ActionSave.onSave = onSaveNew
        ActionsManager.registerResultHandler("save", ActionSave.onSave)
        if ActionHealthD20 and ActionHealthD20.apply then
            ActionDamage_applyDamage = ActionHealthD20.apply
            ActionHealthD20.apply = applyDamage_v2
        elseif ActionDamage and ActionDamage.applyDamage then
            ActionDamage_applyDamage = ActionDamage.applyDamage
            if isClientFGU() then
                ActionDamage.applyDamage = applyDamage_FGU
            else
                ActionDamage.applyDamage = applyDamage_FGC
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
	if not sFormattedText then return end

	local msg = {font = MSGFONT, icon = "undeadfortitude_icon", secret = true, text = sFormattedText}
    Comm.addChatMessage(msg) -- local, not broadcast
end

function applyUndeadFortitude(nodeCT)
    local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(nodeCT)
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
    if not EffectManager5E.hasEffect(nodeTarget, UNCONSCIOUS_EFFECT_LABEL) then
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

function isClientFGU()
    return Session.VersionMajor >= 4
end
function onSaveNew(rSource, rTarget, rRoll)
    if rRoll.bUndeadFortitude == nil then
        if ActionSave_onSave then
            ActionSave_onSave(rSource, rTarget, rRoll)
        end
        return
    end

    if ActionD20 and ActionD20.decodeAdvantage then
        ActionD20.decodeAdvantage(rRoll)
    elseif ActionsManager2 and ActionsManager2.decodeAdvantage then
        ActionsManager2.decodeAdvantage(rRoll)
    end
	local rMessage = ActionsManager.createActionMessage(rSource, rRoll)
	Comm.deliverChatMessage(rMessage)

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
        rOriginalAttacker = ActorManager.resolveActor(rRoll.sOriginalAttacker)
    end
    local rActualSource = rOriginalAttacker or rSource

    if nConSave >= nDC then
        -- Undead Fortitude save was made!
        nDamage = nAllHP - tonumber(rRoll.nWounds or 0) - 1
        local sDamage = string.gsub(rRoll.sDamage, "=%-?%d+", "=" .. nDamage)
        local rDamageRoll = {
            sType = "damage",
            sDesc = sDamage,
            nTotal = tonumber(nDamage),
            aDice = {},
            bSecret = bSecret
        }
        if ActionHealthD20 and ActionHealthD20.apply then
            ActionDamage_applyDamage(rActualSource, rTarget or rSource, rDamageRoll)
        elseif isClientFGU() then
            ActionDamage_applyDamage(rActualSource, rTarget or rSource, rDamageRoll)
        else
            ActionDamage_applyDamage(rActualSource, rTarget or rSource, bSecret, sDamage, nDamage)
        end
    else
        -- Undead Fortitude save was NOT made
        if tonumber(rRoll.nWounds) < tonumber(rRoll.nTotalHP) then
            local rDamageRoll = {
                sType = "damage",
                sDesc = rRoll.sDamage,
                nTotal = tonumber(rRoll.nDamage),
                aDice = {},
                bSecret = bSecret
            }
            if ActionHealthD20 and ActionHealthD20.apply then
                ActionDamage_applyDamage(rActualSource, rTarget or rSource, rDamageRoll)
            elseif isClientFGU() then
                ActionDamage_applyDamage(rActualSource, rTarget or rSource, rDamageRoll)
            else
                ActionDamage_applyDamage(rActualSource, rTarget or rSource, bSecret, rRoll.sDamage, nDamage)
            end
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

function getTargetHealthData_FGC(sTargetNodeType, nodeTarget)
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
	end

    return {
        nTotalHP = nTotalHP,
        nTempHP = nTempHP,
        nWounds = nWounds
    }
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
    if isClientFGU() then
        return getTargetHealthData_FGU(sTargetNodeType, nodeTarget, rRoll)
    else
        return getTargetHealthData_FGC(sTargetNodeType, nodeTarget)
    end
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
    local nAllHP = aFortitudeData.nTotalHP + aFortitudeData.nTempHP
    if aFortitudeData.nWounds + nTotal >= nAllHP
       and (aFortitudeData.bNoMods or not aFortitudeData.bUndead or not string.find(sDamage, "%[TYPE:.*radiant.*%]"))
       and (aFortitudeData.bNoMods or not string.find(sDamage, "%[CRITICAL%]"))
       and not EffectManager5E.hasEffect(rTarget, UNCONSCIOUS_EFFECT_LABEL)
       and aFortitudeData.nTotalHP > aFortitudeData.nWounds then
        local rRoll = { }
        rRoll.sType = "save"
        rRoll.aDice = { "d20" }
        local nMod, bADV, bDIS, sAddText = ActorManager5E.getSave(rTarget, "constitution")
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
        rRoll.nDamage = nTotal
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

function applyDamage_FGC(rSource, rTarget, bSecret, sDamage, nTotal)
	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget)
	if not nodeTarget then return end

    local aFortitudeData = hasFortitudeTrait(sTargetNodeType, nodeTarget, nil)
    local bFortitudeTriggered
    if aFortitudeData then
        bFortitudeTriggered = processFortitude(aFortitudeData, nTotal, sDamage, rSource, rTarget, bSecret)
    end

    if not bFortitudeTriggered then
        ActionDamage_applyDamage(rSource, rTarget, bSecret, sDamage, nTotal)
    end
end

function applyDamage_FGU(rSource, rTarget, rRoll)
	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget)
	if not nodeTarget then return end

    local aFortitudeData = hasFortitudeTrait(sTargetNodeType, nodeTarget, rRoll)
     local bFortitudeTriggered
    if aFortitudeData then
        bFortitudeTriggered = processFortitude(aFortitudeData, rRoll.nTotal, rRoll.sDesc, rSource, rTarget, false)
    end

    if not bFortitudeTriggered then
        ActionDamage_applyDamage(rSource, rTarget, rRoll)
    end
end

function applyDamage_v2(rSource, rTarget, rRoll)
	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget)
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
        ActionDamage_applyDamage(rSource, rTarget, rRoll)
    end
end
