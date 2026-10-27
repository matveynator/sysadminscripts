#!/bin/bash

set -u
set -o pipefail

# install gurl (golang curl with ssl)
curl -L 'http://files.zabiyaka.net/gurl/latest/linux/amd64/gurl' > /usr/local/bin/gurl; 
chmod +x /usr/local/bin/gurl;

###############################################################################
# PHP 5.4.45 / Debian 6 / Dotdeb
# CVE-2026-109618 + CVE-2026-109619
###############################################################################

OLDVER='5.4.45-1~dotdeb+6.1'
NEWVER='5.4.45-1~dotdeb+6.1+php2shell1'

STAMP="$(date +%Y%m%d-%H%M%S)"

BASE=/root/php54-php2shell
WORK="$BASE/work-$STAMP"
SRCROOT="$WORK/src"
STAGE="$WORK/stage"
PKGOUT="$BASE/packages/$NEWVER"

BACKUP="/backup/php54-before-php2shell-$STAMP"

DOTDEB_HTTPS='https://mirrors.nju.edu.cn/dotdeb/pool/all/p/php5'
DOTDEB_HTTP='http://mirrors.nju.edu.cn/dotdeb/pool/all/p/php5'

DSCNAME='php5_5.4.45-1~dotdeb+6.1.dsc'

PATCH_REPO='axon003/php-legacy-cve-2026-109618'
PATCH_NAME='php-5.4.45-cve-2026-109618-109619.patch'

INSTALL_STARTED=0
POLICY_SAVED=0
HAD_POLICY=0

###############################################################################

die()
{
    echo
    echo "ERROR: $*"
    echo
    exit 1
}

