# Wasalny Orders

Monorepo for ready-shipment delivery: one Flutter app supports clients and captains, a NestJS API owns business rules, and the React admin dashboard handles operations.

## Structure

- `apps/mobile` - Flutter, Riverpod, GoRouter, Dio, OpenStreetMap, SharedPreferences, and FCM-ready notification wiring.
- `apps/api` - NestJS, Prisma/PostgreSQL, Redis, JWT, validation, and Swagger.
- `apps/admin` - React, TypeScript, Vite, Tailwind, React Query, and React Router.
- `packages` - reserved for shared contracts as the API and clients stabilize.

## تشغيل قاعدة البيانات محليًا

شغّل خدمات Docker بالأمر `docker compose up -d`. PostgreSQL متاح على `localhost:5433` بدلًا من 5432 لتجنب التعارض مع PostgreSQL المحلي، وRedis على `localhost:6380` لتجنب تعارض المنفذ الافتراضي. أنشئ قاعدة الاختبار ثم نفّذ أول migration من مجلد API:

```powershell
docker compose exec postgres psql -U wasalny -d postgres -c "CREATE DATABASE waslny_test;"
Set-Location apps/api
npx prisma migrate dev --name init
```

### نسخة محلية بدون Docker (PostgreSQL 18 على المنفذ 5435)

هذا الجهاز يشغّل عنقود PostgreSQL محليًا مستقلًا للمشروع على `localhost:5435`:

- الخدمة: `postgresql-waslny-orders-v2` · مجلد البيانات: `C:\pgdata\waslny_orders_v2` · استماع على `localhost` فقط.
- القاعدة: `waslny_orders_dev` · المستخدم: `waslny_orders_user` (بلا صلاحيات سوبر).
- كلمة المرور تُوضع في `apps/api/.env` فقط (ملف غير متتبَّع)، وليس في `.env.example`.
- العنقود الأقدم على `5434` يبقى كما هو للقراءة فقط ولا يجب تعديله.

## Start local services

Requirements: Node.js 22+, npm, Flutter stable, and Docker Desktop.

```powershell
docker compose up -d
Copy-Item apps/api/.env.example apps/api/.env
npm install
npm run prisma:generate --workspace api
npm run prisma:migrate --workspace api
npm run dev:api
```

> `npm run prisma:migrate` also runs the seed. Set `ADMIN_PASSWORD` in `apps/api/.env` to a unique value first: there is no default password in any environment, and known placeholders are refused with a clear error.

In a second terminal, start the dashboard with `npm run dev:admin`. The mobile app can run with `cd apps/mobile; flutter pub get; flutter run`. On Android emulators, set `API_BASE_URL=http://10.0.2.2:3000/api/v1`; on iOS simulators use `http://localhost:3000/api/v1`.

## Environment isolation

This machine hosts more than one project. Our Docker resources are namespaced with the `waslny_orders_` prefix — never touch containers, volumes, or networks that don't carry it:

- Compose project: `waslny_orders` (`name:` in `docker-compose.yml`)
- Containers: `waslny_orders_postgres`, `waslny_orders_redis`
- Volumes: `waslny_orders_pgdata`, `waslny_orders_redisdata`
- Network: `waslny_orders_net`
- Ports (host): PostgreSQL `5433` (`POSTGRES_PORT`), Redis `6380` (`REDIS_PORT`)
- Database: `waslny_orders_dev`, user `waslny_orders_user` (credentials from root `.env`, gitignored)

> ⚠️ WARNING: port `5432` and containers such as `wasalny_db_container` belong to a different project. Do not stop, remove, exec into, or connect to them. Our stack intentionally avoids `5432`/`6379` on the host.

## Receiving Kashier webhooks locally

Kashier calls `POST /api/v1/webhooks/kashier` server-to-server, so `localhost` never works directly. Expose this API with a tunnel, then point Kashier at the public URL:

1. Start a tunnel to the API (pick one tool, do not commit its URL):
   - Cloudflare: `cloudflared tunnel --url http://localhost:3000`
   - ngrok: `ngrok http 3000`
2. Copy the public base URL, e.g. `https://<random>.trycloudflare.com`.
3. Set `KASHIER_WEBHOOK_URL=https://<random>.trycloudflare.com/api/v1/webhooks/kashier` in `apps/api/.env` (per-payment `serverWebhook`; may stay empty in local dev, required in production).
4. Trigger a test payment and watch for `200 {"acknowledged":true}`.

No tunnel tool is installed or started by this repo — run it yourself when needed.

New users can register as clients. Captain registration creates a pending application; an admin must approve it before accepting orders. The seed script (`npm run prisma:seed --workspace api`) creates the admin account from `ADMIN_EMAIL`/`ADMIN_PASSWORD` (see `apps/api/.env.example`); in production these variables are required and no default password is used. Only a bcrypt hash is ever stored.

## MVP notes

Prices are calculated from straight-line pickup/dropoff distance and configurable base/per-kilometre rates. Captain acceptance is atomic: it checks the available wallet balance against the order commission before assigning the order. Payment processing is intentionally an interface placeholder for a future Kashier integration. Live captain discovery uses Redis when configured; order state remains authoritative in PostgreSQL. Push delivery requires Firebase project credentials and is not activated by the local scaffold.

## Commands

- `npm run build:api`
- `npm run build:admin`
- `cd apps/mobile; flutter analyze`
- `cd apps/api; npm test`
