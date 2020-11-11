load("@bazel_skylib//lib:collections.bzl", "collections")
# load("//implementation:common.bzl",
#     "OCAML_VERSION")

# 4.07.1 broken on XCode 12:
# https://discuss.ocaml.org/t/ocaml-4-07-1-fails-to-build-with-apple-xcode-12/6441/15
OCAML_VERSION = "4.08.0"
OCAMLBUILD_VERSION = "0.14.0"
OCAMLFIND_VERSION = "1.8.1"
COMPILER_NAME = "ocaml-base-compiler.%s" % OCAML_VERSION
OPAM_ROOT_DIR = ".opam_root_dir"
# Set to false to see debug messages
DEBUG_QUIET = False

# # The path to the root opam directory within external
# OPAMROOT = "OPAMROOT"

# print("private/ocaml.bzl loading")

def _has_pkg_impl(ctx):
    # search arg in list of enabled pkgs
    _ignore = ctx.build_setting_value
    return BuildSettingInfo(value = True)

has_pkg_flag = rule(
    implementation = _has_pkg_impl,
    build_setting = config.bool(flag = True)
)


################################################################
# Set up ppx stuff
def is_ppx_driver(repo_ctx, pkg):
    # 'ocamlfind printppx' prints the ppx preprocessor options as they would
    # occur in an OCaml compiler invocation for the packages listed in
    # the command. The output includes one "-ppx" option for each
    # preprocessor. The possible options have the same meaning as for
    # "ocamlfind ocamlc". The option "-predicates" adds assumed
    # predicates and "-ppxopt package,arg" adds "arg" to the ppx
    # invocation of package package.
    # This tells us which packages can serve as ppx exes (?)
    query_result = repo_ctx.execute(["ocamlfind", "printppx", pkg]).stdout.strip()
    # print("IS PPX DRIVER? {pkg} : {ppx}".format( pkg = pkg, ppx = len(query_result)))
    if len(query_result) == 0:
        return False
    else:
        return True

