{
  lib,
  coreutils,
  crate2nix,
  nix,
  nix-update,
  writeShellApplication,
}:

(writeShellApplication {
  name = "update-crate2nix-package";
  runtimeInputs = [
    coreutils
    crate2nix
    nix
    nix-update
  ];

  text = ''
    attr=''${UPDATE_NIX_ATTR_PATH:-}
    cargoToml="Cargo.toml"
    output=""
    overrideFilename=""
    crateHashes=""
    registryHashes=""
    nixUpdateVersion="branch"
    crate2nixArgs=()

    usage() {
      cat <<'EOF'
Usage: update-crate2nix-package [options] [-- <crate2nix args>...]

Options:
  --cargo-toml <path>
            Cargo.toml path relative to the updated source root. Defaults to
            "Cargo.toml".
  --output <path>
            Repository path to the committed crate2nix output. Defaults to
            "Cargo.nix" next to --override-filename when provided, otherwise
            next to the file defining updateSource.src.
  --override-filename <path>
            File where nix-update should rewrite the source version/hash.
            Optional; by default nix-update derives this from updateSource.
  --crate-hashes <path>
            Path to crate2nix crate hash cache file.
  --registry-hashes <path>
            Path to crate2nix registry hash cache file.
  --version <version>
            Version argument passed to nix-update. Defaults to "branch".
  -h, --help
            Show this help.

Arguments after "--" are passed through to "crate2nix generate".
EOF
    }

    while (( $# > 0 )); do
      case "$1" in
        --cargo-toml)
          if (( $# < 2 )); then
            echo "--cargo-toml requires a path" >&2
            usage >&2
            exit 2
          fi
          cargoToml="$2"
          shift
          ;;
        --output)
          if (( $# < 2 )); then
            echo "--output requires a path" >&2
            usage >&2
            exit 2
          fi
          output="$2"
          shift
          ;;
        --override-filename)
          if (( $# < 2 )); then
            echo "--override-filename requires a path" >&2
            usage >&2
            exit 2
          fi
          overrideFilename="$2"
          shift
          ;;
        --crate-hashes)
          if (( $# < 2 )); then
            echo "--crate-hashes requires a path" >&2
            usage >&2
            exit 2
          fi
          crateHashes="$2"
          shift
          ;;
        --registry-hashes)
          if (( $# < 2 )); then
            echo "--registry-hashes requires a path" >&2
            usage >&2
            exit 2
          fi
          registryHashes="$2"
          shift
          ;;
        --version)
          if (( $# < 2 )); then
            echo "--version requires a value" >&2
            usage >&2
            exit 2
          fi
          nixUpdateVersion="$2"
          shift
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        --)
          shift
          crate2nixArgs+=("$@")
          break
          ;;
        *)
          echo "Unknown argument: $1" >&2
          usage >&2
          exit 2
          ;;
      esac
      shift
    done

    if [[ -z "$attr" ]]; then
      echo "UPDATE_NIX_ATTR_PATH is required" >&2
      exit 2
    fi

    sourceAttr="$attr.updateSource"

    if [[ -z "$output" ]]; then
      if [[ -n "$overrideFilename" ]]; then
        output="$(dirname "$overrideFilename")/Cargo.nix"
      else
        sourceFile=$(
          nix --extra-experimental-features nix-command eval \
            --raw \
            --impure \
            --expr '
              let
                attr = builtins.getEnv "UPDATE_NIX_ATTR_PATH";
                pkgs = import <nixpkgs> { };
                repo = import ./. { inherit pkgs; };
                pkg = pkgs.lib.getAttrFromPath (pkgs.lib.splitString "." attr) repo;
                pos = builtins.unsafeGetAttrPos "src" pkg.updateSource;
              in
              if pos == null then
                throw ("Could not find source position for " + attr + ".updateSource.src")
              else
                pos.file
            '
        )

        case "$sourceFile" in
          "$PWD"/*)
            sourceFile=''${sourceFile#"$PWD"/}
            ;;
        esac

        case "$sourceFile" in
          /*)
            echo "$sourceAttr.src is defined outside the current repository: $sourceFile" >&2
            echo "Define updateSource.src in this package's Nix file, or pass --output explicitly." >&2
            exit 1
            ;;
        esac

        output="$(dirname "$sourceFile")/Cargo.nix"
      fi
    fi

    nixUpdateArgs=(
      "$sourceAttr"
      "--version" "$nixUpdateVersion"
      "--src-only"
    )

    if [[ -n "$overrideFilename" ]]; then
      nixUpdateArgs+=("--override-filename" "$overrideFilename")
    fi

    nix-update "''${nixUpdateArgs[@]}"

    src=$(
      nix-build . \
        -A "$sourceAttr.src" \
        --no-out-link
    )

    generateArgs=(
      generate
      --cargo-toml "$src/$cargoToml"
      --output "$output"
    )

    if [[ -n "$crateHashes" ]]; then
      generateArgs+=("--crate-hashes" "$crateHashes")
    fi

    if [[ -n "$registryHashes" ]]; then
      generateArgs+=("--registry-hashes" "$registryHashes")
    fi

    generateArgs+=("''${crate2nixArgs[@]}")

    crate2nix "''${generateArgs[@]}"
  '';

}).overrideAttrs
  (prev: {
    meta = (prev.meta or { }) // {
      description = "Script to update a crate2nix-based package's source and generated Nix expressions";
      homepage = "https://github.com/Alxandr/nur/tree/master/pkgs/update-crate2nix-package";
      license = lib.licenses.mit;
    };
  })
