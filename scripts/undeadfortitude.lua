-- This extension contains 5e SRD mounted combat rules.  For license details see file: Open Gaming License v1.0a.txt
USER_ISHOST = false

local ActionDamage_applyDamage
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
        displayChatMessage(sParams .. " was not found in the Combat Tracker, skipping Fortitude application.")
        return
    end

    applyUndeadFortitude(nodeCT)
end

function displayChatMessage(sFormattedText)
	if not sFormattedText then return end

	local msg = {font = MSGFONT, icon = "undeadfortitude_icon", secret = false, text = sFormattedText}
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
        ActionSave.onSave(rSource, rTarget, rRoll)
        return
    end

    ActionsManager2.decodeAdvantage(rRoll)
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

    ActionsManager.outputResult(rRoll.bSecret, rSource, nil, msgLong, msgShort)

    -- Undead Fortitude processing
    local nAllHP = rRoll.nTotalHP + rRoll.nTempHP
    if nConSave >= nDC then
        -- Undead Fortitude save was made!
        nDamage = nAllHP - rRoll.nWounds - 1
        local sDamage = string.gsub(rRoll.sDamage, "=%-?%d+", "=" .. nDamage)
        if isClientFGU() then
            local rDamageRoll = deserializeTable(rRoll.rDamageRoll)
            rDamageRoll.nTotal = tonumber(nDamage)
            rDamageRoll.sDesc = sDamage
            ActionDamage_applyDamage(rSource, rTarget, rDamageRoll)
        else
            ActionDamage_applyDamage(rSource, rTarget, rRoll.bSecret, sDamage, nDamage)
        end
    else
        -- Undead Fortitude save was NOT made
        if tonumber(rRoll.nWounds) < tonumber(rRoll.nTotalHP) then
            if isClientFGU() then
                ActionDamage_applyDamage(rSource, rTarget, deserializeTable(rRoll.rDamageRoll))
            else
                ActionDamage_applyDamage(rSource, rTarget, rRoll.bSecret, rRoll.sDamage, nDamage)
            end
        end
    end
end

function serializeTable(tbl)
    local result = "{"
    local first = true

    for key, value in pairs(tbl) do
        if not first then
            result = result .. ","
        end

        if type(key) == "string" then
            result = result .. '["' .. key .. '"]'
        else
            result = result .. "[" .. key .. "]"
        end

        result = result .. "="

        if type(value) == "table" then
            result = result .. serializeTable(value)
        elseif type(value) == "string" then
            result = result .. '"' .. value .. '"'
        else
            result = result .. tostring(value)
        end

        first = false
    end

    result = result .. "}"
    return result
end

function deserializeTable(str)
    local function parseValue(value)
        if value == "true" then
            return true
        elseif value == "false" then
            return false
        elseif tonumber(value) then
            return tonumber(value)
        else
            return value:sub(2, -2)
        end
    end

    local function parsePair(key, value)
        return key, parseValue(value)
    end

    local tbl = {}
    local startIdx = 1
    endIndex, key, value = select(2, str:find('%[%"(.-)%"]=([^,}]+)', startIdx))
    while key ~= nil and value ~= nil do
        parsedKey, parsedValue = parsePair(key, value)
        tbl[parsedKey] = parsedValue
        startIdx = endIndex + 1
        endIndex, key, value = select(2, str:find('%[%"(.-)%"]=([^,}]+)', startIdx))
    end

    return tbl
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

function processFortitude(aFortitudeData, nTotal, sDamage, rTarget, bSecret, rDamageRoll)
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
        rRoll.bUndeadFortitude = true
        rRoll.nDamage = nTotal
        rRoll.sDamage = sDamage
        rRoll.nTotalHP = aFortitudeData.nTotalHP
        rRoll.nTempHP = aFortitudeData.nTempHP
        rRoll.nWounds = aFortitudeData.nWounds
        rRoll.sModDC = tostring(aFortitudeData.nModDC) -- override number, can be nil
        rRoll.sStaticDC = tostring(aFortitudeData.nStaticDC) -- override number, can be nil
        rRoll.sTrimmedFortitudeTraitNameForSave = aFortitudeData.sTrimmedFortitudeTraitNameForSave
        if rDamageRoll ~= nil then
            rRoll.rDamageRoll = serializeTable(rDamageRoll)
        end

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
        bFortitudeTriggered = processFortitude(aFortitudeData, nTotal, sDamage, rTarget, bSecret, nil)
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
        bFortitudeTriggered = processFortitude(aFortitudeData, rRoll.nTotal, rRoll.sDesc, rTarget, false, rRoll)
    end

    if not bFortitudeTriggered then
        ActionDamage_applyDamage(rSource, rTarget, rRoll)
    end
end
