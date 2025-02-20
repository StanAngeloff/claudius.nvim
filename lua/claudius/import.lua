local M = {}

-- Helper function to convert JS object notation to valid JSON
local function prepare_json(content)
  local lines = {}
  -- Process each line individually
  for line in content:gmatch("[^\r\n]+") do
    -- Only look for unquoted property names at the start of the line
    line = line:gsub("^%s*([%w_%.-]+)%s*:", function(prop)
      return string.format('"%s":', prop)
    end)
    lines[#lines + 1] = line
  end

  -- Join lines back together with spaces
  return table.concat(lines, " ")
end

-- Extract content between create() call
local function extract_content(lines)
  local content = {}
  local capturing = false

  for _, line in ipairs(lines) do
    if line:match("anthropic%.messages%.create%(") then
      capturing = true
      -- Get everything after the opening parenthesis
      local after_paren = line:match("%((.*)$")
      if after_paren then
        content[#content + 1] = after_paren
      end
    elseif capturing then
      if line:match("^%s*%}%)%s*;%s*$") then
        -- Last line - only take the closing brace
        content[#content + 1] = "}"
        break
      else
        content[#content + 1] = line
      end
    end
  end

  return table.concat(content, "\n")
end

-- Convert message content to text
local function get_message_text(content)
  if type(content) == "string" then
    return content
  elseif type(content) == "table" then
    if content[1] and content[1].type == "text" then
      return content[1].text
    end
  end
  return ""
end

-- Generate chat file content
local function generate_chat(data)
  local output = {}

  -- Add system message if present
  if data.system then
    table.insert(output, "@System: " .. data.system)
    table.insert(output, "")
  end

  -- Process messages
  for _, msg in ipairs(data.messages or {}) do
    local prefix = msg.role == "user" and "@You: " or "@Assistant: "
    local text = get_message_text(msg.content)

    -- Add blank line before message if needed
    if #output > 0 and output[#output] ~= "" then
      table.insert(output, "")
    end

    table.insert(output, prefix .. text)
  end

  return table.concat(output, "\n")
end

-- Main import function
function M.import_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  -- Extract and prepare content
  local content = extract_content(lines)
  if #content == 0 then
    vim.notify("No Claude API call found in buffer", vim.log.levels.ERROR)
    return
  end

  local json_str = prepare_json(content)

  -- Parse JSON with better error handling
  local ok, data = pcall(vim.fn.json_decode, json_str)
  if not ok then
    -- Log the problematic JSON string for debugging
    -- Get temp dir and path separator
    local tmp_path = os.tmpname()
    local tmp_dir = tmp_path:match("^(.+)[/\\]")
    local sep = tmp_path:match("[/\\]")
    local debug_file = io.open(tmp_dir .. sep .. "claudius_import_debug.log", "w")
    if debug_file then
      debug_file:write("Original content:\n")
      debug_file:write(content .. "\n\n")
      debug_file:write("Prepared JSON:\n")
      debug_file:write(json_str .. "\n")
      debug_file:close()
    end

    vim.notify(
      "Failed to parse API call data. Debug info written to " .. os.tmpname():match("^(.+)[/\\]") .. os.tmpname():match("[/\\]") .. "claudius_import_debug.log",
      vim.log.levels.ERROR
    )
    return
  end

  -- Generate chat content
  local chat_content = generate_chat(data)

  -- Replace buffer contents
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(chat_content, "\n", {}))

  -- Set filetype to chat
  vim.bo[bufnr].filetype = "chat"
end

return M
