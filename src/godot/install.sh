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

# Normalize version tag
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
find /tmp/godot_extract -type f -exec ls -la {} \;

# Find the Godot executable
# Mono builds contain:  <version-folder>/Godot_v{version}_mono_linux.{arch}  (the actual binary)
# It has a DOT before the architecture, not an underscore

# Priority 1: File matching exact mono binary pattern (Linux + dot-arch suffix)
GODOT_EXEC=$(find /tmp/godot_extract -type f -name "Godot_v*_mono_linux.*" 2>/dev/null | head -n 1)

# Priority 2: Standard Linux binary pattern
if [ -z "$GODOT_EXEC" ]; then
    GODOT_EXEC=$(find /tmp/godot_extract -type f -name "Godot_v*_linux.*" 2>/dev/null | head -n 1)
fi

# Priority 3: Any ELF binary
if [ -z "$GODOT_EXEC" ]; then
    echo "Searching for ELF binaries..."
    while IFS= read -r file; do
        if file "$file" 2>/dev/null | grep -qi "elf.*executable"; then
            GODOT_EXEC="$file"
            break
        fi
    done < <(find /tmp/godot_extract -type f 2>/dev/null)
fi

if [ -z "$GODOT_EXEC" ]; then
    echo "Error: Could not find Godot executable in downloaded archive." >&2
    echo "Extracted files:" >&2
    ls -laR /tmp/godot_extract/ >&2
    exit 1
fi

echo "Found Godot executable: $GODOT_EXEC"

# Make it executable before copying
chmod +x "$GODOT_EXEC"

# Copy all files from extract dir to GODOT_DIR (important for mono .so dependencies)
cp -r /tmp/godot_extract/. "$GODOT_DIR/"

# Find the executable in the target directory (should preserve relative path)
FINAL_EXEC=$(find "$GODOT_DIR" -type f -name "$(basename "$GODOT_EXEC")" 2>/dev/null | head -n 1)

if [ -z "$FINAL_EXEC" ]; then
    echo "Error: Godot executable not found after copy to $GODOT_DIR." >&2
    ls -laR "$GODOT_DIR/" >&2
    exit 1
fi

# Ensure it's executable
chmod +x "$FINAL_EXEC"

echo "Final executable location: $FINAL_EXEC"

# Verify it's actually a binary (not a config file!)
FILE_TYPE=$(file -b "$FINAL_EXEC")
echo "Executable file type: $FILE_TYPE"

if ! echo "$FILE_TYPE" | grep -qi "elf\|executable\|binary"; then
    echo "Warning: Found file doesn't appear to be a binary ($FILE_TYPE). This may cause issues." >&2
fi

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
echo "  Type: ${FILE_TYPE}"
echo ""
echo "Usage:"
echo "  godot                    # Start editor"
echo "  godot --headless         # Headless mode (CI/CD)"
echo "  godot --build-solutions  # Build C# solutions (requires .NET SDK)"
echo "  godot --help             # Show all CLI options"
echo "=========================================="
