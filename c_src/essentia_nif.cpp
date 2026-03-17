#include <erl_nif.h>
#include <climits>
#include <cstring>
#include <vector>
#include <essentia/essentia.h>
#include <essentia/algorithm.h>
#include <essentia/algorithmfactory.h>
#include <essentia/pool.h>
#include <essentia/scheduler/network.h>

using namespace essentia;
using namespace essentia::standard;

// NIF state structure
typedef struct {
    ErlNifResourceType* essentia_resource_type;
} EssentiaPrivData;

// Delete all algorithms in the vector and clear it
static void free_algorithms(std::vector<Algorithm*>& algos) {
    for (Algorithm* a : algos) delete a;
    algos.clear();
}

// Convert a vector of Real values to an Erlang list of floats
static ERL_NIF_TERM real_vec_to_list(ErlNifEnv* env, const std::vector<Real>& v) {
    ERL_NIF_TERM list = enif_make_list(env, 0);
    for (int i = (int)v.size() - 1; i >= 0; i--)
        list = enif_make_list_cell(env, enif_make_double(env, v[i]), list);
    return list;
}

// Initialize Essentia
static int load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
    EssentiaPrivData* data = (EssentiaPrivData*)enif_alloc(sizeof(EssentiaPrivData));
    if (data == NULL) return 1;
    essentia::init();
    *priv_data = data;
    return 0;
}

// Clean up Essentia
static void unload(ErlNifEnv* env, void* priv_data) {
    EssentiaPrivData* data = (EssentiaPrivData*)priv_data;
    if (data) {
        essentia::shutdown();
        enif_free(data);
    }
}

// Extract chords from audio file
// Returns {:ok, [%{chord: binary, strength: float}]} | {:error, reason}
static ERL_NIF_TERM extract_chords(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char file_path[PATH_MAX];
    if (!enif_get_string(env, argv[0], file_path, PATH_MAX, ERL_NIF_LATIN1)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_atom(env, "invalid_path"));
    }

    std::vector<Algorithm*> algos;

    try {
        // ChordsDetection expects a full vector of HPCP frames, not per-frame calls.
        // Pipeline: MonoLoader → FrameCutter → Windowing → Spectrum → SpectralPeaks → HPCP
        // Accumulate all HPCP frames, then call ChordsDetection once.
        AlgorithmFactory& factory = AlgorithmFactory::instance();

        Algorithm* audio           = factory.create("MonoLoader",
                                                    "filename", std::string(file_path),
                                                    "sampleRate", 44100);
        Algorithm* frameCutter     = factory.create("FrameCutter",
                                                    "frameSize", 4096,
                                                    "hopSize", 2048,
                                                    "startFromZero", true);
        Algorithm* windowing       = factory.create("Windowing", "type", "blackmanharris62");
        Algorithm* spectrum        = factory.create("Spectrum");
        Algorithm* spectralPeaks   = factory.create("SpectralPeaks",
                                                    "maxPeaks", 10000,
                                                    "magnitudeThreshold", 0.00001,
                                                    "minFrequency", 40,
                                                    "maxFrequency", 5000,
                                                    "orderBy", "magnitude");
        Algorithm* hpcp            = factory.create("HPCP");
        Algorithm* chordsDetection = factory.create("ChordsDetection");

        algos = {audio, frameCutter, windowing, spectrum, spectralPeaks, hpcp, chordsDetection};

        std::vector<Real> audio_buffer;
        std::vector<Real> frame, windowed_frame, spec;
        std::vector<Real> frequencies, magnitudes, hpcp_frame;
        std::vector<std::vector<Real>> hpcp_frames;
        std::vector<std::string> chords;
        std::vector<Real> strengths;

        audio->output("audio").set(audio_buffer);
        frameCutter->input("signal").set(audio_buffer);
        frameCutter->output("frame").set(frame);
        windowing->input("frame").set(frame);
        windowing->output("frame").set(windowed_frame);
        spectrum->input("frame").set(windowed_frame);
        spectrum->output("spectrum").set(spec);
        spectralPeaks->input("spectrum").set(spec);
        spectralPeaks->output("frequencies").set(frequencies);
        spectralPeaks->output("magnitudes").set(magnitudes);
        hpcp->input("frequencies").set(frequencies);
        hpcp->input("magnitudes").set(magnitudes);
        hpcp->output("hpcp").set(hpcp_frame);
        chordsDetection->input("pcp").set(hpcp_frames);
        chordsDetection->output("chords").set(chords);
        chordsDetection->output("strength").set(strengths);

        audio->compute();

        while (true) {
            frameCutter->compute();
            if (frame.empty()) break;
            windowing->compute();
            spectrum->compute();
            spectralPeaks->compute();
            hpcp->compute();
            hpcp_frames.push_back(hpcp_frame);
        }

        chordsDetection->compute();
        free_algorithms(algos);

        // Build list of %{chord: <<...>>, strength: float} maps
        ERL_NIF_TERM result_list = enif_make_list(env, 0);
        ERL_NIF_TERM chord_key    = enif_make_atom(env, "chord");
        ERL_NIF_TERM strength_key = enif_make_atom(env, "strength");

        for (int i = (int)chords.size() - 1; i >= 0; i--) {
            ERL_NIF_TERM chord_bin;
            unsigned char* buf = enif_make_new_binary(env, chords[i].size(), &chord_bin);
            memcpy(buf, chords[i].c_str(), chords[i].size());

            ERL_NIF_TERM map_keys[2] = {chord_key, strength_key};
            ERL_NIF_TERM map_vals[2] = {chord_bin, enif_make_double(env, strengths[i])};
            ERL_NIF_TERM entry;
            enif_make_map_from_arrays(env, map_keys, map_vals, 2, &entry);
            result_list = enif_make_list_cell(env, entry, result_list);
        }

        return enif_make_tuple2(env, enif_make_atom(env, "ok"), result_list);
    }
    catch (const std::exception& e) {
        free_algorithms(algos);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_string(env, e.what(), ERL_NIF_LATIN1));
    }
}

