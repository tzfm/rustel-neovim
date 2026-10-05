vim.opt.runtimepath:prepend(vim.fn.getcwd())
local api = vim.api
local view = require("rustel.view")
local highlights = require("rustel.highlights")
local ns = api.nvim_create_namespace("rustel.view")
local buf, win = api.nvim_get_current_buf(), api.nvim_get_current_win()
local source = {
  "// é", '$: note("c4")._scope()', "", '$: note("e4")',
  "  ._pianoroll({ labels: true })", "// end", "",
}
api.nvim_buf_set_lines(buf, 0, -1, false, source)
vim.bo[buf].fileformat = "dos"
vim.bo[buf].bomb = true
vim.bo[buf].modified = false
local snapshot = highlights.snapshot(buf)
local tick = api.nvim_buf_get_changedtick(buf)
local function endpoint(row) return snapshot.starts[row] + #source[row] end
local function marks() return api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true }) end
local function text(lines)
  local result = {}
  for _, line in ipairs(lines) do
    local chunks = {}
    for _, chunk in ipairs(line) do chunks[#chunks + 1] = chunk[1] end
    result[#result + 1] = table.concat(chunks)
  end
  return table.concat(result, "\n")
end
local function screen()
  vim.cmd("redraw")
  local lines = {}
  for row = 1, api.nvim_win_get_height(win) do
    local cells = {}
    for column = 1, api.nvim_win_get_width(win) do cells[#cells + 1] = vim.fn.screenstring(row, column) end
    lines[#lines + 1] = table.concat(cells)
  end
  return table.concat(lines, "\n")
end
local state = {
  revision = snapshot.revision, cycle = 5, cps = 0.5,
  visuals = {
    { kind = "scope", inline = true, slot = 0, to = endpoint(2) },
    { kind = "pianoroll", inline = true, slot = 63, to = endpoint(5), options = "{labels: true}" },
  },
  events = {
    { start = 8, finish = 8.5, pitch = 60, visual_slots = { [63] = true } },
    { start = 9.8, finish = 10.2, pitch = 64, visual_slots = { [63] = true } },
    { start = 11.5, finish = 14, label = "drum\n音", visual_slots = { [63] = true } },
    { start = 9, finish = 11, label = "excluded", visual_slots = { [0] = true } },
  },
  audio = { scope = {}, spectrum = {} },
}
for i = 1, 512 do state.audio.scope[i], state.audio.spectrum[i] = math.sin(i / 8), -40 end
view.open(buf)
view.open(buf)
view.draw(state, 10, snapshot)
local drawn = marks()
assert(#drawn == 2, "both lanes must have an inline visual")
assert(drawn[1][2] == 1 and drawn[2][2] == 4, "visuals must sit under their calls, including Unicode/CRLF/BOM sources")
assert(text(drawn[1][4].virt_lines):find("scope", 1, true))
local roll = text(drawn[2][4].virt_lines)
assert(roll:find("pianoroll", 1, true) and roll:find("C4", 1, true) and roll:find("E4", 1, true))
assert(roll:find("drum 音", 1, true), "inline chunks must preserve Unicode labels")
assert(not roll:find("excluded", 1, true), "each lane must retain its event selection")
local visible = screen()
assert(visible:find("Rustel · scope", 1, true) and visible:find("Rustel · pianoroll", 1, true),
  "both lane visuals must appear in the editor viewport together")
assert(#api.nvim_list_wins() == 1 and api.nvim_get_current_win() == win, "visuals must not open or focus a window")
assert(api.nvim_buf_get_changedtick(buf) == tick and not vim.bo[buf].modified)
assert(vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), source), "visuals must never enter score text")

local function redraw() view.draw(state, 10, highlights.snapshot(buf)); return marks() end
local function edit(first_row, first_col, last_row, last_col, replacement)
  vim.cmd("let &g:undolevels = &g:undolevels")
  api.nvim_buf_set_text(buf, first_row, first_col, last_row, last_col, replacement)
end
edit(0, 0, 0, 0, { "// draft", "" })
drawn = redraw()
assert(#drawn == 2 and drawn[1][2] == 2 and drawn[2][2] == 5, "both visuals must follow unsaved inserted lines")
for _ = 1, 5 do redraw() end
vim.cmd("undo")
drawn = redraw()
assert(drawn[1][2] == 1 and drawn[2][2] == 4, "redraws must preserve anchor undo positions")
vim.cmd("redo")
drawn = redraw()
assert(drawn[1][2] == 2 and drawn[2][2] == 5, "redo must move both anchors again")
vim.cmd("undo")

edit(1, #source[2], 1, #source[2], { "", "" })
drawn = redraw()
assert(drawn[1][2] == 1 and drawn[2][2] == 5, "a newline after a call must leave its own visual attached")
view.toggle(buf)
assert(#redraw() == 0)
view.toggle(buf)
assert(#redraw() == 2, "toggling back on while dirty must retain the anchors")
vim.cmd("undo")

edit(1, 0, 2, 0, {})
assert(#redraw() == 2, "deleting a call must keep its playing visual until reload")
vim.cmd("undo")
drawn = redraw()
assert(drawn[1][2] == 1 and drawn[2][2] == 4, "undo must restore a deleted call's visual")

api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
redraw()
api.nvim_buf_set_lines(buf, 0, -1, false, source)
drawn = redraw()
assert(drawn[1][2] == 1 and drawn[2][2] == 4, "pasting identical source must replace collapsed anchors")

state.visuals = {}
for _, kind in ipairs({ "pianoroll", "punchcard", "wordfall", "spiral", "pitchwheel", "scope", "tscope", "spectrum", "markcss" }) do
  state.visuals[#state.visuals + 1] = { kind = kind, inline = true, to = endpoint(5) }
end
view.draw(state, 10, snapshot)
drawn = marks()
assert(#drawn == 1 and #drawn[1][4].virt_lines == 56, "same-line views must coexist; markcss stays in source highlighting")
for i = 1, 8 do
  assert(text({ drawn[1][4].virt_lines[(i - 1) * 7 + 1] }):find(state.visuals[i].kind, 1, true))
end
vim.cmd("normal! 50" .. api.nvim_replace_termcodes("<C-e>", true, false, true))
assert(screen():find("Rustel · spectrum", 1, true), "tall inline views must be reachable by scrolling")

vim.wo.number = true
for _, columns in ipairs({ 60, 24, 12 }) do
  vim.o.columns = columns
  view.draw(state, 10, snapshot)
  local width = api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
  for i, line in ipairs(marks()[1][4].virt_lines) do
    if (i - 1) % 7 ~= 0 then
      assert(vim.fn.strdisplaywidth(text({ line })) == width, "drawings must fit beside the source gutter")
    end
  end
end
state.visuals = {}
view.draw(state, 10, snapshot)
assert(#marks() == 1 and marks()[1][2] == #source - 2, "fallback roll belongs before trailing blank lines")
state.visuals = { { kind = "scope", inline = false, to = endpoint(2) } }
view.draw(state, 10, snapshot)
assert(marks()[1][2] == #source - 2, "global visuals belong before trailing blank lines")
state.visuals = { { kind = "scope", inline = true, to = snapshot.bytes + 1 } }
view.draw(state, 10, snapshot)
assert(#marks() == 0, "invalid source ranges must not create misplaced visuals")
state.visuals = {}
state.revision = string.rep("0", 64)
view.draw(state, 10, snapshot)
assert(#marks() == 0, "a stale layout must not attach to edited text")
state.revision = snapshot.revision
view.draw(state, 10, snapshot)
view.toggle(buf)
assert(#marks() == 0, "toggle must hide all virtual lines")
view.draw(state, 11, snapshot)
assert(#marks() == 0, "refresh must respect hidden visuals")
view.toggle(buf)
view.draw(state, 11, snapshot)
assert(#marks() == 1, "toggle must restore visuals")
view.close()
view.close()
assert(#marks() == 0 and api.nvim_buf_is_valid(buf), "close must clear only the decorations")
assert(#api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("rustel.anchors"), 0, -1, {}) == 0,
  "close must also release hidden source anchors")

source = { '$: note("c4")._scope()._pianoroll()', "" }
api.nvim_buf_set_lines(buf, 0, -1, false, source)
snapshot = highlights.snapshot(buf)
local split = assert(source[1]:find("._pianoroll", 1, true)) - 1
state.revision = snapshot.revision
state.visuals = {
  { kind = "scope", inline = true, to = snapshot.starts[1] + split },
  { kind = "pianoroll", inline = true, to = snapshot.starts[1] + #source[1] },
}
view.open(buf)
assert(#redraw() == 1)
edit(0, split, 0, split, { "", "" })
drawn = redraw()
assert(#drawn == 2 and drawn[1][2] == 0 and drawn[2][2] == 1,
  "splitting calls onto separate lines must split their panels")
vim.cmd("undo")
drawn = redraw()
assert(#drawn == 1 and #drawn[1][4].virt_lines == 14, "undo must regroup the panels")
for i = 1, 16 do
  api.nvim_buf_set_lines(buf, 1, -1, false, { "// pending " .. i })
  view.remember(highlights.snapshot(buf))
end
assert(#redraw() == 1, "pending saves must not discard the playing layout's anchors")
local hidden = api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("rustel.anchors"), 0, -1, {})
assert(#hidden <= 8 * 4, "pending source captures must stay bounded")
view.close()
print("view tests passed")
