# Copyright 2013, Trimble Navigation Limited

# This software is provided as an example of using the Ruby interface
# to SketchUp.

# Permission to use, copy, modify, and distribute this software for
# any purpose and without fee is hereby granted, provided that the above
# copyright notice appear in all copies.

# THIS SOFTWARE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#-----------------------------------------------------------------------------

# Base class for SketchUp Ruby extensions.
class SketchupExtension

    attr_accessor :name, :description, :version, :creator, :copyright, :id, :version_id, :extension_path

    def initialize(name, filePath = nil)
      @name = name
      @description = ""
      @path = filePath
      @id = ""
      @version_id = ""
      @has_been_uninstalled = false
      
      # We use the global function here to get the file
      # path of the caller, then parse out just the path from the return
      # value.
      @extension_path = ""
      stack = caller_locations(1, 1)
      if stack && stack.length > 0 && File.exist?(stack[0].path)
        @extension_path = stack[0].path
      end

      if @extension_path != nil && @extension_path.length > 0
        self.load_extension_info
      end

      @version = "1.0"
      # Default values for extensions copyright and creator should be empty.
      # These two values should be set when registering your extension.
      @creator = ""
      @copyright = ""
      @loaded = false
      @registered = false

      # When an extension is registered with Sketchup.register_extension,
      # SketchUp will then update this setting if the user makes changes
      # in the Preferences > Extensions panel.
      @load_on_start = false
    end
    
    def load_extension_info
      # Get the filename without the path and extension.
      extension_folder_name = File.basename(@extension_path, ".rb")
      # Now get the path to the extension's folder (same name as the extension
      # file name).
      extension_folder_name = File.expand_path(
        File.join(File.dirname(@extension_path),
        extension_folder_name))
      # Now append extension_info.txt to the end.
      extension_info_file_name = File.join(extension_folder_name,
        "extension_info.txt")
      # If the file does not exist, this is not an extension store
      # extension.  That's ok.  Just return.
      if File.exists?(extension_info_file_name) == false
        return
      end
      
      # Run through the file line by line and parse out the id and version_id.
      extension_info_file = File.open(extension_info_file_name, "r")
      entry_string = ""
      in_comment_block = false
      extension_info_file.each do |line|
        # Ignore simple comment lines - BIG assumption the whole line is
        # a comment.
        if !line.include?("//")
          # Also ignore comment blocks.
          if line.include?("/*")
            in_comment_block = true
          end
          if in_comment_block==true
            if line.include?("*/")
              in_comment_block=false
            end
          else
            entry_string += line
          end
        end

        # Parse the string into key and value parts.
        
        # Remove the white space.
        entry_string.strip!

        # Split the line on the '='.
        keyvalue = entry_string.split("=")
        
        # Get the key, without any surrounding whitespace.
        key = keyvalue[0].strip

        # Get the value, without any surrounding whitespace.
        value = keyvalue[1].strip
        
        # If the key is ID or VERSION_ID set the internal
        # variables.
        if key == "ID"
          @id = value
        elsif key == "VERSION_ID"
          @version_id = value
        end

        entry_string = ""
      end
      extension_info_file.close
    end

    # Loads the extension, which is the equivalent of checking its checkbox
    # in the Preferences > Extension panel.
    def check
      # If we're already registered, reregister to initiate the load.
      if @registered
        Sketchup.register_extension self, true
      else
        # If we're not registered, just require the implementation file.
        success = Sketchup::require @path
        if success
          @loaded = true
          return true
        else
          return false
        end
      end
    end

    # Unloads the extension, which is the equivalent of unchecking its checkbox
    # in the Preferences > Extension panel.
    def uncheck
      # If we're already registered, re-register to initiate the unload.
      if @registered
        Sketchup.register_extension self, false
      end
    end

    # Get whether this extension has been loaded.
    def loaded?
      return @loaded
    end

    # Get whether this extension is set to load on start of SketchUp.
    def load_on_start?
      return @load_on_start
    end

    # Get whether this extension has been registered with SketchUp via the
    # Sketchup.register_extension method.
    def registered?
      return @registered
    end
    
    # Get whether this extension has been uninstalled with SketchUp via the
    # Extension Warehouse.
    def has_been_uninstalled?
      return @has_been_uninstalled
    end

    # This method is called by SketchUp when the extension is registered via the
    # Sketchup.register_extension method. NOTE: This is an internal method that
    # should not be called from Ruby.
    def register_from_sketchup()
      @registered = true
    end

    # This is called by SketchUp when the extension is unloaded via the UI.
    # NOTE: This is an internal method that should not be called from Ruby.
    def unload()
      @load_on_start = false
    end

    # This is called by SketchUp when the extension is unstalled via the UI.
    # NOTE: This is an internal method that should not be called from Ruby.
    def mark_as_uninstalled
      @has_been_uninstalled = true
    end
    
    # This is called by SketchUp when the extension is updated via the UI.
    # NOTE: This is an internal method that should not be called from Ruby.
    def set_version_id(id_value)
      @version_id = id_value
    end

    # This is called by SketchUp when the extension is loaded via the UI.
    # NOTE: This is an internal method that should not be called from Ruby.
    def load()
      success = Sketchup::require @path
      if success
        @load_on_start = true
        @loaded = true
        return true
      else
        return false
      end
    end
end
