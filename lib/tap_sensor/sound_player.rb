# frozen_string_literal: true

require 'pathname'

module MacMoan
  # Plays sound files using macOS afplay.
  #
  # Selects a random file from the configured zone map, validates
  # the path stays within the sound directory (no traversal), and
  # spawns a non-blocking afplay process. Reaps finished child
  # processes to avoid zombies.
  class SoundPlayer
    AFPLAY = '/usr/bin/afplay'
    ALLOWED_EXTENSIONS = %w[.wav .mp3 .aiff .m4a].freeze

    def initialize(config)
      @config = config
      @sound_dir = Pathname.new(config.sound_dir).expand_path
      @last_sound = nil
      @child_pids = []
      validate_setup
    end

    def play_for_zone(zone)
      reap_children

      filenames = @config.zone_map[zone]
      return unless filenames

      files = filenames
        .map { |f| @sound_dir.join(f) }
        .select { |f| f.file? && ALLOWED_EXTENSIONS.include?(f.extname.downcase) }

      return if files.empty?

      # Avoid repeating the last sound
      choices = files.length > 1 ? files.reject { |f| f == @last_sound } : files
      sound = choices.sample
      @last_sound = sound
      play(sound)
    end

    private

    def play(path)
      resolved = path.realpath

      unless resolved.to_s.start_with?(@sound_dir.realpath.to_s + '/')
        warn "[MacMoan] Path traversal blocked: #{path}"
        return
      end

      puts "[AUDIO] Playing: #{resolved.basename}"
      spawn_opts = { out: File::NULL, err: File::NULL }

      # When running under sudo, drop back to the invoking user so
      # afplay can access the user's audio session.
      sudo_uid = ENV['SUDO_UID']
      sudo_gid = ENV['SUDO_GID']
      if sudo_uid && sudo_gid
        spawn_opts[:uid] = sudo_uid.to_i
        spawn_opts[:gid] = sudo_gid.to_i
      end

      pid = Process.spawn(AFPLAY, resolved.to_s, **spawn_opts)
      @child_pids << pid
    end

    def reap_children
      @child_pids.reject! do |pid|
        _pid, _status = Process.waitpid2(pid, Process::WNOHANG)
        !_pid.nil?
      rescue Errno::ECHILD
        true
      end
    end

    def validate_setup
      raise "afplay not found at #{AFPLAY}" unless File.executable?(AFPLAY)

      return if @sound_dir.directory?

      warn "[MacMoan] Sound directory not found: #{@sound_dir}"
    end
  end
end
