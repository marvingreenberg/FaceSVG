# frozen_string_literal: true

###########################################################
# Licensed under the MIT license
###########################################################

# i = Sketchup::active_model.options['UnitsOptions']['LengthUnit']
# unit = ['in','ft','mm','cm','m'][i]

module FaceSVG
  # SVG units are: in, cm, mm... all these are unused for now, except INCHES
  INCHES = 'in'
  CM = 'cm'
  MM = 'mm'
  SHAPER = 'shaper'
  PK_INTERIOR = 'interior'
  PK_EXTERIOR = 'exterior'
  PK_POCKET = 'hogging'
  PK_GUIDE = 'guide' # TODO

  # SVG XML CONSTANTS
  SHAPER_CUT_DEPTH = 'shaper:cutDepth'
  SHAPER_PATH_TYPE = 'shaper:pathType'
  FILL = 'fill'
  STROKE = 'stroke'
  STROKE_WIDTH = 'stroke-width'
  FILL_RULE = 'fill-rule'
  EVENODD = 'evenodd'
  VECTOR_EFFECT = 'vector-effect'
  VE_NON_SCALING_STROKE = 'non-scaling-stroke'

  # Options
  LAYOUT_WIDTH = 'Layout Width'
  LAYOUT_SPACING = 'Layout Spacing'
  POCKET_MAX = 'Pocket offset (max)'
  CUT_DEPTH = 'Cut Depth'
  CORNER_RELIEF = 'Corner Relief'
  CR_SYMMETRIC = 'Symmetric'
  CR_ASYMMETRIC = 'Asymmetric'
  CR_SYMMETRIC_AUTO = 'Symmetric, automatic'
  CR_NONE = 'None'
  CR_OPTIONS = [CR_NONE, CR_SYMMETRIC, CR_ASYMMETRIC,
                CR_SYMMETRIC_AUTO].join('|')
  BIT_DIAMETER = 'Bit Diameter'

  # Menus
  SETTINGS = 'Settings'
  FACESVG = 'FaceSVG'
  LAYOUT_SVG = 'Layout SVG Profile'
  RESET_LAYOUT = 'Reset layout'
  WRITE_SVG = 'Write SVG profile'
  SVG_OUTPUT_FILE = 'SVG output file'
  PROFILE_GROUP = 'SVG Profile Group' # group name
  PROFILE_LAYER = 'SVG Profile' # layer name

  # For comparisons in the code
  # Sketchup has some situations, like small
  # ( < cm) features with curves where the tolerance
  # needs to be larger (when ordering edges of a path)
  TOLERANCE = 0.025

  module PathType
    CUT = :CUT
    POCKET = :POCKET
  end

  # Messages
  ERROR_ASYMMETRIC_SINGLE_EDGE_SS =
    '*Error* Select a single face edge for asymmetric corner relief (%s selected)'
  NN_WARNING_LOOPS_IGNORED =
    '*Warning* %s profiles ignored - not rectangular'
  EDGE_NOT_INNER =
    'Edge not part of an inner loop, cannot do asymmetric corner relief'
  EDGE_TOO_SHORT_NN =
    'Cannot generate corner relief with radius %s - edge too short'
  EDGE_NOT_IN_RECTANGLE =
    '*Error* Edge not rectangular'
  UNEXPECTED_NO_CONNECT_XX_AT_XX =
    'Unexpected: No edge/arc connected %s at %s'
end
