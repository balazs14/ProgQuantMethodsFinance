const crypto = require("crypto");
const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const { isDeepStrictEqual } = require("util");
const vscode = require("vscode");

const EXTENSION_HEARTBEAT = ".pqmf-exam-guard-extension-heartbeat";
const SCRIPT_HEARTBEAT = ".pqmf-exam-guard-script-heartbeat";
const GUARD_LOG = ".pqmf-exam-guard.log";
const SETUP_MARKER = ".pqmf-exam-guard-setup";
const SETUP_MARKER_MAX_AGE_MS = 60_000;
const HEARTBEAT_GRACE_MS = 20_000;
const HEARTBEAT_STALE_MS = 20_000;
const FOCUS_GRACE_MS = 10_000;
const FULLSCREEN_STARTUP_GRACE_MS = 15_000;
const RUNTIME_VSCODE_FILES = new Set([
  ".vscode/settings.json",
  ".vscode/.ai-extension-detected",
  ".vscode/.ai-extension-detected.outside-file",
  `.vscode/${EXTENSION_HEARTBEAT}`,
  `.vscode/${SCRIPT_HEARTBEAT}`,
  `.vscode/${GUARD_LOG}`,
]);
const POLICY_KEYS = [
  "chat.disableAIFeatures",
  "chat.commandCenter.enabled",
  "github.copilot.enable",
  "github.copilot.inlineSuggest.enable",
  "github.copilot.nextEditSuggestions.enabled",
  "github.copilot.editor.enableCodeActions",
  "editor.inlineSuggest.enabled",
  "editor.inlineSuggest.suppressSuggestions",
  "extensions.allowed",
  "files.exclude",
  "search.exclude",
];
const OUT_OF_FOCUS_CHECK_DISABLED_KEY = "pqmfExamGuard.disableOutOfFocusCheck";
const OUTSIDE_WORKSPACE_CHECK_DISABLED_KEY =
  "pqmfExamGuard.disableOutsideWorkspaceCheck";
const NORMAL_COLORS = {
  "editor.background": "#183D2F",
  "notebook.editorBackground": "#183D2F",
  "notebook.cellEditorBackground": "#1e1e1e",
  "statusBar.background": "#1f2937",
  "statusBar.foreground": "#f9fafb",
  "titleBar.activeBackground": "#111827",
  "titleBar.activeForeground": "#f9fafb",
  "activityBar.background": "#1f2937",
  "activityBar.foreground": "#f9fafb",
};
const VIOLATION_COLORS = {
  "statusBar.background": "#ff1493",
  "statusBar.foreground": "#ffffff",
  "titleBar.activeBackground": "#ff1493",
  "titleBar.activeForeground": "#ffffff",
  "activityBar.background": "#ff1493",
  "activityBar.foreground": "#ffffff",
  "sideBar.background": "#ffb6c1",
  "sideBar.foreground": "#000000",
};

const warnedWorkspaceRoots = new Set();
const loggedViolationReasons = new Set();
let activatedAt = Date.now();
let activeContext;
let activeExamRoot;
let guardOutput;
let guardLogOffset = 0;
let guardViolationStatus;
let guardResetStatus;
let lastDisplayedMarkerReason;
let setupPauseLogged = false;
let focusLossTimer;
let fullscreenArmedAt = Number.POSITIVE_INFINITY;
let fullscreenCheckAvailable = true;
let resetInProgress = false;

function workspaceRoot() {
  const folder =
    vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  return folder ? folder.uri.fsPath : undefined;
}

function vscodeDir(root) {
  return path.join(root, ".vscode");
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return undefined;
  }
}

function baseSettings(root) {
  return readJson(path.join(vscodeDir(root), "settings.base.json"));
}

