import { serve } from "@hono/node-server";
import { app } from "./routes.js";
import { startQueue } from "./queue.js";

const PORT = Number(process.env.PORT ?? 8620);

startQueue();

serve({ fetch: app.fetch, port: PORT, hostname: "0.0.0.0" }, (info) => {
  console.log(`[dramaflow] server listening on http://127.0.0.1:${info.port}`);
});
