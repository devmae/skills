#!/usr/bin/env node

import { realpathSync, statSync } from "node:fs";
import { spawnSync } from "node:child_process";

const platform = process.env.COGNEE_PICKER_PLATFORM || process.platform;
const prompt = "Cognee를 설정할 프로젝트 폴더를 선택하세요.";

function run(command, args) {
  const result = spawnSync(command, args, {
    cwd: process.cwd(),
    encoding: "utf8",
    windowsHide: false,
  });

  if (result.error) {
    console.error(`ERROR folder picker를 실행할 수 없음: ${result.error.message}`);
    process.exit(2);
  }

  if (result.status === 130) {
    console.error("INFO folder picker를 취소함");
    process.exit(130);
  }

  if (result.status !== 0) {
    const detail = result.stderr.trim();
    if (platform === "darwin" && /-128|User canceled/i.test(detail)) {
      console.error("INFO folder picker를 취소함");
      process.exit(130);
    }
    console.error(`ERROR folder picker 실패${detail ? `: ${detail}` : ""}`);
    process.exit(2);
  }

  return result.stdout.trim();
}

let selectedPath;

if (platform === "darwin") {
  const osascript = process.env.COGNEE_OSASCRIPT_BIN || "/usr/bin/osascript";
  selectedPath = run(osascript, [
    "-e",
    `POSIX path of (choose folder with prompt "${prompt}")`,
  ]);
} else if (platform === "win32") {
  const powershell = process.env.COGNEE_POWERSHELL_BIN || "powershell.exe";
  const script = [
    "Add-Type -AssemblyName System.Windows.Forms",
    "$dialog = New-Object System.Windows.Forms.FolderBrowserDialog",
    `$dialog.Description = '${prompt}'`,
    "$dialog.ShowNewFolderButton = $false",
    "$dialog.SelectedPath = (Get-Location).Path",
    "$result = $dialog.ShowDialog()",
    "if ($result -eq [System.Windows.Forms.DialogResult]::OK) {",
    "  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)",
    "  [Console]::Out.Write($dialog.SelectedPath)",
    "  exit 0",
    "}",
    "exit 130",
  ].join("\n");

  selectedPath = run(powershell, [
    "-NoProfile",
    "-STA",
    "-Command",
    script,
  ]);
} else {
  console.error(`ERROR 이 OS에서는 folder picker를 지원하지 않음: ${platform}`);
  process.exit(2);
}

if (!selectedPath) {
  console.error("ERROR 선택한 프로젝트 경로가 비어 있음");
  process.exit(2);
}

try {
  const resolvedPath = realpathSync(selectedPath);
  if (!statSync(resolvedPath).isDirectory()) {
    throw new Error("폴더가 아님");
  }
  process.stdout.write(resolvedPath);
} catch (error) {
  console.error(`ERROR 선택한 프로젝트 폴더를 열 수 없음: ${selectedPath} (${error.message})`);
  process.exit(2);
}
