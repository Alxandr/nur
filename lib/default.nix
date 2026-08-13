{
  pkgs,
  packages,
}:

let
  inherit (pkgs) lib;
  crate2nixTestHook =
    pkgs.makeSetupHook
      {
        name = "crate2nix-test-hook";
      }
      (
        pkgs.writeText "crate2nix-test-hook.sh" ''
          crate2nixTestHook() {
            echo "Executing crate2nixTestHook"
            runHook preCheck

            local flagsArray=()
            local status=0
            concatTo flagsArray checkFlags checkFlagsArray

            export CRATE2NIX_TEST_SOURCE_ROOT="$PWD"

            for testCrate in $testCrates; do
              if ! "$testCrate/bin/test" "''${flagsArray[@]}"; then
                status=1
              fi
            done

            unset CRATE2NIX_TEST_SOURCE_ROOT
            runHook postCheck
            return "$status"
          }

          if [[ -z "''${dontCrate2nixTest-}" && -z "''${checkPhase-}" ]]; then
            checkPhase=crate2nixTestHook
          fi
        ''
      );

in
rec {
  crate2nix =
    attrs@{
      # Package name
      pname,
      # Cargo workspace member name (defaults to the package name)
      workspaceMember ? pname,
      # Optional package version override (defaults to the Cargo version)
      versionOverride ? null,
      # Package meta
      meta,
      # Workspace source root (must match the workspace that generated the JSON)
      src,
      # Path to the pre-resolved JSON file
      resolvedJson,
      # Optional: function to create buildRustCrate for a given pkgs
      buildRustCrateForPkgs ? pkgs: pkgs.buildRustCrate,
      # Optional: default crate overrides
      defaultCrateOverrides ? pkgs.defaultCrateOverrides,
      # Optional: extra arguments to pass to the update script
      updateScriptExtraArgs ? [ ],
      # Optional: tools added to PATH when running test harnesses
      testInputs ? [ ],
      # Optional: environment variables set when running test harnesses
      testEnvironment ? { },
      # Optional: arguments passed to every test harness
      checkFlags ? [ ],
      # Optional: workspace crates whose tests should not be built or run
      disabledTestCrates ? [ ],
      # Optional: use mold linker
      useMoldLinker ? true,
    }:
    let
      cargoNix = pkgs.callPackage ./crate2nix.nix {
        inherit
          src
          resolvedJson
          defaultCrateOverrides
          testInputs
          testEnvironment
          ;
        buildRustCrateForPkgs =
          cratePkgs:
          let
            buildRustCrate = buildRustCrateForPkgs cratePkgs;
          in
          if useMoldLinker then
            buildRustCrate.override {
              stdenv = cratePkgs.stdenvAdapters.useMoldLinker cratePkgs.stdenv;
            }
          else
            buildRustCrate;
      };
      resolved = cargoNix.resolved;
      dependencyPackageIdsFor =
        {
          rootPackageId,
          includeDevDependencies ? false,
        }:
        let
          closure = builtins.genericClosure {
            startSet = [
              { key = rootPackageId; }
            ];

            operator =
              node:
              let
                crateInfo = resolved.crates.${node.key};
                dependencies =
                  (crateInfo.dependencies or [ ])
                  ++ (crateInfo.buildDependencies or [ ])
                  ++ lib.optionals (includeDevDependencies && node.key == rootPackageId) (
                    crateInfo.devDependencies or [ ]
                  );
              in
              map (dependency: { key = dependency.packageId; }) dependencies;
          };
        in
        map (node: node.key) (builtins.filter (node: node.key != rootPackageId) closure);
      workspaceDependenciesFor =
        rootPackageId:
        let
          dependencyPackageIds = dependencyPackageIdsFor { inherit rootPackageId; };
        in
        lib.filterAttrs (
          _workspaceName: packageId: builtins.elem packageId dependencyPackageIds
        ) resolved.workspaceMembers;
      workspaceDependencies = workspaceDependenciesFor resolved.workspaceMembers.${workspaceMember};
      pkg = cargoNix.workspaceMembers.${workspaceMember}.buildBins;

      allTestMembers =
        lib.optionals (!builtins.elem workspaceMember disabledTestCrates) [
          cargoNix.workspaceMembers.${workspaceMember}.buildTests
        ]
        ++ lib.mapAttrsToList (name: _packageId: cargoNix.workspaceMembers.${name}.buildTests) (
          lib.filterAttrs (name: _packageId: !builtins.elem name disabledTestCrates) workspaceDependencies
        );
      cargoVersion = lib.strings.removePrefix "rust_${workspaceMember}-" pkg.name;
      version = if versionOverride == null then cargoVersion else versionOverride;
    in
    # Run the prebuilt test harnesses without rebuilding the canonical binary.
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname version src;
      meta = (pkg.meta or { }) // meta;
      nativeBuildInputs = [ crate2nixTestHook ];

      dontConfigure = true;
      dontBuild = true;
      doCheck = true;
      inherit checkFlags;

      postPatch = ''
        patchShebangs .
      '';

      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        ${lib.getExe pkgs.lndir} -silent ${pkg} "$out"
        runHook postInstall
      '';

      testCrates = allTestMembers;

      passthru = (pkg.passthru or { }) // {
        updateSource = crate2nix-package-update-script.mkUpdateSource (
          attrs
          // {
            name = pname;
            inherit version;
          }
        );

        updateScript = crate2nix-package-update-script {
          extraArgs = [
            "--output"
            (toString resolvedJson)
          ]
          ++ updateScriptExtraArgs;
        };
      };
    };

  crate2nix-package-update-script = {
    __functor =
      self:
      {
        extraArgs ? [ ],
      }:
      [ (lib.getExe packages.update-crate2nix-package) ] ++ extraArgs;

    mkUpdateSource =
      attrs@{
        name,
        src,
        version,
        ...
      }:
      pkgs.stdenvNoCC.mkDerivation {
        pname = "${name}-src";
        inherit version src;

        dontUnpack = true;
        installPhase = "mkdir -p $out";
      }
      // attrs;
  };

  nuget-global-tool-update-script = {
    __functor =
      self:
      {
        extraArgs ? [ ],
      }:
      [ (lib.getExe packages.update-nuget-global-tool) ] ++ extraArgs;
  };
}
