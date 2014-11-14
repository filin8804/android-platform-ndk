#!/bin/bash

# Copyright (c) 2011-2015 CrystaX .NET.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are
# permitted provided that the following conditions are met:
#
#    1. Redistributions of source code must retain the above copyright notice, this list of
#       conditions and the following disclaimer.
#
#    2. Redistributions in binary form must reproduce the above copyright notice, this list
#       of conditions and the following disclaimer in the documentation and/or other materials
#       provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY CrystaX .NET ''AS IS'' AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
# FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL CrystaX .NET OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# The views and conclusions contained in the software and documentation are those of the
# authors and should not be interpreted as representing official policies, either expressed
# or implied, of CrystaX .NET.

# include common function and variable definitions
. `dirname $0`/prebuilt-common.sh

PROGRAM_PARAMETERS=""

PROGRAM_DESCRIPTION=\
"Rebuild libobjc2 for the Android NDK.

This requires a temporary NDK installation containing
toolchain binaries for all target architectures.

By default, this will try with the current NDK directory, unless
you use the --ndk-dir=<path> option.

The output will be placed in appropriate sub-directories of
<ndk>/$OBJC2_SUBDIR, but you can override this with the --out-dir=<path>
option.
"

PACKAGE_DIR=
register_var_option "--package-dir=<path>" PACKAGE_DIR "Put prebuilt tarballs into <path>."

NDK_DIR=
register_var_option "--ndk-dir=<path>" NDK_DIR "Specify NDK root path for the build."

SRC_DIR=
register_var_option "--src-dir=<path>" SRC_DIR "Specify libobjc2 source dir."

BUILD_DIR=
OPTION_BUILD_DIR=
register_var_option "--build-dir=<path>" OPTION_BUILD_DIR "Specify temporary build dir."

OUT_DIR=
register_var_option "--out-dir=<path>" OUT_DIR "Specify output directory directly."

ABIS="$PREBUILT_ABIS"
register_var_option "--abis=<list>" ABIS "Specify list of target ABIs."

TOOLCHAIN_VERSION=clang3.5
register_var_option "--toolchain-version=<ver>" TOOLCHAIN_VERSION "Specify toolchain version"

register_jobs_option

extract_parameters "$@"

ABIS=$(commas_to_spaces $ABIS)

# Handle NDK_DIR
if [ -z "$NDK_DIR" ] ; then
    NDK_DIR=$ANDROID_NDK_ROOT
    log "Auto-config: --ndk-dir=$NDK_DIR"
else
    if [ ! -d "$NDK_DIR" ] ; then
        echo "ERROR: NDK directory does not exists: $NDK_DIR"
        exit 1
    fi
fi

if [ -z "$OPTION_BUILD_DIR" ]; then
    BUILD_DIR=$NDK_TMPDIR/build-libobjc2
else
    BUILD_DIR=$OPTION_BUILD_DIR
fi
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
fail_panic "Could not create build directory: $BUILD_DIR"

if [ -z "$SRC_DIR" -o ! -d "$SRC_DIR" ]; then
    dump "Could not found libobjc2 source directory: $SRC_DIR"
    dump "Use --src-dir=<dir> to specify source directory."
    exit 1
fi

# $1: ABI
llvm_tripple_for_abi()
{
    local ABI=$1
    case $ABI in
        armeabi)
            echo "armv5te-none-linux-androideabi"
            ;;
        armeabi-v7a*)
            echo "armv7-none-linux-androideabi"
            ;;
        arm64-v8a)
            echo "aarch64-none-linux-android"
            ;;
        x86)
            echo "i686-none-linux-android"
            ;;
        x86_64)
            echo "x86_64-none-linux-android"
            ;;
        mips)
            echo "mipsel-none-linux-android"
            ;;
        mips64)
            echo "mips64el-none-linux-android"
            ;;
        *)
            dump "Unknown ABI: '$ABI'"
            exit 1
    esac
}

# $1: ABI
gcc_toolchain_prefix_for_abi()
{
    local ABI=$1
    case $ABI in
        armeabi*)
            echo "arm-linux-androideabi"
            ;;
        arm64-v8a)
            echo "aarch64-linux-android"
            ;;
        mips|mips64)
            echo "${ABI}el-linux-android"
            ;;
        x86|x86_64)
            echo $ABI
            ;;
        *)
            dump "Unknown ABI: '$ABI'"
            exit 1
    esac
}

