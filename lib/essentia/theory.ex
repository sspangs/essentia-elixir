defmodule Essentia.Theory do
  @moduledoc """
  Pure Elixir music theory utilities.

  ## Chord functions

  `chord_function/3` labels a chord by its Roman numeral role in a given key.
  Useful for understanding harmonic context — e.g. "Am" in C major is "vi".

  ## Transposition

  `transpose/2` shifts a chord or list of chords by a number of semitones.

  ## Notes on chord names

  Chord names follow Essentia's output format: root note (e.g. `"C"`, `"C#"`,
  `"Bb"`) followed by an optional quality suffix (`"m"`, `"7"`, `"maj7"`, etc.).
  Flat roots (e.g. `"Bb"`) are normalised to their sharp equivalent internally
  but returned with the original suffix.
  """

  @chromatic ~w(C C# D D# E F F# G G# A A# B)

  @enharmonic %{
    "Db" => "C#", "Eb" => "D#", "Fb" => "E", "Gb" => "F#",
    "Ab" => "G#", "Bb" => "A#", "Cb" => "B"
  }

  # Scale intervals (semitones from root) and their Roman numeral labels.
  @major_intervals [0, 2, 4, 5, 7, 9, 11]
  @minor_intervals [0, 2, 3, 5, 7, 8, 10]
  @major_numerals  ~w(I ii iii IV V vi vii°)
  @minor_numerals  ~w(i ii° III iv v VI VII)

  @doc """
  Returns the Roman numeral function of `chord` within the given key.

  Only the chord root is used for the lookup — the quality suffix (e.g. `"m"`,
  `"7"`) is ignored. Chords whose root doesn't fall on a diatonic scale degree
  return `"?"`.

  ## Examples

      iex> Essentia.Theory.chord_function("Am", "C", "major")
      "vi"

      iex> Essentia.Theory.chord_function("G7", "C", "major")
      "V"

      iex> Essentia.Theory.chord_function("E", "A", "minor")
      "V"

      iex> Essentia.Theory.chord_function("C#", "D", "major")
      "?"
  """
  def chord_function(chord, key_root, scale) do
    {chord_root, _suffix} = parse_chord(chord)
    key_idx   = note_index(key_root)
    chord_idx = note_index(chord_root)
    interval  = rem(chord_idx - key_idx + 12, 12)

    {intervals, numerals} =
      if scale == "major",
        do: {@major_intervals, @major_numerals},
        else: {@minor_intervals, @minor_numerals}

    case Enum.find_index(intervals, &(&1 == interval)) do
      nil -> "?"
      i   -> Enum.at(numerals, i)
    end
  end

  @doc """
  Transposes a list of chord names by `semitones`.

  Roots are shifted chromatically using sharps. The quality suffix of each
  chord is preserved unchanged.

  ## Examples

      iex> Essentia.Theory.transpose(["C", "Am", "F", "G"], 2)
      ["D", "Bm", "G", "A"]

      iex> Essentia.Theory.transpose(["C#m", "E", "B"], -1)
      ["Cm", "Eb", "Bb"]
  """
  def transpose(chords, semitones) when is_list(chords) do
    Enum.map(chords, &transpose_chord(&1, semitones))
  end

  @doc """
  Transposes a single chord name by `semitones`.

  ## Examples

      iex> Essentia.Theory.transpose_chord("Am", 3)
      "Cm"

      iex> Essentia.Theory.transpose_chord("G7", -2)
      "F7"
  """
  def transpose_chord(chord, semitones) do
    {root, suffix} = parse_chord(chord)
    new_idx = rem(note_index(root) + semitones + 120, 12)
    Enum.at(@chromatic, new_idx) <> suffix
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp parse_chord(""), do: {"", ""}

  defp parse_chord(chord) do
    if String.length(chord) >= 2 and String.at(chord, 1) in ["#", "b"] do
      root   = chord |> String.slice(0, 2) |> normalize_note()
      suffix = String.slice(chord, 2..-1//1)
      {root, suffix}
    else
      {normalize_note(String.slice(chord, 0, 1)), String.slice(chord, 1..-1//1)}
    end
  end

  defp normalize_note(note), do: Map.get(@enharmonic, note, note)

  defp note_index(note) do
    normalized = normalize_note(note)
    Enum.find_index(@chromatic, &(&1 == normalized)) || 0
  end
end
