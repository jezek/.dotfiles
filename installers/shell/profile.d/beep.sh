# echoes current script absolute path
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )" # copy-paste from: https://stackoverflow.com/questions/4774054/reliable-way-for-a-bash-script-to-get-the-full-path-to-itself
BASENAME=$(basename "$0")
echo "BEEP - you runned: "$SCRIPTPATH"/"$BASENAME
