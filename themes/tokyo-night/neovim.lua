-- Copal theme: tokyo-night. The palette stage 4 paints i3, the terminal and
-- the status bar with -- the same six values, so the editor is not a
-- different program's idea of dark.
local p = {
  bg = '#1a1b26', bg_dark = '#16161e', bg_hi = '#292e42',
  fg = '#c0caf5', comment = '#565f89',
  blue = '#7aa2f7', cyan = '#7dcfff', green = '#9ece6a',
  yellow = '#e0af68', red = '#f7768e', magenta = '#bb9af7',
}

-- After the colorscheme, not before: a colorscheme sets 'background' itself
-- and would overwrite an assignment made first. habamax already sets dark, so
-- this line changes nothing today -- it stops being a no-op the moment
-- somebody changes the base, which is exactly how the light theme broke.
pcall(vim.cmd.colorscheme, 'habamax')
vim.o.background = 'dark'

if vim.env.COLORTERM == 'truecolor' or vim.env.COLORTERM == '24bit' then
  vim.o.termguicolors = true
  local hi = function(g, o) vim.api.nvim_set_hl(0, g, o) end
  hi('Normal',       { fg = p.fg, bg = p.bg })
  hi('NormalFloat',  { fg = p.fg, bg = p.bg_dark })
  hi('FloatBorder',  { fg = p.blue, bg = p.bg_dark })
  hi('LineNr',       { fg = p.comment })
  hi('CursorLineNr', { fg = p.yellow, bold = true })
  hi('Visual',       { bg = p.bg_hi })
  hi('Comment',      { fg = p.comment, italic = true })
  hi('Constant',     { fg = p.yellow })
  hi('String',       { fg = p.green })
  hi('Identifier',   { fg = p.magenta })
  hi('Function',     { fg = p.blue })
  hi('Statement',    { fg = p.magenta })
  hi('PreProc',      { fg = p.cyan })
  hi('Type',         { fg = p.cyan })
  hi('Special',      { fg = p.cyan })
  hi('Search',       { fg = p.bg, bg = p.yellow })
  hi('IncSearch',    { fg = p.bg, bg = p.red })
  hi('Pmenu',        { fg = p.fg, bg = p.bg_hi })
  hi('PmenuSel',     { fg = p.bg, bg = p.blue })
  hi('StatusLine',   { fg = p.fg, bg = p.bg_hi })
  hi('StatusLineNC', { fg = p.comment, bg = p.bg_dark })
  hi('DiagnosticError', { fg = p.red })
  hi('DiagnosticWarn',  { fg = p.yellow })
  hi('DiagnosticInfo',  { fg = p.blue })
  hi('DiagnosticHint',  { fg = p.cyan })
else
  -- 256-colour fallback: the nearest cube entries to the same six colours.
  vim.o.termguicolors = false
  vim.cmd([[
    highlight Normal       ctermbg=NONE ctermfg=189
    highlight Comment      ctermfg=61
    highlight String       ctermfg=107
    highlight Function     ctermfg=110
    highlight Statement    ctermfg=141
    highlight Type         ctermfg=117
    highlight Constant     ctermfg=179
    highlight Search       ctermfg=234 ctermbg=179
    highlight StatusLine   ctermfg=189 ctermbg=237
  ]])
end
