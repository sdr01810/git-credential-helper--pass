#!/bin/sh
## Provides a git(1) credential helper that delegates to pass(1).
##
## Arguments:
##
##     { get | store | erase } password-name
##
## For the behavior contract, consult:
##
##     https://git-scm.com/docs/gitcredentials
##
####
##
## Copyright 2021 Stephen D. Rogers
## 
## Licensed under the BSD 3-Clause License (the "License"); you may not use
## this file except in compliance with the License.  You may obtain a copy of
## the License at
## 
##     https://opensource.org/licenses/BSD-3-Clause
## 
## Software distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
## 
## The master copy of this script can be found here:
## 
##     https://github.com/sdr01810/git-credential-helper--pass.git
## 
## It has the following third-party source code dependencies:
## 
## - Some functions have been copied from `snippets--sh`:
##
##       https://github.com/sdr01810/snippets--sh.git
##

set -e

[ -z "${BASH}" ] || set -o pipefail

##

necessary_command_list_non_core="$(egrep -vh '^\s*(#|$)' <<-.

	pass
	realpath
	.
)"

if ! hash ${necessary_command_list_non_core} 2>&- ; then

	echo "At least one of these necessary commands is not available:"
	echo
	echo "${necessary_command_list_non_core}" | sed -e 's/^/    /'

	exit 2
fi 1>&2

##

this_script_fpn="$(realpath "${0:?}")"

this_script_dpn="$(dirname "${this_script_fpn:?}")"
this_script_fbn="$(basename "${this_script_fpn:?}")"

##

this_script_name="${this_script_fbn%.*sh}"

this_script_pkg_root="$(dirname "${this_script_dpn:?}")"

##

case ::"${GIT_CREDENTIAL_HELPER_ACTION_IMPL_POLICY}":: in
(*:'should_trace_execution':*)
	this_script_should_trace_execution=true
	;;
(*:'should_trace_execution=true':*)
	this_script_should_trace_execution=true
	;;
(*)
	this_script_should_trace_execution=false
	;;
esac

##
## from snippet library:
##

check_attribute_has_been_provided_as_variable_with_name_prefix() { # variable_name_prefix attribute_name

	local variable_name_prefix="${1}" ; [ $# -lt 1 ] || shift 1

	local attribute_name="${1:?missing value for attribute_name}" ; shift 1

	local variable_name="${variable_name_prefix}${attribute_name:?}"

	eval "local attribute_value=\"\${${variable_name:?}}\""

	if ! [ -n "${attribute_value}" ] ; then

		croak "attribute expected but not provided: ${attribute_name:?}"
	fi
}

croak() { # [ message ... ]

	local message="$*" ; shift $#

	[ -n "${message}" ] || message="internal error"

	echo 1>&2 "${this_script_name:?}: ${message:?}"

	return 2
}

read_attribute_lines_into_variables_with_name_prefix() { # variable_name_prefix

	local variable_name_prefix="${1}" ; [ $# -lt 1 ] || shift 1

	while read -r line ; do

		local attribute_name="${line%%=*}" attribute_value="${line#*=}"

		local variable_name="${variable_name_prefix}${attribute_name:?}"

		eval "${variable_name:?}=\"\${attribute_value}\""
	done
}

xx() { # ...

	! "${this_script_should_trace_execution:?}" ||

	echo 1>&2 "${PS4:-+}" "$@"

	"$@"
}

##
## framework for git credential helper implementations:
##

check_git_credential_attribute_has_been_provided() { # attribute_name

	check_attribute_has_been_provided_as_variable_with_name_prefix 'credential_' "$@"
}

delegate_git_credential_helper_action_to() { # delegate action

	local delegate="${1:?missing value for delegate}" ; shift 1

	local action="${1:?missing value for action}" ; shift 1

	[ $# -eq 0 ] || croak "unexpected argument(s):" "$@"

	local action_handler="git_credential_helper_action_impl__${delegate:?}__${action:?}"

	if hash "${action_handler:?}" 2>&- ; then
	(
		# action is supported; handle it

		read_git_credential_attribute_lines_into_variables

		"${action_handler:?}" "$@"
	)
	else
		true # ignore it
	fi
}

get_git_credential_id_for_helper() { #

	check_git_credential_attribute_has_been_provided protocol

	local result="protocol=${credential_protocol:?}"

	result="${result}/host=${credential_host}"

	result="${result}/user=${credential_username}"

	result="${result}${credential_path:+/${credential_path}}"

	#^-- By design: the protocol (URI scheme) is an essential (and required) element of the
	#^-- credential ID.  At first glance, one could argue that the protocol doesn't matter,
	#^-- because `git` supports multiple protocols for accessing the same repository on the
	#^-- same host.  However, the `git:` protocol doesn't even use passwords; it uses `ssh`
	#^-- keys.  And these days you wouldn't want to send a password in the clear using
	#^-- `http:`, whereas using `https:` to do that is still considered OK.

	#^-- By design: the user name is an essential (but optional) element of the credential
	#^-- ID.  We want to support a single person using multiple user names to access the
	#^-- same `git` host, each for a different purpose.  In that case, the same person would
	#^-- need to store a separate password for each user name.  At the same time, we want to
	#^-- support the simple case where a single person uses a single user name to access a
	#^-- `git` host.  That's why the user name is optional.

	echo "${result}"
}

read_git_credential_attribute_lines_into_variables() { #

	read_attribute_lines_into_variables_with_name_prefix 'credential_'

	credential_id_for_helper="$(get_git_credential_id_for_helper)"
}

##
## core logic:
##

git_credential_helper_action_impl__pass__get() { #

	xx :
	xx pass show "git/${credential_id_for_helper:?}"
}

case ::"${GIT_CREDENTIAL_HELPER_ACTION_IMPL_POLICY}":: in (*:can_keep_passwords_insecurely_in_memory:*)

git_credential_helper_action_impl__pass__store() { #

	case ::"${GIT_CREDENTIAL_HELPER_ACTION_IMPL_POLICY}":: in
	(*:can_store_empty_password:*)
		true
		;;
	(*)
		check_git_credential_attribute_has_been_provided password
		;;
	esac

	xx :
	xx pass insert --multiline -e "git/${credential_id_for_helper:?}" >/dev/null <<-EOF
		username: ${credential_username}
		password: ${credential_password}
	EOF
}

;; esac

git_credential_helper_action_impl__pass__erase() { #

	xx :
	xx pass delete "git/${credential_id_for_helper:?}" >/dev/null
}

main() { # action ...

	delegate_git_credential_helper_action_to 'pass' "$@"
}

main "$@"
