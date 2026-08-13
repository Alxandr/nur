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
      version ? null,
      # Package meta
      meta,
      # Workspace source root (must match the workspace that generated the JSON)
      src,
      # Path to the pre-resolved JSON file
      resolvedJson,
      # Path where the updater writes regenerated JSON (defaults to the build input)
      updateResolvedJson ? resolvedJson,
      # Optional: function to create buildRustCrate for a given pkgs
      buildRustCrateForPkgs ? pkgs: pkgs.buildRustCrate,
      # Optional: default crate overrides
      defaultCrateOverrides ? pkgs.defaultCrateOverrides,
      # Optional: extra arguments to pass to the update script
      updateScriptExtraArgs ? [ ],
    }:
    let
      cargoNix = pkgs.callPackage ./crate2nix.nix {
        inherit
          src
          resolvedJson
          buildRustCrateForPkgs
          defaultCrateOverrides
          ;
      };
      pkg = cargoNix.workspaceMembers.${workspaceMember}.build;
    in
    pkg.overrideAttrs (
      finalAttrs: previousAttrs:
      let
        cargoVersion = lib.strings.removePrefix "rust_${workspaceMember}-" previousAttrs.name;
        packageVersion = if version == null then cargoVersion else version;
      in
      {
        inherit pname;
        version = packageVersion;
        name = "${pname}-${packageVersion}";
        meta = (previousAttrs.meta or { }) // meta;

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
              (toString updateResolvedJson)
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
