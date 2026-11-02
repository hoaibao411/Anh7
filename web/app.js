"use strict";

/* =========================================================
   LƯU TRỮ DỮ LIỆU
   - Chạy trong app: lưu ra file data.json trên máy (qua Swift),
     Swift tự sao lưu mỗi ngày. Đây là nơi lưu CHÍNH.
   - Đồng thời ghi thêm vào localStorage làm bản dự phòng.
   - Mở bằng trình duyệt (Live Server): chỉ dùng localStorage.
   ========================================================= */
const DATA_KEYS = ["todos", "notes", "name", "theme"];

const store = (() => {
  const native = window.__NATIVE__ || null;
  const hasNative = !!(
    native &&
    window.webkit &&
    window.webkit.messageHandlers &&
    window.webkit.messageHandlers.store
  );
  const memory = {};

  // Đọc 1 khóa từ localStorage; trả về undefined nếu không có hoặc lỗi
  function readLocal(key) {
    try {
      const raw = localStorage.getItem(key);
      return raw === null ? undefined : JSON.parse(raw);
    } catch (error) {
      return undefined;
    }
  }

  function writeLocal(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch (error) {
      // Không ghi được localStorage: vẫn còn file trên máy (nếu chạy trong app)
    }
  }

  // Gửi toàn bộ dữ liệu cho Swift ghi ra file
  function saveToFile() {
    if (!hasNative) return;
    try {
      window.webkit.messageHandlers.store.postMessage({
        action: "save",
        data: JSON.stringify(memory)
      });
    } catch (error) {
      // Lỗi cầu nối: dữ liệu vẫn còn trong localStorage
    }
  }

  // Nạp dữ liệu khi khởi động: ưu tiên file trên máy, không có thì lấy localStorage
  const fileData = hasNative && native.data && typeof native.data === "object" ? native.data : null;
  if (fileData) {
    DATA_KEYS.forEach((key) => {
      if (key in fileData) memory[key] = fileData[key];
    });
  } else {
    DATA_KEYS.forEach((key) => {
      const value = readLocal(key);
      if (value !== undefined) memory[key] = value;
    });
    // Lần đầu dùng bản mới: chuyển dữ liệu cũ từ localStorage sang file
    if (Object.keys(memory).length > 0) saveToFile();
  }

  return {
    hasNative,
    path: hasNative ? native.path : "",
    get(key, fallback) {
      return key in memory ? memory[key] : fallback;
    },
    set(key, value) {
      memory[key] = value;
      writeLocal(key, value);
      saveToFile();
    },
    openFolder() {
      if (!hasNative) return;
      window.webkit.messageHandlers.store.postMessage({ action: "openFolder" });
    }
  };
})();

/* =========================================================
   TRẠNG THÁI ỨNG DỤNG
   ========================================================= */
const state = {
  todos: store.get("todos", []),   // [{ id, text, done, created }]
  notes: store.get("notes", []),   // [{ id, title, body, updated }]
  name: store.get("name", ""),
  theme: store.get("theme", "auto"),
  filter: "all",
  activeNoteId: null
};

const saveTodos = () => store.set("todos", state.todos);
const saveNotes = () => store.set("notes", state.notes);

/* =========================================================
   TIỆN ÍCH
   ========================================================= */
const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => document.querySelectorAll(selector);

// Tạo mã định danh ngắn, không trùng
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);

// Viết hoa chữ cái đầu mỗi từ: "thứ năm" -> "Thứ Năm"
const capitalize = (text) => text.replace(/(^|\s)\S/g, (c) => c.toUpperCase());

const formatTime = (timestamp) =>
  new Date(timestamp).toLocaleString("vi-VN", {
    hour: "2-digit",
    minute: "2-digit",
    day: "2-digit",
    month: "2-digit"
  });

const ICON_CHECK = '<svg viewBox="0 0 24 24"><polyline points="5 12 10 17 19 7"/></svg>';
const ICON_TRASH = '<svg viewBox="0 0 24 24"><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/></svg>';

