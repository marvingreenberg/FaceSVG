# Simple Node object to construct SVG XML output (no built in support for XML in ruby)

FMT = '%0.3f'
def V2d(*args); args = args[0].to_a if args.size == 1; V_.new(args[0,2]); end

class V_ < Array
  # A simple vector supporting scalar multiply and vector add, % dot product, magnitude
  def initialize(elts); self.concat(elts); end
  def *(scalar); V_.new(self.map { |c| c*scalar }); end
  def +(v2); V_.new(self.zip(v2).map { |c,v| c+v }); end
  def -(v2); V_.new(self.zip(v2).map { |c,v| c-v }); end
  def %(v2); self.zip(v2).map { |c,v| c*v }.reduce ( :+ ); end
  def abs(); (self.map { |c| c*c }.reduce(:+))**0.5; end
  def inspect(); "(" + self.map { |c| "%0.2f"%c }.join(',') + ")"; end
  def to_s; inspect; end
  def x; self[0]; end
  def y; self[1]; end
end

module ShaperSVG
  module SVG
    
    # Sketchup is a mess - it draws curves and keeps information about them
    #  but treats everything as edges
    # Create class to aggregate ArcCurve with its associated Edges
    # For some reason, need to iterate across edges from endxy to startxy,
    class ArcObject
      # Arc has a sequence of Sketchup::Edge (line) segments, and a curve object
      # with accurate arc information    
      def initialize(xform, arcglob)
        @glob = arcglob
        @crv = @glob.crv
        # Ensure the edges are ordered as a path

        @centerxy = V2d(@crv.center.transform(xform))
        @startxy = V2d(@glob.startpos.transform(xform))
        @endxy = V2d(@glob.endpos.transform(xform))

        self.ellipse_parameters()
        puts "Defining ArcObject start, end, center '%s' '%s' '%s'" % [@startxy, @endxy, @centerxy]
      end

      def startxy(); @startxy; end
      def midxy(); @midxy; end
      def endxy(); @endxy; end

      # https://gamedev.stackexchange.com/questions/45412/
      #    understanding-math-used-to-determine-if-vector-is-clockwise-counterclockwise-f
      def sweep(xy0, xy1)
        # Calculate the sweep, same as finding if (start->center)
        # is clockwise rotation from (start->end)
        start_to_end = (xy1 - xy0)
        start_to_end_ccw_normal = V2d(start_to_end.y, -start_to_end.x)
        start_to_center = (@centerxy - xy0)
        (start_to_end_ccw_normal % start_to_center > 0) ? '0' : '1'
      end

      # curve has curve.center, .radius, .xaxis, .yaxis,
      # .start_angle, .end_angle, see Sketchup API
      # Note, now all paths are transformed to z=0. So start using 2d
      # https://en.wikipedia.org/wiki/Ellipse  See Ellipse as an affine image,
      # specifically cot(2t) = ((f1 * f1) - (f2 * f2)) / 2( f1 * f2 )
      # cot is just 1/tan, so...
      def ellipse_parameters()
        # circle
        if @crv.xaxis.length == @crv.yaxis.length
          @vx = V2d(@crv.xaxis)
          @vy = V2d(@crv.yaxis)
          @rx = @ry = @crv.radius
        else
          f1 = V2d(@crv.xaxis)
          f2 = V2d(@crv.yaxis)
          vertex_angle1 = 0.5 * Math::atan( ((f1 % f2) * 2) / ((f1 % f1) - (f2 % f2)) )
          # Get the two vertices "x" and "y"
          @vx = ellipseXY_at_angle(vertex_angle1)
          @vy = ellipseXY_at_angle(vertex_angle1 + Math::PI/2)
          # ellipse radii are magnitude of x,y vertex vectors
          @rx = @vx.abs
          @ry = @vy.abs  
        end
        # Angle of "x" vertex vector
        @xrot = (@vx.x == 0) ? 90 : Math::atan(@vx.y / @vx.x)
        @xrotdeg = @xrot.radians # converted from radians

        @midxy = nil
        if (@crv.end_angle - @crv.start_angle) > Math::PI
          midangle = (@crv.end_angle + @crv.start_angle)/2.0
          @midxy = ellipseXY_at_angle(midangle,absolute:true)
        end
      end
      
      def ellipseXY_at_angle(ang, absolute: false)
        # Return point on ellipse at angle, relative to center.  If absolute, add center
        p = V2d(@crv.xaxis)*Math::cos(ang) + V2d(@crv.yaxis)*Math::sin(ang)
        p = p + @centerxy if absolute
        p
      end

      # Always set largeArc to 0, draw as two arcs is > PI.
      # This works for degenerate case where start==end
      SVG_ARC_FORMAT = " A #{FMT} #{FMT} #{FMT} 0 %s #{FMT} #{FMT}"
      def svgdata(prev)
        sweepFlag = sweep(@startxy, @midxy ? @midxy : @endxy)
        if prev.nil?
          puts "\n\nMove to %s" % [@startxy]
        end
        if not @midxy.nil?
          puts "Arc to mid %s" % [@midxy]
          puts 'Large arc, center %s vx %s vy %s Orig start,end angle %s,%s' % [
                 @centerxy, @vx, @vy, @crv.start_angle.radians, @crv.end_angle.radians ]
        end
        puts "Arc to %s" % [@endxy]

        # If first path (prev is nil) output "move", rest just output (possibly 2) arc
        ( (prev.nil? ? "M #{FMT} #{FMT}" % @startxy : '') + 
          ( @midxy.nil? ? '' :
              ( SVG_ARC_FORMAT % [
                  @rx, @ry, @xrotdeg, sweepFlag, @midxy.x, @midxy.y])) +
          SVG_ARC_FORMAT % [
            @rx, @ry, @xrotdeg, sweepFlag, @endxy.x, @endxy.y]
        )
      end
    end
    
    class EdgeObject
      # Edge is a single line segment with a start and end x,y
      def initialize(xform, edgeglob)
        @glob = edgeglob
        @startxy = V2d(@glob.startpos.transform(xform))
        @endxy = V2d(@glob.endpos.transform(xform))     
      end
      def startxy(); @startxy; end
      def endxy(); @endxy; end

      def svgdata(prev)

        # If first path (prev is nil) output "move", rest just line draw
        if prev.nil?
          puts "\n\nMove to %s" % [@startxy]
        end
        puts "Line to %s" % [@endxy]
        
        (prev.nil? ? "M #{FMT} #{FMT}" % @startxy : '') + (
          " L #{FMT} #{FMT}" % @endxy)
      end
    end

    # Class used to collect the output paths to be emitted as SVG
    #
    # == Methods to set up the SvgOut
    #
    # +new(minx, miny, maxx, maxy, unit)+ - set up the extents and units for the SVG output
    # +path(...)+ - add exterior and interior paths representing cuts
    #
    # == Write SVG output
    # +write(file)+
    #
    # Embody +parameters+ or +options+ in Teletype Text tags.
    class Canvas
      def initialize(viewport, unit, version)
        @minx, @miny, @maxx, @maxy = viewport
        @width = @maxx - @minx    
        @height = @maxy - @miny
        @unit = unit

        @root = Node.new('svg', attrs: {
                           'enable-background': "new #{FMT} #{FMT} #{FMT} #{FMT}" % [@minx,@miny,@maxx, @maxy],
                                        'height': "#{FMT}#{@unit}" % [@height],
                                        'width': "#{FMT}#{@unit}" % [@width],
                                        'version': "1.1", # SVG VERSION
                                        'viewBox': "#{FMT} #{FMT} #{FMT} #{FMT}" % [@minx,@miny,@maxx, @maxy],
                                        'x': "#{FMT}#{@unit}" %[@minx],
                                        'y': "#{FMT}#{@unit}" %[@minx],
                                        'xmlns': "http://www.w3.org/2000/svg",
                                        'xmlns:xlink': "http://www.w3.org/1999/xlink",
                                        'xmlns:shaper': "http://www.shapertools.com/namespaces/shaper",
                                        'shaper:sketchupaddin': version
                         })
      end                

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
      # * +cut_depth+ - depth in inches? for cutter head.  Unclear how this should be set.
      def path(data, fill: nil, stroke: nil, stroke_width: nil,
               path_type:"exterior", vector_effect:"non-scaling-stroke", cut_depth:"0.0125",
               transform: nil)
        p = Node.new('path',
                     attrs: {
                       'd': data,
                             'vector-effect': vector_effect,
                             'shaper:cutDepth': cut_depth,
                             'shaper:pathType': path_type })
        p.add_attr('fill', fill) if fill
        p.add_attr('stroke', stroke) if stroke
        p.add_attr('stroke-width', stroke_width) if stroke_width
        
        @root.add_child(p)
      end

      def write(file)
        file.write("<!-- ARC is A xrad yrad xrotation-degrees largearc sweep end_x end_y -->\n")
        @root.write(file)
      end

    end
    

    class Node
      def initialize(name, attrs: nil, text: nil)
        @name = name
        # attribute map
        @attrs = attrs or {}
        # node text
        @text = text
        # node children
        @children = []
      end
      
      def add_attr(name, value); @attrs[name] = value; end
      def add_text(text);  @text = text;  end
      def add_child(node); @children << node; end

      def write(file)
        file.write("\n<#{@name} ")
        @attrs and @attrs.each { |k,v| file.write("#{k}='#{v}' ") }
        if @children.length == 0 and not @text
          file.write("/>")
        else
          file.write(">")
          file.write(@text) if @text
          @children.each { |c| c.write(file) }
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
      # class Loop factory method.  See "Globs" in layout.rb, basically
      # to aggregate edges with arc metadata, and deal with ordering
      def self.create(xform, glob_arr, outer)
        Loop.new( 
          glob_arr.map { |glob|
            glob.isArc() ? ArcObject.new(xform, glob) : EdgeObject.new(xform, glob)
          }, outer)
      end   
      
      def initialize(pathparts, outer: false)
        # pathparts: array of ArcObjects and EdgeObjects
        @pathparts = pathparts
        if outer
          @attributes = { path_type: "exterior", fill: "rgb(0,0,0)" }
        else
          @attributes = { path_type: "interior", stroke_width: "2", stroke: "rgb(0,0,0)", fill: "rgb(255,255,255)" }
        end
      end

      def attributes
        @attributes
      end
      # Append all indifidual path data parts, with Z at end to closepath
      def svgdata
        prev = nil
        (@pathparts.map { |p| d = p.svgdata(prev);  prev = p; d }).join(' ') + " Z"
      end
    end

  end
end
