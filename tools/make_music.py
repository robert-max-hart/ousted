#!/usr/bin/env python3
# ----------------------------------------------------------------
# make_music.py
#     Synthesises the game's background music into assets/audio/music/ as
#     <season>_<n>.ogg (spring, summer, autumn, winter; five pieces each of about two minutes,
#     22.05 kHz mono Vorbis; WAV if ffmpeg is missing). Folk and medieval
#     in feel, but mellow: a soft piano tune in a church mode over a
#     piano arpeggio and a soft drone, no drum (the first version, with
#     flute and lute, is kept in archive/music_v1/ for comparison).
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

# season: target (a season piece runs about this many seconds: the A A B A form goes round with fresh phrases each round, ending on an A; the title has none and plays its tune `reps` times), reps (how many times the four phrases go round), tonic (MIDI note of the tune's lowest tonic), mode, tempo (beats a minute), steps in a bar (eighth notes), the lead voice,
# drum, how often the tune rests, and the four-bar chord loops for the A and B phrases (scale degrees, 0 is the tonic chord)
SEASONS = {
    "spring": {"tonic": 62, "mode": "mixolydian", "bpm": 104, "steps": 8, "reps": 1, "target": 117, "lead": "piano", "drum": False, "rest": 0.10, "A": [0, 3, 0, 4], "B": [3, 0, 4, 0]},
    "summer": {"tonic": 67, "mode": "ionian",     "bpm": 84, "steps": 6, "reps": 2, "target": 120, "lead": "piano", "drum": False, "rest": 0.06, "A": [0, 4, 0, 3], "B": [3, 4, 0, 4]},
    "autumn": {"tonic": 57, "mode": "dorian",     "bpm": 84,  "steps": 8, "reps": 1, "target": 114, "lead": "piano", "drum": False, "rest": 0.16, "A": [0, 6, 0, 4], "B": [3, 0, 6, 0]},
    # the title screen's piece: piano alone (no drone), slow and warm, twice round so it runs a little over a minute; written as title.ogg
    "title":  {"tonic": 60, "mode": "ionian",     "bpm": 72,  "steps": 8, "reps": 2, "lead": "piano", "drum": False, "rest": 0.12, "drone": False, "A": [0, 5, 3, 4], "B": [3, 4, 0, 4]},
    "winter": {"tonic": 64, "mode": "aeolian",    "bpm": 64,  "steps": 8, "reps": 1, "target": 120, "lead": "piano", "drum": False, "rest": 0.28, "A": [0, 5, 0, 4], "B": [5, 4, 0, 3]},
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

def piano_synth(freq, sec, rng, vel=0.7):
    """A piano: up to 14 stiff-string (slightly sharp) partials, each from two detuned strings that beat, with the hammer-strike spectrum
    (the partial a eighth of the way along the string is missing), a fast-then-slow decay, velocity-dependent brightness and a soft hammer thump."""
    total = n_samples(sec)
    out = [0.0] * total
    stiff = 0.0002 * (1.0 + (freq / 500.0) ** 2)             # inharmonicity: upper partials run sharp
    decay = 1.6 + 60.0 / max(freq, 60.0)                       # lower notes ring longer
    bright = 0.55 + 0.45 * vel
    for k in range(1, 15):
        fk = freq * k * math.sqrt(1.0 + stiff * k * k)
        if fk > RATE * 0.45:
            break
        amp = (abs(math.sin(math.pi * k / 8.0)) + 0.12) / (k ** 1.1) * (bright ** (k - 1))
        slow = (1.0 + 0.7 * k) / decay
        fast = 7.0 + 2.0 * k
        for detune, share in ((1.0 - rng.uniform(0.0001, 0.0005), 0.5), (1.0 + rng.uniform(0.0001, 0.0005), 0.5)):
            w = 2 * math.pi * fk * detune / RATE
            ph = rng.uniform(0.0, 0.5)
            g_fast = math.exp(-fast / RATE)
            g_slow = math.exp(-slow / RATE)
            e_fast = 0.55
            e_slow = 0.45
            a = amp * share
            for i in range(total):
                out[i] += a * (e_fast + e_slow) * math.sin(w * i + ph)
                e_fast *= g_fast
                e_slow *= g_slow
    thump = n_samples(0.018)                                    # the hammer: a soft low-passed knock
    lp = 0.0
    for i in range(min(thump, total)):
        lp += 0.15 * (rng.uniform(-1.0, 1.0) - lp)
        out[i] += lp * 0.25 * vel * (1.0 - i / thump) ** 2
    attack = n_samples(0.004)
    release = n_samples(min(0.25, sec * 0.4))
    for i in range(total):
        out[i] *= min(1.0, i / attack) * min(1.0, (total - i) / release)
    return out

# the sampled piano: an SFZ bank (Upright Piano KW from FreePats, CC0) unpacked into tools/upright_piano/ (or pass SFZ_DIR in the environment);
# without it, piano() falls back to the additive synth above
SFZ_DIR = os.environ.get("SFZ_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "upright_piano"))
_regions = None
_cache = {}
_tmp = None

def _load_regions():
    """Parse the .sfz: a list of (lokey, hikey, keycenter, lovel, hivel, wav path)."""
    global _regions
    _regions = []
    if not os.path.isdir(SFZ_DIR):
        return
    sfz = None
    for dirpath, _dirs, files in os.walk(SFZ_DIR):
        for fn in files:
            if fn.lower().endswith(".sfz"):
                sfz = os.path.join(dirpath, fn)
    if sfz is None:
        return
    group = {}
    region = None
    for line in open(sfz, encoding="utf-8", errors="replace"):
        line = line.split("//")[0].strip()
        if line.startswith("<group>"):
            group = {}
            region = None
            continue
        if line.startswith("<region>"):
            region = dict(group)
            _regions.append(region)
            line = line[len("<region>"):].strip()
        elif line.startswith("<"):
            region = None
            continue
        target = region if region is not None else group
        for part in line.split():
            if "=" in part:
                k, v = part.split("=", 1)
                target[k] = v
        if line.startswith("sample=") and region is not None:
            region["sample"] = line[len("sample="):].strip()
    out = []
    for r in _regions:
        if "sample" in r and "pitch_keycenter" in r:
            out.append((int(r["lokey"]), int(r["hikey"]), int(r["pitch_keycenter"]), int(r.get("lovel", 0)), int(r.get("hivel", 127)), os.path.join(os.path.dirname(sfz), r["sample"].replace("\\", "/"))))
    _regions = out

def _sample(path):
    """The sample as mono floats at RATE (converted once with ffmpeg)."""
    global _tmp
    if path in _cache:
        return _cache[path]
    if _tmp is None:
        _tmp = tempfile.TemporaryDirectory()
    wav = os.path.join(_tmp.name, str(len(_cache)) + ".wav")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", str(RATE), "-c:a", "pcm_s16le", wav], check=True)
    with wave.open(wav, "rb") as w:
        raw = w.readframes(w.getnframes())
    data = [v / 32768.0 for (v,) in struct.iter_unpack("<h", raw)]
    _cache[path] = data
    return data

def piano(freq, sec, rng, vel=0.7):
    """A sampled upright piano: the nearest sample (soft layer under vel 0.75, loud layer above), resampled to pitch, with a short release."""
    if _regions is None:
        _load_regions()
    if not _regions or not shutil.which("ffmpeg"):
        return piano_synth(freq, sec, rng, vel)
    midi = int(round(69 + 12 * math.log2(freq / 440.0)))
    v = int(vel * 127)
    best = None
    for r in _regions:
        if r[0] <= midi <= r[1] and r[3] <= v <= r[4]:
            best = r
            break
    if best is None:
        return piano_synth(freq, sec, rng, vel)
    data = _sample(best[5])
    ratio = freq / midi_hz(best[2])
    total = n_samples(sec)
    out = []
    n = len(data)
    for i in range(total):
        pos = i * ratio
        j = int(pos)
        if j + 1 >= n:
            break
        fr = pos - j
        out.append(data[j] * (1.0 - fr) + data[j + 1] * fr)
    release = min(len(out), n_samples(min(0.35, sec * 0.4)))
    for i in range(release):
        out[len(out) - 1 - i] *= i / release
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

def reverb(x, wet=0.09):
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


def soften(x, shelf_hz=2500.0, shelf_gain=0.45, cut_hz=7000.0):
    """The final EQ: a high shelf that takes about 7 dB off everything above shelf_hz, then a gentle low-pass at cut_hz to remove the air."""
    a = 1.0 - math.exp(-2 * math.pi * shelf_hz / RATE)
    c = 1.0 - math.exp(-2 * math.pi * cut_hz / RATE)
    lo = 0.0
    top = 0.0
    out = []
    for v in x:
        lo += a * (v - lo)
        y = lo + shelf_gain * (v - lo)
        top += c * (y - top)
        out.append(top)
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

def compose(season_name, seed, bass_shift=12):          # the arpeggio sits an octave above its first, lower setting
    season = SEASONS[season_name]
    rng = random.Random(seed)
    steps = season["steps"]
    step_sec = 60.0 / season["bpm"] / 2.0
    if steps == 6:
        step_sec = 60.0 / season["bpm"] / 3.0
    if "target" in season:
        # a long piece: as many phrases as fit the target, each round of A A B A with new tunes, stopping on an A (never after 3 of the 4)
        phrase_sec = 4 * steps * step_sec
        count = max(2, round((season["target"] - 3.0) / phrase_sec))
        if count % 4 == 3:
            count += 1
        form = []
        while len(form) < count:
            a = compose_phrase(season, season["A"], rng, rng.choice([2, 3, 4]), True)
            b = compose_phrase(season, season["B"], rng, rng.choice([5, 6]), False)
            b[-1] = (b[-1][0], b[-1][1], 4)
            form += [("A", a), ("A", a), ("B", b), ("A", a)]
        form = form[:count]
    else:
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
            f = midi_hz(scale_note(season, deg) + 12)                # the right hand sings an octave up
            add_at(buf, piano(f, min(3.0, dur + 1.4), rng), t0, 0.5)
    # the lute under it: an arpeggio of each bar's chord
    for p, (name, phrase) in enumerate(form):
        chords = season[name]
        for bar, root in enumerate(chords):
            base = (p * 4 + bar) * steps
            r = root - 7
            arp = [r, r + 4, r + 2, r + 4, r + 7, r + 4, r + 2, r + 4] if steps == 8 else [r, r + 4, r + 7, r + 4, r + 2, r + 4]
            for k, d in enumerate(arp):
                if season_name in ("autumn", "winter") and k % 2 == 1:
                    continue                                    # the lute leads: it plays half as much underneath
                add_at(buf, piano(midi_hz(scale_note(season, d) - 12 + bass_shift), 1.8, rng), (base + k) * step_sec, 0.2 if k else 0.26)
    # the drone and the drum
    drone_sec = bars * steps * step_sec + tail
    if season.get("drone", True):
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
        add_at(buf, piano(midi_hz(scale_note(season, d - 7)), 3.2, rng), bars * steps * step_sec, 0.3)
    lp = 0.0
    for i in range(len(buf)):                     # a gentle low-pass takes the edge off
        lp += 0.55 * (buf[i] - lp)
        buf[i] = lp
    buf = reverb(buf)
    buf = soften(buf)
    # piano is spiky (loud attacks, quiet tails), so level it by loudness (a target RMS), but never so high that the peaks clip:
    # the gain is capped so the 99.9th-percentile peak sits at 0.378, and the soft limiter below only has to catch stray spikes
    rms = math.sqrt(sum(v * v for v in buf) / len(buf)) or 1.0
    peaks = sorted(abs(v) for v in buf[::3])
    peak = peaks[int(len(peaks) * 0.999)] or 1.0
    gain = min(0.113 / rms, 0.378 / peak)
    fade = n_samples(0.4)
    out = [0.9 * math.tanh(v * gain / 0.9) for v in buf]
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
    import sys
    only = sys.argv[1:]            # e.g. `make_music.py title` writes just the title piece
    for season_name in SEASONS:
        if only and season_name not in only:
            continue
        for n in ((0,) if season_name == "title" else (1, 2, 3, 4, 5)):
            piece = compose(season_name, sum(map(ord, season_name)) * 100 + n)
            name = season_name if n == 0 else "%s_%d" % (season_name, n)
            write(name, piece)
            print("wrote %s (%.0f s)" % (name, len(piece) / RATE))
