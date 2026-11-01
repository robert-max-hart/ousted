#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_sounds.py
#     Synthesises the game's sound files (22.05 kHz, mono, 16-bit WAV):
#       assets/audio/sfx/       work sounds (chop, hammer, pick, dig, rustle, anvil;
#                               a few variants each: <name>_1.wav ...), interface
#                               sounds (click, place, error, demolish) and event
#                               chimes (done, birth, death, merchant, season)
#       assets/audio/ambient/   seamless loops: wind, rain, water, birds, crickets
#     They are placeholders made from noise, sine partials and envelopes (the
#     random generator is seeded, so a rerun writes the same files). Edit a
#     recipe below and run:
#         python3 tools/make_sounds.py
#     then `godot --headless --path . --import`. Any file can be replaced by a
#     recorded one of the same name. How the game uses them: scripts/audio/sfx.gd
#     (effects) and scripts/audio/ambient_audio.gd (loops).
# ----------------------------------------------------------------
import math, os, random, struct, wave

RATE = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = random.Random(1234)
trng = random.Random(9001)          # for the sounds at the end of the script (thunder, fire)


# --------------------------------
# Building blocks (a sound is a list of floats, roughly -1..1)

def n_samples(sec):
    return int(sec * RATE)

def silence(sec):
    return [0.0] * n_samples(sec)

def noise(sec):
    return [rng.uniform(-1.0, 1.0) for _ in range(n_samples(sec))]

def sine(freq, sec, phase=0.0):
    w = 2.0 * math.pi * freq / RATE
    return [math.sin(w * i + phase) for i in range(n_samples(sec))]

def env_exp(x, decay_sec, attack_sec=0.002):
    """Fast attack, exponential decay."""
    out = []
    a = max(1, n_samples(attack_sec))
    k = 1.0 / (decay_sec * RATE)
    for i, v in enumerate(x):
        e = min(1.0, i / a) * math.exp(-i * k * 4.6)
        out.append(v * e)
    return out

def lowpass(x, cutoff):
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / RATE)
    y, s = [], 0.0
    for v in x:
        s += a * (v - s)
        y.append(s)
    return y

def highpass(x, cutoff):
    lp = lowpass(x, cutoff)
    return [v - l for v, l in zip(x, lp)]

def bandpass(x, lo, hi):
    return lowpass(highpass(x, lo), hi)

