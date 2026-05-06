class WidgetSerializer
  include JSONAPI::Serializer

  attributes :id, :name, :status, :created_at
end
