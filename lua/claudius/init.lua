local M = {}
local ns_id = vim.api.nvim_create_namespace('claudius')

-- Utility functions for JSON encoding/decoding
local function json_decode(str)
  return vim.fn.json_decode(str)
end

local function json_encode(data)
  return vim.fn.json_encode(data)
end

-- Track ongoing requests
M.current_request = nil

-- Folding functions
function M.get_fold_level(lnum)
  local line = vim.fn.getline(lnum)
  local last_line = vim.fn.line('$')

  -- If line starts with @, it's the start of a fold
  if line:match("^@[%w]+:") then
    return ">1"
  end

  -- If next line starts with @ or this is the last line, this is the end of the current fold
  local next_line = vim.fn.getline(lnum + 1)
  if next_line:match("^@[%w]+:") or lnum == last_line then
    return "<1"
  end

  -- Otherwise, we're inside a fold
  return "1"
end

function M.get_fold_text()
  local foldstart = vim.v.foldstart
  local line = vim.fn.getline(foldstart)
  local lines_count = vim.v.foldend - vim.v.foldstart + 1

  -- Extract the prefix (@You:, @Assistant:, etc.)
  local prefix = line:match("^(@[%w]+:)")
  if not prefix then
    return line
  end

  -- Get the first line of content (excluding the prefix)
  local content = line:sub(#prefix + 1):gsub("^%s*", "")

  -- Create fold text: prefix + first line + number of lines
  return string.format("%s %s... (%d lines)", prefix, content:sub(1, 50), lines_count)
end

-- Message types
local MSG_TYPE = {
  SYSTEM = "System",
  USER = "You",
  ASSISTANT = "Assistant"
}

-- Default configuration
local default_config = {
  highlights = {
    system = "Special",
    user = "Normal",
    assistant = "Comment"
  },
  prefix_style = "bold,underline",
  ruler = {
    char = "─",  -- The character to use for the ruler
    style = "FoldColumn"  -- Highlight group for the ruler
  }
}

-- Helper function to add rulers
local function add_rulers(bufnr)
  -- Clear existing extmarks
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Get buffer lines
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^@[%w]+:") then
      -- If this isn't the first line, add a ruler before it
      if i > 1 then
        -- Create virtual line with ruler
        local ruler_text = string.rep(default_config.ruler.char, math.floor(vim.api.nvim_win_get_width(0) * 1))
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, i-1, 0, {
          virt_lines = {{{ruler_text, default_config.ruler.style}}},
          virt_lines_above = true,
        })
      end
    end
  end
end

