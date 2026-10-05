vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local state = require("rustel.state")
local view = require("rustel.view")
local highlights = require("rustel.highlights")
local audio = require("rustel.render.audio")
local canvas = require("rustel.render.canvas")
local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
local source = { 'note("c3")._scope()', 'note("c6")._spectrum()', 'scope()', "" }
api.nvim_buf_set_lines(buf, 0, -1, false, source)
local snapshot = highlights.snapshot(buf)
local current = state.new()

local function values(value)
  local result = {}
  for index = 1, 512 do result[index] = value end
  return result
end

local function tap(slot, scope, spectrum)
  return { slot = slot, scope = values(scope), spectrum = values(spectrum) }
end

local function frame(generation)
  return {
    version = 1, generation = generation or 1, device_time = 1, sample_rate = 48000,
    stream_id = 10, epoch = 1,
    scope = values(0), spectrum = values(-120),
    visuals = { tap(0, 0.75, -60), tap(63, -0.75, -10) },
  }
end

local function layout(generation)
  state.ingest(current, { ui_layout = {
    version = 2, generation = generation or 1, source_revision = snapshot.revision,
    visuals = {
      { kind = "scope", inline = true, slot = 0, to = snapshot.starts[1] + #source[1] },
      { kind = "spectrum", inline = true, slot = 63, to = snapshot.starts[2] + #source[2] },
      { kind = "scope", inline = true, to = snapshot.starts[3] + #source[3] },
    },
  } }, 1)
end

local function panels(redraw)
  if redraw ~= false then view.draw(state.tick(current, 1), 1, snapshot) end
  local result = {}
  local ns = api.nvim_create_namespace("rustel.view")
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local lines = {}
    for index, line in ipairs(mark[4].virt_lines) do
      if index > 1 then
        local chunks = {}
        for _, chunk in ipairs(line) do chunks[#chunks + 1] = chunk[1] end
        lines[#lines + 1] = table.concat(chunks)
      end
    end
    result[#result + 1] = table.concat(lines, "\n")
  end
  return result
end

local function expected(kind, data)
  local width = api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
  local drawing = canvas.new(width, 6)
  audio.render(drawing, kind, data)
  return table.concat(drawing:finish(), "\n")
end

view.open(buf)
layout()
local playing = frame()
state.ingest(current, { ui_audio = playing }, 1)
local shown = panels()
assert(#shown == 3)
assert(shown[1] == expected("scope", playing.visuals[1]) and shown[1] ~= expected("scope", playing),
  "scope must use its own lane's samples")
assert(shown[2] == expected("spectrum", playing.visuals[2]) and shown[2] ~= expected("spectrum", playing),
  "spectrum must use its own lane's bins, including slot 63")
assert(shown[3] == expected("scope", playing), "slotless audio views must use the master mix")

local missing = frame()
missing.visuals = { tap(63, -0.5, -30) }
state.ingest(current, { ui_audio = missing }, 1)
shown = panels()
assert(shown[1] == expected("scope", playing.visuals[1]), "temporarily missing slots must hold their last audio")
assert(shown[2] == expected("spectrum", missing.visuals[1]) and shown[2] ~= expected("spectrum", playing.visuals[2]),
  "fresh lane audio must replace its previous frame")
local held = shown
missing = frame()
missing.visuals = {}
state.ingest(current, { ui_audio = missing }, 1)
shown = panels()
assert(shown[1] == held[1] and shown[2] == held[2], "empty capture must retain known slots within the same stream")
assert(shown[3] == expected("scope", missing), "empty visual capture must still permit the master view")

layout()
missing = frame()
missing.visuals = { missing.visuals[2] }
state.ingest(current, { ui_audio = missing }, 1)
shown = panels()
assert(shown[1]:find("waiting for audio", 1, true), "replaced layouts must not retain old taps or use the master")
assert(shown[2] == expected("spectrum", missing.visuals[1]), "available taps must work after a layout replacement")

for _, reset in ipairs({
  function(data) data.stream_id = 11 end,
  function(data) data.epoch = 2 end,
  function(data) data.stream_id = nil end,
  function(data) data.epoch = nil end,
}) do
  state.ingest(current, { ui_audio = frame() }, 1)
  missing = frame()
  missing.visuals = {}
  reset(missing)
  state.ingest(current, { ui_audio = missing }, 1)
  shown = panels()
  assert(shown[1]:find("waiting for audio", 1, true) and shown[2]:find("waiting for audio", 1, true),
    "changed or unknown streams and epochs must discard held taps")
  assert(shown[3] == expected("scope", missing), "stream resets must still permit the master view")
end

local legacy = frame()
legacy.visuals = nil
state.ingest(current, { ui_audio = legacy }, 1)
shown = panels()
assert(shown[1] == expected("scope", legacy) and shown[2] == expected("spectrum", legacy),
  "older runtimes without visual capture must retain the master fallback")

state.ingest(current, { ui_audio = playing }, 1)
for _, corrupt in ipairs({
  function(data) data.visuals = false end,
  function(data) data.visuals = { unexpected = true } end,
  function(data) data.visuals = { [2] = data.visuals[2] } end,
  function(data) data.visuals[2].slot = 0 end,
  function(data) data.visuals[1].slot = -1 end,
  function(data) data.visuals[1].slot = 64 end,
  function(data) data.visuals[1].slot = 0.5 end,
  function(data) data.visuals[1].slot = "0" end,
  function(data) data.visuals[1].slot = 0 / 0 end,
  function(data) data.visuals[1].scope[512] = nil end,
  function(data) data.visuals[1].spectrum[512] = math.huge end,
  function(data) data.visuals[1].scope[200] = 0 / 0 end,
  function(data) data.scope[512] = nil end,
  function(data) data.sample_rate = 0 end,
  function(data) data.device_time = -1 end,
  function(data)
    data.visuals = {}
    for slot = 0, 64 do data.visuals[#data.visuals + 1] = tap(slot, 0, -120) end
  end,
}) do
  local invalid = frame(2)
  corrupt(invalid)
  state.ingest(current, { ui_audio = invalid }, 1)
  assert(current.audio == playing and current.generation == 1 and current.revision == snapshot.revision,
    "malformed audio must not replace the current audio or advance the generation")
end

local next_frame = frame(2)
next_frame.visuals = {}
state.ingest(current, { ui_audio = next_frame }, 1)
shown = panels()
assert(shown[1]:find("waiting for audio", 1, true) and shown[2]:find("waiting for audio", 1, true),
  "new audio arriving before its layout must not attach to old rows")
state.ingest(current, { ui_audio = playing }, 1)
assert(current.audio == next_frame, "older generations must not restore stale audio")
assert(#current.audio.visuals == 0, "new generations must not retain old taps")

source[1] = 'note("d3")._scope()'
api.nvim_buf_set_lines(buf, 0, -1, false, source)
snapshot = highlights.snapshot(buf)
layout(2)
assert(current.audio == nil, "replacing a layout must discard audio captured before that layout")
state.ingest(current, { ui_audio = playing }, 1)
assert(current.audio == nil, "old audio must not bind to the replacement layout")
next_frame = frame(2)
state.ingest(current, { ui_audio = next_frame }, 1)
shown = panels()
assert(shown[1] == expected("scope", next_frame.visuals[1]), "the new layout must accept matching audio")

view.freeze()
next_frame.visuals[1].scope = values(-1)
state.ingest(current, { ui_audio = frame(3) }, 1)
view.toggle(buf)
assert(#panels(false) == 0)
view.toggle(buf)
assert(vim.deep_equal(panels(false), shown), "frozen lane audio must survive new data and visibility toggles")
view.close()
print("lanes: ok")
