# Changelog

## [Unreleased]

### Added

- `gf_navigation`：增强 `gf` 跳转，支持 `[text](path#anchor)` 链接解析 + 锚点定位标题（LSP 优先）

### Fixed

- `gf` 光标不在链接上时回退 `normal! gf`，找不到文件抛 E447 冒泡成红色 E5108 traceback；改为 pcall 兜住 + 温和提示。链接 `:edit` 前先逃出 `winfixbuf` 窗口（vv-explorer / vv-git 等面板），避免 E1513
- `gf` 绝对路径链接（`/abs/p.md` 或 `~/...`）不再无条件拼当前 buffer 目录得到 `<bufdir>//abs/p.md` 静默开空 buffer；检测到 `/` 或 `~` 开头改走 `fnamemodify(:p)` 直接打开真实文件
- `gf` 链接目标含括号（如 `Plan_(2024).md` / 维基风 URL）被非贪婪 `(.-)%)` 截断到首个 `)`；改用 Lua 平衡匹配 `%b()` 完整捕获目标
- `gf` 锚点片段原样注入 Vim 正则（`#anchor` 含 `[` / `\` / `.` 等魔法字符时炸 E54 冒泡或过度匹配到错误标题）；改为按 `-` 分段 + `\V` very-nomagic + `escape`，并 pcall 包裹 `search` 退化为温和「未找到」提示
- `install_keymaps` 的三个 buffer-local autocmd（`TextChanged`/`BufDelete`/`BufWritePre`）在 `FileType` 对同一 buffer 重复触发（`:set ft` 重设 / `:edit` 重载）时逐次累积、句柄泄漏；建 autocmd 前先 `nvim_clear_autocmds({ group, buffer })` 保证每类恰好 1 个
- `guard.lua` regex 回退路径（treesitter 不可用时）：混合围栏类型（`~~~` 内含 ` ``` ` 或四反引号围栏含三反引号）导致奇偶错乱、`in_fence` 误报；改为字符+长度感知的开/闭状态机，与 `renumber_range` 逻辑对齐
- `reindent()` 反缩进守卫用字节长度比较 `#p.indent < shiftwidth`，在 `expandtab=true` 文件中遇到 tab 缩进项（字节长 1 < shiftwidth 4）时静默拒绝；改为 `vwidth` 视觉宽度比较，并用逐字符视觉消耗正确剥离混合缩进
- 自动重排防抖改为复用 `vv-utils.timer.debounce`（每 buffer 独立实例），去掉手搓 token 计数；`BufDelete` 时 `cancel()` 关闭 uv timer 句柄，`disable()` 时统一 cancel 所有待定 timer
- 新增 `BufWritePre` 钩子：保存前取消待定防抖并同步重排，修复 debounce 在 `BufWritePost` 后触发、与 render-markdown 异步渲染竞争 treesitter 节点导致的 *Index out of bounds* 崩溃（`node.lua:34` 无 pcall 守卫）
- `schedule_renumber` 回调用 `nvim_win_call` 包裹 `renumber_at`，确保 `buf_get` 的 `0` 句柄解析到正确 buffer（原来靠 `get_current_buf() ~= buf` 丢弃，用户在防抖窗口内切换 buffer 会静默漏排）
- `list.parse` 用 `^%[(.)%]` 单字节捕获 checkbox，配置多字节状态（如 `✓` / `✗` / `☐`）解析回 `nil`、再次切换会重复插入空框而非循环；改为 `^%[([^%]]+)%]` 捕获完整字形，多字节状态可正常循环

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
