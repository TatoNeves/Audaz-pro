/**
 * AUDAZ PRO - Collaborators Service
 *
 * Handles ticket collaborator operations
 */

const CollaboratorsService = {
    // ============================================
    // Get Collaborators for a Ticket
    // ============================================
    async getByTicketId(ticketId) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('get_ticket_collaborators', {
                p_ticket_id: ticketId
            });

            if (error) {
                console.error('Get collaborators error:', error);
                return { success: false, error: 'Error fetching collaborators' };
            }

            if (!data.success) {
                return { success: false, error: data.error || 'Error fetching collaborators' };
            }

            return {
                success: true,
                collaborators: data.collaborators || []
            };
        } catch (err) {
            console.error('Get collaborators error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Add Collaborator
    // ============================================
    async add(ticketId, userId, role = 'manual') {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('add_ticket_collaborator', {
                p_ticket_id: ticketId,
                p_user_id: userId,
                p_role: role
            });

            if (error) {
                console.error('Add collaborator error:', error);
                return { success: false, error: 'Error adding collaborator' };
            }

            if (!data.success) {
                return { success: false, error: data.error || 'Error adding collaborator' };
            }

            return {
                success: true,
                collaboratorId: data.collaborator_id
            };
        } catch (err) {
            console.error('Add collaborator error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Remove Collaborator
    // ============================================
    async remove(ticketId, userId) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('remove_ticket_collaborator', {
                p_ticket_id: ticketId,
                p_user_id: userId
            });

            if (error) {
                console.error('Remove collaborator error:', error);
                return { success: false, error: 'Error removing collaborator' };
            }

            if (!data.success) {
                return { success: false, error: data.error || 'Error removing collaborator' };
            }

            return { success: true };
        } catch (err) {
            console.error('Remove collaborator error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    }
};

// Export
window.CollaboratorsService = CollaboratorsService;
