# Hermes Agent on Debian + KDE Plasma — Master Setup Plan

## Hardware: Ryzen 5 3600 / 32 GB DDR4-3600 / GTX 2070 Super 8 GB VRAM

## Goals: local Hermes agent, persistent under dedicated user, Tailscale-private, longevity-first

> Status at plan start: Debian + KDE Plasma installed, Tailscale installed and joined
> (tailnet IP 100.100.179.16), Hermes install script available. **CUDA drivers NOT yet installed.**
> All commands assume you are logged in as `amti` unless noted.

---

## Phase 0 — RESULTS (recorded 2026-11-21, user `amti@deb`)

| Check | Result | Verdict |
|---|---|---|
| Debian release | 13 (trixie) | Plan adjusted: repo path = `debian13`, NOT bookworm |
| GPU | TU104 GeForce RTX 2070 SUPER (10de:1e84) + HD Audio + USB-C | Detected, Turing (open modules OK) |
| Display driver in use | **nouveau** (owns GPU: fb0, DRM initialized) | Must be blacklisted in Phase 1.2 |
| Secure Boot | **disabled** (platform in Setup Mode) | Phase 1.5 MOK step SKIPPED |
| Disk | 196 GB free on / | OK for 21.5 GB model |
| RAM/Swap | 31 GiB RAM (26 available), 11 GiB swap | OK |
| Tailscale | 100.100.179.16 | Healthy |

**Phase 0 verdict: PASS.** Proceed to Phase 1 (trixie-adjusted, nouveau eviction included below).

---

## Phase 0 — Pre-flight audit (30 min, zero risk)

```bash
# 0.1 Confirm Debian release and GPU detection
lsb_release -a
lspci -nn | grep -i nvidia          # must list TU104 [GeForce RTX 2070 Super]
sudo dmesg | grep -i nouveau      # nouveau must NOT own the GPU after Phase 1

# 0.2 Check Secure Boot state (decides whether MOK enrollment is needed later)
sudo mokutil --sb-state           # "SecureBoot enabled" => Phase 1.5 required

# 0.3 Disk + memory headroom (model download is ~21.5 GB)
df -h /home /var /tmp
free -h

# 0.4 Confirm Tailscale still healthy
tailscale ip -4                   # expect 100.100.179.16
tailscale status
```

**Go/No-Go:** GPU listed, ≥25 GB free disk, ≥28 GB free RAM before model load. If SecureBoot is
enabled, do not skip Phase 1.5.

---

## Phase 1 — NVIDIA driver + CUDA toolkit (the current blocker)

Strategy: use **NVIDIA's own CUDA repo** for driver *and* toolkit so versions stay matched.
Do **not** mix with Debian's `nvidia-cuda-toolkit` package (version conflicts — this is a known
failure mode when the two repos overlap). **Your system is Debian 13 (trixie): the repo path is
`debian13`, and the weak-key problem some early-2026 trixie installs hit is avoided by
verifying the keyring's SHA256 (step 1.2).**

```bash
# 1.1 Build prerequisites
sudo apt update
sudo apt install -y build-essential dkms linux-headers-$(uname -r) git curl wget

# 1.2 Add NVIDIA CUDA repository — TRIXIE path, with SHA256 verification of the keyring
wget https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb
echo "d0d4ef986a44400f9db33c600ef33a985175e7cc63d805a10e1839c7a1e78f5f  cuda-keyring_1.1-1_all.deb" | sha256sum --check
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update

# 1.3 EVICT NOUVEAU FIRST (it currently owns your GPU — see Phase 0 results).
#     Skipping this is the #1 cause of "nvidia-smi: No devices found" on Debian.
echo -e "blacklist nouveau
options nouveau modeset=0" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
sudo update-initramfs -u

# 1.4 Install open kernel modules (Turing+) + CUDA toolkit.
#     Alternative for maximum desktop-display stability: replace 'nvidia-open' with 'cuda-drivers'
sudo apt install -y nvidia-open cuda-toolkit

# 1.5 Pin the driver branch so routine 'apt upgrade' never jumps branches under you (longevity)
sudo tee /etc/apt/preferences.d/nvidia-pin <<'EOF'
Package: *nvidia* *cuda* libcuda* libnv*
Pin: release o=NVIDIA
Pin-Priority: 1001
EOF
sudo apt update
```

### 1.6 Reboot and verify (Secure Boot is DISABLED on this machine — no MOK needed)
```bash
sudo reboot
# after login:
nvidia-smi                        # must show RTX 2070 Super, driver version, ~8174 MiB total
nvcc --version                    # CUDA version from /usr/local/cuda/bin
lsmod | grep nouveau              # MUST print nothing
lsmod | grep nvidia               # must show nvidia, nvidia_modeset, nvidia_uvm, nvidia_drm
sudo systemctl enable --now nvidia-persistenced   # faster init, keeps GPU state
```
**Go/No-Go:** `nvidia-smi` shows the card. If it says "No devices found": check
`dkms status`, confirm step 1.3 ran and initramfs was updated, and `journalctl -b | grep -i nvidia`.
(Secure Boot is disabled on this box, so module signing is not the failure mode here.)

