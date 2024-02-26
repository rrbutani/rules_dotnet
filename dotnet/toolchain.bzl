"""
Rules to configure the .NET toolchain of rules_dotnet.
"""

DotnetInfo = provider(
    doc = "Information about the dotnet toolchain",
    fields = {
        "runtime_path": "Path to the dotnet executable",
        "runtime_files": """Files required in runfiles to make the dotnet executable available.

May be empty if the runtime_path points to a locally installed tool binary.""",
        "csharp_compiler_path": "Path to the C# compiler executable",
        "csharp_compiler_files": """Files required in runfiles to make the C# compiler executable available.

May be empty if the csharp_compiler_path points to a locally installed tool binary.""",
        "fsharp_compiler_path": "Path to the F# compiler executable",
        "fsharp_compiler_files": """Files required in runfiles to make the F# compiler executable available.

May be empty if the fsharp_compiler_path points to a locally installed tool binary.""",
        "apphost_path": "Path to the apphost executable",
        "apphost_files": """Files required in runfiles to make the apphost executable available.

May be empty if the apphost_path points to a locally installed tool binary.""",
        "sdk_version": "Version of the dotnet SDK",
        "runtime_version": "Version of the dotnet runtime",
        "runtime_tfm": "The target framework moniker for the current SDK",
        "csharp_default_version": "Default version of the C# language",
        "csharp_treat_warnings_as_errors": "Treat all C# compiler warnings as errors",
        "csharp_warnings_as_errors": "List of C# compiler warning codes that should be treated as errors",
        "csharp_warnings_not_as_errors": "List of C# compiler warning codes that should not be treated as errors",
        "csharp_warning_level": "List of C# compiler warning codes that should not be displayed",
        "fsharp_default_version": "Default version of the F# language",
        "fsharp_treat_warnings_as_errors": "Treat all F# compiler warnings as errors",
        "fsharp_warnings_as_errors": "List of F# compiler warning codes that should be treated as errors",
        "fsharp_warnings_not_as_errors": "List of F# compiler warning codes that should not be treated as errors",
        "fsharp_warning_level": "List of F# compiler warning codes that should not be displayed",
    },
)

def _is_repository_main(repository):
    return repository == ""

# TODO: add tests!

# buildifier: disable=no-effect
"""
Remember:
  - with [sibling layout]:
    ```
    execroot
    ├── ext # some external repo
    └── main_repo_name # main repo; also pwd for actions
        └── bazel-out
            └── ext
                └── k8-fastbuild
                    └── bin
                    #   ^^^ is what `ctx.bin_dir` will be for targets in `@ext`:
                    # `bazel-out/ext/k8-fastbuild/bin`
    ```
  - without:
    ```
    execroot
    └── main_repo_name # main repo; also pwd for actions
        ├── bazel-out
        │   └── k8-fastbuild
        │       └── bin # < is what `ctx.bin_dir` will be: `bazel-out/k8-fastbuild/bin`
        │           └── external
        │               └── ext
        └── external
            └── ext # some external repo
    ```

[sibling layout]: https://bazel.build/reference/command-line-reference#flag--experimental_sibling_repository_layout

Also see:
  - https://github.com/bazelbuild/bazel/issues/12821
"""
def _sibling_repository_layout_enabled(ctx):
    # NOTE: we'd like to just use `is_sibling_repository_layout()` but it's a
    # private API:
    # return ctx.configuration.is_sibling_repository_layout()

    # So instead, we can _infer_ whether sibling repository layout is enabled
    # by looking at `ctx.bin_dir`.
    #
    # A quick recap of `bin_dir` values (as detailed above):
    #  + rule invocation in main repo:
    #    - not sibling layout: bazel-out/k8-fastbuild/bin
    #    - sibling layout: bazel-out/k8-fastbuild/bin
    #  + rule invocation in external repo:
    #    - not sibling layout: bazel-out/k8-fastbuild/bin
    #    - sibling layout: bazel-out/<external repo name>/k8-fastbuild/bin

    repository = ctx.label.workspace_name
    if not _is_repository_main(repository):
        bin_path = ctx.bin_dir.path
        # NOTE: we're betting that it's exceedingly unlikely that the
        # configuration name (i.e. `k8-fastbuild`) is the same as the repository
        # name. As a check we'll also assert on the number of path segments.
        is_sibling_layout = bin_path.split("/")[1] == repository
        if is_sibling_layout:
            # Just to be extra sure...
            if len(bin_path.split("/")) != 4: fail(
                "does this bin path (in external repo) means sibling layout: ",
                bin_path,
            )
        return is_sibling_layout
    else:
        # When the rule is invoked from the main repo, `bin_dir` tells us
        # nothing.

        # Assume not-sibling for now?
        # TODO: this will break when:
        #   - the `dotnet_toolchain` invocation is the main repo
        #   - the `runtime`'s first file is *not* from the main repo
        #   - sibling layout is enabled
        #
        # TODO: if we define a target in this repo that we inspect the above
        # changes to:
        #   - **`rules_dotnet` is the main repo**
        #   - in the `dotnet_toolchain`'s invocation, `runtime`'s first file is
        #     not from the main repo
        #   - sibling layout is enabled
        #
        # This is much more palatable; `rules_dotnet` will not be the main repo
        # for any users of this ruleset.
        return False

