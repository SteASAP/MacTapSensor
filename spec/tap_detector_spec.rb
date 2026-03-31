# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MacMoan::TapDetector do
  let(:config) do
    MacMoan::Configuration.new(
      threshold: 0.30,
      cooldown: 0.30,
      settle: 0.45,
      rearm_delta: 0.08,
      baseline_window: 10,
      escalate_window: 2.5,
      decay_window: 4.0,
      reset_window: 8.0,
      max_zone: 5
    )
  end

  let(:time_now) { [0.0] }
  let(:clock) { -> { time_now[0] } }
  let(:detector) { described_class.new(config, clock: clock) }

  def sample(x = 0.0, y = 0.0, z = -1.0)
    MacMoan::Sample.new(x, y, z)
  end

  def fill_baseline(n = 10)
    n.times { detector.process(sample) }
  end

  def advance_time(seconds)
    time_now[0] += seconds
  end

  describe 'baseline filling' do
    it 'returns nil while baseline is being filled' do
      (config.baseline_window - 1).times do
        expect(detector.process(sample)).to be_nil
      end
    end

    it 'starts detecting after baseline is full' do
      fill_baseline
      # A normal sample should return nil (no spike)
      expect(detector.process(sample)).to be_nil
    end
  end

  describe 'spike detection' do
    before { fill_baseline }

    it 'detects a spike above threshold' do
      advance_time(1.0)
      event = detector.process(sample(0.3, 0.3, -1.5))
      expect(event).to be_a(MacMoan::TapEvent)
      expect(event.delta).to be > config.threshold
    end

    it 'ignores small deviations below threshold' do
      advance_time(1.0)
      event = detector.process(sample(0.01, 0.01, -1.01))
      expect(event).to be_nil
    end

    it 'includes correct zone in event' do
      advance_time(1.0)
      event = detector.process(sample(0.5, 0.5, -1.5))
      expect(event.zone).to eq(1)
    end

    it 'includes sample data in event' do
      advance_time(1.0)
      s = sample(0.5, 0.5, -1.5)
      event = detector.process(s)
      expect(event.sample).to eq(s)
    end
  end

  describe 'cooldown and re-arm' do
    before { fill_baseline }

    it 'blocks during settle window' do
      advance_time(1.0)
      first = detector.process(sample(0.5, 0.5, -1.5))
      expect(first).not_to be_nil

      # Still within settle window
      advance_time(0.1)
      second = detector.process(sample(0.5, 0.5, -1.5))
      expect(second).to be_nil
    end

    it 'requires re-arm before next trigger' do
      advance_time(1.0)
      detector.process(sample(0.5, 0.5, -1.5))

      # Past settle window but not re-armed (still high delta)
      advance_time(config.settle + 0.01)
      result = detector.process(sample(0.5, 0.5, -1.5))
      expect(result).to be_nil
    end

    it 're-arms after calm reading past settle window' do
      advance_time(1.0)
      detector.process(sample(0.5, 0.5, -1.5))

      # Wait past settle
      advance_time(config.settle + 0.01)
      # Calm sample to re-arm
      detector.process(sample(0.0, 0.0, -1.0))

      # Now another spike should trigger
      advance_time(config.cooldown + 0.01)
      event = detector.process(sample(0.5, 0.5, -1.5))
      expect(event).to be_a(MacMoan::TapEvent)
    end
  end

  describe 'zone escalation' do
    before { fill_baseline }

    def trigger_and_rearm(gap:)
      advance_time(gap > config.settle ? gap : config.settle + 0.01)
      # Re-arm with calm sample
      detector.process(sample)
      advance_time(0.01)
      detector.process(sample(0.5, 0.5, -1.5))
    end

    it 'escalates zone on rapid taps' do
      advance_time(1.0)
      e1 = detector.process(sample(0.5, 0.5, -1.5))
      expect(e1.zone).to eq(1)

      e2 = trigger_and_rearm(gap: config.escalate_window - 0.1)
      expect(e2.zone).to eq(2)

      e3 = trigger_and_rearm(gap: config.escalate_window - 0.1)
      expect(e3.zone).to eq(3)
    end

    it 'resets zone after long idle' do
      advance_time(1.0)
      detector.process(sample(0.5, 0.5, -1.5))

      # Escalate
      trigger_and_rearm(gap: config.escalate_window - 0.1)

      # Long pause → reset
      e = trigger_and_rearm(gap: config.reset_window + 1.0)
      expect(e.zone).to eq(1)
    end

    it 'caps zone at max_zone' do
      advance_time(1.0)
      detector.process(sample(0.5, 0.5, -1.5))

      (config.max_zone + 2).times do
        e = trigger_and_rearm(gap: config.escalate_window - 0.1)
        expect(e.zone).to be <= config.max_zone
      end
    end
  end

  describe 'baseline learning' do
    before { fill_baseline }

    it 'does not update baseline during spike' do
      advance_time(1.0)
      # Spike - should NOT be added to baseline
      detector.process(sample(0.5, 0.5, -1.5))

      # Wait, re-arm
      advance_time(config.settle + 0.01)
      detector.process(sample(0.0, 0.0, -1.0))

      # Baseline should still be close to 1.0 (not polluted by spike)
      advance_time(config.cooldown + 0.01)
      event = detector.process(sample(0.5, 0.5, -1.5))
      expect(event).not_to be_nil
      expect(event.baseline).to be_within(0.1).of(1.0)
    end
  end
end
