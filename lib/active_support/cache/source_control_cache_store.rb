# frozen_string_literal: true

require "active_support"
require "active_support/cache"
require "active_support/notifications"
require "active_support/core_ext/object/json"
require "digest"
require "fileutils"

module ActiveSupport
  module Cache
    # A cache store implementation that stores cache entries as files
    # suitable for version control. Each cache entry is stored as two files:
    # - #{hash}.key: the full cache key
    # - #{hash}.value: the serialized cache value
    #
    # This store does NOT honor expiration parameters.
    #
    # Example usage:
    #   config.cache_store = :source_control_cache_store, cache_path: "tmp/cache"
    class SourceControlCacheStore < Store
      attr_reader :cache_path, :subdirectory_delimiter

      # Initialize a new SourceControlCacheStore
      #
      # @param cache_path [String] The directory where cache files will be stored
      # @param subdirectory_delimiter [String, nil] Optional delimiter to split keys into subdirectories
      # @param options [Hash] Additional options (currently unused)
      def initialize(cache_path:, subdirectory_delimiter: nil, **options)
        super(options)
        @cache_path = cache_path
        @subdirectory_delimiter = subdirectory_delimiter
        FileUtils.mkdir_p(@cache_path)
      end

      # Clear all cache entries
      def clear(options = nil)
        if File.directory?(@cache_path)
          Dir.glob(File.join(@cache_path, "*")).each do |path|
            if File.file?(path)
              File.delete(path)
            elsif File.directory?(path)
              FileUtils.rm_rf(path)
            end
          end
        end
        true
      end

      private

      # Read an entry from the cache
      #
      # @param key [String] The cache key
      # @param options [Hash] Options (unused)
      # @return [Object, nil] The cached value or nil if not found
      def read_entry(key, **options)
        value_file = value_path_for_key(key)

        return nil unless File.exist?(value_file)

        value = File.read(value_file)
        entry = deserialize_entry(value)
        
        # Ignore expiration by creating a new entry without expiration
        return entry unless entry.is_a?(ActiveSupport::Cache::Entry)
        
        # Create a new entry that never expires
        ActiveSupport::Cache::Entry.new(entry.value, expires_in: nil)
      rescue StandardError
        # If we can't read or deserialize, treat as cache miss
        nil
      end

      # Write an entry to the cache
      #
      # @param key [String] The cache key
      # @param entry [ActiveSupport::Cache::Entry] The cache entry
      # @param options [Hash] Options (expiration is ignored)
      # @return [Boolean] Returns true on success, false on failure
      def write_entry(key, entry, **options)
        if @subdirectory_delimiter
          write_entry_with_subdirectories(key, entry, **options)
        else
          write_entry_simple(key, entry, **options)
        end
      rescue StandardError
        # Return false if write fails (permissions, disk space, etc.)
        false
      end

      # Write entry using simple hash-based file structure
      def write_entry_simple(key, entry, **options)
        hash = hash_key(key)
        
        # Write the key file
        File.write(key_path(hash), key)
        
        # Write the value file
        File.write(value_path(hash), serialize_entry(entry, **options))
        
        true
      end

      # Write entry using subdirectory structure
      def write_entry_with_subdirectories(key, entry, **options)
        chunks = key.to_s.split(@subdirectory_delimiter)
        current_dir = @cache_path
        
        # Create subdirectories for each chunk
        chunks.each_with_index do |chunk, index|
          chunk_hash = hash_chunk(chunk)
          current_dir = File.join(current_dir, chunk_hash)
          FileUtils.mkdir_p(current_dir)
          
          # Write _key_chunk file
          File.write(File.join(current_dir, "_key_chunk"), chunk)
        end
        
        # Write the value file in the final directory
        File.write(File.join(current_dir, "value"), serialize_entry(entry, **options))
        
        true
      end

      # Delete an entry from the cache
      #
      # @param key [String] The cache key
      # @param options [Hash] Options (unused)
      # @return [Boolean] Returns true if any file was deleted
      def delete_entry(key, **options)
        if @subdirectory_delimiter
          delete_entry_with_subdirectories(key, **options)
        else
          delete_entry_simple(key, **options)
        end
      end

      # Delete entry using simple hash-based file structure
      def delete_entry_simple(key, **options)
        hash = hash_key(key)
        key_file = key_path(hash)
        value_file = value_path(hash)
        
        deleted = false
        
        begin
          deleted = true if File.exist?(key_file) && File.delete(key_file)
        rescue StandardError
          # Ignore errors, continue trying to delete value file
        end
        
        begin
          deleted = true if File.exist?(value_file) && File.delete(value_file)
        rescue StandardError
          # Ignore errors
        end
        
        deleted
      end

      # Delete entry using subdirectory structure
      def delete_entry_with_subdirectories(key, **options)
        value_file = value_path_for_key(key)
        
        return false unless File.exist?(value_file)
        
        # Delete the entire directory tree for this key
        chunks = key.to_s.split(@subdirectory_delimiter)
        first_chunk_hash = hash_chunk(chunks[0])
        dir_to_delete = File.join(@cache_path, first_chunk_hash)
        
        begin
          FileUtils.rm_rf(dir_to_delete) if File.exist?(dir_to_delete)
          true
        rescue StandardError
          false
        end
      end

      # Generate a hash for the given key
      #
      # @param key [String] The cache key
      # @return [String] The SHA256 hash of the key
      def hash_key(key)
        ::Digest::SHA256.hexdigest(key.to_s)
      end

      # Generate a hash for a key chunk
      #
      # @param chunk [String] A chunk of the cache key
      # @return [String] The SHA256 hash of the chunk
      def hash_chunk(chunk)
        ::Digest::SHA256.hexdigest(chunk.to_s)
      end

      # Get the path for the key file
      #
      # @param hash [String] The hash of the key
      # @return [String] The full path to the key file
      def key_path(hash)
        File.join(@cache_path, "#{hash}.key")
      end

      # Get the path for the value file
      #
      # @param hash [String] The hash of the key
      # @return [String] The full path to the value file
      def value_path(hash)
        File.join(@cache_path, "#{hash}.value")
      end

      # Get the value file path for a given key
      #
      # @param key [String] The cache key
      # @return [String] The full path to the value file
      def value_path_for_key(key)
        if @subdirectory_delimiter
          chunks = key.to_s.split(@subdirectory_delimiter)
          current_dir = @cache_path
          
          chunks.each do |chunk|
            chunk_hash = hash_chunk(chunk)
            current_dir = File.join(current_dir, chunk_hash)
          end
          
          File.join(current_dir, "value")
        else
          value_path(hash_key(key))
        end
      end
    end
  end
end
