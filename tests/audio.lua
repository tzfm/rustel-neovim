vim.opt.runtimepath:prepend(vim.fn.getcwd())
local audio = require("rustel.render.audio")
local canvas = require("rustel.render.canvas")

local function values(value)
  local result = {}
  for index = 1, 512 do result[index] = type(value) == "function" and value(index) or value end
  return result
end

local function render(kind, frame, options, width, height)
  local surface = canvas.new(width or 32, height or 8)
  audio.render(surface, kind, frame, options)
  local lines = surface:finish()
  local pixels = {}
  local dots = { { 1, 2, 4, 64 }, { 8, 16, 32, 128 } }
  for row, line in ipairs(lines) do
    assert(vim.fn.strdisplaywidth(line) == surface.width, "audio rows must fit the view")
    for column, code in ipairs(vim.fn.str2list(line, true)) do
      if code >= 0x2800 and code <= 0x28ff then
        for x = 0, 1 do
          for y = 0, 3 do
            if bit.band(code - 0x2800, dots[x + 1][y + 1]) ~= 0 then
              pixels[((row - 1) * 4 + y) * surface.pixel_width + (column - 1) * 2 + x] = true
            end
          end
        end
      end
    end
  end
  local function point(x, y) return pixels[y * surface.pixel_width + x] == true end
  return lines, point, vim.tbl_count(pixels)
end

local wave = values(function(index) return 0.7 * math.sin(index * math.pi / 32) end)
local frame = { scope = wave, spectrum = values(-120) }
local lines, _, count = render("scope", frame)
assert(count > 64, "a waveform must have visible vertical detail")
assert(vim.deep_equal(lines, render("tscope", frame)), "tscope must use the runtime scope data")

local _, point, silence = render("scope", { scope = values(0) })
assert(silence == 64 and point(0, 16) and point(63, 16), "silence must draw a centered flat trace")
local _, quiet = render("scope", { scope = values(0.25) }, { fit = false })
local _, fitted = render("scope", { scope = values(0.25) })
local _, scaled = render("scope", { scope = values(0.25) }, { scale = 2 })
assert(quiet(1, 12) and fitted(1, 2) and scaled(1, 8), "fit and explicit scale must affect trace amplitude")
local _, position = render("scope", { scope = values(0) }, { pos = 0.25 })
assert(position(1, 8), "pos must move the baseline")
local _, logarithmic = render("scope", { scope = values(0.1) }, { scale = 1, log = true })
assert(logarithmic(1, 6), "log scope must show low-amplitude detail")

local falling = { scope = values(function(index) return index < 101 and 0.8 or -0.8 end) }
local _, aligned = render("scope", falling, { fit = false })
local _, unaligned = render("scope", falling, { fit = false, align = false })
assert(aligned(0, 28) and unaligned(0, 4), "scope must align to a falling trigger crossing")
assert(not aligned(63, 28) and unaligned(63, 28), "alignment must retain the original time scale")

local _, _, empty = render("spectrum", { spectrum = values(-120) })
local _, half, half_count = render("spectrum", { spectrum = values(-40) })
local _, full, full_count = render("spectrum", { spectrum = values(0) })
assert(empty == 0, "silent spectrum must be empty")
assert(half_count * 2 == full_count and half(0, 16) and not half(0, 15) and full(0, 0),
  "spectrum input is already in dB and must scale linearly between display limits")

local bins = values(-120)
bins[512] = 0
for _, width in ipairs({ 1, 7, 32, 80 }) do
  local _, peak = render("spectrum", { spectrum = bins }, nil, width, 3)
  assert(peak(width * 2 - 1, 0), "the final frequency bin must survive logarithmic resize")
end
bins[512], bins[32] = -120, 0
local _, linear = render("spectrum", { spectrum = bins }, { log = false })
local _, log = render("spectrum", { spectrum = bins })
assert(linear(2, 0) and log(34, 0), "log frequency spacing must give lower frequencies more room")
local _, limited = render("spectrum", { spectrum = values(-40) }, { minDb = -40, maxDb = -20 })
assert(not limited(0, 31), "spectrum limits must control the noise floor")

local waiting = render("spectrum", { scope = wave })
assert(table.concat(waiting):find("waiting for audio", 1, true), "missing spectrum must wait for audio")
for _, kind in ipairs({ "scope", "tscope", "spectrum" }) do
  render(kind, frame, nil, 1, 1)
  render(kind, nil, nil, 1, 1)
  render(kind, frame, nil, 0, 0)
end
print("audio: ok")
