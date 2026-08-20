import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

const schema = z.object({
  email: z.string().email().max(200),
});

export type CheckoutResult =
  { status: "redirect"; url: string } | { status: "unconfigured"; message: string };

/**
 * Cria a sessão de Checkout da Stripe (cartão + Apple Pay quando disponível).
 * Enquanto não existirem credenciais, retorna um estado explícito de
 * "não configurado" — nunca simulamos um pagamento.
 */
export const createCheckoutSession = createServerFn({ method: "POST" })
  .validator((data: unknown) => schema.parse(data))
  .handler(async ({ data }): Promise<CheckoutResult> => {
    const secret = process.env["STRIPE_SECRET_KEY"] ?? process.env["STRIPE_TEST_API_KEY"];
    const priceId = process.env["STRIPE_PRICE_ID"];

    if (!secret) {
      return {
        status: "unconfigured",
        message:
          "O pagamento ainda não está ativo: faltam as credenciais da Stripe neste ambiente.",
      };
    }

    const { getRequestUrl } = await import("@tanstack/react-start/server");
    const appBaseUrl = process.env["APP_BASE_URL"] ?? getRequestUrl().origin;

    const body = new URLSearchParams({
      mode: "payment",
      "line_items[0][quantity]": "1",
      customer_email: data.email,
      success_url: `${appBaseUrl}/sucesso?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${appBaseUrl}/comprar`,
    });

    if (priceId) {
      body.set("line_items[0][price]", priceId);
    } else {
      // Sem price pré-criado: o valor vem sempre do ambiente, nunca do cliente.
      const amountCents = Number(process.env["PORTSIDE_PRICE_AMOUNT"] ?? 24900);
      const currency = (process.env["PORTSIDE_PRICE_CURRENCY"] ?? "BRL").toLowerCase();
      body.set("line_items[0][price_data][currency]", currency);
      body.set("line_items[0][price_data][unit_amount]", String(Math.round(amountCents)));
      body.set("line_items[0][price_data][product_data][name]", "Portside — licença vitalícia");
      body.set(
        "line_items[0][price_data][product_data][description]",
        "Licença pessoal do Portside para Macs com Apple Silicon.",
      );
    }

    const response = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secret}`,
        "Content-Type": "application/x-www-form-urlencoded",
        "Idempotency-Key": crypto.randomUUID(),
      },
      body,
    });

    if (!response.ok) {
      const text = await response.text();
      console.error(`Stripe checkout failed [${response.status}]: ${text}`);
      throw new Error("Não foi possível iniciar o pagamento. Tente novamente.");
    }

    const session = (await response.json()) as { url: string };
    return { status: "redirect", url: session.url };
  });
