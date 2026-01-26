# qr2fa

터미널에서 사용하는 TOTP MFA 인증 관리 도구. QR 캡처와 클라우드 동기화 지원.

## 주요 기능

- 🎨 **Interactive TUI** - 실시간 코드 갱신 및 검색
- 📸 **QR 캡처** - 화면에서 직접 QR 코드 캡처 (macOS)
- 🔄 **Google Authenticator 마이그레이션** - 한 번에 여러 계정 가져오기
- ☁️ **클라우드 동기화** - iCloud Drive / Dropbox / Google Drive 지원
- ⚡ **빠른 접근** - 클립보드 자동 복사
- 🏷️ **태그 관리** - dev/prod/staging/personal 환경별 분류

## 설치

```bash
# Go로 설치
go install github.com/kimmojae/qr2fa@latest

# 소스에서 빌드
git clone https://github.com/kimmojae/qr2fa
cd qr2fa
make build
make install
```

## 사용법

### 대화형 모드 (추천)

```bash
qr2fa  # TUI 실행

# 키바인딩
# ↑/↓ 또는 j/k: 이동
# Enter: 클립보드 복사
# 타이핑: 실시간 검색
# q: 종료
```

### 주요 명령어

```bash
# 계정 목록
qr2fa list
qr2fa list --tag prod

# 코드 조회 & 복사
qr2fa get "AWS Console"

# 계정 추가
qr2fa add                              # 대화형
qr2fa add --qr ~/Downloads/qr.png      # QR 이미지
qr2fa qr-capture                       # 화면 캡처 ⭐

# 계정 관리
qr2fa show "AWS Console"               # QR 코드 보기
qr2fa edit "AWS Console"               # 편집
qr2fa rename "old" "new"               # 이름 변경
qr2fa delete "AWS Console"             # 삭제

# 백업/복원
qr2fa export backup.json
qr2fa import backup.json

# 설정 관리
qr2fa config show                      # 현재 설정 보기
qr2fa config set-path                  # 저장 경로 변경
qr2fa config set-path ~/Dropbox/.qr2fa # 직접 지정
qr2fa config reset                     # 설정 초기화
```

### QR 화면 캡처

Google Authenticator 내보내기를 포함한 모든 QR 코드를 화면에서 직접 캡처:

```bash
qr2fa qr-capture
# 1. 화면에 QR 코드 표시
# 2. 마우스로 영역 선택
# 3. 자동으로 계정 추가 (다중 계정 자동 감지)
```

## 저장 경로 설정

### 첫 실행 시 자동 설정

처음 qr2fa를 실행하면 저장 경로를 선택하는 프롬프트가 나타납니다:

```bash
$ qr2fa list

⚠️  저장 경로가 설정되지 않았습니다.

데이터 저장 위치를 선택하세요:

1. iCloud Drive [추천]
   ~/Library/Mobile Documents/com~apple~CloudDocs/.qr2fa
   Mac 간 자동 동기화

2. 직접 입력
   사용자 지정 경로 입력

선택 (1-2) [1]: 1
✓ 설정 저장 완료
```

### 저장 경로 변경

```bash
# 대화형으로 변경
qr2fa config set-path

# 직접 지정
qr2fa config set-path ~/Dropbox/.qr2fa

# 현재 설정 확인
qr2fa config show

# 설정 초기화 (다음 실행 시 다시 선택)
qr2fa config reset
```

### 우선순위

저장 위치는 다음 우선순위로 결정됩니다:

1. **`--data-dir` 플래그** (일회성 오버라이드)
   ```bash
   qr2fa --data-dir ~/Dropbox/.qr2fa list
   ```

2. **`MFA_DATA_DIR` 환경변수** (세션별 오버라이드)
   ```bash
   export MFA_DATA_DIR=~/Dropbox/.qr2fa
   qr2fa list
   ```

3. **설정 파일** (`~/.config/qr2fa/config.json`)
   - 첫 실행 시 선택하거나 `qr2fa config set-path`로 설정

4. **프롬프트** (설정이 없을 경우)

## 보안

- 파일 권한: `0600` (소유자만 읽기/쓰기)
- 시크릿은 평문 JSON으로 저장 (편의성 우선)
- FileVault + iCloud 암호화로 보호
- Apple ID 2FA 활성화 권장

⚠️ **중요**: 시크릿이 평문으로 저장되므로 디스크 암호화(FileVault)와 강력한 로그인 비밀번호 필수

## 개발

```bash
make build     # 빌드
make test      # 테스트
make release   # 멀티 플랫폼 빌드
make proto     # protobuf 재생성
```

**프로젝트 구조:**
- `cmd/` - CLI 명령어 (Cobra)
- `internal/account/` - 데이터 모델
- `internal/storage/` - JSON 저장
- `internal/totp/` - TOTP 생성
- `internal/qr/` - QR 인코딩/디코딩
- `internal/tui/` - Bubbletea UI
- `internal/migration/` - Google Auth 마이그레이션

## 호환성

- **macOS**: 전체 지원 (QR 캡처 포함)
- **Linux**: 지원 (QR 캡처 제외)
- **Windows**: 미테스트

## 라이선스

MIT License

## 기여

Pull Request 환영합니다! [GitHub Issues](https://github.com/kimmojae/qr2fa/issues)
