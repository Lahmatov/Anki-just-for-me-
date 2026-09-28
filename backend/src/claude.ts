import Anthropic from "@anthropic-ai/sdk";
import { ApiError } from "./http";

/** Один запрос к модели: система, реплики, схема ответа. */
export interface ClaudeCall {
  system: string;
  messages: { role: "user" | "assistant"; content: string }[];
  maxTokens: number;
  schema: Record<string, unknown>;
}

export interface ClaudeResult {
  text: string;
  inputTokens: number;
  outputTokens: number;
}

export interface ClaudeLike {
  complete(call: ClaudeCall): Promise<ClaudeResult>;
}

/** Ошибка модели, за которую уже заплачено: расход надо списать. */
export class PaidModelError extends ApiError {
  constructor(code: string, readonly inputTokens: number, readonly outputTokens: number) {
    super(502, code);
  }
}

/**
 * Клиент Anthropic. Ключ — только в секрете Worker. Ответ ограничен
 * JSON-схемой (structured outputs) и `max_tokens`: даже если кто-то
 * протащит в текст инструкцию, модель вернёт только слова или реплику.
 */
export function anthropicClaude(apiKey: string, model: string): ClaudeLike {
  const client = new Anthropic({ apiKey, maxRetries: 2, timeout: 60_000 });
  return {
    async complete(call) {
      let response: Anthropic.Message;
      try {
        response = await client.messages.create({
          model,
          max_tokens: call.maxTokens,
          system: call.system,
          messages: call.messages,
          output_config: { format: { type: "json_schema", schema: call.schema } },
        });
      } catch (error) {
        // Подробности ошибки поставщика клиенту не отдаются.
        if (error instanceof Anthropic.RateLimitError) throw new ApiError(503, "model_busy");
        if (error instanceof Anthropic.APIConnectionError) throw new ApiError(503, "model_unavailable");
        if (error instanceof Anthropic.APIError) {
          console.error("anthropic error", error.status);
          throw new ApiError(502, "model_error");
        }
        throw error;
      }

      const inputTokens = response.usage.input_tokens;
      const outputTokens = response.usage.output_tokens;
      if (response.stop_reason === "refusal") {
        throw new PaidModelError("model_refused", inputTokens, outputTokens);
      }
      if (response.stop_reason === "max_tokens") {
        throw new PaidModelError("model_truncated", inputTokens, outputTokens);
      }
      const text = response.content
        .map((block) => (block.type === "text" ? block.text : ""))
        .join("");
      return { text, inputTokens, outputTokens };
    },
  };
}
