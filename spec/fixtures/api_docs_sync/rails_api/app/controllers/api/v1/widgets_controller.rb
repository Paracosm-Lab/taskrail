module Api
  module V1
    class WidgetsController < ApplicationController
      # Requires Bearer token
      def index
        render json: WidgetSerializer.new(Widget.order(created_at: :desc)).serializable_hash
      end

      # Requires Bearer token
      def create
        widget = Widget.create!(widget_params)
        render json: WidgetSerializer.new(widget).serializable_hash, status: :created
      end

      # Requires Bearer token
      def show
        widget = Widget.find(params[:id])
        render json: WidgetSerializer.new(widget).serializable_hash
      end

      private

      def widget_params
        params.require(:widget).permit(:name, :status)
      end
    end
  end
end
