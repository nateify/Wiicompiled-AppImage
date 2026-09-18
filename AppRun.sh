#!/bin/bash
set -euo pipefail
HERE="${SHARUN_DIR:-$(dirname "$(readlink -f "$0")")}"
CACHE="${XDG_DATA_HOME:-$HOME/.local/share}/WiiCompiled/workspace"
mkdir -p "$CACHE"

unset LD_PRELOAD
unset LD_LIBRARY_PATH

export PATH="$HERE/bin:$CACHE/toolchain/bin:$PATH"

if [ ! -f "$CACHE/.bundle-version" ] ||
    [ "$(cat "$HERE/workspace/.bundle-version" 2>/dev/null)" != "$(cat "$CACHE/.bundle-version" 2>/dev/null)" ]; then
    mkdir -p "$CACHE/Launcher"
    for dir in runtime aurora-main projects; do
        rm -rf "${CACHE:?}/$dir"
        cp -r "$HERE/workspace/$dir" "$CACHE/$dir"
    done
    cp "$HERE/workspace/Launcher/local-build.sh" "$CACHE/Launcher/local-build.sh"
    cp "$HERE/workspace/.bundle-version" "$CACHE/.bundle-version"
fi

# Stable symlinks to prevent CMake/Ninja command line drift
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
