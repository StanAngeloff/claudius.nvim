--- Claudius plugin core functionality
--- Provides chat interface and API integration
local M = {}
local ns_id = vim.api.nvim_create_namespace("claudius")
local log = require("claudius.logging")
local buffers = require("claudius.buffers")
local provider = nil

-- Execute a command in the context of a specific buffer
function M.buffer_cmd(bufnr, cmd)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    -- If buffer has no window, do nothing
    return
  end
  vim.fn.win_execute(winid, "noautocmd " .. cmd)
end

-- Session-wide usage tracking
local session_usage = {
  input_tokens = 0,
  output_tokens = 0,
}

-- Utility functions for JSON encoding/decoding
local function json_decode(str)
  return vim.fn.json_decode(str)
end

local function json_encode(data)
  return vim.fn.json_encode(data)
end

-- Folding functions
function M.get_fold_level(lnum)
  local line = vim.fn.getline(lnum)
  local last_line = vim.fn.line("$")

  -- If line starts with @, it's the start of a fold
  if line:match("^@[%w]+:") then
    return ">1" -- vim: foldlevel string
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
  ASSISTANT = "Assistant",
}

-- Message selection and navigation functions
local textobject = require("claudius.textobject")

-- Navigation functions
local function find_next_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, cur_line, -1, false)

  for i, line in ipairs(lines) do
    if line:match("^@[%w]+:") then
      -- Get the line and find position after the colon and whitespace
      local full_line = vim.api.nvim_buf_get_lines(0, cur_line + i - 1, cur_line + i, false)[1]
      local col = full_line:find(":%s*") + 1 -- Find position after the colon
      while full_line:sub(col, col) == " " do -- Skip any whitespace
        col = col + 1
      end
      vim.api.nvim_win_set_cursor(0, { cur_line + i, col - 1 })
      return true
    end
  end
  return false
end

local function find_prev_message()
  local cur_line = vim.api.nvim_win_get_cursor(0)[1] - 2
  if cur_line < 0 then
    return false
  end

  for i = cur_line, 0, -1 do
    local line = vim.api.nvim_buf_get_lines(0, i, i + 1, false)[1]
    if line:match("^@[%w]+:") then
      -- Get the line and find position after the colon and whitespace
      local full_line = vim.api.nvim_buf_get_lines(0, i, i + 1, false)[1]
      local col = full_line:find(":%s*") + 1 -- Find position after the colon
      while full_line:sub(col, col) == " " do -- Skip any whitespace
        col = col + 1
      end
      vim.api.nvim_win_set_cursor(0, { i + 1, col - 1 })
      return true
    end
  end
  return false
end

-- Module configuration
local config = {}

-- Store the current provider instance
local provider = nil

-- Default configuration
local default_config = {
  highlights = {
    system = "Special",
    user = "Normal",
    assistant = "Comment",
  },
  prefix_style = "bold,underline",
  ruler = {
    char = "─", -- The character to use for the ruler
    style = "NonText", -- Highlight group for the ruler
  },
  signs = {
    enabled = false, -- Enable sign column highlighting (disabled by default)
    char = "▌", -- Default vertical bar character
    system = {
      char = nil, -- Use default char
      hl = true, -- Inherit from highlights.system
    },
    user = {
      char = nil, -- Use default char
      hl = true, -- Inherit from highlights.user
    },
    assistant = {
      char = nil, -- Use default char
      hl = true, -- Inherit from highlights.assistant
    },
  },
  notify = require("claudius.notify").default_opts,
  pricing = {
    enabled = true, -- Whether to show pricing information in notifications
  },
  provider = "claude", -- Default provider: "claude", "openai", or "vertex"
  model = nil, -- Will use provider-specific default if nil
  parameters = {
    max_tokens = nil, -- Will use default if nil
    temperature = nil, -- Will use default if nil
    vertex = {
      project_id = nil, -- Google Cloud project ID
      location = "us-central1", -- Google Cloud region
    },
  },
  text_object = "m", -- Default text object key, set to false to disable
  editing = {
    disable_textwidth = true, -- Whether to disable textwidth in chat buffers
    auto_write = false, -- Whether to automatically write the buffer after changes
  },
  logging = {
    enabled = false, -- Logging disabled by default
    path = vim.fn.stdpath("cache") .. "/claudius.log", -- Default log path
  },
  keymaps = {
    normal = {
      send = "<C-]>",
      cancel = "<C-c>",
      next_message = "]m", -- Jump to next message
      prev_message = "[m", -- Jump to previous message
    },
    insert = {
      send = "<C-]>",
    },
    enabled = true, -- Set to false to disable all keymaps
  },
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
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, i - 1, 0, {
          virt_lines = { { { ruler_text, default_config.ruler.style } } },
          virt_lines_above = true,
        })
      end
    end
  end
