{
  description = "Home Manager configuration of bbarker";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-NIX_VERSION_PLACEHOLDER";
    home-manager = {
      # url = "github:nix-community/home-manager";
      url = "github:nix-community/home-manager/release-NIX_VERSION_PLACEHOLDER";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code.url = "github:sadjow/claude-code-nix";
    unison-lang = {
      url = "github:ceedubs/unison-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixGL for GPU support on non-NixOS systems (Pop!_OS, Ubuntu, etc.)
    # nixGL overrides nvidia_x11 with `kernel = null`, which nixpkgs 26.05
    # refuses, so it keeps the last release it builds with; a wrapper that
    # loads the host's driver needs nothing from our pin.
    nixpkgs-nixgl.url = "github:nixos/nixpkgs/nixos-25.05";
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs-nixgl";
    };
  };

  outputs = { nixpkgs, home-manager, claude-code,  unison-lang, nixgl, nixpkgs-nixgl, ... }:
    let
      system = "SYSTEM_PLACEHOLDER";
      isLinux = builtins.match ".*linux.*" system != null;
      isImpure = builtins.hasAttr "currentTime" builtins;

      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          claude-code.overlays.default
          # Its tree-sitter override passes `extraGrammars`, which nixpkgs 26.05
          # removed; only unison-ucm is used from it.
          (final: prev: builtins.removeAttrs (unison-lang.overlay final prev) [ "tree-sitter" ])
          (final: prev: {
            unison-ucm = prev.unison-ucm.overrideAttrs (old: rec {
              version = "1.5.0";
              src = let
                platform = {
                  aarch64-darwin = { sys = "macos-arm64"; hash = "sha256-Ph1ql4I1qPmJpYTjMuZw7KGMFfEJn88YgfwSa2K9vq4="; };
                  x86_64-darwin = { sys = "macos-x64"; hash = "sha256-T55TdDTY4WFeBGtCJ8jCenei5t2fFJeK9jhSN//Bi5I="; };
                  x86_64-linux = { sys = "linux-x64"; hash = "sha256-/LLtYoTh9puhDE6Kgo3WVxDwnPHujLh25zKqnvVmz/Q="; };
                  aarch64-linux = { sys = "linux-arm64"; hash = "sha256-pL4UQdBAu6vbQB24KUz3aRqT+QIhmSvY59W46frb/04="; };
                }.${final.stdenv.hostPlatform.system};
              in final.fetchurl {
                url = "https://github.com/unisonweb/unison/releases/download/release/${version}/ucm-${platform.sys}.tar.gz";
                inherit (platform) hash;
              };
            });
          })
        ] ++ (if (isLinux && isImpure) then [
          (final: prev: {
            nixgl = import "${nixgl}/default.nix" {
              pkgs = import nixpkgs-nixgl { inherit system; config.allowUnfree = true; };
              enable32bits = system == "x86_64-linux";
              enableIntelX86Extensions = system == "x86_64-linux";
            };
          })
        ] else []);
        config.allowUnfree = true;
      };
    # ai-sh = pkgs.rustPlatform.buildRustPackage rec {
    #   pname = "ai-sh";
    #   version = "0.1.3";

    #   src = pkgs.fetchFromGitHub {
    #     owner = "abhayvishwakarma";
    #     repo = "ai-shell";
    #     rev = "v${version}";
    #     sha256 = "sha256-3ZdNwXNFqgFMSrGRqQOXXcNNmwmKzRJFjHwRGVnXyZY=";
    #   };

    #   cargoSha256 = "sha256-nnOUKUJZgTXQKlNMmMnXxZKkANLRXwzVWKzKZPwxsxc=";

    nativeBuildInputs = [ pkgs.pkg-config ];
    #   buildInputs = [ pkgs.openssl ];

    #   # If there are any features you want to enable, add them here
    #   # cargoFeatures = [ "some-feature" ];

    #   meta = with pkgs.lib; {
    #     description = "A CLI tool to generate shell commands using AI";
    #     homepage = "https://github.com/abhayvishwakarma/ai-shell";
    #     license = licenses.mit;
    #   };
    # };

    in {
      homeConfigurations."bbarker" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;

        # Specify your home configuration modules here, for example,
        # the path to your home.nix.
        modules = [ ./home.nix ];

        # nixGL is available via pkgs overlay when on Linux+impure
        # extraSpecialArgs = { };
      };
    };
}
