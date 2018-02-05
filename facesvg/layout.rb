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
        @edge = edge
        @curve = edge.curve
        @is_arc = true
        FaceSVG.dbg('Transform path %s', self)
      end
      attr_reader :is_arc

      def inspect
        format('Arc %s->%s%s', FaceSVG.pos_s(startpos), FaceSVG.pos_s(endpos), @reverse ? 'R' : '')
      end

      def startpos
        @reverse ? @curve.last_edge.end.position : @curve.first_edge.start.position
      end

      def endpos
        @reverse ? @curve.first_edge.start.position : @curve.last_edge.end.position
      end

      def reverse
        @reverse = true
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
        @edge = edge
        @is_arc = false
        FaceSVG.dbg('Transform path %s', self)
      end
      attr_reader :is_arc

      def inspect
        format('Edge %s->%s%s',
               FaceSVG.pos_s(startpos), FaceSVG.pos_s(endpos), @reverse ? 'R' : '')
      end

      def startpos
        @reverse ? self[0].end.position : self[0].start.position
      end

      def endpos
        @reverse ? self[0].start.position : self[0].end.position
      end

      def reverse
        @reverse = true
        self
      end

      def self.make(edge)
        # exit if edge is part of curve
        return nil unless edge.curve.nil?
        Line.new(edge)
      end
    end
    ########################################################################
    class MyEntitiesObserver < Sketchup::EntitiesObserver
      def onElementRemoved(_entities, entity_id)
        FaceSVG.dbg("onElementRemoved: #{entity_id}")
      end
    end
    # entities.add_observer, remove_observer
    ########################################################################
    class FaceProfile
      def self.annotate_loop(loop); end

      def initialize(profilecollection, su_face)
        # Find the face and all its edges
        # Also find edges that are not loops, on the face
        # these would be all edges, not part of boundary, that are normal to the
        # face normal...
        @paths = []

        # Add them all to a group to copy, and duplicate it
        tmpgrp = Sketchup.active_model.entities.add_group([su_face] + su_face.edges)
        @su_facegrp = Sketchup.active_model.entities
                              .add_instance(tmpgrp.definition, tmpgrp.transformation)
        @su_facegrp.name= 'su_facegrp'
        # revert the temporary face group
        tmpgrp.explode

        # Get the (single) face from the transformed, copied group
        @su_face = @su_facegrp.entities.select { |f| f.is_a?(Sketchup::Face) }[0]
        # Transform face onto z=0 plane, to origin in group reference frame
        #   (maybe not +xy quadrant?)
        # @xform = Geom::Transformation.new(su_face.bounds.min, su_face.normal).inverse
        @xform = Geom::Transformation.new(ORIGIN, su_face.normal).inverse
        @su_facegrp.entities.transform_entities(@xform, @su_face)

        # TODO: may need to use the bounds to transform to +xy quadrant
        # TODO: issues with reflections

        profilecollection.layout_facegrp(self, @su_face.bounds)
      end

      def createloops()
        @su_face.loops.each do |loop|
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
          FaceSVG::SVG::Loop.create(pathparts, kind, depth)
        end
      end
      attr_reader :su_facegrp

      # This was needed, along with facemap, before code is/was changed to just
      #  find the group and iterate over its elements...
      def id
        @su_facegrp.guid
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
        if @su_profilegrp and @su_profilegrp.valid?
          puts format('Remove %s', @su_profilegrp)
          Sketchup.active_model.start_operation(FaceSVG::LAYOUT_SVG)
          Sketchup.active_model.entities.erase_entities @su_profilegrp
          Sketchup.active_model.commit_operation()
        end

        # Use a map to hold the faces, to allow for an observer to update the map
        #  if groups are manually deleted
        @facemap = {}
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
      ################
      def add_face_profile(id, fp)
        @facemap[id] = fp
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

        @facemap.each_value do |faceprofile|
          faceprofile.createloops().each do |loop|
            svg.path(loop.svgdata, loop.attributes)
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
        Sketchup.active_model.selection(&:valid?) .each do |elt|
          # TTD Usability improvements?
          next unless elt.is_a?(Sketchup::Face)
          face = elt

          # Create FaceProfile to hold face profile edges,  holds reference to
          # its containing ProfileCollection
          f = FaceProfile.new(self, face)
          add_face_profile(f.id, f)
        end
        Sketchup.active_model.commit_operation()
      end
    end
  end
end
