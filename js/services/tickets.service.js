/**
 * AUDAZ PRO - Tickets Service
 *
 * Handles all ticket-related CRUD operations
 */

const TicketsService = {
    // ============================================
    // Create Ticket
    // ============================================
    async create(ticketData) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('create_ticket', {
                p_type: ticketData.type,
                p_title: ticketData.title,
                p_description: ticketData.description,
                p_priority: ticketData.priority,
                p_category: ticketData.category || null,
                p_attachment_url: ticketData.attachment_url || null
            });

            if (error) {
                console.error('Create ticket error:', error);
                return { success: false, error: 'Error creating ticket' };
            }

            if (!data.success) {
                return {
                    success: false,
                    error: data.error || 'Error creating ticket',
                    limit_reached: data.limit_reached || false,
                    limit: data.limit,
                    used: data.used
                };
            }

            return {
                success: true,
                ticketId: data.ticket_id
            };
        } catch (err) {
            console.error('Create ticket error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Get Ticket by ID
    // ============================================
    async getById(ticketId) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client
                .from('tickets')
                .select(`
                    *,
                    creator:profiles!tickets_created_by_fkey(id, full_name, role),
                    assignee:profiles!tickets_assigned_to_fkey(id, full_name, role),
                    organization:organizations(id, name)
                `)
                .eq('id', ticketId)
                .single();

            if (error) {
                console.error('Get ticket error:', error);
                return { success: false, error: 'Ticket not found' };
            }

            return {
                success: true,
                ticket: data
            };
        } catch (err) {
            console.error('Get ticket error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // List Tickets with Filters
    // ============================================
    async list(filters = {}) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            let query = client
                .from('tickets')
                .select(`
                    *,
                    creator:profiles!tickets_created_by_fkey(id, full_name, role),
                    assignee:profiles!tickets_assigned_to_fkey(id, full_name, role),
                    organization:organizations(id, name)
                `)
                .order('last_activity_at', { ascending: false });

            // Apply filters
            if (filters.status) {
                query = query.eq('status', filters.status);
            }

            if (filters.type) {
                query = query.eq('type', filters.type);
            }

            if (filters.priority) {
                query = query.eq('priority', filters.priority);
            }

            if (filters.org_id) {
                query = query.eq('org_id', filters.org_id);
            }

            if (filters.assigned_to) {
                query = query.eq('assigned_to', filters.assigned_to);
            }

            if (filters.search) {
                query = query.or(`title.ilike.%${filters.search}%,description.ilike.%${filters.search}%`);
            }

            // Pagination
            if (filters.limit) {
                query = query.limit(filters.limit);
            }

            if (filters.offset) {
                query = query.range(filters.offset, filters.offset + (filters.limit || 10) - 1);
            }

            const { data, error, count } = await query;

            if (error) {
                console.error('List tickets error:', error);
                return { success: false, error: 'Error fetching tickets' };
            }

            return {
                success: true,
                tickets: data || [],
                count
            };
        } catch (err) {
            console.error('List tickets error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Get Recent Tickets (for dashboard)
    // ============================================
    async getRecent(limit = 5) {
        return this.list({ limit });
    },

    // ============================================
    // Get Ticket Stats
    // ============================================
    async getStats(orgId = null) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('get_ticket_stats', {
                p_org_id: orgId
            });

            if (error) {
                console.error('Get stats error:', error);
                return { success: false, error: 'Error fetching statistics' };
            }

            if (!data.success) {
                return { success: false, error: data.error || 'Error fetching statistics' };
            }

            return {
                success: true,
                stats: {
                    open: data.open,
                    in_progress: data.in_progress,
                    done: data.done,
                    total: data.total
                }
            };
        } catch (err) {
            console.error('Get stats error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Update Ticket Status
    // ============================================
    async updateStatus(ticketId, status) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('update_ticket_status', {
                p_ticket_id: ticketId,
                p_status: status
            });

            if (error) {
                console.error('Update status error:', error);
                return { success: false, error: 'Error updating status' };
            }

            if (!data.success) {
                return { success: false, error: data.error || 'Error updating status' };
            }

            return { success: true };
        } catch (err) {
            console.error('Update status error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Assign Ticket
    // ============================================
    async assign(ticketId, assigneeId) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('assign_ticket', {
                p_ticket_id: ticketId,
                p_assignee_id: assigneeId
            });

            if (error) {
                console.error('Assign ticket error:', error);
                return { success: false, error: 'Error assigning ticket' };
            }

            if (!data.success) {
                return { success: false, error: data.error || 'Error assigning ticket' };
            }

            return { success: true };
        } catch (err) {
            console.error('Assign ticket error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Get Support Agents (for assignment dropdown)
    // ============================================
    async getSupportAgents() {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client
                .from('profiles')
                .select('id, full_name, role')
                .in('role', ['support_agent', 'support_admin'])
                .order('full_name');

            if (error) {
                console.error('Get agents error:', error);
                return { success: false, error: 'Error fetching agents' };
            }

            return {
                success: true,
                agents: data || []
            };
        } catch (err) {
            console.error('Get agents error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    async getOrganizationMembers(orgId) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        if (!orgId) {
            return { success: false, error: 'Invalid organization' };
        }

        try {
            const { data, error } = await client
                .from('profiles')
                .select('id, full_name, role')
                .eq('org_id', orgId)
                .order('full_name');

            if (error) {
                console.error('Get organization members error:', error);
                return { success: false, error: 'Error fetching members' };
            }

            return {
                success: true,
                members: data || []
            };
        } catch (err) {
            console.error('Get organization members error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Get All Organizations (for support filters)
    // ============================================
    async getOrganizations() {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client
                .from('organizations')
                .select('id, name')
                .order('name');

            if (error) {
                console.error('Get organizations error:', error);
                return { success: false, error: 'Error fetching organizations' };
            }

            return {
                success: true,
                organizations: data || []
            };
        } catch (err) {
            console.error('Get organizations error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Get Organization Monthly Usage
    // ============================================
    async getMonthlyUsage(orgId) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('get_org_monthly_usage', {
                p_org_id: orgId
            });

            if (error) {
                console.error('Get monthly usage error:', error);
                return { success: false, error: 'Error fetching usage' };
            }

            if (data && data.length > 0) {
                return {
                    success: true,
                    usage: {
                        limit: data[0].monthly_limit,
                        used: data[0].tickets_used,
                        remaining: data[0].tickets_remaining,
                        month: data[0].current_month,
                        planName: data[0].plan_name,
                        extra_tasks: data[0].extra_tasks || 0
                    }
                };
            }

            return {
                success: true,
                usage: {
                    limit: 10,
                    used: 0,
                    remaining: 10,
                    month: new Date().toISOString().slice(0, 7),
                    planName: 'Basic',
                    extra_tasks: 0
                }
            };
        } catch (err) {
            console.error('Get monthly usage error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Check if Organization Can Create Ticket
    // ============================================
    async canCreateTicket(orgId) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('can_create_ticket', {
                p_org_id: orgId
            });

            if (error) {
                console.error('Can create ticket error:', error);
                return { success: false, error: 'Error checking limit' };
            }

            return {
                success: true,
                allowed: data.allowed,
                reason: data.reason || null,
                limit: data.limit,
                used: data.used,
                remaining: data.remaining || 0
            };
        } catch (err) {
            console.error('Can create ticket error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Cancel Ticket (Client)
    // ============================================
    async cancel(ticketId) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            // Update status to cancelled
            const { data, error } = await client
                .from('tickets')
                .update({
                    status: 'cancelled',
                    updated_at: new Date().toISOString(),
                    last_activity_at: new Date().toISOString()
                })
                .eq('id', ticketId)
                .select()
                .single();

            if (error) {
                console.error('Cancel ticket error:', error);
                return { success: false, error: 'Error cancelling ticket' };
            }

            // Log the event
            await client.from('ticket_events').insert({
                ticket_id: ticketId,
                event_type: 'status_changed',
                old_value: null,
                new_value: 'cancelled'
            });

            return { success: true, ticket: data };
        } catch (err) {
            console.error('Cancel ticket error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Delete Ticket (Client)
    // ============================================
    async delete(ticketId) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            // First delete related records
            await client.from('ticket_events').delete().eq('ticket_id', ticketId);
            await client.from('comments').delete().eq('ticket_id', ticketId);
            await client.from('ticket_collaborators').delete().eq('ticket_id', ticketId);

            // Then delete the ticket
            const { error } = await client
                .from('tickets')
                .delete()
                .eq('id', ticketId);

            if (error) {
                console.error('Delete ticket error:', error);
                return { success: false, error: 'Error deleting ticket' };
            }

            return { success: true };
        } catch (err) {
            console.error('Delete ticket error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    }
};

// Export
window.TicketsService = TicketsService;
