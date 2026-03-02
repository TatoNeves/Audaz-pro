import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY")!;
const STRIPE_PRICE_ID = Deno.env.get("STRIPE_PRICE_ID")!; // Price ID for one extra task unit
const SITE_URL = Deno.env.get("SITE_URL") || "https://audaz-pro-5lkci.ondigitalocean.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Authenticate user via Supabase
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization")! } } }
    );

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get user's org_id and existing stripe_customer_id
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("org_id")
      .eq("id", user.id)
      .single();

    if (profileError || !profile?.org_id) {
      return new Response(
        JSON.stringify({ success: false, error: "Organization not found" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: org, error: orgError } = await supabase
      .from("organizations")
      .select("id, name, stripe_customer_id")
      .eq("id", profile.org_id)
      .single();

    if (orgError || !org) {
      return new Response(
        JSON.stringify({ success: false, error: "Organization not found" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parse quantity from request body
    const body = await req.json();
    const quantity = parseInt(body.quantity, 10);

    if (!quantity || quantity < 1 || quantity > 500) {
      return new Response(
        JSON.stringify({ success: false, error: "Quantity must be between 1 and 500" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Resolve or create Stripe customer
    let stripeCustomerId = org.stripe_customer_id;

    if (!stripeCustomerId) {
      const customerRes = await fetch("https://api.stripe.com/v1/customers", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          email: user.email!,
          name: org.name,
          "metadata[org_id]": org.id,
        }),
      });

      const customer = await customerRes.json();

      if (!customerRes.ok) {
        console.error("Stripe create customer error:", customer);
        return new Response(
          JSON.stringify({ success: false, error: "Failed to create billing customer" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      stripeCustomerId = customer.id;

      // Persist the customer ID using service role
      const supabaseAdmin = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
      );
      await supabaseAdmin.rpc("update_stripe_customer_id", {
        p_org_id: org.id,
        p_stripe_customer_id: stripeCustomerId,
      });
    }

    // Create Stripe Checkout session
    const sessionParams = new URLSearchParams({
      customer: stripeCustomerId,
      mode: "payment",
      "line_items[0][price]": STRIPE_PRICE_ID,
      "line_items[0][quantity]": String(quantity),
      success_url: `${SITE_URL}/client/billing/success.html?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${SITE_URL}/client/billing/cancel.html`,
      "metadata[org_id]": org.id,
      "metadata[quantity]": String(quantity),
      "payment_intent_data[metadata][org_id]": org.id,
      "payment_intent_data[metadata][quantity]": String(quantity),
    });

    const sessionRes = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: sessionParams,
    });

    const session = await sessionRes.json();

    if (!sessionRes.ok) {
      console.error("Stripe create session error:", session);
      return new Response(
        JSON.stringify({ success: false, error: "Failed to create checkout session" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: true, url: session.url }),
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
