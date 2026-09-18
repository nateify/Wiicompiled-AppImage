#!/bin/sh

set -eu

ARCH="$(uname -m)"
BUILD_DIR="/tmp/wiicompiled-build"
VERSION="$(cat ~/version)"

case "$ARCH" in
x86_64) APPIMAGE_ARCH="x86_64" ;;
aarch64) APPIMAGE_ARCH="aarch64" ;;
*)
    echo "Unsupported arch: $ARCH" >&2
    exit 1
    ;;
esac

export ARCH VERSION
export APPDIR="${PWD}/AppDir"
export OUTPATH="${PWD}/dist"
export OUTNAME="WiiCompiled-Setup-${VERSION}-${ARCH}.AppImage"
export ADD_HOOKS="self-updater.hook"
export UPINFO="gh-releases-zsync|${GITHUB_REPOSITORY%/*}|${GITHUB_REPOSITORY#*/}|latest|*$ARCH.AppImage.zsync"
export DEPLOY_VULKAN=1
export DEPLOY_OPENGL=1
export ANYLINUX_LIB=1
export STRIP=1

rm -rf "$APPDIR"
mkdir -p "$APPDIR/bin" \
    "$APPDIR/usr/toolchain" \
    "$APPDIR/workspace/Launcher" \
    "$APPDIR/native-prebuilt" \
    "$APPDIR/sysroot/usr/include" \
    "$APPDIR/sysroot/usr/lib" \
    "$OUTPATH"

echo "Staging binaries and toolchains into AppDir..."
cp "$BUILD_DIR/out-setup/WiiCompiled.Setup.Linux" "$APPDIR/bin/wiicompiled-setup"
cp "$BUILD_DIR/out-translator/Translator.Cli" "$APPDIR/bin/translator-cli"
cp "$BUILD_DIR/nodtool" "$APPDIR/bin/nodtool"
chmod +x "$APPDIR/bin/"*

cp -a "$BUILD_DIR/Launcher/artifacts/portable-tools/toolchain-${APPIMAGE_ARCH}"/. "$APPDIR/usr/toolchain/"

cp -a "$BUILD_DIR/Launcher/artifacts/native-prebuilt-${APPIMAGE_ARCH}"/. "$APPDIR/native-prebuilt/"

for dir in runtime aurora-main projects; do
    cp -r "$BUILD_DIR/$dir" "$APPDIR/workspace/$dir"
done
find "$APPDIR/workspace/aurora-main/extern" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
rm -rf "$APPDIR/workspace/runtime/build"
cp "$BUILD_DIR/Launcher/local-build.sh" "$APPDIR/workspace/Launcher/local-build.sh"
echo "$VERSION" >"$APPDIR/workspace/.bundle-version"

if [ -d /usr/include ]; then
    cp -a /usr/include/. "$APPDIR/sysroot/usr/include/"
fi
for crt in /usr/lib/crt*.o /usr/lib/libc.so /usr/lib/libm.so /usr/lib/libpthread.so; do
    [ -e "$crt" ] && cp -a "$crt" "$APPDIR/sysroot/usr/lib/" || true
done

echo "Creating desktop entry and icon..."
export DESKTOP="${PWD}/wiicompiled-setup.png"
export ICON="${PWD}/wiicompiled-setup.png"
cat >"$APPDIR/wiicompiled-setup.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=WiiCompiled Setup
Comment=A native PC port of Mario Kart Wii, made with static recompilation.
Exec=wiicompiled-setup
Icon=wiicompiled-setup
Categories=Game;
Terminal=true
EOF

cat >"$APPDIR/AppRun.sh" <<'APPRUN'
#!/bin/bash
set -euo pipefail
HERE="${SHARUN_DIR:-$(dirname "$(readlink -f "$0")")}"
CACHE="${XDG_DATA_HOME:-$HOME/.local/share}/WiiCompiled/workspace"
mkdir -p "$CACHE"

if [ ! -f "$CACHE/.bundle-version" ] || \
   [ "$(cat "$HERE/workspace/.bundle-version" 2>/dev/null)" != "$(cat "$CACHE/.bundle-version" 2>/dev/null)" ]; then
    mkdir -p "$CACHE/Launcher"
    for dir in runtime aurora-main projects; do
        rm -rf "$CACHE/$dir"
        cp -r "$HERE/workspace/$dir" "$CACHE/$dir"
    done
    cp "$HERE/workspace/Launcher/local-build.sh" "$CACHE/Launcher/local-build.sh"
    cp "$HERE/workspace/.bundle-version" "$CACHE/.bundle-version"
fi

# Stable symlinks so CMake doesn't bake ephemeral /tmp/.mount_XXXX paths into build.ninja
[ -L "$CACHE/toolchain" ] || rm -rf "$CACHE/toolchain"
[ -L "$CACHE/native-prebuilt" ] || rm -rf "$CACHE/native-prebuilt"
ln -sfn "$HERE/usr/toolchain" "$CACHE/toolchain"
ln -sfn "$HERE/native-prebuilt" "$CACHE/native-prebuilt"

extra_args=()
if [ -d "$HERE/sysroot" ]; then
    [ -L "$CACHE/sysroot" ] || rm -rf "$CACHE/sysroot"
    ln -sfn "$HERE/sysroot" "$CACHE/sysroot"
    extra_args+=(--sysroot "$CACHE/sysroot")
fi

exec "$HERE/bin/wiicompiled-setup" --workspace "$CACHE" \
    --translator-bin "$HERE/bin/translator-cli" \
    --disc-tool-bin "$HERE/bin/nodtool" \
    --cc "$CACHE/toolchain/bin/clang" \
    --cxx "$CACHE/toolchain/bin/clang++" \
    --fuse-ld lld \
    --cmake "$CACHE/toolchain/bin/cmake" \
    --ninja "$CACHE/toolchain/bin/ninja" \
    --native-prebuilt-dir "$CACHE/native-prebuilt" \
    "${extra_args[@]}" "$@"
APPRUN
chmod +x "$APPDIR/AppRun.sh"

echo "Deploying dependencies with quick-sharun..."
quick-sharun \
    "$APPDIR/bin/wiicompiled-setup" \
    "$APPDIR/bin/translator-cli" \
    "$APPDIR/bin/nodtool" \
    "$APPDIR/usr/toolchain/bin/clang-22" \
    "$APPDIR/usr/toolchain/bin/lld" \
    "$APPDIR/usr/toolchain/bin/llvm-ar" \
    "$APPDIR/usr/toolchain/bin/cmake" \
    "$APPDIR/usr/toolchain/bin/ninja" \
    /usr/bin/bash \
    /usr/bin/tar \
    /usr/bin/sha256sum \
    /usr/bin/nproc

# Re-establish toolchain symlinks inside the package
(
    cd "$APPDIR/usr/toolchain/bin"
    ln -sf clang-22 clang
    ln -sf clang clang++
    ln -sf lld ld.lld
    ln -sf llvm-ar llvm-ranlib
)

echo "Generating AppImage via quick-sharun..."
quick-sharun --make-appimage

echo "Testing AppImage..."
quick-sharun --simple-test "$OUTPATH"/*.AppImage --version

echo "Built successfully: $(ls "$OUTPATH"/*.AppImage)"