section()
{
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

fetch_url()
{
    URL="$1"
    OUT="$2"

    N=1

    while [ "$N" -le 8 ]
    do
        echo "Download attempt $N:"
        echo "  $URL"

        rm -f "$OUT.tmp"

        if gurl -o "$OUT.tmp" "$URL"; then
            if [ -s "$OUT.tmp" ]; then
                mv "$OUT.tmp" "$OUT"
                return 0
            fi
        fi

        rm -f "$OUT.tmp"
        N=$((N + 1))
        sleep 2
    done

    return 1
}

fetch_dotdeb()
{
    FILE="$1"
    OUT="$2"

    if fetch_url "$DOTDEB_HTTPS/$FILE" "$OUT"; then
        return 0
    fi

    echo "HTTPS mirror failed, trying HTTP..."

    if fetch_url "$DOTDEB_HTTP/$FILE" "$OUT"; then
        return 0
    fi

    return 1
}

apt_simulate()
{
    apt-get \
        -o Acquire::Check-Valid-Until=false \
        -s install "$@"
}

apt_install()
{
    apt-get \
        -o Acquire::Check-Valid-Until=false \
        --allow-unauthenticated \
        --no-remove \
        -y install "$@"
}

###############################################################################
# PLATFORM
###############################################################################

section "PRECHECK"

[ "$(id -u)" = "0" ] || die "run as root"

command -v gurl >/dev/null 2>&1 || die "gurl not found"

[ "$(uname -m)" = "x86_64" ] || die "expected x86_64"

grep -q '^6\.' /etc/debian_version || {
    echo "Debian version:"
    cat /etc/debian_version
    die "expected Debian 6"
}

CURPHP="$(dpkg-query -W -f='${Version}' php5-cli 2>/dev/null || true)"

[ "$CURPHP" = "$OLDVER" ] || {
    echo "Installed php5-cli: $CURPHP"
    die "expected $OLDVER"
}

apache2ctl -V 2>&1 | grep -qi 'Server MPM:.*Prefork' \
    || die "Apache is not Prefork"

apache2ctl -M 2>&1 | grep -q 'php5_module' \
    || die "php5_module not loaded"

php -m 2>/dev/null | grep -Fxq 'XCache' \
    || die "XCache is not loaded"

echo
php -v

echo
php -n -i | grep -E \
'^(PHP API|PHP Extension|Zend Extension|Zend Extension Build|PHP Extension Build|Thread Safety)'

php -n -i | grep -q '^PHP API => 20100412$' \
    || die "wrong PHP API"

php -n -i | grep -q '^PHP Extension => 20100525$' \
    || die "wrong PHP extension ABI"

php -n -i | grep -q '^Zend Extension => 220100525$' \
    || die "wrong Zend ABI"

php -n -i | grep -q '^PHP Extension Build => API20100525,NTS$' \
    || die "expected NTS ABI"

###############################################################################
# DPKG STATE
###############################################################################

section "DPKG CHECK"

AUDIT="$(dpkg --audit 2>&1 || true)"

if [ -n "$AUDIT" ]; then
    echo "$AUDIT"
    die "dpkg database not clean"
fi

echo "dpkg OK"

###############################################################################
# DIRECTORIES
###############################################################################

mkdir -p \
    "$SRCROOT" \
    "$STAGE" \
    "$PKGOUT" \
    "$BACKUP/runtime/usr/lib/apache2/modules" \
    "$BACKUP/runtime/usr/lib" \
    "$BACKUP/configs" \
    "$BACKUP/rollback" \
    "$BACKUP/diagnostics" \
    "$BACKUP/logs" \
    "$BACKUP/source"

###############################################################################
# BACKUP CURRENT SYSTEM
###############################################################################

section "BACKUP CURRENT PHP/APACHE"

dpkg --get-selections \
    > "$BACKUP/diagnostics/dpkg-selections.txt"

dpkg-query -W \
    -f='${binary:Package}\t${Version}\t${Status}\n' \
    > "$BACKUP/diagnostics/packages.txt"

php -v \
    > "$BACKUP/diagnostics/php-version.txt" 2>&1

php -m \
    > "$BACKUP/diagnostics/php-modules.txt" 2>&1

php -i \
    > "$BACKUP/diagnostics/php-info.txt" 2>&1

apache2ctl -V \
    > "$BACKUP/diagnostics/apache-version.txt" 2>&1

apache2ctl -M \
    > "$BACKUP/diagnostics/apache-modules.txt" 2>&1

apache2ctl -S \
    > "$BACKUP/diagnostics/apache-vhosts.txt" 2>&1 || true

cp -a /etc/php5 "$BACKUP/configs/"
cp -a /etc/apache2 "$BACKUP/configs/"

cp -a \
    /usr/lib/apache2/modules/libphp5.so \
    "$BACKUP/runtime/usr/lib/apache2/modules/"

cp -a \
    /usr/lib/php5 \
    "$BACKUP/runtime/usr/lib/"

sha256sum \
    /usr/lib/apache2/modules/libphp5.so \
    | tee "$BACKUP/diagnostics/libphp5-before.sha256"

###############################################################################
# ROLLBACK DEBS
###############################################################################

section "COLLECT ROLLBACK PACKAGES"

copy_old_deb()
{
    P="$1"
    FOUND=""

    for F in /var/cache/apt/archives/"${P}"_*.deb
    do
        [ -f "$F" ] || continue

        V="$(dpkg-deb -f "$F" Version 2>/dev/null || true)"

        if [ "$V" = "$OLDVER" ]; then
            FOUND="$F"
            break
        fi
    done

    [ -n "$FOUND" ] || die "rollback .deb missing for $P"

    echo "ROLLBACK $P:"
    echo "  $FOUND"

    cp -a "$FOUND" "$BACKUP/rollback/"
}

copy_old_deb libapache2-mod-php5
copy_old_deb php5
copy_old_deb php5-cli
copy_old_deb php5-common
copy_old_deb php5-gd
copy_old_deb php5-mysql
copy_old_deb php5-xcache

echo
ls -lh "$BACKUP/rollback"

###############################################################################
# APT
###############################################################################

section "APT UPDATE"

apt-get \
    -o Acquire::Check-Valid-Until=false \
    update \
    2>&1 | tee "$BACKUP/logs/apt-update.log"

###############################################################################
# BASIC PACKAGING TOOLS
###############################################################################

section "INSTALL BASIC BUILD TOOLS"

BASIC="dpkg-dev python-minimal"

apt_simulate $BASIC \
    > "$BACKUP/logs/apt-basic-simulate.log" 2>&1 \
    || {
        cat "$BACKUP/logs/apt-basic-simulate.log"
        die "cannot resolve basic build tools"
    }

if grep -q '^Remv ' "$BACKUP/logs/apt-basic-simulate.log"; then
    cat "$BACKUP/logs/apt-basic-simulate.log"
    die "APT wants to remove packages"
fi

apt_install $BASIC \
    2>&1 | tee "$BACKUP/logs/apt-basic-install.log" \
    || die "basic build tools installation failed"

command -v dpkg-source >/dev/null 2>&1 \
    || die "dpkg-source still missing"

###############################################################################
# DOWNLOAD EXACT DOTDEB SOURCE
###############################################################################

section "DOWNLOAD DOTDEB SOURCE"

cd "$SRCROOT" || die "cannot enter source dir"

fetch_dotdeb "$DSCNAME" "$SRCROOT/$DSCNAME" \
    || die "cannot download Dotdeb .dsc"

grep -q '^Source: php5$' "$SRCROOT/$DSCNAME" \
    || die "wrong source package"

grep -Fq "Version: $OLDVER" "$SRCROOT/$DSCNAME" \
    || {
        cat "$SRCROOT/$DSCNAME"
        die "wrong source version"
    }

echo
echo "DSC:"
grep -E '^(Source|Version|Format):' "$SRCROOT/$DSCNAME"

###############################################################################
# EXTRACT SOURCE FILE LIST FROM DSC
###############################################################################

awk '
    /^Files:/ { in_files=1; next }

    in_files && /^[ \t]/ {
        print $1 "  " $3
        next
    }

    in_files {
        exit
    }
' "$SRCROOT/$DSCNAME" > "$SRCROOT/source.md5"

[ -s "$SRCROOT/source.md5" ] \
    || die "could not parse Files section from dsc"

echo
echo "Source files:"
cat "$SRCROOT/source.md5"

###############################################################################
# DOWNLOAD SOURCE FILES
###############################################################################

while read MD5 FILE
do
    [ -n "$FILE" ] || continue

    echo
    echo "Fetching $FILE"

    if ! fetch_dotdeb "$FILE" "$SRCROOT/$FILE"; then

        # The upstream orig tarball is also preserved by Debian archive.
        case "$FILE" in
            php5_5.4.45.orig.tar.*)
                echo "Trying Debian archive for upstream tarball..."

                fetch_url \
                    "http://archive.debian.org/debian/pool/main/p/php5/$FILE" \
                    "$SRCROOT/$FILE" \
                    || die "cannot download $FILE"
                ;;
            *)
                die "cannot download $FILE"
                ;;
        esac
    fi