---

## Phase 2 — Build llama.cpp with CUDA (1–2 h, mostly unattended)

> Correction vs. earlier draft: llama.cpp **dropped the plain Makefile in 2024**. Use CMake.
> The repo also moved to `ggml-org/llama.cpp` (old `ggerganov` URL redirects).

```bash
# 2.1 Clone and build with CUDA
git clone https://github.com/ggml-org/llama.cpp.git ~/llama.cpp
cd ~/llama.cpp
cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j 6

# 2.2 Install system-wide
sudo cp build/bin/llama-server /usr/local/bin/llama-server
sudo chown root:root /usr/local/bin/llama-server
sudo chmod 755 /usr/local/bin/llama-server
llama-server --version

# 2.3 GPU smoke test — server must see CUDA device(s)
llama-server --list-devices 2>/dev/null || llama-server -h | head -5
```

**Go/No-Go:** build log shows `ggml_cuda` compiled, binary runs.

---

## Phase 3 — Dedicated unprivileged user + persistence scaffolding

```bash
# 3.1 Create the user (no sudo membership, locked password — no login/SSH possible)
sudo useradd -m -s /bin/bash -U hermes-agent
sudo usermod -L hermes-agent
id hermes-agent                   # verify: NOT in sudo group

# 3.2 Let user services survive logout/reboot
sudo loginctl enable-linger hermes-agent

# 3.3 Scaffold dirs (as hermes-agent)
sudo -iu hermes-agent bash -c 'mkdir -p ~/.config/systemd/user ~/.hermes/hf-cache'
```

---

## Phase 4 — Install & harden Hermes under hermes-agent

```bash
sudo -iu hermes-agent
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.bashrc

# 4.1 Mandatory safeguards (from the comparison docs — do not skip)
hermes config set approval_mode interactive
hermes config set approval_required_tools "shell,filesystem,memory"
hermes config set memory.write_approval true
hermes config set command_confirmation destructive

hermes doctor                     # must pass
exit                              # back to amti
```

---

## Phase 5 — Model placement (as hermes-agent)

```bash
sudo -iu hermes-agent
# Pre-download so the systemd unit starts instantly later (needs ~21.5 GB):
huggingface-cli download unsloth/Qwen3.6-35B-A3B-GGUF Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \
  --local-dir ~/.hermes/models
exit
```

> If that repo/file name has changed by the time you run this, pick any **tool-capable MoE
> (30B+ class, 4-bit quant ≤ ~22 GB)** and substitute the names everywhere below.
> Disk check: `df -h /home` must show ≥25 GB free.

---

## Phase 6 — Persistent systemd user services (the longevity core)

### 6.1 llama-server (GPU model backend, port 8080, loopback only)

```bash
sudo -iu hermes-agent
cat > ~/.config/systemd/user/llama-server.service <<'EOF'
[Unit]
Description=llama-server local model backend (Hermes)
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/.hermes
ExecStart=/usr/local/bin/llama-server \
  --model %h/.hermes/models/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \
  -ngl 99 -ot "\.ffn_.*_exps\.=CPU" \
  -c 32768 -fa on -ctk q8_0 -ctv q8_0 \
  --no-mmproj --threads 6 \
  --host 127.0.0.1 --port 8080
Restart=always
RestartSec=5
# --- resource guardrails: a runaway model kills ONLY this service, never KDE ---
CPUQuota=800%            # 8 of 12 threads; desktop stays responsive
MemoryHigh=22G           # soft throttle
MemoryMax=25G            # hard cgroup OOM kill at 25 GB (32 GB machine)
Environment="HF_HOME=%h/.hermes/hf-cache"
Environment="LD_LIBRARY_PATH=/usr/local/cuda/lib64"

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now llama-server.service
journalctl --user -u llama-server.service -f    # watch startup; Ctrl-C when "HTTP server listening"
```

**VRAM target:** attention + shared layers + KV cache ≈ 4.5–5.5 GB on the 2070 Super,
leaving ≥2 GB for KDE/KWin. If `nvidia-smi` shows >7 GB: lower `-c` to 16384 or increase
offload (`-ot` patterns) — never let it touch 8 GB.

### 6.2 Point Hermes at the local backend

```bash
sudo -iu hermes-agent
hermes config set provider openai
hermes config set base_url http://127.0.0.1:8080/v1
hermes config set api_key local-no-key
hermes config set model Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
```

### 6.3 Hermes gateway (agent UI/API, port 8642, loopback only)

