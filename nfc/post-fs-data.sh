#!/system/bin/sh
# Fire the vendor NFC HAL init trigger that a GSI leaves unset.
# vendor.nfc_hal_service is "disabled" and only started by:
#   on property:ro.vendor.hw.nfc=nq && property:persist.vendor.nfc.config_file_name=*
#       start vendor.nfc_hal_service
# ro.vendor.hw.nfc is set by vendor; the config_file_name prop is empty on a GSI.
resetprop persist.vendor.nfc.config_file_name libnfc-nxp.conf
