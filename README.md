# optica-client

This `optica-client` is a CLI for Airbnb's [Optica](https://github.com/airbnb/optica) service.
It's command-line name is `optical`.

## Installation

Install it via Rubygems:

    $ gem install optica-client

To use in an app, add this line to your application's Gemfile:

```ruby
gem 'optica-client'
```

And then execute:

    $ bundle

## Usage

```text
Usage: optical [options] [FIELD=FILTER] [FIELD2=FILTER2...]

  Fetch host information from Optica, and cache it for 15 minutes. Output the
  fetched information as single-line JSON hashes, suitable for furhter processing with `jq`.

  FIELD: any optica field; see your optica host for availible fields
  FILTER: either a bare string, like "optica", or a regex string, like "/^(o|O)ptica?/"

Options:
    -s, --select a,b,c               Retrieve the given fields, in addition to the defaults
    -a, --all                        Retrieve all fields (default is just role,id,hostname)
    -v, --verbose                    Print debug information to STDERR
    -p, --pretty[=true]              Pretty-print JSON (default true when STDOUT is a TTY)
    -r, --refresh                    Delete cache before performing request.
    -h, --host URI                   Optica host (default "https://optica.d.musta.ch")
    -H, --set-default-host URI       Set the default optica host
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/justjake/optica-cleint.
