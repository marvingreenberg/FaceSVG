# frozen_string_literal: true

module FaceSVG
  module SVG
    class SVGSegment
      attr_reader(:startxy, :endxy)

      # Edge is a single line segment with a start and end x,y
      def initialize(startxy, endxy)
        @startxy = startxy
        @endxy = endxy
      end

      def to_h(); { startxy: @startxy, endxy: @endxy }; end

      def svgdata(is_first: false)
        # If first path (is_first) output "move", rest just line draw
        FaceSVG.dbg('Move to %s', @startxy) if is_first
        FaceSVG.dbg('Line to %s', @endxy)

        (is_first ? 'M %0.3f %0.3f' % [@startxy.x, @startxy.y] : '') + (' L %0.3f %0.3f' % [@endxy.x, @endxy.y])
      end
    end
  end
end
