local indent = require('smart-paste.indent')

--- Helper: create a scratch buffer with given options and return bufnr.
--- @param opts table|nil Buffer options to set (expandtab, tabstop, shiftwidth)
--- @return number bufnr
local function make_buf(opts)
  local bufnr = vim.api.nvim_create_buf(false, true)
  opts = opts or {}
  if opts.expandtab ~= nil then
    vim.bo[bufnr].expandtab = opts.expandtab
  else
    vim.bo[bufnr].expandtab = true
  end
  vim.bo[bufnr].tabstop = opts.tabstop or 4
  vim.bo[bufnr].shiftwidth = opts.shiftwidth or opts.tabstop or 4
  return bufnr
end

--- Helper: create a scratch buffer with specific lines and return bufnr.
--- @param lines string[] Lines to set in the buffer
--- @param opts table|nil Buffer options
--- @return number bufnr
local function make_buf_with_lines(lines, opts)
  local bufnr = make_buf(opts)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

--- Helper: delete a buffer safely.
--- @param bufnr number
local function delete_buf(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

describe('indent', function()
  describe('get_source_indent', function()
    it('returns indent of first non-empty line (4 spaces)', function()
      local lines = { '    hello', '        world' }
      assert.are.equal(4, indent.get_source_indent(lines))
    end)

    it('skips empty first line and returns indent of second line (2 spaces)', function()
      local lines = { '', '  hello' }
      assert.are.equal(2, indent.get_source_indent(lines))
    end)

    it('skips empty first line and returns tab indent as visual width', function()
      local lines = { '', '\thello' }
      local result = indent.get_source_indent(lines)
      local expected = vim.fn.strdisplaywidth('\t')
      assert.are.equal(expected, result)
    end)

    it('returns 0 when all lines are empty', function()
      local lines = { '', '', '' }
      assert.are.equal(0, indent.get_source_indent(lines))
    end)

    it('returns 0 when all lines are whitespace-only', function()
      local lines = { '   ', '\t', '  \t  ' }
      assert.are.equal(0, indent.get_source_indent(lines))
    end)

    it('returns 0 for single line with no indent', function()
      local lines = { 'hello' }
      assert.are.equal(0, indent.get_source_indent(lines))
    end)

    it('handles mixed tab+spaces (tab + 2 spaces) correctly', function()
      local lines = { '', '\t  hello' }
      local result = indent.get_source_indent(lines)
      local expected = vim.fn.strdisplaywidth('\t  ')
      assert.are.equal(expected, result)
    end)

    it('returns indent from first non-empty line, not the minimum', function()
      local lines = { '        deep', '    shallow' }
      assert.are.equal(8, indent.get_source_indent(lines))
    end)
  end)

  describe('get_target_indent', function()
    it('returns indent of non-empty line at given row', function()
      local bufnr = make_buf_with_lines({ '    local x = 1' })
      local result = indent.get_target_indent(bufnr, 0)
      assert.are.equal(4, result)
      delete_buf(bufnr)
    end)

    it('scans upward on empty row to find nearest non-empty line', function()
      local bufnr = make_buf_with_lines({ '        indented', '' })
      local result = indent.get_target_indent(bufnr, 1)
      assert.are.equal(8, result)
      delete_buf(bufnr)
    end)

    it('returns 0 when row 0 is empty (no previous lines)', function()
      local bufnr = make_buf_with_lines({ '' })
      local result = indent.get_target_indent(bufnr, 0)
      assert.are.equal(0, result)
      delete_buf(bufnr)
    end)

    it('returns correct visual columns for tab-indented line', function()
      local bufnr = make_buf_with_lines({ '\tindented' }, { tabstop = 4 })
      local result = indent.get_target_indent(bufnr, 0)
      local expected = vim.fn.strdisplaywidth('\t')
      assert.are.equal(expected, result)
      delete_buf(bufnr)
    end)

    it('scans through multiple empty lines to find non-empty', function()
      local bufnr = make_buf_with_lines({ '      code', '', '', '', '' })
      local result = indent.get_target_indent(bufnr, 4)
      assert.are.equal(6, result)
      delete_buf(bufnr)
    end)

    it('returns 0 when all lines above are empty', function()
      local bufnr = make_buf_with_lines({ '', '', '', 'content' })
      local result = indent.get_target_indent(bufnr, 2)
      assert.are.equal(0, result)
      delete_buf(bufnr)
    end)

    it('returns 0 when all lines are empty (top of file)', function()
      local bufnr = make_buf_with_lines({ '', '', '' })
      local result = indent.get_target_indent(bufnr, 2)
      assert.are.equal(0, result)
      delete_buf(bufnr)
    end)
  end)

  describe('heuristic fallback', function()
    it('returns heuristic indent when no indentexpr and no parser', function()
      local bufnr = make_buf_with_lines({ '    code', '' })
      vim.bo[bufnr].indentexpr = ''
      vim.bo[bufnr].filetype = 'zzz_nonexistent'
      local result = indent.get_target_indent(bufnr, 1)
      assert.are.equal(4, result)
      delete_buf(bufnr)
    end)

    it('does not error when treesitter parser is unavailable', function()
      local bufnr = make_buf_with_lines({ '  code', '' })
      vim.bo[bufnr].indentexpr = ''
      vim.bo[bufnr].filetype = 'zzz_nonexistent'
      local ok, result = pcall(indent.get_target_indent, bufnr, 1)
      assert.is_true(ok)
      assert.are.equal('number', type(result))
      assert.are.equal(2, result)
      delete_buf(bufnr)
    end)
  end)

  describe('sanity check', function()
    it('prefers heuristic when indentexpr diverges by more than 1 shiftwidth', function()
      local bufnr = make_buf_with_lines({ '    code', '' }, { shiftwidth = 4, tabstop = 4 })
      vim.bo[bufnr].indentexpr = '100'
      local result = indent.get_target_indent(bufnr, 1)
      assert.are.equal(4, result)
      delete_buf(bufnr)
    end)
  end)

  describe('indentexpr strategy', function()
    it('uses indentexpr result when configured and within sanity bounds', function()
      local bufnr = make_buf_with_lines({ '        code', '' }, { shiftwidth = 4, tabstop = 4 })
      vim.bo[bufnr].indentexpr = '8'
      local result = indent.get_target_indent(bufnr, 1)
      assert.are.equal(8, result)
      delete_buf(bufnr)
    end)

    it('falls through when indentexpr is empty string', function()
      local bufnr = make_buf_with_lines({ '      code', '' }, { shiftwidth = 4, tabstop = 4 })
      vim.bo[bufnr].indentexpr = ''
      local result = indent.get_target_indent(bufnr, 1)
      assert.are.equal(6, result)
      delete_buf(bufnr)
    end)

    it('falls through when indentexpr returns -1', function()
      local bufnr = make_buf_with_lines({ '    code', '' }, { shiftwidth = 4, tabstop = 4 })
      vim.bo[bufnr].indentexpr = '-1'
      local result = indent.get_target_indent(bufnr, 1)
      assert.are.equal(4, result)
      delete_buf(bufnr)
    end)

    it('falls through when indentexpr errors', function()
      local bufnr = make_buf_with_lines({ '    code', '' }, { shiftwidth = 4, tabstop = 4 })
      vim.bo[bufnr].indentexpr = 'luaeval(\'error("boom")\')'
      local result = indent.get_target_indent(bufnr, 1)
      assert.are.equal(4, result)
      delete_buf(bufnr)
    end)
  end)

  do
    local parser_probe = vim.api.nvim_create_buf(false, true)
    vim.bo[parser_probe].filetype = 'lua'
    local has_lua_parser = pcall(vim.treesitter.get_parser, parser_probe)
    delete_buf(parser_probe)

    if has_lua_parser then
      describe('treesitter scope counting', function()
        it('computes indent inside a Lua function body', function()
          local bufnr = make_buf_with_lines({
            'local function foo()',
            '  local x = 1',
            'end',
          }, { shiftwidth = 2, tabstop = 2 })
          vim.bo[bufnr].filetype = 'lua'
          vim.bo[bufnr].indentexpr = ''
          local result = indent.get_target_indent(bufnr, 1)
          assert.are.equal(2, result)
          delete_buf(bufnr)
        end)

        it('computes indent inside nested Lua scopes', function()
          local bufnr = make_buf_with_lines({
            'local function foo()',
            '  if true then',
            '    local x = 1',
            '  end',
            'end',
          }, { shiftwidth = 2, tabstop = 2 })
          vim.bo[bufnr].filetype = 'lua'
          vim.bo[bufnr].indentexpr = ''
          local result = indent.get_target_indent(bufnr, 2)
          assert.are.equal(4, result)
          delete_buf(bufnr)
        end)

        it('returns 0 at top-level scope', function()
          local bufnr = make_buf_with_lines({ 'local x = 1' }, { shiftwidth = 2, tabstop = 2 })
          vim.bo[bufnr].filetype = 'lua'
          vim.bo[bufnr].indentexpr = ''
          local result = indent.get_target_indent(bufnr, 0)
          assert.are.equal(0, result)
          delete_buf(bufnr)
        end)
      end)
    end
  end

  describe('apply_delta', function()
    it('adds positive delta to lines (expandtab=true)', function()
      local bufnr = make_buf({ expandtab = true, tabstop = 4 })
      local lines = { 'hello', 'world' }
      local result = indent.apply_delta(lines, 4, bufnr)
      assert.are.equal('    hello', result[1])
      assert.are.equal('    world', result[2])
      delete_buf(bufnr)
    end)

    it('subtracts negative delta from lines', function()
      local bufnr = make_buf({ expandtab = true, tabstop = 4 })
      local lines = { '        hello', '        world' }
      local result = indent.apply_delta(lines, -4, bufnr)
      assert.are.equal('    hello', result[1])
      assert.are.equal('    world', result[2])
      delete_buf(bufnr)
    end)

    it('clamps negative delta to 0 (never negative indent)', function()
      local bufnr = make_buf({ expandtab = true, tabstop = 4 })
      local lines = { '  hello' }
      local result = indent.apply_delta(lines, -8, bufnr)
      assert.are.equal('hello', result[1])
      delete_buf(bufnr)
    end)

    it('preserves relative indentation between lines', function()
      local bufnr = make_buf({ expandtab = true, tabstop = 4 })
      local lines = { '    outer', '        inner' }
      local result = indent.apply_delta(lines, 4, bufnr)
      assert.are.equal('        outer', result[1])
      assert.are.equal('            inner', result[2])
      delete_buf(bufnr)
    end)

    it('preserves empty lines as-is', function()
      local bufnr = make_buf({ expandtab = true, tabstop = 4 })
      local lines = { '    code', '', '    more' }
      local result = indent.apply_delta(lines, 4, bufnr)
      assert.are.equal('        code', result[1])
      assert.are.equal('', result[2])
      assert.are.equal('        more', result[3])
      delete_buf(bufnr)
    end)

    it('preserves whitespace-only lines as-is', function()
      local bufnr = make_buf({ expandtab = true, tabstop = 4 })
      local lines = { '    code', '   ', '    more' }
      local result = indent.apply_delta(lines, 4, bufnr)
      assert.are.equal('        code', result[1])
      assert.are.equal('   ', result[2])
      assert.are.equal('        more', result[3])
      delete_buf(bufnr)
    end)

    it('generates tabs when expandtab=false (8 visual cols = 2 tabs)', function()
      local bufnr = make_buf({ expandtab = false, tabstop = 4 })
      local lines = { 'hello' }
      local result = indent.apply_delta(lines, 8, bufnr)
      assert.are.equal('\t\thello', result[1])
      delete_buf(bufnr)
    end)

    it('generates tabs+spaces when expandtab=false, non-aligned delta', function()
      local bufnr = make_buf({ expandtab = false, tabstop = 4 })
      local lines = { 'hello' }
      local result = indent.apply_delta(lines, 6, bufnr)
      assert.are.equal('\t  hello', result[1])
      delete_buf(bufnr)
    end)

    it('converts tab source to spaces in expandtab=true buffer', function()
      local bufnr = make_buf({ expandtab = true, tabstop = 4 })
      local lines = { '\thello' }
      local result = indent.apply_delta(lines, 4, bufnr)
      -- tab = 4 visual cols in default tabstop=8 display, but strdisplaywidth uses actual tabstop
      -- original: \t = strdisplaywidth('\t') visual cols
      -- after +4: original_vcols + 4, output as spaces
      local original_vcols = vim.fn.strdisplaywidth('\t')
      local expected_spaces = string.rep(' ', original_vcols + 4)
      assert.are.equal(expected_spaces .. 'hello', result[1])
      delete_buf(bufnr)
    end)

    it('converts space source to tabs in expandtab=false buffer', function()
      local bufnr = make_buf({ expandtab = false, tabstop = 4 })
      local lines = { '    hello' }
      local result = indent.apply_delta(lines, 4, bufnr)
      -- 4 spaces = 4 visual cols, +4 = 8 visual cols = 2 tabs with tabstop=4
      assert.are.equal('\t\thello', result[1])
      delete_buf(bufnr)
    end)

    it('returns a copy of lines when delta is 0', function()
      local bufnr = make_buf({ expandtab = true, tabstop = 4 })
      local lines = { '    hello', 'world' }
      local result = indent.apply_delta(lines, 0, bufnr)
      assert.are.equal('    hello', result[1])
      assert.are.equal('world', result[2])
      -- Verify it is a copy, not a reference
      assert.are_not.equal(lines, result)
      delete_buf(bufnr)
    end)

    it('handles negative delta with tab-indented source (expandtab=true)', function()
      local bufnr = make_buf({ expandtab = true, tabstop = 4 })
      -- \t\t = 2 tabs = 16 visual cols (tabstop=8 default strdisplaywidth)
      -- We use strdisplaywidth for correctness
      local lines = { '\t\thello' }
      local original_vcols = vim.fn.strdisplaywidth('\t\t')
      local delta = -4
      local result = indent.apply_delta(lines, delta, bufnr)
      local expected_vcols = original_vcols + delta
      local expected = string.rep(' ', expected_vcols) .. 'hello'
      assert.are.equal(expected, result[1])
      delete_buf(bufnr)
    end)
  end)
end)
