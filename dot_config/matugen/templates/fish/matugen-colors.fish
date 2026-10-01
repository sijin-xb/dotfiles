# =============================================================================
#  fish 语法高亮配色 —— matugen 生成，不要手改
#  模板：~/.config/matugen/templates/fish/matugen-colors.fish
#
#  安装方式：本文件输出到 ~/.config/fish/conf.d/matugen-colors.fish，
#  fish 启动时会自动 source conf.d/ 下的所有 .fish。
#
#  ⚠ 注意 source 顺序：fish 先按字母序 source conf.d/*.fish，最后才读
#  config.fish。所以如果 config.fish 里还有硬编码的 set -g fish_color_*，
#  它会覆盖这里。装了本模板后，请把 config.fish 里那几行删掉。
#
#  颜色全部取自 Material You 语义角色，明暗模式由 matugen 的 default 决定。
# =============================================================================

# ── 命令行语法 ───────────────────────────────────────────────────────────────
set -g fish_color_normal          {{colors.on_surface.default.hex}}
set -g fish_color_command         {{colors.primary.default.hex}}
set -g fish_color_keyword         {{colors.tertiary.default.hex}}
set -g fish_color_quote           {{colors.tertiary_fixed_dim.default.hex}}
set -g fish_color_redirection     {{colors.secondary.default.hex}}
set -g fish_color_end             {{colors.secondary.default.hex}}
set -g fish_color_error           {{colors.error.default.hex}}
set -g fish_color_param           {{colors.on_surface.default.hex}}
set -g fish_color_comment         {{colors.outline.default.hex}}
set -g fish_color_match           --background={{colors.inverse_primary.default.hex}} --foreground={{colors.inverse_surface.default.hex}}
set -g fish_color_operator        {{colors.secondary.default.hex}}
set -g fish_color_escape          {{colors.tertiary.default.hex}}
set -g fish_color_autosuggestion  {{colors.outline.default.hex}}

# ── 选区 ─────────────────────────────────────────────────────────────────────
set -g fish_color_selection       --background={{colors.primary_container.default.hex}} --foreground={{colors.on_primary_container.default.hex}}
set -g fish_color_search_match    --background={{colors.secondary_container.default.hex}} --foreground={{colors.on_secondary_container.default.hex}}
set -g fish_color_history_current --bold

# ── 提示符（fish 内置 prompt 用；starship 接管后这几项只在降级时生效）──────
set -g fish_color_user            {{colors.tertiary.default.hex}}
set -g fish_color_host            {{colors.primary.default.hex}}
set -g fish_color_host_remote     {{colors.tertiary.default.hex}}
set -g fish_color_cwd             {{colors.primary.default.hex}}
set -g fish_color_cwd_root        {{colors.error.default.hex}}
set -g fish_color_valid_path      --underline {{colors.primary.default.hex}}
set -g fish_color_cancel          {{colors.error.default.hex}}

# ── 补全分页器 ───────────────────────────────────────────────────────────────
set -g fish_pager_color_background            {{colors.surface_container_low.default.hex}}
set -g fish_pager_color_prefix                --bold --underline {{colors.primary.default.hex}}
set -g fish_pager_color_completion            {{colors.on_surface.default.hex}}
set -g fish_pager_color_description           {{colors.outline.default.hex}}
set -g fish_pager_color_progress              {{colors.on_surface_variant.default.hex}}
set -g fish_pager_color_secondary_background  {{colors.surface_container.default.hex}}
set -g fish_pager_color_selected_background   --background={{colors.secondary_container.default.hex}}
set -g fish_pager_color_selected_prefix       {{colors.on_secondary_container.default.hex}}
set -g fish_pager_color_selected_completion   {{colors.on_secondary_container.default.hex}}
set -g fish_pager_color_selected_description  {{colors.on_secondary_container.default.hex}}
