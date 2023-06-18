-- This extension contains 5e SRD mounted combat rules.  For license details see file: Open Gaming License v1.0a.txt
USER_ISHOST = false

local ActionDamage_applyDamage
local aUndeadFortitudeRollQueue = {}
local UNCONSCIOUS_EFFECT_LABEL = "Unconscious"
local UNDEAD_FORTITUDE = "Undead Fortitude"

function onInit()
    USER_ISHOST = User.isHost()

	if USER_ISHOST then
		Comm.registerSlashHandler("uf", processChatCommand)
		Comm.registerSlashHandler("undeadfortitude", processChatCommand)
        ActionsManager.registerResultHandler("save", onSaveNew)
        ActionDamage_applyDamage = ActionDamage.applyDamage
        if isClientFGU() then
            ActionDamage.applyDamage = applyDamage_FGU
        else
            ActionDamage.applyDamage = applyDamage_FGC
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
        displayChatMessage(sParams .. " was not found in the Combat Tracker, skipping Undead Fortitude application.")
        return
    end

    applyUndeadFortitude(nodeCT)
end

function displayChatMessage(sFormattedText)
	if not sFormattedText then return end

	local msg = {font = "msgfont", icon = "undeadfortitude_icon", secret = false, text = sFormattedText}
    Comm.addChatMessage(msg) -- local, not broadcast
end

function applyUndeadFortitude(nodeCT)
    local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(nodeCT)
	if not nodeTarget then
		return
	end

    local sWounds
    if sTargetNodeType == "pc" then
        sWounds = "hp.wounds"
    elseif sTargetNodeType == "ct" then
        sWounds = "wounds"
	else
		return
	end

    local sDisplayName = ActorManager.getDisplayName(nodeTarget)
    if not EffectManager5E.hasEffect(nodeTarget, UNCONSCIOUS_EFFECT_LABEL) then
        displayChatMessage(sDisplayName .. " is not an unconscious actor, skipping Fortitude application.")
        return
    end

    local nWounds = DB.getValue(nodeTarget, sWounds, 0) - 1
    DB.setValue(nodeTarget, sWounds, "number", nWounds)
    EffectManager.removeEffect(nodeTarget, UNCONSCIOUS_EFFECT_LABEL)
    EffectManager.removeEffect(nodeTarget, "Prone")
    displayChatMessage("Fortitude was applied to " .. sDisplayName .. ".")
end

function isClientFGU()
    return Session.VersionMajor >= 4
end

function onSaveNew(rSource, rTarget, rRoll)
    local sFortitudeTraitNameForSave = UNDEAD_FORTITUDE
    if aUndeadFortitudeRollQueue[1] ~= nil then
        sFortitudeTraitNameForSave = aUndeadFortitudeRollQueue[1].sFortitudeTraitNameForSave
    end

    if not string.find(rRoll.sDesc, sFortitudeTraitNameForSave) then
        ActionSave.onSave(rSource, rTarget, rRoll)
        return
    end

    ActionsManager2.decodeAdvantage(rRoll)
	local rMessage = ActionsManager.createActionMessage(rSource, rRoll)
	Comm.deliverChatMessage(rMessage)

    local nConSave = ActionsManager.total(rRoll)
    local aLastUndeadFortitudeRoll = table.remove(aUndeadFortitudeRollQueue, 1)
    if aLastUndeadFortitudeRoll == nil then return end

    local nDamage = aLastUndeadFortitudeRoll.nDamage
    local nModDC = 5
    if aLastUndeadFortitudeRoll.nModDC ~= nil then
        nModDC = aLastUndeadFortitudeRoll.nModDC
    end

    local nDC = nModDC + nDamage
    if aLastUndeadFortitudeRoll.nStaticDC ~= nil then
        nDC = aLastUndeadFortitudeRoll.nStaticDC
    end

    local msgShort = {font = "msgfont"}
	local msgLong = {font = "msgfont"}

	msgShort.text = sFortitudeTraitNameForSave
	msgLong.text = sFortitudeTraitNameForSave .. " [" .. nConSave ..  "]"
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

	local bSecret = aLastUndeadFortitudeRoll.bSecret
    ActionsManager.outputResult(bSecret, rSource, nil, msgLong, msgShort)

    -- Undead Fortitude processing
    local nAllHP = aLastUndeadFortitudeRoll.nTotalHP + aLastUndeadFortitudeRoll.nTempHP
    if nConSave >= nDC then
        -- Undead Fortitude save was made!
        nDamage = nAllHP - aLastUndeadFortitudeRoll.nWounds - 1
        local sDamage = string.gsub(aLastUndeadFortitudeRoll.sDamage, "=%-?%d+", "=" .. nDamage)
        if isClientFGU() then
            rRoll.nTotal = nDamage
            rRoll.sDesc = sDamage
            ActionDamage_applyDamage(rSource, rTarget, rRoll)
        else
            ActionDamage_applyDamage(rSource, rTarget, bSecret, sDamage, nDamage)
        end
    else
        -- Undead Fortitude save was NOT made
        if aLastUndeadFortitudeRoll.nWounds < aLastUndeadFortitudeRoll.nTotalHP then
            if isClientFGU() then
                ActionDamage_applyDamage(rSource, rTarget, rRoll)
            else
                ActionDamage_applyDamage(rSource, rTarget, aLastUndeadFortitudeRoll.bSecret, aLastUndeadFortitudeRoll.sDamage, nDamage)
            end
        end
    end
