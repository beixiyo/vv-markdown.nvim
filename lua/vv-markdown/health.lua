-- :checkhealth vv-markdown

local M = {}

function M.check()
  local h = vim.health
  h.start('vv-markdown')

  -- Neovim 版本
  if vim.fn.has('nvim-0.10') == 1 then
    h.ok('Neovim >= 0.10')
  else
    h.error('需要 Neovim >= 0.10')
  end

  -- treesitter markdown parser（可选增强）
  local ts_ok = pcall(vim.treesitter.language.add, 'markdown')
  if ts_ok then
    h.ok('treesitter markdown parser 可用：代码块守卫精确')
  else
    h.warn('未安装 treesitter markdown parser：代码块守卫回退 regex 围栏计数',
      { '安装：`:TSInstall markdown markdown_inline`' })
  end

  -- mini.pairs（可选）
  if pcall(require, 'mini.pairs') then
    h.ok('mini.pairs 已安装：非列表行 <CR> 回退自动配对')
  else
    h.info('未检测到 mini.pairs：非列表行 <CR> 走原生换行')
  end

  -- render-markdown 共存提醒
  if pcall(require, 'render-markdown') then
    h.warn('检测到 render-markdown.nvim：其默认会按 treesitter 位置重算有序序号显示，可能与本插件冲突',
      {
        '建议在 render-markdown setup 中设：',
        "bullet = { ordered_icons = function(ctx) return vim.trim(ctx.value) end }",
        '详见 README「与 render-markdown 共存」',
      })
  end
end

return M
