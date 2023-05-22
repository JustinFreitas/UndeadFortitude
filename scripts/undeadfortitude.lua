-- This extension contains 5e SRD mounted combat rules.  For license details see file: Open Gaming License v1.0a.txt
USER_ISHOST = false

local ActionDamage_applyDamage
local aUndeadFortitudeRollQueue = {}

function onInit()
    USER_ISHOST = User.isHost()

	if USER_ISHOST then
        ActionDamage_applyDamage = ActionDamage.applyDamage
        if isClientFGU() then
            ActionDamage.applyDamage = applyDamage_FGU

        else
            ActionDamage.applyDamage = applyDamage
        end
        ActionsManager.registerResultHandler("save", onSaveNew);
    end
end

function isClientFGU()
    return Session.VersionMajor >= 4
end

function onSaveNew(rSource, rTarget, rRoll)
    if not string.find(rRoll.sDesc, "Undead Fortitude") then
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
    local nDC = 5 + nDamage
    local msgShort = {font = "msgfont"};
	local msgLong = {font = "msgfont"};

	msgShort.text = "Undead Fortitude";
	msgLong.text = "Undead Fortitude [" .. nConSave ..  "]";
    msgLong.text = msgLong.text .. "[vs. DC " .. nDC .. "]";
	msgShort.text = msgShort.text .. " ->";
	msgLong.text = msgLong.text .. " ->";
    msgShort.text = msgShort.text .. " [for " .. ActorManager.getDisplayName(rSource) .. "]";
    msgLong.text = msgLong.text .. " [for " .. ActorManager.getDisplayName(rSource) .. "]";

	msgShort.icon = "roll_cast";

	if nConSave >= nDC then
		msgLong.text = msgLong.text .. " [SUCCESS]";
	else
		msgLong.text = msgLong.text .. " [FAILURE]";
	end

	local bSecret = aLastUndeadFortitudeRoll.bSecret;
    ActionsManager.outputResult(bSecret, rSource, nil, msgLong, msgShort)

    -- APPLY THE DAMAGE BASED ON THE Undead Fortitude SAVE
    local nAllHP = aLastUndeadFortitudeRoll.nTotalHP + aLastUndeadFortitudeRoll.nTempHP
    --Debug.chat(rSource, rTarget, rRoll)
    if nConSave >= nDC then
        --Debug.chat("Undead Fortitude save was made!  DC:" .. nDC .. "  Roll:" .. nConSave)
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
        --Debug.chat("Undead Fortitude save was NOT made.  DC:" .. nDC .. "  Roll:" .. nConSave)
        if aLastUndeadFortitudeRoll.nWounds < aLastUndeadFortitudeRoll.nTotalHP then -- TODO:  Is this right or use the Unconscious effect?
            if isClientFGU() then
                ActionDamage_applyDamage(rSource, rTarget, rRoll)
            else
                ActionDamage_applyDamage(rSource, rTarget, aLastUndeadFortitudeRoll.bSecret, aLastUndeadFortitudeRoll.sDamage, nDamage)
            end
        end
    end
end

--In FGU, the sig to this function is just rSource, rTarget, rRoll.
function applyDamage(rSource, rTarget, bSecret, sDamage, nTotal)
	local nTotalHP, nTempHP, nWounds, aTraits;
	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget);
	if not nodeTarget then
		return;
	end

    local hasUndeadFortitude = false
	if sTargetNodeType == "pc" then
		nTotalHP = DB.getValue(nodeTarget, "hp.total", 0)
		nTempHP = DB.getValue(nodeTarget, "hp.temporary", 0)
		nWounds = DB.getValue(nodeTarget, "hp.wounds", 0)
        aTraits = DB.getChildren(nodeTarget, "traitlist")
    elseif sTargetNodeType == "ct" then
		nTotalHP = DB.getValue(nodeTarget, "hptotal", 0)
		nTempHP = DB.getValue(nodeTarget, "hptemp", 0)
		nWounds = DB.getValue(nodeTarget, "wounds", 0)
        aTraits = DB.getChildren(nodeTarget, "traits")
	else
		return
	end

    local nAllHP = nTotalHP + nTempHP
    if nWounds + nTotal >= nAllHP then
        for _, trait in pairs(aTraits) do
            if DB.getText(trait, "name"):lower() == "undead fortitude" then
                hasUndeadFortitude = true
                break
            end
        end
    end

    if hasUndeadFortitude
       and not string.find(sDamage, "%[TYPE:.*radiant.*%]")
       and not string.find(sDamage, "%[CRITICAL%]")
       and not EffectManager5E.hasEffect(rTarget, "Unconscious")
       and nTotalHP > nWounds then
        local rRoll = { }
        rRoll.sType = "save"
        rRoll.aDice = { "d20" }
        local nMod, bADV, bDIS, sAddText = ActorManager5E.getSave(rTarget, "constitution")
        rRoll.nMod = nMod
        rRoll.sDesc = "[SAVE] Constitution for Undead Fortitude" -- TODO: Adv/Dis from effects Breaks w/out Constitution in desc.  Should it be localized?
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
        aLastUndeadFortitudeRoll.nTotalHP = nTotalHP
        aLastUndeadFortitudeRoll.nTempHP = nTempHP
        aLastUndeadFortitudeRoll.nWounds = nWounds
        table.insert(aUndeadFortitudeRollQueue, aLastUndeadFortitudeRoll)
        ActionsManager.applyModifiersAndRoll(rTarget, rTarget, false, rRoll)
        return
    end

    ActionDamage_applyDamage(rSource, rTarget, bSecret, sDamage, nTotal)
