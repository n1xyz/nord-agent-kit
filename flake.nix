{
  description = "Nord MCP server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    bun2nix.url = "github:nix-community/bun2nix/2.1.2";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      bun2nix,
    }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ bun2nix.overlays.default ];
        };
    in
    {
      packages = eachSystem (
        system:
        let
          pkgs = pkgsFor system;
          manifest = builtins.fromJSON (builtins.readFile ./packages/mcp-server/package.json);
          keyringPlatform =
            {
              aarch64-darwin = "darwin-arm64";
              x86_64-darwin = "darwin-x64";
              aarch64-linux = "linux-arm64-gnu";
              x86_64-linux = "linux-x64-gnu";
            }
            .${system};
        in
        {
          default = self.packages.${system}.nord-mcp;
          inherit (pkgs) bun2nix;
          nord-mcp = pkgs.stdenv.mkDerivation {
            pname = "nord-mcp";
            inherit (manifest) version;
            src = pkgs.lib.fileset.toSource {
              root = ./packages/mcp-server;
              fileset = pkgs.lib.fileset.unions [
                ./packages/mcp-server/src
                ./packages/mcp-server/scripts
                ./packages/mcp-server/package.json
                ./packages/mcp-server/tsconfig.json
                ./packages/mcp-server/bun.lock
                ./packages/mcp-server/LICENSE
                ./packages/mcp-server/NOTICE
                ./packages/mcp-server/THIRD_PARTY_NOTICES.txt
                ./packages/mcp-server/licenses
              ];
            };

            nativeBuildInputs = [
              pkgs.bun2nix.hook
              pkgs.nodejs_22
              pkgs.makeWrapper
            ]
            ++ pkgs.lib.optional pkgs.stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook;
            buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.stdenv.cc.cc.lib
            ];

            bunDeps = pkgs.bun2nix.fetchBunDeps {
              bunNix = ./packages/mcp-server/bun.nix;
            };
            bunInstallFlags = [
              "--frozen-lockfile"
              "--linker=hoisted"
              "--backend=copyfile"
            ];
            dontUseBunPatch = true;
            dontRunLifecycleScripts = true;

            buildPhase = ''
              runHook preBuild
              node scripts/build.mjs
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/lib/nord-mcp/node_modules/@napi-rs" "$out/bin"
              cp -r dist package.json "$out/lib/nord-mcp/"
              cp -r node_modules/@napi-rs/keyring \
                node_modules/@napi-rs/keyring-${keyringPlatform} \
                "$out/lib/nord-mcp/node_modules/@napi-rs/"
              cp -r LICENSE NOTICE THIRD_PARTY_NOTICES.txt licenses "$out/lib/nord-mcp/"
              makeWrapper ${pkgs.nodejs_22}/bin/node "$out/bin/nord-mcp" \
                --add-flags "$out/lib/nord-mcp/dist/cli.js"
              runHook postInstall
            '';

            doInstallCheck = true;
            installCheckPhase = ''
              runHook preInstallCheck
              "$out/bin/nord-mcp" --help
              "$out/bin/nord-mcp" --version
              ${pkgs.nodejs_22}/bin/node -e 'require(process.argv[1])' \
                "$out/lib/nord-mcp/node_modules/@napi-rs/keyring"
              runHook postInstallCheck
            '';

            meta = {
              inherit (manifest) description homepage;
              license = pkgs.lib.licenses.asl20;
              mainProgram = "nord-mcp";
              platforms = systems;
            };
          };
        }
      );

      devShells = eachSystem (
        system:
        let
          pkgs = (pkgsFor system).extend (
            import ./nix/codex-overlay.nix {
              nord-mcp = self.packages.${system}.nord-mcp;
            }
          );
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.bun
              pkgs.nodejs_22
              pkgs.bun2nix
              pkgs.codex
              self.packages.${system}.nord-mcp
            ];
          };
        }
      );
    };
}
