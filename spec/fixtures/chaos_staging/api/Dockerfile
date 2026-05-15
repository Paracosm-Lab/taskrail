FROM ruby:3.3-alpine
WORKDIR /app
COPY Gemfile /app/Gemfile
RUN bundle install
COPY config.ru /app/config.ru
CMD ["bundle", "exec", "rackup", "-o", "0.0.0.0", "-p", "9292"]
