-- 上下文守卫：判断某行是否在代码块内（续行/重排都要跳过 fenced code）
--
-- 优雅降级：优先用 treesitter（已 attach 的 markdown parser，结构准确），
-- parser 不可用时回退到从文件头扫 ``` / ~~~ 的奇偶计数。

local M = {}

--- treesitter 路径：光标行节点是否落在 code_fence / fenced_code_block 内
local function ts_in_fence(row)
  local ok, parser = pcall(vim.treesitter.get_parser, 0, 'markdown')
  if not ok or not parser then return nil end          -- 不可用 → 交给 regex 回退

  local ok2, tree = pcall(function() return parser:parse()[1] end)
  if not ok2 or not tree then return nil end

  local node = tree:root():named_descendant_for_range(row - 1, 0, row - 1, 0)
  while node do
    local t = node:type()
    -- 只守卫「围栏代码块」。不含 indented_code_block：tree-sitter 会把缩进 4+ 空格的
    -- 列表项也解析成 indented_code_block，纳入会让常见的缩进列表 <CR> 续行静默失效。
    if t == 'fenced_code_block' or t == 'code_fence_content' then
      return true
    end
    node = node:parent()
  end
  return false
end

--- regex 回退：从文件头到 row 识别围栏开合（字符感知，避免混合围栏奇偶错乱）
local function regex_in_fence(row)
  local lines = vim.api.nvim_buf_get_lines(0, 0, row - 1, false)
  local fence = nil   -- 当前开启的围栏 { char, len }；nil 表示不在围栏内
  for _, l in ipairs(lines) do
    if fence then
      -- 在围栏内：只有同字符且长度足够、无 info string 的行才能关闭
      local ticks, rest = l:match('^%s*([`~]+)(.*)$')
      if ticks and ticks:sub(1, 1) == fence.char and #ticks >= fence.len and (rest:match('^%s*$') ~= nil) then
        fence = nil
      end
    else
      local ticks = l:match('^%s*([`~]+)')
      if ticks and #ticks >= 3 then
        fence = { char = ticks:sub(1, 1), len = #ticks }
      end
    end
  end
  return fence ~= nil
end

--- row（1-based）是否在代码块内
---@param row integer
---@return boolean
function M.in_fence(row)
  local r = ts_in_fence(row)
  if r ~= nil then return r end
  return regex_in_fence(row)
end

return M
