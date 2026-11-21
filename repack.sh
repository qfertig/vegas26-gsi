#!/usr/bin/env bash
#
# repack.sh - build the vegas26 RRO overlays, and optionally bake them into an
# ext4 LineageOS microG GSI so they apply with NO root for anyone who flashes it.
#
# This is a REFERENCE script. Run it in WSL/Ubuntu (or any Linux). It is not fully
# hardened; read it, and verify the result on-device (`cmd overlay list` should show
# both overlays enabled after boot). See README Part 5.
#
# Requirements (apt install): e2fsprogs android-sdk-libsparse-utils
#   plus Android SDK build-tools on PATH (aapt2, apksigner) and a JDK (keytool).
#
# Usage:
#   ./repack.sh build                      # build both overlay APKs into ./out/
#   ./repack.sh bake  LineageOS-...-ext4-gsi.img.xz   # build + inject into the GSI
#
# `bake` also adds the system-side fixes from README Part 5.5 (NFC init rc, props/system.prop, SurfaceFlinger cpuset).
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
ANDROID_JAR="${ANDROID_JAR:?set ANDROID_JAR to an android.jar, e.g. \$ANDROID_SDK/platforms/android-36.1/android.jar}"
OVERLAY_DIR_IN_IMG="system/product/overlay"   # verify after mounting; GSIs are often nested one level
SYSTEM_IN_IMG="system"                         # /system inside the image (same nesting as above)

put_file() {
  # Add or replace one file in the image.
  # $1 = image, $2 = host file, $3 = path in image, $4 = SELinux label for a NEW file
  # (a replaced file keeps the label it had; default u:object_r:system_file:s0).
  local img="$1" src="$2" dst="$3" label="${4:-u:object_r:system_file:s0}" keep="$OUT/.selinux"
  [ -f "$src" ] || { echo "missing $src" >&2; exit 1; }
  rm -f "$keep"
  debugfs -R "ea_get -f $keep $dst security.selinux" "$img" >/dev/null 2>&1 || true
  debugfs -w -R "rm $dst" "$img" 2>/dev/null || true
  debugfs -w -R "write $src $dst" "$img"
  debugfs -w -R "sif $dst mode 0100644" "$img"
  debugfs -w -R "sif $dst uid 0" "$img"
  debugfs -w -R "sif $dst gid 0" "$img"
  if [ -s "$keep" ]; then
    debugfs -w -R "ea_set -f $keep $dst security.selinux" "$img"
  else
    debugfs -w -R "ea_set $dst security.selinux ${label}\\000" "$img"
  fi
}

build_one() {
  # $1 = overlay source dir (contains AndroidManifest.xml + res/)
  local src="$1" name; name="$(basename "$src")"
  echo ">> building overlay: $name"
  rm -rf "$OUT/$name"; mkdir -p "$OUT/$name"
  aapt2 compile --dir "$src/res" -o "$OUT/$name/compiled.zip"
  aapt2 link -o "$OUT/$name/unsigned.apk" -I "$ANDROID_JAR" \
     --manifest "$src/AndroidManifest.xml" --min-sdk-version 30 "$OUT/$name/compiled.zip"
  [ -f "$OUT/debug.keystore" ] || keytool -genkeypair -keystore "$OUT/debug.keystore" \
     -alias k -storepass android -keypass android -dname "CN=rro" -validity 10000 -keyalg RSA -keysize 2048
  apksigner sign --ks "$OUT/debug.keystore" --ks-pass pass:android \
     --out "$OUT/${name}.apk" "$OUT/$name/unsigned.apk"
  echo "   -> $OUT/${name}.apk"
}

do_build() {
  mkdir -p "$OUT"
  build_one "$HERE/overlays/cutout"
  build_one "$HERE/overlays/aperture-aux"
}

