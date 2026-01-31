# DeMoD Voice Clone Architecture

This document describes the technical architecture and design decisions of the DeMoD Voice Clone system.

## System Overview

DeMoD Voice Clone is a production-grade voice cloning and TTS system built on Nix for reproducibility and dependency management. The system integrates multiple backends (XTTS-v2, Piper) with a unified CLI interface.

```
┌─────────────────────────────────────────┐
│         demod-voice CLI                 │
│  (Unified Python argparse interface)    │
└───────────┬─────────────────────────────┘
            │
    ┌───────┴────────┬─────────────┐
    │                │             │
┌───▼────┐      ┌───▼────┐   ┌───▼────────┐
│ XTTS-v2│      │ Piper  │   │ tinygrad   │
│(Coqui) │      │(rhasspy)│   │(experimental)│
└────────┘      └────────┘   └────────────┘
    │                │             │
    └────────┬───────┴─────────────┘
             │
    ┌────────▼────────┐
    │ PyTorch/ONNX    │
    │ Runtime         │
    └────────┬────────┘
             │
    ┌────────▼────────┐
    │ CUDA/ROCm       │
    │ (GPU Accel)     │
    └─────────────────┘
```

## Component Architecture

### 1. CLI Layer (`bin/demod-voice`)

**Purpose:** Unified command-line interface for all voice synthesis operations.

**Design:**
- Single entry point with subcommand architecture
- Uses Python argparse for argument parsing
- Delegates to backend-specific functions
- Handles error reporting and user feedback

**Subcommands:**
- `xtts-zero-shot`: Zero-shot voice cloning
- `piper-infer`: Piper model inference
- `piper-preprocess`: Dataset preparation
- `batch`: Batch processing from CSV
- `health`: System health check

**New Features:**
- Configuration file support (`~/.config/demod-voice/config.yaml`)
- Structured logging with `--verbose` and `--quiet` flags
- GPU validation with automatic CPU fallback
- Progress indicators for batch operations

**Key Design Decisions:**
- Pure Python script (no bash wrapper) for better error handling
- Subprocess isolation for backend calls to prevent memory leaks
- Path validation before heavy operations
- GPU flag propagates to all backends

### 2. XTTS-v2 Backend

**Technology:** Coqui TTS with XTTS-v2 architecture

**Capabilities:**
- Zero-shot voice cloning from 6-10s reference
- Multi-lingual synthesis (17+ languages)
- Streaming generation support
- GPU-accelerated inference

**Implementation Details:**
```python
from TTS.api import TTS
tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to("cuda")
tts.tts_to_file(
    text=text,
    speaker_wav=reference_path,
    language=language,
    file_path=output_path
)
```

**Resource Requirements:**
- VRAM: 6-8 GB for inference
- Model size: ~1.8 GB download
- First run: Downloads model automatically
- Subsequent runs: Cached in `~/.local/share/tts`

**Limitations:**
- Requires clean reference audio (no background noise)
- Quality degrades with poor reference samples
- Slower than Piper (2-5s per sentence)

### 3. Piper Backend

**Technology:** ONNX Runtime with custom VITS models

**Capabilities:**
- Fast CPU inference (real-time or faster)
- Multi-speaker models supported
- Low memory footprint
- Deterministic output

**Implementation Details:**
- ONNX models loaded by Piper binary
- Text preprocessing in Python
- Audio generation in C++ (via Piper)
- No GPU required (CPU-optimized)

**Model Format:**
```
model_name.onnx       # Neural network weights
model_name.onnx.json  # Configuration (phonemes, speakers, etc.)
```

**Performance:**
- Latency: <100ms for short phrases on modern CPU
- Memory: ~200 MB per model
- Quality: High (comparable to XTTS for trained voices)

### 4. Configuration System (`demod_voice/config.py`)

**Purpose:** Centralized configuration management with YAML support

**Features:**
- Default configuration values
- User config file loading (`~/.config/demod-voice/config.yaml`)
- Deep merging of user overrides with defaults
- Config validation with detailed error messages
- Programmatic config saving

**Configuration Hierarchy:**
1. Default values (built-in)
2. User config file (if exists)
3. CLI flags (highest priority)

### 5. Batch Processing (`demod_voice/batch.py`)

**Purpose:** Efficient processing of multiple voice cloning jobs

**Features:**
- CSV-based job specification
- Job validation before processing
- Progress tracking with tqdm
- Continue-on-error or fail-fast modes
- Parallel processing support (future)

**CSV Format:**
```csv
reference,text,output,language,speaker
/path/to/ref.wav,"Hello",/path/to/out.wav,en,0
```

### 6. Nix Packaging

**Purpose:** Reproducible, isolated build environment

**Structure:**
```nix
{
  inputs = { nixpkgs, flake-utils, tinygrad };
  outputs = { packages, apps, devShells, dockerImage };
}
```

