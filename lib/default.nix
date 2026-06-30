{
  pkgs,
  packages,
  crate2nixTools,
}:

let
  inherit (pkgs) lib;

in
{
  inherit (crate2nixTools) generatedCargoNix;
  nuget-global-tool-update-script = { }: [ (lib.getExe packages.update-nuget-global-tool) ];
}
