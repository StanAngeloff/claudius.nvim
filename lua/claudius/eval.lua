--- Safe environment and execution for Lua code in Claudius, where safe is a loose term.
local M = {}

-- Create a safe environment for executing Lua code
function M.create_safe_env()
  return {
    -- String manipulation
    string = {
      byte = string.byte,
      char = string.char,
      find = string.find,
      format = string.format,
      gmatch = string.gmatch,
      gsub = string.gsub,
      len = string.len,
      lower = string.lower,
      match = string.match,
      rep = string.rep,
      reverse = string.reverse,
      sub = string.sub,
      upper = string.upper,
    },

    -- Table operations for data structuring
    table = {
      concat = table.concat,
      insert = table.insert,
      remove = table.remove,
      sort = table.sort,
      unpack = table.unpack,
    },

    -- Math for calculations in templates
    math = {
      abs = math.abs,
      ceil = math.ceil,
      floor = math.floor,
      max = math.max,
      min = math.min,
      random = math.random,
      randomseed = math.randomseed,
      round = math.floor, -- common alias
      pi = math.pi,
    },

    -- UTF-8 support for unicode string handling
    utf8 = utf8,

    -- Essential functions for template operation
    assert = assert,
    error = error,
    ipairs = ipairs,
    pairs = pairs,
    select = select,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    print = print,

    -- Useful constants
    _VERSION = _VERSION,
  }
end

-- Execute code in a safe environment
function M.execute_safe(code, env)
  -- Create environment and store initial keys
  env = env or M.create_safe_env()
  local initial_keys = {}
  for k in pairs(env) do
    initial_keys[k] = true
  end

  local chunk, err = load(code, "safe_env", "t", env)
  if not chunk then
    error("Claudius: Failed to load code: " .. err)
  end

  local ok, err = pcall(chunk)
  if not ok then
    error("Claudius: Failed to execute code: " .. err)
  end

  -- Collect only new keys that weren't in initial environment
  local globals = {}
  for k, v in pairs(env) do
    if not initial_keys[k] then
      globals[k] = v
    end
  end

  return globals
end

-- Evaluate an expression in a given environment
function M.eval_expression(expr, env)
  -- Wrap expression in return statement if it's not already a statement
  if not expr:match("^%s*return%s+") then
    expr = "return " .. expr
  end

  local chunk, err = load(expr, "expression", "t", env)
  if not chunk then
    error("Claudius: Failed to parse expression: " .. err)
  end

  local ok, result = pcall(chunk)
  if not ok then
    error("Claudius: Failed to evaluate expression: " .. result)
  end

  return result
end

return M
