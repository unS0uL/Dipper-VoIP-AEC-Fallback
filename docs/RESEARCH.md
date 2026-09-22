# Technical research summary

This document records the evidence behind the module design. It is not an installation guide; see the [project README](../README.md) first.

## Problem statement

On a Xiaomi Mi 8 (`dipper`) running crDroid 10.10 / Android 14, the far end heard a strong copy of its own speech during Telegram speakerphone calls. The same phone had acceptable voice capture in earpiece mode. Restoring a single-microphone Fluence route reduced echo but degraded ordinary VoIP capture, so it was rejected as a permanent workaround.

## Hardware and software path

```text
VoIP app / WebRTC
  -> Android AudioRecord (VOICE_COMMUNICATION)
  -> Android audio effects configuration
  -> Qualcomm audio HAL and sound-device selection
  -> mixer_paths_tavil.xml
  -> Qualcomm Fluence / ACDB / ADSP
  -> WCD9340 codec and microphone array
```

Relevant mixer paths in the tested vendor:

| Use case | Mixer path | Microphone transport |
|---|---|---|
| Handset end-fire | `handset-dmic-endfire` | DMIC2 + DMIC4 |
| Speaker end-fire | `speaker-dmic-endfire` | DMIC1 + DMIC5 |
| Speaker single mic | `speaker-mic` | DMIC1 |
| VoIP speaker reference | `echo-reference voip-speaker` | `QUAT_MI2S_TX` |

The speakerphone path is therefore not missing a second microphone or an echo-reference definition.

## Evidence collected

### Active failing path before the fix

During Telegram calls:

- audio mode: `MODE_IN_COMMUNICATION`;
- capture source: `VOICE_COMMUNICATION`, mono, 48 kHz;
- output: speakerphone;
- Qualcomm `Acoustic Echo Canceler` and `Noise Suppression` were attached to the record session;
- HAL selected `speaker-dmic-endfire` for `audio-record-voip`.

This ruled out the common explanation that the app was using a normal-media capture path without AEC/NS.

### Vendor components verified

The tested vendor contains the expected Qualcomm components:

| Component | SHA-256 |
|---|---|
| `Forte_Speaker_cal.acdb` | `5aa4ab6f404d23bbc79c9cc7a3e5ad0af6132952861e7a9311bcdc79776a5d80` |
| `Forte_Handset_cal.acdb` | `e79e3c77b4bf2e8235d6a77d9029de14a1c56901796ba15c5e9231acc6cab2fa` |
| `Forte_Global_cal.acdb` | `abc719a85691d27be9ffe12e8dea6f66234198227aeb895de1f41c88d2228ef1` |
| `adsp_avs_config.acdb` | `80574d33b788902951e6fce1318dbce0438eb9c5bc123bc7d9b5842d41dec9c8` |
| 32-bit `libqcomvoiceprocessing.so` | `c19aaca8162817272c5ec2222fad7ee56ebf59702e06060fa5893ec991673a6d` |

The three Forte calibration files match the Mi 8 MIUI-derived vendor blobs used by LineageOS. That makes a missing DSP library or a generic ACDB replacement an unlikely and unsafe solution.

### Configuration provenance

The local `/vendor/etc/mixer_paths_tavil.xml` has SHA-256:

```text
e91b9fa2e5c47dc0c3b77de82884d107211c36d542b95e0f3ea5c1d9a9ce67b9
```

It exactly matches the LineageOS Xiaomi SDM845-common configuration. The relevant speakerphone/end-fire/echo-reference sections were unchanged from the earlier MIUI-derived configuration. No evidence justified transplanting another device's mixer XML.

## Rejected approaches

| Approach | Why it was rejected |
|---|---|
| Import ACDB, ADSP firmware, or audio libraries from another phone | These files are calibrated for microphone sensitivity, enclosure acoustics, device IDs, and delays. They can worsen echo or break audio. |
| Permanently set `persist.vendor.audio.fluence.speaker=false` | It reduced echo in a temporary experiment but impaired ordinary VoIP capture and did not switch cleanly inside a session. |
| Manually force an echo-reference mixer control | A live A/B test did not produce a meaningful improvement; HAL-owned controls can be reset on route changes. |
| Raise microphone gain | It increases both background noise and residual echo. |
| Install a generic audio enhancer | Equalizers and playback enhancements do not repair capture-path AEC. |

## Implemented experiment

The module uses a Magisk overlay of the tested device's `audio_effects.xml` and removes only:

1. the Qualcomm `aec` effect declaration;
2. the default `<apply effect="aec"/>` for the `voice_communication` stream.

The `ns` declaration and default application remain. No physical vendor file is modified.

After reboot, a live Telegram speakerphone call showed:

- `MODE_IN_COMMUNICATION`;
- output speaker;
- input `speaker-dmic-endfire`, ACDB 116;
- Qualcomm Noise Suppression present;
- Qualcomm Android AEC absent;
- user-reported major echo reduction, normal voice level, and acceptable noise suppression.

Telegram earpiece calls and cellular calls in both modes also passed a user test without regression.

The Android framework does not reveal Telegram's internal algorithm. Therefore the correct statement is: removing the ineffective Android hardware AEC allowed an effective application-level fallback in the tested Telegram call; it does not prove a particular Telegram AEC implementation or guarantee the same behavior in every app.

## Known interaction: AML + ViPER4AndroidFX

