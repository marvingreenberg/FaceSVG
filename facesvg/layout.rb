###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'

# Provides SVG module with SVG::Canvas class
Sketchup.require('facesvg/constants')
Sketchup.require('facesvg/su_util')
Sketchup.require('facesvg/svg')

module FaceSVG
  module Layout
    ################
    extend self

    class ProfileCollection
      # Used to transform the points in a face loop, and find the min,max x,y in
      #   the z=0 plane
      def initialize()
        reset()
      end
      ################
      # TODO: Use a map to hold the faces??,
      #   to allow for an observer to update the layout if elements are deleted
      def reset
        # UI: reset the layout state and clear any existing profile group
        FaceSVG.su_close_active()
        if existing_profilegrp
          FaceSVG.dbg('Remove %s', @profilegrp)
          Sketchup.active_model.entities.erase_entities @profilegrp
        end
        @profilegrp_id = 0
        nextgrp()
        @profilegrp = nil # grp to hold current the SU face group
        # Information to manage the layout, maxx, maxy updated in layout_facegrp
        @layoutx, @layouty, @rowheight = [CFG.layout_spacing, CFG.layout_spacing, 0.0]
      end

      def nextgrp
        @profilegrp_id += 1
        @current_profilegrp_name = PROFILE_GROUP + @profilegrp_id.to_s
        # @profilegrp_list = []  #unused for now
      end

      ################
      def makesvg(name, modelname, *grps)
        bnds = Bounds.new.update(*grps)
        viewport = [bnds.min.x, bnds.min.y, bnds.max.x, bnds.max.y]
        svg = SVG::Canvas.new(name, viewport, CFG.units)

        svg.title(format('%s cut profile', modelname))
        svg.desc(format('Shaper cut profile from Sketchup model %s', modelname))

        grps.each do |g|
          # Get a surface (to calculate pocket offset if needed)
          faces = g.entities.grep(Sketchup::Face)
          surface = faces.find { |f| f.material == FaceSVG.surface }
          # Use transform if index nil? - means all svg in one file, SINGLE  TODO: figure out WTF this means
          faces.each { |f| svg.add_paths(g.transformation, f, surface) }
        end
        svg
      end
      ################
      def write
        # UI: write any layed out profiles as svg
        existing = existing_profilegrp
        return unless existing
        grps = existing.entities.grep(Sketchup::Group)

        # TODO: sort out where and when title is assigned
        modelname = Sketchup.active_model.name

        # single_file - generate one "svg::Canvas" with all face grps
        outpath = UI.savepanel(SVG_OUTPUT_FILE,
                               CFG.default_dir, "#{modelname}.svg")
        return false if outpath.nil?
        CFG.default_dir = File.dirname(outpath)
        name = File.basename(outpath)

        File.open(outpath, 'w') do |file|
          svg = makesvg(name, modelname, *grps)
          svg.write(file)
        end
      end
      ################
      def process_selection(selset)
        # UI: process any selected faces and lay out into profile grp
        layout_facegrps(*selset.select(&:valid?).grep(Sketchup::Face))
      end

      ################
      def existing_profilegrp()
        # Return nil or the existing group for the profile entities
        return @profilegrp if @profilegrp && @profilegrp.valid?
        @profilegrp = Sketchup::active_model.entities.grep(Sketchup::Group)
                              .find { |g| g.name == @current_profilegrp_name && g.valid? }
        return @profilegrp if @profilegrp
        # None existing
      end
      def create_profilegrp()
        existing = existing_profilegrp()
        return existing if existing
        @profilegrp = Sketchup.active_model.entities.add_group()
        FaceSVG.dbg('Set name for %s to >>%s<<', @profilegrp, @current_profilegrp_name)
        @profilegrp.name = @current_profilegrp_name
        FaceSVG.dbg('Create %s (%s,%s)', @profilegrp, @current_profilegrp_name, @profilegrp.name)
      end
      ################
      def empty?
        existing_profilegrp.nil?
      end
      ################
      def add_su_facegrp(facegrp)
        # Add new element to existing profile group by recreating the group
        create_profilegrp
        @profilegrp.layer = Sketchup.active_model.layers[0]
        grp_name = @profilegrp.name
        @profilegrp = Sketchup.active_model.entities
                              .add_group(@profilegrp.explode + [facegrp])
        @su_profilelayer = Sketchup.active_model.layers.add(PROFILE_LAYER)
        @profilegrp.name = grp_name
        @profilegrp.layer = @su_profilelayer
      end
      ################
      def layout_facegrps(*su_faces)
        FaceSVG.capture_faceprofiles(*su_faces) do |new_entities, bnds|
          layout_xf = Geom::Transformation
                      .new([@layoutx, @layouty, 0.0])
          # explode, work around more weird behavior with Arcs?
          # Transform them and then add them back into a group
          Sketchup.active_model.entities.transform_entities(layout_xf, new_entities)

          create_profilegrp
          newgrp = @profilegrp.entities.add_group(new_entities)
          FaceSVG.dbg('Face %s  layout x,y %s %s', bnds, @layoutx, @layoutx)

          # Handle automatic corner relief
          if CFG.corner_relief == CR_SYMMETRIC_AUTO
            surface_faces = new_entities.grep(Sketchup::Face)
                                        .select { |f| f.material == FaceSVG.surface }
            Relief.relieve_face_corners(*surface_faces, CFG.bit_diameter/2, auto: true)
          end

          add_su_facegrp(newgrp)

          @layoutx += CFG.layout_spacing + bnds.width
          # As each element is layed out horizontally, keep track of the tallest bit
          @rowheight = [@rowheight, bnds.height].max
          if @layoutx > CFG.layout_width
            @layoutx = 0.0 + CFG.layout_spacing
            @layouty += @rowheight + CFG.layout_spacing
            @rowheight = 0.0
          end
        end
      end
    end
  end
end
