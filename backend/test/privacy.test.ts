import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { BACKUP } from "../src/backups";
import { RETENTION } from "../src/retention";

/**
 * Сроки в политике конфиденциальности совпадают с кодом (GDPR, ст. 13(2)(a)):
 * меняешь срок в retention.ts — поменяй и в docs/legal, иначе тест упадёт.
 */
const LANGUAGES = ["ru", "pt", "en"] as const;
const policy = (language: string) =>
  readFileSync(new URL(`../../docs/legal/privacy.${language}.md`, import.meta.url), "utf8");

describe("политика конфиденциальности и сроки хранения", () => {
  for (const language of LANGUAGES) {
    const text = policy(language);

    it(`${language}: журнал расхода — ${RETENTION.usageLogDays} дней`, () => {
      expect(text).toContain(String(RETENTION.usageLogDays));
    });

    it(`${language}: устройство — ${RETENTION.inactiveDeviceDays / 30.4 | 0} месяцев без связи`, () => {
      expect(text).toContain(String(Math.round(RETENTION.inactiveDeviceDays / 30.4)));
    });

    it(`${language}: подписка — ${RETENTION.lapsedSubscriptionDays} дней после конца`, () => {
      expect(text).toContain(String(RETENTION.lapsedSubscriptionDays));
    });

    it(`${language}: облачных копий — ${BACKUP.keep}`, () => {
      expect(text).toContain(String(BACKUP.keep));
    });

    it(`${language}: обращения в поддержку упомянуты со сроком`, () => {
      expect(RETENTION.supportTicketDays).toBe(365);
      expect(text).toMatch(/Год после|Um ano após|One year after/);
    });

    it(`${language}: перечислены обработчики`, () => {
      for (const processor of ["Cloudflare", "Anthropic", "Apple"]) expect(text).toContain(processor);
    });

    it(`${language}: есть орган надзора и срок утечки`, () => {
      expect(text).toContain("CNPD");
      expect(text).toContain("72");
    });

    // Законы штатов США (P-75): срок ответа CCPA — 45 дней, запрет «продажи»
    // и возраст детей по COPPA — во всех трёх языках одинаково.
    it(`${language}: раздел для жителей США`, () => {
      expect(text).toContain("CCPA");
      expect(text).toContain("45");
      expect(text).toContain("COPPA");
      expect(text).toMatch(/Do Not Track/);
    });

    it(`${language}: группы возраста — как в законе Техаса`, () => {
      for (const group of ["13–15", "16–17", "18+"]) expect(text).toContain(group);
    });
  }
});
