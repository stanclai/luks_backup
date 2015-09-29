#!/usr/bin/env sh

[ $# -eq 0 -o "$1" = "--help" -o "$1" = "-h" -o "$1" = "/h" ] && {
cat <<EOF
Usage:
`basename $0` <archive_file_name> [YES_I_WANT_TO_AUTOMAGICALLY_RESTORE_MY_LUKS_HEADER <luks_device>]

<archive_file_name>     Name of the encrypted archive with LUKS header backup
YES_I_WANT_TO_AUTOMAGICALLY_RESTORE_MY_LUKS_HEADER
                        You MUST provide this string as it is to automatically
                        recover your corrupted LUKS header. It's very dangerous
                        operation, so you'll do it at your own risk.
<luks_device>           LUKS device with corrupted header to restore from backup.

To work properly this script needs an utility 'xxd' to be installed.
In case you don't want to use it, feel free to modify this script
and another script for create backup and get rid of any reference of
'xxd'. It will result in slightly longer tarball filenames.

Another utility used by this script is 'par2': recovery information
generator. It's not mandatory to install it, though. But in case
of damaged backup archive additional recovery volumes would be just
what you'd want.
EOF
exit 0
}

[ -z "`which xxd`" ] && { echo "To use this program install 'xxd,' please,"; echo "or modify the script and delete all references to 'xxd'."; exit 1; }

[ -f "$1" ] || { echo "File $1 not found."; exit 1; }

FULLNAME=$1

IFS_=$IFS
IFS='.'
# http://www.etalabs.net/sh_tricks.html [Reading input line-by-line]
read BASENAME DATE HASH SIG EXT <<EOF
$(echo "$FULLNAME")
EOF
IFS=$IFS_

[ -z "$SIG" -o ${#SIG} -ne 22 ] && { echo "Invalid signature. Exiting."; exit 2; }
[ -z "$HASH" -o ${#HASH} -ne 27 ] && { echo "Invalid checksum. Exiting."; exit 2; }

NONCE=`/lib/cryptsetup/askpass "Enter passphrase to decrypt archive:"`

TEST=`echo -n "$BASENAME.$DATE.$HASH.$EXT" | openssl md5 -hmac "$NONCE" -binary | base64 | sed -e 's/=//g' | tr '+/' '-_'`

# This method of filename integrity verification is deprecated.
# It's incompatible with new version of the archiving script.
# But we have to check against it if someone saved the backup
# with old version of the 'luks_save.sh' script.
OLD_TEST=`echo -n "$BASENAME.$DATE.$HASH.$EXT.$NONCE" | md5sum | sed -e 's/\s\+-\s*//' | xxd -r -ps | base64 | sed -e 's/=//g' | tr '+/' '-_'`

if [ "$TEST" = "$SIG" -o "$OLD_TEST" = "$SIG" ]; then
    echo "Archive name is valid."
    HMAC=1
else
    echo "Warning: Archive was renamed or the secret is wrong."
    HMAC=0
fi

HEXHASH=`echo "$HASH=" | tr '_-' '/+' | base64 -d | xxd -ps`

echo "$HEXHASH  $FULLNAME" | sha1sum -c >/dev/null 2>&1 && {
    echo "Archive file is safe."
} || {
    if [ $HMAC -eq 1 ]; then
        echo "Error: Archive file is corrupted."
    else
        echo "Warning: Archive file probably was corrupted, but I'll try to unpack it nevertheless."
    fi
    if [ -f "$FULLNAME.par2" ]; then
        echo "Reparing volumes are present. Good."
        if [ -x "`which par2`" ]; then
            echo "Par2 found... Checking damages..."
            par2 v $FULLNAME.par2 >/dev/null 2>&1
            case $? in
                0)
                    echo "Data are safe. Continue."
                    ;;
                1)
                    echo "Repair is possible."
                    par2 r $FULLNAME.par2
                    echo "Continue with decryption..."
                    ;;
                2)
                    echo "Repair is impossible. Exiting."
                    exit 3
                    ;;
                *)
                    echo "Par2: Unknown error. Exiting."
                    exit 3
                    ;;
            esac
        else
            echo "Par2 not found. Archive can be repaired after par2 utility will be installed."
        fi
    else
        echo "Reparing information is not found."
        [ $HMAC -eq 1 ] && { echo "It's impossible to reconstruct the archive. Exiting."; exit 3; } || { echo "But keep trying."; }
    fi
}

