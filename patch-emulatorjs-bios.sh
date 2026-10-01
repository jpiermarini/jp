# Temp fix for: arcade/mame cores in EmulatorJS extract the BIOS zip instead
# of writing it whole, so locate_archive() (FBNeo etc.) can never find it.
# Root cause + fix credit: mwolfinspace
# (see: https://github.com/rommapp/romm/issues/4207)
#
# What this script does:
#   1. Copies emulator.js and emulator.min.js out of your running RomM
#      container.
#   2. Applies the literal patch to both (exact string replace, not regex,
#      so minified code doesn't need escaping).
#   3. Saves the patched files into an overlay directory on the host.
#   4. Prints the docker-compose volume lines you need to bind-mount them
#      back into the container so the fix survives image updates.
#
# Usage:
#   ./patch-emulatorjs-bios.sh [container_name] [overlay_dir]
#
# Defaults:
#   container_name = romm
#   overlay_dir    = /opt/romm/ejs-overlay
#
set -euo pipefail

CONTAINER="${1:-romm}"
OVERLAY_DIR="${2:-/opt/romm/ejs-overlay}"
DATA_PATH="/var/www/html/assets/emulatorjs/data"

echo "== EmulatorJS BIOS-extraction patch =="
echo "Container:   $CONTAINER"
echo "Overlay dir: $OVERLAY_DIR"
echo

command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 not found in PATH" >&2; exit 1; }

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "ERROR: container '$CONTAINER' is not running." >&2
    echo "Pass the correct container name as the first argument." >&2
    exit 1
fi

mkdir -p "$OVERLAY_DIR/src"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "-- Extracting current files from container --"
docker cp "$CONTAINER:$DATA_PATH/src/emulator.js" "$TMP_DIR/emulator.js"
docker cp "$CONTAINER:$DATA_PATH/emulator.min.js" "$TMP_DIR/emulator.min.js"

echo "-- Patching emulator.js --"
python3 - "$TMP_DIR/emulator.js" "$OVERLAY_DIR/src/emulator.js" <<'PYEOF'
import sys

src_path, dst_path = sys.argv[1], sys.argv[2]
text = open(src_path, "r", encoding="utf-8").read()

OLD = '''            const gotData = async (input) => {
                if (this.config.dontExtractBIOS === true) {
                    this.gameManager.FS.writeFile(assetUrl, new Uint8Array(input));
                    return resolve(assetUrl);
                }
                const data = await this.checkCompression(new Uint8Array(input), decompressProgressMessage);
                for (const k in data) {
                    const coreFilename = "/" + this.fileName;
                    const coreFilePath = coreFilename.substring(0, coreFilename.length - coreFilename.split("/").pop().length);
                    if (k === "!!notCompressedData") {
                        this.gameManager.FS.writeFile(coreFilePath + assetUrl.split("/").pop().split("#")[0].split("?")[0], data[k]);
                        break;
                    }
                    if (k.endsWith("/")) continue;
                    this.gameManager.FS.writeFile(coreFilePath + k.split("/").pop(), data[k]);
                }
            }'''

NEW = '''            const gotData = async (input) => {
                const coreFilename = "/" + this.fileName;
                const coreFilePath = coreFilename.substring(0, coreFilename.length - coreFilename.split("/").pop().length);
                if (["arcade", "mame"].includes(this.getCore(true))) {
                    this.gameManager.FS.writeFile(coreFilePath + assetUrl.split("/").pop().split("#")[0].split("?")[0], new Uint8Array(input));
                    return resolve(assetUrl);
                }
                if (this.config.dontExtractBIOS === true) {
                    this.gameManager.FS.writeFile(assetUrl, new Uint8Array(input));
                    return resolve(assetUrl);
                }
                const data = await this.checkCompression(new Uint8Array(input), decompressProgressMessage);
                for (const k in data) {
                    if (k === "!!notCompressedData") {
                        this.gameManager.FS.writeFile(coreFilePath + assetUrl.split("/").pop().split("#")[0].split("?")[0], data[k]);
                        break;
                    }
                    if (k.endsWith("/")) continue;
                    this.gameManager.FS.writeFile(coreFilePath + k.split("/").pop(), data[k]);
                }
            }'''

