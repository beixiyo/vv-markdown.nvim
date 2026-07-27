-- 列表引擎：解析行 / 续行 / 缩进签名重排 / 缩进增减
--
-- 设计要点：
--   · 纯行扫描（regex），不依赖 treesitter —— 续行热路径上 treesitter 的当前编辑行是 stale 的。
--   · 重排用「缩进签名」：以缩进字符串为 key 各自维护计数器，遇到更浅缩进时清空更深层级，
--     天然让嵌套 / blockquote / 兄弟子列表各自独立编号。
--   · 重排幂等：只改和目标不同的数字片段（nvim_buf_set_text），所以由 TextChanged 触发也不会
--     无限递归（自己的写入若无变化就不再触发）。

local M = {}

-- 由 init.lua 注入的只读配置访问器（避免循环 require）
---@type fun(): VVMarkdown.Config
local get_config = function() return { colon_indent = true, dedent_empty = true } end
function M._set_config_getter(fn) get_config = fn end

-- 重排期间置位，供 TextChanged handler 跳过自身写入
M._busy = false

-- 复选框内容：恰好一个 UTF-8 码点（[ ] / [x] / 自定义单字形如 [✓]）。
-- 用「一个 ASCII 字节或一个 UTF-8 多字节序列」而非 [^%]]+，避免把多字符散文
-- （`- [TODO] x` / `- [WIP] y` / `- [CDATA] z`）误判成复选框。
local CB_GLYPH = '%[([\1-\127\194-\253][\128-\191]*)%]'
local CB_PRE = '^' .. CB_GLYPH .. '%s' -- 复选框后跟空格
local CB_EOL = '^' .. CB_GLYPH .. '$'  -- 复选框独占整段

--- 编辑后同步刷新 markdown treesitter 树。
--- 关掉「本插件编辑」造成的树过期窗口，避免 render-markdown 等监听者在调度回调里
--- 用过期树 get_node_text 越界（render-markdown node.lua:34 未 pcall 守卫）。优雅降级：无 parser 即跳过。
function M.settle_ts()
  if get_config().settle_treesitter == false then return end
  local ok, parser = pcall(vim.treesitter.get_parser, 0, 'markdown')
  if ok and parser then pcall(function() parser:parse() end) end
end

-- ---------------------------------------------------------------------------
-- 基础工具
-- ---------------------------------------------------------------------------

local function buf_get(row)
  return vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ''
end

local function is_blank(line)
  return line:match('^%s*$') ~= nil
end

local function is_fence(line)
  return line:match('^%s*```') ~= nil or line:match('^%s*~~~') ~= nil
end

--- 围栏起始信息（` 或 ~，长度 >=3），非围栏返回 nil
local function fence_open(line)
  local ticks = line:match('^%s*([`~]+)')
  if ticks and #ticks >= 3 then return { char = ticks:sub(1, 1), len = #ticks } end
  return nil
end

--- line 是否闭合 open 围栏：同字符、长度 >= 起始、且无 info string（CommonMark）
local function fence_closes(line, open)
  local ticks, rest = line:match('^%s*([`~]+)(.*)$')
  if not ticks then return false end
  return ticks:sub(1, 1) == open.char and #ticks >= open.len and rest:match('^%s*$') ~= nil
end

--- 缩进的视觉列宽（tab 按 tabstop 展开），用作重排计数器 key，统一 tab/space
local function vwidth(indent)
  local ts = vim.bo.tabstop
  if ts == 0 then ts = 8 end
  local w = 0
  for i = 1, #indent do
    if indent:sub(i, i) == '\t' then w = w + ts - (w % ts) else w = w + 1 end
  end
  return w
end

--- 水平分割线（--- / *** / ___ / - - -），必须排除，否则会被当成无序列表标记
local function is_hr(line)
  local s = line:gsub('%s', '')
  return #s >= 3 and (s:match('^%-+$') ~= nil or s:match('^%*+$') ~= nil or s:match('^_+$') ~= nil)
end

--- 当前缩进单位长度（expandtab → shiftwidth 个空格；否则 1 个 tab）
local function indent_step()
  local sw = vim.bo.shiftwidth
  if sw == 0 then sw = vim.bo.tabstop end
  return vim.bo.expandtab and sw or 1
end

