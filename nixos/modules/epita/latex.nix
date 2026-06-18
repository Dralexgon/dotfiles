{ pkgs, inputs, ... }:

let
  # older way: nixpkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
  pkgs-stable = import inputs.nixpkgs-stable { system = pkgs.system; config.allowUnfree = true; };
in
{
  environment.systemPackages = with pkgs; [
    pkgs-stable.texliveFull
    pkgs-stable.fontconfig
  ];
}

