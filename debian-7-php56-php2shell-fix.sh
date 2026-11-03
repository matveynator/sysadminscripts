#!/bin/bash
#
# tiwar.net repair: Debian 7 (wheezy) amd64 + Dotdeb PHP 5.6.40
# Self-contained security rebuild for CVE-2026-109618 / CVE-2026-109619.
#
# Source inputs are taken from our frozen mirror first:
#   https://files.zabiyaka.net/php2shell/
# If the exact PHP 5.6 Dotdeb source package is absent there, the script
# recovers it read-only from the historical Dotdeb source repository and
# verifies every downloaded source payload against the repository Sources
# metadata and the package .dsc. The PHP2Shell patch may be recovered from
# the pinned public patch repository and MUST match the hard-coded SHA256.
#
# The script:
#   - bootstraps gurl automatically;
#   - verifies the local source bundle using SHA256SUMS;
#   - makes rollback .debs (APT cache first, dpkg-repack fallback);
#   - installs build dependencies from Debian archive;
#   - builds 5.6.40 with the frozen security patch;
#   - verifies ABI/extensions before installation;
#   - installs only matching PHP core packages already present;
#   - automatically rolls back on install/runtime failure.
#
# IMPORTANT: automatic patching is intentionally restricted to the exact
# PHP package version 5.6.40-1~dotdeb+7.1. Other PHP 5.6.x versions are NOT upgraded
# automatically by this script.

set -u
set -o pipefail

PHP_UPSTREAM='5.6.40'
OLDVER='5.6.40-1~dotdeb+7.1'
NEWVER="${OLDVER}+php2shell1"
STAMP="$(date +%Y%m%d-%H%M%S)"

SOURCE_BASE='https://files.zabiyaka.net/php2shell'
GURL_URL='http://files.zabiyaka.net/gurl/latest/linux/amd64/gurl'

DOTDEB_REPOS='https://packages.dotdeb.org https://archives.dotdeb.org http://packages.dotdeb.org http://archives.dotdeb.org'
DOTDEB_DIST='wheezy-php56'
DOTDEB_COMPONENT='all'

PATCH_FALLBACK_URL='https://raw.githubusercontent.com/fletto2/php56-php2shell-patches/main/php-5.6.40-php2shell.patch'
PATCH_FALLBACK_SHA256='10a2d6da0364fd94d591b7d6663d1a5243bbdf0d7a8a8b979aed0695173d7bc5'
PATCH_FALLBACK_NAME='php-5.6.40-php2shell.patch'
PHP5640_TARGZ_SHA256='56fb9878d12fdd921f6a0897e919f4e980d930160e154cbde2cc6d9206a27cac'

# Source payload filenames are discovered from the SHA256-verified .dsc.
# Do not hard-code *.orig.tar.gz / *.debian.tar.* names: old Dotdeb bundles
# are sometimes stored under different filenames.
DSC=''
PATCH=''
MANIFEST='SHA256SUMS'


BASE='/root/php56-php2shell'
WORK="$BASE/work-$STAMP"
SRCROOT="$WORK/src"
STAGE="$WORK/stage"
PKGOUT="$BASE/packages/$NEWVER"
BACKUP="/backup/php56-before-php2shell-$STAMP"

APT_LIST="$WORK/wheezy-build.list"
APT_PARTS="$WORK/apt-parts-empty"

HAS_APACHE=0
INSTALL_STARTED=0
POLICY_SAVED=0
HAD_POLICY=0

die() {
    echo
    echo "ERROR: $*"
    echo
    exit 1
}

section() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

fetch() {
    URL="$1"
    OUT="$2"
    N=1

    while [ "$N" -le 8 ]; do
        echo "[$N/8] $URL"
        rm -f "$OUT.tmp"

        if gurl -o "$OUT.tmp" "$URL" </dev/null; then
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

# ---------------------------------------------------------------------------
# Platform
# ---------------------------------------------------------------------------

[ "$(id -u)" = "0" ] || die "run as root"

section "PLATFORM PRECHECK"

echo "Kernel:"
uname -a
echo
echo "Debian:"
cat /etc/debian_version 2>/dev/null || true

[ "$(uname -m)" = "x86_64" ] || die "amd64/x86_64 required"
grep -q '^7\.' /etc/debian_version 2>/dev/null     || die "expected Debian 7.x (wheezy)"

mkdir -p "$WORK" "$SRCROOT" "$STAGE" "$PKGOUT" "$APT_PARTS" /backup

# ---------------------------------------------------------------------------
# Isolated archive APT configuration.
# Does not overwrite /etc/apt/sources.list.
# ---------------------------------------------------------------------------

cat > "$APT_LIST" <<'EOF'
deb http://archive.debian.org/debian wheezy main contrib non-free
deb http://archive.debian.org/debian-security wheezy/updates main contrib non-free
EOF

APT_OPTS=(
    -o "Dir::Etc::sourcelist=$APT_LIST"
    -o "Dir::Etc::sourceparts=$APT_PARTS"
    -o "APT::Get::List-Cleanup=0"
    -o "Acquire::Check-Valid-Until=false"
    -o "Acquire::ForceIPv4=true"
)

apt_update() {
    apt-get "${APT_OPTS[@]}" update
}

apt_simulate() {
    apt-get "${APT_OPTS[@]}" -s install "$@"
}

apt_install() {
    apt-get "${APT_OPTS[@]}"         --allow-unauthenticated         --no-remove         -y install "$@"
}

# ---------------------------------------------------------------------------
# Bootstrap gurl over plain HTTP, because old TLS stacks are unreliable.
# ---------------------------------------------------------------------------

section "GURL"

if ! command -v gurl >/dev/null 2>&1; then
    echo "Installing gurl from:"
    echo "  $GURL_URL"

    if command -v curl >/dev/null 2>&1; then
        curl -fL "$GURL_URL" > /usr/local/bin/gurl             || die "could not download gurl using curl"
    elif command -v wget >/dev/null 2>&1; then
        wget -O /usr/local/bin/gurl "$GURL_URL"             || die "could not download gurl using wget"
    else
        echo "curl/wget missing; bootstrapping curl from Debian archive"
        apt_update || die "APT update failed while bootstrapping curl"
        apt_install curl || die "could not install curl"
        curl -fL "$GURL_URL" > /usr/local/bin/gurl             || die "could not download gurl"
    fi

    chmod 755 /usr/local/bin/gurl
fi

command -v gurl >/dev/null 2>&1 || die "gurl unavailable"
gurl --version 2>/dev/null || gurl -V 2>/dev/null || true

# ---------------------------------------------------------------------------
# Exact current PHP / ABI
# ---------------------------------------------------------------------------

section "CURRENT PHP"

PKGVER="$(dpkg-query -W -f='${Version}' php5-cli 2>/dev/null || true)"
echo "php5-cli package: $PKGVER"

if [ "$PKGVER" = "$NEWVER" ]; then
    echo "Already patched."
    /usr/bin/php5 -v 2>/dev/null | head -1 || true
    exit 0
fi

case "$PKGVER" in
    5.6.*) ;;
    *) die "PHP 5.6 expected; found $PKGVER" ;;
esac

[ "$PKGVER" = "$OLDVER" ] || {
    echo "Found PHP package version: $PKGVER"
    echo "This script intentionally does not migrate another PHP 5.6.x release."
    die "supported base is exactly $OLDVER"
}

[ -x /usr/bin/php5 ] || die "/usr/bin/php5 missing"

