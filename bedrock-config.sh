#!/usr/bin/env bash
# ==============================================================================
# bedrock-config.sh -- which Bedrock models OpenClaw is offered
# ==============================================================================
#
# The single source of truth for that list. apply.sh and check_env.sh source
# this file and it is exported into Terraform, so the LiteLLM model_list, the
# OpenClaw model picker and the pre-flight all describe the same models. Any
# number of entries from 1 upward works.
#
# ------------------------------------------------------------------------------
# Relationship to probe_bedrock.py
# ------------------------------------------------------------------------------
# This file says what to serve. The probe says what is servable.
#
#     ./probe_bedrock.py                 what this account can call, ranked
#     ./probe_bedrock.py --check <id>    one id, answers through the exit code
#
# check_env.sh runs --check on every id below before a deploy creates
# anything, because a listed model id is not the same as a callable one. Take
# ids from the probe's output rather than from AWS documentation.
#
# Passing the probe is necessary, not sufficient: it proves a model answers
# and calls a tool, not that it can hold a multi-step agent turn. Verify in
# the OpenClaw UI before changing BEDROCK_PRIMARY.
#
# ------------------------------------------------------------------------------
# Format
# ------------------------------------------------------------------------------
#     "<alias>|<bedrock-model-id>|<display name>"
#
#   alias    what LiteLLM routes on and what OpenClaw stores as the model id.
#            Keep it stable across id bumps -- that is the point of an alias.
#   model    the Bedrock id, normally a "us." cross-region inference profile.
#   display  what a human sees in the OpenClaw model picker.
# ==============================================================================

# Excluded on purpose:
#   amazon.nova-*  answers and calls tools, still too weak to drive a turn
#   deepseek.r1    Converse rejects a toolConfig outright -- no tool use
BEDROCK_MODELS=(
  "claude-sonnet|us.anthropic.claude-sonnet-4-5-20250929-v1:0|Claude Sonnet"
  "claude-haiku|us.anthropic.claude-haiku-4-5-20251001-v1:0|Claude Haiku"
)

# Alias agents default to. Must be one of the aliases above; check_env.sh and
# Terraform both reject a primary that is not in the list, because it yields an
# OpenClaw that starts fine and cannot run an agent.
BEDROCK_PRIMARY="claude-haiku"

# Bedrock region. Must match aws_region_name in the LiteLLM config rendered by
# 03-openclaw/scripts/userdata.sh -- model access is granted per region, so
# validating against a different one proves nothing.
export BEDROCK_REGION="${BEDROCK_REGION:-us-east-1}"


# ==============================================================================
# Helpers
# ==============================================================================

# JSON array of model objects, shaped for TF_VAR_models.
bedrock_models_json() {
  local entry alias model display
  for entry in "${BEDROCK_MODELS[@]}"; do
    IFS='|' read -r alias model display <<< "${entry}"
    jq -n \
      --arg alias   "${alias}" \
      --arg model   "${model}" \
      --arg display "${display}" \
      '{alias: $alias, model: $model, display: $display}'
  done | jq -s '.'
}

# Bedrock model ids, one per line -- what check_env.sh probes.
bedrock_model_ids() {
  local entry
  for entry in "${BEDROCK_MODELS[@]}"; do
    printf '%s\n' "${entry}" | cut -d'|' -f2
  done
}

# Aliases, one per line.
bedrock_model_aliases() {
  local entry
  for entry in "${BEDROCK_MODELS[@]}"; do
    printf '%s\n' "${entry}" | cut -d'|' -f1
  done
}

# Resolve an alias to its Bedrock id; non-zero if the alias is unknown.
bedrock_model_for_alias() {
  local want="$1" entry alias model
  for entry in "${BEDROCK_MODELS[@]}"; do
    IFS='|' read -r alias model _ <<< "${entry}"
    if [ "${alias}" = "${want}" ]; then
      printf '%s' "${model}"
      return 0
    fi
  done
  return 1
}

# Hand the list to Terraform. Called by apply.sh before the 03-openclaw apply.
bedrock_export_tf_vars() {
  TF_VAR_models="$(bedrock_models_json)"
  TF_VAR_primary_alias="${BEDROCK_PRIMARY}"
  TF_VAR_bedrock_region="${BEDROCK_REGION}"
  export TF_VAR_models TF_VAR_primary_alias TF_VAR_bedrock_region
}
