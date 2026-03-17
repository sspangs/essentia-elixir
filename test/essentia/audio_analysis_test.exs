defmodule Essentia.AudioAnalysisTest do
  use ExUnit.Case, async: true

  alias Essentia.AudioAnalysis

  @fixture Path.join([__DIR__, "..", "fixtures", "test_audio.mp3"])

  # ---------------------------------------------------------------------------
  # Pure Elixir — no NIF required
  # ---------------------------------------------------------------------------

  describe "chord_timeline/2" do
    test "collapses consecutive identical chords into segments" do
      chords = [
        %{chord: "Am", strength: 0.9},
        %{chord: "Am", strength: 0.8},
        %{chord: "F",  strength: 0.7}
      ]
      result = AudioAnalysis.chord_timeline(chords, 3.0)
      assert length(result) == 2
      assert Enum.at(result, 0) == %{chord: "Am", start: 0.0, end: 2.0, strength: 0.9}
      assert Enum.at(result, 1) == %{chord: "F",  start: 2.0, end: 3.0, strength: 0.7}
    end

    test "keeps max strength when merging consecutive frames" do
      chords = [%{chord: "C", strength: 0.5}, %{chord: "C", strength: 0.9}]
      [segment] = AudioAnalysis.chord_timeline(chords, 2.0)
      assert segment.strength == 0.9
    end

    test "returns each frame as its own segment when all chords differ" do
      chords = [%{chord: "C", strength: 0.8}, %{chord: "G", strength: 0.7}]
      result = AudioAnalysis.chord_timeline(chords, 2.0)
      assert length(result) == 2
    end

    test "returns empty list for empty input" do
      assert AudioAnalysis.chord_timeline([], 4.0) == []
    end
  end

  describe "suggest_chord_progressions/1" do
    test "delegates to Essentia.Chord.related_progressions/1" do
      input = ["C", "G", "Am", "F"]
      assert AudioAnalysis.suggest_chord_progressions(input) ==
               Essentia.Chord.related_progressions(input)
    end

    test "returns empty list for empty input" do
      assert AudioAnalysis.suggest_chord_progressions([]) == []
    end

    test "returns a list of progressions" do
      result = AudioAnalysis.suggest_chord_progressions(["C", "Am"])
      assert is_list(result)
      assert Enum.all?(result, &is_list/1)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests — require NIF compiled + audio fixture
  # Run with: mix test --include integration
  # ---------------------------------------------------------------------------

  describe "analyze/1" do
    @tag :integration
    test "returns key, tempo, chords, tuning, duration, chord_timeline, and suggested_progressions" do
      if File.exists?(@fixture) do
        assert {:ok, result} = AudioAnalysis.analyze(@fixture)
        assert Map.has_key?(result, :key)
        assert Map.has_key?(result, :tempo)
        assert Map.has_key?(result, :chords)
        assert Map.has_key?(result, :tuning)
        assert Map.has_key?(result, :duration)
        assert Map.has_key?(result, :chord_timeline)
        assert Map.has_key?(result, :suggested_progressions)

        for segment <- result.chord_timeline do
          assert is_binary(segment.chord)
          assert is_binary(segment.function)
          assert is_float(segment.start)
          assert is_float(segment.end)
          assert is_float(segment.strength)
          assert segment.start < segment.end
        end

        assert is_list(result.suggested_progressions)
        assert Enum.all?(result.suggested_progressions, &is_list/1)
      end
    end

    @tag :integration
    test "returns error for a nonexistent file" do
      assert {:error, _} = AudioAnalysis.analyze("/no/such/file.mp3")
    end
  end
end
