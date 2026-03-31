# frozen_string_literal: true

module MacMoan
  TapEvent = Struct.new(:time, :magnitude, :baseline, :delta, :sample, :zone, :idle_gap, keyword_init: true)
end
