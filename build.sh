#!/bin/bash -e

set -o pipefail

SELF_DIR="$(dirname "$(realpath "${0}")")"

source /etc/os-release
dpkg --add-architecture i386

if [ x"${USE_CHINA_MIRROR}" = x1 ]; then
    cat >/etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: https://mirrors.ustc.edu.cn/ubuntu
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: https://mirrors.ustc.edu.cn/ubuntu
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
fi

export DEBIAN_FRONTEND=noninteractive

rm -f /etc/apt/apt.conf.d/*
echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' >/etc/apt/apt.conf.d/01keep-debs
echo -e 'Acquire::https::Verify-Peer "false";\nAcquire::https::Verify-Host "false";' >/etc/apt/apt.conf.d/99-trust-https

apt update
apt install -y g++ \
	make \
	libtool \
	jq \
	pkgconf \
	file \
	tcl \
	autoconf \
	automake \
	autopoint \
	patch \
	wget \
	unzip \
	ninja-build \
	cmake \
	nasm \
	meson \
	git-core

BUILD_ARCH="$(gcc -dumpmachine)"
TARGET_ARCH="${CROSS_HOST%%-*}"
TARGET_HOST="${CROSS_HOST#*-}"

case "${TARGET_HOST}" in
*"mingw"*)
	TARGET_HOST=Windows
	TARGET_OS=mingw32
	rm -fr "${CROSS_ROOT}"
	hash -r
	apt update
	apt install -y wine mingw-w64
	export WINEPREFIX=/tmp/
	RUNNER_CHECKER="wine"
	export CC="${CROSS_HOST}-gcc"
	export CXX="${CROSS_HOST}-g++"
	;;
*"darwin"*)
	TARGET_HOST=Darwin
	TARGET_OS=darwin
	export OSXCROSS_PKG_CONFIG_USE_NATIVE_VARIABLES=1
	if [ x"${TARGET_ARCH}" == "xx86_64" ]; then
		export CC="o64-clang"
		export CXX="o64-clang++"
	elif [ x"${TARGET_ARCH}" == "xaarch64" ]; then
		export CC="oa64-clang"
		export CXX="oa64-clang++"
	fi
	export LD="${CROSS_HOST}-ld"
	export AR="${CROSS_HOST}-ar"
	export NM="${CROSS_HOST}-nm"
	export AS="${CROSS_HOST}-as"
	export STRIP="${CROSS_HOST}-strip"
	export RANLIB="${CROSS_HOST}-ranlib"
	;;
*)
	TARGET_HOST=Linux
	TARGET_OS=linux
	apt install -y "qemu-user-static"
	RUNNER_CHECKER="qemu-${TARGET_ARCH}-static"
	export CC="${CROSS_HOST}-gcc"
	export CXX="${CROSS_HOST}-g++"
	;;
esac

export PATH="${CROSS_ROOT}/bin:${PATH}"
export CROSS_PREFIX="${CROSS_ROOT}/${CROSS_HOST}"
export PKG_CONFIG_PATH="${CROSS_PREFIX}/lib64/pkgconfig:${CROSS_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"
export LDFLAGS="-L${CROSS_PREFIX}/lib -I${CROSS_PREFIX}/include"

if [ x"${TARGET_HOST}" != "xDarwin" ]; then
	export LDFLAGS="-L${CROSS_PREFIX}/lib64 -L${CROSS_PREFIX}/lib -I${CROSS_PREFIX}/include -s -static --static"
fi

export DOWNLOADS_DIR="${SELF_DIR}/downloads"
mkdir -p "${DOWNLOADS_DIR}"
export SRC_DIR="${SELF_DIR}/src"

prepare_lame() {
	lame_tag="3.100"
	lame_latest_url="https://sourceforge.net/projects/lame/files/lame/$lame_tag/lame-$lame_tag.tar.gz/download?use_mirror=gigenet"
	if [ ! -f "${DOWNLOADS_DIR}/lame-${lame_tag}.tar.gz" ]; then
		wget -cT10 -O "${DOWNLOADS_DIR}/lame-${lame_tag}.tar.gz.part" "${lame_latest_url}"
		mv -fv "${DOWNLOADS_DIR}/lame-${lame_tag}.tar.gz.part" "${DOWNLOADS_DIR}/lame-${lame_tag}.tar.gz"
	fi
	mkdir -p "${SRC_DIR}/lame-${lame_tag}"
	tar -zxvf "${DOWNLOADS_DIR}/lame-${lame_tag}.tar.gz" --strip-components=1 -C "${SRC_DIR}/lame-${lame_tag}"
	cd "${SRC_DIR}/lame-${lame_tag}"
	./configure --prefix="${CROSS_PREFIX}" --host="${CROSS_HOST}" --disable-shared --enable-static
	make -j
	make install
}

prepare_libx264() {
	libx264_tag="master"
	libx264_latest_url="https://code.videolan.org/videolan/x264/-/archive/master/x264-$libx264_tag.tar.bz2"
	if [ ! -f "${DOWNLOADS_DIR}/libx264-${libx264_tag}.tar.bz2" ]; then
		wget -cT10 -O "${DOWNLOADS_DIR}/libx264-${libx264_tag}.tar.bz2.part" "${libx264_latest_url}"
		mv -fv "${DOWNLOADS_DIR}/libx264-${libx264_tag}.tar.bz2.part" "${DOWNLOADS_DIR}/libx264-${libx264_tag}.tar.bz2"
	fi
	mkdir -p "${SRC_DIR}/libx264-${libx264_tag}"
	tar -jxvf "${DOWNLOADS_DIR}/libx264-${libx264_tag}.tar.bz2" --strip-components=1 -C "${SRC_DIR}/libx264-${libx264_tag}"
	cd "${SRC_DIR}/libx264-${libx264_tag}"
	./configure --prefix="${CROSS_PREFIX}" --host="${CROSS_HOST}" --cross-prefix="${CROSS_HOST}-" --disable-asm --enable-static --disable-opencl --enable-pic
	make -j
	make install
}

prepare_libx265() {
	libx265_tag="3.5"
	libx265_latest_url="https://bitbucket.org/multicoreware/x265_git/downloads/x265_${libx265_tag}.tar.gz"
	if [ ! -f "${DOWNLOADS_DIR}/libx265-${libx265_tag}.tar.gz" ]; then
		wget -cT10 -O "${DOWNLOADS_DIR}/libx265-${libx265_tag}.tar.gz.part" "${libx265_latest_url}"
		mv -fv "${DOWNLOADS_DIR}/libx265-${libx265_tag}.tar.gz.part" "${DOWNLOADS_DIR}/libx265-${libx265_tag}.tar.gz"
	fi
	mkdir -p "${SRC_DIR}/libx265-${libx265_tag}"
	tar -zxvf "${DOWNLOADS_DIR}/libx265-${libx265_tag}.tar.gz" --strip-components=1 -C "${SRC_DIR}/libx265-${libx265_tag}"
	cd "${SRC_DIR}/libx265-${libx265_tag}/build/linux"
	find . -mindepth 1 ! -name 'make-Makefiles.bash' -and ! -name 'multilib.sh' -exec rm -rf {} +
	if [ x"${TARGET_HOST}" == xWindows ]; then
		cmake -G "Ninja" ../../source \
			-DEXPORT_C_API=ON \
			-DENABLE_SHARED=OFF \
			-DENABLE_LIBNUMA=OFF \
			-DSTATIC_LINK_CRT=ON \
			-DENABLE_CLI=OFF \
			-DCMAKE_SYSTEM_NAME="${TARGET_HOST}" \
			-DCMAKE_INSTALL_PREFIX="${CROSS_PREFIX}" \
			-DCMAKE_C_COMPILER="${CC}" \
			-DCMAKE_CXX_COMPILER="${CXX}" \
			-DCMAKE_SYSTEM_PROCESSOR="${TARGET_ARCH}" \
			-DCMAKE_RC_COMPILER="${CROSS_HOST}-windres" \
			-DCMAKE_CXX_FLAGS="-static-libgcc -static-libstdc++ -static -O3 -s" \
			-DCMAKE_C_FLAGS="-static-libgcc -static-libstdc++ -static -O3 -s" \
			-DCMAKE_BUILD_TYPE=Release
		sed -i 's/-lx265/-lx265 -lstdc++ -lgcc -lgcc -static/g' x265.pc
	elif [ x"${TARGET_HOST}" == xDarwin ]; then
		rm -rf crosscompile.cmake
		if [ x"${TARGET_ARCH}" == "xaarch64" ]; then
			echo "set(CROSS_COMPILE_ARM 1)" >>crosscompile.cmake
		fi
		echo "set(CMAKE_SYSTEM_NAME ${TARGET_HOST})" >>crosscompile.cmake
		echo "set(CMAKE_SYSTEM_PROCESSOR ${TARGET_ARCH})" >>crosscompile.cmake
		echo "set(CMAKE_C_COMPILER ${CC})" >>crosscompile.cmake
		echo "set(CMAKE_CXX_COMPILER ${CXX})" >>crosscompile.cmake
		echo "set(CMAKE_AR ${AR})" >>crosscompile.cmake
		echo "set(CMAKE_RANLIB ${RANLIB})" >>crosscompile.cmake
		cmake -DCMAKE_TOOLCHAIN_FILE="crosscompile.cmake" \
			-G "Ninja" ../../source \
			-DEXPORT_C_API=ON \
			-DCMAKE_VERBOSE_MAKEFILE=ON \
			-DENABLE_SHARED=OFF \
			-DENABLE_LIBNUMA=OFF \
			-DENABLE_ASSEMBLY=OFF \
			-DENABLE_CLI=OFF \
			-DCMAKE_INSTALL_PREFIX="${CROSS_PREFIX}" \
			-DCMAKE_INSTALL_NAME_TOOL="${CROSS_HOST}-install_name_tool" \
			-DCMAKE_BUILD_TYPE=Release
	else
		cmake -G "Ninja" ../../source \
			-DENABLE_SHARED=OFF \
			-DENABLE_LIBNUMA=OFF \
			-DENABLE_CLI=OFF \
			-DCMAKE_SYSTEM_NAME="${TARGET_HOST}" \
			-DCMAKE_INSTALL_PREFIX="${CROSS_PREFIX}" \
			-DCMAKE_C_COMPILER="${CROSS_HOST}-gcc" \
			-DCMAKE_CXX_COMPILER="${CROSS_HOST}-g++" \
			-DCMAKE_SYSTEM_PROCESSOR="${TARGET_ARCH}" \
			-DCMAKE_BUILD_TYPE=Release
		if [ x"${TARGET_ARCH}" == "xaarch64" ]; then
			sed -i 's/-lgcc/-lgcc -lstdc++/g' x265.pc
		else
			sed -i 's/-lgcc_s/-lgcc_eh/g' x265.pc
		fi
	fi
	ninja
	ninja install
}

prepare_dav1d() {
	dav1d_tag="1.3.0"
	dav1d_latest_url="https://code.videolan.org/videolan/dav1d/-/archive/${dav1d_tag}/dav1d-${dav1d_tag}.tar.gz"
	if [ ! -f "${DOWNLOADS_DIR}/dav1d-${dav1d_tag}.tar.gz" ]; then
		wget -cT10 -O "${DOWNLOADS_DIR}/dav1d-${dav1d_tag}.tar.gz.part" "${dav1d_latest_url}"
		mv -fv "${DOWNLOADS_DIR}/dav1d-${dav1d_tag}.tar.gz.part" "${DOWNLOADS_DIR}/dav1d-${dav1d_tag}.tar.gz"
	fi
	mkdir -p "${SRC_DIR}/dav1d-${dav1d_tag}"
	tar -zxvf "${DOWNLOADS_DIR}/dav1d-${dav1d_tag}.tar.gz" --strip-components=1 -C "${SRC_DIR}/dav1d-${dav1d_tag}"
	cd "${SRC_DIR}/dav1d-${dav1d_tag}"
	rm -rf "${CROSS_HOST}.txt"
	if [ x"${TARGET_HOST}" == xDarwin ]; then
		echo "[binaries]" >>"${CROSS_HOST}.txt"
		echo "c = '${CC}'" >>"${CROSS_HOST}.txt"
		echo "cpp = '${CXX}'" >>"${CROSS_HOST}.txt"
		echo "strip = '${CROSS_HOST}-strip'" >>"${CROSS_HOST}.txt"
		echo "ar = '${CROSS_HOST}-ar'" >>"${CROSS_HOST}.txt"
		echo "ld = '${CROSS_HOST}-ld'" >>"${CROSS_HOST}.txt"
		echo "[host_machine]" >>"${CROSS_HOST}.txt"
		echo "system = '${TARGET_OS,,}'" >>"${CROSS_HOST}.txt"
		echo "cpu_family = '${TARGET_ARCH}'" >>"${CROSS_HOST}.txt"
		echo "cpu = '${TARGET_ARCH}'" >>"${CROSS_HOST}.txt"
		echo "endian = 'little'" >>"${CROSS_HOST}.txt"
	elif [ x"${TARGET_HOST}" == xWindows ]; then
		meson setup \
			--buildtype=release \
			-Denable_tools=false \
			-Denable_tests=false \
			--default-library=static \
			./build \
			--prefix "${CROSS_PREFIX}" \
			--libdir="$CROSS_PREFIX/lib" \
			--cross-file "package/crossfiles/${CROSS_HOST}.meson"
	else
		echo "[binaries]" >>"${CROSS_HOST}.txt"
		echo "c = '${CROSS_HOST}-gcc'" >>"${CROSS_HOST}.txt"
		echo "cpp = '${CROSS_HOST}-g++'" >>"${CROSS_HOST}.txt"
		echo "strip = '${CROSS_HOST}-strip'" >>"${CROSS_HOST}.txt"
		echo "ar = '${CROSS_HOST}-ar'" >>"${CROSS_HOST}.txt"
		echo "ld = '${CROSS_HOST}-ld'" >>"${CROSS_HOST}.txt"
		echo "[host_machine]" >>"${CROSS_HOST}.txt"
		echo "system = '${TARGET_OS,,}'" >>"${CROSS_HOST}.txt"
		echo "cpu_family = '${TARGET_ARCH}'" >>"${CROSS_HOST}.txt"
		echo "cpu = '${TARGET_ARCH}'" >>"${CROSS_HOST}.txt"
		echo "endian = 'little'" >>"${CROSS_HOST}.txt"
	fi
	meson setup \
		--buildtype=release \
		-Denable_tools=false \
		-Denable_tests=false \
		--default-library=static \
		./build \
		--prefix "${CROSS_PREFIX}" \
		--libdir "${CROSS_PREFIX}/lib" \
		--cross-file "${CROSS_HOST}.txt"
	cd build
	ninja
	ninja install
}

build_ffmpeg() {
	ffmpeg_tag="6.1.2"
	ffmpeg_latest_url="https://www.ffmpeg.org/releases/ffmpeg-${ffmpeg_tag}.tar.gz"
	if [ ! -f "${DOWNLOADS_DIR}/ffmpeg-${ffmpeg_tag}.tar.gz" ]; then
		wget -cT10 -O "${DOWNLOADS_DIR}/ffmpeg-${ffmpeg_tag}.tar.gz.part" "${ffmpeg_latest_url}"
		mv -fv "${DOWNLOADS_DIR}/ffmpeg-${ffmpeg_tag}.tar.gz.part" "${DOWNLOADS_DIR}/ffmpeg-${ffmpeg_tag}.tar.gz"
	fi
	mkdir -p "${SRC_DIR}/ffmpeg-${ffmpeg_tag}"
	tar -zxf "${DOWNLOADS_DIR}/ffmpeg-${ffmpeg_tag}.tar.gz" --strip-components=1 -C "${SRC_DIR}/ffmpeg-${ffmpeg_tag}"
	cd "${SRC_DIR}/ffmpeg-${ffmpeg_tag}"
	FFMPEG_CONFIG=()
	if [ x"${TARGET_HOST}" == xDarwin ]; then
		SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
		EXTRA_LDFLAGS="-L$CROSS_PREFIX/lib -isysroot $SDKROOT"
		EXTRA_CFLAGS="-I$CROSS_PREFIX/include -isysroot $SDKROOT"
		FFMPEG_CONFIG+=("--disable-videotoolbox")
		FFMPEG_CONFIG+=("--pkg-config="${CROSS_HOST}-pkg-config"")
		FFMPEG_CONFIG+=("--strip="${CROSS_HOST}-strip"")
		FFMPEG_CONFIG+=("--cross-prefix="${CROSS_HOST}-"")
		FFMPEG_CONFIG+=("--disable-stripping")
	else
		EXTRA_CFLAGS="-I{$CROSS_PREFIX}/include"
		EXTRA_LDFLAGS="-L${CROSS_PREFIX}/lib"
		FFMPEG_CONFIG+=("--strip="${CROSS_HOST}-strip"")
		FFMPEG_CONFIG+=("--extra-ldexeflags=-static")
	fi

	./configure "${FFMPEG_CONFIG[@]}" \
		--disable-debug \
		--disable-network \
		--disable-autodetect \
		--enable-small \
		--disable-iconv \
		--disable-parsers \
		--prefix="${CROSS_PREFIX}" \
		--pkg-config-flags="--static" \
		--extra-cflags="${EXTRA_CFLAGS}" \
		--extra-ldflags="${EXTRA_LDFLAGS}" \
		--extra-libs="-lpthread -lm" \
		--cc="${CC}" \
		--cxx="${CXX}" \
		--arch="${TARGET_ARCH}" \
		--target-os="${TARGET_OS}" \
		--enable-cross-compile \
		--enable-pic \
		--enable-gpl \
		--enable-version3 \
		--enable-static \
		--disable-muxers \
		--enable-muxer=mp4,mp3,flv,adts,flac,image2 \
		--disable-demuxers \
		--enable-demuxer=mov,mp3,flv,aac,flac \
		--disable-encoders \
		--enable-encoder=libx264,libx265,aac,av1,libmp3lame,flac,mjpeg \
		--disable-decoders \
		--enable-decoder=h264,hevc,aac,av1,mp3,libdav1d,flac \
		--disable-protocols \
		--enable-protocol=file \
		--disable-filters \
		--enable-filter=delogo,aresample,scale \
		--enable-swscale \
		--disable-bsfs \
		--disable-avdevice \
		--disable-shared \
		--disable-doc \
		--enable-libx264 \
		--enable-libx265 \
		--enable-libdav1d \
		--disable-ffplay \
		--disable-ffprobe \
		--enable-libmp3lame
	make -j
	make install
	make distclean
	cp -fv "${CROSS_PREFIX}/bin/"ffmpeg* "${SELF_DIR}"
	cp -fv "${SRC_DIR}/ffmpeg-${ffmpeg_tag}/COPYING.GPLv3" "${SELF_DIR}/LICENSE"
}

prepare_lame
prepare_libx264
prepare_libx265
prepare_dav1d
build_ffmpeg
