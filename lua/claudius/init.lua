local M = {}
local ns_id = vim.api.nvim_create_namespace('claudius')

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
      syntax match ChatSystemPrefix "^@System:" contained
      syntax match ChatUserPrefix "^@You:" contained
      syntax match ChatAssistantPrefix "^@Assistant:" contained

      " Define the regions that contain the prefixes
      syntax region ChatSystem start=/^@System:/ end=/\(^@\(You\|Assistant\):\)\@=\|\%$/ contains=ChatSystemPrefix
      syntax region ChatUser start=/^@You:/ end=/\(^@\(System\|Assistant\):\)\@=\|\%$/ contains=ChatUserPrefix
      syntax region ChatAssistant start=/^@Assistant:/ end=/\(^@\(System\|You\):\)\@=\|\%$/ contains=ChatAssistantPrefix
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
end

return M