/usr/bin/php5 -v

echo
/usr/bin/php5 -n -i | grep -E '^(PHP API|PHP Extension|Zend Extension|Zend Extension Build|PHP Extension Build|Thread Safety)'

/usr/bin/php5 -n -i | grep -q '^PHP API => 20131106$'     || die "unexpected PHP API"
/usr/bin/php5 -n -i | grep -q '^PHP Extension => 20131226$'     || die "unexpected extension ABI"
/usr/bin/php5 -n -i | grep -q '^Zend Extension => 220131226$'     || die "unexpected Zend ABI"
/usr/bin/php5 -n -i | grep -q '^PHP Extension Build => API20131226,NTS$'     || die "expected PHP 5.6 NTS ABI"
/usr/bin/php5 -n -i | grep -q '^Zend Extension Build => API220131226,NTS$'     || die "expected PHP 5.6 Zend NTS ABI"

if dpkg-query -W -f='${Status}' libapache2-mod-php5 2>/dev/null     | grep -q 'install ok installed'
then
    HAS_APACHE=1
    command -v apache2ctl >/dev/null 2>&1 || die "apache2ctl missing"
    apache2ctl -V 2>&1 | grep -qi 'Server MPM:.*Prefork'         || die "Apache mod_php requires Prefork here"
    apache2ctl -M 2>&1 | grep -q 'php5_module'         || die "php5_module is not loaded"
fi

HAS_FPM=0
if dpkg-query -W -f='${Status}' php5-fpm 2>/dev/null | grep -q 'install ok installed'
then
    HAS_FPM=1
    [ -x /etc/init.d/php5-fpm ] || die "php5-fpm init script missing"
    if [ -x /usr/sbin/php5-fpm ]; then
        /usr/sbin/php5-fpm -t || die "php5-fpm config invalid before build"
    fi
fi

# ---------------------------------------------------------------------------
# Dpkg consistency
# ---------------------------------------------------------------------------

section "DPKG AUDIT"

AUDIT="$(dpkg --audit 2>&1 || true)"
[ -z "$AUDIT" ] || {
    echo "$AUDIT"
    die "dpkg database is not clean"
}
echo "OK"

# ---------------------------------------------------------------------------
# Discover matching core packages. Third-party PHP extensions are not rebuilt.
# ---------------------------------------------------------------------------

CORE_CANDIDATES='
libapache2-mod-php5
libphp5-embed
php5
php5-cgi
php5-cli
php5-common
php5-curl
php5-dbg
php5-dev
php5-enchant
php5-fpm
php5-gd
php5-imap
php5-interbase
php5-intl
php5-ldap
php5-mcrypt
php5-mysql
php5-odbc
php5-pgsql
php5-pspell
php5-readline
php5-recode
php5-snmp
php5-sqlite
php5-sybase
php5-tidy
php5-xmlrpc
php5-xsl
php-pear
'

INSTALLED_CORE=()

for P in $CORE_CANDIDATES; do
    STATUS="$(dpkg-query -W -f='${Status}' "$P" 2>/dev/null || true)"
    [ "$STATUS" = 'install ok installed' ] || continue

    V="$(dpkg-query -W -f='${Version}' "$P" 2>/dev/null || true)"
    if [ "$V" = "$OLDVER" ]; then
        INSTALLED_CORE+=("$P")
    fi
done

[ "${#INSTALLED_CORE[@]}" -gt 0 ] || die "no matching PHP core packages found"

echo "Core packages:"
printf '  %s\n' "${INSTALLED_CORE[@]}"

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

section "BACKUP"

mkdir -p     "$BACKUP/configs"     "$BACKUP/runtime/usr/lib/apache2/modules"     "$BACKUP/runtime/usr/lib"     "$BACKUP/runtime/usr/bin"     "$BACKUP/rollback"     "$BACKUP/diagnostics"     "$BACKUP/logs"     "$BACKUP/source"

dpkg --get-selections > "$BACKUP/diagnostics/dpkg-selections.txt"
dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n'     > "$BACKUP/diagnostics/packages.txt"

cp -a /etc/php5 "$BACKUP/configs/" 2>/dev/null || true
cp -a /etc/apache2 "$BACKUP/configs/" 2>/dev/null || true
cp -a /usr/lib/php5 "$BACKUP/runtime/usr/lib/" 2>/dev/null || true

if [ -f /usr/lib/apache2/modules/libphp5.so ]; then
    cp -a /usr/lib/apache2/modules/libphp5.so         "$BACKUP/runtime/usr/lib/apache2/modules/"
    sha256sum /usr/lib/apache2/modules/libphp5.so         > "$BACKUP/diagnostics/libphp5-before.sha256"
fi

for F in /usr/bin/php /usr/bin/php5 /usr/bin/php-config /usr/bin/php-config5          /usr/bin/phpize /usr/bin/phpize5
do
    if [ -e "$F" ] || [ -L "$F" ]; then
        cp -a "$F" "$BACKUP/runtime/usr/bin/" 2>/dev/null || true
    fi
done

/usr/bin/php5 -m > "$BACKUP/diagnostics/php-modules-before.txt" 2>&1
/usr/bin/php5 -i > "$BACKUP/diagnostics/php-info-before.txt" 2>&1

if [ "$HAS_APACHE" = "1" ]; then
    apache2ctl -V > "$BACKUP/diagnostics/apache-version.txt" 2>&1
    apache2ctl -M > "$BACKUP/diagnostics/apache-modules-before.txt" 2>&1
    apache2ctl -S > "$BACKUP/diagnostics/apache-vhosts-before.txt" 2>&1 || true
fi

if [ "$HAS_FPM" = "1" ] && [ -x /usr/sbin/php5-fpm ]; then
    /usr/sbin/php5-fpm -tt > "$BACKUP/diagnostics/php5-fpm-before.txt" 2>&1 || true
fi

# ---------------------------------------------------------------------------
# Install build/repack tooling first. This does not change PHP.
# ---------------------------------------------------------------------------

section "APT BUILD TOOLS"

apt_update 2>&1 | tee "$BACKUP/logs/apt-update.log"     || die "APT update failed"

BASIC=(build-essential dpkg-dev debhelper quilt fakeroot python dpkg-repack)

apt_simulate "${BASIC[@]}" > "$BACKUP/logs/apt-basic-simulate.log" 2>&1     || {
        cat "$BACKUP/logs/apt-basic-simulate.log"
        die "cannot resolve basic tools"
    }

if grep -q '^Remv ' "$BACKUP/logs/apt-basic-simulate.log"; then
    cat "$BACKUP/logs/apt-basic-simulate.log"
    die "APT wants to remove packages"
fi

apt_install "${BASIC[@]}" 2>&1 | tee "$BACKUP/logs/apt-basic-install.log"     || die "build/repack tool installation failed"

command -v dpkg-source >/dev/null 2>&1 || die "dpkg-source missing"
command -v dpkg-buildpackage >/dev/null 2>&1 || die "dpkg-buildpackage missing"
command -v dpkg-repack >/dev/null 2>&1 || die "dpkg-repack missing"

# ---------------------------------------------------------------------------
# Exact rollback .debs: cache first, otherwise repack currently installed pkg.
# ---------------------------------------------------------------------------

section "CREATE ROLLBACK PACKAGES"

ROLLBACK_DEBS=()