end

function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
 end

function hasFortitudeTrait(sTargetNodeType, nodeTarget, rTarget, rRoll)
    local aTraits
	if sTargetNodeType == "pc" then
        aTraits = DB.getChildren(nodeTarget, "traitlist")
    elseif sTargetNodeType == "ct" then
        aTraits = DB.getChildren(nodeTarget, "traits")
	else
		return
	end

    for _, aTrait in pairs(aTraits) do
        local aDecomposedTraitName = decomposeTraitName(aTrait)
        if aDecomposedTraitName.nFortitudeStart ~= nil then
            return getFortitudeData(aDecomposedTraitName, aTraits, sTargetNodeType, nodeTarget, rTarget, rRoll)
        end
    end
end

function getTargetHealthData_FGC(sTargetNodeType, nodeTarget)
    local nTotalHP = DB.getValue(nodeTarget, "hp.total", 0)
    local nTempHP = DB.getValue(nodeTarget, "hp.temporary", 0)
    local nWounds = DB.getValue(nodeTarget, "hp.wounds", 0)
	if sTargetNodeType == "pc" then
		nTotalHP = DB.getValue(nodeTarget, "hp.total", 0)
		nTempHP = DB.getValue(nodeTarget, "hp.temporary", 0)
		nWounds = DB.getValue(nodeTarget, "hp.wounds", 0)
    elseif sTargetNodeType == "ct" then
		nTotalHP = DB.getValue(nodeTarget, "hptotal", 0)
		nTempHP = DB.getValue(nodeTarget, "hptemp", 0)
		nWounds = DB.getValue(nodeTarget, "wounds", 0)
	end

    return {
        nTotalHP = nTotalHP,
        nTempHP = nTempHP,
        nWounds = nWounds
    }
end

function getTargetHealthData_FGU(sTargetNodeType, nodeTarget, rTarget, rRoll)
    local nTotalHP = DB.getValue(nodeTarget, "hp.total", 0)
    local nTempHP = DB.getValue(nodeTarget, "hp.temporary", 0)
    local nWounds = DB.getValue(nodeTarget, "hp.wounds", 0)
	if sTargetNodeType == "pc" then
		nTotalHP = DB.getValue(nodeTarget, "hp.total", 0)
		nTempHP = DB.getValue(nodeTarget, "hp.temporary", 0)
		nWounds = DB.getValue(nodeTarget, "hp.wounds", 0)
    elseif sTargetNodeType == "ct" then
		nTotalHP = DB.getValue(nodeTarget, "hptotal", 0)
		nTempHP = DB.getValue(nodeTarget, "hptemp", 0)
		nWounds = DB.getValue(nodeTarget, "wounds", 0)
	elseif sTargetNodeType == "ct" and ActorManager.isRecordType(rTarget, "vehicle") then
		if (rRoll.sSubtargetPath or "") ~= "" then
			nTotalHP = DB.getValue(DB.getPath(rRoll.sSubtargetPath, "hp"), 0)
			nWounds = DB.getValue(DB.getPath(rRoll.sSubtargetPath, "wounds"), 0)
			nTempHP = 0
		else
			nTotalHP = DB.getValue(nodeTarget, "hptotal", 0)
			nTempHP = DB.getValue(nodeTarget, "hptemp", 0)
			nWounds = DB.getValue(nodeTarget, "wounds", 0)
		end
	end

    return {
        nTotalHP = nTotalHP,
        nTempHP = nTempHP,
        nWounds = nWounds
    }
end

function getFortitudeData(aDecomposedTraitName, aTraits, sTargetNodeType, nodeTarget, rTarget, rRoll)
    local bUndead = false
    if trim(aDecomposedTraitName.sFortitudeTraitPrefix):lower():match("undead") then
        bUndead = true
    end

    local sTrimmedSuffixLower = trim(aDecomposedTraitName.sFortitudeTraitSuffix):lower()
    local nStaticDC = tonumber(sTrimmedSuffixLower:match("dc%s*(%d+)"))
    local nModDC = tonumber(sTrimmedSuffixLower:match("mod%s*(%d+)"))
    local bNoMods = trim(sTrimmedSuffixLower):find("no%s*mods")
    local aTargetHealthData
    if isClientFGU() then
        aTargetHealthData = getTargetHealthData_FGU(sTargetNodeType, nodeTarget, rTarget, rRoll)
    else
        aTargetHealthData = getTargetHealthData_FGC(sTargetNodeType, nodeTarget)
    end

    return {
        nTotalHP = aTargetHealthData.nTotalHP,
        nTempHP = aTargetHealthData.nTempHP,
        nWounds = aTargetHealthData.nWounds,
        aTraits = aTraits,
        bUndead = bUndead,
        nStaticDC = nStaticDC,
        nModDC = nModDC,
        bNoMods = bNoMods,
        sFortitudeTraitNameForSave = aDecomposedTraitName.sFortitudeTraitNameForSave
    }
