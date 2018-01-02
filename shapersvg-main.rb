###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'extensions'
require 'LangHandler'

# https://stackoverflow.com/questions/11503558/how-to-undefine-class-in-ruby
load 'shapersvg/main.rb'   # Use load, so reload will update plugin

# Sketchup API is a litle strange - many operations create edges, but actually maintain a higher resolution 
#   circular or elliptical arc.  Still need to figure out various transforms, applied to shapes


unless file_loaded?(__FILE__)
  menu = UI.menu('Plugins')
  menu.add_item('ShaperSVG 2D Layout') {
    ShaperSVG::Main::shapersvg_2d_layout
  }
  menu.add_item('ShaperSVG Settings') {
    ShaperSVG::Main::shapersvg_settings
  }
  
  UI.messagebox "Loaded #{__FILE__}", MB_OK
  file_loaded(__FILE__)
end
