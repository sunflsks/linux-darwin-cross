#!/bin/bash

# Thanks to apple-libtapi by tpoechtrager for fixed CMakeLists

# First, get the Apple LLVM sources and add the TAPI sources to those
# Then, build the toolchain + obj2yaml/yaml2objc
# Finally, get the cctools-port sources and build the cctools

source versions

trap script_interrupt INT

function script_interrupt() {
	echo "Exiting..."
	exit 1
}

# Get PREFIX and DESTDIR

function usage() {
    echo "Usage: $0 -p PREFIX -d DESTDIR -x"
    script_interrupt
}

unset PREFIX
unset DESTDIR
unset REMOVE_PREFIXES

while getopts "p:d:r" opts; do
    case "$opts" in
        p)
            PREFIX="${OPTARG}"
            ;;
        d)
            DESTDIR="${OPTARG}"
            ;;
        r)
            REMOVE_PREFIXES="YES"
            ;;
        *)
            usage
            ;;
    esac
done

echo "Apple LLVM Version: $LLVM_VER"
echo "apple-libtapi Version: $LIBTAPI_VER"
echo "cctools-port Version: $CCTOOLS_PORT_VER"
echo "libplist Version: $LIBPLIST_VER"

sleep 1

if [ -z $DESTDIR ]; then
    export DESTDIR="$(realpath Output)"
else
    DESTDIR="$(realpath $DESTDIR)"
fi

if [ -z $PREFIX ]; then
    PREFIX="/usr/local/opt/cross/apple/arm-apple-darwin"
fi

ROOT_DIR="$PWD"

mkdir -p "$DESTDIR/$PREFIX/bin"

# TODO: Make this much, much better. Perhaps add ability to look in custom dir for libs?
echo "Checking for libraries (libxar.so)..."
mkdir -p "$DESTDIR/$PREFIX/lib"

if [ -f /usr/lib/libxar.so ]; then
    cp -P /usr/lib/libxar.so* "$DESTDIR/$PREFIX/lib"
else
    echo "Optional library $lib missing!"
    sleep 1
fi

function get_sources() {
    # Get LLVM
    if [[ ! -d llvm-project ]]; then
        if [[ "$LLVM_VER" == "main" ]]; then
            LLVM_BRANCH="main"
        else
            LLVM_BRANCH="stable/$LLVM_VER"
        fi
        
        git clone -b "apple/$LLVM_BRANCH" --single-branch --depth=1 git://github.com/apple/llvm-project
    else
        echo "Using previously cloned LLVM"
    fi

    # For some reason I cannot find a way to get TAPI to compile, so I'll just use
    # tpoechtrager's LLVM and TAPI. :(

    if [[ ! -d apple-libtapi ]]; then
        git clone -b "$LIBTAPI_VER" --single-branch --depth=1 git://github.com/tpoechtrager/apple-libtapi
    else
        echo "Using previously cloned apple-libtapi"
    fi

    # Get cctools-port
    if [[ ! -d cctools-port ]]; then
        git clone -b "$CCTOOLS_PORT_VER" --single-branch --depth=1 git://github.com/tpoechtrager/cctools-port
    fi
    
    if [[ ! -d ldid ]]; then
        git clone --depth=1 git://git.saurik.com/ldid.git
    fi
    
    if [[ ! -d libplist ]]; then
        git clone --branch "$LIBPLIST_VER" --depth=1 git://github.com/libimobiledevice/libplist
    fi
}

function build_tapi() {
    # Build and install TAPI
    cp -v fixed-scripts/betterBuild.sh apple-libtapi/build.sh
    cd apple-libtapi && ./build.sh && cd "$ROOT_DIR"
    mv apple-libtapi/build/{bin,lib} "$DESTDIR/$PREFIX/"
}

function build_llvm() {
    # Build and install LLVM
    printf "\nCompiling LLVM\n"
    cd llvm-project
    if [ -d build ]; then
        rm -rf build;
    fi

    mkdir build && cd build
    cmake \
        -G Ninja \
        -DLLVM_ENABLE_PROJECTS="clang;obj2yaml;yaml2obj" \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        ../llvm
    ninja -j6

    env DESTDIR=output-temp ninja install
    cd "$ROOT_DIR"
    rsync -a llvm-project/build/output-temp/* "$DESTDIR"
}

function build_cctools_port() {
    # Build and install cctools-port
    cd cctools-port/cctools
    LIBS_DIR="$DESTDIR/$PREFIX/lib"
    CONFIGURE_ARGS="--enable-lto-support  --with-libtapi=$LIBS_DIR  --enable-tapi-support"

    ./configure \
    --prefix="$PREFIX" \
    --target=aarch64-apple-darwin \
    $CONFIGURE_ARGS

    make -j5
    make DESTDIR="$DESTDIR" install
    cd "$ROOT_DIR"
}

function remove_prefixes() {
    cd "$DESTDIR/$PREFIX/bin"
    
    for file in ./aarch64*; do
        ## aarch64-apple-darwin- character count is 22
        NEWFILENAME="$(echo $file | cut -b 24-)"
        mv "$file" "$NEWFILENAME"
    done
    cd "$ROOT_DIR"
}

function build_libplist() {
    cd libplist
    ./autogen.sh --prefix="$PREFIX"
    make -j5
    make DESTDIR="$DESTDIR" install
    cd "$ROOT_DIR"
}

function build_ldid2() {
    cp fixed-scripts/make.sh ldid/
    cd ldid
    (export PREFIX DESTDIR && bash make.sh)
    cp out/ldid "$DESTDIR/$PREFIX/bin"
    cd "$ROOT_DIR"
}

function strip_binaries() {
    echo "Stripping binaries..."
    cd "$DESTDIR/$PREFIX/bin"
    for file in ./*; do
        case "$(file -S -bi $file)" in
            *application/x-sharedlib*)
                STRIPFLAGS="--strip-unneeded"
                ;;
            *application/x-archive*)
                STRIPFLAGS="--strip-debug"
                ;;
            *application/x-executable*)
                STRIPFLAGS="--strip-all"
                ;;
            *application/x-pie-executable*)
                STRIPFLAGS="--strip-unneeded"
                ;;
            *)
                continue
        esac
        strip "$STRIPFLAGS" "$file"
    done
    cd "$ROOT_DIR"
}

get_sources
build_tapi
build_llvm
build_cctools_port
build_libplist
build_ldid2

if [[ "$REMOVE_PREFIXES" ]]; then
    remove_prefixes
fi

strip_binaries
