local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("rustel-active")

function M.snapshot(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local separator = ({ unix = "\n", dos = "\r\n", mac = "\r" })[vim.bo[buf].fileformat]
  local bom = vim.bo[buf].bomb and "\239\187\191" or ""
  local text = bom .. table.concat(lines, separator)
  if vim.bo[buf].endofline then text = text .. separator end
  local starts, offset = {}, #bom
  for index, line in ipairs(lines) do
    starts[index], offset = offset, offset + #line + #separator
  end
  local written_revision
  if not vim.bo[buf].endofline and vim.bo[buf].fixendofline and not vim.bo[buf].binary then
    -- A write can add a final newline and leave 'endofline' unchanged.
    written_revision = vim.fn.sha256(text .. separator)
  end
  return { revision = vim.fn.sha256(text), written_revision = written_revision,
    lines = lines, starts = starts, bytes = #text }
end

function M.clear(buf)
  if api.nvim_buf_is_valid(buf) then api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
end

function M.draw(buf, snapshot, events, now)
  M.clear(buf)
  if not snapshot then return end
  local seen = {}
  for _, event in ipairs(events) do
    local matches = event.revision == snapshot.revision or event.revision == snapshot.written_revision
    if matches and event.start <= now and math.max(event.finish, event.start + 0.035) > now then
      for _, range in ipairs(event.context) do
        local first, last = range[1], range[2]
        if type(first) == "number" and type(last) == "number"
          and first >= 0 and first < last and last <= snapshot.bytes then
          for row, start in ipairs(snapshot.starts) do
            local from = math.max(first, start) - start
            local to = math.min(last - start, #snapshot.lines[row])
            local key = row .. ":" .. from .. ":" .. to
            if from < to and not seen[key] then
              seen[key] = true
              api.nvim_buf_set_extmark(buf, ns, row - 1, from, {
                end_row = row - 1, end_col = to, hl_group = "RustelActive", priority = 200,
              })
            end
            if start >= last then break end
          end
        end
      end
    end
  end
end

return M
