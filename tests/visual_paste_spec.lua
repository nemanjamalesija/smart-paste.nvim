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

local function snapshot_registers()
  local names = { '"' }
  for i = 0, 9 do
    table.insert(names, tostring(i))
  end
  for c = string.byte('a'), string.byte('z') do
    table.insert(names, string.char(c))
  end

  local snapshot = {}
  for _, name in ipairs(names) do
    local info = vim.fn.getreginfo(name)
    snapshot[name] = {
      regcontents = vim.deepcopy(info.regcontents),
      regtype = info.regtype,
      points_to = info.points_to,
      isunnamed = info.isunnamed,
    }
  end
  return snapshot
end

group('visual_paste', function()
  case('linewise visual paste replaces selection with re-indented content', function()
    local bufnr = make_buf({
      'def foo():',
      '    x = 1',
      '    y = 2',
      '',
    })
    vim.api.nvim_set_current_buf(bufnr)

    vim.fn.setreg('a', { 'if True:', '    pass' }, 'V')
    set_selection(bufnr, 2, 3)
    paste.do_visual_paste('a', 'p', 'V')

    assert_eq(get_lines(bufnr), { 'def foo():', '    if True:', '        pass', '' })
    delete_buf(bufnr)
  end)

  case('single-line visual selection is replaced correctly', function()
    local bufnr = make_buf({ '    a = 1', '    b = 2' })
    vim.api.nvim_set_current_buf(bufnr)

    vim.fn.setreg('b', { 'x = 99' }, 'V')
    set_selection(bufnr, 1, 1)
    paste.do_visual_paste('b', 'p', 'V')

    assert_eq(get_lines(bufnr), { '    x = 99', '    b = 2' })
    delete_buf(bufnr)
  end)

  case('linewise visual paste on nonblank row ignores noisy indentexpr', function()
    local bufnr = make_buf({
      'root',
      '  item',
      '  keep',
    })
    vim.api.nvim_set_current_buf(bufnr)

    vim.bo[bufnr].indentexpr = '0'
    vim.fn.setreg('n', { 'value: 1' }, 'V')
    set_selection(bufnr, 2, 2)
    paste.do_visual_paste('n', 'p', 'V')
    vim.bo[bufnr].indentexpr = ''

    assert_eq(get_lines(bufnr), { 'root', '  value: 1', '  keep' })
    delete_buf(bufnr)
  end)

  case('charwise visual mode falls through to vanilla path', function()
    local bufnr = make_buf({ 'alpha', 'beta' })
    vim.api.nvim_set_current_buf(bufnr)

    local orig_feedkeys = vim.api.nvim_feedkeys
    local calls = 0
    vim.api.nvim_feedkeys = function(...)
      calls = calls + 1
      return orig_feedkeys(...)
    end

    vim.fn.setreg('c', 'XX', 'v')
    paste.do_visual_paste('c', 'p', 'v')

    vim.api.nvim_feedkeys = orig_feedkeys
    if calls == 0 then
      delete_buf(bufnr)
      error('expected vanilla fallback to call nvim_feedkeys')
    end
    delete_buf(bufnr)
  end)

  case('linewise visual mode with charwise register falls through to vanilla path', function()
    local bufnr = make_buf({ 'alpha', 'beta' })
    vim.api.nvim_set_current_buf(bufnr)
    set_selection(bufnr, 1, 2)

    local orig_feedkeys = vim.api.nvim_feedkeys
    local calls = 0
    vim.api.nvim_feedkeys = function(...)
      calls = calls + 1
      return orig_feedkeys(...)
    end

    vim.fn.setreg('z', 'XX', 'v')
    paste.do_visual_paste('z', 'p', 'V')

    vim.api.nvim_feedkeys = orig_feedkeys
    if calls == 0 then
      delete_buf(bufnr)
      error('expected charwise register in linewise visual mode to call nvim_feedkeys')
    end
    delete_buf(bufnr)
  end)

  case('blockwise visual mode falls through to vanilla path', function()
    local bufnr = make_buf({ 'alpha', 'beta' })
    vim.api.nvim_set_current_buf(bufnr)

    local orig_feedkeys = vim.api.nvim_feedkeys
    local calls = 0
    vim.api.nvim_feedkeys = function(...)
      calls = calls + 1
      return orig_feedkeys(...)
    end

    vim.fn.setreg('d', { 'YY' }, '\0222')
    paste.do_visual_paste('d', 'p', '\022')

    vim.api.nvim_feedkeys = orig_feedkeys
    if calls == 0 then
      delete_buf(bufnr)
      error('expected blockwise fallback to call nvim_feedkeys')
    end
    delete_buf(bufnr)
  end)

  case('registers are not mutated during visual smart paste', function()
    local bufnr = make_buf({
      'def foo():',
      '    x = 1',
      '    y = 2',
      '',
    })
    vim.api.nvim_set_current_buf(bufnr)

    vim.fn.setreg('e', { 'if True:', '    pass' }, 'V')
    local before = snapshot_registers()

    set_selection(bufnr, 2, 3)
    paste.do_visual_paste('e', 'p', 'V')

    local after = snapshot_registers()
    assert_eq(after, before, 'register contents changed unexpectedly')
    delete_buf(bufnr)
  end)

  case('entire-buffer visual selection leaves no trailing empty artifact', function()
    local bufnr = make_buf({ '    code', '    more' })
    vim.api.nvim_set_current_buf(bufnr)

    vim.fn.setreg('f', { 'replacement' }, 'V')
    set_selection(bufnr, 1, 2)
    paste.do_visual_paste('f', 'p', 'V')

    assert_eq(get_lines(bufnr), { '    replacement' })
    delete_buf(bufnr)
  end)

  case('count is respected for linewise visual smart paste', function()
    local bufnr = make_buf({ '    left', '    right' })
    vim.api.nvim_set_current_buf(bufnr)

    vim.fn.setreg('g', { 'item' }, 'V')
    set_selection(bufnr, 1, 1)
    paste.do_visual_paste('g', 'p', 'V', 2)
    assert_eq(get_lines(bufnr), { '    item', '    item', '    right' })
    delete_buf(bufnr)
  end)

  case('visual smart paste is undone in a single step', function()
    local original = { 'def foo():', '    a = 1', '    b = 2', '' }
    local tmp = vim.fn.tempname()
    local f = assert(io.open(tmp, 'w'))
    f:write(table.concat(original, '\n') .. '\n')
    f:close()

    vim.cmd('edit ' .. vim.fn.fnameescape(tmp))
    local bufnr = vim.api.nvim_get_current_buf()
    vim.bo[bufnr].expandtab = true
    vim.bo[bufnr].tabstop = 4
    vim.bo[bufnr].shiftwidth = 4

    vim.fn.setreg('h', { 'if ok:', '    pass' }, 'V')
    set_selection(bufnr, 2, 3)
    paste.do_visual_paste('h', 'p', 'V')
    vim.cmd('silent normal! u')

    assert_eq(get_lines(bufnr), original)
    os.remove(tmp)
  end)
end)
