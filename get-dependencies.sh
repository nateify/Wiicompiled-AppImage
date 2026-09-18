#!/bin/sh

set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
pacman -Syu --noconfirm --needed \
    base-devel \
    git \
    wget \
    curl \
    dotnet-sdk-8.0 \
    cmake \
    ninja \
    clang \
    llvm \
    lld \
    vulkan-headers \
    libglvnd \
    libpulse \
    alsa-lib \
    libx11 \
    libxext \
    libxrandr \
    libxcursor \
    libxfixes \
    libxi \
    libxss \
    libxtst \
    libxkbcommon \
    libdrm \
    mesa \
    libusb \
    wayland \
    libdecor \
    python

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano

echo "Cloning WiiCompiled upstream repository..."
echo "---------------------------------------------------------------"
BUILD_DIR="/tmp/wiicompiled-build"
rm -rf "$BUILD_DIR"
git clone --recursive https://github.com/patchzyy/Wiicompiled.git "$BUILD_DIR"

cd "$BUILD_DIR"

if [ "${DEVEL_RELEASE-}" = "1" ]; then
    VERSION="$(git rev-parse --short HEAD)"
else
    LATEST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"
    if [ -n "$LATEST_TAG" ]; then
        git checkout "$LATEST_TAG"
        VERSION="${LATEST_TAG#v}"
    else
        VERSION="$(git rev-parse --short HEAD)"
    fi
fi
echo "$VERSION" >~/version

case "$ARCH" in
x86_64)
    DOTNET_RID="linux-x64"
    APPIMAGE_ARCH="x86_64"
    ;;
aarch64)
    DOTNET_RID="linux-arm64"
    APPIMAGE_ARCH="aarch64"
    ;;
*)
    echo "Unsupported arch: $ARCH" >&2
    exit 1
    ;;
esac

echo "Building .NET artifacts and toolchains ($DOTNET_RID)..."
echo "---------------------------------------------------------------"
dotnet publish "$BUILD_DIR/Launcher/WiiCompiled.Setup.Linux" \
    -c Release -r "$DOTNET_RID" --self-contained \
    -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true \
    -o "$BUILD_DIR/out-setup"

dotnet publish "$BUILD_DIR/translator/src/Translator.Cli" \
    -c Release -r "$DOTNET_RID" --self-contained \
    -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true \
    -o "$BUILD_DIR/out-translator"

NODTOOL_BIN="$(dotnet run --project "$BUILD_DIR/Launcher/WiiCompiled.Setup.Common.Cli" -c Release -- --workspace "$BUILD_DIR" | tail -n1)"
cp "$NODTOOL_BIN" "$BUILD_DIR/nodtool"
chmod +x "$BUILD_DIR/nodtool"

bash "$BUILD_DIR/Launcher/prepare-portable-tools.sh" --arch "$APPIMAGE_ARCH"

bash "$BUILD_DIR/Launcher/Prepare-NativePrebuilt.sh" --arch "$APPIMAGE_ARCH"
