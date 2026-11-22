# Moto G Power 2026 (XT2617V / vegas26): Unlock, LineageOS GSI, SIM Unlock, and Working VoLTE

A complete, reproducible guide taking a **carrier-locked Straight Talk / Tracfone Moto G Power 2026** from a locked bootloader to a de-Googled **LineageOS 23.2 microG** daily driver with **mobile data, SMS, and VoLTE calls all working**, on a **MediaTek MT6835** device that is widely assumed to be unable to do GSI VoLTE.

Verified end to end on a real device, 2026-11.

---

## Table of contents

- [What you get](#what-you-get)
- [Which tool does what](#which-tool-does-what)
- [Runbook: SIM unlock, copy-paste, Linux-first](#runbook-sim-unlock-copy-paste-linux-first)
- [Tested device / compatibility](#tested-device--compatibility)
- [Warnings](#warnings)
- [Using an AI assistant](#using-an-ai-assistant)
- [Before you start](#before-you-start)
- [Prerequisites](#prerequisites)
- [How the pieces fit (the layer model)](#how-the-pieces-fit-the-layer-model)
- [Part 1: Bootloader unlock](#part-1-bootloader-unlock)
- [Part 2: Install the LineageOS GSI](#part-2-install-the-lineageos-gsi)
- [Part 3: SIM / network unlock (modem)](#part-3-sim--network-unlock-modem)
- [Part 4: Cellular, APN and VoLTE](#part-4-cellular-apn-and-volte)
- [Part 5: Optional polish (cameras, cutout, density)](#part-5-optional-polish-cameras-cutout-density)
- [Troubleshooting](#troubleshooting)
- [How updates work](#how-updates-work)
- [Repo contents](#repo-contents)
- [Credits and prior work](#credits-and-prior-work)
- [Quick reference](#quick-reference)

---

## What you get

- Bootloader unlocked on the `-4-3` (June 2026) build, past the carrier OEM-unlock wall.
- LineageOS 23.2 microG GSI running persistently (the reboot-loop that kills most GSI attempts here is solved, see Part 2).
- SIM/network unlock via a patched modem (`md1img`), legal on a device you own.
- VoLTE calls working natively (LineageOS ships `com.mediatek.ims`; verified with a live QCI-1 voice bearer on AT&T).
- Mobile data and SMS working.
- Optional polish: both rear cameras, a centered display cutout, and corrected UI density.

## Which tool does what

Two separate tools do two separate jobs. They are easy to confuse because both patch MediaTek images, but they are not interchangeable. Do not run one expecting the other's result.

| Tool | Repo | Operates on | Job | Used in |
|---|---|---|---|---|
| **val-protocol** | [Maikyxd/val-protocol](https://github.com/Maikyxd/val-protocol) | `lk_a.img` (Little Kernel / bootloader) | Bootloader unlock ONLY | Part 1 |
| **vegas-freedom** | [andrewwm/vegas-freedom](https://github.com/andrewwm/vegas-freedom) | `md1img.img` (modem) | SIM / network unlock ONLY | Part 3 |

- **val-protocol produces no modem image and is never run to unlock a SIM.** It appears only in Part 1 (bootloader).
- **vegas-freedom produces no bootloader image and is never run to unlock a bootloader.** It appears only in Part 3 (modem).
- **NOT FOR THIS DEVICE:** a modem-unlock tool built for a different Motorola codename will not match vegas26. For example, a `kansas`-codename modem-unlock tool targets the `kansas` device, not `vegas26` (XT2617V). Use **vegas-freedom** for the modem here, nothing else. If a tool's `check` step does not print `CANDIDATE MATCH` against your stock `md1img`, it is the wrong tool or the wrong source build; stop.

## Runbook: SIM unlock, copy-paste, Linux-first

Flat, top-to-bottom order for SIM-unlocking a device you own. Each step is explained in detail in the numbered Parts below; this is the condensed run order so you do not have to re-derive it. Linux-first; the only Windows difference is the driver bind (see Prerequisites). Fill in your own `<SECRET>`, serial, and keys from your phone; keep them private.

```bash
# 0. PRE-CHECKS (confirm this is the right device/build/slot before anything)
adb devices
adb shell getprop ro.boot.hardware.sku             # XT2617V
adb shell getprop ro.build.fingerprint             # note the -4-x build string
adb shell getprop ro.build.version.security_patch
adb shell getprop ro.boot.slot_suffix              # _a on the tested unit
adb shell getprop ro.boot.flash.locked             # 1 = locked, 0 = already unlocked
adb shell getprop gsm.sim.state                    # NETWORK_LOCKED before unlock

# 1. LINUX USB (substitute for the Windows driver bind; see Prerequisites)
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="22b8", MODE="0660", GROUP="plugdev"' \
  | sudo tee /etc/udev/rules.d/51-moto.rules
sudo udevadm control --reload-rules && sudo udevadm trigger
# add your user to plugdev and replug if needed

# 2. UNLOCK BOOTLOADER  -- ONLY if ro.boot.flash.locked = 1. THIS WIPES USERDATA.
#    Full procedure is Part 1 (temp root -> backup -> val-protocol LK patch ->
#    frp byte bypass -> fastboot oem unlock). Skip entirely if already unlocked.
fastboot getvar securestate                        # expect flashing_unlocked when done

# 3. BACKUP the protected set + modem (dd, pull, verify SHA-256 both sides). Part 1.2.
for p in nvram nvdata seccfg persist prodpersist proinfo protect1 protect2 md1img_a; do
  adb shell su -c "dd if=/dev/block/by-name/$p of=/sdcard/bk_$p.img"
  adb pull /sdcard/bk_$p.img ./bk_$p.img
  adb shell su -c "sha256sum /sdcard/bk_$p.img"; sha256sum ./bk_$p.img   # must match
done
# Keep bk_md1img_a.img as the revert. These are BACKED UP, NEVER FLASHED.

# 4. GET STOCK md1img (the INPUT to the patcher, not what you flash)
#    Pull the matching (or -4-7) stock firmware zip from the lolinet mirror;
#    the standalone md1img.img is inside the zip. See Part 3 / Prerequisites.

# 5. PATCH THE MODEM (vegas-freedom). The check gate is the safety.
python modem/unlock_vegas.py check <stock_md1img.img>
#   REQUIRE: 3/3 CATI symbols, 8/8 microMIPS32 signatures, "CANDIDATE MATCH". If not, STOP.
python modem/unlock_vegas.py build --experimental-relocate -o md1img_patched.signed.img <stock_md1img.img>
#   expect audit: entries=23 layout_ok=True integrity=True ; all sub-images hash_ok and rsa_ok

# 6. FLASH -- A SLOT ONLY. Never md1img_b.
adb reboot bootloader
fastboot devices
fastboot flash md1img_a md1img_patched.signed.img
fastboot reboot

# 7. VERIFY
adb shell getprop gsm.sim.state                    # NETWORK_LOCKED -> LOADED
# insert the target SIM; it should register on the carrier

# 8. REVERT (only if the unlock did not take or anything is off)
fastboot flash md1img_a bk_md1img_a.img && fastboot reboot
```

IMEI and calibration live in `nvram`/`nvdata`/`protect*`, which you only back up and never flash, so this cannot erase your IMEI.

## Tested device / compatibility

| Item | Value |
|---|---|
| Model / SKU | moto g power - 2026 / XT2617V (`vegas26`, bootloader `vegas`) |
| Carrier | Straight Talk / Tracfone (`ro.carrier=tracfone`); tested with a US Mobile SIM (Dark Star = AT&T) |
| Android | 16 |
| Build | W1WEOS36.48-22-3-3-4-3 |
| Security patch | 2026-06-01 |
| Kernel | `5.15.189-android13-8-...` |
| SoC | MediaTek MT6835 (Dimensity 6300) |
| Baseband (known-good on `-4-3`) | `MT6835O_NR17.RC.MP.V18.6.6.P107.02.309R` |
| Active slot | `_a` |

If your `-4-x`, patch, or kernel differ, re-verify every step. A tool printing "VALID" is not proof your unit will boot a patched image. (The underlying [parsimo2010 base guide](https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide) was proven on `-4-2`; this guide and an independent community report confirm the same flow on `-4-3`.)

## Warnings

**Safety and legal notice:** use this guide only on devices you own or are explicitly authorized to service. It is intended for repair, interoperability, and personal recovery work. It never modifies the IMEI.

Experimental and firmware-specific. Bootloader and modem modification can brick a device with no guaranteed recovery. Unlocking wipes userdata. Do this only on a device you own and are willing to lose. SIM-unlocking a phone you own is legal in the US (Unlocking Consumer Choice and Wireless Competition Act). Never publish your serial number, unlock keys, or dumps of `frp`/`nvram`/`nvdata`/`seccfg`/`persist`/`protect*`/`md1img`; they are device-unique. Placeholders like `<YOUR SERIAL>` and `<SECRET>` in this guide must stay redacted in anything you share.

## Using an AI assistant

You can have an AI coding assistant (Claude Code, Codex, OpenCode, and similar) walk you through this guide and run most of the commands for you.

**1. Open the assistant inside this repo** so it reads the context files (`AGENTS.md`, `CLAUDE.md`) automatically:

```
git clone https://github.com/qfertig/vegas26-gsi.git
cd vegas26-gsi
claude        # or: codex / opencode
```

**2. Paste this as your first message** (fill in the brackets):

```
This is my own Motorola Moto G Power 2026 (XT2617V, vegas26), and I want to follow the guide
in this repo (README.md; context and safety rules are in AGENTS.md). Intended use: a device I
own, for repair, interoperability, and personal recovery. Nothing here modifies the IMEI.

My setup: [Windows/Linux], phone currently on [stock firmware / already unlocked / a GSI],
carrier/SIM [your carrier], and I want to do [all parts / just Part X].

Please walk me through it step by step: explain what each step does, run the adb/fastboot
commands for me where you can, make sure I have my Part 1.2 backup before anything gets
modified, and ask me before every flash, wipe, or unlock. Follow the safety rails in AGENTS.md.
```

If you're using a plain chat (not one of the tools above), paste the same message plus a link to this repo. The assistant won't see `AGENTS.md` there, so the message has to carry that context on its own.

## Before you start

- **Skill level:** intermediate. You should be comfortable running commands in a terminal and with basic `adb`/`fastboot`. If you have never flashed a phone, read the platform-tools docs and practice `adb devices` / `fastboot devices` first.
- **Time:** plan a full afternoon for Parts 1-4. Part 5 is optional.
- **You need:** the phone (XT2617V), a Windows PC (Linux works too with small changes), a good **data** USB cable plugged directly into the PC (no hubs), and a SIM card to test cellular.
- **Order matters:** do the Part 1 backup before changing anything. It is your only way back.
- **Device-specific files are yours to create:** your partition backups, your unlock `<SECRET>` and keys, and your patched LK come from *your* phone. Nothing in this repo replaces them, and you should never use someone else's.

## Prerequisites

Tools:

- **Android platform-tools** (adb/fastboot) 37.0.1+: https://developer.android.com/tools/releases/platform-tools
- **Google USB Driver** (Windows, for the fastboot driver bind): https://developer.android.com/studio/run/win-usb
- **Linux instead of the Windows driver:** no driver install. Add a udev rule for Motorola (USB VID `22b8`) so adb/fastboot can see the device without root, then replug:
  ```bash
  echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="22b8", MODE="0660", GROUP="plugdev"' | sudo tee /etc/udev/rules.d/51-moto.rules
  sudo udevadm control --reload-rules && sudo udevadm trigger
  ```
  On Linux the separate bootloader/fastbootd driver binds that Windows needs do not apply.
- **Python 3.10+** with `capstone` and `pyasn1` (for the LK patcher and the modem unlock).
- For the optional overlays: **Android SDK build-tools** (`aapt2`, `apksigner`) and a JDK (both come with Android Studio).

Downloads and prior guides this builds on:

- **Base bootloader guide** (validated on `-4-2`; source of the pinned APK hashes used in Part 1): [parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide](https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide)
- **DFRoot** (temporary root via CVE-2026-43284, used in Part 1): https://github.com/diabl0w/DFRoot (see its [wiki](https://github.com/diabl0w/DFRoot/wiki) and Releases)
- **DirtyFrag** (alternative temporary-root tool, same purpose as DFRoot, if one stops working on a future patch): https://github.com/mitschud/DirtyFrag
- **KernelSU manager** (used with DFRoot): https://github.com/tiann/KernelSU/releases
- **LK bootloader patcher (Val Protocol):** https://github.com/Maikyxd/val-protocol
- **Modem SIM-unlock tool (vegas-freedom):** https://github.com/andrewwm/vegas-freedom , this is THE modem tool for vegas26. A modem-unlock tool built for another Motorola codename (for example a `kansas`-targeted one) is NOT for this device; do not substitute it. The `check` gate in Part 3 is what proves a tool/source matches your modem.
- **LineageOS microG GSI builds:** the lineageos-4-microg / Colors project (SourceForge), or the MisterZtr GSI index: https://github.com/MisterZtr/LineageOS_gsi
- **Stock firmware mirror** (for the `md1img`): https://mirrors.lolinet.com/firmware/moto/
- **Google Android 16 GSI release notes** (documents the reboot-after-flash issue): https://developer.android.com/about/versions/16/gsi-release-notes
- **Magisk** (only needed for the optional rooted overlays in Part 5): https://github.com/topjohnwu/Magisk
- **Open Camera** (rootless 2nd-camera fix in Part 5): https://f-droid.org/packages/net.sourceforge.opencamera/

## How the pieces fit (the layer model)

Understanding these four independent layers makes everything below make sense, and explains why you can update without losing your changes:

- **`system`** = the LineageOS GSI. You flash upstream updates here; it is replaced wholesale on each update.
- **`product`** (and `vendor`) = stock Motorola partitions. A GSI flash does NOT touch them, so anything you place here (optional overlays, Part 5) survives updates.
- **`userdata` (`/data`)** = your apps and settings. Survives flashing a new GSI (see the hot-swap note in Part 2).
- **`md1img`** = the modem. Your SIM unlock lives here and is untouched by OS flashing.

---

## Part 1: Bootloader unlock

### 1.0 Verify, don't assume
```powershell
adb shell getprop ro.boot.hardware.sku            # XT2617V
adb shell getprop ro.build.fingerprint            # ...-4-3/...
adb shell getprop ro.build.version.security_patch # 2026-06-01
adb shell getprop ro.boot.slot_suffix             # _a
adb shell getprop ro.boot.flash.locked            # 1 (locked)
```

**Block updates before you do anything else.** An automatic OTA can patch out the exact vulnerabilities this process depends on (the temp-root CVE and the LK weakness), and once patched there is no known way back in. Turn Wi-Fi off and keep it off until the bootloader is unlocked, and belt-and-suspenders it with:
```powershell
adb shell svc wifi disable
adb shell settings put global ota_disable_automatic_update 1   # extra precaution; does not cancel an already-staged update
```
If an update is already downloading, turn Wi-Fi off; if it has staged and wants a restart, do NOT restart until you have temp root and have checked the slot state.

### 1.1 Temporary root (reversible, undone by reboot)
Install the KernelSU manager + DFRoot APKs (hash-verify against the base guide), then on the phone:
1. DFRoot: select KernelSU as SU manager, then "Launch Root once" (Start-at-Boot / Auto-Soft-Reboot / Disable-KSU-Modules all OFF).
2. KernelSU shows "Working [Jailbreak mode]".
3. KernelSU, Superuser, enable Shell (`com.android.shell`). Without this, `adb shell su` returns "inaccessible or not found".
```powershell
adb shell su -c id     # uid=0(root) ... context=u:r:ksu:s0
```
This root can write block devices, which the `frp` bypass and the modem backup both need.

### 1.2 Full backup (while temp root is live)
`dd` each partition to a file, pull to PC, verify SHA-256 both sides:
```
lk_a lk_b boot_a init_boot_a vendor_boot_a vbmeta_a vbmeta_system_a misc
nvram nvdata seccfg persist prodpersist proinfo protect1 protect2 dtbo_a preloader_raw_a frp md1img_a
```
Keep all of these private. `md1img_a` (~76 MB) is your modem revert for Part 3.

### 1.3 Patch and flash LK
On PC (val-protocol venv, `pip install -r requirements.txt` plus `pyasn1`):
```powershell
python lk_static_analyzer.py <backup>\lk_a.img -o lk-analysis --no-full-disasm
python lk_auto_patch.py <backup>\lk_a.img -o lk.unlock-serial.img `
  --analysis-dir lk-patch-analysis --preset unlock-serial --key-token-secret <SECRET> --keep-workdir
```
`lk_auto_patch` must print `Result: VALID`. The `-4-3` LK payload is 1,238,664 bytes (identical to `-4-2`).

**Windows fastboot driver bind:** in bootloader mode the phone is `USB\VID_22B8&PID_2E80` and may show `CM_PROB_FAILED_INSTALL`. In Device Manager: the Android device, Update driver, Browse, Let me pick, Have Disk, `android_winusb.inf`, uncheck "Show compatible hardware", "Android Bootloader Interface". Note: **fastbootd enumerates as a separate device** and needs this bind done again.

```powershell
fastboot getvar serialno                # <YOUR SERIAL>
python lk_keygen.py --secret <SECRET> --serialno <YOUR SERIAL> --count 5
fastboot flash lk_a lk.unlock-serial.img
fastboot reboot bootloader
```

### 1.4 The carrier OEM-unlock wall
On a Tracfone unit `fastboot oem unlock <KEY>` fails with "Check 'Allow OEM Unlock'", and that toggle is greyed out. Cause: a UserManager restriction `no_moto_oem_unlock`, re-applied at runtime by a carrier component, and the backing file is fs-verity protected.

Bypass: set the OEM-unlock flag directly in `frp` (the last byte of the AOSP Persistent Data Block, `0x01` = enabled). With temp root:
```sh
RP=$(realpath /dev/block/by-name/frp); SZ=$(blockdev --getsize64 "$RP")   # 1048576
blockdev --setrw "$RP"
printf '\001' | dd of="$RP" bs=1 seek=$((SZ-1)) conv=notrunc
dd if="$RP" bs=1 skip=$((SZ-1)) count=1 2>/dev/null | od -An -tx1          # -> 01
```
Then reboot straight to the bootloader (so Android cannot reset it) and unlock:
```powershell
adb reboot bootloader
fastboot oem unlock <ONE OF YOUR KEYS>
fastboot getvar securestate              # -> flashing_unlocked
```
Low-risk: a wrong byte just means unlock is refused again (no wipe), and unlocking disables FRP anyway.

### 1.5 After the unlock wipe: get past the carrier activation screen

Unlocking the bootloader erases userdata (so does any later `/data` wipe, e.g. for a GSI). On a Straight Talk / Tracfone unit the phone then boots to a carrier **activation screen** you cannot pass without a plan, which strands the whole process if you are not ready for it. Get around it with Google's official **Test DPC** enterprise provisioning. This is ordinary Android setup provisioning on a device you own; it is not cellular activation or SIM unlocking.

1. Power off and **remove the carrier SIM** (so it cannot re-assert a network lock during setup), then boot.
2. At the first Welcome/Hello screen, tap the **same blank spot six times** to open Android's enterprise-provisioning QR scanner.
3. Scan Google's official [Test DPC QR](https://raw.githubusercontent.com/googlesamples/android-testdpc/master/qrcode.png) (from the [Test DPC project](https://github.com/googlesamples/android-testdpc#provisioning)). Connect to Wi-Fi so Test DPC downloads. Use the Google QR only, never a QR from an unknown administrator.
4. Choose **Use for work only**, then at Finish Setup tap **Finish**. You land on the home screen.
5. **Turn Wi-Fi off immediately** and keep updates blocked (see the Part 1 update note) until the bootloader is unlocked.
6. Enable Developer options (tap Build number seven times) and turn on USB debugging.
7. **Remove the Test DPC device-owner** so nothing stays managed (its own UI may crash; the ADB service path works):
```powershell
adb shell dumpsys activity service com.afwsamples.testdpc/.DeviceAdminService clear-device-owner
adb shell dumpsys device_policy          # should show NO Device Owner / Profile Owner
adb shell pm uninstall com.afwsamples.testdpc   # expect: Success
```
Do not just uninstall an active device owner or factory-reset to clear it; clear ownership first with the command above. Do not scan the QR again once setup is complete.

You repeat this entire setup every time userdata is wiped: once after the bootloader unlock, and again if you later factory-reset for a GSI. Credit: the [parsimo2010 base guide](https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide) documents this Test DPC flow; an independent community report corroborated it on `-4-3` (using a ManageEngine MDM as an alternative route to the same bypass).

---

## Part 2: Install the LineageOS GSI

"LineageOS on this phone" means a GSI flashed to `system`. No device-specific port, no TWRP; `fastbootd` does everything. Use **LineageOS 23.2 microG** (Android 16): it is the one that ships `com.mediatek.ims`, so VoLTE works (Lunaris-AOSP and others do not). Get the arm64 **A/B, ext4** build.

### 2.1 GSI readiness (this device passes)
```
ro.treble.enabled=true   ro.boot.dynamic_partitions=true   ro.virtual_ab.enabled=true
ro.product.first_api_level=36   ro.product.cpu.abi=arm64-v8a   ro.vndk.version=33 (use REGULAR, not vndklite)
```

### 2.2 THE CRITICAL FIX: how you wipe decides whether it survives a reboot
Symptom that traps everyone: after flashing a GSI and running `fastboot -w`, it boots fine the **first** time, then **bootloops on the second boot** to "Can't load Android system, your data may be corrupt". (It loops with no SIM in, too, so the SIM is a red herring.)

Cause: `/data` uses metadata encryption with hardware-wrapped keys. `fastboot -w` **erases but does not format** `/data` and `/metadata` (you will see `Erase successful, but not automatically formatting`). First boot creates a key on raw space; the reboot cannot re-derive it.

Fix: **wipe `/data` via stock recovery, not `fastboot -w`.** Recovery's factory reset formats `/data` and provisions the wrapped key through the vendor TEE, after which all reboots survive. (Google's A16 GSI notes prescribe the same.)

To reach it: bootloader menu, Recovery mode, you land on "No command", **hold Power and tap Volume Up once**, the hidden menu appears, Wipe data/factory reset. (Or let the "Can't load Android system" screen appear and tap its Factory reset button.)

### 2.3 Flash (recovery wipe, not `-w`)
```
# decompress (.xz, not .gz):  xz -d LineageOS-23.2-....-microG-gsi.img.xz
adb reboot bootloader
# verified boot OFF, FROM THE BOOTLOADER (fastbootd cannot see vbmeta on this device):
fastboot --disable-verity --disable-verification flash vbmeta        vbmeta_a.img
fastboot --disable-verity --disable-verification flash vbmeta_system vbmeta_system_a.img
fastboot reboot fastboot                 # fastbootd (re-bind the USB driver here)
fastboot flash system LineageOS-23.2-....-microG-gsi.img
fastboot reboot
# it will fail to boot onto stale /data and show "Can't load Android system"
# tap FACTORY RESET (NOT fastboot -w); first clean boot takes 5-10 min
```
If `flash system` reports "not enough space", in fastbootd: `fastboot delete-logical-partition product_a` (and `_b`), then reflash (reversible).

### 2.4 Hot-swap note (updates and A/B are non-destructive)
Once `/data` has been properly formatted once (via recovery), you can flash a different GSI to `system` and just `fastboot reboot`; it reuses the good `/data`, skips setup, and survives reboots. This is how you apply **updates** without wiping (see [How updates work](#how-updates-work)).

### 2.5 Back to stock
Restore the stock `system` from your backup, reflash stock `vbmeta`/`vbmeta_system` without the `--disable` flags, then wipe via recovery.

---

## Part 3: SIM / network unlock (modem)

The network-lock (`gsm.sim.state = NETWORK_LOCKED`) is separate from the bootloader unlock and is enforced by the MediaTek modem (`md1img`). IMEI and calibration live in `nvram`/`nvdata`/`protect*`, NOT in `md1img`, so this cannot erase your IMEI.

Tool: [vegas-freedom](https://github.com/andrewwm/vegas-freedom). Its `build` is pinned to the `-4-2` modem; newer builds use `check` then `build --experimental-relocate`. Source the `md1img` from a stock flashfile on the [lolinet mirror](https://mirrors.lolinet.com/firmware/moto/) (standalone `md1img.img` inside the zip).

**Verified compatibility (the one tested datapoint):** a `-4-7`-sourced stock `md1img`, patched with `--experimental-relocate`, runs fine on a `-4-3` phone. That is the only combination proven on hardware here. There is **no tested multi-version matrix and no committed hashes** (modem binaries are gitignored and device-sourced). So the safety gate is not a version table, it is the `check` step: **`check` must print `CANDIDATE MATCH` (3/3 CATI symbols, 8/8 microMIPS32 signatures) against your stock `md1img` before you build or flash.** If it does not, you have the wrong source build or the wrong tool; stop and do not flash.

```powershell
# venv needs capstone and pyasn1
python modem/unlock_vegas.py check  <stock md1img.img>
#   -> 3/3 CATI symbols, 8/8 microMIPS32 signatures, "CANDIDATE MATCH"
python modem/unlock_vegas.py build --experimental-relocate -o md1img_patched.signed.img <stock md1img.img>
#   -> audit: entries=23 layout_ok=True integrity=True ; all sub-images hash_ok and rsa_ok

# flash the A slot ONLY (never md1img_b), bootloader unlocked:
fastboot flash md1img_a md1img_patched.signed.img
fastboot reboot
```
Result: `gsm.sim.state` goes `NETWORK_LOCKED` to `LOADED`, registered on your carrier. Keep the stock `md1img` as the revert. **Never flash `md1img_b`, `preloader`, `lk`, `seccfg`, `gpt`, `efuse`, `nvram`, `nvdata`, `protect*`.**

---

## Part 4: Cellular, APN and VoLTE

### 4.1 Mobile data (APN)
Enter your carrier's APN. For US Mobile Dark Star it is `ereseller` (LineageOS already ships matching "Tracfone AT&T" / "ereseller" entries; just select one in Settings, Network and internet, SIMs, the SIM, Access Point Names). Toggle airplane mode once if it is slow to attach.

### 4.2 VoLTE (works natively on LineageOS)
On a clean LineageOS 23.2 microG install, with no extra steps, VoLTE calls work because the GSI ships the real MediaTek IMS stack:
```
adb shell pm list packages | grep mediatek.ims
#   com.mediatek.ims  com.mediatek.ims.overlay  com.mediatek.ims.overlay.telephony
```
Verify a call is true VoLTE with a live radio capture (`adb logcat -b radio -b main` during a call): look for `MtkMmTelFeature`, `useImsForCall=true`, `imsService=com.mediatek.ims.ImsService`, an IMS `pcscf:` and a `qci:1` voice bearer, and `SCP_REGISTER_FEATURE_FOR_VOICE_CALL success`. SMS also rides IMS.

Note: Lunaris-AOSP and other GSIs that lack `com.mediatek.ims` will NOT do VoLTE no matter what toggles you set, which is the whole reason to use LineageOS here. Debugging tip: trust a live call capture over a one-off `pm list` / `logcat -d` grep (those gave false negatives during this project), and `mVopsSupport=2` means UNKNOWN, not "not supported".

---

## Part 5: Optional polish (cameras, cutout, density)

All optional, all non-destructive. Two of these have a rootless path that works today, and a rooted path for the perfect result.

### 5.1 Second rear camera
The HAL exposes all cameras (`dumpsys media.camera` shows 3). LineageOS Aperture hides the aux rear lens because `config_enableAuxCameras` defaults to false on a GSI.
- **Rootless (works now):** install [Open Camera](https://f-droid.org/packages/net.sourceforge.opencamera/), set Settings, Camera API, Camera2 API; the camera-switch button (and the "camera +" control) selects the 2nd rear lens.
- **Rooted (stock Material app):** deploy the Aperture RRO in `overlays/aperture-aux/` (sets `config_enableAuxCameras=true`) so the stock Aperture app itself shows both lenses. See 5.4 for deployment.

### 5.2 Display cutout (hole-punch)
On a GSI no cutout is defined, so apps draw into the camera area.
- **Rootless (approximate):** `adb shell cmd overlay enable com.android.internal.display.cutout.emulation.tall` reserves a centered top strip. The built-in `...emulation.hole` is a circle but anchored top-left (wrong for a centered camera). Disable with `cmd overlay disable <package>`.
- **Rooted (perfect centered circle):** deploy the framework RRO in `overlays/cutout/` (a centered `config_mainBuiltInDisplayCutout`). See 5.4. Tune the circle's center-y and radius in `res/values/config.xml` to match your camera exactly.

### 5.3 Display density
Default GSI density (390) renders a touch small on this 1080x2388 panel. Adjust in Settings, Display, Display size (persists, no adb), or `adb shell wm density 410` (`wm density reset` to revert). 410-420 feels right.

### 5.4 Deploying the overlays (the root part), and why it survives updates
Custom overlays that target the framework (`android`) or a system app cannot be sideloaded to `/data` on this GSI (install is rejected: "signed with different certificates"), because the GSI's platform key is private. They must live in a **trusted system partition**. Putting them in **`/product/overlay`** is ideal: `/product` is a stock partition that a GSI system-flash does NOT touch, so your overlays **survive every OS update** (no re-baking).

This step needs root, once. On this device:
- `adb root` breaks USB (adbd restarts, the gadget drops), so do NOT rely on it. Root with **[Magisk](https://github.com/topjohnwu/Magisk)** by patching `init_boot` instead (persistent, systemless).
- With root, place the overlay APKs in `/product/overlay/` with owner `0:0`, mode `0644`, and the same SELinux context as the existing overlays there (read one with `ls -Z /product/overlay`). If `/product` is read-only (EROFS or verity), use a **Magisk module** to inject the files instead of editing the partition.
- Build each overlay from its source with `aapt2` + `apksigner` (self-signed is fine in a system partition); see `repack.sh` for the exact commands. Make them static (`android:isStatic="true"`) to auto-enable, or enable mutable ones once with `cmd overlay enable --user 0 <package>`.

This is the one advanced, device-specific step and was not fully hardened in this writeup; treat it as a starting point and verify `cmd overlay list` shows your overlays enabled after a reboot.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `fastboot devices` is empty, or a command hangs on `< waiting for any device >` | Fastboot driver not bound for this mode | Bind "Android Bootloader Interface" in Device Manager (Part 1.3). Bootloader and fastbootd are **separate devices**, bind both. |
| `adb` keeps dropping every couple of minutes | Windows USB power saving | Disable USB selective suspend (Power Options), use a direct port, replug. |
| `adb root` makes the phone vanish from USB | adbd restart drops the USB gadget on this GSI | Don't use `adb root`. Use plain adb, or Magisk for root. |
| GSI boots once, then "Can't load Android system" on every reboot | `fastboot -w` doesn't format `/data` | Wipe via **recovery factory reset** (Part 2.2). |
| Can't find "Wipe data" in recovery | Menu is hidden behind "No command" | Hold **Power**, tap **Volume Up** once (Part 2.2). |
| `fastboot oem unlock` says "Check 'Allow OEM Unlock'" | Carrier restriction | `frp` last-byte bypass (Part 1.4). |
| Stuck at the carrier activation / setup screen after a wipe | Tracfone activation lock on a device with no plan | Google Test DPC provisioning bypass, then remove the device-owner (Part 1.5). |
| "SIM network unlock PIN" / `NETWORK_LOCKED` | Carrier lock in the modem | Part 3. |
| Signal bars but no data, "!" on the signal icon | Wrong or missing APN | Select the `ereseller` (or your carrier's) APN, toggle airplane mode (Part 4.1). |
| Calls fail but data works | GSI lacks MediaTek IMS | Use LineageOS 23.2 microG (ships `com.mediatek.ims`). |
| Overlay install fails: "signed with different certificates" | Framework overlays can't be sideloaded on this GSI | Deploy to `/product/overlay` with root (Part 5.4). |

## How updates work

The LineageOS microG GSI is built and released by its maintainer; you get new builds with current security patches, but **GSIs have no auto-OTA** (the LineageOS Updater app only serves official device builds). To update:

1. Download the newer GSI image from the maintainer.
2. `fastboot flash system <new-image>` in fastbootd.
3. Reboot.

Your `/data`, apps, settings, your `/product` overlays (Part 5), and your modem unlock all **persist** (see the layer model). That is the hot-swap from 2.4: non-destructive, about 5 minutes, done whenever you check the maintainer's page. This gives you LineageOS's ongoing updates long after Motorola would stop, applied by hand instead of a tap. The vendor and modem stay frozen at the current version, which is expected and fine.

## Repo contents

- `README.md` , this guide.
- `overlays/cutout/` , framework RRO source for a centered display cutout (edit `res/values/config.xml` to match your camera).
- `overlays/aperture-aux/` , RRO source to make the stock Aperture camera expose the 2nd rear lens.
- `repack.sh` , reference script to build the overlays and (optionally) bake them into an ext4 GSI's `/system/product/overlay`, for anyone who wants a prebuilt image instead of deploying overlays by hand.

## Credits and prior work

- Base bootloader guide: [parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide](https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide)
- LK patcher: [Maikyxd/val-protocol](https://github.com/Maikyxd/val-protocol)
- Modem SIM-unlock: [andrewwm/vegas-freedom](https://github.com/andrewwm/vegas-freedom)
- LineageOS GSI builds: the lineageos-4-microg / Colors project, and [MisterZtr/LineageOS_gsi](https://github.com/MisterZtr/LineageOS_gsi)
- Firmware mirror: [lolinet](https://mirrors.lolinet.com/firmware/moto/)
- Open Camera, Magisk, and the AOSP/LineageOS projects.

## Quick reference

- Temp root (DFRoot 4.7 + KernelSU 3.3.1): works (`ksu:s0`).
- LK payload `-4-3` equals `-4-2`: 1,238,664 bytes; `lk_auto_patch --preset unlock-serial` prints VALID.
- Tracfone OEM-unlock wall: `no_moto_oem_unlock`; bypass by writing `0x01` to the last byte of `frp`, then `fastboot oem unlock`.
- GSI reboot-loop equals the wipe method: `fastboot -w` leaves `/data` raw; wipe via recovery factory reset instead; then GSIs hot-swap without wiping.
- LineageOS 23.2 microG gives data, SMS, and VoLTE (ships `com.mediatek.ims`). Pick it over GSIs that lack the MediaTek IMS stack.
- SIM unlock: vegas-freedom `check` (8/8), `build --experimental-relocate`, `fastboot flash md1img_a`; `NETWORK_LOCKED` to `LOADED`. Stock `md1img` kept as revert; IMEI untouched.
- Custom overlays must live in a trusted partition (`/product/overlay`, survives updates); needs Magisk root once. Rootless alternatives: Open Camera, and a built-in cutout emulation overlay.
