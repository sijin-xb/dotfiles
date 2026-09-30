-- nvim 配色 —— 由 matugen 从壁纸生成，请勿手改。
--
-- 与 kitty / fuzzel / walker / GTK / micro / Kate 共用同一份 M3 色板，
-- 语义按 Material Design 3 的角色映射：
--   表面   surface_container_*          文字  on_surface / on_surface_variant
--   注释   outline                      关键字 primary
--   函数   secondary                    字符串 tertiary
--   错误   error                        类型   secondary（加粗）
--
-- 终端 16 色沿用 kitty 的映射，nvim 里 :terminal 与外面的 kitty 颜色一致。

local c = {
  bg          = "{{colors.surface_container_lowest.default.hex}}",
  bg_alt      = "{{colors.surface_container.default.hex}}",
  bg_float    = "{{colors.surface_container_high.default.hex}}",
  bg_current  = "{{colors.surface_container_low.default.hex}}",
  fg          = "{{colors.on_surface.default.hex}}",
  fg_dim      = "{{colors.on_surface_variant.default.hex}}",
  comment     = "{{colors.outline.default.hex}}",
  outline     = "{{colors.outline_variant.default.hex}}",
  primary     = "{{colors.primary.default.hex}}",
  secondary   = "{{colors.secondary.default.hex}}",
  tertiary    = "{{colors.tertiary.default.hex}}",
  error       = "{{colors.error.default.hex}}",
  sel_bg      = "{{colors.secondary_container.default.hex}}",
  search_bg   = "{{colors.tertiary_container.default.hex}}",
  ok          = "{{colors.tertiary.default.hex}}",
}

local function hi(group, opts)
  vim.api.nvim_set_hl(0, group, opts)
end

vim.o.background = "dark"
vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") then
  vim.cmd("syntax reset")
end
vim.g.colors_name = "matugen"

-- ── 编辑区 / 行号 / 光标 ────────────────────────────────────────────────
hi("Normal",      { fg = c.fg, bg = c.bg })
hi("NormalNC",    { fg = c.fg, bg = c.bg })
hi("NormalFloat", { fg = c.fg, bg = c.bg_float })
hi("FloatBorder", { fg = c.outline, bg = c.bg_float })
hi("FloatTitle",  { fg = c.primary, bg = c.bg_float, bold = true })
hi("SignColumn",  { fg = c.comment, bg = c.bg })
hi("LineNr",      { fg = c.comment })
hi("CursorLine",  { bg = c.bg_current })
hi("CursorLineNr",{ fg = c.fg, bold = true })
hi("CursorColumn",{ bg = c.bg_current })
hi("ColorColumn", { bg = c.bg_current })
hi("Cursor",      { fg = c.bg, bg = c.fg })
hi("TermCursor",  { fg = c.bg, bg = c.fg })
hi("MatchParen",  { fg = c.primary, bold = true })
hi("Whitespace",  { fg = c.outline })
hi("WinSeparator",{ fg = c.outline })
hi("VertSplit",   { fg = c.outline })

-- ── 状态栏 / 标签栏 ─────────────────────────────────────────────────────
hi("StatusLine",   { fg = c.fg,     bg = c.bg_alt })
hi("StatusLineNC", { fg = c.fg_dim, bg = c.bg_alt })
hi("TabLine",      { fg = c.fg_dim, bg = c.bg_alt })
hi("TabLineFill",  { bg = c.bg })
hi("TabLineSel",   { fg = c.primary, bg = c.bg_alt, bold = true })
hi("WildMenu",     { fg = c.bg, bg = c.primary })

-- ── 弹出菜单 / 搜索 / 选区 ──────────────────────────────────────────────
hi("Pmenu",      { fg = c.fg,     bg = c.bg_float })
hi("PmenuSel",   { fg = c.bg,     bg = c.primary, bold = true })
hi("PmenuSbar",  { bg = c.bg_alt })
hi("PmenuThumb", { bg = c.outline })
hi("Search",     { fg = c.fg, bg = c.search_bg })
hi("IncSearch",  { fg = c.fg, bg = c.search_bg, bold = true })
hi("CurSearch",  { fg = c.bg, bg = c.tertiary, bold = true })
hi("Visual",     { bg = c.sel_bg })
hi("VisualNOS",  { bg = c.sel_bg })
hi("Folded",     { fg = c.fg_dim, bg = c.bg_alt })
hi("FoldColumn", { fg = c.comment })
hi("Question",   { fg = c.primary })
hi("MoreMsg",    { fg = c.primary })
hi("WarningMsg", { fg = c.tertiary })
hi("ErrorMsg",   { fg = c.error, bold = true })
hi("MsgArea",    { fg = c.fg })
hi("Directory",  { fg = c.primary })
hi("Title",      { fg = c.primary, bold = true })
hi("Conceal",    { fg = c.fg_dim })
hi("NonText",    { fg = c.outline })
hi("SpecialKey", { fg = c.outline })
hi("EndOfBuffer",{ fg = c.bg })

