# frozen_string_literal: true

Sketchup.require('matrix')

module FaceSVG
  extend self

  class Bounds
    # Convenience wrapper around a bounding box, accumulate the bounds
    #  of related faces and create a transform to move highest face
    #  to z=0, and min x,y to 0,0
    # BoundingBox width and height methods are undocumented nonsense, ignore them
    def initialize()
      @bounds = Geom::BoundingBox.new
    end
    def update(*e_ary)
      e_ary.each { |e| @bounds.add(e.bounds) }
      self
    end

    # Return a number that is a measure of the "extent" if the bounding box
    def extent; @bounds.diagonal; end
    def width; @bounds.max.x - @bounds.min.x; end
    def height; @bounds.max.y - @bounds.min.y; end
    def min; @bounds.min; end
    def max; @bounds.max; end
    def to_s; format('Bounds(min %s max %s)', @bounds.min, @bounds.max); end

    def shift_transform
      # Return a transformation to move min to 0,0, and shift bounds accordingly
      Geom::Transformation
        .new([1.0, 0.0, 0.0, 0.0,
              0.0, 1.0, 0.0, 0.0,
              0.0, 0.0, 1.0, 0.0,
              -@bounds.min.x, -@bounds.min.y, -@bounds.max.z, 1.0])
    end
  end
end
