# frozen_string_literal: true

require('facesvg/svg/path_attributes')
require('facesvg/svg/node')
require 'facesvg/su_util'

module FaceSVG
  module SVG
    extend self

    BKGBOX = 'new %0.3f %0.3f %0.3f %0.3f'
    VIEWBOX = '%0.3f %0.3f %0.3f %0.3f'
    # Class used to collect the output paths to be emitted as SVG
    class Canvas
      def initialize(fname, viewport, _unit)
        @filename = fname
        @minx, @miny, @maxx, @maxy = viewport
        @width = @maxx - @minx
        @height = @maxy - @miny
        # TODO: fix units somewhere globally
        # for now just use 'in' since that's what sketchup does.
        @unit = 'in'
        @matrix = format('matrix(1,0,0,-1,0.0,%0.3f)', @maxy)

        @root = Node
                .new('svg',
                     attrs: {
                       'height' => format("%0.3f#{@unit}", @height),
                       'width' => format("%0.3f#{@unit}", @width),
                       'version' => '1.1', # SVG VERSION
                       'viewBox' => format(VIEWBOX, @minx, @miny, @width, @height),
                       'x' => format("%0.3f#{@unit}", @minx),
                       'y' => format("%0.3f#{@unit}", @minx),
                       'xmlns' => 'http://www.w3.org/2000/svg',
                       'xmlns:xlink' => 'http://www.w3.org/1999/xlink',
                       'xmlns:shaper' => 'http://www.shapertools.com/namespaces/shaper',
                       'shaper:sketchupaddin' => FaceSVG::VERSION # plugin version
                     })
      end

      attr_reader :filename

      # Set the SVG model title
      def title(text); @root.add_children(Node.new('title', text: text)); end
      # Set the SVG model description
      def desc(text); @root.add_children(Node.new('desc', text: text)); end

      def write(file)
        file.write("<!-- ARC is A xrad yrad xrotation-degrees largearc sweep end_x end_y -->\n")
        @root.write(file)
      end

      def pocket_paths(data_and_bounds, cut_depth)
        # Merge all paths in single 'd' path
        merged = data_and_bounds.map { |pair| pair[0] }.join(' ')
        # in first data_and_bounds pair, get the extent for this outermost bounds
        # Want the pocket ordered slightly after the identical extent interior cut
        outer_extent = data_and_bounds[0][1].extent - 0.01
        attrs = { 'd' => merged, 'extent' => outer_extent, 'transform' => @matrix }
        attrs.merge!(PathAttributes.new(PK_POCKET, cut_depth))
        # Return array of one path node (with merged path data)
        [Node.new('path', attrs: attrs)]
      end

      def cut_paths(data_and_bounds, cut_depth)
        # First, the outer loop
        outer, obnds = data_and_bounds[0]
        attrs = { 'd' => outer, 'extent' => obnds.extent, 'transform' => @matrix }
        attrs.merge!(PathAttributes.new(PK_EXTERIOR, cut_depth))
        outer_path = Node.new('path', attrs: attrs)

        inner_paths = data_and_bounds.drop(1).map { |data, bnds|
          attrs = { 'd' => data, 'extent' => bnds.extent, 'transform' => @matrix }
          attrs.merge!(PathAttributes.new(PK_INTERIOR, cut_depth))
          Node.new('path', attrs: attrs)
        }
        [outer_path] + inner_paths
      end

      def get_svgdata_and_bounds(transformation, face)
        loops = [face.outer_loop] + face.loops.reject { |x| x == face.outer_loop }

        # Return array of [ [SVGData, Bounds], [SVGData, Bounds] ,...]
        loops.map do |loop|
          svg_parts = FaceSVG.svg_parts_for_loop(loop, transformation)
          # Return array of [SVGData strings, Bounds]
          svgdata = "#{svg_parts.map.with_index { |part, i| part.svgdata(is_first: i == 0) }.join(' ')} Z "
          bounds =  Bounds.new.update(*loop.edges)
          [svgdata, bounds]
        end
      end

      def add_paths(transformation, face, surface)
        # Ensure outer loop is first
        data_and_bounds = get_svgdata_and_bounds(transformation, face)
        # First data path is exterior, or pocket cut outer bounds
        # Pocket cut paths are joined as outer and inner with evenodd fill-rule
        # Exterior, interior done as separate path to generate correct exterior interior cuts
        if face.material == FaceSVG.pocket
          cut_depth = FaceSVG.su_face_offset(face, surface)
          nodes = pocket_paths(data_and_bounds, cut_depth)
        else
          cut_depth = CFG.cut_depth
          nodes = cut_paths(data_and_bounds, cut_depth)
        end
        @root.add_children(*nodes)
      end
    end
  end
end
