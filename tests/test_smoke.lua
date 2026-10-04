-- 真实场景在独立子进程中执行；收集阶段仅注册具名用例。
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set({ setup = 'fixture_smoke.lua' })

T["识别有序无序与勾选列表并拒绝标题式伪列表"] = function()
  child.lua_func(function()
    local list, set, get, check, continue_at, continue_at_col = Smoke.list, Smoke.set, Smoke.get, Smoke.check, Smoke.continue_at, Smoke.continue_at_col
    -- 列表行解析
    check('解析有序列表', (list.parse('1. a') or {}).kind, 'ol')
    check('解析无序列表', (list.parse('- a') or {}).kind, 'ul')
    check('解析右括号有序标记', (list.parse('3) a') or {}).num, 3)
    check('解析拒绝水平线', list.parse('---'), nil)
    check('解析拒绝粗体伪列表', list.parse('**bold**'), nil)
    check('解析勾选状态', (list.parse('- [x] a') or {}).checkbox, 'x')
    check('解析保留缩进', (list.parse('   - a') or {}).indent, '   ')
  end)
end

T["重排删除项、嵌套层级与代码围栏且保持幂等"] = function()
  child.lua_func(function()
    local list, set, get, check, continue_at, continue_at_col = Smoke.list, Smoke.set, Smoke.get, Smoke.check, Smoke.continue_at, Smoke.continue_at_col
    -- 当前列表块重排
    set({ '1. a', '3. c' });            list.renumber_at(2); check('删除中间项后重排', get(), '1. a|2. c')
    set({ '1. a', '5. b', '9. c' });    list.renumber_at(1); check('重排归一化序号', get(), '1. a|2. b|3. c')
    set({ '1. a', '2. b', '  5. x', '  9. y', '3. c' }); list.renumber_at(1)
    check('嵌套层级独立重排', get(), '1. a|2. b|  1. x|  2. y|3. c')
    set({ '```', '1. x', '5. y', '```', '1. a', '9. b' }); list.renumber_at(5)
    check('重排保护代码围栏', get(), '```|1. x|5. y|```|1. a|2. b')
    set({ '1. a', '2. b' });            local changed = list.renumber_at(1)
    check('重排幂等', changed, false)
  end)
end

T["续行自动编号并保持缩进与后续项"] = function()
  child.lua_func(function()
    local list, set, get, check, continue_at, continue_at_col = Smoke.list, Smoke.set, Smoke.get, Smoke.check, Smoke.continue_at, Smoke.continue_at_col
    check('有序列表续行', continue_at({ '1. a' }, 1), '1. a|2. ')
    check('无序列表续行保留缩进', continue_at({ '  - foo' }, 1), '  - foo|  - ')
    check('续行重排后续列表项', continue_at({ '1. a', '2. b' }, 1), '1. a|2. |3. b')
  end)
end

