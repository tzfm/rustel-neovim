local M = {}

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function number(value, default)
  return type(value) == "number" and value == value and math.abs(value) < math.huge and value or default
end

local function flag(value, default)
  if value == nil then return default end
  return value ~= false and value ~= 0
end

local function scope(canvas, samples, options)
  local count = #samples
  local start = 1
  local trigger = clamp(number(options.trigger, 0), -1, 1)
  if flag(options.align, true) then
    for index = 2, math.floor(count / 2) do
      if samples[index - 1] > -trigger and samples[index] <= -trigger then
        start = index
        break
      end
    end
  end
  local scale = clamp(number(options.scale, 1), 0.01, 8)
  if flag(options.fit, options.scale == nil) then
    local peak = 0
    for index = start, count do peak = math.max(peak, math.abs(samples[index])) end
    scale = peak > 0.002 and math.min(12, 0.92 / peak) or 1
  end
  local width, height = canvas.pixel_width, canvas.pixel_height
  local center = math.floor(clamp(number(options.pos, 0.5), 0, 1) * (height - 1) + 0.5)
  for x = 0, width - 1, 4 do canvas:point(x, center, "Comment") end
  local logarithmic = flag(options.log, flag(options.db, false))
  local previous
  for x = 0, width - 1 do
    -- After alignment, keep the same time scale. Leave the unused end blank.
    local index = start + math.floor(x * (count - 1) / math.max(1, width - 1))
    if index > count then break end
    local sample = clamp(samples[index] * scale, -1, 1)
    if logarithmic and sample ~= 0 then
      local level = clamp(1 + 20 * math.log(math.abs(sample)) / math.log(10) / 60, 0, 1)
      sample = sample < 0 and -level or level
    end
    local y = clamp(math.floor(center - sample * (height - 1) / 2 + 0.5), 0, height - 1)
    if previous then canvas:line(x - 1, previous, x, y, "String")
    else canvas:point(x, y, "String") end
    previous = y
  end
end

local function spectrum(canvas, bins, options)
  local minimum = clamp(number(options.minDb, number(options.min, -80)), -160, 24)
  local maximum = math.max(minimum + 1, clamp(number(options.maxDb, number(options.max, 0)), -120, 48))
  local logarithmic = flag(options.log, true)
  local function boundary(column)
    if column == canvas.width then return #bins end
    local ratio = column / canvas.width
    if logarithmic then return math.exp(ratio * math.log(#bins + 1)) - 1 end
    return ratio * #bins
  end
  for column = 0, canvas.width - 1 do
    local first = math.min(#bins, math.floor(boundary(column)) + 1)
    local last = clamp(math.floor(boundary(column + 1)), first, #bins)
    local peak = minimum
    -- Use the peak of each frequency group. A narrow peak stays visible after a resize.
    for index = first, last do peak = math.max(peak, bins[index]) end
    local height = math.floor(clamp((peak - minimum) / (maximum - minimum), 0, 1) * canvas.pixel_height + 0.5)
    if height > 0 then
      canvas:rect(column * 2, canvas.pixel_height - height, 2, height, "Type")
    end
  end
end

function M.render(canvas, kind, frame, options)
  if canvas.width < 1 or canvas.height < 1 then return end
  local samples = frame and frame[kind == "spectrum" and "spectrum" or "scope"]
  if not samples or #samples == 0 then
    canvas:text(0, math.floor((canvas.height - 1) / 2), "waiting for audio", "Comment")
    return
  end
  if kind == "spectrum" then spectrum(canvas, samples, options or {})
  else scope(canvas, samples, options or {}) end
end

return M