do_bake() {
  local xz="${1:?usage: repack.sh bake <...-ext4-gsi.img.xz>}"
  do_build
  echo ">> decompressing GSI"
  cp "$xz" "$OUT/"; local base; base="$(basename "$xz" .xz)"
  ( cd "$OUT" && xz -dk "$(basename "$xz")" )
  local img="$OUT/$base"

  # If it is a sparse image, convert to raw first:  simg2img "$img" "$img.raw" && mv "$img.raw" "$img"
  echo ">> fsck + grow a little slack"
  e2fsck -fy "$img" || true
  truncate -s +8M "$img"; resize2fs "$img"

  echo ">> inject overlays via debugfs (no mount needed)"
  # Copy the SELinux context from an existing overlay in the image onto the new files.
  local ctx; ctx="$(debugfs -R "ea_list $OVERLAY_DIR_IN_IMG" "$img" 2>/dev/null | grep -o 'security.selinux.*' || true)"
  for name in cutout aperture-aux; do
    debugfs -w -R "rm $OVERLAY_DIR_IN_IMG/${name}.apk" "$img" 2>/dev/null || true
    debugfs -w -R "write $OUT/${name}.apk $OVERLAY_DIR_IN_IMG/${name}.apk" "$img"
    debugfs -w -R "sif $OVERLAY_DIR_IN_IMG/${name}.apk mode 0100644" "$img"
    debugfs -w -R "sif $OVERLAY_DIR_IN_IMG/${name}.apk uid 0" "$img"
    debugfs -w -R "sif $OVERLAY_DIR_IN_IMG/${name}.apk gid 0" "$img"
    # Set SELinux label to match siblings (typically u:object_r:system_file:s0):
    debugfs -w -R "ea_set $OVERLAY_DIR_IN_IMG/${name}.apk security.selinux u:object_r:system_file:s0\\000" "$img"
  done

  echo ">> NFC: init rc that starts the vendor NXP HAL (README Part 5.5)"
  put_file "$img" "$HERE/init/vegas26-nfc.rc" "$SYSTEM_IN_IMG/etc/init/vegas26-nfc.rc"

  echo ">> props: props/system.prop into /system/build.prop (README Part 5.5)"
  rm -f "$OUT/build.prop"
  debugfs -R "dump $SYSTEM_IN_IMG/build.prop $OUT/build.prop" "$img"
  [ -s "$OUT/build.prop" ] || { echo "no $SYSTEM_IN_IMG/build.prop in the image" >&2; exit 1; }
  printf '\n# vegas26-gsi repack.sh\n' >> "$OUT/build.prop"
  local line key
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    key="${line%%=*}"
    sed -i "/^${key//./\\.}=/d" "$OUT/build.prop"   # ours replaces any existing value
    echo "$line" >> "$OUT/build.prop"
  done < "$HERE/props/system.prop"
  put_file "$img" "$OUT/build.prop" "$SYSTEM_IN_IMG/build.prop"

  echo ">> task_profiles: SurfaceFlinger main + RenderEngine on all cores (README Part 5.5)"
  # AOSP puts SFMainPolicy / SFRenderEnginePolicy in cpuset system-background, which on MT6835
  # is the little cores only. Switch both to foreground (all cores).
  local tp="$OUT/task_profiles.json" p
  rm -f "$tp"
  debugfs -R "dump $SYSTEM_IN_IMG/etc/task_profiles.json $tp" "$img"
  sed -i -E '/"Name": "SF(Main|RenderEngine)Policy"/,/"Path"/ s/"system-background"/"foreground"/' "$tp"
  for p in SFMainPolicy SFRenderEnginePolicy; do
    grep -A8 "\"Name\": \"$p\"" "$tp" | grep -q '"Path": "foreground"' \
      || { echo "WARN: $p not found as expected, task_profiles.json left as is" >&2; tp=""; break; }
  done
  [ -z "$tp" ] || put_file "$img" "$tp" "$SYSTEM_IN_IMG/etc/task_profiles.json"

  echo ">> fsck + recompress"
  e2fsck -fy "$img" || true
  ( cd "$OUT" && xz -9 -T0 -k "$base" )
  echo "DONE -> $OUT/${base}.xz  (flash to system in fastbootd; see README Part 2)"
}

case "${1:-}" in
  build) do_build ;;
  bake)  shift; do_bake "${1:-}" ;;
  *) echo "usage: $0 {build | bake <...-ext4-gsi.img.xz>}"; exit 1 ;;
esac