done < "$SRCROOT/source.md5"

###############################################################################
# VERIFY DOTDEB SOURCE CHECKSUMS
###############################################################################

section "VERIFY SOURCE CHECKSUMS"

cd "$SRCROOT" || die

md5sum -c source.md5 \
    || die "Dotdeb source checksum mismatch"

cp -a "$SRCROOT/$DSCNAME" "$BACKUP/source/"
cp -a "$SRCROOT/source.md5" "$BACKUP/source/"

###############################################################################
# EXTRACT SOURCE
###############################################################################

section "EXTRACT SOURCE"

dpkg-source -x "$SRCROOT/$DSCNAME" \
    2>&1 | tee "$BACKUP/logs/dpkg-source.log" \
    || die "dpkg-source failed"

SRCDIR="$(
    find "$SRCROOT" \
        -maxdepth 1 \
        -type d \
        -name 'php5-5.4.45*' \
        | head -1
)"

[ -n "$SRCDIR" ] || die "PHP source directory not found"

echo "Source directory:"
echo "$SRCDIR"

cd "$SRCDIR" || die

###############################################################################
# MYSQL SERVER IS NOT NEEDED FOR nocheck BUILD
###############################################################################

section "REMOVE MYSQL-SERVER BUILD-ONLY DEPENDENCY"

python <<'PY'
import re

path = "debian/control"
data = open(path, "r").read()

# Remove a standalone mysql-server / virtual-mysql-server Build-Depends line.
data = re.sub(
    r'(?m)^[ \t]*mysql-server(?:[ \t]*\|[ \t]*virtual-mysql-server)?[ \t]*,?[ \t]*\n',
    '',
    data
)

# Handle an inline form if present.
data = re.sub(
    r',[ \t]*mysql-server(?:[ \t]*\|[ \t]*virtual-mysql-server)?[ \t]*(?=,)',
    '',
    data
)

open(path, "w").write(data)
PY

grep -n 'mysql-server\|virtual-mysql-server' debian/control \
    && die "mysql-server dependency still present" \
    || true

###############################################################################
# DETERMINE BUILD DEPENDENCIES
###############################################################################

section "RESOLVE BUILD DEPENDENCIES"

python <<'PY' > "$WORK/build-deps.txt"
import os
import re
import subprocess
import sys

text = open("debian/control", "r").read()
source = text.split("\n\n", 1)[0]

fields = {}
current = None

for line in source.splitlines():
    if line.startswith(" ") or line.startswith("\t"):
        if current:
            fields[current] += " " + line.strip()
        continue

    if ":" in line:
        key, value = line.split(":", 1)
        current = key.strip()
        fields[current] = value.strip()

raw = []

for key in ("Build-Depends", "Build-Depends-Indep"):
    if key in fields:
        raw.append(fields[key])

deps = ",".join(raw)

chosen = []

