{
  pkgs,
  packages,
}:

let
  inherit (pkgs) lib;

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
      # Optional: use mold linker
      useMoldLinker ? true,
    }:
    let
      cargoNix = pkgs.callPackage ./crate2nix.nix {
        inherit
          src
          resolvedJson
          defaultCrateOverrides
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

      allTestMembers = [
        cargoNix.workspaceMembers.${workspaceMember}.buildTests
      ]
      ++ lib.mapAttrsToList (
        name: _packageId: cargoNix.workspaceMembers.${name}.buildTests
      ) workspaceDependencies;
    in
    pkg.overrideAttrs (
      finalAttrs: previousAttrs:
      let
        cargoVersion = lib.strings.removePrefix "rust_${workspaceMember}-" previousAttrs.name;
        version = if versionOverride == null then cargoVersion else versionOverride;
      in
      {
        inherit pname version;
        name = "${pname}-${version}";
        meta = (previousAttrs.meta or { }) // meta;

        nativeBuildInputs = (previousAttrs.nativeBuildInputs or [ ]) ++ allTestMembers;

        passthru = (previousAttrs.passthru or { }) // {
          updateSource = crate2nix-package-update-script.mkUpdateSource (
            attrs
            // {
              name = pname;
              version = finalAttrs.version;
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

        __intentionallyOverridingVersion = true;
      }
    );

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
