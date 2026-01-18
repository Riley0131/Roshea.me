# Deploying to Render

This project is configured to deploy with Render using `render.yaml`. Follow these steps.

## 1) Create the Render service
1. Push this repo to GitHub.
2. In Render: New + -> Web Service -> Connect the repo.
3. Render will detect `render.yaml` and prefill build/start commands.
4. Click Create Web Service.

## 2) Environment variables
Render will create `DJANGO_SECRET_KEY` automatically. Set these in the Render UI if you need to override defaults:
- `DJANGO_DEBUG`: set to `false` (already in `render.yaml`).
- `DJANGO_ALLOWED_HOSTS`: optional; comma-separated hosts (e.g. `example.com,www.example.com`).
  - Render also injects `RENDER_EXTERNAL_HOSTNAME` automatically; the app will add it to `ALLOWED_HOSTS`.

## 3) Static files
Static files are handled by WhiteNoise. The build step runs:
```
pip install -r requirements.txt && python roshea/manage.py collectstatic --noinput
```
No other changes are needed.

## 4) Custom domain (optional)
If you add a custom domain in Render, set `DJANGO_ALLOWED_HOSTS` to include it (comma-separated). You do not need to set `CSRF_TRUSTED_ORIGINS` manually; the app auto-configures it for the Render hostname.

## 5) Local parity (optional)
To match production locally:
```
export DJANGO_DEBUG=false
export DJANGO_SECRET_KEY='dev-only-secret'
```
Then run:
```
python roshea/manage.py runserver
```

## Files involved
- `render.yaml`: Render service definition
- `requirements.txt`: includes `gunicorn` + `whitenoise`
- `roshea/roshea/settings.py`: WhiteNoise + Render env handling