def available(pkg):
    p = subprocess.Popen(
        ["apt-cache", "show", pkg],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    out, err = p.communicate()
    return re.search(r"(?m)^Package:\s*" + re.escape(pkg) + r"\s*$", out) is not None

for clause in deps.split(","):
    clause = clause.strip()

    if not clause:
        continue

    # Architecture restrictions in this package are not exclusions for amd64.
    clause = re.sub(r"\[[^\]]*\]", "", clause)

    alternatives = clause.split("|")
    selected = None

    for alt in alternatives:
        alt = re.sub(r"\([^)]*\)", "", alt)
        alt = alt.strip()

        if not alt:
            continue

        # Strip old multiarch qualifier if present.
        pkg = alt.split(":", 1)[0].strip()

        if pkg in ("mysql-server", "virtual-mysql-server"):
            continue

        if available(pkg):
            selected = pkg
            break

    if selected is None:
        sys.stderr.write("No available package for dependency: %s\n" % clause)
        sys.exit(2)

    if selected not in chosen:
        chosen.append(selected)

for pkg in chosen:
    print pkg
PY

[ "$?" = "0" ] || die "could not resolve build dependencies"

echo
cat "$WORK/build-deps.txt"

BUILD_DEPS="$(tr '\n' ' ' < "$WORK/build-deps.txt")"

###############################################################################
# SIMULATE BUILD DEP INSTALL
###############################################################################

section "SIMULATE BUILD DEP INSTALL"

apt-get \
    -o Acquire::Check-Valid-Until=false \
    -s install $BUILD_DEPS \
    > "$BACKUP/logs/apt-builddeps-simulate.log" 2>&1 \
    || {
        cat "$BACKUP/logs/apt-builddeps-simulate.log"
        die "build dependency simulation failed"
    }

if grep -q '^Remv ' "$BACKUP/logs/apt-builddeps-simulate.log"; then
    cat "$BACKUP/logs/apt-builddeps-simulate.log"
    die "APT wants to remove packages; refusing"
fi

echo "Simulation OK"

###############################################################################
# INSTALL BUILD DEPENDENCIES
###############################################################################

section "INSTALL BUILD DEPENDENCIES"

apt_install $BUILD_DEPS \
    2>&1 | tee "$BACKUP/logs/apt-builddeps-install.log" \
    || die "build dependency installation failed"

###############################################################################
# FINAL BUILD DEP CHECK
###############################################################################

section "DPKG BUILDCHECK"

cd "$SRCDIR" || die

if ! dpkg-checkbuilddeps \
        > "$BACKUP/logs/dpkg-checkbuilddeps.log" 2>&1
then
    cat "$BACKUP/logs/dpkg-checkbuilddeps.log"
    die "build dependencies are still missing"
fi

echo "All build dependencies satisfied."

###############################################################################
# DOWNLOAD PATCH - RESOLVE CURRENT MAIN TO IMMUTABLE COMMIT
###############################################################################

section "DOWNLOAD PHP2SHELL PATCH"

PATCH_META="$WORK/patch-commit.json"

fetch_url \
    "https://api.github.com/repos/$PATCH_REPO/commits/main" \
    "$PATCH_META" \
    || die "cannot resolve patch repository commit"

PATCH_COMMIT="$(
    sed -n \
      's/^[[:space:]]*"sha":[[:space:]]*"\([0-9a-f]\{40\}\)".*/\1/p' \
      "$PATCH_META" \
      | head -1
)"

echo "$PATCH_COMMIT" | grep -Eq '^[0-9a-f]{40}$' \
    || die "invalid GitHub commit hash"

echo "Patch repository commit:"
echo "$PATCH_COMMIT"

PATCHFILE="$WORK/$PATCH_NAME"

fetch_url \
    "https://raw.githubusercontent.com/$PATCH_REPO/$PATCH_COMMIT/patches/$PATCH_NAME" \
    "$PATCHFILE" \
    || die "cannot download PHP 5.4 patch"

###############################################################################
# SANITY CHECK PATCH
###############################################################################

grep -q 'max_multipart_body_parts' "$PATCHFILE" \
    || die "patch does not contain multipart limit"

grep -q 'zend_mm_safe_error_ex' "$PATCHFILE" \
    || die "patch does not contain safe OOM handling"

grep -q 'CVE-2026-109619' "$PATCHFILE" \
    || die "patch does not mention CVE-2026-109619"

sha256sum "$PATCHFILE" \
    | tee "$BACKUP/source/php2shell-patch.sha256"

echo "$PATCH_COMMIT" \
    > "$BACKUP/source/php2shell-patch.commit"

cp -a "$PATCHFILE" "$BACKUP/source/"

###############################################################################
# PATCH DRY RUN
###############################################################################

section "PATCH DRY RUN"

cd "$SRCDIR" || die

patch --dry-run -p1 < "$PATCHFILE" \
    > "$BACKUP/logs/patch-dry-run.log" 2>&1 \
    || {
        cat "$BACKUP/logs/patch-dry-run.log"
        die "PHP 5.4 patch does not cleanly apply to Dotdeb source"
    }

cat "$BACKUP/logs/patch-dry-run.log"

