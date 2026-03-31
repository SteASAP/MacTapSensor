# frozen_string_literal: true

require 'thread'

module MacMoan
  class SensorNotFound < RuntimeError; end
  class PermissionError < RuntimeError; end

  # Bridge to the Apple Silicon SPU IMU via a native C helper process.
  #
  # The helper binary (sensor_helper) uses IOKit's HID Event System
  # private API with GCD dispatch queues to read the Bosch BMI286 IMU.
  # It outputs "x,y,z" lines at ~100Hz on stdout, which this bridge
  # reads via a pipe.
  #
  # A native helper is required because GCD dispatch queue callbacks
  # cannot safely invoke Ruby code through Fiddle.
  #
  # Requires root privileges (sudo) to open the HID event system client.
  class IOKitBridge
    HELPER_PATH = File.expand_path('sensor_helper', __dir__).freeze

    def initialize(decimation: 1)
      @decimation = decimation
      @samples = Thread::Queue.new
      @running = false
      @worker = nil
      @dec_counter = 0
    end

    def self.available?
      File.executable?(HELPER_PATH)
    end

    def start
      raise 'Already running' if @running

      unless Process.euid.zero?
        raise PermissionError, 'Requires root privileges (sudo)'
      end

      unless File.executable?(HELPER_PATH)
        raise SensorNotFound,
          "Sensor helper not found at #{HELPER_PATH}. " \
          "Run: cc -O2 -o #{HELPER_PATH} #{HELPER_PATH}.c " \
          "-framework CoreFoundation -framework IOKit"
      end

      @running = true
      @worker = Thread.new { run_worker }
    end

    def read_samples
      result = []
      loop { result << @samples.pop(true) }
    rescue ThreadError
      result
    end

    def stop
      return unless @running

      @running = false

      if @helper_pid
        begin
          Process.kill('TERM', @helper_pid)
          Process.waitpid(@helper_pid)
        rescue Errno::ESRCH, Errno::ECHILD
          # already gone
        end
        @helper_pid = nil
      end

      @worker&.join(3)
      @worker = nil
    end

    private

    def run_worker
      rd, wr = IO.pipe
      err_rd, err_wr = IO.pipe

      @helper_pid = Process.spawn(HELPER_PATH, out: wr, err: err_wr)
      wr.close
      err_wr.close

      # Wait for READY signal from helper (up to 3 seconds)
      ready = false
      3.times do
        if IO.select([err_rd], nil, nil, 1)
          line = err_rd.gets
          if line&.strip == 'READY'
            ready = true
            break
          end
        end
      end

      unless ready
        warn '[MacMoan] Sensor helper did not signal ready'
        begin
          while (line = err_rd.read_nonblock(4096))
            warn "[MacMoan] helper: #{line}"
          end
        rescue IO::WaitReadable, EOFError
          # ok
        end
      end

      # Drain helper stderr in background
      Thread.new do
        while (line = err_rd.gets)
          warn "[MacMoan] helper: #{line.strip}" unless line.strip.empty?
        end
      rescue IOError
        # pipe closed
      end

      # Read CSV lines from helper stdout
      while @running
        line = rd.gets
        break unless line

        parts = line.strip.split(',')
        next unless parts.length == 3

        @dec_counter += 1
        next if @dec_counter < @decimation

        @dec_counter = 0

        x, y, z = parts.map(&:to_f)
        @samples.push(Sample.new(x, y, z))
      end
    rescue StandardError => e
      warn "[MacMoan] Sensor worker error: #{e.message}"
      warn e.backtrace.first(5).join("\n")
    ensure
      rd&.close
      err_rd&.close
    end
  end
end
