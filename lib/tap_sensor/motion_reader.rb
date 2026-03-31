# frozen_string_literal: true

module MacMoan
  # High-level wrapper around IOKitBridge.
  # Translates sample_rate into decimation factor and provides
  # a clean interface for starting/stopping sensor reads.
  class MotionReader
    NATIVE_RATE_HZ = 100

    def initialize(config)
      decimation = [1, (NATIVE_RATE_HZ.to_f / config.sample_rate).round].max
      @bridge = IOKitBridge.new(decimation: decimation)
    end

    def self.available?
      IOKitBridge.available?
    end

    def start
      @bridge.start
    end

    def read_samples
      @bridge.read_samples
    end

    def stop
      @bridge.stop
    end
  end
end
