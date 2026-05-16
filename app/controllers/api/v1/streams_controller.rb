module Api
  module V1
    class StreamsController < ApplicationController
      include ActionController::Live

      POLL_SECONDS = 2
      MAX_STREAM_SECONDS = 5.minutes

      def show
        response.headers["Content-Type"] = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"

        queue = queue_slug
        cursor = write_snapshot(queue)
        deadline = MAX_STREAM_SECONDS.from_now

        while Time.current < deadline
          sleep POLL_SECONDS
          next_cursor = DashboardPayloadBuilder.cursor(queue_slug: queue)
          if next_cursor == cursor
            write_event("heartbeat", { event_type: "heartbeat", cursor: cursor, emitted_at: Time.current.iso8601 })
          else
            cursor = write_snapshot(queue)
          end
        end
      rescue IOError, ActionController::Live::ClientDisconnected
        nil
      rescue StandardError => e
        Rails.logger.error("dashboard stream failed: #{e.class}: #{e.message}")
      ensure
        response.stream.close
      end

      private

      def queue_slug
        return params[:queue] if params[:queue].present?

        WorkQueue.order(:created_at).limit(1).pick(:slug) || raise(ActiveRecord::RecordNotFound, "No queues found")
      end

      def write_snapshot(queue)
        payload = DashboardPayloadBuilder.snapshot(queue_slug: queue, limit: params.fetch(:limit, DashboardPayloadBuilder::ACTIVE_LIMIT))
        write_event("snapshot", payload)
        payload.fetch(:cursor)
      end

      def write_event(event_name, payload)
        response.stream.write("event: #{event_name}\n")
        response.stream.write("data: #{JSON.dump(payload)}\n\n")
      end
    end
  end
end
