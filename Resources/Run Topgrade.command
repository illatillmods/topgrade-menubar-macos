#!/bin/sh
set -eu

resource_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
runner="$resource_dir/../MacOS/TopgradeMenu"

exec "$runner" --run-topgrade