// Extract key from audio file
// Returns {:ok, %{key: binary, scale: binary, strength: float}} | {:error, reason}
static ERL_NIF_TERM extract_key(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char file_path[PATH_MAX];
    if (!enif_get_string(env, argv[0], file_path, PATH_MAX, ERL_NIF_LATIN1)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_atom(env, "invalid_path"));
    }

    std::vector<Algorithm*> algos;

    try {
        // Key requires HPCP chroma input, not raw audio.
        // Pipeline: MonoLoader → FrameCutter → Windowing → Spectrum → SpectralPeaks → HPCP → Key
        // Accumulate mean HPCP across all frames, then call Key once.
        AlgorithmFactory& factory = AlgorithmFactory::instance();

        Algorithm* audio         = factory.create("MonoLoader",
                                                  "filename", std::string(file_path),
                                                  "sampleRate", 44100);
        Algorithm* frameCutter   = factory.create("FrameCutter",
                                                  "frameSize", 4096,
                                                  "hopSize", 2048,
                                                  "startFromZero", true);
        Algorithm* windowing     = factory.create("Windowing", "type", "blackmanharris62");
        Algorithm* spectrum      = factory.create("Spectrum");
        Algorithm* spectralPeaks = factory.create("SpectralPeaks",
                                                  "maxPeaks", 10000,
                                                  "magnitudeThreshold", 0.00001,
                                                  "minFrequency", 40,
                                                  "maxFrequency", 5000,
                                                  "orderBy", "magnitude");
        Algorithm* hpcp          = factory.create("HPCP");
        Algorithm* keyAlg        = factory.create("Key");

        algos = {audio, frameCutter, windowing, spectrum, spectralPeaks, hpcp, keyAlg};

        std::vector<Real> audio_buffer;
        std::vector<Real> frame, windowed_frame, spec;
        std::vector<Real> frequencies, magnitudes, hpcp_frame;
        std::vector<Real> hpcp_mean(12, 0.0f);
        std::string key_str, scale_str;
        Real strength;
        int frame_count = 0;

        audio->output("audio").set(audio_buffer);
        frameCutter->input("signal").set(audio_buffer);
        frameCutter->output("frame").set(frame);
        windowing->input("frame").set(frame);
        windowing->output("frame").set(windowed_frame);
        spectrum->input("frame").set(windowed_frame);
        spectrum->output("spectrum").set(spec);
        spectralPeaks->input("spectrum").set(spec);
        spectralPeaks->output("frequencies").set(frequencies);
        spectralPeaks->output("magnitudes").set(magnitudes);
        hpcp->input("frequencies").set(frequencies);
        hpcp->input("magnitudes").set(magnitudes);
        hpcp->output("hpcp").set(hpcp_frame);
        keyAlg->input("pcp").set(hpcp_mean);
        keyAlg->output("key").set(key_str);
        keyAlg->output("scale").set(scale_str);
        keyAlg->output("strength").set(strength);

        audio->compute();

        while (true) {
            frameCutter->compute();
            if (frame.empty()) break;
            windowing->compute();
            spectrum->compute();
            spectralPeaks->compute();
            hpcp->compute();
            for (size_t i = 0; i < 12; i++) hpcp_mean[i] += hpcp_frame[i];
            frame_count++;
        }

        if (frame_count > 0) {
            for (size_t i = 0; i < 12; i++) hpcp_mean[i] /= frame_count;
        }

        keyAlg->compute();
        free_algorithms(algos);

        // Use binaries — atom encoding breaks on sharps/flats (e.g. "C#")
        ERL_NIF_TERM key_bin, scale_bin;
        unsigned char* key_buf   = enif_make_new_binary(env, key_str.size(), &key_bin);
        unsigned char* scale_buf = enif_make_new_binary(env, scale_str.size(), &scale_bin);
        memcpy(key_buf,   key_str.c_str(),   key_str.size());
        memcpy(scale_buf, scale_str.c_str(), scale_str.size());

        ERL_NIF_TERM map_keys[3] = {
            enif_make_atom(env, "key"),
            enif_make_atom(env, "scale"),
            enif_make_atom(env, "strength")
        };
        ERL_NIF_TERM map_vals[3] = {key_bin, scale_bin, enif_make_double(env, strength)};
        ERL_NIF_TERM result;
        enif_make_map_from_arrays(env, map_keys, map_vals, 3, &result);

        return enif_make_tuple2(env, enif_make_atom(env, "ok"), result);
    }
    catch (const std::exception& e) {
        free_algorithms(algos);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_string(env, e.what(), ERL_NIF_LATIN1));
    }
}

