###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'
require 'json'
require 'fileutils'

# redefine module if reloading plugin under sketchup
begin
  Object.send(:remove_const, :FaceSVG)
rescue
  true
end

Sketchup.require('facesvg/constants')
Sketchup.require('facesvg/layout')
Sketchup.require('facesvg/relief')
Sketchup.require('facesvg/su_util')

# API is strange - many operations create only approximate edges, but maintain accurate
#   circular or elliptical arc metadata separately.

module FaceSVG
  VERSION = Sketchup.extensions.find { |e| e.name == 'Face SVG Export' }.version

  FaceSVG.info('--- FaceSVG %s plugin initialized ---', VERSION)
  extend self # instead of 'def self' everywhere

  @@profilemap = Hash.new { |h, k| h[k] = Layout::ProfileCollection.new() }

  # On Mac, can have multiple open models, keep ProfileCollection for each model
  def profile()
    @@profilemap[Sketchup.active_model.guid]
  end

  def facesvg_2d_layout(selset)
    su_operation(LAYOUT_SVG) { profile().process_selection(selset) }
  end

  def corner_relief_available(selset)
    CFG.corner_relief != CR_NONE && (
      selset.find { |e| e.is_a?(Sketchup::Edge) || e.is_a?(Sketchup::Face) })
  end
  def facesvg_corner_relief(selset)
    # Can do: symmetric corner relief on a face, or on an edge and connected edges
    # Can do: asymmetric corner relief on a single edge on a face
    su_operation(LAYOUT_SVG) { Relief.relieve_corners(selset) }
  end

  def facesvg_write
    # Write the SVG file
    su_operation('write', transaction: false) { profile().write() }
  end

  # Almost pointless? If can undo the layout state, it would be...
  #  could make the information an attribute on the profile group...
  def facesvg_reset
    # Delete the cut path layout
    su_operation(RESET_LAYOUT) { profile().reset() }
  end

  def facesvg_next
    profile().next_grp()
  end

  def facesvg_settings
    title = format('%s %s %s', FACESVG, VERSION, SETTINGS)
    inputs = UI.inputbox(CFG.labels, CFG.values, CFG.options, title)

    if inputs
      CFG.inputs(inputs)
      # Just keep settings in a simple place, no Sketchup support
      CFG.save()
    end
  rescue => excp
    _show_and_reraise(excp)
  end

  unless file_loaded?(__FILE__)
    begin
      # No point to static menu for now
      # menu = UI.menu('Plugins')
      # menu.add_item('FaceSVG 2D Layout') {
      #   facesvg_2d_layout
      # }
      # menu.add_item('FaceSVG Settings') {
      #   facesvg_settings
      # }

      UI.add_context_menu_handler do |context_menu|
        selset = Sketchup.active_model.selection
        s_m = context_menu.add_submenu(FACESVG)
        s_m.add_item(SETTINGS) { facesvg_settings }
        s_m.add_item(RESET_LAYOUT) { facesvg_reset }

        unless selset.grep(Sketchup::Face).empty?
          s_m.add_item(LAYOUT_SVG) {
            facesvg_2d_layout(selset)
          }
        end

        if CFG.multifile_mode
          s_m.add_item(NEXT_GROUP) {
            facesvg_next()
          }
        end
        if corner_relief_available(selset)
          s_m.add_item(CORNER_RELIEF) {
            facesvg_corner_relief(selset)
          }
        end

        s_m.add_item(WRITE_SVG) { facesvg_write } unless profile().empty?
      end

      @@context_menu_set = true
      # UI.messagebox "Loaded #{__FILE__}", MB_OK (debugging only)
      file_loaded(__FILE__)
    rescue => excp
      _show_and_reraise(excp)
    end
  end
end
