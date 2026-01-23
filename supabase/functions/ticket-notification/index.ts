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

const statusTranslations: Record<string, string> = {
  open: "Aberto",
  in_progress: "Em Progresso",
  done: "Concluído",
};

const priorityTranslations: Record<string, string> = {
  baixa: "Baixa",
  media: "Média",
  alta: "Alta",
};

const typeTranslations: Record<string, string> = {
  alteracao: "Alteração",
  suporte: "Suporte",
};

function getSubject(type: NotificationType, ticketTitle: string): string {
  const subjects: Record<NotificationType, string> = {
    ticket_created: `Novo Ticket: ${ticketTitle}`,
    ticket_status_changed: `Status Atualizado: ${ticketTitle}`,
    ticket_assigned: `Ticket Atribuído: ${ticketTitle}`,
    ticket_comment: `Novo Comentário: ${ticketTitle}`,
    ticket_priority_changed: `Prioridade Alterada: ${ticketTitle}`,
  };
  return subjects[type];
}

function generateEmailContent(data: NotificationRequest): string {
  const { type, ticketTitle, ticketType, orgName, ticketUrl } = data;

  let contentHtml = "";
  let headerColor = "#000000";
  let headerText = "Notificação";

  switch (type) {
    case "ticket_created":
      headerText = "Novo Ticket Criado";
      headerColor = "#22c55e";
      contentHtml = `
        <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
          Um novo ticket foi criado por <strong>${data.createdBy}</strong>:
        </p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f8f9fa; border-radius: 8px; margin: 20px 0;">
          <tr>
            <td style="padding: 20px;">
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Título:</strong> ${ticketTitle}
              </p>
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Tipo:</strong> ${typeTranslations[ticketType || ""] || ticketType}
              </p>
              <p style="margin: 0; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Organização:</strong> ${orgName}
              </p>
            </td>
          </tr>
        </table>
      `;
      break;

    case "ticket_status_changed":
      headerText = "Status Atualizado";
      headerColor = "#3b82f6";
      contentHtml = `
        <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
          O status do ticket foi atualizado:
        </p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f8f9fa; border-radius: 8px; margin: 20px 0;">
          <tr>
            <td style="padding: 20px;">
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Ticket:</strong> ${ticketTitle}
              </p>
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Status Anterior:</strong> ${statusTranslations[data.oldStatus || ""] || data.oldStatus}
              </p>
              <p style="margin: 0; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Novo Status:</strong>
                <span style="background-color: #22c55e; color: white; padding: 2px 8px; border-radius: 4px; font-size: 12px;">
                  ${statusTranslations[data.newStatus || ""] || data.newStatus}
                </span>
              </p>
            </td>
          </tr>
        </table>
      `;
      break;

    case "ticket_assigned":
      headerText = "Ticket Atribuído";
      headerColor = "#8b5cf6";
      contentHtml = `
        <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
          Um ticket foi atribuído a você:
        </p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f8f9fa; border-radius: 8px; margin: 20px 0;">
          <tr>
            <td style="padding: 20px;">
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Ticket:</strong> ${ticketTitle}
              </p>
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Atribuído por:</strong> ${data.assignedBy}
              </p>
              <p style="margin: 0; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Organização:</strong> ${orgName}
              </p>
            </td>
          </tr>
        </table>
      `;
      break;

    case "ticket_comment":
      headerText = "Novo Comentário";
      headerColor = "#f59e0b";
      contentHtml = `
        <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
          <strong>${data.commentBy}</strong> adicionou um comentário:
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
      headerText = "Prioridade Alterada";
      headerColor = "#ef4444";
      contentHtml = `
        <p style="color: #666666; font-size: 16px; line-height: 1.6; margin: 0 0 20px;">
          A prioridade do ticket foi alterada:
        </p>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f8f9fa; border-radius: 8px; margin: 20px 0;">
          <tr>
            <td style="padding: 20px;">
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Ticket:</strong> ${ticketTitle}
              </p>
              <p style="margin: 0 0 10px; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Prioridade Anterior:</strong> ${priorityTranslations[data.oldPriority || ""] || data.oldPriority}
              </p>
              <p style="margin: 0; color: #666666; font-size: 14px;">
                <strong style="color: #333333;">Nova Prioridade:</strong>
                <span style="background-color: ${data.newPriority === 'alta' ? '#ef4444' : data.newPriority === 'media' ? '#f59e0b' : '#22c55e'}; color: white; padding: 2px 8px; border-radius: 4px; font-size: 12px;">
                  ${priorityTranslations[data.newPriority || ""] || data.newPriority}
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
</head>
<body style="margin: 0; padding: 0; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f5f5f5;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #f5f5f5; padding: 40px 20px;">
    <tr>
      <td align="center">
        <table role="presentation" width="600" cellspacing="0" cellpadding="0" style="background-color: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">
          <!-- Header -->
          <tr>
            <td style="background-color: ${headerColor}; padding: 30px; text-align: center;">
              <h1 style="color: #ffffff; margin: 0; font-size: 24px; font-weight: bold;">${headerText}</h1>
              <p style="color: rgba(255,255,255,0.8); margin: 10px 0 0; font-size: 14px;">Audaz Pro</p>
            </td>
          </tr>

          <!-- Content -->
          <tr>
            <td style="padding: 40px 30px;">
              ${contentHtml}

              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top: 30px;">
                <tr>
                  <td align="center">
                    <a href="${ticketUrl}" style="display: inline-block; background-color: #000000; color: #ffffff; text-decoration: none; padding: 16px 40px; border-radius: 8px; font-size: 16px; font-weight: 600;">
                      Ver Ticket
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
                © ${new Date().getFullYear()} Audaz Pro. Todos os direitos reservados.
              </p>
              <p style="color: #999999; font-size: 12px; margin: 10px 0 0;">
                Você está recebendo este email porque faz parte de ${orgName}.
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
        from: "Audaz Pro <noreply@audazpro.com>",
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
