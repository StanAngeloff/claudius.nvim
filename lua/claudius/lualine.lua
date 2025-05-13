--- Lualine component for Claudius
local M = {}

local function get_model_for_lualine()
  local claudius_init_ok, claudius_init = pcall(require, "claudius.init")
  if claudius_init_ok and claudius_init and claudius_init.get_current_model_name then
    return claudius_init.get_current_model_name() or "" -- Return empty string if model is nil
  end
  return "" -- Fallback if claudius.init is not available or model is not set
end

M.model = get_model_for_lualine

return M
