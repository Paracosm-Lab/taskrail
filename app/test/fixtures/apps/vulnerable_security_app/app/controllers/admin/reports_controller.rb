module Admin
  class ReportsController < ApplicationController
    def index
      render plain: LegacyExporter.new.export(params[:path])
    end
  end
end
