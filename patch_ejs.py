#!/usr/bin/env python3
"""
patch_ejs.py — ShyRobbie URL-detection BIOS fix for EmulatorJS in RomM 5.3.x

Fixes: arcade/mame cores (FBNeo) extract the BIOS zip into loose files instead
of writing it whole, so locate_archive() can never find /neogeo.zip -> games
fail with "missing ROM" even when firmware is present and CRC-correct.

Why URL detection: RomM 5.3.0 refactored the pipeline so this.getCore(!0)
returns null, breaking the older getCore-based patch. Matching the firmware
URL string (neogeo/mame/arcade) works regardless. The ?file_ids=... query is
stripped with .split("?")[0].

Make sure the volume line is added in docker-compose.yml:
- /opt/romm/ejs-overlay/emulator.min.js:/var/www/html/assets/emulatorjs/data/emulator.min.js:ro

Credit: ShyRobbie / mwolfinspace — https://github.com/rommapp/romm/issues/4207

Usage:
    sudo python3 patch_ejs.py [container] [overlay_dir]
Defaults:
    container    = romm
    overlay_dir  = /opt/romm/ejs-overlay
"""
import subprocess, os, sys, tempfile, shutil

container = sys.argv[1[overlay/romm/ejs-] if len(sys.argv) > 1 else "sys.argv[2] if len(sys.argv) > 2 else "/opt/romm/ejs-overlay"
data_path = "/var/www/html/assets/emulatorjs/data"
src_in    = f"{container}:{data_path}/emulator.min.js"

OLD = ('const a=async e=>{if(!0===this.config.dontExtractBIOS)'
       'return this.gameManager.FS.writeFile(t,new Uint8Array(e)),s(t);'
       'const i=await this.checkCompression(new Uint8Array(e),n);')

NEW = ('const a=async e=>{const coreFilename="/"+this.fileName,'
       'coreFilePath=coreFilename.substring(0,coreFilename.length-'
       'coreFilename.split("/").pop().length);'
       'if(t.includes("neogeo")||t.includes("mame")||t.includes("arcade")){'
       'const cleanName=t.split("/").pop().split("?")[0];'
       'this.gameManager.FS.writeFile(coreFilePath+cleanName,new Uint8Array(e));'
       'return s(t)}'
       'if(!0===this.config.dontExtractBIOS)'
       'return this.gameManager.FS.writeFile(t,new Uint8Array(e)),s(t);'
       'const i=await this.checkCompression(new Uint8Array(e),n);')

os.makedirs(overlay, exist_ok=True)
tmp = tempfile.mkdtemp()
try:
    local = os.path.join(tmp, "emulator.min.js")
    subprocess.run(["docker", "cp", src_in, local], check=True)
    text = open(local, encoding="utf-8").read()

    if 't.includes("neogeo")' in text:
        print("Already patched. Nothing to do.")
        sys.exit(0)

    count = text.count(OLD)
    print("OLD match count:", count)
    if count != 1:
        print("ERROR: expected exactly 1 match. File NOT written.")
        print("The bundled EmulatorJS version may differ from the 5.3.x target.")
        sys.exit(1)

    out = os.path.join(overlay, "emulator.min.js")
    open(out, "w", encoding="utf-8").write(text.replace(OLD, NEW))
    print("Patched successfully (URL-based detection).")
    print(f"Wrote: {out}")
    print("\nEnsure this volume line is active under the romm service, then recreate:")
    print(f"      - {out}:{data_path}/emulator.min.js:ro")
finally:
    shutil.rmtree(tmp, ignore_errors=True)
