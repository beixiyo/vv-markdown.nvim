# Changelog

## 0.3.0 - 2026-07-13

### Added

- 新增 `gf_navigation`，增强 `gf` 的 `text(path#anchor)` 文件与标题锚点跳转（LSP 优先）

### Fixed

- 非链接上的 `gf` 找不到文件时改为温和提示，链接跳转可避开 `winfixbuf` 面板窗口限制
- `gf` 正确打开绝对路径、`~/` 路径及含括号的链接目标
- 锚点含正则特殊字符时不再报错或误匹配标题
- 重复触发 FileType 不再累积 buffer-local 自动命令
- 无 treesitter 时，代码块守卫正确识别混合类型及不同长度的围栏
- tab 或混合缩进列表项可按视觉宽度正确反缩进
- 删除 buffer 或禁用插件时取消待定自动重排，防止遗留任务
- 保存前同步重排，避免与 render-markdown 异步渲染竞争导致越界崩溃
- 防抖期间切换 buffer 不再漏掉原 buffer 的重排
- checkbox 多字节状态可正常循环，不再重复插入空框

## v0.1.0

首个版本

### Added

- insert `<CR>` 智能续行：支持有序自增、无序列表、缩进、尾部文本下移、`1)` 标记、checkbox 续空、行尾冒号缩进及空项退出 / 反缩进
- normal `o` / `O` 同样支持列表续行，非列表行保留原生行为
- 编辑后防抖自动重排有序列表，嵌套层级独立编号，重复重排不产生递归编辑
- `<C-t>` / `<C-d>` 缩进或反缩进列表项并重排，非列表行保留原生行为
- checkbox 支持单行 / Visual 范围切换及多状态循环
- 代码块内禁用列表操作，treesitter 优先、regex 回退
- 非列表行 `<CR>` 回退 `MiniPairs.cr()`，与 mini.pairs 共存
- 新增命令 `VVMarkdownEnable` / `VVMarkdownDisable` / `VVMarkdownToggle` / `VVMarkdownRenumber` / `VVMarkdownToggleCheckbox`
- 新增 `settle_treesitter`（默认 `true`），编辑后刷新 Markdown 树，减少中间编辑状态并避免 render-markdown 读取过期树越界

### Fixed

- 缩进列表项不再被误判为代码块，混合围栏类型不再干扰列表编号
- 重排在分隔线、标题与顶层段落处重置，不再跨独立列表串号
- 光标位于标记或勾选框内时回车不再重复 checkbox，状态字符含 `%` 时替换正常
- 自动重排可从光标附近 ±3 行定位列表，较浅的续行缩进或多个空行不再截断列表块
- 混合 tab / space 按视觉宽度统一层级编号，行中冒号不再误触发缩进
