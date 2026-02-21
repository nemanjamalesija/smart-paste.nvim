--- @class SmartPaste.Paste
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

--- Strip leading whitespace from the first line in a list.
--- Trailing whitespace is preserved (may be intentional per user decision).
--- @param lines string[]
--- @return string[]
local function strip_leading_whitespace(lines)
  local result = vim.deepcopy(lines)
  if #result > 0 then
    result[1] = result[1]:match('^%s*(.*)$') or result[1]
  end
  return result
end

--- Resolve contextual indent for a specific row.
--- For nonblank lines this uses actual leading whitespace width.
--- For blank lines it falls back to indent engine prediction.
--- @param bufnr integer
--- @param row integer 0-indexed
--- @return integer indent
--- @return string line
local function resolve_row_context_indent(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  if line:match('^%s*$') then
    return indent.get_target_indent(bufnr, row), line
  end
  local leading = line:match('^(%s*)') or ''
  return vim.fn.strdisplaywidth(leading), line
end

--- Get effective shiftwidth for a specific buffer (`shiftwidth=0` -> `tabstop`).
--- @param bufnr integer
--- @return integer shiftwidth
local function get_shiftwidth(bufnr)
  local sw
  vim.api.nvim_buf_call(bufnr, function()
    sw = vim.fn.shiftwidth()
  end)
  if type(sw) ~= 'number' or sw <= 0 then
    sw = vim.bo[bufnr].tabstop
  end
  return sw
end

--- Heuristic: line opens an HTML/Vue-like tag block.
--- Supports single-line tag openers and multiline opener tails (`>` line).
--- @param line string
--- @return boolean
local function looks_like_tag_opener(line)
  if line:match('^%s*>%s*$') then
    return true
  end
  if line:match('^%s*<[%w:_-]') and line:match('>%s*$') and not line:match('/>%s*$') and not line:match('^%s*</') then
    return true
  end
  return false
end

--- Heuristic: line closes an HTML/Vue-like tag block.
--- @param line string
--- @return boolean
local function looks_like_tag_closer(line)
  return line:match('^%s*</[%w:_-][^>]*>%s*$') ~= nil
end

--- Heuristic: line ends with an opener token for block-like constructs.
--- @param line string
--- @return boolean
local function looks_like_scope_opener(line)
  if line:match('[%{%[%(:]%s*$') then
    return true
  end
  if looks_like_tag_opener(line) then
    return true
  end
  return line:match('%f[%a](then|do|else|elseif|repeat|function)%s*$') ~= nil
end

--- Heuristic: line begins with a closing token for block-like constructs.
--- @param line string
--- @return boolean
local function looks_like_scope_closer(line)
  if line:match('^%s*[%}%]%)]') then
    return true
  end
  if looks_like_tag_closer(line) then
    return true
  end
  return line:match('^%s*(end|elif|else|elseif|catch|finally)%f[%A]') ~= nil
end

--- Resolve target indent for linewise insertion at the current cursor gap.
--- Uses neighbor context only around likely scope boundaries so ordinary
--- top-level/adjacent indentation remains stable.
--- @param bufnr integer
--- @param cursor_row integer 0-indexed
--- @param after boolean
--- @return integer indent
local function resolve_linewise_target_indent(bufnr, cursor_row, after)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 0 then
    return 0
  end

  local clamped_row = math.max(0, math.min(cursor_row, line_count - 1))
  local current_indent, current_line = resolve_row_context_indent(bufnr, clamped_row)

  if after then
    local next_row = clamped_row + 1
    if next_row < line_count and looks_like_scope_opener(current_line) then
      local next_indent, next_line = resolve_row_context_indent(bufnr, next_row)
      if next_indent > current_indent then
        return next_indent
      end
      if next_line:match('^%s*$') then
        return current_indent + get_shiftwidth(bufnr)
      end
      -- Empty block case: opener followed by a closer at same indent.
      if looks_like_scope_closer(next_line) and next_indent <= current_indent then
        return current_indent + get_shiftwidth(bufnr)
      end
    end
    return current_indent
  end

  local prev_row = clamped_row - 1
  if prev_row >= 0 and looks_like_scope_closer(current_line) then
    local prev_indent, prev_line = resolve_row_context_indent(bufnr, prev_row)
    if prev_indent > current_indent then
      return prev_indent
    end
    if prev_line:match('^%s*$') then
      return current_indent + get_shiftwidth(bufnr)
    end
    -- Empty block case: closer preceded by an opener at same indent.
    if looks_like_scope_opener(prev_line) and prev_indent <= current_indent then
      return current_indent + get_shiftwidth(bufnr)
    end
  end

  return current_indent
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
--- @param key_entry table Normalized key entry { lhs, after, follow, charwise_newline }
--- @param context? table Optional execution context { register?, count? }
--- @return string The keysequence 'g@l' to trigger operatorfunc
function M.smart_paste(key_entry, context)
  local register = vim.v.register
  local count = vim.v.count1

  if type(context) == 'table' then
    if type(context.register) == 'string' and context.register ~= '' then
      register = context.register
    end
    if type(context.count) == 'number' and context.count > 0 then
      count = math.floor(context.count)
    end
  end

  state.register = register
  state.count = count
  state.key = key_entry.lhs
  state.after = key_entry.after
  state.follow = key_entry.follow
  state.charwise_newline = key_entry.charwise_newline
  vim.go.operatorfunc = "v:lua.require'smart-paste.paste'.do_paste"
  return 'g@l'
end

--- Operatorfunc callback that performs the actual paste.
--- Reads the register (never mutates it), computes indent delta for
--- linewise content, and places text via a single `nvim_put` call
--- for undo atomicity. When `charwise_newline` is enabled for a key entry,
--- charwise register content is converted to indented linewise paste.
--- Other charwise/blockwise operations fall through to vanilla paste via
--- `nvim_feedkeys`.
---
--- @param _motion_type string Ignored; required by operatorfunc signature
function M.do_paste(_motion_type)
  local reg = state.register
  local count = state.count
  local key = state.key
  local after = state.after
  local follow = state.follow

  -- Fallback defaults for safety
  if not reg then
    reg = '"'
  end
  if not count then
    count = 1
  end
  if not key then
    key = 'p'
  end
  if after == nil then
    after = true
  end
  if follow == nil then
    follow = false
  end

  local reginfo = vim.fn.getreginfo(reg)
  if not reginfo or not reginfo.regcontents then
    return
  end

  local is_linewise = vim.startswith(reginfo.regtype, 'V')

  if not is_linewise then
    local charwise_newline = state.charwise_newline == true
    local is_charwise = (reginfo.regtype == 'v')

    if charwise_newline and is_charwise then
      local lines = reginfo.regcontents
      local stripped = strip_leading_whitespace(lines)
      local source_indent = indent.get_source_indent(stripped)
      local bufnr = vim.api.nvim_get_current_buf()
      local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed
      local target_indent = resolve_linewise_target_indent(bufnr, row, after)
      local delta = target_indent - source_indent
      local adjusted = indent.apply_delta(stripped, delta, bufnr)
      local final_lines = repeat_lines(adjusted, count)
      vim.api.nvim_put(final_lines, 'l', after, follow)
      return
    end

    local raw_keys = '"' .. reg .. tostring(count) .. key
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(raw_keys, true, false, true), 'n', false)
    return
  end

  local lines = reginfo.regcontents

  -- Compute indent delta using the indent engine
  local source_indent = indent.get_source_indent(lines)
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 0-indexed
  local target_indent = resolve_linewise_target_indent(bufnr, row, after)
  local delta = target_indent - source_indent
  local adjusted = indent.apply_delta(lines, delta, bufnr)

  -- Handle count: repeat adjusted lines N times
  local final_lines = repeat_lines(adjusted, count)

  -- Place text: single nvim_put call = single undo step
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
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(raw_keys, true, false, true), 'n', false)
    return
  end

  local reginfo = vim.fn.getreginfo(reg)
  if not reginfo or not reginfo.regcontents then
    return
  end

  -- Visual smart replacement is linewise-only on both axes:
  -- linewise selection (`V`) and linewise register (`V...`).
  -- Charwise/blockwise registers fall through to native visual paste.
  local is_linewise_register = type(reginfo.regtype) == 'string' and vim.startswith(reginfo.regtype, 'V')
  if not is_linewise_register then
    local raw_keys = 'gv"' .. reg .. key
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(raw_keys, true, false, true), 'n', false)
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
  local target_indent = select(1, resolve_row_context_indent(bufnr, start_row - 1))
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
  local put_after = false
  if start_row > line_count then
    -- Selection touched EOF; insert below the new last line so replacement
    -- lands at the original selection start (end-of-buffer position).
    put_after = true
  end
  if cursor_row < 1 then
    cursor_row = 1
  end
  vim.api.nvim_win_set_cursor(0, { cursor_row, 0 })

  -- Insert replacement at deletion point as linewise text.
  vim.api.nvim_put(final_lines, 'l', put_after, false)

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
--- @param reg_or_tbl string|table Register name or state table
--- @param count? number Paste count (legacy signature)
--- @param key? string Paste key (legacy signature)
function M._test_set_state(reg_or_tbl, count, key)
  if type(reg_or_tbl) == 'table' then
    state.register = reg_or_tbl.register or '"'
    state.count = reg_or_tbl.count or 1
    state.key = reg_or_tbl.key or 'p'
    state.after = reg_or_tbl.after
    state.follow = reg_or_tbl.follow
    state.charwise_newline = reg_or_tbl.charwise_newline
    return
  end

  state.register = reg_or_tbl
  state.count = count
  state.key = key
  state.after = (key == 'p' or key == 'gp' or key == ']p')
  state.follow = (key == 'gp' or key == 'gP')
  state.charwise_newline = (key == ']p' or key == '[p')
end

return M
