/**
 * AUDAZ PRO - Auth Guard
 *
 * Route protection and role-based access control
 */

const AuthGuard = {
    // ============================================
    // Initialize Auth Guard
    // ============================================
    async init(options = {}) {
        const {
            requiredRoles = [],
            redirectTo = '/client/index.html',
            onAuthenticated = null,
            onUnauthenticated = null
        } = options;

        // Check if Supabase is configured
        if (!AudazSupabase.isConfigured()) {
            console.error('Supabase not configured');
            this.showConfigError();
            return null;
        }

        // Get current session
        const session = await AudazSupabase.getCurrentSession();

        if (!session) {
            // No session - user not authenticated
            if (onUnauthenticated) {
                onUnauthenticated();
            } else {
                window.location.href = redirectTo;
            }
            return null;
        }

        // Get user profile
        const profileResult = await AuthService.getProfile();

        if (!profileResult.success || !profileResult.profile) {
            console.error('Profile not found');
            await AuthService.signOut();
            window.location.href = redirectTo;
            return null;
        }

        const profile = profileResult.profile;

        // Check role requirements
        if (requiredRoles.length > 0 && !requiredRoles.includes(profile.role)) {
            console.error('Access denied - invalid role');
            this.handleAccessDenied(profile);
            return null;
        }

        // Authentication successful
        if (onAuthenticated) {
            onAuthenticated(profile);
        }

        return profile;
    },

    // ============================================
    // Handle Access Denied
    // ============================================
    handleAccessDenied(profile) {
        // Redirect to appropriate dashboard based on role
        if (AuthService.isSupport(profile)) {
            window.location.href = '/support/dashboard.html';
        } else if (AuthService.isClient(profile)) {
            window.location.href = '/client/dashboard.html';
        } else {
            window.location.href = '/client/index.html';
        }
    },

    // ============================================
    // Check if user is authenticated (without redirect)
    // ============================================
    async isAuthenticated() {
        if (!AudazSupabase.isConfigured()) {
            return false;
        }

        const session = await AudazSupabase.getCurrentSession();
        return !!session;
    },

    // ============================================
    // Get current profile (cached during page load)
    // ============================================
    currentProfile: null,

    async getProfile() {
        if (this.currentProfile) {
            return this.currentProfile;
        }

        const result = await AuthService.getProfile();
        if (result.success) {
            this.currentProfile = result.profile;
            return result.profile;
        }

        return null;
    },

    // ============================================
    // Show Config Error
    // ============================================
    showConfigError() {
        document.body.innerHTML = `
            <div style="min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 2rem; text-align: center;">
                <div>
                    <h1 style="color: #ffe500; margin-bottom: 1rem;">Configuration Required</h1>
                    <p style="color: rgba(255,255,255,0.7); margin-bottom: 2rem;">
                        Supabase is not configured. Please update the
                        <code style="background: rgba(255,255,255,0.1); padding: 0.25rem 0.5rem; border-radius: 4px;">js/supabase-config.js</code>
                        file with your project credentials.
                    </p>
                    <a href="/" class="btn btn-primary">Go to Home</a>
                </div>
            </div>
        `;
    },

    // ============================================
    // Setup Logout Button
    // ============================================
    setupLogoutButton(selector = '.logout-btn') {
        const btn = document.querySelector(selector);
        if (!btn) return;

        btn.addEventListener('click', async (e) => {
            e.preventDefault();
            const confirmed = await UIComponents.confirm('Are you sure you want to sign out?', 'Logout');
            if (confirmed) {
                await AuthService.signOut();
                window.location.href = '/client/index.html';
            }
        });
    },

    // ============================================
    // Update User Info in UI
    // ============================================
    updateUserInfo(profile, options = {}) {
        const nameEl = document.querySelector(options.nameSelector || '.user-name');
        const roleEl = document.querySelector(options.roleSelector || '.user-role');
        const orgEl = document.querySelector(options.orgSelector || '.user-org');
        const avatarEl = document.querySelector(options.avatarSelector || '.user-avatar');

        if (nameEl) {
            nameEl.textContent = profile.full_name;
        }

        if (roleEl) {
            roleEl.textContent = InvitationsService.formatRole(profile.role);
        }

        if (orgEl && profile.organization) {
            orgEl.textContent = profile.organization.name;
        }

        if (avatarEl) {
            avatarEl.textContent = profile.full_name.charAt(0).toUpperCase();
        }
    },

    // ============================================
    // Listen for Auth Changes
    // ============================================
    onAuthChange(callback) {
        AudazSupabase.onAuthStateChange((event, session) => {
            if (event === 'SIGNED_OUT') {
                this.currentProfile = null;
                callback(null);
            } else if (event === 'SIGNED_IN') {
                this.getProfile().then(profile => callback(profile));
            }
        });
    }
};

// Export
window.AuthGuard = AuthGuard;
