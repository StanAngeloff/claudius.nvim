--- Lualine component for Claudius
local lualine_component = require("lualine.component")

-- Create a new component for displaying the Claudius model
local claudius_model_component = lualine_component:extend()

--- Updates the status of the component.
-- This function is called by lualine to get the text to display.
function claudius_model_component:update_status()
  local claudius_init_ok, claudius_init = pcall(require, "claudius.init")
  if claudius_init_ok and claudius_init and claudius_init.get_current_model_name then
    return claudius_init.get_current_model_name() or "" -- Return model name or empty string
  end
  return "" -- Fallback if claudius.init is not available or model is not set
end

local M = {}
M.model = claudius_model_component -- Expose the component instance

return M
