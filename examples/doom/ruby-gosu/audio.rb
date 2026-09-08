# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Implements the wasm module's thirteen `audio` imports on gosu.
#
# Doom hands over sample data once per sound (`registerSound`) and then names
# it by id, so nothing here needs to know how a WAD is laid out. Music arrives
# as standard MIDI: the module converts Doom's own MUS encoding before calling
# `registerSong`.
#
# gosu loads samples and songs from files rather than from memory, so each
# registration is written to a temporary file first, which is also what Doom's
# own SDL backend does with music.
# The module's memory, as seen from an import that runs after construction.
#
# Doom hands over sample data by address, so the audio host reads the same
# memory the other imports do; like them it is built before `Doom.new`
# returns the instance it reads from.
class DeferredMemory
  def initialize(doom_holder) = @doom_holder = doom_holder

  def get_string(offset, length) = @doom_holder[0].memory.buffer.get_string(offset, length)
end

class DoomAudio
  # Doom's `sep` runs 0 (hard left) to 254 (hard right); 127 is centred.
  # Its volumes run 0 to 127.
  SEPARATION_CENTRE = 127.0
  MAX_VOLUME = 127.0

  # A DMX sound lump is an 8-byte header followed by unsigned 8-bit mono
  # samples, of which DMX ignores 16 at each end.
  DMX_FORMAT = 3
  DMX_HEADER_BYTES = 8
  DMX_PAD_SAMPLES = 16

  def initialize(memory)
    @memory = memory
    @samples = {}
    @channels = {}
    @songs = {}
    @playing = nil
    @music_volume = 1.0
    @dir = Dir.mktmpdir("dewasm-doom-audio")
    at_exit { FileUtils.remove_entry(@dir) if File.directory?(@dir) }
  end

  # The import table to hand to the generated module.
  def imports
    {
      "registerSound" => method(:register_sound),
      "startSound" => method(:start_sound),
      "stopSound" => method(:stop_sound),
      "updateSoundParams" => method(:update_sound_params),
      "soundIsPlaying" => method(:sound_is_playing),
      "registerSong" => method(:register_song),
      "unregisterSong" => method(:unregister_song),
      "playSong" => method(:play_song),
      "stopSong" => method(:stop_song),
      "pauseSong" => method(:pause_song),
      "resumeSong" => method(:resume_song),
      "setMusicVolume" => method(:set_music_volume),
      "songIsPlaying" => method(:song_is_playing),
    }
  end

  private

  def register_sound(sfx_id, ptr, length)
    wav = wav_from_dmx(@memory.get_string(ptr, length))
    return if wav.nil?

    path = File.join(@dir, "sfx#{sfx_id}.wav")
    File.binwrite(path, wav)
    @samples[sfx_id] = Gosu::Sample.new(path)
  rescue StandardError => e
    # A sound that will not load is not worth ending the game over; Doom
    # carries on silently for it and keeps asking for the others.
    warn "audio: sfx #{sfx_id} not registered (#{e.class}: #{e.message})"
  end

  # Wrap a DMX lump's samples in a WAV container, dropping the pad DMX skips.
  # Returns nil for anything that is not a valid DMX sound, matching the
  # checks in Doom's own `CacheSFX`.
  def wav_from_dmx(lump)
    return nil if lump.bytesize < DMX_HEADER_BYTES

    format, rate, count = lump.unpack("vvV")
    return nil unless format == DMX_FORMAT
    return nil if count > lump.bytesize - DMX_HEADER_BYTES || count <= 48

    pcm = lump.byteslice(DMX_HEADER_BYTES + DMX_PAD_SAMPLES, count - 2 * DMX_PAD_SAMPLES)
    return nil if pcm.nil? || pcm.empty?

    # Canonical 44-byte WAV header: PCM, mono, 8 bits per sample.
    +"RIFF" << [36 + pcm.bytesize].pack("V") << "WAVEfmt " <<
      [16, 1, 1, rate, rate, 1, 8].pack("VvvVVvv") <<
      "data" << [pcm.bytesize].pack("V") << pcm
  end

  def start_sound(sfx_id, channel, volume, separation)
    sample = @samples[sfx_id]
    return if sample.nil?

    stop_sound(channel)
    @channels[channel] = sample.play_pan(pan_of(separation), volume_of(volume), 1.0, false)
  end

  def stop_sound(channel)
    @channels.delete(channel)&.stop
  end

  def update_sound_params(channel, volume, separation)
    playing = @channels[channel]
    return if playing.nil?

    playing.volume = volume_of(volume)
    playing.pan = pan_of(separation)
  end

  def sound_is_playing(channel)
    @channels[channel]&.playing? ? 1 : 0
  end

  def pan_of(separation) = ((separation - SEPARATION_CENTRE) / SEPARATION_CENTRE).clamp(-1.0, 1.0)

  def volume_of(volume) = (volume / MAX_VOLUME).clamp(0.0, 1.0)

  def register_song(ptr, length)
    handle = @songs.size + 1
    path = File.join(@dir, "song#{handle}.mid")
    File.binwrite(path, @memory.get_string(ptr, length))
    @songs[handle] = Gosu::Song.new(path)
    handle
  rescue StandardError => e
    warn "audio: music not registered (#{e.class}: #{e.message})"
    # 0 tells Doom the music could not be registered; it then plays none.
    0
  end

  def unregister_song(handle)
    song = @songs.delete(handle)
    return if song.nil?

    song.stop if @playing.equal?(song)
    @playing = nil if @playing.equal?(song)
  end

  def play_song(handle, looping)
    song = @songs[handle]
    return if song.nil?

    song.volume = @music_volume
    song.play(looping != 0)
    @playing = song
  end

  def stop_song
    @playing&.stop
    @playing = nil
  end

  def pause_song = @playing&.pause

  # Gosu documents `Song#play` as "Starts or resumes playback of the song",
  # so playing the paused song is how it is un-paused. Doom pauses for the
  # menu and resumes on dismissing it.
  def resume_song = @playing&.play(true)

  def set_music_volume(volume)
    @music_volume = volume_of(volume)
    @playing&.volume = @music_volume
  end

  def song_is_playing = @playing&.playing? ? 1 : 0
end
