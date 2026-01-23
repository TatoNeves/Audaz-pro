/**
 * AUDAZ PRO - Authentication Service
 *
 * Handles all authentication operations using Supabase Auth
 */

const AuthService = {
    // ============================================
    // Sign Up (Create new account + organization)
    // ============================================
    async signUp(email, password, fullName, organizationName) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            // 1. Create auth user
            const { data: authData, error: authError } = await client.auth.signUp({
                email,
                password,
                options: {
                    data: {
                        full_name: fullName,
                        organization_name: organizationName
                    }
                }
            });

            if (authError) {
                return { success: false, error: this.translateError(authError.message) };
            }

            if (!authData.user) {
            return { success: false, error: 'Error creating user' };
            }

            // 2. Create organization and profile via RPC
            const { data: rpcData, error: rpcError } = await client.rpc('create_organization_on_signup', {
                p_user_id: authData.user.id,
                p_org_name: organizationName,
                p_full_name: fullName
            });

            if (rpcError) {
                console.error('RPC Error:', rpcError);
                return { success: false, error: 'Error creating organization' };
            }

            if (!rpcData.success) {
                return { success: false, error: rpcData.error || 'Error creating organization' };
            }

            return {
                success: true,
                user: authData.user,
                session: authData.session,
                orgId: rpcData.org_id,
                needsEmailConfirmation: !authData.session
            };
        } catch (err) {
            console.error('SignUp error:', err);
            return { success: false, error: 'Unexpected error creating account' };
        }
    },

    // ============================================
    // Sign Up via Invitation
    // ============================================
    async signUpWithInvitation(email, password, fullName, invitationToken) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            // 1. Validate invitation first
            const { data: inviteData, error: inviteError } = await client.rpc('get_invitation_by_token', {
                p_token: invitationToken
            });

            if (inviteError || !inviteData.success) {
                return { success: false, error: inviteData?.error || 'Invalid invitation' };
            }

            // Check if email matches invitation
            if (inviteData.email.toLowerCase() !== email.toLowerCase()) {
                return { success: false, error: 'Email does not match the invitation' };
            }

            // 2. Create auth user
            const { data: authData, error: authError } = await client.auth.signUp({
                email,
                password,
                options: {
                    data: {
                        full_name: fullName,
                        invitation_token: invitationToken
                    }
                }
            });

            if (authError) {
                return { success: false, error: this.translateError(authError.message) };
            }

            if (!authData.user) {
            return { success: false, error: 'Error creating user' };
            }

            // 3. Accept invitation via RPC
            const { data: rpcData, error: rpcError } = await client.rpc('accept_invitation', {
                p_token: invitationToken,
                p_user_id: authData.user.id,
                p_full_name: fullName
            });

            if (rpcError) {
                console.error('RPC Error:', rpcError);
                return { success: false, error: 'Error accepting invitation' };
            }

            if (!rpcData.success) {
                return { success: false, error: rpcData.error || 'Error accepting invitation' };
            }

            return {
                success: true,
                user: authData.user,
                session: authData.session,
                orgId: rpcData.org_id,
                role: rpcData.role,
                needsEmailConfirmation: !authData.session
            };
        } catch (err) {
            console.error('SignUp with invitation error:', err);
            return { success: false, error: 'Unexpected error creating account' };
        }
    },

    // ============================================
    // Sign In
    // ============================================
    async signIn(email, password) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { data, error } = await client.auth.signInWithPassword({
                email,
                password
            });

            if (error) {
                return { success: false, error: this.translateError(error.message) };
            }

            return {
                success: true,
                user: data.user,
                session: data.session
            };
        } catch (err) {
            console.error('SignIn error:', err);
            return { success: false, error: 'Unexpected error signing in' };
        }
    },

    // ============================================
    // Sign Out
    // ============================================
    async signOut() {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { error } = await client.auth.signOut();

            if (error) {
                return { success: false, error: this.translateError(error.message) };
            }

            return { success: true };
        } catch (err) {
            console.error('SignOut error:', err);
            return { success: false, error: 'Unexpected error signing out' };
        }
    },

    // ============================================
    // Get Current Profile
    // ============================================
    async getProfile() {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const user = await AudazSupabase.getCurrentUser();
            if (!user) {
                return { success: false, error: 'User not authenticated' };
            }

            const { data: profile, error } = await client
                .from('profiles')
                .select(`
                    *,
                    organization:organizations(*)
                `)
                .eq('id', user.id)
                .single();

            if (error) {
                console.error('Profile fetch error:', error);
                return { success: false, error: 'Error fetching profile' };
            }

            return {
                success: true,
                profile
            };
        } catch (err) {
            console.error('GetProfile error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Password Reset
    // ============================================
    async sendPasswordReset(email) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { error } = await client.auth.resetPasswordForEmail(email, {
                redirectTo: `${window.location.origin}/client/reset-password.html`
            });

            if (error) {
                return { success: false, error: this.translateError(error.message) };
            }

            return { success: true };
        } catch (err) {
            console.error('Password reset error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Update Password
    // ============================================
    async updatePassword(newPassword) {
        const client = AudazSupabase.getClient();
        if (!client) {
            return { success: false, error: 'Supabase not configured' };
        }

        try {
            const { error } = await client.auth.updateUser({
                password: newPassword
            });

            if (error) {
                return { success: false, error: this.translateError(error.message) };
            }

            return { success: true };
        } catch (err) {
            console.error('Update password error:', err);
            return { success: false, error: 'Unexpected error' };
        }
    },

    // ============================================
    // Role Checking Helpers
    // ============================================
    isClient(profile) {
        return profile?.role === 'client_admin' || profile?.role === 'client_user';
    },

    isClientAdmin(profile) {
        return profile?.role === 'client_admin';
    },

    isSupport(profile) {
        return profile?.role === 'support_agent' || profile?.role === 'support_admin';
    },

    isSupportAdmin(profile) {
        return profile?.role === 'support_admin';
    },

    // ============================================
    // Error Translation (Friendly English)
    // ============================================
    translateError(message) {
        const translations = {
            'Invalid login credentials': 'Invalid email or password',
            'Email not confirmed': 'Email not confirmed. Check your inbox.',
            'User already registered': 'This email is already registered',
            'Password should be at least 6 characters': 'Password must be at least 6 characters',
            'Signup requires a valid password': 'Invalid password',
            'Unable to validate email address': 'Invalid email address',
            'Email rate limit exceeded': 'Too many attempts. Please wait a few minutes.',
            'For security purposes, you can only request this once every 60 seconds': 'Please wait 60 seconds before trying again'
        };

        return translations[message] || message;
    }
};

// Export
window.AuthService = AuthService;
