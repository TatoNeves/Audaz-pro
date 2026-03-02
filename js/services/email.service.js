/**
 * AUDAZ PRO - Email Service
 *
 * Handles email sending via Supabase Edge Functions + Resend
 */

const EmailService = {
    // ============================================
    // SEND INVITE EMAIL
    // ============================================
    async sendInviteEmail({ to, inviteUrl, orgName, role, expiresAt }) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.functions.invoke('send-invite-email', {
                body: {
                    to,
                    inviteUrl,
                    orgName,
                    role,
                    expiresAt
                }
            });

            if (error) {
                console.error('Send invite email error:', error);
                return { success: false, error: error.message || 'Failed to send email' };
            }

            if (data && !data.success) {
                console.error('Send invite email error:', data.error);
                return { success: false, error: data.error || 'Failed to send email' };
            }

            return { success: true, messageId: data?.messageId };
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
        const client = AudazSupabase.getClient();
        if (!client) {
            console.error('[EmailService] Supabase client not available');
            return { success: false, error: 'Supabase not configured' };
        }

        const payload = {
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
        };

        console.log('[EmailService] Sending notification:', JSON.stringify(payload, null, 2));

        try {
            const { data, error } = await client.functions.invoke('ticket-notification', {
                body: payload
            });

            console.log('[EmailService] Response:', { data, error });

            if (error) {
                console.error('[EmailService] Function invoke error:', error);
                return { success: false, error: error.message || 'Failed to send notification' };
            }

            if (data && !data.success) {
                console.error('[EmailService] Function returned error:', data.error);
                return { success: false, error: data.error || 'Failed to send notification' };
            }

            console.log('[EmailService] Notification sent successfully, messageId:', data?.messageId);
            return { success: true, messageId: data?.messageId };
        } catch (error) {
            console.error('[EmailService] Exception:', error);
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
