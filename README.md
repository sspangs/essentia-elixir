# essentia-elixir

Elixir wrapper around [Essentia](https://essentia.upf.edu), a C++ library for audio analysis and descriptor extraction. Exposes key detection, tempo/beat tracking, chord extraction, tuning estimation, and spectral feature analysis via Erlang NIFs.

## Requirements

- Elixir ~> 1.14
- Erlang/OTP 24+
- A C++14-capable compiler (`clang++` on macOS, `g++` on Linux)
- [Essentia](https://essentia.upf.edu/installing.html) built from source (no Homebrew formula exists)
- Essentia's runtime dependencies (installed separately):
  - `fftw3` + `fftw3f` (single-precision)
  - `libyaml`
  - `ffmpeg` (`avcodec`, `avformat`, `avutil`)
  - `libsamplerate`
  - `taglib`

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:essentia_elixir, github: "sspangs/essentia-elixir"}
  ]
end
```

Then:

```shell
mix deps.get
mix compile
```

`mix compile` invokes the `Makefile` which compiles `c_src/essentia_nif.cpp` into `priv/essentia_nif.so`. If Essentia headers are not found, compilation is skipped with a warning and all NIF functions will raise `:nif_not_loaded` at runtime.

### Installing Essentia from source

Essentia is not available via Homebrew and must be built from source:

```shell
git clone https://github.com/MTG/essentia.git
cd essentia
brew install pkg-config eigen fftw libyaml libsamplerate taglib ffmpeg
CXXFLAGS="-std=c++14" python3 waf configure --mode=release --build-static --prefix=/usr/local
python3 waf
sudo python3 waf install
```

### Custom Essentia install path

If Essentia is installed somewhere other than `/usr/local`, override before compiling:

```shell
ESSENTIA_INCLUDE=/path/to/include ESSENTIA_LIB=/path/to/lib mix compile
```

### Apple Silicon (M1/M2/M3)

Homebrew on Apple Silicon installs to `/opt/homebrew` instead of `/usr/local`. The Makefile detects this automatically via `brew --prefix`. If you need to override it:

```shell
HOMEBREW_PREFIX=/opt/homebrew mix compile
```

## Usage

### Full analysis with chord suggestions

`Essentia.AudioAnalysis.analyze/1` runs a single-pass audio analysis and automatically
appends suggested chord progressions:

```elixir
{:ok, result} = Essentia.AudioAnalysis.analyze("/path/to/song.mp3")

result.key
# => %{key: "A", scale: "minor", strength: 0.83}

result.tempo
# => %{bpm: 120.0, ticks: [0.5, 1.0, 1.5, ...]}  # beat timestamps in seconds

result.chords
# => [%{chord: "Am", strength: 0.91}, %{chord: "F", strength: 0.87}, ...]

result.tuning
# => %{frequency: 440.0, cents_off: 0.0}

result.duration
# => 214.3  # seconds

result.chord_timeline
# => [
#   %{chord: "Am", function: "vi", start: 0.0,  end: 4.6,  strength: 0.91},
#   %{chord: "F",  function: "IV", start: 4.6,  end: 9.2,  strength: 0.87},
#   %{chord: "C",  function: "I",  start: 9.2,  end: 13.8, strength: 0.93},
#   %{chord: "G",  function: "V",  start: 13.8, end: 18.4, strength: 0.89},
# ]

result.suggested_progressions
# => [["C", "G", "Am", "F"], ["Am", "Em", "Am", "F"], ...]
```

The `chord_timeline` collapses raw per-frame chord data into timestamped segments and
annotates each with its Roman numeral function in the detected key (e.g. `"vi"`, `"IV"`).

### Raw single-pass analysis

Use `Essentia.analyze_all/1` directly when you want the raw analysis without chord suggestions:

```elixir
{:ok, result} = Essentia.analyze_all("/path/to/song.mp3")
```

### Individual extractors

Use these when you only need one feature:

```elixir
# Key detection
{:ok, %{key: key, scale: scale, strength: s}} = Essentia.extract_key("song.mp3")
# key => "C#", scale => "major"

# Tempo and beat positions
{:ok, %{bpm: bpm, ticks: ticks}} = Essentia.extract_tempo("song.mp3")
# bpm => 128.0, ticks => [0.46, 0.93, 1.40, ...]

# Chords
{:ok, chords} = Essentia.extract_chords("song.mp3")
# [%{chord: "Dm", strength: 0.78}, ...]

# Tuning
{:ok, %{frequency: freq, cents_off: cents}} = Essentia.extract_tuning("song.mp3")
# freq => 441.3, cents => 5.1

# Duration
{:ok, duration} = Essentia.get_duration("song.mp3")
# => 214.3

# Spectral features (loudness, MFCC, spectral contrast)
{:ok, features} = Essentia.analyze_audio("song.mp3")
# %{loudness: -12.4, mfcc: [...], spectral_contrast: [...]}
```

### Chord suggestions

Generate related progressions from a chord list using substitution rules:

```elixir
Essentia.AudioAnalysis.suggest_chord_progressions(["C", "G", "Am", "F"])
# => [
#   ["Am", "G", "Am", "F"],
#   ["C", "Em", "Am", "F"],
#   ["C", "G", "C",  "F"],
#   ["C", "G", "Am", "Dm"]
# ]
```

### Music theory utilities

```elixir
# Label a chord by its role in a key
Essentia.Theory.chord_function("Am", "C", "major")   # => "vi"
Essentia.Theory.chord_function("G7", "C", "major")   # => "V"
Essentia.Theory.chord_function("E",  "A", "minor")   # => "V"

# Transpose a progression by semitones
Essentia.Theory.transpose(["C", "Am", "F", "G"], 2)  # => ["D", "Bm", "G", "A"]
Essentia.Theory.transpose(["C", "Am", "F", "G"], -5) # => ["G", "Em", "C", "D"]
```

## Return types

All functions return `{:ok, result}` or `{:error, reason}`.

Key and chord names are **binaries** (e.g. `"C#"`, `"Bbm"`), not atoms. Erlang atoms cannot contain `#` unquoted, so strings are used throughout.

## Running tests

```shell
# Unit tests only (no NIF or audio file required)
mix test

# Integration tests (requires compiled NIF + a fixture audio file)
cp /some/song.mp3 test/fixtures/test_audio.mp3
mix test --include integration
```

## Architecture

```
lib/
  essentia.ex                  # NIF stubs + @on_load
  essentia/
    audio_analysis.ex          # Higher-level API (analyze/1, suggest_chord_progressions/1)
    chord.ex                   # Pure Elixir chord substitution utilities
    application.ex             # OTP application entry point

c_src/
  essentia_nif.cpp             # All NIF implementations

priv/
  essentia_nif.so              # Compiled at mix compile time (gitignored)
```

All NIF functions are marked `ERL_NIF_DIRTY_JOB_CPU_BOUND` so they run on dirty scheduler threads and do not block the BEAM.

## Supported audio formats

Any format supported by your FFmpeg installation: mp3, wav, flac, aac, ogg, etc.
