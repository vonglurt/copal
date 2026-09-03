-- Copal theme: antiquity. Linux Antiquity's helios palette -- the light half,
-- which is the half its kitty.conf paints the terminal with. See docs/THEME.md
-- for why the terminal is light while the shell chrome is dark; the editor
-- lives in the terminal, so it follows the terminal.
local p = {
  bg = '#fce2ab', bg_dark = '#f2d492', bg_hi = '#e8c473',
  fg = '#000000', comment = '#7a6636',
  brown = '#6b4423', rust = '#a33b20', olive = '#5c6b1f',
  ink = '#1e2a3a', wine = '#7b2d3e', gold = '#8a6a12',
}

-- 'shine', not 'habamax', and the order matters -- both were bugs found by
-- actually running this.
--
-- ORDER: a colorscheme sets 'background' itself, so assigning it first is
-- pointless. habamax forces background=dark, which silently undid the
-- 'light' this theme had just asked for.
--
-- BASE: and that mattered for more than one variable. 'background' is what
-- every highlight group this file does NOT override consults -- Folded,
-- MatchParen, DiffAdd, Todo, WinSeparator and a few dozen more. Left at
-- dark, all of them keep habamax's dark-scheme colours and render on a cream
-- background, where several are unreadable. Building on a light base means
-- the groups named below are corrections rather than the only thing standing
-- between you and grey-on-cream. 'shine' is the cleanest light scheme
-- Neovim ships; Normal is overridden to the helios paper colour regardless.
pcall(vim.cmd.colorscheme, 'shine')
vim.o.background = 'light'

if vim.env.COLORTERM == 'truecolor' or vim.env.COLORTERM == '24bit' then
  vim.o.termguicolors = true
  local hi = function(g, o) vim.api.nvim_set_hl(0, g, o) end
  hi('Normal',       { fg = p.fg, bg = p.bg })
  hi('NormalFloat',  { fg = p.fg, bg = p.bg_dark })
  hi('FloatBorder',  { fg = p.brown, bg = p.bg_dark })
  hi('LineNr',       { fg = p.comment })
  hi('CursorLineNr', { fg = p.rust, bold = true })
  hi('Visual',       { bg = p.bg_hi })
  hi('Comment',      { fg = p.comment, italic = true })
  hi('Constant',     { fg = p.gold })
  hi('String',       { fg = p.olive })
  hi('Identifier',   { fg = p.wine })
  hi('Function',     { fg = p.ink, bold = true })
  hi('Statement',    { fg = p.rust, bold = true })
  hi('PreProc',      { fg = p.brown })
  hi('Type',         { fg = p.ink })
  hi('Special',      { fg = p.brown })
  hi('Search',       { fg = p.bg, bg = p.brown })
  hi('IncSearch',    { fg = p.bg, bg = p.rust })
  hi('Pmenu',        { fg = p.fg, bg = p.bg_hi })
  hi('PmenuSel',     { fg = p.bg, bg = p.brown })
  hi('StatusLine',   { fg = p.bg, bg = p.brown })
  hi('StatusLineNC', { fg = p.comment, bg = p.bg_hi })
  hi('DiagnosticError', { fg = p.rust })
  hi('DiagnosticWarn',  { fg = p.gold })
  hi('DiagnosticInfo',  { fg = p.ink })
  hi('DiagnosticHint',  { fg = p.olive })
else
  vim.o.termguicolors = false
  vim.cmd([[
    highlight Normal       ctermbg=NONE ctermfg=0
    highlight Comment      ctermfg=94
    highlight String       ctermfg=100
    highlight Function     ctermfg=17
    highlight Statement    ctermfg=124
    highlight Type         ctermfg=23
    highlight Constant     ctermfg=136
    highlight StatusLine   ctermfg=230 ctermbg=94
  ]])
end
