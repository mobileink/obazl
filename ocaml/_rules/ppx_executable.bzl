load("@bazel_skylib//lib:collections.bzl", "collections")

load("//ocaml/_providers:ocaml.bzl",
     "OcamlSDK",
     "OcamlArchiveProvider",
     "OcamlModuleProvider")
load("//ocaml/_providers:opam.bzl", "OpamPkgInfo")
load("//ocaml/_providers:ppx.bzl",
     "PpxExecutableProvider",
     "PpxModuleProvider")
# load("//ocaml/_actions:ppx.bzl",
#      # "apply_ppx",
#      "ocaml_ppx_compile",
#      # "ocaml_ppx_apply",
#      "ocaml_ppx_library_gendeps",
#      "ocaml_ppx_library_cmo",
#      "ocaml_ppx_library_compile",
#      "ocaml_ppx_library_link")
load("//ocaml/_utils:deps.bzl", "get_all_deps")
load("//implementation:utils.bzl",
     "get_opamroot",
     "get_sdkpath",
     "get_src_root",
     "file_to_lib_name",
     "strip_ml_extension",
     "OCAML_FILETYPES",
     "OCAML_IMPL_FILETYPES",
     "OCAML_INTF_FILETYPES",
     "WARNING_FLAGS"
)

#############################################
####  PPX_EXECUTABLE IMPLEMENTATION
def _ppx_executable_impl(ctx):

  debug = False
  # if (ctx.label.name == "ppx[ppx_sexp_conv][ppx_bin_prot][ppx_let][ppx_hash][ppx_compare][ppx_deriving.enum][ppx_assert][ppx_deriving.eq][ppx_snarky][ppx_fields_conv][ppx_inline_test][ppx_custom_printf]"):
  #     debug = True

  if debug:
      print("\n\n\tPPX_EXECUTABLE TARGET: %s\n\n" % ctx.label.name)

 #   dep_labels = [dep.label for dep in ctx.attr.deps]
