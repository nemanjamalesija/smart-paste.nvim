local M = {}
local indent = require('smart-paste.indent')

-- Module-level state: captured BEFORE g@l fires (v:register and v:count1 reset after)
local state = {}

--- Expression mapping target for smart paste.
--- Captures the current register, count, and key into module state,
--- sets up the operatorfunc for dot-repeat, and returns the g@ trigger.
---
--- Must be called from an `{ expr = true }` keymap. The returned string
--- `'g@l'` is fed back to Vim as if typed, which triggers `do_paste`
--- via operatorfunc. On dot-repeat, Vim replays `g@l` automatically,
--- re-invoking `do_paste` with the same captured state.
---
--- @param key string One of 'p', 'P', 'gp', 'gP'
--- @return string The keysequence 'g@l' to trigger operatorfunc
function M.smart_paste(key)
  state.register = vim.v.register
  state.count = vim.v.count1
  state.key = key
  vim.go.operatorfunc = "v:lua.require'smart-paste.paste'.do_paste"
  return 'g@l'
end

--- Operatorfunc callback that performs the actual paste.
--- Reads the register (never mutates it), computes indent delta for
--- linewise content, and places text via a single `nvim_put` call
--- for undo atomicity. Charwise and blockwise registers fall through
--- to vanilla paste via `nvim_feedkeys`.
---
--- @param _motion_type string Ignored; required by operatorfunc signature
function M.do_paste(_motion_type)
  local reg = state.register
  local count = state.count
  local key = state.key

  -- Fallback defaults for safety
  if not reg then reg = '"' end
  if not count then count = 1 end
  if not key then key = 'p' end

  local reginfo = vim.fn.getreginfo(reg)
  if not reginfo or not reginfo.regcontents then
    return
  end

  -- Gate: only linewise registers get smart indentation
  if not vim.startswith(reginfo.regtype, 'V') then
    local raw_keys = '"' .. reg .. tostring(count) .. key
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes(raw_keys, true, false, true),
      'n', false
    )
    return
  end

  local lines = reginfo.regcontents

  -- Compute indent delta using the indent engine
  local source_indent = indent.get_source_indent(lines)
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed
  local target_indent = indent.get_target_indent(bufnr, row)
  local delta = target_indent - source_indent
  local adjusted = indent.apply_delta(lines, delta, bufnr)

  -- Handle count: repeat adjusted lines N times
  local final_lines = {}
  for _ = 1, count do
    for _, line in ipairs(adjusted) do
      table.insert(final_lines, line)
    end
  end

  -- Place text: single nvim_put call = single undo step
  local after = (key == 'p' or key == 'gp')
  local follow = (key == 'gp' or key == 'gP')
  vim.api.nvim_put(final_lines, 'l', after, follow)
end

--- Test helper (not part of public API).
--- Allows tests to set module state directly without going through smart_paste.
--- @param reg string Register name
--- @param count number Paste count
--- @param key string Paste key ('p', 'P', 'gp', 'gP')
function M._test_set_state(reg, count, key)
  state.register = reg
  state.count = count
  state.key = key
end

return M
