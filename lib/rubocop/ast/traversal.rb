# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
module RuboCop
  module AST
    # Provides methods for traversing an AST.
    # Does not transform an AST; for that, use Parser::AST::Processor.
    # Override methods to perform custom processing. Remember to call `super`
    # if you want to recursively process descendant nodes.
    module Traversal
      TYPE_TO_METHOD = Hash.new { |h, type| h[type] = :"on_#{type}" }

      def walk(node)
        return if node.nil?

        send(TYPE_TO_METHOD[node.type], node)
        nil
      end

      NO_CHILD_NODES    = %i[true false nil int float complex
                             rational str sym regopt self lvar
                             ivar cvar gvar nth_ref back_ref cbase
                             arg restarg blockarg shadowarg
                             kwrestarg zsuper redo retry
                             forward_args forwarded_args
                             match_var match_nil_pattern empty_else
                             forward_arg lambda procarg0 __ENCODING__].freeze
      ONE_CHILD_NODE    = %i[splat kwsplat block_pass not break next
                             preexe postexe match_current_line defined?
                             arg_expr pin match_rest if_guard unless_guard
                             match_with_trailing_comma].freeze
      MANY_CHILD_NODES  = %i[dstr dsym xstr regexp array hash pair
                             mlhs masgn or_asgn and_asgn rasgn mrasgn
                             undef alias args super yield or and
                             while_post until_post iflipflop eflipflop
                             match_with_lvasgn begin kwbegin return
                             in_match match_alt
                             match_as array_pattern array_pattern_with_tail
                             hash_pattern const_pattern find_pattern
                             index indexasgn].freeze
      SECOND_CHILD_ONLY = %i[lvasgn ivasgn cvasgn gvasgn optarg kwarg
                             kwoptarg].freeze
      private_constant :NO_CHILD_NODES, :ONE_CHILD_NODE, :MANY_CHILD_NODES, :SECOND_CHILD_ONLY

      NO_CHILD_NODES.each do |type|
        module_eval("def on_#{type}(node); end", __FILE__, __LINE__)
      end

      ONE_CHILD_NODE.each do |type|
        module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          def on_#{type}(node)
            if (child = node.children[0])
              send(TYPE_TO_METHOD[child.type], child)
            end
          end
        RUBY
      end

      MANY_CHILD_NODES.each do |type|
        module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          def on_#{type}(node)
            node.children.each { |child| send(TYPE_TO_METHOD[child.type], child) }
            nil
          end
        RUBY
      end

      SECOND_CHILD_ONLY.each do |type|
        # Guard clause is for nodes nested within mlhs
        module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          def on_#{type}(node)
            if (child = node.children[1])
              send(TYPE_TO_METHOD[child.type], child)
            end
          end
        RUBY
      end

      def on_const(node)
        return unless (child = node.children[0])

        send(TYPE_TO_METHOD[child.type], child)
      end

      def on_casgn(node)
        children = node.children
        if (child = children[0]) # always const???
          send(TYPE_TO_METHOD[child.type], child)
        end
        return unless (child = children[2])

        send(TYPE_TO_METHOD[child.type], child)
      end

      def on_class(node)
        children = node.children
        child = children[0] # always const???
        send(TYPE_TO_METHOD[child.type], child)
        if (child = children[1])
          send(TYPE_TO_METHOD[child.type], child)
        end
        return unless (child = children[2])

        send(TYPE_TO_METHOD[child.type], child)
      end

      def on_def(node)
        children = node.children
        on_args(children[1])
        return unless (child = children[2])

        send(TYPE_TO_METHOD[child.type], child)
      end

      def on_send(node)
        node.children.each_with_index do |child, i|
          next if i == 1

          send(TYPE_TO_METHOD[child.type], child) if child
        end
        nil
      end

      alias on_csend on_send

      def on_op_asgn(node)
        children = node.children
        child = children[0]
        send(TYPE_TO_METHOD[child.type], child)
        child = children[2]
        send(TYPE_TO_METHOD[child.type], child)
      end

      def on_defs(node)
        children = node.children
        child = children[0]
        send(TYPE_TO_METHOD[child.type], child)
        on_args(children[2])
        return unless (child = children[3])

        send(TYPE_TO_METHOD[child.type], child)
      end

      def on_if(node)
        children = node.children
        child = children[0]
        send(TYPE_TO_METHOD[child.type], child)
        if (child = children[1])
          send(TYPE_TO_METHOD[child.type], child)
        end
        return unless (child = children[2])

        send(TYPE_TO_METHOD[child.type], child)
      end

      def on_while(node)
        children = node.children
        child = children[0]
        send(TYPE_TO_METHOD[child.type], child)
        return unless (child = children[1])

        send(TYPE_TO_METHOD[child.type], child)
      end

      alias on_until  on_while
      alias on_module on_while
      alias on_sclass on_while

      def on_block(node)
        children = node.children
        child = children[0]
        send(TYPE_TO_METHOD[child.type], child) # can be send, zsuper...
        on_args(children[1])
        return unless (child = children[2])

        send(TYPE_TO_METHOD[child.type], child)
      end

      def on_case(node)
        node.children.each do |child|
          send(TYPE_TO_METHOD[child.type], child) if child
        end
        nil
      end

      alias on_rescue     on_case
      alias on_resbody    on_case
      alias on_ensure     on_case
      alias on_for        on_case
      alias on_when       on_case
      alias on_case_match on_case
      alias on_in_pattern on_case
      alias on_irange     on_case
      alias on_erange     on_case

      def on_numblock(node)
        children = node.children
        child = children[0]
        send(TYPE_TO_METHOD[child.type], child)
        return unless (child = children[2])

        send(TYPE_TO_METHOD[child.type], child)
      end

      defined = instance_methods(false)
                .grep(/^on_/)
                .map { |s| s.to_s[3..-1].to_sym } # :on_foo => :foo

      to_define = ::Parser::Meta::NODE_TYPES.to_a
      to_define -= defined
      to_define -= %i[numargs ident] # transient
      to_define -= %i[blockarg_expr restarg_expr] # obsolete
      to_define -= %i[objc_kwarg objc_restarg objc_varargs] # mac_ruby
      to_define.each do |type|
        module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
          def on_#{type}(node)
            node.children.each do |child|
              next unless child.class == Node
              send(TYPE_TO_METHOD[child.type], child)
            end
            nil
          end
        RUBY
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength
