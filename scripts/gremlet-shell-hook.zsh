# Optional: source this from ~/.zshrc to have a Gremlet wave whenever a command takes longer than 30 seconds.
#   source /path/to/DesktopPets/scripts/gremlet-shell-hook.zsh
GREMLET_LONG_SECONDS=${GREMLET_LONG_SECONDS:-30}
autoload -Uz add-zsh-hook
_gremlet_preexec() { _gremlet_started=$SECONDS }
_gremlet_precmd() {
  local code=$?
  [[ -z $_gremlet_started ]] && return
  if (( SECONDS - _gremlet_started >= GREMLET_LONG_SECONDS )); then
    local action=done; (( code != 0 )) && action=fail
    curl -s -m 1 -X POST -H 'X-Gremlets: 1' "http://127.0.0.1:${GREMLETS_PORT:-47920}/$action" >/dev/null 2>&1 &!
  fi
  unset _gremlet_started
}
add-zsh-hook preexec _gremlet_preexec
add-zsh-hook precmd _gremlet_precmd
