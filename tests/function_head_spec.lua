local paste = require('smart-paste.paste')
local heuristics = require('smart-paste.heuristics')

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
  vim.bo[bufnr].commentstring = '-- %s'
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function delete_buf(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
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

group('function_head_opener', function()
  case('recognizes function definition heads as scope openers', function()
    local bufnr = make_buf({})
    local openers = {
      'local function test()',
      'function M.setup(opts)',
      'function obj:method(a, b)',
      '  local function nested(x)',
      'local f = function(a)',
      'vim.schedule(function()',
      'local function test() -- note',
    }
    for _, line in ipairs(openers) do
      if not heuristics.is_scope_opener(line, bufnr) then
        error('expected opener: ' .. line)
      end
    end
    delete_buf(bufnr)
  end)

  case('does not treat complete statements or plain calls as openers', function()
    local bufnr = make_buf({})
    local non_openers = {
      'function foo() return 1 end',
      'pcall(function() return x end)',
      'print("hello")',
      'local x = foo(bar)',
      'end',
      'function_helper(x)',
      'local function_name = get_name(info)',
      'local y = my_function(data)',
    }
    for _, line in ipairs(non_openers) do
      if heuristics.is_scope_opener(line, bufnr) then
        error('expected non-opener: ' .. line)
      end
    end
    delete_buf(bufnr)
  end)

  case(']p below a function definition indents the block to the body level', function()
    local bufnr = make_buf({ 'local function test()', '    print("antes")', 'end' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('a', { 'if condition then', '    print("a")', 'end' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = 'a',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), {
      'local function test()',
      '    if condition then',
      '        print("a")',
      '    end',
      '    print("antes")',
      'end',
    })
    delete_buf(bufnr)
  end)

  case(']p into an empty function body indents one shiftwidth', function()
    local bufnr = make_buf({ 'local function test()', 'end' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('b', { 'print("x")' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = 'b',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'local function test()', '    print("x")', 'end' })
    delete_buf(bufnr)
  end)

  case(']p below a callback head indents the block into the callback', function()
    local bufnr = make_buf({ 'vim.schedule(function()', '    print("later")', 'end)' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('c', { 'print("first")' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    paste._test_set_state({
      register = 'c',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), {
      'vim.schedule(function()',
      '    print("first")',
      '    print("later")',
      'end)',
    })
    delete_buf(bufnr)
  end)
end)
