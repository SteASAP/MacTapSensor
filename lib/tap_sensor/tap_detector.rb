# frozen_string_literal: true

module MacMoan
  # Detects physical taps using rolling baseline comparison.
  #
  # Maintains a window of "calm" magnitude readings as a baseline.
  # When the current magnitude deviates beyond a threshold, a tap
  # is registered. Includes settle/re-arm logic to prevent false
  # triggers from post-impact vibration, and zone-based escalation
  # for rapid successive taps.
  class TapDetector
    # Accept an injectable clock proc for testability.
    def initialize(config, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @config = config
      @clock = clock
      @baseline_history = []
      @armed = true
      @blocked_until = 0.0
      @last_trigger = 0.0
      @last_tap_time = 0.0
      @current_zone = 1
    end

    # Process a single Sample. Returns a TapEvent if a tap is detected, nil otherwise.
    def process(sample)
      mag = magnitude(sample)

      # Fill baseline buffer before detecting
      if @baseline_history.length < @config.baseline_window
        @baseline_history.push(mag)
        return nil
      end

      baseline = @baseline_history.sum / @baseline_history.length
      delta = (mag - baseline).abs
      now = @clock.call

      # Ignore everything during settle window after a hit
      return nil if now < @blocked_until

      # Re-arm only when motion has calmed down
      unless @armed
        @armed = true if delta < @config.rearm_delta
        return nil
      end

      # Spike detection
      if delta > @config.threshold && (now - @last_trigger) > @config.cooldown
        idle_gap = @last_tap_time.positive? ? (now - @last_tap_time) : 9999.0
        zone = compute_zone(idle_gap)

        @last_trigger = now
        @last_tap_time = now
        @blocked_until = now + @config.settle
        @armed = false

        return TapEvent.new(
          time: now,
          magnitude: mag,
          baseline: baseline,
          delta: delta,
          sample: sample,
          zone: zone,
          idle_gap: idle_gap
        )
      end

      # Only learn from calm samples to avoid corrupting the baseline
      if delta < @config.rearm_delta
        @baseline_history.push(mag)
        @baseline_history.shift if @baseline_history.length > @config.baseline_window
      end

      nil
    end

    private

    def magnitude(sample)
      Math.sqrt(sample.x**2 + sample.y**2 + sample.z**2)
    end

    def compute_zone(idle_gap)
      if idle_gap > @config.reset_window
        @current_zone = 1
      elsif idle_gap > @config.decay_window
        @current_zone = [@current_zone - 1, 1].max
      elsif idle_gap <= @config.escalate_window
        @current_zone = [@current_zone + 1, @config.max_zone].min
      end

      @current_zone
    end
  end
end
