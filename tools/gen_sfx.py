#!/usr/bin/env python3
"""Generate Zad X Play's original sound effects (the app has no music).

Everything here is synthesised from scratch (sine tones, soft envelopes and a
little filtered noise) using only the Python standard library, so the output
is 100% original and owned by Zad X. No samples are downloaded or copied.

Usage:
    python3 tools/gen_sfx.py            # writes assets/sfx/*.wav

Format: mono, 22050 Hz, 16-bit PCM WAV.
Design goals (children's app):
  * soft attacks, no harsh square/saw waves, nothing loud or scary;
  * short effects (< 60 KB each) so they load instantly.
"""

import math
import os
import struct
import wave

RATE = 22050
PEAK = 0.55  # effects never exceed ~-5 dBFS; the app lowers them further
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")

TAU = 2 * math.pi


def note(name):
    """Frequency of a note like 'C6', 'G5', 'A#4'."""
    names = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
    pitch, octave = name[:-1], int(name[-1])
    midi = 12 * (octave + 1) + names[pitch]
    return 440.0 * 2 ** ((midi - 69) / 12)


def silence(seconds):
    return [0.0] * int(seconds * RATE)


def mix_into(buf, samples, start_s, gain=1.0):
    start = int(start_s * RATE)
    need = start + len(samples)
    if need > len(buf):
        buf.extend([0.0] * (need - len(buf)))
    for i, v in enumerate(samples):
        buf[start + i] += v * gain


def bell(freq, dur, attack=0.006, decay=6.0, partials=((1, 1.0), (2.0, 0.35), (3.0, 0.12)), glide=0.0):
    """Soft bell/chime: a few sine partials, gentle attack, exponential decay.
    Higher partials decay faster, which keeps the sound round, not tinny."""
    n = int(dur * RATE)
    out = []
    phases = [0.0] * len(partials)
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-decay * t)
        f = freq * (1 + glide * t / dur)
        v = 0.0
        for k, (mult, amp) in enumerate(partials):
            phases[k] += TAU * f * mult / RATE
            v += amp * math.exp(-decay * (mult - 1) * 0.6 * t) * math.sin(phases[k])
        out.append(v * env)
    # short fade-out so the file never ends with a click
    fade = min(n, int(0.02 * RATE))
    for i in range(fade):
        out[n - 1 - i] *= i / fade
    return out


def soft_noise(dur, cutoff_start, cutoff_end, seed=1):
    """Low-passed noise with a sine-shaped envelope (a gentle 'whoosh')."""
    n = int(dur * RATE)
    state = seed
    y = 0.0
    y2 = 0.0
    out = []
    for i in range(n):
        state = (1103515245 * state + 12345) & 0x7FFFFFFF  # deterministic LCG
        x = state / 0x3FFFFFFF - 1.0
        cutoff = cutoff_start + (cutoff_end - cutoff_start) * i / n
        a = 1 - math.exp(-TAU * cutoff / RATE)
        y += a * (x - y)
        y2 += a * (y - y2)  # two poles: smoother, no hiss
        env = math.sin(math.pi * i / n) ** 2
        out.append(y2 * env)
    return out


def normalise(samples, peak=PEAK):
    m = max(abs(s) for s in samples) or 1.0
    return [s * peak / m for s in samples]


def write(name, samples, peak=PEAK):
    samples = normalise(samples, peak)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
        w.writeframes(frames)
    print(f"{name:20s} {len(samples) / RATE:5.2f} s  {os.path.getsize(path) / 1024:7.1f} KB")


# --------------------------------------------------------------------------- effects


def sfx_tap():
    # tiny rounded "pop": one soft partial gliding down
    return bell(note("A5"), 0.07, attack=0.002, decay=45, partials=((1, 1.0), (2.0, 0.08)), glide=-0.25)


def sfx_correct():
    # rising two-note chime: G5 -> C6
    buf = []
    mix_into(buf, bell(note("G5"), 0.35, decay=7), 0.0)
    mix_into(buf, bell(note("C6"), 0.55, decay=5), 0.13)
    return buf


def sfx_wrong():
    # soft low "boop" sliding gently down; pure sine, low volume, never harsh
    return bell(note("E4"), 0.32, attack=0.015, decay=9, partials=((1, 1.0), (2.0, 0.05)), glide=-0.12)


def sfx_star():
    # sparkly major arpeggio C6 E6 G6 C7 with a quiet high shimmer
    buf = []
    for i, n in enumerate(["C6", "E6", "G6", "C7"]):
        mix_into(buf, bell(note(n), 0.5, decay=7, partials=((1, 1.0), (2.0, 0.25), (4.0, 0.06))), i * 0.07)
    mix_into(buf, bell(note("E7"), 0.45, decay=9, partials=((1, 1.0),)), 0.3, gain=0.18)
    return buf


def sfx_level_up():
    # short 4-note fanfare G5 C6 E6 G6, last note held a little longer
    buf = []
    seq = [("G5", 0.0, 0.25), ("C6", 0.12, 0.25), ("E6", 0.24, 0.25), ("G6", 0.38, 0.75)]
    for n, start, dur in seq:
        mix_into(buf, bell(note(n), dur, attack=0.01, decay=4.5, partials=((1, 1.0), (2.0, 0.3), (3.0, 0.1))), start)
    mix_into(buf, bell(note("C6"), 0.75, attack=0.02, decay=4, partials=((1, 1.0),)), 0.38, gain=0.4)
    return buf


def sfx_task_complete():
    # warm rolled C-major chord (E5 G5 C6) - "well done!"
    buf = []
    for i, n in enumerate(["E5", "G5", "C6"]):
        mix_into(buf, bell(note(n), 0.8, attack=0.01, decay=4.0), i * 0.05)
    return buf


def sfx_unlock():
    # soft "click" then an opening chime D6 -> A6
    buf = []
    mix_into(buf, bell(note("A4"), 0.05, attack=0.001, decay=60, partials=((1, 1.0), (3.0, 0.2))), 0.0, gain=0.5)
    mix_into(buf, bell(note("D6"), 0.35, decay=7), 0.06)
    mix_into(buf, bell(note("A6"), 0.6, decay=5, partials=((1, 1.0), (2.0, 0.2))), 0.16)
    return buf


def sfx_transition():
    # very soft airy whoosh
    return soft_noise(0.22, 500, 1600, seed=7)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    write("tap.wav", sfx_tap(), peak=0.4)
    write("correct.wav", sfx_correct())
    write("wrong.wav", sfx_wrong(), peak=0.4)
    write("star.wav", sfx_star())
    write("level_up.wav", sfx_level_up())
    write("task_complete.wav", sfx_task_complete())
    write("unlock.wav", sfx_unlock())
    write("transition.wav", sfx_transition(), peak=0.22)


if __name__ == "__main__":
    main()