def mix(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, v in enumerate(p):
            out[i] += v
    return out

def gain(x, g):
    return [v * g for v in x]

def delay(x, sec):
    return silence(sec) + x

def normalise(x, peak=0.8):
    m = max(abs(v) for v in x) or 1.0
    return [v * peak / m for v in x]

def fade_edges(x, sec=0.004):
    n = min(len(x) // 2, n_samples(sec))
    for i in range(n):
        x[i] *= i / n
        x[-1 - i] *= i / n
    return x

def bell(freq, sec, partials=((1.0, 1.0), (2.76, 0.5), (5.4, 0.25), (8.9, 0.12))):
    parts = []
    for ratio, amp in partials:
        parts.append(gain(env_exp(sine(freq * ratio, sec), sec / (1.0 + 0.6 * ratio)), amp))
    return mix(*parts)

def loop_seamless(x, fade_sec=1.0):
    """Cross-fade the tail into the head so the loop has no seam; returns a shorter, seamless array."""
    f = n_samples(fade_sec)
    body = x[: len(x) - f]
    for i in range(f):
        t = i / f
        body[i] = body[i] * t + x[len(x) - f + i] * (1.0 - t)
    return body

def write(path, x):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with wave.open(full, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in x))


# --------------------------------
# Work sounds: a few variants each, so repeated strikes do not sound identical

def chop(i):
    pitch = rng.uniform(0.85, 1.2)
    thud = env_exp(sine(150 * pitch, 0.22), 0.12)
    tok = env_exp(bandpass(noise(0.12), 500, 2500), 0.05)
    crack = env_exp(sine(620 * pitch, 0.1), 0.04)
    return normalise(mix(gain(thud, 1.0), gain(tok, 0.9), gain(crack, 0.35)), 0.75)

def hammer(i):
    pitch = rng.uniform(0.9, 1.15)
    tick = env_exp(highpass(noise(0.05), 1500), 0.012)
    ring = mix(env_exp(sine(980 * pitch, 0.25), 0.1), gain(env_exp(sine(1530 * pitch, 0.25), 0.07), 0.6))
    knock = env_exp(sine(210 * pitch, 0.12), 0.05)
    return normalise(mix(gain(tick, 0.8), gain(ring, 0.6), gain(knock, 0.6)), 0.7)

def pick(i):
    pitch = rng.uniform(0.9, 1.2)
    clack = env_exp(bandpass(noise(0.1), 1200, 4500), 0.035)
    tone = env_exp(sine(740 * pitch, 0.15), 0.05)
    low = env_exp(sine(260 * pitch, 0.15), 0.06)
    return normalise(mix(gain(clack, 1.0), gain(tone, 0.5), gain(low, 0.5)), 0.7)

def dig(i):
    scrape = env_exp(lowpass(noise(0.34), rng.uniform(1100, 1700)), 0.16, 0.03)
    thump = env_exp(sine(95, 0.2), 0.09, 0.01)
    return normalise(mix(scrape, gain(thump, 0.5)), 0.55)

def rustle(i):
    x = bandpass(noise(0.45), 1800, 6500)
    shaped = []
    n = len(x)
    for k, v in enumerate(x):
        t = k / n
        shaped.append(v * math.sin(math.pi * t) * (0.6 + 0.4 * math.sin(k * 0.02 + i)))
    return normalise(shaped, 0.4)

def anvil(i):
    pitch = rng.uniform(0.95, 1.05)
    ring = mix(gain(bell(1100 * pitch, 1.0, ((1.0, 1.0), (2.4, 0.5), (3.9, 0.35), (5.6, 0.2))), 1.0))
    click = env_exp(highpass(noise(0.03), 2500), 0.008)
    return normalise(mix(ring, gain(click, 0.7)), 0.7)

def treefall(i):
    """A tree going over: wood fibres creaking and splitting, then the thump of the crown and a rush of leaves. About 1.7 s,
    the thump lands as the tree in the game reaches the ground (FallingTree.FALL_SECONDS)."""
    n = n_samples(1.8)
    creak = bandpass(noise(1.8), 250, 900)
    shaped = []
    for k, x in enumerate(creak):
        t = k / RATE
        env = min(1.0, t / 0.15) * (1.0 if t < 1.0 else math.exp(-(t - 1.0) * 14.0))
        shaped.append(x * env * (0.5 + 0.5 * math.sin(t * 38.0 + math.sin(t * 7.0) * 3.0)) * 2.2)
    crack = delay(env_exp(highpass(noise(0.12), 1200), 0.05), 0.15)
    thump = delay(mix(env_exp(sine(55, 0.7), 0.4, 0.01), gain(env_exp(sine(110, 0.5), 0.25, 0.01), 0.7), gain(env_exp(lowpass(noise(0.5), 700), 0.3, 0.01), 0.9)), 1.2)
    leaves = delay(env_exp(bandpass(noise(0.6), 2500, 7000), 0.3, 0.05), 1.05)
    return normalise(mix(shaped, gain(crack, 0.8), thump, gain(leaves, 0.5)), 0.8)

for name, fn, count in (("chop", chop, 3), ("hammer", hammer, 3), ("pick", pick, 3), ("dig", dig, 2), ("rustle", rustle, 2), ("anvil", anvil, 2)):
    for i in range(1, count + 1):
        write("sfx/%s_%d.wav" % (name, i), fade_edges(fn(i)))


# --------------------------------
# Interface sounds and event chimes

write("sfx/click.wav", fade_edges(normalise(mix(env_exp(sine(1700, 0.05), 0.02), gain(env_exp(sine(950, 0.05), 0.02), 0.5)), 0.45)))
write("sfx/place.wav", fade_edges(normalise(mix(env_exp(sine(120, 0.25), 0.12), gain(env_exp(bandpass(noise(0.1), 400, 1800), 0.04), 0.8), gain(env_exp(sine(300, 0.12), 0.05), 0.4)), 0.7)))
write("sfx/error.wav", fade_edges(normalise(mix(env_exp(sine(220, 0.14), 0.07), delay(env_exp(sine(165, 0.18), 0.09), 0.11)), 0.5)))
write("sfx/demolish.wav", fade_edges(normalise(mix(env_exp(lowpass(noise(0.4), 1600), 0.22, 0.01), gain(env_exp(sine(80, 0.3), 0.15), 0.7)), 0.7)))

def notes(freqs, gap, ring):
    parts = []
    for k, f in enumerate(freqs):
        parts.append(delay(bell(f, ring, ((1.0, 1.0), (2.0, 0.3), (3.0, 0.1))), k * gap))
    return mix(*parts)

write("sfx/done.wav", fade_edges(normalise(notes([523.3, 659.3], 0.13, 0.7), 0.55)))                       # a building is finished
write("sfx/birth.wav", fade_edges(normalise(notes([523.3, 659.3, 784.0], 0.16, 0.9), 0.5)))
write("sfx/death.wav", fade_edges(normalise(bell(110, 2.2, ((1.0, 1.0), (2.0, 0.5), (2.7, 0.35), (4.2, 0.15))), 0.6)))
write("sfx/merchant.wav", fade_edges(normalise(mix(bell(880, 1.0, ((1.0, 1.0), (2.1, 0.4))), delay(bell(1175, 1.0, ((1.0, 1.0), (2.1, 0.4))), 0.22), delay(bell(880, 1.0, ((1.0, 1.0), (2.1, 0.4))), 0.5)), 0.5)))
write("sfx/season.wav", fade_edges(normalise(notes([392.0, 523.3, 659.3, 784.0], 0.2, 1.3), 0.45)))


# --------------------------------
# Ambient loops (12 to 20 s, seamless)

def lfo(n, rate, depth, base=1.0, phase=0.0):
    w = 2.0 * math.pi * rate / RATE
    return [base + depth * math.sin(w * i + phase) for i in range(n)]

def wind():
    sec = 14
    x = noise(sec + 1)
    low = lowpass(x, 420)
    mid = bandpass(x, 500, 1400)
    n = len(x)
    a = lfo(n, 0.11, 0.45, 0.6)
    b = lfo(n, 0.07, 0.4, 0.5, 1.7)
    y = [l * 3.0 * a[i] + m * 1.4 * b[i] * b[i] for i, (l, m) in enumerate(zip(low, mid))]
    return normalise(loop_seamless(y, 2.0), 0.5)

def rain():
    sec = 11
    x = noise(sec + 1)
    hiss = highpass(lowpass(x, 7000), 1200)
    n = len(x)
    drops = [0.0] * n
    for _ in range(int(sec * 70)):                       # the sparse, louder drops on top of the hiss
        p = rng.randrange(n - 400)
        a = rng.uniform(0.3, 1.0)
        f = rng.uniform(2500, 5500)
        for k in range(300):
            drops[p + k] += a * math.sin(2 * math.pi * f * k / RATE) * math.exp(-k / 35.0) * 0.5
    return normalise(loop_seamless([h * 1.2 + d for h, d in zip(hiss, drops)], 1.5), 0.5)

def water():
    sec = 13
    x = noise(sec + 1)
    n = len(x)
    base = lowpass(x, 900)
    bub = bandpass(x, 300, 1200)
    a = lfo(n, 0.23, 0.35, 0.65)
    b = lfo(n, 0.61, 0.5, 0.5, 0.9)
    c = lfo(n, 1.3, 0.5, 0.5, 2.2)
    y = [base[i] * 2.5 * a[i] + bub[i] * 1.5 * b[i] * c[i] for i in range(n)]
    return normalise(loop_seamless(y, 2.0), 0.45)

def chirp(f0, f1, sec, shape=1.0):
    n = n_samples(sec)
    out, ph = [], 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t ** shape
        ph += 2.0 * math.pi * f / RATE
        out.append(math.sin(ph) * math.sin(math.pi * t) ** 0.7)
    return out

def birds():
    sec = 20
    n = n_samples(sec)
    y = [0.0] * n
    species = [
        lambda: [chirp(3600, 4800, 0.09), delay(chirp(4800, 3900, 0.08), 0.1), delay(chirp(3700, 5000, 0.1), 0.2)],
        lambda: [chirp(2400, 3300, 0.18, 0.6), delay(chirp(3300, 2300, 0.16, 1.4), 0.2)],
        lambda: [chirp(5200, 4400, 0.06), delay(chirp(5200, 4400, 0.06), 0.09), delay(chirp(5200, 4400, 0.06), 0.18), delay(chirp(5400, 4300, 0.06), 0.27)],
    ]
    for _ in range(11):
        start = rng.randrange(n_samples(0.5), n - n_samples(1.5))
        call = mix(*rng.choice(species)())
        amp = rng.uniform(0.25, 0.7)
        for k, v in enumerate(call):
            y[start + k] += v * amp
    return normalise(y, 0.45)

def crickets():
    sec = 12
    n = n_samples(sec)
    y = [0.0] * n
    for voice, (f, period) in enumerate(((4300, 0.42), (4700, 0.51), (4050, 0.37))):
        t0 = rng.uniform(0, period)
        t = t0
        while t < sec - 0.6:
            for burst in range(3):                       # a chirp of three quick pulses
                start = n_samples(t + burst * 0.045)
                pulse = env_exp(sine(f, 0.04), 0.03, 0.004)
                for k, v in enumerate(pulse):
                    if start + k < n:
                        y[start + k] += v * 0.5
            t += period
    return normalise(y, 0.35)

write("ambient/wind.wav", wind())
write("ambient/rain.wav", rain())
write("ambient/water.wav", water())
write("ambient/birds.wav", birds())
write("ambient/crickets.wav", crickets())

write("sfx/treefall.wav", fade_edges(treefall(0)))        # (last, so adding or changing it never shifts the random numbers the others use)

# --------------------------------
# Added later (written after the sounds above, so a change here never shifts the random numbers they use):
# footsteps, animal calls, small event sounds. All quiet: the game plays most of them softly and only near the camera.

def step_grass(i):
    pitch = rng.uniform(0.85, 1.2)
    return normalise(mix(env_exp(bandpass(noise(0.1), 250, 1400), 0.05, 0.004), gain(env_exp(sine(95 * pitch, 0.08), 0.04), 0.5)), 0.35)

def step_road(i):
    pitch = rng.uniform(0.9, 1.2)
    return normalise(mix(env_exp(highpass(noise(0.07), 1800), 0.02, 0.001), gain(env_exp(sine(150 * pitch, 0.09), 0.04), 0.7)), 0.4)

def step_wade(i):
    splash = env_exp(bandpass(noise(0.28), 500, 3200), 0.13, 0.01)
    plop = delay(env_exp(sine(rng.uniform(260, 380), 0.1), 0.05), 0.04)
    return normalise(mix(splash, gain(plop, 0.5)), 0.4)

def step_deck(i):
    pitch = rng.uniform(0.9, 1.15)
    return normalise(mix(env_exp(sine(200 * pitch, 0.12), 0.06), gain(env_exp(sine(470 * pitch, 0.08), 0.04), 0.5), gain(env_exp(highpass(noise(0.04), 2000), 0.012), 0.4)), 0.4)

for name, fn, count in (("step_grass", step_grass, 3), ("step_road", step_road, 3), ("step_wade", step_wade, 3), ("step_deck", step_deck, 2)):
    for i in range(1, count + 1):
        write("sfx/%s_%d.wav" % (name, i), fade_edges(fn(i)))

def voice(f_of_t, sec, harmonics, vib_rate=0.0, vib_depth=0.0, attack=0.05):
    """A harmonic voice: a gliding pitch with a vibrato, partials by weight, a smooth envelope (an animal call)."""
    n = n_samples(sec)
    out, ph = [], 0.0
    for k in range(n):
        t = k / RATE
        f = f_of_t(t / sec) * (1.0 + vib_depth * math.sin(2 * math.pi * vib_rate * t))
        ph += 2.0 * math.pi * f / RATE
        v = sum(a * math.sin((h + 1) * ph) for h, a in enumerate(harmonics))
        e = min(1.0, t / attack) * math.sin(math.pi * (k / n)) ** 0.6
        out.append(v * e)
    return out

def cluck(i):
    parts = []
    for k in range(2 + i % 2):
        f0 = rng.uniform(620, 820)
        parts.append(delay(gain(voice(lambda u, f0=f0: f0 * (1.25 - 0.4 * u), 0.07, (1.0, 0.6, 0.3), 0.0, 0.0, 0.01), 1.0), k * 0.1))
    return normalise(mix(*parts), 0.5)

def baa(i):
    base = rng.uniform(330, 420)
    x = voice(lambda u: base * (1.0 + 0.12 * math.sin(math.pi * u)), 0.85, (1.0, 0.8, 0.9, 0.7, 0.4, 0.25), 26.0, 0.035, 0.08)
    return normalise(bandpass(x, 300, 3000), 0.5)

def moo(i):
    base = rng.uniform(105, 135)
    x = voice(lambda u: base * (1.25 - 0.35 * u), 1.5, (1.0, 0.9, 0.7, 0.5, 0.35, 0.2), 4.5, 0.02, 0.25)
    return normalise(lowpass(x, 1100), 0.55)

for name, fn, count in (("cluck", cluck, 3), ("baa", baa, 2), ("moo", moo, 2)):
    for i in range(1, count + 1):
        write("sfx/%s_%d.wav" % (name, i), fade_edges(fn(i), 0.01))

write("sfx/drink.wav", fade_edges(normalise(mix(env_exp(bandpass(noise(0.3), 400, 1800), 0.12, 0.02), delay(env_exp(bandpass(noise(0.25), 500, 2200), 0.1, 0.02), 0.22), gain(delay(env_exp(sine(420, 0.1), 0.05), 0.08), 0.4)), 0.4)))
write("sfx/eat.wav", fade_edges(normalise(mix(*[delay(env_exp(bandpass(noise(0.06), 800, 3200), 0.03, 0.002), k * 0.1) for k in range(3)]), 0.3)))
write("sfx/bell.wav", fade_edges(normalise(mix(*[delay(bell(1250, 1.4, ((1.0, 1.0), (2.0, 0.45), (2.8, 0.3), (4.1, 0.15))), k * 0.55) for k in range(4)]), 0.5)))
write("sfx/coins.wav", fade_edges(normalise(mix(*[delay(bell(rng.choice((2400, 3000, 3600)), 0.35, ((1.0, 1.0), (2.3, 0.4))), k * 0.07 + rng.uniform(0, 0.03)) for k in range(5)]), 0.45)))
write("sfx/splash.wav", fade_edges(normalise(mix(env_exp(bandpass(noise(0.4), 400, 3200), 0.2, 0.01), gain(delay(env_exp(sine(180, 0.25), 0.12), 0.05), 0.6)), 0.5)))
write("sfx/merchant_leave.wav", fade_edges(normalise(mix(bell(784, 1.0, ((1.0, 1.0), (2.1, 0.4))), delay(bell(659.3, 1.0, ((1.0, 1.0), (2.1, 0.4))), 0.24), delay(bell(523.3, 1.2, ((1.0, 1.0), (2.1, 0.4))), 0.5)), 0.45)))
write("sfx/drought.wav", fade_edges(normalise(mix([v * math.sin(math.pi * k / n_samples(2.8)) for k, v in enumerate(lowpass(noise(2.8), 320))], gain([math.sin(math.pi * k / n_samples(2.8)) * v for k, v in enumerate(sine(66, 2.8))], 0.5)), 0.5), 0.05))


# --------------------------------
# Fire sounds. These and the thunder use their own random generator and sit at the end of the script, so adding them never changes the
# older files (the main generator's numbers are used in order).

def fire_crackle():
    """A seamless loop of burning wood: a low roar with pops and snaps of different sizes, 6 seconds."""
    sec = 6.0
    n = n_samples(sec)
    roar = lowpass([trng.uniform(-1.0, 1.0) for _ in range(n)], 420)
    swell = [0.45 + 0.2 * math.sin(2 * math.pi * k / n * 3 + 1.0) + 0.1 * math.sin(2 * math.pi * k / n * 7) for k in range(n)]
    out = [r * w * 0.5 for r, w in zip(roar, swell)]
    for _ in range(70):
        at = trng.uniform(0, sec - 0.2)
        size = trng.uniform(0.2, 1.0)
        pop = env_exp(highpass([trng.uniform(-1.0, 1.0) for _ in range(n_samples(0.05))], 900 + 1500 * size), 0.012 + 0.02 * size, 0.0005)
        for i, v in enumerate(pop):
            k = n_samples(at) + i
            if k < n:
                out[k] += v * size * 0.8
    return loop_seamless(normalise(out, 0.6) + silence(1.0), 1.0)

def fire_alarm():
    """A hand bell struck fast: the call that a fire has broken out. About 2.4 s."""
    parts = []
    for k in range(9):
        parts.append(delay(bell(1560 if k % 2 == 0 else 1480, 0.7, ((1.0, 1.0), (2.0, 0.5), (2.9, 0.3), (4.2, 0.15))), k * 0.24))
    return normalise(mix(*parts), 0.6)

def thunder(i):
    """A crack, then a long rolling rumble that swells and dies away (about 4 s; two takes differ in length and rolls)."""
    sec = 3.6 + 0.8 * i
    n = n_samples(sec)
    rumble = lowpass([trng.uniform(-1.0, 1.0) for _ in range(n)], 220 + 40 * i)
    rolls = [trng.uniform(0.3, 1.8) for _ in range(3)]
    shaped = []
    for k, x in enumerate(rumble):
        t = k / RATE
        env = min(1.0, t / 0.25) * math.exp(-t * (0.7 + 0.1 * i))
        swell = 0.55 + 0.45 * math.sin(t * 5.0 + rolls[0]) * math.sin(t * 2.3 + rolls[1])
        shaped.append(x * env * swell * 3.0)
    crack = env_exp(highpass([trng.uniform(-1.0, 1.0) for _ in range(n_samples(0.3))], 700), 0.06, 0.001)
    boom = env_exp(lowpass([trng.uniform(-1.0, 1.0) for _ in range(n_samples(1.2))], 160), 0.5, 0.02)
    return normalise(mix(shaped, gain(crack, 0.5), gain(boom, 1.2)), 0.85)

for i in (1, 2):
    write("sfx/thunder_%d.wav" % i, fade_edges(thunder(i)))

write("ambient/fire.wav", fire_crackle())
write("sfx/fire_alarm.wav", fade_edges(fire_alarm()))

total = sum(1 for _, _, fs in os.walk(ROOT) for f in fs if f.endswith(".wav"))
print("wrote", total, "sound files to", os.path.normpath(ROOT))