for P in "${INSTALLED_CORE[@]}"; do
    A="$(dpkg-query -W -f='${Architecture}' "$P")"
    FILE="${P}_${OLDVER}_${A}.deb"
    DEST="$BACKUP/rollback/$FILE"

    if [ -f "/var/cache/apt/archives/$FILE" ]; then
        echo "APT cache: $FILE"
        cp -a "/var/cache/apt/archives/$FILE" "$DEST"
    else
        echo "Repacking installed $P ..."
        mkdir -p "$WORK/repack"
        (
            cd "$WORK/repack" || exit 1
            rm -f ./*.deb
            dpkg-repack "$P"
        ) || die "dpkg-repack failed for $P"

        RF="$(find "$WORK/repack" -maxdepth 1 -type f -name '*.deb' | head -1)"
        [ -n "$RF" ] || die "repacked .deb missing for $P"

        # dpkg-repack may encode version characters in filename; validate metadata,
        # then normalize the destination filename ourselves.
        RP="$(dpkg-deb -f "$RF" Package)"
        RV="$(dpkg-deb -f "$RF" Version)"
        RA="$(dpkg-deb -f "$RF" Architecture)"

        [ "$RP" = "$P" ] || die "repacked package mismatch for $P"
        [ "$RV" = "$OLDVER" ] || die "repacked version mismatch for $P"
        [ "$RA" = "$A" ] || die "repacked architecture mismatch for $P"

        cp -a "$RF" "$DEST"
    fi

    RP="$(dpkg-deb -f "$DEST" Package)"
    RV="$(dpkg-deb -f "$DEST" Version)"
    RA="$(dpkg-deb -f "$DEST" Architecture)"

    [ "$RP" = "$P" ] || die "rollback package mismatch: $DEST"
    [ "$RV" = "$OLDVER" ] || die "rollback version mismatch: $DEST"
    [ "$RA" = "$A" ] || die "rollback arch mismatch: $DEST"

    ROLLBACK_DEBS+=("$DEST")
    echo "OK $FILE"
done

# ---------------------------------------------------------------------------
# Repair stale /usr/bin/php style alternatives, if this old host has them.
# ---------------------------------------------------------------------------

section "PHP ALTERNATIVES"

for SPEC in 'php:/usr/bin/php5' 'php-config:/usr/bin/php-config5' 'phpize:/usr/bin/phpize5'
do
    NAME="${SPEC%%:*}"
    TARGET="${SPEC#*:}"
    LINK="/usr/bin/$NAME"

    [ -e "$TARGET" ] || continue

    if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
        echo "Preserving standalone stale $LINK"
        mv "$LINK" "$LINK.before-php2shell-$STAMP"

        if update-alternatives --query "$NAME" >/dev/null 2>&1; then
            update-alternatives --set "$NAME" "$TARGET" || true
        else
            update-alternatives --install "$LINK" "$NAME" "$TARGET" 50
        fi
    fi
done

# ---------------------------------------------------------------------------
# Source acquisition.
# ---------------------------------------------------------------------------

section "DOWNLOAD LOCAL SOURCE BUNDLE"
cd "$SRCROOT" || die "cannot enter source directory"

fetch "$SOURCE_BASE/$MANIFEST" "$SRCROOT/$MANIFEST" || die "cannot download $MANIFEST"
BUNDLE_LIST="$WORK/bundle-files.txt"
awk 'NF >= 2 { name=$2; sub(/^\*/, "", name); if (name != "" && name !~ /^#/) print name }' \
    "$SRCROOT/$MANIFEST" > "$BUNDLE_LIST"
[ -s "$BUNDLE_LIST" ] || die "$MANIFEST contains no files"

echo "Frozen source-kit files:"
cat "$BUNDLE_LIST"

while IFS= read -r FILE; do
    case "$FILE" in */*|..*) die "unsafe filename in $MANIFEST: $FILE" ;; esac
    fetch "$SOURCE_BASE/$FILE" "$SRCROOT/$FILE" || die "cannot download $FILE"
done < "$BUNDLE_LIST"

section "VERIFY SHA256 BUNDLE"
( cd "$SRCROOT" && sha256sum -c "$MANIFEST" ) || die "SHA256 verification failed"

find_matching_dsc() {
    DSC=''
    DSC_COUNT=0
    for FILE in "$SRCROOT"/*.dsc; do
        [ -f "$FILE" ] || continue
        SRCNAME="$(sed -n 's/^Source:[[:space:]]*//p' "$FILE" | head -1)"
        SRCVER="$(sed -n 's/^Version:[[:space:]]*//p' "$FILE" | head -1)"
        if [ "$SRCNAME" = 'php5' ] && [ "$SRCVER" = "$OLDVER" ]; then
            DSC="$(basename "$FILE")"
            DSC_COUNT=$((DSC_COUNT + 1))
        fi
    done
    [ "$DSC_COUNT" -eq 1 ]
}

parse_dotdeb_sources() {
    INDEX_GZ="$1"
    OUT="$2"
    python - "$INDEX_GZ" "$OLDVER" > "$OUT" <<'PY_DOTDEB'
import gzip, sys
path, wanted = sys.argv[1:3]
raw = gzip.open(path, 'rb').read()
try:
    text = raw.decode('utf-8')
except AttributeError:
    text = raw
except UnicodeDecodeError:
    text = raw.decode('latin1')

matches=[]
for para in text.split('\n\n'):
    fields={}; current=None
    for line in para.splitlines():
        if line.startswith(' ') or line.startswith('\t'):
            if current: fields[current] += '\n' + line.strip()
            continue
        if ':' in line:
            k,v=line.split(':',1); current=k.strip(); fields[current]=v.strip()
    if fields.get('Package') == 'php5' and fields.get('Version') == wanted:
        matches.append(fields)
if len(matches) != 1:
    sys.stderr.write('Sources index matching php5 %s entries: %d\n' % (wanted, len(matches)))
    sys.exit(2)
f=matches[0]
directory=f.get('Directory','').strip()
if not directory: sys.exit(3)
rows=[]
checks=f.get('Checksums-Sha256','')
if checks:
    for line in checks.splitlines():
        p=line.split()
        if len(p)>=3: rows.append(('sha256',p[0],p[1],p[2]))
else:
    for line in f.get('Files','').splitlines():
        p=line.split()
        if len(p)>=3: rows.append(('md5',p[0],p[1],p[2]))
if not rows: sys.exit(4)
for algo,digest,size,name in rows:
    sys.stdout.write('%s\t%s\t%s\t%s\t%s\n' % (directory,algo,digest,size,name))
PY_DOTDEB
}

verify_file_digest() {
    ALGO="$1"; EXPECTED="$2"; FILE="$3"
    case "$ALGO" in
        sha256) GOT="$(sha256sum "$FILE" | awk '{print $1}')" ;;
        md5) GOT="$(md5sum "$FILE" | awk '{print $1}')" ;;
        *) return 2 ;;
    esac
    [ "$GOT" = "$EXPECTED" ]
}

