###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup.rb'
require 'extensions.rb'
require 'LangHandler.rb'

# $uStrings = LanguageHandler.new("shaperSVG")
# extensionSVG = SketchupExtension.new $uStrings.GetString("shaperSVG"), "shapersvg/shapersvg.rb"
# extensionSVG.description=$uStrings.GetString("Create SVG files from faces")
# Sketchup.register_extension extensionSVG, true

# Sketchup API is a litle strange - many operations create edges, but actually maintain a higher resolution 
#   circular or elliptical arc.  Still need to figure out various transforms, applied to shapes
# https://stackoverflow.com/questions/11503558/how-to-undefine-class-in-ruby

# Ruby is just weird
SHAPERADDIN_VERSION = 'version:0.1'
INCHES = 'in'
CM = 'cm'
MM = 'mm'
FMT = '%0.2f'

# TTD
# More settings material size 2x4 4x4, bit size 1/8, 1/4
# Look at
# https://www.codeproject.com/Articles/210979/Fast-optimizing-rectangle-packing-algorithm-for-bu
# for way to simply arrange the rectangles efficiently

SPACING = 1.0 # 1" spacing
SHEETWIDTH = 48.0

# SVG units are: in, cm, mm

# redefine classes if reloading
[:Node, :SvgOut, :LayoutTransformer, :ShaperSVG,
 :Edge, :Loop, :InnerLoop, :OuterLoop].each { |x|
  begin
    Object.send(:remove_const, x)
  rescue => exception
    true
  end
}


# Simple Node object to construct SVG XML output (no built in support for XML in ruby)
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

# Class used to collect the output paths to be emitted as SVG
#
# == Methods to set up the SvgOut
#
# +new(minx, miny, maxx, maxy, unit)+ - set up the extents and units for th SVG output
# +path(...)+ - add exterior and interior paths representing cuts
#
# == Write SVG output
# +write(file)+
#
# Embody +parameters+ or +options+ in Teletype Text tags.
class SvgOut
  def initialize(minx, miny, maxx, maxy, unit)
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
                                    'shaper:sketchupaddin': SHAPERADDIN_VERSION
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


## open path cut
class Edge; def initialize(points); @points = points; end; end

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

def create(points: nil, arcparms: nil, inner: false)
  if inner
    l = InnerLoop.new(points)
  else
    l = OuterLoop.new(points)
  end
  l
end

class LayoutTransformer
  # Transform the points in a face loop, and find the min,max x,y in
  #   the z=0 plane
  def initialize()
    @loops = []                                 # Array of loops
    @xform = nil
    @layoutx, @layouty, @rowheight = [0.0, 0.0, 0.0]
    @arcs = []
    @grps = []
    @currgrp = nil
    self.reset_face_extents
  end

  def write(file)
    svg = SvgOut.new(@minx, @miny, @maxx, @maxy, INCHES)
    svg.title('Title')                 
    svg.desc('Description')
    @loops.each { |loop| UI.messagebox loop; svg.path(loop.svgdata, loop.attributes) }
    svg.write(file)
  end

  # TODO set_face - make a grp, a transform and a rotation
  def set_transform(grp, t)
    @currgrp = grp.entities.add_group()
    @grps << @currgrp
    @xform = t
  end

  def set_rotation(r)
    @rotation = r
  end

  def reset_face_extents()
    # Use layout to scan min max x and y for each loop
    @minx, @miny, @maxx, @maxy = [1e100, 1e100, -1e100,-1e100]
    @arcs = []
  end

  def increment_layout()
    @layoutx = SPACING + @maxx - @minx
    # As each element is layed out horizontally, keep track of the tallest bit
    @rowheight = [@rowheight, @maxy - @miny].max
    if @layoutx > SHEETWIDTH
      @layoutx = 0.0
      @layouty += @rowheight
      @rowheight = 0
    end
  end
  
  def transform(grp, edge, get_extents: false)
    
    pstart = edge.start.position.transform!(@xform)
    # Keep track of the bounds of the loop after transform
    # See also Curve.first_edge and Curve.last_edge
    if edge.curve and edge.curve.is_a?(Sketchup::ArcCurve)
      
      # Many edges (line segments) are part of one ArcCurve, process once
      if not @curves.member?(edge.curve)
        @curves << edge.curve
        # transform the arc curve parameters (center, x-axis, z-axis) into z=0 plane
        # radius and start, end angle invariant (maybe issue with angles)
        center = edge.curve.center.transform!(@xform)
        normal = edge.curve.normal.transform!(@rotation)  # should be [0,0,1]
        UI.messagebox normal.to_s
        xaxis  = edge.curve.xaxis.transform!(@rotation)  # transformed xaxis
        
        firstedge = @currgrp.entities.add_arc(
          center, normal, xaxis,
          edge.curve.radius, edge.curve.start_angle, edge.curve.end_angle)[0]
        xf_ret = firstedge.curve # return the created Sketchup::ArcCurve
      end
    else
      pend = edge.end.position.transform!(@xform)
      xf_ret = @currgrp.entities.add_edges([pstart,pend])[0] # return the created Sketchup::Edge
        
    # Get extents from all edges, including segments in an arc
    if get_extents
      @minx = pstart[0] if pstart[0] < @minx
      @miny = pstart[1] if pstart[1] < @miny
      @maxx = pstart[0] if pstart[0] > @maxx
      @maxy = pstart[1] if pstart[1] > @maxy
    end
  end
  
  def makeLoop(grp, points, inner: false)
    points.each { |p| self.move p }
    points << points[0]                           # close loop
    g = grp.entities.add_group()
    g.entities.add_edges(points)

    ### TODO separate the transformation and grouping of the cutting paths
    ### from the creation of the transformed loops for SVG output
    ### Let the designer interact with the created cutting paths before emitting
    ### SVG, say to change layout or delete items to be cut...
    @loops << create( points: points, inner: inner ) 
  end
  
  def move(p)
    p[0] = p[0] - @minx + @layoutx
    p[1] = p[1] - @miny + @layouty
  end
