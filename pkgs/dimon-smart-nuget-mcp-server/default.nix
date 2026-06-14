{
  buildDotnetModule,
  fetchFromGitHub,
  dotnetCorePackages,
}:

buildDotnetModule (finalAttrs: {
  pname = "NugetMcpServer";
  version = "1.1.4";

  src = fetchFromGitHub {
    owner = "DimonSmart";
    repo = "NugetMcpServer";
    tag = "v${finalAttrs.version}";
    hash = "sha256-wpVUznAZrr+7w6LAVDX9yKSuNPkhAPMYCrpbwkgPoXk=";
  };

  dotnet-sdk = dotnetCorePackages.sdk_9_0;
  dotnet-runtime = dotnetCorePackages.runtime_9_0;
  projectFile = [ "NugetMcpServer/NugetMcpServer.csproj" ];
  testProjectFile = [ "NugetMcpServer.Tests/NugetMcpServer.Tests.csproj" ];
  nugetDeps = ./deps.json;
})
