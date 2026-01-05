#!/bin/bash

while true; do	
	if [[ -n "$domain" ]]; then
		break
	fi
	echo -en "Enter your panel domain(sub.domain.tld): " && read domain 
done

XUIPORT=$(sqlite3 -list /etc/x-ui/x-ui.db 'SELECT "value" FROM settings WHERE "key"="webPort" LIMIT 1;' 2>&1)
XUIPATH=$(sqlite3 -list /etc/x-ui/x-ui.db 'SELECT "value" FROM settings WHERE "key"="webBasePath" LIMIT 1;' 2>&1)



mkdir -p /root/cert/${domain}
chmod 755 /root/cert/*

ln -s /etc/letsencrypt/live/${domain}/fullchain.pem /root/cert/${domain}/fullchain.pem
ln -s /etc/letsencrypt/live/${domain}/privkey.pem /root/cert/${domain}/privkey.pem



NGINX_CONF="/etc/nginx/sites-available/${domain}"

# normalize XUIPATH: remove leading/trailing slashes
XUIPATH_NORM="${XUIPATH#/}"
XUIPATH_NORM="${XUIPATH_NORM%/}"

LOC1="/${XUIPATH_NORM}/"
LOC2="/${XUIPATH_NORM}"


read -r -d '' XUI_BODY <<EOF
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;

        proxy_pass https://127.0.0.1:${XUIPORT};
        break;
EOF

tmp="$(mktemp)"

awk -v loc1="$LOC1" -v loc2="$LOC2" -v body="$XUI_BODY" '
function emit_location(loc) {
  print "    location " loc " {"
  n = split(body, a, "\n")
  for (i=1; i<=n; i++) print a[i]
  print "    }"
}

BEGIN{
  replaced1=0; replaced2=0;
  inloc=0; depth=0; curr="";
  inserted=0;
}

{
  line=$0


  if (inloc) {
    for (i=1; i<=length(line); i++) {
      c=substr(line,i,1)
      if (c=="{") depth++
      else if (c=="}") depth--
    }
    if (depth<=0) {
      inloc=0
      curr=""
    }
    next
  }

  if (match(line, "^[[:space:]]*location[[:space:]]+" loc1 "[[:space:]]*\\{")) {
    emit_location(loc1); replaced1=1
    inloc=1; depth=1
    next
  }
  if (match(line, "^[[:space:]]*location[[:space:]]+" loc2 "[[:space:]]*\\{")) {
    emit_location(loc2); replaced2=1
    inloc=1; depth=1
    next
  }

  if (!inserted && line ~ /^[[:space:]]*include[[:space:]]+\/etc\/nginx\/snippets\/includes\.conf;/) {
    if (!replaced1) { emit_location(loc1); replaced1=1 }
    if (!replaced2) { emit_location(loc2); replaced2=1 }
    inserted=1
    print line
    next
  }

  print line
}

END{
}
' "$NGINX_CONF" > "$tmp" && cat "$tmp" > "$NGINX_CONF" && rm -f "$tmp"


/usr/local/x-ui/x-ui cert -webCert "/root/cert/${domain}/fullchain.pem" -webCertKey "/root/cert/${domain}/privkey.pem"

x-ui restart
nginx -t
systemctl restart nginx

