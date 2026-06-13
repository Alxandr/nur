{
  lib,
  pkgs,
  fetchFromGitHub,
  useVariableFont ? true,
  nix-update-script,
}:

let
  src = fetchFromGitHub {
    owner = "tonsky";
    repo = "FiraCode";
    rev = "d0cf393af83155564bd9a288151381a155449d09";
    sha256 = "sha256-nPboEYH1N8k3BSbEW6aGsK2kAElwWOI4oX/jPCV6g6c=";
  };

  updateScript = nix-update-script {
    extraArgs = [
      "--version"
      "branch"
      "--override-filename"
      "pkgs/fira-code/default.nix"
    ];
  };

  meta = {
    description = "Monospaced font with programming ligatures";
    homepage = "https://github.com/tonsky/FiraCode";
    license = lib.licenses.ofl;
  };

in
if useVariableFont then
  pkgs.callPackage ./vf.nix {
    inherit meta src updateScript;
  }
else
  pkgs.callPackage ./ttf.nix {
    inherit meta src updateScript;
  }