function isExamWorkspace(root = workspaceRoot()) {
  if (!root) return false;
  if (activeExamRoot && path.resolve(root) === path.resolve(activeExamRoot)) {
    return true;
  }
  const settings =
    baseSettings(root) || readJson(path.join(vscodeDir(root), "settings.json"));
  return (
    settings &&
    Object.prototype.hasOwnProperty.call(
      settings,
      OUTSIDE_WORKSPACE_CHECK_DISABLED_KEY,
    )
  );
}

function normalizePath(filePath) {
  const resolved = fs.existsSync(filePath)
    ? fs.realpathSync(filePath)
    : path.resolve(filePath);
  return process.platform === "win32" ? resolved.toLowerCase() : resolved;
}

function isInsideWorkspace(filePath, rootPath) {
  const root = normalizePath(rootPath);
  const candidate = normalizePath(filePath);
  return candidate === root || candidate.startsWith(root + path.sep);
}

function urisFromTabInput(input) {
  return input
    ? [input.uri, input.original, input.modified].filter(Boolean)
    : [];
}

function markerPath(root) {
  return path.join(vscodeDir(root), ".ai-extension-detected");
}

function launcherSetupInProgress(root) {
  const setupMarker = path.join(root, SETUP_MARKER);
  try {
    if (
      Date.now() - fs.statSync(setupMarker).mtimeMs <=
      SETUP_MARKER_MAX_AGE_MS
    ) {
      return true;
    }
    fs.unlinkSync(setupMarker);
  } catch {
    // Missing or already-cleaned setup markers mean normal enforcement.
  }
  return false;
}

function guardLogPath(root) {
  return path.join(vscodeDir(root), GUARD_LOG);
}

function syncGuardLogToOutput(root) {
  if (!guardOutput) return;
  try {
    const contents = fs.readFileSync(guardLogPath(root));
    if (contents.length < guardLogOffset) guardLogOffset = 0;
    if (contents.length > guardLogOffset) {
      guardOutput.append(contents.subarray(guardLogOffset).toString("utf8"));
      guardLogOffset = contents.length;
    }
  } catch (error) {
    if (error.code !== "ENOENT") {
      guardOutput.appendLine(
        `${new Date().toISOString()} [extension] WARN Could not read shared guard log: ${error.message}`,
      );
    }
  }
}

function appendGuardLog(root, source, level, message) {
  const entry = `${new Date().toISOString()} [${source}] ${level} ${String(message).replace(/\r?\n/g, " | ")}\n`;
  const logFile = guardLogPath(root);
  try {
    fs.appendFileSync(logFile, entry, "utf8");
  } catch {
    try {
      fs.chmodSync(logFile, 0o644);
      fs.appendFileSync(logFile, entry, "utf8");
    } catch {
      if (guardOutput) guardOutput.append(entry);
      return;
    }
  }
  syncGuardLogToOutput(root);
}

function showGuardLog() {
  const root = activeExamRoot || workspaceRoot();
  if (root) syncGuardLogToOutput(root);
  if (guardOutput) guardOutput.show(false);
}

function updateViolationControls(root, revealNew = false) {
  if (!guardViolationStatus || !guardResetStatus) return;
  let reason;
  try {
    reason = fs.readFileSync(markerPath(root), "utf8").trim();
  } catch {
    guardViolationStatus.hide();
    guardResetStatus.hide();
    lastDisplayedMarkerReason = undefined;
    return;
  }
  const summary = reason.split(/\r?\n/, 1)[0];
  guardViolationStatus.text = `$(warning) Exam violation: ${summary.slice(0, 70)}`;
  guardViolationStatus.tooltip = `PQMF Exam Guard violation\n\n${reason}\n\nClick to show the complete audit log.`;
  guardViolationStatus.show();
  guardResetStatus.show();
  if (revealNew && reason !== lastDisplayedMarkerReason) {
    lastDisplayedMarkerReason = reason;
    showGuardLog();
  }
}

