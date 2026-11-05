{ pkgs, inputs, ... }:

let
  # older way: nixpkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
  nixpkgs23 = import inputs.nixpkgs23 { system = pkgs.stdenv.hostPlatform.system; config.allowUnfree = true; };
in
{
  environment.systemPackages = with pkgs; [
    nixpkgs23.texliveFull
    nixpkgs23.fontconfig
  ];
}