end

-- Helper function to auto-write the buffer if enabled
local function auto_write_buffer(bufnr)
  if config.editing.auto_write and vim.bo[bufnr].modified then
    log.debug("Auto-writing buffer")
    M.buffer_cmd(bufnr, "silent! write")
  end
end

-- Initialize or switch provider based on configuration
local function initialize_provider(provider_config)
  local provider_defaults = require("claudius.provider.defaults")

  -- Set default model if not specified
  if not provider_config.model then
    provider_config.model = provider_defaults.get_model(provider_config.provider)
  end

  -- Set default parameters if not specified
  if not provider_config.parameters.max_tokens then
    provider_config.parameters.max_tokens = provider_defaults.parameters.max_tokens
  end

  if not provider_config.parameters.temperature then
    provider_config.parameters.temperature = provider_defaults.parameters.temperature
  end

  -- Create a fresh provider instance with a clean state
  local new_provider
  if provider_config.provider == "openai" then
    new_provider = require("claudius.provider.openai").new(provider_config)
  elseif provider_config.provider == "vertex" then
    new_provider = require("claudius.provider.vertex").new(provider_config)
  else
    -- Default to Claude if not specified
    new_provider = require("claudius.provider.claude").new(provider_config)
  end

  -- Update the global provider reference
  provider = new_provider

  return new_provider
end