################################################################
def _opam_repo_nonhermetic(repo_ctx):
    # print("opam/bootstrap.bzl opam_configure()")
    repo_ctx.report_progress("Bootstrapping nonhermetic OPAM...")
    for i in range(10000000): x = i # pause

    # print("CURRENT SYSTEM: %s" % repo_ctx.os.name)
    env = repo_ctx.os.environ
    # for item in env.items():
    #     print("ENV ENTRY: %s" % str(item))

    # print("ROOT WS DIRECTORY: %s" % str(repo_ctx.path(Label("@//:WORKSPACE.bazel")))[:-16])

    #### opam pinning
    pin = False
    if pin:
        rootpath = str(repo_ctx.path(Label("@//:WORKSPACE.bazel")))[:-16]
        print("ROOT DIR: %s" % rootpath)
        ## FIXME: parameterize
        for pkg in ["src/external/ocaml-sodium",
                    "src/external/rpc_parallel",
                    "src/external/ocaml-extlib",
                    "src/external/async_kernel",
                    "src/external/coda_base58",
                    "src/external/graphql_ppx"
                    ]:
            pkg_path = rootpath + pkg
            repo_ctx.report_progress("OPAM pinning {pkg}...".format(pkg=pkg))
            pinout = repo_ctx.execute(["opam", "pin", "-y", "add", pkg_path])
            if pinout.return_code != 0:
                print("ERROR opam pin rc: %s" % pinout.return_code)
                print("ERROR stdout: %s" % pinout.stdout)
                print("ERROR stderr: %s" % pinout.stderr)

    opamroot = repo_ctx.execute(["opam", "var", "prefix"]).stdout.strip()
    # if verbose:
    #     print("opamroot: " + opamroot)

    packages = []

    ## we need to run both opam and ocamlfind list
    ## opam includes pinned local pkgs, ocamlfind does not
    ## ocamlfind includes subpackages like ppx_derivine.eq, opam does  not
    ## then we use collections.uniq to dedup.
    pkgs = repo_ctx.execute(["opam", "list"]).stdout.splitlines()
    for pkg in pkgs:
        if not pkg.startswith("#"):
            packages.append(pkg.split(" ")[0])
    pkgs = repo_ctx.execute(["ocamlfind", "list"]).stdout.splitlines()
    for pkg in pkgs:
        packages.append(pkg.split(" ")[0])

    opam_pkgs = []
    repo_ctx.report_progress("constructing OPAM pkg rules...")
    for p in collections.uniq(packages):
        ## WARNING: this is slow
        # print("PKG rule for %s" % p)
        ppx = is_ppx_driver(repo_ctx, p)
        opam_pkgs.append(
            "opam_pkg(name = \"{pkg}\", ppx_driver={ppx})".format( pkg = p, ppx = ppx )
        )
    # print("ocamlfind pkgs:")
    # for p in opam_pkgs:
    #   print(p)
    ocamlfind_pkgs = "\n".join(opam_pkgs)

    opambin = repo_ctx.which("opam") # "/usr/local/Cellar/opam/2.0.7/bin"
    # if "OPAM_SWITCH_PREFIX" in repo_ctx.os.environ:
    #     opampath = repo_ctx.os.environ["OPAM_SWITCH_PREFIX"] + "/bin"
    # else:
    #     fail("Env. var OPAM_SWITCH_PREFIX is unset; try running 'opam env'")
    repo_ctx.report_progress("OPAM: intalling BUILD.bazel files...")

    # repo_ctx.symlink(opambin, "opam") # the opam executable

    local_opam_root = "/Users/gar/.obazl/opam"
    # repo_ctx.symlink(local_opam_root, "opam")
    repo_ctx.symlink(local_opam_root + "/lib", "lib")

    repo_ctx.symlink(opamroot, "sdk")
    repo_ctx.symlink(opamroot + "/bin", "bin")

    repo_ctx.file("WORKSPACE", "", False)
    repo_ctx.template(
        "BUILD.bazel",
        Label("//ocaml/_bootstrap/opam/templates:BUILD.opam.tpl"),
        executable = False,
        # substitutions = { "{opam_pkgs}": ocamlfind_pkgs }
    )
    repo_ctx.template(
        "pkg/BUILD.bazel",
        Label("//ocaml/_bootstrap/opam/templates:BUILD.opampkg.tpl"),
        executable = False,
        substitutions = { # "{has_pkg_values}": has_pkgs,
                          "{opam_pkgs}": ocamlfind_pkgs }
    )
#     repo_ctx.file(
#         "sdk/lib/integers/BUILD.bazel",
#         content = """load("@obazl_rules_ocaml//ocaml:build.bzl", "ocaml_import")

#     # repo_ctx.template(
#     #     "ppx/BUILD.bazel",
#     #     Label("@obazl_rules_ocaml//opam:ppx/BUILD.tpl"),
#     #     executable = False,
#     # )
#     # repo_ctx.file(
#     #     "ppx/ppx_inline_test_lib_runtime_exit.ml",
#     #     content = "(* GENERATED FILE - DO NOT EDIT *)\nlet () = Ppx_inline_test_lib.Runtime.exit ();;",
#     #     executable = False,
#     # )

#     # repo_ctx.template(
#     #     "ppxlib/BUILD.bazel",
#     #     Label("@obazl_rules_ocaml//opam:ppxlib/BUILD.tpl"),
#     #     executable = False,
#     #     # substitutions = { "{opam_pkgs}": ocamlfind_pkgs }
#     #     # substitutions = {"{pkg}": "ppxlib.metaquot"}
#     # )
#     # repo_ctx.file(
#     #     "ppxlib/ppxlib_driver_standalone_runner.ml",
#     #     content = "(* GENERATED FILE - DO NOT EDIT *)\nlet () = Ppxlib.Driver.standalone ()",
#     #     executable = False,
#     # )