// Extract tempo (BPM) from audio file
// Returns {:ok, float} | {:error, reason}
static ERL_NIF_TERM extract_tempo(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char file_path[PATH_MAX];
    if (!enif_get_string(env, argv[0], file_path, PATH_MAX, ERL_NIF_LATIN1)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_atom(env, "invalid_path"));
    }

    std::vector<Algorithm*> algos;

    try {
        AlgorithmFactory& factory = AlgorithmFactory::instance();

        Algorithm* audio           = factory.create("MonoLoader",
                                                    "filename", std::string(file_path),
                                                    "sampleRate", 44100);
        Algorithm* rhythmExtractor = factory.create("RhythmExtractor2013");

        algos = {audio, rhythmExtractor};

        std::vector<Real> audio_buffer;
        Real bpm, confidence;
        std::vector<Real> ticks, estimates, bpmIntervals;

        audio->output("audio").set(audio_buffer);
        rhythmExtractor->input("audio").set(audio_buffer);
        rhythmExtractor->output("bpm").set(bpm);
        rhythmExtractor->output("confidence").set(confidence);
        rhythmExtractor->output("ticks").set(ticks);
        rhythmExtractor->output("estimates").set(estimates);
        rhythmExtractor->output("bpmIntervals").set(bpmIntervals);

        audio->compute();
        rhythmExtractor->compute();
        free_algorithms(algos);

        ERL_NIF_TERM map_keys[2] = {enif_make_atom(env, "bpm"), enif_make_atom(env, "ticks")};
        ERL_NIF_TERM map_vals[2] = {enif_make_double(env, bpm), real_vec_to_list(env, ticks)};
        ERL_NIF_TERM result;
        enif_make_map_from_arrays(env, map_keys, map_vals, 2, &result);

        return enif_make_tuple2(env, enif_make_atom(env, "ok"), result);
    }
    catch (const std::exception& e) {
        free_algorithms(algos);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_string(env, e.what(), ERL_NIF_LATIN1));
    }
}

