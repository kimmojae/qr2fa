package cmd

import (
	"fmt"

	"github.com/atotto/clipboard"
	"github.com/spf13/cobra"

	"github.com/kimmojae/qr2fa/internal/totp"
)

var (
	noCopy bool
)

// getCmd represents the get command
var getCmd = &cobra.Command{
	Use:   "get <account-name>",
	Short: "Get TOTP code for an account",
	Long:  `Get the current TOTP code for a specific account and copy it to clipboard.`,
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

		code, err := totp.Generate(acc)
		if err != nil {
			return fmt.Errorf("failed to generate code: %w", err)
		}

		// Print code
		fmt.Println(code)

		// Copy to clipboard unless --no-copy is set
		if !noCopy {
			if err := clipboard.WriteAll(code); err != nil {
				fmt.Fprintf(cmd.ErrOrStderr(), "Warning: Failed to copy to clipboard: %v\n", err)
			} else {
				fmt.Fprintf(cmd.ErrOrStderr(), "✓ Code copied to clipboard\n")
			}
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(getCmd)
	getCmd.Flags().BoolVar(&noCopy, "no-copy", false, "Don't copy code to clipboard")
}
