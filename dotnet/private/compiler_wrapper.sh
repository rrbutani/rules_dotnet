#! /usr/bin/env bash
set -eou pipefail

# This wrapper script is used because the C#/F# compilers both embed absolute paths
# into their outputs and those paths are not deterministic. The compilers also
# allow overriding these paths using pathmaps. Since the paths can not be known
# at analysis time we need to override them at execution time.

COMPILER="$2"
PATHMAP_FLAG="-pathmap"

# Needed because unfortunately the F# compiler uses a different flag name
if [[ $(basename "$COMPILER") == "fsc.dll" ]]; then
  PATHMAP_FLAG="--pathmap"
fi
PATHMAP="$PATHMAP_FLAG:$PWD=."

# NOTE: not setting on the `CSharpCompile`/`FSharpCompile` actions because of
# path mapping; we do not have a way to path-map env vars yet...
#
# TODO(path-mapping, blocked-on-upstream-bazel): want `env: dict[str, Args]`?
#   - see: https://github.com/bazelbuild/bazel/pull/29875 (not quite enough)
export DOTNET_CLI_HOME="$(dirname "$1")"

# shellcheck disable=SC2145
./"$@" "$PATHMAP"
