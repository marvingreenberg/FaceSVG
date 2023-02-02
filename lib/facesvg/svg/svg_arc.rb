# frozen_string_literal: true

require('facesvg/svg/util')
require('facesvg/svg/vector_n')

module FaceSVG
  module SVG
    extend self

    def to_degrees(angle); angle * 180.0 / Math::PI; end

    # Sketchup is a mess - it draws curves and keeps information about them
    #  but treats everything as edges
    # Create class to aggregate ArcCurve with its associated Edges
    class SVGArc
      attr_reader(:startxy, :endxy)

      # ArcCurve has a sequence of Sketchup::Edge (line) segments, and a curve object
      # with accurate arc information
      # Note, now all paths are transformed to z=0. So start using 2d
      def initialize(centerxy, radius, startxy, endxy, start_angle, end_angle, xaxis2d, yaxis2d)
        @radius = radius
        @centerxy = centerxy
        @startxy = startxy
        @endxy = endxy
        @start_angle = start_angle
        @end_angle = SVG.su_bug(end_angle)
        @xaxis2d = xaxis2d
        @yaxis2d = yaxis2d

        ellipse_parameters()
      end

      def to_h()
        {
          radius: @radius,
          centerxy: @centerxy,
          startxy: @startxy,
          endxy: @endxy,
          start_angle: @start_angle,
          end_angle: @end_angle,
          xaxis2d: @xaxis2d,
          yaxis2d: @yaxis2d
        }
      end

      # https://gamedev.stackexchange.com/questions/45412/
      #    understanding-math-used-to-determine-if-vector-is-clockwise-counterclockwise-f

      # cwin svg coordinate space, +y is down.
      def cw_normal(vtx0)
        SVG.vector_2d(-vtx0.y, vtx0.x)
      end

      # Sweep flag depends on svg coordinate sense.  cw_normal, above defines.
      def sweep()
        # Calculate the sweep to midpoint, < 180 degrees,
        # same as finding if (center -> start)
        # is clockwise rotation from (center -> midpoint)
        vec_center_to_start = (@startxy - @centerxy)
        vec_center_to_middle = (@midxy - @centerxy)
        vec_center_to_middle.dot(cw_normal(vec_center_to_start)) > 0 ? '1' : '0'
      end

      # https://en.wikipedia.org/wiki/Ellipse  See Ellipse as an affine image,
      # specifically cot(2t) = ((f1 * f1) - (f2 * f2)) / 2( f1 * f2 )
      # cot is just 1/tan, so...
      def ellipse_parameters
        # circle, axes are orthogonal, same length
        if ((@xaxis2d.dot @yaxis2d) == 0 && SVG.same(@xaxis2d.abs, @yaxis2d.abs))
          @vx = @xaxis2d
          @vy = @yaxis2d
          @rx = @ry = @radius
        else
          f1 = @xaxis2d
          f2 = @yaxis2d
          vertex_angle1 = 0.5 * Math.atan2(((f1.dot f2) * 2), ((f1.dot f1) - (f2.dot f2)))
          # Get the two vertices "x" and "y"
          @vx = ellipseXY_at_angle(vertex_angle1)
          @vy = ellipseXY_at_angle(vertex_angle1 + (Math::PI/2))
          # ellipse radii are magnitude of x,y vertex vectors
          @rx = @vx.abs
          @ry = @vy.abs
        end
        # Angle of "x" vertex vector
        @xrotdeg = (@vx.x == 0) ? 90 : SVG.to_degrees(Math.atan2(@vx.y, @vx.x)).modulo(360.0)

        midangle = (@end_angle + @start_angle)/2.0
        @midxy = ellipseXY_at_angle(midangle, absolute: true)

        # Draw large arcs as two arcs, instead of using flag, to handle closed path case
        @largearc = (@end_angle - @start_angle) > Math::PI
      end

      def ellipseXY_at_angle(ang, absolute: false)
        # Return point on ellipse at angle, relative to center.  If absolute, add center
        p = (@xaxis2d * Math.cos(ang)) + (@yaxis2d * Math.sin(ang))
        p = p + @centerxy if absolute
        p
      end

      # Always set large arc FLAG to 0, just draw as two arcs if arc > PI.
      # This works for degenerate case where start==end
      SVG_ARC_FORMAT = ' A %0.3f %0.3f %0.3f 0 %s %0.3f %0.3f'
      def svgdata(is_first: false)
        sweep_fl = sweep()
        FaceSVG.dbg('Center %s vx %s vy %s Orig start,end angle %s,%s',
                    @centerxy, @vx, @vy, SVG.to_degrees(@start_angle), SVG.to_degrees(@end_angle))

        FaceSVG.dbg('Move to %s', @startxy) if is_first
        FaceSVG.dbg('Arc to mid %s', @midxy) if @largearc
        FaceSVG.dbg('Arc to %s', @endxy)

        # If first path (is_first) output "move",
        # Then draw arc to end, with arc to midpoint if "largarc"
        result = ((is_first ? format('M %0.3f %0.3f', @startxy.x, @startxy.y) : '') +
          (@largearc ?
            format(SVG_ARC_FORMAT, @rx, @ry, @xrotdeg, sweep_fl, @midxy.x, @midxy.y)
            : '') +
          format(SVG_ARC_FORMAT, @rx, @ry, @xrotdeg, sweep_fl, @endxy.x, @endxy.y))
        FaceSVG.testdata(function: 'FaceSVG::SVG::SVGArc.svgdata',
                         inputs: [to_h, is_first], result: result)
        result
      end
    end
  end
end
