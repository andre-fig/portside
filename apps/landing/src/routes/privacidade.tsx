import { createFileRoute } from "@tanstack/react-router";
import { Header } from "@/components/site/Header";
import { Footer } from "@/components/site/Footer";

export const Route = createFileRoute("/privacidade")({
  head: () => ({
    meta: [
      { title: "Privacidade — Portside" },
      { name: "description", content: "Como o Portside trata seus dados pessoais e de pagamento." },
      { property: "og:title", content: "Privacidade — Portside" },
      {
        property: "og:description",
        content: "Como o Portside trata seus dados pessoais e de pagamento.",
      },
    ],
  }),
  component: Privacidade,
});

function Privacidade() {
  return (
    <div className="min-h-screen bg-background">
      <Header />
      <main className="mx-auto max-w-3xl px-5 py-20">
        <h1 className="text-4xl font-semibold">Privacidade</h1>
        <div className="mt-8 space-y-5 text-[15px] leading-relaxed text-muted-foreground">
          <p>
            Coletamos apenas o e-mail informado na compra, usado para enviar a chave de licença, o
            link de download e comunicações essenciais sobre o produto.
          </p>
          <p>
            O pagamento é processado pela Stripe. Dados de cartão são enviados diretamente à Stripe
            e nunca passam pelos servidores do Portside.
          </p>
          <p>
            Chaves de licença não são registradas de forma completa em logs, analytics ou mensagens
            de erro.
          </p>
        </div>
      </main>
      <Footer />
    </div>
  );
}
