local M = {}

--- Get the visual column indent of the first non-empty line in a list of lines.
--- Empty and whitespace-only lines are skipped. Returns 0 if all lines are empty.
--- Uses `vim.fn.strdisplaywidth` for correct visual column measurement with
--- mixed tabs and spaces.
--- @param lines string[] List of lines (e.g. from register content)
--- @return number Visual column width of leading whitespace
function M.get_source_indent(lines)
  for _, line in ipairs(lines) do
    if not line:match('^%s*$') then
      local leading = line:match('^(%s*)') or ''
      return vim.fn.strdisplaywidth(leading)
    end
  end
  return 0
end

--- Get the target indent at a given buffer row.
--- If the row is empty or whitespace-only, scans upward to the nearest
--- non-empty line. Returns 0 when all lines above (inclusive) are empty.
--- Uses `vim.fn.strdisplaywidth` for correct visual column measurement.
--- @param bufnr number Buffer handle
--- @param row number 0-indexed row number
--- @return number Visual column width of leading whitespace
function M.get_target_indent(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''

  if line:match('^%s*$') then
    for r = row - 1, 0, -1 do
      local prev = vim.api.nvim_buf_get_lines(bufnr, r, r + 1, false)[1]
      if prev and not prev:match('^%s*$') then
        line = prev
        break
      end
    end
  end

  if line:match('^%s*$') then
    return 0
  end

  local leading = line:match('^(%s*)') or ''
  return vim.fn.strdisplaywidth(leading)
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
    if line:match('^%s*$') then
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