T["列表边界、空行、冒号、勾选、插入与视觉缩进回归"] = function()
  child.lua_func(function()
    local list, set, get, check, continue_at, continue_at_col = Smoke.list, Smoke.set, Smoke.get, Smoke.check, Smoke.continue_at, Smoke.continue_at_col
    -- ── 回归：对抗审查发现的 bug ──
    -- #1 整表重排跨 HR / 标题 不串号
    set({ '1. a', '2. b', '---', '1. c', '2. d' });        list.renumber_buffer(); check('R#1 水平线隔开列表', get(), '1. a|2. b|---|1. c|2. d')
    set({ '1. a', '2. b', '## h', '5. c', '9. d' });       list.renumber_buffer(); check('R#1 标题隔开列表', get(), '1. a|2. b|## h|1. c|2. d')
    -- #2 光标距列表 2 行仍重排
    set({ '1. a', '9. b', '', '', 'end' });                list.renumber_at(4);    check('R#2 附近三行内定位列表', get(), '1. a|2. b|||end')
    -- #3 浅续行不截断嵌套
    set({ '1. top', '    9. s1', '    9. s2', '   cont', '    9. s3' }); list.renumber_at(2)
    check('R#3 浅层续行不截断子列表', get(), '1. top|    1. s1|    2. s2|   cont|    3. s3')
    -- #5 单空行 loose list 仍连续；连续两个空行断开列表块
    set({ '1. a', '', '9. b' });                           list.renumber_at(1);    check('R#5 单空行保持宽松列表连续', get(), '1. a||2. b')
    set({ '1. a', '', '', '9. b' });                       list.renumber_at(1);    check('R#5 双空行隔开列表', get(), '1. a|||9. b')
    set({ '1. sdf', '2. sdfdsf', '3. sdf', '', '', '1. sdf', '2. ' }); list.renumber_at(6)
    check('R#5 独立有序列表不串号', get(), '1. sdf|2. sdfdsf|3. sdf|||1. sdf|2. ')
    -- #10 混合围栏（~~~ 内含 ```）
    set({ '1. a', '~~~md', '3. x', '```', '7. y', '~~~', '9. b' }); list.renumber_buffer()
    check('R#10 混合围栏保护列表内容', get(), '1. a|~~~md|3. x|```|7. y|~~~|2. b')
    -- #7 勾选框光标在标记内不重复
    check('R#7 标记内光标不重复勾选框', (function()
      set({ '1. [ ] task' }); vim.api.nvim_win_set_cursor(0, { 1, 1 }); list.continue(); return get()
    end)(), '1. |2. [ ] task')
    -- #8 行中冒号不触发缩进；行尾冒号仍触发
    check('R#8 行中冒号不触发缩进', continue_at_col({ '1. Note: x' }, 1, 8), '1. Note:|2.  x')
    check('R#8 行末冒号触发缩进', continue_at({ '1. foo:' }, 1), '1. foo:|  1. ')
    -- #11 checkbox 状态含 % 不损坏
    check('R#11 百分号状态不损坏替换', (function()
      local cb = require('vv-markdown.checkbox')
      cb._set_config_getter(function() return { checkbox = { states = { ' ', '%' } } } end)
      set({ '- [ ] t' }); cb.toggle_range(1, 1); local r = get()
      cb._set_config_getter(function() return { checkbox = { states = { ' ', 'x' } } } end)
      return r
    end)(), '- [%] t')
    -- bug2: normal o / O 新建项（缓冲区效果）
    set({ '1. a', '2. b' }); vim.api.nvim_win_set_cursor(0, { 1, 0 }); list.new_item_below(); vim.cmd('stopinsert')
    check('o 在下方插入新项', get(), '1. a|2. |3. b')
    set({ '1. a', '2. b' }); vim.api.nvim_win_set_cursor(0, { 2, 0 }); list.new_item_above(); vim.cmd('stopinsert')
    check('O 在上方插入新项', get(), '1. a|2. |3. b')
    -- o 在嵌套子项上 → 续子项
    set({ '1. a', '  1. x', '  2. y' }); vim.api.nvim_win_set_cursor(0, { 2, 0 }); list.new_item_below(); vim.cmd('stopinsert')
    check('o 续行子列表项', get(), '1. a|  1. x|  2. |  3. y')

    -- #4 混合 tab/space 同视觉深度（noexpandtab, tabstop=4）
    vim.bo.expandtab = false; vim.bo.tabstop = 4
    set({ '1. a', '\t1. x', '    9. y' }); list.renumber_at(1)
    check('R#4 tab 和空格按同一视觉层级重排', get(), '1. a|\t1. x|    2. y')
    vim.bo.expandtab = true; vim.bo.shiftwidth = 2
  end)
end

T["混合代码围栏与更长围栏保护内部行"] = function()
  child.lua_func(function()
    local list, set, get, check, continue_at, continue_at_col = Smoke.list, Smoke.set, Smoke.get, Smoke.check, Smoke.continue_at, Smoke.continue_at_col
    -- guard.lua regex_in_fence 混合围栏类型（Bug fix: ~~~ 内 ``` 不应错误关闭围栏）
    -- 直接测 guard 模块（headless 下无 treesitter → 走 regex 路径）
    local guard = require('vv-markdown.guard')
    set({ '~~~', '```lua', '1. item', '```', '~~~', 'normal' })
    -- row=3 ("1. item") 在 ~~~ 围栏内；旧代码第 2 行 ``` 会 toggle→false，row=3 误报 false
    check('混合围栏内行受到保护', guard.in_fence(3), true)
    -- row=6 ("normal") 在围栏外
    check('混合围栏外行不受保护', guard.in_fence(6), false)
    -- 四反引号围栏内含三反引号不应被关闭
    set({ '````', '```lua', 'code', '```', '````', 'end' })
    check('四反引号围栏内不被三反引号关闭', guard.in_fence(3), true)
    check('四反引号围栏外行正常', guard.in_fence(6), false)
  end)
end

T["使用视觉宽度反缩进含 tab 的列表项"] = function()
  child.lua_func(function()
    local list, set, get, check, continue_at, continue_at_col = Smoke.list, Smoke.set, Smoke.get, Smoke.check, Smoke.continue_at, Smoke.continue_at_col
    -- reindent dedent: expandtab=true 下 tab 缩进项应能反缩进（Bug fix: vwidth guard）
    vim.bo.expandtab = true; vim.bo.shiftwidth = 2; vim.bo.tabstop = 2
    -- tab 在 expandtab buffer 里，字节长度 1 < shiftwidth 2，旧代码会 return false
    set({ '- outer', '\t- inner' }); vim.api.nvim_win_set_cursor(0, { 2, 3 })
    check('空格模式按视觉宽度反缩进 tab', list.dedent(), true)
    -- 反缩进后 inner 项应变成 "- inner"（去掉 tab）
    check('反缩进完整读回去掉 tab', get(), '- outer|- inner')
  end)
end

T["离开 Markdown 恢复原导航映射并保留用户重绑"] = function()
  child.lua_func(function()
    local list, set, get, check, continue_at, continue_at_col = Smoke.list, Smoke.set, Smoke.get, Smoke.check, Smoke.continue_at, Smoke.continue_at_col
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
  end)
end

return T
