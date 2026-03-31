# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe MacMoan::SoundPlayer do
  let(:tmpdir) { Dir.mktmpdir('macmoan_test') }
  let(:config) do
    MacMoan::Configuration.new(
      sound_dir: tmpdir,
      zone_map: { 1 => %w[a.wav b.wav], 2 => %w[c.wav] }
    )
  end

  after { FileUtils.rm_rf(tmpdir) }

  def create_sound(name)
    path = File.join(tmpdir, name)
    File.write(path, 'fake audio data')
    path
  end

  describe '#play_for_zone' do
    it 'does nothing for unknown zone' do
      player = described_class.new(config)
      expect { player.play_for_zone(99) }.not_to raise_error
    end

    it 'does nothing when no matching files exist' do
      player = described_class.new(config)
      expect { player.play_for_zone(1) }.not_to raise_error
    end

    it 'selects from correct zone files' do
      create_sound('a.wav')
      create_sound('b.wav')

      player = described_class.new(config)

      # Stub Process.spawn to capture what would be played
      played = []
      allow(Process).to receive(:spawn) do |*args|
        played << args[1] # second arg is the file path
        0 # fake PID
      end

      10.times { player.play_for_zone(1) }

      played.each do |path|
        basename = File.basename(path)
        expect(%w[a.wav b.wav]).to include(basename)
      end
    end

    it 'rejects files with disallowed extensions' do
      create_sound('evil.sh')
      config_with_evil = MacMoan::Configuration.new(
        sound_dir: tmpdir,
        zone_map: { 1 => %w[evil.sh] }
      )
      player = described_class.new(config_with_evil)

      allow(Process).to receive(:spawn)
      player.play_for_zone(1)
      expect(Process).not_to have_received(:spawn)
    end
  end
end