end

--In FGU, the sig to this function is just rSource, rTarget, rRoll...  rRoll.bSecret, rRoll.sDesc, rRoll.nTotal
function applyDamage_FGU(rSource, rTarget, rRoll)
	local nTotalHP, nTempHP, nWounds, aTraits;
	local sTargetNodeType, nodeTarget = ActorManager.getTypeAndNode(rTarget);
	if not nodeTarget then
		return;
	end

    local hasUndeadFortitude = false
	if sTargetNodeType == "pc" then
		nTotalHP = DB.getValue(nodeTarget, "hp.total", 0)
		nTempHP = DB.getValue(nodeTarget, "hp.temporary", 0)
		nWounds = DB.getValue(nodeTarget, "hp.wounds", 0)
        aTraits = DB.getChildren(nodeTarget, "traitlist")
    elseif sTargetNodeType == "ct" then
		nTotalHP = DB.getValue(nodeTarget, "hptotal", 0)
		nTempHP = DB.getValue(nodeTarget, "hptemp", 0)
		nWounds = DB.getValue(nodeTarget, "wounds", 0)
        aTraits = DB.getChildren(nodeTarget, "traits")
	elseif sTargetNodeType == "ct" and ActorManager.isRecordType(rTarget, "vehicle") then
		if (rRoll.sSubtargetPath or "") ~= "" then
			nTotalHP = DB.getValue(DB.getPath(rRoll.sSubtargetPath, "hp"), 0);
			nWounds = DB.getValue(DB.getPath(rRoll.sSubtargetPath, "wounds"), 0);
			nTempHP = 0;
		else
			nTotalHP = DB.getValue(nodeTarget, "hptotal", 0);
			nTempHP = DB.getValue(nodeTarget, "hptemp", 0);
			nWounds = DB.getValue(nodeTarget, "wounds", 0);
		end
	else
		return
	end

    local nAllHP = nTotalHP + nTempHP
    if nWounds + rRoll.nTotal >= nAllHP then
        for _, trait in pairs(aTraits) do
            if DB.getText(trait, "name"):lower() == "undead fortitude" then
                hasUndeadFortitude = true
                break
            end
        end
    end

    if hasUndeadFortitude and not EffectManager5E.hasEffect(rTarget, "Unconscious") and nTotalHP > nWounds then
        local rUndeadFortitudeRoll = { }
        rUndeadFortitudeRoll.sType = "save"
        rUndeadFortitudeRoll.aDice = { "d20" }
        local nMod, bADV, bDIS, sAddText = ActorManager5E.getSave(rTarget, "constitution")
        rUndeadFortitudeRoll.nMod = nMod
        rUndeadFortitudeRoll.sDesc = "[SAVE] Constitution for Undead Fortitude" -- TODO: Adv/Dis from effects Breaks w/out Constitution in desc.  Should it be localized?
        if sAddText and sAddText ~= "" then
            rUndeadFortitudeRoll.sDesc = rUndeadFortitudeRoll.sDesc .. " " .. sAddText
        end
        if bADV then
            rUndeadFortitudeRoll.sDesc = rUndeadFortitudeRoll.sDesc .. " [ADV]"
        end
        if bDIS then
            rUndeadFortitudeRoll.sDesc = rUndeadFortitudeRoll.sDesc .. " [DIS]"
        end

        rUndeadFortitudeRoll.bSecret = false -- (ActorManager.getFaction(rTarget) ~= "friend") -- TODO: Is this correct for secret?  Shouldn't we check the roll options?
        local aLastUndeadFortitudeRoll = {}
        aLastUndeadFortitudeRoll.nDamage = rRoll.nTotal
        aLastUndeadFortitudeRoll.sDamage = rRoll.sDesc
        aLastUndeadFortitudeRoll.bSecret = rRoll.bSecret
        aLastUndeadFortitudeRoll.nTotalHP = nTotalHP
        aLastUndeadFortitudeRoll.nTempHP = nTempHP
        aLastUndeadFortitudeRoll.nWounds = nWounds
        table.insert(aUndeadFortitudeRollQueue, aLastUndeadFortitudeRoll)
        ActionsManager.applyModifiersAndRoll(rTarget, rTarget, false, rUndeadFortitudeRoll)
        return
    end

    ActionDamage_applyDamage(rSource, rTarget, rRoll)
end
