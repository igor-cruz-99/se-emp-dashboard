/**
 * Interruptor de desenvolvimento: pula a tela de login para ajustar o visual
 * sem precisar autenticar a cada reload.
 *
 * Ligar/desligar em `.env.local` (`VITE_DEV_SKIP_AUTH=1` + `DEV_SKIP_AUTH=1`)
 * e reiniciar o `npm run dev`.
 *
 * A checagem `import.meta.env.DEV` garante que isso é removido do bundle de
 * produção pelo tree-shaking mesmo que a variável vaze para o ambiente da
 * Vercel. O lado servidor tem a mesma trava (`NODE_ENV !== 'production'`).
 */
export const DEV_SKIP_AUTH =
  import.meta.env.DEV && import.meta.env.VITE_DEV_SKIP_AUTH === '1'
