-- 每个子进程的编辑辅助，初始化真实 list 模块和 buffer 选项
local list = require('vv-markdown.list')
local function set(lines) vim.api.nvim_buf_set_lines(0, 0, -1, false, lines) end
local function get() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|') end
local function check(name, got, want)
  assert(got == want, name .. '：期望 ' .. vim.inspect(want) .. '，实际 ' .. vim.inspect(got))
end
vim.bo.expandtab = true
vim.bo.shiftwidth = 2
vim.o.virtualedit = 'onemore'
local function continue_at_col(lines, row, col)
  set(lines)
  vim.api.nvim_win_set_cursor(0, { row, col })
  list.continue()
  return get()
end
local function continue_at(lines, row) return continue_at_col(lines, row, #lines[row]) end
Smoke = { list = list, set = set, get = get, check = check,
  continue_at = continue_at, continue_at_col = continue_at_col }
