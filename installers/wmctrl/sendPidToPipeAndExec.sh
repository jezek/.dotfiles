#! /bin/bash
pipe=$1
if [[ ! -p $pipe ]]; then
	echo "no pipe found: $pipe"
	exit 1
fi

shift

echo $$ > $pipe
exec "$@"
