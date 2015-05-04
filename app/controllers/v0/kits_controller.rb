module V0
  class KitsController < ApplicationController

    def index
      @kits = Kit.all
      paginate json: @kits, each_serializer: DetailedKitSerializer
    end

    def show
      @kit = Kit.friendly.find(params[:id])
      authorize @kit
      render json: @kit, serializer: DetailedKitSerializer
    end

  end
end
