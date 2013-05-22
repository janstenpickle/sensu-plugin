require 'net/http'
require 'json'
require 'sensu-plugin/utils'

module Sensu
  module Handler
    module Utils

      class SensuFilterException < Exception
      end

      include Sensu::Plugin::Utils

      # Filters exit the proccess if the event should not be handled.
      # Implementation of the default filters is below.

      def filter
	filter_disabled
	filter_repeated
	filter_silenced
	filter_dependencies
      end


      # Helpers and filters.

      def bail(msg)
	raise SensuFilterException, msg + ': ' + @event['client']['name'] + '/' + @event['check']['name']
      end

      def api_request(method, path, &blk)
	settings = @settings if settings.nil?
	http = Net::HTTP.new(settings['api']['host'], settings['api']['port'])
	req = net_http_req_class(method).new(path)
	if settings['api']['user'] && settings['api']['password']
	  req.basic_auth(settings['api']['user'], settings['api']['password'])
	end
	yield(req) if block_given?
	http.request(req)
      end

      def filter_disabled
	if @event['check']['alert'] == false
	  bail 'alert disabled'
	end
      end

      def filter_repeated
	occurrences = @event['check']['occurrences'] || 1
	interval    = @event['check']['interval']    || 30
	refresh     = @event['check']['refresh']     || 1800
	if @event['occurrences'] < occurrences
	  bail 'not enough occurrences'
	end
	if @event['occurrences'] > occurrences && @event['action'] == 'create'
	  number = refresh.fdiv(interval).to_i
	  unless number == 0 || @event['occurrences'] % number == 0
	    bail 'only handling every ' + number.to_s + ' occurrences'
	  end
	end
      end

      def stash_exists?(path)
	api_request(:GET, '/stash' + path).code == '200'
      end

      def filter_silenced
	stashes = {
	  'client' => '/silence/' + @event['client']['name'],
	  'check'  => '/silence/' + @event['client']['name'] + '/' + @event['check']['name']
	}
	stashes.each do |scope, path|
	  begin
	    timeout(2) do
	      if stash_exists?(path)
		bail scope + ' alerts silenced'
	      end
	    end
	  rescue Timeout::Error
	    puts 'timed out while attempting to query the sensu api for a stash'
	  end
	end
      end

      def event_exists?(client, check)
	api_request(:GET, '/event/' + client + '/' + check).code == '200'
      end

      def filter_dependencies
	if @event['check'].has_key?('dependencies')
	  if @event['check']['dependencies'].is_a?(Array)
	    @event['check']['dependencies'].each do |check|
	      begin
		timeout(2) do
		  if event_exists?(@event['client']['name'], check)
		    bail 'check dependency event exists'
		  end
		end
	      rescue Timeout::Error
		puts 'timed out while attempting to query the sensu api for an event'
	      end
	    end
	  end
        end
      end

    end
  end

end
