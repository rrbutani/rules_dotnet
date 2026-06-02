#! /usr/bin/env bash
set -eou pipefail

# This wrapper script is used because the C#/F# compilers both embed absolute paths
# into their outputs and those paths are not deterministic. The compilers also
# allow overriding these paths using pathmaps. Since the paths can not be known
# at analysis time we need to override them at execution time.

COMPILER="$2"
PATHMAP_FLAG="-pathmap"

# export FORCECONSOLECOLOR=1
# export FORCE_COLOR=1
# export TERM=xterm
# export DOTNET_SYSTEM_CONSOLE_ALLOW_ANSI_COLOR_REDIRECTION=1
export PATH+=":/run/current-system/sw/bin/"
export LD_LIBRARY_PATH+=":/nix/store/4424mzk2pyia5v1j33zjgrjaivrdy03y-icu4c-76.1/lib/"

# Needed because unfortunately the F# compiler uses a different flag name
if [[ $(basename "$COMPILER") == "fsc.dll" ]]; then
  PATHMAP_FLAG="--pathmap"
fi
PATHMAP="$PATHMAP_FLAG:$PWD=."

# shellcheck disable=SC2145
./"$@" "$PATHMAP"
