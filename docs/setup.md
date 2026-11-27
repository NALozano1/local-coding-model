# Setup

For Linux with CUDA 12.8 or newer, CMake 3.24 or newer, Ninja, GCC 11, Python 3.10 and tmux.
About 80 GB of disk. `80` below is the A30's CUDA architecture; set it to match your GPU.
Run everything from the repository folder.

These commands collect the steps used for the tested setup. **They have not been run start to finish
from a fresh clone.**

## 1. Python environment

    python3 -m venv venv
    venv/bin/pip install -r requirements.txt

## 2. llama.cpp

    git clone https://github.com/ggml-org/llama.cpp engines/llama.cpp
    git -C engines/llama.cpp checkout 0e4e925e8
    cmake -S engines/llama.cpp -B engines/llama.cpp/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=80
    cmake --build engines/llama.cpp/build -j --target llama-server

## 3. Maya (two builds: the original for Q4, a patched one for Q8)

    for v in q4 q8; do
      git clone https://github.com/alesha-pro/maya-inkling-mini engines/maya-$v
      git -C engines/maya-$v checkout 27daec5
    done
    git -C engines/maya-q8 apply "$PWD/patches/maya-q8.patch"
    for v in q4 q8; do
      cmake -S engines/maya-$v -B engines/maya-$v/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DSTRATA_ENABLE_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=80 -DSTRATA_BUILD_TESTS=OFF \
        -DCMAKE_C_COMPILER=gcc-11 -DCMAKE_CXX_COMPILER=g++-11 -DCMAKE_CUDA_HOST_COMPILER=g++-11
      cmake --build engines/maya-$v/build -j --target maya-ik2
    done

## 4. Models

Maya needs the files in `Old_Support/` (the older GGUF layout).

    mkdir -p models
    get() { curl -fL -C - -o "models/$2" "https://huggingface.co/$1/resolve/main/$3"; }
    G=unsloth/Inkling-2-Mini-GGUF
    get $G Inkling-2-Mini-UD-Q4_K_M.gguf    Inkling-2-Mini-UD-Q4_K_M.gguf
    get $G dspark-Inkling-2-Mini-Q8_0.gguf  dspark-Inkling-2-Mini-Q8_0.gguf
    get $G Inkling-2-Mini-UD-Q4_K_XL.gguf   Old_Support/Inkling-2-Mini-UD-Q4_K_XL.gguf_file
    get $G Inkling-2-Mini-UD-Q8_K_XL.gguf   Old_Support/Inkling-2-Mini-UD-Q8_K_XL.gguf_file
    get thinkingmachines/Inkling-2-Mini mtp.safetensors mtp.safetensors

Convert the Q8 file for Maya (the result is for Maya only):

    PYTHONPATH=engines/llama.cpp/gguf-py venv/bin/python engines/maya-q8/tools/ik2_fp8_experts.py \
      models/Inkling-2-Mini-UD-Q8_K_XL.gguf models/Inkling-2-Mini-UD-Q8_K_XL-maya-fp8.gguf

## 5. Maya tokenizer

    for v in q4 q8; do
      (cd engines/maya-$v && ../../venv/bin/python tools/strata_tokenizer.py \
        --gguf ../../models/Inkling-2-Mini-UD-Q4_K_XL.gguf --out ik2 \
        --chat-template tools/ik2/chat_template.jinja --check)
    done

## Credits and licences

`patches/maya-q8.patch` modifies [Maya](https://github.com/alesha-pro/maya-inkling-mini) (MIT).
[llama.cpp](https://github.com/ggml-org/llama.cpp) is MIT. Check the model pages for the model licences.