def _opam_repo_hermetic(repo_ctx):
    repo_ctx.report_progress("Bootstrapping hermetic OPAM...")
    for i in range(10000000): x = i # pause

    repo_ctx.report_progress("Initializing opam and its root directory: {}".format(OPAM_ROOT_DIR))
    for i in range(10000000): x = i # pause

    ## download opam binary
    os_name = repo_ctx.os.name.lower()
    if os_name.find("windows") != -1:
        fail("Windows is not supported yet, sorry!")
    elif os_name.startswith("mac os"):
        repo_ctx.download(
            url = "https://github.com/ocaml/opam/releases/download/2.0.0-beta4/opam-2.0.0-beta4-x86_64-darwin",
            output = "opam",
            sha256 = "d23c06f4f03de89e34b9d26ebb99229a725059abaf6242ae3b9e9bf946b445e1",
            executable = True,
        )
    else:
        repo_ctx.download(
            url = "https://github.com/ocaml/opam/releases/download/2.0.0-beta4/opam-2.0.0-beta4-x86_64-linux",
            output = "opam",
            sha256 = "3de4b78a263d4c1e46760c26bdc2b02fdbce980a9fc9141385058c2b0174708c",
            executable = True,
        )
    repo_ctx.file("WORKSPACE.bazel", "", False)
    repo_ctx.file("BUILD", "exports_files([\"opam\"])", False)

    opam_bin = "opam"
    repo_ctx.report_progress("Initializing opam and its root directory..")
    for i in range(10000000): x = i # pause
    repo_ctx.execute([
        opam_bin,
        "init",
        "-vv",
        "--root", OPAM_ROOT_DIR,
        "--no-setup",
        "--no-opamrc",
        "--compiler", COMPILER_NAME
    ], quiet = DEBUG_QUIET)

    repo_ctx.report_progress("Installing {}".format(COMPILER_NAME))
    for i in range(10000000): x = i # pause
    repo_ctx.execute([
        opam_bin,
        "switch", COMPILER_NAME,
        "--root", OPAM_ROOT_DIR
    ], quiet = DEBUG_QUIET)

    repo_ctx.report_progress("Installing ocamlfind {}".format(OCAMLFIND_VERSION))
    for i in range(10000000): x = i # pause
    repo_ctx.execute([
        opam_bin,
        "install",
        "ocamlfind=%s" % OCAMLFIND_VERSION,
        "--yes",
        "--root", OPAM_ROOT_DIR
    ], quiet = DEBUG_QUIET)

    repo_ctx.report_progress("Installing opam packages..")
    for i in range(10000000): x = i # pause
    [repo_ctx.execute([
        opam_bin,
        "install",
        "%s=%s" % (pkg, version),
        "--yes",
        "--root", OPAM_ROOT_DIR
    ], quiet = DEBUG_QUIET)
     for (pkg, version) in repo_ctx.attr.opam_pkgs.items()]

    # _opam_repo_nonhermetic(repo_ctx)

def _opam_repo_impl(repo_ctx):
    # repo_ctx.report_progress("Bootstrapping OPAM... hermetic? {}".format(repo_ctx.attr.hermetic))
    ## pause so we can see the progress msg:
    for i in range(10000000): x = i

    if repo_ctx.attr.hermetic:
        _opam_repo_hermetic(repo_ctx)
    else:
        _opam_repo_nonhermetic(repo_ctx)

# ocaml_import(
#     name = \"integers\",
#     cmxa = "integers.cmxa",
#     visibility = [\"//visibility:public\"],
# )
# """,
#         executable = False,
#     )

#     repo_ctx.file(
#         "sdk/lib/ocaml/BUILD.bazel",
#         content = """load("@rules_cc//cc:defs.bzl", "cc_library")

# cc_library(
#     name = \"csdk\",
#     hdrs = glob([\"caml/*.h\"]),
#     visibility = [\"//visibility:public\"],
# )
# """,
#         executable = False,
#     )

#     repo_ctx.file(
#         "sdk/lib/ctypes/BUILD.bazel",
#         content = """load("@rules_cc//cc:defs.bzl", "cc_library")
# load("@obazl_rules_ocaml//ocaml:build.bzl", "ocaml_import")

# cc_library(
#     name = \"cc\",
#     hdrs = glob([\"*.h\"]),
#     visibility = [\"//visibility:public\"],
# )

# ocaml_import(
#     name = \"ctypes\",
#     cmxa = \"ctypes.cmxa",
#     deps = ["@opam//sdk/lib/integers"],
#     visibility = [\"//visibility:public\"],
# )

