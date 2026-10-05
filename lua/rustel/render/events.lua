local M = {}
local options = require("rustel.render.options")
local number, flag = options.number, options.flag
local tau = math.pi * 2
local notes = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function active(event, now) return event.start <= now and event.finish >= now end
local function group(event, now)
  return active(event, now) and "String" or (event.finish < now and "Comment" or "Type")
end
local function label(event)
  if not event.pitch then return event.label or "sound" end
  local pitch = math.floor(event.pitch + 0.5)
  return notes[pitch % 12 + 1] .. (math.floor(pitch / 12) - 1)
end

local function text_label(event, now)
  return (active(event, now) and event.active_label) or event.custom_label or label(event)
end

local function timing(event, state, now)
  local cps = state.cps or 0.5
  local cycle_now = state.cycle or now * cps
  return event.cycle or cycle_now + (event.start - now) * cps,
    event.cycle_end or cycle_now + (event.finish - now) * cps
end

local function roll(canvas, events, kind, opts, state, now)
  local cycles = number(opts, "cycles", 4, 0.25, 64)
  local playhead = number(opts, "playhead", 0.5, 0, 1)
  local cycle_now = state.cycle or now * (state.cps or 0.5)
  local begin = cycle_now - cycles * playhead
  local vertical = flag(opts, "vertical", kind == "wordfall")
  local labels = flag(opts, "labels", kind == "wordfall")
  local fold = flag(opts, "fold", true)
  local time_size = vertical and canvas.pixel_height or canvas.pixel_width
  local lane_size = vertical and canvas.pixel_width or canvas.pixel_height
  local lanes, indexes, shown = {}, {}, {}
  local low, high = math.huge, -math.huge
  for _, event in ipairs(events) do
    local first, last = timing(event, state, now)
    if last >= begin and first <= begin + cycles then
      shown[#shown + 1] = event
      local name = label(event)
      if not indexes[name] then
        indexes[name] = true
        lanes[#lanes + 1] = { label = name, pitch = event.pitch }
      end
      if event.pitch then low, high = math.min(low, event.pitch), math.max(high, event.pitch) end
    end
  end
  table.sort(lanes, function(a, b)
    if a.pitch and b.pitch then return a.pitch > b.pitch end
    if a.pitch or b.pitch then return a.pitch ~= nil end
    return a.label < b.label
  end)
  for i, lane in ipairs(lanes) do indexes[lane.label] = i - 1 end
  if low == math.huge then low, high = 24, 96 end
  low = number(opts, "minMidi", low - 1, -24, 144)
  high = math.max(low + 1, number(opts, "maxMidi", high + 1, -12, 168))
  local lane_height = math.max(1, lane_size / math.max(1, #lanes))
  -- Reverse an axis when vertical and the flip flag differ.
  local function time_at(time)
    local position = clamp((time - begin) / cycles, 0, 1)
    if vertical ~= flag(opts, "flipTime", false) then position = 1 - position end
    return position * (time_size - 1)
  end
  local text = {}
  for _, event in ipairs(shown) do
    if not flag(opts, "hideInactive", false) or active(event, now) then
      local first, last = timing(event, state, now)
      first, last = time_at(first), time_at(last)
      first, last = math.min(first, last), math.max(first, last)
      local lane = indexes[label(event)] * lane_height
      if not fold and event.pitch then lane = (1 - clamp((event.pitch - low) / (high - low), 0, 1)) * (lane_size - 2) end
      local thickness = active(event, now) and math.max(1, lane_height - 1) or 1
      if not fold then thickness = active(event, now) and 2 or 1 end
      if vertical ~= flag(opts, "flipValues", false) then
        lane = lane_size - lane - (fold and lane_height or thickness)
      end
      if vertical then
        canvas:rect(lane, first, thickness, math.max(1, last - first), group(event, now))
        if labels then text[#text + 1] = { math.floor(lane / 2), math.floor(first / 4), text_label(event, now) } end
      else
        canvas:rect(first, lane, math.max(1, last - first), thickness, group(event, now))
        if labels then text[#text + 1] = { math.floor(first / 2), math.floor(lane / 4), text_label(event, now) } end
      end
    end
  end
  local head = time_at(cycle_now)
  if vertical then canvas:line(0, head, canvas.pixel_width - 1, head, "Special")
  else canvas:line(head, 0, head, canvas.pixel_height - 1, "Special") end
  for _, entry in ipairs(text) do canvas:text(entry[1], entry[2], entry[3], "Normal") end
end

local function legend(canvas, events, now, side)
  local row, seen = 0, {}
  for _, event in ipairs(events) do
    local name = text_label(event, now)
    if active(event, now) and not seen[name] then
      canvas:text(math.floor(side / 2) + 1, row, name, "String")
      row, seen[name] = row + 1, true
    end
  end
end

local function spiral(canvas, events, opts, state, now)
  local stretch = number(opts, "stretch", 1, 0.1, 4)
  local inset = number(opts, "inset", 3, 0.5, 12)
  local steady = number(opts, "steady", 1, -4, 4)
  local padding = number(opts, "padding", 0, 0, 1)
  local cycle_now = state.cycle or now * (state.cps or 0.5)
  local side = math.min(canvas.pixel_width, canvas.pixel_height)
  local cx, cy, radius = side / 2, canvas.pixel_height / 2, side / 2 - 1
  local turns = (inset + 2) * stretch
  local function point(turn, offset)
    local r = math.max(0, radius * turn / turns + (offset or 0))
    local angle = tau * (turn + steady * cycle_now * stretch) - math.pi / 2
    return cx + r * math.cos(angle), cy + r * math.sin(angle)
  end
  local steps = math.ceil(turns * 32)
  for step = 0, steps, 2 do
    local x, y = point(turns * step / steps)
    canvas:point(x, y, "Comment")
  end
  for _, event in ipairs(events) do
    local cycle, finish = timing(event, state, now)
    finish = math.min(finish, cycle + (event.finish - event.start) * (state.cps or 0.5))
    if finish >= cycle_now - inset and cycle <= cycle_now + 2 then
      local first = clamp((cycle - cycle_now + inset) * stretch, 0, turns)
      local last = clamp((finish - padding - cycle_now + inset) * stretch, first, turns)
      local count = clamp(math.ceil((last - first) * 64), 1, 512)
      local x, y = point(first)
      for step = 1, count do
        local next_x, next_y = point(first + (last - first) * step / count)
        canvas:line(x, y, next_x, next_y, group(event, now))
        x, y = next_x, next_y
      end
    end
  end
  local x0, y0 = point(inset * stretch, -2)
  local x1, y1 = point(inset * stretch, 2)
  canvas:line(x0, y0, x1, y1, "Special")
  legend(canvas, events, now, side)
end

local function root_pitch(root)
  if type(root) == "number" and root > 0 then return 69 + 12 * math.log(root / 440) / math.log(2) end
  local letter, accidental = tostring(root or "c"):lower():match("^([a-g])([#b]?)")
  local pitches = { c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11 }
  return (pitches[letter] or 0) + (accidental == "#" and 1 or accidental == "b" and -1 or 0)
end

local function pitchwheel(canvas, events, opts, _, now)
  local edo = math.floor(number(opts, "edo", 12, 1, 96))
  local root = root_pitch(opts.root)
  local scale, latest_scale
  for _, event in ipairs(events) do
    if event.scale then
      latest_scale = event.scale
      if active(event, now) then scale = event.scale end
    end
  end
  scale = scale or latest_scale
  if scale then
    root = root_pitch(scale.root_hz)
    edo = math.floor(clamp(scale.edo or edo, 1, 96))
  end
  local side = math.min(canvas.pixel_width, canvas.pixel_height)
  local cx, cy, radius = side / 2, canvas.pixel_height / 2, math.max(0, side / 2 - 3)
  local function point(turn)
    local angle = turn * tau - math.pi / 2
    return cx + radius * math.cos(angle), cy + radius * math.sin(angle)
  end
  if flag(opts, "circle", false) then
    for step = 0, 96 do local x, y = point(step / 96); canvas:point(x, y, "Comment") end
  end
  for degree = 0, edo - 1 do local x, y = point(degree / edo); canvas:point(x, y, "Comment") end
  local sounding = {}
  for _, event in ipairs(events) do
    if event.pitch and active(event, now) then
      local turn = ((event.pitch - root) / 12) % 1
      local x, y = point(turn)
      if (opts.mode or "flake") == "flake" then canvas:line(cx, cy, x, y, "String") end
      if flag(opts, "hapcircles", true) then canvas:rect(x - 1, y - 1, 3, 3, "String") end
      sounding[#sounding + 1] = { turn = turn, x = x, y = y }
    end
  end
  if opts.mode == "polygon" and #sounding > 1 then
    table.sort(sounding, function(a, b) return a.turn < b.turn end)
    for i, entry in ipairs(sounding) do
      local next_entry = sounding[i % #sounding + 1]
      canvas:line(entry.x, entry.y, next_entry.x, next_entry.y, "String")
    end
  end
  legend(canvas, events, now, side)
end

function M.render(canvas, kind, events, opts, state, now)
  if kind == "spiral" then spiral(canvas, events, opts, state, now)
  elseif kind == "pitchwheel" then pitchwheel(canvas, events, opts, state, now)
  else roll(canvas, events, kind, opts, state, now) end
end

return M
