###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'

UI.messagebox "Starting load"

# Provides SVG module with SVG::Canvas class
require 'shapersvg/svg'

UI.messagebox "Loaded SVG module"

# $uStrings = LanguageHandler.new("shaperSVG")
# extensionSVG = SketchupExtension.new $uStrings.GetString("shaperSVG"), "shapersvg/shapersvg.rb"
# extensionSVG.description=$uStrings.GetString("Create SVG files from faces")
# Sketchup.register_extension extensionSVG, true

# Sketchup API is a litle strange - many operations create edges, but actually maintain a higher resolution 
#   circular or elliptical arc.  Still need to figure out various transforms, applied to shapes
# https://stackoverflow.com/questions/11503558/how-to-undefine-class-in-ruby

# SVG units are: in, cm, mm
INCHES = 'in'
CM = 'cm'
MM = 'mm'

# https://www.codeproject.com/Articles/210979/Fast-optimizing-rectangle-packing-algorithm-for-bu
# for way to simply arrange the rectangles efficiently

module ShaperSVG
module Layout

class Transformer
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
    svg = ShaperSVG::SVG::Canvas.new(@minx, @miny, @maxx, @maxy, INCHES, ShaperSVG::ADDIN_VERSION)
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

  def move(p)
    p[0] = p[0] - @minx + @layoutx
    p[1] = p[1] - @miny + @layouty
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
    @loops << SVG.createLoop( points: points, inner: inner ) 
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

    end
    # Get extents from all edges, including segments in an arc
    if get_extents
      @minx = pstart[0] if pstart[0] < @minx
      @miny = pstart[1] if pstart[1] < @miny
      @maxx = pstart[0] if pstart[0] > @maxx
      @maxy = pstart[1] if pstart[1] > @maxy
    end
  end
    
  def process(elt)
    puts "process #{elt}"
    if elt.is_a?(Sketchup::Group)
      # Recurse down into groups to find faces in selected groups
      elt.entities.each { |e| self.process(e) }
    elsif elt.is_a?(Sketchup::Face)
      face = elt
      puts "processing #{face}"
      # For each face, reset the face extents
      self.reset_face_extents
      grp = Sketchup::active_model.entities.add_group()
      # Set the transfrom matrix for all the loops (outer and inside cutouts) on face
      # Transforms onto z=0 plane
      self.set_transform(Geom::Transformation.new(face.bounds.min, face.normal).inverse)
      self.set_rotation(Geom::Transformation.new([0,0,0], face.normal).inverse)

      # Use the outer loop to get the bounds
      entities = face.outer_loop.edges.map { |edge|
        self.transform(edge, get_extents: true)
      }
      self.makeLoop(grp, entities)

      # For any inner loops, don't recalculate the extents
      face.loops.each { |loop|
        if not loop.equal?(face.outer_loop)
          entities = loop.edges.map { |edge|
            self.transform(edge)
          } 
          self.makeLoop(grp, entities, inner: true)
        end
      }

      self.increment_layout
      
    else
      puts "process: skipping #{elt}"
    end
  end
end


end
end
