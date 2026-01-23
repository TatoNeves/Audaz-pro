# Supabase Edge Functions - Deploy Instructions

## Prerequisites

1. Install Supabase CLI:
```bash
npm install -g supabase
```

2. Login to Supabase:
```bash
supabase login
```

3. Link your project:
```bash
supabase link --project-ref jliqlisrnuusqxiswfcg
```

## Set Resend API Key

Before deploying, set the Resend API key as a secret:

```bash
supabase secrets set RESEND_API_KEY=re_EF9Zt1s9_P7BDhB6pofK2wVGAMZCJ3wnM
```

## Deploy Functions

**IMPORTANT**: Use `--no-verify-jwt` flag to allow public access (required for client-side calls):

```bash
supabase functions deploy send-invite-email --no-verify-jwt
supabase functions deploy ticket-notification --no-verify-jwt
```

Or deploy all at once:

```bash
supabase functions deploy --no-verify-jwt
```

> Note: The `--no-verify-jwt` flag is required because these functions are called from the browser using the Supabase client. Without this flag, you'll get 401 Unauthorized errors.

## Configure Resend Domain

For production, you need to:

1. Go to [Resend Dashboard](https://resend.com/domains)
2. Add and verify your domain (audazpro.com)
3. Update the "from" email in the Edge Functions to use your verified domain

Currently using: `noreply@audazpro.com`

## Testing

Test the functions locally:

```bash
supabase functions serve send-invite-email --env-file ./supabase/.env.local
```

Create a `.env.local` file in the `supabase` folder:

```
RESEND_API_KEY=re_EF9Zt1s9_P7BDhB6pofK2wVGAMZCJ3wnM
```

## Function URLs

After deployment, functions will be available at:

- `https://jliqlisrnuusqxiswfcg.supabase.co/functions/v1/send-invite-email`
- `https://jliqlisrnuusqxiswfcg.supabase.co/functions/v1/ticket-notification`

## Troubleshooting

Check function logs:

```bash
supabase functions logs send-invite-email
supabase functions logs ticket-notification
```
