#!/usr/bin/env python3
"""Probe which Bedrock models can actually drive an agent, and how fast.

Why this exists
    bedrock-config.sh lists the models LiteLLM serves to OpenClaw, and
    check_env.sh calls this script with --check on each of them before a
    deploy starts. The full probe answers the question you have when choosing
    what goes in that list: which models will this account serve today, in
    this region, and what do they cost you in latency?

    Bedrock availability is not uniform. An inference profile can be ACTIVE,
    be listed by list-inference-profiles, and still return AccessDenied for a
    given account -- because model access was never granted, because the
    Marketplace subscription is missing, or because the model is gated to
    specific customers. As with the Vertex probe this is modelled on, the only
    reliable test is to make the call.

    So this makes the call, through the Converse API -- the same API LiteLLM's
    bedrock provider uses for chat models.

What "answering" means here
    The probe asks every model what the weather is in Pune, and hands it a
    get_weather tool. Only the models that actually call the tool are listed.

    That is a deliberately harder test than replying to a prompt, because
    OpenClaw drives everything -- Exec, files, the browser -- through tool
    calls. Three things can go wrong, and only the first is obvious:

      1. The model is retired or the account was never granted access, and
         Converse returns AccessDenied.
      2. The model cannot do tool use at all. DeepSeek R1 answers a plain
         prompt in a third of a second and Converse rejects a toolConfig
         outright: "This model doesn't support tool use." It ranked near the
         top of this list while being unable to run the agent at all.
      3. The model accepts the tool and answers in prose anyway. It will not
         reach for a tool when it needs one.

    Passing only clears a model to be tried. It is not proof of competence:
    Nova answers, calls tools, and is still too weak to hold an agent turn,
    which is why bedrock-config.sh excludes it. Verify tool calling in the
    OpenClaw UI before making anything the primary.

Reading the output
    Timings are the latency Bedrock itself reports, not the wall clock, and
    they RANK models against each other -- they are not a throughput measure.
    A short reply is mostly time to first token; re-run with --tokens 800 for
    something closer to the length an agent turn actually generates.

    A "think" mark means the model spent reasoning tokens before answering.
    Those count as output, so they cost both time and money on every turn.

Usage
    python3 probe_bedrock.py                    # probe every us.* text profile
    python3 probe_bedrock.py claude nova        # only ids matching a filter
    python3 probe_bedrock.py --tokens 800       # timing mode, longer output
    python3 probe_bedrock.py --geo global       # global.* profiles instead
    python3 probe_bedrock.py --geo all          # us.*, global.* and on-demand
    python3 probe_bedrock.py --region us-west-2
    python3 probe_bedrock.py --jobs 1           # one call at a time
    python3 probe_bedrock.py --check us.anthropic.claude-sonnet-4-6

    --check verifies one exact id and communicates through the exit code, so a
    shell pre-flight can gate a deploy on it -- the same contract
    probe_vertex.py offers in the GCP project.

Requirements
    The aws CLI with working credentials -- the same thing check_env.sh already
    needs. Deliberately NO Python dependencies: boto3 would be the natural
    choice, but requiring it would mean a venv just to run a liveness check.
    The cost is ~1s of CLI start-up per call, which is why the timings below
    use the latency Bedrock itself reports rather than the wall clock.
"""

import json
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

# Must match the region the project deploys to (us-east-1 throughout
# 01-core and 03-openclaw). Probing a different region answers a question
# this project never asks.
DEFAULT_REGION = "us-east-1"

# bedrock-config.sh uses "us." cross-region profiles, so us.* is the default
# geography probed.
GEOS = ("us", "global", "ondemand", "all")

AWS_ERROR = re.compile(
    r"An error occurred \((\w+)\) when calling the \w+ operation: (.*)", re.S)

# The "AccessDeniedException: " that aws() prepends, or that the CLI prints
# itself on the paths AWS_ERROR does not match. It is the same class on almost
# every failing line, so it costs a column and distinguishes nothing.
ERROR_PREFIX = re.compile(r"^[A-Za-z]+(?:Exception|Error|Failure):\s*")

