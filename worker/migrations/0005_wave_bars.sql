-- Random waveform bars (JSON array of ints 1–20), set at upload
ALTER TABLE voice_messages ADD COLUMN wave_bars TEXT;
