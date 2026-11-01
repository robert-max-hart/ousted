#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_music.py
#     Synthesises the game's background music into assets/audio/music/ as
#     <season>_<n>.ogg (spring, summer, autumn, winter; two pieces each,
#     22.05 kHz mono Vorbis; WAV if ffmpeg is missing). Folk and medieval
#     in feel: a flute (or lute) tune in a church mode over a lute
#     arpeggio, a soft drone and, in the livelier seasons, a frame drum.
#     Each piece is four phrases (A A B A) in the season's own key,
#     mode and tempo; the notes are composed by a seeded random walk
#     over the scale (steps mostly, chord tones on the strong beats,
#     the tune coming home to the tonic), so a rerun writes the same
#     files. Placeholders in the same spirit as make_sounds.py: any file
#     can be replaced by a recorded one of the same name.
#         python3 tools/make_music.py
#     then `godot --headless --path . --import`. How the game plays them:
#     scripts/audio/music_player.gd (a piece for the season, then a quiet gap).
# ----------------------------------------------------------------
import math, os, random, shutil, struct, subprocess, tempfile, wave

RATE = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "music")

MODES = {
    "ionian":     [0, 2, 4, 5, 7, 9, 11],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "dorian":     [0, 2, 3, 5, 7, 9, 10],
    "aeolian":    [0, 2, 3, 5, 7, 8, 10],
}

# season: reps (how many times the four phrases go round), tonic (MIDI note of the tune's lowest tonic), mode, tempo (beats a minute), steps in a bar (eighth notes), the lead voice,
# drum, how often the tune rests, and the four-bar chord loops for the A and B phrases (scale degrees, 0 is the tonic chord)
SEASONS = {
    "spring": {"tonic": 62, "mode": "mixolydian", "bpm": 104, "steps": 8, "reps": 1, "lead": "flute", "drum": True,  "rest": 0.10, "A": [0, 3, 0, 4], "B": [3, 0, 4, 0]},
    "summer": {"tonic": 67, "mode": "ionian",     "bpm": 84, "steps": 6, "reps": 2, "lead": "flute", "drum": True,  "rest": 0.06, "A": [0, 4, 0, 3], "B": [3, 4, 0, 4]},
    "autumn": {"tonic": 57, "mode": "dorian",     "bpm": 84,  "steps": 8, "reps": 1, "lead": "lute",  "drum": True,  "rest": 0.16, "A": [0, 6, 0, 4], "B": [3, 0, 6, 0]},
    "winter": {"tonic": 64, "mode": "aeolian",    "bpm": 64,  "steps": 8, "reps": 1, "lead": "lute",  "drum": False, "rest": 0.28, "A": [0, 5, 0, 4], "B": [5, 4, 0, 3]},
}
# rhythm cells (in eighth notes) that add up to a bar
CELLS = {
    8: [[4, 4], [2, 2, 4], [4, 2, 2], [2, 2, 2, 2], [3, 1, 2, 2], [2, 1, 1, 4], [1, 1, 2, 4], [6, 2], [3, 1, 4], [2, 2, 3, 1]],
    6: [[3, 3], [2, 2, 2], [3, 1, 2], [2, 1, 3], [6], [1, 2, 3]],
}


# --------------------------------
# Building blocks (a sound is a list of floats)

def n_samples(sec):
    return int(sec * RATE)

def midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)

