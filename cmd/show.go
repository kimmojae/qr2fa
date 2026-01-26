package cmd

import (
	"encoding/base64"
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/kimmojae/qr2fa/internal/qr"
	"github.com/kimmojae/qr2fa/internal/totp"
)

var (
	showSave string
)

// showCmd represents the show command
var showCmd = &cobra.Command{
	Use:   "show <account-name>",
	Short: "Show QR code for an account",
	Long:  `Display the QR code for an account in the terminal, or save it as a PNG file.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		accountName := args[0]

		if err := initStorage(); err != nil {
			return err
		}

		st, err := storageManager.Load()
		if err != nil {
			return fmt.Errorf("failed to load storage: %w", err)
		}

		acc := st.FindByName(accountName)
		if acc == nil {
			return fmt.Errorf("account '%s' not found", accountName)
		}

		// Generate otpauth URL
		url := acc.ToOTPAuthURL()

		// Save to file if requested
		if showSave != "" {
			if err := qr.GeneratePNG(url, showSave); err != nil {
				return fmt.Errorf("failed to save QR code: %w", err)
			}
			fmt.Printf("✓ QR code saved to %s\n", showSave)
			return nil
		}

		// Display in terminal
		fmt.Printf("\n%s\n\n", acc.DisplayName())

		// Try to display as inline image (for WezTerm, iTerm2, etc.)
		if err := displayQRInline(url); err != nil {
			// Fallback to text-based QR if inline image fails
			if err := qr.GenerateTerminal(url); err != nil {
				return fmt.Errorf("failed to generate QR code: %w", err)
			}
		}

		// Show current code and secret
		code, _ := totp.Generate(acc)
		remaining := totp.RemainingSeconds(acc)
		formattedCode := totp.FormatCode(code)

		fmt.Printf("\nCode: %s  (%ds remaining)\n", formattedCode, remaining)
		fmt.Printf("Secret: %s\n\n", acc.Secret)

		return nil
	},
}

func init() {
	rootCmd.AddCommand(showCmd)
	showCmd.Flags().StringVarP(&showSave, "save", "s", "", "Save QR code to PNG file")
}

// displayQRInline displays QR code as inline image in terminal (iTerm2/WezTerm protocol)
func displayQRInline(content string) error {
	// Create temporary PNG file with small size
	tmpFile, err := os.CreateTemp("", "mfa-qr-*.png")
	if err != nil {
		return err
	}
	tmpPath := tmpFile.Name()
	tmpFile.Close()
	defer os.Remove(tmpPath)

	// Generate small QR code PNG (200x200 pixels)
	if err := qr.GeneratePNGWithSize(content, tmpPath, 200); err != nil {
		return err
	}

	// Read the PNG file
	data, err := os.ReadFile(tmpPath)
	if err != nil {
		return err
	}

	// Encode to base64
	encoded := base64.StdEncoding.EncodeToString(data)

	// Display using iTerm2 inline image protocol
	// width=20 means 20 character cells wide (adjust for size)
	fmt.Printf("\033]1337;File=inline=1;width=20;preserveAspectRatio=1:%s\a\n", encoded)

	return nil
}
