# The Bookface on AWS Lambda, packaged as a container image.
#
# Local development does NOT use this — run the app with plain Puma (`bin/rails
# server`). This image is only for the Lambda deployment the CDK stack builds.
#
# Lamby adapts the incoming Lambda event (a Function URL request) to Rack. The
# AWS Lambda Runtime Interface Client is the ENTRYPOINT; CMD names the handler:
# load config/environment (booting Rails), then call Lamby.cmd.
FROM ruby:4.0-bookworm

# The runtime client runs through bundler rather than a global `gem install`: its
# binstub calls Gem.use_gemdeps, so starting it from a dir with a Gemfile.lock
# activates the bundle and hides every gem outside it — a globally installed RIC
# would then vanish with "can't find gem aws_lambda_ric". Keeping it in the
# bundle avoids the whole class of problem.
ENTRYPOINT [ "bundle", "exec", "aws_lambda_ric" ]

RUN mkdir /app \
    && groupadd -g 10001 app \
    && useradd -u 10000 -g app -m app \
    && chown -R app:app /app
USER app
WORKDIR "/app"

ENV BUNDLE_IGNORE_CONFIG=1
ENV BUNDLE_PATH=./vendor/bundle
ENV RAILS_ENV=production

# Install gems first so the dependency layer caches across app changes.
COPY --chown=app:app Gemfile Gemfile.lock* ./
RUN bundle config set --local without 'development test' \
    && bundle install

COPY --chown=app:app . .

# Fingerprint assets into public/assets. No Node, no bundling step — Stimulus and
# Turbo ship inside their gems and are delivered by importmap. The dummy key is
# build-time only; the real SECRET_KEY_BASE arrives as an env var.
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# The handler: load config/environment (booting Rails), then call Lamby.cmd.
# CMD is the real-Lambda contract (the service turns it into _HANDLER); local
# emulators don't always, so bake _HANDLER in as a default too. On real Lambda
# the service overwrites it, so the two can't drift.
ENV _HANDLER="config/environment.Lamby.cmd"
CMD ["config/environment.Lamby.cmd"]
