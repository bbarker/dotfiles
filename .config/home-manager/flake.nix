{
  description = "Home Manager configuration of bbarker";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    unison-lang = {
      url = "github:ceedubs/unison-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, unison-lang, ... }:
    let
      system = "x86_64-linux";
      # pkgs = nixpkgs.legacyPackages.${system};

      # Define an overlay that includes unison-lang packages
      unisonOverlay = final: prev: {
        # Here you might need to adapt depending on how unison-lang exposes its packages
        # This is a placeholder and might not directly work without adjustments
        # unison-lang = unison-lang.packages.${system}.unison-lang;
        unison-lang = unison-lang.packages.${system};
      };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ unisonOverlay ];
      };

      
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