echo
echo "PATCH DRY RUN OK"

###############################################################################
# APPLY THROUGH QUILT WHEN AVAILABLE
###############################################################################

section "APPLY PATCH"

if [ -f debian/patches/series ]; then

    cp -a \
        "$PATCHFILE" \
        "debian/patches/9999-php2shell-cve-2026.patch"

    if ! grep -q '^9999-php2shell-cve-2026.patch' debian/patches/series
    then
        echo '9999-php2shell-cve-2026.patch -p1' \
            >> debian/patches/series
    fi

    export QUILT_PATCHES=debian/patches

    quilt push -a \
        2>&1 | tee "$BACKUP/logs/quilt.log" \
        || die "quilt could not apply security patch"

else

    echo "No quilt series; applying directly."

    patch -p1 < "$PATCHFILE" \
        2>&1 | tee "$BACKUP/logs/patch-apply.log" \
        || die "patch application failed"
fi

###############################################################################
# BUMP DEBIAN VERSION
###############################################################################

section "BUMP PACKAGE VERSION"

TMPCHANGE="$WORK/changelog.new"

{
    echo "php5 ($NEWVER) squeeze; urgency=high"
    echo
    echo "  * Local security rebuild."
    echo "  * Backport mitigations for CVE-2026-109618 and CVE-2026-109619."
    echo
    echo " -- Local Security Build <root@localhost>  $(date -R)"
    echo
    cat debian/changelog
} > "$TMPCHANGE"

mv "$TMPCHANGE" debian/changelog

HEADVER="$(dpkg-parsechangelog -SVersion)"

[ "$HEADVER" = "$NEWVER" ] \
    || die "changelog version incorrect: $HEADVER"

head -10 debian/changelog

###############################################################################
# BUILD
###############################################################################

section "BUILD PHP 5.4 PACKAGES"

cd "$SRCDIR" || die

export DEB_BUILD_OPTIONS='nocheck parallel=2'

dpkg-buildpackage -b -uc -us \
    2>&1 | tee "$BACKUP/logs/php54-build.log"

BUILD_RC=${PIPESTATUS[0]}

[ "$BUILD_RC" = "0" ] \
    || die "PHP package build failed"

###############################################################################
# LOCATE REQUIRED PACKAGES
###############################################################################

section "VERIFY BUILT PACKAGES"

find_built()
{
    P="$1"
    A="$2"

    F="$(
        find "$SRCROOT" \
            -maxdepth 1 \
            -type f \
            -name "${P}_${NEWVER}_${A}.deb" \
            | head -1
    )"

    [ -n "$F" ] || die "built package missing: $P ($A)"

    V="$(dpkg-deb -f "$F" Version)"
    N="$(dpkg-deb -f "$F" Package)"
    ARCH="$(dpkg-deb -f "$F" Architecture)"

    [ "$V" = "$NEWVER" ] || die "wrong version in $F"
    [ "$N" = "$P" ] || die "wrong package name in $F"
    [ "$ARCH" = "$A" ] || die "wrong architecture in $F"

    echo "$F"
}

NEW_COMMON="$(find_built php5-common amd64)"
NEW_CLI="$(find_built php5-cli amd64)"
NEW_GD="$(find_built php5-gd amd64)"
NEW_MYSQL="$(find_built php5-mysql amd64)"
NEW_APACHE="$(find_built libapache2-mod-php5 amd64)"
NEW_META="$(find_built php5 all)"

for F in \
    "$NEW_COMMON" \
    "$NEW_CLI" \
    "$NEW_GD" \
    "$NEW_MYSQL" \
    "$NEW_APACHE" \
    "$NEW_META"
do
    echo
    echo "$F"
    dpkg-deb -f "$F" Package Version Architecture
    cp -a "$F" "$PKGOUT/"
done

cp -a "$PATCHFILE" "$PKGOUT/"
cp -a "$BACKUP/source/php2shell-patch.sha256" "$PKGOUT/"
cp -a "$BACKUP/source/php2shell-patch.commit" "$PKGOUT/"

###############################################################################
# OFFLINE STAGE
###############################################################################

section "OFFLINE TEST"

rm -rf "$STAGE"
mkdir -p "$STAGE"

for F in \
    "$NEW_COMMON" \
    "$NEW_CLI" \
    "$NEW_GD" \
    "$NEW_MYSQL" \
    "$NEW_APACHE"
do
    dpkg-deb -x "$F" "$STAGE" \
        || die "cannot extract $F"
done

NEWPHP="$STAGE/usr/bin/php5"
NEWLIB="$STAGE/usr/lib/apache2/modules/libphp5.so"

[ -x "$NEWPHP" ] || die "new staged PHP binary missing"
[ -f "$NEWLIB" ] || die "new staged libphp5.so missing"

