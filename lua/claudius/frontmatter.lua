--- Frontmatter handling for Claudius chat files
local M = {}

local eval = require("claudius.eval")

-- Parse frontmatter from lines
function M.parse(lines)
  if not lines[1] or not lines[1]:match("^```lua%s*$") then
    return nil, lines
  end

  local frontmatter = {}
  local content = {}
  local in_frontmatter = true
  local start_idx = 2

  for i = 2, #lines do
    if lines[i]:match("^```%s*$") then
      in_frontmatter = false
      start_idx = i + 1
      break
    end
    table.insert(frontmatter, lines[i])
  end

  -- If we never found the closing ```, treat everything as content
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
function M.execute(code, chat_file_path)
  if not code then
    return {}
  end

  -- Create a base environment for frontmatter execution
  local env_for_frontmatter = eval.create_safe_env()

  -- Set __filename and __include_stack if chat_file_path is provided,
  -- enabling include() usage within frontmatter.
  if chat_file_path and chat_file_path ~= "" then
    env_for_frontmatter.__filename = chat_file_path
    env_for_frontmatter.__include_stack = { chat_file_path }
  else
    -- If chat_file_path is not available, include() will error if called from frontmatter,
    -- as __filename would be nil. This is acceptable as include() primarily makes sense with a file context.
  end

  return eval.execute_safe(code, env_for_frontmatter)
end

return M
