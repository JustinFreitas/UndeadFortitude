local BUTTON_POSITION_INDEX = 8

function onInit()
	if super and super.onInit then
		super.onInit();
	end

    registerMenuItem("Apply Undead Fortitude to Unconscious Actor", "white_undeadfortitude_icon", BUTTON_POSITION_INDEX)
end

function onMenuSelection(selection, subselection)
    local nodeCT = getDatabaseNode()
    if not nodeCT then return end

    if selection == BUTTON_POSITION_INDEX then
        applyUndeadFortitude(nodeCT)
        return
    end

    if super and super.onMenuSelection then
        super.onMenuSelection(selection, subselection)
    end
end

function applyUndeadFortitude(nodeCT)
    UndeadFortitude.applyUndeadFortitude(nodeCT)
end
