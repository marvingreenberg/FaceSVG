# Simple Node object to construct SVG XML output (no built in support for XML in ruby)

# This allows reloading modules as modifications are made
begin
  Object.send(:remove_const, :SVG)
rescue => exception
  true
end

FMT = '%0.3f'

module ShaperSVG
module SVG

  # Sketchup is a mess - it draws curves and keeps information about them
  #  but treats everything as edges
  # Create class to aggregate ArcCurve with its associated Edges
  # Instead of largeArc, break every arc into two pieces if largeArc?
  class ArcObject
    # Arc has a sequence of Sketchup::Edge (line) segments, and a curve object
    # with accurate arc information    
    def initialize(xform, curve_edges)
      @xform = xform
      @curve = curve_edges[0].curve
      # Ensure the edges are ordered as a path
      @edges = @curve.edges
      self.ellipse_parameters()

      # curve has curve.center, curve.radius, curve.xaxis, curve.yaxis, curve.start_angle, curve.end_angle
    end
    # Note, by this point all paths should be transformed to z=0, but still treat all as 3d for simplicity
    # From https://en.wikipedia.org/wiki/Ellipse#Ellipse_as_an_affine_image_of_the_unit_circle_x%C2%B2+y%C2%B2=1
    def ellipse_parameters()
      # circle
      if @curve.xaxis.length == @curve.yaxis.length
        @vx = @curve.xaxis
        @vy = @curve.yaxis
        @rx = @ry = @curve.radius
      else
        f1 = @curve.xaxis
        f2 = @curve.yaxis
        val = ((f1 % f2) * 2) / ((f1 % f1) - (f2 % f2))  
        vertex_angle1 = Math::atan(val) / 2
        vertex_angle2 = vertex_angle1 + Math::PI/2
        @vx = ellipAtAngle(vertex_xangle1)
        @vy = ellipAtAngle(vertex_angle2)
        @rx = @vx.length
        @ry = @vy.length
      end
      # Angle of x vertex vector
      @xrot = (@vx[0] == 0) ? 90 : Math::atan(@vx[1] / @vx[0]).radians
    end
    
    def ellipAtAngle(ang)
      cosa = Math::cos(ang)
      sina = Math::sin(ang)
      Geom::Vector3d.new( [0,1,2].map { |i|  @curve.xaxis[i]*cosa + @curve.yaxis[i]*sina } )
    end

    def startxy()
      p = @edges[0].start.position.transform(@xform)
      [p[0],p[1]] # x,y
    end
    def PI_xy()
      # return nil if < 180 degree arc.
      # center + @vx is start, 180 degrees away  is (center - @vx)
      if (@curve.end_angle - @curve.start_angle) > Math::PI
        p = @curve.center.transform(@xform) - @vx
        [p[0], p[1]]
      end
    end
          
    def endxy()
      p = @edges[-1].end.position.transform(@xform)
      [p[0],p[1]] # x,y
    end
    def svgdata(prev)
      # angle > PI, draw arc up to PI, then PI to end angle
      centerxy = [@curve.center[0],@curve.center[1]]
      r = @curve.radius.round(3)
      # large arc is always false, always draw two arcs if > 180
      largeArc= '0'
      # sweep may need to be calculated from something, like where center is
      sweep = '0'
      midpoint = self.PI_xy # may be nil
      endpoint = self.endxy 
      ( (prev.nil? ? "M #{FMT} #{FMT}" % self.startxy : '') + 
        ( midpoint.nil? ? '' : 
            (" A #{FMT} #{FMT} #{FMT} %s %s #{FMT} #{FMT}" % 
             [@rx, @ry, @xrotdeg, largeArc, sweep, midpoint[0], midpoint[1]] )) +
        " A #{FMT} #{FMT} #{FMT} %s %s #{FMT} #{FMT}" % 
          [@rx, @ry, @xrotdeg, largeArc, sweep, endpoint[0], endpoint[1]] )
    end
  end
        
  class EdgeObject
    # Edge is a single line segment with a start and end x,y
    def initialize(xform, edges)
      @xform = xform
      @edges = edges # Always one-element array
    end
    def startxy()
      p = @edges[0].start.position.transform(@xform)
      [p[0],p[1]] # x,y
    end
    def endxy()
      # some comment about start,end and edge ordering
      p = @edges[0].end.position.transform(@xform)
      [p[0],p[1]] # x,y
    end
    def svgdata(prev)
      (prev.nil? ? "M #{FMT} #{FMT}" % self.endxy : '') + (
        " L #{FMT} #{FMT}" % self.startxy)
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
    # class Loop factory method
    def self.create(xform, edgesarray, outer)
      Loop.new( 
        edgesarray.map { |edgearr|
          (edgearr.size == 1 ?
             EdgeObject.new(xform, edgearr)
           :
             ArcObject.new(xform, edgearr)
          )
        }, outer)
    end   
    
    def initialize(pathparts, outer:false)
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
