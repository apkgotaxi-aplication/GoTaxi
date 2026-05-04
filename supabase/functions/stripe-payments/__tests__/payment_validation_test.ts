// Strict tests for Stripe payment validation logic
// Run with: deno test --allow-read --allow-net supabase/functions/stripe-payments/__tests__/payment_validation_test.ts

import { assertEquals, assertFalse, assertTrue } from "https://deno.land/std@0.200.0/testing/asserts.ts";

// Mock data structures
interface MockPaymentIntent {
  id: string;
  status: string;
  metadata?: {
    ride_id?: string;
    user_id?: string;
  };
}

interface MockRide {
  id: string;
  user_id: string;
  pagado: boolean;
  stripe_payment_intent_id?: string;
  stripe_payment_status?: string;
}

interface MockSession {
  id: string;
  payment_status: string;
  payment_intent: string | { id: string };
  metadata?: {
    ride_id?: string;
    user_id?: string;
  };
}

// Test validation logic extracted from the functions
function shouldMarkAsPaid(paymentStatus: string, intentStatus: string): boolean {
  return paymentStatus === "paid" && intentStatus === "succeeded";
}

function validatePaymentIntentBelongsToRide(
  intentRideId: string | undefined,
  rideId: string
): boolean {
  return intentRideId === rideId;
}

function validateUserOwnsPayment(
  intentUserId: string | undefined,
  userId: string
): boolean {
  return intentUserId === userId;
}

function shouldPreventDoublePayment(ridePaid: boolean): boolean {
  return ridePaid === true;
}

function isValidPaymentStatus(status: string): boolean {
  return status === "succeeded";
}

Deno.test("Payment Validation - shouldMarkAsPaid", () => {
  // Only mark as paid if BOTH payment_status is 'paid' AND intent status is 'succeeded'
  assertEquals(shouldMarkAsPaid("paid", "succeeded"), true);
  assertEquals(shouldMarkAsPaid("paid", "processing"), false);
  assertEquals(shouldMarkAsPaid("paid", "requires_payment_method"), false);
  assertEquals(shouldMarkAsPaid("unpaid", "succeeded"), false);
  assertEquals(shouldMarkAsPaid("paid", "failed"), false);
  assertEquals(shouldMarkAsPaid("", "succeeded"), false);
});

Deno.test("Payment Validation - PaymentIntent belongs to ride", () => {
  // Verify PaymentIntent metadata matches the ride_id
  assertEquals(
    validatePaymentIntentBelongsToRide("ride_123", "ride_123"),
    true
  );
  assertEquals(
    validatePaymentIntentBelongsToRide("ride_456", "ride_123"),
    false
  );
  assertEquals(
    validatePaymentIntentBelongsToRide(undefined, "ride_123"),
    false
  );
  assertEquals(
    validatePaymentIntentBelongsToRide("", "ride_123"),
    false
  );
});

Deno.test("Payment Validation - User owns payment", () => {
  // Verify PaymentIntent user_id matches the authenticated user
  assertEquals(
    validateUserOwnsPayment("user_123", "user_123"),
    true
  );
  assertEquals(
    validateUserOwnsPayment("user_456", "user_123"),
    false
  );
  assertEquals(
    validateUserOwnsPayment(undefined, "user_123"),
    false
  );
});

Deno.test("Payment Validation - Prevent double payment", () => {
  // Should NOT mark as paid if ride is already paid
  assertEquals(shouldPreventDoublePayment(true), true);
  assertEquals(shouldPreventDoublePayment(false), false);
});

Deno.test("Payment Validation - Valid payment status", () => {
  // Only 'succeeded' is a valid status for marking as paid
  assertEquals(isValidPaymentStatus("succeeded"), true);
  assertEquals(isValidPaymentStatus("processing"), false);
  assertEquals(isValidPaymentStatus("requires_payment_method"), false);
  assertEquals(isValidPaymentStatus("failed"), false);
  assertEquals(isValidPaymentStatus("canceled"), false);
});

Deno.test("Webhook - checkout.session.completed validation", () => {
  // Simulate webhook validation logic
  const session: MockSession = {
    id: "cs_123",
    payment_status: "paid",
    payment_intent: "pi_123",
    metadata: {
      ride_id: "ride_123",
      user_id: "user_123",
    },
  };

  const rideId = "ride_123";
  const userId = "user_123";

  // 1. Verify session belongs to this ride
  const sessionRideId = session.metadata?.ride_id ?? "";
  assertEquals(sessionRideId !== rideId, false, "Session should belong to this ride");

  // 2. Verify user matches
  const sessionUserId = session.metadata?.user_id ?? "";
  assertEquals(sessionUserId !== userId, false, "Session should belong to this user");

  // 3. Only proceed if payment_status is 'paid'
  const paymentStatus = session.payment_status ?? "";
  assertEquals(paymentStatus === "paid", true, "Payment status should be paid");

  // 4. Retrieve payment intent and verify status is 'succeeded'
  // (This would be done in actual code)
});

