# DeMoD LLC Voice Clone

Production-grade local voice cloning and text-to-speech system built with Nix. Privacy-first, reproducible, and hardware-accelerated.

## Features

- **Zero-shot voice cloning** via Coqui XTTS-v2 (6-10 second reference audio)
- **Fast Piper TTS inference** for production deployment
- **Dataset preprocessing** for fine-tuning custom voices
- **GPU acceleration** (CUDA, ROCm, Vulkan via tinygrad)
- **Reproducible builds** with Nix flakes
- **Container-ready** Docker images
- **MIT licensed** and fully open source

## Quick Start

### Nix Flakes (Recommended)

```bash
# Run directly from GitHub
nix run github:DeMoDLLC/voice-clone-flake -- --help

# Or install to profile
nix profile install github:DeMoDLLC/voice-clone-flake

# Clone locally
git clone https://github.com/DeMoDLLC/voice-clone-flake.git
cd voice-clone-flake
nix develop  # Enter development shell
```

### Docker (Multi-Architecture)

Pre-built images available for **x86_64 (AMD64)** and **ARM64** architectures with **CUDA**, **ROCm**, and **CPU-only** variants.

#### Quick Start (Auto-Detect Architecture)

```bash
# Pull the best image for your architecture
# - AMD64: Gets CUDA variant (NVIDIA GPU support)
# - ARM64: Gets CPU variant (Apple Silicon, AWS Graviton)
docker pull alh477/demod-voice:latest

# Or use GitHub Container Registry
docker pull ghcr.io/alh477/demod-voice:latest
```

#### GPU-Accelerated (NVIDIA CUDA)

```bash
# Pull CUDA variant
docker pull alh477/demod-voice:cuda

# Run with NVIDIA GPU
docker run --gpus all -v $(pwd):/workspace \
  alh477/demod-voice:cuda \
  xtts-zero-shot /workspace/reference.wav "Hello world" \
  --output /workspace/output.wav --gpu
```

#### GPU-Accelerated (AMD ROCm)

```bash
# Pull ROCm variant (AMD64 only)
docker pull alh477/demod-voice:rocm

# Run with AMD GPU
docker run --device /dev/kfd --device /dev/dri -v $(pwd):/workspace \
  alh477/demod-voice:rocm \
  xtts-zero-shot /workspace/reference.wav "Hello world" \
  --output /workspace/output.wav --gpu
```

#### CPU-Only (Smallest Image)

```bash
# Pull CPU variant (70% smaller!)
docker pull alh477/demod-voice:cpu

# Run without GPU
docker run -v $(pwd):/workspace \
  alh477/demod-voice:cpu \
  xtts-zero-shot /workspace/reference.wav "Hello world" \
  --output /workspace/output.wav
```

#### Available Image Tags

| Tag | Description | Size | Best For |
|-----|-------------|------|----------|
| `latest` | Auto-detects architecture | ~4GB AMD64<br>~1GB ARM64 | Most users |
| `cuda` | All CUDA variants | ~4GB | NVIDIA GPUs |
| `rocm` | All ROCm variants | ~3.5GB | AMD GPUs |
| `cpu` | All CPU variants | ~1.2GB | No GPU / Storage constrained |
| `latest-amd64` | CUDA on AMD64 | ~4GB | Intel/AMD + NVIDIA |
| `latest-arm64` | CPU on ARM64 | ~1GB | Apple Silicon, ARM servers |

**Specific Versions:**
- `1.0.0-cuda-amd64` - NVIDIA on Intel/AMD CPUs
- `1.0.0-cuda-arm64` - NVIDIA on ARM (Jetson)
- `1.0.0-rocm-amd64` - AMD on Intel/AMD CPUs
- `1.0.0-cpu-amd64` - No GPU on Intel/AMD
- `1.0.0-cpu-arm64` - No GPU on ARM (Apple Silicon, Graviton)

**Registries:**
- **DockerHub**: `alh477/demod-voice`
- **GitHub Container Registry**: `ghcr.io/alh477/demod-voice`

#### Which Image Should I Use?

**Decision Tree:**

1. **What CPU do you have?**
   - Intel or AMD → Use `-amd64` images
   - Apple Silicon (M1/M2/M3) → Use `-arm64` images
   - AWS/Azure ARM instances → Use `-arm64` images

2. **What GPU do you have?**
   - NVIDIA (RTX, Tesla, A100) → Use `cuda` tag
   - AMD (RX 6000/7000, MI series) → Use `rocm` tag
   - No GPU / Cloud VM → Use `cpu` tag
   - Not sure → Use `latest` (auto-detects best option)

3. **Storage constrained?**
   - Use `cpu` variant (70% smaller than CUDA)
   - Or use `latest` which is optimized per-architecture

**Examples:**

```bash
# Desktop with NVIDIA RTX
docker pull alh477/demod-voice:cuda

# MacBook Pro M3 (no GPU in Docker)
docker pull alh477/demod-voice:cpu

# AWS Graviton server
docker pull alh477/demod-voice:cpu

# Not sure - let Docker decide
docker pull alh477/demod-voice:latest  # Works on any platform
```

## Requirements

- **OS**: Linux (x86_64 or aarch64)
- **Nix**: 2.18+ with flakes enabled
- **GPU** (optional but recommended):
  - NVIDIA GPU with CUDA 11.8+
  - AMD GPU with ROCm 5.7+
  - 8GB+ VRAM for XTTS inference

## Usage

### Zero-Shot Voice Cloning

Clone any voice from a short reference sample:

```bash
demod-voice xtts-zero-shot \
  reference_audio.wav \
  "This is the text I want to synthesize in the cloned voice." \
  --output cloned_output.wav \
  --language en \
  --gpu
```

