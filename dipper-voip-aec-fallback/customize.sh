ui_print "- Checking device and vendor audio configuration"

device="$(getprop ro.product.vendor.device)"
[ -n "$device" ] || device="$(getprop ro.product.device)"
[ "$device" = "dipper" ] || abort "Unsupported device: ${device:-unknown}. This module is only for Xiaomi Mi 8 (dipper)."

config=/vendor/etc/audio_effects.xml
[ -r "$config" ] || abort "Missing $config; installation aborted."

config_sha="$(sha256sum "$config" | awk '{print $1}')"
case "$config_sha" in
  6eb46150017639cd283c8c6e4aee8b39ac7b1a9849104e7ab2a6bd048b6b35e6|\
  9737dc9dad0f2c6a37f44be98456a1929fe9fe23ef4afb400979a60f65b2c008)
    ui_print "- Verified known dipper audio_effects.xml"
    ;;
  *)
    abort "Unsupported audio_effects.xml checksum: $config_sha. Do not install this device-specific overlay on an unverified vendor."
    ;;
esac