-- Setup function to initialize the plugin
M.setup = function(opts)
  -- Merge user config with defaults
  opts = opts or {}
  config = vim.tbl_deep_extend("force", default_config, opts)

  -- Initialize provider based on config
  initialize_provider(config)

  -- Configure logging based on user settings
  log.configure({
    enabled = config.logging.enabled,
    path = config.logging.path,
  })

  -- Helper function to toggle logging
  local function toggle_logging(enable)
    if enable == nil then
      enable = not log.is_enabled()
    end
    log.set_enabled(enable)
    if enable then
      vim.notify("Claudius: Logging enabled - " .. log.get_path())
    else
      vim.notify("Claudius: Logging disabled")
    end
  end

  -- Set up filetype detection for .chat files
  vim.filetype.add({
    extension = {
      chat = "chat",
    },
    pattern = {
      [".*%.chat"] = "chat",
    },
  })

  -- Define sign groups for each role
  if config.signs.enabled then
    -- Define signs with proper casing to match message types
    local signs = {
      ["You"] = { config = config.signs.user, highlight = config.highlights.user },
      ["System"] = { config = config.signs.system, highlight = config.highlights.system },
      ["Assistant"] = { config = config.signs.assistant, highlight = config.highlights.assistant },
    }
    -- Ensure we have lowercase versions of the role names for sign configs
    config.signs.you = config.signs.user
    for role, sign_data in pairs(signs) do
      if sign_data.config.hl ~= false then
        local sign_name = "claudius_" .. string.lower(role)
        vim.fn.sign_define(sign_name, {
          text = sign_data.config.char or config.signs.char,
          texthl = sign_data.config.hl == true and sign_data.highlight or sign_data.config.hl,
        })
      end
    end
  end

  -- Define syntax highlighting and Tree-sitter configuration
  local function set_syntax()
    local bufnr = vim.api.nvim_get_current_buf()

    -- Enable Tree-sitter for the buffer
    vim.treesitter.start(bufnr, "markdown")

    -- Explicitly load our syntax file
    vim.cmd("runtime! syntax/chat.vim")

    -- Link highlights to user config
    vim.cmd(string.format("highlight link ChatSystem %s", config.highlights.system))
    vim.cmd(string.format("highlight link ChatUser %s", config.highlights.user))
    vim.cmd(string.format("highlight link ChatAssistant %s", config.highlights.assistant))

    -- Set up prefix highlights
    vim.cmd(string.format(
      [[
      execute 'highlight ChatSystemPrefix guifg=' . synIDattr(synIDtrans(hlID("ChatSystem")), "fg", "gui") . ' gui=%s'
      execute 'highlight ChatUserPrefix guifg=' . synIDattr(synIDtrans(hlID("ChatUser")), "fg", "gui") . ' gui=%s'
      execute 'highlight ChatAssistantPrefix guifg=' . synIDattr(synIDtrans(hlID("ChatAssistant")), "fg", "gui") . ' gui=%s'
    ]],
      config.prefix_style,
      config.prefix_style,
      config.prefix_style
    ))
  end

  -- Set up folding expression
  local function setup_folding()
    vim.wo.foldmethod = "expr"
    vim.wo.foldexpr = 'v:lua.require("claudius").get_fold_level(v:lnum)'
    vim.wo.foldtext = 'v:lua.require("claudius").get_fold_text()'
    -- Start with all folds open
    vim.wo.foldlevel = 99
  end

  -- Add autocmd for updating rulers
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "VimResized", "TextChanged", "TextChangedI" }, {
    pattern = "*.chat",
    callback = function(ev)
      add_rulers(ev.buf)
      -- Clear and reapply all signs
      vim.fn.sign_unplace("claudius_ns", { buffer = ev.buf })
      M.parse_buffer(ev.buf) -- This will reapply signs
    end,
  })

  -- Create user commands
  vim.api.nvim_create_user_command("ClaudiusSend", function()
    M.send_to_provider()
  end, {})

  vim.api.nvim_create_user_command("ClaudiusCancel", function()
    M.cancel_request()
  end, {})

  vim.api.nvim_create_user_command("ClaudiusImport", function()
    require("claudius.import").import_buffer()
  end, {})

  vim.api.nvim_create_user_command("ClaudiusSendAndInsert", function()
    local bufnr = vim.api.nvim_get_current_buf()
    M.buffer_cmd(bufnr, "stopinsert")
    M.send_to_provider({
      on_complete = function()
        M.buffer_cmd(bufnr, "startinsert!")
      end,
    })
  end, {})

  -- Command to switch providers
  vim.api.nvim_create_user_command("ClaudiusSwitch", function(opts)
    local args = opts.fargs
    if #args < 1 then
      vim.notify("Usage: ClaudiusSwitch <provider> [model]", vim.log.levels.ERROR)
      return
    end

    local switch_opts = {
      provider = args[1],
    }

    if args[2] then
      switch_opts.model = args[2]
    end

    M.switch(switch_opts)
  end, {
    nargs = "+",
    complete = function(_, _, _)
      return { "claude", "openai", "vertex" }
    end,
  })

  -- Navigation commands
  vim.api.nvim_create_user_command("ClaudiusNextMessage", function()
    find_next_message()
  end, {})

  vim.api.nvim_create_user_command("ClaudiusPrevMessage", function()
    find_prev_message()
  end, {})

  -- Logging commands
  vim.api.nvim_create_user_command("ClaudiusEnableLogging", function()
    toggle_logging(true)
  end, {})

  vim.api.nvim_create_user_command("ClaudiusDisableLogging", function()
    toggle_logging(false)
  end, {})

  vim.api.nvim_create_user_command("ClaudiusOpenLog", function()
    if not log.is_enabled() then
      vim.notify("Claudius: Logging is currently disabled", vim.log.levels.WARN)
      -- Give user time to see the warning
      vim.defer_fn(function()
        vim.cmd("tabedit " .. log.get_path())
      end, 1000)
    else
      vim.cmd("tabedit " .. log.get_path())
    end
  end, {})

  -- Command to recall last notification
  vim.api.nvim_create_user_command("ClaudiusRecallNotification", function()
    require("claudius.notify").recall_last()
  end, {
    desc = "Recall the last notification",
  })

  -- Set up autocmd for the chat filetype
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType" }, {
    pattern = { "*.chat", "chat" },
    callback = function(ev)
      set_syntax()
      add_rulers(ev.buf)
    end,
  })

  -- Create the filetype detection
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "*.chat",
    callback = function()
      vim.bo.filetype = "chat"
      setup_folding()

      -- Disable textwidth if configured
      if config.editing.disable_textwidth then
        vim.bo.textwidth = 0
      end

      -- Set autowrite if configured
      if config.editing.auto_write then
        vim.opt_local.autowrite = true
      end
    end,
  })

  -- Set up the mappings for Claudius interaction if enabled
  if config.keymaps.enabled then
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "chat",
      callback = function()
        -- Normal mode mappings
        if config.keymaps.normal.send then
          vim.keymap.set("n", config.keymaps.normal.send, function()
            M.send_to_provider()
          end, { buffer = true, desc = "Send to Claudius" })
        end

        if config.keymaps.normal.cancel then
          vim.keymap.set(
            "n",
            config.keymaps.normal.cancel,
            M.cancel_request,
            { buffer = true, desc = "Cancel Claudius Request" }
          )
        end

        -- Message navigation keymaps
        if config.keymaps.normal.next_message then
          vim.keymap.set(
            "n",
            config.keymaps.normal.next_message,
            find_next_message,
            { buffer = true, desc = "Jump to next message" }
          )
        end

        if config.keymaps.normal.prev_message then
          vim.keymap.set(
            "n",
            config.keymaps.normal.prev_message,
            find_prev_message,
            { buffer = true, desc = "Jump to previous message" }
          )
        end

        -- Set up text objects with configured key
        textobject.setup({ text_object = config.text_object })

        -- Insert mode mapping - send and return to insert mode
        if config.keymaps.insert.send then
          vim.keymap.set("i", config.keymaps.insert.send, function()
            local bufnr = vim.api.nvim_get_current_buf()
            M.buffer_cmd(bufnr, "stopinsert")
            M.send_to_provider({
              on_complete = function()
                M.buffer_cmd(bufnr, "startinsert!")
              end,
            })
          end, { buffer = true, desc = "Send to Claudius and continue editing" })
        end
      end,
    })
  end
