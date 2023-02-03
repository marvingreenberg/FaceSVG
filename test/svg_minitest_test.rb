# frozen_string_literal: true

require 'minitest/mock'
require 'ostruct'
require 'facesvg/svg/vector_n'
require 'facesvg/svg/util'

require 'minitest/autorun'

describe FaceSVG::SVG::VectorN do
  it 'vector operations' do
    v1 = FaceSVG::SVG::VectorN.new([1, 2])
    v2 = FaceSVG::SVG::VectorN.new([2, 3])
    _(v1 + v2).must_equal([3, 5])
    _((v1 * 3) + v2).must_equal([5, 9])
    _(v1.dot(v2)).must_equal(8)
    _(v1.abs).must_equal(5**0.5)
  end

  it 'handles SU 2017 bug' do
    _(FaceSVG::SVG.su_bug(3*Math::PI)).must_equal(Math::PI)
  end
end

# empty = OpenStruct.new
# (h.methods - Object.methods - empty.methods).filter { |m| !m.to_s.end_with?('=') }
