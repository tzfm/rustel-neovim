local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("rustel.anchors")

function M.matches(source, revision)
  return source and revision and (source.revision == revision or source.written_revision == revision)
end

function M.capture(buf, snapshot)
  local source = { revision = snapshot.revision, written_revision = snapshot.written_revision, marks = {} }
  local function mark(row, column)
    return api.nvim_buf_set_extmark(buf, ns, row - 1, column, { right_gravity = false })
  end
  -- A visual range ends on the character after the closing ")".
  for row, line in ipairs(snapshot.lines) do
    for column in line:gmatch("()%)") do
      source.marks[snapshot.starts[row] + column] = mark(row, column)
    end
  end
  local row = #snapshot.lines
  while row > 1 and snapshot.lines[row]:match("^%s*$") do row = row - 1 end
  source.last = mark(row, #snapshot.lines[row])
  return source
end

function M.row(buf, source, visual)
  local id = source.last
  if visual.inline then id = source.marks[visual.to] end
  if id then return api.nvim_buf_get_extmark_by_id(buf, ns, id, {})[1] end
end

function M.forget(buf, source)
  for _, id in pairs(source.marks) do api.nvim_buf_del_extmark(buf, ns, id) end
  api.nvim_buf_del_extmark(buf, ns, source.last)
end

function M.clear(buf)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

return M
