# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveSupport::Cache::SourceControlCacheStore do
  let(:cache_path) { Dir.mktmpdir }
  let(:store) { described_class.new(cache_path: cache_path) }

  after do
    FileUtils.rm_rf(cache_path) if File.exist?(cache_path)
  end

  describe "#initialize" do
    it "creates the cache directory if it doesn't exist" do
      new_path = File.join(cache_path, "new_cache")
      expect(File.directory?(new_path)).to be false
      
      described_class.new(cache_path: new_path)
      
      expect(File.directory?(new_path)).to be true
    end

    it "stores the cache path" do
      expect(store.cache_path).to eq(cache_path)
    end
  end

  describe "#write and #read" do
    it "writes and reads a simple value" do
      store.write("test_key", "test_value")
      expect(store.read("test_key")).to eq("test_value")
    end

    it "writes and reads a complex object" do
      complex_object = { name: "John", age: 30, hobbies: ["reading", "coding"] }
      store.write("complex", complex_object)
      expect(store.read("complex")).to eq(complex_object)
    end

    it "returns nil for non-existent keys" do
      expect(store.read("non_existent")).to be_nil
    end

    it "creates both .key and .value files" do
      store.write("my_key", "my_value")
      
      # Calculate the expected hash
      hash = Digest::SHA256.hexdigest("my_key")
      key_file = File.join(cache_path, "#{hash}.key")
      value_file = File.join(cache_path, "#{hash}.value")
      
      expect(File.exist?(key_file)).to be true
      expect(File.exist?(value_file)).to be true
    end

    it "stores the original key in the .key file" do
      original_key = "my_special_key"
      store.write(original_key, "value")
      
      hash = Digest::SHA256.hexdigest(original_key)
      key_file = File.join(cache_path, "#{hash}.key")
      
      expect(File.read(key_file)).to eq(original_key)
    end

    it "overwrites existing values" do
      store.write("key", "value1")
      store.write("key", "value2")
      expect(store.read("key")).to eq("value2")
    end
  end

  describe "#delete" do
    it "deletes an existing entry" do
      store.write("key_to_delete", "value")
      expect(store.read("key_to_delete")).to eq("value")
      
      result = store.delete("key_to_delete")
      expect(result).to be_truthy
      expect(store.read("key_to_delete")).to be_nil
    end

    it "removes both .key and .value files" do
      store.write("key", "value")
      hash = Digest::SHA256.hexdigest("key")
      key_file = File.join(cache_path, "#{hash}.key")
      value_file = File.join(cache_path, "#{hash}.value")
      
      expect(File.exist?(key_file)).to be true
      expect(File.exist?(value_file)).to be true
      
      store.delete("key")
      
      expect(File.exist?(key_file)).to be false
      expect(File.exist?(value_file)).to be false
    end

    it "returns false for non-existent keys" do
      result = store.delete("non_existent")
      expect(result).to be_falsey
    end
  end

  describe "#clear" do
    it "removes all cache files" do
      store.write("key1", "value1")
      store.write("key2", "value2")
      store.write("key3", "value3")
      
      expect(Dir.glob(File.join(cache_path, "*")).length).to be > 0
      
      store.clear
      
      expect(Dir.glob(File.join(cache_path, "*")).length).to eq(0)
    end

    it "returns true" do
      expect(store.clear).to be true
    end
  end

  describe "#fetch" do
    it "returns cached value if present" do
      store.write("fetch_key", "cached_value")
      
      result = store.fetch("fetch_key") { "block_value" }
      expect(result).to eq("cached_value")
    end

    it "executes block and caches result if not present" do
      result = store.fetch("new_key") { "computed_value" }
      
      expect(result).to eq("computed_value")
      expect(store.read("new_key")).to eq("computed_value")
    end
  end

  describe "expiration (should be ignored)" do
    it "ignores expires_in option" do
      # Write with expiration - it should be ignored
      store.write("expiring_key", "value", expires_in: 0.001)
      
      # Sleep a bit to ensure expiration would have happened
      sleep(0.01)
      
      # Value should still be present since expiration is ignored
      expect(store.read("expiring_key")).to eq("value")
    end
  end

  describe "key hashing" do
    it "uses SHA256 for hashing keys" do
      key = "test_key"
      expected_hash = Digest::SHA256.hexdigest(key)
      
      store.write(key, "value")
      
      key_file = File.join(cache_path, "#{expected_hash}.key")
      expect(File.exist?(key_file)).to be true
    end

    it "handles keys with special characters" do
      key = "key/with:special*chars?"
      store.write(key, "value")
      
      expect(store.read(key)).to eq("value")
    end

    it "handles very long keys" do
      key = "a" * 1000
      store.write(key, "value")
      
      expect(store.read(key)).to eq("value")
    end
  end

  describe "edge cases" do
    it "handles nil values" do
      store.write("nil_key", nil)
      expect(store.read("nil_key")).to be_nil
    end

    it "handles empty string values" do
      store.write("empty_key", "")
      expect(store.read("empty_key")).to eq("")
    end

    it "handles numeric values" do
      store.write("number", 42)
      expect(store.read("number")).to eq(42)
    end

    it "handles boolean values" do
      store.write("true_key", true)
      store.write("false_key", false)
      
      expect(store.read("true_key")).to eq(true)
      expect(store.read("false_key")).to eq(false)
    end
  end

  describe "subdirectory_delimiter feature" do
    let(:cache_path_with_delimiter) { Dir.mktmpdir }
    let(:store_with_delimiter) { described_class.new(cache_path: cache_path_with_delimiter, subdirectory_delimiter: "---") }

    after do
      FileUtils.rm_rf(cache_path_with_delimiter) if File.exist?(cache_path_with_delimiter)
    end

    it "stores subdirectory_delimiter parameter" do
      expect(store_with_delimiter.subdirectory_delimiter).to eq("---")
    end

    it "creates nested directories for split keys" do
      store_with_delimiter.write("foo---bar---boo-ba", "27")
      
      # Calculate expected hashes
      foo_hash = Digest::SHA256.hexdigest("foo")
      bar_hash = Digest::SHA256.hexdigest("bar")
      boo_ba_hash = Digest::SHA256.hexdigest("boo-ba")
      
      # Check that directories exist
      expect(File.directory?(File.join(cache_path_with_delimiter, foo_hash))).to be true
      expect(File.directory?(File.join(cache_path_with_delimiter, foo_hash, bar_hash))).to be true
      expect(File.directory?(File.join(cache_path_with_delimiter, foo_hash, bar_hash, boo_ba_hash))).to be true
    end

    it "creates _key_chunk files with correct content" do
      store_with_delimiter.write("foo---bar---boo-ba", "27")
      
      foo_hash = Digest::SHA256.hexdigest("foo")
      bar_hash = Digest::SHA256.hexdigest("bar")
      boo_ba_hash = Digest::SHA256.hexdigest("boo-ba")
      
      # Check _key_chunk files
      foo_chunk_file = File.join(cache_path_with_delimiter, foo_hash, "_key_chunk")
      bar_chunk_file = File.join(cache_path_with_delimiter, foo_hash, bar_hash, "_key_chunk")
      boo_ba_chunk_file = File.join(cache_path_with_delimiter, foo_hash, bar_hash, boo_ba_hash, "_key_chunk")
      
      expect(File.read(foo_chunk_file)).to eq("foo")
      expect(File.read(bar_chunk_file)).to eq("bar")
      expect(File.read(boo_ba_chunk_file)).to eq("boo-ba")
    end

    it "stores value in the final directory" do
      store_with_delimiter.write("foo---bar---boo-ba", "27")
      
      foo_hash = Digest::SHA256.hexdigest("foo")
      bar_hash = Digest::SHA256.hexdigest("bar")
      boo_ba_hash = Digest::SHA256.hexdigest("boo-ba")
      
      value_file = File.join(cache_path_with_delimiter, foo_hash, bar_hash, boo_ba_hash, "value")
      
      expect(File.exist?(value_file)).to be true
      expect(store_with_delimiter.read("foo---bar---boo-ba")).to eq("27")
    end

    it "reads values correctly from subdirectory structure" do
      store_with_delimiter.write("alpha---beta", "test_value")
      expect(store_with_delimiter.read("alpha---beta")).to eq("test_value")
    end

    it "handles single chunk keys (no delimiter present)" do
      store_with_delimiter.write("single_key", "single_value")
      
      single_hash = Digest::SHA256.hexdigest("single_key")
      value_file = File.join(cache_path_with_delimiter, single_hash, "value")
      
      expect(File.exist?(value_file)).to be true
      expect(store_with_delimiter.read("single_key")).to eq("single_value")
    end

    it "deletes entries in subdirectory structure" do
      store_with_delimiter.write("foo---bar---baz", "value")
      expect(store_with_delimiter.read("foo---bar---baz")).to eq("value")
      
      result = store_with_delimiter.delete("foo---bar---baz")
      expect(result).to be_truthy
      expect(store_with_delimiter.read("foo---bar---baz")).to be_nil
    end

    it "clears all entries including subdirectories" do
      store_with_delimiter.write("key1---sub1", "value1")
      store_with_delimiter.write("key2---sub2", "value2")
      store_with_delimiter.write("key3---sub3---sub4", "value3")
      
      expect(Dir.glob(File.join(cache_path_with_delimiter, "*")).length).to be > 0
      
      store_with_delimiter.clear
      
      expect(Dir.glob(File.join(cache_path_with_delimiter, "*")).length).to eq(0)
    end

    it "uses fetch correctly with subdirectory structure" do
      result = store_with_delimiter.fetch("new---key") { "computed" }
      expect(result).to eq("computed")
      expect(store_with_delimiter.read("new---key")).to eq("computed")
    end

    it "overwrites existing values in subdirectory structure" do
      store_with_delimiter.write("key---sub", "value1")
      store_with_delimiter.write("key---sub", "value2")
      expect(store_with_delimiter.read("key---sub")).to eq("value2")
    end

    it "handles complex objects in subdirectory structure" do
      complex_object = { name: "Test", data: [1, 2, 3] }
      store_with_delimiter.write("obj---data", complex_object)
      expect(store_with_delimiter.read("obj---data")).to eq(complex_object)
    end

    it "handles many levels of nesting" do
      key = "a---b---c---d---e---f"
      store_with_delimiter.write(key, "deep_value")
      expect(store_with_delimiter.read(key)).to eq("deep_value")
    end
  end
end
