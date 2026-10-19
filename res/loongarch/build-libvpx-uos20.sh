#!/usr/bin/env bash
set -euo pipefail

version=1.15.2
archive="libvpx-${version}.tar.gz"
url="https://chromium.googlesource.com/webm/libvpx/+archive/refs/tags/v${version}.tar.gz"
sha256=eed77e19fa03d844048fa71fd91696bdc76e0d2fd303aff79412986af8bdb010

prefix="${1:-$HOME/.local/rustdesk-loongarch}"
work_root="${2:-$HOME/.cache/rustdesk-libvpx}"
source_dir="$work_root/libvpx-${version}-src"
build_dir="$work_root/libvpx-${version}-build"
archive_path="$work_root/$archive"

: "${CC:=/usr/bin/gcc}"
: "${CXX:=/usr/bin/g++}"
: "${AR:=/usr/bin/gcc-ar}"
: "${RANLIB:=/usr/bin/gcc-ranlib}"
: "${NM:=/usr/bin/gcc-nm}"
: "${JOBS:=$(nproc)}"

case "$(uname -m)" in
  loongarch64 | loong64) ;;
  *)
    echo "error: this script must run on LoongArch64" >&2
    exit 1
    ;;
esac

for tool in "$CC" "$CXX" "$AR" "$RANLIB" "$NM" curl sha256sum tar make; do
  command -v "$tool" >/dev/null || {
    echo "error: required tool not found: $tool" >&2
    exit 1
  }
done

for flag in -mlsx -mlasx; do
  if ! printf 'int main(void) { return 0; }\n' |
    "$CC" "$flag" -x c -c -o /dev/null -; then
    echo "error: $CC does not support $flag" >&2
    exit 1
  fi
done

mkdir -p "$work_root" "$source_dir" "$build_dir" "$prefix"
if [[ ! -f "$archive_path" ]]; then
  curl -fL "$url" -o "$archive_path"
fi
printf '%s  %s\n' "$sha256" "$archive_path" | sha256sum -c -

if [[ ! -f "$source_dir/configure" ]]; then
  tar -xzf "$archive_path" -C "$source_dir"
fi

export CC CXX AR RANLIB NM
cd "$build_dir"
if [[ ! -f Makefile ]]; then
  "$source_dir/configure" \
    --target=loongarch64-linux-gcc \
    --prefix="$prefix" \
    --disable-examples \
    --disable-tools \
    --disable-docs \
    --disable-unit-tests \
    --disable-shared \
    --enable-static \
    --enable-pic \
    --enable-runtime-cpu-detect \
    --enable-lsx \
    --enable-lasx
fi

make -j"$JOBS"
make install

grep -E '^#define (VPX_ARCH_LOONGARCH|HAVE_LSX|HAVE_LASX|CONFIG_RUNTIME_CPU_DETECT) ' \
  vpx_config.h
if ! "$NM" "$prefix/lib/libvpx.a" | grep -E '_(lsx|lasx)$' >/dev/null; then
  echo "error: the installed libvpx archive contains no LSX/LASX routines" >&2
  exit 1
fi

cat <<EOF
libvpx ${version} was installed in $prefix

Use it for the RustDesk Linux build with:
  export PKG_CONFIG_PATH="$prefix/lib/pkgconfig\${PKG_CONFIG_PATH:+:\$PKG_CONFIG_PATH}"
  export VPX_STATIC=1
EOF
