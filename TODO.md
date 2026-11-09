# TODO

## Local image generation (RTX 3060, 12 GB VRAM)

System RAM is only 14 GB, so prefer models that fit fully in VRAM (offloading to RAM is limited).

### Models to try
- [ ] **Z-Image-Turbo** (6B): best pick, 8 steps, INT8 build ~6.2 GB
- [ ] **FLUX.2 [klein] 4B**: 4 steps, Apache 2.0, ~8 GB with text encoder offloaded
- [ ] **Qwen-Image** (Q4 GGUF): best text rendering, ~13 GB, tight/slow
- [ ] **FLUX.1 Dev / Schnell** (city96 GGUF Q4–Q5): huge LoRA ecosystem, Dev is non-commercial
- [ ] **SDXL finetunes** (Illustrious / Pony): anime/characters, fastest on a 3060

### Install ComfyUI
```bash
cd ~/dev/ai && git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git comfyui && cd comfyui \
  && uv venv --python 3.12 .venv \
  && uv pip install --python .venv torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 \
  && uv pip install --python .venv -r requirements.txt \
  && git clone --depth 1 https://github.com/city96/ComfyUI-GGUF custom_nodes/ComfyUI-GGUF \
  && uv pip install --python .venv -r custom_nodes/ComfyUI-GGUF/requirements.txt
```

Run (open http://127.0.0.1:8188):
```bash
cd ~/dev/ai/comfyui && LD_LIBRARY_PATH=/run/opengl-driver/lib .venv/bin/python main.py
```

Optional later: package it declaratively (e.g. a `nix develop` shell or a NixOS module) instead of the uv venv.

### Sources
- https://willitrunai.com/image-models/best-for/12gb
- https://vdf.ai/blog/best-local-image-generation-models/
- https://www.earngenix.com/blog/best-local-image-generation-models-2026
- https://localaimaster.com/blog/best-local-image-models-compared
