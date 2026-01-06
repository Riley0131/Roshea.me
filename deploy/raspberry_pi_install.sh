#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-roshea}"
APP_USER="${APP_USER:-pi}"
APP_GROUP="${APP_GROUP:-www-data}"
DOMAIN="${DOMAIN:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_DIR="${APP_DIR:-$REPO_ROOT}"
PROJECT_DIR="$APP_DIR/roshea"
VENV_DIR="$APP_DIR/venv"
ENV_FILE="/etc/$APP_NAME/env"

if [[ -n "$DOMAIN" ]]; then
  SERVER_NAME="$DOMAIN"
  ALLOWED_HOSTS="${DOMAIN// /,},localhost,127.0.0.1"
else
  SERVER_NAME="_"
  ALLOWED_HOSTS="localhost,127.0.0.1"
fi

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0"
  exit 1
fi

if ! id -u "$APP_USER" >/dev/null 2>&1; then
  echo "User '$APP_USER' not found. Create it or set APP_USER."
  exit 1
fi

apt-get update
apt-get install -y python3 python3-venv python3-pip python3-dev build-essential nginx git

if [[ ! -d "$APP_DIR" ]]; then
  if [[ -n "${REPO_URL:-}" ]]; then
    git clone "$REPO_URL" "$APP_DIR"
  else
    echo "APP_DIR '$APP_DIR' does not exist and REPO_URL is not set."
    exit 1
  fi
fi

if [[ ! -f "$PROJECT_DIR/manage.py" ]]; then
  echo "Expected manage.py at $PROJECT_DIR/manage.py"
  echo "Set APP_DIR to the repo root or set REPO_URL."
  exit 1
fi

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install -r "$APP_DIR/requirements.txt"

install -d -m 0750 "/etc/$APP_NAME"

if [[ ! -f "$ENV_FILE" ]]; then
  SECRET_KEY=$("$VENV_DIR/bin/python" - <<'PY'
import secrets
print(secrets.token_urlsafe(50))
PY
)
  cat > "$ENV_FILE" <<EOF
DJANGO_SECRET_KEY=$SECRET_KEY
DJANGO_DEBUG=0
DJANGO_ALLOWED_HOSTS=$ALLOWED_HOSTS
DJANGO_CSRF_TRUSTED_ORIGINS=
DJANGO_SECURE_SSL_REDIRECT=0
DJANGO_SESSION_COOKIE_SECURE=0
DJANGO_CSRF_COOKIE_SECURE=0
DJANGO_SECURE_HSTS_SECONDS=0
DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS=0
DJANGO_SECURE_HSTS_PRELOAD=0
EOF
  chmod 0640 "$ENV_FILE"
  chown root:"$APP_GROUP" "$ENV_FILE"
fi

chown -R "$APP_USER":"$APP_GROUP" "$APP_DIR"

runuser -u "$APP_USER" -- "$VENV_DIR/bin/python" "$PROJECT_DIR/manage.py" migrate --noinput
runuser -u "$APP_USER" -- "$VENV_DIR/bin/python" "$PROJECT_DIR/manage.py" collectstatic --noinput

cat > "/etc/systemd/system/$APP_NAME.service" <<EOF
[Unit]
Description=Gunicorn for $APP_NAME
After=network.target

[Service]
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$VENV_DIR/bin/gunicorn --workers 3 --bind unix:/run/$APP_NAME/$APP_NAME.sock --access-logfile - --error-logfile - $APP_NAME.wsgi:application
Restart=on-failure
RuntimeDirectory=$APP_NAME
RuntimeDirectoryMode=0755

[Install]
WantedBy=multi-user.target
EOF

cat > "/etc/nginx/sites-available/$APP_NAME" <<EOF
server {
    listen 80;
    server_name ${SERVER_NAME:-_};

    location /static/ {
        alias $PROJECT_DIR/staticfiles/;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:/run/$APP_NAME/$APP_NAME.sock;
    }
}
EOF

ln -sf "/etc/nginx/sites-available/$APP_NAME" "/etc/nginx/sites-enabled/$APP_NAME"
if [[ -f /etc/nginx/sites-enabled/default ]]; then
  rm -f /etc/nginx/sites-enabled/default
fi

systemctl daemon-reload
systemctl enable --now "$APP_NAME"
nginx -t
systemctl reload nginx

echo "Deployment complete."
echo "Edit $ENV_FILE to set domain/SSL settings, then run: systemctl restart $APP_NAME"
