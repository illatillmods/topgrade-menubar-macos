#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
source_dir=${script_dir:h}
source_app="$source_dir/.build/Topgrade Menu.app"
destination_dir="$HOME/Applications"
destination_app="$destination_dir/Topgrade Menu.app"
ghostty_alias="$HOME/.TopgradeMenu.app"
ghostty_alias_target="Applications/Topgrade Menu.app"
seed_used_now=false
terminal_selection=""
register_login=true
fresh_install=true
prior_running=false
backup_app=""
destination_touched=false
ghostty_alias_created=false
install_complete=false

while (( $# > 0 )); do
    case "$1" in
        --seed-used-now)
            seed_used_now=true
            shift
            ;;
        --terminal)
            if (( $# < 2 )); then
                /usr/bin/printf '%s\n' 'Missing value after --terminal.' >&2
                exit 64
            fi
            terminal_selection=$2
            shift 2
            ;;
        *)
            /usr/bin/printf 'Unknown installer option: %s\n' "$1" >&2
            exit 64
            ;;
    esac
done

if (( EUID == 0 )); then
    /usr/bin/printf '%s\n' 'Do not run this installer with sudo or as root.' >&2
    exit 1
fi

rollback_if_needed() {
    local exit_status=$?
    if (( exit_status != 0 )) && [[ "$install_complete" != true ]]; then
        if [[ "$ghostty_alias_created" == true \
            && -L "$ghostty_alias" \
            && "$(/usr/bin/readlink "$ghostty_alias")" == "$ghostty_alias_target" ]]; then
            /bin/rm "$ghostty_alias"
        fi

        if [[ "$destination_touched" == true && -e "$destination_app" ]]; then
            if [[ -x "$destination_app/Contents/MacOS/TopgradeMenu" ]]; then
                "$destination_app/Contents/MacOS/TopgradeMenu" --unregister-login || true
            fi
            "$source_app/Contents/MacOS/TopgradeMenu" --quit || true
            for _ in {1..20}; do
                if ! "$source_app/Contents/MacOS/TopgradeMenu" --is-running >/dev/null; then
                    break
                fi
                /bin/sleep 0.1
            done

            if ! "$source_app/Contents/MacOS/TopgradeMenu" --is-running >/dev/null; then
                if [[ -n "$backup_app" ]]; then
                    failed_app="${backup_app:h}/Failed Topgrade Menu.app.disabled"
                else
                    failed_dir="$HOME/Library/Application Support/Topgrade Menu/Failed Installs/$(/bin/date +%Y%m%d-%H%M%S)-$$"
                    /bin/mkdir -p "$failed_dir"
                    failed_app="$failed_dir/Topgrade Menu.app.disabled"
                fi
                /bin/mv "$destination_app" "$failed_app" || true
            fi
        fi

        if [[ -n "$backup_app" && -e "$backup_app" ]]; then
            if [[ ! -e "$destination_app" ]]; then
                /bin/mv "$backup_app" "$destination_app"
                /usr/bin/printf '%s\n' 'Installation failed; the previous app was restored.' >&2
            else
                /usr/bin/printf '%s\n' \
                    "Installation failed; the previous app remains recoverable at $backup_app." >&2
            fi
        fi
        if [[ "$fresh_install" == false && -x "$destination_app/Contents/MacOS/TopgradeMenu" ]]; then
            if [[ "$register_login" == true ]]; then
                "$destination_app/Contents/MacOS/TopgradeMenu" --register-login || true
            fi
            if [[ "$prior_running" == true ]]; then
                /usr/bin/open "$destination_app" || true
            fi
        fi
    fi
    return $exit_status
}
trap rollback_if_needed EXIT

if [[ -e "$ghostty_alias" || -L "$ghostty_alias" ]]; then
    if [[ ! -L "$ghostty_alias" \
        || "$(/usr/bin/readlink "$ghostty_alias")" != "$ghostty_alias_target" ]]; then
        /usr/bin/printf '%s\n' \
            "Installation stopped because $ghostty_alias already exists and is not the expected app alias." >&2
        exit 1
    fi
fi

"$script_dir/build-app.sh"
/bin/mkdir -p "$destination_dir"

if [[ -e "$destination_app" ]]; then
    fresh_install=false
    if "$source_app/Contents/MacOS/TopgradeMenu" --is-running >/dev/null; then
        prior_running=true
    fi
    register_login=false
    prior_login_status=$("$destination_app/Contents/MacOS/TopgradeMenu" --status \
        | /usr/bin/sed -n 's/^Launch at Login: //p')
    if [[ "$prior_login_status" == "enabled" || "$prior_login_status" == "requires approval" ]]; then
        register_login=true
    fi

    "$destination_app/Contents/MacOS/TopgradeMenu" --unregister-login
    "$source_app/Contents/MacOS/TopgradeMenu" --quit
    for _ in {1..20}; do
        if ! "$source_app/Contents/MacOS/TopgradeMenu" --is-running >/dev/null; then
            break
        fi
        /bin/sleep 0.1
    done
    if "$source_app/Contents/MacOS/TopgradeMenu" --is-running >/dev/null; then
        /usr/bin/printf '%s\n' 'The existing Topgrade Menu app did not quit; installation stopped safely.' >&2
        exit 1
    fi

    timestamp=$(/bin/date +%Y%m%d-%H%M%S)
    backup_dir="$HOME/Library/Application Support/Topgrade Menu/Backups/$timestamp-$$"
    backup_app="$backup_dir/Topgrade Menu.app.disabled"
    /bin/mkdir -p "$backup_dir"
    /bin/mv "$destination_app" "$backup_app"
    /usr/bin/printf '%s\n' \
        "Topgrade Menu.app archived before replacement at $timestamp." \
        "Restore by moving Topgrade Menu.app.disabled back to $destination_app." \
        > "$backup_dir/MANIFEST.txt"
fi

destination_touched=true
/usr/bin/ditto "$source_app" "$destination_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$destination_app"

if [[ ! -L "$ghostty_alias" ]]; then
    /bin/ln -s "$ghostty_alias_target" "$ghostty_alias"
    ghostty_alias_created=true
fi
if [[ ! -x "$ghostty_alias/Contents/MacOS/TopgradeMenu" ]]; then
    /usr/bin/printf '%s\n' 'The Ghostty runner alias does not resolve to the installed app.' >&2
    exit 1
fi

if [[ -n "$terminal_selection" ]]; then
    "$destination_app/Contents/MacOS/TopgradeMenu" --set-terminal "$terminal_selection"
elif [[ "$fresh_install" == true ]]; then
    "$destination_app/Contents/MacOS/TopgradeMenu" --set-terminal-from-environment
fi

if [[ "$register_login" == true ]]; then
    "$destination_app/Contents/MacOS/TopgradeMenu" --register-login
else
    /usr/bin/printf '%s\n' 'Launch at Login: not registered (preserved)'
fi

if [[ "$seed_used_now" == true ]]; then
    "$destination_app/Contents/MacOS/TopgradeMenu" --mark-used-now
fi

/usr/bin/open "$destination_app"

for _ in {1..20}; do
    if "$destination_app/Contents/MacOS/TopgradeMenu" --is-running >/dev/null; then
        break
    fi
    /bin/sleep 0.25
done
if ! "$destination_app/Contents/MacOS/TopgradeMenu" --is-running >/dev/null; then
    /usr/bin/printf '%s\n' 'The app was installed but did not remain running.' >&2
    exit 1
fi

"$destination_app/Contents/MacOS/TopgradeMenu" --status
install_complete=true
