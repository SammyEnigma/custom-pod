#!/bin/bash
# shellcheck disable=SC1090,SC2154,SC2153
set -eou pipefail

pod_vars_dir="$POD_VARS_DIR"
pod_layer_dir="$POD_LAYER_DIR"
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

. "${pod_vars_dir}/vars.sh"

GRAY='\033[0;90m'
RED='\033[0;31m'
NC='\033[0m' # No Color

function info {
	msg="$(date '+%F %T') - ${1:-}"
	>&2 echo -e "${GRAY}${msg}${NC}"
}

function error {
	msg="$(date '+%F %T') - ${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${1:-}"
	>&2 echo -e "${RED}${msg}${NC}"
	exit 2
}

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (env)."
fi

shift;

pod_shared_run_file="$pod_layer_dir/$var_shared__script_dir/main.sh"

case "$command" in
	"prepare")
		data_dir="/var/main/data"

		"$pod_script_env_file" up toolbox

		"$pod_script_env_file" exec-nontty toolbox /bin/bash <<-SHELL
			if [ "$var_custom__pod_type" = "app" ] || [ "$var_custom__pod_type" = "db" ]; then
				dir="$data_dir/elasticsearch"

				if [ ! -d "\$dir" ]; then
					mkdir -p "\$dir"
					chmod 755 "\$dir"
				fi
			fi
		SHELL

		"$pod_shared_run_file" "$command" "$@"
		;;
	"migrate")
		"$pod_script_env_file" "migrate:$var_custom__pod_type" ${args[@]+"${args[@]}"}
		"$pod_shared_run_file" "$command" "$@"
		;;
	"migrate:app")
		"$pod_script_env_file" "migrate:web" ${args[@]+"${args[@]}"}
		"$pod_script_env_file" "migrate:db" ${args[@]+"${args[@]}"}
		;;
	"migrate:web")
		info "$command - nothing to do..."
		;;
	"migrate:db")
		vm_max_map_count="${var_migrate_es_vm_max_map_count:-262144}"
		info "$command increasing vm max map count to $vm_max_map_count"
		sudo sysctl -w vm.max_map_count="$vm_max_map_count"
		;;
	"action:exec:actions")
		"$pod_script_env_file" "action:subtask:log_register.memory_overview" > /dev/null 2>&1 ||:
		"$pod_script_env_file" "action:subtask:log_register.memory_details" > /dev/null 2>&1 ||:

		if [ "${var_custom__use_nginx:-}" = "true" ]; then
			"$pod_script_env_file" "action:subtask:log_register.nginx_basic_status" > /dev/null 2>&1 ||:
			"$pod_script_env_file" "action:subtask:nginx_reload" > /dev/null 2>&1 ||:
		fi

		"$pod_script_env_file" "action:subtask:logrotate" > /dev/null 2>&1 ||:
		"$pod_script_env_file" "action:subtask:log_summary" > /dev/null 2>&1 ||:
		"$pod_script_env_file" "action:subtask:backup" > /dev/null 2>&1 ||:
		;;
	"action:exec:log_summary")
        days_ago="${var_custom__log_summary__days_ago:-}"
        days_ago="${arg_days_ago:-$days_ago}"

        max_amount="${var_custom__log_summary__max_amount:-}"
        max_amount="${arg_max_amount:-$max_amount}"
        max_amount="${max_amount:-100}"

		"$pod_script_env_file" "shared:log:memory_overview:summary" --days_ago="$days_ago" --max_amount="$max_amount"

		if [ "$var_custom__pod_type" = "app" ] || [ "$var_custom__pod_type" = "web" ]; then
			if [ "${var_custom__use_nginx:-}" = "true" ]; then
				"$pod_script_env_file" "shared:log:nginx:summary" --days_ago="$days_ago" --max_amount="$max_amount"
				"$pod_script_env_file" "shared:log:nginx:summary:connections" --days_ago="$days_ago" --max_amount="$max_amount"
			fi
		fi

		"$pod_script_env_file" "shared:log:file_descriptors:summary" --max_amount="$max_amount"
		"$pod_script_env_file" "shared:log:disk:summary" \
			--verify_size_docker_dir="${var_custom__log_summary__verify_size_docker_dir:-}" \
			--verify_size_containers="${var_custom__log_summary__verify_size_containers:-}"
		;;
	*)
		"$pod_shared_run_file" "$command" "$@"
		;;
esac