-- Setup function to initialize the plugin
M.setup = function(opts)
  -- Merge user config with defaults
  opts = opts or {}
  local config = vim.tbl_deep_extend("force", default_config, opts)

  -- Create filetype detection for .chat files
  vim.filetype.add({
    extension = {
      chat = "chat"
    },
    pattern = {
      [".*%.chat"] = "chat"
    }
  })

  -- Define syntax highlighting
  local function set_syntax()
    -- Clear existing syntax
    vim.cmd("syntax clear")

    -- Define syntax regions and matches
    vim.cmd([[
      " Define the prefix matches first
      syntax match ChatSystemPrefix '^@System:' contained
      syntax match ChatUserPrefix '^@You:' contained
      syntax match ChatAssistantPrefix '^@Assistant:' contained

      " Define the regions that contain the prefixes
      syntax region ChatSystem start='^@System:' end='\(^@\(You\|Assistant\):\)\@=\|\%$' contains=ChatSystemPrefix
      syntax region ChatUser start='^@You:' end='\(^@\(System\|Assistant\):\)\@=\|\%$' contains=ChatUserPrefix
      syntax region ChatAssistant start='^@Assistant:' end='\(^@\(System\|You\):\)\@=\|\%$' contains=ChatAssistantPrefix
    ]])

    -- Link main highlights to user config
    vim.cmd(string.format("highlight link ChatSystem %s", config.highlights.system))
    vim.cmd(string.format("highlight link ChatUser %s", config.highlights.user))
    vim.cmd(string.format("highlight link ChatAssistant %s", config.highlights.assistant))

    -- Set up prefix highlights to inherit colors but add custom style
    vim.cmd(string.format([[
      execute 'highlight ChatSystemPrefix guifg=' . synIDattr(synIDtrans(hlID("ChatSystem")), "fg", "gui") . ' gui=%s'
      execute 'highlight ChatUserPrefix guifg=' . synIDattr(synIDtrans(hlID("ChatUser")), "fg", "gui") . ' gui=%s'
      execute 'highlight ChatAssistantPrefix guifg=' . synIDattr(synIDtrans(hlID("ChatAssistant")), "fg", "gui") . ' gui=%s'
    ]], config.prefix_style, config.prefix_style, config.prefix_style))
  end

  -- Set up folding expression
  local function setup_folding()
    vim.wo.foldmethod = 'expr'
    vim.wo.foldexpr = 'v:lua.require("claudius").get_fold_level(v:lnum)'
    vim.wo.foldtext = 'v:lua.require("claudius").get_fold_text()'
    -- Start with all folds open
    vim.wo.foldlevel = 99
  end

  -- Add autocmd for updating rulers
  vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter", "VimResized", "TextChanged", "TextChangedI"}, {
    pattern = "*.chat",
    callback = function(ev)
      add_rulers(ev.buf)
    end
  })

  -- Set up autocmd for the chat filetype
  vim.api.nvim_create_autocmd({"BufEnter", "BufWinEnter"}, {
    pattern = "*.chat",
    callback = function(ev)
      set_syntax()
      add_rulers(ev.buf)
    end
  })

  -- Create the filetype detection
  vim.api.nvim_create_autocmd({"BufRead", "BufNewFile"}, {
    pattern = "*.chat",
    callback = function()
      vim.bo.filetype = "chat"
      setup_folding()
    end
  })

  -- Set up the mappings for Claude interaction
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "chat",
    callback = function()
      vim.keymap.set("n", "<C-]>", M.send_to_claude, { buffer = true, desc = "Send to Claude" })
      vim.keymap.set("n", "<C-c>", M.cancel_request, { buffer = true, desc = "Cancel Claude Request" })
    end
  })
end

