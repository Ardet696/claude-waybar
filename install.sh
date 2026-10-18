#!/usr/bin/env bash
# claude-waybar installer
#
#   ./install.sh              link scripts into ~/.local/bin and register the
#                             Claude Code hooks + statusLine
#   ./install.sh --uninstall  undo both
#
# ~/.claude/settings.json is backed up to settings.json.claude-waybar-bak
# before every change. Existing hooks are kept; an existing statusLine is
# chained (claude-waybar-statusline passes the payload through to it).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_HOME="$HOME/.local/bin"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
HOOK="$BIN_HOME/claude-waybar-hook"
STATUS="$BIN_HOME/claude-waybar-statusline"
EVENTS='["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","Notification",
	"Stop","SubagentStart","SubagentStop","SessionEnd"]'

# Drop every hook group that calls claude-waybar-hook
STRIP='def strip: map(select(any(.hooks[]?; .command | contains("claude-waybar-hook")) | not));'

patch_settings() {
	local filter=$1
	mkdir -p "$(dirname "$SETTINGS")"
	[[ -s $SETTINGS ]] || echo '{}' >"$SETTINGS"
	cp "$SETTINGS" "$SETTINGS.claude-waybar-bak"
	jq --arg hook "$HOOK" --arg status "$STATUS" --argjson events "$EVENTS" \
		"$STRIP $filter" "$SETTINGS" >"$SETTINGS.tmp"
	mv "$SETTINGS.tmp" "$SETTINGS"
}

install() {
	mkdir -p "$BIN_HOME"
	local src
	for src in "$REPO"/bin/*; do
		ln -sfn "$src" "$BIN_HOME/$(basename "$src")"
		echo "linked $BIN_HOME/$(basename "$src")"
	done

	patch_settings '
		.hooks //= {}
		| reduce $events[] as $e (.;
			.hooks[$e] = ((.hooks[$e] // []) | strip)
				+ [{hooks: [{type: "command", command: "\($hook) \($e)", async: true}]}])
		| (.statusLine.command // "") as $cur
		| if ($cur | contains("claude-waybar-statusline")) then .
		elif $cur == "" then .statusLine = {type: "command", command: $status}
		else .statusLine.command = "\($status) \($cur)" end'
	echo "registered hooks + statusLine in $SETTINGS"

	cat <<-EOF

		Next: add the waybar module (see README.md)
		  1. copy waybar/module.jsonc into your waybar config and put "custom/claude" in a modules-* list
		  2. append waybar/style.css to your waybar style.css
		  3. pkill -SIGUSR2 waybar
		New Claude Code sessions show up automatically.
	EOF
}

uninstall() {
	local src
	for src in "$REPO"/bin/*; do
		local dst="$BIN_HOME/$(basename "$src")"
		[[ -L $dst ]] && rm "$dst" && echo "removed $dst"
	done

	[[ -f $SETTINGS ]] || return 0
	patch_settings '
		.hooks |= ((. // {}) | map_values(strip) | with_entries(select(.value | length > 0)))
		| if .hooks == {} then del(.hooks) else . end
		| (.statusLine.command // "") as $cur
		| if ($cur | startswith($status)) then
			($cur | ltrimstr($status) | ltrimstr(" ")) as $rest
			| if $rest == "" then del(.statusLine) else .statusLine.command = $rest end
		else . end'
	echo "removed hooks + statusLine from $SETTINGS"
}

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

case ${1:-} in
	'')          install ;;
	--uninstall) uninstall ;;
	*)           echo "usage: $0 [--uninstall]" >&2; exit 1 ;;
esac
