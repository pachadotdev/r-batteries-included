#!/bin/bash
# wine-install-repack.sh - Install R & Rtools in Wine, add OpenBLAS, repack
set -e

echo "==================================================================="
echo "  Wine Container Install & Repack Strategy"
echo "==================================================================="
echo ""

# ============================================================================
# Configuration
# ============================================================================
R_VERSION="4.5.1"
OPENBLAS_VERSION="0.3.28"
WINE_PREFIX="$HOME/.wine-r-build"
WORK_DIR="wine-repack"

echo "Configuration:"
echo "  Wine prefix: $WINE_PREFIX"
echo "  Work dir:    $WORK_DIR"
echo ""

# ============================================================================
# Check Dependencies
# ============================================================================
echo "Checking dependencies..."
for cmd in wine wget unzip; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "ERROR: $cmd not found"
    exit 1
  fi
done
echo "All dependencies available"

# ============================================================================
# Setup Clean Wine Prefix
# ============================================================================
echo ""
echo "Step 1/7: Setting up clean Wine prefix..."

if [ -d "$WINE_PREFIX" ]; then
  echo "  Removing old Wine prefix..."
  rm -rf "$WINE_PREFIX"
fi

export WINEPREFIX="$WINE_PREFIX"
export WINEARCH=win64
export WINEDEBUG=-all  # Suppress Wine debug output

# Initialize Wine
echo "  Initializing Wine (this may take a moment)..."
wineboot -i >/dev/null 2>&1
sleep 2

echo "Wine prefix ready: $WINE_PREFIX"

# ============================================================================
# Install R Silently in Wine
# ============================================================================
echo ""
echo "Step 2/7: Installing R in Wine..."

R_INSTALLER="R-${R_VERSION}-win.exe"
if [ ! -f "$R_INSTALLER" ]; then
  echo "ERROR: $R_INSTALLER not found!"
  echo "Please run this from the directory containing the installers."
  exit 1
fi

echo "  Running R installer silently..."
wine "$R_INSTALLER" /VERYSILENT /DIR="C:\\R\\R-${R_VERSION}" /NORESTART >/dev/null 2>&1 &
INSTALL_PID=$!

# Wait for installation with progress indicator
echo -n "  Installing"
while kill -0 $INSTALL_PID 2>/dev/null; do
  echo -n "."
  sleep 2
done
wait $INSTALL_PID
echo " Done!"

# Verify installation
R_PATH="$WINE_PREFIX/drive_c/R/R-${R_VERSION}"
if [ ! -d "$R_PATH" ]; then
  echo "ERROR: R installation not found at $R_PATH"
  echo "Contents of C:\\R:"
  ls -la "$WINE_PREFIX/drive_c/R/" 2>/dev/null || echo "Directory doesn't exist"
  exit 1
fi

echo "R installed to: $R_PATH"

# ============================================================================
# Install Rtools Silently in Wine
# ============================================================================
echo ""
echo "Step 3/7: Installing Rtools in Wine..."

RTOOLS_INSTALLER="rtools45-6691-6492.exe"
if [ ! -f "$RTOOLS_INSTALLER" ]; then
  echo "ERROR: $RTOOLS_INSTALLER not found!"
  exit 1
fi

echo "  Running Rtools installer silently..."
wine "$RTOOLS_INSTALLER" /VERYSILENT /DIR="C:\\R\\Rtools45" /NORESTART >/dev/null 2>&1 &
RTOOLS_PID=$!

# Wait for installation
echo -n "  Installing"
while kill -0 $RTOOLS_PID 2>/dev/null; do
  echo -n "."
  sleep 2
done
wait $RTOOLS_PID
echo " Done!"

# Verify installation
RTOOLS_PATH="$WINE_PREFIX/drive_c/R/Rtools45"
if [ ! -d "$RTOOLS_PATH" ]; then
  echo "ERROR: Rtools installation not found at $RTOOLS_PATH"
  exit 1
fi

echo "Rtools installed to: $RTOOLS_PATH"

# ============================================================================
# Download and Integrate OpenBLAS
# ============================================================================
echo ""
echo "Step 4/7: Adding OpenBLAS..."

OPENBLAS_ZIP="OpenBLAS-${OPENBLAS_VERSION}-x64.zip"
if [ ! -f "$OPENBLAS_ZIP" ]; then
  echo "  Downloading OpenBLAS..."
  wget -q --show-progress https://github.com/OpenMathLib/OpenBLAS/releases/download/v${OPENBLAS_VERSION}/${OPENBLAS_ZIP}