local function indent_unit()
  local sw = vim.bo.shiftwidth
  if sw == 0 then sw = vim.bo.tabstop end
  return vim.bo.expandtab and string.rep(' ', sw) or '\t'
end

-- ---------------------------------------------------------------------------
-- 解析
-- ---------------------------------------------------------------------------

--- 解析一行列表项；非列表 / HR 返回 nil
---@param line string
---@return VVMarkdownItem|nil
function M.parse(line)
  if is_hr(line) then return nil end

  local indent, num, delim, space, content = line:match('^(%s*)(%d+)([.)])(%s+)(.*)$')
  if num then
    local cb = content:match(CB_PRE) or content:match(CB_EOL)
    return {
      kind = 'ol',
      indent = indent,
      num = tonumber(num),
      delim = delim,
      space = space,
      content = content,
      checkbox = cb,
      lead = indent .. num .. delim .. space,
    }
  end

  local i2, marker, sp2, c2 = line:match('^(%s*)([-*+])(%s+)(.*)$')
  if marker then
    local cb = c2:match(CB_PRE) or c2:match(CB_EOL)
    return {
      kind = 'ul',
      indent = i2,
      marker = marker,
      space = sp2,
      content = c2,
      checkbox = cb,
      lead = i2 .. marker .. sp2,
    }
  end

  return nil
end

-- ---------------------------------------------------------------------------
-- 列表块定位 + 重排
-- ---------------------------------------------------------------------------

--- 定位包含 row 的连续列表块边界
---@return integer|nil top, integer|nil bot  1-based 行号
local function find_block(row)
  local n = vim.api.nvim_buf_line_count(0)

  -- 在 row 附近（±3 行）找列表项作种子：多行删除后光标可能落在离列表 2+ 行处
  local seed
  for d = 0, 3 do
    for _, r in ipairs(d == 0 and { row } or { row - d, row + d }) do
      if r >= 1 and r <= n and M.parse(buf_get(r)) then seed = r break end
    end
    if seed then break end
  end
  if not seed then return nil end

  -- base = 块内最浅列表项的视觉缩进；扩展中遇更浅项就下调，
  -- 使「比嵌套项浅但仍在外层项内」的续行不致截断块（用 vwidth 统一 tab/space）
  local base = vwidth(M.parse(buf_get(seed)).indent)

  -- 跨过单个空行看另一侧第一个非空行是否列表项（loose list）
  -- 连续两个及以上空行视为块边界，避免把用户显式分开的两组列表串号
  local function blank_run_ok(r, step)
    local k = r
    local blanks = 0
    while k >= 1 and k <= n and is_blank(buf_get(k)) do
      blanks = blanks + 1
      if blanks >= 2 then return false end
      k = k + step
    end
    return k >= 1 and k <= n and M.parse(buf_get(k)) ~= nil
  end

  local function listish(r, step)
    local l = buf_get(r)
    if is_fence(l) or is_hr(l) then return false end
    if M.parse(l) then return true end
    if is_blank(l) then return blank_run_ok(r, step) end
    return vwidth(l:match('^%s*')) > base       -- 比基准更深的续行/子内容
  end

  local top = seed
  while top > 1 and listish(top - 1, -1) do
    top = top - 1
    local p = M.parse(buf_get(top))
    if p and vwidth(p.indent) < base then base = vwidth(p.indent) end
  end

  local bot = seed
  while bot < n and listish(bot + 1, 1) do
    bot = bot + 1
    local p = M.parse(buf_get(bot))
    if p and vwidth(p.indent) < base then base = vwidth(p.indent) end
  end

  return top, bot
end

