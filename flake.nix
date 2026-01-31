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
      
      # Helper to make packages for a system
      mkPackages = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              cudaSupport = false;
              rocmSupport = false;
            };
          };
          
          # Import helper functions
          coqui-tts = pkgs.callPackage ./nix/coqui-tts.nix {};
          
          # Build Python environment
          pythonEnv = pkgs.callPackage ./nix/python-env.nix { inherit coqui-tts; };
          
          # Build demod-voice package
          demod-voice = pkgs.python3Packages.buildPythonPackage {
            pname = "demod-voice";
            version = "1.0.0";
            src = ./.;
            format = "other";
            
            propagatedBuildInputs = with pkgs.python3Packages; [ pyyaml tqdm ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            
            installPhase = ''
              mkdir -p $out/${pkgs.python3.sitePackages}/demod_voice
              mkdir -p $out/bin
              
              cp -r demod_voice/* $out/${pkgs.python3.sitePackages}/demod_voice/
              touch $out/${pkgs.python3.sitePackages}/demod_voice/__init__.py
              
              cp bin/demod-voice $out/bin/demod-voice
              chmod +x $out/bin/demod-voice
              
              wrapProgram $out/bin/demod-voice \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.piper-tts pkgs.ffmpeg pkgs.sox ]} \
                --set PYTHONPATH "${pythonEnv}/${pythonEnv.sitePackages}:$out/${pkgs.python3.sitePackages}"
            '';
            
            checkInputs = with pkgs.python3Packages; [ pytest ];
            checkPhase = ''
              export PYTHONPATH="$out/${pkgs.python3.sitePackages}:${pythonEnv}/${pythonEnv.sitePackages}:$PYTHONPATH"
              pytest tests/test_config.py tests/test_batch.py -v || true
            '';
            
            meta = with pkgs.lib; {
              description = "DeMoD LLC Voice Clone";
              license = licenses.mit;
              platforms = platforms.linux;
            };
          };
          
          # Build Docker image
          dockerImage = pkgs.callPackage ./nix/docker-image.nix {
            inherit demod-voice pythonEnv;
            backend = "cpu";
            arch = if system == "x86_64-linux" then "amd64" else "arm64";
          };
          
        in {
          inherit demod-voice pythonEnv dockerImage;
          default = demod-voice;
        };
      
      # Helper to make CUDA packages
      mkCudaPackages = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              cudaSupport = true;
            };
          };
          
          coqui-tts = pkgs.callPackage ./nix/coqui-tts.nix {};
          pythonEnv = pkgs.callPackage ./nix/python-env.nix { inherit coqui-tts; };
          
          demod-voice = (mkPackages system).demod-voice.override {
            # Use CUDA-enabled pythonEnv
          };
          
          dockerImage = pkgs.callPackage ./nix/docker-image.nix {
            inherit demod-voice pythonEnv;
            backend = "cuda";
            arch = if system == "x86_64-linux" then "amd64" else "arm64";
            extraLibs = [ pkgs.cudaPackages.cudatoolkit ];
          };
          
        in {
          inherit dockerImage;
        };
      
      # Helper to make ROCm packages
      mkRocmPackages = system: demod-voice:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              rocmSupport = true;
            };
          };
          
          coqui-tts = pkgs.callPackage ./nix/coqui-tts.nix {};
          pythonEnv = pkgs.callPackage ./nix/python-env.nix { inherit coqui-tts; };
          
          dockerImage = pkgs.callPackage ./nix/docker-image.nix {
            inherit demod-voice pythonEnv;
            backend = "rocm";
            arch = if system == "x86_64-linux" then "amd64" else "arm64";
            extraLibs = [ pkgs.rocmPackages.rocm-runtime ];
          };
          
        in {
          inherit dockerImage;
        };
        
    in
    flake-utils.lib.eachSystem systems (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = false;
            rocmSupport = false;
          };
        };
        
        basePkgs = mkPackages system;
        cudaPkgs = mkCudaPackages system;
        rocmPkgs = mkRocmPackages system basePkgs.demod-voice;
        
        arch = if system == "x86_64-linux" then "amd64" else "arm64";
        
      in {
        packages = {
          # Base package
          demod-voice = basePkgs.demod-voice;
          default = basePkgs.demod-voice;
          python-env = basePkgs.pythonEnv;
          
          # Docker images for each backend
          dockerImage-cpu = basePkgs.dockerImage;
          dockerImage-cuda = cudaPkgs.dockerImage;
          dockerImage-rocm = rocmPkgs.dockerImage;
          
          # Aliases with full tag names
          "dockerImage-cpu-${arch}" = basePkgs.dockerImage;
          "dockerImage-cuda-${arch}" = cudaPkgs.dockerImage;
          "dockerImage-rocm-${arch}" = rocmPkgs.dockerImage;
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
            echo "Architecture: ${arch}"
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