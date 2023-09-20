# frozen_string_literal: true

require "logger"
require "json"
require "ostruct"
require "cgi"
require "net/https"
require "uri"

class NPM
  def self.search(query)
    url = "https://registry.npmjs.com/-/v1/search?size=10&text="

    packages = JSON.parse(
      Net::HTTP.get(URI("#{url}#{CGI.escape(query)}"))
    ).fetch("objects")

    packages.map do |package|
      package = package["package"]
      links = package["links"]

      {
        name: package["name"],
        version: package["version"],
        info: package["description"],
        homepage_uri: links["homepage"] || links["npm"],
        source_code_uri: links["repository"],
        package_uri: links["npm"]
      }
    end
  rescue StandardError
    []
  end
end

class AlfredWorkflow
  attr_reader :query

  def initialize(query)
    @query = query
  end

  def feedback
    @feedback ||= {items: []}
  end

  def items
    feedback[:items]
  end

  def call
    debug ruby_version: RUBY_VERSION, query: query

    search_results = NPM.search(query)
    search_results.each(&method(:build_package_item))

    if search_results.empty?
      items << {
        uid: "no-results",
        title: "No NPM packages found for '#{query}'.",
        subtitle: "Search on npmjs.org instead",
        valid: true,
        icon: "#{__dir__}/icon.png",
        arg: "https://npmjs.com/search?q=#{CGI.escape(query)}"
      }
    end
  rescue StandardError => error
    error(error)
  ensure
    debug :feedback, feedback
    puts JSON.pretty_generate(feedback)
  end

  def build_package_item(package)
    package = OpenStruct.new(package)

    debug package

    items << {
      uid: package.name,
      title: package.name,
      subtitle: "v#{package.version} - #{package.info}",
      arg: "https://npmjs.org/package/#{package.name}",
      icon: "#{__dir__}/icon.png",
      valid: true,
      mods: {
        alt: mod_item(title: "Source code url", arg: package.source_code_uri),
        ctrl: mod_item(title: "Home page url", arg: package.homepage_uri),
        cmd: mod_item(title: "Package url", arg: package.package_uri)
      }
    }
  end

  def mod_item(title:, arg:)
    valid = !arg.to_s.empty?

    {
      valid: valid,
      subtitle: valid ? "Open #{arg}" : "#{title} not available",
      arg: arg
    }
  end

  def logger
    @logger ||= Logger.new("/tmp/alfred.log")
  end

  def debug(*args, **kwargs)
    logger.debug(JSON.pretty_generate(args: args, kwargs: kwargs))
  end

  def error(error)
    logger.error(
      JSON.pretty_generate(
        class: error.class.name,
        message: error.message,
        backtrace: error.backtrace
      )
    )

    error_item = {
      uid: "error",
      subtitle: "Search on npms.org instead",
      arg: "https://npmjs.org/search?q=#{CGI.escape(query)}",
      valid: true
    }

    error_item[:title] = case error
                         when SocketError
                           "Couldn't fetch information from npmjs.org"
                         else
                           "Error: #{error.class}"
                         end

    items << error_item
  end
end

AlfredWorkflow.new(ARGV[0]).call
