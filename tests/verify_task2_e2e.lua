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

local smart = require('smart-paste')
smart.setup()
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
  local max_lines = 320
  if fpath == 'lua/smart-paste/init.lua' or fpath == 'lua/smart-paste/paste.lua' then
    max_lines = 400
  end
  assert(count <= max_lines, fpath .. ' is ' .. count .. ' lines (max ' .. max_lines .. ')')
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

-- Test 13b: visual linewise paste with charwise register falls through to vanilla
do
  set_buf_lines({
    'alpha',
    'beta',
  })
  vim.fn.setreg('j2', 'XX', 'v')
  vim.api.nvim_buf_set_mark(0, '<', 1, 0, {})
  vim.api.nvim_buf_set_mark(0, '>', 2, 0, {})

  local orig_feedkeys = vim.api.nvim_feedkeys
  local feed_calls = 0
  vim.api.nvim_feedkeys = function(...)
    feed_calls = feed_calls + 1
    return nil
  end

  paste.do_visual_paste('j2', 'p', 'V')
  vim.api.nvim_feedkeys = orig_feedkeys

  if feed_calls ~= 1 then
    error('visual linewise paste with charwise register should use vanilla fallback')
  end
end
print('PASS: visual linewise paste with charwise register falls through to vanilla')

-- Test 14: ]p charwise-to-newline inserts below with smart indent
set_buf_lines({
  'def foo():',
  '    x = 1',
  '',
})
vim.fn.setreg('k', 'return y', 'v')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state({ register = 'k', count = 1, key = ']p', after = true, follow = false, charwise_newline = true })
paste.do_paste('line')
assert_line_exists('^    return y$', ']p should insert charwise content as indented new line')
print('PASS: ]p charwise-to-newline produces correct indent')

-- Test 15: [p charwise-to-newline inserts above with smart indent
set_buf_lines({
  'def bar():',
  '    z = 9',
  '',
})
vim.fn.setreg('l', 'return z', 'v')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state({ register = 'l', count = 1, key = '[p', after = false, follow = false, charwise_newline = true })
paste.do_paste('line')
local lines15 = get_buf_lines()
if lines15[2] ~= '    return z' then
  fail_with_buffer('[p should insert charwise content as indented new line ABOVE cursor')
end
print('PASS: [p charwise-to-newline inserts above cursor')

-- Test 16: blockwise register with charwise_newline falls through to vanilla
do
  local orig_feedkeys = vim.api.nvim_feedkeys
  local feed_calls = 0
  vim.api.nvim_feedkeys = function(...)
    feed_calls = feed_calls + 1
    return nil
  end

  vim.fn.setreg('m', { 'xx' }, '\0222')
  paste._test_set_state({ register = 'm', count = 1, key = ']p', after = true, follow = false, charwise_newline = true })
  paste.do_paste('line')

  vim.api.nvim_feedkeys = orig_feedkeys
  if feed_calls ~= 1 then
    error('blockwise with charwise_newline should fall through to vanilla paste')
  end
end
print('PASS: blockwise register with ]p falls through to vanilla paste')

-- Test 17: dot-repeat replays ]p charwise-to-newline at new context
set_buf_lines({
  'root',
  '    scope',
  '',
  'tail',
})
vim.fn.setreg('n', 'again', 'v')
paste._test_set_state({ register = 'n', count = 1, key = ']p', after = true, follow = false, charwise_newline = true })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.go.operatorfunc = "v:lua.require'smart-paste.paste'.do_paste"
vim.cmd('normal! g@l')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('normal! .')

local dot_char_lines = get_buf_lines()
local dot_char_top = 0
local dot_char_scoped = 0
for _, line in ipairs(dot_char_lines) do
  if line == 'again' then
    dot_char_top = dot_char_top + 1
  end
  if line == '    again' then
    dot_char_scoped = dot_char_scoped + 1
  end
end
if dot_char_top ~= 1 or dot_char_scoped ~= 1 then
  fail_with_buffer('dot-repeat should replay ]p with context-aware indentation')
end
print('PASS: dot-repeat replays ]p charwise-to-newline with new-context indentation')

