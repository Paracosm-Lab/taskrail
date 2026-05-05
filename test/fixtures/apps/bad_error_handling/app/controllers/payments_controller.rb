class PaymentsController
  def params
    { amount: 100 }
  end

  def render(json:, status: 200)
    { json: json, status: status }
  end

  def create
    charge = PaymentGateway.charge(params[:amount])
    render json: charge
  rescue => e
    puts e.message
    render json: { error: "something went wrong" }, status: 500
  end
end
