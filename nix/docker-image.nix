# Helper function to build Docker image
{ pkgs, demod-voice, pythonEnv, backend, arch, extraLibs ? [] }:

let
  version = "1.0.0";
  
  # Backend-specific environment variables
  backendEnv = 
    if backend == "cuda" then [
      "NVIDIA_VISIBLE_DEVICES=all"
      "NVIDIA_DRIVER_CAPABILITIES=compute,utility"
    ]
    else if backend == "rocm" then [
      "HSA_OVERRIDE_GFX_VERSION=10.3.0"
      "ROCM_PATH=/opt/rocm"
    ]
    else [];  # CPU has no special env vars
    
  # Backend-specific labels
  backendLabels = {
    "org.opencontainers.image.backend" = backend;
    "org.opencontainers.image.architecture" = arch;
  };
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
      "PYTHONPATH=${pythonEnv}/${pythonEnv.sitePackages}:${demod-voice}/${pkgs.python3.sitePackages}"
      "HOME=/tmp"
      "TTS_HOME=/tmp/.local/share/tts"
    ] ++ backendEnv;
    WorkingDir = "/workspace";
    Volumes = {
      "/workspace" = {};
    };
    Labels = backendLabels;
  };
  
  # Optimize layer caching
  maxLayers = 100;
}