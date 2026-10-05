local M = {}
local Canvas = {}
Canvas.__index = Canvas
local dots = { { 1, 2, 4, 64 }, { 8, 16, 32, 128 } }

function M.new(width, height)
  return setmetatable({ width = width, height = height, pixel_width = width * 2,
    pixel_height = height * 4, cells = {} }, Canvas)
end

function Canvas:point(x, y, group)
  x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  if x < 0 or y < 0 or x >= self.pixel_width or y >= self.pixel_height then return end
  local key = math.floor(y / 4) * self.width + math.floor(x / 2) + 1
  local cell = self.cells[key] or { bits = 0 }
  cell.bits = bit.bor(cell.bits, dots[x % 2 + 1][y % 4 + 1])
  cell.group = group or "String"
  self.cells[key] = cell
end

function Canvas:line(x0, y0, x1, y1, group)
  local steps = math.ceil(math.max(math.abs(x1 - x0), math.abs(y1 - y0)))
  if steps == 0 then self:point(x0, y0, group); return end
  for i = 0, steps do
    self:point(x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps, group)
  end
end

function Canvas:rect(x, y, width, height, group)
  local last_x = math.min(self.pixel_width - 1, math.ceil(x + width) - 1)
  local last_y = math.min(self.pixel_height - 1, math.ceil(y + height) - 1)
  for row = math.max(0, math.floor(y)), last_y do
    for column = math.max(0, math.floor(x)), last_x do self:point(column, row, group) end
  end
end

function Canvas:text(x, y, text, group)
  if y < 0 or y >= self.height then return end
  for _, char in ipairs(vim.fn.split(tostring(text):gsub("[%c]", " "), "\\zs")) do
    local width = vim.fn.strdisplaywidth(char)
    if x + width > self.width then break end
    if x >= 0 and width > 0 then
      local key = y * self.width + x + 1
      for i = key, key + width - 1 do
        local old = self.cells[i]
        local head = old and old.head or i
        local length = self.cells[head] and self.cells[head].width or 1
        for j = head, head + length - 1 do self.cells[j] = nil end
      end
      self.cells[key] = { text = char, bits = 0, width = width, group = group or "Comment" }
      for i = 1, width - 1 do self.cells[key + i] = { text = "", bits = 0, head = key } end
    end
    x = x + width
  end
end

function Canvas:finish()
  local lines, spans = {}, {}
  for row = 0, self.height - 1 do
    local parts, bytes = {}, 0
    for column = 0, self.width - 1 do
      local cell = self.cells[row * self.width + column + 1]
      local text = cell and (cell.text or vim.fn.nr2char(0x2800 + cell.bits)) or " "
      parts[#parts + 1] = text
      if cell and cell.group and #text > 0 then
        local previous = spans[#spans]
        if previous and previous.row == row and previous.last == bytes and previous.group == cell.group then
          previous.last = bytes + #text
        else
          spans[#spans + 1] = { row = row, first = bytes, last = bytes + #text, group = cell.group }
        end
      end
      bytes = bytes + #text
    end
    lines[#lines + 1] = table.concat(parts)
  end
  return lines, spans
end

return M