-- Parse a single message from lines
local function parse_message(lines, start_idx)
  local line = lines[start_idx]
  local msg_type = line:match("^@([%w]+):")
  if not msg_type then
    return nil, start_idx
  end

  local content = {}
  local i = start_idx
  -- Remove the prefix from first line
  local first_content = line:sub(#msg_type + 3)
  if first_content:match("%S") then
    content[#content + 1] = first_content:gsub("^%s*", "")
  end
  
  i = i + 1
  -- Collect lines until we hit another prefix or end of buffer
  while i <= #lines do
    local next_line = lines[i]
    if next_line:match("^@[%w]+:") then
      break
    end
    if next_line:match("%S") or #content > 0 then
      content[#content + 1] = next_line
    end
    i = i + 1
  end

  return {
    type = msg_type,
    content = table.concat(content, "\n")
  }, i - 1
end

-- Parse the entire buffer into a sequence of messages
function M.parse_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local messages = {}
  local i = 1

  while i <= #lines do
    local msg, last_idx = parse_message(lines, i)
    if msg then
      messages[#messages + 1] = msg
      i = last_idx + 1
    else
      i = i + 1
    end
  end

  return messages
end

-- Format messages for Claude API
local function format_messages(messages)
  local formatted = {}
  local system_message = nil
  
  for _, msg in ipairs(messages) do
    if msg.type == MSG_TYPE.SYSTEM then
      system_message = msg.content
    else
      local role = msg.type == MSG_TYPE.USER and "user"
        or msg.type == MSG_TYPE.ASSISTANT and "assistant"
        or nil
      
      if role then
        table.insert(formatted, {
          role = role,
          content = msg.content
        })
      end
    end
  end
  
  return formatted, system_message
end

-- Append assistant response to buffer
local function append_response(response)
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  
  -- Add a newline if the last line isn't empty
  if #lines > 0 and lines[#lines]:match("%S") then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, {""})
  end
  
  -- Add the assistant response
  local response_lines = {"@Assistant: " .. response}
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, response_lines)
end

-- Cancel ongoing request if any
function M.cancel_request()
  if M.current_request then
    M.current_request:shutdown()
    M.current_request = nil
    vim.notify("Claude request cancelled", vim.log.levels.INFO)
  end
end

-- Show loading spinner
local function start_loading_spinner()
  local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = 1
  local bufnr = vim.api.nvim_get_current_buf()
  
  -- Clear any existing virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  
  -- Create loading line at the end of buffer
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, {"@Assistant: Thinking..."})
  
  return vim.fn.timer_start(100, function()
    if not M.current_request then
      return
    end
    frame = (frame % #spinner_frames) + 1
    local text = "@Assistant: " .. spinner_frames[frame] .. " Thinking..."
    local last_line = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, {text})
  end, {["repeat"] = -1})
end

-- Clean up spinner and prepare for response
local function cleanup_spinner(bufnr)
  -- Stop any existing rulers/virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  
  -- Remove the "Thinking..." line
  local last_line = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, {})
end

-- Handle the Claude interaction
function M.send_to_claude()
  -- Cancel any ongoing request
  M.cancel_request()

  local api_key = os.getenv("ANTHROPIC_API_KEY")
  if not api_key then
    vim.notify("ANTHROPIC_API_KEY environment variable not set", vim.log.levels.ERROR)
    return
  end

  local messages = M.parse_buffer()
  if #messages == 0 then
    vim.notify("No messages found in buffer", vim.log.levels.WARN)
    return
  end

  local formatted_messages, system_message = format_messages(messages)
  local request_body = {
    model = "claude-3-opus-20240229",
    messages = formatted_messages,
    system = system_message,
    stream = true
  }

  local spinner_timer = start_loading_spinner()
  local response_started = false
  local function handle_response_line(line)
    -- Debug: Log raw line
    vim.schedule(function()
      vim.notify("Raw line: " .. vim.inspect(line), vim.log.levels.DEBUG)
    end)
    
    if not line:match("^data: ") then 
      vim.schedule(function()
        vim.notify("Skipping non-data line", vim.log.levels.DEBUG)
      end)
      return 
    end
    
    local json_str = line:gsub("^data: ", "")
    if json_str == "[DONE]" then
      vim.schedule(function()
        vim.notify("Received [DONE] event", vim.log.levels.DEBUG)
        vim.fn.timer_stop(spinner_timer)
        M.current_request = nil
      end)
      return
    end

    -- Debug: Log JSON string
    vim.schedule(function()
      vim.notify("JSON string: " .. json_str, vim.log.levels.DEBUG)
    end)

    local ok, data = pcall(json_decode, json_str)
    if not ok then
      vim.schedule(function()
        vim.notify("Failed to parse JSON: " .. json_str, vim.log.levels.ERROR)
      end)
      return
    end

    -- Debug: Log parsed data
    vim.schedule(function()
      vim.notify("Parsed data: " .. vim.inspect(data), vim.log.levels.DEBUG)
    end)

    if data.type == "content_block_delta" and data.delta and data.delta.text then
      vim.schedule(function()
        local bufnr = vim.api.nvim_get_current_buf()
        
        -- Stop spinner on first content
        if not response_started then
          vim.fn.timer_stop(spinner_timer)
          response_started = true
          cleanup_spinner(bufnr)
        end
        
        -- Split content into lines
        local lines = vim.split(data.delta.text, "\n", { plain = true })
        
        if #lines > 0 then
          local last_line = vim.api.nvim_buf_line_count(bufnr)
          
          -- Handle first response line
          if not response_started then
            lines[1] = "@Assistant: " .. lines[1]
            vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, lines)
          else
            -- Append to existing response
            vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, lines)
          end
          
          -- Update response_started after handling first line
          response_started = true
        end
      end)
    end
  end

  -- Prepare curl command
  local cmd = {
    'curl',
    '-N',  -- disable buffering
    '-s',  -- silent mode
    '-H', 'x-api-key: ' .. api_key,
    '-H', 'anthropic-version: 2023-06-01',
    '-H', 'content-type: application/json',
    '-d', json_encode(request_body),
    'https://api.anthropic.com/v1/messages'
  }

  -- Start job
  M.current_request = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      vim.schedule(function()
        vim.notify("Received stdout chunk: " .. vim.inspect(data), vim.log.levels.DEBUG)
      end)
      if data then
        for _, line in ipairs(data) do
          if line and #line > 0 then
            handle_response_line(line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.schedule(function()
          vim.notify("Stderr: " .. vim.inspect(data), vim.log.levels.ERROR)
        end)
      end
    end,
    on_exit = function()
      vim.schedule(function()
        M.current_request = nil
        vim.fn.timer_stop(spinner_timer)
      end)
    end
  })
end

return M
