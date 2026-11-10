// api/documents.js — Génération de documents professionnels (Vercel Node)
// L'utilisateur décrit le document, Gemini en produit la structure (JSON),
// puis on fabrique un vrai fichier .docx, .xlsx ou .pdf téléchargeable.
//
// POST /api/documents  { "prompt": "...", "format": "docx|pdf|xlsx" }

import {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, BorderStyle,
} from 'docx';
import ExcelJS from 'exceljs';
import { PDFDocument, StandardFonts, rgb } from 'pdf-lib';

export const config = { maxDuration: 60 };

const MODEL = 'gemini-3.5-flash-lite';
const FALLBACK_MODEL = 'gemini-3.5-flash';
const MAX_PROMPT = 2000;
const MAX_SECTIONS = 14;
const MAX_PARAGRAPHS = 14;
const MAX_BULLETS = 24;
const MAX_TABLE_ROWS = 60;
const MAX_TABLE_COLS = 8;
const MAX_SHEETS = 5;
const MAX_SHEET_ROWS = 300;

const MIME = {
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  pdf: 'application/pdf',
};

const EXT = { docx: 'docx', xlsx: 'xlsx', pdf: 'pdf' };

/* ---------- Schémas de sortie Gemini ---------- */

const TEXT_SCHEMA = {
  type: 'OBJECT',
  properties: {
    title: { type: 'STRING' },
    subtitle: { type: 'STRING' },
    author: { type: 'STRING' },
    sections: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          heading: { type: 'STRING' },
          paragraphs: { type: 'ARRAY', items: { type: 'STRING' } },
          bullets: { type: 'ARRAY', items: { type: 'STRING' } },
          table: {
            type: 'OBJECT',
            properties: {
              headers: { type: 'ARRAY', items: { type: 'STRING' } },
              rows: { type: 'ARRAY', items: { type: 'ARRAY', items: { type: 'STRING' } } },
            },
            required: ['headers', 'rows'],
          },
        },
        required: ['heading'],
      },
    },
  },
  required: ['title', 'sections'],
};

const SHEET_SCHEMA = {
  type: 'OBJECT',
  properties: {
    title: { type: 'STRING' },
    sheets: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          name: { type: 'STRING' },
          headers: { type: 'ARRAY', items: { type: 'STRING' } },
          rows: { type: 'ARRAY', items: { type: 'ARRAY', items: { type: 'STRING' } } },
        },
        required: ['name', 'headers', 'rows'],
      },
    },
  },
  required: ['title', 'sheets'],
};

const TEXT_PROMPT = `Tu es un rédacteur professionnel francophone.
Produis le contenu COMPLET et prêt à remettre du document demandé par l'utilisateur.
Règles :
- Rédige dans la langue de la demande (français par défaut), avec un style professionnel et soigné.
- Titre court et explicite. Sous-titre facultatif. Auteur facultatif.
- Entre 3 et 8 sections avec des titres clairs.
- Des paragraphes réellement rédigés (pas de « à compléter », pas de placeholders, pas de crochets).
- Des puces utiles et un ou deux tableaux quand c'est pertinent (comparatif, budget, planning…).
- Aucun commentaire, aucune explication hors du JSON demandé.`;

const SHEET_PROMPT = `Tu es un analyste qui prépare des classeurs Excel professionnels.
Produis les données COMPLÈTES du classeur demandé par l'utilisateur.
Règles :
- 1 à 4 feuilles maximum, avec des noms courts et explicites.
- Chaque feuille possède une ligne d'en-têtes puis des lignes de données réalistes et cohérentes.
- Les nombres doivent être écrits comme des nombres (ex. "1250.50"), sans symbole monétaire ni séparateur de milliers.
- Les dates au format AAAA-MM-JJ.
- Remplis suffisamment de lignes pour être utile (au moins 8 quand c'est pertinent).
- Aucun commentaire, aucune explication hors du JSON demandé.`;

/* ---------- Utilitaires ---------- */

const str = (v, max = 400) => String(v ?? '').replace(/\s+/g, ' ').trim().slice(0, max);
const lines = (v, max = 1200) =>
  String(v ?? '')
    .split(/\n+/)
    .map((s) => s.trim())
    .filter(Boolean)
    .slice(0, 12)
    .map((s) => s.slice(0, max));

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 200000) {
        reject(new Error('Requête trop volumineuse'));
        req.destroy();
      }
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(data || '{}'));
      } catch (e) {
        reject(new Error('JSON invalide'));
      }
    });
    req.on('error', reject);
  });
}

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader(
    'Access-Control-Expose-Headers',
    'Content-Disposition, X-Document-Title, X-Document-Format'
  );
}

