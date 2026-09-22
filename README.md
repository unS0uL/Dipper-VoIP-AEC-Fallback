# Dipper VoIP AEC Fallback

A small systemless Magisk module for Xiaomi Mi 8 (`dipper`) that fixes severe far-end echo during speakerphone VoIP calls.

It targets one specific failure mode: Qualcomm hardware AEC is exposed and enabled, but fails to cancel echo on the speakerphone capture route. The module does **not** replace DSP firmware, ACDB calibration, the audio HAL, `/vendor`, drivers, or microphone routing. It only stops Android from automatically attaching that faulty AEC to `VOICE_COMMUNICATION` capture. Stock Qualcomm Noise Suppression (NS) remains enabled.

## Verified result

| Item | Verified configuration |
|---|---|
| Device | Xiaomi Mi 8 (`dipper`), China 256 GB |
| ROM | crDroid 10.10 |
| Android | 14 |
| Root | Magisk 30.7 |
| Vendor stack | Qualcomm SDM845 / Fluence |

Results after installation:

- Telegram earpiece mode: normal voice capture;
- Telegram speakerphone: far-end echo removed and NS retained;
- cellular calls in both earpiece and speakerphone modes: no regression observed.

During the successful Telegram speakerphone call, ADB confirmed `MODE_IN_COMMUNICATION`, `speaker-dmic-endfire`, ACDB 116, and `Noise Suppression / Qualcomm Fluence` as the only Android record pre-processing effect.

## AEC and NS in plain language

**AEC** (Acoustic Echo Cancellation) receives a copy of the remote caller's audio before it reaches the loudspeaker. It estimates the part that leaks back into the microphone through air and the device enclosure, then subtracts it from your outgoing audio.

AEC depends on delay, phase, loudspeaker distortion, microphone sensitivity, and device geometry. It can be present and enabled yet fail on one route, which was the observed Mi 8 speakerphone behavior.

**NS** (Noise Suppression) reduces background noise in the microphone stream. This module keeps the stock Qualcomm Fluence NS implementation. It does not add or alter AGC (automatic gain control).

With the broken Android hardware AEC no longer advertised for VoIP, an app may use its own software echo processing. Telegram improved substantially in the verified configuration. The module does not modify Telegram itself.

## Exact change made by this module

The module overlays a copy of `/vendor/etc/audio_effects.xml` through Magisk. Only these two Qualcomm AEC entries are removed:

```xml
<effect name="aec" library="audio_pre_processing" ... />
<apply effect="aec"/>
```

The Qualcomm NS entries remain unchanged:

```xml
<effect name="ns" library="audio_pre_processing" ... />
<apply effect="ns"/>
```

This applies to Android `VOICE_COMMUNICATION` capture, typically used by Telegram, Signal, Discord, and WebRTC-based apps. A cellular `VOICE_CALL` normally follows a separate vendor path, so it must be tested after installation.

## Call coverage

| Call type | What the module changes | Tested result on crDroid 10.10 |
|---|---|---|
| VoIP applications (Telegram/WebRTC) | Directly changes the default `VOICE_COMMUNICATION` AEC attachment | Speakerphone far-end echo removed; voice capture and NS remained acceptable |
| Stock dialer / cellular call (3G/4G/VoLTE where available) | Does not directly reconfigure the separate `VOICE_CALL` vendor path | Earpiece and speakerphone calls completed without far-end echo or voice-quality regression |

Do not interpret the cellular result as a claim that this module retunes cellular DSP. It is a post-install regression test: it confirms that the VoIP overlay did not harm the standard dialer path on the verified device.

## Compatibility — read before installing

This is **not a universal audio module**. The release ZIP is intentionally restricted to Xiaomi Mi 8 (`dipper`) with one of these verified `audio_effects.xml` checksums:

```text
6eb46150017639cd283c8c6e4aee8b39ac7b1a9849104e7ab2a6bd048b6b35e6  stock tested XML
9737dc9dad0f2c6a37f44be98456a1929fe9fe23ef4afb400979a60f65b2c008  this module already active
```

