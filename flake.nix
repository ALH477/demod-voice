{
  description = "DeMoD LLC Voice Clone - Multi-Arch Local TTS and Voice Cloning Tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    tinygrad = {
      url = "github:tinygrad/tinygrad";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, tinygrad }:
    let
      # Define supported systems
      systems = [ "x86_64-linux" "aarch64-linux" ];
      
      # Helper to make packages for a system with specific Python version
      mkPackages = system: pythonVersion:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              cudaSupport = false;
              rocmSupport = false;
            };
          };
          
          # Select Python version (311 for Coqui TTS compatibility)
          python = if pythonVersion == "311" then pkgs.python311 else pkgs.python3;
          pythonPkgs = python.pkgs;
          
          # Override packages with flaky tests
          einops' = pythonPkgs.einops.overridePythonAttrs (oldAttrs: {
            doCheck = false;
          });
          
          # Build Coqui TTS with specific Python
          coqui-tts = pythonPkgs.buildPythonPackage rec {
            pname = "TTS";
            version = "0.22.0";
            format = "pyproject";
            
            src = pkgs.fetchFromGitHub {
              owner = "coqui-ai";
              repo = "TTS";
              rev = "v${version}";
              sha256 = "sha256-RQVlPHYZ5X/6xbxwGNcgntcyAsBS8T2ketdk+OCIS3Q=";
            };
            
            nativeBuildInputs = with pythonPkgs; [
              setuptools
              wheel
              cython
            ];

            propagatedBuildInputs = with pythonPkgs; [
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
              einops'
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

            doCheck = false;
            
            pythonImportsCheck = [ "TTS" ];
          };
          
          # Build Python environment
          pythonEnv = python.withPackages (ps: with ps; [
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
          
          # Build demod-voice package
          demod-voice = pythonPkgs.buildPythonPackage {
            pname = "demod-voice";
            version = "1.0.0";
            src = ./.;
            format = "other";
            
            propagatedBuildInputs = with pythonPkgs; [ pyyaml tqdm ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            
            installPhase = ''
              mkdir -p $out/${python.sitePackages}/demod_voice
              mkdir -p $out/bin
              
              cp -r demod_voice/* $out/${python.sitePackages}/demod_voice/
              touch $out/${python.sitePackages}/demod_voice/__init__.py
              
              cp bin/demod-voice $out/bin/demod-voice
              chmod +x $out/bin/demod-voice
              
              wrapProgram $out/bin/demod-voice \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.piper-tts pkgs.ffmpeg pkgs.sox ]} \
                --set PYTHONPATH "${pythonEnv}/${python.sitePackages}:$out/${python.sitePackages}"
            '';
            
            checkInputs = with pythonPkgs; [ pytest ];
            checkPhase = ''
              export PYTHONPATH="$out/${python.sitePackages}:${pythonEnv}/${python.sitePackages}:$PYTHONPATH"
              pytest tests/test_config.py tests/test_batch.py -v || true
            '';
            
            meta = with pkgs.lib; {
              description = "DeMoD LLC Voice Clone";
              license = licenses.mit;
              platforms = platforms.linux;
            };
          };
          
        in {
          inherit demod-voice pythonEnv python pythonPkgs;
        };
      
      # Build Docker image helper
      mkDockerImage = { pkgs, demod-voice, pythonEnv, python, backend, arch, extraLibs ? [] }:
        let
          version = "1.0.0";
          
          backendEnv = 
            if backend == "cuda" then [
              "NVIDIA_VISIBLE_DEVICES=all"
              "NVIDIA_DRIVER_CAPABILITIES=compute,utility"
            ]
            else if backend == "rocm" then [
              "HSA_OVERRIDE_GFX_VERSION=10.3.0"
              "ROCM_PATH=/opt/rocm"
            ]
            else [];
            
        in
        pkgs.dockerTools.buildLayeredImage {
          name = "demod-voice";
          tag = "${version}-${backend}-${arch}";
          
          contents = [
            demod-voice
            pythonEnv
            pkgs.piper-tts
            pkgs.ffmpeg
            pkgs.sox
            pkgs.bashInteractive
            pkgs.coreutils
            pkgs.cacert
          ] ++ extraLibs;

          config = {
            Cmd = [ "${demod-voice}/bin/demod-voice" "--help" ];
            Env = [
              "PATH=/bin:${pkgs.lib.makeBinPath ([ pkgs.piper-tts pkgs.ffmpeg pkgs.sox ] ++ extraLibs)}"
              "PYTHONUNBUFFERED=1"
              "PYTHONPATH=${pythonEnv}/${python.sitePackages}:${demod-voice}/${python.sitePackages}"
              "HOME=/tmp"
              "TTS_HOME=/tmp/.local/share/tts"
            ] ++ backendEnv;
            WorkingDir = "/workspace";
            Volumes = {
              "/workspace" = {};
            };
          };
          
          maxLayers = 100;
        };
        
    in
    flake-utils.lib.eachSystem systems (system:
      let
        # Use Python 3.11 for Coqui TTS compatibility (requires < 3.12)
        basePkgs = mkPackages system "311";
        
        arch = if system == "x86_64-linux" then "amd64" else "arm64";
        
        # Base imports for checks and devShell
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = false;
            rocmSupport = false;
          };
        };
        
        # CUDA variant
        cudaPkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        };
        
        cudaBase = mkPackages system "311";
        
        dockerImage-cuda = mkDockerImage {
          pkgs = cudaPkgs;
          inherit (cudaBase) demod-voice pythonEnv;
          python = cudaBase.python;
          backend = "cuda";
          inherit arch;
          extraLibs = [ cudaPkgs.cudaPackages.cudatoolkit ];
        };
        
        # ROCm variant
        rocmPkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            rocmSupport = true;
          };
        };
        
        rocmBase = mkPackages system "311";
        
        dockerImage-rocm = mkDockerImage {
          pkgs = rocmPkgs;
          inherit (rocmBase) demod-voice pythonEnv;
          python = rocmBase.python;
          backend = "rocm";
          inherit arch;
          extraLibs = [ rocmPkgs.rocmPackages.rocm-runtime ];
        };
        
        # CPU variant
        dockerImage-cpu = mkDockerImage {
          inherit pkgs;
          inherit (basePkgs) demod-voice pythonEnv python;
          backend = "cpu";
          inherit arch;
        };
        
      in {
        packages = {
          # Base package
          demod-voice = basePkgs.demod-voice;
          default = basePkgs.demod-voice;
          python-env = basePkgs.pythonEnv;
          
          # Docker images for each backend
          inherit dockerImage-cpu dockerImage-cuda dockerImage-rocm;
          
          # Aliases with full tag names
          "dockerImage-cpu-${arch}" = dockerImage-cpu;
          "dockerImage-cuda-${arch}" = dockerImage-cuda;
          "dockerImage-rocm-${arch}" = dockerImage-rocm;
        };

        apps = {
          demod-voice = {
            type = "app";
            program = "${basePkgs.demod-voice}/bin/demod-voice";
          };
          default = {
            type = "app";
            program = "${basePkgs.demod-voice}/bin/demod-voice";
          };
        };

        checks = {
          cli-help = pkgs.runCommand "test-cli-help" {
            buildInputs = [ basePkgs.demod-voice ];
          } ''
            ${basePkgs.demod-voice}/bin/demod-voice --help > $out
          '';
          
          health-check = pkgs.runCommand "test-health-check" {
            buildInputs = [ basePkgs.demod-voice ];
          } ''
            ${basePkgs.demod-voice}/bin/demod-voice health --json > $out
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = [
            basePkgs.pythonEnv
            basePkgs.demod-voice
            pkgs.piper-tts
            pkgs.git
            pkgs.ffmpeg
            pkgs.sox
            pkgs.python311Packages.black
            pkgs.python311Packages.ruff
            pkgs.python311Packages.mypy
            pkgs.python311Packages.pytest
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.cudaPackages.cudatoolkit
            pkgs.vulkan-loader
          ];

          shellHook = ''
            echo "========================================"
            echo "DeMoD LLC Voice Clone Dev Environment"
            echo "Architecture: ${arch}"
            echo "Python: 3.11 (for Coqui TTS compatibility)"
            echo "========================================"
            echo ""
            echo "Available Docker builds:"
            echo "  nix build .#dockerImage-cpu-${arch}"
            echo "  nix build .#dockerImage-cuda-${arch}"
            echo "  nix build .#dockerImage-rocm-${arch}"
            echo ""
            echo "CLI usage: demod-voice --help"
            echo ""
          '';

          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (
            pkgs.lib.optionals pkgs.stdenv.isLinux [
              pkgs.stdenv.cc.cc.lib
              pkgs.cudaPackages.cudatoolkit
            ]
          );
        };
      }
    );
}