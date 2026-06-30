{
  pkgs,
  nurLib,
  nixVersions,
  fetchFromGitHub,
  nix-update-script,
}:

let
  src = fetchFromGitHub {
    owner = "oxalica";
    repo = "nil";
    rev = "01e573c9e31ba3be7eaa848ba7dfcbd04260163e";
    hash = "sha256-ImGN436GYd50HjoKTeRK+kWYIU/7PkDv15UmoUCPDUk=";
  };

  customBuildRustCrateForPkgs =
    pkgs:
    pkgs.buildRustCrate.override {
      defaultCrateOverrides = pkgs.defaultCrateOverrides // {
        builtin = prev: {
          nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [
            (nixVersions.latest or nixVersions.unstable)
          ];
        };
      };
    };

  generated = nurLib.generatedCargoNix {
    name = "nil";
    src = src;
  };

  cargoNix = pkgs.callPackage "${generated}/default.nix" {
    buildRustCrateForPkgs = customBuildRustCrateForPkgs;
  };

in
cargoNix.workspaceMembers.nil.build.overrideAttrs {
  passthru = {
    updateSource = generated.overrideAttrs {
      version = "0.0.0"; # nix-update requires a version - given that we use git commits, the value does not really matter
    };

    updateScript = nix-update-script {
      attrPath = "nil.updateSource";
      extraArgs = [
        "--version"
        "branch"
        "--override-filename"
        "pkgs/nil/default.nix"
        "--src-only"
      ];
    };
  };
}
