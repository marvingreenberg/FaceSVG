# frozen_string_literal: true

require('facesvg/svg/vector_n')

module FaceSVG
  module SVG
    class SVGSegment
      # Edge is a single line segment with a start and end x,y
      def initialize(startpos, endpos)
        @startxy = vector_2d(startpos)
        @endxy = vector_2d(endpos)
      end

      def svgdata(is_first: false)
        # If first path (is_first) output "move", rest just line draw
        FaceSVG.dbg('Move to %s', @startxy) if is_first
        FaceSVG.dbg('Line to %s', @endxy)

        (is_first ?
          'M %0.3f %0.3f' % [@startxy.x, @startxy.y] :
          '') + (
          ' L %0.3f %0.3f' % [@endxy.x, @endxy.y])
      end
    end
  end
end
