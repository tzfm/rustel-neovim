#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
for test in tests/*.lua; do
  "${NVIM:-nvim}" --headless -u NONE -i NONE -n \
    -c "lua local ok, err = pcall(dofile, '$test'); if not ok then print(err); vim.cmd('cquit 1') end" -c 'qa!'
done
