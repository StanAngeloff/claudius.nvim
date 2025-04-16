--- Claudius plugin core functionality
--- Provides chat interface and API integration
local M = {}

local buffers = require("claudius.buffers")
local plugin_config = require("claudius.config")
local log = require("claudius.logging")
local provider_config = require("claudius.provider.config")
local textobject = require("claudius.textobject")

local provider = nil

-- Module configuration (will hold merged user opts and defaults)
local config = {}

local ns_id = vim.api.nvim_create_namespace("claudius")

-- Session-wide usage tracking
local session_usage = {
  input_tokens = 0,
  output_tokens = 0,
}

-- Execute a command in the context of a specific buffer
local function buffer_cmd(bufnr, cmd)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    -- If buffer has no window, do nothing
    return
  end
  vim.fn.win_execute(winid, "noautocmd " .. cmd)
end

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
        -- Create virtual line with ruler using the current config
        local ruler_text = string.rep(config.ruler.char, math.floor(vim.api.nvim_win_get_width(0) * 1))
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, i - 1, 0, {
          virt_lines = { { { ruler_text, config.ruler.hl } } },
          virt_lines_above = true,
        })
      end
    end
  end
end

-- Helper function to force UI update (rulers and signs)
local function update_ui(bufnr)
  -- Ensure buffer is valid before proceeding
  if not vim.api.nvim_buf_is_valid(bufnr) then
    log.debug("update_ui(): Invalid buffer: " .. bufnr)
    return
  end
  add_rulers(bufnr)
  -- Clear and reapply all signs
  vim.fn.sign_unplace("claudius_ns", { buffer = bufnr })
  M.parse_buffer(bufnr) -- This will reapply signs
end

-- Helper function to auto-write the buffer if enabled
local function auto_write_buffer(bufnr)
  if config.editing.auto_write and vim.bo[bufnr].modified then
    log.debug("auto_write_buffer(): bufnr = " .. bufnr)
    buffer_cmd(bufnr, "silent! write")
  end
end

-- Initialize or switch provider based on configuration
local function initialize_provider(provider_name, model_name, parameters)
  -- Validate and potentially update the model based on the provider
  local original_model = model_name -- Could be nil
  local validated_model = provider_config.get_appropriate_model(original_model, provider_name)

  -- Log if we had to switch models during initialization/switch
  if validated_model ~= original_model and original_model ~= nil then
    log.info(
      "initialize_provider(): Model "
        .. log.inspect(original_model)
        .. " is not valid for provider "
        .. log.inspect(provider_name)
        .. ". Using default: "
        .. log.inspect(validated_model)
    )
  elseif original_model == nil then
    log.debug(
      "initialize_provider(): Using default model for provider "
        .. log.inspect(provider_name)
        .. ": "
        .. log.inspect(validated_model)
    )
  end

  -- Use the validated model for the final provider configuration
  -- Also update the global config table so format_usage gets the correct model
  config.model = validated_model

  -- Prepare the final parameters table by merging base and provider-specific settings
  local merged_params = {}
  local base_params = parameters or {}
  local provider_overrides = base_params[provider_name] or {}

  -- 1. Copy all non-provider-specific keys from the base parameters
  for k, v in pairs(base_params) do
    -- Only copy if it's not a provider-specific table or if it's a general parameter
    if type(v) ~= "table" or plugin_config.is_general_parameter(k) then
      merged_params[k] = v
    end
  end
  -- 2. Merge the provider-specific overrides, potentially overwriting general keys
  for k, v in pairs(provider_overrides) do
    merged_params[k] = v
  end

  -- Set the validated model in the merged parameters
  merged_params.model = validated_model

  -- Log the final configuration being passed to the provider constructor
  log.debug(
    "initialize_provider(): Initializing provider "
      .. log.inspect(provider_name)
      .. " with config: "
      .. log.inspect(merged_params)
  )

  -- Create a fresh provider instance with the merged parameters
  local new_provider
  if provider_name == "openai" then
    new_provider = require("claudius.provider.openai").new(merged_params)
  elseif provider_name == "vertex" then
    new_provider = require("claudius.provider.vertex").new(merged_params)
  else
    -- Default to Claude if not specified (or if provider_name is 'claude')
    new_provider = require("claudius.provider.claude").new(merged_params)
  end

  -- Update the global provider reference
  provider = new_provider

  return new_provider
