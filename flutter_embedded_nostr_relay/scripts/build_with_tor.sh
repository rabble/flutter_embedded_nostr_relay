#!/bin/bash
# ABOUTME: Build script that compiles the Flutter app with Tor support enabled
# ABOUTME: This script builds the Rust Arti FFI library and includes it in the Flutter build

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Building Flutter Embedded Nostr Relay with Tor support...${NC}"

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_DIR="$PROJECT_ROOT/packages"
ARTI_FFI_DIR="$PACKAGES_DIR/arti_ffi"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required tools
echo -e "${YELLOW}Checking dependencies...${NC}"

if ! command_exists cargo; then
    echo -e "${RED}Error: Rust/Cargo not found. Please install Rust: https://rustup.rs/${NC}"
    exit 1
fi

if ! command_exists flutter; then
    echo -e "${RED}Error: Flutter not found. Please install Flutter: https://flutter.dev/docs/get-started/install${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All dependencies found${NC}"

# Build the Arti FFI library
echo -e "${YELLOW}Building Arti FFI library...${NC}"

if [ ! -d "$ARTI_FFI_DIR" ]; then
    echo -e "${RED}Error: Arti FFI directory not found at $ARTI_FFI_DIR${NC}"
    echo -e "${YELLOW}Creating minimal Arti FFI structure...${NC}"
    
    mkdir -p "$ARTI_FFI_DIR/src"
    
    # Create minimal Cargo.toml
    cat > "$ARTI_FFI_DIR/Cargo.toml" << 'EOF'
[package]
name = "arti_ffi"
version = "0.1.0"
edition = "2021"

[lib]
name = "arti_ffi"
crate-type = ["cdylib"]

[dependencies]
arti = "1.1.0"
arti-client = "0.10.0"
tor-rtcompat = "0.9.0"
libc = "0.2"
serde = "1.0"
serde_json = "1.0"

[profile.release]
lto = true
codegen-units = 1
panic = "abort"
EOF

    # Create the lib.rs we already have
    cp "$PROJECT_ROOT/lib/src/tor/packages/arti_ffi/src/lib.rs" "$ARTI_FFI_DIR/src/" 2>/dev/null || true
fi

cd "$ARTI_FFI_DIR"

# Build for the current platform
echo -e "${YELLOW}Building for current platform...${NC}"
cargo build --release

# Copy the built library to the appropriate location
LIB_DIR="$PROJECT_ROOT/lib/tor_libs"
mkdir -p "$LIB_DIR"

# Determine the library extension based on the platform
case "$(uname)" in
    Darwin)
        LIB_EXT="dylib"
        TARGET_PLATFORM="macos"
        ;;
    Linux)
        LIB_EXT="so"
        TARGET_PLATFORM="linux"
        ;;
    MINGW*|MSYS*|CYGWIN*)
        LIB_EXT="dll"
        TARGET_PLATFORM="windows"
        ;;
    *)
        echo -e "${RED}Unsupported platform: $(uname)${NC}"
        exit 1
        ;;
esac

BUILT_LIB="target/release/libarti_ffi.$LIB_EXT"
if [ ! -f "$BUILT_LIB" ]; then
    echo -e "${RED}Error: Built library not found at $BUILT_LIB${NC}"
    exit 1
fi

# Copy the library
cp "$BUILT_LIB" "$LIB_DIR/"
echo -e "${GREEN}✓ Arti FFI library built and copied to $LIB_DIR${NC}"

# Return to project root
cd "$PROJECT_ROOT"

# Get dependencies
echo -e "${YELLOW}Getting Flutter dependencies...${NC}"
flutter pub get

# Run tests to ensure everything is working
echo -e "${YELLOW}Running Tor tests...${NC}"
dart test test/unit/tor/ --reporter=compact

# Build the Flutter app
echo -e "${YELLOW}Building Flutter app with Tor support...${NC}"

# Set environment variable to indicate Tor support is enabled
export FLUTTER_TOR_ENABLED=true

# Build based on specified target or default to all
TARGET="${1:-all}"

case "$TARGET" in
    android)
        echo -e "${YELLOW}Building for Android...${NC}"
        flutter build apk --release
        echo -e "${GREEN}✓ Android APK built successfully${NC}"
        ;;
    ios)
        echo -e "${YELLOW}Building for iOS...${NC}"
        flutter build ios --release
        echo -e "${GREEN}✓ iOS app built successfully${NC}"
        ;;
    linux)
        echo -e "${YELLOW}Building for Linux...${NC}"
        flutter build linux --release
        echo -e "${GREEN}✓ Linux app built successfully${NC}"
        ;;
    macos)
        echo -e "${YELLOW}Building for macOS...${NC}"
        flutter build macos --release
        echo -e "${GREEN}✓ macOS app built successfully${NC}"
        ;;
    windows)
        echo -e "${YELLOW}Building for Windows...${NC}"
        flutter build windows --release
        echo -e "${GREEN}✓ Windows app built successfully${NC}"
        ;;
    web)
        echo -e "${YELLOW}Note: Tor support is not available for web builds${NC}"
        flutter build web --release
        echo -e "${GREEN}✓ Web app built successfully (without Tor)${NC}"
        ;;
    all)
        echo -e "${YELLOW}Building for all supported platforms...${NC}"
        
        # Build for current platform based on OS
        case "$(uname)" in
            Darwin)
                flutter build macos --release
                echo -e "${GREEN}✓ macOS app built successfully${NC}"
                ;;
            Linux)
                flutter build linux --release
                echo -e "${GREEN}✓ Linux app built successfully${NC}"
                ;;
        esac
        
        # Web build (no Tor support)
        echo -e "${YELLOW}Building web version (without Tor support)...${NC}"
        flutter build web --release
        echo -e "${GREEN}✓ Web app built successfully${NC}"
        ;;
    *)
        echo -e "${RED}Unknown target: $TARGET${NC}"
        echo -e "${YELLOW}Available targets: android, ios, linux, macos, windows, web, all${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}🎉 Build completed successfully with Tor support!${NC}"
echo -e "${BLUE}Tor libraries are included and will be available at runtime.${NC}"
echo -e "${YELLOW}Note: Make sure target devices have necessary permissions for Tor usage.${NC}"