Sketchup.require('facesvg/constants')
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
      def ==(v2); (self - v2).abs < 0.0005; end
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
        xf = arcpathpart.xform
        # Ensure the edges are ordered as a path
        @radius = arcpathpart.crv.radius
        @centerxy = SVG.V2d(arcpathpart.crv.center.transform(xf))
        @startxy = SVG.V2d(arcpathpart.startpos.transform(xf))
        @endxy = SVG.V2d(arcpathpart.endpos.transform(xf))
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

      # cw in svg coordinate space, +y is down
      def cw_normal(v0)
        SVG.V2d(-v0.y, v0.x)
      end

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
        if ((@xaxis2d.dot @yaxis2d) == 0 and
            (@xaxis2d.abs - @yaxis2d.abs < 0.05))
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
        @xrot = (@vx.x == 0) ? 90 : Math.atan(@vx.y / @vx.x)
        @xrotdeg = @xrot.radians # converted from radians

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
      def svgdata(prev)
        sweep_fl = sweep()
        FaceSVG.dbg('Center %s vx %s vy %s Orig start,end angle %s,%s',
                    @centerxy, @vx, @vy, @start_angle.radians,
                    @end_angle.radians)

        FaceSVG.dbg('Move to %s', @startxy) if prev.nil?
        FaceSVG.dbg('Arc to mid %s', @midxy) if @largearc
        FaceSVG.dbg('Arc to %s', @endxy)

        # If first path (prev is nil) output "move",
        # Then draw arc to end, with arc to midpoint if "largarc"
        ((prev.nil? ? format("M #{FMT} #{FMT}", @startxy.x, @startxy.y) : '') +
          (@largearc ?
            format(SVG_ARC_FORMAT, @rx, @ry, @xrotdeg, sweep_fl, @midxy.x, @midxy.y)
            : '') +
          format(SVG_ARC_FORMAT, @rx, @ry, @xrotdeg, sweep_fl, @endxy.x, @endxy.y))
      end
    end

    class SVGSegment
      # Edge is a single line segment with a start and end x,y
      def initialize(edgepathpart)
        xf = edgepathpart.xform
        @startxy = SVG.V2d(edgepathpart.startpos.transform(xf))
        @endxy = SVG.V2d(edgepathpart.endpos.transform(xf))
      end

      def svgdata(prev)
        # If first path (prev is nil) output "move", rest just line draw
        FaceSVG.dbg('Move to %s', @startxy) if prev.nil?
        FaceSVG.dbg('Line to %s', @endxy)

        (prev.nil? ? "M #{FMT} #{FMT}" % @startxy : '') + (
          " L #{FMT} #{FMT}" % @endxy)
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
      def title(text); @root.add_child(Node.new('title', text: text)); end
      # Set the SVG model description
      def desc(text); @root.add_child(Node.new('desc', text: text)); end

      # Add an SVG path node
      #
      # ==== Attributes
      #
      # * +data+ - SVG path node 'd' sttribute, like "M 0 0 L 0 1 L 1 1 Z"
      # * +fill+ - rgb for fill, like "rgb(0,0,0)" as a string.
      # * +stroke+ - rgb for path stroke
      # * +stroke_width+ - pixel width for path stroke
      # * +path_type+ - "exterior" or "interior" or "edge???"
      # * +cut_depth+ - depth in inches? for cutter head.
      def mkpath(data, fill: nil, stroke: nil, stroke_width: nil, path_type: 'exterior',
                 vector_effect: 'non-scaling-stroke', cut_depth: '0.0125', zlayer: 0.0)

        p = Node
            .new('path',
                 attrs: {
                   'd'=> data,
                   'vector-effect' => vector_effect,
                   'shaper:cutDepth' => cut_depth,
                   'shaper:pathType' => path_type,
                   'zlayer' => zlayer })
        p.add_attr('fill', fill) if fill
        p.add_attr('stroke', stroke) if stroke
        p.add_attr('stroke-width', stroke_width) if stroke_width

        @root.add_child(p)
      end

      def write(file)
        file.write("<!-- ARC is A xrad yrad xrotation-degrees largearc sweep end_x end_y -->\n")
        @root.write(file)
      end

      def addpaths(xf, face, surface)
        # Only do outer loop for pocket faces
        if face.material == POCKET
          paths = [[face.outer_loop, PK_POCKET]]
          cut_depth = FaceSVG.face_offset(face, surface)
        else
          # Make list of all loops with outer_loop marked as exterior
          paths = face.loops.map { |l|
            [l, (l == face.outer_loop) ? PK_EXTERIOR : PK_INTERIOR]
          }
          cut_depth = CFG.cut_depth
        end

        paths.each do |loop, profile_kind|
          FaceSVG.dbg('Profile, %s edges, %s %s', loop.edges.size, profile_kind, cut_depth)
          # regroup edges so arc edges are grouped with metadata, all ordered end to start
          curves = [] # Keep track of processed arcs
          pathparts = loop.edges.map { |edge| PathPart.create(xf, curves, edge) }
          pathparts = FaceSVG.reorder(pathparts.reject(&:nil?))
          svgloop = Loop.create(pathparts, profile_kind, cut_depth)
          mkpath(svgloop.svgdata, svgloop.attributes)
        end
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
        @attrs = attrs or {}
        # node text
        @text = text
        # node children
        @children = []
        # Default stuff ordered to top (10.0) -- desc, title, etc.
        @zlayer = attrs && attrs.delete('zlayer') || 10.0
      end

      attr_reader :zlayer

      def <=>(other)
        -(zlayer <=> other.zlayer) # minus, since bigger are first
      end

      def add_attr(name, value); @attrs[name] = value; end
      def add_text(text); @text = text; end

      def add_child(node); @children << node; end

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

    ## open path cut
    class Edge
      def initialize(points)
        @points = points
      end
    end

    class Loop
      # class Loop factory method.  See Arcs and Lines in reorder.rb, basically
      # to aggregate edges with arc metadata, and deal with ordering
      def self.create(pathpart_arr, kind, cut_depth)
        Loop.new(
          pathpart_arr.map { |part|
            part.crv.nil? ? SVGSegment.new(part) : SVGArc.new(part)
          }, kind, cut_depth)
      end

      def white; 'rgb(255,255,255)'; end
      def black; 'rgb(0,0,0)'; end
      # blue extracted from example Shaper.png
      def blue; 'rgb(20,110,255)'; end
      def gray(depth)
        # Scale the "grayness" based on depth.  Supposedly SO will
        # recognize from 60,60,60 to 180,180,180 as gray (maybe more?)
        gray = 70 + (100.0*depth/CFG.pocket_max).to_int
        "rgb(#{gray},#{gray},#{gray})"
      end

      def initialize(pathparts, kind, cut_depth)
        # pathparts: array of SVGArcs and SVGSegments
        @pathparts = pathparts
        # SVG paths have to be ordered to be displayed correctly, add a pseudo-zlayer
        if kind == PK_EXTERIOR
          @attributes = { zlayer: 2.0, path_type: kind, cut_depth: cut_depth, fill: black }
        elsif kind == PK_INTERIOR
          @attributes = { zlayer: 1.0, path_type: kind, cut_depth: cut_depth, fill: white,
            stroke_width: '2', stroke: black }
        elsif kind == PK_POCKET
          @attributes = { zlayer: -cut_depth, path_type: kind, cut_depth: cut_depth, fill: gray(cut_depth),
            stroke_width: '2', stroke: gray(cut_depth) }
        else # PK_GUIDE, let's not fill, could be problematic
          @attributes = { path_type: kind, stroke_width: '2', stroke: blue }
        end
      end

      attr_reader :attributes

      # Append all individual path data parts, with Z at end to closepath
      def svgdata
        prev = nil
        (@pathparts.map { |p| d = p.svgdata(prev); prev = p; d }).join(' ') + ' Z'
      end
    end
  end
end