function recordViolation(reason) {
  const root = workspaceRoot();
  if (!root || !isExamWorkspace(root) || launcherSetupInProgress(root)) return;
  try {
    const marker = markerPath(root);
    if (!fs.existsSync(marker)) fs.writeFileSync(marker, `${reason}\n`, "utf8");
    const rootKey = normalizePath(root);
    const reasonKey = `${rootKey}\0${reason}`;
    if (!loggedViolationReasons.has(reasonKey)) {
      loggedViolationReasons.add(reasonKey);
      appendGuardLog(root, "extension", "VIOLATION", reason);
    }
    updateViolationControls(root, true);
    if (!warnedWorkspaceRoots.has(rootKey)) {
      warnedWorkspaceRoots.add(rootKey);
      void vscode.window
        .showWarningMessage(
          "The exam-workspace policy was violated. The workspace has been marked for instructor reset.",
          "Show Log",
        )
        .then((selection) => {
          if (selection === "Show Log") showGuardLog();
        });
    }
  } catch {
    // The independent script watcher can still record the violation.
  }
}

function writeExtensionHeartbeat(root) {
  const heartbeat = path.join(vscodeDir(root), EXTENSION_HEARTBEAT);
  try {
    fs.writeFileSync(heartbeat, `${Date.now()}\n`, "utf8");
  } catch {
    try {
      fs.chmodSync(heartbeat, 0o644);
      fs.writeFileSync(heartbeat, `${Date.now()}\n`, "utf8");
    } catch {
      // The in-memory watchdog continues even if recovery is impossible.
    }
  }
}

