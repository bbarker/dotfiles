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
    unison-lang = {
      url = "github:ceedubs/unison-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixGL for GPU support on non-NixOS systems (Pop!_OS, Ubuntu, etc.)
    nixgl = {
      url = "github:nix-community/nixGL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, unison-lang, nixgl, ... }:
    let
      system = "SYSTEM_PLACEHOLDER";
      isLinux = builtins.match ".*linux.*" system != null;
      isImpure = builtins.hasAttr "currentTime" builtins;

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ unison-lang.overlay ]
          ++ (if (isLinux && isImpure) then [ nixgl.overlays.default ] else []);
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
