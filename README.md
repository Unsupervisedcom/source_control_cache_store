# SourceControlCacheStore

Rails cache store appropriate for storing the results in source control.

## Overview

`SourceControlCacheStore` is a Rails cache store (compatible with Rails 7.1 and higher) that stores cache entries as files suitable for version control. Each cache entry is stored as two files:

- `#{hash}.key` - the full key that was used
- `#{hash}.value` - the serialized value that was stored

This cache store is designed to be committed to version control, making it ideal for caching build artifacts, compiled assets, or other deterministic results that should be shared across different environments.

## Features

- **File-based storage**: Each cache entry is stored as separate `.key` and `.value` files
- **Hashed filenames**: Uses SHA256 hashing for keys to create consistent, filesystem-safe filenames
- **No expiration**: Cache entries do NOT honor expiration parameters - they persist until explicitly deleted
- **Rails 7.1+ compatible**: Implements the ActiveSupport::Cache::Store interface

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'source_control_cache_store'
```

And then execute:

```bash
$ bundle install
```

## Usage

Configure your Rails application to use the SourceControlCacheStore:

```ruby
# config/application.rb or config/environments/*.rb
config.cache_store = :source_control_cache_store, cache_path: Rails.root.join("tmp", "cache")
```

Or create an instance directly:

```ruby
require 'source_control_cache_store'

cache = ActiveSupport::Cache::SourceControlCacheStore.new(
  cache_path: "/path/to/cache/directory"
)

# Write to cache
cache.write("my_key", "my_value")

# Read from cache
value = cache.read("my_key")  # => "my_value"

# Fetch with block (returns cached value or executes block and caches result)
result = cache.fetch("computed_key") do
  expensive_computation()
end

# Delete a cache entry
cache.delete("my_key")

# Clear all cache entries
cache.clear
```

### Subdirectory Delimiter

You can optionally configure a `subdirectory_delimiter` to organize cache entries into nested subdirectories based on key segments:

```ruby
cache = ActiveSupport::Cache::SourceControlCacheStore.new(
  cache_path: "/path/to/cache/directory",
  subdirectory_delimiter: "---"
)

# With delimiter "---", key "foo---bar---boo-ba" creates:
# /path/to/cache/directory/
#   hash(foo)/
#     _key_chunk (contains "foo")
#     hash(bar)/
#       _key_chunk (contains "bar")
#       hash(boo-ba)/
#         _key_chunk (contains "boo-ba")
#         value (contains the cached value)

cache.write("foo---bar---boo-ba", "27")
value = cache.read("foo---bar---boo-ba")  # => "27"
```

When a delimiter is configured:
- The cache key is split by the delimiter into segments
- Each segment creates a subdirectory named `hash(segment)` using SHA256
- Each subdirectory contains a `_key_chunk` file with the original segment text
- The cached value is stored in a `value` file in the final subdirectory

This feature is useful for organizing cache entries hierarchically when keys have a natural structure.

## Key Features

### Hashed Keys

Keys are hashed using SHA256 to create filesystem-safe filenames. The original key is preserved in the `.key` file, while the hash is used for the filename:

```ruby
cache.write("user:123:profile", { name: "John" })
# Creates:
# - abc123def456.key (contains "user:123:profile")
# - abc123def456.value (contains serialized hash)
```

### No Expiration

Unlike other cache stores, `SourceControlCacheStore` intentionally ignores expiration parameters:

```ruby
# The expires_in option is ignored
cache.write("key", "value", expires_in: 1.hour)
cache.read("key")  # => "value" (will never expire)
```

This behavior is by design, as the cache is intended for version-controlled content that should be explicitly managed rather than automatically expired.

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bundle exec rspec` to run the tests.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Unsupervisedcom/source_control_cache_store.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