else
  echo "  Using existing $OPENBLAS_ZIP"
fi

# Extract OpenBLAS
rm -rf openblas-temp
unzip -q "$OPENBLAS_ZIP" -d openblas-temp

OPENBLAS_DLL=$(find openblas-temp -name "libopenblas.dll" | head -1)
if [ -z "$OPENBLAS_DLL" ]; then
  echo "ERROR: libopenblas.dll not found!"
  exit 1
fi

# Replace R's BLAS/LAPACK with OpenBLAS
R_BIN="$R_PATH/bin/x64"
echo "  Backing up original DLLs..."
cp "$R_BIN/Rblas.dll" "$R_BIN/Rblas.dll.bak"
cp "$R_BIN/Rlapack.dll" "$R_BIN/Rlapack.dll.bak"

echo "  Installing OpenBLAS..."
cp "$OPENBLAS_DLL" "$R_BIN/Rblas.dll"
cp "$OPENBLAS_DLL" "$R_BIN/Rlapack.dll"

rm -rf openblas-temp

echo "OpenBLAS integrated ($(du -h "$R_BIN/Rblas.dll" | cut -f1))"

# ============================================================================
# Configure R
# ============================================================================
echo ""
echo "Step 5/7: Configuring R..."

R_ETC="$R_PATH/etc"

# Create Rprofile.site
cat > "$R_ETC/Rprofile.site" << 'EOF'
# R Batteries Included
local({
  # Configure OpenBLAS threads
  n_cores <- parallel::detectCores()
  if (is.na(n_cores) || n_cores < 1) n_cores <- 4
  n_threads <- max(1, n_cores - 1)
  Sys.setenv(OPENBLAS_NUM_THREADS = n_threads)
  
  # Add Rtools to PATH
  rtools_path <- "C:/R/Rtools45/usr/bin"
  if (dir.exists(rtools_path)) {
    current_path <- Sys.getenv("PATH")
    if (!grepl(rtools_path, current_path, fixed = TRUE)) {
      Sys.setenv(PATH = paste(rtools_path, current_path, sep = ";"))
    }
  }
  
  # Add mingw bin too
  mingw_path <- "C:/R/Rtools45/x86_64-w64-mingw32.static.posix/bin"
  if (dir.exists(mingw_path)) {
    current_path <- Sys.getenv("PATH")
    if (!grepl(mingw_path, current_path, fixed = TRUE)) {
      Sys.setenv(PATH = paste(mingw_path, current_path, sep = ";"))
    }
  }

  # Set default CRAN mirror and disable interactive selection
  # Use the main CRAN global mirror and prevent the selection menu from appearing
  try({
    options(repos = c(CRAN = "https://cran.r-project.org"))
    # Prevent packages::chooseCRANmirror and utils::menu from prompting
    options("cran.use.default" = TRUE)
    # Ensure non-interactive sessions don't prompt
    options("menu.graphics" = FALSE)
  }, silent = TRUE)
  
  if (interactive()) {
    packageStartupMessage(
      "\n================================================================\n",
      " R ", R.version$major, ".", R.version$minor, " Batteries Included \n",
      "==================================================================\n",
      sprintf("Using OpenBLAS %s\n", Sys.getenv("OPENBLAS_VERSION")),
      sprintf("CPU cores: %d | OpenBLAS threads: %d\n", n_cores, n_threads),
      "==================================================================\n"
    )
  }
})
EOF

echo "R configured"

# ============================================================================
# Export Installed Files
# ============================================================================
echo ""
echo "Step 6/7: Exporting installed files..."

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "  Copying R installation..."
cp -r "$R_PATH" "$WORK_DIR/R-${R_VERSION}"

echo "  Copying Rtools installation..."
cp -r "$RTOOLS_PATH" "$WORK_DIR/Rtools45"

echo "Files exported to: $WORK_DIR"

# Show what we have
echo ""
echo "Exported structure:"
du -sh "$WORK_DIR/R-${R_VERSION}" "$WORK_DIR/Rtools45"

# ============================================================================
# Create Installer Script
# ============================================================================
echo ""
echo "Step 7/7: Creating installer script..."

