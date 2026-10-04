## Push Notification Flow

This folder wires Supabase to Firebase Cloud Messaging for the driver app.

### What happens

1. The Flutter app registers its FCM token in `public.users.push_tokens` as a JSON array.
2. When an order changes to `accepted`, Postgres trigger `trg_notify_on_order_accepted` calls the edge function `send-order-accepted-push`.
3. The edge function reads active driver tokens from `users.role = 'driver'` and flattens the `users.push_tokens` JSON array before sending through the Firebase HTTP v1 API.

### Required Supabase secrets

Set these before deploying the function:

```bash
supabase secrets set \
  SUPABASE_URL=https://xmhbrnkukhmzizkiyyhg.supabase.co \
  SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY \
  FIREBASE_PROJECT_ID=your-firebase-project-id \
  FIREBASE_CLIENT_EMAIL=your-service-account-email \
  FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
```

### Deploy

```bash
supabase functions deploy send-order-accepted-push
supabase db push
```

Because this function is called by a Postgres trigger through `pg_net`, JWT verification must be disabled for it. This repo sets that in `supabase/config.toml`:

```toml
[functions.send-order-accepted-push]
verify_jwt = false
```

### Important

- The Flutter client must use the public Supabase anon key, never the service role key.
- For iOS, add `GoogleService-Info.plist`, enable Push Notifications + Background Modes in Xcode, and upload your APNs key/certificate in Firebase.
