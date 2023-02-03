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

# @since SketchUp 6
class LanguageHandler

  # @param [String] strings_file_name
  #
  # @since SketchUp 6
  def initialize(strings_file_name)
    unless strings_file_name.is_a?(String)
      raise ArgumentError, 'must be a String'
    end
    # If a string is requested that isn't in our dictionary, return the string
    # requested unchanged.
    @strings = Hash.new { |hash, key| key }
    # We use the global function here to get the file path of the caller,
    # then parse out just the path from the return value.
    stack = caller_locations(1, 1)
    if stack && stack.length > 0 && File.exist?(stack[0].path)
      extension_path = stack[0].path
    else
      extension_path = nil
    end
    parse(strings_file_name, extension_path)
  end

  # @param [String] key
  #
  # @return [String]
  # @since SketchUp 2014
  def [](key)
    # The key might be junk data, such as nil, in which case we just return
    # the value. The first draft of the Langhandler update raised an
    # argument error when the key wasn't a string, but that caused some
    # compatibility issues - particulary with Dynamic Components.
    value = @strings[key]
    # Return a copy of the string to prevent accidental modifications.
    if value.is_a?(String)
      value = value.dup
    end
    return value
  end
  alias :GetString :[] # SketchUp 6

  # @param [String] file_name
  #
  # @return [String]
  # @since SketchUp 2014
  def resource_path(file_name)
    unless file_name.is_a?(String)
      raise ArgumentError, 'must be a String'
    end
    if @language_folder
      file_path = File.join(@language_folder, file_name)
      if File.exists?(file_path)
        return file_path
      end
    end
    return ''
  end
  alias :GetResourcePath :resource_path # SketchUp 6

  # @return [String]
  # @since SketchUp 2014
  def strings
    return @strings
  end
  alias :GetStrings :strings # SketchUp 6

  # Returns the location of the loaded strings file.
  #
  # @return [String, nil]
  # @since SketchUp 2016 M1
  def strings_file
    @strings_file ? @strings_file.dup : nil
  end

  private

  # @param [String] strings_file_name
  # @param [String] extension_file_path
  #
  # @return [String, Nil]
  # @since SketchUp 2014
  def find_strings_file(strings_file_name, extension_file_path = nil)
    strings_file_path = ''
    
    # Check if there is local resources for this strings file.
    if extension_file_path
      # Get the filename without the path and extension.
      file_type = File.extname(extension_file_path)
      basename = File.basename(extension_file_path, file_type)
      # Now get the path to the extension's folder (same name as the extension
      # file name).
      extension_path = File.dirname(extension_file_path)
      resource_folder_path = File.join(extension_path, basename, 'Resources')
      resource_folder_path = File.expand_path(resource_folder_path)
      strings_file_path = File.join(resource_folder_path, Sketchup.get_locale,
        strings_file_name)
      # If the file is not there, then try the local default language folder.
      if File.exists?(strings_file_path) == false
        strings_file_path = File.join(resource_folder_path, 'en-US',
          strings_file_name)
      end
    end
    
    # If that doesn't exist, then try the SketchUp resources folder.
    if File.exists?(strings_file_path) == false
      strings_file_path = Sketchup.get_resource_path(strings_file_name)      
    end

    if strings_file_path && File.exists?(strings_file_path)
      return strings_file_path
    else
      return nil
    end
  end

  # @param [String] strings_file_name
  # @param [String] extension_file_path
  #
  # @return [Boolean]
  # @since SketchUp 6
  def parse(strings_file_name, extension_file_path = nil)
    strings_file = find_strings_file(strings_file_name, extension_file_path)
    if strings_file.nil?
      return false
    end

    # Store where the strings file was loaded from. To ease debugging.
    @strings_file = strings_file
    
    # Set the language folder - this is used by GetResourcePath().
    @language_folder = File.expand_path(File.dirname(strings_file))

    File.open(strings_file, 'r:BOM|UTF-8') { |lang_file|
      entry_string = ''
      in_comment_block = false
      lang_file.each_line { |line|
        # Ignore simple comment lines - BIG assumption that the whole line
        # is a comment.
        if !line.lstrip.start_with?('//')
          # Also ignore comment blocks.
          if line.include?('/*')
            in_comment_block = true
          end
          if in_comment_block
            if line.include?('*/')
              in_comment_block = false
            end
          else
            entry_string += line
          end
        end

        if entry_string.include?(';')
          # Parse the string into key and value parts.
          pattern = /^\s*"(.+)"="(.+)"\s*;\s*(?:\/\/.*)*$/
          result = pattern.match(entry_string)
          if result && result.size == 3
            key = result[1]
            value = result[2]
            @strings[key] = value
          end
          entry_string.clear
        end
      } # each line
    }
    return true
  end

end # class
