###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'

# redefine module if reloading plugin under sketchup
begin
  Object.send(:remove_const, :FaceSVG)
rescue => exception
  true
end

load 'facesvg/layout.rb'

# API is strange - many operations create only approximate edges, but maintain a higher resolution 
#   circular or elliptical arc.  

# TTD
# More settings material size 2x4 4x4, bit size 1/8, 1/4
# Look at
# https://www.codeproject.com/Articles/210979/Fast-optimizing-rectangle-packing-algorithm-for-bu
# for way to simply arrange the rectangles efficiently in layout, maybe overkill.


module FaceSVG

  @@spacing = 0.5 # 1/2" spacing
  @@sheetwidth = 24.0
  @@sheetheight = 24.0 # unused
  @@VERSION = '1.0'    # FaceSVG::EXTENSION.version inaccessible, inexplicably

  @@default_dir = nil

  extend self       # instead of 'def ' everywhere
  
  @@profilemap = Hash.new {
    |h,k| h[k] = FaceSVG::Layout::ProfileCollection.new(k) } 
  
  # On Mac, can have multiple open models, keep separate tranfrom instance for each model
  def profile()
    title = Sketchup::active_model.title or 'Untitled'
    @@profilemap[title]
  end
  
  def _handle(exception)
    UI.messagebox exception.backtrace.reject(&:empty?).join("\n**")
    UI.messagebox exception.to_s
  end

  # Joy of ruby verbosity
  def default_dir(); @@default_dir; end
  def default_dir=(d); @@default_dir = d; end
  def spacing(); @@spacing; end
  def sheetheight(); @@sheetheight; end
  def sheetwidth(); @@sheetwidth; end
  def version(); @@VERSION; end
  
  def facesvg_2d_layout
    profile().process_selection()
  rescue => exception
    _handle(exception)
    raise
  end

  def facesvg_write
    # Write the SVG file
    profile().write()
  rescue => exception
    _handle(exception)
    raise
  end
  
  def facesvg_reset
    # Delete the cut path layout
    profile().reset()
  rescue => exception
    _handle(exception)
    raise
  end

  # def facesvg_settings
  #   # No real useful settings yet
  #   inputs = UI.inputbox(
  #     ["Output filename", "Segments", "Text"],
  #     [@@out_filename, @@segments, @@text],
  #     ["","on|off","on|off"],
  #     "--------                 SVG Export Settings                 -----------")
  #   @@out_filename, @@segments, @@text = inputs if inputs
  # rescue => exception
  #   _handle(exception)
  #   raise
  # end
  
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
        selset = Sketchup::active_model.selection
        _sm = context_menu.add_submenu('FaceSVG')          
        _sm.add_item('Reset layout') { facesvg_reset }
        _sm.add_item('Layout SVG profile') { facesvg_2d_layout }
        if profile().size > 0
          _sm.add_item('Write SVG profile') { facesvg_write }
        end
      end # context_menu_handler

      @@context_menu_set = true      
      UI.messagebox "Loaded #{__FILE__}", MB_OK
      file_loaded(__FILE__)
    rescue => exception
      _handle(exception)
      raise
    end
  end
end
