-- vv-markdown：Markdown 列表智能编辑
--
-- 能力：insert <CR> 智能续行（有序自增 / 无序复制 / 缩进保持 / 光标后文本下移 / 空项退出或反缩进 /
--       冒号缩进子项）、删除/缩进/粘贴后自动重排有序列表、<C-t>/<C-d> 缩进增减、checkbox 切换、
--       代码块守卫、与 mini.pairs 共存（非列表行 <CR> 回退自动配对）
-- 优雅降级：treesitter 仅用于代码块守卫（无则 regex 回退）；不依赖任何 LSP
require('vv-markdown.types')

local M = {}

local AUGROUP = 'VVMarkdown'

---@type VVMarkdown.Config
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
  gf_navigation = true,
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
local renumber_debounces = {}    -- buf -> { fn, cancel }（vv-utils debounce 实例）
local keymap_handle = nil
local lifecycle_generation = 0

-- ---------------------------------------------------------------------------
-- 自动重排（TextChanged 防抖，复用 vv-utils.timer.debounce）
-- ---------------------------------------------------------------------------

local function get_or_make_debounce(buf)
  if not renumber_debounces[buf] then
    local generation = lifecycle_generation

    local function do_renumber(row)
      if not enabled or generation ~= lifecycle_generation then return end
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if not vim.tbl_contains(config.filetypes, vim.bo[buf].filetype) then return end

      -- 用 win_call 保证 buf_get 里的 handle 0 解析到正确 buffer（即使用户已切走）
      local win = vim.fn.bufwinid(buf)
      if win == -1 then return end
      vim.api.nvim_win_call(win, function()
        require('vv-markdown.list').renumber_at(row)
      end)
    end

    local wrapped, cancel = require('vv-utils.timer').debounce(
      do_renumber,
      function() return config.renumber_debounce end
    )
    renumber_debounces[buf] = { fn = wrapped, cancel = cancel }
  end
  return renumber_debounces[buf]
end

local function schedule_renumber(buf)
  if not config.auto_renumber then return end
  local list = require('vv-markdown.list')
  if list._busy then return end                       -- 跳过自身写入引发的 TextChanged
  local row = vim.api.nvim_win_get_cursor(0)[1]
  get_or_make_debounce(buf).fn(row)
end

-- ---------------------------------------------------------------------------
-- buffer-local keymap
-- ---------------------------------------------------------------------------

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'n', false)
end

---@return VVKeymapSpec[]
local function keymap_specs()
  local k = config.keymaps
  local specs = {}

  local function add(mode, lhs, rhs, desc, opts)
    if not lhs then return end
    specs[#specs + 1] = {
      mode = mode,
      lhs = lhs,
      rhs = rhs,
      opts = vim.tbl_extend('force', { silent = true, desc = desc }, opts or {}),
    }
  end

  -- insert <CR> 智能续行（expr，遮蔽 mini.pairs 全局 <CR>）
  if config.continue then
    add('i', k.continue, function() return require('vv-markdown.cr').expr() end,
      'vv-markdown: 续行', { expr = true, replace_keycodes = true })
  end

  -- insert 缩进 / 反缩进（非列表行回退原生 <C-t>/<C-d>）
  add('i', k.indent, function()
    if not require('vv-markdown.list').indent() then feed(k.indent) end
  end, 'vv-markdown: 缩进')
  add('i', k.dedent, function()
    if not require('vv-markdown.list').dedent() then feed(k.dedent) end
  end, 'vv-markdown: 反缩进')

  -- normal o / O 新建列表项（非列表行回退原生），等价 insert <CR> 续行
  add('n', k.open_below, function()
    if not require('vv-markdown.list').new_item_below() then feed(k.open_below) end
  end, 'vv-markdown: 下方新建项')
  add('n', k.open_above, function()
    if not require('vv-markdown.list').new_item_above() then feed(k.open_above) end
  end, 'vv-markdown: 上方新建项')

  -- checkbox 切换（normal 单行 / visual 范围）
  add('n', k.toggle_checkbox, function() require('vv-markdown.checkbox').toggle() end, 'vv-markdown: 切换勾选')
  add('x', k.toggle_checkbox, function()
    local a, b = vim.fn.line('v'), vim.fn.line('.')
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
    require('vv-markdown.checkbox').toggle_range(a, b)
  end, 'vv-markdown: 切换勾选')

  -- 整表重排
  add('n', k.renumber, function() require('vv-markdown.list').renumber_buffer() end, 'vv-markdown: 整表重排')

  return specs
