local M = {}

--- @class SmartPasteKeyFlags
--- @field after boolean
--- @field follow boolean
--- @field charwise_newline boolean

--- @class SmartPasteKeyEntry : SmartPasteKeyFlags
--- @field lhs string

--- @class SmartPasteKeyInput
--- @field lhs string
--- @field like? string
--- @field after? boolean
--- @field follow? boolean
--- @field charwise_newline? boolean

--- @class SmartPasteConfig
--- @field keys SmartPasteKeyEntry[]
--- @field exclude_filetypes string[]

--- @class SmartPastePasteOpts
--- @field key? string|SmartPasteKeyInput Paste behavior key (default: 'p')
--- @field register? string Register override (example: '+')
--- @field count? number Paste count override

local defaults = {
  keys = { 'p', 'P', 'gp', 'gP', ']p', '[p' },
  exclude_filetypes = {},
}

--- @type table<string, SmartPasteKeyFlags>
local INFERRED_FLAGS = {
  ['p'] = { after = true, follow = false, charwise_newline = false },
  ['P'] = { after = false, follow = false, charwise_newline = false },
  ['gp'] = { after = true, follow = true, charwise_newline = false },
  ['gP'] = { after = false, follow = true, charwise_newline = false },
  [']p'] = { after = true, follow = false, charwise_newline = true },
  ['[p'] = { after = false, follow = false, charwise_newline = true },
}

--- @type table<string, boolean>
local VISUAL_ELIGIBLE = {
  p = true,
  P = true,
}

--- Normalize a register name to one Vim register character.
--- Accepts both '+' and '"+' forms.
--- @param register string|nil
--- @return string
local function normalize_register(register)
  if type(register) ~= 'string' or register == '' then
    return '"'
  end
  if vim.startswith(register, '"') and #register > 1 then
    return register:sub(2, 2)
  end
  return register:sub(1, 1)
end

--- Normalize optional count input.
--- @param count number|nil
--- @return number|nil
local function normalize_count(count)
  if type(count) ~= 'number' or count <= 0 then
    return nil
  end
  return math.floor(count)
end

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
--- @param entry string|SmartPasteKeyInput
--- @return SmartPasteKeyEntry|nil
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
    local like_flags
    if type(entry.like) == 'string' then
      like_flags = INFERRED_FLAGS[entry.like]
    end

    local after = entry.after
    if after == nil and like_flags then
      after = like_flags.after
    end
    if after == nil then
      after = false
    end

    local follow = entry.follow
    if follow == nil and like_flags then
      follow = like_flags.follow
    end
    if follow == nil then
      follow = false
    end

    local charwise_newline = entry.charwise_newline
    if charwise_newline == nil and like_flags then
      charwise_newline = like_flags.charwise_newline
    end
    if charwise_newline == nil then
      charwise_newline = false
    end

    return {
      lhs = entry.lhs,
      after = after,
      follow = follow,
      charwise_newline = charwise_newline,
    }
  end

  return nil
end

--- Initialize smart-paste with optional user configuration.
--- Merges user opts with defaults, registers keymaps for configured keys,
--- and sets up Plug escape hatches for raw paste access.
--- @param opts? table User configuration (keys, exclude_filetypes)
function M.setup(opts)
  --- @type { keys: (string|table)[], exclude_filetypes: string[] }
  local config = vim.tbl_deep_extend('force', defaults, opts or {})
  --- @type SmartPasteKeyEntry[]
  local normalized_keys = {}
  for _, raw_entry in ipairs(config.keys) do
    local norm = normalize_key_entry(raw_entry)
    if norm then
      table.insert(normalized_keys, norm)
    end
  end
  --- @type string[]
  local exclude_filetypes = config.exclude_filetypes
  --- @type SmartPasteConfig
  local normalized_config = {
    keys = normalized_keys,
    exclude_filetypes = exclude_filetypes,
  }
  M.config = normalized_config

  local paste = require('smart-paste.paste')

  clear_managed_keymaps()

  for _, entry in ipairs(normalized_keys) do
    vim.keymap.set('n', entry.lhs, function()
      if vim.tbl_contains(exclude_filetypes, vim.bo.filetype) then
        return entry.lhs
      end
      return paste.smart_paste(entry)
    end, { expr = true, desc = 'Smart paste: ' .. entry.lhs })
  end

  for _, entry in ipairs(normalized_keys) do
    if VISUAL_ELIGIBLE[entry.lhs] then
      vim.keymap.set('x', entry.lhs, function()
        local reg = vim.v.register
        local vmode = vim.fn.mode()

        if vim.tbl_contains(exclude_filetypes, vim.bo.filetype) then
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

--- Perform smart paste programmatically from an optional explicit register.
--- Useful for custom non-recursive mappings (for example: system clipboard).
--- @param opts? SmartPastePasteOpts
function M.paste(opts)
  opts = opts or {}

  local paste = require('smart-paste.paste')
  local entry = normalize_key_entry(opts.key or 'p') or normalize_key_entry('p')
  local register = normalize_register(opts.register or vim.v.register)
  local count = normalize_count(opts.count)
  local exclude = (M.config and M.config.exclude_filetypes) or defaults.exclude_filetypes

  if vim.tbl_contains(exclude, vim.bo.filetype) then
    local raw_count = count or vim.v.count1
    local raw_keys = '"' .. register .. tostring(raw_count) .. entry.lhs
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(raw_keys, true, false, true), 'n', false)
    return
  end

  local trigger = paste.smart_paste(entry, { register = register, count = count })
  vim.cmd('normal! ' .. trigger)
end

return M