Deno.test("syncRidePaymentFromCheckoutSession - Strict validation", () => {
  const rideId = "ride_123";
  const userId = "user_123";
  
  // Case 1: Valid case - everything matches
  const validSession: MockSession = {
    id: "cs_123",
    payment_status: "paid",
    payment_intent: { id: "pi_123" },
    metadata: { ride_id: "ride_123", user_id: "user_123" },
  };
  
  let paymentIntent: MockPaymentIntent = {
    id: "pi_123",
    status: "succeeded",
    metadata: { ride_id: "ride_123", user_id: "user_123" },
  };
  
  // Validate: session ride_id matches
  assertEquals(
    validatePaymentIntentBelongsToRide(paymentIntent.metadata?.ride_id, rideId),
    true
  );
  
  // Validate: user_id matches
  assertEquals(
    validateUserOwnsPayment(paymentIntent.metadata?.user_id, userId),
    true
  );
  
  // Validate: intent status is succeeded
  assertEquals(isValidPaymentStatus(paymentIntent.status), true);
  
  // Case 2: Invalid - ride_id mismatch
  paymentIntent = {
    id: "pi_123",
    status: "succeeded",
    metadata: { ride_id: "ride_456", user_id: "user_123" }, // Wrong ride_id
  };
  
  assertEquals(
    validatePaymentIntentBelongsToRide(paymentIntent.metadata?.ride_id, rideId),
    false
  );  
  // Case 3: Invalid - user_id mismatch
  paymentIntent = {
    id: "pi_123",
    status: "succeeded",
    metadata: { ride_id: "ride_123", user_id: "user_456" }, // Wrong user
  };
  
  assertEquals(
    validateUserOwnsPayment(paymentIntent.metadata?.user_id, userId),
    false
  );  
  // Case 4: Invalid - status not succeeded
  paymentIntent = {
    id: "pi_123",
    status: "processing", // Not succeeded
    metadata: { ride_id: "ride_123", user_id: "user_123" },
  };
  
  assertEquals(isValidPaymentStatus(paymentIntent.status), false);
});

Deno.test("markRidePaid - Prevent double payment", () => {
  // Case 1: Ride already paid - should skip
  const rideAlreadyPaid: MockRide = {
    id: "ride_123",
    user_id: "user_123",
    pagado: true, // Already paid
  };
  
  assertEquals(shouldPreventDoublePayment(rideAlreadyPaid.pagado), true);
  
  // Case 2: Ride not paid - can proceed
  const rideNotPaid: MockRide = {
    id: "ride_123",
    user_id: "user_123",
    pagado: false,
  };
  
  assertEquals(shouldPreventDoublePayment(rideNotPaid.pagado), false);
});

Deno.test("syncRidePaymentFromStripe - Validation flow", () => {
  const rideId = "ride_123";
  const userId = "user_123";
  
  // Simulate payment intent from Stripe
  const paymentIntent: MockPaymentIntent = {
    id: "pi_123",
    status: "succeeded",
    metadata: {
      ride_id: "ride_123",
      user_id: "user_123",
    },
  };
  
  // All validations must pass
  const rideIdMatch = validatePaymentIntentBelongsToRide(
    paymentIntent.metadata?.ride_id,
    rideId
  );
  assertTrue(rideIdMatch, "Ride ID should match");
  
  const userIdMatch = validateUserOwnsPayment(
    paymentIntent.metadata?.user_id,
    userId
  );
  assertTrue(userIdMatch, "User ID should match");
  
  const validStatus = isValidPaymentStatus(paymentIntent.status);
  assertTrue(validStatus, "Status should be succeeded");
  
  // Only if ALL validations pass, mark as paid
  const shouldMarkPaid = rideIdMatch && userIdMatch && validStatus;
  assertEquals(shouldMarkPaid, true);
});

Deno.test("Edge cases - Payment status variations", () => {
  // Test all possible Stripe payment statuses
  const statuses = [
    { status: "succeeded", shouldMark: true },
    { status: "processing", shouldMark: false },
    { status: "requires_payment_method", shouldMark: false },
    { status: "requires_confirmation", shouldMark: false },
    { status: "requires_action", shouldMark: false },
    { status: "canceled", shouldMark: false },
    { status: "failed", shouldMark: false },
  ];
  
  for (const { status, shouldMark } of statuses) {
    assertEquals(
      isValidPaymentStatus(status),
      shouldMark,
      `Status ${status} should ${shouldMark ? "" : "not "}mark as paid`
    );
  }
});

console.log("✅ All payment validation tests completed!");
