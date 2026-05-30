package cmd

import (
	"encoding/base64"
	"fmt"
	"os"

	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"

	"github.com/kimmojae/qr2fa/internal/qr"
)

var (
	showSave string
)

// showCmd represents the show command
var showCmd = &cobra.Command{
	Use:   "show <number>",
	Short: "Show QR code for an account",
	Long:  `Display the QR code for an account in the terminal, or save it as a PNG file. Use the account number from 'qr2fa list'.`,
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := initStorage(); err != nil {
			return err
		}

		st, err := storageManager.Load()
		if err != nil {
			return fmt.Errorf("failed to load storage: %w", err)
		}

		acc, err := findAccountByID(st, args[0])
		if err != nil {
			return err
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

		// Display account info
		labelStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
		dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("245"))

		fmt.Println()
		fmt.Printf("%s %d\n", labelStyle.Render("ID:"), acc.ID)
		fmt.Printf("%s %s\n", labelStyle.Render("Issuer:"), acc.Issuer)
		fmt.Printf("%s %s\n", labelStyle.Render("Name:"), acc.Name)
		if acc.Tag != "" {
			tagColors := map[string]lipgloss.Color{
				"dev":  lipgloss.Color("12"),
				"prod": lipgloss.Color("9"),
			}
			color, ok := tagColors[acc.Tag]
			if !ok {
				color = lipgloss.Color("14")
			}
			fmt.Printf("%s %s\n", labelStyle.Render("Tag:"), lipgloss.NewStyle().Foreground(color).Render(acc.Tag))
		}
		fmt.Printf("%s %s\n", labelStyle.Render("Secret:"), acc.Secret)

		// QR Code section
		fmt.Println()
		fmt.Println(dimStyle.Render("── QR Code ──"))
		fmt.Println()

		// Try to display as inline image (for WezTerm, iTerm2, etc.)
		if err := displayQRInline(url); err != nil {
			// Fallback to text-based QR if inline image fails
			if err := qr.GenerateTerminal(url); err != nil {
				return fmt.Errorf("failed to generate QR code: %w", err)
			}
		}
		fmt.Println()

		return nil
	},
}

func init() {
	rootCmd.AddCommand(showCmd)
	showCmd.Flags().StringVarP(&showSave, "save", "s", "", "Save QR code to PNG file")
}

// displayQRInline displays QR code as inline image in terminal (iTerm2/WezTerm/Kitty/Ghostty protocol)
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

	// Detect terminal type and use appropriate protocol
	termProgram := os.Getenv("TERM_PROGRAM")
	term := os.Getenv("TERM")

	// Try Kitty protocol for Ghostty and Kitty terminals
	if termProgram == "ghostty" || term == "xterm-kitty" {
		return displayKittyImage(data)
	}

	// Use iTerm2 protocol for iTerm2 and WezTerm
	if termProgram == "iTerm.app" || termProgram == "WezTerm" {
		return displayITerm2Image(data)
	}

	// Try both protocols as fallback
	// First try Kitty (more widely supported in modern terminals)
	if err := displayKittyImage(data); err == nil {
		return nil
	}

	// Fall back to iTerm2 protocol
	return displayITerm2Image(data)
}

// displayKittyImage displays image using Kitty graphics protocol
func displayKittyImage(data []byte) error {
	encoded := base64.StdEncoding.EncodeToString(data)

	// Kitty graphics protocol
	// a=T: transmit and display
	// f=100: PNG format
	// t=d: direct transmission (base64)
	// C=1: cursor movement after image
	fmt.Printf("\033_Ga=T,f=100,t=d;%s\033\\\n", encoded)

	return nil
}

// displayITerm2Image displays image using iTerm2 inline image protocol
func displayITerm2Image(data []byte) error {
	encoded := base64.StdEncoding.EncodeToString(data)

	// iTerm2 inline image protocol
	// width=20 means 20 character cells wide
	fmt.Printf("\033]1337;File=inline=1;width=20;preserveAspectRatio=1:%s\a\n", encoded)

	return nil
}
