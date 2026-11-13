{
  lib,
  nurLib,
  fetchFromGitHub,
  nix-update-script,
}:
nurLib.mkAgentPlugins (finalAttrs: {
  pname = finalAttrs.finalPackage.marketplace.name or "dotnet-skills";
  version = "unstable-2026-11-06";

  src = fetchFromGitHub {
    owner = "dotnet";
    repo = "skills";
    rev = "96c3d68dad2855e3ab5178aa1a262789d86a1466";
    sha256 = "sha256-Upje+I8r85kfwoB0/cxsrv6r+XgC+QZicUKx8BFuVNY=";
  };

  marketplace = ./marketplace.json;

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--version"
      "branch=main"
      "--version-regex"
      "^0-(.*)$"
    ];
  };

  meta = {
    description = ".NET Agent Skills";
    homepage = "https://github.com/dotnet/skills";
    license = lib.licenses.mit;
  };
})
