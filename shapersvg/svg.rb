# Simple Node object to construct SVG XML output (no built in support for XML in ruby)

FMT = '%0.3f'
      
module ShaperSVG
module SVG
    
  # format a position with more brevity
  def self.pos_s(xy); "(%s,%s)" % xy.to_a.map { |m| m.round(2) }; end

  # Sketchup is a mess - it draws curves and keeps information about them
  #  but treats everything as edges
  # Create class to aggregate ArcCurve with its associated Edges
  # For some reason, need to iterate across edges from endxy to startxy,
  class ArcObject
    # Arc has a sequence of Sketchup::Edge (line) segments, and a curve object
    # with accurate arc information    
    def initialize(xform, arcglob)
      @xform = xform
      @crv = arcglob.crv
      # Ensure the edges are ordered as a path
      @glob = arcglob
      self.ellipse_parameters()

      @startxy = @glob.startpos.transform(@xform).to_a[0,2]
      @endxy = @glob.endpos.transform(@xform).to_a[0,2]
    end

    def startxy(); @startxy; end
    def midxy(); @midxy; end
    def endxy(); @endxy; end

    # https://gamedev.stackexchange.com/questions/45412/
    #    understanding-math-used-to-determine-if-vector-is-clockwise-counterclockwise-f
    def sweep()
      # Calculate the sweep from the orientation of the endpoints start -> finish,
      #   and the center, ref below may be relevant.  Maybe dot product  of normal and start->end
      # https://en.wikipedia.org/wiki/Distance_from_a_point_to_a_line#Line_defined_by_two_points
      '0'
    end

    # curve has curve.center, curve.radius, curve.xaxis, curve.yaxis, curve.start_angle, curve.end_angle
    # Note, by this point all paths should be transformed to z=0.  But all the vectors below are still in 3D
    # From https://en.wikipedia.org/wiki/Ellipse#Ellipse_as_an_affine_image_of_the_unit_circle_x%C2%B2+y%C2%B2=1
    def ellipse_parameters()
      # circle
      if @crv.xaxis.length == @crv.yaxis.length
        @vx = @crv.xaxis
        @vy = @crv.yaxis
        @rx = @ry = @crv.radius
      else
        f1 = @crv.xaxis
        f2 = @crv.yaxis
        val = ((f1 % f2) * 2) / ((f1 % f1) - (f2 % f2))  
        @vertex_angle1 = Math::atan(val) / 2
        @vertex_angle2 = @vertex_angle1 + Math::PI/2
        @vx = ellipAtAngle(@vertex_angle1)
        @vy = ellipAtAngle(@vertex_angle2)
        @rx = @vx.length
        @ry = @vy.length
      end
      @center = @crv.center.transform(@xform)
      # Angle of x vertex vector
      @xrot = (@vx[0] == 0) ? 90 : Math::atan(@vx[1] / @vx[0])
      @xrotdeg = @xrot.radians # converted from radians

      # Transform doesn't preserve angles...  but it does preserve angle ratios?
      @midxy = nil
      
      if (@crv.end_angle - @crv.start_angle) > Math::PI
        midangle = (@crv.end_angle + @crv.start_angle)/2.0
        @midxy = (ellipAtAngle(midangle,absolute:true)).to_a[0,2]
      end
    end
    
    def ellipAtAngle(ang, absolute: false)
      # Return point on ellipse at angle, relative to center.  If absolute, add center
      cosa = Math::cos(ang)
      sina = Math::sin(ang)
      p = Geom::Vector3d.new( [0,1,2].map { |i|  @crv.xaxis[i]*cosa + @crv.yaxis[i]*sina } )
      if absolute
        p = p + Geom::Vector3d.new( @center.to_a )
      end
      p
    end

    def svgdata(prev)
      # large arc is always false, always draw two arcs if > PI
      largeArc= '0'

      if prev.nil?
        puts "\n\nMove to %s" % [ShaperSVG::SVG.pos_s(@startxy)]
      end
      if not @midxy.nil?
        puts "Arc to mid %s" % [ShaperSVG::SVG.pos_s(@midxy)]
        puts 'Large arc, center %s vx %s vy %s Orig start,end angle %s,%s' % [
               @center, @vx, @vy, @crv.start_angle.radians, @crv.end_angle.radians ]
      end
      puts "Arc to %s" % [ShaperSVG::SVG.pos_s(@endxy)]
      
      ( (prev.nil? ? "M #{FMT} #{FMT}" % @startxy : '') + 
        ( @midxy.nil? ? '' : 
            (" A #{FMT} #{FMT} #{FMT} %s %s #{FMT} #{FMT}" % 
             [@rx, @ry, @xrotdeg, largeArc, self.sweep(), @midxy[0], @midxy[1]] )) +
        " A #{FMT} #{FMT} #{FMT} %s %s #{FMT} #{FMT}" % 
          [@rx, @ry, @xrotdeg, largeArc, self.sweep(), @endxy[0], @endxy[1]] )
    end
  end
        
  class EdgeObject
    # Edge is a single line segment with a start and end x,y
    def initialize(xform, edgeglob)
      @xform = xform
      @glob = edgeglob
      @startxy = @glob.startpos.transform(@xform).to_a[0,2]
      @endxy = @glob.endpos.transform(@xform).to_a[0,2]      
    end
    def startxy(); @startxy; end
    def endxy(); @endxy; end

    def svgdata(prev)

      if prev.nil?
        puts "\n\nMove to %s" % [ShaperSVG::SVG.pos_s(@startxy)]
      end
      puts "Line to %s" % [ShaperSVG::SVG.pos_s(@endxy)]
      
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
    
    def initialize(pathparts, outer:false)
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
