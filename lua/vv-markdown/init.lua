-- vv-markdown：Markdown 列表智能编辑
--
-- 能力：insert <CR> 智能续行（有序自增 / 无序复制 / 缩进保持 / 光标后文本下移 / 空项退出或反缩进 /
--       冒号缩进子项）、删除/缩进/粘贴后自动重排有序列表、<C-t>/<C-d> 缩进增减、checkbox 切换、
--       代码块守卫、与 mini.pairs 共存（非列表行 <CR> 回退自动配对）。
-- 优雅降级：treesitter 仅用于代码块守卫（无则 regex 回退）；不依赖任何 LSP。

local M = {}

local AUGROUP = 'VVMarkdown'

---@type VVMarkdownConfig
local defaults = {
  enabled = true,
  filetypes = { 'markdown' },
  continue = true,
  auto_renumber = true,
  renumber_debounce = 60,
  colon_indent = true,
  dedent_empty = true,
  mini_pairs_fallback = true,
  settle_treesitter = true,
  checkbox = { states = { ' ', 'x' } },
  keymaps = {
    continue = '<CR>',
    indent = '<C-t>',
    dedent = '<C-d>',
    open_below = 'o',
    open_above = 'O',
    toggle_checkbox = '<leader>x',
    renumber = '<leader>nn',
  },
}

local config = defaults
local enabled = false
local renumber_token = {}        -- buf -> debounce token

-- ---------------------------------------------------------------------------
-- 自动重排（TextChanged 防抖）
-- ---------------------------------------------------------------------------

local function schedule_renumber(buf)
  if not config.auto_renumber then return end
  local list = require('vv-markdown.list')
  if list._busy then return end                       -- 跳过自身写入引发的 TextChanged

  local row = vim.api.nvim_win_get_cursor(0)[1]
  renumber_token[buf] = (renumber_token[buf] or 0) + 1
  local my = renumber_token[buf]

  vim.defer_fn(function()
    if renumber_token[buf] ~= my then return end
    if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf then return end
    require('vv-markdown.list').renumber_at(row)
  end, config.renumber_debounce)
end

-- ---------------------------------------------------------------------------
-- buffer-local keymap
-- ---------------------------------------------------------------------------

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'n', false)
end

local function install_keymaps(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local k = config.keymaps
  local function map(mode, lhs, rhs, desc, opts)
    if not lhs then return end
    opts = vim.tbl_extend('force', { buffer = buf, silent = true, desc = desc }, opts or {})
    vim.keymap.set(mode, lhs, rhs, opts)
  end

  -- insert <CR> 智能续行（expr，遮蔽 mini.pairs 全局 <CR>）
  if config.continue then
    map('i', k.continue, function() return require('vv-markdown.cr').expr() end,
      'vv-markdown: 续行', { expr = true, replace_keycodes = true })
  end

  -- insert 缩进 / 反缩进（非列表行回退原生 <C-t>/<C-d>）
  map('i', k.indent, function()
    if not require('vv-markdown.list').indent() then feed(k.indent) end
  end, 'vv-markdown: 缩进')
  map('i', k.dedent, function()
    if not require('vv-markdown.list').dedent() then feed(k.dedent) end
  end, 'vv-markdown: 反缩进')

  -- normal o / O 新建列表项（非列表行回退原生），等价 insert <CR> 续行
  map('n', k.open_below, function()
    if not require('vv-markdown.list').new_item_below() then feed(k.open_below) end
  end, 'vv-markdown: 下方新建项')
  map('n', k.open_above, function()
    if not require('vv-markdown.list').new_item_above() then feed(k.open_above) end
  end, 'vv-markdown: 上方新建项')

  -- checkbox 切换（normal 单行 / visual 范围）
  map('n', k.toggle_checkbox, function() require('vv-markdown.checkbox').toggle() end, 'vv-markdown: 切换勾选')
  map('x', k.toggle_checkbox, function()
    local a, b = vim.fn.line('v'), vim.fn.line('.')
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
    require('vv-markdown.checkbox').toggle_range(a, b)
  end, 'vv-markdown: 切换勾选')

  -- 整表重排
  map('n', k.renumber, function() require('vv-markdown.list').renumber_buffer() end, 'vv-markdown: 整表重排')

  -- 每个 markdown buffer 挂 buffer-local TextChanged → 防抖重排
  vim.api.nvim_create_autocmd('TextChanged', {
    group = AUGROUP,
    buffer = buf,
    callback = function() schedule_renumber(buf) end,
  })
end

local function remove_keymaps(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local k = config.keymaps
  local function del(mode, lhs) if lhs then pcall(vim.keymap.del, mode, lhs, { buffer = buf }) end end
  del('i', k.continue)
  del('i', k.indent)
  del('i', k.dedent)
  del('n', k.open_below)
  del('n', k.open_above)
  del('n', k.toggle_checkbox)
  del('x', k.toggle_checkbox)
  del('n', k.renumber)
end

local function is_target_ft(ft)
  return ft ~= '' and vim.tbl_contains(config.filetypes, ft)
end

-- ---------------------------------------------------------------------------
-- 生命周期
-- ---------------------------------------------------------------------------

function M.enable()
  if enabled then return end
  enabled = true

  vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = AUGROUP,
    pattern = config.filetypes,
    callback = function(ev) install_keymaps(ev.buf) end,
  })

  -- 懒加载时已打开的 buffer：补装
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and is_target_ft(vim.bo[buf].filetype) then
      install_keymaps(buf)
    end
  end