// Thông báo nhỏ ở cuối màn hình
let toastTimer;
function toast(message) {
  const el = $("#toast");
  el.textContent = message;
  el.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove("show"), 1800);
}

/*
   Xác nhận bằng 2 lần bấm.
   Lý do: cửa sổ app (WKWebView) không hiện hộp thoại confirm()/alert()
   nếu không viết thêm code Swift, nên dùng cách đổi chữ trên nút.
*/
function confirmTwice(button, confirmLabel, action) {
  if (button._armed) {
    clearTimeout(button._armed.timer);
    button.textContent = button._armed.original;
    button.classList.remove("confirm");
    button._armed = null;
    action();
    return;
  }
  const original = button.textContent;
  button.textContent = confirmLabel;
  button.classList.add("confirm");
  button._armed = {
    original,
    timer: setTimeout(() => {
      button.textContent = original;
      button.classList.remove("confirm");
      button._armed = null;
    }, 3000)
  };
}

// Theo dõi lúc đang gõ tiếng Việt (bộ gõ đang ghép dấu) để Enter không gửi nhầm
function trackComposition(input) {
  input.dataset.composing = "0";
  input.addEventListener("compositionstart", () => (input.dataset.composing = "1"));
  input.addEventListener("compositionend", () => (input.dataset.composing = "0"));
}

/* =========================================================
   ĐIỀU HƯỚNG GIỮA CÁC TRANG
   ========================================================= */
function showView(name) {
  $$(".nav-item").forEach((btn) => btn.classList.toggle("active", btn.dataset.view === name));
  $$(".view").forEach((view) => view.classList.toggle("active", view.id === "view-" + name));
  if (name === "todo") $("#todo-input").focus();
}

$$(".nav-item").forEach((btn) => btn.addEventListener("click", () => showView(btn.dataset.view)));
$$("[data-goto]").forEach((btn) => btn.addEventListener("click", () => showView(btn.dataset.goto)));

/* =========================================================
   ĐỒNG HỒ & LỜI CHÀO
   ========================================================= */
function tick() {
  const now = new Date();
  const time = now.toLocaleTimeString("vi-VN", { hour: "2-digit", minute: "2-digit" });
  const date = capitalize(
    now.toLocaleDateString("vi-VN", { weekday: "long", day: "numeric", month: "long", year: "numeric" })
  );

  $("#clock-big").textContent = time;
  $("#clock-small").textContent = time;
  $("#clock-date").textContent = date;
  $("#today").textContent = date;

  const hour = now.getHours();
  let greeting;
  if (hour < 11) greeting = "Chào buổi sáng";
  else if (hour < 14) greeting = "Chào buổi trưa";
  else if (hour < 18) greeting = "Chào buổi chiều";
  else greeting = "Chào buổi tối";

  $("#greeting").textContent = state.name ? `${greeting}, ${state.name}` : greeting;
}

/* =========================================================
   TRANG TỔNG QUAN
   ========================================================= */
function renderHome() {
  const openCount = state.todos.filter((t) => !t.done).length;
  const doneCount = state.todos.length - openCount;

  $("#stat-open").textContent = openCount;
  $("#stat-done").textContent = doneCount;
  $("#stat-notes").textContent = state.notes.length;
  $("#badge-todo").textContent = openCount;
  $("#badge-notes").textContent = state.notes.length;

  const list = $("#recent-todos");
  list.innerHTML = "";
  const recent = state.todos.filter((t) => !t.done).slice(0, 5);

  if (recent.length === 0) {
    const li = document.createElement("li");
    li.className = "muted";
    li.textContent = "Không có việc nào đang chờ.";
    list.appendChild(li);
    return;
  }

  recent.forEach((todo) => {
    const li = document.createElement("li");
    const dot = document.createElement("span");
    dot.className = "dot";
    const text = document.createElement("span");
    text.textContent = todo.text; // textContent để chữ người dùng nhập không bị hiểu thành HTML
    li.append(dot, text);
    list.appendChild(li);
  });
}

