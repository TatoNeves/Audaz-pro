import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform",
};

type NotificationType =
  | "ticket_created"
  | "ticket_status_changed"
  | "ticket_assigned"
  | "ticket_comment"
  | "ticket_priority_changed";

interface NotificationRequest {
  type: NotificationType;
  to: string[];
  ticketId: string;
  ticketTitle: string;
  ticketType?: string;
  orgName: string;
  // Optional fields based on notification type
  createdBy?: string;
  oldStatus?: string;
  newStatus?: string;
  assignedTo?: string;
  assignedBy?: string;
  commentBy?: string;
  commentPreview?: string;
  oldPriority?: string;
  newPriority?: string;
  ticketUrl?: string;
}

const statusLabels: Record<string, string> = {
  open: "Open",
  in_progress: "In Progress",
  done: "Done",
};

const priorityLabels: Record<string, string> = {
  baixa: "Low",
  media: "Medium",
  alta: "High",
  low: "Low",
  medium: "Medium",
  high: "High",
};

const typeLabels: Record<string, string> = {
  alteracao: "Change Request",
  suporte: "Support",
  change: "Change Request",
  support: "Support",
};

function getSubject(type: NotificationType, ticketTitle: string): string {
  const subjects: Record<NotificationType, string> = {
    ticket_created: `New Ticket: ${ticketTitle}`,
    ticket_status_changed: `Status Updated: ${ticketTitle}`,
    ticket_assigned: `Ticket Assigned: ${ticketTitle}`,
    ticket_comment: `New Comment: ${ticketTitle}`,
    ticket_priority_changed: `Priority Changed: ${ticketTitle}`,
  };
  return subjects[type];
}

const emailStyles = `
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

      .email-meta {
        color: rgba(255, 255, 255, 0.75);
      }
    }
  </style>
`;

function generateEmailContent(data: NotificationRequest): string {
  const { type, ticketTitle, ticketType, orgName, ticketUrl } = data;

  let contentHtml = "";
  let headerColor = "#000000";
  let headerText = "Notification";

  switch (type) {
    case "ticket_created":
      headerText = "New Ticket Created";
      headerColor = "#22c55e";
      contentHtml = `
        <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
          A new ticket was created by <strong>${data.createdBy}</strong>:
        </p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f8f9fa; border-radius: 8px; margin: 20px 0;">
          <tr>
            <td style="padding: 20px;">
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Title:</strong> ${ticketTitle}
              </p>
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Type:</strong> ${typeLabels[ticketType || ""] || ticketType}
              </p>
              <p style="margin: 0; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Organization:</strong> ${orgName}
              </p>
            </td>
          </tr>
        </table>
      `;
      break;

    case "ticket_status_changed":
      headerText = "Status Updated";
      headerColor = "#3b82f6";
      contentHtml = `
        <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
          The ticket status has been updated:
        </p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f8f9fa; border-radius: 8px; margin: 20px 0;">
          <tr>
            <td style="padding: 20px;">
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Ticket:</strong> ${ticketTitle}
              </p>
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Previous Status:</strong> ${statusLabels[data.oldStatus || ""] || data.oldStatus}
              </p>
              <p style="margin: 0; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">New Status:</strong>
                <span style="background-color: #22c55e; color: white; padding: 2px 8px; border-radius: 4px; font-size: 12px;">
                  ${statusLabels[data.newStatus || ""] || data.newStatus}
                </span>
              </p>
            </td>
          </tr>
        </table>
      `;
      break;

    case "ticket_assigned":
      headerText = "Ticket Assigned";
      headerColor = "#8b5cf6";
      contentHtml = `
        <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
          A ticket has been assigned to you:
        </p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f8f9fa; border-radius: 8px; margin: 20px 0;">
          <tr>
            <td style="padding: 20px;">
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Ticket:</strong> ${ticketTitle}
              </p>
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Assigned by:</strong> ${data.assignedBy}
              </p>
              <p style="margin: 0; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Organization:</strong> ${orgName}
              </p>
            </td>
          </tr>
        </table>
      `;
      break;

    case "ticket_comment":
      headerText = "New Comment";
      headerColor = "#f59e0b";
      contentHtml = `
        <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
          <strong>${data.commentBy}</strong> added a comment:
        </p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f8f9fa; border-radius: 8px; margin: 20px 0;">
          <tr>
            <td style="padding: 20px;">
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Ticket:</strong> ${ticketTitle}
              </p>
              <p style="margin: 0; color: #666666; font-size: 14px; font-style: italic; border-left: 3px solid #ddd; padding-left: 15px;">
                "${data.commentPreview}"
              </p>
            </td>
          </tr>
        </table>
      `;
      break;

    case "ticket_priority_changed":
      headerText = "Priority Changed";
      headerColor = "#ef4444";
      contentHtml = `
        <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
          The ticket priority has been changed:
        </p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f8f9fa; border-radius: 8px; margin: 20px 0;">
          <tr>
            <td style="padding: 20px;">
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Ticket:</strong> ${ticketTitle}
              </p>
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Previous Priority:</strong> ${priorityLabels[data.oldPriority || ""] || data.oldPriority}
              </p>
              <p style="margin: 0; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">New Priority:</strong>
                <span style="background-color: ${data.newPriority === 'alta' || data.newPriority === 'high' ? '#ef4444' : data.newPriority === 'media' || data.newPriority === 'medium' ? '#f59e0b' : '#22c55e'}; color: white; padding: 2px 8px; border-radius: 4px; font-size: 12px;">
                  ${priorityLabels[data.newPriority || ""] || data.newPriority}
                </span>
              </p>
            </td>
          </tr>
        </table>
      `;
      break;
  }

  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${headerText} - Audaz Pro</title>
  ${emailStyles}
  </head>
<body class="email-body" style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f5f5f5; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table role="presentation" width="600" cellspacing="0" cellpadding="0" class="email-card" style="border-radius: 12px; overflow: hidden;">
          <!-- Header -->
          <tr>
            <td style="background-color: ${headerColor}; padding: 30px; text-align: center;">
              <h1 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: bold;">${headerText}</h1>
              <p style="color: rgba(255,255,255,0.8); margin: 10px 0 0; font-size: 14px;">Audaz Pro</p>
            </td>
          </tr>

          <!-- Content -->
          <tr>
            <td class="email-content" style="padding: 40px 30px;">
              ${contentHtml}

              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top: 30px;">
                <tr>
                  <td align="center">
                    <a class="email-button" href="${ticketUrl}" style="display: inline-block; background-color: #000000; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600;">
                      View Ticket
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color: #f8f9fa; padding: 20px 30px; text-align: center; border-top: 1px solid #eeeeee;">
              <p style="color: #999999; font-size: 12px; margin: 0;">
                © ${new Date().getFullYear()} Audaz Pro. All rights reserved.
              </p>
              <p style="color: #999999; font-size: 12px; margin: 10px 0 0;">
                You are receiving this email because you are part of ${orgName}.
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
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const data: NotificationRequest = await req.json();

    // Validate inputs
    if (!data.to || data.to.length === 0 || !data.ticketTitle || !data.type) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing required fields" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const subject = getSubject(data.type, data.ticketTitle);
    const html = generateEmailContent(data);

    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: "Audaz Pro <noreply@audazpro.ca>",
        to: data.to,
        subject: subject,
        html: html,
      }),
    });

    const resData = await res.json();

    if (!res.ok) {
      console.error("Resend error:", resData);
      return new Response(
        JSON.stringify({ success: false, error: resData.message || "Failed to send email" }),
        { status: res.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, messageId: resData.id }),
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