# Avoid using non-normalized paths (workspace/../other_workspace/path)
def _to_manifest_path(ctx, file):
    # TODO: this is wrong for sibling layout?
    if file.short_path.startswith("../"):
        if _sibling_repository_layout_enabled(ctx):
            return file.short_path
        else:
            return "external/" + file.short_path[3:]
    else:
        return ctx.workspace_name + "/" + file.short_path

def _dotnet_toolchain_impl(ctx):
    if ctx.attr.runtime and ctx.attr.runtime_path:
        fail("Can only set one of runtime or runtime_path but both were set.")
    if not ctx.attr.runtime and not ctx.attr.runtime_path:
        fail("Must set one of runtime or runtime_path.")

    if ctx.attr.csharp_compiler and ctx.attr.csharp_compiler_path:
        fail("Can only set one of csharp_compiler or csharp_compiler_path but both were set.")
    if not ctx.attr.csharp_compiler and not ctx.attr.csharp_compiler_path:
        fail("Must set one of csharp_compiler or csharp_compiler_path.")

    if ctx.attr.fsharp_compiler and ctx.attr.fsharp_compiler_path:
        fail("Can only set one of fsharp_compiler or fsharp_compiler_path but both were set.")
    if not ctx.attr.fsharp_compiler and not ctx.attr.fsharp_compiler_path:
        fail("Must set one of fsharp_compiler or fsharp_compiler_path.")

    if ctx.attr.apphost and ctx.attr.apphost_path:
        fail("Can only set one of apphost or apphost_path but both were set.")
    if not ctx.attr.apphost and not ctx.attr.apphost_path:
        fail("Must set one of apphost or apphost_path.")

    runtime_files = []
    runtime_path = ctx.attr.runtime_path

    csharp_compiler_files = []
    csharp_compiler_path = ctx.attr.csharp_compiler_path

    fsharp_compiler_files = []
    fsharp_compiler_path = ctx.attr.fsharp_compiler_path

    apphost_files = []
    apphost_path = ctx.attr.apphost_path

    if ctx.attr.runtime:
        runtime_files = ctx.attr.runtime.files.to_list() + ctx.attr.runtime.default_runfiles.files.to_list()
        runtime_path = _to_manifest_path(ctx, runtime_files[0]) # TODO: try looking for a binary that matches the name?

    if ctx.attr.csharp_compiler:
        csharp_compiler_files = ctx.attr.csharp_compiler.files.to_list() + ctx.attr.csharp_compiler.default_runfiles.files.to_list()
        csharp_compiler_path = _to_manifest_path(ctx, csharp_compiler_files[0])

    if ctx.attr.fsharp_compiler:
        fsharp_compiler_files = ctx.attr.fsharp_compiler.files.to_list() + ctx.attr.fsharp_compiler.default_runfiles.files.to_list()
        fsharp_compiler_path = _to_manifest_path(ctx, fsharp_compiler_files[0])

    if ctx.attr.apphost:
        apphost_files = ctx.attr.apphost.files.to_list()
        apphost_path = _to_manifest_path(ctx, apphost_files[0])

    # Make the $(tool_BIN) variable available in places like genrules.
    # See https://docs.bazel.build/versions/main/be/make-variables.html#custom_variables
    template_variables = platform_common.TemplateVariableInfo({
        "DOTNET_BIN": runtime_path,
        "CSC_BIN": csharp_compiler_path,
        "FSC_BIN": fsharp_compiler_path,
        "DOTNET_SDK_VERSION": ctx.attr.sdk_version,
        "DOTNET_RUNTIME_VERSION": ctx.attr.runtime_version,
        "DOTNET_RUNTIME_TFM": ctx.attr.runtime_tfm,
    })

    default = DefaultInfo(
        files = depset(runtime_files + csharp_compiler_files + fsharp_compiler_files + apphost_files),
        runfiles = ctx.runfiles(files = runtime_files + csharp_compiler_files + fsharp_compiler_files + apphost_files),
    )

    dotnetinfo = DotnetInfo(
        runtime_path = runtime_path,
        runtime_files = runtime_files,
        csharp_compiler_path = csharp_compiler_path,
        csharp_compiler_files = csharp_compiler_files,
        fsharp_compiler_path = fsharp_compiler_path,
        fsharp_compiler_files = fsharp_compiler_files,
        apphost_path = apphost_path,
        apphost_files = apphost_files,
        sdk_version = ctx.attr.sdk_version,
        runtime_version = ctx.attr.runtime_version,
        runtime_tfm = ctx.attr.runtime_tfm,
        csharp_default_version = ctx.attr.csharp_default_version,
        csharp_treat_warnings_as_errors = ctx.attr._csharp_treat_warnings_as_errors,
        csharp_warnings_as_errors = ctx.attr._csharp_warnings_as_errors,
        csharp_warnings_not_as_errors = ctx.attr._csharp_warnings_not_as_errors,
        csharp_warning_level = ctx.attr._csharp_warning_level,
        fsharp_default_version = ctx.attr.fsharp_default_version,
        fsharp_treat_warnings_as_errors = ctx.attr._fsharp_treat_warnings_as_errors,
        fsharp_warnings_as_errors = ctx.attr._fsharp_warnings_as_errors,
        fsharp_warnings_not_as_errors = ctx.attr._fsharp_warnings_not_as_errors,
        fsharp_warning_level = ctx.attr._fsharp_warning_level,
    )

    # Export all the providers inside our ToolchainInfo
    # so the resolved_toolchain rule can grab and re-export them.
    toolchain_info = platform_common.ToolchainInfo(
        default = default,
        dotnetinfo = dotnetinfo,
        template_variables = template_variables,
        runtime = ctx.attr.runtime,
        csharp_compiler = ctx.attr.csharp_compiler,
        fsharp_compiler = ctx.attr.fsharp_compiler,
        apphost = ctx.file.apphost,
        host_model = ctx.attr.host_model,
        strict_deps = ctx.attr._strict_deps,
    )
    return [
        default,
        toolchain_info,
        template_variables,
    ]

