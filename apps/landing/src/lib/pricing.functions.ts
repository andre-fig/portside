import { createServerFn } from "@tanstack/react-start";

export type PricingConfig = {
  amount: number;
  currency: string;
  formatted: string;
  locale: string;
  mode: "test" | "live";
  checkoutReady: boolean;
};

/**
 * Preço e moeda vêm sempre do ambiente (configuração/backend).
 * Nunca duplicar o valor no frontend.
 */
export const getPricing = createServerFn({ method: "GET" }).handler(
  async (): Promise<PricingConfig> => {
    const amount = Number(process.env["PORTSIDE_PRICE_AMOUNT"] ?? 24900) / 100;
    const currency = process.env["PORTSIDE_PRICE_CURRENCY"] ?? "BRL";
    const locale = process.env["PORTSIDE_PRICE_LOCALE"] ?? "pt-BR";
    const secret = process.env["STRIPE_SECRET_KEY"] ?? process.env["STRIPE_TEST_API_KEY"] ?? "";

    return {
      amount,
      currency,
      locale,
      formatted: new Intl.NumberFormat(locale, {
        style: "currency",
        currency,
        minimumFractionDigits: amount % 1 === 0 ? 0 : 2,
      }).format(amount),
      mode: secret.startsWith("sk_live_") ? "live" : "test",
      checkoutReady: Boolean(secret),
    };
  },
);
