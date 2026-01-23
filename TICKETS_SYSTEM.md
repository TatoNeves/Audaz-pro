# AUDAZ Pro - Ticket System

The ticket system ships with two portals (client and support) powered by Supabase authentication, role-based access, and a centralized API layer.

## Directory layout

```
audaz-website/
├── client/                          # Customer portal
│   ├── index.html                   # Login and registration
│   ├── dashboard.html               # Stats + recent tickets
│   ├── tickets/
│   │   ├── index.html               # Filtered ticket list
│   │   ├── new.html                 # Create a new ticket
│   │   └── detail.html              # Ticket detail + comments
│   └── settings/
│       └── team.html                # Team management + invitations
├── support/                         # Support portal
│   ├── index.html                   # Support login
│   ├── dashboard.html               # Support overview
│   └── tickets/
│       ├── index.html               # All tickets across organizations
│       └── detail.html              # Ticket detail + actions
├── invite/
│   └── index.html                   # Invitation acceptance flow
├── js/
│   ├── supabase-config.js           # Supabase credentials (required)
│   ├── services/
│   │   ├── auth.service.js          # Authentication helpers
│   │   ├── tickets.service.js       # Ticket CRUD
│   │   ├── comments.service.js      # Comments and timeline
│   │   └── invitations.service.js   # Team invitations
│   └── components/
│       ├── ui.components.js         # Shared UI building blocks
│       └── auth-guard.js            # Route protection utilities
├── css/
│   └── tickets.css                  # Tickets-specific styles
└── supabase/
    └── migrations/
        ├── 001_create_tables.sql
        ├── 002_triggers_and_functions.sql
        └── 003_rls_policies.sql
```

## Supabase configuration

1. Create a new Supabase project.
2. Run the migrations in order from the SQL editor.
3. Update `js/supabase-config.js` with your Supabase URL and anon key.
4. Grant execute permissions (already handled at the end of `002_triggers_and_functions.sql`).
5. Make sure the `ticket-attachments` bucket exists and then apply `006_storage_policies.sql` so authenticated users can upload/download attachments via Supabase Storage.

### Storage policies

The attachments flow uploads files into `ticket-attachments`, so Supabase Storage needs a policy that explicitly allows authenticated clients to INSERT and SELECT from `storage.objects` for that bucket. The new migration `006_storage_policies.sql` enables RLS on `storage.objects` and grants these permissions scoped to the bucket; run your normal Supabase migration command (`supabase db push`, `supabase migrations run`, etc.) after adding the migration so the policy is active before anyone uploads files.

## Authentication flows

### Customer portal

- **Sign up**: Creates the user, organization, profile (client_admin), and sends a confirmation email.
- **Login**: Authenticates via Supabase and loads the client dashboard.
- **Create ticket**: Submits issues or change requests with type, priority, description, optional category and attachment.
- **Track**: View status badges, timeline/history, and add comments with attachments.
- **Team**: Invite up to 4 members per organization and manage access.

### Support portal

- **Login**: Separate Supabase login for support_agent/support_admin roles.
- **Dashboard**: View stats and quick filters for Open / In Progress / High Priority tickets.
- **Ticket management**: Update status, assign agents, comment, and view organization filters.

## Roles & access

| Role | Description | Access |
|------|-------------|--------|
| `client_admin` | Organization admin | Tickets + team management |
| `client_user` | Regular user | Tickets within own org |
| `support_agent` | Support agent | All tickets across orgs |
| `support_admin` | Support admin | Full support portal |

## Database schema

| Table | Purpose |
|-------|---------|
| `organizations` | Client accounts |
| `profiles` | User profiles linked to auth.users |
| `tickets` | Support/change tickets |
| `ticket_comments` | Comments per ticket |
| `ticket_events` | Timeline activities |
| `invitations` | Pending team invitations |

## Security (RLS)

- Clients can only access data tied to their organization.
- Support roles can access all tickets and organizations.
- Invitations can only be created by a client_admin.
- Each organization is limited to 4 active members.

## Shared components

Use the shared services and UI components to keep the portals consistent:

### UI Components

Functions include:
- `UIComponents.showToast(message, type)`
- `UIComponents.showLoading(container, message)`
- `UIComponents.showEmptyState(container, options)`
- `UIComponents.createTicketListItem(ticket, options)`
- `UIComponents.createCommentItem(comment)`
- `UIComponents.createTimelineEvent(event)`
- `UIComponents.formatDate(dateString)`
- `UIComponents.confirm(message, title)`
- `UIComponents.setButtonLoading(button, loading)`

### Auth helpers

Use `AuthGuard.init({ requiredRoles, redirectTo })` on each protected page.

### Services

- Auth: `signUp`, `signUpWithInvitation`, `signIn`, `signOut`, `getProfile`.
- Tickets: `create`, `getById`, `list`, `getStats`, `updateStatus`, `assign`, `getSupportAgents`.
- Comments: `add`, `getByTicketId`, `getEventsByTicketId`, `getTimeline`.
- Invitations: `create`, `getByToken`, `list`, `getTeamMembers`.

## Routes

| Route | Purpose | Access |
|-------|---------|--------|
| `/client` | Client login/sign up | Public |
| `/client/dashboard` | Client dashboard | client_* |
| `/client/tickets` | Ticket list | client_* |
| `/client/tickets/new` | New ticket form | client_* |
| `/client/tickets/detail?id=X` | Ticket detail | client_* |
| `/client/settings/team` | Team management | client_* |
| `/invite?token=X` | Accept invitation | Public |
| `/support` | Support login | Public |
| `/support/dashboard` | Support dashboard | support_* |
| `/support/tickets` | Support ticket list | support_* |
| `/support/tickets/detail?id=X` | Support ticket actions | support_* |

## Styling

The ticket system shares the same CSS variables as the marketing site:

```css
:root {
  --color-black: #000000;
  --color-yellow: #ffe500;
  --color-white: #ffffff;
  --color-pink: #f6e8e3;
}
```

Components follow the dark card aesthetic with bright yellow buttons and colorful badges.
