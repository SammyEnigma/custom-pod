#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2154
pod_script_env_file="$var_pod_script"
# shellcheck disable=SC2154
pod_env_shared_file="$var_run__general__script_dir/shared.sh"


function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}:${BASH_LINENO[0]}: ${*}"
}

[ "${var_run__meta__no_stacktrace:-}" != 'true' ] \
	&& trap 'echo "[error] ${BASH_SOURCE[0]}:$LINENO" >&2; exit 3;' ERR

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (env)."
fi

shift;

case "$command" in
	"clear")
		"$pod_script_env_file" "local:clear"
		;;
	"clear-all")
		"$pod_script_env_file" "local:clear-all"
		;;
	"clear-remote")
		"$pod_script_env_file" "s3:subtask:s3_backup" --s3_cmd=rb
		"$pod_script_env_file" "s3:subtask:s3_backup_replica" --s3_cmd=rb
		;;
	*)
		"$pod_env_shared_file" "$command" "$@"
		;;
esac