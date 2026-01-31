# Helper function to build Coqui TTS package
{ pkgs }:

pkgs.python3Packages.buildPythonPackage rec {
  pname = "TTS";
  version = "0.22.0";
  format = "pyproject";
  
  src = pkgs.fetchFromGitHub {
    owner = "coqui-ai";
    repo = "TTS";
    rev = "v${version}";
    sha256 = "sha256-RQVlPHYZ5X/6xbxwGNcgntcyAsBS8T2ketdk+OCIS3Q=";
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

  doCheck = false;
  
  pythonImportsCheck = [ "TTS" ];
}
