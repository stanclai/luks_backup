# LUKS Backup Helper Scripts

## Description

Two shell scripts intended to save and restore LUKS critical data (such as header and master key) in safe manner.
In details that means that LUKS header and master key are protected by several hash sums, then are packed and
encrypted with AES-256 (OFB). Encrypted tarball then gets additional protection using several recovery volumes.
This last step is optional and is performed only if utility `par2` is found on the host.

## Usage

### To save LUKS header backup

`luks_save.sh <path_to_LUKS_device> [<basename_for_archive>] [--key-file|-k <path_to_keyfile>]`

<dl>
<dt>&lt;path_to_LUKS_device&gt;</dt>
<dd>Full path to encrypted device containing LUKS header</dd>
<dt>&lt;basename_for_archive&gt;</dt>
<dd>String identifying all fileset in the archive.  
    If omitted, hostname will be used.  
    If 'hostname' utility is not found, md5 of current  
    date and time will be used.  
    If 'date' is not found, just md5 of random crap  
    from /dev/urandom will be used.</dd>
<dt>--key-file=&lt;path_to_keyfile&gt; | -k &lt;path_to_keyfile&gt;</dt>
<dd>For most operations cryptsetup asks for a key. If you  
    have a keyfile, specify it here. Otherwise enter the  
    password when prompted.</dd>
</dl>

### To restore LUKS header backup

`luks_restore.sh <archive_file_name> [YES_I_WANT_TO_AUTOMAGICALLY_RESTORE_MY_LUKS_HEADER <luks_device>]`

<dl>
<dt>&lt;archive_file_name&gt;</dt>
<dd>Name of the encrypted archive with LUKS header backup</dd>
<dt>YES_I_WANT_TO_AUTOMAGICALLY_RESTORE_MY_LUKS_HEADER</dt>
<dd>You MUST provide this string as it is to automatically
recover your corrupted LUKS header. It's very dangerous
operation, so you'll do it at your own risk.</dd>
<dt>&lt;luks_device&gt;</dt>
<dd>LUKS device with corrupted header to restore from backup.</dd>
</dl>

## Complementary software used by scripts

Mainly that will do to have coreutils and cryptsetup on board.
But there are some important details.

To work properly this script needs an utility `xxd` to be installed.
In case you don't want to use it, feel free to modify the scripts
and get rid of any reference of `xxd`. It will result in slightly
longer tarball filenames.

Another utility used by this script is `par2`: recovery information
generator. It's not mandatory to install it, though. But in case
of damaged backup archive additional recovery volumes would be just
what you'd want.
