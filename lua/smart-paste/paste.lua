local M = {}
local indent = require('smart-paste.indent')

-- Module-level state: captured BEFORE g@l fires (v:register and v:count1 reset after)
local state = {}

--- Repeat a list of lines `count` times.
--- @param lines string[]
--- @param count number
--- @return string[]
local function repeat_lines(lines, count)
  local out = {}
  for _ = 1, count do
    for _, line in ipairs(lines) do
      table.insert(out, line)
    end
  end
  return out
end

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
  local final_lines = repeat_lines(adjusted, count)

  -- Place text: single nvim_put call = single undo step
  local after = (key == 'p' or key == 'gp')
  local follow = (key == 'gp' or key == 'gP')
  vim.api.nvim_put(final_lines, 'l', after, follow)
end

--- Perform smart visual-mode paste for a previously selected region.
--- Supports smart indentation only for linewise visual mode (`V`), and falls
--- back to vanilla visual paste for charwise/blockwise selections.
---
--- The caller is expected to exit visual mode before invoking this function so
--- that `'<` and `'>` marks represent the latest visual selection.
---
--- @param reg string Register name
--- @param key string Paste key (`p` or `P`)
--- @param vmode string Visual mode kind (`v`, `V`, or blockwise)
--- @param count_override? number Optional count override (test helper)
function M.do_visual_paste(reg, key, vmode, count_override)
  if not reg or reg == '' then
    reg = '"'
  end
  if not key or key == '' then
    key = 'p'
  end

  -- Gate: only linewise visual selections get smart indentation.
  if vmode ~= 'V' then
    local raw_keys = 'gv"' .. reg .. key
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes(raw_keys, true, false, true),
      'n', false
    )
    return
  end

  local reginfo = vim.fn.getreginfo(reg)
  if not reginfo or not reginfo.regcontents then
    return
  end

  local start_row = vim.api.nvim_buf_get_mark(0, '<')[1]
  local end_row = vim.api.nvim_buf_get_mark(0, '>')[1]
  if start_row <= 0 or end_row <= 0 then
    return
  end
  if start_row > end_row then
    start_row, end_row = end_row, start_row
  end

  local count = count_override or vim.v.count1
  local bufnr = vim.api.nvim_get_current_buf()
  local source_lines = reginfo.regcontents
  local target_indent = indent.get_target_indent(bufnr, start_row - 1)
  local source_indent = indent.get_source_indent(source_lines)
  local delta = target_indent - source_indent
  local adjusted = indent.apply_delta(source_lines, delta, bufnr)
  local final_lines = repeat_lines(adjusted, count)

  local total_lines = vim.api.nvim_buf_line_count(bufnr)
  local covers_all = (start_row == 1 and end_row == total_lines)

  -- Delete selected lines without mutating registers.
  vim.api.nvim_buf_set_lines(bufnr, start_row - 1, end_row, false, {})

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local cursor_row = math.min(start_row, line_count)
  vim.api.nvim_win_set_cursor(0, { cursor_row, 0 })

  -- Insert replacement at deletion point as linewise text.
  vim.api.nvim_put(final_lines, 'l', false, false)

  -- Deleting and re-inserting full-buffer selections may leave one trailing
  -- empty artifact line; remove it when it exceeds expected output size.
  if covers_all then
    local final_count = vim.api.nvim_buf_line_count(bufnr)
    if final_count > #final_lines then
      local last_line = vim.api.nvim_buf_get_lines(bufnr, final_count - 1, final_count, false)[1]
      if last_line == '' then
        vim.api.nvim_buf_set_lines(bufnr, final_count - 1, final_count, false, {})
      end
    end
  end
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
