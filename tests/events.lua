vim.opt.runtimepath:prepend(vim.fn.getcwd())
local Canvas = require("rustel.render.canvas")
local render = require("rustel.render.events").render
local options = require("rustel.render.options")

local opts = options.parse([[{cycles: 4, 'labels': true, mode: 'polygon', "root": "c#", scale: 1/2, fit: false}]])
assert(opts.cycles == 4 and opts.labels and opts.mode == "polygon" and opts.root == "c#")
assert(opts.fit == false and opts.scale == nil, "only literal option values are accepted")
assert(options.number({ cycles = math.huge }, "cycles", 4, 1, 16) == 4)

local canvas = Canvas.new(2, 1)
canvas:point(0, 0)
canvas:point(1, 3)
local lines, spans = canvas:finish()
assert(lines[1] == vim.fn.nr2char(0x2881) .. " ", "Braille dot positions must be correct")
assert(spans[1].first == 0 and spans[1].last == 3, "highlights use UTF-8 byte offsets")
canvas:text(0, 0, "音")
canvas:text(1, 0, "x")
assert(canvas:finish()[1] == " x", "overlapping text must clear whole wide glyphs")

local events = {
  { start = 9.8, finish = 10.5, pitch = 60, custom_label = "note", active_label = "playing" },
  { start = 10.5, finish = 11.5, pitch = 67, label = "sine" },
  { start = 9.0, finish = 9.1, label = "kick" },
}
local state = { cycle = 5, cps = 0.5 }
local function draw(kind, list, settings, width, height)
  local drawing = Canvas.new(width or 40, height or 8)
  render(drawing, kind, list or events, settings or {}, state, 10)
  local rows, highlights = drawing:finish()
  for _, row in ipairs(rows) do
    assert(vim.fn.strdisplaywidth(row) == drawing.width, "drawing must fit its width")
  end
  return table.concat(rows, "\n"), highlights
end

for _, kind in ipairs({ "pianoroll", "punchcard", "wordfall", "spiral", "pitchwheel" }) do
  for _, width in ipairs({ 1, 7, 40 }) do draw(kind, events, {}, width, 8) end
end
assert(draw("pianoroll") == draw("punchcard"), "Rustel uses the same roll for both kinds")
assert(draw("pianoroll", events, { labels = true }):find("playing", 1, true), "active labels override note labels")
assert(draw("pianoroll", { events[2] }, { labels = true }):find("G4", 1, true), "note labels fall back to pitches")
local _, flipped = draw("pianoroll", { events[1] }, { fold = false, flipValues = true })
local found = false
for _, span in ipairs(flipped) do found = found or span.group == "String" end
assert(found, "flipped unfolded single notes must remain visible")
assert(draw("pitchwheel", { events[2] }) == draw("pitchwheel", {}), "future notes must not sound on the wheel")
assert(draw("pitchwheel", { events[1] }) ~= draw("pitchwheel", {}), "sounding notes must appear on the wheel")
local resting = { start = 8, finish = 9, pitch = 60, scale = { edo = 19, root_hz = 261.6256 } }
assert(draw("pitchwheel", { resting }) == draw("pitchwheel", {}, { edo = 19 }),
  "the latest tuning must remain on the wheel during rests")
assert(draw("pitchwheel", { resting }) ~= draw("pitchwheel", {}), "resting tuning must differ from the default")
local sounding = { start = 9.8, finish = 10.5, pitch = 64, scale = { edo = 24, root_hz = 440 } }
assert(draw("pitchwheel", { sounding, resting }) == draw("pitchwheel", { sounding }),
  "an active tuning must take priority over a later inactive event")
assert(draw("spiral", events) ~= draw("spiral", {}), "spiral must render note arcs")
assert(draw("pianoroll", events) ~= draw("pianoroll", events, { flipTime = true }), "time direction must affect placement")
local _, vertical = draw("wordfall", {}, {})
for _, span in ipairs(vertical) do
  if span.group == "Special" then assert(span.row == 4, "wordfall playhead crosses the pane") end
end
print("event renderer tests passed")