end

class ShaperSVG
  def initialize
    @out_filename = '/Users/mgreenberg/example.svg'
    @segments = true
    @text = true
  end

  def shapersvg_2d_layout
    lt = LayoutTransformer.new
    Sketchup::active_model.selection.each { |s| self.process(s, lt) }
    File.open(@out_filename,'w') do |f|
      lt.write(f)
    end
  rescue => exception
    puts exception.backtrace.reject(&:empty?).join("\n**")
    puts  exception.to_s
    
    UI.messagebox exception.backtrace.reject(&:empty?).join("\n**")
    UI.messagebox exception.to_s
    raise
  end
  
  def shapersvg_settings
    puts "hello export_settings"
    inputs = UI.inputbox(
      ["Output filename", "Segments", "Text"],
      [@out_filename, @segments, @text],
      ["","on|off","on|off"],
      "---------- SVG Export Settings -----------")
    @out_filename, @segments, @text = inputs if inputs
  end
  
  # Do this in a more clever way later, adding different ones to ArcCurve, Curve, etc...
  def emit_closed_path(loop, file, xform)
    loop.edges.each { |edge|

      if edge.curve and edge.curve.is_a?(Sketchup::ArcCurve)
        puts 'Edge %s is a circular arc' % [edge]
        
      # file.write describe_sketchup_arc(edge.curve)
      else
        puts 'Edge start %s  -- Edge end %s' % [edge.start.position, edge.end.position]
        s,e = edge.start.position.transform(xform), edge.end.position.transform(xform)
        file.write 'Edge start %s  -- Edge end %s' % [s,e]
      end
    }
  end

  def process(elt, xformer)
    puts "process #{elt}"
    if elt.is_a?(Sketchup::Group)
      # Recurse down into groups to find faces in selected groups
      elt.entities.each { |e| self.process(e, xformer) }
    elsif elt.is_a?(Sketchup::Face)
      face = elt
      puts "processing #{face}"
      # For each face, reset the face extents LayoutTransformer
      xformer.reset_face_extents
      grp = Sketchup::active_model.entities.add_group()
      # Set the transfrom matrix for all the loops (outer and inside cutouts) on face
      # Transforms onto z=0 plane
      xformer.set_transform(Geom::Transformation.new(face.bounds.min, face.normal).inverse)
      xformer.set_rotation(Geom::Transformation.new([0,0,0], face.normal).inverse)

      # Use the outer loop to get the bounds
      entities = face.outer_loop.edges.map { |edge|
        xformer.transform(edge, get_extents: true)
      }
      xformer.makeLoop(grp, entities)

      # For any inner loops, don't recalculate the extents
      face.loops.each { |loop|
        if not loop.equal?(face.outer_loop)
          entities = loop.edges.map { |edge|
            xformer.transform(edge)
          } 
          xformer.makeLoop(grp, entities, inner: true)
        end
      }

      xformer.increment_layout
      
    else
      puts "process: skipping #{elt}"
    end
  end
end



# TODO figure out how to use modules so module reload works without sketchup restart

unless file_loaded?(__FILE__)

  menu = UI.menu('Plugins')
  menu.add_item('ShaperSVG 2D Layout') {
    ShaperSVG.new.shapersvg_2d_layout
  }
  menu.add_item('ShaperSVG Settings') {
    ShaperSVG.new.shapersvg_settings
  }
  
  UI.messagebox "Loaded #{__FILE__}", MB_OK
  file_loaded(__FILE__)
end
