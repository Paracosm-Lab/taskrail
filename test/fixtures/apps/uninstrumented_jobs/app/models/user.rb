class User
  def self.find(id) = new(id)
  def self.inactive = []

  attr_reader :id

  def initialize(id = nil)
    @id = id
  end

  def orders = []
  def anonymize! = true
end
