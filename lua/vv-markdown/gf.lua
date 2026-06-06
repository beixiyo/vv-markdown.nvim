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

    vim.cmd('normal! gf')
  end, { buffer = buf, desc = 'vv-markdown: gf 链接跳转' })
end

return M
