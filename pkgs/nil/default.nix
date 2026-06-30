{
  pkgs,
  nurLib,
  nixVersions,
  fetchFromGitHub,
  crate2nix-package-update-script,
}:

let
  src = fetchFromGitHub {
    owner = "oxalica";
    repo = "nil";
    rev = "504599f7e555a249d6754698473124018b80d121";
    hash = "sha256-18j8X2Nbe0Wg1+7YrWRlYzmjZ5Wq0NCVwJHJlBIw/dc=";
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

  cargoNix = pkgs.callPackage ./Cargo.nix {
    buildRustCrateForPkgs = customBuildRustCrateForPkgs;
  };

in
cargoNix.workspaceMembers.nil.build.overrideAttrs (finalAttrs: {
  passthru = (finalAttrs.passthru or { }) // {
    updateSource = crate2nix-package-update-script.mkUpdateSource {
      inherit src;
      name = "nil";
      version = "2025-06-13-unstable-2025-12-10"; # nix-update requires a version - given that we use git commits, the value does not really matter
    };

    updateScript = crate2nix-package-update-script {
      extraArgs = [
        "--version"
        "branch"
      ];
    };
  };
})
