# iOS VPN Backend

NestJS backend API for an iOS VPN app. The app talks only to this backend; Remnawave Panel API access stays server-side through `REMNAWAVE_API_TOKEN`.

## Stack

- Node.js, NestJS, PostgreSQL, Prisma ORM
- JWT access and refresh tokens
- bcrypt password hashing and hashed refresh-token storage
- Swagger/OpenAPI at `/docs`
- Docker Compose with PostgreSQL
- Hourly subscription-expiry enforcement

## Setup

```bash
cp .env.example .env
npm install
npm run prisma:generate
npm run prisma:migrate
npm run prisma:seed
npm run start:dev
```

Open Swagger at [http://localhost:3000/docs](http://localhost:3000/docs).

## Docker

```bash
cp .env.example .env
docker compose up --build
```

For local Docker, set:

```env
DATABASE_URL=postgresql://vpn:vpn@postgres:5432/vpn_backend?schema=public
```

## Environment

```env
DATABASE_URL=
JWT_ACCESS_SECRET=
JWT_REFRESH_SECRET=
REMNAWAVE_BASE_URL=https://panel.yeats.uz
REMNAWAVE_API_TOKEN=
SUBSCRIPTION_BASE_URL=https://sub.yeats.uz
```

Never send `REMNAWAVE_API_TOKEN` to the iOS app. All Remnawave calls are wrapped by `RemnawaveService`.

## API

- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/refresh`
- `POST /auth/logout`
- `GET /me`
- `GET /vpn/profile`
- `GET /vpn/usage`
- `POST /vpn/enable`
- `POST /vpn/disable`
- `POST /vpn/reset-traffic`
- `POST /vpn/regenerate-subscription`
- `GET /plans`
- `POST /billing/checkout`
- `POST /billing/webhook/apple`
- `POST /billing/webhook/stripe`

## Registration Flow

1. iOS sends `email`, `password`, and `deviceId`.
2. Backend creates the local user and device.
3. Backend provisions a Remnawave user using the default active plan.
4. Backend stores the Remnawave UUID and subscription URL.
5. Backend returns access and refresh tokens plus profile data.

## Tests

```bash
npm test
```
