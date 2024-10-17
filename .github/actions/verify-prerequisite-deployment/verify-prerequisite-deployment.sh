#!/usr/bin/env bash
set -eu

# DEPLOYMENT_ENVIRONMENT="prod"
# PREREQUISITE_ENVIRONMENT="stage"
# VERSION="aff43153"
# #VERSION="xaff43153"
# GITHUB_REPOSITORY="bettermile/bm-route-sequencer"

# ----

if [ -z "$PREREQUISITE_ENVIRONMENT" ]; then
  echo "::notice::Check passed: No prerequisite deployment is required for deployment to " \
       "'$DEPLOYMENT_ENVIRONMENT'."
  exit 0
fi

repo_owner=$(echo "${GITHUB_REPOSITORY}" | cut -d'/' -f1)
repo_name=$(echo "${GITHUB_REPOSITORY}" | cut -d'/' -f2)

graphql_query='
query($repoOwner: String!, $repoName: String!, $environment: String!) {
  repository(owner: $repoOwner, name: $repoName) {
    deployments(first: 100,
                environments: [$environment],
                orderBy: {field: CREATED_AT, direction: DESC}) {
      nodes {
        createdAt
        latestStatus {
          state
        }
        commitOid
        payload
      }
    }
  }
}
'

jq_query='
.data.repository.deployments.nodes
| map(select(.latestStatus.state == "INACTIVE" or .latestStatus.state == "SUCCESS"))
| map(select(.commitOid | startswith($commit_prefix)))
| map(select(.payload | contains("https://github.com/actions/runner/issues/2120")))
| first | .createdAt // ""
'

latest_deployment=$(gh api graphql \
  -F repoOwner="$repo_owner" \
  -F repoName="$repo_name" \
  -F environment="$PREREQUISITE_ENVIRONMENT" \
  -f query="$graphql_query" \
  | jq -r --arg commit_prefix "$VERSION" "$jq_query")

if [ -n "$latest_deployment" ]; then
  echo "::notice::Version '$VERSION' has been previously deployed to" \
       "environment '$DEPLOYMENT_ENVIRONMENT' at $latest_deployment."
  exit 0
else
  echo "::error::Deployment aborted:" \
       "deployment to '$DEPLOYMENT_ENVIRONMENT' requires a successful prior deployment" \
       "to '$PREREQUISITE_ENVIRONMENT', but none was found."
  exit 1
fi
