-- 冒烟/回归测试：纯算法（parse / renumber / continue），不依赖输入模拟
-- 运行：nvim --headless +"luafile %:p" +qa   或  :luafile %

local ok_count, fail_count, fails = 0, 0, {}

local function check(name, got, want)
  if got == want then
    ok_count = ok_count + 1
  else
    fail_count = fail_count + 1
    fails[#fails + 1] = string.format('  ✗ %s\n      got : %s\n      want: %s', name, tostring(got), tostring(want))
  end
end

-- 让 require 找到本插件（从 tests/ 回溯到仓库根；兼容 clean nvim / CI 从根目录运行）
local here = debug.getinfo(1, 'S').source:sub(2):gsub('tests[/\\]test_smoke%.lua$', '')
if here == '' then here = vim.fn.getcwd() end
vim.opt.runtimepath:append(here)
-- vv-utils（debounce 依赖）：与本仓库同级的 sibling 目录
local utils_root = vim.fn.fnamemodify(here:gsub('[/\\]$', ''), ':h') .. '/vv-utils.nvim'
vim.opt.runtimepath:append(utils_root)

local list = require('vv-markdown.list')

local function set(lines) vim.api.nvim_buf_set_lines(0, 0, -1, false, lines) end
local function get() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|') end

vim.bo.expandtab = true
vim.bo.shiftwidth = 2

-- parse
check('parse ol', (list.parse('1. a') or {}).kind, 'ol')
check('parse ul', (list.parse('- a') or {}).kind, 'ul')
check('parse ol )', (list.parse('3) a') or {}).num, 3)
check('parse hr reject', list.parse('---'), nil)
check('parse bold reject', list.parse('**bold**'), nil)
check('parse checkbox', (list.parse('- [x] a') or {}).checkbox, 'x')
check('parse indent', (list.parse('   - a') or {}).indent, '   ')

-- renumber_at
set({ '1. a', '3. c' });            list.renumber_at(2); check('renumber del-mid', get(), '1. a|2. c')
set({ '1. a', '5. b', '9. c' });    list.renumber_at(1); check('renumber normalize', get(), '1. a|2. b|3. c')
set({ '1. a', '2. b', '  5. x', '  9. y', '3. c' }); list.renumber_at(1)
check('renumber nested', get(), '1. a|2. b|  1. x|  2. y|3. c')
set({ '```', '1. x', '5. y', '```', '1. a', '9. b' }); list.renumber_at(5)
check('renumber fence-guard', get(), '```|1. x|5. y|```|1. a|2. b')
set({ '1. a', '2. b' });            local changed = list.renumber_at(1)
check('renumber idempotent', changed, false)

-- continue（光标置于行尾模拟 insert <CR>；virtualedit 允许停在末字符之后，等价插入模式）
vim.o.virtualedit = 'onemore'
local function continue_at(lines, row)
  set(lines)
  vim.api.nvim_win_set_cursor(0, { row, #lines[row] })
  list.continue()
  return get()
end
local function continue_at_col(lines, row, col)
  set(lines)
  vim.api.nvim_win_set_cursor(0, { row, col })
  list.continue()
  return get()
end
check('continue ol', continue_at({ '1. a' }, 1), '1. a|2. ')
check('continue ul indent', continue_at({ '  - foo' }, 1), '  - foo|  - ')
check('continue renumber after', continue_at({ '1. a', '2. b' }, 1), '1. a|2. |3. b')

-- ── 回归：对抗审查发现的 bug ──
-- #1 整表重排跨 HR / 标题 不串号
set({ '1. a', '2. b', '---', '1. c', '2. d' });        list.renumber_buffer(); check('R#1 hr boundary', get(), '1. a|2. b|---|1. c|2. d')
set({ '1. a', '2. b', '## h', '5. c', '9. d' });       list.renumber_buffer(); check('R#1 heading boundary', get(), '1. a|2. b|## h|1. c|2. d')
-- #2 光标距列表 2 行仍重排
set({ '1. a', '9. b', '', '', 'end' });                list.renumber_at(4);    check('R#2 seed within 3', get(), '1. a|2. b|||end')
-- #3 浅续行不截断嵌套
set({ '1. top', '    9. s1', '    9. s2', '   cont', '    9. s3' }); list.renumber_at(2)
check('R#3 shallow continuation', get(), '1. top|    1. s1|    2. s2|   cont|    3. s3')
-- #5 单空行 loose list 仍连续；连续两个空行断开列表块
set({ '1. a', '', '9. b' });                           list.renumber_at(1);    check('R#5 one-blank loose', get(), '1. a||2. b')
set({ '1. a', '', '', '9. b' });                       list.renumber_at(1);    check('R#5 two-blank boundary', get(), '1. a|||9. b')
set({ '1. sdf', '2. sdfdsf', '3. sdf', '', '', '1. sdf', '2. ' }); list.renumber_at(6)
check('R#5 separated ordered lists stay separate', get(), '1. sdf|2. sdfdsf|3. sdf|||1. sdf|2. ')
-- #10 混合围栏（~~~ 内含 ```）
set({ '1. a', '~~~md', '3. x', '```', '7. y', '~~~', '9. b' }); list.renumber_buffer()
check('R#10 mixed fence', get(), '1. a|~~~md|3. x|```|7. y|~~~|2. b')
-- #7 勾选框光标在标记内不重复
check('R#7 checkbox cursor-in-marker', (function()
  set({ '1. [ ] task' }); vim.api.nvim_win_set_cursor(0, { 1, 1 }); list.continue(); return get()
end)(), '1. |2. [ ] task')
-- #8 行中冒号不触发缩进；行尾冒号仍触发
check('R#8 colon mid-content', continue_at_col({ '1. Note: x' }, 1, 8), '1. Note:|2.  x')
check('R#8 colon eol triggers', continue_at({ '1. foo:' }, 1), '1. foo:|  1. ')
-- #11 checkbox 状态含 % 不损坏
check('R#11 percent state', (function()
  local cb = require('vv-markdown.checkbox')
  cb._set_config_getter(function() return { checkbox = { states = { ' ', '%' } } } end)
  set({ '- [ ] t' }); cb.toggle_range(1, 1); local r = get()
  cb._set_config_getter(function() return { checkbox = { states = { ' ', 'x' } } } end)
  return r
end)(), '- [%] t')
-- bug2: normal o / O 新建项（缓冲区效果）
set({ '1. a', '2. b' }); vim.api.nvim_win_set_cursor(0, { 1, 0 }); list.new_item_below(); vim.cmd('stopinsert')
check('o new-item-below', get(), '1. a|2. |3. b')
set({ '1. a', '2. b' }); vim.api.nvim_win_set_cursor(0, { 2, 0 }); list.new_item_above(); vim.cmd('stopinsert')
check('O new-item-above', get(), '1. a|2. |3. b')
-- o 在嵌套子项上 → 续子项
set({ '1. a', '  1. x', '  2. y' }); vim.api.nvim_win_set_cursor(0, { 2, 0 }); list.new_item_below(); vim.cmd('stopinsert')
check('o nested-item', get(), '1. a|  1. x|  2. |  3. y')

-- #4 混合 tab/space 同视觉深度（noexpandtab, tabstop=4）
vim.bo.expandtab = false; vim.bo.tabstop = 4
set({ '1. a', '\t1. x', '    9. y' }); list.renumber_at(1)
check('R#4 tab/space same level', get(), '1. a|\t1. x|    2. y')
vim.bo.expandtab = true; vim.bo.shiftwidth = 2

-- guard.lua regex_in_fence 混合围栏类型（Bug fix: ~~~ 内 ``` 不应错误关闭围栏）
-- 直接测 guard 模块（headless 下无 treesitter → 走 regex 路径）
local guard = require('vv-markdown.guard')
set({ '~~~', '```lua', '1. item', '```', '~~~', 'normal' })
-- row=3 ("1. item") 在 ~~~ 围栏内；旧代码第 2 行 ``` 会 toggle→false，row=3 误报 false
check('guard regex mixed-fence row-in-fence', guard.in_fence(3), true)
-- row=6 ("normal") 在围栏外
check('guard regex mixed-fence row-outside', guard.in_fence(6), false)
-- 四反引号围栏内含三反引号不应被关闭
set({ '````', '```lua', 'code', '```', '````', 'end' })
check('guard regex 4tick-fence row-in', guard.in_fence(3), true)
check('guard regex 4tick-fence row-out', guard.in_fence(6), false)

-- reindent dedent: expandtab=true 下 tab 缩进项应能反缩进（Bug fix: vwidth guard）
vim.bo.expandtab = true; vim.bo.shiftwidth = 2; vim.bo.tabstop = 2
-- tab 在 expandtab buffer 里，字节长度 1 < shiftwidth 2，旧代码会 return false
set({ '- outer', '\t- inner' }); vim.api.nvim_win_set_cursor(0, { 2, 3 })
check('dedent tab-in-expandtab', list.dedent(), true)
-- 反缩进后 inner 项应变成 "- inner"（去掉 tab）
check('dedent tab-in-expandtab result', get(), '- outer|- inner')

-- gf 生命周期：FileType 切出 Markdown 时恢复原映射，且不能覆盖后来的用户重绑。
do
  local gf = require('vv-markdown.gf')
  local buf = vim.api.nvim_create_buf(false, true)
  local function set_filetype(filetype)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd('set filetype=' .. filetype)
    end)
  end
  local function local_gf_desc()
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      if map.lhs == 'gf' then return map.desc end
    end
  end
  gf._set_config_getter(function() return { gf_navigation = true, filetypes = { 'markdown' } } end)
  vim.keymap.set('n', 'gf', '<cmd>let b:vv_markdown_old_gf = 1<cr>', {
    buffer = buf,
    silent = true,
    desc = 'old gf',
  })
  gf.enable()
  set_filetype('markdown')
  check('gf 在 Markdown buffer 接管 local mapping', local_gf_desc(), 'vv-markdown: gf 链接跳转')
  set_filetype('text')
  check('gf 离开 Markdown 时恢复原 local mapping', local_gf_desc(), 'old gf')
  set_filetype('markdown')

  vim.keymap.set('n', 'gf', '<cmd>let b:vv_markdown_external_gf = 1<cr>', {
    buffer = buf,
    desc = 'external gf',
  })
  set_filetype('text')
  check('gf 自动解绑时保留后来的外部映射', local_gf_desc(), 'external gf')
  gf.disable()
  pcall(vim.keymap.del, 'n', 'gf', { buffer = buf })
  vim.api.nvim_buf_delete(buf, { force = true })
end

local summary = string.format('vv-markdown smoke: %d passed, %d failed', ok_count, fail_count)
if fail_count > 0 then summary = summary .. '\n' .. table.concat(fails, '\n') end
print(summary)
vim.g.vv_markdown_smoke = summary
return summary
