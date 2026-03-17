defmodule Essentia do
  @moduledoc """
  Elixir wrapper for the [Essentia](https://essentia.upf.edu) C++ audio analysis library.

  ## Architecture

  All analysis functions are implemented as Erlang NIFs backed by
  `c_src/essentia_nif.cpp`. The `.so` is compiled via `elixir_make` at
  `mix compile` time and loaded on application start.

  Every NIF is marked `ERL_NIF_DIRTY_JOB_CPU_BOUND` so long-running audio
  processing does not block BEAM schedulers.

  ## Functions at a glance

  | Function | What it returns |
  |---|---|
  | `analyze_all/1` | Key + tempo + chords in one pass — **prefer this for combined analysis** |
  | `extract_key/1` | Musical key and scale |
  | `extract_tempo/1` | BPM |
  | `extract_chords/1` | Per-frame chord list |
  | `analyze_audio/1` | Loudness, MFCC coefficients, spectral contrast |

  ## Return values

  All functions return `{:ok, result}` on success or `{:error, reason}` on
  failure. String values (key names, chord names, scale names) are returned as
  **binaries**, not atoms, because names like `"C#"` are not valid unquoted
  atoms.

  ## Error handling

  Errors from Essentia (e.g. unsupported codec, file not found) are caught in
  C++ and returned as `{:error, charlist_message}`.
  """

  @on_load :load_nifs

  def load_nifs do
    # :code.priv_dir/1 can return {:error, :bad_name} if the app isn't registered,
    # and :filename.join/2 will throw on that tuple. Wrap defensively so a missing
    # or uncompiled NIF never prevents the module from loading.
    case :code.priv_dir(:essentia_elixir) do
      {:error, _} ->
        :ok

      priv_dir ->
        path = :filename.join(priv_dir, ~c"essentia_nif") |> to_string()

        case :erlang.load_nif(path, 0) do
          :ok -> :ok
          {:error, {:reload, _}} -> :ok
          {:error, reason} ->
            require Logger
            Logger.warning("Essentia NIF failed to load: #{inspect(reason)}. Audio analysis functions will raise :nif_not_loaded.")
            :ok
        end
    end
  end
  
  @doc """
  Analyzes an audio file and extracts loudness, MFCC coefficients, and spectral contrast.

  ## Parameters

  - `file_path`: Path to the audio file to analyze

  ## Returns

  `{:ok, %{loudness: float, mfcc: [float], spectral_contrast: [float]}}` or `{:error, reason}`
  """
  def analyze_audio(_file_path) do
    :erlang.nif_error(:nif_not_loaded)
  end
  
  @doc """
  Extracts chords from an audio file.

  ## Parameters

  - `file_path`: Path to the audio file to analyze

  ## Returns

  `{:ok, [%{chord: binary, strength: float}]}` or `{:error, reason}`
  """
  def extract_chords(_file_path) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Extracts the key and scale of an audio file.

  ## Parameters

  - `file_path`: Path to the audio file to analyze

  ## Returns

  `{:ok, %{key: binary, scale: binary, strength: float}}` or `{:error, reason}`
  """
  def extract_key(_file_path) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Extracts the tempo of an audio file, including BPM and beat tick positions.

  ## Parameters

  - `file_path`: Path to the audio file to analyze

  ## Returns

  `{:ok, %{bpm: float, ticks: [float]}}` or `{:error, reason}`

  `ticks` is a list of beat timestamps in seconds.
  """
  def extract_tempo(_file_path) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Estimates the tuning frequency of a recording.

  Useful for detecting whether a track is at concert pitch (A=440 Hz) or
  detuned — common with vintage recordings, certain genres, or recordings
  that used a different tuning standard.

  ## Parameters

  - `file_path`: Path to the audio file to analyze

  ## Returns

  `{:ok, %{frequency: float, cents_off: float}}` or `{:error, reason}`

  - `frequency`: estimated tuning in Hz (440.0 = standard concert pitch)
  - `cents_off`: deviation in cents from A=440 (positive = sharp, negative = flat)
  """
  def extract_tuning(_file_path) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Returns the duration of an audio file in seconds.

  ## Parameters

  - `file_path`: Path to the audio file

  ## Returns

  `{:ok, float}` or `{:error, reason}`
  """
  def get_duration(_file_path) do
    :erlang.nif_error(:nif_not_loaded)
  end

  @doc """
  Single-pass analysis that extracts key, tempo, chords, tuning, and duration
  in one file read. Prefer this over calling the individual functions separately.

  ## Parameters

  - `file_path`: Path to the audio file to analyze

  ## Returns

      {:ok, %{
        key:      %{key: binary, scale: binary, strength: float},
        tempo:    %{bpm: float, ticks: [float]},
        chords:   [%{chord: binary, strength: float}],
        tuning:   %{frequency: float, cents_off: float},
        duration: float
      }}

  or `{:error, reason}`.
  """
  def analyze_all(_file_path) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
