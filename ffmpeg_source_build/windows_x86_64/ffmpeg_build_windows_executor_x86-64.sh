#!/bin/bash
echo "Build Ffmpeg custom windows x86_64 - script: linh439912"
echo "Date: 17/05/2026"
echo " "

ROOT_DIR=$(pwd)

set -e # Stop script is Error !

echo "1. sudo update and install dependencies..."
sudo apt update
sudo apt install -y \
  git yasm nasm build-essential pkg-config \
  mingw-w64 yasm nasm tree meson ninja-build \
  binutils-mingw-w64 autoconf automake libtool \
  gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64

x86_64-w64-mingw32-gcc --version # get version


echo " "
echo "2. Claen Build new and dowload repo..."
FFMPEG_VER="6.0"
URL="https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VER.tar.bz2"
FILE="ffmpeg-$FFMPEG_VER.tar.bz2"
rm -rf "$FILE"
rm -rf ffmpeg-$FFMPEG_VER
rm -rf x264
rm -rf libvpx
rm -rf lame-3.100
rm -rf dav1d
rm -rf opus
rm -rf "$ROOT_DIR/lib_build_windows_x86_64"
rm -rf "$ROOT_DIR/ffmpeg_output_build_windows_x86_64"

mkdir -p "$ROOT_DIR/lib_build_windows_x86_64"

echo "3. Set set compiler Windows..."
export CC=x86_64-w64-mingw32-gcc
export CXX=x86_64-w64-mingw32-g++
export AR=x86_64-w64-mingw32-ar
export RANLIB=x86_64-w64-mingw32-ranlib
export LD=x86_64-w64-mingw32-ld
export STRIP=x86_64-w64-mingw32-strip
export WINDRES=x86_64-w64-mingw32-windres

echo "CC = $CC"
echo "CXX = $CXX"
echo "AR = $AR"
echo "RANLIB = $RANLIB"
echo "LD = $LD"
echo "STRIP = $STRIP"
echo "WINDRES = $WINDRES"

echo " "
echo "4. Build libx264 windows x86_64..."
git clone https://code.videolan.org/videolan/x264.git
cd x264
./configure \
  --host=x86_64-w64-mingw32 \
  --cross-prefix=x86_64-w64-mingw32- \
  --enable-static \
  --disable-shared \
  --disable-cli \
  --prefix=$ROOT_DIR/lib_build_windows_x86_64
make -j$(nproc)
make install
cd $ROOT_DIR

echo " "
echo "5. Build libvpx windows x86_64..."
git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git
cd libvpx
./configure \
  --target=x86_64-win64-gcc \
  --enable-static \
  --disable-shared \
  --enable-pic \
  --disable-examples \
  --disable-unit-tests \
  --disable-tools \
  --disable-docs \
  --prefix=$ROOT_DIR/lib_build_windows_x86_64 
make -j$(nproc)
make install
cd $ROOT_DIR

echo " "
echo "6. Build lame-3.100 windows x86_64..."
if [ ! -d "lame-3.100" ]; then
    wget https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
    tar -xzvf lame-3.100.tar.gz
    rm lame-3.100.tar.gz
fi
cd lame-3.100
./configure \
  --host=x86_64-w64-mingw32 \
  --disable-shared \
  --enable-static \
  --prefix=$ROOT_DIR/lib_build_windows_x86_64
make -j$(nproc)
make install
cd $ROOT_DIR

echo " "
echo "7. Build dav1d windows x86_64..."
if [ ! -d "dav1d" ]; then
    git clone --depth 1 https://code.videolan.org/videolan/dav1d.git
fi
cd dav1d
cat > build-win64.txt <<EOF
[binaries]
c = 'x86_64-w64-mingw32-gcc'
ar = 'x86_64-w64-mingw32-ar'
strip = 'x86_64-w64-mingw32-strip'
windres = 'x86_64-w64-mingw32-windres'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
meson setup build \
  --prefix=$ROOT_DIR/lib_build_windows_x86_64 \
  --cross-file build-win64.txt \
  --libdir=lib \
  --buildtype=release \
  --default-library=static \
  -Denable_tests=false \
  -Denable_examples=false \
  -Denable_tools=false

ninja -C build install
cd $ROOT_DIR

echo " "
echo "8. Build opus windows x86_64..."
if [ ! -d "opus" ]; then
    git clone --depth 1 https://gitlab.xiph.org/xiph/opus.git
fi
cd opus
./autogen.sh
./configure \
  --host=x86_64-w64-mingw32 \
  --disable-shared \
  --enable-static \
  --prefix=$ROOT_DIR/lib_build_windows_x86_64
make -j$(nproc)
make install
cd $ROOT_DIR

tree lib_build_windows_x86_64

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
echo "9. build Ffmpeg-$FFMPEG_VER windows x86_64 executor..."

echo "link lib : $ROOT_DIR/lib_build_windows_x86_64"
echo "Lib: libx264, libvpx, lame-3.100, dav1d, opus"

ROOT_DIR=$(pwd)

export PREFIX=$ROOT_DIR/lib_build_windows_x86_64
export CFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"

if [ ! -d "ffmpeg-$FFMPEG_VER" ]; then
    [ ! -f "$FILE" ] && wget "$URL"
    tar -xjf "$FILE"
    rm -f "$FILE"
    ls ffmpeg-$FFMPEG_VER
fi

echo " "
echo "tree lib_build_windows_x86_64"
tree $PREFIX/lib
tree $PREFIX/include

cd ffmpeg-$FFMPEG_VER # cd to ffmpeg dir and setup build
echo " "
echo "Build process ..."
./configure \
      --extra-cflags="-I$PREFIX/include" \
      --extra-ldflags="-L$PREFIX/lib" \
      --disable-x86asm \
      --disable-inline-asm \
      --enable-cross-compile \
      --pkg-config=pkg-config \
      --target-os=mingw32 \
      --arch=x86_64 \
      --cross-prefix=x86_64-w64-mingw32- \
      --prefix=$ROOT_DIR/ffmpeg_output_build_windows_x86_64 \
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
      --enable-ffmpeg \
      --enable-static \
      --enable-pic \
      --enable-gpl \
      --enable-nonfree \
      --enable-libx264 \
      --enable-libvpx \
      --enable-libmp3lame \
      --enable-libdav1d \
      --enable-libopus \
      --enable-demuxer=lavfi,mov,matroska,webm,webm_dash_manifest,mp3,aac,ogg,opus,mp4,avi,flac,m4a,ts,flv,asf,rm,3gp,mpegts \
      --enable-parser=h264,av1,vp9,opus,aac,mp3,flac,ac3,dca,vorbis,hevc,mpeg2video,flv \
      --enable-decoder=h264,av1,vp8,vp9,aac,opus,vorbis,libdav1d,mp3,flac,ac3,eac3,dca,alac,wmalossless,pcm_alaw,pcm_mulaw,hevc,mpeg2video,flv \
      --enable-encoder=libx264,libvpx_vp9,libmp3lame,libopus,aac,pcm_s16le \
      --enable-muxer=mp4,mov,matroska,webm,adts,mp3,ipod,wav,opus,ogg \
      --enable-protocol=file,lavfi \
      --enable-filter=trim,atrim,concat,aresample,scale,format,fps,setpts,crop,null,anull,testsrc,sine,acompressor,volume,amix,aevalsrc,pan,buffer,abuffersink \
      --enable-indev=lavfi

make -j$(nproc)
make install

cd $ROOT_DIR
tree $ROOT_DIR/ffmpeg_output_build_windows_x86_64
echo "Build successfully"