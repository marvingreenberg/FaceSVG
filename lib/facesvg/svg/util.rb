# frozen_string_literal: true

require('facesvg/svg/vector_n')
require('facesvg/constants')

module FaceSVG
  module SVG
    extend self

    def same(num0, num1)
      (num0-num1).abs < TOLERANCE
    end

    # Sketchup, documented bug
    # http://ruby.sketchup.com/Sketchup/ArcCurve.html#end_angle-instance_method
    def su_bug(end_angle)
      end_angle -= (2 * Math::PI) if end_angle > (2 * Math::PI)
      end_angle
    end
  end
end
