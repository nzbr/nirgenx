{
  description = "Kubernetes deployments in NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs =
    inputs @ { self
    , flake-utils
    , nixpkgs
    , ...
    }:
      with builtins; with nixpkgs.lib;
      let
        findModules =
          dir:
          flatten (
            mapAttrsToList
              (
                name: type:
                let
                  nodeName = (dir + "/${name}");
                in
                if type == "directory"
                then findModules nodeName
                else
                  if hasSuffix ".nix" nodeName
                  then nodeName
                  else [ ]
              )
              (readDir dir)
          );
        flakeLib = foldl recursiveUpdate { } (map (file: import file { inherit lib; }) (findModules ./lib));
        lib = recursiveUpdate nixpkgs.lib flakeLib;
      in
      {
        lib = flakeLib;
        nixosModules.nirgenx = { ... }: {
          imports =
            map
              (x: { config, pkgs, ... }: (import x { inherit config lib pkgs; })) # Import the modules; overwrite the lib that is passed to the module with our combined one
              (findModules ./module);
        };
      } // (
        flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = nixpkgs.legacyPackages."${system}";
        in
        {
          devShell = pkgs.mkShell {
            builtInputs = with pkgs; [
              nixpkgs-fmt
            ];
          };

          packages = {
            helm-update = pkgs.replaceVarsWith {
              name = "helm-update";
              src = ./script/helm-update.py;
              dir = "bin";
              isExecutable = true;
              replacements = {
                inherit (pkgs) nix;
                python3 = pkgs.python3.withPackages (p: [ p.pyyaml ]);
              };
            };
            yaml2nix = pkgs.replaceVarsWith {
              name = "yaml2nix";
              src = ./script/yaml2nix.sh;
              dir = "bin";
              isExecutable = true;
              replacements = {
                inherit (pkgs) bash nix remarshal;
                nixfmt = pkgs.nixfmt-rfc-style;
              };
            };
          };

          apps = {
            helm-update = flake-utils.lib.mkApp {
              name = "helm-update";
              drv = self.packages.${system}.helm-update;
            };
            yaml2nix = flake-utils.lib.mkApp {
              name = "yaml2nix";
              drv = self.packages.${system}.yaml2nix;
            };
          };
        })
      );
}
