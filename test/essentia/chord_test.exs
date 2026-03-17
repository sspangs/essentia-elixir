defmodule Essentia.ChordTest do
  use ExUnit.Case, async: true

  alias Essentia.Chord

  describe "related_progressions/1" do
    test "empty list returns empty list" do
      assert Chord.related_progressions([]) == []
    end

    test "single known chord returns one variation" do
      assert Chord.related_progressions(["C"]) == [["Am"]]
    end

    test "single unknown chord is passed through unchanged" do
      assert Chord.related_progressions(["Xmaj13"]) == [["Xmaj13"]]
    end

    test "returns one variation per chord in the progression" do
      progression = ["C", "G", "Am", "F"]
      result = Chord.related_progressions(progression)
      assert length(result) == length(progression)
    end

    test "each variation differs from original in exactly one position" do
      progression = ["C", "G", "Am", "F"]
      result = Chord.related_progressions(progression)

      for {variation, index} <- Enum.with_index(result) do
        diffs =
          Enum.zip(progression, variation)
          |> Enum.count(fn {a, b} -> a != b end)

        # Either it changed (known chord got substituted) or stayed the same
        # (chord had no substitution). Either way, at most one position differs.
        assert diffs <= 1,
               "Variation #{index} differs in #{diffs} positions, expected at most 1"
      end
    end

    test "variation at index i substitutes chord at position i" do
      progression = ["C", "G", "Am", "F"]
      result = Chord.related_progressions(progression)

      for {variation, i} <- Enum.with_index(result) do
        unchanged = List.delete_at(progression, i)
        variation_without_i = List.delete_at(variation, i)
        assert unchanged == variation_without_i,
               "Variation #{i} changed chords outside position #{i}"
      end
    end

    test "substitutions return strings, not lists" do
      for variation <- Chord.related_progressions(["C", "G", "Am"]) do
        assert Enum.all?(variation, &is_binary/1),
               "Expected all chords to be strings, got: #{inspect(variation)}"
      end
    end

    test "all known chords get a substitute" do
      known = ["C", "Dm", "Em", "F", "G", "Am", "Bdim"]

      for chord <- known do
        [variation] = Chord.related_progressions([chord])
        assert variation != [chord],
               "Expected #{chord} to be substituted but got the same chord back"
      end
    end

    test "unknown chords in a mixed progression are left unchanged" do
      progression = ["C", "Xsus2", "G"]
      result = Chord.related_progressions(progression)
      # Variation at index 1 (Xsus2) should be unchanged
      assert Enum.at(result, 1) == ["C", "Xsus2", "G"]
    end
  end
end
