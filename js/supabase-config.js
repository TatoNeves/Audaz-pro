/**
 * AUDAZ PRO - Supabase Configuration
 *
 * Configure your Supabase project URL and anon key here.
 * Get these from: Supabase Dashboard > Settings > API
 */

// ============================================
// CONFIGURATION - UPDATE THESE VALUES
// ============================================
const SUPABASE_URL = 'https://jliqlisrnuusqxiswfcg.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpsaXFsaXNybnV1c3F4aXN3ZmNnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5NTE2ODksImV4cCI6MjA4NDUyNzY4OX0.DD51bZl0E-mBEtSlbgxsyTStErcmImP_vnP6XSH9rM4';
const SUPABASE_SERVICE_ROLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpsaXFsaXNybnV1c3F4aXN3ZmNnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODk1MTY4OSwiZXhwIjoyMDg0NTI3Njg5fQ.KyPI-V4RRrIt2bXemM50gE31kG3wOV9xLOUsy1su2-M';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_sU_tg7ZtG1sBkeBPA9cVag_u3X6K51e';

// ============================================
// Supabase Client Initialization
// ============================================
let supabaseClient = null;

function getSupabase() {
    if (!supabaseClient) {
        if (SUPABASE_URL === 'YOUR_SUPABASE_URL' || SUPABASE_ANON_KEY === 'YOUR_SUPABASE_ANON_KEY') {
            console.error('Supabase not configured. Please update js/supabase-config.js with your project credentials.');
            return null;
        }

        // Initialize Supabase client
        supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
            auth: {
                autoRefreshToken: true,
                persistSession: true,
                detectSessionInUrl: true
            }
        });
    }
    return supabaseClient;
}

// ============================================
// Auth State Change Listener
// ============================================
function onAuthStateChange(callback) {
    const client = getSupabase();
    if (!client) return null;

    return client.auth.onAuthStateChange((event, session) => {
        callback(event, session);
    });
}

// ============================================
// Session Helpers
// ============================================
async function getCurrentSession() {
    const client = getSupabase();
    if (!client) return null;

    const { data: { session }, error } = await client.auth.getSession();
    if (error) {
        console.error('Error getting session:', error);
        return null;
    }
    return session;
}

async function getCurrentUser() {
    const client = getSupabase();
    if (!client) return null;

    const { data: { user }, error } = await client.auth.getUser();
    if (error) {
        console.error('Error getting user:', error);
        return null;
    }
    return user;
}

// ============================================
// Export for use in other modules
// ============================================
window.AudazSupabase = {
    getClient: getSupabase,
    getCurrentSession,
    getCurrentUser,
    onAuthStateChange,
    SUPABASE_URL,
    SUPABASE_ANON_KEY,
    SUPABASE_SERVICE_ROLE_KEY,
    SUPABASE_PUBLISHABLE_KEY,
    isConfigured: () => SUPABASE_URL !== 'YOUR_SUPABASE_URL' && SUPABASE_ANON_KEY !== 'YOUR_SUPABASE_ANON_KEY'
};
