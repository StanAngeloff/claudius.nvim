--- Claudius default configuration
local M = {}

-- Default configuration values
M.defaults = {
  highlights = {
    system = "Special", -- Highlight group or hex color (e.g., "#ffccaa") for system messages
    user = "Normal", -- Highlight group or hex color for user messages
    assistant = "Comment", -- Highlight group or hex color for assistant messages
    lua_expression = "PreProc", -- Highlight group or hex color for {{expression}}
    file_reference = "Include", -- Highlight group or hex color for @./file references
  },
  role_style = "bold,underline", -- style applied to role markers like @You:
  ruler = {
    char = "━", -- The character to use for the ruler
    hl = "NonText", -- Highlight group or hex color for the ruler
  },
  signs = {
    enabled = false, -- Enable sign column highlighting (disabled by default)
    char = "▌", -- Default vertical bar character
    system = {
      char = nil, -- Use default char
      hl = true, -- Inherit from highlights.system, set false to disable, or provide specific group/hex color
    },
    user = {
      char = "▏",
      hl = true, -- Inherit from highlights.user, set false to disable, or provide specific group/hex color
    },
    assistant = {
      char = nil, -- Use default char
      hl = true, -- Inherit from highlights.assistant, set false to disable, or provide specific group/hex color
    },
  },
  notify = require("claudius.notify").default_opts,
  pricing = {
    enabled = true, -- Whether to show pricing information in notifications
  },
  provider = "claude", -- Default provider: "claude", "openai", or "vertex"
  model = nil, -- Will use provider-specific default if nil
  parameters = {
    max_tokens = 4000, -- Default max tokens for all providers
    temperature = 0.7, -- Default temperature for all providers
    timeout = 120, -- Default response timeout for cURL requests
    connect_timeout = 10, -- Default connection timeout for cURL requests
    vertex = {
      project_id = nil, -- Google Cloud project ID
      location = "global", -- Google Cloud region
      thinking_budget = nil, -- Optional. Budget for model thinking, in tokens. nil or 0 disables thinking. Values >= 1 enable thinking with the specified budget.
    },
    -- Add provider-specific parameter sections here if needed in the future
    -- e.g., claude = {}, openai = {}
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

-- Check if a parameter key is a general parameter applicable to all providers
function M.is_general_parameter(key)
  return key == "max_tokens" or key == "temperature" or key == "timeout" or key == "connect_timeout"
end

return M
