#!/bin/zsh
set -euo pipefail

destination_app="$HOME/Applications/Topgrade Menu.app"
ghostty_alias="$HOME/.TopgradeMenu.app"
ghostty_alias_target="Applications/Topgrade Menu.app"
prior_running=false
register_login=false
state_changed=false
ghostty_alias_removed=false
uninstall_complete=false

if (( EUID == 0 )); then
    /usr/bin/printf '%s\n' 'Do not run this uninstaller with sudo or as root.' >&2
    exit 1
fi

if [[ ! -e "$destination_app" ]]; then
    if [[ -L "$ghostty_alias" \
        && "$(/usr/bin/readlink "$ghostty_alias")" == "$ghostty_alias_target" ]]; then
        /bin/rm "$ghostty_alias"
    fi
    /usr/bin/printf '%s\n' 'Topgrade Menu is not installed in ~/Applications.'
    exit 0
fi

prior_login_status=$("$destination_app/Contents/MacOS/TopgradeMenu" --status \
    | /usr/bin/sed -n 's/^Launch at Login: //p')
if [[ "$prior_login_status" == "enabled" || "$prior_login_status" == "requires approval" ]]; then
    register_login=true
fi
if "$destination_app/Contents/MacOS/TopgradeMenu" --is-running >/dev/null; then
    prior_running=true
fi

restore_state_if_needed() {
    local exit_status=$?
    if (( exit_status != 0 )) && [[ "$ghostty_alias_removed" == true \
        && ! -e "$ghostty_alias" \
        && -e "$destination_app" ]]; then
        /bin/ln -s "$ghostty_alias_target" "$ghostty_alias" || true
    fi
    if (( exit_status != 0 )) && [[ "$state_changed" == true && "$uninstall_complete" != true && -x "$destination_app/Contents/MacOS/TopgradeMenu" ]]; then
        if [[ "$register_login" == true ]]; then
            "$destination_app/Contents/MacOS/TopgradeMenu" --register-login || true
        fi
        if [[ "$prior_running" == true ]]; then
            /usr/bin/open "$destination_app" || true
        fi
        /usr/bin/printf '%s\n' 'Uninstall failed; the prior login and running state was restored.' >&2
    fi
    return $exit_status
}
trap restore_state_if_needed EXIT

"$destination_app/Contents/MacOS/TopgradeMenu" --unregister-login
state_changed=true
"$destination_app/Contents/MacOS/TopgradeMenu" --quit
for _ in {1..20}; do
    if ! "$destination_app/Contents/MacOS/TopgradeMenu" --is-running >/dev/null; then
        break
    fi
    /bin/sleep 0.1
done
if "$destination_app/Contents/MacOS/TopgradeMenu" --is-running >/dev/null; then
    /usr/bin/printf '%s\n' 'The app did not quit, so it was not moved.' >&2
    exit 1
fi

if [[ -L "$ghostty_alias" \
    && "$(/usr/bin/readlink "$ghostty_alias")" == "$ghostty_alias_target" ]]; then
    /bin/rm "$ghostty_alias"
    ghostty_alias_removed=true
fi

timestamp=$(/bin/date +%Y%m%d-%H%M%S)
trash_app="$HOME/.Trash/Topgrade Menu-$timestamp.app"
/bin/mkdir -p "$HOME/.Trash"
/bin/mv "$destination_app" "$trash_app"
uninstall_complete=true

/usr/bin/printf '%s\n' \
    "Moved the app to: $trash_app" \
    'Topgrade and this source checkout were left untouched.' \
    'Optional preference removal:' \
    'defaults delete dev.illatillmods.TopgradeMenu'