end

function decomposeTraitName(aTrait)
    local sTraitName = DB.getText(aTrait, "name")
    local sTraitNameLower = sTraitName:lower()
    local nFortitudeStart, nFortitudeEnd = sTraitNameLower:find("fortitude")
    local sFortitudeTraitPrefix, sFortitudeTraitSuffix, sFortitudeTraitNameForSave
    if nFortitudeStart ~= nil and nFortitudeEnd ~= nil then
        sFortitudeTraitPrefix = sTraitName:sub(1, nFortitudeStart - 1)
        sFortitudeTraitSuffix = sTraitName:sub(nFortitudeEnd + 1)
        sFortitudeTraitNameForSave = trim(sTraitName:sub(1, nFortitudeEnd))
    end

    return {
        sTraitName = sTraitName,
        sTraitNameLower = sTraitNameLower,
        nFortitudeStart = nFortitudeStart,
        nFortitudeEnd = nFortitudeEnd,
        sFortitudeTraitPrefix = sFortitudeTraitPrefix,
        sFortitudeTraitSuffix = sFortitudeTraitSuffix,
        sFortitudeTraitNameForSave = sFortitudeTraitNameForSave
    }
end

function processFortitude(aFortitudeData, nTotal, sDamage, rTarget)
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
        rRoll.sDesc = "[SAVE] Constitution for " .. aFortitudeData.sFortitudeTraitNameForSave
        if sAddText and sAddText ~= "" then
            rRoll.sDesc = rRoll.sDesc .. " " .. sAddText
        end

        if bADV then
            rRoll.sDesc = rRoll.sDesc .. " [ADV]"
        end

        if bDIS then
            rRoll.sDesc = rRoll.sDesc .. " [DIS]"
        end

        rRoll.bSecret = false -- (ActorManager.getFaction(rTarget) ~= "friend") -- TODO: Is this correct for secret?  Shouldn't we check the roll options?
        local aLastUndeadFortitudeRoll = {}
        aLastUndeadFortitudeRoll.nDamage = nTotal
        aLastUndeadFortitudeRoll.sDamage = sDamage
        aLastUndeadFortitudeRoll.bSecret = rRoll.bSecret
        aLastUndeadFortitudeRoll.nTotalHP = aFortitudeData.nTotalHP
        aLastUndeadFortitudeRoll.nTempHP = aFortitudeData.nTempHP
        aLastUndeadFortitudeRoll.nWounds = aFortitudeData.nWounds
        aLastUndeadFortitudeRoll.nModDC = aFortitudeData.nModDC
        aLastUndeadFortitudeRoll.nStaticDC = aFortitudeData.nStaticDC
        aLastUndeadFortitudeRoll.sFortitudeTraitNameForSave = aFortitudeData.sFortitudeTraitNameForSave
        table.insert(aUndeadFortitudeRollQueue, aLastUndeadFortitudeRoll)
        ActionsManager.applyModifiersAndRoll(rTarget, rTarget, false, rRoll)
        return true
    end
end

function applyDamage_FGC(rSource, rTarget, bSecret, sDamage, nTotal)
	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget)
	if not nodeTarget then return end

    local aFortitudeData = hasFortitudeTrait(sTargetNodeType, nodeTarget, nil, nil)
    local bFortitudeTriggered
    if aFortitudeData then
        bFortitudeTriggered = processFortitude(aFortitudeData, nTotal, sDamage, rTarget)
    end

    if not bFortitudeTriggered then
        ActionDamage_applyDamage(rSource, rTarget, bSecret, sDamage, nTotal)
    end
end

function applyDamage_FGU(rSource, rTarget, rRoll)
	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget)
	if not nodeTarget then return end

    local aFortitudeData = hasFortitudeTrait(sTargetNodeType, nodeTarget, rTarget, rRoll)
    local bFortitudeTriggered
    if aFortitudeData then
        bFortitudeTriggered = processFortitude(aFortitudeData, rRoll.nTotal, rRoll.sDesc, rTarget)
    end

    if not bFortitudeTriggered then
        ActionDamage_applyDamage(rSource, rTarget, rRoll)
    end
end
