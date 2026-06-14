{
  lib,
  buildDotnetGlobalTool,
  dotnetCorePackages,
  nix-update-script,
}:

buildDotnetGlobalTool {
  pname = "glider";
  version = "6.14.0";

  nugetHash = "sha256-a5AG4JBu5JUCdgviVYM/Ue534QqDgwhit6TobyH8wQM=";

  dotnet-sdk = dotnetCorePackages.dotnet_10.sdk;
  dotnet-runtime = dotnetCorePackages.dotnet_10.runtime;

  passthru = {
    updateScript = nix-update-script {
      extraArgs = [
      ];
    };
  };

  meta = {
    homepage = "https://glidermcp.com/";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
    mainProgram = "glider";
  };
}