echo
"$NEWPHP" -n -v || die "new PHP CLI cannot start"

###############################################################################
# ABI MUST BE IDENTICAL
###############################################################################

"$NEWPHP" -n -i \
    > "$BACKUP/diagnostics/new-php-info.txt"

grep -q '^PHP API => 20100412$' \
    "$BACKUP/diagnostics/new-php-info.txt" \
    || die "new PHP API changed"

grep -q '^PHP Extension => 20100525$' \
    "$BACKUP/diagnostics/new-php-info.txt" \
    || die "new extension ABI changed"

grep -q '^Zend Extension => 220100525$' \
    "$BACKUP/diagnostics/new-php-info.txt" \
    || die "new Zend ABI changed"

grep -q '^PHP Extension Build => API20100525,NTS$' \
    "$BACKUP/diagnostics/new-php-info.txt" \
    || die "new PHP is not expected NTS ABI"

echo "ABI OK"

###############################################################################
# LIBRARIES
###############################################################################

echo
echo "New CLI libraries:"

ldd "$NEWPHP" \
    | tee "$BACKUP/diagnostics/new-php-ldd.txt"

grep -q 'not found' "$BACKUP/diagnostics/new-php-ldd.txt" \
    && die "new PHP CLI has unresolved libraries"

echo
echo "New Apache module libraries:"

ldd "$NEWLIB" \
    | tee "$BACKUP/diagnostics/new-libphp-ldd.txt"

grep -q 'not found' "$BACKUP/diagnostics/new-libphp-ldd.txt" \
    && die "new libphp5.so has unresolved libraries"

###############################################################################
# TEST CURRENT EXTENSIONS, ESPECIALLY XCACHE
###############################################################################

echo
echo "Testing current extensions with new binary..."

"$NEWPHP" \
    -c /etc/php5/cli/php.ini \
    -d display_errors=1 \
    -d display_startup_errors=1 \
    -m \
    > "$BACKUP/diagnostics/new-php-modules.txt" \
    2> "$BACKUP/diagnostics/new-php-startup-errors.txt"

if grep -Ei \
'PHP Startup|Unable to load|undefined symbol|cannot open shared object|segmentation|segfault' \
"$BACKUP/diagnostics/new-php-startup-errors.txt"
then
    cat "$BACKUP/diagnostics/new-php-startup-errors.txt"
    die "extension compatibility failure"
fi

for M in \
    bcmath gd mbstring mysql mysqli openssl PDO pdo_mysql \
    XCache "XCache Cacher" xml xmlreader xmlwriter zip
do
    if grep -Fxq "$M" "$BACKUP/diagnostics/new-php-modules.txt"; then
        echo "OK    $M"
    else
        die "required module missing with new PHP: $M"
    fi
done

###############################################################################
# SECURITY PATCH SIGNAL
###############################################################################

echo
echo "Checking max_multipart_body_parts..."

"$NEWPHP" -n -r '
$v = ini_get("max_multipart_body_parts");
if ($v === false) {
    fwrite(STDERR, "MISSING\n");
    exit(1);
}
echo "max_multipart_body_parts=", $v, "\n";
' || die "security patch signal missing"

###############################################################################
# EXPECTED MODULE CHECKSUM
###############################################################################

EXPECTED_LIBPHP_SHA="$(
    sha256sum "$NEWLIB" | awk '{print $1}'
)"

echo "$EXPECTED_LIBPHP_SHA  $NEWLIB" \
    > "$BACKUP/diagnostics/expected-libphp5.sha256"

###############################################################################
# APACHE BEFORE INSTALL
###############################################################################

section "APACHE PRE-INSTALL CHECK"

apache2ctl configtest \
    || die "Apache configuration already broken"

###############################################################################
# SERVICE RESTART BLOCK
###############################################################################

save_policy()
{
    if [ "$POLICY_SAVED" = "1" ]; then
        return
    fi

    POLICY_SAVED=1

    if [ -e /usr/sbin/policy-rc.d ]; then
        HAD_POLICY=1
        cp -a \
            /usr/sbin/policy-rc.d \
            "$BACKUP/policy-rc.d.original"
    fi
}

block_services()
{
    save_policy

    cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF

    chmod 755 /usr/sbin/policy-rc.d
}

restore_policy()
{
    if [ "$POLICY_SAVED" != "1" ]; then
        return
    fi

    if [ "$HAD_POLICY" = "1" ]; then
        cp -a \
            "$BACKUP/policy-rc.d.original" \
            /usr/sbin/policy-rc.d
    else
        rm -f /usr/sbin/policy-rc.d
    fi
}

###############################################################################
# ROLLBACK
###############################################################################

