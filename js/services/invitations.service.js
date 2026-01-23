/**
 * AUDAZ PRO - Invitations Service
 *
 * Handles team invitations management
 */

const InvitationsService = {
    // ============================================
    // Create Invitation
    // ============================================
    async create(email, role = 'client_user') {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('create_invitation', {
                p_email: email,
                p_role: role
            });

            if (error) {
                console.error('Create invitation error:', error);
                return { success: false, error: 'Error creating invitation' };
            }

            if (!data.success) {
                return { success: false, error: data.error || 'Error creating invitation' };
            }

            return {
                success: true,
                invitationId: data.invitation_id,
                token: data.token,
                expiresAt: data.expires_at,
                inviteUrl: `${window.location.origin}/invite/index.html?token=${data.token}`
            };
        } catch (err) {
            console.error('Create invitation error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Get Invitation by Token (public)
    // ============================================
    async getByToken(token) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.rpc('get_invitation_by_token', {
                p_token: token
            });

            if (error) {
                console.error('Get invitation error:', error);
                return { success: false, error: 'Error fetching invitation' };
            }

            if (!data.success) {
                return { success: false, error: data.error || 'Invitation not found' };
            }

            return {
                success: true,
                invitation: {
                    email: data.email,
                    orgName: data.org_name,
                    role: data.role,
                    expiresAt: data.expires_at
                }
            };
        } catch (err) {
            console.error('Get invitation error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // List Invitations for Current Org
    // ============================================
    async list() {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client
                .from('invitations')
                .select(`
                    *,
                    created_by_profile:profiles!invitations_created_by_fkey(id, full_name)
                `)
                .order('created_at', { ascending: false });

            if (error) {
                console.error('List invitations error:', error);
                return { success: false, error: 'Error fetching invitations' };
            }

            // Add status to each invitation
            const invitations = (data || []).map(inv => ({
                ...inv,
                status: this.getInvitationStatus(inv)
            }));

            return {
                success: true,
                invitations
            };
        } catch (err) {
            console.error('List invitations error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Get Team Members for Current Org
    // ============================================
    async getTeamMembers() {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            // First get current user's org_id
            const profileResult = await AuthService.getProfile();
            if (!profileResult.success) {
                return { success: false, error: 'Error fetching profile' };
            }

            const orgId = profileResult.profile.org_id;

            const { data, error } = await client
                .from('profiles')
                .select('*')
                .eq('org_id', orgId)
                .order('created_at');

            if (error) {
                console.error('Get team members error:', error);
                return { success: false, error: 'Error fetching members' };
            }

            return {
                success: true,
                members: data || []
            };
        } catch (err) {
            console.error('Get team members error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Get Invitation Status
    // ============================================
    getInvitationStatus(invitation) {
        if (invitation.accepted_at) {
            return 'accepted';
        }
        if (new Date(invitation.expires_at) < new Date()) {
            return 'expired';
        }
        return 'pending';
    },

    // ============================================
    // Format Role for Display
    // ============================================
    formatRole(role) {
        const translations = {
            'client_admin': 'Administrator',
            'client_user': 'User',
            'support_agent': 'Support Agent',
            'support_admin': 'Support Admin'
        };
        return translations[role] || role;
    }
};

// Export
window.InvitationsService = InvitationsService;
