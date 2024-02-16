# Pull the base image from the AWS public ECR: https://gallery.ecr.aws/lambda/
FROM public.ecr.aws/lambda/ruby:3.2

# Install the standard devlopment tools so we can run `bundle install` and include
# gems with native extensions like :json, :active_record, etc.
RUN yum install -y amazon-linux-extras && yum group install "Development Tools" -y
RUN yum install -y openssl-devel

# Copy function code
COPY app.rb ${LAMBDA_TASK_ROOT}

# Copy dependency management file
COPY Gemfile ${LAMBDA_TASK_ROOT}

# RUN gem install trilogy

# Install dependencies under LAMBDA_TASK_ROOT
ENV GEM_HOME=${LAMBDA_TASK_ROOT}

RUN bundle install

# Set the CMD to your handler (could also be done as a parameter override outside of the Dockerfile)
CMD [ "app.Functions::RorHarvester.process" ]
