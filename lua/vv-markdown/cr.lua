-- 插入模式 <CR> 分发（expr 映射）
--
-- 机制（已 spike 验证）：
--   · 列表行且不在代码块 → 返回 "<Cmd>lua ...continue()<CR>"，把缓冲区编辑推到 expr 限制之外执行。
--   · 非列表行 → 返回 require('mini.pairs').cr()，原样复用自动配对的换行展开（{ }、引号等），
--     这样 markdown 里的 {}+回车多行展开不会失效。mini.pairs 不在则回退裸 <CR>。
--   · 整个映射是 buffer-local + ft=markdown，天然遮蔽 mini.pairs 的全局 <CR>，且只在 markdown 生效。

local M = {}

---@type fun(): VVMarkdown.Config
local get_config = function() return { continue = true, mini_pairs_fallback = true } end
function M._set_config_getter(fn) get_config = fn end

local function plain_cr()
  return vim.api.nvim_replace_termcodes('<CR>', true, false, true)
end

--- expr 映射回调：返回要执行的按键串
---@return string
function M.expr()
  local cfg = get_config()
  local line = vim.api.nvim_get_current_line()
  local list = require('vv-markdown.list')
  local p = line ~= '' and list.parse(line) or nil

  if cfg.continue and p then
    local row = vim.api.nvim_win_get_cursor(0)[1]
    if not require('vv-markdown.guard').in_fence(row) then
      return '<Cmd>lua require("vv-markdown.list").continue()<CR>'
    end
  end

  if cfg.mini_pairs_fallback then
    local ok, mp = pcall(require, 'mini.pairs')
    if ok and type(mp.cr) == 'function' then return mp.cr() end
  end
  return plain_cr()
end

return M