--- 重排 [top,bot] 内所有有序列表项（缩进签名算法），跳过代码块；幂等写入
local function renumber_range(top, bot)
  local counters = {}     -- vwidth(indent) -> 上一个序号
  local fence = nil       -- 当前开启的围栏标记 { char, len }；标记感知，避免混合围栏奇偶错乱
  local edits = {}        -- { row, col, oldlen, new }

  for row = top, bot do
    local line = buf_get(row)
    if fence then
      if fence_closes(line, fence) then fence = nil end
      -- 围栏内：跳过
    else
      local fo = fence_open(line)
      if fo then
        fence = fo
      else
        local p = M.parse(line)
        if p then
          local key = vwidth(p.indent)
          -- 更深层级清空（让重新进入的子列表从头计数）
          for k in pairs(counters) do
            if k > key then counters[k] = nil end
          end
          if p.kind == 'ol' then
            if counters[key] == nil then
              counters[key] = 1                -- 每个层级从 1 归一（缩进成子列表也重置）
            else
              counters[key] = counters[key] + 1
            end
            local want = counters[key]
            if want ~= p.num then
              edits[#edits + 1] = { row = row, col = #p.indent, oldlen = #tostring(p.num), new = tostring(want) }
            end
          end
        elseif is_hr(line) or line:match('^%s*#') or (not is_blank(line) and #(line:match('^%s*')) == 0) then
          -- 结构断点（HR / 标题 / 顶层段落）→ 重置计数，避免整表重排跨列表串号
          counters = {}
        end
      end
    end
  end

  if #edits == 0 then return false end
  M._busy = true
  -- 从后往前写，避免同行多次编辑时列偏移（这里每行至多一处，仍按倒序稳妥）
  for i = #edits, 1, -1 do
    local e = edits[i]
    pcall(vim.api.nvim_buf_set_text, 0, e.row - 1, e.col, e.row - 1, e.col + e.oldlen, { e.new })
  end
  vim.schedule(function() M._busy = false end)
  return true
end

--- 重排包含 row 的列表块；不在列表中则无操作
---@return boolean changed
function M.renumber_at(row)
  local top, bot = find_block(row)
  local changed = top and renumber_range(top, bot) or false
  M.settle_ts()                         -- 任何续行/缩进/重排路径都经此，统一刷新树
  return changed
end

--- 重排整个 buffer（供 :VVMarkdownRenumber 用）
function M.renumber_buffer()
  local n = vim.api.nvim_buf_line_count(0)
  local changed = renumber_range(1, n)
  M.settle_ts()
  return changed
end

-- ---------------------------------------------------------------------------
-- 续行（insert <CR> 落点）
-- ---------------------------------------------------------------------------

--- 在当前列表项上续行：有序自增 / 无序复制 / 缩进保持 / 光标后文本下移 / 空项退出或反缩进
function M.continue()
  local cur = vim.api.nvim_win_get_cursor(0)
  local row, col = cur[1], cur[2]
  local line = buf_get(row)
  local p = M.parse(line)
  if not p then return end                      -- 兜底：cr.lua 已保证是列表行

  local cfg = get_config()

  -- 空项：退出列表或反缩进一级（反缩进后交给 renumber 续上父级序号）
  if p.content == '' then
    if cfg.dedent_empty and #p.indent >= indent_step() then
      local ni = p.indent:sub(1, #p.indent - indent_step())
      local nm = (p.kind == 'ol') and (ni .. '1' .. p.delim .. p.space) or (ni .. p.marker .. p.space)
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { nm })
      vim.api.nvim_win_set_cursor(0, { row, #nm })
      M.renumber_at(row)
    else
      vim.api.nvim_buf_set_lines(0, row - 1, row, false, { '' })
      vim.api.nvim_win_set_cursor(0, { row, 0 })
      M.renumber_at(row - 1)
    end
    return
  end

  -- 整段前缀（含勾选框 token），用于光标落在标记/勾选框内时正确切分
  local fulllead = p.lead
  if p.checkbox then fulllead = p.lead .. '[' .. p.checkbox .. '] ' end

  -- 正常续行：在光标处切分，光标后文本移到新项
  local before = line:sub(1, col)
  local after = line:sub(col + 1)
  if #before < #fulllead then                   -- 光标落在标记/勾选框内：保留标记、丢弃被切碎的勾选框
    before = p.lead
    after = line:sub(#fulllead + 1)
  end

  local newmarker
  if p.kind == 'ol' then
    newmarker = p.indent .. tostring(p.num + 1) .. p.delim .. p.space
  else
    newmarker = p.indent .. p.marker .. p.space
  end
  if p.checkbox then newmarker = newmarker .. '[ ] ' end

  -- 行尾冒号 → 新项缩进一级（仅当光标在行尾、且整行正文以冒号结尾，避免行中冒号误触发）
  if cfg.colon_indent and after == '' and p.content:match(':%s*$') then
    if p.kind == 'ol' then
      newmarker = indent_unit() .. p.indent .. '1' .. p.delim .. p.space
    else
      newmarker = indent_unit() .. p.indent .. p.marker .. p.space
    end
    if p.checkbox then newmarker = newmarker .. '[ ] ' end
  end

  -- 单次原子编辑（替换当前行为两行），减少中间缓冲区状态，避免 render-markdown 等
  -- 监听者读到过期 treesitter 树
  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { before, newmarker .. after })
  vim.api.nvim_win_set_cursor(0, { row + 1, #newmarker })
  M.renumber_at(row + 1)
end

-- ---------------------------------------------------------------------------
-- 缩进 / 反缩进当前列表项（insert 模式 <C-t>/<C-d>）
-- ---------------------------------------------------------------------------

local function reindent(delta)
  local cur = vim.api.nvim_win_get_cursor(0)
  local row, col = cur[1], cur[2]
  local line = buf_get(row)
  local p = M.parse(line)
  if not p then return false end

  local new, dcol
  if delta > 0 then
    new = indent_unit() .. line
    dcol = #indent_unit()
  else
    local unit = indent_unit()
    -- 用视觉宽度判断（避免 expandtab=true 时 tab 缩进项因字节长度 < shiftwidth 而被误阻）
    if vwidth(p.indent) < vwidth(unit) then return false end
    if p.indent:sub(1, #unit) == unit then
      -- 快速路径：前缀与 indent_unit 完全匹配（同质缩进）
      new = line:sub(#unit + 1)
      dcol = -#unit
    else
      -- 混合缩进（tab 在 expandtab 文件或反之）：逐字符消耗恰好一个视觉步长
      local ts = vim.bo.tabstop == 0 and 8 or vim.bo.tabstop
      local target = vwidth(unit)
      local consumed, i = 0, 1
      while i <= #p.indent and consumed < target do
        local c = p.indent:sub(i, i)
        consumed = consumed + (c == '\t' and (ts - consumed % ts) or 1)
        i = i + 1
      end
      new = line:sub(i)
      dcol = -(i - 1)
    end
  end

  vim.api.nvim_buf_set_lines(0, row - 1, row, false, { new })
  vim.api.nvim_win_set_cursor(0, { row, math.max(0, col + dcol) })
  M.renumber_at(row)
  return true
end

function M.indent() return reindent(1) end
function M.dedent() return reindent(-1) end

-- ---------------------------------------------------------------------------
-- normal 模式 o / O 新建列表项（等价 insert <CR> 续行）
-- ---------------------------------------------------------------------------

--- 在下方新建续行项并进入插入模式；非列表/代码块返回 false（交回退原生 o）
function M.new_item_below()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local p = M.parse(buf_get(row))
  if not p or require('vv-markdown.guard').in_fence(row) then return false end
  local nm = (p.kind == 'ol') and (p.indent .. tostring(p.num + 1) .. p.delim .. p.space)
    or (p.indent .. p.marker .. p.space)
  if p.checkbox then nm = nm .. '[ ] ' end
  vim.api.nvim_buf_set_lines(0, row, row, false, { nm })
  M.renumber_at(row + 1)
  vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
  vim.cmd('startinsert!')
  return true
end

--- 在上方新建项并进入插入模式；非列表/代码块返回 false（交回退原生 O）
function M.new_item_above()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local p = M.parse(buf_get(row))
  if not p or require('vv-markdown.guard').in_fence(row) then return false end
  local nm = (p.kind == 'ol') and (p.indent .. tostring(p.num) .. p.delim .. p.space)
    or (p.indent .. p.marker .. p.space)
  if p.checkbox then nm = nm .. '[ ] ' end
  vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, { nm })
  M.renumber_at(row)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.cmd('startinsert!')
  return true
end

---@class VVMarkdownItem
---@field kind 'ol'|'ul'
---@field indent string  前导空白
---@field num integer?  有序序号
---@field delim string?  '.' 或 ')'
---@field marker string?  无序标记 - * +
---@field space string  标记后空白
---@field content string  标记后正文
---@field checkbox string?  勾选状态字符（' ' / 'x' / '-' …），非 checkbox 为 nil
---@field lead string  整段标记（indent..marker..space）

return M
