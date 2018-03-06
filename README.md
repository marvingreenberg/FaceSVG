# SVG Face Export - Sketchup plugin compatible with Shaper Origin

This is a plugin for Sketchup to generate an SVG outline from selected faces.  The plugin adds a couple operations to the "context menu" (right click) when a face is selected or to select the current face. "Layout SVG profile" copies the selected (and related) faces in to a special "SVG Profile" group.  "Write SVG profile" converts the edges of these faces into SVG paths, with the fill set according the the guidelines outlined by *Shaper Origin* for exterior and interior cuts profiles, and for "pocket" cuts.  New to this release, added support for pocket cuts, and the ability to manually edit and change the layout from within Sketchup.

For a detailed description of how to use the plugin see the [Documentation](https://github.com/marvingreenberg/FaceSVG/wiki/Documentation).

Go to https://github.com/marvingreenberg/FaceSVG/releases for download links for the ruby '.rbz' plugin.

**If you find this useful, _especially for the Shaper Origin_, send me, say, $18 via** [paypal.me/marvingreenberg/18](https://paypal.me/marvingreenberg/18).  (You know, one roll of shaper tape)

See the YouTube video to see its operation.

[![FaceSVG Video](https://github.com/marvingreenberg/FaceSVG/blob/master/images/FaceSVG2.png)](https://www.youtube.com/watch?v=IQFW8jPruxM)

The output SVG file should be compatible for use with the Shaper Origin handheld CNC router and with other applications requiring SVG output.

## Installation

1. Go to [Releases](https://github.com/marvingreenberg/FaceSVG/releases)
1. Select the desired ".rbz" plugin download, and click **Download** on the linked page
1. In Sketchup, Window->Extension Manager brings up the extension manager
   1. **If you previously installed the plugin from Extension Warehouse, make sure you uninstall it first, from Extension Manager *Manage* tab**
   1. Click the *Install Extension* and select the ".rbz" that you downloaded
   1. Restart Sketchup.  *Sketchup is pretty inconsistent about updating already loaded plugins*
