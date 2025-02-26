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
function M.execute(code)
  if not code then
    return {}
  end

  return eval.execute_safe(code)
end

return M
