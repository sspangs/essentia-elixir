defmodule Essentia.AudioAnalysis do
  @moduledoc """
  Higher-level audio analysis built on top of `Essentia` NIFs.

  `analyze/1` is the primary entry point for the music tool layer — it runs
  a single-pass audio analysis and enriches the result with a timestamped
  chord timeline (each segment labelled with its harmonic function) and
  suggested chord progressions.

  Use the individual `Essentia` functions directly when you only need one feature.
  """

  @doc """
  Performs a full analysis of an audio file and enriches the result with:

  - `chord_timeline` — chord frames collapsed into timestamped segments, each
    annotated with its Roman numeral function in the detected key.
  - `suggested_progressions` — variations of the detected chord sequence via
    common substitutions.

  Calls `Essentia.analyze_all/1` (single file read).

  ## Parameters

  - `file_path`: Path to the audio file to analyze

  ## Returns

      {:ok, %{
        key:      %{key: binary, scale: binary, strength: float},
        tempo:    %{bpm: float, ticks: [float]},
        chords:   [%{chord: binary, strength: float}],
        tuning:   %{frequency: float, cents_off: float},
        duration: float,
        chord_timeline: [%{
          chord:    binary,
          function: binary,
          start:    float,
          end:      float,
          strength: float
        }],
        suggested_progressions: [[binary]]
      }}

  or `{:error, reason}`.
  """
  def analyze(file_path) do
    with {:ok, result} <- Essentia.analyze_all(file_path) do
      chord_names = Enum.map(result.chords, & &1.chord)
      timeline    = build_labeled_timeline(result.chords, result.duration, result.key)

      enriched =
        result
        |> Map.put(:chord_timeline, timeline)
        |> Map.put(:suggested_progressions, suggest_chord_progressions(chord_names))

      {:ok, enriched}
    end
  end

  @doc """
  Collapses a list of per-frame chord maps into timestamped segments.

  Consecutive frames with the same chord are merged into one segment.
  Timestamps are derived by dividing `duration` evenly across frames.

  ## Parameters

  - `chords`   — list of `%{chord: binary, strength: float}` (from `Essentia.analyze_all/1`)
  - `duration` — total audio duration in seconds

  ## Returns

  A list of `%{chord: binary, start: float, end: float, strength: float}` maps,
  sorted by start time.

  ## Examples

      iex> chords = [%{chord: "Am", strength: 0.9}, %{chord: "Am", strength: 0.8},
      ...>            %{chord: "F", strength: 0.7}]
      iex> Essentia.AudioAnalysis.chord_timeline(chords, 3.0)
      [
        %{chord: "Am", start: 0.0, end: 2.0, strength: 0.9},
        %{chord: "F",  start: 2.0, end: 3.0, strength: 0.7}
      ]
  """
  def chord_timeline([], _duration), do: []

  def chord_timeline(chords, duration) do
    frame_dur = duration / length(chords)

    chords
    |> Enum.with_index()
    |> Enum.map(fn {%{chord: c, strength: s}, i} ->
      %{chord: c, strength: s, start: i * frame_dur, end: (i + 1) * frame_dur}
    end)
    |> merge_consecutive()
  end

  @doc """
  Derives related chord progressions from a list of chord name strings by
  substituting one chord at a time.

  Delegates to `Essentia.Chord.related_progressions/1`. The chord names should
  be plain strings matching the Essentia output format (e.g. `"C"`, `"Am"`,
  `"G7"`).

  ## Parameters

  - `chords`: List of chord name strings

  ## Returns

  A list of chord progressions (each a list of strings).

  ## Examples

      iex> Essentia.AudioAnalysis.suggest_chord_progressions(["C", "G", "Am", "F"])
      [["Am", "G", "Am", "F"], ["C", "Em", "Am", "F"],
       ["C", "G", "C", "F"],  ["C", "G", "Am", "Dm"]]
  """
  def suggest_chord_progressions(chords) do
    Essentia.Chord.related_progressions(chords)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_labeled_timeline(chords, duration, key) do
    chord_timeline(chords, duration)
    |> Enum.map(fn segment ->
      function = Essentia.Theory.chord_function(segment.chord, key.key, key.scale)
      Map.put(segment, :function, function)
    end)
  end

  defp merge_consecutive([]), do: []

  defp merge_consecutive([head | rest]) do
    rest
    |> Enum.reduce([head], fn segment, [prev | acc] ->
      if segment.chord == prev.chord do
        [%{prev | end: segment.end, strength: max(prev.strength, segment.strength)} | acc]
      else
        [segment, prev | acc]
      end
    end)
    |> Enum.reverse()
  end
end