# The tool the probe asks every model to call. OpenClaw drives everything
# through tool calls, so a model that will not reach for this one when asked a
# question it cannot otherwise answer is not a candidate, however fast it is.
TOOL_PROBE = {"tools": [{"toolSpec": {
    "name": "get_weather",
    "description": "Get the weather for a city",
    "inputSchema": {"json": {
        "type": "object",
        "properties": {"city": {"type": "string"}},
        "required": ["city"],
    }},
}}]}


# ==============================================================================
# aws CLI plumbing
# ==============================================================================

def csv_field(text):
    """Make one CSV field out of a detail string.

    Any comma inside becomes a semicolon rather than being quoted: a quoted
    field parses correctly but reads worse on screen, and these lines are
    filmed as often as they are piped anywhere.
    """
    return text.replace(",", ";")


def first_sentence(text):
    """Reduce an AWS error to its first sentence, minus the exception name.

    Bedrock's AccessDenied body runs to three sentences, and only the first
    says what went wrong -- the rest points at the Marketplace. Truncating to
    a fixed width instead cut mid-word and still left the line too long to
    read. The model id already sits in the column to the left, so what stays
    here is the reason on its own.

    Args:
        text: The error string from aws(), in either "Code: message" or raw
            CLI form.

    Returns:
        One sentence, or the whole string when it has no sentence break.
    """
    text = " ".join(text.split())          # CLI errors arrive multi-line
    # aws() normally rewrites this preamble into "Code: message", but the
    # fallback paths hand the raw stderr line straight through.
    raw = AWS_ERROR.search(text)
    if raw:
        text = raw.group(2).strip()
    text = ERROR_PREFIX.sub("", text)
    # Split on ". " rather than "."; the ids are full of dots that never have
    # a space after them, so this cannot cut one in half.
    cut = text.find(". ")
    if cut != -1:
        text = text[:cut + 1]
    return text if len(text) <= 120 else text[:119].rstrip() + "…"


def aws(args, region, timeout=180):
    """Run an aws CLI command and return (ok, parsed_json_or_error_text).

    Args:
        args: CLI arguments after "aws".
        region: Region passed as --region.
        timeout: Seconds before the call is abandoned.

    Returns:
        (True, dict) on success; (False, "Code: message") on failure.
    """
    cmd = ["aws"] + args + ["--region", region, "--output", "json"]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True,
                             timeout=timeout)
    except FileNotFoundError:
        sys.exit("ERROR: aws CLI not found in PATH.")
    except subprocess.TimeoutExpired:
        return False, "Timeout: no answer in %ds" % timeout

    if out.returncode == 0:
        try:
            return True, json.loads(out.stdout or "{}")
        except ValueError:
            return False, "BadJSON: %s" % out.stdout.strip()[:60]

    err = out.stderr.strip()
    m = AWS_ERROR.search(err)
    if m:
        return False, "%s: %s" % (m.group(1), m.group(2).strip())
    return False, err.splitlines()[-1] if err else "exit %d" % out.returncode


def caller_account(region):
    """Return the account id, exiting with a useful message if auth is broken.

    Checked up front so an expired SSO session reads as one clear error rather
    than every model failing with the same ExpiredToken.
    """
    ok, body = aws(["sts", "get-caller-identity"], region, timeout=30)
    if not ok:
        sys.exit("ERROR: aws CLI is not authenticated.\n  %s\n"
                 "  Run 'aws sso login' or export credentials first." % body)
    return body.get("Account", "?")


# ==============================================================================
# Discovery
# ==============================================================================

def text_models(region):
    """Map foundation model id -> summary, for models that emit text.

    Embedding, image and video models appear in the same listings but cannot
    serve Converse; filtering them here keeps the probe from burning a call on
    each one just to read ValidationException.
    """
    ok, body = aws(["bedrock", "list-foundation-models"], region)
    if not ok:
        return {}
    return {m["modelId"]: m for m in body.get("modelSummaries", [])
            if "TEXT" in m.get("outputModalities", [])
            and "TEXT" in m.get("inputModalities", [])
            and m.get("modelLifecycle", {}).get("status") == "ACTIVE"}


