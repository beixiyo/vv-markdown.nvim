# vv-markdown.nvim

Markdown 列表智能编辑：续行 / 自增 / 自动重排 / 缩进 / 勾选。纯 Lua 行扫描，依赖 `vv-utils.nvim`，与 `mini.pairs` 共存，treesitter / LSP 仅作可选增强

## 功能

| 能力 | 说明 |
|------|------|
| **智能续行** | insert `<CR>`：有序自增（`1.`→`2.`）、无序复制（`- * +`）、缩进保持、光标后文本下移、`1)` 风格、checkbox 项续空 `[ ]` |
| **o / O 续行** | normal `o` / `O` 新建列表项，等价 insert `<CR>`；非列表行回退原生 |
| **自动重排** | 删除 / 粘贴 / 撤销 / 缩进后（`TextChanged`）自动把有序列表归一为 `1,2,3`，防抖、幂等、不卡输入 |
| **缩进签名** | 嵌套列表各层独立编号；缩进成子列表自动从 `1` 重排；tab/space 按视觉宽度归一 |
| **空项退出** | 空列表项上回车 → 反缩进一级，或退出列表 |
| **冒号缩进** | 行尾 `:` 回车 → 新项自动缩进一级 |
| **缩进增减** | insert `<C-t>` / `<C-d>` 缩进 / 反缩进当前项并重排（非列表行回退原生） |
| **勾选切换** | `[ ]` ↔ `[x]`（可配置多状态循环），normal 单行 / visual 范围 |
| **代码块守卫** | 围栏代码块内不续行、不重排（treesitter 优先，regex 回退，标记感知） |
| **mini.pairs 共存** | 非列表行 `<CR>` 回退 `MiniPairs.cr()`，`{}` / 引号 自动配对换行不失效 |
| **gf 导航增强** | `[text](path#anchor)` 链接解析跳转，支持锚点定位标题，LSP（marksman）优先 |

## 要求

- Neovim >= 0.10
- **[vv-utils.nvim](https://github.com/beixiyo/vv-utils.nvim)**（必需）—— 防抖计时器
- 可选 treesitter `markdown` parser —— 代码块守卫更精确，无则 regex 围栏计数回退
- 可选 `mini.pairs` —— 非列表行 `<CR>` 回退自动配对
- 可选 `render-markdown.nvim` —— 见下方「与 render-markdown 共存」

## 安装

[lazy.nvim](https://github.com/folke/lazy.nvim)：

```lua
{
  'beixiyo/vv-markdown.nvim',
  ft = 'markdown',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  opts = {},   -- 见下方「配置」
}
```

`vim.pack`（Neovim 0.12+）：

```lua
vim.pack.add({ 'https://github.com/beixiyo/vv-markdown.nvim' })
require('vv-markdown').setup({})
```

## 配置

调用 `setup()` 即生效，以下为默认值：

```lua
require('vv-markdown').setup({
  enabled = true,
  filetypes = { 'markdown' },
  continue = true,              -- insert <CR> 续行
  auto_renumber = true,         -- TextChanged 后自动重排
  renumber_debounce = 60,       -- 防抖 ms
  colon_indent = true,          -- 行尾冒号缩进子项
  dedent_empty = true,          -- 空项回车反缩进（否则清空退出）
  mini_pairs_fallback = true,   -- 非列表行回退 mini.pairs
  settle_treesitter = true,     -- 编辑后同步刷新 md 树（防 render-markdown 读过期树越界）
  gf_navigation = true,                -- 增强 gf：解析 [text](path#anchor) 链接跳转
  checkbox = { states = { ' ', 'x' } },  -- 勾选循环序列，可设 { ' ', '-', 'x' }
  keymaps = {
    continue = '<CR>',          -- insert
    indent = '<C-t>',           -- insert
    dedent = '<C-d>',           -- insert
    open_below = 'o',           -- normal
    open_above = 'O',           -- normal
    toggle_checkbox = '<leader>x',  -- normal / visual
    renumber = '<leader>nn',    -- normal，整表重排
  },
})
```

任一 keymap 设为 `false` 即关闭。所有键均为 **buffer-local + ft=markdown**，不污染其它 filetype

## 命令

`:VVMarkdownEnable` / `Disable` / `Toggle`、`:VVMarkdownRenumber`、`:VVMarkdownToggleCheckbox`（支持 range）

## 与 render-markdown.nvim 共存

render-markdown 默认 `bullet.ordered_icons` 会按 **treesitter 兄弟位置**重算有序序号的显示。本插件已在真实 buffer 维护正确编号，二者对「缩进多少算嵌套」判定可能不一致 —— 例如有序标记 `1. ` 宽度为 3，用 2 空格缩进的嵌套项 treesitter 视为扁平列表，会把 `1.` 显示成 `3.`

建议让 render-markdown 直接显示原文（单一数据源）：

```lua
require('render-markdown').setup({
  bullet = {
    ordered_icons = function(ctx) return vim.trim(ctx.value) end,
  },
})
```

> 若希望编号在 GitHub 等外部渲染器也正确嵌套，请用 **≥ 父标记宽度**的缩进（`1. ` → 3 格，`10. ` → 4 格）

## 命令行测试

```sh
nvim --headless -c "lua vim.bo.filetype='markdown'" \
  -c "luafile tests/test_smoke.lua" -c "qa!"
```

## 已知限制

- **blockquote 内列表**（`> 1. a`）暂不解析续行 / 重排
- 序号宽度变化（`9.`→`10.`）时，**内容对齐**的续行子行缩进不自动跟随（固定缩进不受影响）
- 自动重排在编辑后以**光标附近 ±3 行**为锚定位列表块；若编辑使光标停在离列表更远处，需手动 `<leader>nn` / `:VVMarkdownRenumber`

## 设计

- 续行热路径用 **regex 行扫描**（treesitter 当前编辑行 stale，不可靠）
- 重排用**缩进签名**：以缩进视觉宽度为 key 各维护计数器，遇更浅缩进清空更深层级 → 嵌套天然独立
- 重排**幂等**（只改差异数字片段），故由 `TextChanged` 触发也不会自激递归
- `<CR>` 用 **buffer-local expr** 映射遮蔽 mini.pairs 全局映射，列表行走 `<Cmd>continue<CR>`、非列表行 `return MiniPairs.cr()`

## License

MIT
