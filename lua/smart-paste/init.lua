local M = {}

local defaults = {
  keys = { 'p', 'P', 'gp', 'gP' },
  exclude_filetypes = {},
}

--- Remove any previously managed smart-paste keymaps so re-running setup()
--- (including module reload workflows) does not leave stale mappings behind.
local function clear_managed_keymaps()
  for _, mode in ipairs({ 'n', 'x' }) do
    local maps = vim.api.nvim_get_keymap(mode)
    for _, map in ipairs(maps) do
      if map.desc and map.desc:match('^Smart paste:') then
        pcall(vim.keymap.del, mode, map.lhs)
      end
    end
  end
end

--- Initialize smart-paste with optional user configuration.
--- Merges user opts with defaults, registers keymaps for configured keys,
--- and sets up Plug escape hatches for raw paste access.
--- @param opts? table User configuration (keys, exclude_filetypes)
function M.setup(opts)
  local config = vim.tbl_deep_extend('force', defaults, opts or {})
  M.config = config

  local paste = require('smart-paste.paste')

  clear_managed_keymaps()

  for _, key in ipairs(config.keys) do
    vim.keymap.set('n', key, function()
      if vim.tbl_contains(config.exclude_filetypes, vim.bo.filetype) then
        return key
      end
      return paste.smart_paste(key)
    end, { expr = true, desc = 'Smart paste: ' .. key })
  end

  for _, key in ipairs(config.keys) do
    if key == 'p' or key == 'P' then
      vim.keymap.set('x', key, function()
        local reg = vim.v.register
        local vmode = vim.fn.mode()

        if vim.tbl_contains(config.exclude_filetypes, vim.bo.filetype) then
          local raw_keys = 'gv"' .. reg .. key
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(raw_keys, true, false, true), 'n', false)
          return
        end

        vim.cmd('normal! \27')
        paste.do_visual_paste(reg, key, vmode)
      end, { desc = 'Smart paste: visual ' .. key })
    end
  end

  vim.keymap.set('n', '<Plug>(smart-paste-raw-p)', 'p', {
    noremap = true,
    desc = 'Raw paste after (bypass smart-paste)',
  })
  vim.keymap.set('n', '<Plug>(smart-paste-raw-P)', 'P', {
    noremap = true,
    desc = 'Raw paste before (bypass smart-paste)',
  })
end

return M
