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

pod_env_run_file="$pod_layer_dir/main/scripts/main.sh"

case "$command" in
	"upgrade")
		"$pod_env_run_file" "setup:main:network"
		"$pod_env_run_file" "$command" "$@"
		;;
	"migrate")
		"$pod_script_env_file" "migrate:$var_custom__pod_type" "${args[@]}"
		;;
	"migrate:app")
		"$pod_script_env_file" "migrate:db" "${args[@]}"
		"$pod_script_env_file" "migrate:web" "${args[@]}"
		;;
	"migrate:web")
		info "$command - nothing to do..."
		;;
	"migrate:db")
		"$pod_env_run_file" up mongo

		info "$command - init the mongo database if needed"
		"$pod_env_run_file" run mongo_init /bin/bash <<-SHELL
			set -eou pipefail

			for i in \$(seq 1 30); do
				mongo mongo/"$var_custom__db_name" \
					--authenticationDatabase admin \
					--username "$var_custom__user_name" \
					--password "$var_custom__user_pass" \
					--eval "
						rs.initiate({
							_id: 'rs0',
							members: [ { _id: 0, host: 'localhost:27017' } ]
						})
					" && s=\$? && break || s=\$?;
				echo "Tried \$i times. Waiting 5 secs...";
				sleep 5;
			done;

			if [ "\$s" != "0" ]; then
			  exit "\$s"
			fi

			for i in \$(seq 1 30); do
				mongo mongo/admin \
					--authenticationDatabase admin \
					--username "$var_custom__user_name" \
					--password "$var_custom__user_pass" \
					/tmp/main/init.js && s=\$? && break || s=\$?;
				echo "Tried \$i times. Waiting 5 secs...";
				sleep 5;
			done;

			if [ "\$s" != "0" ]; then
			  exit "\$s"
			fi
		SHELL
		;;
	*)
		"$pod_env_run_file" "$command" "$@"
		;;
esac