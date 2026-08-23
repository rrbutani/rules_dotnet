#!/usr/bin/env bash
# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---
runfiles_export_envvars

set -o pipefail -o errexit -o nounset

dotnet="$(rlocation TEMPLATED_dotnet)"

export DOTNET_MULTILEVEL_LOOKUP="false"
export DOTNET_NOLOGO="1"
export DOTNET_CLI_TELEMETRY_OPTOUT="1"
export DOTNET_ROOT="$(dirname "$dotnet")"

# NOTE: in cases where we've got "manifest only" runfiles (i.e. no runfiles
# tree) there is no single path we can add to `additionalProbingPaths` such that
# the paths in `deps.json` will resolve.
#
# For example, say we have the following library dependencies; a mix of source
# files and generated artifacts, across multiple Bazel repositories, built for
# multiple target platform configurations:
# ```console
# <execroot>
# └── _main/
#     ├── bar/bar.dll                      # source file in main repo
#     ├── bazel-out/
#     │   ├── <plat1>/bin/
#     │   │   ├── foo/foo.dll              # generated artifact in main repo
#     │   │   └── external
#     │   │      └── ext_dep1/baz.dll      # generated artifact in external repo
#     │   └── <plat2>/bin/
#     │       ├── quux/quux.dll            # generated artifact in main repo
#     │       └── external
#     │          └── ext_dep2/dep2.dll     # generated artifact in external repo
#     └── external/
#         └── ext_dep1/lib/dep1.dll        # source file in external repo
# ```
#
# `deps.json` would contain `rlocationpaths` as follows:
# ```
# _main/bar/bar.dll   # source file
# _main/foo/foo.dll   # generated artifact
# ext_dep1/baz.dll    # generated artifact
# _main/quux/quux.dll # generated artifact
# ext_dep2/dep2.dll   # generated artifact
# ext_dep1/dep1.dll   # source file
# ```
#
# This maps cleanly to the corresponding `.runfiles` tree:
# ```console
# <target>.runfiles/
# ├─ _main/
# │  ├─ bar/bar.dll
# │  ├─ foo/foo.dll
# │  └─ quux/quux.dll
# ├─ ext_dep1/
# │  ├─ baz.dll
# │  └─ dep1.dll
# └─ ext_dep2/
#    └─ dep2.dll
# ```
#
# Such that we only need to specify the `.runfiles` tree root as an
# `additionalProbingPath`; all the `rlocationpaths` resolve from here.
#
# But, without such a runfiles tree we have to specify all the "root" paths that
# our dependencies reside at; for the above example this is:
# ```
# <execroot>/_main                                 # for main repo source files
# <execroot>/_main/bazel-out/<plat1>/bin/          # for main repo generated artifacts w/config <plat1>
# <execroot>/_main/bazel-out/<plat1>/bin/external/ # for external repo generated artifacts w/config <plat1>
# <execroot>/_main/bazel-out/<plat2>/bin/          # for main repo generated artifacts w/config <plat2>
# <execroot>/_main/bazel-out/<plat2>/bin/external/ # for main repo generated artifacts w/config <plat2>
# <execroot>/_main/external                        # for external repo source files
# ```
readonly RLOCATIONS_FOR_DEPS_WITH_UNIQUE_ROOTS=(
TEMPLATED_rlocations_for_deps_with_unique_roots
)

declare -a additional_probing_paths=()
if [[ -n "${RUNFILES_DIR}" ]]; then
  # note: `runfiles_export_envvars` sets this var; if there's no runfiles dir it
  # is empty
  additional_probing_paths+=("${RUNFILES_DIR}")
else
  # we're in manifest-only mode! resolve absolute *root* paths for all the dep
  # rlocations we were given as having unique roots:
  for rloc in "${RLOCATIONS_FOR_DEPS_WITH_UNIQUE_ROOTS[@]}"; do
    resolved="$(rlocation "$rloc")"
    if ! [[ "$resolved" == *"$rloc" ]]; then
      echo >&2 "ERROR: resolved path for rlocation '$rloc' does not end with rlocation: '$resolved'"
      exit 1
    fi
    additional_probing_paths+=("${resolved%"$rloc"}")
  done
fi

declare -a extra_flags=()
for path in "${additional_probing_paths[@]}"; do
  extra_flags+=("--additionalprobingpath" "$path")
done

exec "$dotnet" exec "${extra_flags[@]}" "$(rlocation TEMPLATED_executable)" "$@"

# TODO: implement the above for windows as well?
# TODO: replace with hermetic launcher?
