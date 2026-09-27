#!/usr/bin/env bash
# ==============================================================================
# bedrock-config.sh
# ==============================================================================
#
# Single source of truth for the Bedrock models LiteLLM serves to OpenClaw.
# Sourced by apply.sh and check_env.sh so every script agrees on one list, and
# exported into Terraform so the deploy cannot drift from what was validated.
#
# ------------------------------------------------------------------------------
# Why a list and not discovery
# ------------------------------------------------------------------------------
# apply.sh used to resolve four fixed slots (Sonnet, Haiku, Nova Pro, Nova Lite)
# with list-foundation-models at deploy time, while check_env.sh validated a
# separate hardcoded set of ids and the display names lived in a third place.
# The three could disagree, and "newest ACTIVE model" is not the same thing as
# "a model this account can call": the discovery query could pick an id that
# returns AccessDenied, and it skipped every Anthropic id without a -vN:N
# suffix (claude-sonnet-4-6 and later) entirely.
#
# Everything now derives from the array below: the LiteLLM model_list, the
# OpenClaw model picker, and the pre-flight checks. Any number of entries from
# 1 upward renders correctly.
#
# ------------------------------------------------------------------------------
# Model ids are NOT guaranteed to resolve
# ------------------------------------------------------------------------------
# An inference profile can be ACTIVE, be listed by list-inference-profiles,
# and still return AccessDenied for a given account -- model access never
# granted, Marketplace subscription missing, or the model gated to specific
# customers. The only reliable test is to make the call, so check_env.sh
# probes every id in this list before a deploy starts.
#
# To see what your account can actually serve, and how fast:
#     ./probe_bedrock.py
#     ./probe_bedrock.py --check us.anthropic.claude-sonnet-4-6
#
# The primary is NOT simply the newest or fastest model. Latency says nothing
# about whether a model can drive the Exec tool through a multi-step agent
# turn. Always verify tool calling in the UI before changing the primary.
#
# ------------------------------------------------------------------------------
# Format
# ------------------------------------------------------------------------------
#     "<alias>|<bedrock-model-id>|<display name>"
#
#   alias    what LiteLLM routes on and what OpenClaw stores as the model id.
#            Changing it repoints agents, so keep it stable across id bumps --
#            that is the entire point of having an alias.
#   model    the Bedrock id, normally a "us." cross-region inference profile.
#            This is the part that changes.
#   display  what a human sees in the OpenClaw model picker.
# ==============================================================================

# The Claude ids apply.sh's discovery resolved to, carried over unchanged.
#
# Excluded deliberately:
#   amazon.nova-*   removed 2026-09-24. They answer, but not usefully -- not
#                   good enough to drive an agent turn.
#   deepseek.r1     never added. Converse rejects a toolConfig outright:
#                   "This model doesn't support tool use." It is among the
#                   fastest ids the probe returns, and it cannot run the agent
#                   at all. probe_bedrock.py now tags these "no tool use".
#
# Probe run 2026-09-24 (us-east-1): both answer. Also available and not
# yet listed: us.anthropic.claude-sonnet-4-6, claude-opus-4-5/4-6. Denied for
# this account: claude-opus-4-7 and later, claude-sonnet-5, claude-fable-*,
# every openai.* and xai.* profile.
BEDROCK_MODELS=(
  "claude-sonnet|us.anthropic.claude-sonnet-4-5-20250929-v1:0|Claude Sonnet (Bedrock)"
  "claude-haiku|us.anthropic.claude-haiku-4-5-20251001-v1:0|Claude Haiku (Bedrock)"
)

# Alias agents default to. Must be one of the aliases above; check_env.sh and
# Terraform both reject a primary that is not in the list, because it yields an
# OpenClaw that starts fine and cannot run an agent.
BEDROCK_PRIMARY="claude-sonnet"

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
