# Audaz Pro - Static Website

This repository hosts the rewritten version of the Audaz Pro marketing site, optimized for static hosting on platforms such as DigitalOcean App Platform, Netlify, or any static server.

## 📁 Project structure

```
audaz-website/
├── index.html          # Homepage
├── services.html       # Webflow services page
├── retainers.html      # Retainer and support plan page
├── portfolio.html      # Portfolio page
├── contact.html        # Contact form page
├── client/             # Client portal UI (tickets, dashboard, settings)
├── support/            # Support portal UI
├── supabase/           # Supabase migrations and helpers
├── css/
│   └── style.css       # Main styles
├── js/
│   ├── main.js         # Marketing site scripts
│   └── services/       # Supabase + UI services
└── images/             # Local image assets
```

## 🚀 Deploy on DigitalOcean

### Option 1: App Platform (recommended)

1. Create an account at [digitalocean.com](https://www.digitalocean.com/).
2. Push the code to a Git provider (GitHub, GitLab, Bitbucket).
3. In the DigitalOcean Dashboard:
   - Click **Create → Apps**.
   - Link your repository.
   - Choose **Static Site** for the component type.
   - Name your app and continue through the wizard.
4. DigitalOcean will detect the project as a static site — no build step is needed.

### Option 2: Spaces + CDN

1. Create a Space in DigitalOcean.
2. Upload all repository files.
3. Enable the CDN option.
4. Point a custom domain if needed.

### Option 3: Droplet with Nginx

```bash
# install nginx
sudo apt update
sudo apt install nginx

# deploy files
sudo cp -r * /var/www/html/

# restart nginx
sudo systemctl restart nginx
```

## 📧 Supabase form configuration

1. Create a Supabase project at [supabase.com](https://supabase.com/) and capture the project URL and anon key.
2. Apply the migrations found in `supabase/migrations/` (the new `007_contacts.sql` defines the `contacts` table plus the anonymous insert/read policies) via `supabase db push` or your preferred migration workflow.
3. Update `js/supabase-config.js` with your Supabase URL/anon key so every portal page (including the marketing contact flow) shares the same client.
4. The contact page now loads `@supabase/supabase-js@2`, initializes the client from `js/supabase-config.js`, and posts submissions into the `contacts` table (`name`, `company`, `email`, `phone`, `budget`, `message`, `created_at`, `read`). No additional backend is required.
5. If you prefer to keep Formspree or another service, remove the Supabase script tags from `contact.html` and restore the form's `action` attribute so submissions go to that endpoint instead.

## 🎨 Customization

### Colors
Edit `css/style.css` variables under `:root` for brand colors, backgrounds, and accents.

### Images
1. Add assets to `images/`.
2. Update the markup in the HTML files to reference the new images.

### Fonts
The site uses Google Fonts (Archivo Black and DM Sans). To change them:
1. Pick new fonts on [Google Fonts](https://fonts.google.com/).
2. Update the `<link>` references in each `<head>`.
3. Adjust `--font-primary` / `--font-display` variables in the CSS.

## 🧪 Local development

Open `index.html` directly or run a simple server:

```bash
# python
python3 -m http.server 8000

# node
npx serve

# php
php -S localhost:8000
```

## 📱 Responsiveness

Breakpoints included:
- 1024px (tablets)
- 768px (small tablets)
- 480px (mobile)

## ⚡ Performance

- Minified CSS/JS (production builds should retain minification).
- Lazy-loaded images and optimized assets.
- `preconnect` links for Google Fonts.
- CSS animations use transforms for better performance.

## 📝 License

This code is provided for private internal use only. All rights reserved.
