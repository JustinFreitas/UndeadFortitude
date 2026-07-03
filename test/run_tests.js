const { LuaFactory } = require('wasmoon');
const fs = require('fs');
const path = require('path');

async function runTests() {
    const factory = new LuaFactory();
    const lua = await factory.createEngine();

    console.log("Setting up mock environment in Lua VM...");
    
    // Set up standard and custom Fantasy Grounds environment mocks
    await lua.doString(`
        -- Global mock setup
        _USER_ISHOST = true

        User = {
            isHost = function() return _USER_ISHOST == true end
        }

        StringManager = {
            isBlank = function(s)
                if type(s) ~= "string" then return false end
                return s:gsub("%s+", "") == ""
            end
        }

        ActorManager = {
            getActor = function(v) return v end,
            resolveActor = function(v) return v end,
            isPC = function(v) return v._isPC == true end,
            getCreatureNode = function(v) return v end,
            getCTNode = function(v) return v end,
            getDisplayName = function(v)
                if type(v) == "table" then
                    return v._data["name"] or v._name or "Unknown"
                end
                return tostring(v)
            end,
            getCreatureNodeName = function(v)
                if type(v) == "table" then return v._path end
                return tostring(v)
            end
        }

        ActorManager5E = {
            getSave = function(nodeActor, sSave)
                if nodeActor and nodeActor._con_save then
                    return nodeActor._con_save.mod or 0, nodeActor._con_save.adv or false, nodeActor._con_save.dis or false, nodeActor._con_save.text or ""
                end
                return 0, false, false, ""
            end
        }

        EffectManager = {
            hasEffect = function(rActor, sEffect, rTarget, bTargetedOnly)
                if not rActor or not rActor._effects then return false end
                for _, eff in ipairs(rActor._effects) do
                    if eff == sEffect then return true end
                end
                return false
            end,
            removeEffect = function(nodeCT, sEffect)
                if not nodeCT or not nodeCT._effects then return end
                local newEffects = {}
                for _, eff in ipairs(nodeCT._effects) do
                    if eff ~= sEffect then
                        table.insert(newEffects, eff)
                    end
                end
                nodeCT._effects = newEffects
            end
        }

        CombatManager = {
            CT_LIST = "combattracker.list"
        }

        ModifierStack = {
            wasReset = false,
            reset = function()
                ModifierStack.wasReset = true
            end
        }

        -- Original implementation functions to restore in clearMocks
        local function originalActionHealthApply(rSource, rTarget, rRoll)
            table.insert(ActionHealthD20.calls, { rSource = rSource, rTarget = rTarget, rRoll = rRoll })
        end

        local function originalActionDamageApplyDamage(rSource, rTarget, rRoll)
            table.insert(ActionDamage.calls, { rSource = rSource, rTarget = rTarget, rRoll = rRoll })
        end

        ActionHealthD20 = {
            apply = originalActionHealthApply,
            calls = {}
        }

        ActionDamage = {
            applyDamage = originalActionDamageApplyDamage,
            apply = originalActionDamageApplyDamage,
            calls = {}
        }

        ActionsManager = {
            _handlers = {},
            _original_handlers = {
                save = function() end
            },
            getResultHandler = function(sType)
                return ActionsManager._original_handlers[sType]
            end,
            registerResultHandler = function(sType, callback)
                ActionsManager._handlers[sType] = callback
            end,
            total = function(rRoll)
                return rRoll.nTotalOverride or 10
            end,
            outputResult = function(bSecret, rSource, rTarget, msgLong, msgShort)
                table.insert(ActionsManager.outputs, {
                    bSecret = bSecret,
                    rSource = rSource,
                    rTarget = rTarget,
                    msgLong = msgLong,
                    msgShort = msgShort
                })
            end,
            applyModifiersAndRoll = function(rSource, rTarget, bMulti, rRoll)
                table.insert(ActionsManager.rolls, {
                    rSource = rSource,
                    rTarget = rTarget,
                    bMulti = bMulti,
                    rRoll = rRoll
                })
            end,
            outputs = {},
            rolls = {}
        }

        Comm = {
            _slash_handlers = {},
            registerSlashHandler = function(cmd, callback)
                Comm._slash_handlers[cmd] = callback
            end,
            addChatMessage = function(msg)
                table.insert(Comm.chat_messages, msg)
            end,
            chat_messages = {}
        }

        -- Database Mock
        db_store = {}
        DB = {
            getValue = function(arg1, arg2, arg3)
                if type(arg1) == "table" then
                    local val = arg1._data[arg2]
                    if val == nil then return arg3 end
                    return val
                elseif type(arg1) == "string" then
                    local val = db_store[arg1]
                    if val == nil then return arg2 end
                    if type(val) == "table" then
                        return val._data["value"] or arg2
                    end
                    return val
                end
                return arg3 or arg2
            end,
            setValue = function(arg1, arg2, arg3, arg4)
                if type(arg1) == "table" then
                    arg1._data[arg2] = arg4
                    local absolutePath = arg1._path .. "." .. arg2
                    db_store[absolutePath] = arg4
                elseif type(arg1) == "string" then
                    db_store[arg1] = arg3
                end
            end,
            getText = function(node, subpath, default)
                if type(node) == "table" then
                    if subpath then
                        return node._data[subpath] or default or ""
                    else
                        return node._data["value"] or default or ""
                    end
                elseif type(node) == "string" then
                    local val = db_store[node]
                    if type(val) == "table" then
                        return val._data["value"] or default or ""
                    end
                    return val or subpath or ""
                end
                return ""
            end,
            getChildren = function(arg1, arg2)
                if type(arg1) == "string" then
                    local children = {}
                    for path, node in pairs(db_store) do
                        if type(node) == "table" and node._parent_path == arg1 then
                            children[node._name] = node
                        end
                    end
                    return children
                elseif type(arg1) == "table" then
                    local subpath = arg2
                    for k, v in pairs(arg1._children or {}) do
                        if k == subpath then
                            return v
                        end
                    end
                    return {}
                end
                return {}
            end,
            getPath = function(...)
                local args = {...}
                local path_parts = {}
                for i, v in ipairs(args) do
                    if type(v) == "table" then
                        table.insert(path_parts, v._path)
                    elseif type(v) == "string" and v ~= "" then
                        table.insert(path_parts, v)
                    end
                end
                return table.concat(path_parts, ".")
            end
        }

        -- Helpers to setup environment state in tests
        function clearMocks()
            db_store = {}
            ActionHealthD20.calls = {}
            ActionDamage.calls = {}
            ActionHealthD20.apply = originalActionHealthApply
            ActionDamage.applyDamage = originalActionDamageApplyDamage
            ActionDamage.apply = originalActionDamageApplyDamage
            ActionsManager.outputs = {}
            ActionsManager.rolls = {}
            Comm.chat_messages = {}
            ModifierStack.wasReset = false
        end
    `);

    // Load the undeadfortitude.lua source
    console.log("Loading undeadfortitude.lua...");
    const scriptPath = path.join(__dirname, '../scripts/undeadfortitude.lua');
    const code = fs.readFileSync(scriptPath, 'utf8');
    await lua.doString(code);

    // List of test cases to run
    const testCases = [
        {
            name: "onInit registers save result handler and slash commands",
            code: `
                clearMocks()
                _USER_ISHOST = true
                onInit()
                
                assert(ActionsManager._handlers["save"] == onSaveNew, "onSaveNew not registered for save")
                assert(Comm._slash_handlers["uf"] == processChatCommand, "uf slash handler not registered")
                assert(Comm._slash_handlers["undeadfortitude"] == processChatCommand, "undeadfortitude slash handler not registered")
            `
        },
        {
            name: "getCTNodeForDisplayName finds actor by name",
            code: `
                clearMocks()
                local nodeCT = {
                    _name = "zombie",
                    _parent_path = "combattracker.list",
                    _path = "combattracker.list.id-00001",
                    _data = {
                        name = "Stinky Zombie"
                    }
                }
                db_store["combattracker.list.id-00001"] = nodeCT
                
                local found = getCTNodeForDisplayName("Stinky Zombie")
                assert(found == nodeCT, "Should find the correct CT node")
                
                local notFound = getCTNodeForDisplayName("Nonexistent")
                assert(notFound == nil, "Should return nil for nonexistent actor")
            `
        },
        {
            name: "processChatCommand triggers application or shows error",
            code: `
                clearMocks()
                -- Try with nonexistent actor
                processChatCommand(nil, "Ghost")
                assert(#Comm.chat_messages == 1, "Should have added a chat message")
                assert(string.find(Comm.chat_messages[1].text, "not found in the Combat Tracker"), "Should show not found error")
                
                -- Try with existing actor (not unconscious)
                local nodeCT = {
                    _name = "zombie",
                    _parent_path = "combattracker.list",
                    _path = "combattracker.list.id-00001",
                    _data = {
                        name = "Stinky Zombie"
                    },
                    _effects = {}
                }
                db_store["combattracker.list.id-00001"] = nodeCT
                
                Comm.chat_messages = {}
                processChatCommand(nil, "Stinky Zombie")
                assert(#Comm.chat_messages == 1, "Should have added a chat message")
                assert(string.find(Comm.chat_messages[1].text, "is not an unconscious actor"), "Should show unconscious error")
            `
        },
        {
            name: "applyUndeadFortitude applies healing to unconscious actor",
            code: `
                clearMocks()
                local nodeCT = {
                    _name = "zombie",
                    _parent_path = "combattracker.list",
                    _path = "combattracker.list.id-00001",
                    _data = {
                        name = "Stinky Zombie",
                        hptotal = 30,
                        hptemp = 0,
                        wounds = 30
                    },
                    _effects = {"Unconscious", "Prone"},
                    _isPC = false
                }
                db_store["combattracker.list.id-00001"] = nodeCT
                
                applyUndeadFortitude(nodeCT)
                
                -- Check wounds: total HP - 1 = 29
                assert(nodeCT._data.wounds == 29, "Wounds should be set to total HP - 1 (29), got " .. tostring(nodeCT._data.wounds))
                
                -- Check effects removed
                local hasUnconscious = false
                local hasProne = false
                for _, eff in ipairs(nodeCT._effects) do
                    if eff == "Unconscious" then hasUnconscious = true end
                    if eff == "Prone" then hasProne = true end
                end
                assert(not hasUnconscious, "Unconscious effect should be removed")
                assert(not hasProne, "Prone effect should be removed")
                
                -- Check success message
                assert(#Comm.chat_messages == 1, "Should display chat message")
                assert(string.find(Comm.chat_messages[1].text, "Fortitude was applied to Stinky Zombie"), "Should show success message")
            `
        },
        {
            name: "hasFortitudeTrait parses different trait variants",
            code: `
                clearMocks()
                
                local function checkTrait(traitName, expected)
                    local actor = {
                        _path = "combattracker.list.id-00001",
                        _children = {
                            traits = {
                                ["trait-1"] = {
                                    _data = {
                                        name = traitName
                                    }
                                }
                            }
                        },
                        _data = {
                            hptotal = 20,
                            hptemp = 0,
                            wounds = 10
                        }
                    }
                    
                    local res = hasFortitudeTrait("ct", actor, {})
                    if expected == nil then
                        assert(res == nil, "Expected no fortitude trait for: " .. traitName)
                    else
                        assert(res ~= nil, "Expected fortitude trait for: " .. traitName)
                        assert(res.bUndead == expected.bUndead, "bUndead mismatch for: " .. traitName)
                        assert(res.nStaticDC == expected.nStaticDC, "nStaticDC mismatch for: " .. traitName .. " (got " .. tostring(res.nStaticDC) .. ")")
                        assert(res.nModDC == expected.nModDC, "nModDC mismatch for: " .. traitName .. " (got " .. tostring(res.nModDC) .. ")")
                        assert(not not res.bNoMods == not not expected.bNoMods, "bNoMods mismatch for: " .. traitName)
                        assert(res.sTrimmedFortitudeTraitNameForSave == expected.sTrimmedFortitudeTraitNameForSave, "sTrimmedFortitudeTraitNameForSave mismatch for: " .. traitName)
                    end
                end
                
                checkTrait("Undead Fortitude", {
                    bUndead = true,
                    sTrimmedFortitudeTraitNameForSave = "Undead Fortitude"
                })
                
                checkTrait("Zombie Fortitude (DC 10)", {
                    bUndead = false,
                    nStaticDC = 10,
                    sTrimmedFortitudeTraitNameForSave = "Zombie Fortitude"
                })
                
                checkTrait("Fortitude (Mod 2, No Mods)", {
                    bUndead = false,
                    nModDC = 2,
                    bNoMods = true,
                    sTrimmedFortitudeTraitNameForSave = "Fortitude"
                })
                
                checkTrait("Toughness", nil)
            `
        },
        {
            name: "processFortitude trigger logic",
            code: `
                clearMocks()
                
                local actor = {
                    _name = "zombie",
                    _path = "combattracker.list.id-00001",
                    _data = {
                        name = "Zombie",
                        hptotal = 20,
                        hptemp = 0,
                        wounds = 10
                    },
                    _effects = {},
                    _con_save = { mod = 2 }
                }
                
                local traitData = {
                    nTotalHP = 20,
                    nTempHP = 0,
                    nWounds = 10,
                    bUndead = true,
                    sTrimmedFortitudeTraitNameForSave = "Undead Fortitude"
                }
                
                -- Case A: Damage not enough to drop to 0 HP
                local triggered = processFortitude(traitData, 5, "[DAMAGE] bludgeoning", nil, actor, false)
                assert(not triggered, "Should not trigger if damage does not reduce to 0 HP")
                
                -- Case B: Damage reduces to 0 HP, normal type. Should trigger con save.
                triggered = processFortitude(traitData, 10, "[DAMAGE] bludgeoning", nil, actor, false)
                assert(triggered, "Should trigger if damage reduces to 0 HP")
                assert(#ActionsManager.rolls == 1, "Should roll con save")
                assert(ActionsManager.rolls[1].rRoll.bUndeadFortitude == "true", "Roll should be flagged as Undead Fortitude")
                assert(ActionsManager.rolls[1].rRoll.nDamage == 10, "Roll should carry damage amount")
                
                -- Case C: Radiant damage on Undead. Should not trigger.
                ActionsManager.rolls = {}
                triggered = processFortitude(traitData, 10, "[DAMAGE] radiant [TYPE: radiant]", nil, actor, false)
                assert(not triggered, "Should not trigger on radiant damage for undead")
                
                -- Case D: Radiant damage on non-Undead. Should trigger.
                local nonUndeadTraitData = {
                    nTotalHP = 20,
                    nTempHP = 0,
                    nWounds = 10,
                    bUndead = false,
                    sTrimmedFortitudeTraitNameForSave = "Fortitude"
                }
                ActionsManager.rolls = {}
                triggered = processFortitude(nonUndeadTraitData, 10, "[DAMAGE] radiant [TYPE: radiant]", nil, actor, false)
                assert(triggered, "Should trigger on radiant damage for non-undead")
                
                -- Case E: Radiant damage on Undead with No Mods. Should trigger.
                local undeadNoModsTraitData = {
                    nTotalHP = 20,
                    nTempHP = 0,
                    nWounds = 10,
                    bUndead = true,
                    bNoMods = true,
                    sTrimmedFortitudeTraitNameForSave = "Undead Fortitude"
                }
                ActionsManager.rolls = {}
                triggered = processFortitude(undeadNoModsTraitData, 10, "[DAMAGE] radiant [TYPE: radiant]", nil, actor, false)
                assert(triggered, "Should trigger on radiant damage for undead with No Mods")
                
                -- Case F: Critical damage. Should not trigger.
                ActionsManager.rolls = {}
                triggered = processFortitude(traitData, 10, "[DAMAGE] [CRITICAL] bludgeoning", nil, actor, false)
                assert(not triggered, "Should not trigger on critical damage")
                
                -- Case G: Critical damage with No Mods. Should trigger.
                ActionsManager.rolls = {}
                triggered = processFortitude(undeadNoModsTraitData, 10, "[DAMAGE] [CRITICAL] bludgeoning", nil, actor, false)
                assert(triggered, "Should trigger on critical damage with No Mods")
                
                -- Case H: Target already unconscious. Should not trigger.
                table.insert(actor._effects, "Unconscious")
                ActionsManager.rolls = {}
                triggered = processFortitude(traitData, 10, "[DAMAGE] bludgeoning", nil, actor, false)
                assert(not triggered, "Should not trigger if target is already unconscious")
            `
        },
        {
            name: "onSaveNew save results",
            code: `
                clearMocks()
                
                local source = {
                    _name = "zombie",
                    _path = "combattracker.list.id-00001",
                    _data = { name = "Zombie" }
                }
                
                local roll = {
                    bUndeadFortitude = "true",
                    sTrimmedFortitudeTraitNameForSave = "Undead Fortitude",
                    nDamage = 10,
                    sDamage = "[DAMAGE] bludgeoning =10",
                    nTotalHP = 20,
                    nTempHP = 0,
                    nWounds = 10,
                    sModDC = "5",
                    sStaticDC = "nil",
                    nTotalOverride = 15 -- Save result is 15. DC is 5 + 10 = 15. Success!
                }
                
                -- Trigger onSaveNew with a Success
                onSaveNew(source, source, roll)
                
                -- Success should apply damage to leave exactly 1 HP.
                -- HP 20, Wounds 10 -> Damage needed is 9
                assert(#ActionHealthD20.calls == 1 or #ActionDamage.calls == 1, "Should apply damage")
                local appliedRoll = ActionHealthD20.calls[1] and ActionHealthD20.calls[1].rRoll or ActionDamage.calls[1].rRoll
                assert(appliedRoll.nTotal == 9, "Should apply 9 damage to leave 1 HP, got " .. tostring(appliedRoll.nTotal))
                assert(appliedRoll.sDesc == "[DAMAGE] bludgeoning =9", "Should adjust damage description, got " .. tostring(appliedRoll.sDesc))
                
                -- Verify output message contains SUCCESS
                assert(#ActionsManager.outputs == 1, "Should output result message")
                assert(string.find(ActionsManager.outputs[1].msgLong.text, "%[SUCCESS%]"), "Message should contain [SUCCESS]")
                
                -- Clear and test Failure
                clearMocks()
                roll.nTotalOverride = 14 -- DC is 15. Failure!
                onSaveNew(source, source, roll)
                
                -- Failure should apply original damage (10)
                assert(#ActionHealthD20.calls == 1 or #ActionDamage.calls == 1, "Should apply damage")
                local appliedRollFail = ActionHealthD20.calls[1] and ActionHealthD20.calls[1].rRoll or ActionDamage.calls[1].rRoll
                assert(appliedRollFail.nTotal == 10, "Should apply original 10 damage, got " .. tostring(appliedRollFail.nTotal))
                
                -- Verify output message contains FAILURE
                assert(#ActionsManager.outputs == 1, "Should output result message")
                assert(string.find(ActionsManager.outputs[1].msgLong.text, "%[FAILURE%]"), "Message should contain [FAILURE]")
            `
        },
        {
            name: "applyDamage_v2 intercept integration",
            code: `
                clearMocks()
                
                local source = {
                    _name = "orc",
                    _path = "combattracker.list.id-00002",
                    _data = { name = "Orc" }
                }
                
                local target = {
                    _name = "zombie",
                    _parent_path = "combattracker.list",
                    _path = "combattracker.list.id-00001",
                    _data = {
                        name = "Zombie",
                        hptotal = 20,
                        hptemp = 0,
                        wounds = 10
                    },
                    _effects = {},
                    _con_save = { mod = 2 },
                    _children = {
                        traits = {
                            ["trait-1"] = {
                                _data = {
                                    name = "Undead Fortitude"
                                }
                            }
                        }
                    }
                }
                db_store["combattracker.list.id-00001"] = target
                
                -- Initialize upvalues via onInit
                _USER_ISHOST = true
                onInit()

                -- Define the damage roll
                local rRoll = {
                    sDesc = "[DAMAGE] slashing",
                    nTotal = 10, -- reduces actor from 10 HP (20 total - 10 wounds) to 0 HP.
                    bSecret = false
                }
                
                -- Call applyDamage_v2 directly
                applyDamage_v2(source, target, rRoll)
                
                -- Fortitude should be triggered, so original damage is intercepted (not applied yet)
                assert(#ActionHealthD20.calls == 0 and #ActionDamage.calls == 0, "Damage should be intercepted")
                
                -- Con save should have been rolled
                assert(#ActionsManager.rolls == 1, "Con save should be rolled")
                local saveRoll = ActionsManager.rolls[1].rRoll
                assert(saveRoll.bUndeadFortitude == "true", "Roll should be undead fortitude")
                assert(saveRoll.nDamage == 10, "Damage should be 10")
                
                -- Now simulate the save result handler. Set save result to 18 (vs DC 5 + 10 = 15). Success!
                saveRoll.nTotalOverride = 18
                onSaveNew(source, target, saveRoll)
                
                -- Wounds applied should leave exactly 1 HP: HP 20, Wounds 10 -> Damage applied 9
                assert(#ActionHealthD20.calls == 1 or #ActionDamage.calls == 1, "Damage should be applied after save")
                local appliedRoll = ActionHealthD20.calls[1] and ActionHealthD20.calls[1].rRoll or ActionDamage.calls[1].rRoll
                assert(appliedRoll.nTotal == 9, "Should apply 9 damage, got " .. tostring(appliedRoll.nTotal))
            `
        }
    ];

    console.log(`Running ${testCases.length} tests...`);
    let passedCount = 0;
    let failedCount = 0;

    for (const tc of testCases) {
        try {
            await lua.doString(tc.code);
            console.log(`✔ [PASS] ${tc.name}`);
            passedCount++;
        } catch (err) {
            console.error(`✘ [FAIL] ${tc.name}`);
            console.error(`  Error: ${err.message}`);
            failedCount++;
        }
    }

    // Clean up
    lua.global.close();

    console.log("\n=== Test Summary ===");
    console.log(`Total:  ${testCases.length}`);
    console.log(`Passed: ${passedCount}`);
    console.log(`Failed: ${failedCount}`);

    if (failedCount > 0) {
        console.error("\nTests failed!");
        process.exit(1);
    } else {
        console.log("\nAll tests passed successfully!");
        process.exit(0);
    }
}

runTests().catch(err => {
    console.error("Unhandle rejection / error during tests:", err);
    process.exit(1);
});