function json(res, status, payload) {
  cors(res);
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(payload));
}

function slug(value) {
  const s = String(value || 'document')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase()
    .slice(0, 60);
  return s || 'document';
}

/* ---------- Appel Gemini ---------- */

async function callGemini(model, prompt, format, key, timeoutMs = 45000) {
  const isSheet = format === 'xlsx';
  const body = {
    systemInstruction: { parts: [{ text: isSheet ? SHEET_PROMPT : TEXT_PROMPT }] },
    contents: [{ role: 'user', parts: [{ text: prompt }] }],
    generationConfig: {
      responseMimeType: 'application/json',
      responseSchema: isSheet ? SHEET_SCHEMA : TEXT_SCHEMA,
      maxOutputTokens: 8192,
      temperature: 0.4,
    },
  };

  let res;
  try {
    res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      }
    );
  } catch (e) {
    throw Object.assign(new Error(`Gemini: ${e.message}`), { code: 'upstream', status: 504 });
  }

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    let detail = text.slice(0, 300);
    let status = res.status;
    try {
      const err = JSON.parse(text)?.error;
      detail = err?.message || detail;
      status = err?.status === 'RESOURCE_EXHAUSTED' ? 429 : status;
    } catch (_) {
      /* réponse non JSON */
    }
    const code = status === 429 ? 'quota' : 'upstream';
    throw Object.assign(new Error(detail), {
      code,
      status: code === 'quota' ? 429 : status === 503 ? 503 : 502,
    });
  }

  const data = await res.json();
  const candidate = data?.candidates?.[0];
  let raw = (candidate?.content?.parts || []).map((p) => p?.text || '').join('').trim();
  raw = raw.replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/i, '').trim();

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {
    throw Object.assign(
      new Error(`Réponse Gemini illisible${candidate?.finishReason ? ` (${candidate.finishReason})` : ''}`),
      { code: 'format', status: 502 }
    );
  }

  return isSheet ? normalizeSheetModel(parsed) : normalizeTextModel(parsed);
}

async function generateModel(prompt, format, key) {
  let lastError = null;
  const deadline = Date.now() + 52000;

  for (const model of [MODEL, FALLBACK_MODEL]) {
    for (let attempt = 0; attempt < 2; attempt++) {
      const remaining = deadline - Date.now();
      if (remaining < 5000) break;
      try {
        return await callGemini(model, prompt, format, key, Math.min(remaining, 45000));
      } catch (e) {
        lastError = e;
        // Contenu inexploitable : on arrête.
        if (e.code === 'format') throw e;
        // Quota atteint sur ce modèle : on passe au modèle suivant.
        if (e.code === 'quota') break;
        if (deadline - Date.now() < 3000) break;
        await new Promise((r) => setTimeout(r, 1200));
      }
    }
  }

  throw lastError;
}

function normalizeTextModel(m) {
  const sections = (Array.isArray(m?.sections) ? m.sections : [])
    .slice(0, MAX_SECTIONS)
    .map((s) => {
      const table = s?.table;
      const headers = Array.isArray(table?.headers)
        ? table.headers.slice(0, MAX_TABLE_COLS).map((h) => str(h, 80))
        : [];
      const rows = headers.length && Array.isArray(table?.rows)
        ? table.rows.slice(0, MAX_TABLE_ROWS).map((r) =>
            headers.map((_, i) => str(Array.isArray(r) ? r[i] : '', 200))
          )
        : [];
      return {
        heading: str(s?.heading, 160),
        paragraphs: (Array.isArray(s?.paragraphs) ? s.paragraphs : []).slice(0, MAX_PARAGRAPHS).flatMap((p) => lines(p)),
        bullets: (Array.isArray(s?.bullets) ? s.bullets : []).slice(0, MAX_BULLETS).map((b) => str(b, 400)),
        table: headers.length ? { headers, rows } : null,
      };
    })
    .filter((s) => s.heading || s.paragraphs.length || s.bullets.length || s.table);

  const model = {
    title: str(m?.title, 160) || 'Document',
    subtitle: str(m?.subtitle, 240),
    author: str(m?.author, 120),
    sections,
  };

  if (!model.sections.length) {
    throw Object.assign(new Error('Contenu vide'), { code: 'format', status: 502 });
  }
  return model;
}

