{
  pkgs,
  fetchFromGitHub,
  useVariableFont ? true,
}:

let
  src = fetchFromGitHub {
    owner = "tonsky";
    repo = "FiraCode";
    rev = "727682c24c33fb0bbc7ab0ed9b7a8d0d9745a198";
    sha256 = "sha256-2/64g+J9l3XVcYJ2yRsrY5jnQzU+OT6Madl97mCzTuk=";
  };

in
if useVariableFont then
  pkgs.callPackage ./vf.nix { src = src; }
else
  pkgs.callPackage ./ttf.nix { src = src; }
