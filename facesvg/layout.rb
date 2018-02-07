###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'

# Provides SVG module with SVG::Canvas class
Sketchup.require('facesvg/svg')
Sketchup.require('facesvg/util')

# i = Sketchup::active_model.options['UnitsOptions']['LengthUnit']
# unit = ['in','ft','mm','cm','m'][i]

module FaceSVG
  # SVG units are: in, cm, mm... all these are unused for now, except INCHES
  INCHES = 'in'.freeze
  CM = 'cm'.freeze
  MM = 'mm'.freeze
  SHAPER = 'shaper'.freeze
  PROFILE_KIND = 'profilekind'.freeze
  PROFILE_DEPTH = 'profiledepth'.freeze
  PK_INNER = 'inner'.freeze
  PK_OUTER = 'outer'.freeze
  PK_POCKET = 'pocket'.freeze # TTD
  PK_GUIDE = 'guide'.freeze

  module Layout
    # The ordering of edges in sketchup face boundaries seems
    # arbitrary, make predictable Start at arbitrary element, order
    # edges/arcs with endpoints like (e0,e1),(e1,e2),(e2,e3)...(eN,e0)
    def self.reorder(elements)
      # Start at some edge/arc
      ordered = [elements[0]]
      elements.delete_at(0)

      until elements.empty?
        prev_elt = ordered[-1]
        elements.each_with_index do |g, i|
          if connected(ordered, prev_elt, g)
            elements.delete_at(i)
            break
          end
          if i == (elements.size - 1) # at end
            raise format('Unexpected: No edge/arc connected %s to at %s',
                         prev_elt, FaceSVG.pos_s(prev_elt.endpos))
          end
        end
      end
      ordered
    end

    def self.connected(ordered, prev_elt, glob)
      if FaceSVG.samepos(prev_elt.endpos, glob.startpos)
        ordered << glob
        true
      elsif FaceSVG.samepos(prev_elt.endpos, glob.endpos)
        ordered << glob.reverse
        true
      else
        false
      end
    end

    ########################################################################
    # These "elements" collect the edges for an arc with metadata and
    # control to reverse orientation.  Lines just have an edge
    # Many edges are in one arc, so ignore later edges in a processed arc
    class Arc
      def initialize(edge)
        @startpos = edge.curve.first_edge.start.position
        @endpos = edge.curve.last_edge.end.position
        @is_arc = true
        FaceSVG.dbg('Transform path %s', self)
      end
      attr_reader :is_arc
      attr_reader :startpos
      attr_reader :endpos

      def inspect
        format('Arc %s->%s%s', FaceSVG.pos_s(startpos), FaceSVG.pos_s(endpos))
      end
      def reverse
        @startpos, @endpos = [@endpos,@startpos]
        self
      end
      def self.make(curves, edge)
        # return nil if line, or already processed curve containing edge
        return nil if edge.curve.nil? || curves.member?(edge.curve)
        curves << edge.curve
        Arc.new(edge)
      end
    end
    ########################################################################
    class Line
      def initialize(edge)
        @startpos = edge.start.position
        @startpos = edge.end.position
        @is_arc = false
        FaceSVG.dbg('Transform path %s', self)
      end
      attr_reader :is_arc
      attr_reader :startpos
      attr_reader :endpos

      def inspect
        format('Edge %s->%s%s', FaceSVG.pos_s(startpos), FaceSVG.pos_s(endpos))
      end
      def reverse
        @startpos, @endpos = [@endpos,@startpos]
        self
      end
      def self.make(edge)
        # exit if edge is part of curve
        return nil unless edge.curve.nil?
        Line.new(edge)
      end
    end

    ########################################################################
    class ProfileCollection
      # Used to transform the points in a face loop, and find the min,max x,y in
      #   the z=0 plane
      def initialize(title)
        super()
        @title = title
        reset()
      end

      def size
        @facemap.size
      end

      def reset
        if su_profilegrp(create: false)
          FaceSVG.dbg('Remove %s', @su_profilegrp)
          Sketchup.active_model.entities.erase_entities @su_profilegrp
        end

        # Use a map to hold the faces, to allow for an observer to update the map
        #  if groups are manually deleted
        @su_profilegrp = nil # grp to hold all the SU face groups

        # Information to manage the layout
        @layoutx, @layouty, @rowheight = [FaceSVG.spacing, FaceSVG.spacing, 0.0]
        @viewport = [0.0, 0.0, -1e100, -1e100] # maxx, maxy updated in layout_facegrp
      end

      ################
      # Find or create the group for the profile entities
      ################
      PROFILE_GROUP = 'SVG Profile Group'.freeze
      def su_profilegrp(create: true)
        return @su_profilegrp if @su_profilegrp && @su_profilegrp.valid?
        @su_profilegrp = Sketchup::active_model.entities.grep(Sketchup::Group)
                                 .find { |g| g.name==PROFILE_GROUP && g.valid? }
        return @su_profilegrp if @su_profilegrp
        # None existing, create (unless flag false)
        return nil unless create
        @su_profilegrp = Sketchup.active_model.entities.add_group()
        @su_profilelayer = Sketchup.active_model.layers.add('SVG Profile')
        @su_profilegrp.layer = @su_profilelayer
        @su_profilegrp.name = PROFILE_GROUP
        @su_profilegrp
      end

      def add_su_facegrp(facegrp)
        # Add new element to existing facegroup by recreating the group
        @su_profilegrp = Sketchup.active_model.entities
                                 .add_group(su_profilegrp.explode + [facegrp])
        @su_profilegrp.name = 'profile group'
      end
      ########################################################################
      def captureFace(su_face)
        # Add them all to a group to copy, and duplicate it
        tmpgrp = Sketchup.active_model.entities.add_group([su_face])
        su_facegrp = Sketchup.active_model.entities
          .add_instance(tmpgrp.definition, tmpgrp.transformation)
        su_facegrp.name= 'su_facegrp'
        # revert the temporary face group
        tmpgrp.explode

        # Get the (single) face from the transformed, copied group
        @su_face = @su_facegrp.entities.select { |f| f.is_a?(Sketchup::Face) }[0]

        # Transform face onto z=0 plane, to origin in group reference frame
        #   (maybe not +xy quadrant?)
        # xf = Geom::Transformation.new(su_face.bounds.min, su_face.normal).inverse
        xf = Geom::Transformation.new(ORIGIN, @su_face.normal).inverse
        @su_facegrp.entities.transform_entities(xf, @su_face)

        # TODO: may need to use the bounds to transform to +xy quadrant
        # TODO: issues with reflections?
        self.layout_facegrp(self, @su_face.bounds)
      end

      def svgpaths(svg, face)
        face.loops.each do |loop|
          attrs = loop.attribute_dictionary 'facesvg'
          kind = attrs[PROFILE_KIND]
          depth = attrs[PROFILE_DEPTH] # pocket profiles have a depth
          FaceSVG.dbg('Profile, %s edges, %s %s',
                      loop.edges.size, kind, depth)
          # reorganize edges so arc edges are grouped with metadata
          #   and all are ordered end to start
          curves = [] # Keep track of processed arcs
          pathparts = loop.edges.map { |edge|
            Arc.create(curves, edge) || Line.create(edge)
          }.reject(&:nil?)
          pathparts = FaceSVG::Layout.reorder(pathparts)
          svgloop = FaceSVG::SVG::Loop.create(pathparts, kind, depth)
          svg.path(svgloop.svgdata, svgloop.attributes)
        end
      end

      ################
      def write
        filepath = UI.savepanel(
          'SVG output file', FaceSVG::default_dir, "#{@title}.svg"
        )
        return false if filepath.nil?
        FaceSVG::default_dir = File.dirname(filepath)
        svg = FaceSVG::SVG::Canvas.new(@viewport, INCHES, FaceSVG::version)
        svg.title(format('%s cut profile', @title))
        svg.desc(format('Shaper cut profile from Sketchup model %s', @title))

        su_profilegrp.entities.grep(Sketchup::Group).each do |g|
          g.entities.grep(Sketchup::Face).each do |f|
            svgpaths(svg, face)
          end
        end
        File.open(filepath, 'w') do |file|
          svg.write(file)
        end
      end

      # Maybe something like  this is useful
      # edges.each {
      #    |e| e.set_attribute(SHAPER, PROFILEKIND, outer ? PK_OUTER : PK_INNER)
      # }

      ################################
      def layout_facegrp(faceprofile, bounds)
        minx = bounds.min.x
        maxx = bounds.max.x
        miny = bounds.min.y
        maxy = bounds.max.y
        FaceSVG.dbg('Face bounds,  %s %s to %s,%s,0',
                    bounds.min, bounds.max, @layoutx, @layoutx)
        # After the bounds of the outer loop are calculated, transform face layout
        # by moving the group containing the paths (inner and outer)
        facegrp = faceprofile.su_facegrp
        add_su_facegrp(facegrp)

        layout_xf = Geom::Transformation
                    .new([@layoutx - minx, @layouty - miny, 0.0])
        su_profilegrp.entities.transform_entities(layout_xf, facegrp)

        @layoutx += FaceSVG::spacing + maxx - minx
        @viewport[2] = [@viewport[2], @layoutx].max
        # As each element is layed out horizontally, keep track of the tallest bit
        @rowheight = [@rowheight, maxy - miny].max
        if @layoutx > FaceSVG::sheetwidth
          @layoutx = 0.0 + FaceSVG::spacing
          @layouty += @rowheight + FaceSVG::spacing
          @rowheight = 0.0
        end
        # Adjust the x, y max for viewport as each face is laid out
        @viewport[3] = [@viewport[3], @layouty + @rowheight].max
        @viewport[2] = [@viewport[2], @layoutx].max
      end

      ################################
      def process_selection
        Sketchup.active_model.start_operation(FaceSVG::LAYOUT_SVG)
        Sketchup.active_model.selection(&:valid?).grep(Sketchup::Face).each do |f|
          # Capture the face and copy it to the profile group
          captureFace(f)
        end
        Sketchup.active_model.commit_operation()
      end
    end
  end
end
