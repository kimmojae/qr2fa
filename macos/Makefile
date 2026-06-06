APP_NAME    = qr2fa
SCHEME      = qr2fa
PROJECT     = qr2fa/qr2fa.xcodeproj
BUILD_DIR   = build.noindex
RELEASE_APP = $(BUILD_DIR)/DerivedData/Build/Products/Release/$(APP_NAME).app
INSTALL_DIR = /Applications
# 자기서명 코드서명 신원. 이 인증서로 고정 서명해야 화면 기록(TCC) 권한이 빌드 간 유지됨.
SIGN_ID     = qr2fa-selfsign

.PHONY: build install archive zip clean

build:
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# 빌드 → 고정 인증서로 서명 → 기존 실행 종료 → /Applications 에 덮어쓰기 → 다시 실행
install: build
	codesign --force --deep --sign "$(SIGN_ID)" "$(RELEASE_APP)"
	-pkill -x $(APP_NAME) 2>/dev/null || true
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(RELEASE_APP)" "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP_NAME).app" || (sleep 1; open "$(INSTALL_DIR)/$(APP_NAME).app")
	@echo "✅ 설치(서명됨) 완료: $(INSTALL_DIR)/$(APP_NAME).app"

archive:
	xcodebuild archive \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-archivePath $(BUILD_DIR)/$(APP_NAME).xcarchive \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
		SKIP_INSTALL=NO

zip: archive
	cd "$(BUILD_DIR)/$(APP_NAME).xcarchive/Products/Applications" && \
		zip -r "../../../../$(APP_NAME)-macos.zip" "$(APP_NAME).app"
	@echo "✅ 빌드 완료: $(APP_NAME)-macos.zip"

clean:
	rm -rf $(BUILD_DIR)
