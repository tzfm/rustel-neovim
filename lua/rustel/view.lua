local M = {}
local api = vim.api
local canvas = require("rustel.render.canvas")
local options = require("rustel.render.options")
local events = require("rustel.render.events")
local audio = require("rustel.render.audio")
local anchors = require("rustel.anchors")
local ns = api.nvim_create_namespace("rustel.view")
local buf, shown, source, layout, last_snapshot, frame, group
local saved = {}

function M.close()
  if buf and api.nvim_buf_is_valid(buf) then
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    anchors.clear(buf)
  end
  buf, shown, source, layout = nil, false, nil, nil
  last_snapshot, frame = nil, nil
  saved = {}
  if group then api.nvim_del_augroup_by_id(group); group = nil end
end

function M.open(buffer, visible)
  if buf ~= buffer then
    M.close()
    buf = buffer
    group = api.nvim_create_augroup("rustel-view", { clear = true })
    api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
      group = group, buffer = buf, callback = M.close,
    })
  end
  shown = visible ~= false
end

function M.remember(snapshot)
  if not buf or not snapshot or snapshot == last_snapshot then return end
  last_snapshot = snapshot
  saved[#saved + 1] = anchors.capture(buf, snapshot)
  -- Keep the snapshot that is playing. Drop a different saved snapshot.
  if #saved > 8 then
    local oldest = saved[1] == source and 2 or 1
    anchors.forget(buf, table.remove(saved, oldest))
  end
end

local function virtual_lines(drawing)
  local lines, spans = drawing:finish()
  local result, index = {}, 1
  for row, line in ipairs(lines) do
    local chunks, last = {}, 0
    while spans[index] and spans[index].row == row - 1 do
      local span = spans[index]
      if span.first > last then chunks[#chunks + 1] = { line:sub(last + 1, span.first), "Normal" } end
      chunks[#chunks + 1] = { line:sub(span.first + 1, span.last), span.group }
      last, index = span.last, index + 1
    end
    if last < #line then chunks[#chunks + 1] = { line:sub(last + 1), "Normal" } end
    result[#result + 1] = chunks
  end
  return result
end

local function visual_audio(frame, slot)
  if not frame or slot == nil or frame.visuals == nil then return frame end
  for _, visual in ipairs(frame.visuals) do
    if visual.slot == slot then return visual end
  end
end

local function render(state, now)
  if not buf or not api.nvim_buf_is_valid(buf) then return end
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not shown or not source then return end
  local width
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local available = api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
    width = math.min(width or available, available)
  end
  if not width or width < 1 then return end
  local visuals = {}
  for _, visual in ipairs(layout or {}) do
    if visual.kind ~= "markcss" then visuals[#visuals + 1] = visual end
  end
  if #visuals == 0 then visuals[1] = { kind = "pianoroll" } end
  local panels = {}
  for _, visual in ipairs(visuals) do
    local row = anchors.row(buf, source, visual)
    if row then
      local drawing = canvas.new(width, 6)
      local opts = options.parse(visual.options)
      if visual.kind == "scope" or visual.kind == "tscope" or visual.kind == "spectrum" then
        local frame = anchors.matches(source, state.revision) and visual_audio(state.audio, visual.slot) or nil
        audio.render(drawing, visual.kind, frame, opts)
      else
        local selected = {}
        for _, event in ipairs(anchors.matches(source, state.revision) and state.events or {}) do
          if visual.slot == nil or (event.visual_slots and event.visual_slots[visual.slot]) then
            selected[#selected + 1] = event
          end
        end
        events.render(drawing, visual.kind, selected, opts, state, now)
      end
      panels[row] = panels[row] or {}
      panels[row][#panels[row] + 1] = { { "Rustel · " .. visual.kind, "Title" } }
      vim.list_extend(panels[row], virtual_lines(drawing))
    end
  end
  for row, lines in pairs(panels) do
    api.nvim_buf_set_extmark(buf, ns, row, 0, { virt_lines = lines })
  end
end

function M.draw(state, now, snapshot)
  if not buf or not api.nvim_buf_is_valid(buf) then return end
  if anchors.matches(snapshot, state.revision) then M.remember(snapshot) end
  for i = #saved, 1, -1 do
    local entry = saved[i]
    if anchors.matches(entry, state.revision) then source, layout = entry, state.visuals; break end
  end
  frame = { state = state, now = now }
  render(state, now)
end

function M.freeze()
  if frame then frame.state = vim.deepcopy(frame.state) end
end

function M.toggle(buffer)
  if buf ~= buffer then M.open(buffer); return end
  shown = not shown
  if not shown then api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  elseif frame then render(frame.state, frame.now) end
end

return M