rollback()
{
    echo
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo " INSTALL FAILED - ROLLBACK"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo

    block_services

    /etc/init.d/apache2 stop || true

    echo
    echo "Restoring old packages..."

    dpkg -i \
        "$BACKUP/rollback/php5-common_${OLDVER}_amd64.deb" \
        "$BACKUP/rollback/php5-cli_${OLDVER}_amd64.deb" \
        "$BACKUP/rollback/php5-gd_${OLDVER}_amd64.deb" \
        "$BACKUP/rollback/php5-mysql_${OLDVER}_amd64.deb" \
        "$BACKUP/rollback/libapache2-mod-php5_${OLDVER}_amd64.deb" \
        "$BACKUP/rollback/php5_${OLDVER}_all.deb" \
        || true

    echo
    echo "Restoring exact runtime..."

    rm -rf /usr/lib/php5
    cp -a "$BACKUP/runtime/usr/lib/php5" /usr/lib/

    cp -a \
        "$BACKUP/runtime/usr/lib/apache2/modules/libphp5.so" \
        /usr/lib/apache2/modules/libphp5.so

    rm -rf /etc/php5
    cp -a "$BACKUP/configs/php5" /etc/php5

    rm -rf /etc/apache2
    cp -a "$BACKUP/configs/apache2" /etc/apache2

    restore_policy

    echo
    apache2ctl configtest || true

    /etc/init.d/apache2 start || true

    echo
    echo "PHP after rollback:"
    php -v || true

    echo
    echo "Modules:"
    php -m 2>/dev/null | grep -E '^XCache|^mysql$|^mysqli$|^PDO$|^pdo_mysql$' || true

    echo
    echo "Apache:"
    apache2ctl -M 2>&1 | grep -E 'php|mpm' || true

    echo
    echo "ROLLBACK COMPLETE"
    echo "Backup: $BACKUP"

    exit 1
}

signal_handler()
{
    echo
    echo "Signal received."

    if [ "$INSTALL_STARTED" = "1" ]; then
        rollback
    fi

    restore_policy
    exit 130
}

trap signal_handler INT TERM

###############################################################################
# INSTALL
###############################################################################

section "INSTALL PATCHED PHP"

block_services

INSTALL_STARTED=1

dpkg -i \
    "$NEW_COMMON" \
    "$NEW_CLI" \
    "$NEW_GD" \
    "$NEW_MYSQL" \
    "$NEW_APACHE" \
    "$NEW_META" \
    || rollback

###############################################################################
# VERIFY PACKAGE VERSIONS
###############################################################################

section "VERIFY INSTALLED VERSIONS"

for P in \
    libapache2-mod-php5 \
    php5 \
    php5-cli \
    php5-common \
    php5-gd \
    php5-mysql
do
    V="$(dpkg-query -W -f='${Version}' "$P" 2>/dev/null || true)"

    echo "$P    $V"

    [ "$V" = "$NEWVER" ] \
        || rollback
done

###############################################################################
# VERIFY CLI
###############################################################################

section "VERIFY LIVE PHP CLI"

php -v || rollback

php -v 2>&1 | head -1 | grep -Fq "$NEWVER" \
    || rollback

php -r '
$v = ini_get("max_multipart_body_parts");
if ($v === false) exit(1);
echo "max_multipart_body_parts=", $v, "\n";
' || rollback

###############################################################################
# VERIFY XCACHE
###############################################################################

php -m \
    > "$BACKUP/diagnostics/live-modules-after.txt" \
    2> "$BACKUP/diagnostics/live-startup-errors-after.txt" \
    || rollback

if grep -Ei \
'PHP Startup|Unable to load|undefined symbol|cannot open shared object|segmentation|segfault' \
"$BACKUP/diagnostics/live-startup-errors-after.txt"
then
    cat "$BACKUP/diagnostics/live-startup-errors-after.txt"
    rollback
fi

grep -Fxq 'XCache' \
    "$BACKUP/diagnostics/live-modules-after.txt" \
    || rollback

grep -Fxq 'XCache Cacher' \
    "$BACKUP/diagnostics/live-modules-after.txt" \
    || rollback

echo "XCache OK"

###############################################################################
# VERIFY EXACT APACHE MODULE
###############################################################################

ACTUAL_LIBPHP_SHA="$(
    sha256sum /usr/lib/apache2/modules/libphp5.so \
        | awk '{print $1}'
)"

echo "Expected: $EXPECTED_LIBPHP_SHA"
echo "Actual:   $ACTUAL_LIBPHP_SHA"

[ "$ACTUAL_LIBPHP_SHA" = "$EXPECTED_LIBPHP_SHA" ] \
    || rollback

###############################################################################
# APACHE CONFIG
###############################################################################

