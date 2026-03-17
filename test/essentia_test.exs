defmodule EssentiaTest do
  use ExUnit.Case

  # Path to an optional real audio file for integration tests.
  # Place any supported audio file (mp3, wav, flac…) here to run the
  # :integration suite: mix test --include integration
  @fixture Path.join([__DIR__, "fixtures", "test_audio.mp3"])

  # ---------------------------------------------------------------------------
  # NIF stubs are defined (no NIF required)
  # ---------------------------------------------------------------------------

  describe "function exports" do
    # function_exported?/3 only works for loaded modules — ensure it's loaded first
    setup do
      Code.ensure_loaded!(Essentia)
      :ok
    end

    test "analyze_all/1 is exported" do
      assert function_exported?(Essentia, :analyze_all, 1)
    end

    test "extract_chords/1 is exported" do
      assert function_exported?(Essentia, :extract_chords, 1)
    end

    test "extract_key/1 is exported" do
      assert function_exported?(Essentia, :extract_key, 1)
    end

    test "extract_tempo/1 is exported" do
      assert function_exported?(Essentia, :extract_tempo, 1)
    end

    test "extract_tuning/1 is exported" do
      assert function_exported?(Essentia, :extract_tuning, 1)
    end

    test "get_duration/1 is exported" do
      assert function_exported?(Essentia, :get_duration, 1)
    end

    test "analyze_audio/1 is exported" do
      assert function_exported?(Essentia, :analyze_audio, 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests — require NIF compiled + audio fixture
  # Run with: mix test --include integration
  # ---------------------------------------------------------------------------

  describe "extract_key/1" do
    @tag :integration
    test "returns key map for a valid audio file" do
      if File.exists?(@fixture) do
        assert {:ok, result} = Essentia.extract_key(@fixture)
        assert %{key: key, scale: scale, strength: strength} = result
        assert is_binary(key)
        assert is_binary(scale)
        assert scale in ["major", "minor"]
        assert is_float(strength)
        assert strength >= 0.0 and strength <= 1.0
        assert String.match?(key, ~r/^[A-G][b#]?$/)
      end
    end

    @tag :integration
    test "returns error for a nonexistent file" do
      assert {:error, _reason} = Essentia.extract_key("/nonexistent/path/audio.mp3")
    end
  end

  describe "extract_tempo/1" do
    @tag :integration
    test "returns bpm and ticks for a valid audio file" do
      if File.exists?(@fixture) do
        assert {:ok, result} = Essentia.extract_tempo(@fixture)
        assert %{bpm: bpm, ticks: ticks} = result
        assert is_float(bpm) and bpm > 0.0
        assert is_list(ticks)
        assert Enum.all?(ticks, &is_float/1)
        assert ticks == Enum.sort(ticks)
      end
    end

    @tag :integration
    test "returns error for a nonexistent file" do
      assert {:error, _reason} = Essentia.extract_tempo("/nonexistent/path/audio.mp3")
    end
  end

  describe "extract_tuning/1" do
    @tag :integration
    test "returns frequency and cents_off for a valid audio file" do
      if File.exists?(@fixture) do
        assert {:ok, result} = Essentia.extract_tuning(@fixture)
        assert %{frequency: frequency, cents_off: cents_off} = result
        assert is_float(frequency)
        assert frequency > 400.0 and frequency < 480.0
        assert is_float(cents_off)
        assert cents_off >= -100.0 and cents_off <= 100.0
      end
    end

    @tag :integration
    test "returns error for a nonexistent file" do
      assert {:error, _reason} = Essentia.extract_tuning("/nonexistent/path/audio.mp3")
    end
  end

  describe "get_duration/1" do
    @tag :integration
    test "returns a positive duration in seconds for a valid audio file" do
      if File.exists?(@fixture) do
        assert {:ok, duration} = Essentia.get_duration(@fixture)
        assert is_float(duration)
        assert duration > 0.0
        assert duration < 7200.0
      end
    end

    @tag :integration
    test "returns error for a nonexistent file" do
      assert {:error, _reason} = Essentia.get_duration("/nonexistent/path/audio.mp3")
    end
  end

  describe "extract_chords/1" do
    @tag :integration
    test "returns a list of chord maps for a valid audio file" do
      if File.exists?(@fixture) do
        assert {:ok, chords} = Essentia.extract_chords(@fixture)
        assert is_list(chords)

        for %{chord: chord, strength: strength} <- chords do
          assert is_binary(chord)
          assert is_float(strength)
          assert strength >= 0.0
        end
      end
    end

    @tag :integration
    test "returns error for a nonexistent file" do
      assert {:error, _reason} = Essentia.extract_chords("/nonexistent/path/audio.mp3")
    end
  end

  describe "analyze_audio/1" do
    @tag :integration
    test "returns loudness, mfcc, and spectral_contrast for a valid audio file" do
      if File.exists?(@fixture) do
        assert {:ok, result} = Essentia.analyze_audio(@fixture)
        assert %{loudness: loudness, mfcc: mfcc, spectral_contrast: contrast} = result
        assert is_float(loudness)
        assert is_list(mfcc) and length(mfcc) > 0
        assert Enum.all?(mfcc, &is_float/1)
        assert is_list(contrast) and length(contrast) > 0
        assert Enum.all?(contrast, &is_float/1)
      end
    end

    @tag :integration
    test "returns error for a nonexistent file" do
      assert {:error, _reason} = Essentia.analyze_audio("/nonexistent/path/audio.mp3")
    end
  end

  describe "analyze_all/1" do
    @tag :integration
    test "returns key, tempo, chords, tuning, and duration in a single call" do
      if File.exists?(@fixture) do
        assert {:ok, result} = Essentia.analyze_all(@fixture)

        assert %{
          key:      key_map,
          tempo:    tempo_map,
          chords:   chords,
          tuning:   tuning_map,
          duration: duration
        } = result

        assert %{key: key, scale: scale, strength: key_strength} = key_map
        assert is_binary(key) and String.match?(key, ~r/^[A-G][b#]?$/)
        assert scale in ["major", "minor"]
        assert is_float(key_strength)

        assert %{bpm: bpm, ticks: ticks} = tempo_map
        assert is_float(bpm) and bpm > 0.0
        assert is_list(ticks) and Enum.all?(ticks, &is_float/1)

        assert is_list(chords)
        for %{chord: chord, strength: strength} <- chords do
          assert is_binary(chord)
          assert is_float(strength)
        end

        assert %{frequency: freq, cents_off: cents} = tuning_map
        assert is_float(freq) and freq > 400.0 and freq < 480.0
        assert is_float(cents)

        assert is_float(duration) and duration > 0.0
      end
    end

    @tag :integration
    test "returns error for a nonexistent file" do
      assert {:error, _reason} = Essentia.analyze_all("/nonexistent/path/audio.mp3")
    end

    @tag :integration
    test "analyze_all key and bpm match individual extractor results" do
      if File.exists?(@fixture) do
        assert {:ok, all}      = Essentia.analyze_all(@fixture)
        assert {:ok, key}      = Essentia.extract_key(@fixture)
        assert {:ok, tempo}    = Essentia.extract_tempo(@fixture)
        assert {:ok, duration} = Essentia.get_duration(@fixture)

        assert all.key.key   == key.key
        assert all.key.scale == key.scale
        assert_in_delta all.tempo.bpm, tempo.bpm, 0.001
        assert_in_delta all.duration, duration, 0.001
      end
    end
  end
end
