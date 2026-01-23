/**
 * AUDAZ PRO - Email Service
 *
 * Handles email sending via Supabase Edge Functions + Resend
 */

const EmailService = {
    // Supabase Edge Function URLs
    FUNCTIONS_URL: null,

    // Initialize with Supabase project URL
    init() {
        const client = AudazSupabase.getClient();
        if (client) {
            // Get the Supabase URL from the client
            const supabaseUrl = client.supabaseUrl || 'https://jliqlisrnuusqxiswfcg.supabase.co';
            this.FUNCTIONS_URL = `${supabaseUrl}/functions/v1`;
        }
    },

    // Get auth headers for Edge Functions
    async getHeaders() {
        const client = AudazSupabase.getClient();
        if (!client) return {};

        const { data: { session } } = await client.auth.getSession();
        return {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${session?.access_token || ''}`,
        };
    },

    // ============================================
    // SEND INVITE EMAIL
    // ============================================
    async sendInviteEmail({ to, inviteUrl, orgName, role, expiresAt }) {
        if (!this.FUNCTIONS_URL) this.init();

        try {
            const headers = await this.getHeaders();
            const response = await fetch(`${this.FUNCTIONS_URL}/send-invite-email`, {
                method: 'POST',
                headers,
                body: JSON.stringify({
                    to,
                    inviteUrl,
                    orgName,
                    role,
                    expiresAt
                })
            });

            const data = await response.json();

            if (!response.ok) {
                console.error('Send invite email error:', data);
                return { success: false, error: data.error || 'Failed to send email' };
            }

            return { success: true, messageId: data.messageId };
        } catch (error) {
            console.error('Send invite email error:', error);
            return { success: false, error: error.message };
        }
    },

    // ============================================
    // SEND TICKET NOTIFICATION
    // ============================================
    async sendTicketNotification({
        type,
        to,
        ticketId,
        ticketTitle,
        ticketType,
        orgName,
        ticketUrl,
        // Optional fields
        createdBy,
        oldStatus,
        newStatus,
        assignedTo,
        assignedBy,
        commentBy,
        commentPreview,
        oldPriority,
        newPriority
    }) {
        if (!this.FUNCTIONS_URL) this.init();

        try {
            const headers = await this.getHeaders();
            const response = await fetch(`${this.FUNCTIONS_URL}/ticket-notification`, {
                method: 'POST',
                headers,
                body: JSON.stringify({
                    type,
                    to: Array.isArray(to) ? to : [to],
                    ticketId,
                    ticketTitle,
                    ticketType,
                    orgName,
                    ticketUrl,
                    createdBy,
                    oldStatus,
                    newStatus,
                    assignedTo,
                    assignedBy,
                    commentBy,
                    commentPreview,
                    oldPriority,
                    newPriority
                })
            });

            const data = await response.json();

            if (!response.ok) {
                console.error('Send ticket notification error:', data);
                return { success: false, error: data.error || 'Failed to send notification' };
            }

            return { success: true, messageId: data.messageId };
        } catch (error) {
            console.error('Send ticket notification error:', error);
            return { success: false, error: error.message };
        }
    },

    // ============================================
    // HELPER: Notify on Ticket Created
    // ============================================
    async notifyTicketCreated({ ticket, createdBy, supportEmails, orgName }) {
        const ticketUrl = `${window.location.origin}/support/tickets/detail.html?id=${ticket.id}`;

        return this.sendTicketNotification({
            type: 'ticket_created',
            to: supportEmails,
            ticketId: ticket.id,
            ticketTitle: ticket.title,
            ticketType: ticket.type,
            orgName,
            ticketUrl,
            createdBy
        });
    },

    // ============================================
    // HELPER: Notify on Status Change
    // ============================================
    async notifyStatusChanged({ ticket, oldStatus, newStatus, notifyEmails, orgName }) {
        const ticketUrl = `${window.location.origin}/client/tickets/detail.html?id=${ticket.id}`;

        return this.sendTicketNotification({
            type: 'ticket_status_changed',
            to: notifyEmails,
            ticketId: ticket.id,
            ticketTitle: ticket.title,
            orgName,
            ticketUrl,
            oldStatus,
            newStatus
        });
    },

    // ============================================
    // HELPER: Notify on Assignment
    // ============================================
    async notifyAssignment({ ticket, assignedToEmail, assignedBy, orgName }) {
        const ticketUrl = `${window.location.origin}/support/tickets/detail.html?id=${ticket.id}`;

        return this.sendTicketNotification({
            type: 'ticket_assigned',
            to: [assignedToEmail],
            ticketId: ticket.id,
            ticketTitle: ticket.title,
            orgName,
            ticketUrl,
            assignedBy
        });
    },

    // ============================================
    // HELPER: Notify on New Comment
    // ============================================
    async notifyNewComment({ ticket, commentBy, commentPreview, notifyEmails, orgName, isSupport }) {
        const basePath = isSupport ? '/support/tickets' : '/client/tickets';
        const ticketUrl = `${window.location.origin}${basePath}/detail.html?id=${ticket.id}`;

        return this.sendTicketNotification({
            type: 'ticket_comment',
            to: notifyEmails,
            ticketId: ticket.id,
            ticketTitle: ticket.title,
            orgName,
            ticketUrl,
            commentBy,
            commentPreview: commentPreview.substring(0, 200) + (commentPreview.length > 200 ? '...' : '')
        });
    },

    // ============================================
    // HELPER: Notify on Priority Change
    // ============================================
    async notifyPriorityChanged({ ticket, oldPriority, newPriority, notifyEmails, orgName }) {
        const ticketUrl = `${window.location.origin}/client/tickets/detail.html?id=${ticket.id}`;

        return this.sendTicketNotification({
            type: 'ticket_priority_changed',
            to: notifyEmails,
            ticketId: ticket.id,
            ticketTitle: ticket.title,
            orgName,
            ticketUrl,
            oldPriority,
            newPriority
        });
    }
};

// Export
window.EmailService = EmailService;
