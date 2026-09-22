#!/system/bin/sh
# Sourced by Audio Modification Library after it has assembled its audio config.
# Do not modify AML, Viper, DSP, ACDB, mixer paths, or any effect other than
# the broken default Qualcomm AEC attachment for VOICE_COMMUNICATION.

aml_vendor_effects="$MODPATH/system/vendor/etc/audio_effects.xml"
[ -f "$aml_vendor_effects" ] || return 0

sed -i '/^[[:space:]]*<effect name="aec" library="audio_pre_processing" uuid="0f8d0d2a-59e5-45fe-b6e4-248c8a799109"\/>[[:space:]]*$/d' "$aml_vendor_effects"
sed -i '/^[[:space:]]*<apply effect="aec"\/>[[:space:]]*$/d' "$aml_vendor_effects"

return 0
