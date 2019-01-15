# QiniuStorage

Unoffical gem for Qiniu Cloud Storage

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'qiniu-storage'
```

And then execute:

```bash
$ bundle
```
## Usage

```ruby
client = QiniuStorage.new(access_key: ENV['QINIU_ACCESS_KEY'], secret_key: ENV['QINIU_SECRET_KEY'])

# List buckets
buckets = client.buckets

# Create bucket
bucket = client.bucket('test')
# Specify region
bucket = client.bucket('test', region: 'z1')
bucket.create

# Delete bucket
bucket.drop

# Manage files
files = bucket.files
# => #<QiniuStorage::File::Bundle:0x00007fa233319ef8 ...>
files.keys
# => ['key1', 'key2']
files.names
# => ['test:key1', 'test:key2']
files.batch_stat
# => [{"code"=>200, "data"=>{"fsize"=>4, "hash"=>"FhBzq2zaS5kc0p-eg6MH80AErpMn", ...}}, ... ]
files.delete_all 
# => [{"code"=>200}, {"code"=>200}]
files.next?
# => true
next_files = files.next
# => #<QiniuStorage::File::Bundle:0x00007fa2339b5a78 ...>
files.keys
# => ['key3']
files.next?
# => false

# Upload file
file = bucket.file("xxxx")
file.attach(StringIO.new("Hello, world"))
```

## TODO

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/songjiz/qiniu_storage.
