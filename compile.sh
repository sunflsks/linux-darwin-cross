#!/bin/bash

# Thanks to apple-libtapi by tpoechtrager for fixed CMakeLists

# First, get the Apple LLVM sources and add the TAPI sources to those
# Then, build the toolchain + obj2yaml/yaml2objc
# Finally, get the cctools-port sources and build the cctools


if [ -z $DESTDIR ]; then
    export DESTDIR="$PWD/Output"
fi

if [ -z $PREFIX ]; then
    PREFIX="/usr/local/opt/cross/apple/arm-apple-darwin"
fi

ROOT_DIR="$PWD"

mkdir -p "$DESTDIR/$PREFIX/bin"

# Get LLVM
if [[ ! -d llvm-project ]]; then
    git clone --depth=1 git://github.com/apple/llvm-project
else
    echo "Using previously cloned LLVM"
fi

# For some reason I cannot find a way to get TAPI to compile, so I'll just use
# tpoechtrager's LLVM and TAPI. :(

if [[ ! -d apple-libtapi ]]; then
    git clone --depth=1 git://github.com/tpoechtrager/apple-libtapi
else
    echo "Using previously cloned apple-libtapi"
fi

# Build and install TAPI
cp -v betterBuild.sh apple-libtapi/build.sh
cd apple-libtapi && ./build.sh && cd "$ROOT_DIR"
mv apple-libtapi/build/bin/* "$DESTDIR/$PREFIX/bin/"

# Build and install LLVM
printf "\nCompiling LLVM\n"
cd llvm-project
if [ -d build ]; then
    rm -rf build;
fi

mkdir build && cd build
cmake \
    -G Ninja \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    ../llvm
ninja -j6

env DESTDIR=output-temp ninja install
cd "$ROOT_DIR"
rsync -a llvm-project/build/output-temp/* "$DESTDIR"
