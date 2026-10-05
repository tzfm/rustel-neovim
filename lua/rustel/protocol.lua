local M = {}

-- Neovim 0.9 vim.tbl_islist accepts a hole. A list here is 1..n with no hole.
local function is_list(value)
  if vim.islist then return vim.islist(value) end
  if type(value) ~= "table" then return false end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" then return false end
    count = count + 1
  end
  for index = 1, count do
    if value[index] == nil then return false end
  end
  return true
end

function M.finite(value)
  return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function M.revision(value)
  return type(value) == "string" and #value == 64 and not value:find("[^0-9a-f]")
end

local function samples(frame)
  if type(frame) ~= "table" then return false end
  for _, key in ipairs({ "scope", "spectrum" }) do
    local values = frame[key]
    if type(values) ~= "table" or not is_list(values) or #values ~= 512 then return false end
    for index = 1, 512 do if not M.finite(values[index]) then return false end end
  end
  return true
end

function M.audio(frame)
  if not M.finite(frame.device_time) or frame.device_time < 0
    or not M.finite(frame.sample_rate) or frame.sample_rate <= 0 or not samples(frame) then return false end
  if frame.visuals == nil then return true end
  if type(frame.visuals) ~= "table" or not is_list(frame.visuals) or #frame.visuals > 64 then return false end
  local slots = {}
  for _, visual in ipairs(frame.visuals) do
    if not samples(visual) then return false end
    local slot = visual.slot
    if not M.finite(slot) or slot % 1 ~= 0 or slot < 0 or slot > 63 or slots[slot] then return false end
    slots[slot] = true
  end
  return true
end

function M.slots(value)
  local low, high = 0, 0
  for digit in tostring(value or "0"):gmatch("%d") do
    local next_low = low * 10 + tonumber(digit)
    high = (high * 10 + math.floor(next_low / 4294967296)) % 4294967296
    low = next_low % 4294967296
  end
  local slots = {}
  for slot = 0, 63 do
    local half = slot < 32 and low or high
    if math.floor(half / 2 ^ (slot % 32)) % 2 == 1 then slots[slot] = true end
  end
  return slots
end

function M.stream(on_message, on_text)
  local pending, overflow = "", false
  local function emit(line)
    if line == "" then return end
    -- A Lua number cannot hold every bit of a 64-bit slot mask.
    -- Quote the mask before JSON decode.
    line = line:gsub('("ui_visuals"%s*:%s*)(%d+)', '%1"%2"')
    local ok, message = pcall(vim.json.decode, line)
    if ok and type(message) == "table" then
      on_message(message)
    elseif on_text then
      on_text(line)
    end
  end
  return function(data)
    for index, chunk in ipairs(data or {}) do
      if index > 1 then
        if not overflow then emit(pending) end
        pending, overflow = "", false
      end
      if not overflow then
        pending = pending .. chunk
        if #pending > 4 * 1024 * 1024 then pending, overflow = "", true end
      end
    end
  end
end

return M
