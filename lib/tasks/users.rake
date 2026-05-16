namespace :taskrail do
  desc "Create or update an admin user from EMAIL and PASSWORD"
  task create_admin: :environment do
    email = ENV.fetch("EMAIL").to_s.strip.downcase
    password = ENV.fetch("PASSWORD")

    user = User.find_or_initialize_by(email: email)
    user.password = password if user.new_record?
    user.password_confirmation = password if user.new_record?
    user.admin = true
    user.save!

    puts "Admin user ready: #{user.email}"
  end
end