ARCHTYPE=${EXT##tar.}

case "$ARCHTYPE" in
    "Z")
        D="-Z"
        [ -x "`which uncompress`" -o -x "`which uncompress.real`" ] || NODECOMPRESSOR=1
        ;;
    "gz")
        D="-z"
        [ -x "`which gunzip`" -o -x "`which gzip`" ] || NODECOMPRESSOR=1
        ;;
    "bz2")
        D="-j"
        [ -x "`which bunzip2`" -o -x "`which zip2`" ] || NODECOMPRESSOR=1
        ;;
    "xz")
        D="-J"
        [ -x "`which unxz`" -o -x "`which xz`" ] || NODECOMPRESSOR=1
        ;;
    "lzip")
        D="--lzip"
        [ -x "`which lunzip`" -o -x "`which lzip`" ] || NODECOMPRESSOR=1
        ;;
    "lzma")
        # the same s..t, that xz... nevertheless, here we are.
        D="--lzma"
        [ -x "`which unlzma`" -o -x "`which lzmadec`" -o -x "`which lzma`" -o -x "`which unxz`" -o -x "`which xz`" ] || NODECOMPRESSOR=1
        ;;
    "lzo"|"lzop")
        D="--lzop"
        [ -x "`which lzop`" ] || NODECOMPRESSOR=1
        ;;
    "") # just uncompressed tar
        D=""
        ;;
    *)
        echo "Unknown archive type. Exiting."
        exit 3
        ;;
esac

PHRASE=${BASENAME}@${DATE}-${NONCE}
export PASSWD=`echo -n "$PHRASE" | sha256sum | sed -e 's/\s\+-\s*//' | xxd -r -ps | base64`

openssl aes-256-ofb -d -in $FULLNAME -pass env:PASSWD | tar -x $D >/dev/null 2>&1 && {
    [ $HMAC -eq 0 ] && echo "Fine. Archive file was renamed, but its content is intact.";
} || {
    [ $HMAC -eq 0 ] && { echo "Probably you used invalid passphrase. Be more attentive next time. Exiting."; exit 4; }
}

DIRNAME="$BASENAME-$DATE"
cd $DIRNAME

echo ""
echo "Checking sha512 hash..."
sha512sum -c <$BASENAME.sha512 || exit 5
echo ""
echo "Checking sha256 hash..."
sha256sum -c <$BASENAME.sha256 || exit 5
echo ""
echo "Checking sha1 hash..."
sha1sum -c <$BASENAME.sha1 || exit 5
echo ""
echo "Checking md5 hash..."
md5sum -c <$BASENAME.md5 || exit 5

cd ../

if [ -z "$2" ]; then
    echo ""
    echo "Now you can restore your LUKS header from backup"
    echo "using the following command:"
    echo "cryptsetup luksHeaderRestore <your_luks_device> --header-backup-file $DIRNAME/$BASENAME.header --master-key-file $DIRNAME/$BASENAME.mk"
fi

if [ "$2" = "YES_I_WANT_TO_AUTOMAGICALLY_RESTORE_MY_LUKS_HEADER" ]; then
    DEV="$3"
    [ -z "$DEV" ] && { echo "LUKS device name missed. Exiting."; exit 6; }
    [ ! -b "$DEV" -a ! -f "$DEV" ] && { echo "$DEV isn't valid block device. Exiting."; exit 6; }
    cryptsetup luksHeaderRestore $DEV --header-backup-file $DIRNAME/$BASENAME.header --master-key-file $DIRNAME/$BASENAME.mk
    cryptsetup isLuks $DEV && echo "Congratulations! Your LUKS header was restored successfully!" || { echo "Something went terribly wrong... Sorry... The device $DEV isn't valid LUKS device any more."; exit 7; }
fi

exit 0
