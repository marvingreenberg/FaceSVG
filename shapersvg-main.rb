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