function normalizeSheetModel(m) {
  const sheets = (Array.isArray(m?.sheets) ? m.sheets : [])
    .slice(0, MAX_SHEETS)
    .map((s, i) => {
      const headers = (Array.isArray(s?.headers) ? s.headers : [])
        .slice(0, 20)
        .map((h) => str(h, 80));
      const rows = (Array.isArray(s?.rows) ? s.rows : [])
        .slice(0, MAX_SHEET_ROWS)
        .map((r) => headers.map((_, c) => str(Array.isArray(r) ? r[c] : '', 300)));
      return {
        name: str(s?.name, 31) || `Feuille ${i + 1}`,
        headers,
        rows,
      };
    })
    .filter((s) => s.headers.length);

  if (!sheets.length) {
    throw Object.assign(new Error('Aucune donnée exploitable'), { code: 'format', status: 502 });
  }
  return { title: str(m?.title, 160) || 'Classeur', sheets };
}

/* ---------- Word (.docx) ---------- */

function docxCell(text, bold = false, fill = null) {
  return new TableCell({
    ...(fill ? { shading: { fill } } : {}),
    margins: { top: 80, bottom: 80, left: 100, right: 100 },
    children: [
      new Paragraph({
        children: [new TextRun({ text: text || ' ', bold, size: 19 })],
      }),
    ],
  });
}

function docxTable(table) {
  const borders = {
    top: { style: BorderStyle.SINGLE, size: 4, color: 'D1D5DB' },
    bottom: { style: BorderStyle.SINGLE, size: 4, color: 'D1D5DB' },
    left: { style: BorderStyle.SINGLE, size: 4, color: 'D1D5DB' },
    right: { style: BorderStyle.SINGLE, size: 4, color: 'D1D5DB' },
    insideHorizontal: { style: BorderStyle.SINGLE, size: 4, color: 'E5E7EB' },
    insideVertical: { style: BorderStyle.SINGLE, size: 4, color: 'E5E7EB' },
  };

  return new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    borders,
    rows: [
      new TableRow({
        tableHeader: true,
        children: table.headers.map((h) => docxCell(h, true, 'EFF6FF')),
      }),
      ...table.rows.map(
        (r) => new TableRow({ children: table.headers.map((_, i) => docxCell(r[i] || '')) })
      ),
    ],
  });
}

async function buildDocx(model) {
  const children = [];

  children.push(
    new Paragraph({
      children: [new TextRun({ text: model.title, bold: true, size: 44, color: '111827' })],
      spacing: { after: 120 },
    })
  );

  if (model.subtitle) {
    children.push(
      new Paragraph({
        children: [new TextRun({ text: model.subtitle, italics: true, size: 26, color: '4B5563' })],
        spacing: { after: 160 },
      })
    );
  }

  const meta = [model.author, new Date().toLocaleDateString('fr-FR')].filter(Boolean).join('  ·  ');
  children.push(
    new Paragraph({
      children: [new TextRun({ text: meta, size: 18, color: '6B7280' })],
      spacing: { after: 240 },
      border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: 'E5E7EB', space: 8 } },
    })
  );

  for (const s of model.sections) {
    if (s.heading) {
      children.push(
        new Paragraph({
          children: [new TextRun({ text: s.heading, bold: true, size: 28, color: '1F2937' })],
          heading: HeadingLevel.HEADING_1,
          spacing: { before: 280, after: 120 },
        })
      );
    }
    for (const p of s.paragraphs) {
      children.push(
        new Paragraph({
          children: [new TextRun({ text: p, size: 21 })],
          spacing: { after: 120, line: 300 },
          alignment: AlignmentType.JUSTIFIED,
        })
      );
    }
    for (const b of s.bullets) {
      children.push(
        new Paragraph({
          children: [new TextRun({ text: b, size: 21 })],
          bullet: { level: 0 },
          spacing: { after: 80, line: 290 },
        })
      );
    }
    if (s.table) {
      children.push(new Paragraph({ text: '', spacing: { after: 80 } }));
      children.push(docxTable(s.table));
      children.push(new Paragraph({ text: '', spacing: { after: 120 } }));
    }
  }

  const doc = new Document({
    creator: 'Makasi AI',
    title: model.title,
    description: model.subtitle || 'Document généré par Makasi AI',
    styles: {
      default: {
        document: { run: { font: 'Calibri', size: 21 } },
      },
    },
    sections: [
      {
        properties: {
          page: { margin: { top: 1000, bottom: 1000, left: 1100, right: 1100 } },
        },
        children,
      },
    ],
  });

  return Packer.toBuffer(doc);
}