section "APACHE CONFIGTEST"

apache2ctl configtest \
    || rollback

###############################################################################
# LOG POSITIONS
###############################################################################

APLOG_START=0
PHPLOG_START=0

if [ -f /var/log/apache2/error.log ]; then
    APLOG_START="$(wc -l < /var/log/apache2/error.log)"
fi

if [ -f /var/log/php5/apache2-error.log ]; then
    PHPLOG_START="$(wc -l < /var/log/php5/apache2-error.log)"
fi

###############################################################################
# ENABLE SERVICE CONTROL AND RESTART
###############################################################################

restore_policy

section "RESTART APACHE"

/etc/init.d/apache2 restart \
    || rollback

sleep 2

###############################################################################
# VERIFY APACHE
###############################################################################

section "VERIFY APACHE"

ps aux | grep '[a]pache2' \
    || rollback

apache2ctl -M \
    > "$BACKUP/diagnostics/apache-modules-after.txt" 2>&1 \
    || rollback

grep -E 'php|mpm' \
    "$BACKUP/diagnostics/apache-modules-after.txt"

grep -q 'mpm_prefork_module' \
    "$BACKUP/diagnostics/apache-modules-after.txt" \
    || rollback

grep -q 'php5_module' \
    "$BACKUP/diagnostics/apache-modules-after.txt" \
    || rollback

###############################################################################
# NEW APACHE LOG MESSAGES
###############################################################################

section "CHECK NEW LOG MESSAGES"

NEW_APLOG="$BACKUP/logs/apache-after-install.log"
NEW_PHPLOG="$BACKUP/logs/php-after-install.log"

if [ -f /var/log/apache2/error.log ]; then
    START=$((APLOG_START + 1))
    tail -n +"$START" /var/log/apache2/error.log \
        > "$NEW_APLOG" 2>/dev/null || true

    cat "$NEW_APLOG"
fi

if [ -f /var/log/php5/apache2-error.log ]; then
    START=$((PHPLOG_START + 1))
    tail -n +"$START" /var/log/php5/apache2-error.log \
        > "$NEW_PHPLOG" 2>/dev/null || true
fi

if grep -Ei \
'undefined symbol|PHP Startup.*Unable to load|cannot open shared object|segmentation fault|segfault' \
"$NEW_APLOG" "$NEW_PHPLOG" 2>/dev/null
then
    echo "Serious startup/runtime error detected."
    rollback
fi

###############################################################################
# FINAL STATE
###############################################################################

section "FINAL STATE"

php -v

echo
php -r '
echo "max_multipart_body_parts=",
     ini_get("max_multipart_body_parts"),
     "\n";
'

echo
echo "XCache:"
php -m | grep -E '^XCache'

echo
echo "Packages:"

for P in \
    libapache2-mod-php5 \
    php5 \
    php5-cli \
    php5-common \
    php5-gd \
    php5-mysql \
    php5-xcache
do
    dpkg-query -W \
        -f='${binary:Package}\t${Version}\t${Status}\n' \
        "$P"
done

echo
echo "libphp5.so:"
sha256sum /usr/lib/apache2/modules/libphp5.so

###############################################################################
# SAVE FINAL DIAGNOSTICS
###############################################################################

php -v \
    > "$BACKUP/diagnostics/php-version-after.txt" 2>&1

php -m \
    > "$BACKUP/diagnostics/php-modules-after.txt" 2>&1

apache2ctl -M \
    > "$BACKUP/diagnostics/apache-modules-after-final.txt" 2>&1

###############################################################################
# ARCHIVE BACKUP
###############################################################################

section "ARCHIVE BACKUP"

tar czpf "$BACKUP.tar.gz" \
    -C /backup \
    "$(basename "$BACKUP")" \
    || echo "WARNING: backup directory exists but tar.gz creation failed"

if [ -f "$BACKUP.tar.gz" ]; then
    sha256sum "$BACKUP.tar.gz" \
        > "$BACKUP.tar.gz.sha256"

    ls -lh "$BACKUP.tar.gz"
    cat "$BACKUP.tar.gz.sha256"
fi

INSTALL_STARTED=0

###############################################################################

section "PHP 5.4 PHP2SHELL UPDATE SUCCESSFUL"

echo
echo "Installed:"
php -v | head -1

echo
echo "Security signal:"
php -r '
$v = ini_get("max_multipart_body_parts");
var_dump($v);
'

echo
echo "Built packages:"
ls -lh "$PKGOUT"

echo
echo "Full backup:"
echo "  $BACKUP"

echo
echo "Archive:"
echo "  $BACKUP.tar.gz"

echo
echo "Build tree:"
echo "  $WORK"

echo
echo "DO NOT DELETE THE BACKUP."
echo

exit 0
