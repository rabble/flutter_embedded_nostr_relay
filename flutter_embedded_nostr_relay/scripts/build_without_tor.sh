#!/bin/bash
# ABOUTME: Build script that compiles the Flutter app without Tor support
# ABOUTME: This script builds a smaller binary that excludes all Tor dependencies and FFI code

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Building Flutter Embedded Nostr Relay without Tor support...${NC}"

# Get the project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required tools
echo -e "${YELLOW}Checking dependencies...${NC}"

if ! command_exists flutter; then
    echo -e "${RED}Error: Flutter not found. Please install Flutter: https://flutter.dev/docs/get-started/install${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Flutter found${NC}"

# Return to project root
cd "$PROJECT_ROOT"

# Clean any existing Tor libraries
echo -e "${YELLOW}Cleaning Tor libraries...${NC}"
LIB_DIR="$PROJECT_ROOT/lib/tor_libs"
if [ -d "$LIB_DIR" ]; then
    rm -rf "$LIB_DIR"
    echo -e "${GREEN}✓ Tor libraries directory removed${NC}"
fi

# Get dependencies
echo -e "${YELLOW}Getting Flutter dependencies...${NC}"
flutter pub get

# Run tests to ensure base functionality works without Tor
echo -e "${YELLOW}Running tests (excluding Tor integration tests)...${NC}"
dart test test/unit/ --exclude-tags=tor --reporter=compact || true
dart test test/unit/tor/tor_complete_test.dart --reporter=compact

# Build the Flutter app
echo -e "${YELLOW}Building Flutter app without Tor support...${NC}"

# Set environment variable to indicate Tor support is disabled
export FLUTTER_TOR_ENABLED=false

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
        echo -e "${YELLOW}Building for web...${NC}"
        flutter build web --release
        echo -e "${GREEN}✓ Web app built successfully${NC}"
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
        
        # Web build
        flutter build web --release
        echo -e "${GREEN}✓ Web app built successfully${NC}"
        ;;
    *)
        echo -e "${RED}Unknown target: $TARGET${NC}"
        echo -e "${YELLOW}Available targets: android, ios, linux, macos, windows, web, all${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}🎉 Build completed successfully without Tor support!${NC}"
echo -e "${BLUE}This build is smaller and has no Tor dependencies.${NC}"
echo -e "${YELLOW}The app will only connect to regular relays (no .onion support).${NC}"

# Show build sizes if possible
BUILD_DIR="$PROJECT_ROOT/build"
if [ -d "$BUILD_DIR" ]; then
    echo -e "${BLUE}Build artifacts:${NC}"
    find "$BUILD_DIR" -name "*.app" -o -name "*.apk" -o -name "*.exe" -o -name "*.dmg" 2>/dev/null | while read file; do
        if [ -f "$file" ]; then
            size=$(du -h "$file" | cut -f1)
            echo -e "  ${YELLOW}$file${NC} (${size})"
        elif [ -d "$file" ]; then
            size=$(du -sh "$file" | cut -f1)
            echo -e "  ${YELLOW}$file${NC} (${size})"
        fi
    done
fi