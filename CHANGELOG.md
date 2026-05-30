# Changelog

## v0.1.0

首个版本。

- insert `<CR>` 智能续行：有序自增、无序复制、缩进保持、光标后文本下移、`1)` 风格、checkbox 续空、行尾冒号缩进子项、空项退出/反缩进。
- `TextChanged` 防抖自动重排：删除/粘贴/撤销/缩进后归一有序列表，缩进签名隔离嵌套，幂等防递归。
- `<C-t>`/`<C-d>` 缩进/反缩进当前项并重排（非列表行回退原生）。
- checkbox 切换/多态循环（normal + visual range）。
- 代码块守卫（treesitter 优先，regex 回退）。
- 与 mini.pairs 共存：非列表行 `<CR>` 回退 `MiniPairs.cr()`。
- 用户命令 `VVMarkdownEnable/Disable/Toggle/Renumber/ToggleCheckbox`。

### 对抗审查加固（11 处确认 bug 全修，回归用例覆盖）

- 代码块守卫不再把 4+ 空格缩进列表项误判为 indented_code_block（续行不再静默失效）。
- 围栏标记感知：`~~~` 内的 ` ``` `（及反之）不再造成奇偶错乱破坏序号。
- 整表重排在 HR / 标题 / 顶层段落处重置计数，不跨独立列表串号。
- 光标落在标记/勾选框内回车不再重复 checkbox。
- 自动重排种子定位放宽到 ±3 行；续行缩进比嵌套项浅不再截断块；2+ 空行 loose list 不再断。
- 重排计数按**视觉宽度**归一，混合 tab/space 同级不再各自计数。
- `colon_indent` 仅在行尾冒号触发，行中冒号不再误缩进。
- checkbox 状态字符含 `%` 不再损坏替换串。

### 列表交互补全

- normal 模式 `o` / `O` 新建列表项（有序自增 / 无序复制 / 缩进保持 / checkbox 续空），
  等价 insert `<CR>` 续行；非列表行回退原生 `o` / `O`。

### render-markdown 共存加固

- `continue()` 改为单次原子 `nvim_buf_set_lines`（替换一行为两行），减少中间缓冲区状态。
- 新增 `settle_treesitter`（默认 true）：每次续行/缩进/重排/勾选编辑后同步 `parser:parse()` 刷新 md 树，
  关掉本插件编辑造成的「树过期」窗口，避免 render-markdown 在调度渲染里用过期树 `get_node_text` 越界
  （render-markdown `node.lua:34` 未 pcall 守卫，属其健壮性缺口）。