After the successful baseline test, Audio Modification Library (AML) and ViPER4AndroidFX were enabled together and the phone booted normally. Static post-boot checks still showed the expected AEC-free overlay and Qualcomm NS. However, the user reported that speakerphone far-end echo returned during a call with both modules enabled.

This is recorded as a **user-confirmed, live-call incompatibility**. It has not yet been isolated to AML, Viper, a Viper driver state, or their combination with a live ADB trace. Do not claim compatibility; keep both modules disabled until a dedicated A/B investigation is completed.

### AML integration analysis

Read-only inspection of the installed modules identifies a concrete configuration conflict:

1. ViPER4AndroidFX ships its own `system/vendor/etc/audio_effects.xml`. That file contains the stock Qualcomm AEC declaration and the default `voice_communication` AEC application.
2. The current Dipper module also ships `system/vendor/etc/audio_effects.xml`, but with those two AEC lines removed.
3. AML's `post-fs-data.sh` moves audio configuration files from every enabled audio mod into its merge workspace. Its `service.sh` then merges effects and remounts the generated result before restarting `audioserver`.

The current Dipper module is a raw overlay and does not provide AML's optional `aml.sh` hook. Consequently AML can merge Viper's stock-AEC configuration back into the final XML, undoing the fallback. This accounts for the observed echo returning when AML and Viper are enabled together.

### Feasible AML-aware design

An AML-aware version can include a small `aml.sh` hook. AML sources this hook after it has merged enabled audio mods. The hook would operate only on the final AML-managed vendor `audio_effects.xml` and remove exactly the same two AEC lines as the standalone overlay:

```text
<effect name="aec" ... />
<apply effect="aec"/>
```

It would leave the Viper library/effect, Qualcomm NS, all mixer paths, ACDB, DSP data, and cellular voice path untouched. This is the correct integration point because it avoids mount-order competition between AML, Viper, and the fallback module.

Starting with module v1.3, this `aml.sh` integration is shipped in the module. When AML finishes merging audio modifications, `aml.sh` removes the Qualcomm `aec` effect declaration and its `<apply effect="aec"/>` hook from AML's merged `audio_effects.xml`, keeping VoIP software AEC fallback active even with AML and ViPER4Android enabled.

## Why this is device-specific

Android selects default capture preprocessing from `/vendor/etc/audio_effects.xml`. That file lists vendor libraries and effect UUIDs which are not portable configuration values. Copying it to another model can remove effects that the other model needs.

The release installer enforces both device codename `dipper` and a known source XML checksum. Any port must start from the target ROM's own XML and repeat the route/effect verification.

## crDroid 11 / Android 15 source compatibility

The latest official `dipper` build available during this analysis is crDroid 11.17 / Android 15, build date 2026-08-05. Its OTA manifest identifies the device tree `crdroidandroid/android_device_xiaomi_dipper` and the common tree `crdroidandroid/android_device_xiaomi_sdm845-common`.

The 15.0 branch heads reviewed were `c3aaa8264afe8e9feebde82536bfb43c90c67c56` (device) and `3f83acb51e8aa061581262bb963ef1d2134b4d38` (common). The following 15.0 source files have exactly the same SHA-256 values as the verified 14.0 sources:

| File | SHA-256 |
|---|---|
| `common/audio/audio_effects.xml` | `6eb46150017639cd283c8c6e4aee8b39ac7b1a9849104e7ab2a6bd048b6b35e6` |
| `common/audio/mixer_paths_tavil.xml` | `e91b9fa2e5c47dc0c3b77de82884d107211c36d542b95e0f3ea5c1d9a9ce67b9` |
| `dipper/audio/audio_platform_info.xml` | `9c191833a73b217382a042cd0ccaddf56c6c15e0e721f899273a0dc541a733e4` |
| `dipper/audio/mixer_paths_overlay_static.xml` | `6f4173200a7ba4a64397245fe3b2733ebe6b957dffb0236386c2fd4c6945b6c3` |
| `dipper/audio/mixer_paths_overlay_dynamic.xml` | `eec92864bf318d058eb63e18cfce081426581b5e5ff8c16935e0e8a3f2007df6` |

This is strong evidence for **code compatibility**, not a field validation. Android 15 must still be tested after installation with VoIP and cellular calls. Future builds must be re-evaluated rather than assumed compatible.

## Primary sources

- [Android AEC API](https://developer.android.com/reference/android/media/audiofx/AcousticEchoCanceler)
- [Android NS API](https://developer.android.com/reference/android/media/audiofx/NoiseSuppressor)
- [AOSP: configure preprocessing effects](https://source.android.com/docs/core/audio/implement-pre-processing)
- [Qualcomm audio HAL: Fluence device mapping](https://android.googlesource.com/platform/hardware/qcom/audio/+/ee6d1cac7542f70f90f8203b3908ad5f24d016fe/hal/msm8974/platform.c)
- [Qualcomm on AEC sensitivity to acoustics and microphone arrays](https://www.qualcomm.com/news/onq/2021/01/fundamentals-voice-ui-part-i-building-blocks)
- [WebRTC Audio Processing Module](https://webrtc.googlesource.com/src/+/f981cb3d2e2b053669c2827332574907128592f3/modules/audio_processing/g3doc/audio_processing_module.md)
- [LineageOS issue #477: analogous ineffective speakerphone AEC route](https://github.com/LineageOS/issues/issues/477)
