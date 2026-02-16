# Mission Control — Second Brain

Mission Control is a secure, dark-mode cockpit for reviewing memories, docs, agents, and live context. The app now ships with an email-based one-time-passcode (OTP) login so Bill (or any trusted operator) can sign in from anywhere without maintaining passwords.

## Tech stack

- [Next.js 16 / App Router](https://nextjs.org/) with React Server Components
- Prisma ORM with a SQLite datasource for local development (swap to Postgres/Neon for Vercel)
- SendGrid for transactional OTP emails
- Tailwind-esque custom styling (no runtime CSS dependency)

## Prerequisites

- Node.js 20+
- npm 10+
- A SendGrid account + API key (free tier works)
- A database connection. The repo is configured for SQLite by default (file:./dev.db). For Vercel/production, provision a hosted database (Neon, Supabase, Turso, etc.) and point `DATABASE_URL` to that connection string before running `prisma migrate deploy`.

## Environment variables

Duplicate the sample file and fill in your secrets:

```bash
cp .env.example .env
```

| Variable | Description |
| --- | --- |
| `DATABASE_URL` | SQLite file for dev or remote DB URL for prod |
| `MISSION_CONTROL_ALLOWED_EMAILS` | Comma-separated list of emails allowed to request OTPs (e.g. `bill@example.com`) |
| `OTP_EXPIRATION_MINUTES` | Minutes before codes expire (default 10) |
| `SESSION_TTL_DAYS` | Session lifetime in days (default 14) |
| `SESSION_COOKIE_NAME` | Cookie used to store the signed-in session token |
| `SENDGRID_API_KEY` | API key with `Mail Send` permission |
| `SENDGRID_FROM_EMAIL` / `SENDGRID_FROM_NAME` | The verified sender used for OTP emails |
| `OTP_HASH_SECRET` | Extra salt for hashing OTP codes |

## Database setup

Prisma manages all tables (users, OTP requests, sessions). After configuring `DATABASE_URL` run:

```bash
npm install
npx prisma migrate dev --name otp-auth
```

For production/CI, run `npx prisma migrate deploy` after the build step. When deploying to Vercel with a remote Postgres provider, update `provider` inside `prisma/schema.prisma` and re-run the migration against that database.

## Running locally

```bash
npm run dev
```

Visit [http://localhost:3000](http://localhost:3000). If your email address is on the allowed list you will see the new login screen:

1. Enter the email address and click **Send code**.
2. Check your inbox for the SendGrid email (the code is logged to the server console when SendGrid isn’t configured).
3. Submit the 6-digit code to create a secure session.
4. The main Mission Control dashboard now shows your email + a Sign out button. Protected APIs (conversation sync, etc.) require this session cookie as well.

## OTP & session endpoints

| Method | Route | Purpose |
| --- | --- | --- |
| `POST` | `/api/auth/request-otp` | Validate email, store hashed OTP in the DB, send SendGrid email |
| `POST` | `/api/auth/verify-otp` | Validate the submitted code, mark it consumed, mint a session cookie |
| `POST` | `/api/auth/logout` | Destroy the current session and clear the cookie |
| `POST` | `/api/conversations/sync` | Now requires a valid session; pulls the latest hotline history |

## Deployment checklist (Vercel)

1. Provision a remote database (Neon / Supabase Postgres, Planetscale MySQL, Turso libSQL, etc.).
2. Update `DATABASE_URL` to the remote connection string and run `npx prisma migrate deploy` locally to apply the schema.
3. Push the repository to GitHub and import it into Vercel.
4. In the Vercel dashboard set the environment variables from `.env.example` (especially DB + SendGrid + allowed emails).
5. Vercel’s build step (`npm install && npm run build`) will bundle Prisma client. After the first deploy, run `npx prisma migrate deploy` against the production database (either locally with the prod `DATABASE_URL` or through a CI step) to ensure migrations are applied.
6. Share the `/login` link with Bill. OTP emails will arrive via SendGrid, and valid sessions unlock the full dashboard plus sync actions.

## Useful commands

| Command | Description |
| --- | --- |
| `npm run dev` | Run Next.js locally |
| `npm run build && npm start` | Production build preview |
| `npx prisma studio` | Inspect and edit the OTP/session tables |
| `npx prisma migrate dev --name <label>` | Create & apply a new migration |

## Troubleshooting

- **No OTP email**: Ensure `SENDGRID_API_KEY` and sender are set. In development the code is logged to the console when SendGrid is missing.
- **“Email not allowed”**: Add the address to `MISSION_CONTROL_ALLOWED_EMAILS`.
- **Session instantly logs out**: Check browser cookie blocking and confirm `SESSION_COOKIE_NAME` isn’t duplicated by another environment.
- **Deploy errors on Vercel**: Verify that `DATABASE_URL` points to a persistent, hosted DB. SQLite files are read-only on serverless runtimes.

With these changes, Mission Control now has a secure OTP wall, stateful session management, SendGrid email delivery, and Vercel-ready deployment instructions so Bill can sign in remotely within minutes.
