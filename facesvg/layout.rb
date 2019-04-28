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

    FACESVG_STATE = 'facesvg_state'.freeze
    LAYOUTX = 'layoutx'.freeze
    LAYOUTY = 'layouty'.freeze
    ROWHEIGHT = 'rowheight'.freeze

    def profilegrps()
      # Return the active profile groups in the model
      # Order by the @layouty (the row)
      Sketchup::active_model.entities.grep(Sketchup::Group)
              .select { |g| g.layer.name == PROFILE_LAYER && g.valid? }
              .sort_by! { |g| [g.bounds.min.y] }.to_a
    end

    class ProfileCollection
      # Used to transform the points in a face loop, and find the min,max x,y in
      #   the z=0 plane
      def initialize()
        clrgrps()
        current_profilegrp(initializing: true) # will update @profilegrp_name if any exist
      end
      def clrgrps()
        @layoutx, @layouty = [0.0, 0.0]
        @rowheight = 0.0
        @profilegrp_name = nil # Initial group. No groups
      end
      ################
      def reset
        # UI: reset the layout state and clear any existing profile group(s)
        FaceSVG.dbg('Reset facesvg')
        FaceSVG.su_close_active()
        # Delete any existing profilegrps
        FaceSVG::Layout::profilegrps().each do |g|
          FaceSVG.dbg('Remove %s', g)
          Sketchup.active_model.entities.erase_entities(g) if g.valid?
        end
        clrgrps()
      end
      ################
      def empty?()
        FaceSVG::Layout::profilegrps().size == 0
      end
      ################
      def load_attrs(grp)
        attr_dict = grp.attribute_dictionary(FACESVG_STATE, true)
        # Adjust the layout position if group is moved
        @layoutx = attr_dict[LAYOUTX] || FaceSVG::cfg().layout_spacing
        @layouty = attr_dict[LAYOUTY] || FaceSVG::cfg().layout_spacing
        @rowheight = attr_dict[ROWHEIGHT] || 0.0
        @profilegrp_name = grp.name
      end
      ################
      def updt_attrs(grp)
        grp.set_attribute(FACESVG_STATE, LAYOUTX, @layoutx)
        grp.set_attribute(FACESVG_STATE, LAYOUTY, @layouty)
        grp.set_attribute(FACESVG_STATE, ROWHEIGHT, @rowheight)
      end
      ################
      def next_grp()
        @profilegrp_name = nil
        FaceSVG.dbg('next_grp')
        # Don't make the group - issues with empty groups and SU
      end

      ################
      def current_profilegrp(initializing: false)
        grps = FaceSVG::Layout::profilegrps()
        curr = grps[-1]
        # Already current is set, or nil but not creating
        return curr if curr && curr.name == @profilegrp_name
        # load the attrs for the curr (latest existing group)
        load_attrs(curr) if curr
        # curr was nil, or name didn't match, create a new one
        curr = create_profilegrp(grps) unless initializing
        curr
      end
      ################
      def create_profilegrp(grps)
        @profilegrp_name = format('%03d FaceSVG Profile', 1 + grps.length)
        FaceSVG.dbg('create_profilegrp: "%s"', @profilegrp_name)
        next_row()
        FaceSVG.su_close_active() # Needed since want top level model
        curr = Sketchup.active_model.entities.add_group()
        curr.layer = Sketchup.active_model.layers.add(PROFILE_LAYER)
        curr.name = @profilegrp_name
        curr
      end
      ################
      def makesvg(name, modelname, *grps)
        FaceSVG.dbg('makesvg: %s %s', name, modelname)
        bnds = Bounds.new.update(*grps)
        viewport = [bnds.min.x, bnds.min.y, bnds.max.x, bnds.max.y]
        svg = SVG::Canvas.new(name, viewport, FaceSVG::cfg().units)
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
      def multi?(grps)
        is_multi = FaceSVG::cfg().multifile_mode?
        if grps.size > 1 && !is_multi
          is_multi = true
          UI.messagebox(format('Writing multiple files: found multiple groups: %s',
                               grps.map(&:name).join(', ')))
        end
        is_multi
      end

      def write()
        # UI: write any layed out profiles as svg
        modelname = Sketchup.active_model.title
        profgrps = FaceSVG::Layout::profilegrps()
        is_multi = multi?(profgrps)
        if is_multi
          # Write SVG files into a directory named <modelname>_svgs
          of_dir = UI.select_directory(title: SVG_OUTPUT_DIRECTORY,
                                       directory: FaceSVG::cfg().default_dir)
          model_dir = "#{modelname}_svgs"
          of_dir = File.join(of_dir, model_dir) unless of_dir.end_with?(model_dir)
          of_path = File.join(of_dir, '%s.svg') # filename substituted for each grp
        else
          of_path = UI.savepanel(SVG_OUTPUT_FILE, FaceSVG::cfg().default_dir, "#{modelname}.svg")
          of_dir = File.dirname(of_path) if of_path
        end
        return false if of_path.nil?

        FaceSVG::cfg().default_dir = of_dir
        ofiles = []
        profgrps.each do |pg|
          outpath = format(of_path, pg.name)
          ofiles << File.basename(outpath)
          FaceSVG.dbg('Writing %s', outpath)
          grps = pg.entities.grep(Sketchup::Group)
          File.open(outpath, 'w') do |file|
            svg = makesvg(pg.name, modelname, *grps)
            svg.write(file)
          end
        end
        UI.messagebox("In #{of_dir}, wrote #{ofiles}") if FaceSVG::cfg().confirmation_dialog
      end
      ################
      def process_selection(selset)
        # UI: process any selected faces and lay out into profile grp
        layout_facegrps(*selset.select(&:valid?).grep(Sketchup::Face))
      end
      ################
      def add_su_facegrp(curr_profilegrp, facegrp)
        # Add new element to existing profile group by recreating the group
        # Save the layer and name, then explode (on default layer) and recreate
        grp_name = curr_profilegrp.name
        grp_layer = curr_profilegrp.layer
        curr_profilegrp.layer = Sketchup.active_model.layers[0]
        new_profilegrp = Sketchup.active_model.entities.add_group(curr_profilegrp.explode + [facegrp])
        # reset to orignal layer, name
        new_profilegrp.layer = grp_layer
        new_profilegrp.name = grp_name
        new_profilegrp
      end
      ################
      def next_position(bnds, currgrp)
        @layoutx += FaceSVG::cfg().layout_spacing + bnds.width
        # As each element is layed out horizontally, keep track of the tallest bit
        @rowheight = [@rowheight, bnds.height].max
        next_row() if @layoutx > FaceSVG::cfg().layout_width
        updt_attrs(currgrp) # update the group attribute_dictionary as attrs are changed
        FaceSVG.dbg('Updated layout attrs %s %s %s', @layoutx, @layouty, @rowheight)
      end
      ################
      def next_row()
        @layoutx = 0.0 + FaceSVG::cfg().layout_spacing
        @layouty += FaceSVG::cfg().layout_spacing + @rowheight
        @rowheight = 0.0
      end
      ################
      def layout_facegrps(*su_faces)
        # Create a new profile grp if needed, setting @profilegrp
        currgrp = current_profilegrp()

        FaceSVG.capture_faceprofiles(*su_faces) do |new_entities, bnds|
          FaceSVG.dbg('Profile %s Face bounds %s layout x,y (%s,%s)',
                      currgrp.name, bnds, @layoutx, @layoutx)
          layout_xf = Geom::Transformation
                      .new([@layoutx, @layouty, 0.0])
          # explode, work around more weird behavior with Arcs?
          # Transform them and then add them back into a group
          Sketchup.active_model.entities.transform_entities(layout_xf, new_entities)

          newfacegrp = currgrp.entities.add_group(new_entities)
          FaceSVG.dbg("layout_facegrps: create new facegrp #{newfacegrp} with #{new_entities}")

          # Handle automatic corner relief
          if FaceSVG::cfg().corner_relief == CR_SYMMETRIC_AUTO
            surface_faces = new_entities.grep(Sketchup::Face)
                                        .select { |f| f.material == FaceSVG.surface }
            Relief.relieve_face_corners(*surface_faces, FaceSVG::cfg().bit_size/2, auto: true)
            FaceSVG.dbg('layout_facegrps: applied corner relief: %s', FaceSVG::cfg().corner_relief)
          end

          # Possible efficiency improvment, add all the new groups at once? Instead of one at a time
          currgrp = add_su_facegrp(currgrp, newfacegrp)
          next_position(bnds, currgrp)
        end
      end
    end
  end
end