end

-- Place signs for a message
local function place_signs(bufnr, start_line, end_line, role)
  if not config.signs.enabled then
    return
  end

  local sign_name = "claudius_" .. string.lower(role)
  local sign_config = config.signs[string.lower(role)]
  if sign_config and sign_config.hl ~= false then
    for lnum = start_line, end_line do
      vim.fn.sign_place(0, "claudius_ns", sign_name, bufnr, { lnum = lnum })
    end
  end
end

-- Parse a single message from lines
local function parse_message(bufnr, lines, start_idx, frontmatter_offset)
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

  local result = {
    type = msg_type,
    content = table.concat(content, "\n"),
    start_line = start_idx,
    end_line = i - 1,
  }

  -- Place signs for the message, adjusting for frontmatter
  place_signs(bufnr, result.start_line + frontmatter_offset, result.end_line + frontmatter_offset, msg_type)

  return result, i - 1
end

-- Parse the entire buffer into a sequence of messages
function M.parse_buffer(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local messages = {}

  -- Handle frontmatter if present
  local frontmatter = require("claudius.frontmatter")
  local fm_code, content = frontmatter.parse(lines)

  -- Calculate frontmatter offset for sign placement
  local frontmatter_offset = 0
  if fm_code then
    -- Count lines in frontmatter (code + delimiters)
    frontmatter_offset = #vim.split(fm_code, "\n", true) + 2
  end

  -- If no frontmatter was found, use all lines as content
  content = content or lines

  local i = 1
  while i <= #content do
    local msg, last_idx = parse_message(bufnr, content, i, frontmatter_offset)
    if msg then
      messages[#messages + 1] = msg
      i = last_idx + 1
    else
      i = i + 1
    end
  end

  return messages, fm_code
end

-- Cancel ongoing request if any
function M.cancel_request()
  local bufnr = vim.api.nvim_get_current_buf()
  local state = buffers.get_state(bufnr)

  if state.current_request then
    log.info("Cancelling request " .. tostring(state.current_request))

    -- Mark as cancelled
    state.request_cancelled = true

    -- Use provider to cancel the request
    if provider:cancel_request(state.current_request) then
      state.current_request = nil

      -- Clean up the buffer
      local last_line = vim.api.nvim_buf_line_count(bufnr)
      local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]

      -- If we're still showing the thinking message, remove it
      if last_line_content:match("^@Assistant:.*Thinking%.%.%.$") then
        log.debug("Cleaning up thinking message")
        M.cleanup_spinner(bufnr)
      end

      -- Auto-write if enabled and we've received some content
      if state.request_cancelled and not last_line_content:match("^@Assistant:.*Thinking%.%.%.$") then
        auto_write_buffer(bufnr)
      end

      local msg = "Claudius: Request cancelled"
      if log.is_enabled() then
        msg = msg .. ". See " .. log.get_path() .. " for details"
      end
      vim.notify(msg, vim.log.levels.INFO)
    end
  else
    log.debug("Cancel request called but no current request found")
  end
end

-- Clean up spinner and prepare for response
M.cleanup_spinner = function(bufnr)
  local state = buffers.get_state(bufnr)
  if state.spinner_timer then
    vim.fn.timer_stop(state.spinner_timer)
    state.spinner_timer = nil
  end

  -- Stop any existing rulers/virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Remove the "Thinking..." line
  local last_line = vim.api.nvim_buf_line_count(bufnr)
  local prev_line = vim.api.nvim_buf_get_lines(bufnr, last_line - 2, last_line - 1, false)[1]

  -- Ensure we maintain a blank line if needed
  if prev_line and prev_line:match("%S") then
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { "" })
  else
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, {})
  end
