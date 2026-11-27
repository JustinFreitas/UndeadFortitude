local CANDIDATE_SLOTS = { 8, 7, 5, 4, 3, 2, 1 }
local nMenuSlot = nil

function onInit()
	if super and super.onInit then
		super.onInit();
	end

	nMenuSlot = nil
	if hasMenuItem then
		for _, nSlot in ipairs(CANDIDATE_SLOTS) do
			if not hasMenuItem(nSlot) then
				nMenuSlot = nSlot
				break
			end
		end
	else
		nMenuSlot = 8
	end

	if nMenuSlot then
		registerMenuItem("Apply Fortitude to Unconscious Actor", "white_undeadfortitude_icon", nMenuSlot)
	end
end

function onMenuSelection(selection, subselection, subsubselection)
    if nMenuSlot and selection == nMenuSlot then
        local nodeCT = getDatabaseNode()
        if nodeCT then
            applyUndeadFortitude(nodeCT)
        end
        return
    end

    if super and super.onMenuSelection then
        super.onMenuSelection(selection, subselection, subsubselection)
    end
end

function applyUndeadFortitude(nodeCT)
    UndeadFortitude.applyUndeadFortitude(nodeCT)
end