#   if Label("@opam//pkg:ppxlib.runner") in dep_labels:
#     if not "-predicates" in ctx.attr.opts:
#       print("""\n\nWARNING: target '{target}' depends on
# '@opam//pkg:ppxlib.runner' but lacks -predicates option. PPX binaries that depend on this
# usually pass \"-predicates\", \"ppx_driver\" to opts. Without this option, the binary may
# compile but may not work as intended.\n\n""".format(target = ctx.label.name))
#   else:
#     print("""\n\nWARNING: ppx_executable target '{target}'
# does not have a driver dependency.  Such targets usually depend on '@opam//pkg:ppxlib.runner'
# or a similar PPX driver. Without a driver, the target may compile but not work as intended.\n\n""".format(target = ctx.label.name))

  # print("PPX BINARY: %s" % ctx.label.name)
  # for src in ctx.attr.srcs:
    # print("PPX BIN SRC: %s" % src)
    # print("PPX BIN SRC type: %s" % type(src))
    # if PpxModuleProvider in src:
      # print("PPX MODULE PROVIDER: %s" % src[PpxModuleProvider])

  mydeps = get_all_deps("ppx_executable", ctx)
  if debug:
      print("MYDEPS: %s" % mydeps)

  dep_graph = []

  tc = ctx.toolchains["@obazl_rules_ocaml//ocaml:toolchain"]
  env = {"OPAMROOT": get_opamroot(),
         "PATH": get_sdkpath(ctx)}

  outfilename = ctx.label.name
  outbinary = ctx.actions.declare_file(outfilename)

  ################################################################
  args = ctx.actions.args()
  args.add("ocamlopt")
  options = tc.opts + ctx.attr.opts
  if "-predicates" not in options:
      print("\n\n\tWARNING: did you forget a -predicates option for your ppx_executable (%s)?\n\n" % ctx.label.name)
  if "-linkall" not in options:
      print("\n\n\tWARNING: did you forget the -linkall option for your ppx_executable?\n\n")

  args.add_all(collections.uniq(options))

  args.add("-o", outbinary)

  build_deps = []
  includes = []

  dynamic_libs = []
  static_libs  = []
  link_search  = []
  # print("NOPAMS: %s" % mydeps.nopam)
  # we need to add the archive components to inputs, the archive is not enough
  # without these we get "implementation not found"
  for dep in mydeps.nopam.to_list():
    # if debug:
      # print("DEPGRAPH:  %s" % dep_graph)
    if debug:
        print("DEP:  %s" % dep)
    if dep.extension == "cmi":
      dep_graph.append(dep)
      includes.append(dep.dirname)
    elif dep.extension == "mli":
      dep_graph.append(dep)
      includes.append(dep.dirname)
    elif dep.extension == "cmx":
      dep_graph.append(dep)
      includes.append(dep.dirname)
      build_deps.append(dep)
    elif dep.extension == "o":
      dep_graph.append(dep)
      includes.append(dep.dirname)
    elif dep.extension == "cmxa":
      dep_graph.append(dep)
      includes.append(dep.dirname)
      # build_deps.append(dep)
    elif dep.extension == "a":
      dep_graph.append(dep)
      includes.append(dep.dirname)
      static_libs.append(dep)
    elif dep.extension == "so":
        dep_graph.append(dep)
        link_search.append("-L" + dep.dirname)
        libname = file_to_lib_name(dep)
        dynamic_libs.append("-l" + libname)
        # libname = dep.basename[:-3]
        # if libname.startswith("lib"):
        #     libname = libname.strip("l")
        #     libname = libname.strip("i")
        #     libname = libname.strip("b")
        #     dynamic_libs.append("-l" + libname)
        # else:
        #     fail("Found '.so' file without 'lib' prefix: %s" % dep)
    elif dep.extension == "dylib":
        dep_graph.append(dep)
        link_search.append("-L" + dep.dirname)
        libname = file_to_lib_name(dep)
        dynamic_libs.append("-l" + libname)

  # for dep in ctx.attr.build_deps:
  #   for g in dep[DefaultInfo].files.to_list():
  #     if g.path.endswith(".cmx"):
  #       build_deps.append(g)
  #       includes.append(g.dirname)
  #     if g.path.endswith(".cmxa"):
  #       build_deps.append(g)
  #       includes.append(g.dirname)

  args.add_all(link_search, before_each="-ccopt", uniquify = True)
  args.add_all(dynamic_libs, before_each="-cclib", uniquify = True)

  args.add_all(includes, before_each="-I", uniquify = True)
  args.add_all(build_deps)


  opam_deps = mydeps.opam.to_list()
  ## indirect lazy deps
  opam_deps.extend(mydeps.opam_lazy.to_list())

  if len(opam_deps) > 0:
    # print("Linking OPAM deps for {target}".format(target=ctx.label.name))
    args.add("-linkpkg")
    for dep in opam_deps:
        # args.add("-package", dep)
        args.add("-package", dep.pkg.to_list()[0].name)
        # args.add_all([dep.to_list()[0].name for dep in opam_deps], before_each="-package")


  # WARNING: don't add build_deps to command line.  For namespaced
  # modules, they may contain both a .cmx and a .cmxa with the same
  # name, which define the same module, which will make the compiler
  # barf.
  # OTOH, if we do not list them, they will not be found when the ppx is used.

    # if not dep.ppx_driver:
    #   if dep.pkg.to_list()[0].name == "async":
    #     if async:
    #       args.add("-package", dep.pkg.to_list()[0].name)
    #   else:
    #       args.add("-package", dep.pkg.to_list()[0].name)
  # print("\n\nTarget: {target}\nOPAM deps: {deps}\n\n".format(target=ctx.label.name, deps=opam_deps))

  # opam_labels = [dep.to_list()[0].name for dep in opam_deps]
  # opam_labels = [dep.pkg.to_list()[0].name for dep in opam_deps]
  # if len(opam_deps) > 0:
  #   # print("Linking OPAM deps for {target}".format(target=ctx.label.name))
  #   args.add("-linkpkg")
  #   for dep in opam_deps:
  #     # print("OPAM DEP: %s" % dep.pkg.to_list()[0].name)
  #     # if (dep.pkg.to_list()[0].name != "ppx_deriving.api"):
  #     #   if (dep.pkg.to_list()[0].name != "ppx_deriving.eq"):
  #     args.add("-package", dep.pkg.to_list()[0].name)
  #     args.add_all([dep.to_list()[0].name for dep in opam_deps], before_each="-package")
  # print("OPAM LABELS: %s" % opam_labels)

  # args.add("-absname")

  # non-ocamlfind-enabled deps:
 # for dep in build_deps:
  #   print("BUILD DEP: %s" % dep)

  if debug:
      print("DEP_GRAPH:")
      print(dep_graph)

  ## direct lazy deps
  opam_lazy_deps = []
  nopam_lazy_deps = []
  # this covers direct lazy deps; what about indirects?
  # e.g. suppose a direct lazy dep depends on a module that has its own lazy deps.
  # e.g. a non-lazy dep has lazy deps - ppx_executable depends on ppx_modules with lazy deps
  for dep in ctx.attr.lazy_deps:
    if debug:
        print("DEP LAZY_DEP: %s" % dep)
        # ed = ctx.attr.deps[key]
        # if OpamPkgInfo in ed:
        #     if debug:
        #         print("is OPAM")
        #     output_dep = ed[OpamPkgInfo].pkg.to_list()[0]
        #     lazy_deps.append(output_dep)
        # # else:
        # #     lazy_deps.append(ctx.attr.deps[key].name)
    if OpamPkgInfo in dep:
        if debug:
            print("is OPAM: %s" % dep)
        provider = dep[OpamPkgInfo]
        opam_lazy_deps.append(provider)
    else:
        nopam_lazy_deps.append(dep)

  ## this is handled by get_all_deps
  # nopam_lazy_deps.extend(mydeps.nopam_lazy.to_list())


  ## FIXME: put deps of main into dep_graph, but also make sure main file itself comes last

  # driver shim source must come after lib deps!
  # for src in ctx.files.main:
  #     if src.extension == "cmx":
  #         args.add(src)
  #     elif src.extension == "ml":
  #         args.add(src)

  dep_graph.extend(build_deps)
  dep_graph.extend(ctx.files.main)

        ## opam deps are just strings, we feed them to ocamlfind, which finds the file.
        ## this means we cannot add them to the dep_graph.
        ## this makes sense, the exe we build does not depend on these,
        ## it's the subsequent transform that depends on them.
    # else:
    #     dep_graph.append(dep)
    #FIXME: also support non-opam transform deps

  # print("DEP_GRAPH: %s" % dep_graph)
  ctx.actions.run(
    env = env,
    executable = tc.ocamlfind,
    arguments = [args],
    inputs = dep_graph,
    outputs = [outbinary],
    tools = [tc.ocamlfind, tc.ocamlopt], # tc.opam,
    mnemonic = "OcamlPPXBinary",
    progress_message = "Compiling ppx_executable({}), {}".format(
      ctx.label.name, ctx.attr.message
      )
  )

  defaultInfo = None
  if len(ctx.attr.data) == 0:
        defaultInfo = DefaultInfo(
            executable=outbinary
        )
  else:
      print("DATA: %s" % ctx.files.data)
      defaultInfo = DefaultInfo(
          executable=outbinary,
          runfiles = ctx.runfiles(
              root_symlinks = {
                  # FIXME: foreach
                  ctx.files.data[0].short_path: ctx.files.data[0]
                  # "src/config.mlh": ctx.files.data[0]
              }
          )
      )

  # print("PPX_EXECUTABLE TRANSFORM: %s" % lazy_deps)

  results = [
      defaultInfo,
      PpxExecutableProvider(
          payload=outbinary,
          args = depset(direct = ctx.attr.args),
          deps = struct(
              opam = mydeps.opam,
              opam_lazy = mydeps.opam_lazy,
              # opam_lazy = depset(direct = opam_lazy_deps),
                nopam = mydeps.nopam,
              nopam_lazy = mydeps.nopam_lazy
              # nopam_lazy = depset(direct = nopam_lazy_deps)
            )
      )
  ]

  if debug:
      print("PPX_EXECUTABLE RESULTS:")
      print(results)

  return results
