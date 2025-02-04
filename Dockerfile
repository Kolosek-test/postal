FROM ruby:3.2.2-bullseye AS base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  software-properties-common dirmngr apt-transport-https \
  && (curl -sL https://deb.nodesource.com/setup_20.x | bash -) \
  && rm -rf /var/lib/apt/lists/*

# Install main dependencies
RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  build-essential  \
  netcat \
  curl \
  libmariadb-dev \
  libcap2-bin \
  nano \
  nodejs

RUN setcap 'cap_net_bind_service=+ep' /usr/local/bin/ruby

# Configure 'postal' to work everywhere (when the binary exists
# later in this process)
ENV PATH="/opt/postal/app/bin:${PATH}"

# Setup an application
RUN useradd -r -d /opt/postal -m -s /bin/bash -u 999 postal
USER postal
RUN mkdir -p /opt/postal/app /opt/postal/config
WORKDIR /opt/postal/app

# Install bundler
RUN gem install bundler -v 2.5.6 --no-doc

# Install the latest and active gem dependencies and re-run
# the appropriate commands to handle installs.
COPY --chown=postal Gemfile Gemfile.lock ./
RUN bundle install

# Copy the application (and set permissions)
COPY ./docker/wait-for.sh /docker-entrypoint.sh
COPY --chown=postal . .

# Export the version
ARG VERSION=unspecified
RUN echo $VERSION > VERSION

# Set paths for when running in a container
ENV POSTAL_CONFIG_FILE_PATH=/config/postal.yml

# Set the CMD
ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD ["postal"]

# ci target - use --target=ci to skip asset compilation
FROM base AS ci

# full target - default if no --target option is given
FROM base AS full

RUN RAILS_GROUPS=assets bundle exec rake assets:precompile
RUN touch /opt/postal/app/public/assets/.prebuilt