end

function M.disable()
  if not enabled then return end
  enabled = false
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and is_target_ft(vim.bo[buf].filetype) then
      remove_keymaps(buf)
    end
  end
end

function M.toggle()
  if enabled then M.disable() else M.enable() end
end

---@param opts? VVMarkdownConfig
function M.setup(opts)
  config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})

  -- 注入只读配置访问器（避免子模块循环 require init）
  require('vv-markdown.list')._set_config_getter(M.get_config)
  require('vv-markdown.cr')._set_config_getter(M.get_config)
  require('vv-markdown.checkbox')._set_config_getter(M.get_config)

  vim.api.nvim_create_user_command('VVMarkdownEnable', function() M.enable() end, {})
  vim.api.nvim_create_user_command('VVMarkdownDisable', function() M.disable() end, {})
  vim.api.nvim_create_user_command('VVMarkdownToggle', function() M.toggle() end, {})
  vim.api.nvim_create_user_command('VVMarkdownRenumber', function() require('vv-markdown.list').renumber_buffer() end, {})
  vim.api.nvim_create_user_command('VVMarkdownToggleCheckbox', function(o)
    require('vv-markdown.checkbox').toggle_range(o.line1, o.line2)
  end, { range = true })

  if config.enabled then M.enable() end
end

---@return VVMarkdownConfig
function M.get_config()
  return vim.deepcopy(config)
end

---@class VVMarkdownCheckboxConfig
---@field states string[]  勾选状态循环序列 @default { ' ', 'x' }

---@class VVMarkdownKeymaps
---@field continue string|false         insert 智能续行 @default '<CR>'
---@field indent string|false           insert 缩进当前项 @default '<C-t>'
---@field dedent string|false           insert 反缩进当前项 @default '<C-d>'
---@field open_below string|false       normal 下方新建列表项（等价续行）@default 'o'
---@field open_above string|false       normal 上方新建列表项 @default 'O'
---@field toggle_checkbox string|false  normal/visual 切换勾选 @default '<leader>x'
---@field renumber string|false         normal 整表重排 @default '<leader>nn'

---@class VVMarkdownConfig
---@field enabled boolean               是否启用 @default true
---@field filetypes string[]            生效的 filetype @default { 'markdown' }
---@field continue boolean              insert <CR> 列表续行 @default true
---@field auto_renumber boolean         删除/缩进/粘贴后自动重排有序列表 @default true
---@field renumber_debounce integer     自动重排防抖(ms) @default 60
---@field colon_indent boolean          行尾冒号时新项自动缩进一级 @default true
---@field dedent_empty boolean          空项回车时反缩进（否则直接清空退出列表）@default true
---@field mini_pairs_fallback boolean   非列表行 <CR> 回退 mini.pairs 自动配对 @default true
---@field settle_treesitter boolean     编辑后同步刷新 md treesitter 树（防 render-markdown 读过期树越界）@default true
---@field checkbox VVMarkdownCheckboxConfig
---@field keymaps VVMarkdownKeymaps

return M