/* =========================================================
   TRANG VIỆC CẦN LÀM
   ========================================================= */
function renderTodos() {
  const list = $("#todo-list");
  list.innerHTML = "";

  const items = state.todos.filter((t) => {
    if (state.filter === "open") return !t.done;
    if (state.filter === "done") return t.done;
    return true;
  });

  $("#todo-empty").hidden = items.length > 0;

  items.forEach((todo) => {
    const li = document.createElement("li");
    li.className = "todo-item" + (todo.done ? " done" : "");

    // Nút tròn đánh dấu xong
    const check = document.createElement("button");
    check.className = "check";
    check.title = todo.done ? "Đánh dấu chưa xong" : "Đánh dấu đã xong";
    check.innerHTML = ICON_CHECK;
    check.addEventListener("click", () => {
      todo.done = !todo.done;
      saveTodos();
      renderAll();
    });

    const text = document.createElement("span");
    text.className = "todo-text";
    text.textContent = todo.text;

    // Nút xóa (hiện khi rê chuột)
    const remove = document.createElement("button");
    remove.className = "icon-btn";
    remove.title = "Xóa";
    remove.innerHTML = ICON_TRASH;
    remove.addEventListener("click", () => {
      state.todos = state.todos.filter((t) => t.id !== todo.id);
      saveTodos();
      renderAll();
      toast("Đã xóa việc");
    });

    li.append(check, text, remove);
    list.appendChild(li);
  });
}

const todoInput = $("#todo-input");
trackComposition(todoInput);

$("#todo-form").addEventListener("submit", (event) => {
  event.preventDefault();
  if (todoInput.dataset.composing === "1") return;
  const text = todoInput.value.trim();
  if (!text) return;
  state.todos.unshift({ id: uid(), text, done: false, created: Date.now() });
  todoInput.value = "";
  saveTodos();
  renderAll();
});

$$(".chip").forEach((chip) =>
  chip.addEventListener("click", () => {
    state.filter = chip.dataset.filter;
    $$(".chip").forEach((c) => c.classList.toggle("active", c === chip));
    renderTodos();
  })
);

/* =========================================================
   TRANG GHI CHÚ
   ========================================================= */
// Trả về ghi chú đang chọn; nếu không hợp lệ thì chọn ghi chú đầu tiên
function getActiveNote() {
  let note = state.notes.find((n) => n.id === state.activeNoteId);
  if (!note && state.notes.length > 0) {
    note = state.notes[0];
    state.activeNoteId = note.id;
  }
  return note || null;
}

function renderNoteList() {
  const list = $("#note-list");
  list.innerHTML = "";
  const active = getActiveNote();

  if (state.notes.length === 0) {
    const li = document.createElement("li");
    li.className = "muted";
    li.textContent = "Danh sách trống";
    list.appendChild(li);
    return;
  }

  state.notes.forEach((note) => {
    const li = document.createElement("li");
    if (active && note.id === active.id) li.classList.add("active");

    const title = document.createElement("div");
    title.className = "note-item-title";
    title.textContent = note.title.trim() || "Ghi chú không tên";

    const preview = document.createElement("div");
    preview.className = "note-item-preview";
    preview.textContent = note.body.trim().split("\n")[0] || "Chưa có nội dung";

    li.append(title, preview);
    li.addEventListener("click", () => {
      state.activeNoteId = note.id;
      renderNoteList();
      renderNoteEditor();
    });
    list.appendChild(li);
  });
}

function renderNoteEditor() {
  const note = getActiveNote();
  const editor = $("#note-editor");

  if (!note) {
    editor.hidden = true;
    $("#note-empty").hidden = false;
    editor.dataset.id = "";
    return;
  }

  editor.hidden = false;
  $("#note-empty").hidden = true;

  // Chỉ nạp lại nội dung khi đổi sang ghi chú khác, tránh làm nhảy con trỏ khi đang gõ
  if (editor.dataset.id !== note.id) {
    $("#note-title").value = note.title;
    $("#note-body").value = note.body;
    editor.dataset.id = note.id;
  }
  $("#note-status").textContent = "Sửa lúc " + formatTime(note.updated);
}

