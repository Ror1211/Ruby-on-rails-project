# encoding: utf-8

require 'astrolabe/builder'
require 'digest/md5'

module RuboCop
  # ProcessedSource contains objects which are generated by Parser
  # and other information such as disabled lines for cops.
  # It also provides a convenient way to access source lines.
  class ProcessedSource
    STRING_SOURCE_NAME = '(string)'.freeze

    attr_reader :path, :buffer, :ast, :comments, :tokens, :diagnostics,
                :parser_error, :raw_source, :ruby_version

    def self.from_file(path, ruby_version)
      file = File.read(path)
      new(file, ruby_version, path)
    rescue Errno::ENOENT
      raise RuboCop::Error, "No such file or directory: #{path}"
    end

    def initialize(source, ruby_version, path = nil)
      # In Ruby 2, source code encoding defaults to UTF-8. We follow the same
      # principle regardless of which Ruby version we're running under.
      # Encoding comments will override this setting.
      source.force_encoding(Encoding::UTF_8)

      @raw_source = source
      @path = path
      @diagnostics = []
      @ruby_version = ruby_version

      parse(source, ruby_version)
    end

    def comment_config
      @comment_config ||= CommentConfig.new(self)
    end

    def disabled_line_ranges
      comment_config.cop_disabled_line_ranges
    end

    # Returns the source lines, line break characters removed, excluding a
    # possible __END__ and everything that comes after.
    def lines
      @lines ||= begin
        all_lines = raw_source.lines.map(&:chomp)
        last_token_line = tokens.any? ? tokens.last.pos.line : all_lines.size
        result = []
        all_lines.each_with_index do |line, ix|
          break if ix >= last_token_line && line == '__END__'
          result << line
        end
        result
      end
    end

    def [](*args)
      lines[*args]
    end

    def valid_syntax?
      return false if @parser_error
      @diagnostics.none? { |d| [:error, :fatal].include?(d.level) }
    end

    # Raw source checksum for tracking infinite loops.
    def checksum
      Digest::MD5.hexdigest(@raw_source)
    end

    private

    def parse(source, ruby_version)
      buffer_name = @path || STRING_SOURCE_NAME
      @buffer = Parser::Source::Buffer.new(buffer_name, 1)

      begin
        @buffer.source = source
      rescue EncodingError => error
        @parser_error = error
        return
      end

      parser = create_parser(ruby_version)

      begin
        @ast, @comments, tokens = parser.tokenize(@buffer)
      rescue Parser::SyntaxError # rubocop:disable Lint/HandleExceptions
        # All errors are in diagnostics. No need to handle exception.
      end

      @tokens = tokens.map { |t| Token.from_parser_token(t) } if tokens
    end

    def parser_class(ruby_version)
      case ruby_version
      when 1.9
        require 'parser/ruby19'
        Parser::Ruby19
      when 2.0
        require 'parser/ruby20'
        Parser::Ruby20
      when 2.1
        require 'parser/ruby21'
        Parser::Ruby21
      when 2.2
        require 'parser/ruby22'
        Parser::Ruby22
      when 2.3
        require 'parser/ruby23'
        Parser::Ruby23
      else
        fail ArgumentError, "Unknown Ruby version: #{ruby_version.inspect}"
      end
    end

    def create_parser(ruby_version)
      builder = Astrolabe::Builder.new

      parser_class(ruby_version).new(builder).tap do |parser|
        # On JRuby and Rubinius, there's a risk that we hang in tokenize() if we
        # don't set the all errors as fatal flag. The problem is caused by a bug
        # in Racc that is discussed in issue #93 of the whitequark/parser
        # project on GitHub.
        parser.diagnostics.all_errors_are_fatal = (RUBY_ENGINE != 'ruby')
        parser.diagnostics.ignore_warnings = false
        parser.diagnostics.consumer = lambda do |diagnostic|
          @diagnostics << diagnostic
        end
      end
    end
  end
end
