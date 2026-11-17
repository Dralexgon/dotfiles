# Game dev brainstorm

## Direction (answers so far)

- **Scope:** a few-month side project, or something bigger
- **Tech:** undecided (maybe Unity)
- **What excites me:** all of it: the mechanics, the art and mood, the code
  (procgen, ECS, shaders), and finishing and shipping something

### Engine notes

- **Unity:** big ecosystem, C#, lots of tutorials. On NixOS `unityhub` is
  packaged but can be finicky (FHS env, editor downloads).
- **Godot:** free and open source, light, packaged cleanly in nixpkgs,
  GDScript or C#. Strong for 2D, decent 3D.
- **Bevy (Rust):** ECS-first, code-only, great if the code is the fun part;
  less tooling, younger ecosystem.

## Seed ideas

These build on the bat / "Predatoria" look the dotfiles already have.

1. **Echolocation game:** the screen is mostly black, and you only see the
   world when you "ping." Each ping reveals the area briefly but alerts
   enemies. It's cheap to build because the art is minimal and the tension
   comes from the core mechanic.
2. **Swarm control:** you steer a colony of bats with boids-style flocking.
   You split the swarm, merge it back and sacrifice members to get through
   hazards. Good for simulation and ECS code.
3. **Reverse tower defense:** you're the predator, a night creature raiding
   a village. You plan routes around torches, dawn timers and hunters.
4. **Desktop-native toy:** a tiny game that lives in the Hyprland/Wayland
   setup, like bats that hunt the cursor or a pet on a layer-shell overlay.
   It ties in with the bats-on-theme-switch animation.
5. **Terminal roguelite:** a TUI dungeon crawler that uses the theme colors,
   built with ratatui or bubbletea.

## Process ideas

- Start with a 10-second core loop and prototype only that. If it isn't fun
  with grey boxes, more art won't fix it.
- Join a game jam (Ludum Dare, GMTK, or itch.io jams) for a hard deadline.
- Keep a "fun log": after each session, write one line on what felt good
  and what didn't.
