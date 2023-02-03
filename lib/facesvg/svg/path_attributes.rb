# frozen_string_literal: true

require('facesvg/constants')

module FaceSVG
  module SVG
    class PathAttributes
      def initialize(kind, cut_depth)
        case kind
        when PK_EXTERIOR
          @attributes = {
            SHAPER_PATH_TYPE => kind, SHAPER_CUT_DEPTH => format('%0.3f', cut_depth),
            FILL => black }
        when PK_INTERIOR
          @attributes = {
            SHAPER_PATH_TYPE => kind, SHAPER_CUT_DEPTH => format('%0.3f', cut_depth),
            FILL => white, STROKE => black, STROKE_WIDTH => '2',
            VECTOR_EFFECT => VE_NON_SCALING_STROKE }
        when PK_POCKET
          @attributes = {
            SHAPER_PATH_TYPE => kind,  SHAPER_CUT_DEPTH => format('%0.3f', cut_depth),
            FILL_RULE => EVENODD, FILL => gray(cut_depth),
            STROKE_WIDTH => '2', STROKE =>  gray(cut_depth),
            VECTOR_EFFECT => VE_NON_SCALING_STROKE }
        else # PK_GUIDE, let's not fill, could be problematic
          @attributes = { SHAPER_PATH_TYPE => kind,
            STROKE_WIDTH => '2', STROKE => blue,
            VECTOR_EFFECT => VE_NON_SCALING_STROKE }
        end
      end
      def white; 'rgb(255,255,255)'; end
      def black; 'rgb(0,0,0)'; end
      # blue extracted from example Shaper.png
      def blue; 'rgb(20,110,255)'; end
      def gray(depth)
        # Scale the "grayness" based on depth.  Supposedly SO will
        # recognize from 60,60,60 to 180,180,180 as gray (maybe more?)
        gray = 70 + [(100.0*depth/CFG.pocket_max).to_int, 100].min
        "rgb(#{gray},#{gray},#{gray})"
      end
      # implicit conversion to hash
      def to_hash; @attributes; end
    end
  end
end
