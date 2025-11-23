# frozen_string_literal: true

require "active_support"
require "active_support/cache"
require "active_support/notifications"
require "active_support/core_ext/object/json"
require "active_support/core_ext/digest"
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
      attr_reader :cache_path

      # Initialize a new SourceControlCacheStore
      #
      # @param cache_path [String] The directory where cache files will be stored
      # @param options [Hash] Additional options (currently unused)
      def initialize(cache_path:, **options)
        super(options)
        @cache_path = cache_path
        FileUtils.mkdir_p(@cache_path)
      end

      # Clear all cache entries
      def clear(options = nil)
        if File.directory?(@cache_path)
          Dir.glob(File.join(@cache_path, "*")).each do |file|
            File.delete(file) if File.file?(file)
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
        hash = hash_key(key)
        value_file = value_path(hash)

        return nil unless File.exist?(value_file)

        value = File.read(value_file)
        entry = deserialize_entry(value)
        
        # Ignore expiration by creating a new entry without expiration
        return entry unless entry.is_a?(ActiveSupport::Cache::Entry)
        
        # Create a new entry that never expires
        ActiveSupport::Cache::Entry.new(entry.value, expires_in: nil)
      rescue => e
        # If we can't read or deserialize, treat as cache miss
        nil
      end

      # Write an entry to the cache
      #
      # @param key [String] The cache key
      # @param entry [ActiveSupport::Cache::Entry] The cache entry
      # @param options [Hash] Options (expiration is ignored)
      # @return [Boolean] Always returns true
      def write_entry(key, entry, **options)
        hash = hash_key(key)
        
        # Write the key file
        File.write(key_path(hash), key)
        
        # Write the value file
        File.write(value_path(hash), serialize_entry(entry, **options))
        
        true
      end

      # Delete an entry from the cache
      #
      # @param key [String] The cache key
      # @param options [Hash] Options (unused)
      # @return [Boolean] Returns true if the entry was deleted
      def delete_entry(key, **options)
        hash = hash_key(key)
        key_file = key_path(hash)
        value_file = value_path(hash)
        
        deleted = false
        deleted = File.delete(key_file) if File.exist?(key_file)
        deleted = File.delete(value_file) if File.exist?(value_file)
        
        deleted
      end

      # Generate a hash for the given key
      #
      # @param key [String] The cache key
      # @return [String] The SHA256 hash of the key
      def hash_key(key)
        ::Digest::SHA256.hexdigest(key.to_s)
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
    end
  end
end
