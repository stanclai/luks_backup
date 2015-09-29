#!/usr/bin/env sh

[ $# -eq 0 -o "$1" = "--help" -o "$1" = "-h" -o "$1" = "/h" ] &&  {
cat <<EOF
Usage:
`basename $0` <path_to_LUKS_device> [<basename_for_archive>] [--key-file|-k <path_to_keyfile>]

<path_to_LUKS_device>   Full path to encrypted device containing LUKS header
<basename_for_archive>  String identifying all fileset in the archive.
                        If omitted, hostname will be used.
                        If 'hostname' utility is not found, md5 of current
                        date and time will be used.
                        If 'date' is not found, just md5 of random crap
                        from /dev/urandom will be used.
--key-file=<path_to_keyfile>
-k <path_to_keyfile>    For most operations cryptsetup asks for a key. If you
                        have a keyfile, specify it here. Otherwise enter the
                        password when prompted.

To work properly this script needs an utility 'xxd' to be installed.
In case you don't want to use it, feel free to modify this script
and another script for backup recovery and get rid of any reference of
'xxd'. It will result in slightly longer tarball filenames.

Another utility used by this script is 'par2': recovery information
generator. It's not mandatory to install it, though. But in case
of damaged backup archive additional recovery volumes would be just
what you'd want.
EOF
exit 0
}

[ -z "`which xxd`" ] && { echo "To use this program install 'xxd,' please,"; echo "or modify the script and delete all references to 'xxd'."; exit 1; }

[ -b "$1" -o -f "$1" ] || { echo "Invalid device: $1."; exit 2; }
cryptsetup isLuks "$1" || { echo "Device $1 is not valid LUKS device."; exit 2; }

DEVICE="$1"
# - Why 40 characters only?
# - It isn't enough for you?! Well... Just kidding... You can set more, if you want.
BASENAMEMAXCHARS=40

GenBaseName() {
    if [ -n "$1" ]; then
        BASENAME=`echo $1 | cut -c 1-$BASENAMEMAXCHARS`
    elif [ -x "`which hostname`" ]; then
        BASENAME=`hostname`
    elif [ -x "`which date`" ]; then
        BASENAME=`date | md5sum | sed -e 's/\s\+-\s*//'`
    else
        # It's nonsense, though, 'cos both `date` and `head` are in one `coreutils` package.
        # And without `coreutils` installed `[` will not function.
        BASENAME=`head -c 64 /dev/urandom | md5sum | sed -e 's/\s\+-\s*//'`
    fi
    echo "Basename set to $BASENAME";
}

GetKeyFile() {
    PAR="$1"
    # ${PAR:0:11} is Bash'ism. Doesn't work in sh.
    SUBPAR=`echo $PAR | cut -c 1-11`
    case "$SUBPAR" in
        "-k"|"--key-file")
            KEYFILE="$2"
            return 2
            ;;
        "--key-file=")
            KEYFILE=`echo $PAR | cut -c 12-`
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

if [ -z "$2" ]; then
    GenBaseName
    KEYFILE=""
else
    GetKeyFile $2 $3
    case $? in
        0)
            GenBaseName $2;
            GetKeyFile $3 $4;
            ;;
        1)
            GenBaseName $3
            ;;
        2)
            GenBaseName $4
            ;;
        *)
            exit -1
    esac
fi


if [ -x "`which scrub`" ]; then
    RM="scrub -r"
elif [ -x "`which wipe`" ]; then
    RM="wipe -f -s"
elif [ -x "`which shred`" ]; then
    RM="shred -f -u"
else
    RM="rm -f"
fi

if [ -x "`which date`" ]; then
    # I have to be consequent after GenBaseName function %)
    DATE=`date "+%F"`
else
    # maybe some crazy sysadmin was removed `date` for some reason...
    # maye he has quarreled with Time...
    TMP=`mktemp`
    DATE=`ls -l --time-style="+%F" $TMP | cut -d ' ' -f 6`
    rm -f $TMP
fi

DIRNAME="$BASENAME-$DATE"
mkdir -p $DIRNAME

echo -n "Enter uppercase yes"
if [ -z "$KEYFILE" ]; then
# first prompt: YES
# second prompt: passwd
    echo ", after that enter any LUKS passphrase"
    echo "to unlock header and dump master key:"
    RAWHEX=`cryptsetup luksDump --dump-master-key "$DEVICE" | tail -n4 | sed -e 's/^\(.\+:\)\?\s\+//'`
else
    echo -n ": "
    RAWHEX=`cryptsetup luksDump --dump-master-key "$DEVICE" --key-file="$KEYFILE" | tail -n4 | sed -e 's/^\(.\+:\)\?\s\+//'`
fi
echo $RAWHEX | xxd -r -ps > $DIRNAME/$BASENAME.mk
[ -f "$DIRNAME/$BASENAME.header" ] && $RM "$DIRNAME/$BASENAME.header" >/dev/null 2>&1
cryptsetup luksHeaderBackup $DEVICE --master-key-file $DIRNAME/$BASENAME.mk --header-backup-file $DIRNAME/$BASENAME.header && {
    echo "LUKS header is backed up successfully."
    echo "Continue to form encrypted archive."
} || {
    echo "It should not be happened."
    echo "Error: LUKS header was not backed up."
    exit 3
}