recover_dotdeb_source() {
    section "RECOVER EXACT DOTDEB PHP 5.6 SOURCE"
    RECOVERED=0
    DOTDEB_META="$WORK/dotdeb-source-files.tsv"
    DOTDEB_INDEX="$WORK/dotdeb-Sources.gz"
    for REPO in $DOTDEB_REPOS; do
        echo "Trying Dotdeb source repository: $REPO"
        rm -f "$DOTDEB_INDEX" "$DOTDEB_META"
        INDEX_URL="$REPO/dists/$DOTDEB_DIST/$DOTDEB_COMPONENT/source/Sources.gz"
        fetch "$INDEX_URL" "$DOTDEB_INDEX" || { echo "No source index here."; continue; }
        parse_dotdeb_sources "$DOTDEB_INDEX" "$DOTDEB_META" || { echo "Exact $OLDVER not present here."; continue; }
        echo "Exact Dotdeb source entry found:"
        awk -F '\t' '{printf "  %s  (%s bytes, %s %s)\n", $5, $4, $2, $3}' "$DOTDEB_META"
        OK=1
        while IFS="$(printf '\t')" read -r DIRECTORY ALGO DIGEST SIZE NAME; do
            [ -n "$NAME" ] || continue
            case "$NAME" in */*|..*) OK=0; break ;; esac
            TARGET="$SRCROOT/$NAME"
            URL="$REPO/$DIRECTORY/$NAME"
            if [ -s "$TARGET" ] && verify_file_digest "$ALGO" "$DIGEST" "$TARGET"; then
                echo "Already verified: $NAME"
            else
                rm -f "$TARGET"
                fetch "$URL" "$TARGET" || { OK=0; break; }
                ACTUAL_SIZE="$(wc -c < "$TARGET" | tr -d ' ')"
                [ "$ACTUAL_SIZE" = "$SIZE" ] || { echo "Size mismatch: $NAME"; OK=0; break; }
                verify_file_digest "$ALGO" "$DIGEST" "$TARGET" || { echo "Checksum mismatch: $NAME"; OK=0; break; }
                echo "Recovered and verified: $NAME"
            fi
            grep -Fxq "$NAME" "$BUNDLE_LIST" || echo "$NAME" >> "$BUNDLE_LIST"
        done < "$DOTDEB_META"
        if [ "$OK" = 1 ] && find_matching_dsc; then RECOVERED=1; break; fi
    done
    [ "$RECOVERED" = 1 ]
}

if ! find_matching_dsc; then
    echo "Matching php5 $OLDVER source descriptors on local mirror: $DSC_COUNT"
    recover_dotdeb_source || die "could not recover exact Dotdeb source package $OLDVER"
fi

echo "Source descriptor: $DSC"
DSC_FILES="$WORK/dsc-source-files.tsv"
python - "$SRCROOT/$DSC" > "$DSC_FILES" <<'PY_DSC'
import sys
lines=open(sys.argv[1]).read().splitlines()
def rows(field):
    out=[]; active=False
    for line in lines:
        if line.startswith(field+':'): active=True; continue
        if not active: continue
        if line.startswith(' ') or line.startswith('\t'):
            p=line.split()
            if len(p)>=3: out.append(p[:3])
            continue
        break
    return out
md5=dict((n,(d,s)) for d,s,n in rows('Files'))
sha=dict((n,(d,s)) for d,s,n in rows('Checksums-Sha256'))
names=[]
for n in list(md5.keys())+list(sha.keys()):
    if n not in names: names.append(n)
for n in names:
    if n in sha: d,s=sha[n]; a='sha256'
    else: d,s=md5[n]; a='md5'
    sys.stdout.write('%s\t%s\t%s\t%s\t%s\n' % (a,d,s,n,md5.get(n,('',''))[0]))
PY_DSC
[ -s "$DSC_FILES" ] || die "$DSC contains no source payload checksums"

echo "Source payloads required by $DSC:"
awk -F '\t' '{ printf "  %s  (%s bytes, %s %s)\n", $4, $3, $1, $2 }' "$DSC_FILES"

while IFS="$(printf '\t')" read -r ALGO DIGEST SIZE NAME MD5; do
    [ -n "$NAME" ] || continue
    TARGET="$SRCROOT/$NAME"
    [ -s "$TARGET" ] || die "source payload missing: $NAME"
    ACTUAL_SIZE="$(wc -c < "$TARGET" | tr -d ' ')"
    [ "$ACTUAL_SIZE" = "$SIZE" ] || die "source payload size mismatch: $NAME"
    verify_file_digest "$ALGO" "$DIGEST" "$TARGET" || die "$ALGO mismatch for $NAME"
    if [ -n "$MD5" ]; then [ "$(md5sum "$TARGET" | awk '{print $1}')" = "$MD5" ] || die "MD5 mismatch for $NAME"; fi
    case "$NAME" in
        *5.6.40*.orig.tar.gz)
            GOT_OFFICIAL="$(sha256sum "$TARGET" | awk '{print $1}')"
            [ "$GOT_OFFICIAL" = "$PHP5640_TARGZ_SHA256" ] && echo "Official php.net SHA256 also matches: $NAME" || true
            ;;
    esac
done < "$DSC_FILES"

PATCH=''; PATCH_COUNT=0
for FILE in "$SRCROOT"/*.patch; do
    [ -f "$FILE" ] || continue
    case "$(basename "$FILE")" in *5.4.45*) continue ;; esac
    if grep -q 'max_multipart_body_parts' "$FILE" 2>/dev/null && grep -q 'zend_mm_safe_error_ex' "$FILE" 2>/dev/null; then
        PATCH="$(basename "$FILE")"; PATCH_COUNT=$((PATCH_COUNT + 1))
    fi
done

if [ "$PATCH_COUNT" -eq 0 ]; then
    section "RECOVER PINNED PHP 5.6 SECURITY PATCH"
    TARGET="$SRCROOT/$PATCH_FALLBACK_NAME"
    fetch "$PATCH_FALLBACK_URL" "$TARGET" || die "cannot download pinned PHP 5.6 security patch"
    GOT="$(sha256sum "$TARGET" | awk '{print $1}')"
    [ "$GOT" = "$PATCH_FALLBACK_SHA256" ] || die "pinned security patch SHA256 mismatch (got $GOT)"
    PATCH="$PATCH_FALLBACK_NAME"; PATCH_COUNT=1
    echo "Pinned patch SHA256 OK: $GOT"
elif [ "$PATCH_COUNT" -gt 1 ]; then
    die "ambiguous PHP 5.6 security patch set"
fi

echo "Security patch: $PATCH"
grep -q '^Source: php5$' "$SRCROOT/$DSC" || die "unexpected .dsc"
grep -Fq "Version: $OLDVER" "$SRCROOT/$DSC" || die "wrong .dsc version"
cp -a "$SRCROOT/$MANIFEST" "$SRCROOT/$DSC" "$SRCROOT/$PATCH" "$BACKUP/source/"

# ---------------------------------------------------------------------------
# Extract exact Dotdeb source.
# ---------------------------------------------------------------------------

section "EXTRACT SOURCE"

dpkg-source -x "$SRCROOT/$DSC"     2>&1 | tee "$BACKUP/logs/dpkg-source.log"     || die "dpkg-source failed"

SRCDIR=''
while IFS= read -r D
do
    [ -f "$D/debian/control" ] || continue
    if grep -q '^Source:[[:space:]]*php5$' "$D/debian/control"; then
        SRCDIR="$D"
        break
    fi
done < <(find "$SRCROOT" -mindepth 1 -maxdepth 1 -type d -print)

[ -n "$SRCDIR" ] || die "extracted php5 source directory not found"
echo "Extracted source: $SRCDIR"

cd "$SRCDIR" || die

# ---------------------------------------------------------------------------
# Avoid pulling a local MySQL server just to run package tests.
# Build uses nocheck.
# ---------------------------------------------------------------------------

section "NORMALIZE BUILD DEPENDENCIES"

python <<'PY'
import re

path = 'debian/control'
lines = open(path).read().splitlines(True)
out = []
i = 0

while i < len(lines):
    line = lines[i]

    if line.startswith('Build-Depends:') or line.startswith('Build-Depends-Indep:'):
        key, first = line.split(':', 1)
        value = first.strip()
        i += 1

        while i < len(lines) and (lines[i].startswith(' ') or lines[i].startswith('\t')):
            value += ' ' + lines[i].strip()
            i += 1

        kept = []
        for clause in value.split(','):
            names = []
            for alt in clause.split('|'):
                name = re.sub(r'\([^)]*\)', '', alt)
                name = re.sub(r'\[[^\]]*\]', '', name).strip()
                name = name.split(':', 1)[0].strip()
                names.append(name)

            if 'mysql-server' in names or 'virtual-mysql-server' in names:
                continue

            if clause.strip():
                kept.append(clause.strip())

        out.append('%s: %s\n' % (key, ', '.join(kept)))
        continue

    out.append(line)
    i += 1

open(path, 'w').writelines(out)
PY

grep -n 'mysql-server\|virtual-mysql-server' debian/control     && die "mysql-server build dependency remains"     || true

# ---------------------------------------------------------------------------
# Wheezy LTS Apache development headers.
#
# This host runs apache2.2-common 2.2.22-13+deb7u13.  The normal Wheezy
# archive index may only advertise apache2-prefork-dev +deb7u6, which would
# require downgrading the live Apache stack.  Never do that.  Instead, for
# this exact production version, fetch Debian's matching +deb7u13 dev package,
# verify the published SHA256, expose it through a tiny local APT repository,
# and let the normal no-removal dependency resolver install it.
# ---------------------------------------------------------------------------

if [ "$HAS_APACHE" = "1" ]; then
    APACHE_COMMON_VER="$(dpkg-query -W -f='${Version}' apache2.2-common 2>/dev/null || true)"
    APACHE_DEV_VER="$(dpkg-query -W -f='${Version}' apache2-prefork-dev 2>/dev/null || true)"

    echo "Apache common package:      $APACHE_COMMON_VER"
    echo "Apache prefork dev package: ${APACHE_DEV_VER:-not installed}"

    if [ "$APACHE_DEV_VER" != "$APACHE_COMMON_VER" ]; then
        case "$APACHE_COMMON_VER" in
            '2.2.22-13+deb7u13')
                section "RECOVER MATCHING APACHE PREFORK DEV"

                APDEV_FILE='apache2-prefork-dev_2.2.22-13+deb7u13_amd64.deb'
                APDEV_SHA256='04bbc741ca32c7b11e6a0adcab5b93e110b7c2af129958fe52ab6607498a5c9c'
                APDEV_REPO="$WORK/apache-dev-repo"
                APDEV_DEB="$APDEV_REPO/$APDEV_FILE"
                mkdir -p "$APDEV_REPO"

                APDEV_OK=0
                for APDEV_URL in \
                    "http://archive.debian.org/debian-security/pool/updates/main/a/apache2/$APDEV_FILE" \
                    "https://mirrors.capitalonline.net/debian-archive/debian-security/pool/updates/main/a/apache2/$APDEV_FILE"
                do
                    echo "Trying matching Apache dev package..."
                    if fetch "$APDEV_URL" "$APDEV_DEB"; then
                        GOT="$(sha256sum "$APDEV_DEB" | awk '{print $1}')"
                        if [ "$GOT" = "$APDEV_SHA256" ]; then
                            APDEV_OK=1
                            break
                        fi
                        echo "Checksum mismatch from this source: $GOT"
                        rm -f "$APDEV_DEB"
                    fi
                done

                [ "$APDEV_OK" = "1" ] || die "cannot recover verified apache2-prefork-dev $APACHE_COMMON_VER"

                [ "$(dpkg-deb -f "$APDEV_DEB" Package)" = 'apache2-prefork-dev' ] \
                    || die "wrong Apache development package"
                [ "$(dpkg-deb -f "$APDEV_DEB" Version)" = "$APACHE_COMMON_VER" ] \
                    || die "Apache development package version mismatch"
                [ "$(dpkg-deb -f "$APDEV_DEB" Architecture)" = 'amd64' ] \
                    || die "Apache development package architecture mismatch"

                echo "Verified $APDEV_FILE"
                echo "SHA256: $APDEV_SHA256"

                (
                    cd "$APDEV_REPO" || exit 1
                    dpkg-scanpackages . /dev/null > Packages
                    gzip -9c Packages > Packages.gz
                ) || die "cannot create local Apache dev APT repository"

                # Flat file repository.  APT still uses the frozen Wheezy archives
                # for its dependencies, but gets the exact matching dev package here.
                grep -Fq "deb file:$APDEV_REPO ./" "$APT_LIST" \
                    || echo "deb file:$APDEV_REPO ./" >> "$APT_LIST"

                apt_update 2>&1 | tee "$BACKUP/logs/apt-update-apache-dev.log" \
                    || die "APT update failed after adding matching Apache dev package"

                CANDIDATE="$(apt-cache "${APT_OPTS[@]}" policy apache2-prefork-dev 2>/dev/null \
                    | sed -n 's/^[[:space:]]*Candidate:[[:space:]]*//p' | head -1)"
                echo "apache2-prefork-dev APT candidate: $CANDIDATE"
                [ "$CANDIDATE" = "$APACHE_COMMON_VER" ] \
                    || die "APT did not select matching apache2-prefork-dev $APACHE_COMMON_VER"

                # apache2-prefork-dev and apache2-threaded-dev are mutually
                # exclusive development-header packages on Wheezy.  Replacing
                # threaded-dev with prefork-dev is acceptable on this host because
                # the live server MPM was verified above to be Prefork.  Runtime
                # Apache packages must not be removed, upgraded or downgraded.
                APACHE_RUNTIME_SNAPSHOT="$WORK/apache-runtime-before.tsv"
                : > "$APACHE_RUNTIME_SNAPSHOT"
                for AP in apache2 apache2.2-common apache2.2-bin apache2-mpm-prefork; do
                    AV="$(dpkg-query -W -f='${Version}' "$AP" 2>/dev/null || true)"
                    AS="$(dpkg-query -W -f='${Status}' "$AP" 2>/dev/null || true)"
                    if [ "$AS" = 'install ok installed' ]; then
                        printf '%s\t%s\n' "$AP" "$AV" >> "$APACHE_RUNTIME_SNAPSHOT"
                    fi
                done

                APDEV_SIM="$BACKUP/logs/apt-apache-prefork-dev-simulate.log"
                apt-get "${APT_OPTS[@]}" -s install apache2-prefork-dev \
                    > "$APDEV_SIM" 2>&1 || {
                        cat "$APDEV_SIM"
                        die "cannot simulate matching apache2-prefork-dev installation"
                    }

                APDEV_BAD=0
                while IFS= read -r LINE; do
                    case "$LINE" in
                        Remv\ apache2-threaded-dev*|Remv\ apache2-threaded-dev:amd64*)
                            echo "Allowed dev-package replacement: $LINE"
                            ;;
                        Remv\ *)
                            echo "Unsafe removal requested: $LINE"
                            APDEV_BAD=1
                            ;;
                        Inst\ apache2\ *|Inst\ apache2.2-common\ *|Inst\ apache2.2-bin\ *|Inst\ apache2-mpm-prefork\ *)
                            echo "Unsafe live Apache package change requested: $LINE"
                            APDEV_BAD=1
                            ;;
                    esac
                done < "$APDEV_SIM"

                [ "$APDEV_BAD" = "0" ] || {
                    cat "$APDEV_SIM"
                    die "matching apache2-prefork-dev would alter live Apache packages"
                }

                echo "Installing exact matching Apache prefork development headers..."
                apt-get "${APT_OPTS[@]}" --allow-unauthenticated -y install apache2-prefork-dev \
                    2>&1 | tee "$BACKUP/logs/apt-apache-prefork-dev-install.log"
                APDEV_RC=${PIPESTATUS[0]}
                [ "$APDEV_RC" = "0" ] || die "apache2-prefork-dev installation failed"

                APACHE_DEV_VER="$(dpkg-query -W -f='${Version}' apache2-prefork-dev 2>/dev/null || true)"
                [ "$APACHE_DEV_VER" = "$APACHE_COMMON_VER" ] \
                    || die "wrong apache2-prefork-dev version installed: $APACHE_DEV_VER"

                while IFS="$(printf '\t')" read -r AP BEFORE_VER; do
                    [ -n "$AP" ] || continue
                    AFTER_STATUS="$(dpkg-query -W -f='${Status}' "$AP" 2>/dev/null || true)"
                    AFTER_VER="$(dpkg-query -W -f='${Version}' "$AP" 2>/dev/null || true)"
                    [ "$AFTER_STATUS" = 'install ok installed' ] \
                        || die "live Apache package disappeared while installing headers: $AP"
                    [ "$AFTER_VER" = "$BEFORE_VER" ] \
                        || die "live Apache package version changed: $AP $BEFORE_VER -> $AFTER_VER"
                done < "$APACHE_RUNTIME_SNAPSHOT"

                AUDIT_NOW="$(dpkg --audit 2>&1 || true)"
                [ -z "$AUDIT_NOW" ] || {
                    echo "$AUDIT_NOW"
                    die "dpkg database became inconsistent after Apache header installation"
                }

                echo "apache2-prefork-dev installed safely: $APACHE_DEV_VER"
                ;;
            *)
                die "unsupported live Apache version $APACHE_COMMON_VER; refusing downgrade or guessed headers"
                ;;
        esac
    fi
