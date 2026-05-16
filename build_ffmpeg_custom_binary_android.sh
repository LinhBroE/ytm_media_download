#!/bin/bash
echo " ===== BUILD Custom binary FFMPEG 6.0 ANDROID arm64_v8a of x86_64 ===== "
echo "Build script: linh439912"
echo "Date: 12/05/2026"
echo "======================================"
echo " "

# --- MENU Option ---
echo "CHOOSE YOUR DESIRED ARCHITECTURE BUILD FFMPEG "
echo " "
echo "a: Build From arm64-v8a"
echo "b: Build From x86-64 (Emulator)"
echo "c: Build (All)"
echo "d: Setup SDK, NDK,..., install and update dependencies, download Repo and exit!"
echo " "
read -p "Select Option (a/b/c/d): " choice

set -e
ROOT_DIR=$(pwd)

echo "[1/8] install and update dependencies..."
sudo apt update
sudo apt install -y build-essential git python3 wget unzip \
automake autoconf libtool pkg-config gettext gperf \
libc6-i386 lib32stdc++6 lib32z1 groff cmake yasm nasm \
openjdk-17-jdk meson ninja-build

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH

echo "[2/8] Setup Android SDK..."
if [ ! -d "android-sdk" ]; then
    mkdir -p android-sdk/temp
    cd android-sdk/temp
    wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O tools.zip
    unzip tools.zip
    mkdir -p ../cmdline-tools/latest
    cp -r cmdline-tools/* ../cmdline-tools/latest/
    cd $ROOT_DIR
    rm -rf android-sdk/temp
fi

export ANDROID_SDK_ROOT=$ROOT_DIR/android-sdk
export PATH=$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH

yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-33" "build-tools;34.0.0"

echo "[3/8] Setup Android NDK r25c..."
if [ ! -d "android-ndk-r25c" ]; then
    wget https://dl.google.com/android/repository/android-ndk-r25c-linux.zip
    unzip android-ndk-r25c-linux.zip
    rm android-ndk-r25c-linux.zip
fi

export ANDROID_NDK_ROOT=$ROOT_DIR/android-ndk-r25c
export TOOLCHAIN=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64
export API=24

echo "[4/8] Download Sources (FFmpeg, x264, libvpx, Lame, dav1d, Opus)..."
if [ ! -d "ffmpeg-6.0" ]; then
    wget https://ffmpeg.org/releases/ffmpeg-6.0.tar.bz2
    tar -xjvf ffmpeg-6.0.tar.bz2
    rm ffmpeg-6.0.tar.bz2
fi

if [ ! -d "x264" ]; then
    git clone https://code.videolan.org/videolan/x264.git
fi

if [ ! -d "libvpx" ]; then
    git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git
fi

if [ ! -d "lame-3.100" ]; then
    wget https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
    tar -xzvf lame-3.100.tar.gz
    rm lame-3.100.tar.gz
fi

if [ ! -d "dav1d" ]; then
    git clone --depth 1 https://code.videolan.org/videolan/dav1d.git
fi

if [ ! -d "opus" ]; then
    git clone --depth 1 https://gitlab.xiph.org/xiph/opus.git
fi

build_external_libs() {
    ARCH=$1
    TARGET=$2
    PREFIX=$3
    CC=$4
    AR=$5
    ARCH_ABI=$6
    CPU=$7
    STRIP=$8
    
    echo "--- Building x264 for $ARCH ---"
    cd $ROOT_DIR/x264
    make distclean || true
    
    CC="$CC" ./configure \
        --prefix=$PREFIX \
        --host=$TARGET \
        --enable-static \
        --enable-pic \
        --disable-cli \
        --cross-prefix=$TOOLCHAIN/bin/llvm- \
        --sysroot=$TOOLCHAIN/sysroot \
        --extra-cflags="-D__ANDROID_API__=$API" \
        --disable-asm

    make -j$(nproc)
    make install

    echo "--- Building libvpx for $ARCH ---"
    cd $ROOT_DIR/libvpx
    make clean || true
    
    VPX_TARGET=""
    if [ "$ARCH" == "aarch64" ]; then VPX_TARGET="arm64-android-gcc"; else VPX_TARGET="x86_64-android-gcc"; fi

    # We add Toolchain to PATH to let configure find the tools correctly without --sdk-path
    OLD_PATH=$PATH
    export PATH=$TOOLCHAIN/bin:$PATH

    ./configure \
        --prefix=$PREFIX \
        --target=$VPX_TARGET \
        --enable-static \
        --disable-shared \
        --enable-pic \
        --disable-examples \
        --disable-unit-tests \
        --disable-tools \
        --disable-docs

    make -j$(nproc)
    make install
    export PATH=$OLD_PATH

    echo "--- Building LAME for $ARCH ---"
    cd $ROOT_DIR/lame-3.100
    make distclean || true
    ./configure \
        --prefix=$PREFIX \
        --host=$TARGET \
        --enable-static \
        --disable-shared \
        --disable-frontend \
        CC="$CC" \
        AR="$AR" \
        RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
    
    make -j$(nproc)

    mkdir -p $PREFIX/include/lame
    mkdir -p $PREFIX/lib
    cp include/lame.h $PREFIX/include/lame/
    cp libmp3lame/.libs/libmp3lame.a $PREFIX/lib/

    echo "--- Building dav1d for $ARCH ---"
    cd $ROOT_DIR/dav1d
    rm -rf build
    mkdir -p build

    cat > build/android_cross.meson <<EOF
[binaries]
c = '$CC'
cpp = '${CC%clang}clang++'
ar = '$AR'
strip = '$STRIP'
pkg-config = 'pkg-config'

[host_machine]
system = 'android'
cpu_family = '$(echo $ARCH | sed "s/aarch64/aarch64/;s/x86_64/x86_64/")'
cpu = '$CPU'
endian = 'little'
EOF

    meson setup build \
        --prefix=$PREFIX \
        --libdir=lib \
        --buildtype=release \
        --default-library=static \
        -Denable_tests=false \
        -Denable_examples=false \
        -Denable_tools=false \
        --cross-file build/android_cross.meson

    ninja -C build install

    echo "--- Building libopus for $ARCH ---"
    cd $ROOT_DIR/opus
    ./autogen.sh
    ./configure \
        --prefix=$PREFIX \
        --host=$TARGET \
        --enable-static \
        --disable-shared \
        --enable-pic \
        --disable-extra-programs \
        --disable-doc \
        CC="$CC" \
        AR="$AR" \
        RANLIB="$TOOLCHAIN/bin/llvm-ranlib"

    make -j$(nproc)
    make install
    
    cd $ROOT_DIR
}

build_ffmpeg() {
    ARCH=$1       
    CPU=$2        
    TARGET=$3     
    ARCH_ABI=$4    

    echo "--------------------------------------"
    echo "Start build: $ARCH ($CPU)"
    echo "--------------------------------------"

    CC=$TOOLCHAIN/bin/${TARGET}${API}-clang
    AS=$CC
    AR=$TOOLCHAIN/bin/llvm-ar
    NM=$TOOLCHAIN/bin/llvm-nm
    STRIP=$TOOLCHAIN/bin/llvm-strip
    SYSROOT_LIB=$TOOLCHAIN/sysroot/usr/lib/$TARGET/$API
    
    PREFIX_EXT=$ROOT_DIR/external_libs/$ARCH
    mkdir -p $PREFIX_EXT

    build_external_libs "$ARCH" "$TARGET" "$PREFIX_EXT" "$CC" "$AR" "$ARCH_ABI" "$CPU" "$STRIP"

    export PKG_CONFIG_PATH=$PREFIX_EXT/lib/pkgconfig

    cd $ROOT_DIR/ffmpeg-6.0
    make distclean || true

    ./configure \
      --prefix=$ROOT_DIR/ffmpeg_android_bin/$ARCH \
      --target-os=android \
      --arch=$ARCH \
      --cpu=$CPU \
      --cc=$CC \
      --ar=$AR \
      --as=$AS \
      --nm=$NM \
      --strip=$STRIP \
      --extra-cflags="-I$PREFIX_EXT/include -O3 -fPIC" \
      --extra-ldflags="-L$PREFIX_EXT/lib -L$SYSROOT_LIB -landroid -llog -ljnigraphics -lz -Wl,--no-undefined" \
      --pkg-config-flags="--static" \
      --disable-shared \
      --disable-vulkan \
      --disable-everything \
      --disable-htmlpages \
      --disable-podpages \
      --disable-network \
      --disable-doc \
      --disable-manpages \
      --disable-txtpages \
      --disable-ffplay \
      --disable-ffprobe \
      --enable-cross-compile \
      --enable-ffmpeg \
      --enable-static \
      --enable-pic \
      --enable-mediacodec \
      --enable-jni \
      --enable-gpl \
      --enable-nonfree \
      --enable-libx264 \
      --enable-libvpx \
      --enable-libmp3lame \
      --enable-libdav1d \
      --enable-libopus \
      --enable-demuxer=mov,matroska,webm,webm_dash_manifest,mp3,aac,ogg,opus \
      --enable-parser=h264,av1,vp9,opus,aac \
      --enable-decoder=h264,av1,vp8,vp9,aac,opus,vorbis,libdav1d \
      --enable-encoder=libx264,libvpx_vp9,libmp3lame,libopus,h264_mediacodec,hevc_mediacodec,aac,pcm_s16le \
      --enable-muxer=mp4,mov,matroska,webm,adts,mp3,ipod,wav,opus,ogg \
      --enable-protocol=file \
      --enable-filter=trim,atrim,concat,aresample,scale,format,fps,setpts,crop,null,anull,testsrc \
      --enable-indev=lavfi

    make -j$(nproc)
    make install

    mkdir -p $ROOT_DIR/output_bin
    cp ffmpeg $ROOT_DIR/output_bin/ffmpeg_$ARCH
    
    cd $ROOT_DIR
    echo "=> Done build: $ARCH"
}

case $choice in
    a|A)
        build_ffmpeg "aarch64" "armv8-a" "aarch64-linux-android" "arm64-v8a"
        ;;
    b|B)
        build_ffmpeg "x86_64" "x86-64" "x86_64-linux-android" "x86_64"
        ;;
    c|C)
        build_ffmpeg "aarch64" "armv8-a" "aarch64-linux-android" "arm64-v8a"
        build_ffmpeg "x86_64" "x86-64" "x86_64-linux-android" "x86_64"
        ;;
    d|d)
        echo "Setup...   Done"
        exit 1
        ;;
    *)
        echo "Null option!."
        exit 1
        ;;
esac

echo "======================================"
echo "Success File output: $ROOT_DIR/output_bin/"
ls -lh $ROOT_DIR/output_bin/
echo "======================================"