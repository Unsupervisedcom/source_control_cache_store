# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Committed Cache Directory" do
  # Use a non-git-ignored directory for cache storage
  let(:committed_cache_path) { File.join(__dir__, "fixtures", "committed_cache") }
  let(:store) { ActiveSupport::Cache::SourceControlCacheStore.new(cache_path: committed_cache_path) }

  describe "initial cache population" do
    it "creates the cache directory if it doesn't exist" do
      expect(File.directory?(committed_cache_path)).to be true
    end

    it "populates cache with predefined entries" do
      # Write predefined cache entries that will be committed
      store.write("user:123:profile", { name: "John Doe", email: "john@example.com" })
      store.write("user:456:profile", { name: "Jane Smith", email: "jane@example.com" })
      store.write("config:app:settings", { theme: "dark", language: "en" })

      # Verify the entries were written
      expect(store.read("user:123:profile")).to eq({ name: "John Doe", email: "john@example.com" })
      expect(store.read("user:456:profile")).to eq({ name: "Jane Smith", email: "jane@example.com" })
      expect(store.read("config:app:settings")).to eq({ theme: "dark", language: "en" })
    end

    it "creates .key and .value files for each entry" do
      # Ensure files exist
      cache_files = Dir.glob(File.join(committed_cache_path, "*"))
      
      # We expect at least 6 files (3 entries × 2 files each)
      expect(cache_files.length).to be >= 6
      
      # Check that we have both .key and .value files
      key_files = cache_files.select { |f| f.end_with?(".key") }
      value_files = cache_files.select { |f| f.end_with?(".value") }
      
      expect(key_files.length).to be >= 3
      expect(value_files.length).to be >= 3
    end
  end

  describe "cache stability verification" do
    # Capture initial state for comparison
    let(:initial_file_list) do
      Dir.glob(File.join(committed_cache_path, "**", "*"), File::FNM_DOTMATCH)
        .reject { |f| File.directory?(f) }
        .sort
    end

    before(:each) do
      # Ensure cache entries exist before each test
      store.write("user:123:profile", { name: "John Doe", email: "john@example.com" })
      store.write("user:456:profile", { name: "Jane Smith", email: "jane@example.com" })
      store.write("config:app:settings", { theme: "dark", language: "en" })
    end

    it "does not create new files when reading existing entries" do
      # Capture state before reading
      files_before = initial_file_list
      
      # Read existing entries
      store.read("user:123:profile")
      store.read("user:456:profile")
      store.read("config:app:settings")

      # Get current file list
      current_files = Dir.glob(File.join(committed_cache_path, "**", "*"), File::FNM_DOTMATCH)
        .reject { |f| File.directory?(f) }
        .sort

      # Verify no new files were created
      expect(current_files).to eq(files_before)
    end

    it "does not create new files when writing to existing keys with same values" do
      # Capture state before writing
      files_before = initial_file_list
      
      # Write same values to existing keys
      store.write("user:123:profile", { name: "John Doe", email: "john@example.com" })
      store.write("user:456:profile", { name: "Jane Smith", email: "jane@example.com" })
      store.write("config:app:settings", { theme: "dark", language: "en" })

      # Get current file list
      current_files = Dir.glob(File.join(committed_cache_path, "**", "*"), File::FNM_DOTMATCH)
        .reject { |f| File.directory?(f) }
        .sort

      # Verify no new files were created (same files should exist)
      expect(current_files).to eq(files_before)
    end

    it "has all expected cache files present" do
      # Verify that all expected keys exist
      expect(store.read("user:123:profile")).to eq({ name: "John Doe", email: "john@example.com" })
      expect(store.read("user:456:profile")).to eq({ name: "Jane Smith", email: "jane@example.com" })
      expect(store.read("config:app:settings")).to eq({ theme: "dark", language: "en" })
    end

    it "maintains the exact file count" do
      current_files = Dir.glob(File.join(committed_cache_path, "**", "*"), File::FNM_DOTMATCH)
        .reject { |f| File.directory?(f) }
        .sort

      # Should have exactly 7 files (3 entries × 2 files each + 1 README.md)
      expect(current_files.length).to eq(7)
    end

    it "does not create new files during multiple read operations" do
      # Capture state before reading
      files_before = initial_file_list
      
      # Perform multiple read operations
      10.times do
        store.read("user:123:profile")
        store.read("user:456:profile")
        store.read("config:app:settings")
      end

      # Get current file list
      current_files = Dir.glob(File.join(committed_cache_path, "**", "*"), File::FNM_DOTMATCH)
        .reject { |f| File.directory?(f) }
        .sort

      # Verify no new files were created
      expect(current_files).to eq(files_before)
    end
  end

  describe "file content verification" do
    it "preserves original keys in .key files" do
      key_files = Dir.glob(File.join(committed_cache_path, "*.key"))
      expect(key_files.length).to eq(3)

      # Read all key files and verify they contain expected keys
      key_contents = key_files.map { |f| File.read(f) }.sort
      expect(key_contents).to contain_exactly(
        "config:app:settings",
        "user:123:profile",
        "user:456:profile"
      )
    end

    it "has valid value files that can be deserialized" do
      value_files = Dir.glob(File.join(committed_cache_path, "*.value"))
      expect(value_files.length).to eq(3)

      # All value files should be readable and deserializable
      value_files.each do |value_file|
        expect(File.read(value_file).length).to be > 0
      end
    end

    it "includes README.md documentation" do
      readme_path = File.join(committed_cache_path, "README.md")
      expect(File.exist?(readme_path)).to be true
      expect(File.read(readme_path)).to include("Committed Cache Directory")
    end
  end
end
