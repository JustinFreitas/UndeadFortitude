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
        local sDamage = string.gsub(aLastUndeadFortitudeRoll.sDamage, "=%d+", "=" .. nDamage)
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

    if hasUndeadFortitude and not EffectManager5E.hasEffect(rTarget, "Unconscious") and nTotalHP > nWounds then
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

function addLanguagesToTable(aTable, rCurrentActor, aCampaignLanguages, aLanguagesToAdd)
    for _,sLanguage in pairs(aLanguagesToAdd) do
        local language = StringManager.trim(sLanguage)
        if not aCampaignLanguages[language] then
            language = language .. " (non-campaign)"
        end

        local aNames = aTable[language]
        if not aNames then
            aNames = {}
        end

        local sTrimmedName = StringManager.trim(rCurrentActor.sName)
        table.insert(aNames, sTrimmedName)
        aTable[language] = aNames
    end
end

-- Puts a message in chat that is broadcast to everyone attached to the host (including the host) if bSecret is true, otherwise local only.
function displayChatMessage(sFormattedText, bSecret)
	if not sFormattedText then return end

	local msg = {font = "msgfont", icon = "languagetracker_icon", secret = bSecret, text = sFormattedText}

	-- deliverChatMessage() is a broadcast mechanism, addChatMessage() is local only.
	if bSecret then
		Comm.addChatMessage(msg)
	else
		Comm.deliverChatMessage(msg)
	end
end

function displayTableIfNonEmpty(aTable)
	aTable = validateTableOrNew(aTable)
	if #aTable > 0 then
		local sDisplay = table.concat(aTable, "\r")
		displayChatMessage(sDisplay, true) -- TODO: make any 'party' role public, but everything else should be private to not leak npc info.
	end
end

function getCampaignLanguagesTable()
    local aCampaignLanguages = {}
	for _,v in pairs(DB.getChildren(LanguageManager.CAMPAIGN_LANGUAGE_LIST)) do
		local sLang = DB.getValue(v, LanguageManager.CAMPAIGN_LANGUAGE_LIST_NAME, "")
		sLang = StringManager.trim(sLang)
		if (sLang or "") ~= "" then
            aCampaignLanguages[sLang] = 1
		end
	end

    return aCampaignLanguages
end

function getLanguageTableFromCommaDelimitedString(sCommaDelimited)
    local aTable = {}
    for word in string.gmatch(sCommaDelimited, '([^,]+)') do
        local sTrimmedWord = StringManager.trim(word)
        table.insert(aTable, sTrimmedWord)
    end

    return aTable
end

function getLanguageTableFromDatabaseNodes(nodeCharSheet)
    local aLanguageTable = {}
    for _,vLanguage in pairs(DB.getChildren(nodeCharSheet, "languagelist")) do
        local sTrimmedLanguage = StringManager.trim(DB.getValue(vLanguage, "name", ""))
        table.insert(aLanguageTable, sTrimmedLanguage)
    end

    return aLanguageTable
end

-- Handler for the message to do an attack from a mount.
function insertBlankSeparatorIfNotEmpty(aTable)
	if #aTable > 0 then table.insert(aTable, "") end
end

function insertFormattedTextWithSeparatorIfNonEmpty(aTable, sFormattedText)
	insertBlankSeparatorIfNotEmpty(aTable)
	table.insert(aTable, sFormattedText)
end

-- TODO: Have a chat command that removes Unconscious and deducts a single wound letting chat know the details.
function processChatCommand(_, sParams)
    local aCampaignLanguages = getCampaignLanguagesTable()
    local allFriendlyLanguages = {}
	for _,nodeCT in pairs(DB.getChildren(CombatManager.CT_LIST)) do
        if DB.getValue(nodeCT, "friendfoe", "foe") == "friend" or sParams == "all" then
            local rCurrentActor = ActorManager.resolveActor(nodeCT)
            local nodeCharSheet = DB.findNode(rCurrentActor.sCreatureNode)
            local aLanguagesToAdd
            if rCurrentActor.sType == "charsheet" then
                aLanguagesToAdd = getLanguageTableFromDatabaseNodes(nodeCharSheet)
            else
                aLanguagesToAdd = getLanguageTableFromCommaDelimitedString(DB.getValue(nodeCharSheet, "languages", ""))
            end

            addLanguagesToTable(allFriendlyLanguages, rCurrentActor, aCampaignLanguages, aLanguagesToAdd)
        end
    end

    local sortedLanguages = {}
    for s,v in pairs(allFriendlyLanguages) do
        table.insert(sortedLanguages,{language = s, pcs = v})
    end

	table.sort(sortedLanguages, function (a, b) return a.language < b.language end)
    local aOutput = {}
    local scope = "Party"
    if sParams == "all" then
        scope = "All"
    end
    insertFormattedTextWithSeparatorIfNonEmpty(aOutput, "\r-- " .. scope .. " Known Languages --")
    for _,v in ipairs(sortedLanguages) do
        local pcs = ""
        local bFirstRow = true
        table.sort(v.pcs)
        for _,pc in ipairs(v.pcs) do
            if bFirstRow then
                pcs = pc
                bFirstRow = false
            else
                pcs = pcs .. ", " .. pc
            end
        end

        insertFormattedTextWithSeparatorIfNonEmpty(aOutput, v.language .. " - " .. pcs)
    end

    displayTableIfNonEmpty(aOutput)
end

-- Chat commands that are for host only
function validateTableOrNew(aTable)
	if aTable and type(aTable) == "table" then
		return aTable
	else
		return {}
	end
end
