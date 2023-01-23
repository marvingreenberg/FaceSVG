# frozen_string_literal: true

require 'test/unit'
require 'mocha/test_unit'

class TestFaceSVG < Test::Unit::TestCase
  def test_V2d
    v = FaceSVG::SVG::V2d(1, 2)
    assert_equal(1, v.x)
    assert_equal(2, v.y)
  end

  def test_Vn
    v1 = FaceSVG::SVG::Vn.new([1, 2])
    v2 = FaceSVG::SVG::Vn.new([2, 3])
    assert_equal(5, (v1 + v2).reduce(:+))
    assert_equal([3, 5], ((v1 * 3) + v2).to_a)
    assert_equal((1*2) + (2*3), v1.dot(v2))
    assert_equal(5**0.5, v1.abs)
  end

  def test_su_bug
    assert_equal(Math::PI, FaceSVG::SVG.su_bug(3*Math::PI))
  end

  def test_SVGArc
    edge1 = mock()
    edge2 = mock()
    curve = mock(radius: 2, start_angle: 0, end_angle: Math::PI, xaxis: [1, 0, 0], yaxis: [0, 1, 0])
    arcpathpart = mock(crv: curve, center: [1, 1, 0], startpos: [3, 4, 0], endpos: [5, 6, 0], edges: [edge1, edge2])
    arc = FaceSVG::SVG::SVGArc.new(arcpathpart)
    assert_equal(2, arc.instance_variable_get(:@radius))
    assert_equal([1, 1], arc.instance_variable_get(:@centerxy).to_a)
    assert_equal([3, 4], arc.instance_variable_get(:@startxy).to_a)
    assert_equal([5, 6], arc.instance_variable_get(:@endxy).to_a)
    assert_equal(0, arc.instance_variable_get(:@start_angle))
    assert_equal(Math::PI, arc.instance_variable_get(:@end_angle))
    assert_equal([1, 0], arc.instance_variable_get(:@xaxis2d).to_a)
    assert_equal([0, 1], arc.instance_variable_get(:@yaxis2d).to_a)
  end
end