-- ── 语法：Vim 传统组 ────────────────────────────────────────────────────
hi("Comment",       { fg = c.comment, italic = true })
hi("Constant",      { fg = c.tertiary })
hi("String",        { fg = c.tertiary })
hi("Character",     { fg = c.tertiary })
hi("Number",        { fg = c.tertiary })
hi("Boolean",       { fg = c.tertiary })
hi("Float",         { fg = c.tertiary })
hi("Identifier",    { fg = c.fg })
hi("Function",      { fg = c.secondary })
hi("Statement",     { fg = c.primary })
hi("Conditional",   { fg = c.primary })
hi("Repeat",        { fg = c.primary })
hi("Label",         { fg = c.primary })
hi("Operator",      { fg = c.primary })
hi("Keyword",       { fg = c.primary, bold = true })
hi("Exception",     { fg = c.error })
hi("PreProc",       { fg = c.primary })
hi("Include",       { fg = c.primary })
hi("Define",        { fg = c.primary })
hi("Macro",         { fg = c.primary })
hi("PreCondit",     { fg = c.primary })
hi("Type",          { fg = c.secondary, bold = true })
hi("StorageClass",  { fg = c.secondary })
hi("Structure",     { fg = c.secondary })
hi("Typedef",       { fg = c.secondary, bold = true })
hi("Special",       { fg = c.tertiary })
hi("SpecialChar",   { fg = c.tertiary })
hi("Tag",           { fg = c.primary })
hi("Delimiter",     { fg = c.fg_dim })
hi("SpecialComment",{ fg = c.comment, italic = true })
hi("Debug",         { fg = c.error })
hi("Underlined",    { fg = c.secondary, underline = true })
hi("Ignore",        { fg = c.fg_dim })
hi("Error",         { fg = c.error, bold = true })
hi("Todo",          { fg = c.tertiary, bold = true })

-- ── Treesitter ──────────────────────────────────────────────────────────
hi("@comment",            { link = "Comment" })
hi("@comment.documentation", { fg = c.comment, italic = true })
hi("@constant",           { fg = c.tertiary })
hi("@constant.builtin",   { fg = c.tertiary })
hi("@constant.macro",     { fg = c.primary })
hi("@string",             { fg = c.tertiary })
hi("@string.escape",      { fg = c.secondary })
hi("@string.special",     { fg = c.tertiary })
hi("@character",          { fg = c.tertiary })
hi("@number",             { fg = c.tertiary })
hi("@boolean",            { fg = c.tertiary })
hi("@float",              { fg = c.tertiary })
hi("@function",           { fg = c.secondary })
hi("@function.builtin",   { fg = c.secondary })
hi("@function.call",      { fg = c.secondary })
hi("@function.macro",     { fg = c.primary })
hi("@method",             { fg = c.secondary })
hi("@method.call",        { fg = c.secondary })
hi("@constructor",        { fg = c.secondary })
hi("@keyword",            { fg = c.primary, bold = true })
hi("@keyword.function",   { fg = c.primary, bold = true })
hi("@keyword.operator",   { fg = c.primary })
hi("@keyword.return",     { fg = c.primary, bold = true })
hi("@conditional",        { fg = c.primary })
hi("@repeat",             { fg = c.primary })
hi("@exception",          { fg = c.error })
hi("@include",            { fg = c.primary })
hi("@type",               { fg = c.secondary, bold = true })
hi("@type.builtin",       { fg = c.secondary, bold = true })
hi("@type.definition",    { fg = c.secondary, bold = true })
hi("@type.qualifier",     { fg = c.primary })
hi("@attribute",          { fg = c.secondary })
hi("@property",           { fg = c.fg })
hi("@variable",           { fg = c.fg })
hi("@variable.builtin",   { fg = c.secondary })
hi("@variable.parameter", { fg = c.fg })
hi("@variable.member",    { fg = c.fg })
hi("@namespace",          { fg = c.secondary })
hi("@module",             { fg = c.secondary })
hi("@label",              { fg = c.primary })
hi("@operator",           { fg = c.primary })
hi("@punctuation",        { fg = c.fg_dim })
hi("@punctuation.delimiter", { fg = c.fg_dim })
hi("@punctuation.bracket",   { fg = c.fg_dim })
hi("@punctuation.special",   { fg = c.primary })
hi("@tag",                { fg = c.primary })
hi("@tag.attribute",      { fg = c.secondary })
hi("@tag.delimiter",      { fg = c.fg_dim })
hi("@markup.heading",     { fg = c.primary, bold = true })
hi("@markup.bold",        { bold = true })
hi("@markup.italic",      { italic = true })
hi("@markup.strikethrough", { strikethrough = true })
hi("@markup.link",        { fg = c.secondary, underline = true })
hi("@markup.quote",       { fg = c.comment })
hi("@diff.plus",          { fg = c.ok })
hi("@diff.minus",         { fg = c.error })
hi("@diff.delta",         { fg = c.secondary })

