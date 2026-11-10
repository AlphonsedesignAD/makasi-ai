// api/_keys.js — Lecture des clés Gemini (1 à N clés)
//
// Formats acceptés dans les variables d'environnement :
//   GEMINI_API_KEY=cle1
//   GEMINI_API_KEY_2=cle2
//   GEMINI_API_KEY_3=cle3 ...
//   GEMINI_API_KEYS=cle1,cle2,cle3
//
// Les deux formats peuvent être combinés ; les doublons sont ignorés.

export function geminiKeys() {
  const keys = [];

  const add = (value) => {
    if (!value) return;
    String(value)
      .split(/[\s,;]+/)
      .forEach((part) => {
        const key = part.trim();
        if (key && !keys.includes(key)) keys.push(key);
      });
  };

  add(process.env.GEMINI_API_KEY);
  add(process.env.GEMINI_API_KEYS);

  // GEMINI_API_KEY_2 … GEMINI_API_KEY_9
  for (let i = 2; i <= 9; i++) add(process.env[`GEMINI_API_KEY_${i}`]);

  return keys;
}