**Key Components:**

#### Python Environment
```nix
pythonEnv = pkgs.python3.withPackages (ps: [
  coqui-tts      # Built from source
  torch          # CUDA-enabled
  onnxruntime    # GPU variant
  # ... other deps
]);
```

#### Package Build
```nix
demod-voice = pkgs.stdenv.mkDerivation {
  installPhase = ''
    # Install CLI script
    # Wrap with Python environment
    # Set runtime paths
  '';
};
```

#### Docker Image
```nix
dockerImage = pkgs.dockerTools.buildLayeredImage {
  contents = [ demod-voice piper-tts ffmpeg ];
  config = { Cmd = [...]; };
};
```

**Advantages:**
- Bit-for-bit reproducible builds
- Automatic dependency resolution
- GPU driver compatibility handled transparently
- Easy rollback to previous versions

## Data Flow

### Zero-Shot Cloning Flow

```
User Input (text + reference.wav)
    ↓
Validate inputs (file exists, text non-empty)
    ↓
Load XTTS-v2 model (GPU/CPU)
    ↓
Encode reference audio → speaker embedding
    ↓
Generate mel-spectrogram from text + embedding
    ↓
Vocoder (HiFi-GAN) → waveform
    ↓
Save output.wav
```

### Piper Inference Flow

```
User Input (text + model.onnx)
    ↓
Load ONNX model + config
    ↓
Text → phonemes (language-specific)
    ↓
Phonemes → mel-spectrogram (VITS encoder)
    ↓
Mel-spectrogram → waveform (VITS decoder)
    ↓
Save output.wav
```

## Security Considerations

### Input Validation
- Path traversal prevention (all paths validated)
- File size limits (implicitly via model constraints)
- Text sanitization (handled by TTS libraries)

### Dependency Security
- Nix pins exact versions (hash-verified)
- No network access during build (except fetches)
- Containerized execution option (Docker)

### Model Provenance
- XTTS models: Official Coqui releases
- Piper models: Verified rhasspy releases
- User models: No validation (user responsibility)

## Performance Optimization

### Memory Management
- Models loaded on-demand (lazy loading)
- CUDA memory cleared after inference
- Process isolation via subprocess (CLI layer)

### GPU Utilization
- CUDA graphs for XTTS (when available)
- Mixed precision (FP16) on supported GPUs
- Batch processing support (future enhancement)

### Caching Strategy
- Model weights: `~/.local/share/tts/`
- ONNX models: User-managed
- Compiled CUDA kernels: PyTorch cache

## Error Handling

### Graceful Degradation
1. GPU not available → Fall back to CPU
2. Model download fails → Clear error message
3. Invalid reference audio → Descriptive error

### Error Reporting
```python
try:
    operation()
except SpecificError as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
```

### Logging
- Minimal by default (production-friendly)
- Verbose mode available (future enhancement)
- Errors always to stderr

## Testing Strategy

### Unit Tests
- CLI argument parsing
- Path validation
- Subcommand registration

### Integration Tests
- End-to-end inference (with fixtures)
- Model loading
- File I/O operations

### Nix Tests
```nix
passthru.tests = {
  cli-help = runCommand "test-help" {} ''
    ${demod-voice}/bin/demod-voice --help > $out
  '';
};
```

## Future Enhancements

### Planned Features
1. **Streaming API**: Real-time synthesis
2. **Voice conversion**: Speaker A → Speaker B
3. **Fine-tuning CLI**: Simplified Piper training
4. **Web UI**: Gradio-based interface
5. **Model quantization**: INT8/INT4 for edge deployment

### Architectural Improvements
1. **Plugin system**: Third-party backend support
2. **Remote inference**: API server mode
3. **Batch processing**: Multiple files at once
4. **Model registry**: Download/manage models via CLI

## Dependencies

### Core Runtime
- Python 3.11+
- PyTorch 2.1+ (CUDA 11.8+)
- ONNX Runtime 1.16+
- Piper TTS 1.2+

### Build Time
- Nix 2.18+
- gcc/clang (for native builds)
- CUDA Toolkit (if GPU support)

### Optional
- ROCm (AMD GPU support)
- Vulkan (tinygrad backend)
- Docker (containerized deployment)

## License Compliance

All dependencies are compatible with MIT:
- PyTorch: BSD-style
- Coqui TTS: MPL 2.0
- Piper: MIT
- ONNX Runtime: MIT
- tinygrad: MIT

## Maintenance

### Version Updates
1. Update `flake.lock`: `nix flake update`
2. Test build: `nix build`
3. Update version in README
4. Tag release

### Monitoring
- GitHub Actions CI on every commit
- Automated Docker builds on tags
- Dependency vulnerability scanning (future)

## Contact

Technical questions: dev@demod.llc
Architecture decisions: See GitHub Discussions
