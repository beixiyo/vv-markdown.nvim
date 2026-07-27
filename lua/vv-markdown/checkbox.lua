-- 勾选框：在列表项上切换 / 循环 checkbox 状态
--
-- · 普通列表项（- foo / 1. foo）→ 加上 [ ]
-- · 已有 checkbox → 按 config.checkbox.states 循环到下一个状态
-- · 支持 normal 单行与 visual 多行范围

local M = {}

---@type fun(): VVMarkdown.Config
local get_config = function() return { checkbox = { states = { ' ', 'x' } } } end
function M._set_config_getter(fn) get_config = fn end

local function escape(c) return c:gsub('(%W)', '%%%1') end
-- gsub 替换串里 '%' 需转义成 '%%'（否则 '%x' 被当反向引用，PUC-Lua 直接报错）
local function escape_repl(c) return (c:gsub('%%', '%%%%')) end

--- 计算某一行切换后的新文本；非列表行返回 nil
local function toggled(line, states)
  local list = require('vv-markdown.list')
  local p = list.parse(line)
  if not p then return nil end

  -- 已是 checkbox：循环到下一状态
  if p.checkbox ~= nil then
    for i, s in ipairs(states) do
      if s == p.checkbox then
        local nxt = states[i % #states + 1]
        return (line:gsub('%[' .. escape(p.checkbox) .. '%]', '[' .. escape_repl(nxt) .. ']', 1))
      end
    end
    -- 当前状态不在配置列表里 → 归一到第一个
    return (line:gsub('%[' .. escape(p.checkbox) .. '%]', '[' .. escape_repl(states[1]) .. ']', 1))
  end

  -- 普通列表项 → 插入空 checkbox
  return (line:gsub('^(' .. escape(p.lead) .. ')', '%1[' .. escape_repl(states[1]) .. '] ', 1))
end

--- 切换 [a,b] 行（1-based，闭区间）的勾选状态
---@param a integer
---@param b integer
function M.toggle_range(a, b)
  local states = get_config().checkbox.states
  if a > b then a, b = b, a end
  local changed = false
  for row = a, b do
    local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
    local new = toggled(line, states)
    if new and new ~= line then
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { new })
      changed = true
    end
  end
  if changed then require('vv-markdown.list').settle_ts() end
end

--- 切换当前行
function M.toggle()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  M.toggle_range(row, row)
end

return M
