# SVG Face Export - Sketchup plugin compatible with Shaper Origin

Supported Sketchup Versions: Probably any version since 2017.  This has been tested with Sketchup Pro 2022.  Since
it is a plugin it requires a "Pro" desktop version.

Notes:
  * Release 3.0.2 fixes an issue for very small circular arcs and some other issues with arcs.
  * Release 3.0.1 has a fix to how SVG is generated, caused by unexpected issues with Sketchup edge ordering
  * Release 2.3.0 has a fix for an incorrectly generated viewBox which would scale the SVG incorrectly

This is a plugin for Sketchup to generate an SVG outline from selected faces.  The plugin adds a couple operations to the "context menu" (right click) when a face is selected or to select the current face. "Layout SVG profile" copies the selected (and related) faces in to a special "SVG Profile" group.  "Write SVG profile" converts the edges of these faces into SVG paths, with the fill set according the the guidelines outlined by *Shaper Origin* for exterior and interior cuts profiles, and for "pocket" cuts.  New to this release, added support for pocket cuts, and the ability to manually edit and change the layout from within Sketchup.

For a detailed description of how to use the plugin see the [Documentation](https://github.com/marvingreenberg/FaceSVG/wiki/Documentation).

Go to https://github.com/marvingreenberg/FaceSVG/releases for download links for the ruby '.rbz' plugin.

See the YouTube video for some examples of its operation.

[![FaceSVG Video](https://github.com/marvingreenberg/FaceSVG/blob/main/images/FaceSVG2.png)](https://www.youtube.com/watch?v=IQFW8jPruxM)

The output SVG file should be compatible for use with the Shaper Origin handheld CNC router and with other applications requiring SVG output.
In theory the pocket cut depth property is added, now supported by Shaper Origin Jenner

## Installation

1. Go to [Releases](https://github.com/marvingreenberg/FaceSVG/releases)
1. Select the desired ".rbz" plugin download, and click **Download** on the linked page
1. In Sketchup, Window->Extension Manager brings up the extension manager
   1. **If you previously installed the plugin from Extension Warehouse, make sure you uninstall it first, from Extension Manager *Manage* tab**
   1. Click the *Install Extension* and select the ".rbz" that you downloaded
   1. Restart Sketchup.  *Sketchup is pretty inconsistent about updating already loaded plugins*
