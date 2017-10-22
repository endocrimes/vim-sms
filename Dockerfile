FROM ruby:2.4.0
COPY Gemfile .
COPY Gemfile.lock .
COPY server.rb .
RUN bundle install

ENTRYPOINT bundle exec ruby server.rb

