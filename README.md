# The Bookface

A small, real social app — post something, then argue about it in deeply nested
comment threads. It's a Facebook parody, and it's a demo: a Rails app whose
**entire AWS infrastructure is defined in Ruby** with the [AWS CDK for Ruby](https://github.com/aws/aws-cdk-rfcs/pull/939).

- **Rails 8** (no Active Record) on **AWS Lambda** via [Lamby](https://lamby.custardy.com).
- **Auth**: sign in with **Google**, federated through an **Amazon Cognito** user
  pool. Cognito is the system of record for users; the app only speaks OIDC to it.
- **Data**: **DynamoDB**. A `Posts` table, and a hierarchical `Comments` table
  keyed `(post_id, path)` — see below.
- **Reactions**: Facebook-style — one emoji per user per post/comment — with a
  denormalized `{emoji => count}` cache on each item, kept in step with the
  per-user records via a single `TransactWriteItems`.
- **Images**: uploaded **straight from the browser to S3** with presigned POSTs
  (bytes never pass through Lambda), served via **CloudFront**.
- **Infrastructure**: one Ruby file, `infra/stacks/bookface_stack.rb`. No YAML.

## Hierarchical comments, the DynamoDB way

Comments live in one table, partitioned by post and sorted by a **materialized
path** — the chain of time-ordered segment ids from the post down to the comment:

```
reply to the post   ->  path = "<seg>"                 (depth 0)
reply to a comment  ->  path = "<parent.path>/<seg>"   (depth 1, 2, …)
```

Because a DynamoDB Query returns items sorted by the sort key, ordering by `path`
yields the whole thread in **pre-order** — a parent immediately precedes its
subtree, siblings are chronological — from a **single query, no recursion**.
Depth is just the number of `/` separators, so the view indents straight from the
flat result. See `app/models/comment.rb`.

## Local development — plain Puma, no Lambda

Local dev runs the app itself with Puma (`bin/rails server`); Lambda/Lamby is only
for the deployed image. `docker compose` provides the backing services — DynamoDB
Local for data and MinIO (S3-compatible) for images, with the media bucket created
automatically:

```sh
docker compose up -d               # DynamoDB Local (:8000) + MinIO (:9000)
bin/rails dynamoid:create_tables   # create Posts + Comments + Reactions
bin/rails server                   # http://localhost:3000
```

Media defaults to MinIO in development, so image upload works with no extra config.

No Cognito or Google needed locally: in development the header shows a **dev
sign-in** with a few personas (Ada, Grace, Alan) so you can test multi-author
threads. (It's hard-gated to `Rails.env.development?`.)

## Tests

Cucumber feature tests cover the stubbed sign-in, commenting, replying,
replying-to-replies, and image uploads. They use their own `test-*` DynamoDB
tables, so your dev data is untouched.

**On the host** (Capybara + rack_test, no browser). Covers everything except the
`@javascript` browser-upload scenario:

```sh
docker compose up -d dynamodb   # backing store
bin/cucumber --tags 'not @javascript'
```

**In a container with headless Chrome** — runs the *whole* suite, including the
real browser image upload (the Stimulus controller downscales the file, uploads
it straight to MinIO, and the post loads the image back):

```sh
docker compose --profile test run --rm tests
```

The "stubbed login" is the dev-persona sign-in.

## Deploying

The CDK stack builds the Rails image from the `Dockerfile`, provisions Cognito +
Google + the DynamoDB tables + the media bucket/CDN + the Lambda, and wires them
together. You supply real Google OAuth credentials (never commit them).

There are two environments — `staging` and `prod` — each its own stack
(`TheBookface-<env>`). (Local work runs on plain Puma, so there's no `dev` stack.)
They're just separate stacks (no Control Tower needed): by default both deploy
into the current account under distinct names; point each at its own account with
`BOOKFACE_<ENV>_ACCOUNT` (and `_REGION`) if you want real isolation. `prod` retains
its data on stack delete; `staging` tears down.

### Custom domain (Route 53)

The app lives at a custom domain — `thebookface.net` in prod,
`staging.thebookface.net` in staging. A Lambda Function URL can't carry a custom
domain on its own, so each stack fronts its function with a CloudFront distribution
(Origin Access Control; the Function URL locked to `AWS_IAM` so only CloudFront can
invoke it) and aliases the name at it in Route 53, behind an auto-validated ACM
certificate.

`thebookface.net` is **already registered** in Route 53, and its hosted zone id is
the default in `infra/config/environments.rb` — so deploys pick up the custom domain
with no extra config. To point the stacks at a different account/zone, override it:

```sh
aws route53 list-hosted-zones-by-name --dns-name <your-domain> \
  --query 'HostedZones[0].Id' --output text          # -> /hostedzone/Z0ABC...
export BOOKFACE_HOSTED_ZONE_ID=Z0ABC...              # the id only, no /hostedzone/ prefix
```

Set `BOOKFACE_HOSTED_ZONE_ID` **empty** to force the raw (public) Function-URL
fallback (no CloudFront/cert/Route 53) — handy for a throwaway deploy in an account
that doesn't own the zone.

> The certificate is created in the stack's region and CloudFront requires it in
> **us-east-1** — keep these stacks in us-east-1 (the default).

### Deploy

```sh
cd infra
npm install         # aws-cdk CLI + the jsii runtime the Ruby CDK talks to
bundle install      # the Ruby CDK itself

export CDK_DEFAULT_ACCOUNT=... CDK_DEFAULT_REGION=us-east-1
# BOOKFACE_HOSTED_ZONE_ID is optional — it defaults to thebookface.net's zone.

npx cdk deploy TheBookface-staging \
  -c google_client_id=YOUR_GOOGLE_CLIENT_ID \
  -c google_client_secret=YOUR_GOOGLE_CLIENT_SECRET

# or target one by context:
npx cdk deploy -c env=prod -c google_client_id=... -c google_client_secret=...
```

Per-environment settings live in `infra/config/environments.rb`. Each stack's
outputs: **AppUrl** (the live app on its domain), **FunctionUrl** (the CloudFront
origin, for debugging), **HostedUiDomain**, and **UserPoolId**. The app→Cognito
callback (`AppUrl`) is registered with Cognito automatically; after the first
deploy, add the env's Cognito hosted-UI domain
(`https://<HostedUiDomain>/oauth2/idpresponse`) to the Google OAuth client's
authorized redirect URIs. `cdk synth` works without credentials.

> The infra ships from a Docker image asset, so `cdk deploy` needs Docker. `cdk
> synth` does not.

## Layout

```
app/models/{post,comment,user}.rb   posts, hierarchical comments, the session user
app/controllers/                    posts, comments, sessions (OmniAuth callback)
config/initializers/omniauth.rb     Cognito OIDC (Google via extra_authorize_params)
config/initializers/dynamoid.rb     DynamoDB config (local vs Lambda)
infra/stacks/bookface_stack.rb      the whole deployment, in Ruby
Dockerfile                          Lamby image (deploy only)
```
