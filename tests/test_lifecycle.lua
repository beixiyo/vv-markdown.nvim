-- 真实场景在独立子进程中执行；收集阶段仅注册具名用例。
local H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
local T, child = H.new_set()

T["重配置释放旧资源并只保留当前渲染与键位所有权"] = function()
  child.lua_func(function()
    -- 生命周期回归：setup 替换旧文件类型、键位和自动命令资源。


    local function local_map(buf, mode, lhs)
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
        if map.lhs == lhs then return map end
      end
    end

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
    assert((local_map(buf, 'i', '<F28>') or {}).desc == 'vv-markdown: 续行',
      '首次 setup 应接管配置的 Markdown 映射')
    assert((local_map(buf, 'n', 'gf') or {}).desc == 'vv-markdown: gf 链接跳转',
      '首次 setup 应接管 Markdown 的 gf 映射')
    assert(#vim.api.nvim_get_autocmds({ group = 'VVMarkdown', buffer = buf }) == 3,
      '首次 setup 应只拥有三个缓冲生命周期自动命令')

    markdown.setup({
      enabled = true,
      filetypes = { 'text' },
      keymaps = vim.tbl_extend('force', disabled_keymaps, { continue = '<F29>' }),
    })
    assert((local_map(buf, 'i', '<F28>') or {}).desc == 'existing F28',
      '重配置应恢复被旧配置覆盖的原映射')
    assert((local_map(buf, 'n', 'gf') or {}).desc == 'existing gf',
      '重配置应按旧文件类型配置释放 gf')
    assert(local_map(buf, 'i', '<F29>') == nil,
      '旧文件类型缓冲不应安装新映射')
    assert(#vim.api.nvim_get_autocmds({ group = 'VVMarkdown', buffer = buf }) == 0,
      '旧文件类型不应保留缓冲生命周期自动命令')

    vim.bo[buf].filetype = 'text'
    vim.api.nvim_exec_autocmds('FileType', { buffer = buf, modeline = false })
    assert((local_map(buf, 'i', '<F29>') or {}).desc == 'vv-markdown: 续行',
      '新文件类型应安装新映射')
    assert((local_map(buf, 'n', 'gf') or {}).desc == 'vv-markdown: gf 链接跳转',
      '新文件类型应安装新 gf 映射')
    assert(#vim.api.nvim_get_autocmds({ group = 'VVMarkdown', buffer = buf }) == 3,
      '新文件类型应只有一组缓冲生命周期自动命令')

    markdown.setup({
      enabled = false,
      filetypes = { 'text' },
      keymaps = vim.tbl_extend('force', disabled_keymaps, { continue = '<F29>' }),
    })
    assert(local_map(buf, 'i', '<F29>') == nil,
      '禁用 setup 应释放先前启用实例的映射')
    assert((local_map(buf, 'n', 'gf') or {}).desc == 'existing gf',
      '禁用 setup 应恢复原 gf 映射')
    local has_group = pcall(vim.api.nvim_get_autocmds, { group = 'VVMarkdown' })
    assert(not has_group, '禁用 setup 应移除旧自动命令组')

    pcall(vim.keymap.del, 'i', '<F28>', { buffer = buf })
    pcall(vim.keymap.del, 'n', 'gf', { buffer = buf })
    vim.api.nvim_buf_delete(buf, { force = true })

  end)
end

return T