```bash
sudo -iu hermes-agent
cat > ~/.config/systemd/user/hermes-gateway.service <<'EOF'
[Unit]
Description=Hermes agent gateway
After=llama-server.service
Requires=llama-server.service

[Service]
Type=simple
WorkingDirectory=%h/.hermes
ExecStart=%h/.local/bin/hermes gateway --host 127.0.0.1 --port 8642
Restart=always
RestartSec=5
CPUQuota=200%
MemoryMax=2G

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now hermes-gateway.service
```

> Verify the actual gateway binary path/flags with `hermes gateway --help` once and adjust
> `ExecStart` accordingly. Set dashboard credentials via Hermes env/config before exposure.

---

## Phase 7 — Tailscale exposure (private tailnet only — NEVER Funnel)

```bash
# 7.1 Expose the Hermes gateway to tailnet devices only, with Tailscale-terminated TLS
sudo tailscale serve --bg 8642
tailscale serve status            # expect https://<machine>.<tailnet>.ts.net -> 127.0.0.1:8642

# 7.2 Firewall belt-and-braces (if ufw is in use)
sudo ufw default deny incoming
sudo ufw allow in on tailscale0
```

**Verification from a second tailnet device:**

```bash
curl https://<machine>.<tailnet>.ts.net/v1/models     # or open in browser; must prompt for auth
```

Note the layered port design: **8080 (model) never exposed** — only 8642 (Hermes, authenticated)
reaches the tailnet, and only via Tailscale Serve's HTTPS.

---

## Phase 8 — Ongoing monitoring & maintenance (longevity loop)

```bash
# Weekly health (2 min)
systemctl --user status llama-server.service hermes-gateway.service
systemd-cgtop -b -n 1 | head -20            # confirm cgroup caps hold
nvidia-smi                                   # VRAM headroom check
hermes doctor

# Backup before any upgrade (config, memory, skills, sessions)
sudo -iu hermes-agent bash -c 'tar czf ~/hermes-backup-$(date +%F).tar.gz -C ~ .hermes'

# Upgrade discipline
sudo apt update && sudo apt upgrade          # pinned nvidia branch stays stable
sudo -iu hermes-agent bash -c 'hermes config check && hermes config migrate'
```

Consider enabling **zram** (`sudo apt install zram-tools`) so transient RAM pressure degrades
gracefully instead of invoking the global OOM killer.

---

## Phase 9 — Pre-launch shortcomings & risk review (read before first real task)

| # | Risk / shortcoming | Mitigation in place | Residual risk |
| --- | --- | --- | --- |
| 1 | Local model hallucinates destructive shell flags/paths (docs: weaker models are *more* dangerous than cloud) | interactive approvals + `approval_required_tools shell,filesystem,memory` | You must actually READ approval prompts; never enable YOLO mode |
| 2 | 21.5 GB model + 32 GB RAM + KDE | `MemoryMax=25G` cgroup, zram, `nvidia-smi` watch | Swap thrash if you run heavy desktop apps alongside |
| 3 | 8 GB VRAM overcommit crashes the *driver* (not just the process) | MoE expert offload to RAM, `-ctk/-ctv q8_0`, `--no-mmproj`, keep ≤6 GB used | Driver hiccup still possible; `Restart=always` + reboot recovers |
| 4 | Tool-calling reliability of local models (docs: models may claim "memory saved" without doing it) | Test explicitly: ask agent to write a memory, then `cat ~/.hermes/memories/MEMORY.md` | If flaky, switch Hermes provider to a cloud API — Hermes features stay identical |
| 5 | Slow multi-step agent loops on CPU-offloaded MoE (~2–5 tok/s docs estimate) | GPU keeps attention+shared experts; CPU=6 threads on 3600 | Patience, or cloud provider for heavy tasks |
| 6 | Agent compromise over tailnet | Serve (not Funnel), ufw tailscale0-only, gateway auth, locked hermes-agent password | Tailscale ACLs: restrict which devices can reach the machine |
| 7 | Secrets exposure | Never put keys in shell history; use `~/.hermes/.env` 0600 | — |
| 8 | Driver upgrade breaks everything | nvidia pin file; backup before `apt upgrade` if nervous | — |
| 9 | hermes-agent still has *user-level* write access to anything hermes-agent owns | AppArmor (`sudo aa-genprof /usr/local/bin/llama-server`) if you want belt-and-suspenders | Profile maintenance burden |
| 10 | Port confusion 8080 vs 8642 | Documented above; 8080 never leaves loopback | — |

## Final Go/No-Go launch checklist

- [ ] `nvidia-smi` shows 2070 Super; `nvcc --version` OK
- [ ] `systemctl --user status llama-server hermes-gateway` = active (running), enabled
- [ ] `curl http://127.0.0.1:8080/v1/models` returns the model
- [ ] Test prompt via Hermes completes; approval prompt fires on a shell request
- [ ] Memory write test verified on disk (risk #4)
- [ ] `tailscale serve status` shows HTTPS route; second device reaches it with auth
- [ ] `systemd-cgtop` shows service within CPUQuota/MemoryMax
- [ ] Backup tarball of ~/.hermes created