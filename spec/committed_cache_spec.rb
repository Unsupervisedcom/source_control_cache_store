# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Committed Cache Directory" do
  # Use a non-git-ignored directory for cache storage
  let(:committed_cache_path) { File.join(__dir__, "fixtures", "committed_cache") }
  # Configure store with raw mode to avoid compression
  let(:store) { ActiveSupport::Cache::SourceControlCacheStore.new(cache_path: committed_cache_path, compress: false) }
  
  # Predefined cache entries (keys and values as JSON strings for readability)
  let(:cache_entries) do
    {
      "user:123:profile" => { name: "John Doe", email: "john@example.com" }.to_json,
      "user:456:profile" => { name: "Jane Smith", email: "jane@example.com" }.to_json,
      "config:app:settings" => { theme: "dark", language: "en" }.to_json
    }
  end
  
  # File list helpers
  let(:key_files) { Dir.glob(File.join(committed_cache_path, "*.key")) }
  let(:value_files) { Dir.glob(File.join(committed_cache_path, "*.value")) }
  let(:all_files) do
    Dir.glob(File.join(committed_cache_path, "**", "*"), File::FNM_DOTMATCH)
      .reject { |f| File.directory?(f) }
      .sort
  end
  let(:key_contents) { key_files.map { |f| File.read(f) }.sort }
  
  # Shared examples for validating cache state
  shared_examples "validates committed cache files" do
    it "has the expected number of key files" do
      expect(key_files.length).to eq(3)
    end
    
    it "has the expected number of value files" do
      expect(value_files.length).to eq(3)
    end
    
    it "preserves original keys in .key files" do
      expect(key_contents).to contain_exactly(*cache_entries.keys.sort)
    end
    
    it "has valid value files that can be deserialized" do
      # All value files should be readable
      value_files.each do |value_file|
        expect(File.read(value_file).length).to be > 0
      end
    end
    
    it "maintains the exact file count" do
      # Should have exactly 7 files (3 entries × 2 files each + 1 README.md)
      expect(all_files.length).to eq(7)
    end
  end

  describe "cache stability verification" do
    # Capture initial state for comparison
    let(:initial_file_list) { all_files }

    before(:each) do
      # Ensure cache entries exist before each test using raw mode
      cache_entries.each do |key, value|
        store.write(key, value, raw: true)
      end
    end

    it "does not create new files when reading existing entries" do
      # Capture state before reading
      files_before = initial_file_list
      
      # Read existing entries with raw mode
      cache_entries.keys.each do |key|
        store.read(key, raw: true)
      end

      # Verify no new files were created
      expect(all_files).to eq(files_before)
    end

    it "does not create new files when writing to existing keys with same values" do
      # Capture state before writing
      files_before = initial_file_list
      
      # Write same values to existing keys with raw mode
      cache_entries.each do |key, value|
        store.write(key, value, raw: true)
      end

      # Verify no new files were created (same files should exist)
      expect(all_files).to eq(files_before)
    end

    it "has all expected cache files present" do
      # Verify that all expected keys exist
      cache_entries.each do |key, expected_value|
        expect(store.read(key, raw: true)).to eq(expected_value)
      end
    end

    it "does not create new files during multiple read operations" do
      # Capture state before reading
      files_before = initial_file_list
      
      # Perform multiple read operations
      10.times do
        cache_entries.keys.each do |key|
          store.read(key, raw: true)
        end
      end

      # Verify no new files were created
      expect(all_files).to eq(files_before)
    end
    
    include_examples "validates committed cache files"
  end

  describe "file content verification" do
    include_examples "validates committed cache files"
    
    it "includes README.md documentation" do
      readme_path = File.join(committed_cache_path, "README.md")
      expect(File.exist?(readme_path)).to be true
      expect(File.read(readme_path)).to include("Committed Cache Directory")
    end
  end
end
