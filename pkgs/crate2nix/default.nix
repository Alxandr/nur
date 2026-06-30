{
  pkgs,
  nurLib,
  nixVersions,
  fetchFromGitHub,
  crate2nix-package-update-script,
}:

let
  src = fetchFromGitHub {
    owner = "nix-community";
    repo = "crate2nix";
    rev = "5e1ecfd2d15b34ec90c2e51fdffbe8116595a767";
    hash = "sha256-2577vxyoBa8+ZRiXr3CuPtOuEtPRYsFPSZuEc/KI/80=";
  };

  crate2nix = import "${src}/default.nix" {
    inherit pkgs;
  };

in
crate2nix.overrideAttrs (finalAttrs: {
  passthru = (finalAttrs.passthru or { }) // {
    updateSource = crate2nix-package-update-script.mkUpdateSource {
      inherit src;
      name = "crate2nix";
      version = "0.0.0"; # nix-update requires a version - given that we use git commits, the value does not really matter
    };

    updateScript = crate2nix-package-update-script {
      extraArgs = [
        "--version"
        "branch"
      ];
    };
  };
})
