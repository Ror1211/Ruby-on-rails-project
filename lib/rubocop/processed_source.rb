# encoding: utf-8

module Rubocop
  # ProcessedSource contains objects which are generated by Parser
  # and other information such as disabled lines for cops.
  # It also provides a convenient way to access source lines.
  class ProcessedSource
    attr_reader :buffer, :ast, :comments, :tokens, :diagnostics,
                :comment_config

    def initialize(buffer, ast, comments, tokens, diagnostics)
      @buffer = buffer
      @ast = ast
      @comments = comments
      @tokens = tokens
      @diagnostics = diagnostics
      @comment_config = CommentConfig.new(self)
    end

    def disabled_line_ranges
      comment_config.cop_disabled_line_ranges
    end

    def lines
      if @lines
        @lines
      else
        init_lines
        @lines
      end
    end

    def raw_lines
      if @raw_lines
        @raw_lines
      else
        init_lines
        @raw_lines
      end
    end

    def [](*args)
      lines[*args]
    end

    def valid_syntax?
      @diagnostics.none? { |d| [:error, :fatal].include?(d.level) }
    end

    def file_path
      @buffer.name
    end

    private

    def init_lines
      @raw_lines = @buffer.source.lines
      @lines = @raw_lines.map(&:chomp)
    end
  end
end
