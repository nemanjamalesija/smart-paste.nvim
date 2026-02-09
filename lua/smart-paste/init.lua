local M = {}

local defaults = {
  keys = { 'p', 'P', 'gp', 'gP' },
  exclude_filetypes = {},
}

local INFERRED_FLAGS = {
  ['p'] = { after = true, follow = false, charwise_newline = false },
  ['P'] = { after = false, follow = false, charwise_newline = false },
  ['gp'] = { after = true, follow = true, charwise_newline = false },
  ['gP'] = { after = false, follow = true, charwise_newline = false },
  [']p'] = { after = true, follow = false, charwise_newline = true },
  ['[p'] = { after = false, follow = false, charwise_newline = true },
}

local VISUAL_ELIGIBLE = {
  p = true,
  P = true,
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

--- Normalize a key config entry to a canonical table shape.
--- Accepts legacy string entries and structured table entries.
--- Invalid entries are skipped by returning nil.
--- @param entry string|table
--- @return table|nil
local function normalize_key_entry(entry)
  if type(entry) == 'string' then
    local flags = INFERRED_FLAGS[entry]
    if flags then
      return {
        lhs = entry,
        after = flags.after,
        follow = flags.follow,
        charwise_newline = flags.charwise_newline,
      }
    end
    return { lhs = entry, after = true, follow = false, charwise_newline = false }
  end

  if type(entry) == 'table' then
    if type(entry.lhs) ~= 'string' then
      return nil
    end
    return {
      lhs = entry.lhs,
      after = entry.after or false,
      follow = entry.follow or false,
      charwise_newline = entry.charwise_newline or false,
    }
  end

  return nil
end

--- Initialize smart-paste with optional user configuration.
--- Merges user opts with defaults, registers keymaps for configured keys,
--- and sets up Plug escape hatches for raw paste access.
--- @param opts? table User configuration (keys, exclude_filetypes)
function M.setup(opts)
  local config = vim.tbl_deep_extend('force', defaults, opts or {})
  local normalized_keys = {}
  for _, entry in ipairs(config.keys) do
    local norm = normalize_key_entry(entry)
    if norm then
      table.insert(normalized_keys, norm)
    end
  end
  config.keys = normalized_keys
  M.config = config

  local paste = require('smart-paste.paste')

  clear_managed_keymaps()

  for _, entry in ipairs(config.keys) do
    vim.keymap.set('n', entry.lhs, function()
      if vim.tbl_contains(config.exclude_filetypes, vim.bo.filetype) then
        return entry.lhs
      end
      return paste.smart_paste(entry)
    end, { expr = true, desc = 'Smart paste: ' .. entry.lhs })
  end

  for _, entry in ipairs(config.keys) do
    if VISUAL_ELIGIBLE[entry.lhs] then
      vim.keymap.set('x', entry.lhs, function()
        local reg = vim.v.register
        local vmode = vim.fn.mode()

        if vim.tbl_contains(config.exclude_filetypes, vim.bo.filetype) then
          local raw_keys = 'gv"' .. reg .. entry.lhs
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(raw_keys, true, false, true), 'n', false)
          return
        end

        vim.cmd('normal! \27')
        paste.do_visual_paste(reg, entry.lhs, vmode)
      end, { desc = 'Smart paste: visual ' .. entry.lhs })
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
