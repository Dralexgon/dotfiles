{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    (python312.withPackages (ps: with ps; [
      jupyterlab
      numpy
      matplotlib
      scikitimage
      scikit-learn
      ipywidgets
    ]))
  ];
}
