---
name: cognee-setup
description: 지정한 프로젝트 폴더에서 Claude Code용 cognee-memory를 쓸 수 있는지 점검하고 부족한 설정을 만든다. Git 저장소가 아닌 폴더도 지원한다. Tailscale, cognee-memory 플러그인, 프로젝트별 COGNEE_BASE_URL / COGNEE_API_KEY / COGNEE_PLUGIN_DATASET 설정을 검사한다. 사용자가 "cognee 셋업", "cognee 체크", "cognee 환경 확인", "cognee 되는지 봐줘", "기억/메모리 서버 연결 확인" 등을 요청하거나 cognee를 처음 쓰는 프로젝트의 환경 준비가 필요할 때 사용한다.
---

# Cognee Setup

지정한 프로젝트 폴더에서 [cognee-memory 플러그인](https://github.com/topoteretes/cognee-integrations/tree/main/integrations/claude-code)을 쓰기 위한 환경을 점검하고 설정한다. 프로젝트는 Git 저장소가 아닐 수 있다. cognee는 Tailscale로 연결된 원격 서버에 기억을 저장하므로 Tailscale, 플러그인, 프로젝트별 환경변수가 모두 필요하다.

## 1. 프로젝트 루트 확정

사용자가 지정한 프로젝트 폴더를 루트로 쓴다. Git 정보로 다른 경로를 추측하거나 상위 Git 루트로 바꾸지 않는다. 사용자가 경로를 지정하지 않았다면 현재 작업 폴더를 쓴다.

환경변수는 이 프로젝트 안에서만 설정한다. `~/.zshrc`, `~/.bashrc`, user 전역 설정에는 쓰지 않는다.

## 2. 체크

```bash
bash <이 스킬 경로>/scripts/check.sh <프로젝트 루트>
```

스크립트는 현재 셸의 전역 `COGNEE_*` 값을 판정에 쓰지 않는다. 다음 파일만 검사한다.

- `<프로젝트 루트>/.envrc`: `COGNEE_BASE_URL`, `COGNEE_PLUGIN_DATASET`
- `<프로젝트 루트>/.envrc.local`: `COGNEE_API_KEY`

Git worktree 안의 프로젝트라면 `.envrc`가 추적되고 `.envrc.local`이 ignore되는지도 검사한다.

## 3. FAIL 해결

### Tailscale 미설치

설치 동의를 받은 뒤 실행한다.

```bash
brew install --cask tailscale
```

Tailscale 앱을 실행하고 cognee 서버와 같은 tailnet에 로그인하도록 안내한다.

### 플러그인 미설치

```bash
claude plugin marketplace add topoteretes/cognee-integrations
claude plugin install cognee-memory@cognee
```

설치 후 Claude Code를 다시 시작하도록 안내한다.

### 환경변수 미설정

사용자에게 값을 직접 묻는다. 추측하거나 placeholder를 쓰지 않는다.

- `COGNEE_BASE_URL`: 서버의 Tailscale URL. 머신 목록이 있으면 후보를 제시한다.
- `COGNEE_API_KEY`: 서버 인증 key. 사용자가 직접 입력해야 한다.
- `COGNEE_PLUGIN_DATASET`: 프로젝트별 dataset. 프로젝트 폴더명을 추천한다. 여러 기기에서 같은 프로젝트를 쓸 때는 같은 값을 쓴다.

값을 받지 못하면 파일을 만들지 말고 미완료로 끝낸다.

프로젝트 루트의 `.envrc`에 공개 설정을 기록한다. 기존 내용은 보존한다.

```bash
export COGNEE_BASE_URL="..."
export COGNEE_PLUGIN_DATASET="..."

if [ -f .envrc.local ]; then
  source .envrc.local
fi
```

프로젝트 루트의 `.envrc.local`에 secret을 기록한다.

```bash
export COGNEE_API_KEY="..."
```

### Git 처리

프로젝트 폴더가 Git worktree 안에 있으면 다음 상태를 만든다.

- `.envrc`의 ignore 규칙을 제거하고 `git add -f -- .envrc`로 추적한다.
- `.gitignore`에 `.envrc.local`을 추가한다.
- `.envrc`에는 API key를 절대 넣지 않는다.

Git이 아닌 폴더에서는 두 파일을 프로젝트 루트에만 둔다.

### 환경 적용

direnv가 있으면 `direnv allow <프로젝트 루트>`를 실행한다. 없으면 프로젝트 루트에서 `source .envrc`를 실행하도록 안내한다. 그 뒤 터미널과 Claude Code를 다시 시작한다.

## 4. 재검증

체크 스크립트를 다시 실행한다. `RESULT OK`일 때만 완료로 보고한다. 미완료면 남은 값이나 작업을 짧게 적는다. 완료 후 상태줄에 `cognee: <dataset> · <mode>`가 보이면 정상이다.
