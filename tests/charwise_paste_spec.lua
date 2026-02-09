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

group('charwise_paste', function()
  case(']p pastes single-line charwise content below cursor with smart indent', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('a', 'return x', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'a',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'def foo():', '    x = 1', '    return x', '' })
    delete_buf(bufnr)
  end)

  case('[p pastes single-line charwise content above cursor with smart indent', function()
    local bufnr = make_buf({ 'def foo():', '    y = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('b', 'return y', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'b',
      count = 1,
      key = '[p',
      after = false,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'def foo():', '    return y', '    y = 1', '' })
    delete_buf(bufnr)
  end)

  case(']p strips leading whitespace from charwise content before indenting', function()
    local bufnr = make_buf({ 'if true then', '        x = 1', 'end' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('c', '    return x', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'c',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    local lines = get_lines(bufnr)
    if lines[3] ~= '        return x' then
      delete_buf(bufnr)
      error('expected stripped-and-indented line at target indent')
    end
    delete_buf(bufnr)
  end)

  case(']p converts multi-line charwise content to linewise with preserved relative indent', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('d', { 'if True:', '    pass' }, 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'd',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'def foo():', '    x = 1', '    if True:', '        pass', '' })
    delete_buf(bufnr)
  end)

  case(']p with linewise register follows normal smart linewise path', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('e', { 'item' }, 'V')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'e',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    assert_eq(get_lines(bufnr), { 'def foo():', '    x = 1', '    item', '' })
    delete_buf(bufnr)
  end)

  case(']p with blockwise register falls through to vanilla paste', function()
    local bufnr = make_buf({ 'alpha', 'beta' })
    vim.api.nvim_set_current_buf(bufnr)
    local orig_feedkeys = vim.api.nvim_feedkeys
    local calls = 0
    vim.api.nvim_feedkeys = function(...)
      calls = calls + 1
      return nil
    end

    vim.fn.setreg('f', { 'XX' }, '\0222')
    paste._test_set_state({
      register = 'f',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')

    vim.api.nvim_feedkeys = orig_feedkeys
    if calls ~= 1 then
      delete_buf(bufnr)
      error('expected one vanilla fallback call for blockwise register')
    end
    delete_buf(bufnr)
  end)

  case(']p count repeats charwise-to-newline insertion', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('g', 'return z', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'g',
      count = 2,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')

    local count = 0
    for _, line in ipairs(get_lines(bufnr)) do
      if line == '    return z' then
        count = count + 1
      end
    end
    if count ~= 2 then
      delete_buf(bufnr)
      error('expected two inserted copies for count=2')
    end
    delete_buf(bufnr)
  end)

  case(']p preserves trailing whitespace for charwise content', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('h', 'return x   ', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'h',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })
    paste.do_paste('line')
    local lines = get_lines(bufnr)
    if lines[3] ~= '    return x   ' then
      delete_buf(bufnr)
      error('expected trailing whitespace to be preserved')
    end
    delete_buf(bufnr)
  end)

  case(']p with empty charwise register does not crash', function()
    local bufnr = make_buf({ 'def foo():', '    x = 1', '' })
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setreg('i', '', 'v')
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    paste._test_set_state({
      register = 'i',
      count = 1,
      key = ']p',
      after = true,
      follow = false,
      charwise_newline = true,
    })

    local ok, err = pcall(paste.do_paste, 'line')
    if not ok then
      delete_buf(bufnr)
      error('expected empty charwise register to be handled safely: ' .. tostring(err))
    end
    delete_buf(bufnr)
  end)
end)