-- Test 18: dot-repeat replays [p charwise-to-newline at new context
set_buf_lines({
  'root',
  '    scope',
  '',
  'tail',
})
vim.fn.setreg('o', 'again', 'v')
paste._test_set_state({ register = 'o', count = 1, key = '[p', after = false, follow = false, charwise_newline = true })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.go.operatorfunc = "v:lua.require'smart-paste.paste'.do_paste"
vim.cmd('normal! g@l')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('normal! .')

local dot_char_lines2 = get_buf_lines()
local dot_char_top2 = 0
local dot_char_scoped2 = 0
for _, line in ipairs(dot_char_lines2) do
  if line == 'again' then
    dot_char_top2 = dot_char_top2 + 1
  end
  if line == '    again' then
    dot_char_scoped2 = dot_char_scoped2 + 1
  end
end
if dot_char_top2 ~= 1 or dot_char_scoped2 ~= 1 then
  fail_with_buffer('dot-repeat should replay [p with context-aware indentation')
end
print('PASS: dot-repeat replays [p charwise-to-newline with new-context indentation')

-- Test 19: p on a scope opener uses insertion-point indent (first line in block)
set_buf_lines({
  'if cond {',
  '    body()',
  '}',
})
vim.fn.setreg('q', { 'stmt()' }, 'V')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
paste._test_set_state('q', 1, 'p')
paste.do_paste('line')
local lines19 = get_buf_lines()
if lines19[2] ~= '    stmt()' then
  fail_with_buffer('p on scope opener should indent to first-line-in-block level')
end
print('PASS: p on scope opener indents to insertion point')

-- Test 20: p before a closing token keeps body indent
set_buf_lines({
  'if cond {',
  '    body()',
  '}',
})
vim.fn.setreg('r', { 'stmt()' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state('r', 1, 'p')
paste.do_paste('line')
local lines20 = get_buf_lines()
if lines20[3] ~= '    stmt()' then
  fail_with_buffer('p before closing token should keep body indentation')
end
print('PASS: p before closing token keeps body indentation')

-- Test 21: linewise paste on nonblank row should use row indent even with noisy indentexpr
set_buf_lines({
  'def f():',
  '    a = 1',
  '    b = 2',
  '    c = 3',
})
vim.bo.indentexpr = '8'
vim.fn.setreg('s', { 'x = 9' }, 'V')
vim.api.nvim_win_set_cursor(0, { 3, 0 })
paste._test_set_state('s', 1, 'p')
paste.do_paste('line')
local lines21 = get_buf_lines()
if lines21[4] ~= '    x = 9' then
  fail_with_buffer('linewise paste should keep nonblank row indent when indentexpr is noisy')
end
vim.bo.indentexpr = ''
print('PASS: nonblank row context wins over noisy indentexpr for linewise paste')

-- Test 22: public API paste() honors explicit register override
set_buf_lines({
  'def f():',
  '    y = 0',
  '',
})
vim.fn.setreg('t', { 'x = 1' }, 'V')
vim.fn.setreg('"', { 'wrong = 2' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
smart.paste({ register = 't', key = 'p' })
local lines22 = get_buf_lines()
if lines22[3] ~= '    x = 1' then
  fail_with_buffer('paste() should use explicit register override')
end
print('PASS: paste() uses explicit register override')

-- Test 23: public API paste() supports count override
set_buf_lines({
  'def f():',
  '    y = 0',
  '',
})
vim.fn.setreg('u', { 'x = 1' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
smart.paste({ register = 'u', key = 'p', count = 2 })
local x_count23 = 0
for _, line in ipairs(get_buf_lines()) do
  if line == '    x = 1' then
    x_count23 = x_count23 + 1
  end
end
if x_count23 ~= 2 then
  fail_with_buffer('paste() count override should repeat inserted lines')
end
print('PASS: paste() supports count override')

-- Test 24: public API paste() accepts quoted register syntax
set_buf_lines({
  'def f():',
  '    y = 0',
  '',
})
vim.fn.setreg('v', { 'x = 1' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
smart.paste({ register = '"v', key = 'P' })
local lines24 = get_buf_lines()
if lines24[2] ~= '    x = 1' then
  fail_with_buffer('paste() should normalize quoted register syntax')
end
print('PASS: paste() normalizes quoted register syntax')

-- Test 25: public API paste() remains dot-repeatable
set_buf_lines({
  'root',
  '    scope',
  '',
  'tail',
})
vim.fn.setreg('w', { 'again' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
smart.paste({ register = 'w', key = 'p' })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd('normal! .')
local lines25 = get_buf_lines()
local top25 = 0
local scoped25 = 0
for _, line in ipairs(lines25) do
  if line == 'again' then
    top25 = top25 + 1
  end
  if line == '    again' then
    scoped25 = scoped25 + 1
  end
end
if top25 ~= 1 or scoped25 ~= 1 then
  fail_with_buffer('paste() should preserve dot-repeat behavior')
end
print('PASS: paste() preserves dot-repeat behavior')

-- Test 26: p on empty block opener indents one level inside block
set_buf_lines({
  'func dummy() {',
  '}',
  '',
  'func main() {',
  '    foo := 42',
  '}',
})
vim.fn.setreg('x', { '    foo := 42' }, 'V')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
paste._test_set_state('x', 1, 'p')
paste.do_paste('line')
local lines26 = get_buf_lines()
if lines26[2] ~= '    foo := 42' then
  fail_with_buffer('p on empty block opener should indent inside block by one level')
end
print('PASS: p on empty block opener indents inside block')

-- Test 27: P on empty block closer indents one level inside block
set_buf_lines({
  'func dummy() {',
  '}',
})
vim.fn.setreg('y', { '    foo := 42' }, 'V')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state('y', 1, 'P')
paste.do_paste('line')
local lines27 = get_buf_lines()
if lines27[2] ~= '    foo := 42' then
  fail_with_buffer('P on empty block closer should indent inside block by one level')
end
print('PASS: P on empty block closer indents inside block')

-- Test 28: [p on empty block closer indents one level inside block
set_buf_lines({
  'func dummy() {',
  '}',
})
vim.fn.setreg('z', 'foo := 42', 'v')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
paste._test_set_state({ register = 'z', count = 1, key = '[p', after = false, follow = false, charwise_newline = true })
paste.do_paste('line')
local lines28 = get_buf_lines()
if lines28[2] ~= '    foo := 42' then
  fail_with_buffer('[p on empty block closer should indent inside block by one level')
end
print('PASS: [p on empty block closer indents inside block')

-- Test 29: p under multiline tag opener indents inside tag block
set_buf_lines({
  '  <SelectRoot',
  '    id="playground"',
  '  >',
  '  </SelectRoot>',
})
vim.fn.setreg('c', { '    foo := 42' }, 'V')
vim.api.nvim_win_set_cursor(0, { 3, 0 })
paste._test_set_state('c', 1, 'p')
paste.do_paste('line')
local lines29 = get_buf_lines()
if lines29[4] ~= '      foo := 42' then
  fail_with_buffer('p under multiline tag opener should indent inside tag block')
end
print('PASS: p under multiline tag opener indents inside tag block')

-- Test 30: [p above closing tag indents inside tag block
set_buf_lines({
  '  <SelectRoot',
  '    id="playground"',
  '  >',
  '  </SelectRoot>',
})
vim.fn.setreg('d', 'foo := 42', 'v')
vim.api.nvim_win_set_cursor(0, { 4, 0 })
paste._test_set_state({ register = 'd', count = 1, key = '[p', after = false, follow = false, charwise_newline = true })
paste.do_paste('line')
local lines30 = get_buf_lines()
if lines30[4] ~= '      foo := 42' then
  fail_with_buffer('[p above closing tag should indent inside tag block')
end
print('PASS: [p above closing tag indents inside tag block')

-- Test 31: p under opener with blank inner line still indents inside tag block
set_buf_lines({
  '  <SelectRoot>',
  '',
  '  </SelectRoot>',
})
vim.fn.setreg('e', { 'foo := 42' }, 'V')
vim.api.nvim_win_set_cursor(0, { 1, 0 })
paste._test_set_state('e', 1, 'p')
paste.do_paste('line')
local lines31 = get_buf_lines()
if lines31[2] ~= '      foo := 42' then
  fail_with_buffer('p under opener with blank inner line should indent inside tag block')
end
print('PASS: p under opener with blank inner line indents inside tag block')

-- Test 32: [p above closer with blank inner line still indents inside tag block
set_buf_lines({
  '  <SelectRoot>',
  '',
  '  </SelectRoot>',
})
vim.fn.setreg('f', 'foo := 42', 'v')
vim.api.nvim_win_set_cursor(0, { 3, 0 })
paste._test_set_state({ register = 'f', count = 1, key = '[p', after = false, follow = false, charwise_newline = true })
paste.do_paste('line')
local lines32 = get_buf_lines()
if lines32[3] ~= '      foo := 42' then
  fail_with_buffer('[p above closer with blank inner line should indent inside tag block')
end
print('PASS: [p above closer with blank inner line indents inside tag block')

print('')
print('ALL END-TO-END INTEGRATION TESTS PASSED')
vim.cmd('qa!')
