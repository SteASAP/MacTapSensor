# frozen_string_literal: true

module MacMoan
  # Main application loop. Wires together MotionReader, TapDetector,
  # and SoundPlayer. Handles signal trapping for clean shutdown.
  class App
    def initialize(config = Configuration.new)
      @config = config
      @reader = MotionReader.new(config)
      @detector = TapDetector.new(config)
      @player = SoundPlayer.new(config)
      @running = false
    end

    def run
      print_banner
      @reader.start
      @running = true

      trap('INT')  { @running = false }
      trap('TERM') { @running = false }

      loop do
        break unless @running

        samples = @reader.read_samples

        if samples.empty?
          sleep(0.005)
          next
        end

        samples.each do |sample|
          event = @detector.process(sample)
          next unless event

          log_tap(event)
          @player.play_for_zone(event.zone)
        end

        sleep(0.005)
      end
    ensure
      @reader.stop
      puts "\nStopped."
    end

    private

    def print_banner
      puts 'macMoan - tap-reactive sound engine for Apple Silicon'
      puts "  threshold:  #{@config.threshold}"
      puts "  cooldown:   #{@config.cooldown}s"
      puts "  settle:     #{@config.settle}s"
      puts "  rearm:      #{@config.rearm_delta}"
      puts "  sound_dir:  #{@config.sound_dir}"
      puts "  max_zone:   #{@config.max_zone}"
      puts 'Press Ctrl+C to stop.'
      puts
    end

    def log_tap(event)
      time_str = Time.now.strftime('%H:%M:%S')
      printf(
        "[TAP] time=%s delta=%.4f zone=%d idle=%.2fs xyz=(%.4f, %.4f, %.4f)\n",
        time_str, event.delta, event.zone, event.idle_gap,
        event.sample.x, event.sample.y, event.sample.z
      )
    end
  end
end