cd $DIRNAME
FILESET="$BASENAME.header $BASENAME.mk"

md5sum $FILESET >$BASENAME.md5
sha1sum $FILESET >$BASENAME.sha1
sha256sum $FILESET >$BASENAME.sha256
sha512sum $FILESET >$BASENAME.sha512

#hashrat -whirl -t $FILESET >$BASENAME.whirl
#check: hashrat -c -whirl <$BASENAME.whirl
#hashrat -sha512 -t $FILESET >$BASENAME.sha512
#check: hashrat -c -sha512 <$BASENAME.sha512
# or
#rhash -W -o ${BASENAME}.whirl $PROTECT
##check: rhash -c ${BASENAME}.whirl
#rhash --sha512 -o ${BASENAME}.sha512 $PROTECT
##check: rhash -c ${BASENAME}.sha512

#FILESET="$FILESET $BASENAME.sha512 $BASENAME.sha256 $BASENAME.sha1 $BASENAME.md5"

cd ../
chmod -R a=,u+rX $DIRNAME

EXT="tar"

if [ -x "`which xz`" ]; then
    EXT="$EXT.xz"
    C="-J"
elif [ -x "`which lzma`" ]; then
    EXT="$EXT.lzma"
    C="--lzma"
elif [ -x "`which lzip`" ]; then
    EXT="$EXT.lzip"
    C="--lzip"
elif [ -x "`which bzip2`" ]; then
    EXT="$EXT.bz2"
    C="-j"
elif [ -x "`which lzop`" ]; then
    EXT="$EXT.lzo"
    C="--lzop"
elif [ -x "`which gzip`" ]; then
    EXT="$EXT.gz"
    C="-z"
elif [ -x "`which compress`" ]; then
    EXT="$EXT.Z"
    C="-Z"
else
    echo "Warning: No suitable compressors found. Making uncompressed tarball."
    C=""
fi

DATA=${BASENAME}.${DATE}.${EXT}
echo -n ""
NONCE=`/lib/cryptsetup/askpass "Enter passphrase to encrypt archive:"`
PHRASE=${BASENAME}@${DATE}-${NONCE}
export PASSWD=`echo -n "$PHRASE" | openssl sha256 -binary | base64`
# or
#export PASSWD=`echo -n "$PHRASE" | sha256sum | sed -e 's/\s\+-\s*//' | xxd -r -ps | base64`
# or
#export PASSWD=`echo -n "$PHRASE" | hashrat -rl -sha256 -64`
# or
#export PASSWD=`echo -n "$PHRASE" | sha256 | base64` #hashalot
# or
#export PASSWD=`echo -n "$PHRASE" | rhash -p '%B{sha-256}\n' -`

tar -c $C $DIRNAME | openssl aes-256-ofb -out $DATA -pass env:PASSWD && {

    HASH=`openssl sha1 -binary <$DATA | base64 | sed -e 's/=//g' | tr '+/' '-_'`
#    HASH=`sha1sum <$DATA | sed -e 's/\s\+-\s*//' | xxd -r -ps | base64 | sed -e 's/=//g' | tr '+/' '-_'`
#    HASH=`hashrat -sha1 -64 $DATA | sed -e 's/=//g' | tr '+/' '-_'`
    NAMETOSIGN=${BASENAME}.${DATE}.${HASH}.${EXT}
    SIG=`echo -n "$NAMETOSIGN" | openssl md5 -hmac "${NONCE}" -binary | base64 | sed -e 's/=//g' | tr '+/' '-_'`
#    or
#    SIG=`echo -n "$NAMETOSIGN" | hashrat -md5 -64 | sed -e 's/=//g' | tr '+/' '-_'`

#
# Attention! This is deprecated approach to sign the file name.
# It's incompatible with new version of backup restore script.
#    NAMETOSIGN=${BASENAME}.${DATE}.${HASH}.${EXT}.${NONCE}
#    SIG=`echo -n "$NAMETOSIGN" | md5sum | sed -e 's/\s\+-\s*//' | xxd -r -ps | base64 | sed -e 's/=//g' | tr '+/' '-_'`
#
    NEWNAME=${BASENAME}.${DATE}.${HASH}.${SIG}.${EXT}

    mv $DATA $NEWNAME
    if [ -x "`which par2`" ]; then
        PAR2=1
        echo "Par2 found. Creating recovery volumes..."
        par2 c -r7 $NEWNAME
    else
        echo "Par2 not found. In case of damage recovery would not be possible."
    fi
}

cd $DIRNAME
$RM $FILESET >/dev/null 2>&1
cd ../
rm -rf $DIRNAME

echo "All files are ready."
if [ "$PAR2" = "1" ]; then
    echo "Please put encrypted $EXT archive and all par2 recovery volumes"
    echo "in a safe place and lock the passphrase for archive decrypting"
    echo "in your favourite password manager."
else
    echo "Please put encrypted $EXT archive in a safe place and lock "
    echo "the passphrase for archive decrypting in your favourite password"
    echo "manager."
    echo "If you want to protect your backup archive, you may want to install"
    echo "'par2' and add some redundancy volumes, e.g. somehow as"
    echo "par2 c -r7 <archive_file_name>"
fi

exit 0
