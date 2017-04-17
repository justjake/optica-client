require 'yaml'

module Optical
  # Handles storing and loading configurable settings for our CLI
  class Config

    attr_accessor :config_path
    attr_accessor :default_host

    def self.from_file(path)
      new(config_path: path.to_s).reload
    end

    def initialize(hash = {})
      set_all(hash)
    end

    def to_h
      {
        config_path: config_path.to_s,
        default_host: default_host.to_s,
      }
    end

    def write!
      data = YAML.dump(to_h)
      File.write(config_path, data)
    end

    def reload
      return self unless File.exist?(config_path)

      data = YAML.load(File.read(config_path)).merge(config_path: config_path)
      set_all(data)
      self
    end

    def set_all(data)
      data.each do |key, val|
        self.public_send("#{key}=", val)
      end
    end
  end
end