end

-- Setup function to initialize the plugin
M.setup = function(user_opts)
  -- Merge user config with defaults from the config module
  user_opts = user_opts or {}
  config = vim.tbl_deep_extend("force", plugin_config.defaults, user_opts)

  -- Configure logging based on user settings
  log.configure({
    enabled = config.logging.enabled,
    path = config.logging.path,
  })

  log.info("setup(): Claudius starting...")

  -- Initialize provider based on the merged config
  initialize_provider(config.provider, config.model, config.parameters)

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
    vim.wo.foldexpr = 'v:lua.require("claudius.buffers").get_fold_level(v:lnum)'
    vim.wo.foldtext = 'v:lua.require("claudius.buffers").get_fold_text()'
    -- Start with all folds open
    vim.wo.foldlevel = 99
  end

  -- Add autocmd for updating rulers and signs (debounced via CursorHold)
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "VimResized", "CursorHold", "CursorHoldI" }, {
    pattern = "*.chat",
    callback = function(ev)
      -- Use the new function for debounced updates
      update_ui(ev.buf)
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
    buffer_cmd(bufnr, "stopinsert")
    M.send_to_provider({
      on_complete = function()
        buffer_cmd(bufnr, "startinsert!")
      end,
    })
  end, {})

  -- Parse key=value arguments
  local function parse_key_value_args(args, start_index)
    local result = {}
    for i = start_index or 3, #args do
      local arg = args[i]
      local key, value = arg:match("^([%w_]+)=(.+)$")

      if key and value then
        -- Convert value to appropriate type
        if value == "true" then
          value = true
        elseif value == "false" then
          value = false
        elseif value == "nil" or value == "null" then
          value = nil
        elseif tonumber(value) then
          value = tonumber(value)
        end

        result[key] = value
      end
    end
    return result
  end

  -- Command to switch providers
  vim.api.nvim_create_user_command("ClaudiusSwitch", function(opts)
    local args = opts.fargs

    if #args == 0 then
      -- Interactive selection if no arguments are provided
      local providers = {}
      for name, _ in pairs(provider_config.models) do
        table.insert(providers, name)
      end
      table.sort(providers) -- Sort providers for the selection list

      vim.ui.select(providers, { prompt = "Select Provider:" }, function(selected_provider)
        if not selected_provider then
          vim.notify("Claudius: Provider selection cancelled", vim.log.levels.INFO)
          return
        end

        -- Get models for the selected provider (unsorted)
        local models = provider_config.models[selected_provider] or {}
        if type(models) ~= "table" or #models == 0 then
          vim.notify("Claudius: No models found for provider " .. selected_provider, vim.log.levels.WARN)
          -- Switch to provider with default model
          M.switch(selected_provider, nil, {})
          return
        end

        vim.ui.select(models, { prompt = "Select Model for " .. selected_provider .. ":" }, function(selected_model)
          if not selected_model then
            vim.notify("Claudius: Model selection cancelled", vim.log.levels.INFO)
            return
          end
          -- Call M.switch with selected provider and model, no extra params
          M.switch(selected_provider, selected_model, {})
        end)
      end)
    else
      -- Existing logic for handling command-line arguments
      local switch_opts = {
        provider = args[1],
      }

      if args[2] and not args[2]:match("^[%w_]+=") then
        switch_opts.model = args[2]
      end

      -- Parse any key=value pairs
      local key_value_args = parse_key_value_args(args, switch_opts.model and 3 or 2)
      for k, v in pairs(key_value_args) do
        switch_opts[k] = v
      end

      -- Call the refactored M.switch function
      M.switch(switch_opts.provider, switch_opts.model, key_value_args)
    end
  end, {
    nargs = "*", -- Allow zero arguments for interactive mode
    complete = function(arglead, cmdline, _)
      local args = vim.split(cmdline, "%s+", { trimempty = true })
      local num_args = #args
      local trailing_space = cmdline:match("%s$")

      -- If completing the provider name (argument 2)
      if num_args == 1 or (num_args == 2 and not trailing_space) then
        local providers = {}
        for name, _ in pairs(provider_config.models) do
          table.insert(providers, name)
        end
        table.sort(providers)
        return vim.tbl_filter(function(p)
          return vim.startswith(p, arglead)
        end, providers)
      -- If completing the model name (argument 3)
      elseif (num_args == 2 and trailing_space) or (num_args == 3 and not trailing_space) then
        local provider_name = args[2]
        -- Access the model list directly from the new structure
        local models = provider_config.models[provider_name] or {}

        -- Ensure models is a table before sorting and filtering
        if type(models) == "table" then
          -- Filter the original (unsorted) list
          return vim.tbl_filter(function(model)
            return vim.startswith(model, arglead)
          end, models)
        end
        -- If the provider doesn't exist or models isn't a table, return empty
        return {}
      end

      -- Default: return empty list if no completion matches
      return {}
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
            buffer_cmd(bufnr, "stopinsert")
            M.send_to_provider({
              on_complete = function()
                buffer_cmd(bufnr, "startinsert!")
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
    log.info("cancel_request(): job_id = " .. tostring(state.current_request))

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
        log.debug("cancel_request(): ... Cleaning up 'Thinking...' message")
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
      -- Force UI update after cancellation
      update_ui(bufnr)
    end
  else
    log.debug("cancel_request(): No current request found")
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
  -- Force UI update after cleaning up spinner
  update_ui(bufnr)
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
  -- Immediately update UI after adding the thinking message
  update_ui(bufnr)

  local timer = vim.fn.timer_start(100, function()
    if not state.current_request then
      return
    end
    frame = (frame % #spinner_frames) + 1
    local text = "@Assistant: " .. spinner_frames[frame] .. " Thinking..."
    local last_line = vim.api.nvim_buf_line_count(bufnr)
    buffer_cmd(bufnr, "undojoin")
    vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { text })
    -- Force UI update during spinner animation
    update_ui(bufnr)
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

  log.info("send_to_provider(): Starting new request for buffer " .. bufnr)
  state.request_cancelled = false

  -- Auto-write the buffer before sending if enabled
  auto_write_buffer(bufnr)

  -- Ensure we have a valid provider
  if not provider then
    log.error("send_to_provider(): Provider not initialized")
    vim.notify("Claudius: Provider not initialized", vim.log.levels.ERROR)
    return
  end

  -- Check if we need to prompt for API key
  local api_key_result, api_key_error = pcall(function()
    return provider:get_api_key()
  end)

  if not api_key_result then
    -- There was an error getting the API key
    log.error("send_to_provider(): Error getting API key: " .. tostring(api_key_error))

    -- Get provider-specific authentication notes if available
    local auth_notes = provider_config.auth_notes and provider_config.auth_notes[config.provider]

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
    log.info("send_to_provider(): No API key found, prompting user")
    vim.ui.input({
      prompt = "Enter your API key: ",
      default = "",
      border = "rounded",
      title = " Claudius - API Key Required ",
      relative = "editor",
    }, function(input)
      if input then
        provider.state.api_key = input
        log.info("send_to_provider(): API key set via prompt")
        -- Continue with the Claudius request immediately
        M.send_to_provider()
      else
        log.error("send_to_provider(): API key prompt cancelled by user")
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
    log.debug("send_to_provider(): Evaluating frontmatter code: " .. log.inspect(frontmatter_code))
    local ok, result = pcall(require("claudius.frontmatter").execute, frontmatter_code)
    if not ok then
      vim.notify("Claudius: Frontmatter error - " .. result, vim.log.levels.ERROR)
      return
    end
    log.debug("send_to_provider(): ... Frontmatter evaluation result: " .. log.inspect(result))
    template_vars = result
  end

  local formatted_messages, system_message = provider:format_messages(messages, nil)

  -- Process template expressions in messages
  local eval = require("claudius.eval")
  local env = vim.tbl_extend("force", eval.create_safe_env(), template_vars)

  for i, msg in ipairs(formatted_messages) do
    -- Look for {{expression}} patterns
    msg.content = msg.content:gsub("{{(.-)}}", function(expr)
      log.debug(
        string.format("send_to_provider(): Evaluating template expression (message %d): %s", i, log.inspect(expr))
      )
      local ok, result = pcall(eval.eval_expression, expr, env)
      if not ok then
        local err_msg = string.format("Template error (message %d) - %s", i, result)
        log.error("send_to_provider(): " .. err_msg)
        vim.notify("Claudius: " .. err_msg, vim.log.levels.ERROR)
        return "{{" .. expr .. "}}" -- Keep original on error
      end
      log.debug(string.format("send_to_provider(): ... Expression result (message %d): %s", i, log.inspect(result)))
      return tostring(result)
    end)
  end

  -- Create request body using the validated model stored in the provider
  local request_body = provider:create_request_body(formatted_messages, system_message)

  -- Log the request details (using the provider's stored model)
  log.debug(
    "send_to_provider(): Sending request for provider "
      .. log.inspect(config.provider)
      .. " with model "
      .. log.inspect(provider.parameters.model)
  )

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
      log.error("send_to_provider(): callbacks.on_stderr: " .. line)
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
          buffer_cmd(bufnr, "undojoin")
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
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant:", lines[1] })
            else
              -- Start with @Assistant: prefix as normal
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { "@Assistant: " .. lines[1] })
            end

            -- Add remaining lines if any
            if #lines > 1 then
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line + 1, last_line + 1, false, { unpack(lines, 2) })
            end
          else
            -- Get the last line's content
            local last_line_content = vim.api.nvim_buf_get_lines(bufnr, last_line - 1, last_line, false)[1]

            if #lines == 1 then
              -- Just append to the last line
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { last_line_content .. lines[1] })
            else
              -- First chunk goes to the end of the last line
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line - 1, last_line, false, { last_line_content .. lines[1] })

              -- Remaining lines get added as new lines
              buffer_cmd(bufnr, "undojoin")
              vim.api.nvim_buf_set_lines(bufnr, last_line, last_line, false, { unpack(lines, 2) })
            end
          end

          response_started = true
          -- Force UI update after appending content
          update_ui(bufnr)
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
          buffer_cmd(bufnr, "undojoin")
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

          -- Force UI update after adding the prompt
          update_ui(bufnr)

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
function M.switch(provider_name, model_name, parameters)
  if not provider_name then
    vim.notify("Claudius: Provider name is required", vim.log.levels.ERROR)
    return
  end

  -- Check for ongoing requests
  local bufnr = vim.api.nvim_get_current_buf()
  local state = buffers.get_state(bufnr)
  if state.current_request then
    vim.notify("Claudius: Cannot switch providers while a request is in progress.", vim.log.levels.WARN)
    return
  end

  -- Ensure parameters is a table if nil
  parameters = parameters or {}

  -- Create a new configuration by merging the current config with the provided options
  local new_config = vim.tbl_deep_extend("force", {}, config)

  -- Update provider
  new_config.provider = provider_name

  -- Update model if specified, otherwise reset to use provider default
  new_config.model = model_name or nil

  -- Ensure parameters table and provider-specific sub-table exist
  new_config.parameters = new_config.parameters or {}
  new_config.parameters[provider_name] = new_config.parameters[provider_name] or {}

  -- Merge the provided parameters into the correct parameter locations
  for k, v in pairs(parameters) do
    -- Check if it's a general parameter
    if plugin_config.is_general_parameter(k) then
      new_config.parameters[k] = v
    else
      -- Assume it's a provider-specific parameter
      new_config.parameters[provider_name][k] = v
    end
  end

  -- Log the relevant configuration being used for the new provider
  log.debug(
    "switch(): provider = "
      .. log.inspect(new_config.provider)
      .. ", model = "
      .. log.inspect(new_config.model)
      .. ", parameters = "
      .. log.inspect(new_config.parameters)
  )

  -- Update the global config
  config = new_config

  -- Initialize the new provider with a clean state using the updated config
  provider = nil -- Clear the current provider
  local new_provider = initialize_provider(new_config.provider, new_config.model, new_config.parameters) -- Pass individual args

  -- Force the new provider to clear its API key cache
  if new_provider and new_provider.state then
    new_provider.state.api_key = nil
  end

  -- Notify the user
  local model_info = config.model and (" with model " .. config.model) or ""
  vim.notify("Claudius: Switched to " .. config.provider .. model_info, vim.log.levels.INFO)

  return new_provider
end

return M
