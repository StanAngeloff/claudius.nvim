--- Lualine component for Claudius model display
local lualine_component = require("lualine.component")

-- Create a new component for displaying the Claudius model
local claudius_model_component = lualine_component:extend()

--- Updates the status of the component.
-- This function is called by lualine to get the text to display.
function claudius_model_component:update_status()
  local claudius_ok, claudius = pcall(require, "claudius")
  if claudius_ok and claudius and claudius.get_current_model_name then
    return claudius.get_current_model_name() or "" -- Return model name or empty string
  end
  return "" -- Fallback if claudius.init is not available or model is not set
end

return claudius_model_component -- Return the component instance directly
