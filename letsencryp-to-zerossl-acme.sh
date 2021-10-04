#!/bin/bash
email="security@zabiyaka.net"
LANG=C
cmdname=`basename $0`
newtmpdir=`mktemp -d /tmp/${cmdname}.XXXXXX`
spool="$newtmpdir/spool"
spool2="$newtmpdir/spool2"

function cleanup () {
  rm -rf "${newtmpdir}"
}

trap 'cleanup' EXIT
trap 'cleanup' SIGTERM

if [ ! -f "/root/.acme.sh/acme.sh" ]
then
curl https://get.acme.sh | sh
/root/.acme.sh/acme.sh --register-account -m ${email}
crontab -l | grep -v 'acme.sh' > ${spool}
echo '0 1 * * * /root/.acme.sh/acme.sh --renew-all --renew-hook "/etc/init.d/nginx reload" &> /dev/null' >> ${spool}
crontab ${spool}
cat /dev/null > ${spool}
echo ""
echo "CRONTAB INSTALLED:"
crontab -l |grep 'acme.sh'
echo "INSTALL OK? - CTRL+C to abort"
read
fi

if [ -d /etc/letsencrypt/renewal ] 
then
cd /etc/letsencrypt/renewal/
for file in `ls *.conf`
do
	domain=`ls ${file} | awk -F '.conf' '{print$1}'`
	echo "${domain}" > ${spool}

	for subdomain in `grep -A 100 "[[webroot_map]]" $file |grep "=" | awk '{print$1}'`;
	do 
	 echo "${subdomain}" >> ${spool}
	done

	dir=`grep -A 100 "[[webroot_map]]" $file |grep "=" | awk '{print$3}' |sort -u`
	if [ "${dir}" == "" ] 
	then
	 echo "${domain} has now webroot, please enter webroot: (CTRL+C to abort)"
	 read dir
	 [ "${dir}" == "" ] && echo "empty, using default /var/www/html" && dir="/var/www/html"
	 echo -n "/root/.acme.sh/acme.sh --issue -w ${dir} --issue -d ${domain}" > ${spool2}
	else
	 echo -n "/root/.acme.sh/acme.sh --issue -w ${dir} --issue -d ${domain}" > ${spool2}
	fi

	for dom in `sort -u ${spool} |grep -v "^${domain}$"`
	do
	 echo -n " -d ${dom}" >> ${spool2}
	done

	cat ${spool2} 
	echo ""
	echo "proceed with renew? CTRL+C to abort, any key to continue..."
	read
	bash ${spool2}
	echo ""
        echo "============"
	echo "Configuration:"
	grep -ri -m1 "${domain}" /etc/nginx | head -n 2

	echo "ADD THIS:"
	echo "ssl_certificate /root/.acme.sh/${domain}/fullchain.cer;"
	echo "ssl_certificate_key /root/.acme.sh/${domain}/${domain}.key;"
	echo "nginx -t"
	echo "============"
	echo ""
done


fi