The installer aborts for another device or unknown vendor XML. Do not bypass this check. A copied `audio_effects.xml` from this device could hide required effects on another phone, even one using the same Snapdragon chipset.

For a different Mi 8 ROM, first compare its vendor XML, reproduce the fault, inspect the active route/effects, and create a device-specific overlay from that ROM's own file.

## crDroid support status

| ROM | Status | Evidence |
|---|---|---|
| crDroid 10.10 / Android 14 | **Verified** | Live Telegram and cellular-call tests on the configuration listed above |
| Official crDroid 11.17 / Android 15, `dipper`, build 2026-08-05 | **Code-compatible; not field-tested** | The official device and common source trees have the same SHA-256 for `audio_effects.xml`, `mixer_paths_tavil.xml`, `audio_platform_info.xml`, and both mixer overlay files as the verified Android 14 configuration. The installer checksum gate therefore accepts the known stock XML. |
| Any future crDroid release or other ROM | **Not claimed** | Re-check the source XML and complete VoIP plus cellular-call tests before installation. |

The latest official crDroid build published for `dipper` at the time of this analysis is 11.17 (Android 15). [Official download page](https://crdroid.net/dipper/11).

## Installation

Current tested build: [Dipper-VoIP-AEC-Fallback-v1.2.zip](https://github.com/unS0uL/Dipper-VoIP-AEC-Fallback/releases/latest)
SHA-256: `e6c19c56110c3a0c5614c4a6b86086158ea73d8b7569f68331314cdb8545f5de`

1. Back up your boot image and make sure Magisk works.
2. Download the current release ZIP above or from GitHub Releases.
3. In Magisk, open **Modules** → **Install from storage** and select the ZIP.
4. Reboot.
5. Test VoIP in earpiece mode, VoIP in speakerphone mode, then a cellular call in both modes.

After reboot, Magisk should list **Dipper VoIP AEC Fallback** as enabled.

### Optional ADB verification

During an active VoIP call:

```sh
adb shell su -c 'dumpsys media.audio_flinger | grep -E "Acoustic Echo Canceler|Noise Suppression|Qualcomm Fluence"'
```

For the verified profile, the active VoIP record chain contains `Noise Suppression / Qualcomm Fluence`; it does not contain the Qualcomm `Acoustic Echo Canceler` effect.

## Rollback

1. In Magisk → **Modules**, disable or remove the module.
2. Reboot.

The original `/vendor/etc/audio_effects.xml` returns automatically because `/vendor` is never written. If the Magisk app is unavailable, create the module's `disable` file from recovery or ADB:

```sh
su -c 'touch /data/adb/modules/dipper_voip_aec_fallback/disable'
```

Then reboot.

## Limitations

- This does not repair a failed microphone, loudspeaker, lower USB board, or physical acoustic seal.
- Android exposes NS as on/off; it does not expose a safe public "NS strength" slider for Qualcomm Fluence.
- Keyboard clicks are short transients, not steady noise. Stronger generic NS can damage consonants and make speech metallic before it removes all keyboard noise.
- Do not alter gain, DMIC routing, echo-reference controls, ACDB, or DSP firmware live. Those parameters are HAL/DSP-owned and device-calibrated.
- Not every VoIP application is guaranteed to supply a good software AEC fallback. Test each app independently.

## Technical documentation

- [Technical research summary](docs/RESEARCH.md)
- [Android AcousticEchoCanceler API](https://developer.android.com/reference/android/media/audiofx/AcousticEchoCanceler)
- [Android NoiseSuppressor API](https://developer.android.com/reference/android/media/audiofx/NoiseSuppressor)
- [AOSP pre-processing configuration](https://source.android.com/docs/core/audio/implement-pre-processing)
- [WebRTC Audio Processing Module](https://webrtc.googlesource.com/src/+/f981cb3d2e2b053669c2827332574907128592f3/modules/audio_processing/g3doc/audio_processing_module.md)

## Disclaimer

Use at your own risk. Do not transplant ACDB files, ADSP firmware, audio libraries, or mixer XML from another phone as a shortcut. Those components are device-calibrated and outside this module's scope.
