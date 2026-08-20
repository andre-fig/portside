import { createFileRoute, Link } from "@tanstack/react-router";
import { queryOptions, useSuspenseQuery } from "@tanstack/react-query";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Check, Download, Gamepad2, RefreshCw, Sparkles, Stethoscope, Wand2 } from "lucide-react";
import { Header } from "@/components/site/Header";
import { Footer } from "@/components/site/Footer";
import { Logo } from "@/components/site/Logo";
import { getPricing } from "@/lib/pricing.functions";

const pricingQuery = queryOptions({
  queryKey: ["pricing"],
  queryFn: () => getPricing(),
});

export const Route = createFileRoute("/")({
  loader: ({ context }) => context.queryClient.ensureQueryData(pricingQuery),
  head: () => ({
    meta: [
      { title: "Portside — Mais jogos da sua Steam. Agora no Mac." },
      {
        name: "description",
        content:
          "O Portside prepara automaticamente o ambiente de compatibilidade, abre a Steam do Windows e deixa você instalar e jogar no seu Mac com Apple Silicon.",
      },
      { property: "og:title", content: "Portside — Mais jogos da sua Steam. Agora no Mac." },
      {
        property: "og:description",
        content:
          "Instale, abra a Steam e jogue. Configuração automática para Macs com Apple Silicon.",
      },
    ],
  }),
  component: Landing,
});

const steps = [
  {
    title: "Abra o Portside",
    text: "O ambiente de compatibilidade é preparado automaticamente na primeira execução.",
  },
  {
    title: "Entre na Steam",
    text: "A versão Windows da Steam abre integrada ao macOS, com sua conta e sua biblioteca.",
  },
  {
    title: "Instale e jogue",
    text: "Escolha um jogo, instale e comece a jogar. Sem configurar nada manualmente.",
  },
];

const features = [
  {
    icon: Wand2,
    title: "Configuração automática",
    text: "Nada de Wine, engines ou renderers: o Portside cuida de tudo em segundo plano.",
  },
  {
    icon: Sparkles,
    title: "Integração com o macOS",
    text: "Janelas, atalhos e arquivos se comportam como você espera em um Mac.",
  },
  {
    icon: RefreshCw,
    title: "Ambiente sempre atualizado",
    text: "Melhorias de compatibilidade chegam por atualização, sem trabalho manual.",
  },
  {
    icon: Gamepad2,
    title: "Perfis automáticos por jogo",
    text: "Cada título recebe os ajustes conhecidos que costumam funcionar melhor.",
  },
  {
    icon: Stethoscope,
    title: "Reparo e diagnóstico",
    text: "Um clique para verificar o ambiente e voltar a um estado saudável.",
  },
  {
    icon: Download,
    title: "Sua biblioteca, ampliada",
    text: "Acesse mais títulos da sua conta Steam diretamente no seu Mac.",
  },
];

const faq = [
  {
    q: "O Portside funciona em Macs Intel?",
    a: "Não. O Portside foi feito para Macs com Apple Silicon (M1 ou mais recente).",
  },
  {
    q: "Todos os jogos da minha biblioteca vão rodar?",
    a: "Não. A compatibilidade varia conforme o título. Jogos que dependem de determinados sistemas anticheat, drivers específicos ou launchers próprios podem não funcionar.",
  },
  {
    q: "Preciso de uma licença da Steam ou dos jogos?",
    a: "Sim. O Portside não fornece jogos: você usa sua própria conta e sua própria biblioteca Steam.",
  },
  {
    q: "Preciso configurar Wine ou algo técnico?",
    a: "Não. Toda a complexidade fica escondida. Você abre o Portside, entra na Steam e joga.",
  },
  {
    q: "O Portside é da Valve ou da Apple?",
    a: "Não. É um produto independente, sem afiliação, patrocínio ou endosso da Valve Corporation ou da Apple Inc.",
  },
  {
    q: "Como recebo o aplicativo depois da compra?",
    a: "Após a confirmação do pagamento, você recebe a chave de licença e o link de download na página de confirmação e também por e-mail.",
  },
];