def discover(region, geo, filters):
    """List invocable text-model ids for the chosen geography.

    Inference profiles ("us.anthropic..." / "global.anthropic...") are what
    this project invokes; bare foundation ids only work for models that
    support ON_DEMAND, and newer models mostly do not.

    Args:
        region: AWS region.
        geo: One of GEOS.
        filters: Lowercased substrings; an id is kept if any matches.

    Returns:
        Sorted list of model ids.
    """
    models = text_models(region)
    ids = []

    if geo in ("us", "global", "all"):
        ok, body = aws(["bedrock", "list-inference-profiles",
                        "--type-equals", "SYSTEM_DEFINED"], region)
        if not ok:
            print("WARNING: list-inference-profiles failed -- %s" % body)
            body = {}
        wanted = ("us", "global") if geo == "all" else (geo,)
        for p in body.get("inferenceProfileSummaries", []):
            pid = p.get("inferenceProfileId", "")
            prefix, _, base = pid.partition(".")
            if prefix in wanted and p.get("status") == "ACTIVE" \
                    and base in models:
                ids.append(pid)

    if geo in ("ondemand", "all"):
        for mid, m in models.items():
            # Provisioned-only variants carry a ":N:Mk" suffix and are not
            # callable without a purchased throughput.
            if "ON_DEMAND" in m.get("inferenceTypesSupported", []):
                ids.append(mid)

    ids = sorted(set(ids))
    if filters:
        ids = [i for i in ids if any(f in i.lower() for f in filters)]
    return ids


# ==============================================================================
# Probe
# ==============================================================================

def probe(region, model_id, prompt, max_tokens):
    """Make one real Converse call.

    Returns:
        Dict with ok, latency (Bedrock's own metrics.latencyMs, in seconds),
        wall (including CLI start-up), token counts, and an error string.
    """
    messages = [{"role": "user", "content": [{"text": prompt}]}]
    # temperature 0 keeps the timing comparable between runs; it is not what
    # OpenClaw sends, but a slow model here is slow for the same reason it
    # would be slow in production.
    config = {"maxTokens": max_tokens, "temperature": 0}

    def call():
        return aws(["bedrock-runtime", "converse",
                    "--model-id", model_id,
                    "--messages", json.dumps(messages),
                    "--inference-config", json.dumps(config),
                    "--tool-config", json.dumps(TOOL_PROBE)], region)

    t0 = time.perf_counter()
    ok, body = call()
    if not ok and "support the temperature" in body and "temperature" in config:
        # Some models (Kimi, for one) reject the field outright. That is a
        # request-shape problem, not an availability one, so retry without it.
        del config["temperature"]
        t0 = time.perf_counter()
        ok, body = call()
    wall = time.perf_counter() - t0

    # A model that cannot do tool use is not retried without the toolConfig.
    # It fails here, carrying Bedrock's own wording, because its latency is of
    # no interest: OpenClaw drives everything through tool calls.
    out = {"ok": ok, "wall": wall, "latency": None, "error": None,
           "in_tok": None, "out_tok": None, "think": False,
           "tool_call": False}
    if not ok:
        out["error"] = first_sentence(body)
        return out

    usage = body.get("usage", {})
    out["in_tok"] = usage.get("inputTokens")
    out["out_tok"] = usage.get("outputTokens")
    latency_ms = body.get("metrics", {}).get("latencyMs")
    out["latency"] = latency_ms / 1000.0 if latency_ms is not None else wall
    # Reasoning models (DeepSeek R1, some Claude and OpenAI variants) return a
    # reasoningContent block and count those tokens as output. They are
    # usually the reason a "Reply with OK" probe takes seconds.
    content = body.get("output", {}).get("message", {}).get("content", [])
    out["think"] = any("reasoningContent" in c for c in content)
    # Accepting the tool schema is not the same as using it. A model that
    # answers the weather question in prose -- or refuses it -- has told you
    # it will not reach for a tool when it needs one.
    out["tool_call"] = (body.get("stopReason") == "tool_use"
                        or any("toolUse" in c for c in content))
    return out


def take_value(args, flag, cast, example):
    """Remove "flag value" from args and return value, or None if absent."""
    if flag not in args:
        return None
    i = args.index(flag)
    try:
        value = cast(args[i + 1])
    except (IndexError, ValueError):
        sys.exit("ERROR: %s needs a value, e.g. %s %s" % (flag, flag, example))
    del args[i:i + 2]
    return value


