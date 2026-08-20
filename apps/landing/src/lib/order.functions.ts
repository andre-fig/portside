import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

const schema = z.object({ sessionId: z.string().min(10).max(200) });

export type OrderStatus =
  | { status: "confirmed"; license: string; downloadUrl: string; email: string }
  | { status: "pending"; message: string };

/**
 * A liberação depende SEMPRE da confirmação vinda do webhook da Stripe.
 * O redirecionamento do navegador para /sucesso nunca libera o produto.
 */
export const getOrderStatus = createServerFn({ method: "POST" })
  .validator((data: unknown) => schema.parse(data))
  .handler(async ({ data }): Promise<OrderStatus> => {
    void data;
    return {
      status: "pending",
      message:
        "Estamos aguardando a confirmação do pagamento. A liberação acontece apenas após a validação segura do webhook da Stripe.",
    };
  });
