--- Claudius default configuration
local M = {}

-- Default configuration values
M.defaults = {
  highlights = {
    system = "Special",
    user = "Normal",
    assistant = "Comment",
  },
  role_style = "bold,underline", -- style applied to role markers like @You:
  ruler = {
    char = "─", -- The character to use for the ruler
    hl = "NonText", -- Highlight group for the ruler
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
    max_tokens = 4000, -- Default max tokens for all providers
    temperature = 0.7, -- Default temperature for all providers
    vertex = {
      project_id = nil, -- Google Cloud project ID
      location = "us-central1", -- Google Cloud region
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
  return key == "max_tokens" or key == "temperature"
end

return M