fi

# ---------------------------------------------------------------------------
# Resolve Debian build dependencies.
# ---------------------------------------------------------------------------

export APT_LIST APT_PARTS

python <<'PY' > "$WORK/build-deps.txt"
import os
import re
import subprocess
import sys

APT_COMMON = [
    '-o', 'Dir::Etc::sourcelist=' + os.environ['APT_LIST'],
    '-o', 'Dir::Etc::sourceparts=' + os.environ['APT_PARTS'],
    '-o', 'APT::Get::List-Cleanup=0',
    '-o', 'Acquire::Check-Valid-Until=false',
    '-o', 'Acquire::ForceIPv4=true',
]

APT_CACHE = ['apt-cache'] + APT_COMMON
APT_GET = ['apt-get'] + APT_COMMON

text = open('debian/control').read()
source = text.split('\n\n', 1)[0]

fields = {}
current = None

for line in source.splitlines():
    if line.startswith(' ') or line.startswith('\t'):
        if current:
            fields[current] += ' ' + line.strip()
        continue

    if ':' in line:
        key, value = line.split(':', 1)
        current = key.strip()
        fields[current] = value.strip()

relations = []
for key in ('Build-Depends', 'Build-Depends-Indep'):
    if fields.get(key):
        relations.extend(fields[key].split(','))


