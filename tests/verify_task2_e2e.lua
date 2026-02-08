-- Task 2: End-to-end integration verification
-- Full pipeline: setup() -> paste handler -> indent engine -> nvim_put

vim.o.expandtab = true
vim.o.shiftwidth = 4
vim.o.tabstop = 4

local function set_buf_lines(lines)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

local function get_buf_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function fail_with_buffer(msg)
  print('FAIL: ' .. msg)
  local lines = get_buf_lines()
  for i, line in ipairs(lines) do
    print(i .. ': [' .. line .. ']')
  end
  vim.cmd('cq')
end

local function assert_line_exists(pattern, msg)
  for _, line in ipairs(get_buf_lines()) do
    if line:match(pattern) then
      return
    end
  end
  fail_with_buffer(msg)
end

require('smart-paste').setup()
local paste = require('smart-paste.paste')

-- Test 1: Full smart paste flow (p)
set_buf_lines({
  'def foo():',
  '    x = 1',
  '    y = 2',
  '',
})
vim.fn.setreg('a', { 'if True:', '    pass' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state('a', 1, 'p')
paste.do_paste('line')
assert_line_exists('^    if True:$', 'end-to-end smart paste missing indented first line')
assert_line_exists('^        pass$', 'end-to-end smart paste missing indented nested line')
print('PASS: end-to-end smart paste produces correct indent')

-- Test 2: Paste with count
set_buf_lines({
  'def bar():',
  '    a = 1',
  '',
})
vim.fn.setreg('b', { 'x = 0' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state('b', 2, 'p')
paste.do_paste('line')
local x_count = 0
for _, line in ipairs(get_buf_lines()) do
  if line:match('^    x = 0$') then
    x_count = x_count + 1
  end
end
if x_count ~= 2 then
  fail_with_buffer('expected 2 indented copies, got ' .. x_count)
end
print('PASS: count=2 produces 2 correctly indented copies')

-- Test 3: Paste before (P key)
set_buf_lines({
  'def baz():',
  '    z = 9',
  '',
})
vim.fn.setreg('c', { 'w = 5' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state('c', 1, 'P')
paste.do_paste('line')
local lines3 = get_buf_lines()
if lines3[2] ~= '    w = 5' then
  fail_with_buffer('P should paste before cursor line at target indent')
end
print('PASS: P (paste before) produces correct indent')

-- Test 4: gp uses follow behavior and pastes after cursor line
set_buf_lines({
  'top',
  '    ctx',
  'tail',
})
vim.fn.setreg('d', { 'item' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state('d', 1, 'gp')
paste.do_paste('line')
local lines4 = get_buf_lines()
local cursor4 = vim.api.nvim_win_get_cursor(0)
if lines4[3] ~= '    item' then
  fail_with_buffer('gp should paste after cursor line with smart indent')
end
set_buf_lines({
  'top',
  '    ctx',
  'tail',
})
vim.fn.setreg('d', { 'item' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state('d', 1, 'p')
paste.do_paste('line')
local cursor4_plain = vim.api.nvim_win_get_cursor(0)
if cursor4[1] <= cursor4_plain[1] then
  fail_with_buffer('gp should place cursor further than p (follow behavior)')
end
print('PASS: gp uses follow behavior and correct placement')

-- Test 5: gP uses follow behavior and pastes before cursor line
set_buf_lines({
  'top',
  '    ctx',
  'tail',
})
vim.fn.setreg('e', { 'item' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state('e', 1, 'gP')
paste.do_paste('line')
local lines5 = get_buf_lines()
local cursor5 = vim.api.nvim_win_get_cursor(0)
if lines5[2] ~= '    item' then
  fail_with_buffer('gP should paste before cursor line with smart indent')
end
set_buf_lines({
  'top',
  '    ctx',
  'tail',
})
vim.fn.setreg('e', { 'item' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state('e', 1, 'P')
paste.do_paste('line')
local cursor5_plain = vim.api.nvim_win_get_cursor(0)
if cursor5[1] <= cursor5_plain[1] then
  fail_with_buffer('gP should place cursor further than P (follow behavior)')
end
print('PASS: gP uses follow behavior and correct placement')

-- Test 6: Charwise and blockwise registers fall through to vanilla path
do
  local orig_put = vim.api.nvim_put
  local orig_feedkeys = vim.api.nvim_feedkeys
  local put_calls = 0
  local feed_calls = 0

  vim.api.nvim_put = function(...)
    put_calls = put_calls + 1
    return orig_put(...)
  end
  vim.api.nvim_feedkeys = function(...)
    feed_calls = feed_calls + 1
    return nil
  end

  vim.fn.setreg('f', 'xx', 'v')
  paste._test_set_state('f', 1, 'p')
  paste.do_paste('line')

  vim.fn.setreg('g', { 'yy' }, '\0222')
  paste._test_set_state('g', 1, 'p')
  paste.do_paste('line')

  vim.api.nvim_put = orig_put
  vim.api.nvim_feedkeys = orig_feedkeys

  if put_calls ~= 0 then
    error('smart path should not run for charwise/blockwise registers')
  end
  if feed_calls ~= 2 then
    error('vanilla fallback should run for both charwise and blockwise registers')
  end
end
print('PASS: charwise/blockwise registers use vanilla fallback path')

-- Test 7: Single undo step restores pre-paste buffer
local before_undo = {
  'def undo_case():',
  '    base = 1',
  '',
}
local undo_file = vim.fn.tempname()
local undo_handle = assert(io.open(undo_file, 'w'))
undo_handle:write(table.concat(before_undo, '\n') .. '\n')
undo_handle:close()
vim.cmd('edit ' .. vim.fn.fnameescape(undo_file))
vim.fn.setreg('h', { 'if ok:', '    pass' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state('h', 1, 'p')
paste.do_paste('line')
vim.cmd('silent normal! u')
if not vim.deep_equal(get_buf_lines(), before_undo) then
  fail_with_buffer('undo should restore the full pre-paste state in one step')
end
os.remove(undo_file)
print('PASS: smart paste is undone in one step')

-- Test 8: Dot-repeat replays smart paste at a new location
set_buf_lines({
  'root',
  '    scope',
  '',
  'tail',
})
vim.fn.setreg('i', { 'again' }, 'V')
paste._test_set_state('i', 1, 'p')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.go.operatorfunc = "v:lua.require'smart-paste.paste'.do_paste"
vim.cmd('normal! g@l')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('normal! .')

local dot_lines = get_buf_lines()
local top_level_count = 0
local scoped_count = 0
for _, line in ipairs(dot_lines) do
  if line == 'again' then
    top_level_count = top_level_count + 1
  end
  if line == '    again' then
    scoped_count = scoped_count + 1
  end
end
if top_level_count ~= 1 or scoped_count ~= 1 then
  fail_with_buffer('dot-repeat should paste again with context-aware indent at new cursor position')
end
print('PASS: dot-repeat replays smart paste with new-context indentation')

-- Test 9: Verify all 3 modules integrate without error
local init_ok = package.loaded['smart-paste'] ~= nil
local paste_ok = package.loaded['smart-paste.paste'] ~= nil
local indent_ok = package.loaded['smart-paste.indent'] ~= nil
assert(init_ok, 'init module not loaded')
assert(paste_ok, 'paste module not loaded')
assert(indent_ok, 'indent module not loaded')
print('PASS: all 3 modules (init, paste, indent) loaded and integrated')

-- Test 10: Plugin file count check
local handle = io.popen('ls lua/smart-paste/*.lua | wc -l')
local file_count = tonumber(handle:read('*a'):match('%d+'))
handle:close()
assert(file_count == 3, 'expected 3 lua files, got ' .. file_count)
print('PASS: plugin has exactly 3 Lua files')

-- Test 11: File size check (focused, minimal modules)
local lua_files = { 'lua/smart-paste/init.lua', 'lua/smart-paste/paste.lua', 'lua/smart-paste/indent.lua' }
for _, fpath in ipairs(lua_files) do
  local f = io.open(fpath, 'r')
  local count = 0
  for _ in f:lines() do
    count = count + 1
  end
  f:close()
  -- Phase 2 adds strategy helpers to indent.lua; keep a soft cap for maintainability.
  assert(count <= 320, fpath .. ' is ' .. count .. ' lines (max 320)')
  print('PASS: ' .. fpath .. ' is ' .. count .. ' lines')
end

-- Test 12: visual linewise paste replaces selection with smart-indented content
set_buf_lines({
  'def foo():',
  '    x = 1',
  '    y = 2',
  '',
})
vim.fn.setreg('j', { 'if True:', '    pass' }, 'V')
vim.api.nvim_buf_set_mark(0, '<', 2, 0, {})
vim.api.nvim_buf_set_mark(0, '>', 3, 0, {})
paste.do_visual_paste('j', 'p', 'V')
local visual_lines = get_buf_lines()
if not vim.deep_equal(visual_lines, { 'def foo():', '    if True:', '        pass', '' }) then
  fail_with_buffer('visual linewise smart paste should replace selection with re-indented content')
end
print('PASS: visual linewise paste re-indents replacement content')

-- Test 13: setup registers x-mode keymaps for visual paste
local xmaps = vim.api.nvim_get_keymap('x')
local x_found_p = false
local x_found_P = false
for _, m in ipairs(xmaps) do
  if m.desc and m.desc:find('Smart paste: visual') then
    if m.lhs == 'p' then
      x_found_p = true
    end
    if m.lhs == 'P' then
      x_found_P = true
    end
  end
end
if not x_found_p or not x_found_P then
  error('x-mode keymaps for visual smart paste were not registered')
end
print('PASS: x-mode keymaps for visual paste are registered')

print('')
print('ALL END-TO-END INTEGRATION TESTS PASSED')
vim.cmd('qa!')
