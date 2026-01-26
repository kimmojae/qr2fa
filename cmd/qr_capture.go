package cmd

import (
	"fmt"
	"strings"

	"github.com/spf13/cobra"

	"github.com/kimmojae/qr2fa/internal/account"
	"github.com/kimmojae/qr2fa/internal/migration"
	"github.com/kimmojae/qr2fa/internal/qr"
)

// qrCaptureCmd represents the qr-capture command
var qrCaptureCmd = &cobra.Command{
	Use:   "qr-capture",
	Short: "Capture QR code from screen",
	Long:  `Capture a QR code by selecting an area on the screen (macOS only).`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := initStorage(); err != nil {
			return err
		}

		st, err := storageManager.Load()
		if err != nil {
			return fmt.Errorf("failed to load storage: %w", err)
		}

		// User-friendly instructions
		fmt.Fprintln(cmd.ErrOrStderr(), "📸 QR 코드 캡처 모드")
		fmt.Fprintln(cmd.ErrOrStderr(), "")
		fmt.Fprintln(cmd.ErrOrStderr(), "사용 방법:")
		fmt.Fprintln(cmd.ErrOrStderr(), "  1. 화면에 QR 코드를 띄워주세요")
		fmt.Fprintln(cmd.ErrOrStderr(), "  2. 마우스로 QR 영역을 드래그해서 선택")
		fmt.Fprintln(cmd.ErrOrStderr(), "  3. 자동으로 계정이 추가됩니다")
		fmt.Fprintln(cmd.ErrOrStderr(), "")
		fmt.Fprintln(cmd.ErrOrStderr(), "💡 팁: QR 이미지 파일이 있다면 'qr2fa add --qr <파일>' 사용")
		fmt.Fprintln(cmd.ErrOrStderr(), "")
		fmt.Fprint(cmd.ErrOrStderr(), "화면을 선택하세요 (ESC로 취소)...")

		// Capture QR code from screen
		content, err := qr.CaptureFromScreen()
		if err != nil {
			errMsg := err.Error()

			// Check if it was cancelled
			if strings.Contains(errMsg, "cancelled") || strings.Contains(errMsg, "ESC pressed") {
				fmt.Fprintln(cmd.ErrOrStderr(), "\n")
				fmt.Fprintln(cmd.ErrOrStderr(), "화면 캡처가 취소되었습니다.")
				fmt.Fprintln(cmd.ErrOrStderr(), "")
				fmt.Fprintln(cmd.ErrOrStderr(), "💡 팁: QR 코드 이미지 파일이 있다면:")
				fmt.Fprintln(cmd.ErrOrStderr(), "   qr2fa add --qr <파일경로>")
				fmt.Fprintln(cmd.ErrOrStderr(), "")
				fmt.Fprintln(cmd.ErrOrStderr(), "또는 수동으로 추가:")
				fmt.Fprintln(cmd.ErrOrStderr(), "   qr2fa add")
				return nil
			}

			// Check for permission issues
			if strings.Contains(errMsg, "permission") || strings.Contains(errMsg, "Operation not permitted") {
				fmt.Fprintln(cmd.ErrOrStderr(), "\n")
				fmt.Fprintln(cmd.ErrOrStderr(), "❌ 화면 녹화 권한이 필요합니다!")
				fmt.Fprintln(cmd.ErrOrStderr(), "")
				fmt.Fprintln(cmd.ErrOrStderr(), "권한 설정 방법:")
				fmt.Fprintln(cmd.ErrOrStderr(), "  1. 시스템 설정 열기")
				fmt.Fprintln(cmd.ErrOrStderr(), "  2. '개인정보 보호 및 보안' > '화면 녹화' 이동")
				fmt.Fprintln(cmd.ErrOrStderr(), "  3. 터미널 앱 활성화 (또는 추가)")
				fmt.Fprintln(cmd.ErrOrStderr(), "  4. 터미널 재시작 후 다시 시도")
				return nil
			}

			return fmt.Errorf("failed to capture QR code: %w", err)
		}

		fmt.Fprintln(cmd.ErrOrStderr(), " done!")
		fmt.Fprintln(cmd.ErrOrStderr(), "")

		// Check if it's a migration URL
		if strings.HasPrefix(content, "otpauth-migration://") {
			return handleMigration(cmd, st, content)
		}

		// Parse otpauth URL
		acc, err := account.ParseOTPAuthURL(content)
		if err != nil {
			return fmt.Errorf("failed to parse QR code: %w", err)
		}

		fmt.Fprintf(cmd.ErrOrStderr(), "✓ Detected: %s", acc.Name)
		if acc.Issuer != "" {
			fmt.Fprintf(cmd.ErrOrStderr(), " (%s)", acc.Issuer)
		}
		fmt.Fprintln(cmd.ErrOrStderr())

		// Prompt for name confirmation
		fmt.Fprintf(cmd.ErrOrStderr(), "Name [%s]: ", acc.Name)
		name := readLine()
		if name != "" {
			acc.Name = name
		}

		// Prompt for tag
		fmt.Fprint(cmd.ErrOrStderr(), "Tag [dev/prod/staging/personal]: ")
		tag := readLine()
		acc.Tag = strings.ToLower(strings.TrimSpace(tag))

		// Add account
		if err := st.Add(acc); err != nil {
			return fmt.Errorf("failed to add account: %w", err)
		}

		// Save storage
		if err := storageManager.Save(st); err != nil {
			return fmt.Errorf("failed to save storage: %w", err)
		}

		fmt.Fprintf(cmd.ErrOrStderr(), "✓ Account '%s' added successfully\n", acc.Name)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(qrCaptureCmd)
}

