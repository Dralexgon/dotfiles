{ pkgs, inputs, ... }:

let
  # nixpkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
  pkgs-stable = import inputs.nixpkgs-stable { system = pkgs.system; config.allowUnfree = true; };
in
{
  environment.systemPackages = with pkgs-stable; [
    # (jetbrains.plugins.addPlugins jetbrains.clion ["github-copilot"])
    # (jetbrains.plugins.addPlugins jetbrains.idea-ultimate ["github-copilot"])
    # (jetbrains.plugins.addPlugins jetbrains.pycharm-professional ["github-copilot"])
    (jetbrains.plugins.addPlugins jetbrains.pycharm-community ["github-copilot"])
    (jetbrains.plugins.addPlugins jetbrains.rider ["github-copilot"])
    # (jetbrains.plugins.addPlugins jetbrains.webstorm ["github-copilot"])
    # (jetbrains.plugins.addPlugins jetbrains.goland ["github-copilot"])
    # (jetbrains.plugins.addPlugins jetbrains.rust-rover ["github-copilot"])
  ];
}