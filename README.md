<div align="center">
  <img src="images/icon.png" width="128" height="128" alt="Qr2fa logo">

  # Qr2fa

  macOS 메뉴바에서 쓰는 TOTP MFA 인증 관리 앱. 화면 QR 캡처와 Google Authenticator 마이그레이션 지원.
</div>

## 설치

1. [Releases](https://github.com/kimmojae/qr2fa/releases)에서 `qr2fa-macos.zip` 다운로드
2. `qr2fa.app`을 `/Applications`로 이동
3. 처음 실행 시 Gatekeeper 경고가 뜨면: Finder에서 `qr2fa.app` 우클릭 → **열기** → **열기**
4. 화면 녹화 권한 요청 시 허용 (QR 캡처에 필요)

첫 실행 때 MFA 데이터를 어디에 저장할지 한 번 물어봅니다. iCloud Drive를 고르면 다른 Mac에서도 같은 계정이 그대로 보입니다.

## 기능

- **메뉴바에서 바로** — 아이콘 클릭 → 서비스별 코드 확인 및 클립보드 복사, 30초 갱신 타이머
- **화면 QR 캡처** — 화면에 뜬 QR을 마우스로 영역 선택해 그대로 등록 (ScreenCaptureKit + Vision)
- **Google Authenticator 마이그레이션** — 내보내기 QR 하나로 여러 계정 한 번에 가져오기
- **계정 관리** — 추가·편집·삭제, 태그로 dev/prod 분류, 서비스별 그룹
- **유연한 저장 위치** — iCloud Drive, 로컬, Dropbox 등 원하는 폴더
- **외부 변경 자동 반영** — 다른 Mac에서 iCloud로 동기화된 변경을 재시작 없이 반영
- **로그인 시 자동 시작** (설정 > 일반)

## 사용법

**코드 확인** — 메뉴바 아이콘 클릭 → 서비스 → 계정. 클릭하면 코드가 클립보드로 복사됩니다.

**계정 추가** — 메뉴바 → Settings… → 오른쪽 위 `+`

- **QR 캡처**: 화면에 QR을 띄워두고 영역을 드래그하면 자동 인식. Google Authenticator 내보내기 QR이면 여러 계정이 한 번에 들어옵니다.
- **수동 입력**: 시크릿 키를 직접 붙여넣기

**계정 편집·삭제** — 설정 창에서 계정 선택 → `편집`

## 저장 위치

MFA 데이터는 `accounts.json` 한 파일에 담깁니다. 위치는 첫 실행 때 고르고, 이후 **설정 > 일반**에서 바꿀 수 있습니다.

| 선택 | 경로 |
|---|---|
| iCloud Drive | `~/Library/Mobile Documents/com~apple~CloudDocs/.qr2fa` |
| 이 Mac에만 저장 | `~/.config/qr2fa` |
| 직접 선택 | 원하는 폴더 (Dropbox, 외장 디스크 등) |

고른 위치는 Mac마다 따로 기억되므로, iCloud로 데이터를 공유하면서도 특정 Mac만 다른 폴더를 보게 할 수 있습니다.

**위치를 옮길 때** — 설정 > 일반 > `변경…`으로 새 폴더를 고르면 기존 데이터를 가져갑니다. `Finder에서 보기`로 실제 파일 위치를 열 수 있습니다.

## 보안

- 시크릿은 **평문 JSON**으로 저장됩니다 (편의성 우선). 파일 자체가 곧 인증 수단입니다.
- 앱이 만드는 저장 파일은 소유자만 읽고 쓸 수 있게(`0600`) 잠급니다.
- iCloud Drive에 두면 Apple의 전송·저장 암호화가 적용됩니다.

> ⚠️ **디스크 암호화(FileVault)와 강력한 로그인 비밀번호가 필수입니다.** 이 파일을 통째로 복사당하면 모든 2FA가 뚫립니다. iCloud를 쓴다면 Apple ID의 2단계 인증도 반드시 켜두세요.

## 개발

```bash
cd macos
make build      # Release 빌드 (build.noindex/)
make install    # 빌드 → 자체 서명 → /Applications 교체 → 재실행
make zip        # 릴리스용 아카이브
make clean
```

테스트 (`macos/qr2fa/`에서):

```bash
xcodebuild test -project qr2fa.xcodeproj -scheme qr2fa -destination 'platform=macOS'
```

Xcode 프로젝트는 [XcodeGen](https://github.com/yonaskolb/XcodeGen)이 `macos/qr2fa/project.yml`에서 생성합니다. Swift 파일을 손으로 추가했다면 `xcodegen generate`를 다시 돌려야 빌드 타깃에 포함됩니다.

**구조**

- `App/` — `AppDelegate`(메뉴바 `NSStatusItem`), `qr2faApp`(SwiftUI 씬)
- `Models/` — `Account`, `AccountStorage`
- `Services/` — `StorageService`(저장·경로), `TOTPGenerator`(RFC 6238), `MigrationParser`, `FileWatcher`
- `Views/` — 온보딩, 설정 창, 계정 상세, QR 캡처

---

## Go CLI (deprecated)

> **이 CLI는 더 이상 유지보수하지 않습니다.** 코드는 참고용으로 저장소에 남아 있지만 릴리스에 포함되지 않으며, 새로운 기능은 macOS 앱에만 추가됩니다.
>
> **앱과 저장 위치 설정을 공유하지 않습니다.** 앱은 고른 폴더를 자체 설정에 기억하고, CLI는 `~/.config/qr2fa/config.json`을 봅니다. 둘 다 쓰려면 양쪽이 같은 폴더를 가리키는지 직접 확인하세요 — 그러지 않으면 서로 다른 `accounts.json`을 보게 됩니다. `accounts.json` 형식 자체는 동일합니다.

<details>
<summary>사용법 펼치기</summary>

```bash
cd cli
make build && make install
```

```bash
qr2fa                                  # 대화형 TUI
qr2fa list                             # 계정 목록
qr2fa get 1                            # 코드 조회 & 복사
qr2fa add                              # 계정 추가 (대화형)
qr2fa add --qr ~/Downloads/qr.png      # QR 이미지에서 추가
qr2fa qr-capture                       # 화면 캡처 (macOS 전용)
qr2fa show 1                           # 상세 정보 + QR 코드
qr2fa edit 1 / rename 1 "name" / delete 1
qr2fa export backup.json               # 평문 JSON 백업
qr2fa import backup.json
qr2fa config show / set-path / reset   # 저장 경로
```

저장 경로 우선순위: `--data-dir` 플래그 > `MFA_DATA_DIR` 환경변수 > `~/.config/qr2fa/config.json` > 첫 실행 프롬프트.

CLI가 만드는 파일은 `0600`, 디렉터리는 `0700`입니다. macOS 외 플랫폼에서는 QR 화면 캡처를 쓸 수 없습니다.

</details>

## 라이선스

MIT License

## 기여

Pull Request 환영합니다! [GitHub Issues](https://github.com/kimmojae/qr2fa/issues)
