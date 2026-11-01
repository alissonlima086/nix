{
  description = "Alisson NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    subtui = {
      url = "github:MattiaPun/SubTUI";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    antigravity-nix.url = "github:jacopone/antigravity-nix";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }:
  {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      specialArgs = {
        inherit inputs;
	pkgs-unstable = import inputs.nixpkgs-unstable {
	  system = "x86_64-linux";
	  config.allowUnfree = true;
	};
      };

      modules = [
        ./configuration.nix

        home-manager.nixosModules.home-manager

        {
          home-manager.users.alisson =
            import ./home/alisson;
        }
      ];
    };
  };
}