# ocaml_import(
#     name = \"stubs\",
#     cmxa = \"cstubs.cmxa",
#     deps = [":ctypes"],
#     visibility = [\"//visibility:public\"],
# )
# """,
#         executable = False,
#     )


# def _opam_download_impl(repo_ctx):
#     # print("_opam_download_impl")
#     os_name = repo_ctx.os.name.lower()
#     if os_name.find("windows") != -1:
#         fail("Windows is not supported yet, sorry!")
#     elif os_name.startswith("mac os"):
#         repo_ctx.download(
#             "https://github.com/ocaml/opam/releases/download/2.0.0-beta4/opam-2.0.0-beta4-x86_64-darwin",
#             "opam",
#             "d23c06f4f03de89e34b9d26ebb99229a725059abaf6242ae3b9e9bf946b445e1",
#             executable = True,
#         )
#     else:
#         repo_ctx.download(
#             "https://github.com/ocaml/opam/releases/download/2.0.0-beta4/opam-2.0.0-beta4-x86_64-linux",
#             "opam",
#             "3de4b78a263d4c1e46760c26bdc2b02fdbce980a9fc9141385058c2b0174708c",
#             executable = True,
#         )
#     repo_ctx.file("WORKSPACE", "", False)
#     repo_ctx.file("BUILD.bazel", "exports_files([\"opam\"])", False)

_opam_repo = repository_rule(
    implementation = _opam_repo_impl,
    configure = True,
    local = True,
    attrs = dict(
        _root_workspace = attr.label(default = Label("@//:BUILD.bazel")),
        hermetic = attr.bool(
            default = True
        ),
        pkgs = attr.string_dict(
            doc = "List of OPAM packages to install."
        )
    )
)

################################################################
def _hidden_opam_repo_impl(repo_ctx):
    repo_ctx.report_progress("Bootstrapping hidden _opam repo...")
    for i in range(10000000): x = i # pause

    repo_ctx.file("WORKSPACE.bazel", "workspace = ( \"_opam\" )", False)

    opamroot = repo_ctx.execute(["opam", "var", "prefix"]).stdout.strip()
    # print("opamroot: " + opamroot)

    repo_ctx.symlink(opamroot + "/lib", "lib")

    repo_ctx.file(
        "BUILD.bazel",
        content = "exports_files(glob([\"lib/**/*\"]))",
        executable = False,
    )

_hidden_opam_repo = repository_rule(
    implementation = _hidden_opam_repo_impl,
    local = True,
    # attrs = dict(
    #     hermetic = attr.bool(
    #         default = True
    #     ),
    #     opam_pkgs = attr.string_dict(
    #         doc = "List of OPAM packages to install."
    #     )
    # )
)

# ################################################################
# def _opam_pkg_impl(ctx):
#   ## client should do:
#   ## dep[OpamPkgInfo].pkg.to_list()[0].name)
#   return [OpamPkgInfo(
#       pkg = depset(direct = [ctx.label]),
#       ppx_driver = ctx.attr.ppx_driver
#   )]

# opam_pkg = rule(
#     implementation = _opam_pkg_impl,
#     attrs = dict(
#         ppx_driver = attr.bool(
#             doc = "True if META contains ppx(-ppx_driver...) or ppxopt(-ppx_driver...), indicating that ocamlfind will generate a -ppx/--as-ppx arg if this lib is listed as a dependency.",
#             default = False
#         )
#     ),
#     provides = [OpamPkgInfo]
# )

def opam_configure(hermetic = False,
                   opam = None,
                   switch = "4.07.1",
                   pkgs = None):
    if hermetic:
        if not opam:
            fail("Hermetic builds require a list of OPAM deps.")

    _hidden_opam_repo(name="_opam")
    _opam_repo(name="opam", hermetic = hermetic, pkgs = opam.installed if opam else {})
    # native.local_repository(name = "zopam", path = "/Users/gar/.obazl/opam")

################################################################
BuildSettingInfo = provider(
    doc = "A singleton provider that contains the raw value of a build setting",
    fields = {
        "value": "The value of the build setting in the current configuration. " +
                 "This value may come from the command line or an upstream transition, " +
                 "or else it will be the build setting's default.",
    },
)
