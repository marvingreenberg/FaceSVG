# Simple Node object to construct SVG XML output (no built in support for XML in ruby)

# This allows reloading modules as modifications are made
begin
  Object.send(:remove_const, :SVG)
rescue => exception
  true
end

FMT = '%0.2f'

module ShaperSVG
module SVG

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
    def initialize(minx, miny, maxx, maxy, unit, version)
      @minx, @miny, @maxx, @maxy = minx, miny, maxx, maxy
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
  class Edge; def initialize(points); @points = points; end; end

  def createLoop(points: nil, arcparms: nil, inner: false)
    if inner
      l = InnerLoop.new(points)
    else
      l = OuterLoop.new(points)
    end
    l
  end

  
  class Loop
    def initialize(points); @points = points; end;

    def svgdata
      "M " + (@points.map { |p| puts p; "%0.5f %0.5f"% [p[0],p[1]] }).join(" L ")
    end
  end
  class InnerLoop < Loop
    def attributes
      { path_type: "interior", stroke_width: "2", stroke: "rgb(0,0,0)", fill: "rgb(255,255,255)" }
    end
  end

  class OuterLoop < Loop
    def attributes
      { path_type: "exterior", fill: "rgb(0,0,0)" }
    end
  end

end
end
