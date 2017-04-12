require 'segmentio/analytics/defaults'
require 'segmentio/analytics/utils'
require 'segmentio/analytics/defaults'
require 'segmentio/analytics/request'

module Segmentio
  class Analytics
    class Worker
      include Segmentio::Analytics::Utils
      include Segmentio::Analytics::Defaults

      # public: Creates a new worker
      #
      # The worker continuously takes messages off the queue
      # and makes requests to the segment.io api
      #
      # queue   - Queue synchronized between client and worker
      # write_key  - String of the project's Write key
      # options - Hash of worker options
      #           batch_size - Fixnum of how many items to send in a batch
      #           on_error   - Proc of what to do on an error
      #
      def initialize(queue, write_key, options = {})
        symbolize_keys! options
        @queue = queue
        @write_key = write_key
        @batch_size = options[:batch_size] || Queue::BATCH_SIZE
        @on_error = options[:on_error] || Proc.new { |status, error| }
        @batch = []
        @lock = Mutex.new
      end

      # public: Continuously runs the loop to check for new events
      #
      def run
        until Thread.current[:should_exit]
          return if @queue.empty?

          flush_queue
          process_batch
        end

        flush_queue until_empty: true
        process_batch
      end

      # public: Check whether we have outstanding requests.
      #
      def is_requesting?
        @lock.synchronize { !@batch.empty? }
      end

      private

      def flush_queue(until_empty: false)
        use_batch = !until_empty
        @lock.synchronize do
          until (use_batch && @batch.length >= @batch_size) || @queue.empty?
            @batch << @queue.pop
          end
        end
      end

      def process_batch
        res = Request.new.post @write_key, @batch
        @on_error.call res.status, res.error unless res.status == 200
        @lock.synchronize { @batch.clear }
      end
    end
  end
end
