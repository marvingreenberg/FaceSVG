###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'

# Provides SVG module with SVG::Canvas class
load 'shapersvg/svg.rb'

# $uStrings = LanguageHandler.new("shaperSVG")
# extensionSVG = SketchupExtension.new $uStrings.GetString("shaperSVG"), "shapersvg/shapersvg.rb"
# extensionSVG.description=$uStrings.GetString("Create SVG files from faces")
# Sketchup.register_extension extensionSVG, true

# Sketchup API is a litle strange - many operations create edges, but actually maintain a higher resolution 
#   circular or elliptical arc.  Still need to figure out various transforms, applied to shapes


# SVG units are: in, cm, mm
INCHES = 'in'
CM = 'cm'
MM = 'mm'

module ShaperSVG
module Layout

SHAPER = 'shaper'
PROFILEKIND = 'profilekind'
PK_INNER = 'inner'
PK_OUTER = 'outer'
PK_GUIDE = 'guide'

class Transformer
  # Transform the points in a face loop, and find the min,max x,y in
  #   the z=0 plane
  def initialize()
    self.clear()
  end
  
  def clear()
    @loops = []                                 # Array of loops
    @xform = nil
    @layoutx, @layouty, @rowheight = [0.0, 0.0, 0.0]
    @grps = []
    @curves = []
    @facegrp = nil
    @profilegrp = nil
    @minx, @miny, @maxx, @maxy = [1e100, 1e100, -1e100,-1e100]
    @viewport = [0.0, 0.0, -1e100, -1e100] # maxx, maxy of viewport updated in layout_facegrp
    @selected_model_faces = []
  end
  def profilegrp
    if (not @profilegrp) or not @profilegrp.valid?
      @profilegrp = Sketchup::active_model.entities.add_group()
      @profilelayer = Sketchup::active_model.layers.add('Cut Profile')
      @profilegrp.layer = @profilelayer
    end
    @profilegrp
  end
  
  def reset()
    if @profilegrp && @profilegrp.valid?  # hasn't been deleted manually
      Sketchup.active_model.entities.erase_entities @profilegrp
    end
    self.clear
  end
  
  def mark_face(selections)
    selections.each { |face|
      if face.is_a? Sketchup::Face 
        if @selected_model_faces.member?(face)
          @selected_model_faces.delete(face)
          face.material = nil
        else
          face.material = "Black"
          @selected_model_faces << face
        end
      end
    }
  end

  def write(file)
    svg = ShaperSVG::SVG::Canvas.new(@viewport, INCHES, ShaperSVG::ADDIN_VERSION)
    svg.title('Title')                 
    svg.desc('Description')
    @loops.each { |loop| svg.path(loop.svgdata, loop.attributes) }
    svg.write(file)
  end

  def change_face(face)
    # Reset face extents, update extents as outer loop elements are transformed
    @minx, @miny, @maxx, @maxy = [1e100, 1e100, -1e100,-1e100]
    @facegrp = self.profilegrp.entities.add_group()
    # Set the transfrom matrix for all the loops (outer and inside cutouts) on face
    # Transforms onto z=0 plane
    @xform = Geom::Transformation.new(face.bounds.min, face.normal).inverse
    @grps << @facegrp
  end

### http://ruby.sketchup.com/Sketchup/Entities.html#transform_entities-instance_method
### Important note: If you apply a transformation to entities that are
### not in the current edit context (i.e. faces that are inside a
### group), SketchUp will apply the transformation incorrectly
### COMMENT: maybe doesn't matter, everything is relative?  Maybe use groups cleverly?
### transform the group, not the edges, arcs inside?
  def layout_facegrp()
    # After the bounds of the outer loop are calculated, layout the paths (inner and outer) 
    xf = Geom::Transformation.new( [ @layoutx - @minx, @layouty - @miny, 0.0] )
    @profilegrp.entities.transform_entities(xf, @facegrp)

    @layoutx += SPACING + @maxx - @minx
    @viewport[2] = [@viewport[2],@layoutx].max
    # As each element is layed out horizontally, keep track of the tallest bit
    @rowheight = [@rowheight, @maxy - @miny].max
    if @layoutx > SHEETWIDTH
      @layoutx = 0.0
      @layouty += @rowheight
      @rowheight = 0.0
    end
    # Adjust the x, y max for viewport as each face is laid out
    @viewport[3] = [@viewport[3],@layouty+@rowheight].max
    @viewport[2] = [@viewport[2],@layoutx].max



  end


  def to_z0(face)
    Geom::Transformation.new(face.bounds.min, face.normal).inverse
  end

  def doxf(xf)
    Sketchup::active_model.entities.transform_entities(xf, Sketchup::active_model.selection.to_a ); end

  def area(); "Area %s Perim %s" % [Sketchup::active_model.selection[0].area, Sketchup::active_model.selection[0].edges.map { |e| e.length }.reduce( &:+ )]; end

  # Re: Adding objects into a group/component
  # Sketchup API documentation is embarrassingly TERRIBLE
