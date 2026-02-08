local M = {}

--- Check whether a line is empty or whitespace-only.
--- @param line string
--- @return boolean
local function is_blank(line)
  return line:match('^%s*$') ~= nil
end

--- Measure the visual column width of leading whitespace in a line.
--- Uses `vim.fn.strdisplaywidth` so mixed tabs/spaces compute correctly.
--- @param line string
--- @return number
local function leading_vcols(line)
  local leading = line:match('^(%s*)') or ''
  return vim.fn.strdisplaywidth(leading)
end

--- Get effective shiftwidth for a specific buffer (`shiftwidth=0` -> `tabstop`).
--- @param bufnr number
--- @return number
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

--- Get the visual column indent of the first non-empty line in a list of lines.
--- Empty and whitespace-only lines are skipped. Returns 0 if all lines are empty.
--- @param lines string[] List of lines (e.g. from register content)
--- @return number Visual column width of leading whitespace
function M.get_source_indent(lines)
  for _, line in ipairs(lines) do
    if not is_blank(line) then
      return leading_vcols(line)
    end
  end
  return 0
end

--- Heuristic indent fallback: scan upward to nearest non-empty line and
--- measure its leading whitespace in visual columns.
--- @param bufnr number Buffer handle
--- @param row number 0-indexed row number
--- @return number Visual column width of leading whitespace
local function heuristic_get_indent(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''

  if is_blank(line) then
    for r = row - 1, 0, -1 do
      local prev = vim.api.nvim_buf_get_lines(bufnr, r, r + 1, false)[1]
      if prev and not is_blank(prev) then
        line = prev
        break
      end
    end
  end

  if is_blank(line) then
    return 0
  end

  return leading_vcols(line)
end

--- Evaluate buffer-local `indentexpr` for a target row.
--- Returns nil when indentexpr is unset, errors, or provides no usable answer.
--- @param bufnr number Buffer handle
--- @param row number 0-indexed row number
--- @return number|nil
local function eval_indentexpr(bufnr, row)
  local indentexpr = vim.bo[bufnr].indentexpr
  if indentexpr == '' then
    return nil
  end

  local result
  local ok = pcall(vim.api.nvim_buf_call, bufnr, function()
    local previous_lnum = vim.v.lnum
    vim.v.lnum = row + 1
    local eval_ok, value = pcall(vim.fn.eval, indentexpr)
    vim.v.lnum = previous_lnum
    if eval_ok and type(value) == 'number' and value >= 0 then
      result = value
    end
  end)

  if not ok then
    return nil
  end

  return result
end

local SCOPE_NODES = {
  function_definition = true,
  function_declaration = true,
  method_definition = true,
  method_declaration = true,
  if_statement = true,
  else_clause = true,
  elseif_clause = true,
  for_statement = true,
  while_statement = true,
  do_statement = true,
  try_statement = true,
  catch_clause = true,
  class_definition = true,
  class_declaration = true,
  block = true,
  statement_block = true,
  body = true,
  table_constructor = true,
  object = true,
  array = true,
  arguments = true,
  parameters = true,
}

--- Compute indent from treesitter scope depth when parser data is available.
--- Returns nil when parser/node data is unavailable.
--- @param bufnr number Buffer handle
--- @param row number 0-indexed row number
--- @return number|nil
local function ts_get_indent(bufnr, row)
  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok_parser or not parser then
    return nil
  end

  pcall(function()
    parser:parse()
  end)

  local effective_row = row
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  if is_blank(line) then
    effective_row = -1
    for r = row - 1, 0, -1 do
      local prev = vim.api.nvim_buf_get_lines(bufnr, r, r + 1, false)[1]
      if prev and not is_blank(prev) then
        effective_row = r
        break
      end
    end
    if effective_row < 0 then
      return nil
    end
  end

  local ok_node, node = pcall(vim.treesitter.get_node, {
    bufnr = bufnr,
    pos = { effective_row, 0 },
    ignore_injections = true,
  })
  if not ok_node or not node then
    return nil
  end

  local depth = 0
  local covers_target_row = (effective_row == row)
  local last_counted_start_row = nil
  local current = node
  while current do
    local start_row = select(1, current:start())
    local end_row = select(1, current:end_())
    local multiline = end_row > start_row
    local covers_row = start_row <= row and row < end_row

    if multiline and covers_row then
      covers_target_row = true
    end
    if multiline and covers_row and SCOPE_NODES[current:type()] and start_row ~= last_counted_start_row then
      depth = depth + 1
      last_counted_start_row = start_row
    end

    current = current:parent()
  end

  if effective_row ~= row and not covers_target_row then
    return nil
  end

  return depth * get_shiftwidth(bufnr)
end

--- Keep treesitter/indentexpr answers bounded to local heuristic context.
--- @param ts_indent number
--- @param heuristic_indent number
--- @param bufnr number
--- @return number
local function sanity_check(ts_indent, heuristic_indent, bufnr)
  local sw = get_shiftwidth(bufnr)
  if math.abs(ts_indent - heuristic_indent) > sw then
    return heuristic_indent
  end
  return ts_indent
end

--- Get target indent using strategy cascade:
--- `indentexpr` -> treesitter scope counting -> heuristic fallback.
--- @param bufnr number Buffer handle
--- @param row number 0-indexed row number
--- @return number Visual column width of leading whitespace
function M.get_target_indent(bufnr, row)
  local heuristic_indent = heuristic_get_indent(bufnr, row)

  local indentexpr_indent = eval_indentexpr(bufnr, row)
  if indentexpr_indent ~= nil then
    return sanity_check(indentexpr_indent, heuristic_indent, bufnr)
  end

  local ts_indent = ts_get_indent(bufnr, row)
  if ts_indent ~= nil then
    return sanity_check(ts_indent, heuristic_indent, bufnr)
  end

  return heuristic_indent
end

--- Apply an indent delta to a list of lines.
--- Preserves relative indentation between lines. Clamps individual line
--- indentation to 0 (never produces negative indent). Generates spaces
--- or tabs+spaces based on the buffer's `expandtab` and `tabstop` options.
--- Empty and whitespace-only lines are preserved unchanged.
---
--- Note: `shiftwidth` of 0 falls back to `tabstop` per Vim convention.
--- This module reads `shiftwidth` awareness for future phases but currently
--- uses `tabstop` for tab-width calculations.
---
--- @param lines string[] Lines to adjust
--- @param delta number Visual columns to add (positive) or remove (negative)
--- @param bufnr number Buffer handle (for expandtab/tabstop options)
--- @return string[] Adjusted lines (new table, never mutates input)
function M.apply_delta(lines, delta, bufnr)
  if delta == 0 then
    return vim.deepcopy(lines)
  end

  local expandtab = vim.bo[bufnr].expandtab
  local tabstop = vim.bo[bufnr].tabstop

  local result = {}
  for _, line in ipairs(lines) do
    if is_blank(line) then
      table.insert(result, line)
    else
      local leading = line:match('^(%s*)') or ''
      local content = line:sub(#leading + 1)
      local current_vcols = vim.fn.strdisplaywidth(leading)
      local new_vcols = math.max(0, current_vcols + delta)

      local new_leading
      if expandtab then
        new_leading = string.rep(' ', new_vcols)
      else
        local tabs = math.floor(new_vcols / tabstop)
        local spaces = new_vcols % tabstop
        new_leading = string.rep('\t', tabs) .. string.rep(' ', spaces)
      end

      table.insert(result, new_leading .. content)
    end
  end
  return result
end

return M
