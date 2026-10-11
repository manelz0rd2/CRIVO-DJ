#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Este build precisa ser executado no macOS." >&2
  exit 1
fi

python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt pyinstaller
rm -rf build dist

ICON_ARGS=()
if [[ -f "$ROOT/Assets/CRIVO-DJ.png" ]]; then
  ICONSET="$ROOT/build/CRIVO-DJ.iconset"
  mkdir -p "$ICONSET"
  sips -z 16 16     "$ROOT/Assets/CRIVO-DJ.png" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32     "$ROOT/Assets/CRIVO-DJ.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$ROOT/Assets/CRIVO-DJ.png" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64     "$ROOT/Assets/CRIVO-DJ.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$ROOT/Assets/CRIVO-DJ.png" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256   "$ROOT/Assets/CRIVO-DJ.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ROOT/Assets/CRIVO-DJ.png" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512   "$ROOT/Assets/CRIVO-DJ.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ROOT/Assets/CRIVO-DJ.png" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ROOT/Assets/CRIVO-DJ.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$ROOT/build/CRIVO-DJ.icns"
  ICON_ARGS=(--icon "$ROOT/build/CRIVO-DJ.icns")
fi

python3 -m PyInstaller \
  --noconfirm \
  --clean \
  --onefile \
  --name "crivo-spotdl-helper" \
  --collect-all spotdl \
  --collect-all pykakasi \
  --collect-all yt_dlp \
  --collect-all imageio_ffmpeg \
  "$ROOT/spotdl_helper.py"

python3 -m PyInstaller \
  --noconfirm \
  --clean \
  --windowed \
  --name "CRIVO DJ" \
  --osx-bundle-identifier "com.manelz0rd.crivodj" \
  "${ICON_ARGS[@]}" \
  --add-binary "$ROOT/dist/crivo-spotdl-helper:." \
  --collect-all pyrekordbox \
  --collect-all sqlcipher3 \
  --collect-all mutagen \
  --collect-all yt_dlp \
  --collect-all imageio_ffmpeg \
  --paths "$ROOT/src" \
  "$ROOT/launcher.py"

echo "Aplicativo criado em: $ROOT/dist/CRIVO DJ.app"

