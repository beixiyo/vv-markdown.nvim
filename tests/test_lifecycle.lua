-- Lifecycle regression: setup replaces old filetype, keymap and autocmd resources.

local failures = {}

local function check(condition, message)
  if not condition then
    failures[#failures + 1] = message
  end
end

local function local_map(buf, mode, lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if map.lhs == lhs then return map end
  end
end

local test_file = debug.getinfo(1, 'S').source:sub(2)
local plugin_root = vim.fn.fnamemodify(test_file, ':p:h:h')
local vendors = vim.fn.fnamemodify(plugin_root, ':h')
vim.opt.runtimepath:append(plugin_root)
vim.opt.runtimepath:append(vendors .. '/vv-utils.nvim')

local markdown = require('vv-markdown')
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'markdown'
vim.keymap.set('i', '<F28>', '<cmd>let b:vv_markdown_old = 1<cr>', {
  buffer = buf,
  desc = 'existing F28',
})
vim.keymap.set('n', 'gf', '<cmd>let b:vv_markdown_old_gf = 1<cr>', {
  buffer = buf,
  desc = 'existing gf',
})

local disabled_keymaps = {
  indent = false,
  dedent = false,
  open_below = false,
  open_above = false,
  toggle_checkbox = false,
  renumber = false,
}

markdown.setup({
  enabled = true,
  filetypes = { 'markdown' },
  keymaps = vim.tbl_extend('force', disabled_keymaps, { continue = '<F28>' }),
})
check((local_map(buf, 'i', '<F28>') or {}).desc == 'vv-markdown: 续行',
  'first setup should claim the configured Markdown mapping')
check((local_map(buf, 'n', 'gf') or {}).desc == 'vv-markdown: gf 链接跳转',
  'first setup should claim the Markdown gf mapping')
check(#vim.api.nvim_get_autocmds({ group = 'VVMarkdown', buffer = buf }) == 3,
  'first setup should own exactly three buffer lifecycle autocmds')

markdown.setup({
  enabled = true,
  filetypes = { 'text' },
  keymaps = vim.tbl_extend('force', disabled_keymaps, { continue = '<F29>' }),
})
check((local_map(buf, 'i', '<F28>') or {}).desc == 'existing F28',
  'reconfiguration should restore the mapping replaced by the old config')
check((local_map(buf, 'n', 'gf') or {}).desc == 'existing gf',
  'reconfiguration should release gf using the old filetype config')
check(local_map(buf, 'i', '<F29>') == nil,
  'new mapping should not attach while the buffer has the old filetype')
check(#vim.api.nvim_get_autocmds({ group = 'VVMarkdown', buffer = buf }) == 0,
  'old filetype should not retain buffer lifecycle autocmds')

vim.bo[buf].filetype = 'text'
vim.api.nvim_exec_autocmds('FileType', { buffer = buf, modeline = false })
check((local_map(buf, 'i', '<F29>') or {}).desc == 'vv-markdown: 续行',
  'new filetype should receive the new mapping')
check((local_map(buf, 'n', 'gf') or {}).desc == 'vv-markdown: gf 链接跳转',
  'new filetype should receive the new gf mapping')
check(#vim.api.nvim_get_autocmds({ group = 'VVMarkdown', buffer = buf }) == 3,
  'new filetype should receive one set of buffer lifecycle autocmds')

markdown.setup({
  enabled = false,
  filetypes = { 'text' },
  keymaps = vim.tbl_extend('force', disabled_keymaps, { continue = '<F29>' }),
})
check(local_map(buf, 'i', '<F29>') == nil,
  'setup enabled=false should release mappings from the previous enabled instance')
check((local_map(buf, 'n', 'gf') or {}).desc == 'existing gf',
  'setup enabled=false should restore the gf mapping')
local has_group = pcall(vim.api.nvim_get_autocmds, { group = 'VVMarkdown' })
check(not has_group, 'setup enabled=false should remove the old autocmd group')

pcall(vim.keymap.del, 'i', '<F28>', { buffer = buf })
pcall(vim.keymap.del, 'n', 'gf', { buffer = buf })
vim.api.nvim_buf_delete(buf, { force = true })

if #failures > 0 then
  error('vv-markdown lifecycle failures:\n- ' .. table.concat(failures, '\n- '))
end

print('vv-markdown lifecycle: passed')
