#!/bin/sh
set -e

# Default values
dynv6_token_file="/etc/dynv6_token"
dynv6_ipv6_file="/var/cache/dynv6/ipv6_address"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [--] zone

Positional arguments:
  zone                     The zone in DynV6 to update

Options:
  -T, --token-file PATH    Set the path to the file holding the access token to DynV6
                           Default: $dynv6_token_file
  -A, --address-file PATH  Set the path for the file that caches the current IPv6 address
                           Default: $dynv6_ipv6_file
  -h, --help               Display this help text

EOF
    exit 0
}

# Call GNU getopt to canonicalize arguments.
# -o defines short options ('h' takes no arg, 'n:' takes a required arg)
# -l defines long options ('help' takes no arg, 'name:' takes a required arg)
parsed=$(getopt -o "hT:A:" --long "help,token-file:address-file:" -n "$0" -- "$@")
if [ $? -ne 0 ]; then
    exit 1
fi

# Re-assign positional parameters using eval to safely retain quotes/spaces
eval set -- "$parsed"


# Parse options until reaching the '--' separator
while true; do
    case "$1" in
        -h|--help)
            usage
            ;;
        -A|--address-file)
            dynv6_ipv6_file="$2"
            shift 2
            ;;
        -T|--token-file)
            dynv6_token_file="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo >&2 "$0: internal argument parsing error"
            exit 1
            ;;
    esac
done

# Process remaining positional arguments (if any)
if [ $# -eq 0 ]; then
    echo >&2 "$0: zone argument missing"
    exit 1
elif [ $# -gt 1 ]; then
    echo >&2 "$0: unrecognized positional arguments"
    exit 1
fi

dynv6_zone="$1"
dynv6_token="$(cat "${dynv6_token_file}")"

[ -e "${dynv6_ipv6_file}" ] && old="$(cat "${dynv6_ipv6_file}")"

if [ -z "$dynv6_ipv6_address" ] ; then
  if [ -n "${dynv6_device}" ]; then
    device="dev ${dynv6_device}"
  fi

  # address with netmask
  address="$(ip -6 addr list scope global $device | grep -v " fd" | sed -n 's/.*inet6 \([0-9a-f:]\+\).*/\1/p' | head -n 1)/${netmask:-128}"
else
  address="$dynv6_ipv6_address"
fi

if [ -z "$address" ]; then
  echo "no IPv6 address found" 1>&2
  exit 2
fi

if [ "$old" = "$address" ]; then
  echo "IPv6 address unchanged since last update: $address"
  exit 0
fi

# Clear cache if updating fails
trap 'rm -f $dynv6_ipv6_file' exit

# send addresses to dynv6
curl -fsS "https://dynv6.com/api/update?hostname=${dynv6_zone}&ipv6=$address&token=${dynv6_token}"
curl -fsS "https://ipv4.dynv6.com/api/update?hostname=${dynv6_zone}&ipv4=auto&token=${dynv6_token}"

# save current address
rm -f "${dynv6_ipv6_file}"
echo "$address" > "${dynv6_ipv6_file}"
trap - exit

echo "IPv6 address updated just now: $address"
exit 0

