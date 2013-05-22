require 'sensu/client'
require 'sensu-handler/utils'
require 'sensu/base'

module Sensu
  module Handler
    class AMQP
      include Sensu::Handler::Utils


      def self.run(options={})
	client = self.new(options)
	EM::run do
	  client.start
	  client.trap_signals
	end
      end

      def initialize(options={})
	base = Sensu::Base.new(options)
	@logger = base.logger
	@settings = base.settings
	@extensions = base.extensions
	base.setup_process
	@timers = Array.new
	@checks_in_progress = Array.new
	@safe_mode = @settings[:client][:safe_mode] || false

	#Get the queu name from config if available, otherwise set it as the class name

	if @settings[self.class.name.downcase.to_sym].kind_of?(Hash) and @settings[self.class.name.downcase.to_sym][:queue_name] != nil
	  @queue_name = @settings[self.class.name.downcase.to_sym][:queue_name]
	else 
	  @queue_name = self.class.name.downcase
	end
      end

      def handle
        @logger.error('ignoring event -- no handler defined')
        exit 1
      end

      def setup_rabbitmq
	@logger.info('connecting to rabbitmq', {
	  :settings => @settings[:rabbitmq]
	})
	@rabbitmq = Sensu::RabbitMQ.connect(@settings[:rabbitmq])
	@rabbitmq.on_error do |error|
	  @logger.fatal('rabbitmq connection error', {
	    :error => error.to_s
	  })
	  stop
	end
	@rabbitmq.before_reconnect do
	  @logger.warn('reconnecting to rabbitmq')
	end
	@rabbitmq.after_reconnect do
	  @logger.info('reconnected to rabbitmq')
	end
	@amq = @rabbitmq.channel
      end

      def setup_listener
	@logger.debug('subscribing to mongo events')

	@events_queue = @amq.queue!(@queue_name)
	@events_queue.bind(@amq.direct(@queue_name))
	@events_queue.subscribe(:ack => true) do |header, payload|
	  @event = Oj.load(payload)

	  #Nasty hack to recursively convert symbol key names to strings
	  @event = JSON.parse(@event.to_json)

	  @logger.info('received event', {
	    :event => @event
	  })
	  begin
	    filter
	    handle
	  rescue SensuFilterException => e
	    @logger.warn(e)
	  end
	end

      end

      def unsubscribe
	@logger.warn('unsubscribing from client subscriptions')
	if @rabbitmq.connected?
	  @events_queue.unsubscribe
	else
	  @events_queue.before_recovery do
	    @events_queue.unsubscribe
	  end
	end
      end

      def start
	setup_rabbitmq
	setup_listener
      end

      def stop
	@logger.warn('stopping')
	@timers.each do |timer|
	  timer.cancel
	end
	unsubscribe
	@rabbitmq.close
	@logger.warn('stopping reactor')
	EM::stop_event_loop
      end

      def trap_signals
	@signals = Array.new
	Sensu::STOP_SIGNALS.each do |signal|
	  Signal.trap(signal) do
	    @signals << signal
	  end
	end
	EM::PeriodicTimer.new(1) do
	  signal = @signals.shift
	  if Sensu::STOP_SIGNALS.include?(signal)
	    @logger.warn('received signal', {
	      :signal => signal
	    })
	    stop
	  end
	end
      end
    end 
  end
end
