defmodule Essentia.Chord do
  @moduledoc """
  Utilities for working with musical chords.

  Currently covers the diatonic chords of C major and their common substitutions.
  Chords outside this set are passed through unchanged.
  """

  # Common diatonic substitutions for C major.
  # Each chord maps to a list of alternatives; `related_progressions/1` picks the first.
  @substitutions %{
    "C"    => ["Am", "Cmaj7"],
    "Dm"   => ["F", "Dm7"],
    "Em"   => ["G", "Em7"],
    "F"    => ["Dm", "Fmaj7"],
    "G"    => ["Em", "G7"],
    "Am"   => ["C", "Am7"],
    "Bdim" => ["G7", "Dm"]
  }

  @doc """
  Returns a list of chord progressions derived from `chord_progression` by
  substituting one chord at a time with a common alternative.

  Each element of the returned list is a variation of the original progression
  with exactly one chord replaced. The number of returned progressions equals
  the length of the input.

  Chords not present in the substitution table are left unchanged in that position,
  so the variation for that index is identical to the original.

  ## Examples

      iex> Essentia.Chord.related_progressions(["C", "G", "Am", "F"])
      [
        ["Am", "G", "Am", "F"],
        ["C", "Em", "Am", "F"],
        ["C", "G", "C", "F"],
        ["C", "G", "Am", "Dm"]
      ]

      iex> Essentia.Chord.related_progressions(["C"])
      [["Am"]]

      iex> Essentia.Chord.related_progressions([])
      []
  """
  def related_progressions([]), do: []

  def related_progressions(chord_progression) do
    Enum.map(0..(length(chord_progression) - 1), fn i ->
      List.update_at(chord_progression, i, fn chord ->
        (@substitutions[chord] || [chord]) |> List.first()
      end)
    end)
  end
end
