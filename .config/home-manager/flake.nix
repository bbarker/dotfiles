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
  };

  outputs = { nixpkgs, home-manager, unison-lang, ... }:
    let
      system = "SYSTEM_PLACEHOLDER";

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ unison-lang.overlay ];
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

    #   nativeBuildInputs = [ pkgs.pkg-config ];
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

        # Optionally use extraSpecialArgs
        # to pass through arguments to home.nix
      };
    };
}