// Analyze audio file — loudness, MFCC, and spectral contrast (frame-wise means)
// Returns {:ok, %{loudness: float, mfcc: [float], spectral_contrast: [float]}} | {:error, reason}
static ERL_NIF_TERM analyze_audio(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char file_path[PATH_MAX];
    if (!enif_get_string(env, argv[0], file_path, PATH_MAX, ERL_NIF_LATIN1)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_atom(env, "invalid_path"));
    }

    std::vector<Algorithm*> algos;

    try {
        // Frame-wise pipeline: MonoLoader → FrameCutter → Windowing → Spectrum
        //   → Loudness, MFCC, SpectralContrast (all from spectrum per frame)
        // Returns frame-averaged values.
        AlgorithmFactory& factory = AlgorithmFactory::instance();

        Algorithm* audio               = factory.create("MonoLoader",
                                                        "filename", std::string(file_path),
                                                        "sampleRate", 44100);
        Algorithm* frameCutter         = factory.create("FrameCutter",
                                                        "frameSize", 4096,
                                                        "hopSize", 2048,
                                                        "startFromZero", true);
        Algorithm* windowing           = factory.create("Windowing", "type", "blackmanharris62");
        Algorithm* spectrumAlg         = factory.create("Spectrum");
        Algorithm* loudnessAlg         = factory.create("Loudness");
        Algorithm* mfccAlg             = factory.create("MFCC");
        Algorithm* spectralContrastAlg = factory.create("SpectralContrast");

        algos = {audio, frameCutter, windowing, spectrumAlg,
                 loudnessAlg, mfccAlg, spectralContrastAlg};

        std::vector<Real> audio_buffer;
        std::vector<Real> frame, windowed_frame, spec;
        Real loudness_value;
        std::vector<Real> mfcc_bands, mfcc_coeffs;
        std::vector<Real> contrast_values, contrast_bands;

        audio->output("audio").set(audio_buffer);
        frameCutter->input("signal").set(audio_buffer);
        frameCutter->output("frame").set(frame);
        windowing->input("frame").set(frame);
        windowing->output("frame").set(windowed_frame);
        spectrumAlg->input("frame").set(windowed_frame);
        spectrumAlg->output("spectrum").set(spec);
        loudnessAlg->input("signal").set(frame);
        loudnessAlg->output("loudness").set(loudness_value);
        mfccAlg->input("spectrum").set(spec);
        mfccAlg->output("bands").set(mfcc_bands);
        mfccAlg->output("mfcc").set(mfcc_coeffs);
        spectralContrastAlg->input("spectrum").set(spec);
        spectralContrastAlg->output("spectralContrast").set(contrast_values);
        spectralContrastAlg->output("spectralContrastBands").set(contrast_bands);

        audio->compute();

        double loudness_sum = 0.0;
        int frame_count = 0;
        std::vector<double> mfcc_sum, contrast_sum;

        while (true) {
            frameCutter->compute();
            if (frame.empty()) break;
            windowing->compute();
            spectrumAlg->compute();
            loudnessAlg->compute();
            mfccAlg->compute();
            spectralContrastAlg->compute();

            loudness_sum += loudness_value;

            if (mfcc_sum.empty()) mfcc_sum.resize(mfcc_coeffs.size(), 0.0);
            for (size_t i = 0; i < mfcc_coeffs.size(); i++) mfcc_sum[i] += mfcc_coeffs[i];

            if (contrast_sum.empty()) contrast_sum.resize(contrast_values.size(), 0.0);
            for (size_t i = 0; i < contrast_values.size(); i++) contrast_sum[i] += contrast_values[i];

            frame_count++;
        }

        free_algorithms(algos);

        double mean_loudness = frame_count > 0 ? loudness_sum / frame_count : 0.0;

        ERL_NIF_TERM mfcc_list = enif_make_list(env, 0);
        for (int i = (int)mfcc_sum.size() - 1; i >= 0; i--) {
            double val = frame_count > 0 ? mfcc_sum[i] / frame_count : 0.0;
            mfcc_list = enif_make_list_cell(env, enif_make_double(env, val), mfcc_list);
        }

        ERL_NIF_TERM contrast_list = enif_make_list(env, 0);
        for (int i = (int)contrast_sum.size() - 1; i >= 0; i--) {
            double val = frame_count > 0 ? contrast_sum[i] / frame_count : 0.0;
            contrast_list = enif_make_list_cell(env, enif_make_double(env, val), contrast_list);
        }

        ERL_NIF_TERM map_keys[3] = {
            enif_make_atom(env, "loudness"),
            enif_make_atom(env, "mfcc"),
            enif_make_atom(env, "spectral_contrast")
        };
        ERL_NIF_TERM map_vals[3] = {
            enif_make_double(env, mean_loudness),
            mfcc_list,
            contrast_list
        };
        ERL_NIF_TERM result_map;
        enif_make_map_from_arrays(env, map_keys, map_vals, 3, &result_map);

        return enif_make_tuple2(env, enif_make_atom(env, "ok"), result_map);
    }
    catch (const std::exception& e) {
        free_algorithms(algos);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_string(env, e.what(), ERL_NIF_LATIN1));
    }
}

