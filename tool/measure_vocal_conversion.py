#!/usr/bin/env python3
"""How well did a voice conversion keep the song's key and melody?

    pip install librosa soundfile
    python3 tool/measure_vocal_conversion.py original_vocals.mp3 converted_vocals.wav [--seconds 39.8] [--ref reference.mp3]

Both files are the SAME sung line, before and after conversion. The report gives, from a pitch tracker (librosa pyin):
  * the key offset: how far the converted vocal sits from the original, ignoring whole octaves (0 = in key with the backing
    track; several semitones = sounds wrong against it);
  * the melody error left after the best possible whole-song key correction (the offset you could undo with a pitch shift).
It measures pitch only. It cannot say whether the result sounds good or whether the voice resembles anyone: that needs a listener.
Used for the numbers in docs/PROVIDER_EVALUATION.md (2026-11-01).
"""
import argparse
import warnings

import librosa
import numpy as np

warnings.filterwarnings("ignore")
SR, HOP = 16000, 320  # 20 ms frames


def load(path, seconds=None):
    y, _ = librosa.load(path, sr=SR, mono=True, duration=seconds)
    return y


def f0(y):
    f, voiced, _ = librosa.pyin(y, fmin=65, fmax=900, sr=SR, frame_length=1024, hop_length=HOP)
    return f, voiced


def compare(original, converted):
    fo, vo = f0(original)
    fc, vc = f0(converted)
    n = min(len(fo), len(fc))
    both = vo[:n] & vc[:n]
    if both.sum() < 50:
        raise SystemExit("too few frames are voiced in both files to compare")
    d = 12 * np.log2(fc[:n][both] / fo[:n][both])
    folded = ((d + 6) % 12) - 6  # whole-octave differences do not matter to the key
    grid = np.arange(-6, 6, 0.1)
    best = grid[int(np.argmax([np.mean(np.abs(((folded - g + 6) % 12) - 6) <= 0.5) for g in grid]))]
    resid = ((folded - best + 6) % 12) - 6
    return {
        "median_f0_original_hz": float(np.nanmedian(fo[vo])),
        "median_f0_converted_hz": float(np.nanmedian(fc[vc])),
        "key_offset_semitones": float(best),
        "shift_to_fix_key_semitones": float(-best),
        "within_0.5_st": float(np.mean(np.abs(resid) <= 0.5)),
        "within_1_st": float(np.mean(np.abs(resid) <= 1)),
        "within_2_st": float(np.mean(np.abs(resid) <= 2)),
        "median_abs_error_st": float(np.median(np.abs(resid))),
        "frames_compared": int(both.sum()),
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("original")
    ap.add_argument("converted")
    ap.add_argument("--seconds", type=float, help="compare only the first N seconds (a converter may cut the vocal short)")
    ap.add_argument("--ref", help="the reference voice sample, only to print its median pitch")
    a = ap.parse_args()
    r = compare(load(a.original, a.seconds), load(a.converted, a.seconds))
    if a.ref:
        fr, vr = f0(load(a.ref))
        print(f"reference voice median F0: {np.nanmedian(fr[vr]):.0f} Hz")
    print(f"median F0: original {r['median_f0_original_hz']:.0f} Hz, converted {r['median_f0_converted_hz']:.0f} Hz")
    print(f"key offset (octaves ignored): {r['key_offset_semitones']:+.1f} semitones; "
          f"pitch-shift the converted vocal by {r['shift_to_fix_key_semitones']:+.1f} to put it in key")
    print("after that correction: "
          f"{r['within_0.5_st']:.0%} of frames within 0.5 st, {r['within_1_st']:.0%} within 1 st, {r['within_2_st']:.0%} within 2 st; "
          f"median error {r['median_abs_error_st']:.2f} st  ({r['frames_compared']} frames)")
