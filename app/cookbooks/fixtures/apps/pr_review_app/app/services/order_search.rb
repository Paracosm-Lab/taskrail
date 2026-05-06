class OrderSearch
  def unsafe_search(query)
    Order.where("name LIKE '%#{query}%'")
  end

  def safe_search(query)
    Order.where("name LIKE ?", "%#{query}%")
  end
end
