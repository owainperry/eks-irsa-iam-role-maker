FROM ruby:3.1.2-buster
RUN gem install aws-sdk-iam
COPY main.rb /runner 
ENTRYPOINT ["/runner"]