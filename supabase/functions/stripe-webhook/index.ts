import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY")!;
const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

// Minimal Stripe signature verification using Web Crypto API
async function verifyStripeSignature(
  payload: string,
  sigHeader: string,
  secret: string
): Promise<boolean> {
  try {
    const parts = sigHeader.split(",").reduce<Record<string, string>>((acc, part) => {
      const [key, value] = part.split("=");
      acc[key] = value;
      return acc;
    }, {});

    const timestamp = parts["t"];
    const signature = parts["v1"];

    if (!timestamp || !signature) return false;

    const signedPayload = `${timestamp}.${payload}`;
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"]
    );
    const signatureBytes = await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(signedPayload)
    );
    const expectedSignature = Array.from(new Uint8Array(signatureBytes))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    return expectedSignature === signature;
  } catch {
    return false;
  }
}

serve(async (req) => {
  // Stripe webhooks are POST only
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const sigHeader = req.headers.get("stripe-signature");
  if (!sigHeader) {
    return new Response("Missing stripe-signature header", { status: 400 });
  }

  const rawBody = await req.text();

  const isValid = await verifyStripeSignature(rawBody, sigHeader, STRIPE_WEBHOOK_SECRET);
  if (!isValid) {
    console.error("Invalid Stripe webhook signature");
    return new Response("Invalid signature", { status: 400 });
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  // Only handle checkout completion
  if (event.type !== "checkout.session.completed") {
    return new Response(JSON.stringify({ received: true }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const session = event.data as Record<string, unknown>;
  const sessionObj = session.object as Record<string, unknown>;
  const metadata = sessionObj.metadata as Record<string, string>;

  const orgId = metadata?.org_id;
  const quantity = parseInt(metadata?.quantity || "0", 10);
  const stripeSessionId = sessionObj.id as string;
  const paymentIntentId = sessionObj.payment_intent as string;
  const amountTotal = sessionObj.amount_total as number;
  const currency = sessionObj.currency as string;

  if (!orgId || !quantity || quantity < 1) {
    console.error("Missing org_id or quantity in session metadata", metadata);
    return new Response("Missing metadata", { status: 400 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );

  const { data, error } = await supabase.rpc("record_task_purchase", {
    p_org_id: orgId,
    p_stripe_session_id: stripeSessionId,
    p_stripe_payment_intent_id: paymentIntentId || null,
    p_quantity: quantity,
    p_amount_paid: amountTotal || 0,
    p_currency: currency || "usd",
  });

  if (error) {
    console.error("record_task_purchase error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  if (!data?.success) {
    console.error("record_task_purchase failed:", data);
    // Return 200 to prevent Stripe retries for already-processed sessions
    return new Response(JSON.stringify({ received: true, note: data?.error }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  console.log(`Added ${quantity} extra tasks to org ${orgId}`);

  return new Response(JSON.stringify({ received: true, quantity_added: quantity }), {
    headers: { "Content-Type": "application/json" },
  });
});
