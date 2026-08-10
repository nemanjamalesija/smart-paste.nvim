local paste = require('smart-paste.paste')

local has_busted = type(describe) == 'function' and type(it) == 'function'

local function group(_name, fn)
  if has_busted then
    describe(_name, fn)
  else
    fn()
  end
end

local function case(_name, fn)
  if has_busted then
    it(_name, fn)
    return
  end

  local ok, err = pcall(fn)
  if not ok then
    error(_name .. ': ' .. tostring(err))
  end
end

local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].expandtab = true
  vim.bo[bufnr].tabstop = 4
  vim.bo[bufnr].shiftwidth = 4
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function delete_buf(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

local function set_selection(bufnr, start_row, end_row)
  vim.api.nvim_buf_set_mark(bufnr, '<', start_row, 0, {})
  vim.api.nvim_buf_set_mark(bufnr, '>', end_row, 0, {})
end

local function get_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function assert_eq(actual, expected, msg)
  if not vim.deep_equal(actual, expected) then
    local actual_text = vim.inspect(actual)
    local expected_text = vim.inspect(expected)
    error((msg or 'assertion failed') .. '\nexpected: ' .. expected_text .. '\nactual: ' .. actual_text)
  end
end

-- Fake clipboard provider so tests run headless without a real system
-- clipboard. The paste callback returns whatever `clipboard_store` holds,
-- which lets each case hand the `+` register lines with CRLF endings,
-- exactly what win32yank produces on WSL.
local clipboard_store = { {}, 'v' }

local function install_fake_clipboard()
  vim.g.clipboard = {
    name = 'fake-crlf-test',
    copy = {
      ['+'] = function(lines, regtype)
        clipboard_store = { lines, regtype }
      end,
      ['*'] = function(lines, regtype)
        clipboard_store = { lines, regtype }
      end,
    },
    paste = {
      ['+'] = function()
        return clipboard_store
      end,
      ['*'] = function()
        return clipboard_store
      end,
    },
  }
  -- Force the provider to re-read g:clipboard in case another spec
  -- already triggered clipboard detection.
  vim.g.loaded_clipboard_provider = nil
  vim.cmd('runtime autoload/provider/clipboard.vim')
end

group('clipboard_crlf', function()
  install_fake_clipboard()

  case(']p strips trailing \\r from linewise clipboard content', function()
    local bufnr = make_buf({ 'local function test()', '    print("antes")', 'end' })
    vim.api.nvim_set_current_buf(bufnr)
    clipboard_store = {
      { 'if condition then\r', '    print("a")\r', 'end\r' },
      'V',
    }
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = '+',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), {
      'local function test()',
      'if condition then',
      '    print("a")',
      'end',
      '    print("antes")',
      'end',
    })
    delete_buf(bufnr)
  end)

  case(']p strips trailing \\r from the * register too', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1' })
    vim.api.nvim_set_current_buf(bufnr)
    clipboard_store = { { 'return x\r' }, 'V' }
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = '*',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'def foo():', '    x = 1', '    return x' })
    delete_buf(bufnr)
  end)

  case(']p strips trailing \\r from multi-line charwise clipboard content', function()
    local bufnr = make_buf({ 'if true then', '    x = 1', 'end' })
    vim.api.nvim_set_current_buf(bufnr)
    clipboard_store = { { 'y = 2\r', 'z = 3\r' }, 'v' }
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = '+',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'if true then', '    x = 1', '    y = 2', '    z = 3', 'end' })
    delete_buf(bufnr)
  end)

  case('visual paste strips trailing \\r from linewise clipboard content', function()
    local bufnr = make_buf({ 'if true then', '    old = 1', 'end' })
    vim.api.nvim_set_current_buf(bufnr)
    clipboard_store = { { 'new = 2\r' }, 'V' }
    set_selection(bufnr, 2, 2)
    paste.do_visual_paste('+', 'p', 'V', 1)
    assert_eq(get_lines(bufnr), { 'if true then', '    new = 2', 'end' })
    delete_buf(bufnr)
  end)

  case('named registers keep literal \\r characters like vanilla paste', function()
    local bufnr = make_buf({ 'top', 'bottom' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('a', { 'keeps cr\r' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = 'a',
      count = 1,
      key = 'p',
      after = true,
      follow = false,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'top', 'keeps cr\r', 'bottom' })
    delete_buf(bufnr)
  end)
end)