cat > "$WORK_DIR/installer.iss" << EOF
[Setup]
AppId={{PA-REPACK-R-${R_VERSION}}}
AppName=R Batteries Included
AppVersion=${R_VERSION}
AppPublisher=Custom Build
DefaultDirName=C:\\R
DefaultGroupName=R
OutputDir=.
OutputBaseFilename=R-${R_VERSION}-Batteries-Included
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
DisableProgramGroupPage=yes
DisableWelcomePage=no
PrivilegesRequired=admin

[Files]
Source: "R-${R_VERSION}\\*"; DestDir: "{app}\\R-${R_VERSION}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "Rtools45\\*"; DestDir: "{app}\\Rtools45"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\\R ${R_VERSION}"; Filename: "{app}\\R-${R_VERSION}\\bin\\x64\\Rgui.exe"; WorkingDir: "{userdocs}"
Name: "{commondesktop}\\R ${R_VERSION}"; Filename: "{app}\\R-${R_VERSION}\\bin\\x64\\Rgui.exe"; WorkingDir: "{userdocs}"

[Registry]
Root: HKLM; Subkey: "Software\\R-core\\R"; Flags: uninsdeletekeyifempty
Root: HKLM; Subkey: "Software\\R-core\\R\\${R_VERSION}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\\R-core\\R\\${R_VERSION}"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}\\R-${R_VERSION}"
Root: HKLM; Subkey: "Software\\R-core\\R"; ValueType: string; ValueName: "Current Version"; ValueData: "${R_VERSION}"
Root: HKLM; Subkey: "Software\\R-core\\R"; ValueType: string; ValueName: "InstallPath"; ValueData: "{app}\\R-${R_VERSION}"

[Run]
Filename: "{app}\\R-${R_VERSION}\\bin\\x64\\Rgui.exe"; Description: "Launch R"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\\R-${R_VERSION}"
Type: filesandordirs; Name: "{app}\\Rtools45"

EOF

echo "Installer script created"

# ============================================================================
# Compile Installer
# ============================================================================
echo ""
echo "Checking for Inno Setup..."

ISCC_PATH="$HOME/.wine/drive_c/Program Files (x86)/Inno Setup 6/ISCC.exe"
if [ ! -f "$ISCC_PATH" ]; then
  echo ""
  echo "Inno Setup not found. Installing..."
  
  if [ ! -f "is.exe" ]; then
    wget -q --show-progress https://jrsoftware.org/download.php/is.exe
  fi
  
  export WINEPREFIX="$HOME/.wine"
  wine is.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- >/dev/null 2>&1 &
  INNO_PID=$!
  
  echo -n "  Installing Inno Setup"
  while kill -0 $INNO_PID 2>/dev/null; do
    echo -n "."
    sleep 2
  done
  wait $INNO_PID
  echo " Done!"
  
  if [ ! -f "$ISCC_PATH" ]; then
    echo "ERROR: Inno Setup installation failed"
    exit 1
  fi
fi

echo "Inno Setup available"
echo ""
echo "Compiling installer..."

export WINEPREFIX="$HOME/.wine"
cd "$WORK_DIR"
wine "$ISCC_PATH" "installer.iss" 2>&1 | grep -E "(Compiling|Successful|Error)" || true

# ============================================================================
# Success
# ============================================================================
echo ""
echo "==================================================================="
echo "                        SUCCESS!"
echo "==================================================================="
echo ""

INSTALLER_EXE="$WORK_DIR/R-${R_VERSION}-Batteries-Included.exe"
if [ -f "$INSTALLER_EXE" ]; then
  echo "Installer created:"
  echo "  Location: $INSTALLER_EXE"
  echo "  Size: $(du -h "$INSTALLER_EXE" | cut -f1)"
  echo ""
  echo "This installer provides:"
  echo "  R ${R_VERSION}"
  echo "  OpenBLAS ${OPENBLAS_VERSION}"
  echo "  Rtools 4.5"
  echo "  Desktop shortcut to Rgui.exe"
  echo "  Start menu entry"
  echo "  Registry keys"
  echo ""
  echo "1-Click Install"
else
  echo "Files ready in: $WORK_DIR"
  echo ""
  echo "To compile manually:"
  echo "  cd $WORK_DIR"
  echo "  wine \"C:\\Program Files (x86)\\Inno Setup 6\\ISCC.exe\" installer.iss"
fi

echo ""
echo "==================================================================="

# Optional: Cleanup
echo ""
read -p "Clean up Wine build prefix? (saves $(du -sh "$WINE_PREFIX" | cut -f1)) [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  rm -rf "$WINE_PREFIX"
  echo "Cleaned up Wine prefix"
fi