// Estimates the tuning frequency of the recording (concert pitch deviation).
// Returns {:ok, %{frequency: float, cents_off: float}} | {:error, reason}
// frequency: estimated tuning in Hz (440.0 = standard concert pitch)
// cents_off: deviation in cents from A=440 (positive = sharp, negative = flat)
static ERL_NIF_TERM extract_tuning(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char file_path[PATH_MAX];
    if (!enif_get_string(env, argv[0], file_path, PATH_MAX, ERL_NIF_LATIN1)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_atom(env, "invalid_path"));
    }

    std::vector<Algorithm*> algos;

    try {
        // Pipeline: MonoLoader → FrameCutter → Windowing → Spectrum → SpectralPeaks → TuningFrequency
        AlgorithmFactory& factory = AlgorithmFactory::instance();

        Algorithm* audio         = factory.create("MonoLoader",
                                                  "filename", std::string(file_path),
                                                  "sampleRate", 44100);
        Algorithm* frameCutter   = factory.create("FrameCutter",
                                                  "frameSize", 4096,
                                                  "hopSize", 2048,
                                                  "startFromZero", true);
        Algorithm* windowing     = factory.create("Windowing", "type", "blackmanharris62");
        Algorithm* spectrumAlg   = factory.create("Spectrum");
        Algorithm* spectralPeaks = factory.create("SpectralPeaks",
                                                  "maxPeaks", 10000,
                                                  "magnitudeThreshold", 0.00001,
                                                  "minFrequency", 40,
                                                  "maxFrequency", 5000,
                                                  "orderBy", "magnitude");
        Algorithm* tuningAlg     = factory.create("TuningFrequency");

        algos = {audio, frameCutter, windowing, spectrumAlg, spectralPeaks, tuningAlg};

        std::vector<Real> audio_buffer;
        std::vector<Real> frame, windowed_frame, spec;
        std::vector<Real> frequencies, magnitudes;
        Real tuning_freq, tuning_cents;

        audio->output("audio").set(audio_buffer);
        frameCutter->input("signal").set(audio_buffer);
        frameCutter->output("frame").set(frame);
        windowing->input("frame").set(frame);
        windowing->output("frame").set(windowed_frame);
        spectrumAlg->input("frame").set(windowed_frame);
        spectrumAlg->output("spectrum").set(spec);
        spectralPeaks->input("spectrum").set(spec);
        spectralPeaks->output("frequencies").set(frequencies);
        spectralPeaks->output("magnitudes").set(magnitudes);
        tuningAlg->input("frequencies").set(frequencies);
        tuningAlg->input("magnitudes").set(magnitudes);
        tuningAlg->output("tuningFrequency").set(tuning_freq);
        tuningAlg->output("tuningCents").set(tuning_cents);

        audio->compute();

        // Accumulate per-frame estimates; median is more robust than mean for tuning
        std::vector<Real> freq_estimates, cents_estimates;
        while (true) {
            frameCutter->compute();
            if (frame.empty()) break;
            windowing->compute();
            spectrumAlg->compute();
            spectralPeaks->compute();
            if (!frequencies.empty()) {
                tuningAlg->compute();
                freq_estimates.push_back(tuning_freq);
                cents_estimates.push_back(tuning_cents);
            }
        }

        free_algorithms(algos);

        double final_freq = 440.0, final_cents = 0.0;
        if (!freq_estimates.empty()) {
            // Median is more robust than mean for per-frame tuning estimates
            std::sort(freq_estimates.begin(), freq_estimates.end());
            std::sort(cents_estimates.begin(), cents_estimates.end());
            size_t mid = freq_estimates.size() / 2;
            final_freq  = freq_estimates[mid];
            final_cents = cents_estimates[mid];
        }

        ERL_NIF_TERM map_keys[2] = {enif_make_atom(env, "frequency"), enif_make_atom(env, "cents_off")};
        ERL_NIF_TERM map_vals[2] = {enif_make_double(env, final_freq), enif_make_double(env, final_cents)};
        ERL_NIF_TERM result;
        enif_make_map_from_arrays(env, map_keys, map_vals, 2, &result);

        return enif_make_tuple2(env, enif_make_atom(env, "ok"), result);
    }
    catch (const std::exception& e) {
        free_algorithms(algos);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_string(env, e.what(), ERL_NIF_LATIN1));
    }
}

