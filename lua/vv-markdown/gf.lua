--- Markdown 增强 gf：支持 `[text](path#anchor)` 链接跳转 + 锚点定位标题

local M = {}

local config_getter ---@type fun():VVMarkdown.Config
local handle ---@type VVKeymapHandle|nil

function M._set_config_getter(fn)
  config_getter = fn
end

local function open_link()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2] + 1

    local pos = 1
    while true do
      -- %b() 平衡匹配：链接目标本身含括号（如 Plan_(2024).md）不会被首个 ) 截断
      local s, e, group = line:find('%[.-%](%b())', pos)
      if not s then break end
      local path = group:sub(2, -2)        -- 去掉外层 ( )

      if col >= s and col <= e then
        if path:match('^https?://') then break end

        local file_path, anchor = path:match('^(.-)#(.+)$')
        if not file_path then
          file_path, anchor = path, nil
        end

        if file_path ~= '' then
          -- 绝对路径（/ 开头）或 ~ 家目录链接不能再拼当前 buffer 目录，否则得到 <bufdir>//abs
          local target = (file_path:sub(1, 1) == '/' or file_path:sub(1, 1) == '~')
            and vim.fn.fnamemodify(file_path, ':p')
            or vim.fn.expand('%:p:h') .. '/' .. file_path

          -- 当前窗口若开了 winfixbuf（vv-explorer / vv-git 等面板），:edit 会抛 E1513
          -- 先跳到一个普通（非锁定、非浮动）窗口再 edit，对齐 vv-git commands.lua 的处理
          local win = vim.api.nvim_get_current_win()
          if vim.wo[win].winfixbuf then
            for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
              if not vim.wo[w].winfixbuf and vim.api.nvim_win_get_config(w).relative == '' then
                vim.api.nvim_set_current_win(w)
                break
              end
            end
          end

          vim.cmd('edit ' .. vim.fn.fnameescape(target))
        end

        if anchor then
          -- 按 '-' 分段、每段用 \V very-nomagic 并 escape 反斜杠，保留「'-' → 通配」语义，
          -- 同时让锚点里的正则魔法字符（[ \ . 等）按字面匹配，不再炸 search() 也不过度匹配
          local parts = {}
          for seg in (anchor .. '-'):gmatch('(.-)%-') do
            parts[#parts + 1] = vim.fn.escape(seg, '\\')
          end
          local pattern = '\\c^#\\+.*\\V' .. table.concat(parts, '\\.\\*')
          vim.fn.cursor(1, 1)
          -- pcall 兜底：任何残留的非法 pattern 退化为「未找到」notify，不冒泡成红色 Vim 错误
          local ok, lnum = pcall(vim.fn.search, pattern, 'c')
          if not ok or lnum == 0 then
            vim.notify('Heading not found: #' .. anchor, vim.log.levels.WARN)
          end
        end

        return
      end

      pos = e + 1
    end

    -- 光标不在 markdown 链接上：回退到原生 gf
    -- 原生 gf 找不到文件会抛 E447，pcall 兜住避免冒泡成红色 E5108 traceback
    local ok = pcall(vim.cmd, 'normal! gf')
    if not ok then
      vim.notify('No file under cursor', vim.log.levels.WARN)
    end
end

function M.enable()
  if handle or not config_getter then return end

  local config = config_getter()
  handle = require('vv-utils.keymap').attach({
    id = 'vv-markdown.gf',
    filetypes = config.filetypes,
    enabled = function() return config_getter().gf_navigation end,
    mappings = {
      { mode = 'n', lhs = 'gf', rhs = open_link, opts = { desc = 'vv-markdown: gf 链接跳转' } },
    },
  })
end

function M.disable()
  if not handle then return end
  handle:detach()
  handle = nil
end

return M
