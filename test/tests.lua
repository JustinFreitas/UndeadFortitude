-- UNIT TESTS START
passed = 0
failed = 0
local test_cases = {}

function add_test(name, fn)
  table.insert(test_cases, { name = name, fn = fn })
end

function assert_equal(expected, actual, message)
  if expected ~= actual then
    error(string.format("Expected '%s', but got '%s'. %s", tostring(expected), tostring(actual), tostring(message or "")), 2)
  end
end

function assert_true(actual, message)
  if not actual then
    error(string.format("Expected true, but got false. %s", tostring(message or "")), 2)
  end
end

function assert_false(actual, message)
  if actual then
    error(string.format("Expected false, but got true. %s", tostring(message or "")), 2)
  end
end

function assert_nil(actual, message)
  if actual ~= nil then
    error(string.format("Expected nil, but got '%s'. %s", tostring(actual), tostring(message or "")), 2)
  end
end

-- Reset mock states helper
function reset_mocks()
  DB_DATA = {}
  ACTORS = {}
  ACTIVE_EFFECTS = {}
  REMOVED_EFFECTS = {}
  ROLL_REQUESTS = {}
  OUTPUT_RESULTS = {}
  CHAT_MESSAGES = {}
  ORIGINAL_DAMAGE_CALLS = {}
  MODIFIER_STACK_RESETS = 0
  MOCK_SAVE_RESULT = {
    nMod = 0,
    bADV = false,
    bDIS = false,
    sAddText = ""
  }
end

-- Test 1: trim helper function
add_test("trim helper function", function()
  assert_equal("hello", trim("  hello  "))
  assert_equal("hello", trim("hello"))
  assert_equal("", trim("   "))
end)

-- Test 2: getDecomposedTraitName function
add_test("getDecomposedTraitName function", function()
  -- Mock aTrait DB text
  DB_DATA["trait1.name"] = "Undead Fortitude"
  local dec1 = getDecomposedTraitName("trait1")
  assert_equal(8, dec1.nFortitudeStart)
  assert_equal(16, dec1.nFortitudeEnd)
  assert_equal("Undead ", dec1.sFortitudeTraitPrefix)
  assert_equal("", dec1.sFortitudeTraitSuffix)
  assert_equal("Undead Fortitude", dec1.sTrimmedFortitudeTraitNameForSave)

  DB_DATA["trait2.name"] = "Zombie Fortitude mod 2"
  local dec2 = getDecomposedTraitName("trait2")
  assert_equal(8, dec2.nFortitudeStart)
  assert_equal(16, dec2.nFortitudeEnd)
  assert_equal("Zombie ", dec2.sFortitudeTraitPrefix)
  assert_equal(" mod 2", dec2.sFortitudeTraitSuffix)
  assert_equal("Zombie Fortitude", dec2.sTrimmedFortitudeTraitNameForSave)

  DB_DATA["trait3.name"] = "Some Other Trait"
  local dec3 = getDecomposedTraitName("trait3")
  assert_nil(dec3.nFortitudeStart)
end)

-- Test 3: getFortitudeData function
add_test("getFortitudeData function", function()
  reset_mocks()
  local aDecomposed = {
    sFortitudeTraitPrefix = "Undead ",
    sFortitudeTraitSuffix = " mod 3 dc 14 no mods",
    sTrimmedFortitudeTraitNameForSave = "Undead Fortitude",
    nFortitudeStart = 8
  }
  DB_DATA["actor.hp.total"] = 20
  DB_DATA["actor.hp.temporary"] = 5
  DB_DATA["actor.hp.wounds"] = 10

  local data = getFortitudeData(aDecomposed, {}, "pc", "actor", {})
  assert_true(data.bUndead)
  assert_equal(14, data.nStaticDC)
  assert_equal(3, data.nModDC)
  assert_true(data.bNoMods ~= nil)
  assert_equal(20, data.nTotalHP)
  assert_equal(5, data.nTempHP)
  assert_equal(10, data.nWounds)
end)