def main():
    args = sys.argv[1:]

    region = take_value(args, "--region", str, "us-west-2") or DEFAULT_REGION
    geo = take_value(args, "--geo", str, "global") or "us"
    if geo not in GEOS:
        sys.exit("ERROR: --geo must be one of %s" % ", ".join(GEOS))
    jobs = take_value(args, "--jobs", int, "4") or 6

    # Enough room for a toolUse block -- a tool name plus a small JSON
    # argument. The old default of 16 was sized for a one-word reply and
    # truncated the tool call itself, which made tool-capable models look as
    # though they had ignored the tool.
    max_tokens = take_value(args, "--tokens", int, "800") or 128

    # A question that cannot be answered without calling the tool. Replying
    # "OK" proved only that the endpoint was alive; this asks for the one
    # behaviour OpenClaw depends on, so a model either calls get_weather or
    # it is not a candidate.
    prompt = "What is the weather in Pune?"
    if max_tokens > 400:
        # Timing mode rather than capability mode: give it something it will
        # keep writing about so the tokens-per-second figure means something.
        prompt = ("Write a short paragraph explaining what a resume is, "
                  "in plain language.")

    check_mode = len(args) >= 2 and args[0] == "--check"
    check_name = args[1] if check_mode else None
    filters = [] if check_mode else [a.lower() for a in args]

    account = caller_account(region)

    if check_mode:
        r = probe(region, check_name, prompt, max_tokens)
        if r["ok"] and r["tool_call"]:
            print("OK: %s called the tool in %s (%.2fs)"
                  % (check_name, region, r["latency"]))
            return 0
        reason = (r["error"] if not r["ok"]
                  else "answered without calling a tool")
        print("FAIL: %s in %s -- %s" % (check_name, region, reason))
        return 1

    print("account    : %s" % account)
    print("region     : %s" % region)
    print("geo        : %s" % geo)
    print("max_tokens : %d" % max_tokens)
    print("filters    : %s\n"
          % (filters or "(none -- probing every text model found)"))

    ids = discover(region, geo, filters)
    if not ids:
        print("No text models matched.")
        return 1

    print("%d model(s) to probe, %d at a time\n" % (len(ids), jobs))
    print("status,model,details")

    # Concurrency does not skew the ranking: latency is measured by Bedrock on
    # its side of the wire, not by this process. Drop to --jobs 1 if the
    # account starts returning ThrottlingException.
    results = {}
    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        futures = {pool.submit(probe, region, mid, prompt, max_tokens): mid
                   for mid in ids}
        for fut in as_completed(futures):
            mid = futures[fut]
            r = results[mid] = fut.result()
            if r["ok"]:
                think = " think" if r["think"] else ""
                called = "tool" if r["tool_call"] else "no-tool-call"
                detail = "%.2fs in %s out %s %s%s" % (
                    r["latency"], r["in_tok"], r["out_tok"], called, think)
            else:
                detail = r["error"]
            print("%s,%s,%s" % ("OK" if r["ok"] else "FAIL", mid,
                                csv_field(detail)))

    # ==========================================================================
    # Result -- fastest first
    # ==========================================================================
    # Only models that actually called the tool. Answering the weather
    # question in prose is a pass on the API and a fail on the job.
    working = sorted(((m, r) for m, r in results.items()
                      if r["ok"] and r["tool_call"]),
                     key=lambda pair: pair[1]["latency"])
    print()
    if not working:
        print("No model called the tool in %s." % region)
        print("Check model access: "
              "https://console.aws.amazon.com/bedrock/home#/modelaccess")
        return 1

    print("Called the tool in %s (%d of %d, fastest first):"
          % (region, len(working), len(ids)))
    for mid, r in working:
        out_tok = r["out_tok"] or 0
        rate = ("  %6.1f tok/s" % (out_tok / r["latency"])
                if out_tok and r["latency"] > 0 else "")
        print("  %7.2fs  %-48s%s" % (r["latency"], mid, rate))

    # The one line worth keeping on screen: what to do with the list. The
    # caveats about timings, reasoning tokens and tool use live in the module
    # docstring, not in the console every run.
    print()
    print("To serve a model, add it to BEDROCK_MODELS in bedrock-config.sh;")
    print("check_env.sh then probes it before every deploy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
