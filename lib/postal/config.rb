# frozen_string_literal: true

require "erb"
require "yaml"
require "pathname"
require "cgi"
require "openssl"
require "fileutils"
require "konfig"
require "konfig/sources/environment"
require "konfig/sources/yaml"
require "dotenv"
require "klogger"

require_relative "error"
require_relative "version"
require_relative "config_schema"
require_relative "legacy_config_source"

module Postal

  class << self

    # Return the path to the config file
    #
    # @return [String]
    def config_file_path
      ENV.fetch("POSTAL_CONFIG_FILE_PATH", "config/postal/postal.yml")
    end

    def initialize_config
      sources = []

      # Load environment variables to begin with. Any config provided
      # by an environment variable will override any provided in the
      # config file.
      Dotenv.load(".env")
      sources << Konfig::Sources::Environment.new(ENV)

      # If a config file exists, we need to load that. Config files can
      # either be legacy (v1) or new (v2). Any file without a 'version'
      # key is a legacy file whereas new-style config files will include
      # the 'version: 2' key/value.
      if File.file?(config_file_path)
        puts "Loading config from #{config_file_path}"

        config_file = File.read(config_file_path)
        yaml = YAML.safe_load(config_file)
        config_version = yaml["version"] || 1
        case config_version
        when 1
          puts "WARNING: Using legacy config file format. Upgrade your postal.yml to use"
          puts "version 2 of the Postal configuration or configure using environment"
          puts "variables. See https://postalserver.io/config-v2 for details."
          sources << LegacyConfigSource.new(yaml)
        when 2
          sources << Konfig::Sources::YAML.new(config_file)
        else
          raise "Invalid version specified in Postal config file. Must be 1 or 2."
        end
      else
        puts "No configuration file found at #{config_file_path}"
        puts "Only using environment variables for configuration"
      end

      # Build configuration with the provided sources.
      Konfig::Config.build(ConfigSchema, sources: sources)
    end

    def host_with_protocol
      @host_with_protocol ||= "#{Config.postal.web_protocol}://#{Config.postal.web_hostname}"
    end

    def logger
      @logger ||= begin
        k = Klogger.new(nil, destination: Config.logging.enabled? ? $stdout : "/dev/null", highlight: Config.logging.highlighting_enabled?)
        k.add_destination(graylog_logging_destination) if Config.gelf.host.present?
        k
      end
    end

    def process_name
      @process_name ||= begin
        "host:#{Socket.gethostname} pid:#{Process.pid}"
      rescue StandardError
        "pid:#{Process.pid}"
      end
    end

    def locker_name
      string = process_name.dup
      string += " job:#{Thread.current[:job_id]}" if Thread.current[:job_id]
      string += " thread:#{Thread.current.native_thread_id}"
      string
    end

    def locker_name_with_suffix(suffix)
      "#{locker_name} #{suffix}"
    end

    def signing_key
      @signing_key ||= OpenSSL::PKey::RSA.new(File.read(Config.postal.signing_key_path))
    end

    def rp_dkim_dns_record
      public_key = signing_key.public_key.to_s.gsub(/-+[A-Z ]+-+\n/, "").gsub(/\n/, "")
      "v=DKIM1; t=s; h=sha256; p=#{public_key};"
    end

    def ip_pools?
      Config.postal.use_ip_pools?
    end

    def graylog_logging_destination
      @graylog_logging_destination ||= begin
        notifier = GELF::Notifier.new(Config.gelf.host, Config.gelf.port, "WAN")
        proc do |_logger, payload, group_ids|
          short_message = payload.delete(:message) || "[message missing]"
          notifier.notify!(short_message: short_message, **{
            facility: Config.gelf.facility,
            _environment: Config.rails.environment,
            _version: Postal::VERSION.to_s,
            _group_ids: group_ids.join(" ")
          }.merge(payload.transform_keys { |k| "_#{k}".to_sym }.transform_values(&:to_s)))
        end
      end
    end

  end

  Config = initialize_config

end
