# frozen_string_literal: true

require 'pathname'

module MacMoan
  class Configuration
    ALLOWED_EXTENSIONS = %w[.wav .mp3 .aiff .m4a].freeze

    DEFAULTS = {
      sample_rate: 100,
      cooldown: 0.30,
      settle: 0.45,
      threshold: 0.15,
      rearm_delta: 0.05,
      baseline_window: 80,
      escalate_window: 2.5,
      decay_window: 4.0,
      reset_window: 8.0,
      max_zone: 5,
      sound_dir: 'sounds/moan',
      zone_map: nil, # auto-generated from sound_dir if nil
    }.freeze

    attr_accessor :sample_rate, :cooldown, :settle, :threshold,
                  :rearm_delta, :baseline_window,
                  :escalate_window, :decay_window, :reset_window,
                  :max_zone, :sound_dir, :zone_map

    def initialize(**overrides)
      DEFAULTS.merge(overrides).each do |key, value|
        raise ArgumentError, "Unknown config key: #{key}" unless DEFAULTS.key?(key)

        public_send(:"#{key}=", value)
      end

      self.zone_map ||= build_zone_map
    end

    # Rebuild zone_map from the current sound_dir. Call this after
    # changing sound_dir post-initialization.
    def rebuild_zone_map!
      self.zone_map = build_zone_map
    end

    private

    # Scans the sound directory for audio files and distributes
    # them evenly across zones 1..max_zone.
    def build_zone_map
      dir = Pathname.new(sound_dir).expand_path
      return {} unless dir.directory?

      files = dir.children
        .select { |f| f.file? && ALLOWED_EXTENSIONS.include?(f.extname.downcase) }
        .map(&:basename)
        .map(&:to_s)
        .sort

      return {} if files.empty?

      map = {}
      (1..max_zone).each { |z| map[z] = [] }

      files.each_with_index do |f, i|
        zone = (i % max_zone) + 1
        map[zone] << f
      end

      map
    end
  end
end
