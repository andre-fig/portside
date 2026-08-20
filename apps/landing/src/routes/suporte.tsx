import { createFileRoute } from "@tanstack/react-router";
import { Header } from "@/components/site/Header";
import { Footer } from "@/components/site/Footer";

export const Route = createFileRoute("/suporte")({
  head: () => ({
    meta: [
      { title: "Suporte — Portside" },
      {
        name: "description",
        content: "Ajuda com instalação, licença e compatibilidade de jogos no Portside.",
      },
      { property: "og:title", content: "Suporte — Portside" },
      {
        property: "og:description",
        content: "Ajuda com instalação, licença e compatibilidade de jogos no Portside.",
      },
    ],
  }),
  component: Suporte,
});

function Suporte() {
  return (
    <div className="min-h-screen bg-background">
      <Header />
      <main className="mx-auto max-w-3xl px-5 py-20">
        <h1 className="text-4xl font-semibold">Suporte</h1>
        <div className="mt-8 space-y-5 text-[15px] leading-relaxed text-muted-foreground">
          <p>
            Precisa de ajuda com instalação, licença ou um jogo específico? Escreva para{" "}
            <a href="mailto:suporte@portside.app" className="text-primary hover:underline">
              suporte@portside.app
            </a>
            .
          </p>
          <p>
            Ao relatar um problema de compatibilidade, informe o modelo do Mac, a versão do macOS e
            o nome do jogo. Nunca envie sua chave de licença completa por canais públicos.
          </p>
        </div>
      </main>
      <Footer />
    </div>
  );
}
