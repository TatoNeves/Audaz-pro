import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform",
};

interface InviteEmailRequest {
  to: string;
  inviteUrl: string;
  orgName: string;
  role: string;
  expiresAt: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { to, inviteUrl, orgName, role, expiresAt }: InviteEmailRequest = await req.json();

    // Validate inputs
    if (!to || !inviteUrl || !orgName) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing required fields" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const roleDisplay = role === "client_admin" ? "Administrator" : "User";
    const expiresDate = new Date(expiresAt).toLocaleDateString("en-US", {
      day: "2-digit",
      month: "long",
      year: "numeric",
    });

    const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Audaz Pro Invitation</title>
  <style>
    body {
      background-color: #f5f5f5;
      color: #111111;
      margin: 0;
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    }

    .email-card {
      background-color: #ffffff;
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 4px 16px rgba(15, 15, 15, 0.15);
    }

    .email-content {
      color: #111111;
    }

    .email-button {
      background-color: #000000;
      color: #ffffff;
    }

    @media (prefers-color-scheme: dark) {
      body {
        background-color: #000000;
        color: #f5f5f5;
      }

      .email-card {
        background-color: #111111;
        box-shadow: 0 6px 20px rgba(255, 255, 255, 0.08);
      }

      .email-content {
        color: #f5f5f5;
      }

      .email-button {
        background-color: #ffffff;
        color: #000000;
      }
    }
  </style>
</head>
<body class="email-body" style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f5f5f5; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table role="presentation" width="600" cellspacing="0" cellpadding="0" class="email-card" style="border-radius: 12px; overflow: hidden;">
          <!-- Header -->
          <tr>
            <td style="background-color: #000000; padding: 30px; text-align: center;">
              <img src="https://audaz-pro-5lkci.ondigitalocean.app/images/66943b1c1348ffa2b811c19c_Audaz%20Black.png" alt="Audaz Pro" style="max-width: 180px; height: auto;">
            </td>
          </tr>

          <!-- Content -->
          <tr>
            <td class="email-content" style="padding: 40px 30px;">
              <h2 style="color: #333333; margin: 0 0 20px; font-size: 24px;">You've been invited!</h2>

              <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
                You have received an invitation to join the organization <strong style="color: #333333;">${orgName}</strong> on Audaz Pro.
              </p>

              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f8f9fa; border-radius: 8px; margin: 20px 0;">
                <tr>
                  <td style="padding: 20px;">
                    <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                      <strong style="color: #333333;">Organization:</strong> ${orgName}
                    </p>
                    <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                      <strong style="color: #333333;">Role:</strong> ${roleDisplay}
                    </p>
                    <p style="margin: 0; color: #666666; font-size: 14px;">
                      <strong style="color: #333333;">Valid until:</strong> ${expiresDate}
                    </p>
                  </td>
                </tr>
              </table>

              <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 30px;">
                Click the button below to accept the invitation and create your account:
              </p>

              <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                <tr>
                  <td align="center">
                    <a class="email-button" href="${inviteUrl}" style="display: inline-block; background-color: #000000; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600;">
                      Accept Invitation
                    </a>
                  </td>
                </tr>
              </table>

              <p style="color: #999999; font-size: 14px; line-height: 1.6; margin: 30px 0 0;">
                If the button doesn't work, copy and paste this link into your browser:<br>
                <a href="${inviteUrl}" style="color: #666666; word-break: break-all;">${inviteUrl}</a>
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color: #f8f9fa; padding: 20px 30px; text-align: center; border-top: 1px solid #eeeeee;">
              <p style="color: #999999; font-size: 12px; margin: 0;">
                © ${new Date().getFullYear()} Audaz Pro. All rights reserved.
              </p>
              <p style="color: #999999; font-size: 12px; margin: 10px 0 0;">
                This email was sent because someone invited you to Audaz Pro.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
    `;

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: "Audaz Pro <noreply@audazpro.ca>",
        to: [to],
        subject: `Invitation to ${orgName} - Audaz Pro`,
        html: html,
      }),
    });

    const data = await res.json();

    if (!res.ok) {
      console.error("Resend error:", data);
      return new Response(
        JSON.stringify({ success: false, error: data.message || "Failed to send email" }),
        { status: res.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, messageId: data.id }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