-- Test 4: hasFortitudeTrait function
add_test("hasFortitudeTrait function", function()
  reset_mocks()
  -- Setup a PC with Undead Fortitude trait
  local nodePC = "charselect.id-00001"
  DB_DATA[nodePC .. ".hp.total"] = 25
  DB_DATA[nodePC .. ".hp.temporary"] = 0
  DB_DATA[nodePC .. ".hp.wounds"] = 5
  -- PC traitlist
  DB_DATA[nodePC .. ".traitlist.id-00001.name"] = "Undead Fortitude mod 5"

  local data = hasFortitudeTrait("pc", nodePC, nil)
  assert_true(data ~= nil, "Trait should be found")
  assert_equal("Undead Fortitude", data.sTrimmedFortitudeTraitNameForSave)
  assert_equal(5, data.nModDC)

  -- Setup a CT actor with another trait
  local nodeCT = "combattracker.list.id-00002"
  DB_DATA[nodeCT .. ".hptotal"] = 15
  DB_DATA[nodeCT .. ".hptemp"] = 0
  DB_DATA[nodeCT .. ".wounds"] = 0
  DB_DATA[nodeCT .. ".traits.id-00001.name"] = "Some other trait"
  
  local data2 = hasFortitudeTrait("ct", nodeCT, nil)
  assert_nil(data2, "Should return nil for actor without fortitude")
end)

