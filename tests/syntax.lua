vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd("filetype plugin on")
vim.cmd("syntax on")

local function group(line, text)
  local source = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1]
  local column = assert(source:find(text, 1, true), "missing text: " .. text)
  return vim.fn.synIDattr(vim.fn.synID(line, column, 1), "name")
end

local function expect(line, text, name)
  assert(group(line, text) == name, string.format("line %d, %s: expected %s, got %s", line, text, name, group(line, text)))
end

for _, extension in ipairs({ "strudel", "rustel" }) do
  vim.cmd("edit! " .. vim.fn.fnameescape(vim.fn.tempname() .. "." .. extension))
  assert(vim.bo.filetype == "rustel", extension .. " filetype was not detected")
  assert(vim.bo.commentstring == "// %s")
end

vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  '$: s("bd [hh ~]*2").gain(0.5)',
  '$bass: note(\'c2 <eb2 g2>\')',
  'const title = "hello * world"',
  '// note("c4*4")',
  '/* s("bd*4")',
  '   still a comment */',
  'samples("https://example.com/samples.json")',
  'sound(',
  '  `bd [hh',
  '   ~]*2`',
  ').slow(2)',
  'const message = `hello',
  '  * world`',
  'const pattern = mini("[c3 e3]*2")',
  's("bd\\\"*2")',
  's(pattern).gain(1)',
  "s('bd\\'*2')",
  's(`bd\\`*2`)',
  'note',
  '(',
  '  "c4*4"',
  ')',
  's(`bd ${2} ~`)',
  's("bd/2").gain(0.5) // hi * there',
})

expect(1, "$:", "rustelLabel")
expect(1, "s(", "rustelFunction")
expect(1, "bd", "rustelPatternDouble")
expect(1, "[", "rustelMiniOperator")
expect(1, "~", "rustelMiniRest")
expect(1, "*", "rustelMiniOperator")
expect(1, "gain", "rustelFunction")
expect(1, "0.5", "javaScriptNumber")
expect(2, "$bass:", "rustelLabel")
expect(2, "c2", "rustelPatternSingle")
expect(2, "<", "rustelMiniOperator")
expect(3, "const", "javaScriptReserved")
expect(3, "*", "javaScriptStringD")
expect(4, "note", "javaScriptLineComment")
expect(5, "s(", "javaScriptComment")
expect(6, "still", "javaScriptComment")
expect(7, "/", "javaScriptStringD")
expect(8, "sound", "rustelFunction")
expect(9, "bd", "rustelPatternTemplate")
expect(9, "[", "rustelMiniOperator")
expect(10, "~", "rustelMiniRest")
expect(10, "*", "rustelMiniOperator")
expect(11, "slow", "rustelFunction")
expect(12, "hello", "javaScriptStringT")
expect(13, "*", "javaScriptStringT")
expect(14, "[", "rustelMiniOperator")
expect(15, "*", "rustelMiniOperator")
expect(16, "gain", "rustelFunction")
expect(17, "*", "rustelMiniOperator")
expect(18, "*", "rustelMiniOperator")
expect(19, "note", "rustelFunction")
expect(21, "*", "rustelMiniOperator")
expect(23, "${", "javaScriptEmbed")
expect(23, "~", "rustelMiniRest")
expect(24, "/2", "rustelMiniOperator")
expect(24, "hi", "javaScriptLineComment")

print("syntax: ok")
vim.cmd("qa!")
