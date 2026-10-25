"""Generates every sound of the game by synthesis (no recordings, no downloads): footsteps, sword, hit,
bow, axe on wood, pick on stone, shovel, campfire, rain, wind, crickets, birds, menu clicks and two
lute tunes (day and night). Writes 16-bit mono WAV files to assets/sounds/.

    python tools/sounds/make_sounds.py

Deterministic (fixed seeds). Never edit a .wav by hand: change this script and run it again.
"""
import os
import wave

import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "sounds")
rng = np.random.default_rng(1234)


def t(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def env(n, attack=0.005, decay=0.2):
    """Fast attack, exponential decay over n samples."""
    x = np.arange(n) / RATE
    a = np.clip(x / max(attack, 1e-4), 0.0, 1.0)
    return a * np.exp(-x / max(decay, 1e-4))


def lowpass(x, cutoff):
    """One-pole low-pass."""
    k = np.exp(-2.0 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1.0 - k) * v + k * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def band(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def noise(seconds):
    return rng.uniform(-1.0, 1.0, int(seconds * RATE))


def loopable(x, fade=0.25):
    """Crossfades the tail into the head so the clip loops without a click."""
    n = int(fade * RATE)
    head, tail = x[:n].copy(), x[-n:].copy()
    ramp = np.linspace(0.0, 1.0, n)
    out = x[:-n].copy()
    out[:n] = head * ramp + tail * (1.0 - ramp)
    return out


def pluck(freq, seconds, damp=0.996, bright=0.5):
    """Karplus-Strong plucked string (the lute)."""
    n = int(seconds * RATE)
    period = max(2, int(RATE / freq))
    buf = rng.uniform(-1.0, 1.0, period)
    buf = lowpass(buf, 2000 + 6000 * bright)
    out = np.empty(n)
    for i in range(n):
        j = i % period
        out[i] = buf[j]
        buf[j] = damp * 0.5 * (buf[j] + buf[(j + 1) % period])
    return out


def norm(x, peak=0.8):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def write(name, x, peak=0.8):
    os.makedirs(OUT, exist_ok=True)
    data = (norm(x, peak) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print("WROTE", name, "%.2fs" % (len(data) / RATE))


# --- One-shots ------------------------------------------------------------------------------

def step(seed):
    r = np.random.default_rng(seed)
    x = r.uniform(-1, 1, int(0.14 * RATE))
    x = lowpass(x, 900) * env(len(x), 0.004, 0.035)
    thud = np.sin(2 * np.pi * 70 * t(0.14)) * env(int(0.14 * RATE), 0.002, 0.03)
    return x + 0.6 * thud


def swing():
    n = int(0.28 * RATE)
    x = noise(0.28)
    sweep = np.linspace(400, 2600, n)
    out = np.zeros(n)
    for i in range(0, n, 256):  # a band that slides up: the whoosh
        seg = x[i:i + 256]
        out[i:i + 256] = band(seg, sweep[i] * 0.7, sweep[i] * 1.3)
    shape = np.sin(np.linspace(0, np.pi, n)) ** 2
    return out * shape


def hit():
    n = int(0.22 * RATE)
    thump = np.sin(2 * np.pi * 110 * t(0.22) * np.exp(-t(0.22) * 6)) * env(n, 0.001, 0.06)
    click = band(noise(0.22), 1500, 5000) * env(n, 0.0005, 0.012)
    return thump + 0.5 * click


def bow():
    twang = pluck(196, 0.45, damp=0.993, bright=0.9)
    whoosh = band(noise(0.45), 800, 3000) * np.linspace(1, 0, int(0.45 * RATE)) ** 3 * 0.3
    return twang + whoosh


def chop():
    n = int(0.3 * RATE)
    knock = np.sin(2 * np.pi * 320 * t(0.3)) * env(n, 0.001, 0.05)
    crack = band(noise(0.3), 600, 3500) * env(n, 0.0008, 0.03)
    return knock + 0.8 * crack


def pick():
    n = int(0.35 * RATE)
    ring = (np.sin(2 * np.pi * 1850 * t(0.35)) + 0.5 * np.sin(2 * np.pi * 2730 * t(0.35))) * env(n, 0.0005, 0.07)
    grit = band(noise(0.35), 2000, 7000) * env(n, 0.0005, 0.02)
    return ring * 0.6 + grit


def dig():
    n = int(0.4 * RATE)
    scrape = band(noise(0.4), 300, 1800) * np.sin(np.linspace(0, np.pi, n)) ** 1.5
    thud = np.sin(2 * np.pi * 90 * t(0.4)) * env(n, 0.002, 0.05)
    return scrape + 0.5 * thud


def birds():
    out = np.zeros(int(1.6 * RATE))
    for start, f0, f1 in [(0.05, 3200, 4200), (0.3, 3600, 2900), (0.42, 3600, 2900), (0.9, 2800, 4400)]:
        d = 0.09
        k = t(d)
        f = np.linspace(f0, f1, len(k))
        chirp = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.sin(np.linspace(0, np.pi, len(k)))
        i = int(start * RATE)
        out[i:i + len(k)] += chirp
    return out


def blip(freqs, each=0.05):
    parts = [np.sin(2 * np.pi * f * t(each)) * env(int(each * RATE), 0.002, each * 0.5) for f in freqs]
    return np.concatenate(parts)


# --- Loops ----------------------------------------------------------------------------------

def campfire():
    s = 4.3
    rumble = lowpass(noise(s), 180) * 0.6
    crackle = np.zeros(int(s * RATE))
    for _ in range(70):
        i = rng.integers(0, len(crackle) - 400)
        w = rng.integers(40, 300)
        crackle[i:i + w] += band(rng.uniform(-1, 1, w), 1500, 6000) * env(w, 0.0003, 0.004) * rng.uniform(0.3, 1.0)
    return loopable(rumble + crackle)


def rain():
    s = 4.3
    hiss = band(noise(s), 900, 7000)
    drops = np.zeros(int(s * RATE))
    for _ in range(400):
        i = rng.integers(0, len(drops) - 200)
        drops[i:i + 120] += band(rng.uniform(-1, 1, 120), 2000, 8000) * env(120, 0.0002, 0.002)
    return loopable(hiss * 0.5 + drops * 0.5)


def wind():
    s = 6.3
    x = lowpass(noise(s), 420)
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * t(s) / 6.0)
    return loopable(x * swell)


def crickets():
    s = 4.3
    out = np.zeros(int(s * RATE))
    for start in np.arange(0.0, s - 0.3, 0.55):
        for k in range(3):
            i = int((start + k * 0.045) * RATE)
            d = int(0.03 * RATE)
            out[i:i + d] += np.sin(2 * np.pi * 4300 * t(0.03)) * np.sin(np.linspace(0, np.pi, d))
    return loopable(out, fade=0.1)


# --- Music: a lute and a drone ---------------------------------------------------------------

def tune(notes, beat, root, drone_gain, damp, bright):
    """notes: list of (semitones from root or None, beats)."""
    total = sum(b for _, b in notes) * beat
    out = np.zeros(int(total * RATE) + RATE)
    pos = 0.0
    for semi, beats in notes:
        if semi is not None:
            f = root * 2 ** (semi / 12)
            p = pluck(f, beats * beat + 0.8, damp=damp, bright=bright)
            i = int(pos * RATE)
            out[i:i + len(p)] += p
        pos += beats * beat
    out = out[:int(total * RATE)]
    drone = (np.sin(2 * np.pi * root / 2 * t(total)) + 0.5 * np.sin(2 * np.pi * root * 3 / 4 * t(total)))
    return loopable(out + drone_gain * drone * 0.25, fade=0.6)


DAY = [(0, 1), (3, 1), (5, 1), (7, 2), (5, 1), (3, 1), (2, 2), (0, 1), (2, 1), (3, 1), (5, 1), (7, 1), (10, 1),
       (7, 2), (5, 1), (7, 1), (8, 1), (7, 1), (5, 1), (3, 1), (2, 2), (0, 2), (None, 1),
       (7, 1), (10, 1), (12, 2), (10, 1), (7, 1), (5, 2), (3, 1), (5, 1), (7, 1), (5, 1), (3, 1), (2, 1), (0, 3), (None, 1)]
NIGHT = [(0, 2), (3, 2), (7, 3), (5, 1), (3, 2), (2, 2), (0, 4), (None, 2),
         (7, 2), (8, 2), (7, 2), (5, 2), (3, 3), (2, 1), (0, 4), (None, 2)]

if __name__ == "__main__":
    write("step_1", step(1), 0.5)
    write("step_2", step(2), 0.5)
    write("swing", swing(), 0.6)
    write("hit", hit(), 0.8)
    write("bow", bow(), 0.7)
    write("chop", chop(), 0.7)
    write("pick", pick(), 0.6)
    write("dig", dig(), 0.6)
    write("birds", birds(), 0.4)
    write("ui_move", blip([880]), 0.35)
    write("ui_ok", blip([660, 990], 0.06), 0.4)
    write("campfire", campfire(), 0.6)
    write("rain", rain(), 0.6)
    write("wind", wind(), 0.5)
    write("crickets", crickets(), 0.35)
    write("music_day", tune(DAY, 0.42, 293.66, 0.5, 0.996, 0.55), 0.5)  # D dorian, a walking pace
    write("music_night", tune(NIGHT, 0.6, 220.0, 0.35, 0.997, 0.35), 0.4)  # A minor, slow and soft
