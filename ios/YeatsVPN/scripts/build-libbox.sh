#!/bin/bash
set -euo pipefail

# Build Libbox.xcframework from sing-box source.
#
# Prerequisites:
#   brew install go
#   go install golang.org/x/mobile/cmd/gomobile@latest
#   go install golang.org/x/mobile/cmd/gobind@latest
#   gomobile init
#
# Usage:
#   cd ios/YeatsVPN
#   ./scripts/build-libbox.sh [version]
#   # e.g. ./scripts/build-libbox.sh v1.13.13

SINGBOX_VERSION="${1:-v1.13.13}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build/sing-box"
OUTPUT="$PROJECT_DIR/Libbox.xcframework"

echo "==> Building Libbox.xcframework (sing-box $SINGBOX_VERSION)"

# Check prerequisites
if ! command -v go &>/dev/null; then
    echo ""
    echo "ERROR: Go is not installed."
    echo ""
    echo "Install it with:"
    echo "  brew install go"
    echo ""
    echo "Then re-run this script."
    exit 1
fi

echo "==> Go version: $(go version)"

# Install gomobile if needed
if ! command -v gomobile &>/dev/null; then
    echo "==> Installing gomobile..."
    go install golang.org/x/mobile/cmd/gomobile@latest
    go install golang.org/x/mobile/cmd/gobind@latest
    export PATH="$PATH:$(go env GOPATH)/bin"
    gomobile init
fi

echo "==> gomobile: $(which gomobile)"

# Clone sing-box if not present
if [ ! -d "$BUILD_DIR" ]; then
    echo "==> Cloning sing-box..."
    git clone --depth 1 --branch "$SINGBOX_VERSION" \
        https://github.com/SagerNet/sing-box.git "$BUILD_DIR"
else
    echo "==> Using existing sing-box at $BUILD_DIR"
    cd "$BUILD_DIR"
    git fetch --tags
    git checkout "$SINGBOX_VERSION" 2>/dev/null || true
fi

cd "$BUILD_DIR"

# Build the iOS xcframework
echo "==> Building xcframework for iOS (arm64)..."
rm -rf "$OUTPUT"

gomobile bind -v \
    -target ios \
    -trimpath \
    -ldflags "-s -w -X github.com/sagernet/sing-box/constant.Version=$SINGBOX_VERSION" \
    -tags "with_quic,with_utls,with_reality_server,with_clash_api,with_gvisor" \
    -o "$OUTPUT" \
    ./experimental/libbox

echo ""
echo "==> Done! Libbox.xcframework built at:"
echo "    $OUTPUT"
echo ""
echo "Next steps:"
echo "  1. Open YeatsVPN.xcodeproj in Xcode"
echo "  2. Select the PacketTunnel target"
echo "  3. Go to General > Frameworks, Libraries, and Embedded Content"
echo "  4. Click + and add Libbox.xcframework"
echo "  5. Make sure it's set to 'Embed & Sign'"
echo "  6. Build and run"
