local function text(lines)
  if not lines or #lines == 0 then return "" end
  if lines[#lines] == "" then lines[#lines] = nil end
  return table.concat(lines, "\n")
end

return function(command, env, timeout)
  local stdout, stderr, code
  local job = vim.fn.jobstart(command, {
    env = env,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data) stdout = data end,
    on_stderr = function(_, data) stderr = data end,
    on_exit = function(_, exit_code) code = exit_code end,
  })
  assert(job > 0, "could not start Neovim")
  assert(vim.wait(timeout, function() return code ~= nil end, 20), "Neovim subprocess timed out")
  return { code = code, stdout = text(stdout), stderr = text(stderr) }
end
