#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
source_dir=${script_dir:h}
app_dir="$source_dir/.build/Topgrade Menu.app"
topgrade_executable=${TOPGRADE_EXECUTABLE:-}

if [[ -z "$topgrade_executable" ]]; then
    topgrade_executable=$(whence -p topgrade 2>/dev/null || true)
fi

if [[ "$topgrade_executable" != /* || ! -x "$topgrade_executable" || -d "$topgrade_executable" ]]; then
    /usr/bin/printf '%s\n' \
        "Topgrade was not found as an absolute executable path." \
        "Install Topgrade or set TOPGRADE_EXECUTABLE to its absolute path." >&2
    exit 1
fi

cd "$source_dir"
"$script_dir/check.sh"
/usr/bin/swift build -c release --product TopgradeMenu

if [[ "$app_dir" != "$source_dir/.build/Topgrade Menu.app" || "$source_dir" == / ]]; then
    /usr/bin/printf 'Refusing unsafe build destination: %s\n' "$app_dir" >&2
    exit 1
fi
if [[ -e "$app_dir" ]]; then
    /bin/rm -rf -- "$app_dir"
fi

/bin/mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
/bin/cp "$source_dir/.build/release/TopgradeMenu" "$app_dir/Contents/MacOS/TopgradeMenu"
/bin/cp "$source_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
/bin/cp "$source_dir/Resources/Run Topgrade.command" "$app_dir/Contents/Resources/Run Topgrade.command"
/bin/chmod 755 "$app_dir/Contents/MacOS/TopgradeMenu" "$app_dir/Contents/Resources/Run Topgrade.command"
/usr/bin/printf '%s\n' "$topgrade_executable" > "$app_dir/Contents/Resources/topgrade-path"
safe_path=""
for path_entry in ${(s/:/)PATH}; do
    if [[ "$path_entry" == /* && "$path_entry" != *$'\n'* && "$path_entry" != *$'\r'* ]]; then
        safe_path=${safe_path:+$safe_path:}$path_entry
    fi
done
if [[ -z "$safe_path" ]]; then
    /usr/bin/printf '%s\n' 'PATH did not contain any safe absolute directories.' >&2
    exit 1
fi
/usr/bin/printf '%s\n' "$safe_path" > "$app_dir/Contents/Resources/topgrade-environment-path"
/bin/chmod 644 \
    "$app_dir/Contents/Info.plist" \
    "$app_dir/Contents/Resources/topgrade-path" \
    "$app_dir/Contents/Resources/topgrade-environment-path"

/usr/bin/plutil -lint "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier dev.illatillmods.TopgradeMenu "$app_dir"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_dir"

/usr/bin/printf '%s\n' "$app_dir"