if OLD not in text:
    if NEW in text:
        print("emulator.js: already patched, leaving as-is.")
        open(dst_path, "w", encoding="utf-8").write(text)
        sys.exit(0)
    print("ERROR: expected original gotData() block not found in emulator.js.", file=sys.stderr)
    print("The EmulatorJS version bundled in your image may differ from the one this patch targets.", file=sys.stderr)
    sys.exit(1)

text = text.replace(OLD, NEW)
open(dst_path, "w", encoding="utf-8").write(text)
print("emulator.js: patched successfully.")
PYEOF

echo "-- Patching emulator.min.js --"
python3 - "$TMP_DIR/emulator.min.js" "$OVERLAY_DIR/emulator.min.js" <<'PYEOF'
import sys

src_path, dst_path = sys.argv[1], sys.argv[2]
text = open(src_path, "r", encoding="utf-8").read()

OLD = 'const a=async e=>{if(!0===this.config.dontExtractBIOS)return this.gameManager.FS.writeFile(t,new Uint8Array(e)),s(t);const i=await this.checkCompression(new Uint8Array(e),n);for(const e in i){const n="/"+this.fileName,s=n.substring(0,n.length-n.split("/").pop().length);if("!!notCompressedData"===e){this.gameManager.FS.writeFile(s+t.split("/").pop().split("#")[0].split("?")[0],i[e]);break}e.endsWith("/")||this.gameManager.FS.writeFile(s+e.split("/").pop(),i[e])}};'

NEW = 'const a=async e=>{if(["arcade","mame"].includes(this.getCore(!0))){const p="/"+this.fileName,q=p.substring(0,p.length-p.split("/").pop().length);return this.gameManager.FS.writeFile(q+t.split("/").pop().split("#")[0].split("?")[0],new Uint8Array(e)),s(t)}if(!0===this.config.dontExtractBIOS)return this.gameManager.FS.writeFile(t,new Uint8Array(e)),s(t);const i=await this.checkCompression(new Uint8Array(e),n);for(const e in i){const n="/"+this.fileName,s=n.substring(0,n.length-n.split("/").pop().length);if("!!notCompressedData"===e){this.gameManager.FS.writeFile(s+t.split("/").pop().split("#")[0].split("?")[0],i[e]);break}e.endsWith("/")||this.gameManager.FS.writeFile(s+e.split("/").pop(),i[e])}};'

if OLD not in text:
    if NEW in text:
        print("emulator.min.js: already patched, leaving as-is.")
        open(dst_path, "w", encoding="utf-8").write(text)
        sys.exit(0)
    print("ERROR: expected minified gotData block not found in emulator.min.js.", file=sys.stderr)
    print("The EmulatorJS version bundled in your image may differ from the one this patch targets.", file=sys.stderr)
    sys.exit(1)

text = text.replace(OLD, NEW)
open(dst_path, "w", encoding="utf-8").write(text)
print("emulator.min.js: patched successfully.")
PYEOF

echo
echo "== Done =="
echo "Patched files staged at:"
echo "  $OVERLAY_DIR/emulator.min.js"
echo "  $OVERLAY_DIR/src/emulator.js"
echo
echo "Add these volume mounts to your RomM docker-compose.yml under the romm service, then run:"
echo "  docker compose up -d $CONTAINER"
echo
cat <<EOF
    volumes:
      - $OVERLAY_DIR/emulator.min.js:$DATA_PATH/emulator.min.js:ro
      - $OVERLAY_DIR/src/emulator.js:$DATA_PATH/src/emulator.js:ro
EOF
