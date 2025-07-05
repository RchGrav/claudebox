# Detect host → set $BROWSER so every CLI can 'open' URLs on the host.

detect_mode() {
  case "${DOCKER_BROWSER_MODE:-}" in
        linux-x11|wsl2|darwin-fifo) echo "$DOCKER_BROWSER_MODE"; return;;
  esac

  # fallback heuristic if env not provided
  if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null ; then
      echo wsl2
  elif [[ -n "$DISPLAY" && -S /tmp/.X11-unix/$(echo "$DISPLAY"|cut -d: -f2) ]]; then
      echo linux-x11
  elif [[ "$(uname -s)" == "Linux" ]]; then
      # Linux without display - could be headless or WSL without X
      echo wsl2  # Default to wslview, it will fail gracefully if not in WSL
  else
      # Only assume macOS if we're not on Linux
      echo darwin-fifo
  fi
}

case "$(detect_mode)" in
  wsl2)
    export BROWSER=wslview
    ;;
  linux-x11)
    export BROWSER=xdg-open
    ;;
  darwin-fifo)
    export BROWSER='sh -c "echo $1 > /var/run/browser.fifo"'
    ;;
esac
