--- Claudius logging functionality
--- Provides centralized logging capabilities with custom inspect
local M = {}

-- Default configuration
local config = {
  enabled = false,
  path = vim.fn.stdpath("cache") .. "/claudius.log",
}

-- Write a log message to the log file
local function write_log(level, msg)
  if not config.enabled then
    return
  end

  local f = io.open(config.path, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S") .. " [" .. level .. "] " .. msg .. "\n")
    f:close()
  end
end

-- Custom inspect function for logging
function M.inspect(obj)
  return vim.inspect(obj, {
    newline = " ", -- Use space instead of newline
    indent = "", -- No indentation
    process = function(item)
      -- Truncate long strings
      if type(item) == "string" and #item > 1000 then
        return vim.inspect(item:sub(1, 1000) .. "...")
      end
      return item
    end,
  })
end

-- Log an info message
function M.info(msg)
  write_log("INFO", msg)
end

-- Log an error message
function M.error(msg)
  write_log("ERROR", msg)
end

-- Log a debug message
function M.debug(msg)
  write_log("DEBUG", msg)
end

-- Log a warning message
function M.warn(msg)
  write_log("WARN", msg)
end

-- Enable or disable logging
function M.set_enabled(enabled)
  config.enabled = enabled
end

-- Check if logging is enabled
function M.is_enabled()
  return config.enabled
end

-- Get the log path
function M.get_path()
  return config.path
end

-- Set the log path
function M.set_path(path)
  config.path = path
end

-- Configure the logging module
function M.configure(opts)
  if opts then
    if opts.enabled ~= nil then
      config.enabled = opts.enabled
    end
    if opts.path then
      config.path = opts.path
    end
  end
end

return M
