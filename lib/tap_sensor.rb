# frozen_string_literal: true

require_relative 'tap_sensor/sample'
require_relative 'tap_sensor/tap_event'
require_relative 'tap_sensor/configuration'
require_relative 'tap_sensor/iokit_bridge'
require_relative 'tap_sensor/motion_reader'
require_relative 'tap_sensor/tap_detector'
require_relative 'tap_sensor/sound_player'
require_relative 'tap_sensor/app'

module MacMoan
  VERSION = '1.0.0'
end