# $1: ABI
gcc_toolchain_name_for_abi()
{
    local ABI=$1
    case $ABI in
        armeabi*)
            echo "arm-linux-androideabi"
            ;;
        arm64-v8a)
            echo "aarch64-linux-android"
            ;;
        mips|mips64)
            echo "${ABI}el-linux-android"
            ;;
        x86)
            echo "i686-linux-android"
            ;;
        x86_64)
            echo "x86_64-linux-android"
            ;;
        *)
            dump "Unknown ABI: '$ABI'"
            exit 1
    esac
}

# $1: ABI
# $2: build directory
# $4: (optional) installation directory
build_libobjc2_for_abi ()
{
    local ABI=$1
    local BUILDDIR="$2"
    local DSTDIR="$3"
    local ARCH APILEVEL SYSROOT
    local CCFLAGS CFLAGS CXXFLAGS
    local LLVM_DIR LLVM_TRIPPLE
    local GCC_DIR GCC_VERSION
    local GCC_TOOLCHAIN_PREFIX GCC_TOOLCHAIN_NAME

    mkdir -p "$BUILDDIR"

    # If the output directory is not specified, use default location
    if [ -z "$DSTDIR" ]; then
        DSTDIR=$NDK_DIR/$OBJC2_SUBDIR/libs/$ABI
    fi

    mkdir -p "$DSTDIR"

    (cd $SRC_DIR && tar cf - ./*) | (cd $BUILDDIR && tar xf -)
    fail_panic "Couldn't copy libobjc2 sources to temporary directory"

    ARCH=$(convert_abi_to_arch $ABI)

    if [ ${ABI%%64*} != ${ABI} ]; then
        APILEVEL=21
    else
        APILEVEL=9
    fi
    SYSROOT=$NDK_DIR/platforms/android-$APILEVEL/arch-$ARCH

    if [ "${TOOLCHAIN_VERSION##clang}" != "${TOOLCHAIN_VERSION}" ]; then
        GCC_VERSION=4.9
    else
        GCC_VERSION=${TOOLCHAIN_VERSION##gcc}
    fi

    GCC_TOOLCHAIN_PREFIX=$(gcc_toolchain_prefix_for_abi $ABI)
    GCC_DIR=$NDK_DIR/toolchains/$GCC_TOOLCHAIN_PREFIX-$GCC_VERSION/prebuilt/$HOST_TAG

    if [ "${TOOLCHAIN_VERSION##clang}" != "${TOOLCHAIN_VERSION}" ]; then
        LLVM_VERSION=${TOOLCHAIN_VERSION##clang}
        if [ -z "$LLVM_VERSION" ]; then
            LLVM_VERSION=3.5
        fi

        LLVM_DIR=$NDK_DIR/toolchains/llvm-$LLVM_VERSION/prebuilt/$HOST_TAG
        CC=$LLVM_DIR/bin/clang
        CXX=$LLVM_DIR/bin/clang++
        AR=$LLVM_DIR/bin/llvm-ar

        LLVM_TRIPPLE=$(llvm_tripple_for_abi $ABI)

        CCFLAGS="-target $LLVM_TRIPPLE"
        CCFLAGS="$CCFLAGS -gcc-toolchain $GCC_DIR"
    else
        GCC_TOOLCHAIN_NAME=$(gcc_toolchain_name_for_abi $ABI)
        CC=$GCC_DIR/bin/$GCC_TOOLCHAIN_NAME-gcc
        CXX=$GCC_DIR/bin/$GCC_TOOLCHAIN_NAME-g++
        AR=$GCC_DIR/bin/$GCC_TOOLCHAIN_NAME-ar

        CCFLAGS=""
    fi

    case $ABI in
        armeabi)
            CCFLAGS="$CCFLAGS -march=armv5te -mtune=xscale -msoft-float -mthumb"
            ;;
        armeabi-v7a)
            CCFLAGS="$CCFLAGS -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=softfp -mthumb"
            ;;
        armeabi-v7a-hard)
            CCFLAGS="$CCFLAGS -march=armv7-a -mfpu=vfpv3-d16 -mhard-float -mthumb"
            ;;
        mips)
            CCFLAGS="$CCFLAGS -mabi=32 -mips32r6"
            ;;
        mips64)
            CCFLAGS="$CCFLAGS -mabi=64 -mips64r6"
            ;;
    esac

    if [ "${TOOLCHAIN_VERSION##clang}" != "$TOOLCHAIN_VERSION" ]; then
        CCFLAGS="$CCFLAGS -fintegrated-as"
    fi

    CCFLAGS="$CCFLAGS -fPIC"

    CFLAGS=""
    CFLAGS="$CFLAGS -g -O2"
    CFLAGS="$CFLAGS --sysroot=$SYSROOT"

    if [ "${TOOLCHAIN_VERSION##clang}" != "$TOOLCHAIN_VERSION" ]; then
        CFLAGS="$CFLAGS -Wno-deprecated-objc-isa-usage"
        CFLAGS="$CFLAGS -Wno-objc-root-class"
    fi

    CXXFLAGS="$CFLAGS -I$NDK_DIR/sources/cxx-stl/llvm-libc++/libcxx/include"

    LDFLAGS=""
    LDFLAGS="$LDFLAGS -nostdlib"
    LDFLAGS="$LDFLAGS -fPIC"
    LDFLAGS="$LDFLAGS -L$NDK_DIR/$CRYSTAX_SUBDIR/libs/$ABI"
    if [ "${ABI##armeabi}" != "$ABI" ]; then
        LDFLAGS="$LDFLAGS/thumb"
    elif [ "$ABI" = "mips" ]; then
        LDFLAGS="$LDFLAGS/r6"
    fi

    if [ "$ABI" = "armeabi-v7a-hard" ]; then
        LDFLAGS="$LDFLAGS -Wl,--no-warn-mismatch"
    fi

    dump "=== Building libobjc2 for $ABI"
    make -C $BUILDDIR -f $BUILDDIR/Makefile -j$NUM_JOBS \
        CC="$CC $CCFLAGS" \
        CXX="$CXX $CCFLAGS" \
        AR="$AR" \
        CFLAGS="-std=c99 $CFLAGS" \
        CXXFLAGS="-std=c++11 $CXXFLAGS" \
        LDFLAGS="$LDFLAGS" \

    fail_panic "Couldn't build libobjc2 for $ABI"

    dump "=========================== OOKKKKKKKKKKKKKKKKKKKKKKKK"

    if [ -z "$OBJC2_HEADERS_INSTALLED" ]; then
        run rm -Rf $NDK_DIR/$OBJC2_SUBDIR/include
        run mkdir -p $NDK_DIR/$OBJC2_SUBDIR/include
        fail_panic "Can't create directory for headers"
        run cp -r $BUILDDIR/objc $NDK_DIR/$OBJC2_SUBDIR/include/
        fail_panic "Can't install headers"
        OBJC2_HEADERS_INSTALLED=yes
        export OBJC2_HEADERS_INSTALLED
    fi

    run rm -Rf $NDK_DIR/$OBJC2_SUBDIR/libs/$ABI
    run mkdir -p $NDK_DIR/$OBJC2_SUBDIR/libs/$ABI
    fail_panic "Can't create directory for $ABI libraries"

    for f in libobjc.a libobjc.so libobjcxx.so; do
        run cp $BUILDDIR/$f $NDK_DIR/$OBJC2_SUBDIR/libs/$ABI
        fail_panic "Can't install $ABI libraries"
    done
}

OBJC2_HEADERS_INSTALLED=

BUILT_ABIS=""
for ABI in $ABIS; do
    DO_BUILD_PACKAGE="yes"
    if [ -n "$PACKAGE_DIR" ]; then
        PACKAGE_NAME="objc2-libs-$ABI.tar.bz2"
        echo "Look for: $PACKAGE_NAME"
        try_cached_package "$PACKAGE_DIR" "$PACKAGE_NAME" no_exit
        if [ $? = 0 ]; then
            DO_BUILD_PACKAGE="no"
        else
            BUILT_ABIS="$BUILT_ABIS $ABI"
        fi
    fi
    if [ "$DO_BUILD_PACKAGE" = "yes" ]; then
        build_libobjc2_for_abi $ABI "$BUILD_DIR/$ABI" "$OUT_DIR"
    fi
done

# If needed, package files into tarballs
if [ -n "$PACKAGE_DIR" ] ; then
    for ABI in $BUILT_ABIS; do
        FILES=""
        for LIB in libobjc.a libobjc.so libobjcxx.so; do
            FILES="$FILES $OBJC2_SUBDIR/libs/$ABI/$LIB"
        done
        PACKAGE_NAME="objc2-libs-$ABI.tar.bz2"
        PACKAGE="$PACKAGE_DIR/$PACKAGE_NAME"
        log "Packaging: $PACKAGE"
        pack_archive "$PACKAGE" "$NDK_DIR" "$FILES"
        fail_panic "Could not package $ABI objc2 binaries!"
        dump "Packaging: $PACKAGE"
        cache_package "$PACKAGE_DIR" "$PACKAGE_NAME"
    done
fi

if [ -z "$OPTION_BUILD_DIR" ]; then
    log "Cleaning up..."
    rm -rf $BUILD_DIR
else
    log "Don't forget to cleanup: $BUILD_DIR"
fi

log "Done!"
