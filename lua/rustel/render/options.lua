local M = {}

function M.parse(source)
  if type(source) == "table" then return source end
  local options = {}
  for key, value in tostring(source or ""):gmatch([[['"]?([%a_][%w_]*)['"]?%s*:%s*([^,{}]+)]]) do
    value = vim.trim(value)
    if value == "true" or value == "false" then
      options[key] = value == "true"
    elseif tonumber(value) then
      options[key] = tonumber(value)
    elseif value:match('^"[^"\\]*"$') or value:match("^'[^'\\]*'$") then
      options[key] = value:sub(2, -2)
    end
  end
  return options
end

function M.number(options, key, fallback, low, high)
  local value = tonumber(options[key]) or fallback
  if value ~= value or value == math.huge or value == -math.huge then value = fallback end
  return math.max(low, math.min(high, value))
end

function M.flag(options, key, fallback)
  local value = options[key]
  if value == nil then return fallback end
  return value ~= false and value ~= 0
end

return M