function createNote() {
  const note = { id: uid(), title: "", body: "", updated: Date.now() };
  state.notes.unshift(note);
  state.activeNoteId = note.id;
  saveNotes();
  renderAll();
  showView("notes");
  $("#note-title").focus();
}

$("#note-new").addEventListener("click", createNote);
$("#note-empty-new").addEventListener("click", createNote);

// Lưu NGAY mỗi lần gõ (để thoát app đột ngột cũng không mất chữ);
// chỉ phần vẽ lại danh sách được hoãn 400ms cho mượt
let noteRenderTimer;
function handleNoteInput() {
  const note = getActiveNote();
  if (!note) return;
  note.title = $("#note-title").value;
  note.body = $("#note-body").value;
  note.updated = Date.now();
  saveNotes();
  $("#note-status").textContent = "Đã lưu lúc " + formatTime(note.updated);
  clearTimeout(noteRenderTimer);
  noteRenderTimer = setTimeout(() => {
    renderNoteList();
    renderHome();
  }, 400);
}

$("#note-title").addEventListener("input", handleNoteInput);
$("#note-body").addEventListener("input", handleNoteInput);

$("#note-delete").addEventListener("click", (event) => {
  confirmTwice(event.currentTarget, "Nhấn lần nữa để xóa", () => {
    state.notes = state.notes.filter((n) => n.id !== state.activeNoteId);
    state.activeNoteId = null;
    saveNotes();
    renderAll();
    toast("Đã xóa ghi chú");
  });
});

/* =========================================================
   TRANG CÀI ĐẶT
   ========================================================= */
function applyTheme(theme) {
  state.theme = theme;
  store.set("theme", theme);
  if (theme === "auto") {
    document.documentElement.removeAttribute("data-theme");
  } else {
    document.documentElement.setAttribute("data-theme", theme);
  }
  $$("#theme-switch button").forEach((btn) =>
    btn.classList.toggle("active", btn.dataset.themeValue === theme)
  );
}

$$("#theme-switch button").forEach((btn) =>
  btn.addEventListener("click", () => applyTheme(btn.dataset.themeValue))
);

const nameInput = $("#name-input");
nameInput.addEventListener("input", () => {
  state.name = nameInput.value.trim();
  store.set("name", state.name);
  tick();
});

// Hiển thị nơi đang lưu dữ liệu + nút mở thư mục
function renderStorageInfo() {
  const info = $("#storage-info");
  const pathEl = $("#storage-path");
  const button = $("#open-data");
  if (store.hasNative) {
    info.textContent = "Tự lưu ra file trên máy, tự sao lưu mỗi ngày (giữ 30 ngày gần nhất).";
    pathEl.textContent = store.path;
    pathEl.hidden = false;
    button.hidden = false;
  } else {
    info.textContent = "Đang chạy ngoài app: dữ liệu chỉ lưu trong trình duyệt.";
    pathEl.hidden = true;
    button.hidden = true;
  }
}

$("#open-data").addEventListener("click", () => store.openFolder());

$("#reset-all").addEventListener("click", (event) => {
  confirmTwice(event.currentTarget, "Nhấn lần nữa để xóa hết", () => {
    state.todos = [];
    state.notes = [];
    state.name = "";
    state.activeNoteId = null;
    saveTodos();
    saveNotes();
    store.set("name", "");
    nameInput.value = "";
    tick();
    renderAll();
    toast("Đã xóa toàn bộ dữ liệu");
  });
});

/* =========================================================
   KHỞI ĐỘNG
   ========================================================= */
function renderAll() {
  renderHome();
  renderTodos();
  renderNoteList();
  renderNoteEditor();
}

applyTheme(state.theme);
renderStorageInfo();
nameInput.value = state.name;
tick();
setInterval(tick, 1000);
renderAll();
