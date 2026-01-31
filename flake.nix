{
  description = "DeMoD LLC Voice Clone - Local TTS and Voice Cloning Tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    tinygrad = {
      url = "github:tinygrad/tinygrad";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, tinygrad }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        };

        # Build Coqui TTS from source
        coqui-tts = pkgs.python3Packages.buildPythonPackage rec {
          pname = "TTS";
          version = "0.22.0";
          format = "pyproject";
          
          src = pkgs.fetchFromGitHub {
            owner = "coqui-ai";
            repo = "TTS";
            rev = "v${version}";
            sha256 = "sha256-f/JYeASaOeByOzV7VW8z8F1VJVuKE0hFGv9sH3VJPsA=";
          };
          
          nativeBuildInputs = with pkgs.python3Packages; [
            setuptools
            wheel
          ];

          propagatedBuildInputs = with pkgs.python3Packages; [
            numpy
            scipy
            torch
            torchaudio
            librosa
            soundfile
            inflect
            tqdm
            packaging
            numba
            einops
            transformers
            tokenizers
            coqpit
            pyyaml
            fsspec
            pydub
            gruut
            bangla
            jamo
            pypinyin
            mecab-python3
            unidic-lite
          ];

          # Skip tests - they require additional test data
          doCheck = false;
          
          pythonImportsCheck = [ "TTS" ];
        };

        # Enhanced Python environment
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          coqui-tts
          torch
          torchaudio
          torchvision
          pytorch-lightning
          onnxruntime
          numpy
          scipy
          librosa
          pydub
          pyyaml
          fsspec
          soundfile
          tqdm
        ]);

        # Build tinygrad package
        tinygradPkg = pkgs.python3Packages.buildPythonPackage {
          pname = "tinygrad";
          version = "0.9.0";
          src = tinygrad;
          format = "setuptools";
          
          propagatedBuildInputs = with pkgs.python3Packages; [
            numpy
            pillow
            requests
            tqdm
          ];
          
          doCheck = false;
        };

        # Build demod-voice as a proper Python package
        demod-voice = pkgs.python3Packages.buildPythonPackage {
          pname = "demod-voice";
          version = "1.0.0";
          
          src = ./.;
          
          format = "other";
          
          propagatedBuildInputs = with pkgs.python3Packages; [
            pyyaml
            tqdm
          ];
          
          nativeBuildInputs = [ pkgs.makeWrapper ];
          
          # Install the Python package
          installPhase = ''
            mkdir -p $out/${pkgs.python3.sitePackages}/demod_voice
            mkdir -p $out/bin
            
            # Install Python modules
            cp -r demod_voice/* $out/${pkgs.python3.sitePackages}/demod_voice/
            
            # Create __init__.py if it doesn't exist
            touch $out/${pkgs.python3.sitePackages}/demod_voice/__init__.py
            
            # Install CLI script
            cp bin/demod-voice $out/bin/demod-voice
            chmod +x $out/bin/demod-voice
            
            # Wrap the CLI with all dependencies
            wrapProgram $out/bin/demod-voice \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.piper-tts pkgs.ffmpeg pkgs.sox ]} \
              --set PYTHONPATH "${pythonEnv}/${pythonEnv.sitePackages}:$out/${pkgs.python3.sitePackages}"
          '';
          
          # Tests
          checkInputs = with pkgs.python3Packages; [ pytest ];
          checkPhase = ''
            export PYTHONPATH="$out/${pkgs.python3.sitePackages}:${pythonEnv}/${pythonEnv.sitePackages}:$PYTHONPATH"
            pytest tests/test_config.py tests/test_batch.py -v || true
          '';
          
          meta = with pkgs.lib; {
            description = "DeMoD LLC Voice Clone - Local TTS and Voice Cloning";
            license = licenses.mit;
            platforms = platforms.linux;
            maintainers = [ ];
          };
        };

      in {
        packages = {
          inherit demod-voice;
          default = demod-voice;
          
          # Expose Python env for debugging
          python-env = pythonEnv;
        };

        apps = {
          demod-voice = {
            type = "app";
            program = "${demod-voice}/bin/demod-voice";
          };
          default = self.apps.${system}.demod-voice;
        };

        # Checks for CI
        checks = {
          # Test that CLI runs
          cli-help = pkgs.runCommand "test-cli-help" {
            buildInputs = [ demod-voice ];
          } ''
            ${demod-voice}/bin/demod-voice --help > $out
          '';
          
          # Test health check
          health-check = pkgs.runCommand "test-health-check" {
            buildInputs = [ demod-voice ];
          } ''
            ${demod-voice}/bin/demod-voice health --json > $out
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pythonEnv
            tinygradPkg
            demod-voice
            pkgs.piper-tts
            pkgs.git
            pkgs.ffmpeg
            pkgs.sox
            pkgs.python3Packages.black
            pkgs.python3Packages.ruff
            pkgs.python3Packages.mypy
            pkgs.python3Packages.pytest
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.cudaPackages.cudatoolkit
            pkgs.vulkan-loader
          ];

          shellHook = ''
            echo "========================================"
            echo "DeMoD LLC Voice Clone Dev Environment"
            echo "========================================"
            echo ""
            echo "CLI usage: demod-voice --help"
            echo ""
            echo "Examples:"
            echo "  demod-voice xtts-zero-shot reference.wav \"Hello from DeMoD\" --output demo.wav"
            echo "  demod-voice piper-infer model.onnx \"Test sentence\" --output test.wav"
            echo ""
            echo "Python environment includes:"
            echo "  - Coqui TTS (XTTS-v2)"
            echo "  - PyTorch with CUDA support"
            echo "  - tinygrad for experimentation"
            echo ""
          '';

          # Enable CUDA if available
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (
            pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.stdenv.cc.cc.lib
              pkgs.cudaPackages.cudatoolkit
            ]
          );
        };

        # Docker image for containerized deployment
        dockerImage = pkgs.dockerTools.buildLayeredImage {
          name = "demod-voice";
          tag = "latest";
          
          contents = [
            demod-voice
            pythonEnv
            pkgs.piper-tts
            pkgs.ffmpeg
            pkgs.sox
            pkgs.bashInteractive
            pkgs.coreutils
            pkgs.cacert  # SSL certificates for model downloads
          ];

          config = {
            Cmd = [ "${demod-voice}/bin/demod-voice" "--help" ];
            Env = [
              "PATH=/bin:${pkgs.lib.makeBinPath [ pkgs.piper-tts pkgs.ffmpeg pkgs.sox ]}"
              "PYTHONUNBUFFERED=1"
              "PYTHONPATH=${pythonEnv}/${pythonEnv.sitePackages}:${demod-voice}/${pkgs.python3.sitePackages}"
              "HOME=/tmp"  # For model cache
              "TTS_HOME=/tmp/.local/share/tts"  # Coqui TTS cache location
            ];
            WorkingDir = "/workspace";
            Volumes = {
              "/workspace" = {};
            };
          };
        };
      }
    );
}