function Landing() {
  const { data: pricing } = useSuspenseQuery(pricingQuery);

  return (
    <div className="min-h-screen bg-background">
      <Header />
      <main>
        {/* Hero */}
        <section className="relative overflow-hidden px-5 pt-20 pb-16 sm:pt-28 sm:pb-24">
          <div
            aria-hidden
            className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[520px] bg-gradient-soft"
          />
          <div className="mx-auto max-w-4xl text-center reveal">
            <Logo className="mx-auto h-20 w-20 sm:h-24 sm:w-24" />
            <h1 className="mt-8 text-4xl font-semibold sm:text-6xl">
              Mais jogos da sua Steam.
              <br />
              <span className="text-gradient-brand">Agora no Mac.</span>
            </h1>
            <p className="mx-auto mt-6 max-w-2xl text-base leading-relaxed text-muted-foreground sm:text-xl">
              O Portside prepara tudo automaticamente para você abrir a Steam do Windows, instalar
              seus jogos e começar a jogar no seu Mac com Apple Silicon.
            </p>
            <div className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
              <Link
                to="/comprar"
                className="w-full rounded-full bg-gradient-brand px-7 py-3 text-[15px] font-medium text-primary-foreground shadow-float transition-transform hover:-translate-y-0.5 sm:w-auto"
              >
                Comprar Portside
              </Link>
              <a
                href="#como-funciona"
                className="w-full rounded-full border border-border px-7 py-3 text-[15px] font-medium transition-colors hover:bg-secondary sm:w-auto"
              >
                Veja como funciona
              </a>
            </div>
            <p className="mt-5 text-[13px] text-muted-foreground">
              Para Macs com Apple Silicon. A compatibilidade varia conforme o jogo.
            </p>
          </div>
        </section>

        {/* Fluxo */}
        <section id="como-funciona" className="scroll-mt-20 px-5 py-20 sm:py-28">
          <div className="mx-auto max-w-6xl">
            <h2 className="max-w-2xl text-3xl font-semibold sm:text-5xl">
              Três passos. Nenhuma configuração.
            </h2>
            <ol className="mt-12 grid gap-5 md:grid-cols-3">
              {steps.map((s, i) => (
                <li
                  key={s.title}
                  className="rounded-3xl border border-border/70 bg-card p-8 shadow-card transition-transform hover:-translate-y-1"
                >
                  <span className="inline-flex h-8 w-8 items-center justify-center rounded-full bg-gradient-brand text-sm font-semibold text-primary-foreground">
                    {i + 1}
                  </span>
                  <h3 className="mt-5 text-lg font-semibold">{s.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{s.text}</p>
                </li>
              ))}
            </ol>
          </div>
        </section>

        {/* Recursos */}
        <section className="bg-secondary/40 px-5 py-20 sm:py-28">
          <div className="mx-auto max-w-6xl">
            <h2 className="max-w-2xl text-3xl font-semibold sm:text-5xl">
              A complexidade fica escondida.
            </h2>
            <p className="mt-4 max-w-xl text-muted-foreground">
              Você vê apenas a Steam e seus jogos. O resto é trabalho do Portside.
            </p>
            <div className="mt-12 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
              {features.map((f) => (
                <div key={f.title} className="rounded-3xl bg-card p-7 shadow-card">
                  <f.icon className="h-6 w-6 text-primary" aria-hidden />
                  <h3 className="mt-4 text-base font-semibold">{f.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-muted-foreground">{f.text}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Compatibilidade */}
        <section id="compatibilidade" className="scroll-mt-20 px-5 py-20 sm:py-28">
          <div className="mx-auto max-w-3xl">
            <h2 className="text-3xl font-semibold sm:text-5xl">Transparência sobre o que roda.</h2>
            <p className="mt-6 text-lg leading-relaxed text-muted-foreground">
              Muitos títulos da sua biblioteca funcionam bem, outros funcionam com ressalvas e
              alguns não funcionam. É assim que a compatibilidade evolui: caso a caso.
            </p>
            <ul className="mt-8 space-y-3 text-[15px] text-muted-foreground">
              {[
                "A experiência depende do jogo, da versão e do hardware do seu Mac.",
                "Títulos que dependem de determinados sistemas anticheat podem não iniciar.",
                "Jogos que exigem drivers específicos ou launchers próprios podem não ser compatíveis.",
                "O ambiente é atualizado com frequência, ampliando a lista de títulos que funcionam.",
              ].map((t) => (
                <li key={t} className="flex gap-3">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                  <span>{t}</span>
                </li>
              ))}
            </ul>
            <p className="mt-8 text-sm text-muted-foreground">
              Não prometemos que todos os jogos funcionam — preferimos ser claros antes da compra.
            </p>
          </div>
        </section>

        {/* Preço */}
        <section id="preco" className="scroll-mt-20 bg-secondary/40 px-5 py-20 sm:py-28">
          <div className="mx-auto max-w-md">
            <div className="rounded-[28px] bg-card p-9 text-center shadow-float">
              <h2 className="text-2xl font-semibold">Portside</h2>
              <p className="mt-1 text-sm text-muted-foreground">Licença para uso pessoal</p>
              <p className="mt-7 text-5xl font-semibold tracking-tight">{pricing.formatted}</p>
              <p className="mt-2 text-[13px] text-muted-foreground">
                Pagamento único · {pricing.currency}
              </p>
              <Link
                to="/comprar"
                className="mt-8 inline-flex w-full items-center justify-center rounded-full bg-gradient-brand px-6 py-3 text-[15px] font-medium text-primary-foreground transition-opacity hover:opacity-90"
              >
                Comprar Portside
              </Link>
              <ul className="mt-7 space-y-2 text-left text-sm text-muted-foreground">
                {[
                  "Configuração automática do ambiente",
                  "Perfis automáticos por jogo",
                  "Atualizações de compatibilidade",
                  "Chave de licença enviada por e-mail",
                ].map((t) => (
                  <li key={t} className="flex gap-2">
                    <Check className="mt-0.5 h-4 w-4 shrink-0 text-primary" aria-hidden />
                    {t}
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </section>

        {/* FAQ */}
        <section id="faq" className="scroll-mt-20 px-5 py-20 sm:py-28">
          <div className="mx-auto max-w-3xl">
            <h2 className="text-3xl font-semibold sm:text-5xl">Perguntas frequentes</h2>
            <Accordion type="single" collapsible className="mt-10">
              {faq.map((item) => (
                <AccordionItem key={item.q} value={item.q}>
                  <AccordionTrigger className="text-left text-base">{item.q}</AccordionTrigger>
                  <AccordionContent className="text-[15px] leading-relaxed text-muted-foreground">
                    {item.a}
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          </div>
        </section>
      </main>
      <Footer />
    </div>
  );
}