end

-- Show loading spinner
local function start_loading_spinner(bufnr)
  local state = buffers.get_state(bufnr)
  local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
  local frame = 1

  -- Clear any existing virtual text
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Check if we need to add a blank line
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines > 0 and lines[#lines]:match("%S") then
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "", "@Assistant: Thinking..." })
  else
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "@Assistant: Thinking..." })
  end

  local timer = vim.fn.timer_start(100, function()
    if not state.current_request then
      return
    end
    frame = (frame % #spinner_frames) + 1
    local text = "@Assistant: " .. spinner_frames[frame] .. " Thinking..."
    local last_line = vim.api.nvim_buf_line_count(bufnr)
    M.buffer_cmd(bufnr, "undojoin")
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { text })
  end, { ["repeat"] = -1 })

  state.spinner_timer = timer
  return timer
end

-- Handle the AI provider interaction
function M.send_to_provider(opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_get_current_buf()
  local state = buffers.get_state(bufnr)

  -- Check if there's already a request in progress
  if state.current_request then
    vim.notify("Claudius: A request is already in progress. Use <C-c> to cancel it first.", vim.log.levels.WARN)
    return
  end

  log.info("Starting new request")
  state.request_cancelled = false

  -- Auto-write the buffer before sending if enabled
  auto_write_buffer(bufnr)

  -- Ensure we have a valid provider
  if not provider then
    log.error("No provider initialized")
    vim.notify("Claudius: Provider not initialized", vim.log.levels.ERROR)
    return
  end

  -- Check if we need to prompt for API key
  local api_key_result, api_key_error = pcall(function()
    return provider:get_api_key()
  end)

  if not api_key_result then
    -- There was an error getting the API key
    log.error("Error getting API key: " .. tostring(api_key_error))

    -- Get provider-specific authentication notes if available
    local provider_defaults = require("claudius.provider.defaults")
    local auth_notes = provider_defaults.auth_notes and provider_defaults.auth_notes[config.provider]

    if auth_notes then
      -- Show a more detailed alert with the auth notes
      require("claudius.notify").alert(
        tostring(api_key_error):gsub("%s+$", "") .. "\n\n---\n\n" .. auth_notes,
        { title = "Claudius - Authentication Error: " .. config.provider }
      )
    else
      require("claudius.notify").alert(tostring(api_key_error), { title = "Claudius - Authentication Error" })
    end
    return
  end

  if not api_key_error and not provider.state.api_key then
    log.info("No API key found in environment or keyring, prompting user")
    vim.ui.input({
      prompt = "Enter your API key: ",
      default = "",
      border = "rounded",
      title = " Claudius - API Key Required ",
      relative = "editor",
    }, function(input)
      if input then
        provider.state.api_key = input
        log.info("API key set via prompt")
        -- Continue with the Claudius request immediately
        M.send_to_provider()
      else
        log.error("API key prompt cancelled")
        vim.notify("Claudius: API key required to continue", vim.log.levels.ERROR)
      end
    end)

    -- Return early since we'll continue in the callback
    return
  end

  local messages, frontmatter_code = M.parse_buffer(bufnr)
  if #messages == 0 then
    vim.notify("Claudius: No messages found in buffer", vim.log.levels.WARN)
    return
  end

  -- Execute frontmatter if present and get variables
  local template_vars = {}
  if frontmatter_code then
    log.debug("Evaluating frontmatter code:\n" .. frontmatter_code)
    local ok, result = pcall(require("claudius.frontmatter").execute, frontmatter_code)
    if not ok then
      vim.notify("Claudius: Frontmatter error - " .. result, vim.log.levels.ERROR)
      return
    end
    log.debug("Frontmatter evaluation result:\n" .. vim.inspect(result))
    template_vars = result
  end

  local formatted_messages, system_message = provider:format_messages(messages, nil)

  -- Process template expressions in messages
  local eval = require("claudius.eval")
  local env = vim.tbl_extend("force", eval.create_safe_env(), template_vars)

  for i, msg in ipairs(formatted_messages) do
    -- Look for {{expression}} patterns
    msg.content = msg.content:gsub("{{(.-)}}", function(expr)
      log.debug(string.format("Evaluating template expression (message %d): %s", i, expr))
      local ok, result = pcall(eval.eval_expression, expr, env)
      if not ok then
        local err_msg = string.format("Template error (message %d) - %s", i, result)
        log.error(err_msg)
        vim.notify("Claudius: " .. err_msg, vim.log.levels.ERROR)
        return "{{" .. expr .. "}}" -- Keep original on error
      end
      log.debug(string.format("Expression result (message %d): %s", i, tostring(result)))
      return tostring(result)
    end)
  end

  -- Create request body with provider-specific model
  local provider_defaults = require("claudius.provider.defaults")
  local model = provider_defaults.get_appropriate_model(config.model, config.provider)

  -- Log if we had to switch models
  if model ~= config.model then
    log.info("Switching from " .. config.model .. " to " .. model .. " for " .. config.provider .. " provider")
  end

  local request_body = provider:create_request_body(formatted_messages, system_message, {
    model = model,
    max_tokens = config.parameters.max_tokens,
    temperature = config.parameters.temperature,
  })

  -- Log the request details
  log.debug("New request for " .. config.provider .. " to " .. model)

  local spinner_timer = start_loading_spinner(bufnr)
  local response_started = false

  -- Format usage information for display
  local function format_usage(current, session)
    local pricing = require("claudius.pricing")
    local lines = {}

    -- Request usage
    if current and (current.input_tokens > 0 or current.output_tokens > 0) then
      local current_cost = config.pricing.enabled
        and pricing.calculate_cost(config.model, current.input_tokens, current.output_tokens)
      table.insert(lines, "Request:")
      -- Add model and provider information
      table.insert(lines, string.format("  Model:  `%s` (%s)", config.model, config.provider))
      if current_cost then
        table.insert(lines, string.format("  Input:  %d tokens / $%.2f", current.input_tokens or 0, current_cost.input))
        table.insert(
          lines,
          string.format(" Output:  %d tokens / $%.2f", current.output_tokens or 0, current_cost.output)
        )
        table.insert(lines, string.format("  Total:  $%.2f", current_cost.total))
      else
        table.insert(lines, string.format("  Input:  %d tokens", current.input_tokens or 0))
        table.insert(lines, string.format(" Output:  %d tokens", current.output_tokens or 0))
      end
    end

    -- Session totals
    if session and (session.input_tokens > 0 or session.output_tokens > 0) then
      local session_cost = config.pricing.enabled
        and pricing.calculate_cost(config.model, session.input_tokens, session.output_tokens)
      if #lines > 0 then
        table.insert(lines, "")
      end
      table.insert(lines, "Session:")
      if session_cost then
        table.insert(lines, string.format("  Input:  %d tokens / $%.2f", session.input_tokens or 0, session_cost.input))
        table.insert(
          lines,
          string.format(" Output:  %d tokens / $%.2f", session.output_tokens or 0, session_cost.output)
        )
        table.insert(lines, string.format("  Total:  $%.2f", session_cost.total))
      else
        table.insert(lines, string.format("  Input:  %d tokens", session.input_tokens or 0))
        table.insert(lines, string.format(" Output:  %d tokens", session.output_tokens or 0))
      end
    end
    return table.concat(lines, "\n")
  end

  -- Reset usage tracking for this buffer
  state.current_usage = {
    input_tokens = 0,
    output_tokens = 0,
  }

  -- Set up callbacks for the provider
  local callbacks = {
    on_data = function(line)
      -- Don't log here as it's already logged in process_response_line
    end,

    on_stderr = function(line)
      log.error("stderr: " .. line)
    end,

    on_error = function(msg)
      vim.schedule(function()
        vim.fn.timer_stop(spinner_timer)
        M.cleanup_spinner(bufnr)
        state.current_request = nil

        -- Auto-write on error if enabled
        auto_write_buffer(bufnr)

        local notify_msg = "Claudius: " .. msg
        if log.is_enabled() then
          notify_msg = notify_msg .. ". See " .. log.get_path() .. " for details"
        end
        vim.notify(notify_msg, vim.log.levels.ERROR)
      end)
    end,

    on_done = function()
      vim.schedule(function()
        if spinner_timer then
          vim.fn.timer_stop(spinner_timer)
        end
        state.current_request = nil

        -- Clean up spinner if response never started
        if not response_started then
          M.cleanup_spinner(bufnr)

          -- Auto-write if enabled
          auto_write_buffer(bufnr)

          -- Add new prompt if needed
          local last_line = vim.api.nvim_buf_line_count(bufnr)
          M.buffer_cmd(bufnr, "undojoin")
          vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "", "@You: " })

          -- Move cursor to after the colon and any whitespace
          local lines = vim.api.nvim_buf_get_lines(bufnr, last_line + 1, last_line + 2, false)
          if #lines > 0 then
            local line = lines[1]
            local col = line:find(":%s*") + 1 -- Find position after the colon
            while line:sub(col, col) == " " do -- Skip any whitespace
              col = col + 1
            end
            -- Only set cursor if we're still in the buffer
            if vim.api.nvim_get_current_buf() == bufnr then
              vim.api.nvim_win_set_cursor(0, { last_line + 2, col - 1 })
            end
          end

          -- Call the completion callback if provided
          if opts.on_complete then
            opts.on_complete()
          end
        end
      end)
    end,

    on_usage = function(usage_data)
      if usage_data.type == "input" then
        state.current_usage.input_tokens = usage_data.tokens
      elseif usage_data.type == "output" then
        state.current_usage.output_tokens = usage_data.tokens
      end
    end,

    on_message_complete = function()
      vim.schedule(function()
        -- Update session totals
        session_usage.input_tokens = session_usage.input_tokens + (state.current_usage.input_tokens or 0)
        session_usage.output_tokens = session_usage.output_tokens + (state.current_usage.output_tokens or 0)

        -- Auto-write when response is complete
        auto_write_buffer(bufnr)

        -- Format and display usage information using our custom notification
        local usage_str = format_usage(state.current_usage, session_usage)
        if usage_str ~= "" then
          local notify_opts = vim.tbl_deep_extend("force", config.notify, {
            title = "Usage",
          })
          require("claudius.notify").show(usage_str, notify_opts)
        end
        -- Reset current usage for next request
        state.current_usage = {
          input_tokens = 0,
          output_tokens = 0,
        }
      end)
    end,

    on_content = function(text)
      vim.schedule(function()
        -- Stop spinner on first content
        if not response_started then
          vim.fn.timer_stop(spinner_timer)
        end

        -- Split content into lines
        local lines = vim.split(text, "\n", { plain = true })

        if #lines > 0 then
          local last_line = vim.api.nvim_buf_line_count(bufnr)

          if not response_started then
            -- Clean up spinner and ensure blank line
            M.cleanup_spinner(bufnr)
            last_line = vim.api.nvim_buf_line_count(bufnr)

            -- Check if response starts with a code fence
            if lines[1]:match("^```") then
              -- Add a newline before the code fence
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant:", lines[1] })
            else
              -- Start with @Assistant: prefix as normal
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant: " .. lines[1] })
            end

            -- Add remaining lines if any
            if #lines > 1 then
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line + 1, last_line + 1, false, { unpack(lines, 2) })
            end
          else
            -- Get the last line's content
            local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]

            if #lines == 1 then
              -- Just append to the last line
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { last_line_content .. lines[1] })
            else
              -- First chunk goes to the end of the last line
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { last_line_content .. lines[1] })

              -- Remaining lines get added as new lines
              M.buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { unpack(lines, 2) })
            end
          end

          response_started = true
        end
      end)
    end,

    on_complete = function(code)
      vim.schedule(function()
        state.current_request = nil
        vim.fn.timer_stop(spinner_timer)

        -- Only add the new prompt if the request wasn't cancelled and completed successfully
        if not state.request_cancelled and code == 0 and response_started then
          local last_line = vim.api.nvim_buf_line_count(bufnr)

          -- Check if the last line is empty
          local last_line_content = ""
          if last_line > 0 then
            last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1] or ""
          end

          -- Prepare lines to insert based on whether the last line is empty
          local lines_to_insert = {}
          local cursor_line_offset = 1

          if last_line_content == "" then
            -- Last line is already empty, just add the prompt
            lines_to_insert = { "@You: " }
          else
            -- Last line has content, add a blank line then the prompt
            lines_to_insert = { "", "@You: " }
            cursor_line_offset = 2
          end

          -- Insert the lines
          M.buffer_cmd(bufnr, "undojoin")
          vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, lines_to_insert)

          -- Move cursor to after the colon and any whitespace
          local new_line = last_line + cursor_line_offset - 1
          local lines = vim.api.nvim_buf_get_lines(bufnr, new_line, new_line + 1, false)
          if #lines > 0 then
            local line = lines[1]
            local col = line:find(":%s*") + 1 -- Find position after the colon
            while line:sub(col, col) == " " do -- Skip any whitespace
              col = col + 1
            end
            -- Only set cursor if we're still in the buffer
            if vim.api.nvim_get_current_buf() == bufnr then
              vim.api.nvim_win_set_cursor(0, { new_line + 1, col - 1 })
            end
          end

          -- Auto-write after adding the prompt if enabled
          auto_write_buffer(bufnr)

          -- Call the completion callback if provided
          if opts.on_complete then
            opts.on_complete()
          end
        end
      end)
    end,
  }

  -- Send the request using the provider
  state.current_request = provider:send_request(request_body, callbacks)
