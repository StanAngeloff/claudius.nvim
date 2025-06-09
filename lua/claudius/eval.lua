--- Safe environment and execution for Lua code in Claudius, where safe is a loose term.
local M = {}

local function include_delegate(relative_path, env_of_caller, eval_expression_func, create_safe_env_func)
  if not env_of_caller.__filename then
    error("include() called but __filename is not set in the calling environment.")
  end
  if not env_of_caller.__include_stack then
    error("include() called but __include_stack is not set in the calling environment.")
  end

  local calling_file_path = env_of_caller.__filename
  local base_dir
  -- Check if the path is absolute by comparing it with its absolute version
  if vim.fs.abspath(calling_file_path) == calling_file_path then
    base_dir = vim.fn.fnamemodify(calling_file_path, ":h")
  else
    local dir_of_calling_file = vim.fn.fnamemodify(calling_file_path, ":h") -- Returns '.' if no path part, or the path part
    if dir_of_calling_file == "" or dir_of_calling_file == "." then
      base_dir = vim.fn.getcwd()
    else
      base_dir = vim.fs.normalize(vim.fn.getcwd() .. "/" .. dir_of_calling_file)
    end
  end

  local target_path = vim.fs.normalize(base_dir .. "/" .. relative_path)

  for _, path_in_stack in ipairs(env_of_caller.__include_stack) do
    if path_in_stack == target_path then
      error(
        "Circular include detected: '"
          .. target_path
          .. "'. Include stack: "
          .. table.concat(env_of_caller.__include_stack, " -> ")
      )
    end
  end

  local file, err_msg = io.open(target_path, "r")
  if not file then
    error("Failed to open include file '" .. target_path .. "': " .. (err_msg or "unknown error"))
  end
  local content = file:read("*a")
  file:close()

  local new_include_env = create_safe_env_func() -- Create a fresh base environment
  new_include_env.__filename = target_path
  new_include_env.__include_stack = vim.deepcopy(env_of_caller.__include_stack)
  table.insert(new_include_env.__include_stack, target_path)

  -- Expressions in the included file will be evaluated using new_include_env.
  -- M.eval_expression will ensure new_include_env.include is set up correctly for further nesting.
  local processed_content = content:gsub("{{(.-)}}", function(expr)
    return eval_expression_func(expr, new_include_env)
  end)

  return processed_content
end

local function ensure_include_capability(env, eval_expr_fn, create_env_fn)
  if env.include == nil then
    -- The 'include' function captures the 'env' it's defined in.
    env.include = function(relative_path)
      -- It's crucial that eval_expr_fn and create_env_fn are M.eval_expression and M.create_safe_env
      return include_delegate(relative_path, env, eval_expr_fn, create_env_fn)
    end
  end
end

-- Create a safe environment for executing Lua code
function M.create_safe_env()
  -- Note: The 'include' function is not added here directly.
  -- It will be added by ensure_include_capability, allowing it to capture the correct 'env'.
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

    -- Neovim API functions required by include()
    vim = {
      fn = {
        fnamemodify = vim.fn.fnamemodify,
        getcwd = vim.fn.getcwd,
      },
      fs = {
        normalize = vim.fs.normalize,
        abspath = vim.fs.abspath,
      },
    },

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
function M.execute_safe(code, env_param)
  -- Create environment and store initial keys
  local env = env_param or M.create_safe_env() -- Use provided env or create a new one

  -- Ensure 'include' is available and correctly contextualized for this environment.
  -- M.eval_expression and M.create_safe_env are used for recursive calls from 'include'.
  ensure_include_capability(env, M.eval_expression, M.create_safe_env)

  local initial_keys = {}
  for k in pairs(env) do
    initial_keys[k] = true
  end

  local chunk, load_err = load(code, "safe_env", "t", env)
  if not chunk then
    error("Failed to load code: " .. load_err)
  end

  local ok, exec_err = pcall(chunk)
  if not ok then
    error("Failed to execute code: " .. exec_err)
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
  -- Ensure 'env' is not nil, though callers should guarantee this.
  if not env then
    error("eval.eval_expression called with a nil environment.")
  end

  -- Ensure 'include' is available and correctly contextualized for this environment.
  ensure_include_capability(env, M.eval_expression, M.create_safe_env)

  -- Wrap expression in return statement if it's not already a statement
  if not expr:match("^%s*return%s+") then
    expr = "return " .. expr
  end

  local chunk, parse_err = load(expr, "expression", "t", env)
  if not chunk then
    error("Failed to parse expression: " .. parse_err)
  end

  local ok, eval_result = pcall(chunk)
  if not ok then
    error("Failed to evaluate expression: " .. eval_result)
  end

  return eval_result
end

return M
