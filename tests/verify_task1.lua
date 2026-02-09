-- Task 1 verification: setup API and keymap registration

-- Test 1: setup() with no args
local sp = require('smart-paste')
assert(type(sp.setup) == 'function', 'setup missing')
sp.setup()
assert(sp.config ~= nil, 'config not stored')
assert(#sp.config.keys == 4, 'should have 4 default keys, got ' .. #sp.config.keys)
for _, entry in ipairs(sp.config.keys) do
  assert(type(entry) == 'table', 'key entry should be a table after normalization')
  assert(type(entry.lhs) == 'string', 'key entry should have string lhs')
end
assert(#sp.config.exclude_filetypes == 0, 'should have 0 default excludes')
print('PASS: setup() with no args works')

-- Test 2: keymaps registered for all 4 default keys
local maps = vim.api.nvim_get_keymap('n')
local expected_keys = { p = false, P = false, gp = false, gP = false }
for _, m in ipairs(maps) do
  if m.desc and m.desc:find('Smart paste') then
    expected_keys[m.lhs] = true
  end
end
for k, found in pairs(expected_keys) do
  assert(found, 'keymap for ' .. k .. ' not found')
end
print('PASS: all 4 default keymaps registered')

-- Test 2b: visual keymaps registered for p/P only
local xmaps = vim.api.nvim_get_keymap('x')
local visual_found = { p = false, P = false }
local visual_unexpected = { gp = false, gP = false }
for _, m in ipairs(xmaps) do
  if m.desc and m.desc:find('Smart paste: visual') then
    if visual_found[m.lhs] ~= nil then
      visual_found[m.lhs] = true
    end
    if visual_unexpected[m.lhs] ~= nil then
      visual_unexpected[m.lhs] = true
    end
  end
end
assert(visual_found.p, 'visual keymap for p not found')
assert(visual_found.P, 'visual keymap for P not found')
assert(not visual_unexpected.gp, 'visual gp should not be mapped')
assert(not visual_unexpected.gP, 'visual gP should not be mapped')
print('PASS: visual keymaps registered for p/P only')

-- Test 3: expr=true on keymaps
for _, m in ipairs(maps) do
  if m.lhs == 'p' and m.desc and m.desc:find('Smart paste') then
    assert(m.expr == 1, 'expr not set on p keymap')
  end
end
print('PASS: keymaps have expr=true')

-- Test 4: Plug escape hatches
local found_raw_p = false
local found_raw_P = false
for _, m in ipairs(maps) do
  if m.lhs and m.lhs:find('smart%-paste%-raw%-p%)') then
    found_raw_p = true
  end
  if m.lhs and m.lhs:find('smart%-paste%-raw%-P%)') then
    found_raw_P = true
  end
end
assert(found_raw_p, 'Plug raw-p not found')
assert(found_raw_P, 'Plug raw-P not found')
print('PASS: Plug escape hatches registered')

-- Test 5: desc fields on Plug mappings
for _, m in ipairs(maps) do
  if m.lhs and m.lhs:find('smart%-paste%-raw') then
    assert(m.desc and #m.desc > 0, 'Plug mapping missing desc: ' .. m.lhs)
  end
end
print('PASS: all mappings have desc fields')

-- Test 6: custom keys config
package.loaded['smart-paste'] = nil
local sp2 = require('smart-paste')
sp2.setup({ keys = { 'p' } })
assert(#sp2.config.keys == 1, 'custom keys not respected')
local maps2 = vim.api.nvim_get_keymap('n')
local p_found = false
local gp_found = false
local P_found = false
local gP_found = false
local visual_p_found = false
local visual_P_found = false
for _, m in ipairs(maps2) do
  if m.lhs == 'p' and m.desc and m.desc:find('Smart paste') then
    p_found = true
  end
  if m.lhs == 'gp' and m.desc and m.desc:find('Smart paste') then
    gp_found = true
  end
  if m.lhs == 'P' and m.desc and m.desc:find('Smart paste') then
    P_found = true
  end
  if m.lhs == 'gP' and m.desc and m.desc:find('Smart paste') then
    gP_found = true
  end
end
for _, m in ipairs(vim.api.nvim_get_keymap('x')) do
  if m.desc and m.desc:find('Smart paste: visual') then
    if m.lhs == 'p' then
      visual_p_found = true
    end
    if m.lhs == 'P' then
      visual_P_found = true
    end
  end
end
assert(p_found, 'custom key p not registered')
assert(not gp_found, 'stale gp mapping left after re-setup')
assert(not P_found, 'stale P mapping left after re-setup')
assert(not gP_found, 'stale gP mapping left after re-setup')
assert(visual_p_found, 'visual p mapping missing after re-setup')
assert(not visual_P_found, 'stale visual P mapping left after re-setup')
print('PASS: custom keys config works')

-- Test 7: structured keys config
package.loaded['smart-paste'] = nil
local sp_struct = require('smart-paste')
sp_struct.setup({ keys = { { lhs = 'p', after = true, follow = false } } })
assert(#sp_struct.config.keys == 1, 'structured keys not accepted')
assert(sp_struct.config.keys[1].lhs == 'p', 'structured key lhs wrong')
assert(sp_struct.config.keys[1].after == true, 'structured key after wrong')
print('PASS: structured keys config works')

-- Test 8: mixed string/table keys config
package.loaded['smart-paste'] = nil
local sp_mixed = require('smart-paste')
sp_mixed.setup({ keys = { 'p', { lhs = 'gp', after = true, follow = true } } })
assert(#sp_mixed.config.keys == 2, 'mixed config should have 2 entries')
assert(sp_mixed.config.keys[1].lhs == 'p', 'first entry lhs wrong')
assert(sp_mixed.config.keys[2].lhs == 'gp', 'second entry lhs wrong')
print('PASS: mixed string/table keys config works')

-- Test 9: invalid key entries are skipped
package.loaded['smart-paste'] = nil
local sp_invalid = require('smart-paste')
sp_invalid.setup({ keys = { 'p', { no_lhs = true }, 42 } })
assert(#sp_invalid.config.keys == 1, 'invalid entries should be skipped, got ' .. #sp_invalid.config.keys)
assert(sp_invalid.config.keys[1].lhs == 'p', 'valid entry should survive')
print('PASS: invalid key entries are skipped')

-- Test 10: exclude_filetypes stored
package.loaded['smart-paste'] = nil
local sp3 = require('smart-paste')
sp3.setup({ exclude_filetypes = { 'help', 'TelescopePrompt' } })
assert(#sp3.config.exclude_filetypes == 2, 'exclude_filetypes not stored')
assert(sp3.config.exclude_filetypes[1] == 'help', 'first exclude wrong')
assert(sp3.config.exclude_filetypes[2] == 'TelescopePrompt', 'second exclude wrong')
print('PASS: exclude_filetypes config works')

-- Test 11: re-setup restores full default keyset cleanly
package.loaded['smart-paste'] = nil
local sp4 = require('smart-paste')
sp4.setup()
local maps4 = vim.api.nvim_get_keymap('n')
local restored = { p = false, P = false, gp = false, gP = false }
for _, m in ipairs(maps4) do
  if m.desc and m.desc:find('Smart paste') and restored[m.lhs] ~= nil then
    restored[m.lhs] = true
  end
end
for k, found in pairs(restored) do
  assert(found, 'default key not restored: ' .. k)
end
print('PASS: re-setup restores default keyset')

-- Test 12: line count check
local f = io.open('lua/smart-paste/init.lua', 'r')
local lines = 0
for _ in f:lines() do
  lines = lines + 1
end
f:close()
assert(lines <= 200, 'init.lua is ' .. lines .. ' lines, should be <= 200')
print('PASS: init.lua is ' .. lines .. ' lines (under 200)')

print('')
print('ALL TASK 1 VERIFICATION TESTS PASSED')
vim.cmd('qa!')
