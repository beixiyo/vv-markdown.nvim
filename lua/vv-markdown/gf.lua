--- Markdown 增强 gf：支持 `[text](path#anchor)` 链接跳转 + 锚点定位标题

local M = {}

local config_getter ---@type fun():VVMarkdownConfig

function M._set_config_getter(fn)
  config_getter = fn
end

function M.setup(buf)
  if not config_getter or not config_getter().gf_navigation then return end

  vim.keymap.set('n', 'gf', function()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2] + 1

    local pos = 1
    while true do
      local s, e, path = line:find('%[.-%]%((.-)%)', pos)
      if not s then break end

      if col >= s and col <= e then
        if path:match('^https?://') then break end

        local file_path, anchor = path:match('^(.-)#(.+)$')
        if not file_path then
          file_path, anchor = path, nil
        end

        if file_path ~= '' then
          local dir = vim.fn.expand('%:p:h')

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

          vim.cmd('edit ' .. vim.fn.fnameescape(dir .. '/' .. file_path))
        end

        if anchor then
          local pattern = '^\\c#\\+.*' .. anchor:gsub('%-', '.*')
          vim.fn.cursor(1, 1)
          if vim.fn.search(pattern, 'c') == 0 then
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
  end, { buffer = buf, desc = 'vv-markdown: gf 链接跳转' })
end

return M