-- Test 5: processFortitude trigger conditions
add_test("processFortitude trigger conditions", function()
  reset_mocks()
  local nodePC = "charselect.id-00001"
  local rTarget = { sType = "pc", node = nodePC, sName = "Zombie Steve" }
  ACTORS[nodePC] = rTarget

  local fortitudeData = {
    nTotalHP = 20,
    nTempHP = 5,
    nWounds = 10,
    bUndead = true,
    nModDC = 5,
    nStaticDC = nil,
    bNoMods = false,
    sTrimmedFortitudeTraitNameForSave = "Undead Fortitude"
  }

  -- 1. Damage doesn't reduce to 0: HP remaining = 20+5 - 10 = 15. Damage is 10. Wounds+dmg = 20 < 25.
  local triggered = processFortitude(fortitudeData, 10, "[TYPE: slashing]", nil, rTarget, false)
  assert_false(triggered, "Should not trigger if damage does not reduce to 0 HP")

  -- 2. Damage reduces to 0 (damage = 15. Wounds+dmg = 25 >= 25)
  triggered = processFortitude(fortitudeData, 15, "[TYPE: slashing]", nil, rTarget, false)
  assert_true(triggered, "Should trigger if damage reduces to 0 HP")
  assert_equal(1, #ROLL_REQUESTS)
  assert_equal(1, MODIFIER_STACK_RESETS)
  reset_mocks()

  -- 3. Damage reduces to 0, but is Radiant type (Undead Fortitude bypass)
  triggered = processFortitude(fortitudeData, 15, "[TYPE: radiant]", nil, rTarget, false)
  assert_false(triggered, "Should not trigger if damage type is radiant")
  assert_equal(0, #ROLL_REQUESTS)

  -- 4. Damage reduces to 0, radiant, but bNoMods is true
  local noModsData = {
    nTotalHP = 20,
    nTempHP = 5,
    nWounds = 10,
    bUndead = true,
    nModDC = 5,
    nStaticDC = nil,
    bNoMods = true,
    sTrimmedFortitudeTraitNameForSave = "Undead Fortitude"
  }
  triggered = processFortitude(noModsData, 15, "[TYPE: radiant]", nil, rTarget, false)
  assert_true(triggered, "Should trigger on radiant if bNoMods is true")
  reset_mocks()

  -- 5. Damage reduces to 0, but is Critical hit
  triggered = processFortitude(fortitudeData, 15, "[CRITICAL]", nil, rTarget, false)
  assert_false(triggered, "Should not trigger on critical hits")

  -- 6. Actor is already unconscious
  ACTIVE_EFFECTS[nodePC] = { "Unconscious" }
  triggered = processFortitude(fortitudeData, 15, "[TYPE: slashing]", nil, rTarget, false)
  assert_false(triggered, "Should not trigger if actor is already unconscious")
  reset_mocks()

  -- 7. Actor has wounds equal to or exceeding total HP (already dead/0 HP)
  local deadData = {
    nTotalHP = 20,
    nTempHP = 0,
    nWounds = 20,
    bUndead = true,
    nModDC = 5,
    nStaticDC = nil,
    bNoMods = false,
    sTrimmedFortitudeTraitNameForSave = "Undead Fortitude"
  }
  triggered = processFortitude(deadData, 5, "[TYPE: slashing]", nil, rTarget, false)
  assert_false(triggered, "Should not trigger if wounds already equal or exceed total HP")
end)

-- Test 6: applyDamage_FGC interception
add_test("applyDamage_FGC interception", function()
  reset_mocks()
  -- Setup target with Undead Fortitude trait
  local nodeCT = "combattracker.list.id-00001"
  local rTarget = { sType = "ct", nodeCT = nodeCT, sName = "Zombie" }
  ACTORS[nodeCT] = rTarget
  DB_DATA[nodeCT .. ".name"] = "Zombie"
  DB_DATA[nodeCT .. ".hptotal"] = 15
  DB_DATA[nodeCT .. ".hptemp"] = 0
  DB_DATA[nodeCT .. ".wounds"] = 5
  DB_DATA[nodeCT .. ".traits.id-00001.name"] = "Undead Fortitude mod 5"

  -- Triggering damage (10 slashing reduces wounds to 15, which is 0 HP)
  applyDamage_FGC(nil, rTarget, false, "[TYPE: slashing]", 10)
  assert_equal(1, #ROLL_REQUESTS, "Should trigger fortitude save roll")
  assert_equal(0, #ORIGINAL_DAMAGE_CALLS, "Should intercept and NOT call original damage immediately")

  reset_mocks()
  -- Setup target without fortitude trait
  DB_DATA[nodeCT .. ".hptotal"] = 15
  DB_DATA[nodeCT .. ".hptemp"] = 0
  DB_DATA[nodeCT .. ".wounds"] = 5
  DB_DATA[nodeCT .. ".traits.id-00001.name"] = "Some other trait"
  applyDamage_FGC(nil, rTarget, false, "[TYPE: slashing]", 10)
  assert_equal(0, #ROLL_REQUESTS, "Should not trigger fortitude save")
  assert_equal(1, #ORIGINAL_DAMAGE_CALLS, "Should directly apply original damage")
end)

-- Test 7: onSaveNew success and failure processing
add_test("onSaveNew success and failure", function()
  -- Scenario A: Save SUCCESS
  reset_mocks()
  local nodeCT = "combattracker.list.id-00001"
  local rTarget = { sType = "ct", nodeCT = nodeCT, sName = "Zombie" }
  ACTORS[nodeCT] = rTarget

  -- Total HP = 15, temp HP = 5, wounds before damage = 5. (All HP = 20).
  -- Roll data setup
  local rRoll = {
    bUndeadFortitude = "true",
    sModDC = "5",
    nDamage = 15,
    sDamage = "[TYPE: slashing]",
    nTotalHP = 15,
    nTempHP = 5,
    nWounds = 5,
    sTrimmedFortitudeTraitNameForSave = "Undead Fortitude",
    nMod = 2, -- Con save modifier
    aDice = { { result = 18 } } -- 18 + 2 = 20 total save
  }
  -- DC = ModDC (5) + Damage (15) = 20. Con save total = 20. Success!
  onSaveNew(nil, rTarget, rRoll)

  assert_equal(1, #OUTPUT_RESULTS)
  assert_true(OUTPUT_RESULTS[1].msgLong.text:find("%[SUCCESS%]"), "Message should show success")
  assert_equal(1, #ORIGINAL_DAMAGE_CALLS, "Should apply damage after save")
  -- Expected damage to apply = AllHP (20) - wounds (5) - 1 = 14 damage.
  assert_equal(14, ORIGINAL_DAMAGE_CALLS[1].nTotal, "Should apply adjusted damage to leave 1 HP")
  assert_equal("[TYPE: slashing]", ORIGINAL_DAMAGE_CALLS[1].sDamage)

  -- Scenario B: Save FAILURE
  reset_mocks()
  rRoll.aDice = { { result = 10 } } -- 10 + 2 = 12 total save. DC = 20. Failure!
  onSaveNew(nil, rTarget, rRoll)

  assert_equal(1, #OUTPUT_RESULTS)
  assert_true(OUTPUT_RESULTS[1].msgLong.text:find("%[FAILURE%]"), "Message should show failure")
  assert_equal(1, #ORIGINAL_DAMAGE_CALLS, "Should apply damage after save")
  -- Expected damage to apply = original damage = 15.
  assert_equal(15, ORIGINAL_DAMAGE_CALLS[1].nTotal, "Should apply original damage on save failure")
end)

-- Test 8: applyUndeadFortitude and processChatCommand
add_test("applyUndeadFortitude and processChatCommand", function()
  reset_mocks()
  local nodeCT = "combattracker.list.id-00001"
  local rTarget = { sType = "ct", nodeCT = nodeCT, sName = "Zombie" }
  ACTORS[nodeCT] = rTarget
  DB_DATA[nodeCT .. ".name"] = "Zombie"
  DB_DATA[nodeCT .. ".hptotal"] = 15
  DB_DATA[nodeCT .. ".wounds"] = 15 -- reduced to 0 HP/unconscious
  ACTIVE_EFFECTS[nodeCT] = { "Unconscious", "Prone" }

  -- 1. Apply Undead Fortitude manually
  applyUndeadFortitude(nodeCT)
  -- Should set wounds to HP_total - 1 = 14.
  assert_equal(14, DB_DATA[nodeCT .. ".wounds"])
  -- Should remove "Unconscious" and "Prone" effects
  assert_equal(2, #REMOVED_EFFECTS)
  assert_equal("Unconscious", REMOVED_EFFECTS[1].effect)
  assert_equal("Prone", REMOVED_EFFECTS[2].effect)
  assert_true(CHAT_MESSAGES[1].text:find("Fortitude was applied"), "Should output success chat message")

  -- 2. processChatCommand wrapper
  reset_mocks()
  DB_DATA[nodeCT .. ".name"] = "Zombie"
  DB_DATA[nodeCT .. ".hptotal"] = 15
  DB_DATA[nodeCT .. ".wounds"] = 15
  ACTIVE_EFFECTS[nodeCT] = { "Unconscious", "Prone" }

  processChatCommand(nil, "Zombie")
  assert_equal(14, DB_DATA[nodeCT .. ".wounds"], "Chat command should successfully process Zombie")

  -- 3. processChatCommand where name doesn't exist
  reset_mocks()
  processChatCommand(nil, "Nonexistent Creature")
  assert_true(CHAT_MESSAGES[1].text:find("was not found in the Combat Tracker"), "Should report missing actor")
end)

-- Initialize the extension script
onInit()

-- RUNNER
print("Running Undead Fortitude tests in Lua...")
for _, test in ipairs(test_cases) do
  local ok, err = pcall(test.fn)
  if ok then
    passed = passed + 1
    print("  [PASS] " .. test.name)
  else
    failed = failed + 1
    print("  [FAIL] " .. test.name)
    print("    Error: " .. tostring(err))
  end
end

print(string.format("\nTest results: %d passed, %d failed", passed, failed))