#Try
#group.entities.add_instance(other_group.entities.parent, other_group.transformation*group.transformation)
#other_group.entities.parent.instances[1].material=other_group.material
#other_group.entities.parent.instances[1].layer=other_group.layer
### you can also copy over other attributes of 'other_group' if appropriate

  def transform(edges, outer: false)
    # Create a group for the duplicated edges
    pathgrp = @facegrp.entities.add_group()
    # Duplicate the face edges. map returns single edges as [edge] and arcs as [edge,edge,...]
    #  plus nils for subsequent arc edges - this all to maintain the arc metadata - then joined at end
    # with reduce()
    dupedges = edges.map { |edge|
      if edge.curve and edge.curve.is_a?(Sketchup::ArcCurve)
        ell_orig = edge.curve
        # FIRST edge in an arc retrieves arc metadata and regenerates ALL arc edges,
        # Subsequent arc edges ignored, returning nil
        if not @curves.member?(ell_orig)
          @curves << ell_orig
          # Take unit circle, apply ellxform to duplicate original arc...
          # start, end angle invariant
          elledges = pathgrp.entities.add_arc(
            ORIGIN, X_AXIS, Z_AXIS, 1.0, ell_orig.start_angle, ell_orig.end_angle)
          ellxform = Geom::Transformation.new(
            ell_orig.xaxis.to_a + [0.0] +  ell_orig.yaxis.to_a + [0.0] +
            ell_orig.normal.to_a + [0.0] + ell_orig.center.to_a + [1.0])
          pathgrp.entities.transform_entities(ellxform, elledges)
          # ... then transform it onto z=0 plane (could combine as product of two transforms...)
          elledges
        else
          nil
        end
      else
        xf_edges = pathgrp.entities.add_edges([edge.start.position, edge.end.position])
      end
    }.reject(&:nil?).reduce(&:+)

    # Then transform to z=0 using common face xform
    pathgrp.entities.transform_entities(@xform, dupedges)

    # Find the bounds of the loop after transform
    if outer
      dupedges.each { |e| 
        x,y = e.start.position[0], e.start.position[1]
        @minx = [x, @minx].min
        @miny = [y, @miny].min
        @maxx = [x, @maxx].max
        @maxy = [y, @maxy].max
      }
    end
    # Maybe something like  this is useful
    # dupedges.each {
    #    |e| e.set_attribute(SHAPER, PROFILEKIND, outer ? PK_OUTER : PK_INNER)
    # }

    # Group the edges into single line edges, and
    # arrays of ArcCurve edges
    groupedEdges = dupedges.map { |edge|
      if edge.curve and edge.curve.is_a?(Sketchup::ArcCurve)
        if not @curves.member?(edge.curve)
          nil  # return nil for subsequent edges from same ArcCurve
        else
          @curves.pop(edge.curve)  # process ArcCurve once, returning edges as an array
          edge.curve.edges  # return arc as multi-element array of edges
        end
      else
        [ edge ]   # Return line as 1-element array of edges
      end
    }.reject(&:nil?)
    
  end

  def process_selection()
    @selected_model_faces.each { |elt|
      # Test for group is dead code from earllier iterations...
      if elt.is_a?(Sketchup::Group)
        # Recurse down into groups to find faces in selected groups
        elt.entities.each { |e| self.process(e) }
      elsif elt.is_a?(Sketchup::Face)
        face = elt
        puts "processing #{face}"
        # For each face, reset the face extents and set up transforms
        self.change_face(face)

        # Use the outer loop to get the bounds
        # TODO separate SVG generation from layout.  Probably means
        #  passing @facegrp to Loop::create and not maintaining so
        # much info in transform()

        # Return array of edge arrays.  If edge array size>1 it is an arc
        edges_arr = self.transform(face.outer_loop.edges, outer: true)

        # After outerloop is calculated, can layout the whole facegrp
        # which calculates the facegrp transformation.  All the path loops
        # are in the facegroup
        self.layout_facegrp()

        ### TODO separate the transformation and grouping of the cutting paths
        ### from the creation of the transformed loops for SVG output
        ### Let the designer interact with the created cutting paths before emitting
        ### SVG, say to change layout or delete items to be cut...
        @loops << ShaperSVG::SVG::Loop.create(
          @facegrp.transformation, edges_arr, outer: true)

        # For any inner loops, don't recalculate the extents
        face.loops.each { |loop|
          if not loop.equal?(face.outer_loop)
            edgesarr = self.transform(loop.edges)
            @loops << ShaperSVG::SVG::Loop.create(
              @facegrp.transformation, edgesarr, outer: false)          
          end
        }
      end
    }
  end
end


end
end