// Returns duration of the audio file in seconds.
// Returns {:ok, float} | {:error, reason}
static ERL_NIF_TERM get_duration(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char file_path[PATH_MAX];
    if (!enif_get_string(env, argv[0], file_path, PATH_MAX, ERL_NIF_LATIN1)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_atom(env, "invalid_path"));
    }

    std::vector<Algorithm*> algos;

    try {
        AlgorithmFactory& factory = AlgorithmFactory::instance();
        Algorithm* audio = factory.create("MonoLoader",
                                          "filename", std::string(file_path),
                                          "sampleRate", 44100);
        algos = {audio};

        std::vector<Real> audio_buffer;
        audio->output("audio").set(audio_buffer);
        audio->compute();
        free_algorithms(algos);

        double duration = static_cast<double>(audio_buffer.size()) / 44100.0;
        return enif_make_tuple2(env, enif_make_atom(env, "ok"), enif_make_double(env, duration));
    }
    catch (const std::exception& e) {
        free_algorithms(algos);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_string(env, e.what(), ERL_NIF_LATIN1));
    }
}

// Single-pass analysis: key + tempo + chords in one file read.
// Returns {:ok, %{key: map, tempo: float, chords: list}} | {:error, reason}
static ERL_NIF_TERM analyze_all(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    char file_path[PATH_MAX];
    if (!enif_get_string(env, argv[0], file_path, PATH_MAX, ERL_NIF_LATIN1)) {
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_atom(env, "invalid_path"));
    }

    std::vector<Algorithm*> algos;

    try {
        AlgorithmFactory& factory = AlgorithmFactory::instance();

        // Shared frame pipeline
        Algorithm* audio         = factory.create("MonoLoader",
                                                  "filename", std::string(file_path),
                                                  "sampleRate", 44100);
        Algorithm* frameCutter   = factory.create("FrameCutter",
                                                  "frameSize", 4096,
                                                  "hopSize", 2048,
                                                  "startFromZero", true);
        Algorithm* windowing     = factory.create("Windowing", "type", "blackmanharris62");
        Algorithm* spectrumAlg   = factory.create("Spectrum");
        Algorithm* spectralPeaks = factory.create("SpectralPeaks",
                                                  "maxPeaks", 10000,
                                                  "magnitudeThreshold", 0.00001,
                                                  "minFrequency", 40,
                                                  "maxFrequency", 5000,
                                                  "orderBy", "magnitude");
        Algorithm* hpcp          = factory.create("HPCP");

        // Key (needs mean HPCP)
        Algorithm* keyAlg        = factory.create("Key");

        // Tempo (whole-signal; compute after loading audio)
        Algorithm* rhythmExtractor = factory.create("RhythmExtractor2013");

        // Chords (needs all HPCP frames)
        Algorithm* chordsDetection = factory.create("ChordsDetection");

        // Tuning (per-frame from spectral peaks, median pooled)
        Algorithm* tuningAlg     = factory.create("TuningFrequency");

        algos = {audio, frameCutter, windowing, spectrumAlg, spectralPeaks,
                 hpcp, keyAlg, rhythmExtractor, chordsDetection, tuningAlg};

        std::vector<Real> audio_buffer;
        std::vector<Real> frame, windowed_frame, spec;
        std::vector<Real> frequencies, magnitudes, hpcp_frame;
        std::vector<Real> hpcp_mean(12, 0.0f);
        std::vector<std::vector<Real>> hpcp_frames;
        int frame_count = 0;

        std::string key_str, scale_str;
        Real key_strength;
        Real bpm, confidence;
        std::vector<Real> ticks, estimates, bpmIntervals;
        std::vector<std::string> chords;
        std::vector<Real> chord_strengths;
        Real tuning_freq, tuning_cents;
        std::vector<Real> freq_estimates, cents_estimates;

        // Wire up frame pipeline
        audio->output("audio").set(audio_buffer);
        frameCutter->input("signal").set(audio_buffer);
        frameCutter->output("frame").set(frame);
        windowing->input("frame").set(frame);
        windowing->output("frame").set(windowed_frame);
        spectrumAlg->input("frame").set(windowed_frame);
        spectrumAlg->output("spectrum").set(spec);
        spectralPeaks->input("spectrum").set(spec);
        spectralPeaks->output("frequencies").set(frequencies);
        spectralPeaks->output("magnitudes").set(magnitudes);
        hpcp->input("frequencies").set(frequencies);
        hpcp->input("magnitudes").set(magnitudes);
        hpcp->output("hpcp").set(hpcp_frame);

        // Wire up Key
        keyAlg->input("pcp").set(hpcp_mean);
        keyAlg->output("key").set(key_str);
        keyAlg->output("scale").set(scale_str);
        keyAlg->output("strength").set(key_strength);

        // Wire up RhythmExtractor (whole-signal)
        rhythmExtractor->input("audio").set(audio_buffer);
        rhythmExtractor->output("bpm").set(bpm);
        rhythmExtractor->output("confidence").set(confidence);
        rhythmExtractor->output("ticks").set(ticks);
        rhythmExtractor->output("estimates").set(estimates);
        rhythmExtractor->output("bpmIntervals").set(bpmIntervals);

        // Wire up ChordsDetection
        chordsDetection->input("pcp").set(hpcp_frames);
        chordsDetection->output("chords").set(chords);
        chordsDetection->output("strength").set(chord_strengths);

        // Wire up TuningFrequency (reuses spectral peaks from frame pipeline)
        tuningAlg->input("frequencies").set(frequencies);
        tuningAlg->input("magnitudes").set(magnitudes);
        tuningAlg->output("tuningFrequency").set(tuning_freq);
        tuningAlg->output("tuningCents").set(tuning_cents);

        // Load audio once
        audio->compute();

        double duration = static_cast<double>(audio_buffer.size()) / 44100.0;

        // Compute tempo on the full signal
        rhythmExtractor->compute();

        // Frame loop: accumulate HPCP for key + chords
        while (true) {
            frameCutter->compute();
            if (frame.empty()) break;
            windowing->compute();
            spectrumAlg->compute();
            spectralPeaks->compute();
            hpcp->compute();
            for (size_t i = 0; i < 12; i++) hpcp_mean[i] += hpcp_frame[i];
            hpcp_frames.push_back(hpcp_frame);
            if (!frequencies.empty()) {
                tuningAlg->compute();
                freq_estimates.push_back(tuning_freq);
                cents_estimates.push_back(tuning_cents);
            }
            frame_count++;
        }

        if (frame_count > 0) {
            for (size_t i = 0; i < 12; i++) hpcp_mean[i] /= frame_count;
        }

        keyAlg->compute();
        chordsDetection->compute();
        free_algorithms(algos);

        // Build key map
        ERL_NIF_TERM key_bin, scale_bin;
        unsigned char* kb = enif_make_new_binary(env, key_str.size(), &key_bin);
        unsigned char* sb = enif_make_new_binary(env, scale_str.size(), &scale_bin);
        memcpy(kb, key_str.c_str(), key_str.size());
        memcpy(sb, scale_str.c_str(), scale_str.size());

        ERL_NIF_TERM key_map_keys[3] = {
            enif_make_atom(env, "key"),
            enif_make_atom(env, "scale"),
            enif_make_atom(env, "strength")
        };
        ERL_NIF_TERM key_map_vals[3] = {key_bin, scale_bin, enif_make_double(env, key_strength)};
        ERL_NIF_TERM key_map;
        enif_make_map_from_arrays(env, key_map_keys, key_map_vals, 3, &key_map);

        // Build tempo map (bpm + beat tick positions in seconds)
        ERL_NIF_TERM tempo_map_keys[2] = {enif_make_atom(env, "bpm"), enif_make_atom(env, "ticks")};
        ERL_NIF_TERM tempo_map_vals[2] = {enif_make_double(env, bpm), real_vec_to_list(env, ticks)};
        ERL_NIF_TERM tempo_map;
        enif_make_map_from_arrays(env, tempo_map_keys, tempo_map_vals, 2, &tempo_map);

        // Build chords list
        ERL_NIF_TERM chords_list = enif_make_list(env, 0);
        ERL_NIF_TERM chord_key_atom    = enif_make_atom(env, "chord");
        ERL_NIF_TERM strength_key_atom = enif_make_atom(env, "strength");
        for (int i = (int)chords.size() - 1; i >= 0; i--) {
            ERL_NIF_TERM chord_bin;
            unsigned char* buf = enif_make_new_binary(env, chords[i].size(), &chord_bin);
            memcpy(buf, chords[i].c_str(), chords[i].size());
            ERL_NIF_TERM cm_keys[2] = {chord_key_atom, strength_key_atom};
            ERL_NIF_TERM cm_vals[2] = {chord_bin, enif_make_double(env, chord_strengths[i])};
            ERL_NIF_TERM entry;
            enif_make_map_from_arrays(env, cm_keys, cm_vals, 2, &entry);
            chords_list = enif_make_list_cell(env, entry, chords_list);
        }

        // Build tuning map (median of per-frame estimates)
        double final_freq = 440.0, final_cents = 0.0;
        if (!freq_estimates.empty()) {
            std::sort(freq_estimates.begin(), freq_estimates.end());
            std::sort(cents_estimates.begin(), cents_estimates.end());
            size_t mid  = freq_estimates.size() / 2;
            final_freq  = freq_estimates[mid];
            final_cents = cents_estimates[mid];
        }
        ERL_NIF_TERM tuning_map_keys[2] = {enif_make_atom(env, "frequency"), enif_make_atom(env, "cents_off")};
        ERL_NIF_TERM tuning_map_vals[2] = {enif_make_double(env, final_freq), enif_make_double(env, final_cents)};
        ERL_NIF_TERM tuning_map;
        enif_make_map_from_arrays(env, tuning_map_keys, tuning_map_vals, 2, &tuning_map);

        // Build result map
        ERL_NIF_TERM result_keys[5] = {
            enif_make_atom(env, "key"),
            enif_make_atom(env, "tempo"),
            enif_make_atom(env, "chords"),
            enif_make_atom(env, "tuning"),
            enif_make_atom(env, "duration")
        };
        ERL_NIF_TERM result_vals[5] = {key_map, tempo_map, chords_list, tuning_map,
                                       enif_make_double(env, duration)};
        ERL_NIF_TERM result;
        enif_make_map_from_arrays(env, result_keys, result_vals, 5, &result);

        return enif_make_tuple2(env, enif_make_atom(env, "ok"), result);
    }
    catch (const std::exception& e) {
        free_algorithms(algos);
        return enif_make_tuple2(env, enif_make_atom(env, "error"),
                               enif_make_string(env, e.what(), ERL_NIF_LATIN1));
    }
}

// NIF function mapping
static ErlNifFunc nif_funcs[] = {
    {"extract_chords",  1, extract_chords,  ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"extract_key",     1, extract_key,     ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"extract_tempo",   1, extract_tempo,   ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"extract_tuning",  1, extract_tuning,  ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"get_duration",    1, get_duration,    ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"analyze_audio",   1, analyze_audio,   ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"analyze_all",     1, analyze_all,     ERL_NIF_DIRTY_JOB_CPU_BOUND}
};

ERL_NIF_INIT(Elixir.Essentia, nif_funcs, load, NULL, NULL, unload)
