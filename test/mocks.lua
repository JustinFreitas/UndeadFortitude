-- MOCKS START
DB_DATA = {}
ACTORS = {}
ACTIVE_EFFECTS = {}
REMOVED_EFFECTS = {}
REG_HANDLERS = {}
ROLL_REQUESTS = {}
OUTPUT_RESULTS = {}
SLASH_HANDLERS = {}
CHAT_MESSAGES = {}
MODIFIER_STACK_RESETS = 0
ORIGINAL_DAMAGE_CALLS = {}

MOCK_IS_HOST = true
MOCK_SAVE_RESULT = {
  nMod = 0,
  bADV = false,
  bDIS = false,
  sAddText = ""
}

User = {
  isHost = function()
    return MOCK_IS_HOST
  end
}

DB = {
  getChildren = function(node, path)
    local fullPath = node
    if path then
      fullPath = node .. "." .. path
    end
    local children = {}
    -- Escape Lua pattern special characters
    local escapedPath = fullPath:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local pattern = "^" .. escapedPath .. "%.([^%.]+)"
    for k, v in pairs(DB_DATA) do
      local match = k:match(pattern)
      if match then
        children[match] = fullPath .. "." .. match
      end
    end
    return children
  end,
  getValue = function(node, path, default)
    local fullPath = node
    if type(path) == "string" then
      fullPath = node .. "." .. path
    elseif type(path) == "number" then
      -- path is actually default value, i.e., DB.getValue(node, default)
      default = path
    end
    if DB_DATA[fullPath] ~= nil then
      return DB_DATA[fullPath]
    end
    return default
  end,
  setValue = function(node, path, typeStr, value)
    local fullPath = node
    if value == nil then
      -- Called as DB.setValue(node, typeStr, value)
      value = typeStr
      typeStr = path
    else
      fullPath = node .. "." .. path
    end
    DB_DATA[fullPath] = value
  end,
  getText = function(node, path)
    local fullPath = node
    if path then
      fullPath = node .. "." .. path
    end
    return tostring(DB_DATA[fullPath] or "")
  end
}

local function resolveNode(v)
  if type(v) == "string" then
    return v
  elseif type(v) == "table" then
    return v.node or v.nodeCT
  end
  return nil
end

ActorManager = {
  getActor = function(v)
    if type(v) == "table" then
      return v
    elseif type(v) == "string" then
      return ACTORS[v]
    end
    return nil
  end,
  resolveActor = function(v)
    if type(v) == "table" then
      return v
    elseif type(v) == "string" then
      return ACTORS[v]
    end
    return nil
  end,
  isPC = function(v)
    local node = resolveNode(v)
    if node then
      return node:match("^charselect%.") ~= nil
    end
    if type(v) == "table" then
      return v.sType == "pc"
    end
    return false
  end,
  getCreatureNode = function(v)
    return resolveNode(v)
  end,
  getCTNode = function(v)
    return resolveNode(v)
  end,
  getTypeAndNode = function(v)
    local sType = "ct"
    if ActorManager.isPC(v) then
      sType = "pc"
    end
    return sType, resolveNode(v)
  end,
  getActorTypeAndNode = function(v)
    local sType = "ct"
    if ActorManager.isPC(v) then
      sType = "pc"
    end
    return sType, resolveNode(v)
  end,
  getDisplayName = function(v)
    if type(v) == "table" then
      if v.sName then return v.sName end
      local node = v.node or v.nodeCT
      if node then return DB.getValue(node, "name", "") end
    elseif type(v) == "string" then
      return DB.getValue(v, "name", "")
    end
    return ""
  end,
  getCreatureNodeName = function(v)
    return resolveNode(v)
  end
}

EffectManager = {
  hasEffect = function(rActor, sEffect, rTarget, bTargetedOnly)
    local actorKey = resolveNode(rActor)
    if not actorKey then return false end
    if not ACTIVE_EFFECTS[actorKey] then return false end
    for _, eff in ipairs(ACTIVE_EFFECTS[actorKey]) do
      if eff == sEffect then return true end
    end
    return false
  end,
  removeEffect = function(nodeCT, sEffect)
    local actorKey = resolveNode(nodeCT)
    if not actorKey then return end
    table.insert(REMOVED_EFFECTS, { actor = actorKey, effect = sEffect })
    if ACTIVE_EFFECTS[actorKey] then
      for i, eff in ipairs(ACTIVE_EFFECTS[actorKey]) do
        if eff == sEffect then
          table.remove(ACTIVE_EFFECTS[actorKey], i)
          break
        end
      end
    end
  end
}

EffectManager5E = {
  hasEffect = EffectManager.hasEffect
}

ActorManager5E = {
  getSave = function(nodeActor, sSave)
    return MOCK_SAVE_RESULT.nMod, MOCK_SAVE_RESULT.bADV, MOCK_SAVE_RESULT.bDIS, MOCK_SAVE_RESULT.sAddText
  end
}

ActionsManager = {
  getResultHandler = function(sType)
    return REG_HANDLERS[sType]
  end,
  registerResultHandler = function(sType, handler)
    REG_HANDLERS[sType] = handler
  end,
  total = function(rRoll)
    if rRoll.nTotal then return rRoll.nTotal end
    local sum = rRoll.nMod or 0
    if rRoll.aDice then
      for _, d in ipairs(rRoll.aDice) do
        if type(d) == "table" and d.result then
          sum = sum + d.result
        elseif type(d) == "number" then
          sum = sum + d
        end
      end
    end
    return sum
  end,
  outputResult = function(bSecret, rSource, rTarget, msgLong, msgShort)
    table.insert(OUTPUT_RESULTS, {
      bSecret = bSecret,
      rSource = rSource,
      rTarget = rTarget,
      msgLong = msgLong,
      msgShort = msgShort
    })
  end,
  applyModifiersAndRoll = function(rSource, rTarget, bSecret, rRoll)
    table.insert(ROLL_REQUESTS, {
      rSource = rSource,
      rTarget = rTarget,
      bSecret = bSecret,
      rRoll = rRoll
    })
  end
}

Comm = {
  registerSlashHandler = function(cmd, handler)
    SLASH_HANDLERS[cmd] = handler
  end,
  addChatMessage = function(msg)
    table.insert(CHAT_MESSAGES, msg)
  end
}

CombatManager = {
  CT_LIST = "combattracker.list"
}

ActionD20 = {
  decodeAdvantage = function(rRoll) end
}

ActionsManager2 = {
  decodeAdvantage = function(rRoll) end
}

ModifierStack = {
  reset = function()
    MODIFIER_STACK_RESETS = MODIFIER_STACK_RESETS + 1
  end
}

ActionDamage = {
  applyDamage = function(rSource, rTarget, bSecret, sDamage, nTotal)
    table.insert(ORIGINAL_DAMAGE_CALLS, {
      rSource = rSource,
      rTarget = rTarget,
      bSecret = bSecret,
      sDamage = sDamage,
      nTotal = nTotal
    })
  end
}

StringManager = {
  isBlank = function(s)
    if type(s) ~= "string" then
      return false
    end
    return (string.gsub(s, "%s+", "") == "")
  end
}
-- MOCKS END
