import { describe, expect, it } from "vitest";
import { authorized, WebhookBody } from "../../src/billing/revenuecat.js";

describe("authorized", () => {
  it("accepts the exact bearer", () => expect(authorized("Bearer s3cret", "s3cret")).toBe(true));
  it("rejects a wrong secret and a different length", () => {
    expect(authorized("Bearer s3cre", "s3cret")).toBe(false);
    expect(authorized("Bearer xxxxxx", "s3cret")).toBe(false);
  });
  it("an unset secret never authorises anything — 'Bearer undefined' passed in v1", () => {
    expect(authorized("Bearer undefined", "")).toBe(false);
    expect(authorized("Bearer undefined", undefined as unknown as string)).toBe(false);
  });
  it("missing header is rejected", () => expect(authorized(undefined, "s3cret")).toBe(false));
});

describe("WebhookBody", () => {
  it("parses a minimal RevenueCat event", () => {
    expect(WebhookBody.safeParse({ event: { type: "RENEWAL", app_user_id: "u1", expiration_at_ms: 1 } }).success).toBe(true);
  });
  it("rejects a body without event", () => expect(WebhookBody.safeParse({}).success).toBe(false));
});
