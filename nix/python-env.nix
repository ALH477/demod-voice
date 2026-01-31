# Helper function to build Python environment with specific backend
{ pkgs, coqui-tts }:

pkgs.python3.withPackages (ps: with ps; [
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
])