def relation_satisfied(relation):
    """Ask dpkg itself whether the complete dependency relation is satisfied.

    This is important for alternatives such as "libdb-dev | libdb4.8-dev":
    if the host already has a valid second alternative installed, do not ask
    APT to install the first one and accidentally remove the working package.
    """
    p = subprocess.Popen(
        ['dpkg-checkbuilddeps', '-d', relation],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    out, err = p.communicate()
    return p.returncode == 0


def available(pkg):
    p = subprocess.Popen(
        APT_CACHE + ['show', pkg],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    out, err = p.communicate()
    return re.search(r'(?m)^Package:\s*' + re.escape(pkg) + r'\s*$', out) is not None


def providers(pkg):
    p = subprocess.Popen(
        APT_CACHE + ['showpkg', pkg],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    out, err = p.communicate()

    result = []
    in_reverse_provides = False

    for line in out.splitlines():
        if line.strip() == 'Reverse Provides:':
            in_reverse_provides = True
            continue

        if not in_reverse_provides:
            continue
        if not line.strip():
            continue
        if line.endswith(':') and not line.startswith(' '):
            break

        name = line.strip().split()[0]
        if name and name not in result and available(name):
            result.append(name)

    return result


def safe_to_install(pkg):
    """Accept a build dependency only if apt can add it without removals."""
    p = subprocess.Popen(
        APT_GET + ['-s', '--no-remove', 'install', pkg],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT
    )
    out, err = p.communicate()

    if p.returncode != 0:
        sys.stderr.write('APT simulation rejected %s (rc=%d):\n%s\n' %
                         (pkg, p.returncode, out[-4000:]))
        return False
    if re.search(r'(?m)^Remv\s+', out):
        sys.stderr.write('APT simulation wants removals for %s:\n' % pkg)
        for line in out.splitlines():
            if line.startswith('Remv '):
                sys.stderr.write('  %s\n' % line)
        return False
    return True


def normalized_pkg(alt):
    alt = re.sub(r'\([^)]*\)', '', alt)
    alt = re.sub(r'\[[^\]]*\]', '', alt).strip()
    if not alt:
        return None
    return alt.split(':', 1)[0].strip()


chosen = []

for relation in relations:
    relation = relation.strip()
    if not relation:
        continue

    # Most build dependencies are already present on this production host.
    # Never replace a currently valid alternative just because another
    # alternative happens to appear first in debian/control.
    if relation_satisfied(relation):
        sys.stderr.write('Already satisfied: %s\n' % relation)
        continue

    selected = None
    rejected = []

    for alt in relation.split('|'):
        pkg = normalized_pkg(alt)
        if not pkg:
            continue

        candidates = []
        if available(pkg):
            candidates.append(pkg)
        else:
            candidates.extend(providers(pkg))

        for candidate in candidates:
            if safe_to_install(candidate):
                selected = candidate
                if candidate != pkg:
                    sys.stderr.write(
                        'Virtual build dependency %s -> %s\n'
                        % (pkg, candidate)
                    )
                break
            rejected.append(candidate)

        if selected is not None:
            break

    if selected is None:
        sys.stderr.write('Cannot safely resolve build dependency: %s\n' % relation)
        if rejected:
            sys.stderr.write(
                'Rejected because APT would remove/change packages unsafely: %s\n'
                % ', '.join(rejected)
            )
        sys.exit(2)

    if selected not in chosen:
        chosen.append(selected)

for pkg in chosen:
    print(pkg)
PY
[ "$?" = "0" ] || die "could not resolve build dependencies"

BUILD_DEPS=()
while read P; do
    [ -n "$P" ] && BUILD_DEPS+=("$P")
done < "$WORK/build-deps.txt"

echo "Build dependencies:"
printf '  %s\n' "${BUILD_DEPS[@]}"

apt_simulate "${BUILD_DEPS[@]}" > "$BACKUP/logs/apt-builddeps-simulate.log" 2>&1     || {
        cat "$BACKUP/logs/apt-builddeps-simulate.log"
        die "build dependency simulation failed"
    }

if grep -q '^Remv ' "$BACKUP/logs/apt-builddeps-simulate.log"; then
    echo "APT removal plan (refusing to touch production packages):"
    grep '^Remv ' "$BACKUP/logs/apt-builddeps-simulate.log" || true
    echo
    echo "Full simulation log: $BACKUP/logs/apt-builddeps-simulate.log"
    die "APT wants to remove packages"
fi

apt_install "${BUILD_DEPS[@]}" 2>&1 | tee "$BACKUP/logs/apt-builddeps-install.log"     || die "build dependency installation failed"

dpkg-checkbuilddeps > "$BACKUP/logs/dpkg-checkbuilddeps.log" 2>&1     || {
        cat "$BACKUP/logs/dpkg-checkbuilddeps.log"
        die "build dependencies remain unsatisfied"
    }

# ---------------------------------------------------------------------------
# Frozen patch from our own host.
# PHP 5.6 must apply cleanly as-is; no fuzzy/ad-hoc source rewrites are allowed.
# ---------------------------------------------------------------------------

section "SECURITY PATCH"

PATCHFILE="$SRCROOT/$PATCH"

grep -q 'max_multipart_body_parts' "$PATCHFILE" \
    || die "unexpected patch: multipart protection missing"
grep -q 'zend_mm_safe_error_ex' "$PATCHFILE" \
    || die "unexpected patch: safe OOM protection missing"

section "PATCH DRY RUN"

patch --dry-run --batch --forward -p1 < "$PATCHFILE" \
    > "$BACKUP/logs/patch-dry-run.log" 2>&1 \
    || {
        cat "$BACKUP/logs/patch-dry-run.log"
        die "PHP 5.6 security patch does not apply cleanly; source left untouched"
    }

cat "$BACKUP/logs/patch-dry-run.log"

section "APPLY SECURITY PATCH"

mkdir -p debian/patches

CORE_PATCH='9999-php2shell-cve-2026.patch'
cp -a "$PATCHFILE" "debian/patches/$CORE_PATCH"
[ -f debian/patches/series ] || : > debian/patches/series

grep -q "^$CORE_PATCH\([[:space:]]\|$\)" debian/patches/series \
    || echo "$CORE_PATCH -p1" >> debian/patches/series

export QUILT_PATCHES=debian/patches

quilt push -a 2>&1 | tee "$BACKUP/logs/quilt-core.log" \
    || die "quilt failed applying PHP2Shell security patch"

# Final source-level assertions.
grep -Rqs 'max_multipart_body_parts' main ext Zend 2>/dev/null \
    || die "multipart protection signal missing after patch"
grep -Rqs 'zend_mm_safe_error_ex' Zend main 2>/dev/null \
    || die "safe OOM handler missing after patch"

echo
echo "Security patch applied successfully to Dotdeb PHP $PHP_UPSTREAM."
# ---------------------------------------------------------------------------
# New local package version.
# ---------------------------------------------------------------------------

section "PACKAGE VERSION"

{
    echo "php5 ($NEWVER) wheezy; urgency=high"
    echo
    echo "  * Local PHP 5.6 security rebuild for CVE-2026-109618 and CVE-2026-109619."
    echo
    echo " -- Local Security Build <root@localhost>  $(date -R)"
    echo
    cat debian/changelog
} > "$WORK/changelog.new"

mv "$WORK/changelog.new" debian/changelog

PARSED_VERSION="$(
    dpkg-parsechangelog 2>/dev/null         | sed -n 's/^Version:[[:space:]]*//p'         | head -1
)"

[ "$PARSED_VERSION" = "$NEWVER" ]     || die "failed to set new package version (got: $PARSED_VERSION)"

# ---------------------------------------------------------------------------
# Build.
# ---------------------------------------------------------------------------

section "BUILD"

export DEB_BUILD_OPTIONS='nocheck parallel=2'

dpkg-buildpackage -b -uc -us 2>&1 | tee "$BACKUP/logs/php56-build.log"
BUILD_RC=${PIPESTATUS[0]}
[ "$BUILD_RC" = "0" ] || die "PHP build failed"

# ---------------------------------------------------------------------------
# Verify only packages corresponding to what was installed before.
# ---------------------------------------------------------------------------

section "VERIFY BUILT PACKAGES"

NEW_DEBS=()

for P in "${INSTALLED_CORE[@]}"; do
    A="$(dpkg-query -W -f='${Architecture}' "$P")"
    F="$(find "$SRCROOT" -maxdepth 1 -type f         -name "${P}_${NEWVER}_${A}.deb" | head -1)"

    [ -n "$F" ] || die "built package missing: $P ($A)"

    [ "$(dpkg-deb -f "$F" Package)" = "$P" ] || die "package mismatch: $F"
    [ "$(dpkg-deb -f "$F" Version)" = "$NEWVER" ] || die "version mismatch: $F"
    [ "$(dpkg-deb -f "$F" Architecture)" = "$A" ] || die "arch mismatch: $F"

    NEW_DEBS+=("$F")
    cp -a "$F" "$PKGOUT/"
    echo "OK $(basename "$F")"
done

cp -a "$SRCROOT/$PATCH" "$SRCROOT/$MANIFEST" "$PKGOUT/"

# ---------------------------------------------------------------------------
# Offline ABI/runtime test with current extension configuration.
# ---------------------------------------------------------------------------

section "OFFLINE TEST"

rm -rf "$STAGE"
mkdir -p "$STAGE"

for F in "${NEW_DEBS[@]}"; do
    dpkg-deb -x "$F" "$STAGE" || die "cannot extract $F"
done

NEWPHP="$STAGE/usr/bin/php5"
[ -x "$NEWPHP" ] || die "new php5 binary missing"

"$NEWPHP" -n -v || die "new PHP cannot start"
"$NEWPHP" -n -i > "$BACKUP/diagnostics/new-php-info.txt"

grep -q '^PHP API => 20131106$' "$BACKUP/diagnostics/new-php-info.txt"     || die "PHP API changed"
grep -q '^PHP Extension => 20131226$' "$BACKUP/diagnostics/new-php-info.txt"     || die "PHP extension ABI changed"
grep -q '^Zend Extension => 220131226$' "$BACKUP/diagnostics/new-php-info.txt"     || die "Zend ABI changed"
grep -q '^PHP Extension Build => API20131226,NTS$' "$BACKUP/diagnostics/new-php-info.txt"     || die "unexpected PHP build ABI"
grep -q '^Zend Extension Build => API220131226,NTS$' "$BACKUP/diagnostics/new-php-info.txt"     || die "unexpected Zend build ABI"

ldd "$NEWPHP" > "$BACKUP/diagnostics/new-php-ldd.txt"
grep -q 'not found' "$BACKUP/diagnostics/new-php-ldd.txt"     && die "new PHP has unresolved libraries"

if [ "$HAS_APACHE" = "1" ]; then
    NEWLIB="$STAGE/usr/lib/apache2/modules/libphp5.so"
    [ -f "$NEWLIB" ] || die "new libphp5.so missing"
    ldd "$NEWLIB" > "$BACKUP/diagnostics/new-libphp5-ldd.txt"
    grep -q 'not found' "$BACKUP/diagnostics/new-libphp5-ldd.txt"         && die "new libphp5.so has unresolved libraries"
fi

"$NEWPHP"     -c /etc/php5/cli/php.ini     -d display_errors=1     -d display_startup_errors=1     -m     > "$BACKUP/diagnostics/new-php-modules.txt"     2> "$BACKUP/diagnostics/new-php-startup-errors.txt"

if grep -Ei 'PHP Startup|Unable to load|undefined symbol|cannot open shared object|segmentation|segfault' "$BACKUP/diagnostics/new-php-startup-errors.txt"
then
    cat "$BACKUP/diagnostics/new-php-startup-errors.txt"
    die "existing PHP extensions are incompatible with rebuilt PHP"
fi

"$NEWPHP" -n -r '
$v = ini_get("max_multipart_body_parts");
if ($v === false) exit(1);
echo "max_multipart_body_parts=", $v, "\n";
' || die "security patch signal missing"

# ---------------------------------------------------------------------------
# Service restart blocker / rollback.
# ---------------------------------------------------------------------------

save_policy() {
    [ "$POLICY_SAVED" = "0" ] || return 0
    POLICY_SAVED=1

    if [ -e /usr/sbin/policy-rc.d ]; then
        HAD_POLICY=1
        cp -a /usr/sbin/policy-rc.d "$BACKUP/policy-rc.d.original"
    fi
}

block_services() {
    save_policy
    cat > /usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
    chmod 755 /usr/sbin/policy-rc.d
}

restore_policy() {
    [ "$POLICY_SAVED" = "1" ] || return 0

    if [ "$HAD_POLICY" = "1" ]; then
        cp -a "$BACKUP/policy-rc.d.original" /usr/sbin/policy-rc.d
    else
        rm -f /usr/sbin/policy-rc.d
    fi
}

rollback() {
    echo
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo " INSTALL FAILED -- ROLLING BACK"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

    block_services

    if [ "$HAS_APACHE" = "1" ]; then
        /etc/init.d/apache2 stop || true
    fi
    if [ "$HAS_FPM" = "1" ]; then
        /etc/init.d/php5-fpm stop || true
    fi

    dpkg -i "${ROLLBACK_DEBS[@]}" || true

    if [ -d "$BACKUP/runtime/usr/lib/php5" ]; then
        rm -rf /usr/lib/php5
        cp -a "$BACKUP/runtime/usr/lib/php5" /usr/lib/
    fi

    if [ -f "$BACKUP/runtime/usr/lib/apache2/modules/libphp5.so" ]; then
        cp -a "$BACKUP/runtime/usr/lib/apache2/modules/libphp5.so"             /usr/lib/apache2/modules/libphp5.so
    fi

    if [ -d "$BACKUP/configs/php5" ]; then
        rm -rf /etc/php5
        cp -a "$BACKUP/configs/php5" /etc/php5
    fi

    restore_policy

    if [ "$HAS_APACHE" = "1" ]; then
        apache2ctl configtest || true
        /etc/init.d/apache2 start || true
    fi
    if [ "$HAS_FPM" = "1" ]; then
        [ ! -x /usr/sbin/php5-fpm ] || /usr/sbin/php5-fpm -t || true
        /etc/init.d/php5-fpm start || true
    fi

    echo
    echo "Rollback PHP:"
    /usr/bin/php5 -v || true
    echo "Backup: $BACKUP"
    exit 1
}

signal_handler() {
    if [ "$INSTALL_STARTED" = "1" ]; then
        rollback
    fi
    restore_policy
    exit 130
}

trap signal_handler INT TERM

# ---------------------------------------------------------------------------
# Install.
# ---------------------------------------------------------------------------

section "INSTALL PATCHED PACKAGES"

if [ "$HAS_APACHE" = "1" ]; then
    apache2ctl configtest || die "Apache config invalid before install"
fi
if [ "$HAS_FPM" = "1" ] && [ -x /usr/sbin/php5-fpm ]; then
    /usr/sbin/php5-fpm -t || die "php5-fpm config invalid before install"
fi

block_services
INSTALL_STARTED=1

dpkg -i "${NEW_DEBS[@]}" || rollback

for P in "${INSTALLED_CORE[@]}"; do
    V="$(dpkg-query -W -f='${Version}' "$P" 2>/dev/null || true)"
    echo "$P    $V"
    [ "$V" = "$NEWVER" ] || rollback
done

/usr/bin/php5 -v || rollback
/usr/bin/php5 -v 2>&1 | head -1 | grep -Fq "$NEWVER" || rollback

/usr/bin/php5 -m     > "$BACKUP/diagnostics/php-modules-after.txt"     2> "$BACKUP/diagnostics/php-startup-after.txt"     || rollback

if grep -Ei 'PHP Startup|Unable to load|undefined symbol|cannot open shared object|segmentation|segfault' "$BACKUP/diagnostics/php-startup-after.txt"
then
    cat "$BACKUP/diagnostics/php-startup-after.txt"
    rollback
fi

/usr/bin/php5 -r '
$v = ini_get("max_multipart_body_parts");
if ($v === false) exit(1);
echo "max_multipart_body_parts=", $v, "\n";
' || rollback

if [ "$HAS_APACHE" = "1" ]; then
    apache2ctl configtest || rollback
fi
if [ "$HAS_FPM" = "1" ] && [ -x /usr/sbin/php5-fpm ]; then
    /usr/sbin/php5-fpm -t || rollback
fi

restore_policy

if [ "$HAS_APACHE" = "1" ]; then
    section "RESTART APACHE"
    /etc/init.d/apache2 restart || rollback
    sleep 2

    ps aux | grep '[a]pache2' >/dev/null || rollback

    apache2ctl -M > "$BACKUP/diagnostics/apache-modules-after.txt" 2>&1         || rollback

    grep -q 'mpm_prefork_module' "$BACKUP/diagnostics/apache-modules-after.txt"         || rollback
    grep -q 'php5_module' "$BACKUP/diagnostics/apache-modules-after.txt"         || rollback
fi

if [ "$HAS_FPM" = "1" ]; then
    section "RESTART PHP5-FPM"
    /etc/init.d/php5-fpm restart || rollback
    sleep 2
    ps aux | grep '[p]hp5-fpm' >/dev/null || rollback
fi

INSTALL_STARTED=0

# ---------------------------------------------------------------------------
# Final state + backup archive.
# ---------------------------------------------------------------------------

section "FINAL STATE"

/usr/bin/php5 -v

echo
/usr/bin/php5 -r '
echo "max_multipart_body_parts=",
     ini_get("max_multipart_body_parts"),
     "\n";
'

echo
echo "Patched packages:"
for P in "${INSTALLED_CORE[@]}"; do
    dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' "$P"
done

section "ARCHIVE BACKUP"

tar czpf "$BACKUP.tar.gz" -C /backup "$(basename "$BACKUP")"     || echo "WARNING: backup directory exists, tar.gz creation failed"

if [ -f "$BACKUP.tar.gz" ]; then
    sha256sum "$BACKUP.tar.gz" > "$BACKUP.tar.gz.sha256"
fi

section "PHP 5.6 PHP2SHELL UPDATE SUCCESSFUL"

echo
/usr/bin/php5 -v | head -1
echo
echo "Built packages: $PKGOUT"
echo "Backup:         $BACKUP"
echo "Archive:        $BACKUP.tar.gz"
echo
echo "DO NOT DELETE THE BACKUP."
