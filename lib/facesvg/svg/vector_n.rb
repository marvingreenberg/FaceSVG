# frozen_string_literal: true

require('facesvg/svg/util')

module FaceSVG
  module SVG
    extend self

    def vector_2d(*args)
      args = args[0].to_a if args.size == 1
      VectorN.new(args[0, 2])
    end

    class VectorN < Array
      # A simple vector supporting scalar multiply and vector add, % dot product, magnitude
      def initialize(elts); concat(elts); end # rubocop:disable Lint/MissingSuper
      def *(scalar); VectorN.new(map { |c| c * scalar }); end
      def +(vec2); VectorN.new(zip(vec2).map { |c, v| c + v }); end
      def -(vec2); VectorN.new(zip(vec2).map { |c, v| c - v }); end
      def dot(vec2); zip(vec2).map { |c, v| c * v }.reduce(:+); end
      def abs(); map { |c| c * c }.reduce(:+)**0.5; end
      def ==(vec2); SVG.same((self - vec2).abs, 0.0); end
      def inspect(); "(#{map { |c| '%0.3f' % c }.join(',')})"; end
      def to_s; inspect; end
      def x; self[0]; end
      def y; self[1]; end
    end
  end
end
