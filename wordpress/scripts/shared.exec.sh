#!/bin/bash
set -eou pipefail

# shellcheck disable=SC2153
pod_vars_dir="$POD_VARS_DIR"
# shellcheck disable=SC2153
pod_script_env_file="$POD_SCRIPT_ENV_FILE"

# shellcheck disable=SC1090
. "${pod_vars_dir}/vars.sh"

function info {
	"$pod_script_env_file" "util:info" --info="${*}"
}

function error {
	"$pod_script_env_file" "util:error" --error="${BASH_SOURCE[0]}: line ${BASH_LINENO[0]}: ${*}"
}

command="${1:-}"

if [ -z "$command" ]; then
	error "No command entered (env - shared)."
fi

shift;

args=( "$@" )

# shellcheck disable=SC2214
while getopts ':-:' OPT; do
	if [ "$OPT" = "-" ]; then	 # long option: reformulate OPT and OPTARG
		OPT="${OPTARG%%=*}"			 # extract long option name
		OPTARG="${OPTARG#$OPT}"	 # extract long option argument (may be empty)
		OPTARG="${OPTARG#=}"			# if long option argument, remove assigning `=`
	fi
	case "$OPT" in
		setup_url ) arg_setup_url="${OPTARG:-}";;
		setup_title ) arg_setup_title="${OPTARG:-}";;
		setup_admin_user ) arg_setup_admin_user="${OPTARG:-}";;
		setup_admin_password ) arg_setup_admin_password="${OPTARG:-}";;
		setup_admin_email ) arg_setup_admin_email="${OPTARG:-}";;
		setup_restore_seed ) arg_setup_restore_seed="${OPTARG:-}";;
		setup_local_seed_data ) arg_setup_local_seed_data="${OPTARG:-}";;
		setup_remote_seed_data ) arg_setup_remote_seed_data="${OPTARG:-}";;
		old_domain_host ) arg_old_domain_host="${OPTARG:-}";;
		new_domain_host ) arg_new_domain_host="${OPTARG:-}";;
		use_w3tc ) arg_use_w3tc="${OPTARG:-}";;
		??* ) error "Illegal option --$OPT" ;;	# bad long option
		\? )	exit 2 ;;	# bad short option (error reported via getopts)
	esac
done
shift $((OPTIND-1))

case "$command" in
	"setup:new:db")
		"$pod_script_env_file" up wordpress

		# Deploy a brand-new Wordpress site (with possibly seeded data)
		info "$command - installation"
		"$pod_script_env_file" exec-nontty wordpress \
			wp --allow-root core install \
			--url="$arg_setup_url" \
			--title="$arg_setup_title" \
			--admin_user="$arg_setup_admin_user" \
			--admin_password="$arg_setup_admin_password" \
			--admin_email="$arg_setup_admin_email"

		if [ "${arg_setup_restore_seed:-}" = "true" ]; then
			if [ -z "$arg_setup_local_seed_data" ] && [ -z "$arg_setup_remote_seed_data" ]; then
				error "$command - seed_data not provided"
			else
				info "$command - migrate..."
				"$pod_script_env_file" migrate ${args[@]+"${args[@]}"}

				if [ -n "$arg_setup_local_seed_data" ]; then
					info "$command - import local seed data"
					"$pod_script_env_file" exec-nontty wordpress \
						wp --allow-root import ./"$arg_setup_local_seed_data" --authors=create
				fi

				if [ -n "$arg_setup_remote_seed_data" ]; then
					info "$command - import remote seed data"
					"$pod_script_env_file" exec-nontty wordpress /bin/bash <<-SHELL || error "$command"
						curl -L -o ./tmp/tmp-seed-data.xml -k "$arg_setup_remote_seed_data" \
							&& wp --allow-root import ./tmp/tmp-seed-data.xml --authors=create \
							&& rm -f ./tmp/tmp-seed-data.xml
					SHELL
				fi
			fi
		fi
		;;
	"migrate:app")
		"$pod_script_env_file" "migrate:db" ${args[@]+"${args[@]}"}
		"$pod_script_env_file" "migrate:web" ${args[@]+"${args[@]}"}
		;;
	"migrate:db")
		info "$command - nothing to do..."
		;;
	"migrate:web")
		info "$command - start container"
		"$pod_script_env_file" up wordpress

		"$pod_script_env_file" exec-nontty wordpress /bin/bash <<-SHELL || error "$command"
			set -eou pipefail

			>&2 echo "update database"
			wp --allow-root core update-db

			>&2 echo "activate plugins"
			wp --allow-root plugin activate --all

			if [ -n "${arg_old_domain_host:-}" ] && [ -n "${arg_new_domain_host:-}" ]; then
				>&2 echo "update domain"
				wp --allow-root search-replace "$arg_old_domain_host" "$arg_new_domain_host"
			fi

			if [ -d "/var/www/html/web/app/cache" ]; then
				chown -R www-data:www-data "/var/www/html/web/app/cache"
			fi

			if [ -d "/var/www/html/web/app/w3tc-config" ]; then
				chown -R www-data:www-data "/var/www/html/web/app/w3tc-config"
			fi

			# if [ "${arg_use_w3tc:-}" = "true" ]; then
			# 	wp --allow-root plugin install w3-total-cache

			# 	cp /var/www/html/web/app/plugins/w3-total-cache/wp-content/advanced-cache.php /var/www/html/web/app/advanced-cache.php
			# 	mkdir -p /var/www/html/web/app/cache
			# 	chmod 777 /var/www/html/web/app/cache
			# 	mkdir -p /var/www/html/web/app/w3tc-config
			# 	chmod 777 /var/www/html/web/app/w3tc-config

			# 	wp --allow-root plugin activate w3-total-cache
			# 	rm -rf /var/www/html/web/app/cache/page_enhanced
			# 	wp --allow-root w3-total-cache fix_environment
			# fi
		SHELL
		;;
	*)
		error "$command: invalid command"
		;;
esac