dotnet_toolchain = rule(
    implementation = _dotnet_toolchain_impl,
    attrs = {
        "runtime": attr.label(
            doc = "The dotnet CLI",
            mandatory = False,
            executable = True,
            cfg = "exec",
        ),
        "runtime_path": attr.string(
            doc = "Path to the dotnet CLI. Do not set if `runtime` is set",
            mandatory = False,
        ),
        "csharp_compiler": attr.label(
            doc = "The C# compiler binary",
            mandatory = False,
            executable = True,
            cfg = "exec",
        ),
        "csharp_compiler_path": attr.string(
            doc = "Path to the C# compiler binary. Do not set if `csharp_compiler` is set",
            mandatory = False,
        ),
        "fsharp_compiler": attr.label(
            doc = "The F# compiler binary",
            mandatory = False,
            executable = True,
            cfg = "exec",
        ),
        "fsharp_compiler_path": attr.string(
            doc = "Path to the F# compiler binary. Do not set if `fsharp_compiler` is set",
            mandatory = False,
        ),
        "apphost": attr.label(
            doc = "The apphost binary",
            mandatory = False,
            allow_single_file = True,
        ),
        "apphost_path": attr.string(
            doc = "Path to the apphost binary. Do not set if `apphost` is set",
            mandatory = False,
        ),
        "host_model": attr.label(
            doc = "The System.NET.HostModel DLL",
            mandatory = False,
        ),
        "sdk_version": attr.string(
            doc = "The SDK version of the current dotnet SDK",
            mandatory = True,
        ),
        "runtime_version": attr.string(
            doc = "The runtime version of the current dotnet SDK",
            mandatory = True,
        ),
        "runtime_tfm": attr.string(
            doc = "The runtime target framework moniker of the current dotnet SDK",
            mandatory = True,
        ),
        "csharp_default_version": attr.string(
            doc = "The default C# version used by the current dotnet SDK",
            mandatory = True,
        ),
        "_csharp_treat_warnings_as_errors": attr.label(
            doc = "Treat all C# compiler warnings as errors. Note that this attribute can not be used in conjunction with csharp_warnings_as_errors.",
            default = "//dotnet/settings:csharp_treat_warnings_as_errors",
        ),
        "_csharp_warnings_as_errors": attr.label(
            doc = "List of C# compiler warning codes that should be considered as errors. Note that this attribute can not be used in conjunction with csharp_treat_warnings_as_errors.",
            default = "//dotnet/settings:csharp_warnings_as_errors",
        ),
        "_csharp_warnings_not_as_errors": attr.label(
            doc = "List of C# compiler warning codes that should not be considered as errors. Note that this attribute can only be used in conjunction with csharp_treat_warnings_as_errors.",
            default = "//dotnet/settings:csharp_warnings_not_as_errors",
        ),
        "_csharp_warning_level": attr.label(
            doc = "List of C# compiler warning codes that should not be displayed.",
            default = "//dotnet/settings:csharp_warning_level",
        ),
        "fsharp_default_version": attr.string(
            doc = "The default F# version used by the current dotnet SDK",
            mandatory = True,
        ),
        "_fsharp_treat_warnings_as_errors": attr.label(
            doc = "Treat all F# compiler warnings as errors. Note that this attribute can not be used in conjunction with fsharp_warnings_as_errors.",
            default = "//dotnet/settings:fsharp_treat_warnings_as_errors",
        ),
        "_fsharp_warnings_as_errors": attr.label(
            doc = "List of F# compiler warning codes that should be considered as errors. Note that this attribute can not be used in conjunction with fsharp_treat_warnings_as_errors.",
            default = "//dotnet/settings:fsharp_warnings_as_errors",
        ),
        "_fsharp_warnings_not_as_errors": attr.label(
            doc = "List of F# compiler warning codes that should not be considered as errors. Note that this attribute can only be used in conjunction with fsharp_treat_warnings_as_errors.",
            default = "//dotnet/settings:fsharp_warnings_not_as_errors",
        ),
        "_fsharp_warning_level": attr.label(
            doc = "List of F# compiler warning codes that should not be displayed.",
            default = "//dotnet/settings:fsharp_warning_level",
        ),
        "_strict_deps": attr.label(
            doc = "Whether to use strict deps or not",
            default = "//dotnet/settings:strict_deps",
        ),
    },
    doc = """Defines a dotnet compiler/runtime toolchain.

For usage see https://docs.bazel.build/versions/main/toolchains.html#defining-toolchains.
""",
)
