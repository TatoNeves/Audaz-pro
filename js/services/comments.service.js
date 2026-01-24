/**
 * AUDAZ PRO - Comments Service
 *
 * Handles ticket comments and events (timeline)
 */

const CommentsService = {
    // ============================================
    // Add Comment
    // ============================================
    async add(ticketId, body) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('add_ticket_comment', {
                p_ticket_id: ticketId,
                p_body: body
            });

            if (error) {
                console.error('Add comment error:', error);
                return { success: false, error: 'Error adding comment' };
            }

            if (!data.success) {
                return { success: false, error: data.error || 'Error adding comment' };
            }

            return {
                success: true,
                commentId: data.comment_id
            };
        } catch (err) {
            console.error('Add comment error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Get Comments for Ticket
    // ============================================
    async getByTicketId(ticketId) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client
                .from('ticket_comments')
                .select(`
                    *,
                    author:profiles(id, full_name, role)
                `)
                .eq('ticket_id', ticketId)
                .order('created_at', { ascending: true });

            if (error) {
                console.error('Get comments error:', error);
                return { success: false, error: 'Error fetching comments' };
            }

            return {
                success: true,
                comments: data || []
            };
        } catch (err) {
            console.error('Get comments error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Get Events/Timeline for Ticket
    // ============================================
    async getEventsByTicketId(ticketId) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client
                .from('ticket_events')
                .select(`
                    *,
                    actor:profiles(id, full_name, role)
                `)
                .eq('ticket_id', ticketId)
                .order('created_at', { ascending: true });

            if (error) {
                console.error('Get events error:', error);
                return { success: false, error: 'Error fetching history' };
            }

            const events = (data || []).map(event => ({
                ...event,
                data: event.payload || {}
            }));

            return {
                success: true,
                events
            };
        } catch (err) {
            console.error('Get events error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Get Combined Timeline (Comments + Events)
    // ============================================
    async getTimeline(ticketId) {
        const [commentsResult, eventsResult] = await Promise.all([
            this.getByTicketId(ticketId),
            this.getEventsByTicketId(ticketId)
        ]);

        if (!commentsResult.success || !eventsResult.success) {
            return {
                success: false,
                error: commentsResult.error || eventsResult.error
            };
        }

        // Combine and sort by date
        const timeline = [
            ...commentsResult.comments.map(c => ({
                type: 'comment',
                id: c.id,
                created_at: c.created_at,
                actor: c.author,
                data: { body: c.body }
            })),
            ...eventsResult.events.map(e => ({
                type: 'event',
                id: e.id,
                created_at: e.created_at,
                actor: e.actor,
                event_type: e.event_type,
                data: e.payload
            }))
        ].sort((a, b) => new Date(a.created_at) - new Date(b.created_at));

        return {
            success: true,
            timeline
        };
    },

    // ============================================
    // Format Event for Display
    // ============================================
    formatEvent(event) {
        const actorName = event.actor?.full_name || 'System';
        const data = event.data || {};

        switch (event.event_type) {
            case 'created':
                return `${actorName} created the ticket`;

            case 'status_changed':
                const fromStatus = this.translateStatus(data.from);
                const toStatus = this.translateStatus(data.to);
                return `${actorName} changed the status from "${fromStatus}" to "${toStatus}"`;

            case 'assigned':
                const assigneeName = data.assignee_name || 'user';
                return `${actorName} assigned the ticket to ${assigneeName}`;

            case 'priority_changed':
                const fromPriority = this.translatePriority(data.from);
                const toPriority = this.translatePriority(data.to);
                return `${actorName} changed the priority from "${fromPriority}" to "${toPriority}"`;

            case 'commented':
                return `${actorName} added a comment`;

            default:
                return `${actorName} performed an action`;
        }
    },

    // ============================================
    // Translation Helpers
    // ============================================
    translateStatus(status) {
        const translations = {
            'open': 'Open',
            'in_progress': 'In Progress',
            'done': 'Done'
        };
        return translations[status] || status;
    },

    translatePriority(priority) {
        const translations = {
            'baixa': 'Low',
            'media': 'Medium',
            'alta': 'High',
            'urgente': 'Urgent'
        };
        return translations[priority] || priority;
    }
};

// Export
window.CommentsService = CommentsService;
