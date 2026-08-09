const STORAGE_KEY = "prepdot:mvp-state";
const DAILY_TARGET = 20;

const defaultSources = [
  {
    title: "个人简历 v1",
    type: "个人资料",
    category: "综合",
    desc: "用于生成自我介绍、项目追问和经历表达类卡片。",
  },
  {
    title: "Redis 项目复盘",
    type: "项目文档",
    category: "后端",
    desc: "缓存设计、数据一致性、限流和压测结果。",
  },
  {
    title: "前端面试基础卡包",
    type: "内置卡包",
    category: "前端",
    desc: "浏览器、工程化、React 和性能优化基础问题。",
  },
  {
    title: "产品经理面试表达",
    type: "导入卡包",
    category: "产品经理",
    desc: "需求分析、指标拆解、项目复盘和业务判断。",
  },
  {
    title: "Agent 开发入门",
    type: "通用知识",
    category: "Agent",
    desc: "工具调用、记忆、规划和评测的基础概念。",
  },
  {
    title: "计算机网络高频题",
    type: "内置卡包",
    category: "计算机基础",
    desc: "TCP、HTTP、DNS、HTTPS 和拥塞控制。",
  },
];

const defaultCards = [
  {
    question: "为什么你的项目要引入 Redis？",
    answer: "降低数据库压力，承接热点读取，并通过过期策略控制缓存生命周期。",
    category: "后端",
    source: "Redis 项目复盘",
    memory: 48,
  },
  {
    question: "React 中 key 的作用是什么？",
    answer: "帮助协调过程识别节点身份，减少不必要的重建和状态错乱。",
    category: "前端",
    source: "前端面试基础卡包",
    memory: 66,
  },
  {
    question: "如何拆解一个用户留存下降的问题？",
    answer: "先定位阶段和人群，再拆行为路径、供给变化、触达质量和外部因素。",
    category: "产品经理",
    source: "产品经理面试表达",
    memory: 37,
  },
  {
    question: "Agent 的工具调用为什么需要结果校验？",
    answer: "模型可能误用工具或误读结果，校验可以降低错误行动继续扩散的风险。",
    category: "Agent",
    source: "Agent 开发入门",
    memory: 55,
  },
  {
    question: "TCP 三次握手解决了什么问题？",
    answer: "确认双方收发能力和初始序列号，避免历史连接请求造成错误连接。",
    category: "后端",
    source: "计算机网络高频题",
    memory: 72,
  },
];

const savedState = loadState();
const sources = normalizeSources(savedState?.sources ?? defaultSources);
const seedCards = normalizeCards(savedState?.cards ?? defaultCards);
const deckCardMap = new Map(savedState?.deckCards ?? []);

let reviewCursor = savedState?.reviewCursor ?? 0;
let sessionStarted = savedState?.sessionStarted ?? false;
let selectedDeckIndex = savedState?.selectedDeckIndex ?? 1;
let selectedCardIndex = 0;
let activeReviewCards = [];
let activeReviewDeckIndex = null;

const views = document.querySelectorAll(".view");
const navItems = document.querySelectorAll(".nav-item");

initializeDeckCards();

function loadState() {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function saveState() {
  window.localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify({
      sources,
      cards: seedCards,
      deckCards: Array.from(deckCardMap.entries()),
      reviewCursor,
      sessionStarted,
      selectedDeckIndex,
    }),
  );
}

