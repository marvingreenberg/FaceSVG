# SVG Face Export - compatible with Shaper Origin

This is a plugin to generate an SVG outline from selected faces.  The plugin adds a couple operations to the "context menu" (right click) when a face is selected or to select the current face. "Layout SVG profile" copies the selected (and related) faces in to a special "SVG Profile" group.  "Write SVG profile" converts the edges of these faces into SVG paths, with the fill set according the the guidelines outlined by *Shaper Origin* for exterior and interior cuts profiles, and for "pocket" cuts.  New to this release, added support for pocket cuts, and the ability to manually edit and change the layout from within Sketchup.

**Note: the YouTube video has not been updated yet, and additional documentation will be provided in the future** . Also see [the Wiki](https://github.com/marvingreenberg/FaceSVG/wiki) for information on current and future developments.

Go to https://github.com/marvingreenberg/FaceSVG/releases for download links for the ruby '.rbz' plugin.

**If you find this useful, _especially for the Shaper Origin_, send me, say, $18 via** [paypal.me/marvingreenberg/18](https://paypal.me/marvingreenberg/18).  (You know, one roll of shaper tape) If enough people are supporting this I'll make an effort to improve this actively.

See the YouTube video to see its operation.  My plan is to iterate through various improvements quickly.  My goal is to provide useful functionality for generating customized SVG output directly from Sketchup without requiring other software tools.  My near term goal is a slight improvment to allow changes, from within Sketchup, to layed-out edges to be reflected in the output SVG.  I also want to add support for Shaper Origin "pocket cuts".   I'm also very open to suggestions from the user community to improve or add features.

[![FaceSVG Video](https://github.com/marvingreenberg/FaceSVG/blob/v1.0.1/doc/FaceSVG_YouTube.png)](https://www.youtube.com/watch?v=yBeFX-peRTg)

The output SVG file should be compatible for use with the Shaper Origin handheld CNC router and with other applications requiring SVG output.

## Installation

1. Go to [Releases](https://github.com/marvingreenberg/FaceSVG/releases)
1. Select the desired ".rbz" plugin download, and click **Download** on the linked page
1. In Sketchup, Window->Extension Manager brings up the extension manager
   1. **If you previously installed the plugin from Extension Warehouse, make sure you uninstall it first, from Extension Manager *Manage* tab**
   1. Click the *Install Extension* and select the ".rbz" that you downloaded
   1. Restart Sketchup.  *Sketchup is pretty inconsistent about updating already loaded plugins*