def scale_note(season, idx):
    """MIDI note of scale degree idx (0 is the tonic, 7 the octave above, negative below)."""
    mode = MODES[season["mode"]]
    return season["tonic"] + 12 * (idx // 7) + mode[idx % 7]

def add_at(buf, x, start_sec, g=1.0):
    s = n_samples(start_sec)
    if s >= len(buf):
        return
    end = min(len(buf), s + len(x))
    for i in range(end - s):
        buf[s + i] += x[i] * g


# --------------------------------
# Voices

def pluck(freq, sec, rng, bright=0.5, decay=0.996):
    """A plucked string (Karplus-Strong): a burst of noise circulating through a damped delay line."""
    n = max(2, int(RATE / freq))
    line = [rng.uniform(-1.0, 1.0) * bright + rng.uniform(-1.0, 1.0) * (1.0 - bright) * 0.4 for _ in range(n)]
    out = []
    prev = 0.0
    total = n_samples(sec)
    pos = 0
    for i in range(total):
        cur = line[pos]
        nxt = line[(pos + 1) % n]
        v = (cur + nxt) * 0.5 * decay
        line[pos] = v
        pos = (pos + 1) % n
        out.append(cur)
    fade = n_samples(0.05)
    for i in range(min(fade, total)):
        out[total - 1 - i] *= i / fade
    return out

def flute(freq, sec, rng):
    """A breathy flute: a sine with a touch of its octave, a slow attack, a late vibrato and a little air."""
    total = n_samples(sec)
    out = []
    phase = 0.0
    air = 0.0
    attack = n_samples(0.07)
    release = n_samples(min(0.18, sec * 0.5))
    for i in range(total):
        t = i / RATE
        vib = 1.0 + 0.004 * math.sin(2 * math.pi * 5.0 * t) * min(1.0, max(0.0, (t - 0.25) / 0.3))
        phase += 2 * math.pi * freq * vib / RATE
        air += 0.2 * (rng.uniform(-1.0, 1.0) - air)
        v = math.sin(phase) + 0.22 * math.sin(2 * phase) + 0.05 * math.sin(3 * phase) + 0.12 * air
        e = min(1.0, i / attack) * min(1.0, (total - i) / release)
        out.append(v * e)
    return out

def drone(freq, sec, g):
    """A soft held tone with a slow swell."""
    total = n_samples(sec)
    w = 2 * math.pi * freq / RATE
    out = []
    for i in range(total):
        t = i / RATE
        swell = 0.75 + 0.25 * math.sin(2 * math.pi * t / 9.0)
        e = min(1.0, t / 2.0) * min(1.0, (sec - t) / 2.5)
        out.append((math.sin(w * i) + 0.3 * math.sin(2 * w * i + 0.5) + 0.12 * math.sin(3 * w * i)) * swell * e * g)
    return out

def thump(rng, soft=1.0):
    """A frame drum: a quick drop in pitch with a little skin noise."""
    total = n_samples(0.35)
    out = []
    phase = 0.0
    for i in range(total):
        t = i / RATE
        f = 55.0 + 85.0 * math.exp(-t * 30.0)
        phase += 2 * math.pi * f / RATE
        e = math.exp(-t * 11.0)
        out.append((math.sin(phase) + 0.2 * rng.uniform(-1.0, 1.0) * math.exp(-t * 60.0)) * e * soft)
    return out

def shaker(rng, soft=1.0):
    total = n_samples(0.12)
    prev = 0.0
    out = []
    for i in range(total):
        n = rng.uniform(-1.0, 1.0)
        hp = n - prev * 0.6
        prev = n
        out.append(hp * math.exp(-i / RATE * 40.0) * 0.25 * soft)
    return out

def reverb(x, wet=0.26):
    """A few feedback combs: enough room to take the dryness off."""
    out = list(x)
    for delay_sec, fb in ((0.0297, 0.42), (0.0371, 0.38), (0.0411, 0.36), (0.0533, 0.32)):
        d = n_samples(delay_sec)
        buf = [0.0] * len(x)
        for i in range(len(x)):
            back = buf[i - d] if i >= d else 0.0
            buf[i] = x[i] + back * fb
        for i in range(len(x)):
            out[i] += buf[i] * wet * 0.5
    return out


# --------------------------------
# Composing

def chord_tones(root):
    return {root % 7, (root + 2) % 7, (root + 4) % 7}

def compose_phrase(season, chords, rng, centre, ends_home):
    """Four bars of tune: a list of (start step, length in steps, scale degree or None for a rest)."""
    steps = season["steps"]
    notes = []
    idx = centre
    for bar, root in enumerate(chords):
        cell = rng.choice(CELLS[steps])
        pos = bar * steps
        for k, length in enumerate(cell):
            last = bar == len(chords) - 1 and k == len(cell) - 1
            if last and ends_home:
                target = 0 if idx < 4 else 7
                notes.append((pos, length + 1, target))
                idx = target
                pos += length
                continue
            move = rng.choice([-2, -1, -1, 0, 1, 1, 2, 3, -3])
            idx = max(-2, min(10, idx + move))
            if k == 0 or length >= 3:                      # the strong notes sit on a chord tone
                for off in (0, 1, -1, 2, -2):
                    if (idx + off) % 7 in chord_tones(root) and -2 <= idx + off <= 10:
                        idx += off
                        break
            if rng.random() < season["rest"] and k > 0 and not last:
                notes.append((pos, length, None))
            else:
                notes.append((pos, length, idx))
            pos += length
    return notes

def compose(season_name, seed):
    season = SEASONS[season_name]
    rng = random.Random(seed)
    steps = season["steps"]
    step_sec = 60.0 / season["bpm"] / 2.0
    if steps == 6:
        step_sec = 60.0 / season["bpm"] / 3.0
    a = compose_phrase(season, season["A"], rng, rng.choice([2, 3, 4]), True)
    b = compose_phrase(season, season["B"], rng, rng.choice([5, 6]), False)
    b[-1] = (b[-1][0], b[-1][1], 4)
    form = [("A", a), ("A", a), ("B", b), ("A", a)] * season["reps"]
    bars = 4 * len(form)
    tail = 3.0
    total_sec = bars * steps * step_sec + tail
    buf = [0.0] * n_samples(total_sec)
    # the tune
    for p, (name, phrase) in enumerate(form):
        base = p * 4 * steps
        for (start, length, deg) in phrase:
            if deg is None:
                continue
            t0 = (base + start) * step_sec
            dur = length * step_sec * 0.96
            f = midi_hz(scale_note(season, deg))
            if season["lead"] == "flute":
                add_at(buf, flute(f, dur + 0.1, rng), t0, 0.5)
            else:
                add_at(buf, pluck(f, min(2.2, dur + 1.2), rng, 0.6, 0.9965), t0, 0.6)
    # the lute under it: an arpeggio of each bar's chord
    for p, (name, phrase) in enumerate(form):
        chords = season[name]
        for bar, root in enumerate(chords):
            base = (p * 4 + bar) * steps
            r = root - 7
            arp = [r, r + 4, r + 2, r + 4, r + 7, r + 4, r + 2, r + 4] if steps == 8 else [r, r + 4, r + 7, r + 4, r + 2, r + 4]
            for k, d in enumerate(arp):
                if season["lead"] == "lute" and k % 2 == 1:
                    continue                                    # the lute leads: it plays half as much underneath
                add_at(buf, pluck(midi_hz(scale_note(season, d)), 1.6, rng, 0.45, 0.9955), (base + k) * step_sec, 0.3 if k else 0.4)
    # the drone and the drum
    drone_sec = bars * steps * step_sec + tail
    add_at(buf, drone(midi_hz(scale_note(season, -14)), drone_sec, 0.11), 0.0)
    add_at(buf, drone(midi_hz(scale_note(season, -10)), drone_sec, 0.06), 0.0)
    if season["drum"]:
        for bar in range(bars):
            base = bar * steps
            hits = [0, 4] if steps == 8 else [0, 3]
            for h in hits:
                add_at(buf, thump(rng, 1.0 if h == 0 else 0.7), (base + h) * step_sec, 0.28)
            if season_name == "summer":
                for h in (1, 2, 4, 5):
                    add_at(buf, shaker(rng, 0.8), (base + h) * step_sec, 0.5)
    # the last chord rings
    for d in (0, 4, 7):
        add_at(buf, pluck(midi_hz(scale_note(season, d - 7)), 3.2, rng, 0.4, 0.998), bars * steps * step_sec, 0.3)
    buf = reverb(buf)
    peak = max(abs(v) for v in buf) or 1.0
    fade = n_samples(0.4)
    out = [v * 0.7 / peak for v in buf]
    for i in range(fade):
        out[i] *= i / fade
        out[-1 - i] *= i / fade
    return out


# --------------------------------
# Writing

def write(name, x):
    os.makedirs(ROOT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, name + ".wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in x))
        if shutil.which("ffmpeg"):
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", os.path.join(ROOT, name + ".ogg")], check=True)
        else:
            shutil.copy(wav, os.path.join(ROOT, name + ".wav"))

if __name__ == "__main__":
    for season_name in SEASONS:
        for n in (1, 2):
            piece = compose(season_name, sum(map(ord, season_name)) * 100 + n)
            write("%s_%d" % (season_name, n), piece)
            print("wrote %s_%d (%.0f s)" % (season_name, n, len(piece) / RATE))
