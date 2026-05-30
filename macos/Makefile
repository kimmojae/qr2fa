APP_NAME  = qr2fa
SCHEME    = qr2fa
PROJECT   = qr2fa/qr2fa.xcodeproj
BUILD_DIR = build

.PHONY: build archive zip clean

build:
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

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