end

local function clear_buffer_resources(buf)
  local debounce = renumber_debounces[buf]
  if debounce then
    debounce.cancel()
    renumber_debounces[buf] = nil
  end

  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_clear_autocmds({ group = AUGROUP, buffer = buf })
  end
end

local function install_buffer_resources(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end

  -- FileType 可能对同一 buffer 重复触发。先清掉本 buffer 在组里已有的
  -- debounce/autocmd 资源，避免逐次累积
  clear_buffer_resources(buf)

  -- 每个 markdown buffer 挂 buffer-local TextChanged → 防抖重排
  vim.api.nvim_create_autocmd('TextChanged', {
    group = AUGROUP,
    buffer = buf,
    callback = function() schedule_renumber(buf) end,
  })
  -- buffer 销毁时关闭 uv timer，释放句柄并清理 debounce 实例
  vim.api.nvim_create_autocmd('BufDelete', {
    group = AUGROUP,
    buffer = buf,
    callback = function()
      local d = renumber_debounces[buf]
      if d then d.cancel(); renumber_debounces[buf] = nil end
    end,
  })
  -- 保存前：取消待定防抖 + 同步重排，消除「debounce 在 BufWritePost 后触发，
  -- 与 render-markdown 异步渲染竞争 treesitter 节点」的 Index out of bounds 竞态
  vim.api.nvim_create_autocmd('BufWritePre', {
    group = AUGROUP,
    buffer = buf,
    callback = function()
      local d = renumber_debounces[buf]
      if d then d.cancel(); renumber_debounces[buf] = nil end
      if config.auto_renumber and not require('vv-markdown.list')._busy then
        require('vv-markdown.list').renumber_buffer()
      end
    end,
  })
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
  lifecycle_generation = lifecycle_generation + 1

  require('vv-markdown.gf').enable()
  keymap_handle = require('vv-utils.keymap').attach({
    id = 'vv-markdown.edit',
    filetypes = config.filetypes,
    mappings = keymap_specs(),
  })

  vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = AUGROUP,
    pattern = '*',
    callback = function(ev)
      if is_target_ft(vim.bo[ev.buf].filetype) then
        install_buffer_resources(ev.buf)
      else
        clear_buffer_resources(ev.buf)
      end
    end,
  })

  -- 懒加载时已打开的 buffer：补装
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and is_target_ft(vim.bo[buf].filetype) then
      install_buffer_resources(buf)
    end
  end
end

function M.disable()
  if not enabled then return end
  enabled = false
  lifecycle_generation = lifecycle_generation + 1
  require('vv-markdown.gf').disable()
  if keymap_handle then
    keymap_handle:detach()
    keymap_handle = nil
  end
  -- 取消所有待定的重排防抖 timer（关闭 uv 句柄）
  for b, d in pairs(renumber_debounces) do
    d.cancel()
    renumber_debounces[b] = nil
  end
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
end

function M.toggle()
  if enabled then M.disable() else M.enable() end
end

---@param opts? VVMarkdown.ConfigOptions
function M.setup(opts)
  -- 旧实例必须按旧 filetypes/keymaps/config 完整释放后，才能覆盖配置
  if enabled then M.disable() end

  config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})

  -- 注入只读配置访问器（避免子模块循环 require init）
  require('vv-markdown.list')._set_config_getter(M.get_config)
  require('vv-markdown.cr')._set_config_getter(M.get_config)
  require('vv-markdown.checkbox')._set_config_getter(M.get_config)
  require('vv-markdown.gf')._set_config_getter(M.get_config)

  vim.api.nvim_create_user_command('VVMarkdownEnable', function() M.enable() end, { force = true })
  vim.api.nvim_create_user_command('VVMarkdownDisable', function() M.disable() end, { force = true })
  vim.api.nvim_create_user_command('VVMarkdownToggle', function() M.toggle() end, { force = true })
  vim.api.nvim_create_user_command('VVMarkdownRenumber', function() require('vv-markdown.list').renumber_buffer() end,
    { force = true })
  vim.api.nvim_create_user_command('VVMarkdownToggleCheckbox', function(o)
    require('vv-markdown.checkbox').toggle_range(o.line1, o.line2)
  end, { range = true, force = true })

  if config.enabled then M.enable() end
end

---@return VVMarkdown.Config
function M.get_config()
  return vim.deepcopy(config)
end

return M
