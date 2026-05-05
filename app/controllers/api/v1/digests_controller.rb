module Api
  module V1
    class DigestsController < ApplicationController
      rescue_from Engine::TimeWindowParser::InvalidWindow, with: :invalid_window

      def show
        return render json: { error: "missing since" }, status: :bad_request if params[:since].blank?

        since = Engine::TimeWindowParser.parse(params[:since])
        render json: Engine::Digest.generate(since: since, window: params[:since])
      end

      private

      def invalid_window(error)
        render json: { error: error.message }, status: :bad_request
      end
    end
  end
end
