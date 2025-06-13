--- Lualine component for Claudius model display
local lualine_component = require("lualine.component")

-- Create a new component for displaying the Claudius model
local claudius_model_component = lualine_component:extend()

--- Updates the status of the component.
-- This function is called by lualine to get the text to display.
function claudius_model_component:update_status()
  -- Only show the model if the filetype is 'chat'
  if vim.bo.filetype == "chat" then
    local claudius_ok, claudius = pcall(require, "claudius")
    if claudius_ok and claudius then
      local model_name = claudius.get_current_model_name and claudius.get_current_model_name()
      if not model_name or model_name == "" then
        return "" -- No model, show nothing
      end

      local provider_name = claudius.get_current_provider_name and claudius.get_current_provider_name()
      local reasoning_setting = claudius.get_current_reasoning_setting and claudius.get_current_reasoning_setting()

      if
        provider_name == "openai"
        and model_name:sub(1, 1) == "o"
        and reasoning_setting -- This will be "low", "medium", or "high" if valid
      then
        return string.format("%s (%s)", model_name, reasoning_setting)
      else
        return model_name
      end
    end
    return "" -- Fallback if claudius module is not available
  end
  return "" -- Return empty string if not a 'chat' buffer
end

return claudius_model_component -- Return the component instance directly
