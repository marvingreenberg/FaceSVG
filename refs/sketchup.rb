# Copyright 2017, Trimble Inc.

# This software is provided as an example of using the Ruby interface
# to SketchUp.
# Note that this was written a long time ago and we discourage the use of
# global methods and variables.

# Permission to use, copy, modify, and distribute this software for
# any purpose and without fee is hereby granted, provided that the above
# copyright notice appear in all copies.

# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

require 'langhandler.rb'
$suStrings = LanguageHandler.new('gettingstarted.strings')

# This file defines a number of useful utilities that are used by other
# Ruby scripts.

# These functions are used to help with adding new menu items from a
# script.  The function file_loaded? is used to tell if the file
# has already been loaded.  If it returns true, then you should not
# add new menu items.  It is useful to allow you to reload a file
# while you are testing it without having to restart SketchUp and without
# Having it add new menu items every time it is loaded.

# This array keeps track of loaded files.  It is like the Ruby variable $"
# that is set by require, but it is not set automatically.  You have
# to call file_loaded to add a filename to the array
$loaded_files ||= []

# Use in combination with {#file_loaded} to create load guards for code you
# don't want to reload. Especially useful to protect your UI setup from creating
# duplicate menus and toolbars.
#
# @param [String] filename
#
# @see #file_loaded
#
# @example
#   module Example
#     unless file_loaded?(__FILE__)
#       menu = UI.menu('Plugins')
#       menu.add_item('Example') { self.hello }
#       file_loaded(__FILE__)
#     end
#
#     def self.hello
#       puts 'Hello World'
#     end
#
#   end
#
# @version SketchUp 6.0
def file_loaded?(filename)
  $loaded_files.include?(filename.downcase)
end

# Call this function at the end of a file that you are loading to
# let the system know that you have loaded it.
#
# @param [String] filename
#
# @see #file_loaded?
#
# @example
#   module Example
#     unless file_loaded?(__FILE__)
#       menu = UI.menu('Plugins')
#       menu.add_item('Example') { self.hello }
#       file_loaded(__FILE__)
#     end
#
#     def self.hello
#       puts 'Hello World'
#     end
#
#   end
#
# @version SketchUp 6.0
def file_loaded(filename)
  return if $loaded_files.include?(filename.downcase)

  $loaded_files << filename.downcase
end

$menu_separator_list = []
# @deprecated Avoid adding separators to top level menus. If you require
#   grouping use a sub-menu instead.
#
# This function will add a separator to a given menu the first
# time it is called.  It is useful for adding a separator before
# the first plugin that is added to a given menu.
#
# @param [String] menu_name
#
# @version SketchUp 6.0
def add_separator_to_menu(menu_name)
  return if $menu_separator_list.include?(menu_name)

  UI.menu(menu_name).add_separator
  $menu_separator_list << menu_name
end

# This is a wrapper for {UI.inputbox}.  You call it exactly the same
# as {UI.inputbox}.  {UI.inputbox} will raise an exception if it can't
# convert the string entered for one of the values into the right type.
# This method will trap the exception and display an error dialog and
# then prompt for the values again.
#
# @param (see UI#inputbox)
#
# @see UI.inputbox
#
# @version SketchUp 6.0
def inputbox(*args)
  begin
    results = nil
    results = UI.inputbox(*args)
  rescue ArgumentError => e
    UI.messagebox(e.message)
    retry if args.length > 0
  end
  results
end

# @deprecated This adds the path given to +$LOAD_PATH+ which can affect
#   other extensions.
#
# By default, SketchUp automatically loads (using require) all files with
# the .rb extension in the plugins directory.  This function can be used
# to automatically load all .rb files from a different directory also.  to
# use this add a call like the following to a file in the plugins directory
# <code>require_all "MyRubyScripts"</code>
#
# @param [String] dirname
#
# @version SketchUp 6.0
def require_all(dirname)
  rbfiles = Dir[File.join(dirname, '*.{rbe,rbs,rb}')]
  # This isn't ideal, adding to the load path. This could interfere with
  # how extension's load files using `require`.
  $:.push dirname
  rbfiles.each { |f| Sketchup::require f }
rescue
  puts "could not load files from #{dirname}"
end

# @deprecated Use +SKETCHUP_CONSOLE.show+ instead.
#
# This global method is called by the Ruby Console menu item. We call this
# instead of directly calling <code>Sketchup.send_action("showRubyPanel:")</code>
# so that other Ruby Console implementations can hijack this method.
#
# @version SketchUp 6.0
def show_ruby_panel
  Sketchup.send_action('showRubyPanel:')
end
