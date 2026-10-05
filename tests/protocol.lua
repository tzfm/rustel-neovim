vim.opt.runtimepath:prepend(vim.fn.getcwd())
local protocol = require("rustel.protocol")
local state = require("rustel.state")
local highlights = require("rustel.highlights")

local messages, plain = {}, {}
local stream = protocol.stream(function(message) messages[#messages + 1] = message end,
  function(line) plain[#plain + 1] = line end)
stream({ '{"ui_events":', '{"ui_visuals":9223372036854775809}}', "bad JSON", '{"par' })
assert(#messages == 0)
assert(#plain == 3)
stream({ 't":true}', "", '{"ui_visuals":9223372036854775809}', "" })
assert(messages[1].part == true)
local slots = protocol.slots(messages[2].ui_visuals)
assert(slots[0] and slots[63] and not slots[1] and not slots[62], "64-bit slots lost precision")
stream({ string.rep("x", 4 * 1024 * 1024 + 1) })
stream({ "discard", '{"recovered":true}', "" })
assert(messages[3].recovered, "decoder failed to recover after an oversized line")

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "// é", 'note("c4")' })
vim.bo[buf].fileformat = "dos"
vim.bo[buf].bomb = true
vim.bo[buf].endofline = false
local snapshot = highlights.snapshot(buf)
local bytes = '\239\187\191// é\r\nnote("c4")'
assert(snapshot.revision == vim.fn.sha256(bytes), "CRLF/BOM source hash mismatch")
local from = assert(bytes:find("c4", 1, true)) - 1
local event = {
  revision = snapshot.revision, start = 1, finish = 3,
  context = { { from, from + 2 }, { from, from + 2 }, { 0, 999 } },
}
highlights.draw(buf, snapshot, { event }, 2)
local ns = vim.api.nvim_get_namespaces()["rustel-active"]
local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
assert(#marks == 1 and marks[1][2] == 1 and marks[1][3] == 6 and marks[1][4].end_col == 8)
highlights.draw(buf, snapshot, { event }, 4)
assert(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0)
event.finish = event.start + 0.001
highlights.draw(buf, snapshot, { event }, event.start + 0.02)
assert(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 1, "short notes must remain visible for one frame")

local path = vim.fn.tempname() .. ".strudel"
vim.fn.writefile({ 'note("c4")' }, path, "b")
vim.cmd("edit " .. vim.fn.fnameescape(path))
local saved = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(saved, 0, -1, false, { 'note("e4")' })
vim.cmd("silent update")
local saved_bytes = table.concat(vim.fn.readfile(path, "b"), "\n")
local written = highlights.snapshot(saved)
local revision_after_save = vim.fn.sha256(saved_bytes)
assert(revision_after_save == written.revision or revision_after_save == written.written_revision,
  "saved files without an original final newline must match the playing revision")
highlights.draw(saved, written, { {
  revision = revision_after_save, start = 0, finish = 1, context = { { 6, 8 } },
} }, 0.5)
assert(#vim.api.nvim_buf_get_extmarks(saved, ns, 0, -1, {}) == 1)
vim.fn.delete(path)

local current = state.new()
local revision = string.rep("a", 64)
local function batch(generation, device_time, events)
  return { ui_events = {
    version = 2, generation = generation, source_revision = revision,
    cycle = device_time, device_time = device_time, cps = 1, events = events or {},
  } }
end
state.ingest(current, batch(1, 10, { {
  generation = 1, target_time = 11, duration_seconds = 0.5, frequency_hz = 440,
  whole_begin = "11/1", whole_end = "23/2", ui_visuals = "9223372036854775809",
} }), 100)
assert(current.events[1].start == 101 and current.events[1].pitch == 69)
assert(current.events[1].cycle_end == 11.5 and current.events[1].visual_slots[63])
assert(state.tick(current, 100.5).cycle == 10.5)
assert(state.tick(current, 100.5).revision == nil, "events must wait for layout anchor revision")
state.ingest(current, { ui_layout = {
  version = 2, generation = 1, source_revision = revision, visuals = { { kind = "scope", from = 0, to = 10 } },
} }, 100.5)
assert(state.tick(current, 100.5).revision == revision)
state.ingest(current, batch(1, 10.1), 100.01)
assert(math.abs(current.events[1].start - 100.91) < 0.000001,
  "retained events must follow the recovered device clock")
assert(math.abs(current.events[1].finish - 101.41) < 0.000001)
assert(math.abs(state.tick(current, 100.91).cycle - 11) < 0.000001)
state.ingest(current, batch(0, 11), 101)
assert(current.generation == 1 and #current.events == 1, "accepted an older generation")
state.ingest(current, batch(2, 12), 102)
assert(#current.events == 0, "new generation retained old events")
assert(state.tick(current, 102).revision == nil and #current.visuals == 0,
  "new generation retained stale visual anchors")
state.ingest(current, { ui_layout = {
  version = 2, generation = 1, source_revision = revision, visuals = {},
} }, 102)
assert(current.revision == nil, "older layout restored stale anchors")
local next_revision = string.rep("b", 64)
state.ingest(current, { ui_layout = {
  version = 2, generation = 2, source_revision = next_revision, visuals = {},
} }, 102)
assert(state.tick(current, 102).revision == next_revision, "empty layout lost its source revision")
state.ingest(current, { ui_layout = {
  version = 2, generation = 2, source_revision = "invalid", visuals = {},
} }, 102)
assert(current.revision == next_revision, "invalid layout replaced the accepted revision")
state.ingest(current, batch(2, 0), 103)
assert(current.offset == 103, "device clock reset was not handled")
local audio = {
  version = 1, generation = 2, device_time = 0, sample_rate = 48000,
  scope = {}, spectrum = {},
}
for index = 1, 512 do audio.scope[index], audio.spectrum[index] = 0, -120 end
state.ingest(current, { ui_audio = audio }, 103)
assert(current.audio == audio)
state.ingest(current, { ui_audio = { version = 1, generation = 2, device_time = 0, sample_rate = 48000 } }, 103)
assert(current.audio == audio, "incomplete audio frame replaced a valid one")
audio.generation = 3
state.ingest(current, { ui_audio = audio }, 104)
assert(state.tick(current, 104).revision == nil, "new audio generation retained stale anchors")
assert(state.ingest(current, { ui_events = { version = 99 } }, 104):find("protocol"))
print("protocol: ok")
vim.cmd("qa!")