-- ── LSP / 诊断 ──────────────────────────────────────────────────────────
hi("DiagnosticError",            { fg = c.error })
hi("DiagnosticWarn",             { fg = c.tertiary })
hi("DiagnosticInfo",             { fg = c.secondary })
hi("DiagnosticHint",             { fg = c.primary })
hi("DiagnosticVirtualTextError", { fg = c.error, bg = c.bg_current })
hi("DiagnosticVirtualTextWarn",  { fg = c.tertiary, bg = c.bg_current })
hi("DiagnosticVirtualTextInfo",  { fg = c.secondary, bg = c.bg_current })
hi("DiagnosticVirtualTextHint",  { fg = c.primary, bg = c.bg_current })
hi("DiagnosticUnderlineError",   { undercurl = true, sp = c.error })
hi("DiagnosticUnderlineWarn",    { undercurl = true, sp = c.tertiary })
hi("DiagnosticUnderlineInfo",    { undercurl = true, sp = c.secondary })
hi("DiagnosticUnderlineHint",    { undercurl = true, sp = c.primary })
hi("LspReferenceText",           { bg = c.bg_current })
hi("LspReferenceRead",           { bg = c.bg_current })
hi("LspReferenceWrite",          { bg = c.bg_current })
hi("LspSignatureActiveParameter",{ fg = c.primary, bold = true })
hi("LspInfoBorder",              { fg = c.outline })

-- ── Diff / Git ──────────────────────────────────────────────────────────
hi("DiffAdd",    { bg = c.bg_alt, fg = c.ok })
hi("DiffChange", { bg = c.bg_alt, fg = c.secondary })
hi("DiffDelete", { bg = c.bg_alt, fg = c.error })
hi("DiffText",   { bg = c.search_bg, fg = c.fg })
hi("Added",      { fg = c.ok })
hi("Changed",    { fg = c.secondary })
hi("Removed",    { fg = c.error })
hi("GitSignsAdd",    { fg = c.ok })
hi("GitSignsChange", { fg = c.secondary })
hi("GitSignsDelete", { fg = c.error })

-- ── 常用插件的边框与选中（只定色，不定义布局）──────────────────────────
hi("NeoTreeNormal",       { fg = c.fg, bg = c.bg })
hi("NeoTreeNormalNC",     { fg = c.fg, bg = c.bg })
hi("NeoTreeDirectoryName",{ fg = c.primary })
hi("NeoTreeFileName",     { fg = c.fg })
hi("NeoTreeGitModified",  { fg = c.secondary })
hi("NeoTreeGitAdded",     { fg = c.ok })
hi("NeoTreeGitDeleted",   { fg = c.error })
hi("NeoTreeIndentMarker", { fg = c.outline })
hi("TelescopeBorder",     { fg = c.outline })
hi("TelescopeTitle",      { fg = c.primary, bold = true })
hi("TelescopeSelection",  { bg = c.sel_bg })
hi("TelescopeMatching",   { fg = c.primary, bold = true })
hi("LazyNormal",          { bg = c.bg })
hi("LazyButton",          { bg = c.bg_alt, fg = c.fg })
hi("LazyButtonActive",    { bg = c.primary, fg = c.bg, bold = true })
hi("MasonHighlight",      { fg = c.primary })
hi("MasonHeader",         { fg = c.bg, bg = c.primary, bold = true })
hi("NotifyBackground",    { bg = c.bg_float })
hi("NotifyERRORBorder",   { fg = c.error })
hi("NotifyWARNBorder",    { fg = c.tertiary })
hi("NotifyINFOBorder",    { fg = c.secondary })
hi("WhichKeyFloat",       { bg = c.bg_float })

-- ── 终端 16 色：与 kitty 的映射保持一致 ─────────────────────────────────
vim.g.terminal_color_0  = "{{colors.surface_container_lowest.default.hex}}"
vim.g.terminal_color_1  = "{{colors.error.default.hex}}"
vim.g.terminal_color_2  = "{{colors.tertiary.default.hex}}"
vim.g.terminal_color_3  = "{{colors.tertiary_container.default.hex}}"
vim.g.terminal_color_4  = "{{colors.primary.default.hex}}"
vim.g.terminal_color_5  = "{{colors.secondary.default.hex}}"
vim.g.terminal_color_6  = "{{colors.secondary_container.default.hex}}"
vim.g.terminal_color_7  = "{{colors.on_background.default.hex}}"
vim.g.terminal_color_8  = "{{colors.outline.default.hex}}"
vim.g.terminal_color_9  = "{{colors.error.default.hex}}"
vim.g.terminal_color_10 = "{{colors.tertiary.default.hex}}"
vim.g.terminal_color_11 = "{{colors.tertiary_container.default.hex}}"
vim.g.terminal_color_12 = "{{colors.primary.default.hex}}"
vim.g.terminal_color_13 = "{{colors.secondary.default.hex}}"
vim.g.terminal_color_14 = "{{colors.secondary_container.default.hex}}"
vim.g.terminal_color_15 = "{{colors.on_background.default.hex}}"
