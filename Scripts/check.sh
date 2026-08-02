#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
source_dir=${script_dir:h}

for script in "$script_dir"/*.sh; do
    /bin/zsh -n "$script"
done
/bin/sh -n "$source_dir/Resources/Run Topgrade.command"

cd "$source_dir"
/usr/bin/swift run TopgradeMenuChecks
