###########################################################
# Licensed under the MIT license
###########################################################
require 'sketchup'
require 'LangHandler'

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
  PK_INTERIOR = 'interior'.freeze
  PK_EXTERIOR = 'exterior'.freeze
  PK_POCKET = 'pocket'.freeze
  PK_GUIDE = 'guide'.freeze # TODO

  # Options
  SVG_OUTPUT = 'SVG Output'.freeze
  SINGLE_FILE = 'single file'.freeze
  MULTI_FILE = 'multiple file'.freeze
  SVG_OUTPUT_OPTS=[SINGLE_FILE, MULTI_FILE].join('|').freeze
  LAYOUT_WIDTH = 'Layout Width'.freeze
  LAYOUT_SPACING = 'Layout Spacing'.freeze
  POCKET_MAX = 'Pocket offset (max)'.freeze
  CUT_DEPTH = 'Cut Depth'.freeze

  # Menus
  SETTINGS = 'Settings'.freeze
  FACESVG = 'FaceSVG'.freeze
  LAYOUT_SVG = 'Layout SVG Profile'.freeze
  RESET_LAYOUT = 'Reset layout'.freeze
  WRITE_SVG = 'Write SVG profile'.freeze
  SVG_OUTPUT_FILE = 'SVG output file'.freeze
  SVG_OUTPUT_DIRECTORY = 'SVG output directory'.freeze
  PROFILE_GROUP = 'SVG Profile Group'.freeze # group name
  PROFILE_LAYER = 'SVG Profile'.freeze # layer name

  # For comparisons in the code
  # Sketchup has some situations, like small
  # ( < cm) features with curves where the tolerance
  # needs to be larger (when ordering edges of a path)
  TOLERANCE = 0.025
end
