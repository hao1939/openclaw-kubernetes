#!/usr/bin/env bash
# Validates that Service selectors correctly target only their intended workload.
# Catches bugs where a Service accidentally matches multiple Deployments/StatefulSets
# because their label selectors overlap.
set -euo pipefail

chart_dir="${CHART_DIR:-.}"
release_name="${RELEASE_NAME:-openclaw}"
YQ="${YQ:-yq}"

# Check yq is available
if ! command -v "$YQ" &>/dev/null; then
  echo "FAIL: yq is required but not found. Install from https://github.com/mikefarah/yq" >&2
  exit 1
fi

rendered=$(helm template "${release_name}" "${chart_dir}" \
  -f "${chart_dir}/values.yaml" \
  --set secrets.openclawGatewayToken=lint-token)

fail=0

# Helper: run yq per-document and strip YAML separators from output
yq_docs() {
  "$YQ" e "$1" - <<< "$rendered" | grep -v '^---$'
}

# --- Test 1: Service selector must match exactly one workload ---
echo "==> Test: Service selectors match their workload pod labels"

for svc_name in $(yq_docs 'select(.kind == "Service") | .metadata.name'); do
  svc_selector=$(yq_docs "select(.kind == \"Service\" and .metadata.name == \"${svc_name}\") | .spec.selector | to_entries | sort_by(.key) | .[] | .key + \"=\" + .value" | sort)

  # Find workloads whose pod template labels are a superset of this selector
  match_count=0
  matched_workloads=""

  for kind in StatefulSet Deployment; do
    for wl_name in $(yq_docs "select(.kind == \"${kind}\") | .metadata.name" 2>/dev/null); do
      pod_labels=$(yq_docs "select(.kind == \"${kind}\" and .metadata.name == \"${wl_name}\") | .spec.template.metadata.labels | to_entries | sort_by(.key) | .[] | .key + \"=\" + .value" | sort)

      # Check if every selector label exists in the pod labels
      all_match=true
      while IFS= read -r sel_label; do
        [ -z "$sel_label" ] && continue
        if ! grep -qxF "$sel_label" <<< "$pod_labels"; then
          all_match=false
          break
        fi
      done <<< "$svc_selector"

      if $all_match; then
        match_count=$((match_count + 1))
        matched_workloads="${matched_workloads} ${kind}/${wl_name}"
      fi
    done
  done

  if [ "$match_count" -eq 0 ]; then
    echo "  FAIL: Service/${svc_name} selector matches no workload" >&2
    fail=1
  elif [ "$match_count" -gt 1 ]; then
    echo "  FAIL: Service/${svc_name} selector matches multiple workloads:${matched_workloads}" >&2
    fail=1
  else
    echo "  OK: Service/${svc_name} -> ${matched_workloads## }"
  fi
done

# --- Test 2: Workloads must have distinct component labels ---
echo "==> Test: Workloads have distinct component labels"

components=$(yq_docs 'select(.kind == "StatefulSet" or .kind == "Deployment") | .metadata.name + "=" + (.spec.template.metadata.labels["app.kubernetes.io/component"] // "MISSING")' | sort)

missing=$(grep '=MISSING$' <<< "$components" || true)
if [ -n "$missing" ]; then
  echo "  FAIL: Workloads missing app.kubernetes.io/component label:" >&2
  echo "$missing" | sed 's/^/    /' >&2
  fail=1
fi

dupes=$(echo "$components" | awk -F= '{print $NF}' | sort | uniq -d)
if [ -n "$dupes" ]; then
  echo "  FAIL: Duplicate component labels: ${dupes}" >&2
  fail=1
fi

if [ -z "$missing" ] && [ -z "$dupes" ]; then
  echo "$components" | while IFS= read -r line; do
    echo "  OK: ${line}"
  done
fi

# --- Summary ---
if [ "$fail" -ne 0 ]; then
  echo "FAILED: Selector isolation tests found issues" >&2
  exit 1
else
  echo "PASSED: All selector isolation tests passed"
fi