# (library
#  (name deriving_hello)
#  (libraries base ppxlib)
#  (preprocess (pps ppxlib.metaquot))
#  (kind ppx_deriver))

#############################################
########## DECL:  PPX_EXECUTABLE  ################
ppx_executable = rule(
  implementation = _ppx_executable_impl,
  # implementation = _ppx_executable_compile_test,
  attrs = dict(
    _sdkpath = attr.label(
      default = Label("@ocaml//:path")
    ),
    # IMPLICIT: args = string list = runtime args, passed whenever the binary is used
    main = attr.label(
        mandatory = True,
        # allow_single_file = [".ml", ".cmx"],
        providers = [PpxModuleProvider], #  [OcamlModuleProvider]], #, [OpamPkgInfo]],
        default = None
    ),
    ppx  = attr.label(
      doc = "PPX binary (executable).",
      providers = [PpxExecutableProvider],
      mandatory = False,
    ),
    runtime_args = attr.string_list(
        doc = "List of args that must be passed to the ppx_executable at runtime. E.g. -inline-test-lib."
    ),
    data  = attr.label_list(
        doc = "Runtime data dependencies. E.g. a file used by %%import from ppx_optcomp.",
        allow_files = True,
    ),
    opts = attr.string_list(),
    warnings = attr.string_list(),
    linkopts = attr.string_list(),
    linkall = attr.bool(default = True),
    deps = attr.label_list(
      doc = "Deps needed to build this ppx executable.",
      providers = [[DefaultInfo], [PpxModuleProvider]]
    ),
    lazy_deps = attr.label_list(
      doc = """(Lazy) eXtension Dependencies.""",
      # providers = [[DefaultInfo], [PpxModuleProvider]]
    ),
    cc_deps = attr.label_keyed_string_dict(
      doc = "C/C++ library dependencies",
      providers = [[CcInfo]]
    ),
    mode = attr.string(default = "native"),
    message = attr.string()
  ),
  provides = [DefaultInfo, PpxExecutableProvider],
  executable = True,
  toolchains = ["@obazl_rules_ocaml//ocaml:toolchain"],
)
