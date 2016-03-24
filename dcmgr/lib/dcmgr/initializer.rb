# -*- coding: utf-8 -*-

module Dcmgr
  module Initializer

    def self.included(klass)
      klass.extend(ClassMethods)
    end

    module ClassMethods
      def load_conf(conf_class, files = nil)
        depr_msg = %{
          Dcmgr.load_conf is DEPRECATED!
          Use Dcmgr::Configurations.load instead

          Dcmgr.load_conf was used at:
          #{caller.first}
        }

        puts(depr_msg)

        Dcmgr::Configurations.load(conf_class, files)
      end

      def run_initializers(*files)
        unless Dcmgr::Configurations.loaded?
          raise "Complete the configuration prior to run_initializers()."
        end

        @files ||= []
        if files.length == 0
          @files << "*"
        else
          @files = files
        end

        initializer_hooks.each { |n|
          n.call
        }
      end

      def initializer_hooks(&blk)
        @initializer_hooks ||= []
        if blk
          @initializer_hooks << blk
        end
        @initializer_hooks
      end
    end
  end
end
