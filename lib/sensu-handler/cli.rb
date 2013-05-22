require 'net/http'
require 'json'
require 'sensu-handler/utils'
require 'sensu-plugin/utils'

module Sensu
  module Handler 
    class CLI
      include Sensu::Handler::Utils

      # Implementing classes should override this.

      def handle
        puts 'ignoring event -- no handler defined'
      end

      # This works just like Plugin::CLI's autorun.

      @@autorun = self
      class << self
        def method_added(name)
          if name == :handle
            @@autorun = self
          end
        end
      end

      at_exit do
        handler = @@autorun.new
        handler.read_event(STDIN)
        begin
          handler.filter
          handler.handle
        rescue SensuFilterException => e
          puts e
        end
      end

    end

  end

end
