# Offline wake engine notices and source provenance

Hermes packages sherpa-onnx 2.0.1 for **offline English wake detection only**.
No user enrollment, API key, model training or runtime model download is used.
Android's default speech-recognition service, selected TTS voice and gateway
remain separate and may use networks.

- **sherpa-onnx:** https://github.com/k2-fsa/sherpa-onnx
  Source revision `af2d8d81dbfa61c4cea4c568da78f3982edca005`, Apache-2.0.
  Complete license: `licenses/sherpa-onnx-Apache-2.0.txt`.
- **Model:** `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`.
  The exact archive's original `README.md` explicitly declares Apache License
  2.0; it is copied unmodified to `model-README.md` in the APK. Trained on
  GigaSpeech XL; only model weights/tokens, not the training corpus, are bundled.
- **ONNX Runtime:** https://github.com/microsoft/onnxruntime, MIT.
  Copyright (c) Microsoft Corporation. Complete notice:
  `licenses/onnxruntime-MIT.txt` (upstream LICENSE text, recorded SHA-256
  `2f07c72751aed99790b8a4869cf2311df85a860b22ded05fa22803587a48922c`).
- `manifest.json` records exact upstream release asset IDs, source revision,
  archive/runtime sizes and SHA-256, and each selected model file's SHA-256.
  Release URLs/tags are mutable; hashes, not URL identity, are authoritative.
- `keywords.txt` is application-authored and uses the exact frozen literal
  `▁HE Y ▁HER ME S @Hey_Hermes` plus a newline.

## Building, including a fresh checkout

Every Gradle native compile/package depends on `prepareVoiceInputs`. It executes
`python3 scripts/prepare_voice_inputs.py --output build/voice-inputs`, verifies
all inputs, extracts only the three int8 model files/tokens and exact model
README, and packages these notices. Python 3 (stdlib only) and network access on
first build are required. For offline builds, seed the cache with the two exact
archives, or set `HERMES_VOICE_INPUT_DIR` to a directory containing them. A wrong
hash/size fails closed. There are no runtime downloads. No large AAR is tracked.

Run the tooling regressions with:

```
python3 -m unittest scripts.test_prepare_voice_inputs
```

`HERMES_VOICE_CACHE` optionally changes the build-time cache location. The default
is `~/.cache/hermes-voice`; all cache hits are reverified. Generated assets and
the AAR live under ignored `build/voice-inputs`, not a local absolute dependency.

## Source-build route (not an F-Droid acceptance claim)

The packaged prebuilt AAR is pinned and verifiable but is not a claim of
source reproducibility or F-Droid approval. At the exact sherpa source revision,
upstream's `build-android-arm64-v8a.sh`, `build-android-armv7-eabi.sh`,
`build-android-x86-64.sh` and `build-android-x86.sh` build each ABI, followed by
`android/SherpaOnnxAar/gradlew :sherpa_onnx:assembleRelease`. Its reference
`.github/workflows/android-fdroid-reproducible-aar.yaml` pins NDK
`27.2.12479018` and sets `SHERPA_ONNX_ENABLE_C_API=OFF`. Upstream notes that other
runner inputs float; this is a source-build entry point, not a byte-reproduction
receipt. A newly source-built AAR is a different artifact: review its provenance,
update the pin intentionally and rerun JNI/ABI/alignment and device gates; never
bypass the current hash verifier with a local path override.

## Unmeasured release gates

Physical Android 14/15/16 microphone privacy/lifecycle/provider behavior,
Hey Hermes acoustic recall, false activations/noise/accents, latency,
battery/thermal/memory, Bluetooth/car routing and real 16 KB-page native launch
need device measurements. JVM worker/provider regressions and ZIP/ELF inspection
are not those measurements. No background/lock-screen microphone service is
registered; resuming the app never restarts capture.