end

-- Switch to a different provider or model
function M.switch(opts)
  if not opts or not opts.provider then
    vim.notify("Provider is required", vim.log.levels.ERROR)
    return
  end

  -- Check for ongoing requests
  local bufnr = vim.api.nvim_get_current_buf()
  local state = buffers.get_state(bufnr)
  if state.current_request then
    vim.notify("Cannot switch providers while a request is in progress. Cancel it first.", vim.log.levels.WARN)
    return
  end

  -- Create a new configuration by merging the current config with the provided options
  local new_config = vim.tbl_deep_extend("force", {}, config)

  -- Update provider
  new_config.provider = opts.provider

  -- Update model if specified
  if opts.model then
    new_config.model = opts.model
  else
    -- Reset model to use provider default
    new_config.model = nil
  end

  -- Let each provider handle its own parameters by passing all options
  -- This avoids special-casing for specific providers like Vertex AI
  if not new_config.parameters then
    new_config.parameters = {}
  end

  -- Initialize provider-specific parameters if they don't exist
  if not new_config.parameters[opts.provider] then
    new_config.parameters[opts.provider] = {}
  end

  -- Pass all options to the provider-specific parameters object
  for k, v in pairs(opts) do
    if k ~= "provider" and k ~= "model" then
      new_config.parameters[opts.provider][k] = v
    end
  end

  -- Update the global config
  config = new_config

  -- Initialize the new provider with a clean state
  provider = nil -- Clear the current provider
  local new_provider = initialize_provider(config)

  -- Force the new provider to clear its API key cache
  if new_provider and new_provider.state then
    new_provider.state.api_key = nil
  end

  -- Notify the user
  local model_info = config.model and (" with model " .. config.model) or ""
  vim.notify("Switched to " .. config.provider .. model_info, vim.log.levels.INFO)

  return new_provider
end

return M