func handleMigration(cmd *cobra.Command, st *account.Storage, content string) error {
	// Parse migration URL
	accounts, err := migration.ParseMigrationURL(content)
	if err != nil {
		return fmt.Errorf("failed to parse migration URL: %w", err)
	}

	fmt.Fprintf(cmd.ErrOrStderr(), "✓ Detected Google Authenticator migration (%d accounts)\n", len(accounts))
	fmt.Fprintln(cmd.ErrOrStderr(), "Importing:")
	for i, acc := range accounts {
		fmt.Fprintf(cmd.ErrOrStderr(), "  %d. %s", i+1, acc.Name)
		if acc.Issuer != "" {
			fmt.Fprintf(cmd.ErrOrStderr(), " (%s)", acc.Issuer)
		}
		fmt.Fprintln(cmd.ErrOrStderr())
	}

	// Add accounts one by one with individual tag prompts
	fmt.Fprintln(cmd.ErrOrStderr())
	added := 0
	for i, acc := range accounts {
		fmt.Fprintf(cmd.ErrOrStderr(), "Account %d/%d: %s", i+1, len(accounts), acc.Name)
		if acc.Issuer != "" {
			fmt.Fprintf(cmd.ErrOrStderr(), " (%s)", acc.Issuer)
		}
		fmt.Fprintln(cmd.ErrOrStderr())

		// Prompt for tag
		fmt.Fprint(cmd.ErrOrStderr(), "Tag [dev/prod/staging/personal]: ")
		tag := strings.ToLower(strings.TrimSpace(readLine()))
		acc.Tag = tag

		if err := st.Add(acc); err != nil {
			fmt.Fprintf(cmd.ErrOrStderr(), "⚠ Failed to add: %v\n", err)
			continue
		}
		added++
	}

	// Save storage
	if err := storageManager.Save(st); err != nil {
		return fmt.Errorf("failed to save storage: %w", err)
	}

	fmt.Fprintln(cmd.ErrOrStderr())
	fmt.Fprintf(cmd.ErrOrStderr(), "✓ %d accounts added successfully\n", added)

	return nil
}
