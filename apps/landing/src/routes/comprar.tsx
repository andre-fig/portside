import { createFileRoute } from "@tanstack/react-router";
import { queryOptions, useSuspenseQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { useState, type FormEvent } from "react";
import { Check, CreditCard, Lock, ShieldCheck } from "lucide-react";
import { Header } from "@/components/site/Header";
import { Footer } from "@/components/site/Footer";
import { Logo } from "@/components/site/Logo";
import { getPricing } from "@/lib/pricing.functions";
import { createCheckoutSession } from "@/lib/checkout.functions";

const pricingQuery = queryOptions({ queryKey: ["pricing"], queryFn: () => getPricing() });

export const Route = createFileRoute("/comprar")({
  loader: ({ context }) => context.queryClient.ensureQueryData(pricingQuery),
  head: () => ({
    meta: [
      { title: "Comprar Portside — licença para Mac com Apple Silicon" },
      {
        name: "description",
        content:
          "Finalize a compra do Portside com cartão de crédito ou Apple Pay. Licença enviada por e-mail após a confirmação do pagamento.",
      },
      { property: "og:title", content: "Comprar Portside" },
      {
        property: "og:description",
        content: "Pagamento seguro com cartão de crédito ou Apple Pay, processado pela Stripe.",
      },
    ],
  }),
  component: Comprar,
});

function Comprar() {
  const { data: pricing } = useSuspenseQuery(pricingQuery);
  const checkout = useServerFn(createCheckoutSession);
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const result = await checkout({ data: { email } });
      if (result.status === "redirect") {
        window.location.href = result.url;
        return;
      }
      setError(result.message);
    } catch {
      setError("Não foi possível iniciar o pagamento. Tente novamente em instantes.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-background">
      <Header />
      <main className="mx-auto max-w-5xl px-5 py-16 sm:py-24">
        <div className="grid gap-10 md:grid-cols-[1.1fr_1fr] md:items-start">
          <div className="reveal">
            <Logo className="h-14 w-14" />
            <h1 className="mt-6 text-4xl font-semibold sm:text-5xl">Comprar Portside</h1>
            <p className="mt-4 max-w-md text-[15px] leading-relaxed text-muted-foreground">
              Pagamento único. Após a confirmação, você recebe a chave de licença e o link de
              download na tela e também por e-mail.
            </p>
            <ul className="mt-8 space-y-3 text-sm text-muted-foreground">
              {[
                "Licença pessoal para Macs com Apple Silicon",
                "Atualizações de compatibilidade incluídas",
                "Cartão de crédito e Apple Pay (quando disponível)",
              ].map((t) => (
                <li key={t} className="flex gap-2">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                  {t}
                </li>
              ))}
            </ul>
            <p className="mt-8 flex items-start gap-2 text-[13px] text-muted-foreground">
              <Lock className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
              Os dados do cartão são enviados diretamente à Stripe. O Portside nunca recebe nem
              armazena o número do seu cartão.
            </p>
          </div>

          <div className="rounded-[28px] border border-border/70 bg-card p-8 shadow-float">
            <div className="flex items-baseline justify-between">
              <span className="text-sm text-muted-foreground">Total</span>
              <span className="text-3xl font-semibold">{pricing.formatted}</span>
            </div>
            {pricing.mode === "test" && (
              <p className="mt-3 rounded-xl bg-secondary px-3 py-2 text-[12px] text-muted-foreground">
                Ambiente de teste: nenhum pagamento real é processado.
              </p>
            )}

            <form
              onSubmit={(event) => {
                void onSubmit(event);
              }}
              className="mt-7"
            >
              <label htmlFor="email" className="text-sm font-medium">
                E-mail para receber a licença
              </label>
              <input
                id="email"
                type="email"
                required
                autoComplete="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="voce@exemplo.com"
                className="mt-2 w-full rounded-xl border border-input bg-background px-4 py-3 text-[15px] outline-none transition-colors focus:border-ring"
              />
              {error && (
                <p role="alert" className="mt-3 text-[13px] text-destructive">
                  {error}
                </p>
              )}
              <button
                type="submit"
                disabled={loading}
                className="mt-5 inline-flex w-full items-center justify-center gap-2 rounded-full bg-gradient-brand px-6 py-3 text-[15px] font-medium text-primary-foreground transition-opacity hover:opacity-90 disabled:opacity-60"
              >
                <CreditCard className="h-4 w-4" aria-hidden />
                {loading ? "Abrindo pagamento seguro…" : "Ir para o pagamento"}
              </button>
              <p className="mt-4 flex items-start gap-2 text-[12px] leading-relaxed text-muted-foreground">
                <ShieldCheck className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />O Apple Pay aparece
                automaticamente na tela de pagamento quando o seu dispositivo e navegador oferecem
                suporte; caso contrário, o pagamento segue por cartão.
              </p>
            </form>
          </div>
        </div>
      </main>
      <Footer />
    </div>
  );
}