function clearRuntimeWatchdogState(root) {
  for (const fileName of [EXTENSION_HEARTBEAT, SCRIPT_HEARTBEAT]) {
    const filePath = path.join(vscodeDir(root), fileName);
    try {
      fs.chmodSync(filePath, 0o644);
    } catch {
      // The runtime file may not exist yet.
    }
    try {
      fs.unlinkSync(filePath);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  fs.rmSync(path.join(vscodeDir(root), ".extensions-check.lock"), {
    recursive: true,
    force: true,
  });
}

function sha256(filePath) {
  return crypto
    .createHash("sha256")
    .update(fs.readFileSync(filePath))
    .digest("hex");
}

function restoreProtectedFile(context, root, relativePath, specification) {
  const snapshot = path.join(
    context.extensionPath,
    "workspace-snapshot",
    relativePath,
  );
  const candidate = path.join(root, relativePath);
  fs.mkdirSync(path.dirname(candidate), { recursive: true });
  try {
    fs.chmodSync(candidate, 0o644);
  } catch {
    // The file may have been deleted.
  }
  fs.copyFileSync(snapshot, candidate);
  fs.chmodSync(candidate, specification.mode || 0o444);
}

function unexpectedVscodeFile(root, protectedFiles, minimumAgeMs = 10_000) {
  const pending = [vscodeDir(root)];
  while (pending.length) {
    const directory = pending.pop();
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const absolute = path.join(directory, entry.name);
      const relative = path.relative(root, absolute).split(path.sep).join("/");
      if (relative === ".vscode/.extensions-check.lock") continue;
      if (entry.isDirectory()) {
        pending.push(absolute);
      } else if (
        !protectedFiles.has(relative) &&
        !RUNTIME_VSCODE_FILES.has(relative)
      ) {
        // Ignore atomic-save scratch files briefly, but quarantine persistent additions.
        if (Date.now() - fs.statSync(absolute).mtimeMs > minimumAgeMs)
          return relative;
      }
    }
  }
  return undefined;
}

function quarantineUnexpectedFile(root, relativePath) {
  const source = path.join(root, relativePath);
  const quarantine = path.join(root, ".pqmf-guard-quarantine");
  fs.mkdirSync(quarantine, { recursive: true });
  const safeName = relativePath.replace(/[\\/]/g, "_");
  fs.renameSync(source, path.join(quarantine, `${Date.now()}-${safeName}`));
}

function integrityViolation(context, root) {
  const manifest = readJson(
    path.join(context.extensionPath, "guard-manifest.json"),
  );
  if (!manifest || !manifest.files) {
    return "Exam guard integrity manifest is missing or invalid.";
  }
  const protectedFiles = new Set(Object.keys(manifest.files));
  for (const [relativePath, specification] of Object.entries(manifest.files)) {
    const candidate = path.join(root, relativePath);
    try {
      const stat = fs.statSync(candidate);
      if (!stat.isFile() || sha256(candidate) !== specification.sha256) {
        restoreProtectedFile(context, root, relativePath, specification);
        return `Protected exam file changed: ${relativePath}`;
      }
      if (process.platform !== "win32" && (stat.mode & 0o222) !== 0) {
        fs.chmodSync(candidate, specification.mode || 0o444);
        return `Protected exam file permissions changed: ${relativePath}`;
      }
    } catch {
      try {
        restoreProtectedFile(context, root, relativePath, specification);
      } catch {
        return `Protected exam file could not be restored: ${relativePath}`;
      }
      return `Protected exam file missing: ${relativePath}`;
    }
  }
  try {
    const unexpected = unexpectedVscodeFile(root, protectedFiles);
    if (unexpected) {
      quarantineUnexpectedFile(root, unexpected);
      return `Unexpected file added to protected .vscode directory: ${unexpected}`;
    }
  } catch {
    return "The protected .vscode directory could not be verified.";
  }
  return undefined;
}

function scriptHeartbeatViolation(root) {
  if (Date.now() - activatedAt < HEARTBEAT_GRACE_MS) return undefined;
  try {
    const heartbeat = path.join(vscodeDir(root), SCRIPT_HEARTBEAT);
    if (Date.now() - fs.statSync(heartbeat).mtimeMs > HEARTBEAT_STALE_MS) {
      return "Exam guard script heartbeat is stale.";
    }
  } catch {
    return "Exam guard script heartbeat is missing.";
  }
  return undefined;
}

function protectedDefaults(base) {
  const value = base["pqmfExamGuard.protectedSettings"];
  return value && typeof value === "object" && !Array.isArray(value)
    ? value
    : {};
}

function settingsViolated(current, base) {
  return (
    POLICY_KEYS.some((key) => !isDeepStrictEqual(current[key], base[key])) ||
    Object.entries(protectedDefaults(base)).some(
      ([key, expected]) => !isDeepStrictEqual(current[key], expected),
    )
  );
}

function enforceSettings(context) {
  const root = workspaceRoot();
  if (!root || !isExamWorkspace(root) || resetInProgress) return;
  writeExtensionHeartbeat(root);
  if (launcherSetupInProgress(root)) {
    if (!setupPauseLogged) {
      setupPauseLogged = true;
      appendGuardLog(
        root,
        "extension",
        "INFO",
        "Launcher update in progress; integrity checks temporarily paused.",
      );
    }
    return;
  }
  if (setupPauseLogged) {
    setupPauseLogged = false;
    appendGuardLog(
      root,
      "extension",
      "INFO",
      "Launcher update completed; integrity checks resumed.",
    );
  }

  const integrityReason = integrityViolation(context, root);
  if (integrityReason) recordViolation(integrityReason);

  const base = baseSettings(root);
  const settingsPath = path.join(vscodeDir(root), "settings.json");
  if (!base) return;
  const current = readJson(settingsPath) || {};

  const reason =
    scriptHeartbeatViolation(root) ||
    (!fs.existsSync(settingsPath)
      ? "Protected exam settings file is missing."
      : undefined) ||
    (settingsViolated(current, base)
      ? "Protected exam settings were changed."
      : undefined);
  if (reason) recordViolation(reason);

  const target = {
    ...base,
    "workbench.colorCustomizations": fs.existsSync(markerPath(root))
      ? VIOLATION_COLORS
      : NORMAL_COLORS,
  };
  if (current["python.defaultInterpreterPath"]) {
    target["python.defaultInterpreterPath"] =
      current["python.defaultInterpreterPath"];
  }
  if (!isDeepStrictEqual(current, target)) {
    const lockDir = path.join(vscodeDir(root), ".extensions-check.lock");
    try {
      fs.mkdirSync(lockDir);
    } catch {
      // The independent script currently owns the shared settings lock.
      return;
    }
    try {
      fs.writeFileSync(
        settingsPath,
        `${JSON.stringify(target, null, 2)}\n`,
        "utf8",
      );
    } catch {
      recordViolation(
        "The exam guard extension could not restore settings.json.",
      );
    } finally {
      try {
        fs.rmdirSync(lockDir);
      } catch {
        // A stale-lock recovery may already have removed it.
      }
    }
  }
}

function checkUri(uri) {
  const root = workspaceRoot();
  if (
    !root ||
    !isExamWorkspace(root) ||
    vscode.workspace
      .getConfiguration()
      .get(OUTSIDE_WORKSPACE_CHECK_DISABLED_KEY, false) ||
    launcherSetupInProgress(root) ||
    !uri ||
    uri.scheme !== "file"
  )
    return;
  if (!isInsideWorkspace(uri.fsPath, root)) {
    recordViolation(`File outside exam workspace opened:\n${uri.fsPath}`);
    if (activeContext) enforceSettings(activeContext);
  }
}

function checkOpenEditors() {
  const root = workspaceRoot();
  if (!root || !isExamWorkspace(root)) return;
  for (const group of vscode.window.tabGroups.all) {
    for (const tab of group.tabs) {
      for (const uri of urisFromTabInput(tab.input)) checkUri(uri);
    }
  }
  for (const document of vscode.workspace.textDocuments) checkUri(document.uri);
  for (const notebook of vscode.workspace.notebookDocuments)
    checkUri(notebook.uri);
}

function installTerminalDefense(context) {
  const blockerDir = path.join(
    context.globalStorageUri.fsPath,
    "terminal-blockers",
  );
  const message = "The 'copilot' command is disabled in this exam workspace.";
  fs.mkdirSync(blockerDir, { recursive: true });
  const posixBlocker = path.join(blockerDir, "copilot");
  fs.writeFileSync(
    posixBlocker,
    `#!/bin/sh\necho "${message}" >&2\nexit 1\n`,
    "utf8",
  );
  try {
    fs.chmodSync(posixBlocker, 0o755);
  } catch {
    // Windows does not use POSIX executable bits.
  }
  fs.writeFileSync(
    path.join(blockerDir, "copilot.cmd"),
    `@echo off\r\necho ${message} 1>&2\r\nexit /b 1\r\n`,
    "utf8",
  );
  context.environmentVariableCollection.prepend(
    "PATH",
    `${blockerDir}${path.delimiter}`,
  );
}

function outOfFocusCheckEnabled() {
  return !vscode.workspace
    .getConfiguration()
    .get(OUT_OF_FOCUS_CHECK_DISABLED_KEY, false);
}

function handleWindowStateChange(state) {
  if (!outOfFocusCheckEnabled()) {
    if (focusLossTimer) clearTimeout(focusLossTimer);
    focusLossTimer = undefined;
    return;
  }
  if (state.focused) {
    if (focusLossTimer) clearTimeout(focusLossTimer);
    focusLossTimer = undefined;
    return;
  }
  if (focusLossTimer) return;
  focusLossTimer = setTimeout(() => {
    focusLossTimer = undefined;
    if (!vscode.window.state.focused) {
      recordViolation("VS Code was out of focus for more than 10 seconds.");
      if (activeContext) enforceSettings(activeContext);
    }
  }, FOCUS_GRACE_MS);
}

async function checkFullscreen(initial = false) {
  if (!fullscreenCheckAvailable) return;
  try {
    const fullscreen = await vscode.commands.executeCommand(
      "getContextKeyValue",
      "isFullscreen",
    );
    if (typeof fullscreen !== "boolean") {
      fullscreenCheckAvailable = false;
      return;
    }
    if (initial) {
      fullscreenArmedAt = Date.now() + FULLSCREEN_STARTUP_GRACE_MS;
      if (!fullscreen) {
        await vscode.commands.executeCommand(
          "workbench.action.toggleFullScreen",
        );
      }
      return;
    }
    if (Date.now() >= fullscreenArmedAt && !fullscreen) {
      recordViolation("VS Code exited full-screen mode during the exam.");
      if (activeContext) enforceSettings(activeContext);
      fullscreenArmedAt = Date.now() + FULLSCREEN_STARTUP_GRACE_MS;
      await vscode.commands.executeCommand("workbench.action.toggleFullScreen");
    }
  } catch {
    // Fullscreen state is an internal context key; focus protection remains active.
    fullscreenCheckAvailable = false;
  }
}

function hideVscodeDirectory(root) {
  try {
    if (process.platform === "win32") {
      childProcess.spawnSync("attrib", ["+H", vscodeDir(root)], {
        windowsHide: true,
      });
    } else if (process.platform === "darwin") {
      childProcess.spawnSync("chflags", ["hidden", vscodeDir(root)]);
    }
  } catch {
    // files.exclude still hides the directory inside VS Code.
  }
}

function restoreAllProtectedFiles(context, root) {
  const manifest = readJson(
    path.join(context.extensionPath, "guard-manifest.json"),
  );
  if (!manifest || !manifest.files) {
    throw new Error("The exam guard integrity manifest is missing or invalid.");
  }
  fs.mkdirSync(vscodeDir(root), { recursive: true });
  for (const [relativePath, specification] of Object.entries(manifest.files)) {
    restoreProtectedFile(context, root, relativePath, specification);
  }
  const protectedFiles = new Set(Object.keys(manifest.files));
  let unexpected;
  while ((unexpected = unexpectedVscodeFile(root, protectedFiles, -1))) {
    quarantineUnexpectedFile(root, unexpected);
  }
}

function writeNormalSettings(root) {
  const base = baseSettings(root);
  if (!base) throw new Error("The restored base settings are invalid.");
  const settingsPath = path.join(vscodeDir(root), "settings.json");
  const previous = readJson(settingsPath) || {};
  const target = {
    ...base,
    "workbench.colorCustomizations": NORMAL_COLORS,
  };
  if (previous["python.defaultInterpreterPath"]) {
    target["python.defaultInterpreterPath"] =
      previous["python.defaultInterpreterPath"];
  }
  try {
    fs.chmodSync(settingsPath, 0o644);
  } catch {
    // settings.json may have been deleted.
  }
  fs.writeFileSync(
    settingsPath,
    `${JSON.stringify(target, null, 2)}\n`,
    "utf8",
  );
}

async function ensureScriptWatcher(root) {
  try {
    const heartbeat = path.join(vscodeDir(root), SCRIPT_HEARTBEAT);
    if (Date.now() - fs.statSync(heartbeat).mtimeMs <= HEARTBEAT_STALE_MS)
      return;
  } catch {
    // Start the watcher below.
  }
  const tasks = await vscode.tasks.fetchTasks();
  const watcher = tasks.find(
    (task) => task.name === "Restricted mode: watch AI usage",
  );
  if (watcher) await vscode.tasks.executeTask(watcher);
}

async function resetWorkspace() {
  const root = activeExamRoot || workspaceRoot();
  if (!root || !activeContext || !isExamWorkspace(root)) {
    return "echo PQMF exam guard is not active in this workspace.";
  }
  resetInProgress = true;
  try {
    restoreAllProtectedFiles(activeContext, root);
    clearRuntimeWatchdogState(root);
    writeNormalSettings(root);
    for (const fileName of [
      ".ai-extension-detected",
      ".ai-extension-detected.outside-file",
    ]) {
      try {
        fs.unlinkSync(path.join(vscodeDir(root), fileName));
      } catch (error) {
        if (error.code !== "ENOENT") throw error;
      }
    }
    hideVscodeDirectory(root);
    warnedWorkspaceRoots.delete(normalizePath(root));
    activatedAt = Date.now();
    writeExtensionHeartbeat(root);
    appendGuardLog(
      root,
      "extension",
      "RESET",
      "Instructor reset restored protected files and normal colors.",
    );
    updateViolationControls(root);
  } catch (error) {
    vscode.window.showErrorMessage(
      `PQMF exam workspace reset failed: ${error.message}`,
    );
    return "echo PQMF exam workspace reset failed.";
  } finally {
    resetInProgress = false;
  }
  await ensureScriptWatcher(root);
  enforceSettings(activeContext);
  vscode.window.showInformationMessage(
    "PQMF exam workspace reset complete. All protected files were restored.",
  );
  return "echo PQMF exam workspace reset complete.";
}

function activate(context) {
  activeContext = context;
  activatedAt = Date.now();
  if (!isExamWorkspace()) return;
  activeExamRoot = workspaceRoot();
  guardOutput = vscode.window.createOutputChannel("PQMF Exam Guard");
  guardViolationStatus = vscode.window.createStatusBarItem(
    "pqmfExamGuard.violation",
    vscode.StatusBarAlignment.Left,
    10_000,
  );
  guardViolationStatus.command = "pqmfExamGuard.showLog";
  guardViolationStatus.backgroundColor = new vscode.ThemeColor(
    "statusBarItem.errorBackground",
  );
  guardResetStatus = vscode.window.createStatusBarItem(
    "pqmfExamGuard.reset",
    vscode.StatusBarAlignment.Left,
    9_999,
  );
  guardResetStatus.text = "$(refresh) Instructor Reset";
  guardResetStatus.tooltip =
    "Restore protected exam files and clear the violation state.";
  guardResetStatus.command = "pqmfExamGuard.instructorReset";
  context.subscriptions.push(
    guardOutput,
    guardViolationStatus,
    guardResetStatus,
  );
  try {
    guardLogOffset = fs.statSync(guardLogPath(activeExamRoot)).size;
  } catch {
    guardLogOffset = 0;
  }
  appendGuardLog(
    activeExamRoot,
    "extension",
    "SESSION",
    "New VS Code exam-guard session.",
  );
  appendGuardLog(activeExamRoot, "extension", "INFO", "Exam guard activated.");
  try {
    const activeReason = fs
      .readFileSync(markerPath(activeExamRoot), "utf8")
      .trim();
    if (activeReason) {
      appendGuardLog(
        activeExamRoot,
        "extension",
        "STATE",
        `Active violation: ${activeReason}`,
      );
    }
  } catch {
    appendGuardLog(
      activeExamRoot,
      "extension",
      "STATE",
      "No active violation marker.",
    );
  }
  updateViolationControls(activeExamRoot, true);

  installTerminalDefense(context);
  void checkFullscreen(true);
  checkOpenEditors();
  enforceSettings(context);
  const timer = setInterval(() => {
    checkOpenEditors();
    enforceSettings(context);
    void checkFullscreen();
    syncGuardLogToOutput(activeExamRoot);
    updateViolationControls(activeExamRoot, true);
  }, 1000);

  context.subscriptions.push(
    {
      dispose: () => {
        clearInterval(timer);
        if (focusLossTimer) clearTimeout(focusLossTimer);
      },
    },
    vscode.window.onDidChangeWindowState(handleWindowStateChange),
    vscode.window.tabGroups.onDidChangeTabs(checkOpenEditors),
    vscode.workspace.onDidOpenTextDocument((document) =>
      checkUri(document.uri),
    ),
    vscode.workspace.onDidOpenNotebookDocument((notebook) =>
      checkUri(notebook.uri),
    ),
    vscode.workspace.onDidChangeConfiguration(() => enforceSettings(context)),
    vscode.commands.registerCommand(
      "pqmfExamGuard.instructorReset",
      resetWorkspace,
    ),
    vscode.commands.registerCommand("pqmfExamGuard.showLog", showGuardLog),
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
