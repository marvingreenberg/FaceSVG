Sketchup.require('facesvg/constants')
Sketchup.require('facesvg/su_util')
Sketchup.require('facesvg/reorder') # for reorder function and Line/Arc classes

module FaceSVG
  module SVG
    extend self

    FMT = '%0.4f'.freeze

    def V2d(*args)
      args = args[0].to_a if args.size == 1
      Vn.new(args[0, 2])
    end

    class Vn < Array
      # A simple vector supporting scalar multiply and vector add, % dot product, magnitude
      def initialize(elts); concat(elts); end
      def *(scalar); Vn.new(map { |c| c * scalar }); end
      def +(v2); Vn.new(zip(v2).map { |c, v| c + v }); end
      def -(v2); Vn.new(zip(v2).map { |c, v| c - v }); end
      def dot(v2); zip(v2).map { |c, v| c * v }.reduce(:+); end
      def abs(); map { |c| c * c }.reduce(:+)**0.5; end
      def ==(v2); FaceSVG.same((self - v2).abs, 0.0); end
      def inspect(); '(' + map { |c| FMT % c }.join(',') + ')'; end
      def to_s; inspect; end
      def x; self[0]; end
      def y; self[1]; end
    end

    # Sketchup sometime has crazy end angles, like 4*PI
    # OH. it's a documented bug,
    # http://ruby.sketchup.com/Sketchup/ArcCurve.html#end_angle-instance_method
    def su_bug(end_angle)
      end_angle -= (2 * Math::PI) if end_angle > (2 * Math::PI)
      end_angle
    end

    # Sketchup is a mess - it draws curves and keeps information about them
    #  but treats everything as edges
    # Create class to aggregate ArcCurve with its associated Edges
    class SVGArc
      # Arc has a sequence of Sketchup::Edge (line) segments, and a curve object
      # with accurate arc information
      # Note, now all paths are transformed to z=0. So start using 2d
      def initialize(arcpathpart)
        @radius = arcpathpart.crv.radius
        @centerxy = SVG.V2d(arcpathpart.center)
        @startxy = SVG.V2d(arcpathpart.startpos)
        @endxy = SVG.V2d(arcpathpart.endpos)
        @start_angle = arcpathpart.crv.start_angle
        @end_angle = SVG.su_bug(arcpathpart.crv.end_angle)
        @xaxis2d = SVG.V2d(arcpathpart.crv.xaxis)
        @yaxis2d = SVG.V2d(arcpathpart.crv.yaxis)

        ellipse_parameters()
        FaceSVG.dbg("Defining SVGArc start, end, center, radius '%s' '%s' '%s' '%s' (ang %s %s)",
                    @startxy, @endxy, @centerxy, @radius, @start_angle.radians, @end_angle.radians)
      end

      # https://gamedev.stackexchange.com/questions/45412/
      #    understanding-math-used-to-determine-if-vector-is-clockwise-counterclockwise-f

      # cwin svg coordinate space, +y is down.
      def cw_normal(v0)
        SVG.V2d(-v0.y, v0.x)
      end

      # Sweep flag depends on svg coordinate sense.  cw_normal, above defines.
      def sweep()
        # Calculate the sweep to midpoint, < 180 degrees,
        # same as finding if (center -> start)
        # is clockwise rotation from (center -> midpoint)
        c_to_s = (@startxy - @centerxy)
        c_to_e = (@midxy - @centerxy)
        c_to_e.dot(cw_normal(c_to_s)) > 0 ? '1' : '0'
      end

      # https://en.wikipedia.org/wiki/Ellipse  See Ellipse as an affine image,
      # specifically cot(2t) = ((f1 * f1) - (f2 * f2)) / 2( f1 * f2 )
      # cot is just 1/tan, so...
      def ellipse_parameters
        # circle, axes are orthogonal, same length
        if ((@xaxis2d.dot @yaxis2d) == 0 && FaceSVG.same(@xaxis2d.abs, @yaxis2d.abs))
          @vx = @xaxis2d
          @vy = @yaxis2d
          @rx = @ry = @radius
        else
          f1 = @xaxis2d
          f2 = @yaxis2d
          vertex_angle1 = 0.5 * Math.atan2(((f1.dot f2) * 2), ((f1.dot f1) - (f2.dot f2)))
          # Get the two vertices "x" and "y"
          @vx = ellipseXY_at_angle(vertex_angle1)
          @vy = ellipseXY_at_angle(vertex_angle1 + Math::PI/2)
          # ellipse radii are magnitude of x,y vertex vectors
          @rx = @vx.abs
          @ry = @vy.abs
        end
        # Angle of "x" vertex vector
        @xrotdeg = (@vx.x == 0) ? 90 : Math.atan2(@vx.y, @vx.x).radians.modulo(360.0)

        midangle = (@end_angle + @start_angle)/2.0
        @midxy = ellipseXY_at_angle(midangle, absolute: true)

        # Draw large arcs as two arcs, instead of using flag, to handle closed path case
        @largearc = (@end_angle - @start_angle) > Math::PI
      end

      def ellipseXY_at_angle(ang, absolute: false)
        # Return point on ellipse at angle, relative to center.  If absolute, add center
        p = @xaxis2d * Math.cos(ang) + @yaxis2d * Math.sin(ang)
        p = p + @centerxy if absolute
        p
      end

      # Always set large arc FLAG to 0, just draw as two arcs if arc > PI.
      # This works for degenerate case where start==end
      SVG_ARC_FORMAT = " A #{FMT} #{FMT} #{FMT} 0 %s #{FMT} #{FMT}".freeze
      def svgdata(is_first)
        sweep_fl = sweep()
        FaceSVG.dbg('Center %s vx %s vy %s Orig start,end angle %s,%s',
                    @centerxy, @vx, @vy, @start_angle.radians,
                    @end_angle.radians)

        FaceSVG.dbg('Move to %s', @startxy) if is_first
        FaceSVG.dbg('Arc to mid %s', @midxy) if @largearc
        FaceSVG.dbg('Arc to %s', @endxy)

        # If first path (is_first) output "move",
        # Then draw arc to end, with arc to midpoint if "largarc"
        ((is_first ? format("M #{FMT} #{FMT}", @startxy.x, @startxy.y) : '') +
          (@largearc ?
            format(SVG_ARC_FORMAT, @rx, @ry, @xrotdeg, sweep_fl, @midxy.x, @midxy.y)
            : '') +
          format(SVG_ARC_FORMAT, @rx, @ry, @xrotdeg, sweep_fl, @endxy.x, @endxy.y))
      end
    end

    class SVGSegment
      # Edge is a single line segment with a start and end x,y
      def initialize(edgepathpart)
        @startxy = SVG.V2d(edgepathpart.startpos)
        @endxy = SVG.V2d(edgepathpart.endpos)
      end

      def svgdata(is_first)
        # If first path (is_first) output "move", rest just line draw
        FaceSVG.dbg('Move to %s', @startxy) if is_first
        FaceSVG.dbg('Line to %s', @endxy)

        (is_first ?
          "M #{FMT} #{FMT}" % [@startxy.x, @startxy.y] :
          '') + (
          " L #{FMT} #{FMT}" % [@endxy.x, @endxy.y])
      end
    end

    BKGBOX = "new #{FMT} #{FMT} #{FMT} #{FMT}".freeze
    VIEWBOX = "#{FMT} #{FMT} #{FMT} #{FMT}".freeze
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
        @matrix = format("matrix(1,0,0,-1,0.0,#{FMT})", @maxy)

        @root = Node
                .new('svg',
                     attrs: {
                       'enable-background' => format(BKGBOX, @minx, @miny, @maxx, @maxy),
                       'height' => format("#{FMT}#{@unit}", @height),
                       'width' => format("#{FMT}#{@unit}", @width),
                       'version' => '1.1', # SVG VERSION
                       'viewBox' => format(VIEWBOX, @minx, @miny, @maxx, @maxy),
                       'x' => format("#{FMT}#{@unit}", @minx),
                       'y' => format("#{FMT}#{@unit}", @minx),
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

      def pocket_paths(data_bnds, cut_depth)
        # Merge all paths in single 'd' path
        merged = data_bnds.map { |pair| pair[0] }.join(' ')
        # in first data_bnds pair, get the extent for this outermost bounds
        # Want the pocket ordered slightly after the identical extent interior cut
        outer_extent = data_bnds[0][1].extent - 0.01
        attrs = { 'd' => merged, 'extent' => outer_extent, 'transform' => @matrix }
        attrs.merge!(PathAttributes.new(PK_POCKET, cut_depth))
        # Return array of one path node (with merged path data)
        [Node.new('path', attrs: attrs)]
      end

      def cut_paths(data_bnds, cut_depth)
        # First, the outer loop
        outer, obnds = data_bnds[0]
        attrs = { 'd' => outer, 'extent' => obnds.extent, 'transform' => @matrix }
        attrs.merge!(PathAttributes.new(PK_EXTERIOR, cut_depth))
        outer_path = Node.new('path', attrs: attrs)

        inner_paths = data_bnds.drop(1).map { |data, bnds|
          attrs = { 'd' => data, 'extent' => bnds.extent, 'transform' => @matrix }
          attrs.merge!(PathAttributes.new(PK_INTERIOR, cut_depth))
          Node.new('path', attrs: attrs)
        }
        [outer_path] + inner_paths
      end

      def add_paths(xf, face, surface)
        # Ensure outer loop is first
        loops = [face.outer_loop] + face.loops.reject { |x| x == face.outer_loop }

        # Return array of [ [SVGData, Bounds], [SVGData, Bounds] ,...]
        data_bnds = loops.map do |loop|
          pathparts = FaceSVG.reordered_path_parts(loop, xf)
          # Return array of [SVGData strings, Bounds]
          [SVGData.new(pathparts).to_s, Bounds.new.update(*loop.edges)]
        end
        # First data path is exterior, or pocket cut outer bounds
        # Pocket cut paths are joined as outer and inner with evenodd fill-rule
        # Exterior, interior done as separate path to generate correct exterior interior cuts
        if face.material == FaceSVG.pocket
          cut_depth = FaceSVG.face_offset(face, surface)
          nodes = pocket_paths(data_bnds, cut_depth)
        else
          cut_depth = CFG.cut_depth
          nodes = cut_paths(data_bnds, cut_depth)
        end
        @root.add_children(*nodes)
      end
    end

    class Node
      # Simple Node object to construct SVG XML output (no built in support for XML in ruby)
      # Only the paths need to be sorted,  so initialize with a 'z' value.
      # Everything is transformed to z=0 OR below.  So make exterior paths 2.0,
      # interior 1.0, and pocket cuts actual depth (negative offsets)

      def initialize(name, attrs: nil, text: nil)
        @name = name
        # attribute map
        # Default stuff (desc, title) ordered to top (1.0e20)
        @attrs = attrs.nil? ? {} : attrs.clone
        @extent = @attrs.delete('extent') || 1.0e20
        # node text
        @text = text
        # node children
        @children = []
      end

      attr_reader :extent

      def <=>(other)
        -(extent <=> other.extent) # minus, since bigger are first
      end

      def add_attr(name, value); @attrs[name] = value; end
      def add_text(text); @text = text; end

      def add_children(*nodes); @children.push(*nodes); end

      def write(file)
        file.write("\n<#{@name} ")
        @attrs and @attrs.each { |k, v| file.write("#{k}='#{v}' ") }
        if @children.length == 0 and not @text
          file.write('/>')
        else
          file.write('>')
          file.write(@text) if @text
          @children.sort.each { |c| c.write(file) }
          file.write("\n</#{@name}>")
        end
      end
    end

    class PathAttributes
      def initialize(kind, cut_depth)
        if kind == PK_EXTERIOR
          @attributes = {
            SHAPER_PATH_TYPE => kind, SHAPER_CUT_DEPTH => format(FMT, cut_depth),
            FILL => black }
        elsif kind == PK_INTERIOR
          @attributes = {
            SHAPER_PATH_TYPE => kind, SHAPER_CUT_DEPTH => format(FMT, cut_depth),
            FILL => white, STROKE => black, STROKE_WIDTH => '2',
            VECTOR_EFFECT => VE_NON_SCALING_STROKE }
        elsif kind == PK_POCKET
          @attributes = {
            SHAPER_PATH_TYPE => kind,  SHAPER_CUT_DEPTH => format(FMT, cut_depth),
            FILL_RULE => EVENODD, FILL => gray(cut_depth),
            STROKE_WIDTH => '2', STROKE =>  gray(cut_depth),
            VECTOR_EFFECT => VE_NON_SCALING_STROKE }
        else # PK_GUIDE, let's not fill, could be problematic
          @attributes = { SHAPER_PATH_TYPE => kind,
            STROKE_WIDTH => '2', STROKE => blue,
            VECTOR_EFFECT => VE_NON_SCALING_STROKE }
        end
      end
      def white; 'rgb(255,255,255)'; end
      def black; 'rgb(0,0,0)'; end
      # blue extracted from example Shaper.png
      def blue; 'rgb(20,110,255)'; end
      def gray(depth)
        # Scale the "grayness" based on depth.  Supposedly SO will
        # recognize from 60,60,60 to 180,180,180 as gray (maybe more?)
        gray = 70 + [(100.0*depth/CFG.pocket_max).to_int, 100].min
        "rgb(#{gray},#{gray},#{gray})"
      end
      # implicit conversion to hash
      def to_hash; @attributes; end
    end

    class SVGData
      def initialize(pathpart_arr)
        is_first = true
        dataparts = pathpart_arr.map { |part|
          d = (part.crv.nil? ?
            SVGSegment.new(part).svgdata(is_first) :
            SVGArc.new(part).svgdata(is_first))
          is_first = false;
          d
        }
        @svgdata = dataparts.join(' ') + 'Z '
      end
      def to_s; @svgdata; end
    end
  end
end
