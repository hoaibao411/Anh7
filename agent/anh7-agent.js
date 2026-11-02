// =========================================================
// TRỢ LÝ ANH 7 — chạy BÊN TRONG máy ảo macOS
// Ngôn ngữ: JavaScript for Automation (có sẵn trong macOS, chạy bằng osascript)
//
// Giao tiếp với app Anh 7 qua thư mục chia sẻ:
//   /Volumes/My Shared Files/.anh7/apps.json     <- danh sách app (tên, đường dẫn, icon)
//   /Volumes/My Shared Files/.anh7/agent.json    <- "nhịp tim": cho Anh 7 biết trợ lý đang chạy
//   /Volumes/My Shared Files/.anh7/launch/*.json -> yêu cầu mở app từ Win12
// Chỉ mở app nằm trong danh sách đã quét, không chạy lệnh tùy ý.
// =========================================================
ObjC.import('AppKit');
ObjC.import('Foundation');

const VERSION = 1;
const SHARE = '/Volumes/My Shared Files';
const DIR = SHARE + '/.anh7';
const LAUNCH_DIR = DIR + '/launch';
const fm = $.NSFileManager.defaultManager;
const ws = $.NSWorkspace.sharedWorkspace;
const HOME = ObjC.unwrap($.NSHomeDirectory());

const APP_FOLDERS = [
  '/Applications',
  '/Applications/Utilities',
  '/System/Applications',
  '/System/Applications/Utilities',
  HOME + '/Applications',
];

let allowed = {};      // đường dẫn app hợp lệ
let lastScan = 0;

function exists(path) { return fm.fileExistsAtPath(path); }

function ensureDirs() {
  fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(LAUNCH_DIR, true, $(), $());
}

function writeText(path, text) {
  $(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, $());
}

function readText(path) {
  const s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, $());
  return s.isNil() ? null : ObjC.unwrap(s);
}

function list(dir) {
  const arr = fm.contentsOfDirectoryAtPathError(dir, $());
  return arr.isNil() ? [] : ObjC.deepUnwrap(arr);
}

// Icon app -> PNG 64x64 dạng base64
function iconBase64(path) {
  try {
    const size = $.NSMakeSize(64, 64);
    const rect = $.NSMakeRect(0, 0, 64, 64);
    const icon = ws.iconForFile(path);
    const canvas = $.NSImage.alloc.initWithSize(size);
    canvas.lockFocus;
    icon.drawInRectFromRectOperationFraction(rect, $.NSZeroRect, $.NSCompositingOperationSourceOver, 1.0);
    const rep = $.NSBitmapImageRep.alloc.initWithFocusedViewRect(rect);
    canvas.unlockFocus;
    const png = rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $());
    return ObjC.unwrap(png.base64EncodedStringWithOptions(0));
  } catch (e) {
    return '';
  }
}

// Quét app trong các thư mục Ứng dụng (kể cả 1 cấp thư mục con)
function scanApps() {
  const found = [];
  const seen = {};
  function add(path) {
    if (seen[path]) return;
    seen[path] = true;
    let name = ObjC.unwrap(fm.displayNameAtPath(path));
    if (name.endsWith('.app')) name = name.slice(0, -4);
    found.push({ name: name, path: path, icon: iconBase64(path) });
  }
  APP_FOLDERS.forEach(function (folder) {
    list(folder).forEach(function (item) {
      if (item.startsWith('.')) return;
      const full = folder + '/' + item;
      if (item.endsWith('.app')) add(full);
      else {
        const isDir = Ref();
        if (fm.fileExistsAtPathIsDirectory(full, isDir) && isDir[0]) {
          list(full).forEach(function (sub) { if (sub.endsWith('.app')) add(full + '/' + sub); });
        }
      }
    });
  });
  found.sort(function (a, b) { return a.name.localeCompare(b.name); });
  allowed = {};
  found.forEach(function (a) { allowed[a.path] = true; });
  writeText(DIR + '/apps.json', JSON.stringify({ version: VERSION, time: Date.now(), apps: found }));
}

// Xử lý yêu cầu mở app do Win12 gửi vào
function handleLaunches() {
  list(LAUNCH_DIR).forEach(function (file) {
    if (!file.endsWith('.json')) return;
    const full = LAUNCH_DIR + '/' + file;
    let req = null;
    try { req = JSON.parse(readText(full) || 'null'); } catch (e) {}
    fm.removeItemAtPathError(full, $());
    if (!req || typeof req.path !== 'string') return;
    if (!allowed[req.path]) { scanApps(); }           // app mới cài: quét lại rồi kiểm tra
    if (!allowed[req.path]) return;                   // vẫn không có -> bỏ qua
    ws.openURL($.NSURL.fileURLWithPath(req.path));
  });
}

function run() {
  while (true) {
    if (exists(SHARE)) {
      ensureDirs();
      const now = Date.now();
      if (now - lastScan > 60000) { scanApps(); lastScan = now; }   // quét lại mỗi phút
      handleLaunches();
      writeText(DIR + '/agent.json', JSON.stringify({ version: VERSION, time: now }));
    }
    delay(1.5);
  }
}