**Reference audio requirements:**
- Format: WAV, 22050 Hz mono (auto-converted if different)
- Duration: 6-10 seconds of clean speech
- Quality: No background noise, single speaker
- Content: Natural conversational speech works best

### Piper Inference

Fast synthesis with pre-trained or custom Piper models:

```bash
# Single-speaker model
demod-voice piper-infer \
  en_US-lessac-medium.onnx \
  "Fast and efficient text to speech." \
  --output piper_output.wav

# Multi-speaker model
demod-voice piper-infer \
  en_US-libritts-high.onnx \
  "Speaker-specific synthesis." \
  --output speaker_output.wav \
  --speaker 5
```

Download Piper models from: https://github.com/rhasspy/piper/releases

### Configuration

Create a config file at `~/.config/demod-voice/config.yaml` to set defaults:

```yaml
# Default language for XTTS synthesis
default_language: en

# GPU settings
gpu:
  enabled: true
  device_id: 0
  mixed_precision: true

# Output settings
output:
  sample_rate: 22050
  format: wav
```

Or use a custom config file:

```bash
demod-voice --config /path/to/config.yaml xtts-zero-shot reference.wav "Hello"
```

### Batch Processing

Process multiple voice cloning jobs from a CSV file:

```bash
# Create a batch file (columns: reference,text,output[,language,speaker])
cat > batch.csv << EOF
reference,text,output,language
/path/to/ref1.wav,"Hello world",/path/to/out1.wav,en
/path/to/ref2.wav,"Bonjour",/path/to/out2.wav,fr
EOF

# Process all jobs
demod-voice batch batch.csv

# Stop on first error
demod-voice batch batch.csv --fail-fast
```

### Health Check

Verify system health and dependencies:

```bash
# Human-readable output
demod-voice health

# JSON output for automation
demod-voice health --json
```

### Logging Options

Control output verbosity:

```bash
# Verbose logging (debug level)
demod-voice --verbose xtts-zero-shot reference.wav "Hello"

# Quiet mode (errors only)
demod-voice --quiet xtts-zero-shot reference.wav "Hello"

# Force CPU mode
demod-voice --cpu xtts-zero-shot reference.wav "Hello"
```

### Dataset Preprocessing

Prepare custom datasets for Piper fine-tuning:

```bash
# Your dataset structure:
# dataset/
#   wavs/
#     file001.wav
#     file002.wav
#   metadata.csv  (format: filename|text)

demod-voice piper-preprocess \
  --input-dir ./dataset \
  --output-dir ./training_data \
  --language en-us
```

After preprocessing, train with:

```bash
python -m piper_train \
  --dataset-dir ./training_data \
  --output-dir ./checkpoints \
  --quality high
```

## Development

```bash
# Enter development environment
nix develop

# CLI is available directly
demod-voice --help

# Run tests
python -m pytest tests/

# Format code
black bin/
ruff check bin/

# Build package
nix build .#demod-voice
```

## Architecture

```
demod-voice
├── XTTS-v2 backend (Coqui TTS)
│   └── Zero-shot cloning, multi-lingual
├── Piper backend (rhasspy/piper)
│   └── Fast ONNX inference
├── tinygrad support (experimental)
│   └── Alternative compute backend
└── Nix packaging
    ├── Reproducible Python environment
    ├── CUDA/ROCm acceleration
    └── Docker containerization
```

## Performance Notes

**XTTS-v2 (GPU recommended):**
- First inference: ~30-60s (model download + compilation)
- Subsequent: ~2-5s for 10-20 words
- VRAM: 6-8 GB typical

**Piper (CPU-friendly):**
- Inference: Real-time or faster on modern CPUs
- VRAM: None required
- Quality: Excellent for production use

## Troubleshooting

### CUDA not detected

```bash
# Check CUDA availability
python -c "import torch; print(torch.cuda.is_available())"

# Inside Nix shell, ensure LD_LIBRARY_PATH is set
echo $LD_LIBRARY_PATH
```

### Model download issues

XTTS models auto-download on first run. If downloads fail:

```bash
# Pre-download models
python -c "from TTS.api import TTS; TTS('tts_models/multilingual/multi-dataset/xtts_v2')"
```

### Out of memory

Reduce batch size or use CPU mode:

```bash
# Remove --gpu flag to use CPU (slower but uses less VRAM)
demod-voice xtts-zero-shot reference.wav "text" --output out.wav
```

## Roadmap

- [ ] Multi-speaker fine-tuning workflows
- [ ] Real-time streaming synthesis
- [ ] Voice conversion (speaker A to speaker B)
- [ ] Web API server mode
- [ ] Gradio/Streamlit UI
- [ ] Model quantization for edge deployment

## Contributing

Contributions welcome. Please:

1. Fork the repository
2. Create a feature branch
3. Test with `nix flake check`
4. Submit a pull request

For major changes, open an issue first to discuss.

## License

MIT License - see [LICENSE](LICENSE) file.

Copyright (c) 2026 DeMoD LLC

## Acknowledgments

Built on the shoulders of giants:

- [Coqui TTS](https://github.com/coqui-ai/TTS) - XTTS-v2 implementation
- [Piper](https://github.com/rhasspy/piper) - Fast neural TTS
- [tinygrad](https://github.com/tinygrad/tinygrad) - Lightweight ML framework
- [Nix](https://nixos.org) - Reproducible package management

## Support

- Issues: https://github.com/DeMoDLLC/voice-clone-flake/issues
- Discussions: https://github.com/DeMoDLLC/voice-clone-flake/discussions
- Email: support@demod.llc

---

**DeMoD LLC** - Digital Signal Processing and AI Infrastructure