function makeId(prefix) {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function todayKey(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

function addDays(days) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return date.toISOString();
}

function normalizeSources(items) {
  return items.map((source) => ({
    id: source.id ?? makeId("deck"),
    title: source.title,
    type: source.type ?? "卡包",
    category: source.category ?? "综合",
    desc: source.desc ?? "",
    cards: source.cards ?? 0,
    reviewed: source.reviewed ?? 0,
  }));
}

function normalizeCards(items) {
  return items.map((card) => ({
    id: card.id ?? makeId("card"),
    question: card.question,
    answer: card.answer,
    category: card.category ?? "综合",
    source: card.source ?? "未分类",
    memory: clamp(card.memory ?? 35, 0, 100),
    due: card.due ?? "今天",
    reviewCount: card.reviewCount ?? 0,
    lastReviewedAt: card.lastReviewedAt ?? null,
    nextReviewAt: card.nextReviewAt ?? new Date().toISOString(),
  }));
}

function initializeDeckCards() {
  sources.forEach((deck) => {
    if (deckCardMap.has(deck.title)) {
      deckCardMap.set(deck.title, normalizeCards(deckCardMap.get(deck.title)));
      syncDeckStats(deck);
      return;
    }

    const exact = seedCards.filter((card) => card.source === deck.title);
    const categoryMatched = seedCards.filter((card) => card.category === deck.category);
    const fallback = exact.length ? exact : categoryMatched.length ? categoryMatched : seedCards.slice(0, 3);
    deckCardMap.set(
      deck.title,
      normalizeCards(fallback).map((card) => ({ ...card, source: deck.title })),
    );
    syncDeckStats(deck);
  });
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function switchView(viewName) {
  views.forEach((view) => view.classList.toggle("active", view.id === `view-${viewName}`));
  const activeNav = viewName === "review" ? "today" : viewName === "deck-detail" ? "cards" : viewName;
  navItems.forEach((item) => item.classList.toggle("active", item.dataset.view === activeNav));
}

function allCards() {
  return sources.flatMap((deck) => getDeckCards(deck));
}

function getDeckCards(deck = sources[selectedDeckIndex]) {
  if (!deckCardMap.has(deck.title)) {
    deckCardMap.set(deck.title, []);
  }
  return deckCardMap.get(deck.title);
}

function isReviewedToday(card) {
  return card.lastReviewedAt?.slice(0, 10) === todayKey();
}

function isDue(card) {
  return !card.nextReviewAt || new Date(card.nextReviewAt) <= new Date();
}

function sortForReview(cards) {
  return [...cards].sort((a, b) => {
    if (isDue(a) !== isDue(b)) return isDue(a) ? -1 : 1;
    if (a.memory !== b.memory) return a.memory - b.memory;
    return new Date(a.nextReviewAt ?? 0) - new Date(b.nextReviewAt ?? 0);
  });
}

function getTodayPlanCards() {
  const pool = sortForReview(allCards());
  const reviewedToday = pool.filter(isReviewedToday);
  const pendingDue = pool.filter((card) => !isReviewedToday(card) && isDue(card));
  const fillers = pool.filter((card) => !isReviewedToday(card) && !pendingDue.includes(card));
  return [...reviewedToday, ...pendingDue, ...fillers].slice(0, Math.min(DAILY_TARGET, pool.length));
}

function todayStats() {
  const plan = getTodayPlanCards();
  const completed = plan.filter(isReviewedToday).length;
  const total = plan.length;
  return {
    plan,
    completed,
    total,
    percent: total ? Math.round((completed / total) * 100) : 0,
  };
}

function renderToday() {
  const stats = todayStats();
  document.querySelector("#today-date").textContent = new Intl.DateTimeFormat("zh-CN", {
    month: "long",
    day: "numeric",
    weekday: "long",
  }).format(new Date());
  document.querySelector("#total-percent").textContent = `${stats.percent}%`;
  document.querySelector("#completed-count").textContent = `${stats.completed} / ${stats.total}`;
  document.querySelector("#today-progress-fill").style.width = `${stats.percent}%`;
  const startButton = document.querySelector("#start-review-button");
  startButton.textContent = stats.total > 0 && stats.completed >= stats.total ? "今日已完成" : sessionStarted ? "继续复习" : "开始复习";
  startButton.disabled = stats.total === 0 || stats.completed >= stats.total;
}

function renderSources() {
  document.querySelector("#source-grid").innerHTML = sources
    .map(
      (source) => `
        <article class="source-card">
          <span>${source.type} · ${source.category}</span>
          <h2>${source.title}</h2>
          <p>${source.desc}</p>
          <footer>
            <span>${source.cards} 张卡片</span>
            <button class="secondary-action" type="button">打开</button>
          </footer>
        </article>
      `,
    )
    .join("");
}

function memoryDot(value) {
  const opacity = Math.max(0.22, Math.min(1, value / 100));
  return `<span class="memory-dot" style="--memory-opacity:${opacity}" title="记忆度 ${value}%"></span>`;
}

function deckProgress(deck) {
  const deckCards = getDeckCards(deck);
  if (!deckCards.length) return 0;
  const sum = deckCards.reduce((total, card) => total + card.memory, 0);
  return Math.round(sum / deckCards.length);
}

function renderDecks(list = sources) {
  document.querySelector("#deck-grid").innerHTML = list
    .map((deck) => {
      const deckIndex = sources.indexOf(deck);
      const progress = deckProgress(deck);
      return `
        <article class="deck-cover" data-open-deck="${deckIndex}" tabindex="0">
          <div class="deck-cover-head">
            <span>${deck.type}</span>
            <strong>${progress}%</strong>
          </div>
          <h2>${deck.title}</h2>
          <p>${deck.category} · ${deck.cards} 张卡片</p>
          <div class="progress-track">
            <div class="progress-fill" style="width:${progress}%"></div>
          </div>
          <div class="deck-cover-actions">
            <button class="secondary-action" type="button" data-open-deck="${deckIndex}">查看详情</button>
            <button class="secondary-action" type="button" data-start-review>复习</button>
          </div>
        </article>
      `;
    })
    .join("");
}

function syncDeckStats(deck = sources[selectedDeckIndex]) {
  const deckCards = getDeckCards(deck);
  deck.cards = deckCards.length;
  deck.reviewed = deckCards.filter((card) => card.reviewCount > 0).length;
}

function showEditorStatus(message) {
  const status = document.querySelector("#editor-status");
  status.textContent = message;
  status.classList.add("visible");
  window.clearTimeout(showEditorStatus.timer);
  showEditorStatus.timer = window.setTimeout(() => {
    status.classList.remove("visible");
  }, 1600);
}

function renderDeckDetail() {
  const deck = sources[selectedDeckIndex];
  const deckCards = getDeckCards(deck);
  syncDeckStats(deck);
  selectedCardIndex = Math.min(selectedCardIndex, Math.max(deckCards.length - 1, 0));
  const progress = deckProgress(deck);
  const activeCard = deckCards[selectedCardIndex];

  document.querySelector("#deck-detail-title").textContent = deck.title;
  document.querySelector("#deck-detail-meta").textContent = `${deck.category} · ${deck.cards} 张卡片`;
  document.querySelector("#deck-detail-progress").style.width = `${progress}%`;
  document.querySelector("#deck-card-list").innerHTML = deckCards
    .map(
      (card, index) => `
        <button class="deck-card-item ${index === selectedCardIndex ? "active" : ""}" type="button" data-select-card="${index}">
          <strong>${card.question}</strong>
          <span>${memoryDot(card.memory)}${card.category}</span>
        </button>
      `,
    )
    .join("");

  document.querySelector("#save-card-edit").disabled = !activeCard;
  document.querySelector("#delete-card").disabled = !activeCard;
  document.querySelector("#reset-card-edit").disabled = !activeCard;
  if (!activeCard) {
    document.querySelector("#edit-question").value = "";
    document.querySelector("#edit-answer").value = "";
    document.querySelector("#edit-category").value = deck.category;
    document.querySelector("#editor-memory").innerHTML = "暂无卡片";
    return;
  }

  document.querySelector("#edit-question").value = activeCard.question;
  document.querySelector("#edit-answer").value = activeCard.answer;
  document.querySelector("#edit-category").value = activeCard.category;
  document.querySelector("#editor-memory").innerHTML = `${memoryDot(activeCard.memory)}记忆`;
}

function buildReviewQueue(deckIndex = null) {
  const pool = deckIndex === null ? getTodayPlanCards().filter((card) => !isReviewedToday(card)) : sortForReview(getDeckCards(sources[deckIndex]));
  const pending = pool.filter((card) => !isReviewedToday(card) && isDue(card));
  const fallback = pool.filter((card) => !pending.includes(card));
  return [...pending, ...fallback].slice(0, DAILY_TARGET);
}

function startReview(deckIndex = null) {
  activeReviewDeckIndex = deckIndex;
  activeReviewCards = buildReviewQueue(deckIndex);
  reviewCursor = 0;
  sessionStarted = true;
  saveState();
  renderReviewCard();
  renderToday();
  switchView("review");
}

function currentReviewCard() {
  if (!activeReviewCards.length) {
    activeReviewCards = buildReviewQueue(activeReviewDeckIndex);
  }
  return activeReviewCards[reviewCursor % Math.max(activeReviewCards.length, 1)];
}

function renderReviewCard() {
  const card = currentReviewCard();
  if (!card) {
    document.querySelector("#review-index").textContent = "0";
    document.querySelector("#review-total").textContent = "0";
    document.querySelector("#review-category").textContent = "今日完成";
    document.querySelector("#review-memory").innerHTML = "";
    document.querySelector("#review-question").textContent = "今天的卡片已经复习完了";
    document.querySelector("#review-answer").hidden = true;
    document.querySelector("#reveal-answer").textContent = "查看答案";
    renderRelations();
    return;
  }

  document.querySelector("#review-index").textContent = reviewCursor + 1;
  document.querySelector("#review-total").textContent = activeReviewCards.length;
  document.querySelector("#review-category").textContent = card.category;
  document.querySelector("#review-memory").innerHTML = `${memoryDot(card.memory)}记忆`;
  document.querySelector("#review-question").textContent = card.question;
  const answer = document.querySelector("#review-answer");
  answer.textContent = card.answer;
  answer.hidden = true;
  document.querySelector("#reveal-answer").textContent = "查看答案";
  renderRelations();
}

function renderRelations() {
  const card = currentReviewCard();
  const related = card
    ? allCards()
        .filter((item) => item.id !== card.id && (item.category === card.category || item.source === card.source))
        .slice(0, 8)
    : [];

  document.querySelector("#relation-dots").innerHTML = related
    .map(
      (item) => `
        <button
          class="relation-dot"
          type="button"
          style="--memory-opacity:${Math.max(0.22, Math.min(1, item.memory / 100))}"
          aria-label="${item.question}"
        >
          <span></span>
        </button>
      `,
    )
    .join("");
}

function applyRating(card, rating) {
  const rules = {
    again: { delta: -18, days: 0 },
    hard: { delta: 3, days: 1 },
    good: { delta: 12, days: card.reviewCount < 2 ? 2 : 4 },
    easy: { delta: 20, days: card.reviewCount < 2 ? 5 : 10 },
  };
  const rule = rules[rating] ?? rules.good;
  card.memory = clamp(card.memory + rule.delta, 0, 100);
  card.reviewCount += 1;
  card.lastReviewedAt = new Date().toISOString();
  card.nextReviewAt = rule.days === 0 ? new Date().toISOString() : addDays(rule.days);
  card.due = rule.days === 0 ? "今天" : `${rule.days} 天后`;
}

function rerenderAfterDataChange(message = null) {
  sources.forEach(syncDeckStats);
  saveState();
  renderToday();
  renderSources();
  renderDecks();
  renderDeckDetail();
  renderReviewCard();
  if (message) showEditorStatus(message);
}

function updateAiStatus() {
  const enabled = document.querySelector("#ai-enabled").checked;
  const hasKey = document.querySelector("#api-key").value.trim().length > 0;
  const status = enabled && hasKey ? "AI 已启用" : "未配置 API Key";
  document.querySelector("#ai-status").textContent = status;
}

navItems.forEach((item) => {
  item.addEventListener("click", () => switchView(item.dataset.view));
});

document.querySelectorAll("[data-view-jump]").forEach((button) => {
  button.addEventListener("click", () => switchView(button.dataset.viewJump));
});

document.querySelectorAll("[data-start-review]").forEach((trigger) => {
  trigger.addEventListener("click", () => {
    const deckIndex = trigger.closest("#view-deck-detail") ? selectedDeckIndex : null;
    startReview(deckIndex);
  });
});

document.addEventListener("click", (event) => {
  const deckButton = event.target.closest("#deck-grid [data-start-review]");
  if (deckButton) {
    const deckCover = deckButton.closest("[data-open-deck]");
    startReview(Number(deckCover.dataset.openDeck));
    return;
  }

  const deckOpen = event.target.closest("[data-open-deck]");
  if (deckOpen) {
    selectedDeckIndex = Number(deckOpen.dataset.openDeck);
    selectedCardIndex = 0;
    renderDeckDetail();
    switchView("deck-detail");
  }
});

document.querySelector("#deck-card-list").addEventListener("click", (event) => {
  const cardButton = event.target.closest("[data-select-card]");
  if (!cardButton) return;
  selectedCardIndex = Number(cardButton.dataset.selectCard);
  renderDeckDetail();
});

document.querySelector("#reset-card-edit").addEventListener("click", renderDeckDetail);

document.querySelector("#save-card-edit").addEventListener("click", () => {
  const deckCards = getDeckCards();
  const card = deckCards[selectedCardIndex];
  if (!card) return;
  card.question = document.querySelector("#edit-question").value.trim() || card.question;
  card.answer = document.querySelector("#edit-answer").value.trim() || card.answer;
  card.category = document.querySelector("#edit-category").value.trim() || card.category;
  rerenderAfterDataChange("已保存");
});

document.querySelector("#new-card").addEventListener("click", () => {
  const deck = sources[selectedDeckIndex];
  const deckCards = getDeckCards(deck);
  deckCards.push({
    id: makeId("card"),
    question: "新的面试问题",
    answer: "在这里填写答案。",
    category: deck.category,
    source: deck.title,
    memory: 0,
    due: "今天",
    reviewCount: 0,
    lastReviewedAt: null,
    nextReviewAt: new Date().toISOString(),
  });
  selectedCardIndex = deckCards.length - 1;
  rerenderAfterDataChange("已新增卡片");
});

document.querySelector("#delete-card").addEventListener("click", () => {
  const deckCards = getDeckCards();
  if (!deckCards.length) return;
  deckCards.splice(selectedCardIndex, 1);
  selectedCardIndex = Math.max(0, selectedCardIndex - 1);
  rerenderAfterDataChange("已删除");
});

document.querySelector("[data-exit-review]").addEventListener("click", () => {
  switchView("today");
  renderToday();
});

document.querySelector("#reveal-answer").addEventListener("click", (event) => {
  const answer = document.querySelector("#review-answer");
  answer.hidden = !answer.hidden;
  event.currentTarget.textContent = answer.hidden ? "查看答案" : "收起答案";
});

document.querySelectorAll("[data-rating]").forEach((button) => {
  button.addEventListener("click", () => {
    const card = currentReviewCard();
    if (!card) return;
    applyRating(card, button.dataset.rating);
    activeReviewCards = activeReviewCards.filter((item) => item.id !== card.id);
    reviewCursor = Math.min(reviewCursor, Math.max(activeReviewCards.length - 1, 0));
    rerenderAfterDataChange();
  });
});

document.querySelector("#card-search").addEventListener("input", (event) => {
  const keyword = event.target.value.trim().toLowerCase();
  const category = document.querySelector("#category-filter").value;
  const filtered = sources.filter((deck) => {
    const matchesKeyword = `${deck.title} ${deck.desc} ${deck.category} ${deck.type}`.toLowerCase().includes(keyword);
    const matchesCategory = category === "all" || deck.category === category;
    return matchesKeyword && matchesCategory;
  });
  renderDecks(filtered);
});

document.querySelector("#category-filter").addEventListener("change", () => {
  document.querySelector("#card-search").dispatchEvent(new Event("input"));
});

// 实时更新侧边栏 AI 状态
document.querySelector("#api-key").addEventListener("input", updateAiStatus);
document.querySelector("#ai-enabled").addEventListener("change", updateAiStatus);

renderToday();
renderSources();
renderDecks();
renderDeckDetail();
renderReviewCard();

// ============================================================
// SETTINGS PERSISTENCE
// ============================================================

const SETTINGS_KEY = "prepdot:settings";

function loadPersistedSettings() {
  try { return JSON.parse(localStorage.getItem(SETTINGS_KEY) ?? "{}"); }
  catch { return {}; }
}

function persistSettings(settings) {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
}

function getSettings() {
  return loadPersistedSettings();
}

// 启动时恢复设置
(function initSettings() {
  const s = loadPersistedSettings();
  if (s.apiKey)      document.querySelector("#api-key").value      = s.apiKey;
  if (s.modelName)   document.querySelector("#model-name").value   = s.modelName;
  if (s.aiEnabled != null) document.querySelector("#ai-enabled").checked = s.aiEnabled;
  if (s.dailyTarget) document.querySelector("#daily-target").value = s.dailyTarget;
  updateAiStatus();
}());

document.querySelector("#save-settings").addEventListener("click", () => {
  const s = {
    apiKey:      document.querySelector("#api-key").value.trim(),
    modelName:   document.querySelector("#model-name").value,
    aiEnabled:   document.querySelector("#ai-enabled").checked,
    dailyTarget: Number(document.querySelector("#daily-target").value),
  };
  persistSettings(s);
  updateAiStatus();
  showToast("设置已保存");
});

// ============================================================
// GLOBAL TOAST
// ============================================================

function showToast(message) {
  const el = document.querySelector("#global-toast");
  el.textContent = message;
  el.classList.add("visible");
  clearTimeout(showToast._t);
  showToast._t = setTimeout(() => el.classList.remove("visible"), 2600);
}

// ============================================================
// MODAL HELPERS
// ============================================================

function openModal(modal) { modal.hidden = false; }
function closeModal(modal) { modal.hidden = true; }

document.addEventListener("keydown", (e) => {
  if (e.key !== "Escape") return;
  [document.querySelector("#import-modal"), document.querySelector("#ai-modal")]
    .forEach((m) => { if (m && !m.hidden) closeModal(m); });
});

[document.querySelector("#import-modal"), document.querySelector("#ai-modal")].forEach((modal) => {
  modal.addEventListener("click", (e) => { if (e.target === modal) closeModal(modal); });
});

// ============================================================
// SHARED: FORMAT DETECTION + CARD NORMALIZATION
// ============================================================

function escapeHtml(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

const CATEGORY_OPTIONS = ["综合", "前端", "后端", "计算机基础", "产品经理", "Agent"];

function categorySelectHtml(selected, id) {
  return `<select id="${id}">${CATEGORY_OPTIONS.map((c) =>
    `<option value="${c}"${c === selected ? " selected" : ""}>${c}</option>`
  ).join("")}</select>`;
}

/**
 * 将原始 JSON 解析为统一的 { title, category, description, cards[], error? }
 * 支持格式：
 *   A. { title, category, description, cards: [...] }  PrepDot 原生
 *   B. [{ question, answer, category }, ...]           纯数组
 *   C. { deck, notes: [...] }                          Anki 风格
 *   字段别名：front/back、q/a、term/definition 均可识别
 */
function parseCardJson(data, filename) {
  const baseName = filename.replace(/\.json$/i, "");
  let rawCards = [], title = baseName, category = "综合", description = "", error = null;

  if (Array.isArray(data)) {
    rawCards = data;
  } else if (data && Array.isArray(data.cards)) {
    rawCards    = data.cards;
    title       = data.title || data.name || baseName;
    category    = data.category || "综合";
    description = data.description || data.desc || "";
  } else if (data && Array.isArray(data.notes)) {
    rawCards = data.notes;
    title    = data.deck || data.name || baseName;
  } else {
    error = "未找到有效的卡片数组。支持：{ cards:[...] } 或根数组 [...] 或 { notes:[...] }。";
    return { title, category, description, cards: [], error };
  }

  const cards = rawCards.map((c) => ({
    question: c.question || c.front || c.q || c.term       || "",
    answer:   c.answer   || c.back  || c.a || c.definition || "",
    category: c.category || category,
  })).filter((c) => c.question || c.answer);

  if (!cards.length) {
    error = "未找到有效卡片。字段需为 question/answer、front/back 或 q/a。";
  }
  return { title, category, description, cards, error };
}

function renderCardPreviewList(cards, limit = 4) {
  const preview = cards.slice(0, limit);
  return `
    <div class="import-preview-list">
      ${preview.map((c, i) => `
        <div class="import-preview-card">
          <span class="preview-label">Q${i + 1}</span>
          <div>
            <p class="preview-question">${escapeHtml(c.question || "（空）")}</p>
            <p class="preview-answer">${escapeHtml(c.answer || "（空）")}</p>
          </div>
        </div>
      `).join("")}
      ${cards.length > limit ? `<p class="import-more">……还有 ${cards.length - limit} 张</p>` : ""}
    </div>`;
}

/** 将卡片数组正式写入 sources + deckCardMap 并刷新界面 */
function commitImportedCards(cards, title, category, description = "") {
  const newSource = {
    id: makeId("deck"), title, type: "导入卡包", category,
    desc: description || `导入的卡包，共 ${cards.length} 张卡片。`,
    cards: 0, reviewed: 0,
  };
  sources.push(newSource);

  const newCards = cards.map((c) => ({
    id:             makeId("card"),
    question:       c.question,
    answer:         c.answer,
    category:       c.category || category,
    source:         title,
    memory:         35,
    due:            "今天",
    reviewCount:    0,
    lastReviewedAt: null,
    nextReviewAt:   new Date().toISOString(),
  }));

  deckCardMap.set(title, newCards);
  syncDeckStats(newSource);
  saveState();
  renderSources();
  renderDecks();
  renderToday();
  showToast(`✓ 已导入 ${newCards.length} 张卡片 · ${title}`);
}

// ============================================================
// IMPORT: JSON 文件导入
// ============================================================

let pendingImport = null;
const importModal     = document.querySelector("#import-modal");
const importFileInput = document.querySelector("#import-file-input");

document.querySelector("#import-deck-btn").addEventListener("click", () => {
  importFileInput.value = "";
  importFileInput.click();
});

importFileInput.addEventListener("change", (e) => {
  const file = e.target.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = (ev) => {
    let raw;
    try { raw = JSON.parse(ev.target.result); }
    catch {
      pendingImport = { error: "JSON 格式解析失败，请确认文件是否为合法 JSON。", cards: [], title: "", category: "综合", description: "" };
      renderImportPreview(pendingImport);
      openModal(importModal);
      return;
    }
    pendingImport = parseCardJson(raw, file.name);
    renderImportPreview(pendingImport);
    openModal(importModal);
  };
  reader.readAsText(file, "utf-8");
});

function renderImportPreview(data) {
  const body    = document.querySelector("#import-preview-content");
  const confirm = document.querySelector("#confirm-import");

  if (data.error) {
    body.innerHTML = `<p class="import-error">${escapeHtml(data.error)}</p>`;
    confirm.disabled = true;
    return;
  }
  confirm.disabled = false;

  body.innerHTML = `
    <div class="import-fields">
      <label>卡包名称<input type="text" id="import-title" value="${escapeHtml(data.title)}" /></label>
      <label>分类${categorySelectHtml(data.category, "import-category")}</label>
    </div>
    <p class="import-count">共检测到 <strong>${data.cards.length}</strong> 张卡片</p>
    ${renderCardPreviewList(data.cards)}
  `;
}

document.querySelector("#confirm-import").addEventListener("click", () => {
  if (!pendingImport || pendingImport.error || !pendingImport.cards.length) return;
  const title    = document.querySelector("#import-title")?.value.trim()  || pendingImport.title;
  const category = document.querySelector("#import-category")?.value      || pendingImport.category;
  commitImportedCards(pendingImport.cards, title, category, pendingImport.description);
  closeModal(importModal);
  pendingImport = null;
  switchView("cards");
});

[document.querySelector("#close-import-modal"), document.querySelector("#cancel-import")].forEach((btn) => {
  btn.addEventListener("click", () => { closeModal(importModal); pendingImport = null; });
});

// ============================================================
// AI: 调用 OpenAI 兼容接口生成卡片
// ============================================================

let aiResult = null;
const aiModal = document.querySelector("#ai-modal");

function setAiPhase(phase) {
  // phase: "input" | "loading" | "preview"
  document.querySelector("#ai-input-section").hidden    = phase !== "input";
  document.querySelector("#ai-loading-section").hidden  = phase !== "loading";
  document.querySelector("#ai-preview-section").hidden  = phase !== "preview";
  document.querySelector("#generate-ai-btn").hidden     = phase !== "input";
  document.querySelector("#confirm-ai-btn").hidden      = phase !== "preview";
  document.querySelector("#ai-back-btn").hidden         = phase !== "preview";
}

document.querySelector("#ai-gen-btn").addEventListener("click", () => {
  document.querySelector("#ai-deck-title").value     = "";
  document.querySelector("#ai-source-content").value = "";
  document.querySelector("#ai-gen-error").hidden     = true;
  aiResult = null;
  setAiPhase("input");
  openModal(aiModal);
});

document.querySelector("#generate-ai-btn").addEventListener("click", async () => {
  const content  = document.querySelector("#ai-source-content").value.trim();
  const category = document.querySelector("#ai-category").value;
  const count    = Math.min(30, Math.max(3, Number(document.querySelector("#ai-card-count").value) || 10));
  const errorEl  = document.querySelector("#ai-gen-error");

  if (!content) {
    errorEl.textContent = "请输入资料内容。";
    errorEl.hidden = false;
    return;
  }

  const s = getSettings();
  if (!s.apiKey || !s.aiEnabled) {
    errorEl.textContent = "AI 未启用或未配置 API Key，请先前往「设置」页完成配置后保存。";
    errorEl.hidden = false;
    return;
  }
  errorEl.hidden = true;

  setAiPhase("loading");
  try {
    const cards = await callAIGenerateCards({
      content, category, count,
      apiKey: s.apiKey,
      model:  s.modelName || "gpt-4.1-mini",
    });
    aiResult = {
      cards,
      title:    document.querySelector("#ai-deck-title").value.trim() || `AI · ${category}`,
      category,
    };
    document.querySelector("#ai-generated-count").textContent = cards.length;
    document.querySelector("#ai-preview-list").innerHTML = renderCardPreviewList(cards, 30);
    setAiPhase("preview");
  } catch (err) {
    errorEl.textContent = `生成失败：${err.message}`;
    errorEl.hidden = false;
    setAiPhase("input");
  }
});

document.querySelector("#ai-back-btn").addEventListener("click", () => setAiPhase("input"));

document.querySelector("#confirm-ai-btn").addEventListener("click", () => {
  if (!aiResult) return;
  commitImportedCards(aiResult.cards, aiResult.title, aiResult.category);
  closeModal(aiModal);
  aiResult = null;
  switchView("cards");
});

[document.querySelector("#close-ai-modal"), document.querySelector("#cancel-ai")].forEach((btn) => {
  btn.addEventListener("click", () => { closeModal(aiModal); aiResult = null; });
});

/**
 * 调用 OpenAI Chat Completions 接口生成结构化闪卡
 */
async function callAIGenerateCards({ content, category, count, apiKey, model }) {
  const systemPrompt =
    "你是专为求职面试准备设计的闪卡生成器。\n" +
    "规则：每张卡只考查一个知识点；问题用面试语境（如：为什么选…、如何解决…、区别是…）；" +
    "答案 2-4 句，简洁；优先生成高频追问；必须返回合法 JSON，不含任何 Markdown 标记。";

  const userPrompt =
    `请根据以下资料，为【${category}】方向生成 ${count} 张面试闪卡。\n\n` +
    `资料内容：\n${content}\n\n` +
    `只返回 JSON，格式：\n` +
    `{"cards":[{"question":"...","answer":"...","category":"${category}"}]}`;

  const resp = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user",   content: userPrompt   },
      ],
      temperature: 0.7,
    }),
  });

  if (!resp.ok) {
    const err = await resp.json().catch(() => ({}));
    throw new Error(err.error?.message || `HTTP ${resp.status}`);
  }

  const data   = await resp.json();
  const raw    = data.choices?.[0]?.message?.content ?? "";
  const parsed = extractJson(raw);

  if (!Array.isArray(parsed?.cards) || !parsed.cards.length) {
    throw new Error("模型未返回有效卡片数组，请检查 API Key 或重试。");
  }

  return parsed.cards
    .map((c) => ({ question: c.question || "", answer: c.answer || "", category: c.category || category }))
    .filter((c) => c.question && c.answer);
}

/**
 * 鲁棒 JSON 提取：直接解析 → 去掉 Markdown 代码块 → 截取首个 {} 块
 */
function extractJson(text) {
  try { return JSON.parse(text); } catch {}
  const block = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (block) { try { return JSON.parse(block[1]); } catch {} }
  const s = text.indexOf("{"), e = text.lastIndexOf("}");
  if (s !== -1 && e > s) { try { return JSON.parse(text.slice(s, e + 1)); } catch {} }
  throw new Error("无法从返回内容中解析出合法 JSON");
}