/* ---------- Excel (.xlsx) ---------- */

function sheetName(name) {
  return (
    String(name || 'Feuille')
      .replace(/[\\/*?:[\]]/g, '-')
      .replace(/^'+|'+$/g, '')
      .trim()
      .slice(0, 31) || 'Feuille'
  );
}

function coerce(value) {
  const s = String(value ?? '').trim();
  if (!s) return '';
  if (/^-?\d{1,3}(?:[ .]\d{3})*(?:[.,]\d+)?$/.test(s) && !/^0\d/.test(s)) {
    const n = Number(s.replace(/[ .](?=\d{3}\b)/g, '').replace(',', '.'));
    if (Number.isFinite(n)) return n;
  }
  if (/^-?\d+(?:[.,]\d+)?$/.test(s)) {
    const n = Number(s.replace(',', '.'));
    if (Number.isFinite(n)) return n;
  }
  return s;
}

async function buildXlsx(model) {
  const wb = new ExcelJS.Workbook();
  wb.creator = 'Makasi AI';
  wb.created = new Date();

  model.sheets.forEach((sheet, index) => {
    const ws = wb.addWorksheet(sheetName(sheet.name), {
      views: [{ state: 'frozen', ySplit: 3 }],
      properties: { defaultRowHeight: 18 },
    });

    const colCount = Math.max(sheet.headers.length, 1);

    // Titre
    ws.mergeCells(1, 1, 1, colCount);
    const titleCell = ws.getCell(1, 1);
    titleCell.value = index === 0 ? model.title : sheet.name;
    titleCell.font = { bold: true, size: 14, color: { argb: 'FF1F2937' } };
    titleCell.alignment = { vertical: 'middle' };
    ws.getRow(1).height = 26;

    // En-têtes (ligne 3)
    const headerRow = ws.getRow(3);
    sheet.headers.forEach((h, i) => {
      const cell = headerRow.getCell(i + 1);
      cell.value = h;
      cell.font = { bold: true, color: { argb: 'FFFFFFFF' } };
      cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF2563EB' } };
      cell.alignment = { vertical: 'middle', horizontal: 'left', wrapText: true };
      cell.border = {
        top: { style: 'thin', color: { argb: 'FF1D4ED8' } },
        bottom: { style: 'thin', color: { argb: 'FF1D4ED8' } },
        left: { style: 'thin', color: { argb: 'FF1D4ED8' } },
        right: { style: 'thin', color: { argb: 'FF1D4ED8' } },
      };
    });
    headerRow.height = 24;

    // Données
    sheet.rows.forEach((row, r) => {
      const wsRow = ws.getRow(4 + r);
      row.forEach((value, c) => {
        const cell = wsRow.getCell(c + 1);
        cell.value = coerce(value);
        cell.alignment = { vertical: 'top', wrapText: true };
        cell.border = {
          bottom: { style: 'hair', color: { argb: 'FFE5E7EB' } },
        };
      });
    });

    // Largeurs de colonnes
    sheet.headers.forEach((h, i) => {
      const longest = Math.max(
        String(h).length,
        ...sheet.rows.map((r) => String(r[i] ?? '').length)
      );
      ws.getColumn(i + 1).width = Math.min(55, Math.max(12, longest + 2));
    });

    if (sheet.rows.length) {
      ws.autoFilter = {
        from: { row: 3, column: 1 },
        to: { row: 3, column: colCount },
      };
    }
  });

  return Buffer.from(await wb.xlsx.writeBuffer());
}

/* ---------- PDF ---------- */

const PDF_REPL = {
  '\u2019': "'", '\u2018': "'", '\u201C': '"', '\u201D': '"',
  '\u2013': '-', '\u2014': '-', '\u2026': '...', '\u20AC': 'EUR',
  '\u2022': '-', '\u0153': 'oe', '\u0152': 'OE', '\u00A0': ' ',
  '\u202F': ' ', '\u200B': '',
};

function pdfText(value) {
  return String(value ?? '')
    .replace(/[\u2019\u2018\u201C\u201D\u2013\u2014\u2026\u20AC\u2022\u0153\u0152\u00A0\u202F\u200B]/g, (c) => PDF_REPL[c] ?? '')
    .replace(/[^\x20-\x7E\u00A1-\u00FF]/g, '')
    .trim();
}

function wrapText(text, font, size, maxWidth) {
  const clean = pdfText(text);
  if (!clean) return [''];
  const words = clean.split(/\s+/);
  const out = [];
  let line = '';

  const push = (value) => {
    // Découpe les mots trop longs pour la largeur disponible
    if (font.widthOfTextAtSize(value, size) <= maxWidth) {
      out.push(value);
      return '';
    }
    let part = '';
    for (const ch of value) {
      if (font.widthOfTextAtSize(part + ch, size) > maxWidth && part) {
        out.push(part);
        part = ch;
      } else {
        part += ch;
      }
    }
    return part;
  };

  for (const word of words) {
    const test = line ? `${line} ${word}` : word;
    if (font.widthOfTextAtSize(test, size) <= maxWidth) {
      line = test;
    } else {
      if (line) out.push(line);
      line = push(word);
    }
  }
  if (line) out.push(line);
  return out.length ? out : [''];
}

async function buildPdf(model) {
  const pdf = await PDFDocument.create();
  pdf.setTitle(model.title);
  pdf.setCreator('Makasi AI');
  pdf.setProducer('Makasi AI');

  const font = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const italic = await pdf.embedFont(StandardFonts.HelveticaOblique);

  const W = 595.28;
  const H = 841.89;
  const M = 50;
  const maxW = W - M * 2;

  let page = pdf.addPage([W, H]);
  let y = H - M;

  const newPage = () => {
    page = pdf.addPage([W, H]);
    y = H - M;
  };
  const ensure = (h) => {
    if (y - h < M + 26) newPage();
  };

  const drawParagraph = (value, opts = {}) => {
    const size = opts.size || 10.5;
    const f = opts.font || font;
    const indent = opts.indent || 0;
    const lineH = opts.lineH || size * 1.45;
    const color = opts.color || rgb(0.13, 0.16, 0.21);
    const list = wrapText(value, f, size, maxW - indent);
    for (const line of list) {
      ensure(lineH);
      page.drawText(line, { x: M + indent, y: y - size, size, font: f, color });
      y -= lineH;
    }
    y -= opts.after ?? 4;
  };

  const drawTable = (table) => {
    const headers = table.headers.map(pdfText);
    const rows = table.rows.map((r) => headers.map((_, i) => pdfText(r[i] ?? '')));
    const n = headers.length;
    if (!n) return;

    const colW = maxW / n;
    const pad = 4;
    const size = 8.5;
    const lineH = size * 1.32;
    const border = rgb(0.82, 0.85, 0.89);

    const drawRow = (cells, isHeader) => {
      const f = isHeader ? bold : font;
      const wrapped = cells.map((c) => wrapText(c, f, size, colW - pad * 2));
      const height = Math.max(...wrapped.map((l) => l.length)) * lineH + pad * 2;

      if (y - height < M + 26) {
        newPage();
        if (!isHeader) drawRow(headers, true);
      }

      if (isHeader) {
        page.drawRectangle({
          x: M, y: y - height, width: maxW, height,
          color: rgb(0.93, 0.95, 0.98),
        });
      }

      wrapped.forEach((cellLines, i) => {
        cellLines.forEach((line, li) => {
          page.drawText(line, {
            x: M + i * colW + pad,
            y: y - pad - size - li * lineH,
            size, font: f, color: rgb(0.15, 0.18, 0.23),
          });
        });
        page.drawLine({
          start: { x: M + i * colW, y },
          end: { x: M + i * colW, y: y - height },
          thickness: 0.5, color: border,
        });
      });

      page.drawLine({
        start: { x: M, y: y - height },
        end: { x: M + maxW, y: y - height },
        thickness: 0.5, color: border,
      });
      y -= height;
    };

    ensure(30);
    drawRow(headers, true);
    rows.forEach((r) => drawRow(r, false));
    y -= 12;
  };

  // En-tête du document
  drawParagraph(model.title, { font: bold, size: 21, lineH: 27, color: rgb(0.07, 0.09, 0.13), after: 6 });
  if (model.subtitle) {
    drawParagraph(model.subtitle, { font: italic, size: 11.5, lineH: 16, color: rgb(0.29, 0.33, 0.41), after: 4 });
  }
  const meta = [model.author, new Date().toLocaleDateString('fr-FR')].filter(Boolean).join('   ·   ');
  drawParagraph(meta, { size: 8.5, lineH: 12, color: rgb(0.42, 0.45, 0.5), after: 2 });

  ensure(18);
  page.drawLine({
    start: { x: M, y },
    end: { x: M + maxW, y },
    thickness: 0.8,
    color: rgb(0.85, 0.87, 0.9),
  });
  y -= 22;

  for (const s of model.sections) {
    if (s.heading) {
      ensure(34);
      y -= 6;
      drawParagraph(s.heading, { font: bold, size: 13.5, lineH: 19, color: rgb(0.12, 0.16, 0.22), after: 4 });
      ensure(6);
      page.drawRectangle({
        x: M, y: y + 1, width: 42, height: 2.2,
        color: rgb(0.15, 0.39, 0.92),
      });
      y -= 8;
    }

    for (const p of s.paragraphs) {
      drawParagraph(p, { size: 10.5, lineH: 15.5, after: 6 });
    }

    for (const b of s.bullets) {
      ensure(14);
      page.drawText('-', { x: M + 2, y: y - 10, size: 10.5, font: bold, color: rgb(0.15, 0.39, 0.92) });
      drawParagraph(b, { size: 10.5, lineH: 15, indent: 14, after: 3 });
    }

    if (s.table) {
      y -= 2;
      drawTable(s.table);
      y -= 4;
    }
  }

  // Pied de page
  const pages = pdf.getPages();
  pages.forEach((p, i) => {
    const label = `Page ${i + 1} / ${pages.length}`;
    const width = font.widthOfTextAtSize(label, 8);
    p.drawText(label, {
      x: (W - width) / 2,
      y: 26,
      size: 8,
      font,
      color: rgb(0.55, 0.58, 0.63),
    });
    p.drawText('Makasi AI', {
      x: M,
      y: 26,
      size: 8,
      font,
      color: rgb(0.7, 0.72, 0.75),
    });
  });

  return Buffer.from(await pdf.save());
}

/* ---------- Handler ---------- */

export default async function handler(req, res) {
  cors(res);

  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return;
  }

  if (req.method !== 'POST') {
    return json(res, 405, { error: 'Méthode non autorisée.', code: 'method_not_allowed' });
  }

  let body;
  try {
    body = await readBody(req);
  } catch (e) {
    return json(res, 400, { error: e.message, code: 'invalid_request' });
  }

  const prompt = String(body.prompt || '').trim().slice(0, MAX_PROMPT);
  if (!prompt) {
    return json(res, 400, { error: 'Décrivez le document à créer.', code: 'invalid_request' });
  }

  const format = ['docx', 'xlsx', 'pdf'].includes(body.format) ? body.format : 'pdf';
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return json(res, 500, { error: 'Clé Gemini non configurée.', code: 'unavailable' });
  }

  try {
    const model = await generateModel(prompt, format, apiKey);
    const buffer =
      format === 'xlsx'
        ? await buildXlsx(model)
        : format === 'docx'
          ? await buildDocx(model)
          : await buildPdf(model);

    const filename = `${slug(model.title)}-makasi.${EXT[format]}`;

    res.statusCode = 200;
    res.setHeader('Content-Type', MIME[format]);
    res.setHeader('Content-Length', buffer.length);
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="${slug(model.title)}.${EXT[format]}"; filename*=UTF-8''${encodeURIComponent(filename)}`
    );
    res.setHeader('X-Document-Title', encodeURIComponent(model.title));
    res.setHeader('X-Document-Format', format);
    res.setHeader('Cache-Control', 'no-store');
    res.end(buffer);
  } catch (e) {
    const code = e?.code || 'unavailable';
    const status = e?.status && e.status >= 400 ? e.status : 500;
    const messages = {
      quota:
        "Le quota Gemini est épuisé. Activez la facturation sur votre projet Google AI puis réessayez.",
      format: "Le contenu n'a pas pu être structuré. Reformulez la demande.",
      upstream: 'Le service Gemini est momentanément indisponible. Réessayez.',
      unavailable: "Le document n'a pas pu être créé. Réessayez.",
    };
    return json(res, status, {
      error: messages[code] || messages.unavailable,
      code,
      detail: e?.message ? String(e.message).slice(0, 300) : undefined,
    });
  }
}
