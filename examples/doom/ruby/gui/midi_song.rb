# frozen_string_literal: true

# Plays one MIDI file through SDL2_mixer, with the interface `Gosu::Song` has.
#
# gosu decodes audio with SDL_sound, whose decoders are WAV, AIFF, VOC, AU,
# FLAC, MP3, Ogg Vorbis, Shorten and tracker modules: no MIDI. So a released
# gosu rejects the songs Doom registers as an unsupported format, whatever
# synthesiser the machine has, and no setting changes that.
#
# SDL2_mixer, which Doom's own SDL backend uses for these same files,
# synthesises MIDI through fluidsynth or timidity. Music goes there when gosu
# will not take it; the effects are PCM and stay with gosu.
#
# Both libraries then hold an output device at once, which is a normal thing to
# ask of a platform's audio server and what Doom asks of it too.
class MidiSong
  # SDL2_mixer names one music stream, not one per song, so which song owns it
  # is this class's to track. It is the same rule `Gosu::Song` states: playing
  # a song stops the song that was playing.
  @current = nil
  @device = nil

  SDL_INIT_AUDIO = 0x0000_0010
  AUDIO_S16SYS = 0x8010
  FREQUENCY = 44_100
  OUTPUT_CHANNELS = 2
  CHUNK_SAMPLES = 2048
  MAX_VOLUME = 128

  # Binding failure is a state, not an error: the frontend runs without music.
  BINDING_ERROR = begin
    require "ffi"

    module Mixer
      extend FFI::Library
      ffi_lib %w[SDL2_mixer libSDL2_mixer-2.0.so.0 libSDL2_mixer-2.0.0.dylib]
      attach_function :Mix_OpenAudio, %i[int uint16 int int], :int
      attach_function :Mix_CloseAudio, [], :void
      attach_function :Mix_LoadMUS, [:string], :pointer
      attach_function :Mix_FreeMusic, [:pointer], :void
      attach_function :Mix_PlayMusic, %i[pointer int], :int
      attach_function :Mix_HaltMusic, [], :int
      attach_function :Mix_PauseMusic, [], :void
      attach_function :Mix_ResumeMusic, [], :void
      attach_function :Mix_PausedMusic, [], :int
      attach_function :Mix_PlayingMusic, [], :int
      attach_function :Mix_VolumeMusic, [:int], :int
    end

    # `Mix_GetError` is a macro for SDL's own, so the message comes from SDL2.
    # gosu links an SDL of its own, so the audio subsystem this one uses is
    # ours to start.
    module Sdl
      extend FFI::Library
      ffi_lib %w[SDL2 libSDL2-2.0.so.0 libSDL2-2.0.0.dylib]
      attach_function :SDL_InitSubSystem, [:uint32], :int
      attach_function :SDL_GetError, [], :string
    end

    nil
  # FFI::NotFoundError, raised for a missing symbol, is itself a LoadError.
  rescue LoadError => e
    "SDL2_mixer is not usable through ffi (#{e.class}: #{e.message})"
  end

  class << self
    attr_accessor :current

    def available? = BINDING_ERROR.nil?

    # Opened on the first song rather than at startup, so a frontend whose
    # gosu plays MIDI never opens a second device.
    def device
      return @device if @device

      raise BINDING_ERROR unless available?

      if Sdl.SDL_InitSubSystem(SDL_INIT_AUDIO) != 0
        raise "SDL_InitSubSystem failed: #{Sdl.SDL_GetError}"
      end

      if Mixer.Mix_OpenAudio(FREQUENCY, AUDIO_S16SYS, OUTPUT_CHANNELS, CHUNK_SAMPLES) != 0
        raise "Mix_OpenAudio failed: #{Sdl.SDL_GetError}"
      end

      # SDL2_mixer mixes on a thread of its own, which must stop before the
      # interpreter unloads the library out from under it.
      at_exit { close_device }
      @device = :open
    end

    def close_device
      return unless @device

      @device = nil
      @current = nil
      Mixer.Mix_HaltMusic
      Mixer.Mix_CloseAudio
    end
  end

  def initialize(path)
    self.class.device
    @music = Mixer.Mix_LoadMUS(path)
    raise "Mix_LoadMUS(#{path}) failed: #{Sdl.SDL_GetError}" if @music.null?

    @volume = 1.0
  end

  def volume=(value)
    @volume = value.clamp(0.0, 1.0)
    Mixer.Mix_VolumeMusic((@volume * MAX_VOLUME).round) if current?
  end

  attr_reader :volume

  # Gosu documents this as "Starts or resumes playback of the song".
  def play(looping = false)
    Mixer.Mix_VolumeMusic((@volume * MAX_VOLUME).round)
    return Mixer.Mix_ResumeMusic if paused?

    Mixer.Mix_PlayMusic(@music, looping ? -1 : 1)
    self.class.current = self
  end

  def pause
    Mixer.Mix_PauseMusic if playing?
  end

  def paused? = current? && Mixer.Mix_PausedMusic == 1

  def playing? = current? && Mixer.Mix_PlayingMusic == 1 && Mixer.Mix_PausedMusic.zero?

  def stop
    return unless current?

    Mixer.Mix_HaltMusic
    self.class.current = nil
  end

  # `Gosu::Song` frees its music when it is collected; SDL2_mixer's has to be
  # told, and Doom says when by unregistering the song.
  def close
    return if @music.nil?

    stop
    Mixer.Mix_FreeMusic(@music)
    @music = nil
  end

  private

  def current? = self.class.current.equal?(self)
end
