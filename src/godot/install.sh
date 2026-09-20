#!/bin/bash
set -e

VERSION="${VERSION:-latest}"
FLAVOR="${FLAVOR:-standard}"
GODOT_DIR="/opt/godot"
BIN_DIR="/usr/local/bin"

echo "Installing Godot Engine ${VERSION} (${FLAVOR})..."

# Determine architecture
if [ "$(uname -m)" = "aarch64" ]; then
    ARCH="arm64"
elif [ "$(uname -m)" = "x86_64" ]; then
    ARCH="x86_64"
else
    echo "Error: Unsupported architecture $(uname -m). Only x86_64 and arm64 supported." >&2
    exit 1
fi

# Resolve "latest" via GitHub API
if [ "$VERSION" = "latest" ]; then
    VERSION=$(curl -sL https://api.github.com/repos/godotengine/godot/releases/latest \
        | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    echo "Latest version detected: ${VERSION}"
fi

# Normalize version tag:
# Accepts: "4.2", "4.2-stable", "v4.2.1-stable" -> outputs "v4.2-stable" or "v4.2.1-stable"
VERSION=${VERSION#v}
if [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    VERSION="${VERSION}-stable"
fi

# Build the asset filename based on flavor
if [ "$FLAVOR" = "dotnet" ]; then
    ASSET="Godot_v${VERSION}_mono_linux_${ARCH}.zip"
    INSTALL_NAME="godot"
else
    ASSET="Godot_v${VERSION}_linux_${ARCH}.zip"
    INSTALL_NAME="godot"
fi

# Create directories
mkdir -p "$GODOT_DIR"

# Download
DOWNLOAD_URL="https://github.com/godotengine/godot/releases/download/${VERSION}/${ASSET}"
echo "Downloading ${DOWNLOAD_URL}..."
wget -q --show-progress "$DOWNLOAD_URL" -O "/tmp/godot.zip"

# Extract to temp directory
echo "Extracting Godot..."
unzip -q -o "/tmp/godot.zip" -d /tmp/godot_extract

# Debug: show what was extracted
echo "Extracted contents:"
ls -laR /tmp/godot_extract/

# Find the Godot executable recursively
# Both standard and mono builds have binaries in nested folders
GODOT_EXEC=$(find /tmp/godot_extract -type f \( -iname "godot*" -o -iname "*Godot*" \) \
    ! -iname "*.so" ! -iname "*.pdb" ! -iname "*.zip" ! -iname "*.dll" 2>/dev/null | head -n 1)

if [ -z "$GODOT_EXEC" ]; then
    echo "Error: Could not find Godot executable in downloaded archive." >&2
    ls -laR /tmp/godot_extract/ >&2
    exit 1
fi

echo "Found Godot executable: $GODOT_EXEC"

# Copy all files from extract dir to GODOT_DIR (important for mono .so dependencies)
cp -r /tmp/godot_extract/. "$GODOT_DIR/"

# Find the executable in the target directory
FINAL_EXEC=$(find "$GODOT_DIR" -type f -name "$(basename "$GODOT_EXEC")" 2>/dev/null | head -n 1)

if [ -z "$FINAL_EXEC" ] || [ ! -x "$FINAL_EXEC" ]; then
    # Make sure it's executable
    chmod +x "$GODOT_EXEC" 2>/dev/null || true
    FINAL_EXEC=$(find "$GODOT_DIR" -type f -name "$(basename "$GODOT_EXEC")" 2>/dev/null | head -n 1)
    
    if [ -z "$FINAL_EXEC" ]; then
        echo "Error: Godot executable not found after copy to $GODOT_DIR." >&2
        ls -laR "$GODOT_DIR/" >&2
        exit 1
    fi
    
    chmod +x "$FINAL_EXEC"
fi

echo "Final executable location: $FINAL_EXEC"

# Create symlink for easy access
ln -sf "$FINAL_EXEC" "$BIN_DIR/$INSTALL_NAME"

# For standard flavor, also create generic 'godot' symlink
[ "$FLAVOR" = "dotnet" ] && ln -sf "$FINAL_EXEC" "$BIN_DIR/godot" || true

# Cleanup
rm -rf /tmp/godot.zip /tmp/godot_extract

# Verify installation
INSTALLED_VERSION=$("$BIN_DIR/$INSTALL_NAME" --version 2>/dev/null || echo "unknown")
FLAVOR_HINT=""
[ "$FLAVOR" = "dotnet" ] && FLAVOR_HINT=" (.NET/Mono enabled)"

echo ""
echo "=========================================="
echo "Godot installed successfully!"
echo "  Version: ${INSTALLED_VERSION}${FLAVOR_HINT}"
echo "  Location: ${GODOT_DIR}"
echo "  Executable: ${BIN_DIR}/${INSTALL_NAME}"
echo ""
echo "Usage:"
echo "  godot                    # Start editor"
echo "  godot --headless         # Headless mode (CI/CD)"
echo "  godot --build-solutions  # Build C# solutions (requires .NET SDK)"
echo "  godot --help             # Show all CLI options"
echo "=========================================="
