# Reader for .ai/config.yaml — flat YAML subset (domains/install).
# Keys are `section.key: value`; lists are inline `[a, b]`; no nesting.
# shellcheck shell=bash

# Path of the config file for the current project (JIG_PROJECT must be set).
jig_config_file() { printf '%s/%s/config.yaml\n' "$JIG_PROJECT" "$JIG_AI_DIR"; }

# cfg <key> [default] — print the scalar value of <key>, or the default.
cfg() {
  local key="$1" default="${2:-}" file value
  file=$(jig_config_file)
  if [ -f "$file" ]; then
    value=$(sed -n "s/^${key}:[[:space:]]*//p" "$file" | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//' | head -n 1)
  else
    value=""
  fi
  printf '%s\n' "${value:-$default}"
}

# cfg_list <key> [default-list] — print an inline list as space-separated words.
cfg_list() {
  cfg "$1" "${2:-}" | tr -d '[]' | tr ',' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'
}

# cfg_bool <key> [default] — exit 0 when the value is true/yes/1.
cfg_bool() {
  case "$(cfg "$1" "${2:-false}")" in
    true|yes|1|on) return 0 ;;
    *) return 1 ;;
  esac
}
