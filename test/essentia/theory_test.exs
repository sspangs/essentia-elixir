defmodule Essentia.TheoryTest do
  use ExUnit.Case, async: true

  alias Essentia.Theory

  describe "chord_function/3" do
    test "labels diatonic major chords correctly" do
      assert Theory.chord_function("C",    "C", "major") == "I"
      assert Theory.chord_function("Dm",   "C", "major") == "ii"
      assert Theory.chord_function("Em",   "C", "major") == "iii"
      assert Theory.chord_function("F",    "C", "major") == "IV"
      assert Theory.chord_function("G",    "C", "major") == "V"
      assert Theory.chord_function("Am",   "C", "major") == "vi"
      assert Theory.chord_function("Bdim", "C", "major") == "vii°"
    end

    test "labels diatonic minor chords correctly" do
      assert Theory.chord_function("Am",  "A", "minor") == "i"
      assert Theory.chord_function("Bdim","A", "minor") == "ii°"
      assert Theory.chord_function("C",   "A", "minor") == "III"
      assert Theory.chord_function("Dm",  "A", "minor") == "iv"
      assert Theory.chord_function("Em",  "A", "minor") == "v"
      assert Theory.chord_function("F",   "A", "minor") == "VI"
      assert Theory.chord_function("G",   "A", "minor") == "VII"
    end

    test "ignores chord quality suffix for lookup" do
      assert Theory.chord_function("G7",   "C", "major") == "V"
      assert Theory.chord_function("Fmaj7","C", "major") == "IV"
      assert Theory.chord_function("Am7",  "C", "major") == "vi"
    end

    test "returns ? for non-diatonic chords" do
      assert Theory.chord_function("C#", "C", "major") == "?"
      assert Theory.chord_function("Eb", "C", "major") == "?"
    end

    test "handles flat root keys" do
      assert Theory.chord_function("Bb", "F", "major") == "IV"
      assert Theory.chord_function("Eb", "Bb", "major") == "IV"
    end

    test "handles sharp root keys" do
      assert Theory.chord_function("A", "E", "major") == "IV"
      assert Theory.chord_function("B", "E", "major") == "V"
    end
  end

  describe "transpose/2" do
    test "transposes a list up by semitones" do
      assert Theory.transpose(["C", "Am", "F", "G"], 2) == ["D", "Bm", "G", "A"]
    end

    test "transposes down by semitones" do
      assert Theory.transpose(["C", "Am", "F", "G"], -2) == ["A#", "Gm", "D#", "F"]
    end

    test "wraps around octave" do
      assert Theory.transpose(["B"], 1) == ["C"]
      assert Theory.transpose(["C"], -1) == ["B"]
    end

    test "preserves quality suffix" do
      assert Theory.transpose(["Cmaj7", "Am7", "Fmaj7", "G7"], 5) == ["Fmaj7", "Dm7", "A#maj7", "C7"]
    end

    test "returns empty list for empty input" do
      assert Theory.transpose([], 3) == []
    end
  end

  describe "transpose_chord/2" do
    test "transposes a single chord" do
      assert Theory.transpose_chord("Am", 3) == "Cm"
      assert Theory.transpose_chord("G7", -2) == "F7"
    end
  end
end
