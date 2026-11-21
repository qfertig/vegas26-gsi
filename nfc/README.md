# NFC HAL fix (GSI)

On a LineageOS GSI, NFC never comes up on vegas26: `com.android.nfc` ANRs about every 15 s, and `logcat` shows init repeating:

```
init: Could not find 'android.hardware.nfc@1.2::INfc/default' for ctl.interface_start
```

The NXP NFC HAL binary and its init script are in `/vendor` and survive the GSI:

```
/vendor/bin/hw/vendor.nxp.hardware.nfc@1.2-service
/vendor/etc/init/vendor.nxp.hardware.nfc@1.2-service.rc
```

But the service is `disabled` and only started by a property trigger:

```
on property:ro.vendor.hw.nfc=nq && property:persist.vendor.nfc.config_file_name=*
    start vendor.nfc_hal_service
```

`ro.vendor.hw.nfc=nq` is set by the vendor, but `persist.vendor.nfc.config_file_name` is empty on a GSI (on stock a Motorola component sets it). So the trigger never fires, the HAL never registers, and `com.android.nfc` hangs in startup.

## Fix

Set `persist.vendor.nfc.config_file_name` to any valid conf under `/vendor/etc` (e.g. `libnfc-nxp.conf`). The trigger fires, `vendor.nfc_hal_service` starts, the HAL registers, and NFC works:

- `dumpsys nfc` -> `mState=on`
- `lshal` lists `android.hardware.nfc@1.2::INfc/default` and `vendor.nxp.nxpnfc@2.0::INxpNfc/default`
- no more `com.android.nfc` ANR

## Applying the fix

### Native init `.rc` (preferred, no Magisk)

`nfc-hal-gsi.rc` sets the prop from init when the vendor marks the NFC chip present, which fires the vendor's own trigger. Put it in `/product/etc/init/` -- `/product` survives GSI system flashes (same place the overlays go, README Part 5.4), and init parses `.rc` files there with no runtime dependency.

```
# owner 0:0, mode 0644, context u:object_r:system_file:s0
/product/etc/init/nfc-hal-gsi.rc
```

Deploy it with root once like the 5.4 overlays, or bake it into the image's `/product/etc/init/` the way `repack.sh` bakes overlays into `/product/overlay`.

### Magisk module (easy)

The same prop, applied at every boot via `resetprop` in `post-fs-data.sh` (plus `system.prop`). Zip and flash from **Magisk -> Modules -> "+"**:

```
cd nfc && zip -r ../vegas-nfc-hal-fix.zip module.prop system.prop post-fs-data.sh
```

Reverted by disabling the module. `adb root` is off-limits on this GSI.

## Files

- `nfc-hal-gsi.rc` -- native init fix for `/product/etc/init/`.
- `module.prop`, `system.prop`, `post-fs-data.sh` -- the Magisk module.

Verified on LineageOS 23.2 microG, build `-4-3` vendor (NXP `nq`): `mState=on`, HAL registered, ANR gone.
