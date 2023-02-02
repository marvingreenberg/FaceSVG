# frozen_string_literal: true

require 'minitest/mock'

require 'facesvg/svg/vector_n'
require 'facesvg/svg/util'
require 'facesvg/svg/svg_arc'

def xy(*args); FaceSVG::SVG.vector_2d(*args); end

module FaceSVG
  extend self

  def dbg(fmt, *args)
    puts format(fmt, *args)
  end
end

class TestFaceSVG < Test::Unit::TestCase
  def test_vector_2d
    v = ::FaceSVG::SVG.vector_2d(1, 2)
    assert_equal(1, v.x)
    assert_equal(2, v.y)
  end

  def test_vector_n
    v1 = ::FaceSVG::SVG::VectorN.new([1, 2])
    v2 = ::FaceSVG::SVG::VectorN.new([2, 3])
    assert_equal([3, 5], (v1 + v2).to_a)
    assert_equal([5, 9], ((v1 * 3) + v2).to_a)
    assert_equal(8, v1.dot(v2))
    assert_equal(5**0.5, v1.abs)
  end

  def test_su_bug
    assert_equal(Math::PI, ::FaceSVG::SVG.su_bug(3*Math::PI))
  end

  def test_SVGArc
    centerxy = xy([0.0, 0.0])
    radius = 2.0
    startxy = xy([2.0, 0.0])
    endxy = xy([2.0, 0.0])
    start_angle = 0.0
    end_angle = 2 * Math::PI
    xaxis2d = xy([1.0, 0.0])
    yaxis2d = xy([0.0, 1.0])
    arc = ::FaceSVG::SVG::SVGArc.new(
      centerxy, radius, startxy, endxy, start_angle, end_angle, xaxis2d, yaxis2d)

    assert_equal(2, arc.instance_variable_get(:@radius))
    assert_equal([0.0, 0.0], arc.instance_variable_get(:@centerxy).to_a)
    assert_equal([2.0, 0.0], arc.instance_variable_get(:@startxy).to_a)
    assert_equal([2.0, 0.0], arc.instance_variable_get(:@endxy).to_a)
    assert_equal(0, arc.instance_variable_get(:@start_angle))
    assert_equal(2*Math::PI, arc.instance_variable_get(:@end_angle))
    assert_equal([1, 0], arc.instance_variable_get(:@xaxis2d).to_a)
    assert_equal([0, 1], arc.instance_variable_get(:@yaxis2d).to_a)
  end
end
