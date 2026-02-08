# smart-paste.nvim

Pasted code automatically lands at the correct indentation level.

![CI](https://img.shields.io/github/actions/workflow/status/nemanjamalesija/smart-paste.nvim/ci.yml?branch=main&style=for-the-badge&label=CI) ![License](https://img.shields.io/github/license/nemanjamalesija/smart-paste.nvim?style=for-the-badge) ![Neovim](https://img.shields.io/badge/Neovim-0.10+-blueviolet?style=for-the-badge&logo=neovim)

<!-- Demo GIF: replace this line with ![demo](assets/demo.gif) after recording -->

## Features

- Intercepts `p` / `P` / `gp` / `gP` so pasted code lands at the right indent level automatically.
- Three-tier indent strategy: `indentexpr` -> treesitter scope analysis -> heuristic fallback.
- Visual mode (`V` + `p`/`P`): replace selected lines with correctly indented content.
- Dot-repeat (`.`) works naturally.
- Single undo step: one `u` undoes the entire paste.
- Register-safe behavior: registers are read, never rewritten.
- Zero dependencies: pure Lua, no external plugins required.
- Zero config: call `setup()` and paste keys are enhanced.

## Installation

```lua
-- lazy.nvim
{
  'nemanjamalesija/smart-paste.nvim',
  event = 'VeryLazy',
  config = true,
}
```

```lua
-- packer.nvim
use {
  'nemanjamalesija/smart-paste.nvim',
  config = function()
    require('smart-paste').setup()
  end,
}
```

```lua
-- mini.deps
MiniDeps.add('nemanjamalesija/smart-paste.nvim')
require('smart-paste').setup()
```

```vim
" vim-plug
Plug 'nemanjamalesija/smart-paste.nvim'
" then in your init.lua: require('smart-paste').setup()
```

## Setup

```lua
require('smart-paste').setup()
```

With options:

```lua
require('smart-paste').setup({
  keys = { 'p', 'P', 'gp', 'gP' },   -- keys to enhance (default)
  exclude_filetypes = {},            -- filetypes that skip smart indent
})
```

Indentation settings (`shiftwidth`, `expandtab`, `tabstop`) come from your buffer options. No plugin-specific indent config needed.

## Mappings

| Mode | Key | Action |
|------|-----|--------|
| Normal | `p` | Smart paste after cursor line |
| Normal | `P` | Smart paste before cursor line |
| Normal | `gp` | Smart paste after cursor line and follow to end |
| Normal | `gP` | Smart paste before cursor line and follow to end |
| Visual (linewise `V`) | `p` | Replace selection with smart-indented content |
| Visual (linewise `V`) | `P` | Replace selection with smart-indented content |
| Normal | `<Plug>(smart-paste-raw-p)` | Raw `p` (bypass smart paste) |
| Normal | `<Plug>(smart-paste-raw-P)` | Raw `P` (bypass smart paste) |

Example escape-hatch bindings:

```lua
vim.keymap.set('n', '<leader>p', '<Plug>(smart-paste-raw-p)')
vim.keymap.set('n', '<leader>P', '<Plug>(smart-paste-raw-P)')
```

## How It Works

smart-paste reads the register contents via `getreginfo()`, computes an indent delta between the pasted code's original indentation and the correct indentation at the cursor position, then applies that delta to every pasted line. The adjusted text is inserted with `nvim_put()` for atomic undo.

1. `indentexpr` -- buffer's configured indent expression (highest fidelity)
2. Treesitter scope depth -- walks the AST to count nesting levels
3. Heuristic fallback -- uses nearest non-blank line's whitespace

Charwise and blockwise register types fall through to vanilla Vim paste.

## Comparison

How does smart-paste compare to existing solutions?

| Feature | smart-paste.nvim | vim-pasta | nvim-pasta | `]p` (builtin) |
|---------|------------------|-----------|------------|----------------|
| Treesitter-aware indent | Yes | No | No | No |
| indentexpr support | Yes | No | No | Partial |
| Visual mode paste | Yes (linewise) | Yes | Planned | No |
| Dot-repeat | Yes | No | No | Yes |
| Undo atomicity | Yes | No | Unknown | Yes |
| Register safety | Yes (never mutates) | Unknown | Unknown | Yes |
| Zero config | Yes | Yes | Needs keymap setup | N/A (builtin) |
| Maintained (2025+) | Yes | No (2011) | Limited activity | Yes (core) |
| Neovim Lua native | Yes | No (VimScript) | Yes | N/A |

## License

[MIT](LICENSE)
