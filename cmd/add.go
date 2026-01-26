package cmd

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/kimmojae/qr2fa/internal/account"
	"github.com/kimmojae/qr2fa/internal/qr"
)

var (
	addURL    string
	addQRFile string
)

// addCmd represents the add command
var addCmd = &cobra.Command{
	Use:   "add",
	Short: "Add a new MFA account",
	Long:  `Add a new MFA account by providing the secret key, or by parsing an otpauth:// URL.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := initStorage(); err != nil {
			return err
		}

		st, err := storageManager.Load()
		if err != nil {
			return fmt.Errorf("failed to load storage: %w", err)
		}

		var acc *account.Account

		// Parse from URL if provided
		if addURL != "" {
			acc, err = account.ParseOTPAuthURL(addURL)
			if err != nil {
				return fmt.Errorf("failed to parse URL: %w", err)
			}

			// Still prompt for tag
			fmt.Print("Tag [dev/prod/staging/personal]: ")
			tag := readLine()
			acc.Tag = strings.ToLower(strings.TrimSpace(tag))
		} else if addQRFile != "" {
			// Decode QR code from file
			content, err := qr.DecodeFromFile(addQRFile)
			if err != nil {
				return fmt.Errorf("failed to decode QR code from file: %w", err)
			}

			// Parse otpauth URL
			acc, err = account.ParseOTPAuthURL(content)
			if err != nil {
				return fmt.Errorf("failed to parse QR code: %w", err)
			}

			fmt.Fprintf(cmd.ErrOrStderr(), "✓ Detected: %s", acc.Name)
			if acc.Issuer != "" {
				fmt.Fprintf(cmd.ErrOrStderr(), " (%s)", acc.Issuer)
			}
			fmt.Fprintln(cmd.ErrOrStderr())

			// Prompt for tag
			fmt.Fprint(cmd.ErrOrStderr(), "Tag [dev/prod/staging/personal]: ")
			tag := readLine()
			acc.Tag = strings.ToLower(strings.TrimSpace(tag))
		} else {
			// Interactive prompts
			acc, err = promptForAccount()
			if err != nil {
				return err
			}
		}

		// Add account to storage
		if err := st.Add(acc); err != nil {
			return fmt.Errorf("failed to add account: %w", err)
		}

		// Save storage
		if err := storageManager.Save(st); err != nil {
			return fmt.Errorf("failed to save storage: %w", err)
		}

		fmt.Printf("✓ Account '%s' added successfully\n", acc.Name)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(addCmd)
	addCmd.Flags().StringVar(&addURL, "url", "", "otpauth:// URL to parse")
	addCmd.Flags().StringVar(&addQRFile, "qr", "", "QR code image file to parse")
}

func promptForAccount() (*account.Account, error) {
	// Name
	fmt.Print("Name: ")
	name := readLine()
	if name == "" {
		return nil, fmt.Errorf("name is required")
	}

	// Issuer
	fmt.Print("Issuer (optional): ")
	issuer := readLine()

	// Secret
	fmt.Print("Secret: ")
	secret := readLine()
	if secret == "" {
		return nil, fmt.Errorf("secret is required")
	}

	// Tag
	fmt.Print("Tag [dev/prod/staging/personal]: ")
	tag := readLine()
	tag = strings.ToLower(strings.TrimSpace(tag))

	// Create account
	acc, err := account.NewAccount(name, issuer, secret, tag)
	if err != nil {
		return nil, fmt.Errorf("failed to create account: %w", err)
	}

	return acc, nil
}

func readLine() string {
	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	return strings.TrimSpace(line)
}
