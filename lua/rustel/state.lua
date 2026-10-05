local protocol = require("rustel.protocol")
local M = {}
local finite = protocol.finite

local function rational(value)
  if type(value) ~= "string" then return nil end
  local numerator, denominator = value:match("^(-?%d+)/(%d+)$")
  if numerator and tonumber(denominator) > 0 then return tonumber(numerator) / tonumber(denominator) end
  return tonumber(value)
end

function M.new()
  return { events = {}, visuals = {}, generation = -1, cycle = 0, cps = 1 }
end

-- One generation ties the three player messages together.
--
--   layout -> visual positions and the source revision
--   events -> notes, mapped onto the editor clock
--   audio  -> samples for each visual slot
--
-- A new generation clears notes, visuals, audio, and the revision.
-- editor_time = device_time + offset
-- offset = the smallest (editor_now - device_time)
-- A backward device clock clears the current notes.
function M.ingest(state, message, now)
  local batch, layout, audio = message.ui_events, message.ui_layout, message.ui_audio
  local record = batch or layout or audio
  if type(record) ~= "table" then return end
  local version = audio and 1 or 2
  if record.version ~= version then return "Unsupported Rustel UI protocol; update Rustel and the Neovim plugin." end
  if not finite(record.generation) or record.generation < state.generation then return end
  if audio and not protocol.audio(audio) then return end
  if not audio and not protocol.revision(record.source_revision) then return end
  if record.generation > state.generation then
    state.generation = record.generation
    state.events, state.visuals, state.audio, state.revision = {}, {}, nil, nil
  end
  if layout then
    state.visuals = type(layout.visuals) == "table" and layout.visuals or {}
    state.revision = layout.source_revision
    state.audio = nil
    return
  end
  if not finite(record.device_time) or record.device_time < 0 then return end
  if audio then
    local previous = state.audio
    if state.revision and previous and previous.visuals and audio.visuals
      and audio.stream_id ~= nil and audio.stream_id == previous.stream_id
      and audio.epoch ~= nil and audio.epoch == previous.epoch then
      local slots = {}
      for _, visual in ipairs(audio.visuals) do slots[visual.slot] = true end
      for _, visual in ipairs(previous.visuals) do
        if not slots[visual.slot] then audio.visuals[#audio.visuals + 1] = visual end
      end
    end
    state.audio = audio
    return
  end
  if not finite(batch.cycle) or not finite(batch.cps) or batch.cps <= 0 or type(batch.events) ~= "table" then return end
  if state.device_time and batch.device_time < state.device_time then
    state.events, state.offset, state.audio = {}, nil, nil
  end
  state.device_time = batch.device_time
  local offset = math.min(state.offset or math.huge, now - batch.device_time)
  if state.offset and offset ~= state.offset then
    for _, event in ipairs(state.events) do
      event.start = event.start + offset - state.offset
      event.finish = event.finish + offset - state.offset
    end
  end
  state.offset = offset
  state.clock = batch.device_time + state.offset
  state.cycle, state.cps = batch.cycle, batch.cps
  for index, event in ipairs(batch.events) do
    if index > 256 then break end
    if type(event) == "table" and event.generation == state.generation
      and finite(event.target_time) and finite(event.duration_seconds) and event.duration_seconds > 0 then
      local pitch
      if finite(event.frequency_hz) and event.frequency_hz > 0 then
        pitch = 69 + 12 * math.log(event.frequency_hz / 440) / math.log(2)
      end
      state.events[#state.events + 1] = {
        start = event.target_time + state.offset,
        finish = event.target_time + state.offset + event.duration_seconds,
        cycle = rational(event.whole_begin), cycle_end = rational(event.whole_end),
        pitch = pitch, label = event.label or event.value or "sound", custom_label = event.label,
        active_label = event.active_label, color = event.color, scale = event.scale,
        visual_slots = protocol.slots(event.ui_visuals),
        revision = batch.source_revision,
        context = type(event.context) == "table" and event.context or {},
      }
    end
  end
  while #state.events > 1024 do table.remove(state.events, 1) end
end

function M.tick(state, now)
  for index = #state.events, 1, -1 do
    if state.events[index].finish < now - 8 then table.remove(state.events, index) end
  end
  return {
    events = state.events, visuals = state.visuals, audio = state.audio, revision = state.revision,
    cycle = state.cycle + (state.clock and now - state.clock or 0) * state.cps,
    cps = state.cps,
  }
end

return M
