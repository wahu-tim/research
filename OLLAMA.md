# Ollama on Fedora (AMD GPU)

Companion to the [setup guide](README.md), [software guide](SOFTWARE.md) and [extras](EXTRAS.md). GPU details come from web research (Ollama's 2024 AMD announcement, Fedora forum threads, Phoronix, Red Hat docs). Ollama's AMD support changes quickly, and **none of this was verified on Fedora 45**. Check Ollama's current GPU docs (`docs/gpu` in the `ollama/ollama` repo) before relying on it.

## 1. Check your GPU first

Ollama's official AMD path is ROCm, with a limited supported-card list. Cards outside it often fall back to CPU.

```bash
lspci | grep -i vga
sudo dnf install -y rocminfo
rocminfo | grep -i gfx      # your card's gfx target, e.g. gfx1100
```

- The 2024 announcement listed RX 7900 XTX/XT/GRE, 7800 XT, 7700 XT, 7600 XT/7600, 6950 XT, 6900 XT, 6800 XT/6800 and Vega 64/56. Newer cards may have been added since. Check the current docs for yours.
- Your user needs access to the GPU devices: `sudo usermod -aG render,video $USER`, then log out and back in.

### Your hardware

Gigabyte Radeon RX 7800 XT Gaming OC (16 GB GDDR6), Ryzen 9 7950X3D, G.Skill Trident Z5 RGB 96 GB (2 x 48 GB) DDR5-6400 CL32.

- **Support:** the RX 7800 XT was on Ollama's official ROCm list in the 2024 announcement, so it should work without overrides. Its gfx target should be `gfx1101` (confirm with `rocminfo`). Don't set `HSA_OVERRIDE_GFX_VERSION` unless detection fails.
- **VRAM:** 16 GB. Plan for 7B-14B quantized models fully on the GPU, with some headroom for context. Larger models spill to system RAM and slow down.
- **System RAM: 96 GB.** Ollama can split a model between GPU and system RAM, so you can run models far larger than 16 GB of VRAM. The catch is speed, which is limited by RAM bandwidth.
  - **Fits fully in VRAM (fast):** 7B-14B quantized, and possibly some ~20B models.
  - **Partial offload (usable):** ~30B dense models run, at a few tokens per second.
  - **70B-class dense models** fit in 96 GB at 4-bit but will be slow, since most layers run on CPU.
  - **Mixture-of-experts (MoE) models** are the sweet spot. Only a fraction of the weights is active per token, so large MoE models run much faster than dense models of the same size. Examples to look for in the library: Qwen3 30B-A3B and gpt-oss. Check current names and sizes on ollama.com/library.
  - Keep the context length modest. A large context uses a lot of extra memory.
- **CPU: Ryzen 9 7950X3D** (16 cores / 32 threads). Strong for the CPU side of offloading. Notes:
  - **RAM speed is the real limit** for offloaded layers, so enable the EXPO/XMP profile in BIOS. Check with `sudo dmidecode -t memory | grep -i speed`.
  - **Your RAM is a matched 2 x 48 GB kit.** That's true dual channel. DDR5-6400 gives about 102 GB/s theoretical, so the rated bandwidth is good for offloading. In practice Ryzen 7000 often can't run 6400 with the memory controller at the full 1:1 ratio, so it may run at 6000 or drop to a slower controller mode. Confirm what it actually runs at, and that EXPO is enabled, with `sudo dmidecode -t memory | grep -i "configured"`. These figures are estimates, not benchmarks. Measure with `ollama run <model> --verbose` (read `eval rate`, tokens/s) on a model larger than 16 GB, or `sysbench memory run`.
  - **Threads:** Ollama picks a thread count automatically. If CPU-offloaded speed looks poor, try setting `num_thread` to 16 (physical cores) in a Modelfile or request. I haven't verified this helps on this chip.
  - **Integrated GPU:** the 7950X3D has a small iGPU, so ROCm may see two GPUs. If Ollama picks the wrong one, pin the 7800 XT with `HIP_VISIBLE_DEVICES` (use the index shown by `rocminfo`). Add it in `sudo systemctl edit ollama` like the override in Troubleshooting.
  - **X3D scheduling:** only one of the two CCDs has the 3D V-Cache. Recent kernels include an AMD V-Cache preference setting (`amd_x3d_mode` in sysfs), which matters for games more than for LLM work. Leave the default unless you have a reason to change it.
- **Check:** after your first run, `ollama ps` should show the model on GPU. If it shows CPU, go to Troubleshooting.

## 2. Install (native)

```bash
curl -fsSL https://ollama.com/install.sh -o ollama-install.sh
less ollama-install.sh        # read it before running
sh ollama-install.sh
```

The installer sets up a systemd service. Check it:

```bash
systemctl status ollama
ollama --version
```

## 3. First model and GPU check

```bash
ollama pull llama3.2
ollama run llama3.2
ollama ps                     # PROCESSOR column must say GPU, not CPU
```

If `ollama ps` shows 100% CPU, see troubleshooting below.

## 4. Pick models for your VRAM

Rough guide (quantized models). Sizes are approximate, and context length adds memory use.

| VRAM | Sensible model size |
|---|---|
| 6-8 GB | 3B-8B parameters |
| 12-16 GB | 8B-14B |
| 24 GB | up to ~30B |

Useful categories: a general chat model, a code model, and a small fast model for autocomplete. Browse ollama.com/library for current names.

```bash
ollama list                   # installed models
ollama rm <model>             # free disk space
```

## 5. Use it from your tools

- **VS Code:** install the **Continue** extension and point it at `http://localhost:11434`.
- **Terminal:** `ollama run <model> "explain this" < file.txt`
- **API:** `curl http://localhost:11434/api/generate -d '{"model":"llama3.2","prompt":"hi"}'`
- **Web UI (optional):** Open WebUI in a container, pointed at the local API.

## 6. Security (this is a research machine)

- Ollama listens on **localhost only** by default. Keep it that way. If you set `OLLAMA_HOST=0.0.0.0` it is reachable from the network with no authentication.
- Don't expose port 11434 through firewalld unless you put authentication in front of it.
- Treat downloaded models as untrusted data from a third party. Pull from known publishers.
- Don't feed it samples, secrets or client data you wouldn't send to any outside service, unless you've checked that it stays local.

## 7. Alternative: run it in Podman

Keeps the host clean and fits the rootless-container setup in the main guide.

```bash
podman run -d --name ollama \
  --device /dev/kfd --device /dev/dri \
  --group-add keep-groups \
  -v ollama:/root/.ollama \
  -p 127.0.0.1:11434:11434 \
  docker.io/ollama/ollama:rocm
podman exec -it ollama ollama run llama3.2
```

SELinux is the usual sticking point:

1. Try `--security-opt label=type:container_runtime_t` first. A Fedora Silverblue user reported GPU access this way.
2. Only if that fails, use `--security-opt label=disable`. It works but turns off SELinux protection for that container.
3. Avoid `chmod 666` on `/dev/kfd` or `/dev/dri`. Fix group membership instead.

## 8. Troubleshooting

**`ollama ps` shows CPU**

```bash
journalctl -u ollama -b | tail -50        # native install
podman logs ollama                         # container
```

- Look for permission errors on `/dev/kfd`, ROCm/HIP errors, or a ~30 second discovery delay (reported with older ROCm 6.x-era kernel drivers).
- **Unsupported card:** a common workaround is setting `HSA_OVERRIDE_GFX_VERSION` to the nearest supported target (for example `10.3.0` for some RDNA2 cards). Add it with `sudo systemctl edit ollama`:
  ```ini
  [Service]
  Environment="HSA_OVERRIDE_GFX_VERSION=10.3.0"
  ```
  It is not guaranteed. One Fedora user with a 6700 XT reported it still ran on CPU.
- **Vulkan:** Ollama added experimental Vulkan support in late 2025 for AMD and Intel cards ROCm doesn't cover. Whether your installed version has it enabled, I couldn't confirm. Check the release notes. An older report said the official binary of that time had no Vulkan code path.
- **Last resort:** a llama.cpp-based runtime with a Vulkan backend, such as LM Studio.

## 9. Upgrades and cleanup

```bash
curl -fsSL https://ollama.com/install.sh | sh     # re-run to upgrade the native install
sudo systemctl disable --now ollama               # stop it when you don't need it
```

## Sources

- [Ollama: AMD preview announcement](https://ollama.com/blog/amd-preview)
- [Phoronix: Ollama experimental Vulkan support](https://www.phoronix.com/news/ollama-Experimental-Vulkan)
- [Fedora Discussion: LLMs in Fedora](https://discussion.fedoraproject.org/t/llms-in-fedora/124965)
- [Fedora Discussion: Ollama with ROCm on Silverblue](https://discussion.fedoraproject.org/t/fedora-silverblue-ollama-with-rocm-failed-to-check-permission-on-dev-kfd-open-dev-kfd-invalid-argument/131680/10)
- [OneUptime: Run AMD GPU containers with Podman](https://oneuptime.com/blog/post/2026-03-18-run-amd-gpu-containers-podman/markdown)
- [Red Hat: AMD ROCm with Podman](https://docs.redhat.com/ja/documentation/red_hat_ai_inference_server/3.2/html/getting_started/inference-rhaiis-with-podman-amd-rocm_getting-started)
