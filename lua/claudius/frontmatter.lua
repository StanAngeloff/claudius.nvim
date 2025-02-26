--- Frontmatter handling for Claudius chat files
local M = {}

-- Safe environment for executing Lua frontmatter
local function create_safe_env()
  return {
    -- Standard library modules
    string = string,
    table = table,
    math = math,
    -- Basic functions
    assert = assert,
    error = error,
    ipairs = ipairs,
    next = next,
    pairs = pairs,
    pcall = pcall,
    select = select,
    tonumber = tonumber,
    tostring = tostring,
    type = type,
    unpack = unpack,
    -- String conversion
    print = print,
  }
end

-- Parse frontmatter from lines
function M.parse(lines)
  if not lines[1] or not lines[1]:match("^%-%-%-lua%s*$") then
    return nil, lines
  end

  local frontmatter = {}
  local content = {}
  local in_frontmatter = true
  local start_idx = 2

  for i = 2, #lines do
    if lines[i]:match("^%-%-%-") then
      in_frontmatter = false
      start_idx = i + 1
      break
    end
    table.insert(frontmatter, lines[i])
  end

  -- If we never found the closing ---, treat everything as content
  if in_frontmatter then
    return nil, lines
  end

  -- Collect remaining lines as content
  for i = start_idx, #lines do
    table.insert(content, lines[i])
  end

  return table.concat(frontmatter, "\n"), content
end

-- Execute frontmatter code in a safe environment
function M.execute(code)
  if not code then
    return {}
  end

  -- Create environment and store initial keys
  local env = create_safe_env()
  local initial_keys = {}
  for k in pairs(env) do
    initial_keys[k] = true
  end

  local chunk, err = load(code, "frontmatter", "t", env)

  if not chunk then
    error("Failed to load frontmatter: " .. err)
  end

  local ok, err = pcall(chunk)
  if not ok then
    error("Failed to execute frontmatter: " .. err)
  end

  -- Collect only new keys that weren't in initial environment
  local globals = {}
  for k, v in pairs(env) do
    if not initial_keys[k] then
      globals[k] = v
    end
  end

  -- Print globals for debugging
  print("Frontmatter globals:", vim.inspect(globals))

  return globals
end

return M
