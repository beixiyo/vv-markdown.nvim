<div align="center">
  <h1>vv-markdown.nvim</h1>
  <p>English | <a href="./README.zh-CN.md">中文</a></p>
  <p>Want my Neovim config? See <a href="https://github.com/beixiyo/dotfiles">dotfiles</a></p>
  <p>Smart Markdown list editing: continuation, incrementing, renumbering, indentation, and checkboxes</p>
  <p>
    <img src="https://img.shields.io/badge/Neovim-0.10+-57A143?style=flat-square&logo=neovim&logoColor=white" alt="Requires Neovim 0.10+" />
    <img src="https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white" alt="Lua" />
  </p>
</div>

Implemented with pure-Lua line scanning, powered by `vv-utils.nvim`, compatible with `mini.pairs`, and optionally enhanced by treesitter and LSP.

## Requirements

- Neovim >= 0.10
- **[vv-utils.nvim](https://github.com/beixiyo/vv-utils.nvim)** is required for debounce timers
- The treesitter `markdown` parser is optional and improves code-fence detection; otherwise a regex fence counter is used
- `mini.pairs` is optional and receives non-list `<CR>` fallbacks
- `render-markdown.nvim` is optional; see the compatibility section below

## Features

| Capability | Description |
|------------|-------------|
| **Smart continuation** | Insert-mode `<CR>` increments ordered items (`1.` → `2.`), copies unordered markers (`-`, `*`, `+`), preserves indentation, moves trailing text to the next line, supports `1)` markers, and continues checkbox items with `[ ]` |
| **`o` / `O` continuation** | Normal-mode `o` and `O` create list items like insert-mode `<CR>`; non-list lines retain native behavior |
| **Automatic renumbering** | After deletion, paste, undo, or indentation changes, `TextChanged` normalizes ordered lists to `1, 2, 3`; processing is debounced, idempotent, and does not block input |
| **Indentation signatures** | Nested levels are numbered independently; indenting into a child list restarts at `1`; tabs and spaces are normalized by visual width |
| **Leaving an empty item** | Pressing Enter on an empty item dedents one level or exits the list |
| **Colon indentation** | Pressing Enter after a trailing `:` indents the new item by one level |
| **Indent and dedent** | Insert-mode `<C-t>` and `<C-d>` indent or dedent the current item and renumber it; non-list lines retain native behavior |
| **Checkbox toggle** | Cycles `[ ]` and `[x]`, or a configurable state sequence, for one Normal-mode line or a Visual-mode range |
| **Code-fence guard** | Continuation and renumbering are disabled inside fenced code blocks; treesitter is preferred, with a marker-aware regex fallback |
| **`mini.pairs` compatibility** | Non-list `<CR>` falls back to `MiniPairs.cr()`, preserving paired-brace and quote newlines |
| **Enhanced `gf` navigation** | Resolves `[text](path#anchor)` links and heading anchors, preferring an LSP such as marksman when available |

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'beixiyo/vv-markdown.nvim',
  ft = 'markdown',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  opts = {},   -- See Configuration below
}
```

`vim.pack` on Neovim 0.12+:

```lua
vim.pack.add({ 'https://github.com/beixiyo/vv-markdown.nvim' })
require('vv-markdown').setup({})
```

## Configuration

Call `setup()` to enable the plugin. These are the defaults:

```lua
require('vv-markdown').setup({
  enabled = true,
  filetypes = { 'markdown' },
  continue = true,              -- Continue lists with insert-mode <CR>
  auto_renumber = true,         -- Renumber after TextChanged
  renumber_debounce = 60,       -- Debounce delay in milliseconds
  colon_indent = true,          -- Indent a child item after a trailing colon
  dedent_empty = true,          -- Dedent an empty item, otherwise clear it and leave the list
  mini_pairs_fallback = true,   -- Fall back to mini.pairs outside lists
  settle_treesitter = true,     -- Refresh the Markdown tree after editing
  gf_navigation = true,         -- Resolve [text](path#anchor) links with gf
  checkbox = { states = { ' ', 'x' } }, -- May be { ' ', '-', 'x' }
  keymaps = {
    continue = '<CR>',
    indent = '<C-t>',
    dedent = '<C-d>',
    open_below = 'o',
    open_above = 'O',
    toggle_checkbox = '<leader>x',
    renumber = '<leader>nn',
  },
})
```

Set any keymap to `false` to disable it. Every mapping is buffer-local and limited to the `markdown` filetype.

## Commands

`:VVMarkdownEnable`, `:VVMarkdownDisable`, `:VVMarkdownToggle`, `:VVMarkdownRenumber`, and `:VVMarkdownToggleCheckbox`, which supports a range.

## Coexisting with render-markdown.nvim

By default, `render-markdown.nvim` uses `bullet.ordered_icons` to recalculate displayed numbers from treesitter sibling positions. vv-markdown keeps the correct numbers in the real buffer, and the two plugins may disagree about the indentation that creates nesting. For example, the marker `1. ` is three columns wide, so a child indented by two spaces can be parsed as a flat list and displayed as `3.`.

Let render-markdown display the source number so the buffer remains the single source of truth:

```lua
require('render-markdown').setup({
  bullet = {
    ordered_icons = function(ctx) return vim.trim(ctx.value) end,
  },
})
```

For numbering that also nests correctly in external renderers such as GitHub, indent by at least the parent marker width: three spaces after `1. ` and four after `10. `.

## Command-line test

```sh
nvim --headless -c "lua vim.bo.filetype='markdown'" \
  -c "luafile tests/test_smoke.lua" -c "qa!"
```

## Known limitations

- Lists inside blockquotes, such as `> 1. a`, are not currently continued or renumbered
- When a number grows from `9.` to `10.`, continuation-line indentation aligned to the content is not adjusted automatically; fixed indentation is unaffected
- Automatic renumbering locates the list block from an anchor within three lines of the cursor after an edit. If the cursor ends farther away, use `<leader>nn` or `:VVMarkdownRenumber`

## Design

- The continuation hot path uses **regex line scanning**, because the treesitter node for the line currently being edited can be stale
- Renumbering uses an **indentation signature**: each visual indentation width owns a counter, and entering a shallower level clears deeper counters, naturally isolating nested lists
- Renumbering is **idempotent** and changes only differing numeric spans, so `TextChanged` cannot trigger a recursive edit loop
- `<CR>` uses a **buffer-local expression mapping** that shadows the global `mini.pairs` mapping. List lines run the continuation command, while non-list lines return `MiniPairs.cr()`

## License

MIT
